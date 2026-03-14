local ADDON, ns = ...
ns = ns or {}

ns.Snapshots = ns.Snapshots or {}

local function GetRealmEntry(addon)
  addon.db.global.realms = addon.db.global.realms or {}

  local realm = select(1, ns.Data.playerKey())
  if not realm then
    return nil
  end

  local g = addon.db.global.realms
  g[realm] = g[realm] or { chars = {}, warbank = {}, warbankByQuality = {} }
  local realmEntry = g[realm]
  realmEntry.chars = realmEntry.chars or {}
  realmEntry.warbank = realmEntry.warbank or {}
  realmEntry.warbankByQuality = realmEntry.warbankByQuality or {}
  return realmEntry, realm
end

local function GetCharEntry(addon)
  local realmEntry, realm = GetRealmEntry(addon)
  local _, key = ns.Data.playerKey()
  if not realm or not key then
    return nil
  end

  realmEntry.chars[key] = realmEntry.chars[key] or {
    bags = {}, bank = {},
    bagsByQuality = {}, bankByQuality = {},
    recipes = {}, profs = {}, lastSeen = 0,
    className = nil, classToken = nil,
  }

  local entry = realmEntry.chars[key]
  entry.bags = entry.bags or {}
  entry.bank = entry.bank or {}
  entry.bagsByQuality = entry.bagsByQuality or {}
  entry.bankByQuality = entry.bankByQuality or {}
  entry.recipes = entry.recipes or {}
  entry.profs = entry.profs or {}
  entry.lastSeen = entry.lastSeen or 0
  entry.lastRecipeScan = entry.lastRecipeScan or 0
  do
    local className, classToken = UnitClass("player")
    if className and className ~= "" then
      entry.className = className
    end
    if classToken and classToken ~= "" then
      entry.classToken = classToken
    end
  end
  return entry
end

local function GetSnapshotRuntimeState(addon)
  addon._dslSnapshotState = addon._dslSnapshotState or {
    chars = {},
    realms = {},
  }
  return addon._dslSnapshotState
end

local function GetCharSnapshotState(addon)
  local _, key = ns.Data.playerKey()
  if not key then
    return nil
  end

  local state = GetSnapshotRuntimeState(addon)
  state.chars[key] = state.chars[key] or {
    bags = {},
    bank = {},
  }
  return state.chars[key]
end

local function GetRealmSnapshotState(addon)
  local _, realm = GetRealmEntry(addon)
  if not realm then
    return nil
  end

  local state = GetSnapshotRuntimeState(addon)
  state.realms[realm] = state.realms[realm] or {
    warbank = {},
  }
  return state.realms[realm]
end

local function AdjustItemCount(dest, itemID, delta)
  if not (type(dest) == "table" and type(itemID) == "number" and delta and delta ~= 0) then
    return
  end

  local nextValue = (dest[itemID] or 0) + delta
  if nextValue > 0 then
    dest[itemID] = nextValue
  else
    dest[itemID] = nil
  end
end

local function AdjustQualityCount(dest, itemID, quality, delta)
  quality = ns.Data.NormalizeProfessionCraftingQuality(quality)
  if not (type(dest) == "table" and type(itemID) == "number" and quality and delta and delta ~= 0) then
    return
  end

  local byQuality = dest[itemID]
  if not byQuality and delta > 0 then
    byQuality = {}
    dest[itemID] = byQuality
  end
  if not byQuality then
    return
  end

  local nextValue = (byQuality[quality] or 0) + delta
  if nextValue > 0 then
    byQuality[quality] = nextValue
  else
    byQuality[quality] = nil
  end

  if not next(byQuality) then
    dest[itemID] = nil
  end
end

local function ApplySlotState(containerState, slotState, multiplier)
  if not (containerState and slotState and slotState.itemID and slotState.count and slotState.count > 0) then
    return
  end

  local delta = (multiplier or 1) * slotState.count
  AdjustItemCount(containerState.counts, slotState.itemID, delta)
  AdjustQualityCount(containerState.qualityCounts, slotState.itemID, slotState.quality, delta)
