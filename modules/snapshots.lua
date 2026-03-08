local ADDON, ns = ...
ns = ns or {}

ns.Snapshots = ns.Snapshots or {}

local function GetCharEntry(addon)
  addon.db.global.realms = addon.db.global.realms or {}

  local realm, key = ns.Data.playerKey()
  if not realm or not key then
    return nil
  end

  local g = addon.db.global.realms
  g[realm] = g[realm] or { chars = {} }
  g[realm].chars[key] = g[realm].chars[key] or {
    items = {}, bags = {}, bank = {}, warbank = {},
    bagsByQuality = {}, bankByQuality = {}, warbankByQuality = {},
    recipes = {}, profs = {}, lastSeen = 0
  }

  local entry = g[realm].chars[key]
  entry.items = entry.items or {}
  entry.bags = entry.bags or {}
  entry.bank = entry.bank or {}
  entry.warbank = entry.warbank or {}
  entry.bagsByQuality = entry.bagsByQuality or {}
  entry.bankByQuality = entry.bankByQuality or {}
  entry.warbankByQuality = entry.warbankByQuality or {}
  entry.recipes = entry.recipes or {}
  entry.profs = entry.profs or {}
  entry.lastSeen = entry.lastSeen or 0
  entry.lastRecipeScan = entry.lastRecipeScan or 0
  return entry
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

  local reagents = {}
  local slots = schematic.reagentSlotSchematics
  if slots then
    for _, slot in ipairs(slots) do
      local r = ns.Data.PickRequiredReagent(slot)
      local qtyReq = (slot and slot.quantityRequired) or (r and r.quantityRequired) or 0
      if r and r.itemID and qtyReq and qtyReq > 0 then
        table.insert(reagents, { itemID = r.itemID, qty = qtyReq })
      end
    end
  end

  if #reagents == 0 then return end

  cache[recipeID] = {
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

function ns.Snapshots.PlayerHasProfession(profName)
  if not profName or profName == "" or profName == "Unknown" then return false end
  local want = ns.Data.NormalizeProfessionName(profName)
  local set = ns.Snapshots.GetPlayerProfessionSet()
  return set[want] == true
end

function ns.Snapshots.AnyCharHasProfession(addon, profName)
  if not addon or not profName or profName == "" or profName == "Unknown" then return false end

  local want = ns.Data.NormalizeProfessionName(profName)
  local realm = GetRealmName() or "UnknownRealm"
  local realmData = addon.db.global.realms and addon.db.global.realms[realm]
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

function ns.Snapshots.ScanCurrentProfessionLearned(addon)
  if not addon then return false end
  if addon.inCombat or InCombatLockdown() then return false end
  if not ns.Snapshots.IsPlayerProfessionUIOpen() then return false end
  if not ns.Data.EnsureProfessionsLoaded() then return false end
  if not (C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs and C_TradeSkillUI.GetRecipeInfo) then return false end

  local entry = GetCharEntry(addon)
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

  if changed then
    entry.lastRecipeScan = time()
  end
  return changed
end

function ns.Snapshots.SnapshotCurrentCharacter(addon)
  if not (addon and addon.db and addon.db.global and addon.db.global.realms) then return end

  local entry = GetCharEntry(addon)
  if not entry then return end
  entry.lastSeen = time()

  local function addCount(dest, itemID, count)
    if not (dest and itemID and count and count > 0) then return end
    dest[itemID] = (dest[itemID] or 0) + count
  end

  local function addQualityCount(dest, itemID, quality, count)
    quality = ns.Data.NormalizeTrackedQuality(quality)
    if not (dest and itemID and quality and count and count > 0) then return end
    dest[itemID] = dest[itemID] or {}
    dest[itemID][quality] = (dest[itemID][quality] or 0) + count
  end

  local function scanBag(bagID, dest, destByQuality)
    if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo) then return end
    local ok, slots = pcall(C_Container.GetContainerNumSlots, bagID)
    if not ok or type(slots) ~= "number" or slots <= 0 then return end

    for slot = 1, slots do
      local info = C_Container.GetContainerItemInfo(bagID, slot)
      if info and info.itemID and info.stackCount then
        addCount(dest, info.itemID, info.stackCount)
        addQualityCount(destByQuality, info.itemID, ns.Data.GetTrackedQualityFromContainerItem(bagID, slot, info), info.stackCount)
      end
    end
  end

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

  entry.bags = {}
  entry.bagsByQuality = {}
  for bag = 0, 4 do
    scanBag(bag, entry.bags, entry.bagsByQuality)
  end
  scanBag(5, entry.bags, entry.bagsByQuality)

  local bankOpen = (BankFrame and BankFrame:IsShown()) or (ReagentBankFrame and ReagentBankFrame:IsShown())
  if bankOpen then
    entry.bank = {}
    entry.bankByQuality = {}
    scanBag(-1, entry.bank, entry.bankByQuality)
    for bag = 6, 12 do
      scanBag(bag, entry.bank, entry.bankByQuality)
    end
    scanBag(-3, entry.bank, entry.bankByQuality)
  end

  local warbankOpen = false
  if C_Bank and C_Bank.IsAccountBankOpen then
    local ok, v = pcall(C_Bank.IsAccountBankOpen)
    warbankOpen = (ok and v) and true or false
  end

  if warbankOpen or bankOpen then
    local tabBagIDs = GetAccountBankTabBagIDs()
    if #tabBagIDs > 0 then
      entry.warbank = {}
      entry.warbankByQuality = {}
      for _, bagID in ipairs(tabBagIDs) do
        scanBag(bagID, entry.warbank, entry.warbankByQuality)
      end
    end
  end
