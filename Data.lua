-- DecorShoppingList/Data.lua
local ADDON, ns = ...
ns = ns or {}

local L = LibStub("AceLocale-3.0"):GetLocale("DecorShoppingList")

-- -------------------------
-- Helpers
-- -------------------------

local professionsTried = false
local function EnsureProfessionsLoaded()
  if not professionsTried and type(LoadAddOn) == "function" and not (C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic) then
    professionsTried = true
    pcall(LoadAddOn, "Blizzard_Professions")
  end
  return (C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic) and true or false
end

local function ceilDiv(a, b)
  if not b or b <= 0 then return 0 end
  return math.floor((a + b - 1) / b)
end

local function playerKey()
  local name, realm = UnitFullName("player")
  if not name or name == "" then
    return nil, nil
  end

  realm = realm or GetRealmName()
  if not realm or realm == "" then
    return nil, nil
  end

  return realm, (name .. "-" .. realm)
end

local function GetItemNameFast(itemID)
  if not itemID then return nil end

  local name
  if C_Item and C_Item.GetItemNameByID then
    name = C_Item.GetItemNameByID(itemID)
  end
  if not name then
    name = GetItemInfo(itemID)
  end

  if name then return name end

  if C_Item and C_Item.RequestLoadItemDataByID then
    C_Item.RequestLoadItemDataByID(itemID)
  end

  return nil
end

local function GetItemQuality(itemID)
  if not itemID then return nil end
  if C_Item and C_Item.GetItemQualityByID then
    return C_Item.GetItemQualityByID(itemID)
  end
  return select(3, GetItemInfo(itemID))
end

local function ColorizeByQuality(itemID, text)
  if not itemID or not text then return text end
  local q = GetItemQuality(itemID)
  if q == nil then return text end

  if ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q] and ITEM_QUALITY_COLORS[q].color then
    return ITEM_QUALITY_COLORS[q].color:WrapTextInColorCode(text)
  end

  local _, _, _, hex = GetItemQualityColor(q)
  if hex then
    return "|c" .. hex .. text .. "|r"
  end

  return text
end

local function GetItemExpansionID(itemID)
  if not itemID then return nil end

  -- GetItemInfo returns expacID as the 15th return value (if cached/available).
  local expacID = select(15, GetItemInfo(itemID))
  if expacID ~= nil then
    return expacID
  end

  if C_Item and C_Item.RequestLoadItemDataByID then
    C_Item.RequestLoadItemDataByID(itemID)
  end

  return nil
end

local EXPAC_NAMES = {
  [0]  = "Classic",
  [1]  = "The Burning Crusade",
  [2]  = "Wrath of the Lich King",
  [3]  = "Cataclysm",
  [4]  = "Mists of Pandaria",
  [5]  = "Warlords of Draenor",
  [6]  = "Legion",
  [7]  = "Battle for Azeroth",
  [8]  = "Shadowlands",
  [9]  = "Dragonflight",
  [10] = "The War Within",
  [11] = "Midnight",
  [12] = "The Last Titan",
}

local function GetExpansionName(expacID)
  if expacID == nil or expacID < 0 then return "Unknown" end
  return EXPAC_NAMES[expacID] or ("Expansion " .. tostring(expacID))
end

-- -------------------------
-- Source classification (LibPeriodicTable-3.1 + your recipe map)
-- -------------------------

local PT = LibStub and LibStub("LibPeriodicTable-3.1", true)

-- Manual overrides: Lumbering is a Gathering subcat
ns.LUMBER_ITEM_IDS = ns.LUMBER_ITEM_IDS or {}

local function PT_InSet(itemID, setName)
  if not (PT and itemID and setName) then return false end
  return PT.ItemInSet and PT:ItemInSet(itemID, setName) or false
end

-- Returns: source, subSource
-- source: "Gathering" | "Crafting" | "Vendor" | "Other"
-- subSource (Gathering only): "Herbalism" | "Mining" | "Skinning" | "Fishing" | "Lumbering" | (other)
local function GetReagentSource(addon, itemID)
  if not itemID then return "Other", nil end

  -- Crafting = produced by a known recipe (your learned mapping)
  if addon and addon.db and addon.db.profile and addon.db.profile.recipeByItem
    and addon.db.profile.recipeByItem[itemID]
  then
    return "Crafting", nil
  end

  -- Force "* Lumber" items into Gathering → Lumbering
  do
    local name = GetItemNameFast(itemID)
    if name and name:match(" Lumber$") then
      return "Gathering", "Lumbering"
    end
  end


  -- Gathering sub-types (LibPeriodicTable)
  if PT then
    if PT_InSet(itemID, "Tradeskill.Gather.Herbalism") then
      return "Gathering", "Herbalism"
    end
    if PT_InSet(itemID, "Tradeskill.Gather.Mining") then
      return "Gathering", "Mining"
    end
    if PT_InSet(itemID, "Tradeskill.Gather.Skinning") then
      return "Gathering", "Skinning"
    end
    if PT_InSet(itemID, "Tradeskill.Gather.Fishing") then
      return "Gathering", "Fishing"
    end
  end

  -- Fallback heuristics (covers newer mats missing from PT sets)
  do
    local _, _, _, _, classID, subClassID = GetItemInfoInstant(itemID)
    if classID and subClassID and Enum and Enum.ItemClass and Enum.ItemSubClass and Enum.ItemSubClass.Tradegoods then
      if classID == Enum.ItemClass.Tradegoods then
        if subClassID == Enum.ItemSubClass.Tradegoods.MetalAndStone then
          return "Gathering", "Mining"
        end
        if subClassID == Enum.ItemSubClass.Tradegoods.Herb then
          return "Gathering", "Herbalism"
        end
        if subClassID == Enum.ItemSubClass.Tradegoods.Leather then
          return "Gathering", "Skinning"
        end
      end
    end
  end

  -- Vendor
  if PT_InSet(itemID, "Tradeskill.Mat.BySource.Vendor") then
    return "Vendor", nil
  end

  return "Other", nil
end

local function PickRequiredReagent(slot)
  if not slot or not slot.reagents or #slot.reagents == 0 then return nil end
  for _, r in ipairs(slot.reagents) do
    if r and (r.required == true) then
      return r
    end
  end
  return slot.reagents[1]
end

local function GetRecipeSchematicSafe(recipeID)
  if not recipeID then return nil end
  if not EnsureProfessionsLoaded() then return nil end
  return C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
end

local function EnsureRecipeCache(addon)
  if not (addon and addon.db and addon.db.profile) then return nil end
  addon.db.profile.recipeCache = addon.db.profile.recipeCache or {}
  return addon.db.profile.recipeCache
end