end

local function GetContainerState(containerStates, bagID)
  containerStates[bagID] = containerStates[bagID] or {
    slots = {},
    counts = {},
    qualityCounts = {},
  }
  return containerStates[bagID]
end

local function BuildContainerTotals(containerStates, bagIDs, includeQuality)
  local counts = {}
  local qualityCounts = includeQuality and {} or nil

  for _, bagID in ipairs(bagIDs) do
    local containerState = containerStates[bagID]
    if containerState then
      for itemID, count in pairs(containerState.counts or {}) do
        AdjustItemCount(counts, itemID, count)
      end
      if includeQuality and type(containerState.qualityCounts) == "table" then
        for itemID, byQuality in pairs(containerState.qualityCounts) do
          for quality, count in pairs(byQuality) do
            AdjustQualityCount(qualityCounts, itemID, quality, count)
          end
        end
      end
    end
  end

  return counts, qualityCounts
end

local function TablesEqual(a, b)
  if a == b then
    return true
  end
  if type(a) ~= "table" or type(b) ~= "table" then
    return false
  end

  for k, v in pairs(a) do
    local other = b[k]
    if type(v) == "table" or type(other) == "table" then
      if not TablesEqual(v, other) then
        return false
      end
    elseif other ~= v then
      return false
    end
  end

  for k, v in pairs(b) do
    local other = a[k]
    if type(v) == "table" or type(other) == "table" then
      if not TablesEqual(v, other) then
        return false
      end
    elseif other ~= v then
      return false
    end
  end

  return true
end

local function ReplaceIfChanged(dest, key, newValue)
  if TablesEqual(dest[key] or {}, newValue or {}) then
    return false
  end

  dest[key] = newValue or {}
  return true
end

local ScanContainer

local function HasAccessibleContainerSlots(bagIDs)
  if not (C_Container and C_Container.GetContainerNumSlots and type(bagIDs) == "table") then
    return false
  end

  local totalSlots = 0
  for _, bagID in ipairs(bagIDs) do
    local ok, slots = pcall(C_Container.GetContainerNumSlots, bagID)
    if ok and type(slots) == "number" and slots > 0 then
      totalSlots = totalSlots + slots
    end
  end

  return totalSlots > 0
end

local function RefreshContainerTotals(dest, countsKey, qualityKey, containerStates, bagIDs, includeQuality)
  local sawChanges = false
  for _, bagID in ipairs(bagIDs) do
    sawChanges = ScanContainer(containerStates, bagID, includeQuality) or sawChanges
  end

  if not sawChanges then
    return false
  end

  local newCounts, newQualityCounts = BuildContainerTotals(containerStates, bagIDs, includeQuality)
  local changed = ReplaceIfChanged(dest, countsKey, newCounts)

  if includeQuality and qualityKey then
    changed = ReplaceIfChanged(dest, qualityKey, newQualityCounts) or changed
  end

  return changed
end

ScanContainer = function(containerStates, bagID, includeQuality)
  if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo) then
    return false
  end

  local ok, slots = pcall(C_Container.GetContainerNumSlots, bagID)
  if not ok or type(slots) ~= "number" or slots < 0 then
    return false
  end

  local containerState = GetContainerState(containerStates, bagID)
  local seen = {}
  local changed = false

  for slot = 1, slots do
    seen[slot] = true
    local info = C_Container.GetContainerItemInfo(bagID, slot)
    local oldState = containerState.slots[slot]
    local newItemID = info and info.itemID or nil
    local newCount = info and info.stackCount or 0
    local newLink = info and info.hyperlink or nil
    local sameIdentity = oldState
      and oldState.itemID == newItemID
      and oldState.link == newLink
    local sameState = sameIdentity
      and oldState.count == newCount

    if not sameState then
      changed = true
      if oldState then
        ApplySlotState(containerState, oldState, -1)
      end

      if newItemID and newCount > 0 then
        local quality = nil
        if sameIdentity and oldState and oldState.quality then
          quality = oldState.quality
        elseif includeQuality then
          quality = ns.Data.GetTrackedQualityFromContainerItem(bagID, slot, info)
        end

        local newState = {
          itemID = newItemID,
          count = newCount,
          link = newLink,
          quality = quality,
        }
        containerState.slots[slot] = newState
        ApplySlotState(containerState, newState, 1)
      else
        containerState.slots[slot] = nil
      end
    end
  end

  for slot, oldState in pairs(containerState.slots) do
    if not seen[slot] then
      changed = true
      ApplySlotState(containerState, oldState, -1)
      containerState.slots[slot] = nil
    end
  end

  return changed
