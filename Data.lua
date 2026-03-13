-- DecorShoppingList/Data.lua
local ADDON, ns = ...
ns = ns or {}

local L = LibStub("AceLocale-3.0"):GetLocale("DecorShoppingList")

-- -------------------------
-- Helpers
-- -------------------------

local professionsTried = false
local function EnsureProfessionsLoaded()
---@diagnostic disable-next-line: undefined-global
  if not professionsTried and type(LoadAddOn) == "function" and not (C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic) then
    professionsTried = true
---@diagnostic disable-next-line: undefined-global
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

local function NormalizeTrackedQuality(quality)
  quality = tonumber(quality)
  if quality == nil then return nil end
  quality = math.floor(quality)
  if quality < 1 or quality > 3 then return nil end
  return quality
end

local QUALITY_LABELS = {
  [1] = "Bronze",
  [2] = "Silver",
  [3] = "Gold",
}

local QUALITY_ATLAS_CANDIDATES = {
  [1] = { "Professions-Icon-Quality-Tier1-Small", "Professions-Icon-Quality-Tier1" },
  [2] = { "Professions-Icon-Quality-Tier2-Small", "Professions-Icon-Quality-Tier2" },
  [3] = { "Professions-Icon-Quality-Tier3-Small", "Professions-Icon-Quality-Tier3" },
}

local function GetTrackedQualityLabel(quality)
  quality = NormalizeTrackedQuality(quality)
  return quality and QUALITY_LABELS[quality] or nil
end

local function GetTrackedReagentQualityFromItemInfo(itemInfo)
  local api = C_TradeSkillUI
  if api then
    for _, fn in pairs({
      api.GetItemReagentQualityInfo,
    }) do
      if type(fn) == "function" then
        local ok, info = pcall(fn, itemInfo)
        local quality = NormalizeTrackedQuality(ok and type(info) == "table" and info.quality or nil)
        if quality then
          return quality
        end
      end
    end

    for _, fn in pairs({
      api.GetItemReagentQualityByItemInfo,
    }) do
      if type(fn) == "function" then
        local ok, quality = pcall(fn, itemInfo)
        quality = NormalizeTrackedQuality(ok and quality or nil)
        if quality then
          return quality
        end
      end
    end
  end

  return nil
end

local function GetTrackedQualityFromItemInfo(itemInfo)
  local quality = GetTrackedReagentQualityFromItemInfo(itemInfo)
  if quality then
    return quality
  end

  local api = C_TradeSkillUI
  if api then
    for _, fn in pairs({
      api.GetItemCraftedQualityInfo,
    }) do
      if type(fn) == "function" then
        local ok, info = pcall(fn, itemInfo)
        quality = NormalizeTrackedQuality(ok and type(info) == "table" and info.quality or nil)
        if quality then
          return quality
        end
      end
    end

    for _, fn in pairs({
      api.GetItemCraftedQualityByItemInfo,
    }) do
      if type(fn) == "function" then
        local ok
        ok, quality = pcall(fn, itemInfo)
        quality = NormalizeTrackedQuality(ok and quality or nil)
        if quality then
          return quality
        end
      end
    end
  end

  return nil
end

local function GetTrackedQualityFromItemLink(itemLink)
  return GetTrackedReagentQualityFromItemInfo(itemLink)
end

local function GetTrackedQualityFromContainerItem(bagID, slot, info)
  local itemLink = info and info.hyperlink
  if (not itemLink or itemLink == "") and C_Container and C_Container.GetContainerItemLink then
    local ok, link = pcall(C_Container.GetContainerItemLink, bagID, slot)
    if ok then
      itemLink = link
    end
  end
  if (not itemLink or itemLink == "") and ItemLocation and C_Item and C_Item.GetItemLink then
    local ok, itemLocation = pcall(ItemLocation.CreateFromBagAndSlot, bagID, slot)
    if ok and itemLocation then
      local okLink, link = pcall(C_Item.GetItemLink, itemLocation)
      if okLink then
        itemLink = link
      end
    end
  end
  local quality = GetTrackedQualityFromItemInfo(itemLink)
  if quality then
    return quality
  end

  return nil