local function SnapshotRecipeToCache(addon, recipeID, force)
  if not recipeID then return end

  local cache = EnsureRecipeCache(addon)
  if not cache then return end

  -- Reagent definitions are effectively static; only snapshot once unless explicitly forced.
  if cache[recipeID] and not force then return end

  -- Hard rule: only scan profession/recipe data when the profession UI is open (unless forced).
  if not force and not IsPlayerProfessionUIOpen() then return end

  if not EnsureProfessionsLoaded() then return end

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
      local r = PickRequiredReagent(slot)
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

  local function GetProfessionForRecipe(recipeID)
  if not recipeID then
    return nil, nil
  end

  EnsureProfessionsLoaded()
  if not C_TradeSkillUI then
    return nil, nil
  end

  -- Best: direct mapping (when available)
  if C_TradeSkillUI.GetTradeSkillLineForRecipe then
    local tradeSkillID, skillLineName = C_TradeSkillUI.GetTradeSkillLineForRecipe(recipeID)
    if skillLineName and skillLineName ~= "" then
      return skillLineName, tradeSkillID
    end
  end

  -- Reliable path (even when the profession UI isn't open): schematic often contains tradeSkillLineID
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

  -- Fallback: pull tradeSkillLineID from recipe info, then resolve to profession name
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

local function NormalizeProfessionName(name)
  if not name or name == "" then return "Unknown" end

  name = name:gsub("^Dragon Isles%s+", "")
  name = name:gsub("^Khaz Algar%s+", "")
  name = name:gsub("^Zandalari%s+", "")
  name = name:gsub("^Kul Tiran%s+", "")
  name = name:gsub("^Northrend%s+", "")
  name = name:gsub("^Outland%s+", "")
  name = name:gsub("^Pandaria%s+", "")
  name = name:gsub("^Draenor%s+", "")
  name = name:gsub("^Legion%s+", "")
  name = name:gsub("^Shadowlands%s+", "")
  name = name:gsub("^Cataclysm%s+", "")
  name = name:gsub("^Wrath%s+of%s+the%s+Lich%s+King%s+", "")
  name = name:gsub("^Battle%s+for%s+Azeroth%s+", "")

  for _, prof in ipairs({
    "Alchemy","Blacksmithing","Enchanting","Engineering","Herbalism","Inscription",
    "Jewelcrafting","Leatherworking","Mining","Skinning","Tailoring","Cooking","Fishing","First Aid"
  }) do
    if name:find(prof, 1, true) then
      return prof
    end
  end

  return name
end

-- -------------------------
-- Profession ownership checks (player)
-- -------------------------

function ns.GetPlayerProfessionSet()
  local set = {}

  local p1, p2, arch, fish, cook = GetProfessions()
  local function addProf(idx)
    if not idx then return end
    local name = GetProfessionInfo(idx)
    if name and name ~= "" then
      set[NormalizeProfessionName(name)] = true
    end
  end

  addProf(p1)
  addProf(p2)
  addProf(arch)
  addProf(fish)
  addProf(cook)

  return set
end

function ns.PlayerHasProfession(profName)
  if not profName or profName == "" or profName == "Unknown" then return false end
  local want = NormalizeProfessionName(profName)
  local set = ns.GetPlayerProfessionSet()
  return set[want] == true
end

function ns.AnyCharHasProfession(addon, profName)
  if not addon or not profName or profName == "" or profName == "Unknown" then return false end

  local want = NormalizeProfessionName(profName)
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

-- -------------------------
-- Learned recipe cache (per character)
-- Sticky rule:
--   - once TRUE, never set false again for that character
--   - only query live while the player Profession UI is open
-- -------------------------

local function GetCharEntry(addon)
  addon.db.global.realms = addon.db.global.realms or {}

  local realm, key = playerKey()
  if not realm or not key then
    return nil
  end

  local g = addon.db.global.realms
  g[realm] = g[realm] or { chars = {} }
  g[realm].chars[key] = g[realm].chars[key] or {
    items = {}, bags = {}, bank = {}, warbank = {}, recipes = {}, profs = {}, lastSeen = 0
  }

  local entry = g[realm].chars[key]
  entry.items    = entry.items    or {}
  entry.bags     = entry.bags     or {}
  entry.bank     = entry.bank     or {}
  entry.warbank  = entry.warbank  or {}
  entry.recipes  = entry.recipes  or {}
  entry.profs    = entry.profs    or {}
  entry.lastSeen = entry.lastSeen or 0
  entry.lastRecipeScan = entry.lastRecipeScan or 0
  return entry
end

local function IsPlayerProfessionUIOpen()
  return (_G.ProfessionsFrame and _G.ProfessionsFrame:IsShown()) == true
end

-- Scan the currently open profession list and promote learned TRUE into THIS character's cache.
-- Returns true if anything changed.
local function ScanCurrentProfessionLearned(addon)
  if not addon then return false end
  if addon.inCombat or InCombatLockdown() then return false end
  if not IsPlayerProfessionUIOpen() then return false end
  if not EnsureProfessionsLoaded() then return false end
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

-- Snapshot current character inventory into db (bags always; bank only if open)
function ns.SnapshotCurrentCharacter(addon)
  if not (addon and addon.db and addon.db.global and addon.db.global.realms) then return end

  local entry = GetCharEntry(addon)
  if not entry then return end

  entry.lastSeen = time()

  local function addCount(dest, itemID, count)
    if not (dest and itemID and count and count > 0) then return end
    dest[itemID] = (dest[itemID] or 0) + count
  end

  local function scanBag(bagID, dest)
    if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo) then return end
    local ok, slots = pcall(C_Container.GetContainerNumSlots, bagID)
    if not ok or type(slots) ~= "number" or slots <= 0 then return end

    for slot = 1, slots do
      local info = C_Container.GetContainerItemInfo(bagID, slot)
      if info and info.itemID and info.stackCount then
        addCount(dest, info.itemID, info.stackCount)
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

  -- Bags
  entry.bags = {}
  for bag = 0, 4 do
    scanBag(bag, entry.bags)
  end

  -- Reagent bag (Retail): usually 5
  scanBag(5, entry.bags)

  -- Bank (only if open)
  local bankOpen = (BankFrame and BankFrame:IsShown()) or (ReagentBankFrame and ReagentBankFrame:IsShown())
  if bankOpen then
    entry.bank = {}

    -- Main bank container
    scanBag(-1, entry.bank)

    -- Bank bags are commonly 6..12 in Retail; scan defensively
    for bag = 6, 12 do
      scanBag(bag, entry.bank)
    end

    -- Reagent bank container (Retail): -3
    scanBag(-3, entry.bank)
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
      for _, bagID in ipairs(tabBagIDs) do
        scanBag(bagID, entry.warbank)
      end
    end
  end
end

