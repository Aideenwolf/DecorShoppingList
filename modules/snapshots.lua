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
      local tierItemIDs = ns.Data.GetRequiredReagentTierItemIDs and ns.Data.GetRequiredReagentTierItemIDs(slot) or nil
      local qtyReq = (slot and slot.quantityRequired) or (r and r.quantityRequired) or 0
      if r and r.itemID and qtyReq and qtyReq > 0 then
        table.insert(reagents, { itemID = r.itemID, qty = qtyReq, tierItemIDs = tierItemIDs })
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

function ns.Snapshots.SnapshotCurrentCharacter(addon, opts)
  if not (addon and addon.db and addon.db.global and addon.db.global.realms) then return end
  opts = type(opts) == "table" and opts or {}
  local includeQuality = (opts.skipQuality ~= true)

  local realmEntry = GetRealmEntry(addon)
  local entry = GetCharEntry(addon)
  if not realmEntry or not entry then return end
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
    if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo) then return false end
    local ok, slots = pcall(C_Container.GetContainerNumSlots, bagID)
    if not ok or type(slots) ~= "number" or slots <= 0 then return false end

    for slot = 1, slots do
      local info = C_Container.GetContainerItemInfo(bagID, slot)
      if info and info.itemID and info.stackCount then
        addCount(dest, info.itemID, info.stackCount)
        if includeQuality then
          addQualityCount(destByQuality, info.itemID, ns.Data.GetTrackedQualityFromContainerItem(bagID, slot, info), info.stackCount)
        end
      end
    end
    return true
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

  local newBags, newBagsByQuality = {}, {}
  local sawBags = false
  for bag = 0, 4 do
    sawBags = scanBag(bag, newBags, newBagsByQuality) or sawBags
  end
  sawBags = scanBag(5, newBags, newBagsByQuality) or sawBags
  if sawBags then
    entry.bags = newBags
    entry.bagsByQuality = newBagsByQuality
  end

  local bankOpen = false
  if opts.forceWarbank and not opts.forceBank then
    bankOpen = false
  else
    bankOpen = opts.forceBank
        or ((BankFrame and BankFrame:IsShown()) or (ReagentBankFrame and ReagentBankFrame:IsShown()))
  end
  if bankOpen then
    local newBank, newBankByQuality = {}, {}
    local sawBank = false
    sawBank = scanBag(-1, newBank, newBankByQuality) or sawBank
    for bag = 6, 12 do
      sawBank = scanBag(bag, newBank, newBankByQuality) or sawBank
    end
    sawBank = scanBag(-3, newBank, newBankByQuality) or sawBank
    if sawBank then
      entry.bank = newBank
      entry.bankByQuality = newBankByQuality
    end
  end

  local warbankOpen = opts.forceWarbank and true or false
  if C_Bank and C_Bank.IsAccountBankOpen then
    local ok, v = pcall(C_Bank.IsAccountBankOpen)
    warbankOpen = (ok and v) and true or false
  end

  if warbankOpen then
    local tabBagIDs = GetAccountBankTabBagIDs()
    if #tabBagIDs > 0 then
      local newWarbank, newWarbankByQuality = {}, {}
      local sawWarbank = false
      for _, bagID in ipairs(tabBagIDs) do
        sawWarbank = scanBag(bagID, newWarbank, newWarbankByQuality) or sawWarbank
      end
      if sawWarbank then
        realmEntry.warbank = newWarbank
        realmEntry.warbankByQuality = newWarbankByQuality
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

function ns.Snapshots.GetTrackedItemBreakdown(addon, itemID, targetQuality, tierItemIDs)
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

  local useModernQuality = ns.Data.UsesModernReagentQuality and ns.Data.UsesModernReagentQuality(itemID)
  local trackedItemIDs = {}
  if type(tierItemIDs) == "table" and next(tierItemIDs) then
    for quality = 1, 3 do
      if type(tierItemIDs[quality]) == "number" then
        trackedItemIDs[quality] = tierItemIDs[quality]
      end
    end
  end

  local function newCounts()
    return { [1] = 0, [2] = 0, [3] = 0, total = 0 }
  end

  local function sumBucketCounts(entry, bucketName, bucket)
    local counts = newCounts()
    if type(bucket) ~= "table" then
      return counts
    end

    if next(trackedItemIDs) then
      for quality = 1, 3 do
        local trackedItemID = trackedItemIDs[quality]
        if trackedItemID then
          local count = bucket[trackedItemID] or 0
          counts[quality] = count
          counts.total = counts.total + count
        end
      end
      return counts
    end

    if not useModernQuality then
      local count = bucket[itemID] or 0
      counts.total = count
      return counts
    end

    if ns.Data and ns.Data.SumQualityBucketByName then
      ns.Data.SumQualityBucketByName(addon, entry and entry[bucketName], targetName, nil, counts)
      counts.total = (counts[1] or 0) + (counts[2] or 0) + (counts[3] or 0)
    end

    return counts
  end

  local rows = {}
  for charKey, entry in pairs(chars) do
    if type(entry) == "table" then
      local bagCounts = sumBucketCounts(entry, "bagsByQuality", entry.bags)
      local bankCounts = sumBucketCounts(entry, "bankByQuality", entry.bank)
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

  local warbank = sumBucketCounts(realmData, "warbankByQuality", realmData.warbank)

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
