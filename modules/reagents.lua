local ADDON, ns = ...
ns = ns or {}

ns.Reagents = ns.Reagents or {}
local wipeTable = wipe

local PT = LibStub and LibStub("LibPeriodicTable-3.1", true)

local function PT_InSet(itemID, setName)
  if not (PT and itemID and setName) then return false end
  return PT.ItemInSet and PT:ItemInSet(itemID, setName) or false
end

function ns.Reagents.GetSource(addon, itemID)
  if not itemID then return "Other", nil end

  if addon and addon.db and addon.db.profile and addon.db.profile.recipeByItem
    and addon.db.profile.recipeByItem[itemID]
  then
    return "Crafting", nil
  end

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

  do
    local name = ns.Data.GetItemNameFast(itemID)
    if name and name:match(" Lumber$") then
      return "Gathering", "Lumbering"
    end
    if name and name:match(" Ore$") then
      return "Gathering", "Mining"
    end
  end

  do
    local _, _, subClassName, _, _, _, _, _, _, _, _, classID, subClassID = GetItemInfoInstant(itemID)
    local tradeClass = (Enum and Enum.ItemClass and Enum.ItemClass.Tradegoods) or LE_ITEM_CLASS_TRADEGOODS or 7
    local tg = (Enum and (Enum.ItemTradegoodsSubclass or (Enum.ItemSubClass and Enum.ItemSubClass.Tradegoods))) or {}

    local tgHerb = tg.Herb or 11
    local tgLeather = tg.Leather or 7
    local tgParts = tg.Parts or 1
    local tgCloth = tg.Cloth
    local tgInscription = tg.Inscription
    local tgJewelcrafting = tg.Jewelcrafting
    local tgEnchanting = tg.Enchanting
    local tgMetal = tg.MetalAndStone or tg.MetalStone or 9

    if classID == tradeClass and subClassID then
      if subClassID == tgHerb then
        return "Gathering", "Herbalism"
      end
      if subClassID == tgLeather then
        return "Gathering", "Skinning"
      end
      if subClassID == tgParts then
        return "Crafting", "Engineering"
      end
      if tgEnchanting and subClassID == tgEnchanting then
        return "Crafting", "Enchanting"
      end
      if tgCloth and subClassID == tgCloth then
        return "Crafting", "Tailoring"
      end
      if tgInscription and subClassID == tgInscription then
        return "Crafting", "Inscription"
      end
      if tgJewelcrafting and subClassID == tgJewelcrafting then
        return "Crafting", "Jewelcrafting"
      end
      if subClassID == tgMetal then
        return "Crafting", "Blacksmithing"
      end
    end

    if type(subClassName) == "string" then
      local s = string.lower(subClassName)
      if string.find(s, "herb", 1, true) then
        return "Gathering", "Herbalism"
      end
      if string.find(s, "leather", 1, true) or string.find(s, "hide", 1, true) then
        return "Gathering", "Skinning"
      end
      if string.find(s, "part", 1, true) then
        return "Crafting", "Engineering"
      end
      if string.find(s, "enchant", 1, true) then
        return "Crafting", "Enchanting"
      end
      if string.find(s, "cloth", 1, true) then
        return "Crafting", "Tailoring"
      end
      if string.find(s, "inscription", 1, true) or string.find(s, "ink", 1, true) then
        return "Crafting", "Inscription"
      end
      if string.find(s, "jewel", 1, true) or string.find(s, "gem", 1, true) then
        return "Crafting", "Jewelcrafting"
      end
      if string.find(s, "metal", 1, true) or string.find(s, "stone", 1, true) then
        return "Crafting", "Blacksmithing"
      end
    end
  end

  if PT_InSet(itemID, "Tradeskill.Mat.BySource.Vendor") then
    return "Vendor", nil
  end

  return "Other", nil
end

function ns.Reagents.BuildDisplayOnly(addon)
  local collapsed = (addon.db.profile.window and addon.db.profile.window.collapsed) or {}
  local flat = {}

  for _, reagent in pairs(addon.cache.reagents or {}) do
    local itemID = type(reagent) == "table" and reagent.itemID or nil
    local baseItemID = type(reagent) == "table" and (reagent.baseItemID or reagent.itemID) or nil
    local tierItemIDs = type(reagent) == "table" and reagent.tierItemIDs or nil
    local need = type(reagent) == "table" and reagent.need or 0
    if itemID then
      local tooltipItemID = (type(tierItemIDs) == "table" and tierItemIDs[1])
        or ((tierItemIDs and tierItemIDs[1]) or nil)
        or ((ns.Data.SelectTooltipItemID and ns.Data.SelectTooltipItemID(addon, baseItemID, nil)) or itemID)
      local have
      if type(tierItemIDs) == "table" and next(tierItemIDs) then
        local ids = {}
        for _, tierItemID in ipairs(tierItemIDs) do
          if type(tierItemID) == "number" then
            ids[#ids + 1] = tierItemID
          end
        end
        have = ns.GetHaveCountForItemIDs(addon, ids)
      else
        have = ns.GetHaveCountByName(addon, baseItemID)
      end
      local remaining = math.max(0, (need or 0) - (have or 0))
      local rawName = ns.Data.GetItemNameWithCache(addon, tooltipItemID) or ns.Data.GetItemNameWithCache(addon, baseItemID) or ("Item " .. itemID)
      local isComplete = (remaining <= 0)
      local displayName = isComplete and rawName or ns.Data.ColorizeByQuality(tooltipItemID or itemID, rawName)
      local rarity = ns.Data.GetItemQuality(tooltipItemID) or ns.Data.GetItemQuality(itemID) or -1
      local expacID = ns.Data.GetItemExpansionID(baseItemID or itemID)
      local expacName = ns.Data.GetExpansionName(expacID)
      local source, subSource = ns.Reagents.GetSource(addon, baseItemID or itemID)

      table.insert(flat, {
        reagentKey = reagent.key or tostring(itemID),
        itemID = itemID,
        baseItemID = baseItemID,
        tierItemIDs = tierItemIDs,
        tooltipItemID = tooltipItemID,
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
  end

  local mode = (addon.db.profile.window and addon.db.profile.window.reagentSort) or "E"
  local sorted, display = ns.Reagents.SortAndBuildDisplay(flat, mode, collapsed, ns.Data.GetExpansionName)
  addon.cache.reagentsList = sorted
  addon.cache.reagentsDisplay = display
end

function ns.Reagents.SortAndBuildDisplay(flat, mode, collapsed, getExpansionName)
  if ns.Sorting and ns.Sorting.SortReagentFlat then
    return ns.Sorting.SortReagentFlat(flat, mode, collapsed, getExpansionName)
  end
  return flat or {}, flat or {}
end

function ns.Reagents.RecomputeReagentsOnly(addon)
  if not (addon and addon.cache and addon.cache.reagents) then return end
  addon.cache.reagentsList = addon.cache.reagentsList or {}
  addon.cache.reagentsDisplay = addon.cache.reagentsDisplay or {}
  wipeTable(addon.cache.reagentsList)
  wipeTable(addon.cache.reagentsDisplay)
  ns.Reagents.BuildDisplayOnly(addon)
end

ns.RecomputeReagentsOnly = ns.Reagents.RecomputeReagentsOnly