-- Return "have" count for an item.
-- If includeAlts is true: sum across all known characters on this realm (bags + stored bank).
-- If includeAlts is false: only current character (bags + stored bank).
function ns.GetHaveCount(addon, itemID)
  if not (addon and addon.db and itemID) then return 0 end

  -- Provide method-style access too (addon:GetHaveCount(itemID))
  if addon.GetHaveCount == nil then
    addon.GetHaveCount = function(self, id)
      return ns.GetHaveCount(self, id)
    end
  end

  local realm, key = playerKey()
  local realms = addon.db.global and addon.db.global.realms
  local realmData = realms and realms[realm]
  local chars = realmData and realmData.chars
  if not chars then return 0 end

  local function countEntry(entry)
    if type(entry) ~= "table" then return 0 end
    local bags = entry.bags or {}
    local bank = entry.bank or {}
    local warbank = entry.warbank or {}
    return (bags[itemID] or 0) + (bank[itemID] or 0) + (warbank[itemID] or 0)
  end

  -- HaveTotal = HaveCurrent + HaveAlt (+ Warbank later, if added)
  local total = 0
  for _, entry in pairs(chars) do
    total = total + countEntry(entry)
  end

  return total
end

-- Called by Core.lua on TRADE_SKILL_LIST_UPDATE / SHOW / NEW_RECIPE_LEARNED
function ns.SnapshotLearnedRecipes(addon)
  return ns.ScanCurrentProfessionLearned(addon)
end

-- Sticky cache rules:
-- - TRUE is forever once learned on THIS character
-- - Never write FALSE to cache
-- - Only query live API while the player profession UI is open
function ns.IsRecipeLearned(addon, recipeID)
  if not recipeID then return false end

  local realm, key = playerKey()
  local realms = addon.db.global and addon.db.global.realms
  local realmData = realms and realm and realms[realm]
  local chars = realmData and realmData.chars
  if not chars then return false end

  -- "Known" = learned on ANY character (sticky TRUE across alts)
  for _, entry in pairs(chars) do
    if entry and entry.recipes and entry.recipes[recipeID] == true then
      return true
    end
  end

  -- Only when the profession UI is open do we attempt to promote learned state
  -- (still only promotes TRUE; never writes FALSE)
  if not IsPlayerProfessionUIOpen() then
    return false
  end

  local cur = chars[key]
  if EnsureProfessionsLoaded() and C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo then
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

-- Public wrapper to reuse the local implementation (avoid duplicate logic)
function ns.ScanCurrentProfessionLearned(addon)
  return ScanCurrentProfessionLearned(addon)
end

-- -------------------------
-- Public API
-- -------------------------

function ns.GetRecipeOutputItemID(recipeID)
  if not recipeID then return nil end

  local schematic = GetRecipeSchematicSafe(recipeID)
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