end

function ns.Snapshots.GetProfessionForRecipe(recipeID)
  if not recipeID then
    return nil, nil
  end

  ns.Data.EnsureProfessionsLoaded()
  if not C_TradeSkillUI then
    return nil, nil
  end

  if C_TradeSkillUI.GetTradeSkillLineForRecipe then
    local tradeSkillID, skillLineName = C_TradeSkillUI.GetTradeSkillLineForRecipe(recipeID)
    if skillLineName and skillLineName ~= "" then
      return skillLineName, tradeSkillID
    end
  end

  if C_TradeSkillUI.GetRecipeSchematic and C_TradeSkillUI.GetProfessionInfoBySkillLineID then
    local schematic = C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
    local skillLineID = schematic and schematic.tradeSkillLineID
    if type(skillLineID) == "number" then
      local pinfo = C_TradeSkillUI.GetProfessionInfoBySkillLineID(skillLineID)
      local pname = pinfo and pinfo.professionName
      if pname and pname ~= "" then
        return pname, skillLineID
      end
    end
  end

  if C_TradeSkillUI.GetRecipeInfo and C_TradeSkillUI.GetProfessionInfoBySkillLineID then
    local info = C_TradeSkillUI.GetRecipeInfo(recipeID)
    local skillLineID = info and info.tradeSkillLineID
    if type(skillLineID) == "number" then
      local pinfo = C_TradeSkillUI.GetProfessionInfoBySkillLineID(skillLineID)
      local pname = pinfo and pinfo.professionName
      if pname and pname ~= "" then
        return pname, skillLineID
      end
    end
  end

  return nil, nil
end

function ns.Snapshots.SnapshotRecipeToCache(addon, recipeID, force)
  if not recipeID then return end

  local cache = ns.Data.EnsureRecipeCache(addon)
  if not cache then return end
  if cache[recipeID] and not force then return end
  if not force and not ns.Snapshots.IsPlayerProfessionUIOpen() then return end
  if not ns.Data.EnsureProfessionsLoaded() then return end

  local schematic = C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
  if not schematic then return end

  local yieldMin = 1
  if schematic.quantityMin and schematic.quantityMin > 0 then
    yieldMin = schematic.quantityMin
  end

  local outputItemID = nil
  if ns.GetRecipeOutputItemID then
    outputItemID = ns.GetRecipeOutputItemID(recipeID)
  end
  if not outputItemID and schematic then
    outputItemID = schematic.outputItemID or schematic.productItemID
  end

  local professionName = nil
  local professionID = nil
  professionName, professionID = ns.Snapshots.GetProfessionForRecipe(recipeID)
  professionName = ns.Data.NormalizeProfessionName(professionName)

  local reagents = {}
  local slots = schematic.reagentSlotSchematics
  if slots then
    for _, slot in ipairs(slots) do
      local r = ns.Data.PickRequiredReagent(slot)
      local tierItemIDs = ns.Data.GetRequiredReagentTierItemIDs and ns.Data.GetRequiredReagentTierItemIDs(slot) or nil
      local qtyReq = (slot and slot.quantityRequired) or (r and r.quantityRequired) or 0
      if r and r.itemID and qtyReq and qtyReq > 0 then
        table.insert(reagents, { itemID = r.itemID, qty = qtyReq, tierItemIDs = tierItemIDs })
      end
    end
  end

  if #reagents == 0 then return end

  cache[recipeID] = {
    outputItemID = outputItemID,
    profession = professionName,
    professionID = professionID,
    recipeName = schematic.name,
    yieldMin = yieldMin,
    reagents = reagents,
    ts = time(),
  }
