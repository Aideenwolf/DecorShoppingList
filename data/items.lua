local ADDON, ns = ...
ns = ns or {}
ns.Data = ns.Data or {}

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

local function GetItemRarity(itemID)
  if not itemID then return nil end
  if C_Item and C_Item.GetItemQualityByID then
    return C_Item.GetItemQualityByID(itemID)
  end
  return select(3, GetItemInfo(itemID))
end

local function EnsureItemRarityCache(addon)
  if not (addon and addon.db and addon.db.profile) then return nil end
  addon.db.profile.itemRarityCache = addon.db.profile.itemRarityCache or {}
  return addon.db.profile.itemRarityCache
end

local function GetItemRarityWithCache(addon, itemID)
  if not itemID then return nil end

  local cache = EnsureItemRarityCache(addon)
  local cached = cache and cache[itemID]
  if type(cached) == "number" then
    return cached
  end

  local live = GetItemRarity(itemID)
  if type(live) == "number" then
    if cache then
      cache[itemID] = live
    end
    return live
  end

  return nil
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

local function ColorizeByRarity(itemID, text)
  if not itemID or not text then return text end
  local q = GetItemRarity(itemID)
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

local function ColorizeByRarityWithCache(addon, itemID, text)
  if not itemID or not text then return text end
  local q = GetItemRarityWithCache(addon, itemID)
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

ns.Data.GetItemNameFast = GetItemNameFast
ns.Data.GetItemRarity = GetItemRarity
ns.Data.EnsureItemRarityCache = EnsureItemRarityCache
ns.Data.GetItemRarityWithCache = GetItemRarityWithCache
ns.Data.EnsureItemNameCache = EnsureItemNameCache
ns.Data.GetItemNameWithCache = GetItemNameWithCache
ns.Data.ColorizeByRarity = ColorizeByRarity
ns.Data.ColorizeByRarityWithCache = ColorizeByRarityWithCache
ns.Data.IsDecorItem = IsDecorItem
ns.Data.GetItemExpansionID = GetItemExpansionID
ns.Data.GetExpansionName = GetExpansionName
ns.Data.UsesModernReagentQuality = UsesModernReagentQuality
