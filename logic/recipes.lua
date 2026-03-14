local ADDON, ns = ...
ns = ns or {}
local L = LibStub("AceLocale-3.0"):GetLocale("DecorShoppingList")

ns.Recipes = ns.Recipes or {}
local Catalog = LibStub and LibStub("LibDSLCatalog-1.0", true)

-- Goal quality tracking ------------------------------------------------------

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

  local targetQuality = ns.Data.NormalizeProfessionCraftingQuality(goal.targetQuality)
  if goal.qualityMode == QUALITY_MODE_SPECIFIC and targetQuality then
    return QUALITY_MODE_SPECIFIC, targetQuality
  end

  return QUALITY_MODE_ANY, nil
end

local function SetGoalQualityTracking(goal, qualityMode, targetQuality)
  if type(goal) ~= "table" then return end

  targetQuality = ns.Data.NormalizeProfessionCraftingQuality(targetQuality)
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

  if ns.Data.UsesModernReagentQuality and ns.Data.UsesModernReagentQuality(itemID) then
    return ns.GetHaveCountByName(addon, itemID)
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

local function SyncGoalHaveBaseline(addon, goal, itemID)
  if not (addon and type(goal) == "table") then
    return
  end

  itemID = itemID or goal.itemID
  if not itemID then
    return
  end

  local qualityMode, targetQuality = NormalizeGoalQualityTracking(goal)
  local haveKey = (qualityMode == QUALITY_MODE_SPECIFIC and targetQuality)
    and (tostring(itemID) .. ":" .. tostring(targetQuality))
    or tostring(itemID)
  local baselineHave = GetTrackedHaveCount(addon, goal, itemID)

  addon.lastHave = addon.lastHave or {}
  addon.lastHave[haveKey] = baselineHave

  goal.baselineItemID = itemID
  goal.baselineQualityMode = qualityMode
  goal.baselineTargetQuality = targetQuality
  goal.baselineHave = baselineHave
end

local function UpdateGoalRemainingFromCurrentHave(addon, goal, itemID, trackedHave)
  if not (addon and type(goal) == "table") then
    return false
  end

  itemID = itemID or goal.itemID
  if not itemID then
    return false
  end

  local qualityMode, targetQuality = NormalizeGoalQualityTracking(goal)
  local baselineMatches = goal.baselineItemID == itemID
    and goal.baselineQualityMode == qualityMode
    and goal.baselineTargetQuality == targetQuality

  if not baselineMatches or type(goal.baselineHave) ~= "number" then
    SyncGoalHaveBaseline(addon, goal, itemID)
  end

  local haveNow = tonumber(trackedHave)
  if haveNow == nil then
    haveNow = GetTrackedHaveCount(addon, goal, itemID)
  end

  local baselineHave = tonumber(goal.baselineHave) or 0
  local craftedTotal = math.max(0, haveNow - baselineHave)
  local computedRemaining = math.max(0, (goal.qty or 0) - craftedTotal)
  local currentRemaining = tonumber(goal.remaining) or 0

  if computedRemaining < currentRemaining then
    goal.remaining = computedRemaining
    return true
  end

  return false
end

local function UpdateGoalRemainingFromCraftedCount(goal)
  if type(goal) ~= "table" then
    return false
  end

  local craftedCount = tonumber(goal.craftedCount) or 0
  local computedRemaining = math.max(0, (goal.qty or 0) - craftedCount)
  local currentRemaining = tonumber(goal.remaining) or 0
  if computedRemaining < currentRemaining then
    goal.remaining = computedRemaining
    return true
  end
  return false
end

-- Recipe display/cache helpers ----------------------------------------------

local function GetRecipeDisplayName(addon, goal)
  if goal.itemID then
    local itemName = ns.Data.GetItemNameWithCache(addon, goal.itemID)
    if itemName then
      return ns.Data.ColorizeByRarityWithCache(addon, goal.itemID, itemName)
    end
    if goal.name and goal.name ~= "" then
      return ns.Data.ColorizeByRarityWithCache(addon, goal.itemID, goal.name)
    end
  end

  if goal.recipeID then
    if Catalog and Catalog.GetRecipe then
      local recipe = Catalog:GetRecipe(goal.recipeID)
      if type(recipe) == "table" and recipe.recipeName then
        return recipe.recipeName
      end
    end

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

local function PrepareRecipeCacheTables(addon, opts)
  opts = type(opts) == "table" and opts or nil
  local skipReagents = opts and opts.skipReagents

  addon.cache = addon.cache or {}
  addon.cache.recipes = addon.cache.recipes or {}
  addon.cache.recipesDisplay = addon.cache.recipesDisplay or {}
  addon.cache.reagents = addon.cache.reagents or {}
  addon.cache.reagentsList = addon.cache.reagentsList or {}
  addon.cache.reagentsDisplay = addon.cache.reagentsDisplay or {}
  wipeTable(addon.cache.recipes)
  wipeTable(addon.cache.recipesDisplay)
  if not skipReagents then
    wipeTable(addon.cache.reagents)
    wipeTable(addon.cache.reagentsList)
    wipeTable(addon.cache.reagentsDisplay)
    addon.cache._reagentsStale = nil
  else
    addon.cache._reagentsStale = true
  end

  addon.cache._sortCache = addon.cache._sortCache or {}
  addon.cache._sortCache.recipesByProf = addon.cache._sortCache.recipesByProf or {}
  addon.cache._sortCache.reagents = addon.cache._sortCache.reagents or {}
