local ADDON, ns = ...
ns = ns or {}
local L = LibStub("AceLocale-3.0"):GetLocale("DecorShoppingList")

ns.Recipes = ns.Recipes or {}

local QUALITY_MODE_ANY = "any"
local QUALITY_MODE_SPECIFIC = "specific"
local wipeTable = wipe
local tempTablePool = {}

local function AcquireTempTable()
  local t = tempTablePool[#tempTablePool]
  if t then
    tempTablePool[#tempTablePool] = nil
    return t
  end
  return {}
end

local function ReleaseTempTable(t)
  if type(t) ~= "table" then return end
  wipeTable(t)
  tempTablePool[#tempTablePool + 1] = t
end

local function NormalizeGoalQualityTracking(goal)
  if type(goal) ~= "table" then
    return QUALITY_MODE_ANY, nil
  end

  local targetQuality = ns.Data.NormalizeTrackedQuality(goal.targetQuality)
  if goal.qualityMode == QUALITY_MODE_SPECIFIC and targetQuality then
    return QUALITY_MODE_SPECIFIC, targetQuality
  end

  return QUALITY_MODE_ANY, nil
end

local function SetGoalQualityTracking(goal, qualityMode, targetQuality)
  if type(goal) ~= "table" then return end

  targetQuality = ns.Data.NormalizeTrackedQuality(targetQuality)
  if qualityMode == QUALITY_MODE_SPECIFIC and targetQuality then
    goal.qualityMode = QUALITY_MODE_SPECIFIC
    goal.targetQuality = targetQuality
    return
  end

  goal.qualityMode = QUALITY_MODE_ANY
  goal.targetQuality = nil
end

local function GetTrackedHaveCount(addon, goal, itemID)
  itemID = itemID or (type(goal) == "table" and goal.itemID) or nil
  if not itemID then return 0 end

  local qualityMode, targetQuality = NormalizeGoalQualityTracking(goal)
  if qualityMode == QUALITY_MODE_SPECIFIC and targetQuality then
    return ns.GetHaveCountByQuality(addon, itemID, targetQuality)
  end

  return ns.GetHaveCount(addon, itemID)
end

local function GetGoalQualityBreakdown(addon, goal, itemID)
  itemID = itemID or (type(goal) == "table" and goal.itemID) or nil
  if not itemID then
    return { [1] = 0, [2] = 0, [3] = 0 }
  end
  return ns.GetHaveQualityBreakdown(addon, itemID)
end

local function MakeReagentKey(itemID, targetQuality)
  targetQuality = ns.Data.NormalizeTrackedQuality(targetQuality)
  if targetQuality then
    return tostring(itemID) .. ":" .. tostring(targetQuality)
  end
  return tostring(itemID)
end

local function GetRecipeDisplayName(addon, goal)
  if goal.itemID then
    local itemName = ns.Data.GetItemNameWithCache(addon, goal.itemID)
    if itemName then
      return ns.Data.ColorizeByQuality(goal.itemID, itemName)
    end
    if goal.name and goal.name ~= "" then
      return ns.Data.ColorizeByQuality(goal.itemID, goal.name)
    end
  end

  if goal.recipeID then
    local schematic = ns.Data.GetRecipeSchematicSafe(goal.recipeID)
    if schematic and schematic.name then
      return schematic.name
    end
  end

  if goal.name then return goal.name end
  if goal.recipeID then return "Recipe " .. goal.recipeID end
  if goal.itemID then return "Item " .. goal.itemID end
  return "Unknown"
end

function ns.Recipes.GetRecipeOutputItemID(recipeID)
  if not recipeID then return nil end

  local schematic = ns.Data.GetRecipeSchematicSafe(recipeID)
  if schematic then
    if schematic.outputItemID then return schematic.outputItemID end
    if schematic.productItemID then return schematic.productItemID end
  end

  if C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo then
    local info = C_TradeSkillUI.GetRecipeInfo(recipeID)
    if info then
      if info.productItemID then return info.productItemID end
      if info.outputItemID then return info.outputItemID end
    end
  end

  return nil
end

function ns.Recipes.SetGoalForRecipe(addon, recipeID, deltaQty, opts)
  local delta = tonumber(deltaQty) or 0
  local hasTrackingUpdate = type(opts) == "table" and (opts.qualityMode ~= nil or opts.targetQuality ~= nil)
  if not recipeID or (delta == 0 and not hasTrackingUpdate) then return end

  local goals = addon.db.profile.goals
  local key = "r:" .. tostring(recipeID)
  local g = goals[key]

  if not g then
    if delta == 0 then return end
    g = { recipeID = recipeID, qty = 0, remaining = 0, profession = "Unknown" }
    goals[key] = g
  end

  g.qty = math.max(0, (g.qty or 0) + delta)
  g.remaining = math.max(0, (g.remaining or 0) + delta)
  SetGoalQualityTracking(g, hasTrackingUpdate and opts.qualityMode or g.qualityMode, hasTrackingUpdate and opts.targetQuality or g.targetQuality)

  local cache = ns.Data.EnsureRecipeCache(addon)
  if cache and cache[recipeID] then
    g.needsScan = nil
  else
    if ns.Snapshots.IsPlayerProfessionUIOpen() then
      ns.Snapshots.SnapshotRecipeToCache(addon, recipeID, true)
      if cache and cache[recipeID] then
        g.needsScan = nil
      else
        g.needsScan = true
      end
    else
      g.needsScan = true
    end
  end

  ns.IsRecipeLearned(addon, recipeID)
  ns.Data.EnsureProfessionsLoaded()

  do
    local profName, profID = ns.Snapshots.GetProfessionForRecipe(recipeID)
    local normalized = ns.Data.NormalizeProfessionName(profName)
    if normalized and normalized ~= "Unknown" then
      g.profession = normalized
      g.professionID = profID
    end
  end

  local out = ns.GetRecipeOutputItemID(recipeID)
  if out then
    g.itemID = out
    addon.db.profile.recipeByItem[out] = recipeID
  end

  do
    local schematic = ns.Data.GetRecipeSchematicSafe(recipeID)
    if schematic and schematic.name then
      g.name = schematic.name
    end

    if out then
      local itemName = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(out)) or GetItemInfo(out)
      if itemName then
        g.name = itemName
      elseif C_Item and C_Item.RequestLoadItemDataByID then
        C_Item.RequestLoadItemDataByID(out)
      end
    end
  end

  if g.qty == 0 then
    goals[key] = nil
    addon:MarkDirty()
    return
  end

  addon:MarkDirty()
end

function ns.Recipes.ApplyCompletionByInventoryDelta(addon)
  local goals = addon.db.profile.goals
  local touched = false

  for goalKey, goal in pairs(goals) do
    if type(goal) == "table" then
      local itemID = goal.itemID
      if not itemID and goal.recipeID then
        itemID = ns.GetRecipeOutputItemID(goal.recipeID)
        if itemID then goal.itemID = itemID end
      end

      if itemID then
        local qualityMode, targetQuality = NormalizeGoalQualityTracking(goal)
        local haveNow = GetTrackedHaveCount(addon, goal, itemID)
        local haveKey = (qualityMode == QUALITY_MODE_SPECIFIC and targetQuality)
          and (tostring(itemID) .. ":" .. tostring(targetQuality))
          or tostring(itemID)
        local havePrev = addon.lastHave[haveKey]

        if havePrev == nil then
          addon.lastHave[haveKey] = haveNow
        else
          local delta = haveNow - havePrev
          if delta > 0 and (goal.remaining or 0) > 0 then
            goal.remaining = math.max(0, (goal.remaining or 0) - delta)
            touched = true
          end
          addon.lastHave[haveKey] = haveNow
        end

        if (goal.remaining or 0) <= 0 then
          local rawName = ns.Data.GetItemNameWithCache(addon, itemID) or goal.name or ("Item " .. itemID)
          goals[goalKey] = nil
          addon:Print(string.format(L["COMPLETED_RECIPE"], rawName))
          touched = true
        end
      end
    end
  end

  if touched then
    addon.dirty = true
  end
end

function ns.Recipes.AccumulateReagentsForRecipe(addon, recipeID, desiredItems, depth, goal)
  if depth > 20 then return end
  if not recipeID or desiredItems <= 0 then return end

  local yieldMin, reagentsList

  local schematic = ns.Data.GetRecipeSchematicSafe(recipeID)
  if schematic then
    yieldMin = 1
    if schematic.quantityMin and schematic.quantityMin > 0 then
      yieldMin = schematic.quantityMin
    end

    reagentsList = {}
    local slots = schematic.reagentSlotSchematics
    if slots then
      for _, slot in ipairs(slots) do
        local r = ns.Data.PickRequiredReagent(slot)
        local tierItemIDs = ns.Data.GetRequiredReagentTierItemIDs and ns.Data.GetRequiredReagentTierItemIDs(slot) or nil
        local qtyReq = (slot and slot.quantityRequired) or (r and r.quantityRequired) or 0
        if r and r.itemID and qtyReq and qtyReq > 0 then
          table.insert(reagentsList, { itemID = r.itemID, qty = qtyReq, tierItemIDs = tierItemIDs })
        end
      end
    end

    if reagentsList and #reagentsList > 0 then
      local cache = ns.Data.EnsureRecipeCache(addon)
      if cache then
        cache[recipeID] = { yieldMin = yieldMin, reagents = reagentsList, ts = time() }
      end
    end
  end

  if (not reagentsList or #reagentsList == 0) then
    local cache = ns.Data.EnsureRecipeCache(addon)
    if not cache then return end
    local snap = cache[recipeID]
    if not snap or not snap.reagents or #snap.reagents == 0 then
      return
    end
    yieldMin = snap.yieldMin or 1
    reagentsList = snap.reagents
  end

  local craftsNeeded = ns.Data.ceilDiv(desiredItems, yieldMin)
  if craftsNeeded <= 0 then return end

  for _, r in ipairs(reagentsList) do
    if r and r.itemID and r.qty then
      local itemID = r.itemID
      local tierItemIDs = type(r.tierItemIDs) == "table" and r.tierItemIDs or nil
      local qty = (r.qty * craftsNeeded)
      local key = MakeReagentKey(itemID, nil)
      local entry = addon.cache.reagents[key]
      if type(entry) ~= "table" then
        entry = {
          key = key,
          itemID = itemID,
          baseItemID = itemID,
          tierItemIDs = tierItemIDs,
          qualityItemID = nil,
          targetQuality = nil,
          need = 0,
        }
        addon.cache.reagents[key] = entry
      else
        entry.baseItemID = entry.baseItemID or itemID
        entry.tierItemIDs = entry.tierItemIDs or tierItemIDs
      end
      entry.need = (entry.need or 0) + qty
    end
  end
end

function ns.Recipes.RecomputeDisplayOnly(addon)
  if not (addon and addon.cache) then return end
  if not addon.cache.recipes or not addon.cache.reagentsList then
    return ns.RecomputeCaches(addon)
  end

  addon.db.profile.window = addon.db.profile.window or {}
  addon.db.profile.window.collapsed = addon.db.profile.window.collapsed or {}
  local collapsed = addon.db.profile.window.collapsed

  addon.cache.recipesDisplay = addon.cache.recipesDisplay or {}
  wipeTable(addon.cache.recipesDisplay)
  local byProf = AcquireTempTable()

  for _, row in ipairs(addon.cache.recipes) do
    if row.itemID then
      local itemName = ns.Data.GetItemNameWithCache(addon, row.itemID) or row.rawName or row.name
      if itemName and itemName ~= "" then
        row.name = ns.Data.ColorizeByQuality(row.itemID, itemName)
        row.rawName = row.rawName or itemName
      end

      local quality = ns.Data.GetItemQuality(row.itemID)
      if quality ~= nil then
        row.rarity = quality
      end

      local expacID = ns.Data.GetItemExpansionID(row.itemID)
      if expacID ~= nil then
        row.expacID = expacID
        row.expacName = ns.Data.GetExpansionName(expacID)
      end
    end

    local prof = (row.profession and row.profession ~= "") and row.profession or "Unknown"
    byProf[prof] = byProf[prof] or AcquireTempTable()
    table.insert(byProf[prof], row)
  end

  local profNames = AcquireTempTable()
  for profName, _ in pairs(byProf) do
    table.insert(profNames, profName)
  end
  table.sort(profNames)

  for _, profName in ipairs(profNames) do
    table.insert(addon.cache.recipesDisplay, {
      isHeader = true,
      profession = profName,
      name = profName,
      remaining = nil,
      groupKey = "PROF:" .. profName,
      level = 1,
    })

    local list = byProf[profName]
    local rMode = (addon.db.profile.window and addon.db.profile.window.recipeSort) or "N"
    ns.Sorting.SortRecipeList(list, rMode)

    if not collapsed["PROF:" .. profName] and not collapsed[profName] then
      if rMode == "E" then
        local lastExpac = nil
        for _, r in ipairs(list) do
          local expacID = r.expacID or -1
          if expacID ~= lastExpac then
            lastExpac = expacID
            table.insert(addon.cache.recipesDisplay, {
              isHeader = true,
              profession = profName,
              expacID = expacID,
              name = r.expacName or "Unknown",
              remaining = nil,
              groupKey = "PROF:" .. profName .. ":EXP:" .. tostring(expacID),
              level = 2,
            })
          end

          if not collapsed["PROF:" .. profName .. ":EXP:" .. tostring(expacID)] then
            r.level = 2
            table.insert(addon.cache.recipesDisplay, r)
          end
        end
      else
        for _, r in ipairs(list) do
          r.level = 1
          table.insert(addon.cache.recipesDisplay, r)
        end
      end
    end
  end

  local flat = {}
  for _, e in ipairs(addon.cache.reagentsList or {}) do
    table.insert(flat, e)
  end
  local mode = (addon.db.profile.window and addon.db.profile.window.reagentSort) or "E"
  local sorted, display = ns.Reagents.SortAndBuildDisplay(flat, mode, collapsed, ns.Data.GetExpansionName)
  addon.cache.reagentsList = sorted
  addon.cache.reagentsDisplay = display

  for _, profName in ipairs(profNames) do
    ReleaseTempTable(byProf[profName])
  end
  ReleaseTempTable(profNames)
  ReleaseTempTable(byProf)
end

function ns.Recipes.RecomputeCaches(addon)
  addon.cache = addon.cache or {}
  addon.cache.recipes = addon.cache.recipes or {}
  addon.cache.recipesDisplay = addon.cache.recipesDisplay or {}
  addon.cache.reagents = addon.cache.reagents or {}
  addon.cache.reagentsList = addon.cache.reagentsList or {}
  addon.cache.reagentsDisplay = addon.cache.reagentsDisplay or {}
  wipeTable(addon.cache.recipes)
  wipeTable(addon.cache.recipesDisplay)
  wipeTable(addon.cache.reagents)
  wipeTable(addon.cache.reagentsList)
  wipeTable(addon.cache.reagentsDisplay)

  addon.db.profile.window = addon.db.profile.window or {}
  addon.db.profile.window.collapsed = addon.db.profile.window.collapsed or {}

  local collapsed = addon.db.profile.window.collapsed
  local byProf = AcquireTempTable()

  addon.cache._sortCache = addon.cache._sortCache or {}
  addon.cache._sortCache.recipesByProf = addon.cache._sortCache.recipesByProf or {}
  addon.cache._sortCache.reagents = addon.cache._sortCache.reagents or {}

  local memo = AcquireTempTable()
  memo.profByRecipe = memo.profByRecipe or AcquireTempTable()
  memo.hasProfByName = memo.hasProfByName or AcquireTempTable()
  memo.outputItemByRecipe = memo.outputItemByRecipe or AcquireTempTable()
  memo.qualityByItem = memo.qualityByItem or AcquireTempTable()
  memo.expacByItem = memo.expacByItem or AcquireTempTable()
  memo.expacNameByID = memo.expacNameByID or AcquireTempTable()
  memo.iconByItem = memo.iconByItem or AcquireTempTable()
  wipeTable(memo.profByRecipe)
  wipeTable(memo.hasProfByName)
  wipeTable(memo.outputItemByRecipe)
  wipeTable(memo.qualityByItem)
  wipeTable(memo.expacByItem)
  wipeTable(memo.expacNameByID)
  wipeTable(memo.iconByItem)

  local function MemoProfName(recipeID)
    if not recipeID then return "Unknown" end
    local v = memo.profByRecipe[recipeID]
    if v ~= nil then return v end
    v = ns.Data.NormalizeProfessionName(select(1, ns.Snapshots.GetProfessionForRecipe(recipeID)))
    if not v or v == "" then v = "Unknown" end
    memo.profByRecipe[recipeID] = v
    return v
  end

  local function MemoHasProf(profName)
    if not profName or profName == "" then return false end
    local v = memo.hasProfByName[profName]
    if v ~= nil then return v end
    v = ns.PlayerHasProfession(profName) or false
    memo.hasProfByName[profName] = v
    return v
  end

  local function MemoOutputItem(recipeID)
    if not recipeID then return nil end
    local v = memo.outputItemByRecipe[recipeID]
    if v ~= nil then return v end
    v = ns.GetRecipeOutputItemID(recipeID)
    memo.outputItemByRecipe[recipeID] = v or false
    return v
  end

  local function MemoQuality(itemID)
    if not itemID then return -1 end
    local v = memo.qualityByItem[itemID]
    if v ~= nil then return v end
    v = ns.Data.GetItemQuality(itemID) or -1
    memo.qualityByItem[itemID] = v
    return v
  end

  local function MemoExpacID(itemID)
    if not itemID then return nil end
    local v = memo.expacByItem[itemID]
    if v ~= nil then return v end
    v = ns.Data.GetItemExpansionID(itemID)
    memo.expacByItem[itemID] = v
    return v
  end

  local function MemoExpacName(expacID)
    if expacID == nil then return "Unknown" end
    local v = memo.expacNameByID[expacID]
    if v ~= nil then return v end
    v = ns.Data.GetExpansionName(expacID) or "Unknown"
    memo.expacNameByID[expacID] = v
    return v
  end

  local function MemoIcon(itemID)
    if not itemID then return nil end
    local v = memo.iconByItem[itemID]
    if v ~= nil then return v end
    v = ((C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID)) or GetItemIcon(itemID))
    memo.iconByItem[itemID] = v
    return v
  end

  for _, goal in pairs(addon.db.profile.goals) do
    if type(goal) == "table" and (goal.remaining or 0) > 0 then
      local allowed = true
      local missingRecipe = false

      if goal.recipeID then
        local includeAlts = addon.db.profile.includeAlts
        local profName = ns.Data.NormalizeProfessionName(goal.profession)
        if not profName or profName == "Unknown" then
          profName = MemoProfName(goal.recipeID)
          if profName and profName ~= "" and profName ~= "Unknown" then
            goal.profession = profName
          end
        end

        local hasProf = (profName and profName ~= "Unknown") and MemoHasProf(profName) or false

        if includeAlts then
          allowed = true
          if not hasProf then
            missingRecipe = true
          else
            local learned = ns.IsRecipeLearned(addon, goal.recipeID)
            if learned == false then
              missingRecipe = true
            end
          end
        else
          if (profName and profName ~= "Unknown") and (not hasProf) then
            allowed = false
          else
            allowed = true
            if hasProf then
              local learned = ns.IsRecipeLearned(addon, goal.recipeID)
              if learned == false then
                missingRecipe = true
              end
            end
          end
        end
      end

      if allowed then
        if goal.recipeID and (not goal.profession or goal.profession == "" or goal.profession == "Unknown") then
          local pname, pid = ns.Snapshots.GetProfessionForRecipe(goal.recipeID)
          if pname and pname ~= "" then
            goal.profession = pname
            goal.professionID = pid
          end
        end

        local itemID = goal.itemID
        if goal.recipeID and not itemID then
          itemID = MemoOutputItem(goal.recipeID)
          if itemID then goal.itemID = itemID end
        end

        local baseName = GetRecipeDisplayName(addon, goal)
        local name = baseName
        local rarity = (goal.itemID and MemoQuality(goal.itemID)) or goal.rarity or -1
        local prof = ns.Data.NormalizeProfessionName(goal.profession) or "Unknown"
        if prof ~= "Unknown" then goal.profession = prof end
        local qualityMode, targetQuality = NormalizeGoalQualityTracking(goal)
        local trackedHave = GetTrackedHaveCount(addon, goal, itemID)
        local qualityBreakdown = GetGoalQualityBreakdown(addon, goal, itemID)
        local isDecor = itemID and ns.Data.IsDecorItem(itemID) or false

        local expacID = itemID and MemoExpacID(itemID) or nil
        if expacID == nil then
          expacID = goal.expacID
        end
        local expacName = (expacID ~= nil and MemoExpacName(expacID)) or goal.expacName or "Unknown"
        goal.rarity = rarity
        if expacID ~= nil then
          goal.expacID = expacID
          goal.expacName = expacName
        end

        local pInfo = ns.GetProfessionInfo and ns.GetProfessionInfo(prof) or nil
        local row = {
          name = name,
          rawName = goal.name or baseName,
          remaining = goal.remaining or 0,
          recipeID = goal.recipeID,
          itemID = itemID,
          outputItemID = itemID,
          profession = prof,
          professionIcon = pInfo and pInfo.icon or nil,
          rarity = rarity,
          missing = missingRecipe,
          expacID = expacID,
          expacName = expacName,
          icon = itemID and MemoIcon(itemID) or nil,
          need = goal.qty or 0,
          have = trackedHave,
          qualityMode = qualityMode,
          targetQuality = targetQuality,
          qualityBreakdown = qualityBreakdown,
          isDecor = isDecor,
        }

        byProf[prof] = byProf[prof] or AcquireTempTable()
        table.insert(byProf[prof], row)
        table.insert(addon.cache.recipes, row)

        if goal.recipeID then
          local cache = ns.Data.EnsureRecipeCache(addon)
          local entry = cache and cache[goal.recipeID]

          if not entry and ns.Snapshots.IsPlayerProfessionUIOpen() then
            ns.Snapshots.SnapshotRecipeToCache(addon, goal.recipeID, false)
            entry = cache and cache[goal.recipeID]
          end

          if entry then
            goal.needsScan = nil
            row.needsScan = nil
            ns.AccumulateReagentsForRecipe(addon, goal.recipeID, goal.remaining or 0, 0, goal)
          else
            goal.needsScan = true
            row.needsScan = true
          end
        end
      end
    end
  end

  local profNames = AcquireTempTable()
  for profName, _ in pairs(byProf) do
    table.insert(profNames, profName)
  end
  table.sort(profNames)

  for _, profName in ipairs(profNames) do
    table.insert(addon.cache.recipesDisplay, {
      isHeader = true,
      profession = profName,
      name = profName,
      remaining = nil,
      groupKey = "PROF:" .. profName,
      level = 1,
    })

    local list = byProf[profName]
    local profCache = addon.cache._sortCache.recipesByProf
    local rMode = (addon.db.profile.window and addon.db.profile.window.recipeSort) or "N"
    local sig = ns.Sorting.BuildRecipeSortSignature(list, rMode)

    local entry = profCache[profName]
    if entry and entry.sig == sig and entry.order then
      local map = AcquireTempTable()
      for _, r in ipairs(list) do
        local k = tostring(r.recipeID or r.itemID or r.name or "")
        map[k] = r
      end

      local ordered = AcquireTempTable()
      local ok = true
      for _, k in ipairs(entry.order) do
        local r = map[k]
        if not r then ok = false break end
        table.insert(ordered, r)
      end

      if ok and #ordered == #list then
        local originalList = list
        list = ordered
        byProf[profName] = ordered
        ReleaseTempTable(originalList)
      else
        ReleaseTempTable(ordered)
        entry = nil
      end
      ReleaseTempTable(map)
    end

    if not entry then
      ns.Sorting.SortRecipeList(list, rMode)
      local order = AcquireTempTable()
      for _, r in ipairs(list) do
        table.insert(order, tostring(r.recipeID or r.itemID or r.name or ""))
      end
      if profCache[profName] and profCache[profName].order then
        ReleaseTempTable(profCache[profName].order)
      end
      profCache[profName] = { sig = sig, order = order }
    end

    if not collapsed["PROF:" .. profName] and not collapsed[profName] then
      if rMode == "E" then
        local lastExpac = nil
        for _, r in ipairs(list) do
          local expacID = r.expacID or -1
          if expacID ~= lastExpac then
            lastExpac = expacID
            table.insert(addon.cache.recipesDisplay, {
              isHeader = true,
              profession = profName,
              expacID = expacID,
              name = r.expacName or "Unknown",
              remaining = nil,
              groupKey = "PROF:" .. profName .. ":EXP:" .. tostring(expacID),
              level = 2,
            })
          end

          if not collapsed["PROF:" .. profName .. ":EXP:" .. tostring(expacID)] then
            r.level = 2
            table.insert(addon.cache.recipesDisplay, r)
          end
        end
      else
        for _, r in ipairs(list) do
          r.level = 1
          table.insert(addon.cache.recipesDisplay, r)
        end
      end
    end
  end

  ns.Reagents.BuildDisplayOnly(addon)

  for _, profName in ipairs(profNames) do
    local list = byProf[profName]
    if list then
      ReleaseTempTable(list)
    end
  end
  ReleaseTempTable(profNames)
  ReleaseTempTable(byProf)
  ReleaseTempTable(memo.profByRecipe)
  ReleaseTempTable(memo.hasProfByName)
  ReleaseTempTable(memo.outputItemByRecipe)
  ReleaseTempTable(memo.qualityByItem)
  ReleaseTempTable(memo.expacByItem)
  ReleaseTempTable(memo.expacNameByID)
  ReleaseTempTable(memo.iconByItem)
  memo.profByRecipe = nil
  memo.hasProfByName = nil
  memo.outputItemByRecipe = nil
  memo.qualityByItem = nil
  memo.expacByItem = nil
  memo.expacNameByID = nil
  memo.iconByItem = nil
  ReleaseTempTable(memo)
end

function ns.Recipes.GetGoalForRecipe(addon, recipeID)
  local goals = addon and addon.db and addon.db.profile and addon.db.profile.goals
  if not goals or not recipeID then return nil end
  local goal = goals["r:" .. tostring(recipeID)]
  if type(goal) ~= "table" then return nil end
  return goal
end

function ns.Recipes.GetGoalQualityTracking(goal)
  return NormalizeGoalQualityTracking(goal)
end

function ns.Recipes.GetTrackedHaveCount(addon, goal, itemID)
  return GetTrackedHaveCount(addon, goal, itemID)
end

function ns.Recipes.GetGoalQualityBreakdown(addon, goal, itemID)
  return GetGoalQualityBreakdown(addon, goal, itemID)
end

ns.GetRecipeOutputItemID = ns.Recipes.GetRecipeOutputItemID
ns.SetGoalForRecipe = ns.Recipes.SetGoalForRecipe
ns.ApplyCompletionByInventoryDelta = ns.Recipes.ApplyCompletionByInventoryDelta
ns.AccumulateReagentsForRecipe = ns.Recipes.AccumulateReagentsForRecipe
ns.RecomputeDisplayOnly = ns.Recipes.RecomputeDisplayOnly
ns.RecomputeCaches = ns.Recipes.RecomputeCaches