end

function ns.Snapshots.GetPlayerProfessionSet()
  local set = {}
  local p1, p2, arch, fish, cook = GetProfessions()

  local function addProf(idx)
    if not idx then return end
    local name = GetProfessionInfo(idx)
    if name and name ~= "" then
      set[ns.Data.NormalizeProfessionName(name)] = true
    end
  end

  addProf(p1)
  addProf(p2)
  addProf(arch)
  addProf(fish)
  addProf(cook)

  return set
end

local function SameBooleanSet(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then
    return false
  end

  for k, v in pairs(a) do
    if v == true and b[k] ~= true then
      return false
    end
  end

  for k, v in pairs(b) do
    if v == true and a[k] ~= true then
      return false
    end
  end

  return true
end

local function GetProfessionScanContext(addon)
  if not addon then
    return nil, nil
  end

  local entry = GetCharEntry(addon)
  local currentProfs = ns.Snapshots.GetPlayerProfessionSet()
  return entry, currentProfs
end

function ns.Snapshots.ShouldScanCurrentProfessionLearned(addon)
  if not addon then return false end
  local entry, currentProfs = GetProfessionScanContext(addon)
  if not entry then return true end

  if not SameBooleanSet(entry.profs or {}, currentProfs) then
    return true
  end

  if not entry.lastRecipeScan or entry.lastRecipeScan <= 0 then
    return true
  end

  return false
end

function ns.Snapshots.PlayerHasProfession(profName)
  if not profName or profName == "" or profName == "Unknown" then return false end
  local want = ns.Data.NormalizeProfessionName(profName)
  local set = ns.Snapshots.GetPlayerProfessionSet()
  return set[want] == true
end

function ns.Snapshots.AnyCharHasProfession(addon, profName)
  if not addon or not profName or profName == "" or profName == "Unknown" then return false end

  local want = ns.Data.NormalizeProfessionName(profName)
  local _, realm = GetRealmEntry(addon)
  local realmData = addon.db.global.realms and realm and addon.db.global.realms[realm]
  if not realmData or not realmData.chars then return false end

  for _, entry in pairs(realmData.chars) do
    if entry and entry.profs and entry.profs[want] == true then
      return true
    end
  end

  return false
end

function ns.Snapshots.IsPlayerProfessionUIOpen()
  return (_G.ProfessionsFrame and _G.ProfessionsFrame:IsShown()) == true
end

function ns.Snapshots.ScanCurrentProfessionLearned(addon, force)
  if not addon then return false end
  if addon.inCombat or InCombatLockdown() then return false end
  if not ns.Snapshots.IsPlayerProfessionUIOpen() then return false end
  if not ns.Data.EnsureProfessionsLoaded() then return false end
  if not (C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs and C_TradeSkillUI.GetRecipeInfo) then return false end

  local entry, currentProfs = GetProfessionScanContext(addon)
  if not force and not ns.Snapshots.ShouldScanCurrentProfessionLearned(addon) then
    return false
  end

  local ids = C_TradeSkillUI.GetAllRecipeIDs()
  if type(ids) ~= "table" then return false end

  local changed = false
  for _, rid in ipairs(ids) do
    if type(rid) == "number" and entry.recipes[rid] ~= true then
      local info = C_TradeSkillUI.GetRecipeInfo(rid)
      if info and info.learned == true then
        entry.recipes[rid] = true
        changed = true
      end
    end
  end

  entry.profs = currentProfs
  entry.lastRecipeScan = time()
  return changed
end

function ns.Snapshots.SnapshotCurrentCharacter(addon, opts)
  if not (addon and addon.db and addon.db.global and addon.db.global.realms) then return false end
  opts = type(opts) == "table" and opts or {}
  local includeQuality = (opts.skipQuality ~= true)

  local realmEntry = GetRealmEntry(addon)
  local entry = GetCharEntry(addon)
  if not realmEntry or not entry then return false end
  entry.lastSeen = time()
  local changed = false

  local function GetAccountBankTabBagIDs()
    local out = {}
    local bagIndex = Enum and Enum.BagIndex
    if type(bagIndex) ~= "table" then return out end

    for key, bagID in pairs(bagIndex) do
      if type(key) == "string" and type(bagID) == "number" and string.find(key, "AccountBankTab", 1, true) then
        table.insert(out, bagID)
      end
    end

    table.sort(out)
    return out
  end

  local charState = GetCharSnapshotState(addon)
  local realmState = GetRealmSnapshotState(addon)
  local bagIDs = { 0, 1, 2, 3, 4, 5 }
  if charState and HasAccessibleContainerSlots(bagIDs) then
    changed = RefreshContainerTotals(entry, "bags", "bagsByQuality", charState.bags, bagIDs, includeQuality) or changed
  end

  local bankOpen = false
  if opts.forceWarbank and not opts.forceBank then
    bankOpen = false
  else
    bankOpen = opts.forceBank
        or ((BankFrame and BankFrame:IsShown()) or (ReagentBankFrame and ReagentBankFrame:IsShown()))
  end
  if bankOpen then
    local bankIDs = { -1, 6, 7, 8, 9, 10, 11, 12, -3 }
    if charState and HasAccessibleContainerSlots(bankIDs) then
      changed = RefreshContainerTotals(entry, "bank", "bankByQuality", charState.bank, bankIDs, includeQuality) or changed
    end
  end

  local warbankOpen = opts.forceWarbank and true or false
  if C_Bank and C_Bank.IsAccountBankOpen then
    local ok, v = pcall(C_Bank.IsAccountBankOpen)
    warbankOpen = (ok and v) and true or false
  end

  if warbankOpen then
    local tabBagIDs = GetAccountBankTabBagIDs()
    if #tabBagIDs > 0 and realmState then
      changed = RefreshContainerTotals(realmEntry, "warbank", "warbankByQuality", realmState.warbank, tabBagIDs, includeQuality) or changed
    end
  end

  return changed
end

function ns.Snapshots.SnapshotLearnedRecipes(addon, force)
  return ns.Snapshots.ScanCurrentProfessionLearned(addon, force)
end

function ns.Snapshots.IsRecipeLearned(addon, recipeID)
  if not recipeID then return false end

  local realm, key = ns.Data.playerKey()
  local realms = addon.db.global and addon.db.global.realms
  local realmData = realms and realm and realms[realm]
  local chars = realmData and realmData.chars
  if not chars then return false end

  for _, entry in pairs(chars) do
    if entry and entry.recipes and entry.recipes[recipeID] == true then
      return true
    end
  end

  return false
end

function ns.Snapshots.GetTrackedCharacters(addon)
  if not (addon and addon.db and addon.db.global and addon.db.global.realms) then return {}, nil end

  local realm = select(1, ns.Data.playerKey())
  local _, currentKey = ns.Data.playerKey()
  local _, currentClassToken = UnitClass("player")
  local realmData = realm and addon.db.global.realms[realm]
  local chars = realmData and realmData.chars
  if not chars then return {}, realm end

  local out = {}
  for charKey, entry in pairs(chars) do
    if type(entry) == "table" then
      local bagCount = 0
      local bankCount = 0
      local recipeCount = 0

      for _, count in pairs(entry.bags or {}) do
        if type(count) == "number" and count > 0 then
          bagCount = bagCount + count
        end
      end
      for _, count in pairs(entry.bank or {}) do
        if type(count) == "number" and count > 0 then
          bankCount = bankCount + count
        end
      end
      for _, learned in pairs(entry.recipes or {}) do
        if learned == true then
          recipeCount = recipeCount + 1
        end
      end

      table.insert(out, {
        charKey = charKey,
        charName = tostring(charKey or ""):match("^([^-]+)") or tostring(charKey or "?"),
        className = entry.className,
        classToken = entry.classToken or ((charKey == currentKey) and currentClassToken or nil),
        lastSeen = tonumber(entry.lastSeen) or 0,
        lastRecipeScan = tonumber(entry.lastRecipeScan) or 0,
        bagCount = bagCount,
        bankCount = bankCount,
        recipeCount = recipeCount,
      })
    end
  end

  table.sort(out, function(a, b)
    if a.lastSeen ~= b.lastSeen then
      return a.lastSeen > b.lastSeen
    end
    return tostring(a.charKey or "") < tostring(b.charKey or "")
  end)

  return out, realm
end

function ns.Snapshots.GetTrackedItemBreakdown(addon, itemID, tierItemIDs)
  if not (addon and addon.db and addon.db.global and addon.db.global.realms and itemID) then
    return {}, { [1] = 0, [2] = 0, [3] = 0, total = 0 }
  end

  local targetName = ns.Data.ResolveItemGroupName and ns.Data.ResolveItemGroupName(addon, itemID)
  if not targetName or targetName == "" then
    return {}, { [1] = 0, [2] = 0, [3] = 0, total = 0 }
  end

  local realm = select(1, ns.Data.playerKey())
  local _, currentKey = ns.Data.playerKey()
  local _, currentClassToken = UnitClass("player")
  local realmData = realm and addon.db.global.realms[realm]
  local chars = realmData and realmData.chars
  if not chars then
    return {}, { [1] = 0, [2] = 0, [3] = 0, total = 0 }
  end

  local rows = {}
  for charKey, entry in pairs(chars) do
    if type(entry) == "table" then
      local bagCounts = (ns.Data.GetReagentSourceCounts and ns.Data.GetReagentSourceCounts(addon, entry.bags, entry.bagsByQuality, itemID, tierItemIDs)) or { total = 0 }
      local bankCounts = (ns.Data.GetReagentSourceCounts and ns.Data.GetReagentSourceCounts(addon, entry.bank, entry.bankByQuality, itemID, tierItemIDs)) or { total = 0 }
      local total = (bagCounts.total or 0) + (bankCounts.total or 0)

      if total > 0 then
        table.insert(rows, {
          charKey = charKey,
          charName = tostring(charKey or ""):match("^([^-]+)") or tostring(charKey or "?"),
          classToken = entry.classToken or ((charKey == currentKey) and currentClassToken or nil),
          lastSeen = tonumber(entry.lastSeen) or 0,
          bags = bagCounts.total or 0,
          bank = bankCounts.total or 0,
          counts = {
            [1] = (bagCounts[1] or 0) + (bankCounts[1] or 0),
            [2] = (bagCounts[2] or 0) + (bankCounts[2] or 0),
            [3] = (bagCounts[3] or 0) + (bankCounts[3] or 0),
            total = total,
          },
          total = total,
        })
      end
    end
  end

  table.sort(rows, function(a, b)
    if a.total ~= b.total then
      return a.total > b.total
    end
    return tostring(a.charKey or "") < tostring(b.charKey or "")
  end)

  local warbank = (ns.Data.GetReagentSourceCounts and ns.Data.GetReagentSourceCounts(addon, realmData.warbank, realmData.warbankByQuality, itemID, tierItemIDs)) or { total = 0 }

  return rows, warbank
end

ns.GetPlayerProfessionSet = ns.Snapshots.GetPlayerProfessionSet
ns.PlayerHasProfession = ns.Snapshots.PlayerHasProfession
ns.AnyCharHasProfession = ns.Snapshots.AnyCharHasProfession
ns.SnapshotCurrentCharacter = ns.Snapshots.SnapshotCurrentCharacter
ns.SnapshotLearnedRecipes = ns.Snapshots.SnapshotLearnedRecipes
ns.IsRecipeLearned = ns.Snapshots.IsRecipeLearned
ns.ScanCurrentProfessionLearned = ns.Snapshots.ScanCurrentProfessionLearned
ns.GetTrackedCharacters = ns.Snapshots.GetTrackedCharacters
ns.GetTrackedItemBreakdown = ns.Snapshots.GetTrackedItemBreakdown