end

local function AcquireRecipeMemo()
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
  return memo
end

local function ReleaseRecipeMemo(memo)
  if type(memo) ~= "table" then return end
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

local function CollectSortedProfessionNames(byProf)
  local profNames = AcquireTempTable()
  for profName in pairs(byProf) do
    table.insert(profNames, profName)
  end
  table.sort(profNames)
  return profNames
end

function ns.Recipes.GetRecipeOutputItemID(recipeID)
  if not recipeID then return nil end

  if Catalog and Catalog.GetOutputItemForRecipe then
    local outputItemID = Catalog:GetOutputItemForRecipe(recipeID)
    if outputItemID then
      return outputItemID
    end
  end

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
    g = { recipeID = recipeID, qty = 0, remaining = 0, profession = "Unknown", craftedCount = 0 }
    goals[key] = g
  end

  g.qty = math.max(0, (g.qty or 0) + delta)
  g.craftedCount = math.max(0, tonumber(g.craftedCount) or 0)
  g.remaining = math.max(0, g.qty - g.craftedCount)
  SetGoalQualityTracking(g, hasTrackingUpdate and opts.qualityMode or g.qualityMode, hasTrackingUpdate and opts.targetQuality or g.targetQuality)

  local cache = ns.Data.EnsureRecipeCache(addon)
  local hasCatalogRecipe = Catalog and Catalog.HasRecipe and Catalog:HasRecipe(recipeID)
  if not hasCatalogRecipe and ns.Snapshots and ns.Snapshots.IsPlayerProfessionUIOpen and ns.Snapshots.IsPlayerProfessionUIOpen() then
    ns.Snapshots.SnapshotRecipeToCache(addon, recipeID, true)
    cache = ns.Data.EnsureRecipeCache(addon)
  end
  if (cache and cache[recipeID]) or hasCatalogRecipe then
    g.needsScan = nil
  else
    g.needsScan = true
  end
  if not g.name and Catalog and Catalog.GetRecipe then
    local recipe = Catalog:GetRecipe(recipeID)
    if type(recipe) == "table" and recipe.recipeName then
      g.name = recipe.recipeName
    end
  end

  if g.qty == 0 then
    goals[key] = nil
    addon:MarkDirty("goals")
    return
  end

  addon:MarkDirty("goals")
end

function ns.Recipes.NoteCraftSucceeded(addon, recipeID, quantity)
  if not (addon and recipeID) then
    return false
  end

  local goal = ns.Recipes.GetGoalForRecipe(addon, recipeID)
  if type(goal) ~= "table" then
    return false
  end

  local crafted = math.max(1, tonumber(quantity) or 1)
  goal.craftedCount = math.max(0, tonumber(goal.craftedCount) or 0) + crafted
  UpdateGoalRemainingFromCraftedCount(goal)
  return true
end