end

local function ItemSupportsTrackedQuality(itemID)
  if not itemID then
    return false
  end
  return NormalizeTrackedQuality(GetTrackedReagentQualityFromItemInfo(itemID)) ~= nil
end

local function GetTrackedQualityFromOwnedItemID(itemID)
  local quality = NormalizeTrackedQuality(GetTrackedReagentQualityFromItemInfo(itemID))
  if quality then
    return quality
  end

  return nil
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

local function IsDecorItem(itemID)
  if not itemID then return false end

  local itemType, itemSubType = select(6, GetItemInfoInstant(itemID))
  if not itemType then
    itemType, itemSubType = select(6, GetItemInfo(itemID))
  end

  local function norm(v)
    if type(v) ~= "string" then return "" end
    return string.lower(v)
  end

  local itemTypeText = norm(itemType)
  local itemSubTypeText = norm(itemSubType)
  if itemTypeText == "housing" then
    return true
  end
  if itemSubTypeText == "decor" then
    return true
  end
  if string.find(itemTypeText, "housing", 1, true) then
    return true
  end
  if string.find(itemSubTypeText, "decor", 1, true) then
    return true
  end
  return false
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

local function UsesModernReagentQuality(itemID)
  if type(itemID) ~= "number" then
    return false
  end
  local expacID = GetItemExpansionID(itemID)
  return type(expacID) == "number" and expacID >= 9
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