function ns.SetGoalForRecipe(addon, recipeID, deltaQty)
  if not recipeID or not deltaQty or deltaQty == 0 then return end

  local goals = addon.db.profile.goals
  local key = "r:" .. tostring(recipeID)

  goals[key] = goals[key] or { recipeID = recipeID, qty = 0, remaining = 0 }
  local g = goals[key]

  g.qty = math.max(0, (g.qty or 0) + deltaQty)
  g.remaining = math.max(0, (g.remaining or 0) + deltaQty)

  -- Cache-miss behavior:
  -- If recipe reagents aren't cached yet and the profession UI isn't open, flag goal as needing a scan.
  local cache = EnsureRecipeCache(addon)
  if cache and cache[recipeID] then
    g.needsScan = nil
  else
    if IsPlayerProfessionUIOpen() then
      SnapshotRecipeToCache(addon, recipeID, true)
      if cache and cache[recipeID] then
        g.needsScan = nil
      else
        g.needsScan = true
      end
    else
      g.needsScan = true
    end
  end

  -- Seed learned-cache when tracking from the profession UI (prevents learned state "resetting")
  ns.IsRecipeLearned(addon, recipeID) 

  -- Tag profession using API mapping that does NOT depend on the profession UI being open
  EnsureProfessionsLoaded()
  do
    local profName, profID = GetProfessionForRecipe(recipeID)
    g.profession = NormalizeProfessionName(profName) or "Unknown"
    g.professionID = profID
  end

  local out = ns.GetRecipeOutputItemID(recipeID)
  if out then
    g.itemID = out
    addon.db.profile.recipeByItem[out] = recipeID
  end

  do
    local schematic = GetRecipeSchematicSafe(recipeID)
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
  end

  addon:MarkDirty()

  -- One-time migration/fix-up: ensure legacy saved goals have a profession grouping
  -- (old entries were incorrectly tagged and now won't show under real professions).
  addon.db.profile.migrations = addon.db.profile.migrations or {}
  if not addon.db.profile.migrations.professionFixV1 then
    for _, goal in pairs(addon.db.profile.goals) do
      if type(goal) == "table" and goal.recipeID and (goal.remaining or 0) > 0 then
        if not goal.profession or goal.profession == "" or goal.profession == "Unknown" or goal.profession == "Enchanting" then
          goal.profession = "Unknown"
          goal.professionID = nil
        end
      end
    end
    addon.db.profile.migrations.professionFixV1 = true
  end
end

function ns.ApplyCompletionByInventoryDelta(addon)
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
        local haveNow = ns.GetHaveCount(addon, itemID)
        local havePrev = addon.lastHave[itemID]

        if havePrev == nil then
          addon.lastHave[itemID] = haveNow
        else
          local delta = haveNow - havePrev
          if delta > 0 and (goal.remaining or 0) > 0 then
            goal.remaining = math.max(0, (goal.remaining or 0) - delta)
            touched = true
          end
          addon.lastHave[itemID] = haveNow
        end

        if (goal.remaining or 0) <= 0 then
          local rawName = GetItemNameFast(itemID) or goal.name or ("Item " .. itemID)
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

local function BuildReagentsDisplayOnly(addon)
  local collapsed = (addon.db.profile.window and addon.db.profile.window.collapsed) or {}

  local flat = {}
  for itemID, need in pairs(addon.cache.reagents or {}) do
    local have = ns.GetHaveCount(addon, itemID)
    local remaining = math.max(0, (need or 0) - (have or 0))

    local rawName = GetItemNameFast(itemID) or ("Item " .. itemID)
    local isComplete = (remaining <= 0)
    local displayName = isComplete and rawName or ColorizeByQuality(itemID, rawName)

    local rarity = GetItemQuality(itemID) or -1
    local expacID = GetItemExpansionID(itemID)
    local expacName = GetExpansionName(expacID)
    local source, subSource = GetReagentSource(addon, itemID)

    table.insert(flat, {
      itemID = itemID,
      name = displayName,
      rawName = rawName,
      need = need or 0,
      have = have or 0,
      remaining = remaining,
      rarity = rarity,
      expacID = expacID,
      expacName = expacName,
      source = source,
      subSource = subSource,
      isComplete = isComplete,
    })
  end

  local mode = (addon.db.profile.window and addon.db.profile.window.reagentSort) or "E"

  local function nameKey(x) return (x.rawName or ""):lower() end
  local function rarityKey(x) return (x.rarity or -1) end

  local function completeAwareCompare(a, b, innerCompare)
    if a.isComplete ~= b.isComplete then
      return (a.isComplete == false)
    end
    if a.isComplete and b.isComplete then
      return nameKey(a) < nameKey(b)
    end
    return innerCompare(a, b)
  end

  local function sortN(a, b)
    return nameKey(a) < nameKey(b)
  end

  local function sortR(a, b)
    local ar, br = rarityKey(a), rarityKey(b)
    if ar ~= br then return ar > br end
    return nameKey(a) < nameKey(b)
  end

  local function sortEInner(a, b)
    local ae, be = (a.expacID or -1), (b.expacID or -1)
    if ae ~= be then return ae > be end
    local ar, br = rarityKey(a), rarityKey(b)
    if ar ~= br then return ar > br end
    return nameKey(a) < nameKey(b)
  end

  local function sortSInner(a, b)
    local sourceOrder = { Gathering = 1, Crafting = 2, Vendor = 3, Other = 4 }
    local sa = sourceOrder[a.source or "Other"] or 99
    local sb = sourceOrder[b.source or "Other"] or 99
    if sa ~= sb then return sa < sb end

    local function subRank(src, sub)
      if src == "Gathering" then
        local subOrder = { Herbalism = 1, Mining = 2, Skinning = 3, Fishing = 4, Lumbering = 5 }
        return subOrder[sub or ""] or 99
      elseif src == "Crafting" then
        local subOrder = {
          Alchemy = 1, Blacksmithing = 2, Enchanting = 3, Engineering = 4, Inscription = 5,
          Jewelcrafting = 6, Leatherworking = 7, Tailoring = 8, Cooking = 9,
        }
        return subOrder[sub or ""] or 99
      end
      return 99
    end

    if (a.source == b.source) and ((a.source == "Gathering") or (a.source == "Crafting")) then
      local ra = subRank(a.source, a.subSource)
      local rb = subRank(b.source, b.subSource)
      if ra ~= rb then return ra < rb end
    end

    local ar, br = rarityKey(a), rarityKey(b)
    if ar ~= br then return ar > br end
    return nameKey(a) < nameKey(b)
  end

  if mode == "N" then
    table.sort(flat, function(a, b) return completeAwareCompare(a, b, sortN) end)
    addon.cache.reagentsList = flat
    addon.cache.reagentsDisplay = flat
    return
  end

  if mode == "R" then
    table.sort(flat, function(a, b) return completeAwareCompare(a, b, sortR) end)
    addon.cache.reagentsList = flat
    addon.cache.reagentsDisplay = flat
    return
  end

  if mode == "S" then
    table.sort(flat, function(a, b) return completeAwareCompare(a, b, sortSInner) end)

    local display = {}

    local byGather = {}
    local byCraft = {}
    local vendor, other = {}, {}

    for _, e in ipairs(flat) do
      if e.source == "Gathering" then
        local sub = e.subSource or "Other"
        byGather[sub] = byGather[sub] or {}
        table.insert(byGather[sub], e)

      elseif e.source == "Crafting" then
        local sub = e.subSource or "Other"
        byCraft[sub] = byCraft[sub] or {}
        table.insert(byCraft[sub], e)

      elseif e.source == "Vendor" then
        table.insert(vendor, e)

      else
        table.insert(other, e)
      end
    end


    -- Source: Gathering (structured + collapsible)
    if next(byGather) then
      local gKey = "SRC:GATHER"
      table.insert(display, { isHeader = true, name = "Gathering", groupKey = gKey, profession = gKey, level = 0 })

      if not collapsed[gKey] then
        local subOrder = { "Herbalism", "Mining", "Skinning", "Fishing", "Lumbering" }
        for _, sub in ipairs(subOrder) do
          local list = byGather[sub]
          if list and #list > 0 then
            local subKey = gKey .. ":" .. sub
            table.insert(display, { isHeader = true, name = sub, groupKey = subKey, profession = subKey, parentKey = gKey, level = 1 })
            if not collapsed[subKey] then
              for _, e in ipairs(list) do
                e.level = 2
                table.insert(display, e)
              end
            end
          end
        end
      end
    end

      -- Source: Crafting (parent + subgroups)
      if next(byCraft) then
        local cKey = "SRC:CRAFTING"
        table.insert(display, { isHeader = true, name = "Crafting", groupKey = cKey, profession = cKey, level = 0 })

        if not collapsed[cKey] then
          local subOrder = {
            "Alchemy","Blacksmithing","Enchanting","Engineering","Inscription","Jewelcrafting",
            "Leatherworking","Tailoring","Cooking","Other"
          }

          for _, sub in ipairs(subOrder) do
            local list = byCraft[sub]
            if list and #list > 0 then
              local subKey = cKey .. ":" .. sub
              table.insert(display, { isHeader = true, name = sub, groupKey = subKey, profession = subKey, parentKey = cKey, level = 1 })

              if not collapsed[subKey] then
                for _, e in ipairs(list) do
                  e.level = 2
                  table.insert(display, e)
                end
              end
            end
          end
        end
      end

    -- Source: Vendor
    if #vendor > 0 then
      local vKey = "SRC:VENDOR"
      table.insert(display, { isHeader = true, name = "Vendor", groupKey = vKey, profession = vKey, level = 0 })
      if not collapsed[vKey] then
        for _, e in ipairs(vendor) do
          e.level = 1
          table.insert(display, e)
        end
      end
    end

    -- Source: Other
    if #other > 0 then
      local oKey = "SRC:OTHER"
      table.insert(display, { isHeader = true, name = "Other", groupKey = oKey, profession = oKey, level = 0 })
      if not collapsed[oKey] then
        for _, e in ipairs(other) do
          e.level = 1
          table.insert(display, e)
        end
      end
    end

    addon.cache.reagentsList = flat
    addon.cache.reagentsDisplay = display
    return
  end

  -- "E" default
  table.sort(flat, function(a, b) return completeAwareCompare(a, b, sortEInner) end)

  local display = {}
  local byExpac = {}
  local expacOrder = {}

  for _, e in ipairs(flat) do
    local id = e.expacID
    if id == nil then
      id = -1
      e.expacID = id
      e.expacName = "Unknown"
    end

    if byExpac[id] == nil then
      byExpac[id] = {}
      table.insert(expacOrder, id)
    end
    table.insert(byExpac[id], e)
  end

  table.sort(expacOrder, function(a, b)
    a = a or -1
    b = b or -1
    return a > b
  end)

  for _, id in ipairs(expacOrder) do
    local list = byExpac[id]
    if list and #list > 0 then
      local headerName = GetExpansionName(id)
      local key = "EXPAC:" .. tostring(id)
      table.insert(display, { isHeader = true, name = headerName, profession = key, groupKey = key, level = 0 })

      if not collapsed[key] then
        for _, e in ipairs(list) do
          e.level = 1
          table.insert(display, e)
        end
      end
    end
  end

  addon.cache.reagentsList = flat
  addon.cache.reagentsDisplay = display
end

-- -------------------------
-- Recompute (recipes + reagents)
-- -------------------------

local function GetRecipeDisplayName(goal)
  if goal.itemID then
    local itemName = GetItemNameFast(goal.itemID)
    if itemName then
      return ColorizeByQuality(goal.itemID, itemName)
    end
  end

  if goal.recipeID then
    local schematic = GetRecipeSchematicSafe(goal.recipeID)
    if schematic and schematic.name then
      return schematic.name
    end
  end

  if goal.name then return goal.name end
  if goal.recipeID then return "Recipe " .. goal.recipeID end
  if goal.itemID then return "Item " .. goal.itemID end
  return "Unknown"
end

function ns.RecomputeReagentsOnly(addon)
  if not (addon and addon.cache and addon.cache.reagents) then return end
  addon.cache.reagentsList = {}
  addon.cache.reagentsDisplay = {}
  BuildReagentsDisplayOnly(addon)
end

-- Display-only rebuild: rebuild *Display arrays from existing caches without touching math/state.
function ns.RecomputeDisplayOnly(addon)
  if not (addon and addon.cache) then return end

  -- If base caches aren't present yet, fall back to full.
  if not addon.cache.recipes or not addon.cache.reagentsList then
    return ns.RecomputeCaches(addon)
  end

  addon.db.profile.window = addon.db.profile.window or {}
  addon.db.profile.window.collapsed = addon.db.profile.window.collapsed or {}
  local collapsed = addon.db.profile.window.collapsed

  -- -------------------------
  -- RecipesDisplay from cached recipes
  -- -------------------------
  addon.cache.recipesDisplay = {}

  local byProf = {}
  for _, row in ipairs(addon.cache.recipes) do
    local prof = (row.profession and row.profession ~= "") and row.profession or "Unknown"
    byProf[prof] = byProf[prof] or {}
    table.insert(byProf[prof], row)
  end

  local profNames = {}
  for profName, _ in pairs(byProf) do
    table.insert(profNames, profName)
  end
  table.sort(profNames)

  local rMode = (addon.db.profile.window and addon.db.profile.window.recipeSort) or "N"

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

    if rMode == "E" then
      table.sort(list, function(a, b)
        local ae, be = (a.expacID or -1), (b.expacID or -1)
        if ae ~= be then return ae > be end
        return (a.name or "") < (b.name or "")
      end)
    else
      table.sort(list, function(a, b)
        return (a.name or "") < (b.name or "")
      end)
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

  -- -------------------------
  -- ReagentsDisplay from cached reagentsList (re-sort only)
  -- -------------------------
  local flat = {}
  for _, e in ipairs(addon.cache.reagentsList or {}) do
    table.insert(flat, e)
  end

  local function nameKey(x) return (x.rawName or x.name or ""):lower() end
  local function rarityKey(x) return (x.rarity or -1) end

  local function completeAwareCompare(a, b, innerCompare)
    if a.isComplete ~= b.isComplete then
      return (a.isComplete == false)
    end
    if a.isComplete and b.isComplete then
      return nameKey(a) < nameKey(b)
    end
    return innerCompare(a, b)
  end

  local mode = (addon.db.profile.window and addon.db.profile.window.reagentSort) or "E"

  local function sortN(a, b) return nameKey(a) < nameKey(b) end

  local function sortR(a, b)
    local ar, br = rarityKey(a), rarityKey(b)
    if ar ~= br then return ar > br end
    return nameKey(a) < nameKey(b)
  end

  local function sortEInner(a, b)
    local ae, be = (a.expacID or -1), (b.expacID or -1)
    if ae ~= be then return ae > be end
    local ar, br = rarityKey(a), rarityKey(b)
    if ar ~= br then return ar > br end
    return nameKey(a) < nameKey(b)
  end

  local function sortSInner(a, b)
    local sourceOrder = { Gathering = 1, Crafting = 2, Vendor = 3, Other = 4 }
    local sa = sourceOrder[a.source or "Other"] or 99
    local sb = sourceOrder[b.source or "Other"] or 99
    if sa ~= sb then return sa < sb end

    if (a.source == "Gathering") and (b.source == "Gathering") then
      local subOrder = { Herbalism = 1, Mining = 2, Skinning = 3, Fishing = 4, Lumbering = 5 }
      local aSub = subOrder[a.subSource or ""] or 99
      local bSub = subOrder[b.subSource or ""] or 99
      if aSub ~= bSub then return aSub < bSub end
    end

    local ar, br = rarityKey(a), rarityKey(b)
    if ar ~= br then return ar > br end
    return nameKey(a) < nameKey(b)
  end

  if mode == "N" then
    table.sort(flat, function(a, b) return completeAwareCompare(a, b, sortN) end)
    addon.cache.reagentsList = flat
    addon.cache.reagentsDisplay = flat
    return
  end

  if mode == "R" then
    table.sort(flat, function(a, b) return completeAwareCompare(a, b, sortR) end)
    addon.cache.reagentsList = flat
    addon.cache.reagentsDisplay = flat
    return
  end

  if mode == "S" then
    table.sort(flat, function(a, b) return completeAwareCompare(a, b, sortSInner) end)

    local display = {}
    local byGather = {}
    local byCraft = {}
    local vendor, other = {}, {}

    for _, e in ipairs(flat) do
      if e.source == "Gathering" then
        local sub = e.subSource or "Other"
        byGather[sub] = byGather[sub] or {}
        table.insert(byGather[sub], e)

      elseif e.source == "Crafting" then
        local sub = e.subSource or "Other"
        byCraft[sub] = byCraft[sub] or {}
        table.insert(byCraft[sub], e)

      elseif e.source == "Vendor" then
        table.insert(vendor, e)

      else
        table.insert(other, e)
      end
    end

    -- Gathering (parent + subgroups)
    if next(byGather) then
      local gKey = "SRC:GATHER"
      table.insert(display, { isHeader = true, name = "Gathering", groupKey = gKey, profession = gKey, level = 0 })

      if not collapsed[gKey] then
        local subOrder = { "Herbalism", "Mining", "Skinning", "Fishing", "Lumbering", "Other" }
        for _, sub in ipairs(subOrder) do
          local list = byGather[sub]
          if list and #list > 0 then
            local subKey = gKey .. ":" .. sub
            table.insert(display, { isHeader = true, name = sub, groupKey = subKey, profession = subKey, parentKey = gKey, level = 1 })

            if not collapsed[subKey] then
              for _, r in ipairs(list) do
                r.level = 2
                table.insert(display, r)
              end
            end
          end
        end
      end
    end

    -- Crafting (parent + subgroups)
    if next(byCraft) then
      local cKey = "SRC:CRAFTING"
      table.insert(display, { isHeader = true, name = "Crafting", groupKey = cKey, profession = cKey, level = 0 })

      if not collapsed[cKey] then
        local subOrder = {
          "Alchemy","Blacksmithing","Enchanting","Engineering","Inscription","Jewelcrafting",
          "Leatherworking","Tailoring","Cooking","Other"
        }

        for _, sub in ipairs(subOrder) do
          local list = byCraft[sub]
          if list and #list > 0 then
            local subKey = cKey .. ":" .. sub
            table.insert(display, { isHeader = true, name = sub, groupKey = subKey, profession = subKey, parentKey = cKey, level = 1 })

            if not collapsed[subKey] then
              for _, r in ipairs(list) do
                r.level = 2
                table.insert(display, r)
              end
            end
          end
        end
      end
    end

    -- Vendor
    if #vendor > 0 then
      local vKey = "SRC:VENDOR"
      table.insert(display, { isHeader = true, name = "Vendor", groupKey = vKey, profession = vKey, level = 0 })
      if not collapsed[vKey] then
        for _, r in ipairs(vendor) do
          r.level = 1
          table.insert(display, r)
        end
      end
    end

    -- Other
    if #other > 0 then
      local oKey = "SRC:OTHER"
      table.insert(display, { isHeader = true, name = "Other", groupKey = oKey, profession = oKey, level = 0 })
      if not collapsed[oKey] then
        for _, r in ipairs(other) do
          r.level = 1
          table.insert(display, r)
        end
      end
    end

    addon.cache.reagentsList = flat
    addon.cache.reagentsDisplay = display
    return
  end

  -- "E" default
  table.sort(flat, function(a, b) return completeAwareCompare(a, b, sortEInner) end)

  local display = {}
  local byExpac = {}
  local expacOrder = {}

  for _, e in ipairs(flat) do
    local id = e.expacID
    if id == nil then
      id = -1
      e.expacID = id
      e.expacName = "Unknown"
    end

    if byExpac[id] == nil then
      byExpac[id] = {}
      table.insert(expacOrder, id)
    end
    table.insert(byExpac[id], e)
  end

  table.sort(expacOrder, function(a, b)
    a = a or -1
    b = b or -1
    return a > b
  end)

  for _, id in ipairs(expacOrder) do
    local list = byExpac[id]
    if list and #list > 0 then
      local headerName = GetExpansionName(id)
      local key = "EXPAC:" .. tostring(id)
      table.insert(display, { isHeader = true, name = headerName, profession = key, groupKey = key, level = 0 })

      if not collapsed[key] then
        for _, r in ipairs(list) do
          r.level = 1
          table.insert(display, r)
        end
      end
    end
  end

  addon.cache.reagentsList = flat
  addon.cache.reagentsDisplay = display
  return
end

function ns.RecomputeCaches(addon)
  addon.cache = addon.cache or {}
  addon.cache.recipes = {}
  addon.cache.recipesDisplay = {}
  addon.cache.reagents = {}
  addon.cache.reagentsList = {}
  addon.cache.reagentsDisplay = {}

  addon.db.profile.window = addon.db.profile.window or {}
  addon.db.profile.window.collapsed = addon.db.profile.window.collapsed or {}

  if addon.db.profile.includeAlts then
    if ns.BuildAltItemSums then
      ns.BuildAltItemSums(addon)
    end
  else
    if addon.cache then
      addon.cache.altItemSums = nil
    end
  end

  local collapsed = addon.db.profile.window.collapsed
  local byProf = {}
  
    -- Sort reuse caches (avoid resorting when order-driving inputs didn't change)
  addon.cache._sortCache = addon.cache._sortCache or {}
  addon.cache._sortCache.recipesByProf = addon.cache._sortCache.recipesByProf or {}
  addon.cache._sortCache.reagents = addon.cache._sortCache.reagents or {}

  -- Memoization for expensive-but-stable lookups during this recompute pass
  local memo = {
    profByRecipe = {},
    hasProfByName = {},
    outputItemByRecipe = {},
    qualityByItem = {},
    expacByItem = {},
    expacNameByID = {},
    iconByItem = {},
  }

  local function MemoProfName(recipeID)
    if not recipeID then return "Unknown" end
    local v = memo.profByRecipe[recipeID]
    if v ~= nil then return v end
    v = NormalizeProfessionName(select(1, GetProfessionForRecipe(recipeID)))
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
    v = GetItemQuality(itemID) or -1
    memo.qualityByItem[itemID] = v
    return v
  end

  local function MemoExpacID(itemID)
    if not itemID then return nil end
    local v = memo.expacByItem[itemID]
    if v ~= nil then return v end
    v = GetItemExpansionID(itemID)
    memo.expacByItem[itemID] = v
    return v
  end

  local function MemoExpacName(expacID)
    if expacID == nil then return "Unknown" end
    local v = memo.expacNameByID[expacID]
    if v ~= nil then return v end
    v = GetExpansionName(expacID) or "Unknown"
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

		  -- Always try to tag the profession (for grouping)
		  local profName = NormalizeProfessionName(goal.profession)
		  if not profName or profName == "Unknown" then
			profName = MemoProfName(goal.recipeID)
			goal.profession = profName
		  end

		  local hasProf = (profName and profName ~= "Unknown") and MemoHasProf(profName) or false

		  if includeAlts then
			-- INCLUDE ALTS: never hide anything. If you can't craft it on this character, show the X.
			allowed = true
			if (not hasProf) then
			  missingRecipe = true
			else
			  local learned = ns.IsRecipeLearned(addon, goal.recipeID)
			  if learned == false then
				missingRecipe = true
			  end
			end
		  else
			-- NO ALTS: hide professions this character doesn't have
			if (profName and profName ~= "Unknown") and (not hasProf) then
			  allowed = false
			else
			  allowed = true
			  -- If the character has the profession, show X when not learned
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
        -- If it's Unknown, tag via recipe->skillLine mapping (does not require opening the profession UI)
        if goal.recipeID and (not goal.profession or goal.profession == "" or goal.profession == "Unknown") then
          local pname, pid = GetProfessionForRecipe(goal.recipeID)
          if pname and pname ~= "" then
            goal.profession = pname
            goal.professionID = pid
          end
        end

        if not goal.profession or goal.profession == "" then
          goal.profession = "Unknown"
        end

        local itemID = goal.itemID
        if goal.recipeID and not itemID then
          itemID = MemoOutputItem(goal.recipeID)
          if itemID then goal.itemID = itemID end
        end

        local name = GetRecipeDisplayName(goal)
        local rarity = (goal.itemID and MemoQuality(goal.itemID)) or -1
        local prof = NormalizeProfessionName(goal.profession) or "Unknown"
        goal.profession = prof

		local expacID = itemID and MemoExpacID(itemID) or nil
		local expacName = MemoExpacName(expacID)

		local pInfo = ns.GetProfessionInfo and ns.GetProfessionInfo(prof) or nil

		local row = {
		  name = name,
		  rawName = goal.name or name,
		  remaining = goal.remaining or 0,
		  recipeID = goal.recipeID,
		  itemID = itemID,
		  outputItemID = itemID,
		  profession = prof,
		  professionIcon = pInfo and pInfo.icon or nil,
		  rarity = rarity,
		  missing = missingRecipe,

		  -- cache once (reduces work in ListWindow refresh + enables recipe tooltip expansion)
		  expacID = expacID,
		  expacName = expacName,
		  icon = itemID and MemoIcon(itemID) or nil,
		}

        byProf[prof] = byProf[prof] or {}
        table.insert(byProf[prof], row)
        table.insert(addon.cache.recipes, row)

        if goal.recipeID then
          local cache = EnsureRecipeCache(addon)
          local entry = cache and cache[goal.recipeID]

          -- Only snapshot on cache miss, and only when profession UI is open.
          if not entry and IsPlayerProfessionUIOpen() then
            SnapshotRecipeToCache(addon, goal.recipeID, false)
            entry = cache and cache[goal.recipeID]
          end

          if entry then
            goal.needsScan = nil
            row.needsScan = nil
            ns.AccumulateReagentsForRecipe(addon, goal.recipeID, goal.remaining or 0, 0)
          else
            goal.needsScan = true
            row.needsScan = true
          end
        end
      end
    end
  end

  local profNames = {}
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
    -- Reuse prior sorted order if the membership hasn't changed (and sort mode matches)
    local profCache = addon.cache._sortCache.recipesByProf
    local rMode = (addon.db.profile.window and addon.db.profile.window.recipeSort) or "N"
    local sig = tostring(#list) .. "|" .. tostring(rMode)

    local entry = profCache[profName]
    if entry and entry.sig == sig and entry.order then
      local map = {}
      for _, r in ipairs(list) do
        local k = tostring(r.recipeID or r.itemID or r.name or "")
        map[k] = r
      end

      local ordered = {}
      local ok = true
      for _, k in ipairs(entry.order) do
        local r = map[k]
        if not r then ok = false break end
        table.insert(ordered, r)
      end

      if ok and #ordered == #list then
        list = ordered
        byProf[profName] = ordered
      else
        entry = nil
      end
    end

    if not entry then
      if rMode == "E" then
        table.sort(list, function(a, b)
          local ae, be = (a.expacID or -1), (b.expacID or -1)
          if ae ~= be then return ae > be end
          return (a.name or "") < (b.name or "")
        end)
      else
        table.sort(list, function(a, b)
          return (a.name or "") < (b.name or "")
        end)
      end

      local order = {}
      for _, r in ipairs(list) do
        table.insert(order, tostring(r.recipeID or r.itemID or r.name or ""))
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

  -- -------------------------
  -- Reagents list + sorting modes (N / R / E / S)
  -- -------------------------

  local flat = {}
  for itemID, need in pairs(addon.cache.reagents) do
    local have = ns.GetHaveCount(addon, itemID)
    local remaining = math.max(0, (need or 0) - (have or 0))

    local rawName = GetItemNameFast(itemID) or ("Item " .. itemID)
    local isComplete = (remaining <= 0)

    -- If complete, do NOT embed quality color codes in the name (so the row greys correctly)
    local displayName = isComplete and rawName or ColorizeByQuality(itemID, rawName)

    local rarity = GetItemQuality(itemID) or -1
    local expacID = GetItemExpansionID(itemID)
    local expacName = GetExpansionName(expacID)
    local source, subSource = GetReagentSource(addon, itemID)

    table.insert(flat, {
      itemID = itemID,
      name = displayName,
      rawName = rawName,
      need = need or 0,
      have = have or 0,
      remaining = remaining,
      rarity = rarity,
      expacID = expacID,
      expacName = expacName,
      source = source,
      subSource = subSource,
      isComplete = isComplete,
    })
  end

  local function nameKey(x) return (x.rawName or ""):lower() end
  local function rarityKey(x) return (x.rarity or -1) end

  local function completeAwareCompare(a, b, innerCompare)
    if a.isComplete ~= b.isComplete then
      return (a.isComplete == false)
    end
    if a.isComplete and b.isComplete then
      return nameKey(a) < nameKey(b)
    end
    return innerCompare(a, b)
  end

  local mode = (addon.db.profile.window and addon.db.profile.window.reagentSort) or "E"

  local function sortN(a, b)
    return ((a.rawName or a.name or ""):lower()) < ((b.rawName or b.name or ""):lower())
  end

  local function sortR(a, b)
    local ar, br = rarityKey(a), rarityKey(b)
    if ar ~= br then return ar > br end
    return nameKey(a) < nameKey(b)
  end

  local function sortEInner(a, b)
    local ae, be = (a.expacID or -1), (b.expacID or -1)
    if ae ~= be then return ae > be end
    local ar, br = rarityKey(a), rarityKey(b)
    if ar ~= br then return ar > br end
    return nameKey(a) < nameKey(b)
  end

  local function sortSInner(a, b)
    local sourceOrder = { Gathering = 1, Crafting = 2, Vendor = 3, Other = 4 }
    local sa = sourceOrder[a.source or "Other"] or 99
    local sb = sourceOrder[b.source or "Other"] or 99
    if sa ~= sb then return sa < sb end

    local function subRank(src, sub)
      if src == "Gathering" then
        local subOrder = { Herbalism = 1, Mining = 2, Skinning = 3, Fishing = 4, Lumbering = 5 }
        return subOrder[sub or ""] or 99
      elseif src == "Crafting" then
        local subOrder = {
          Alchemy = 1, Blacksmithing = 2, Enchanting = 3, Engineering = 4, Inscription = 5,
          Jewelcrafting = 6, Leatherworking = 7, Tailoring = 8, Cooking = 9,
        }
        return subOrder[sub or ""] or 99
      end
      return 99
    end

    if (a.source == b.source) and ((a.source == "Gathering") or (a.source == "Crafting")) then
      local ra = subRank(a.source, a.subSource)
      local rb = subRank(b.source, b.subSource)
      if ra ~= rb then return ra < rb end
    end

    local ar, br = rarityKey(a), rarityKey(b)
    if ar ~= br then return ar > br end
    return nameKey(a) < nameKey(b)
  end

  if mode == "N" then
    table.sort(flat, function(a, b) return completeAwareCompare(a, b, sortN) end)
    addon.cache.reagentsList = flat
    addon.cache.reagentsDisplay = flat
    return
  elseif mode == "R" then
    table.sort(flat, function(a, b) return completeAwareCompare(a, b, sortR) end)
    addon.cache.reagentsList = flat
    addon.cache.reagentsDisplay = flat
    return
  elseif mode == "E" then
    table.sort(flat, function(a, b) return completeAwareCompare(a, b, sortEInner) end)

    local display = {}
    local byExpac = {}
    local expacOrder = {}

    for _, e in ipairs(flat) do
      local id = e.expacID or -1
      if byExpac[id] == nil then
        byExpac[id] = {}
        table.insert(expacOrder, id)
      end
      table.insert(byExpac[id], e)
    end

    table.sort(expacOrder, function(a, b)
      a = a or -1
      b = b or -1
      return a > b
    end)

    for _, id in ipairs(expacOrder) do
      local list = byExpac[id]
      if list and #list > 0 then
        local headerName = GetExpansionName(id)
        local key = "EXPAC:" .. tostring(id)
        table.insert(display, { isHeader = true, name = headerName, profession = key, groupKey = key, level = 0 })

        if not collapsed[key] then
          for _, e in ipairs(list) do
            e.level = 1
            table.insert(display, e)
          end
        end
      end
    end

    addon.cache.reagentsList = flat
    addon.cache.reagentsDisplay = display
    return
  else
    -- "S" Source grouping (with subgroups)
    table.sort(flat, function(a, b) return completeAwareCompare(a, b, sortSInner) end)

    local display = {}
    local byGather = {}
    local byCraft = {}
    local vendor, other = {}, {}

    for _, e in ipairs(flat) do
      if e.source == "Gathering" then
        local sub = e.subSource or "Other"
        byGather[sub] = byGather[sub] or {}
        table.insert(byGather[sub], e)
      elseif e.source == "Crafting" then
        local sub = e.subSource or "Other"
        byCraft[sub] = byCraft[sub] or {}
        table.insert(byCraft[sub], e)
      elseif e.source == "Vendor" then
        table.insert(vendor, e)
      else
        table.insert(other, e)
      end
    end

    if next(byGather) then
      local gKey = "SRC:GATHER"
      table.insert(display, { isHeader = true, name = "Gathering", groupKey = gKey, profession = gKey, level = 0 })

      if not collapsed[gKey] then
        local subOrder = { "Herbalism", "Mining", "Skinning", "Fishing", "Lumbering" }
        for _, sub in ipairs(subOrder) do
          local list = byGather[sub]
          if list and #list > 0 then
            local subKey = gKey .. ":" .. sub
            table.insert(display, { isHeader = true, name = sub, groupKey = subKey, profession = subKey, parentKey = gKey, level = 1 })
            if not collapsed[subKey] then
              for _, e in ipairs(list) do
                e.level = 2
                table.insert(display, e)
              end
            end
          end
        end

        for sub, list in pairs(byGather) do
          local known = false
          for _, k in ipairs(subOrder) do if k == sub then known = true break end end
          if (not known) and list and #list > 0 then
            local subKey = gKey .. ":" .. sub
            table.insert(display, { isHeader = true, name = sub, groupKey = subKey, profession = subKey, parentKey = gKey, level = 1 })
            if not collapsed[subKey] then
              for _, e in ipairs(list) do
                e.level = 2
                table.insert(display, e)
              end
            end
          end
        end
      end
    end

    if next(byCraft) then
      local cKey = "SRC:CRAFTING"
      table.insert(display, { isHeader = true, name = "Crafting", groupKey = cKey, profession = cKey, level = 0 })

      if not collapsed[cKey] then
        local subOrder = { "Alchemy", "Blacksmithing", "Enchanting", "Engineering", "Inscription", "Jewelcrafting", "Leatherworking", "Tailoring", "Cooking" }
        for _, sub in ipairs(subOrder) do
          local list = byCraft[sub]
          if list and #list > 0 then
            local subKey = cKey .. ":" .. sub
            table.insert(display, { isHeader = true, name = sub, groupKey = subKey, profession = subKey, parentKey = cKey, level = 1 })
            if not collapsed[subKey] then
              for _, e in ipairs(list) do
                e.level = 2
                table.insert(display, e)
              end
            end
          end
        end

        for sub, list in pairs(byCraft) do
          local known = false
          for _, k in ipairs(subOrder) do if k == sub then known = true break end end
          if (not known) and list and #list > 0 then
            local subKey = cKey .. ":" .. sub
            table.insert(display, { isHeader = true, name = sub, groupKey = subKey, profession = subKey, parentKey = cKey, level = 1 })
            if not collapsed[subKey] then
              for _, e in ipairs(list) do
                e.level = 2
                table.insert(display, e)
              end
            end
          end
        end
      end
    end

    local function AddSimpleGroup(title, key, list)
      if not list or #list == 0 then return end
      table.insert(display, { isHeader = true, name = title, groupKey = key, profession = key, level = 0 })
      if not collapsed[key] then
        for _, e in ipairs(list) do
          e.level = 1
          table.insert(display, e)
        end
      end
    end

    AddSimpleGroup("Vendor", "SRC:VENDOR", vendor)
    AddSimpleGroup("Other", "SRC:OTHER", other)

    addon.cache.reagentsList = flat
    addon.cache.reagentsDisplay = display
    return
  end
end

function ns.BuildAltItemSums(addon)
  if not (addon and addon.db and addon.db.global and addon.db.global.realms) then return end

  addon.cache = addon.cache or {}
  addon.cache.altItemSums = {}

  local realm, _ = playerKey()
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
      addTable(entry.warbank) -- if you store this separately later
    end
  end
end

function ns.AccumulateReagentsForRecipe(addon, recipeID, desiredItems, depth)
  if depth > 20 then return end
  if not recipeID or desiredItems <= 0 then return end

  local yieldMin, reagentsList

  local schematic = GetRecipeSchematicSafe(recipeID)
  if schematic then
    yieldMin = 1
    if schematic.quantityMin and schematic.quantityMin > 0 then
      yieldMin = schematic.quantityMin
    end

    reagentsList = {}
    local slots = schematic.reagentSlotSchematics
    if slots then
      for _, slot in ipairs(slots) do
        local r = PickRequiredReagent(slot)
        local qtyReq = (slot and slot.quantityRequired) or (r and r.quantityRequired) or 0
        if r and r.itemID and qtyReq and qtyReq > 0 then
          table.insert(reagentsList, { itemID = r.itemID, qty = qtyReq })
        end
      end
    end

    if reagentsList and #reagentsList > 0 then
      local cache = EnsureRecipeCache(addon)
		if cache then
		  cache[recipeID] = { yieldMin = yieldMin, reagents = reagentsList, ts = time() }
		end
    end
  end

  if (not reagentsList or #reagentsList == 0) then
	local cache = EnsureRecipeCache(addon)
	if not cache then return end
	local snap = cache[recipeID]
    if not snap or not snap.reagents or #snap.reagents == 0 then
      return
    end
    yieldMin = snap.yieldMin or 1
    reagentsList = snap.reagents
  end

  local craftsNeeded = ceilDiv(desiredItems, yieldMin)
  if craftsNeeded <= 0 then return end

  for _, r in ipairs(reagentsList) do
    if r and r.itemID and r.qty then
      local itemID = r.itemID
      local qty = (r.qty * craftsNeeded)
      addon.cache.reagents[itemID] = (addon.cache.reagents[itemID] or 0) + qty
    end
  end
end