function ns.Recipes.ApplyCompletionByInventoryDelta(addon)
  local goals = addon.db.profile.goals
  local touched = false

  for goalKey, goal in pairs(goals) do
    if type(goal) == "table" then
      if UpdateGoalRemainingFromCraftedCount(goal) then
        touched = true
      end

      if (goal.remaining or 0) <= 0 then
        local itemID = goal.itemID
        if not itemID and goal.recipeID then
          itemID = ns.GetRecipeOutputItemID(goal.recipeID)
          if itemID then goal.itemID = itemID end
        end
        local rawName = (itemID and ns.Data.GetItemNameWithCache(addon, itemID)) or goal.name or ("Recipe " .. tostring(goal.recipeID or "?"))
        goals[goalKey] = nil
        addon:Print(string.format(L["COMPLETED_RECIPE"], rawName))
        touched = true
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
  local catalogRecipe = Catalog and Catalog.GetRecipe and Catalog:GetRecipe(recipeID)

  if type(catalogRecipe) == "table" then
    local catalogYieldMin = Catalog.GetYieldRangeForRecipe and select(1, Catalog:GetYieldRangeForRecipe(recipeID)) or nil
    local catalogReagents = Catalog.GetReagentsForRecipe and Catalog:GetReagentsForRecipe(recipeID) or catalogRecipe.reagents
    if type(catalogReagents) == "table" and #catalogReagents > 0 then
      yieldMin = catalogYieldMin or catalogRecipe.outputQuantity or 1
      reagentsList = {}
      for _, reagent in ipairs(catalogReagents) do
        if type(reagent) == "table" and reagent.itemID then
          table.insert(reagentsList, {
            itemID = reagent.itemID,
            qty = reagent.qty or reagent.quantity or 0,
            tierItemIDs = reagent.tierItemIDs,
          })
        end
      end
    end
  end

  local schematic = ns.Data.GetRecipeSchematicSafe(recipeID)
  if (not reagentsList or #reagentsList == 0) and schematic then
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
      local key = tostring(itemID)
      local entry = addon.cache.reagents[key]
      if type(entry) ~= "table" then
        entry = {
          key = key,
          itemID = itemID,
          baseItemID = itemID,
          tierItemIDs = tierItemIDs,
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

function ns.Recipes.RebuildReagentNeedMap(addon)
  if not addon then return end
  addon.cache = addon.cache or {}
  addon.cache.reagents = addon.cache.reagents or {}
  wipeTable(addon.cache.reagents)

  local goals = addon.db and addon.db.profile and addon.db.profile.goals
  if type(goals) ~= "table" then
    addon.cache._reagentsStale = nil
    return
  end

  for _, goal in pairs(goals) do
    if type(goal) == "table" and (goal.remaining or 0) > 0 and goal.recipeID then
      ns.AccumulateReagentsForRecipe(addon, goal.recipeID, goal.remaining or 0, 0, goal)
    end
  end

  addon.cache._reagentsStale = nil
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
        row.name = ns.Data.ColorizeByRarityWithCache(addon, row.itemID, itemName)
        row.rawName = row.rawName or itemName
      end

      local quality = ns.Data.GetItemRarityWithCache(addon, row.itemID)
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

function ns.Recipes.RecomputeCaches(addon, opts)
  opts = type(opts) == "table" and opts or nil
  local skipReagents = opts and opts.skipReagents
  PrepareRecipeCacheTables(addon, opts)

  addon.db.profile.window = addon.db.profile.window or {}
  addon.db.profile.window.collapsed = addon.db.profile.window.collapsed or {}

  local collapsed = addon.db.profile.window.collapsed
  local byProf = AcquireTempTable()
  local memo = AcquireRecipeMemo()
  local completedGoalKeys = AcquireTempTable()

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
    v = ns.Data.GetItemRarityWithCache(addon, itemID) or -1
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
        UpdateGoalRemainingFromCraftedCount(goal)
        local trackedHave = GetTrackedHaveCount(addon, goal, itemID)
        if (goal.remaining or 0) <= 0 then
          completedGoalKeys[#completedGoalKeys + 1] = "r:" .. tostring(goal.recipeID)
        end

        if (goal.remaining or 0) <= 0 then
          -- Skip rendering completed goals; they will be removed after the loop.
        else
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
        local learned = goal.recipeID and ns.IsRecipeLearned(addon, goal.recipeID) and true or false
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
          learned = learned,
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

        if (not skipReagents) and goal.recipeID then
          local cache = ns.Data.EnsureRecipeCache(addon)
          local entry = cache and cache[goal.recipeID]
          local hasCatalogRecipe = Catalog and Catalog.HasRecipe and Catalog:HasRecipe(goal.recipeID)

          if entry or hasCatalogRecipe then
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
  end

  for _, goalKey in ipairs(completedGoalKeys) do
    addon.db.profile.goals[goalKey] = nil
  end

  local profNames = CollectSortedProfessionNames(byProf)

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
    local entry = profCache[profName]
    local sig = (rMode ~= "E") and ns.Sorting.BuildRecipeSortSignature(list, rMode) or nil
    if rMode == "E" and entry and entry.order then
      ReleaseTempTable(entry.order)
      profCache[profName] = nil
      entry = nil
    end

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
      if rMode ~= "E" then
        local order = AcquireTempTable()
        for _, r in ipairs(list) do
          table.insert(order, tostring(r.recipeID or r.itemID or r.name or ""))
        end
        if profCache[profName] and profCache[profName].order then
          ReleaseTempTable(profCache[profName].order)
        end
        profCache[profName] = { sig = sig, order = order }
      elseif profCache[profName] and profCache[profName].order then
        ReleaseTempTable(profCache[profName].order)
        profCache[profName] = nil
      end
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

  if not skipReagents then
    ns.Reagents.BuildDisplayOnly(addon)
  end

  for _, profName in ipairs(profNames) do
    local list = byProf[profName]
    if list then
      ReleaseTempTable(list)
    end
  end
  ReleaseTempTable(profNames)
  ReleaseTempTable(byProf)
  ReleaseTempTable(completedGoalKeys)
  ReleaseRecipeMemo(memo)
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

-- Public API -----------------------------------------------------------------

ns.GetRecipeOutputItemID = ns.Recipes.GetRecipeOutputItemID
ns.SetGoalForRecipe = ns.Recipes.SetGoalForRecipe
ns.NoteCraftSucceeded = ns.Recipes.NoteCraftSucceeded
ns.ApplyCompletionByInventoryDelta = ns.Recipes.ApplyCompletionByInventoryDelta
ns.AccumulateReagentsForRecipe = ns.Recipes.AccumulateReagentsForRecipe
ns.RebuildReagentNeedMap = ns.Recipes.RebuildReagentNeedMap
ns.RecomputeDisplayOnly = ns.Recipes.RecomputeDisplayOnly
ns.RecomputeCaches = ns.Recipes.RecomputeCaches