local function GetRequiredReagentTierItemIDs(slot)
  if not slot or type(slot.reagents) ~= "table" then
    return nil
  end

  local tiers = {}
  local fallback = {}
  for index, reagent in ipairs(slot.reagents) do
    if index > 4 then
      break
    end
    if reagent and reagent.itemID then
      local quality = NormalizeTrackedQuality(GetTrackedReagentQualityFromItemInfo(reagent.itemID))
      if quality then
        tiers[quality] = reagent.itemID
      else
        fallback[#fallback + 1] = reagent.itemID
      end
    end
  end

  if not next(tiers) then
    for index, itemID in ipairs(fallback) do
      if index > 3 then
        break
      end
      tiers[index] = itemID
    end
  end

  if next(tiers) then
    return tiers
  end
  return nil
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

local function EnsureItemNameCache(addon)
  if not (addon and addon.db and addon.db.profile) then return nil end
  addon.db.profile.itemNameCache = addon.db.profile.itemNameCache or {}
  return addon.db.profile.itemNameCache
end

local function GetItemNameWithCache(addon, itemID)
  if not itemID then return nil end

  local cache = EnsureItemNameCache(addon)
  if cache and cache[itemID] and cache[itemID] ~= "" then
    return cache[itemID]
  end

  local live = GetItemNameFast(itemID)
  if live and live ~= "" then
    if cache then
      cache[itemID] = live
    end
    return live
  end

  return nil
end

local function ResolveItemGroupName(addon, itemIDOrName)
  if type(itemIDOrName) == "string" and itemIDOrName ~= "" then
    return itemIDOrName
  end
  if type(itemIDOrName) == "number" then
    return GetItemNameWithCache(addon, itemIDOrName)
  end
  return nil
end

local function SumBucketByName(addon, bucket, targetName)
  if type(bucket) ~= "table" or not targetName or targetName == "" then
    return 0
  end

  local total = 0
  for candidateItemID, count in pairs(bucket) do
    if type(candidateItemID) == "number" and type(count) == "number" and count > 0 then
      local candidateName = GetItemNameWithCache(addon, candidateItemID)
      if candidateName == targetName then
        total = total + count
      end
    end
  end
  return total
end

local function SumBucketByNameAndQuality(addon, bucket, targetName, targetQuality, breakdown)
  if type(bucket) ~= "table" or not targetName or targetName == "" then
    return 0
  end

  targetQuality = NormalizeTrackedQuality(targetQuality)
  local total = 0
  for candidateItemID, count in pairs(bucket) do
    if type(candidateItemID) == "number" and type(count) == "number" and count > 0 then
      local candidateName = GetItemNameWithCache(addon, candidateItemID)
      if candidateName == targetName then
        local candidateQuality = NormalizeTrackedQuality(GetTrackedQualityFromOwnedItemID(candidateItemID))
        if breakdown and candidateQuality then
          breakdown[candidateQuality] = (breakdown[candidateQuality] or 0) + count
        end
        if not targetQuality or candidateQuality == targetQuality then
          total = total + count
        end
      end
    end
  end
  return total
end

local function SumQualityBucketByName(addon, bucket, targetName, targetQuality, breakdown)
  if type(bucket) ~= "table" or not targetName or targetName == "" then
    return 0
  end

  targetQuality = NormalizeTrackedQuality(targetQuality)
  local total = 0
  for candidateItemID, byQuality in pairs(bucket) do
    if type(candidateItemID) == "number" and type(byQuality) == "table" then
      local candidateName = GetItemNameWithCache(addon, candidateItemID)
      if candidateName == targetName then
        for quality = 1, 3 do
          local count = tonumber(byQuality[quality]) or 0
          if count > 0 then
            if breakdown then
              breakdown[quality] = (breakdown[quality] or 0) + count
            end
            if not targetQuality or quality == targetQuality then
              total = total + count
            end
          end
        end
      end
    end
  end
  return total
end

local function SumBucketExact(bucket, itemID)
  if type(bucket) ~= "table" or not itemID then
    return 0
  end
  return bucket[itemID] or 0
end

local function SelectTooltipItemID(addon, itemID, targetQuality)
  if not (addon and addon.db and itemID) then
    return itemID
  end
  if not UsesModernReagentQuality(itemID) then
    return itemID
  end

  targetQuality = NormalizeTrackedQuality(targetQuality)
  local targetName = ResolveItemGroupName(addon, itemID)
  if not targetName or targetName == "" then
    return itemID
  end

  local realms = addon.db.global and addon.db.global.realms
  local realm = select(1, playerKey())
  local realmData = realms and realms[realm]
  if type(realmData) ~= "table" then
    return itemID
  end

  local bestID = nil
  local bestQuality = nil

  local function considerBucket(bucket)
    if type(bucket) ~= "table" then return end
    for candidateItemID, count in pairs(bucket) do
      if type(candidateItemID) == "number" and type(count) == "number" and count > 0 then
        local candidateName = ResolveItemGroupName(addon, candidateItemID)
        if candidateName == targetName then
          local candidateQuality = GetTrackedQualityFromOwnedItemID(candidateItemID)
          if targetQuality then
            if candidateQuality == targetQuality then
              if not bestID or candidateItemID < bestID then
                bestID = candidateItemID
                bestQuality = candidateQuality
              end
            end
          else
            local compareQuality = candidateQuality or 0
            local bestCompare = bestQuality or 0
            if not bestID or compareQuality < bestCompare or (compareQuality == bestCompare and candidateItemID < bestID) then
              bestID = candidateItemID
              bestQuality = candidateQuality
            end
          end
        end
      end
    end
  end

  for _, entry in pairs((realmData and realmData.chars) or {}) do
    if type(entry) == "table" then
      considerBucket(entry.bags)
      considerBucket(entry.bank)
    end
  end
  considerBucket(realmData.warbank)

  return bestID or itemID
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

ns.Data = ns.Data or {}
ns.Data.EnsureProfessionsLoaded = EnsureProfessionsLoaded
ns.Data.ceilDiv = ceilDiv
ns.Data.playerKey = playerKey
ns.Data.GetItemNameFast = GetItemNameFast
ns.Data.GetItemQuality = GetItemQuality
ns.Data.NormalizeTrackedQuality = NormalizeTrackedQuality
ns.Data.GetTrackedQualityLabel = GetTrackedQualityLabel
ns.Data.QUALITY_ATLAS_CANDIDATES = QUALITY_ATLAS_CANDIDATES
ns.Data.GetTrackedQualityFromItemLink = GetTrackedQualityFromItemLink
ns.Data.GetTrackedQualityFromContainerItem = GetTrackedQualityFromContainerItem
ns.Data.GetTrackedQualityFromOwnedItemID = GetTrackedQualityFromOwnedItemID
ns.Data.ItemSupportsTrackedQuality = ItemSupportsTrackedQuality
ns.Data.ColorizeByQuality = ColorizeByQuality
ns.Data.IsDecorItem = IsDecorItem
ns.Data.GetItemExpansionID = GetItemExpansionID
ns.Data.GetExpansionName = GetExpansionName
ns.Data.UsesModernReagentQuality = UsesModernReagentQuality
ns.Data.PickRequiredReagent = PickRequiredReagent
ns.Data.GetRequiredReagentTierItemIDs = GetRequiredReagentTierItemIDs
ns.Data.GetRecipeSchematicSafe = GetRecipeSchematicSafe
ns.Data.EnsureRecipeCache = EnsureRecipeCache
ns.Data.EnsureItemNameCache = EnsureItemNameCache
ns.Data.GetItemNameWithCache = GetItemNameWithCache
ns.Data.ResolveItemGroupName = ResolveItemGroupName
ns.Data.SelectTooltipItemID = SelectTooltipItemID
ns.Data.SumBucketByNameAndQuality = SumBucketByNameAndQuality
ns.Data.SumQualityBucketByName = SumQualityBucketByName
ns.Data.NormalizeProfessionName = NormalizeProfessionName

-- -------------------------
-- Profession ownership checks (player)
-- -------------------------

ns.GetPlayerProfessionSet = ns.Snapshots.GetPlayerProfessionSet
ns.PlayerHasProfession = ns.Snapshots.PlayerHasProfession
ns.AnyCharHasProfession = ns.Snapshots.AnyCharHasProfession
ns.SnapshotCurrentCharacter = ns.Snapshots.SnapshotCurrentCharacter

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
  local includeAlts = addon.db.profile and addon.db.profile.includeAlts
  local realmWarbank = (realmData and realmData.warbank) or {}
  local realmWarbankByQuality = (realmData and realmData.warbankByQuality) or {}

  local function sumQualityBucket(bucket)
    local total = 0
    local byItem = type(bucket) == "table" and bucket[itemID]
    if type(byItem) == "table" then
      for quality = 1, 3 do
        total = total + (byItem[quality] or 0)
      end
    end
    return total
  end

  local function countEntryFlat(entry)
    if type(entry) ~= "table" then return 0 end
    local bags = entry.bags or {}
    local bank = entry.bank or {}
    return (bags[itemID] or 0) + (bank[itemID] or 0)
  end

  local function countEntryByQuality(entry)
    if type(entry) ~= "table" then return 0 end
    return sumQualityBucket(entry.bagsByQuality) + sumQualityBucket(entry.bankByQuality)
  end

  local function pickAggregateCount(flatTotal, qualityTotal)
    -- For aggregate "any quality" counts, use the larger of the flat and per-quality
    -- totals so partial quality detection does not undercount mixed-quality stock.
    if qualityTotal and qualityTotal > 0 then
      return math.max(flatTotal or 0, qualityTotal)
    end
    return flatTotal or 0
  end

  if not includeAlts then
    local flatTotal = countEntryFlat(chars[key]) + (realmWarbank[itemID] or 0)
    local qualityTotal = countEntryByQuality(chars[key]) + sumQualityBucket(realmWarbankByQuality)
    return pickAggregateCount(flatTotal, qualityTotal)
  end

  local flatTotal = 0
  local qualityTotal = 0
  for _, entry in pairs(chars) do
    flatTotal = flatTotal + countEntryFlat(entry)
    qualityTotal = qualityTotal + countEntryByQuality(entry)
  end

  flatTotal = flatTotal + (realmWarbank[itemID] or 0)
  qualityTotal = qualityTotal + sumQualityBucket(realmWarbankByQuality)
  return pickAggregateCount(flatTotal, qualityTotal)
end

function ns.GetHaveCountExact(addon, itemID)
  if not (addon and addon.db and itemID) then return 0 end

  local realm, key = playerKey()
  local realms = addon.db.global and addon.db.global.realms
  local realmData = realms and realms[realm]
  local chars = realmData and realmData.chars
  if not chars then return 0 end
  local includeAlts = addon.db.profile and addon.db.profile.includeAlts
  local realmWarbank = (realmData and realmData.warbank) or {}

  local function countEntry(entry)
    if type(entry) ~= "table" then return 0 end
    return SumBucketExact(entry.bags, itemID) + SumBucketExact(entry.bank, itemID)
  end

  if not includeAlts then
    return countEntry(chars[key]) + SumBucketExact(realmWarbank, itemID)
  end

  local total = 0
  for _, entry in pairs(chars) do
    total = total + countEntry(entry)
  end
  return total + SumBucketExact(realmWarbank, itemID)
end

function ns.GetHaveCountForItemIDs(addon, itemIDs)
  if not (addon and addon.db and type(itemIDs) == "table") then return 0 end

  local realm, key = playerKey()
  local realms = addon.db.global and addon.db.global.realms
  local realmData = realms and realms[realm]
  local chars = realmData and realmData.chars
  if not chars then return 0 end
  local includeAlts = addon.db.profile and addon.db.profile.includeAlts
  local realmWarbank = (realmData and realmData.warbank) or {}

  local function sumFromBucket(bucket)
    local total = 0
    if type(bucket) ~= "table" then
      return 0
    end
    for _, candidateItemID in ipairs(itemIDs) do
      if type(candidateItemID) == "number" then
        total = total + (bucket[candidateItemID] or 0)
      end
    end
    return total
  end

  local function countEntry(entry)
    if type(entry) ~= "table" then return 0 end
    return sumFromBucket(entry.bags) + sumFromBucket(entry.bank)
  end

  if not includeAlts then
    return countEntry(chars[key]) + sumFromBucket(realmWarbank)
  end

  local total = 0
  for _, entry in pairs(chars) do
    total = total + countEntry(entry)
  end
  return total + sumFromBucket(realmWarbank)
end

function ns.GetHaveCountByName(addon, itemIDOrName)
  if not (addon and addon.db and itemIDOrName) then return 0 end
  if type(itemIDOrName) == "number" and not UsesModernReagentQuality(itemIDOrName) then
    return ns.GetHaveCount(addon, itemIDOrName)
  end

  local targetName = ResolveItemGroupName(addon, itemIDOrName)
  if not targetName or targetName == "" then return 0 end

  local realm, key = playerKey()
  local realms = addon.db.global and addon.db.global.realms
  local realmData = realms and realms[realm]
  local chars = realmData and realmData.chars
  if not chars then return 0 end
  local includeAlts = addon.db.profile and addon.db.profile.includeAlts
  local realmWarbank = (realmData and realmData.warbank) or {}

  local function countEntry(entry)
    if type(entry) ~= "table" then return 0 end
    return SumBucketByName(addon, entry.bags, targetName) + SumBucketByName(addon, entry.bank, targetName)
  end

  if not includeAlts then
    return countEntry(chars[key]) + SumBucketByName(addon, realmWarbank, targetName)
  end

  local total = 0
  for _, entry in pairs(chars) do
    total = total + countEntry(entry)
  end
  return total + SumBucketByName(addon, realmWarbank, targetName)
end

function ns.GetHaveCountByQuality(addon, itemID, quality)
  if not (addon and addon.db and itemID) then return 0 end
  quality = NormalizeTrackedQuality(quality)
  if not quality then return 0 end
  if not UsesModernReagentQuality(itemID) then
    return ns.GetHaveCountExact(addon, itemID)
  end

  local targetName = ResolveItemGroupName(addon, itemID)
  if not targetName or targetName == "" then return 0 end

  local realm, key = ns.Data.playerKey()
  local realms = addon.db.global and addon.db.global.realms
  local realmData = realms and realms[realm]
  local chars = realmData and realmData.chars
  if not chars then return 0 end
  local includeAlts = addon.db.profile and addon.db.profile.includeAlts
  local realmWarbankByQuality = (realmData and realmData.warbankByQuality) or {}

  local function countEntry(entry)
    if type(entry) ~= "table" then
      return 0
    end
    return SumQualityBucketByName(addon, entry.bagsByQuality, targetName, quality)
      + SumQualityBucketByName(addon, entry.bankByQuality, targetName, quality)
  end

  if not includeAlts then
    return countEntry(chars[key]) + SumQualityBucketByName(addon, realmWarbankByQuality, targetName, quality)
  end

  local total = 0
  for _, entry in pairs(chars) do
    total = total + countEntry(entry)
  end

  return total + SumQualityBucketByName(addon, realmWarbankByQuality, targetName, quality)
end

function ns.GetHaveQualityBreakdown(addon, itemID)
  local breakdown = { [1] = 0, [2] = 0, [3] = 0 }
  if not (addon and addon.db and itemID) then return breakdown end
  if not UsesModernReagentQuality(itemID) then
    local quality = NormalizeTrackedQuality(GetTrackedQualityFromOwnedItemID(itemID)) or 1
    breakdown[quality] = ns.GetHaveCountExact(addon, itemID)
    return breakdown
  end

  local targetName = ResolveItemGroupName(addon, itemID)
  if not targetName or targetName == "" then return breakdown end

  local realm, key = ns.Data.playerKey()
  local realms = addon.db.global and addon.db.global.realms
  local realmData = realms and realms[realm]
  local chars = realmData and realmData.chars
  if not chars then return breakdown end
  local includeAlts = addon.db.profile and addon.db.profile.includeAlts
  local realmWarbankByQuality = (realmData and realmData.warbankByQuality) or {}

  local function addEntry(entry)
    if type(entry) ~= "table" then
      return
    end
    SumQualityBucketByName(addon, entry.bagsByQuality, targetName, nil, breakdown)
    SumQualityBucketByName(addon, entry.bankByQuality, targetName, nil, breakdown)
  end

  if not includeAlts then
    addEntry(chars[key])
    SumQualityBucketByName(addon, realmWarbankByQuality, targetName, nil, breakdown)
    return breakdown
  end

  for _, entry in pairs(chars) do
    addEntry(entry)
  end

  SumQualityBucketByName(addon, realmWarbankByQuality, targetName, nil, breakdown)

  return breakdown
end

-- Learned recipe snapshot helpers used by Core.lua and Professions.lua
ns.SnapshotLearnedRecipes = ns.Snapshots.SnapshotLearnedRecipes
ns.IsRecipeLearned = ns.Snapshots.IsRecipeLearned
ns.ScanCurrentProfessionLearned = ns.Snapshots.ScanCurrentProfessionLearned

-- -------------------------
-- Public API
-- -------------------------

ns.GetRecipeOutputItemID = ns.Recipes.GetRecipeOutputItemID
ns.SetGoalForRecipe = ns.Recipes.SetGoalForRecipe
ns.ApplyCompletionByInventoryDelta = ns.Recipes.ApplyCompletionByInventoryDelta
ns.RecomputeReagentsOnly = ns.Reagents.RecomputeReagentsOnly
ns.RecomputeDisplayOnly = ns.Recipes.RecomputeDisplayOnly
ns.RecomputeCaches = ns.Recipes.RecomputeCaches
ns.AccumulateReagentsForRecipe = ns.Recipes.AccumulateReagentsForRecipe