end

function ns.Snapshots.SnapshotLearnedRecipes(addon)
  return ns.Snapshots.ScanCurrentProfessionLearned(addon)
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

  if not ns.Snapshots.IsPlayerProfessionUIOpen() then
    return false
  end

  local cur = chars[key]
  if ns.Data.EnsureProfessionsLoaded() and C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo then
    local info = C_TradeSkillUI.GetRecipeInfo(recipeID)
    if info and info.learned ~= nil then
      local learned = info.learned and true or false
      if learned == true and cur then
        cur.recipes = cur.recipes or {}
        cur.recipes[recipeID] = true
      end
      return learned
    end
  end

  return false
end

function ns.Snapshots.BuildAltItemSums(addon)
  if not (addon and addon.db and addon.db.global and addon.db.global.realms) then return end

  addon.cache = addon.cache or {}
  addon.cache.altItemSums = {}

  local realm = ns.Data.playerKey()
  local realmData = addon.db.global.realms[realm]
  local chars = realmData and realmData.chars
  if not chars then return end

  local sums = addon.cache.altItemSums

  local function addTable(t)
    if type(t) ~= "table" then return end
    for itemID, count in pairs(t) do
      if itemID and count and count > 0 then
        sums[itemID] = (sums[itemID] or 0) + count
      end
    end
  end

  for _, entry in pairs(chars) do
    if type(entry) == "table" then
      addTable(entry.bags)
      addTable(entry.bank)
      addTable(entry.warbank)
    end
  end
end

ns.GetPlayerProfessionSet = ns.Snapshots.GetPlayerProfessionSet
ns.PlayerHasProfession = ns.Snapshots.PlayerHasProfession
ns.AnyCharHasProfession = ns.Snapshots.AnyCharHasProfession
ns.SnapshotCurrentCharacter = ns.Snapshots.SnapshotCurrentCharacter
ns.SnapshotLearnedRecipes = ns.Snapshots.SnapshotLearnedRecipes
ns.IsRecipeLearned = ns.Snapshots.IsRecipeLearned
ns.ScanCurrentProfessionLearned = ns.Snapshots.ScanCurrentProfessionLearned
ns.BuildAltItemSums = ns.Snapshots.BuildAltItemSums
