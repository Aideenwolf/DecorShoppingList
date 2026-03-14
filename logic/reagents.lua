local ADDON, ns = ...
ns = ns or {}

ns.Reagents = ns.Reagents or {}
local wipeTable = wipe

local Catalog = LibStub and LibStub("LibDSLCatalog-1.0", true)
local PT = LibStub and LibStub("LibPeriodicTable-3.1", true)

local SOURCE_OVERRIDES = {
  [210930] = { source = "Gathering", subSource = "Mining" }, -- Bismuth
  [210931] = { source = "Gathering", subSource = "Mining" },
  [210932] = { source = "Gathering", subSource = "Mining" },
  [210933] = { source = "Gathering", subSource = "Mining" }, -- Aqirite
}

local PT_SOURCE_RULES = {
  { set = "Tradeskill.Gather.Herbalism", source = "Gathering", subSource = "Herbalism" },
  { set = "Tradeskill.Gather.Mining", source = "Gathering", subSource = "Mining" },
  { prefix = "Tradeskill.Gather.GemsInNodes.", source = "Gathering", subSource = "Mining" },
  { set = "Tradeskill.Gather.Skinning", source = "Gathering", subSource = "Skinning" },
  { set = "Tradeskill.Gather.Fishing", source = "Gathering", subSource = "Fishing" },
  { set = "Tradeskill.Gather.Prospecting", source = "Crafting", subSource = "Jewelcrafting" },
  { set = "Tradeskill.Gather.Milling", source = "Crafting", subSource = "Inscription" },
  { set = "Tradeskill.Gather.Disenchant", source = "Crafting", subSource = "Enchanting" },
}

local function GetReagentMetaKey(reagent)
  if type(reagent) ~= "table" then
    return nil
  end
  return reagent.key
    or (type(reagent.baseItemID) == "number" and tostring(reagent.baseItemID))
    or (type(reagent.itemID) == "number" and tostring(reagent.itemID))
    or nil
end

local function PT_InSet(itemID, setName)
  if not (PT and itemID and setName) then return false end
  return PT.ItemInSet and PT:ItemInSet(itemID, setName) or false
end

local function PT_ItemInSetPrefix(itemID, prefix)
  if not (PT and itemID and prefix and PT.ItemSearch) then
    return false
  end

  local sets = PT:ItemSearch(itemID)
  if type(sets) ~= "table" then
    return false
  end

  for setName in pairs(sets) do
    if type(setName) == "string" and string.sub(setName, 1, #prefix) == prefix then
      return true
    end
  end

  return false
end

local function GetPTRuleMatch(itemID, source)
  if not (PT and itemID) then
    return nil
  end

  for _, rule in ipairs(PT_SOURCE_RULES) do
    if (not source or rule.source == source) then
      local matched = false
      if rule.set then
        matched = PT_InSet(itemID, rule.set)
      elseif rule.prefix then
        matched = PT_ItemInSetPrefix(itemID, rule.prefix)
      end
      if matched then
        return rule
      end
    end
  end

  return nil
end

function ns.Reagents.GetSource(addon, itemID)
  if not itemID then return "Other", nil end

  local catalogOverride = Catalog and Catalog.GetSourceOverride and Catalog:GetSourceOverride(itemID)
  if type(catalogOverride) == "table" and catalogOverride.source then
    return catalogOverride.source, catalogOverride.subSource
  end

  local override = SOURCE_OVERRIDES[itemID]
  if override then
    return override.source, override.subSource
  end

  local itemName = ns.Data.GetItemNameWithCache and ns.Data.GetItemNameWithCache(addon, itemID)

  local function isTransmuteRecipe(entry)
    if type(entry) ~= "table" then
      return false
    end

    local recipeName = type(entry.recipeName) == "string" and string.lower(entry.recipeName) or nil
    if recipeName and string.find(recipeName, "transmute", 1, true) then
      return true
    end

    return false
  end

  local function getCraftingSource()
    local recipeID = Catalog and Catalog.GetRecipeForOutput and Catalog:GetRecipeForOutput(itemID)
    local cache = ns.Data.EnsureRecipeCache and ns.Data.EnsureRecipeCache(addon)

    if not recipeID and addon and addon.db and addon.db.profile then
      recipeID = addon.db.profile.recipeByItem and addon.db.profile.recipeByItem[itemID]
    end

    if type(recipeID) == "number" and type(cache) == "table" then
      local entry = cache[recipeID]
      if type(entry) == "table" then
        if isTransmuteRecipe(entry) then
          return nil, nil
        end
        return "Crafting", entry.profession
      end
    end

    if type(recipeID) == "number" and Catalog and Catalog.GetRecipe then
      local entry = Catalog:GetRecipe(recipeID)
      if type(entry) == "table" then
        if isTransmuteRecipe(entry) then
          return nil, nil
        end
        return "Crafting", entry.profession
      end
    end

    if type(cache) == "table" then
      for _, entry in pairs(cache) do
        if type(entry) == "table" and entry.outputItemID == itemID then
          if isTransmuteRecipe(entry) then
            return nil, nil
          end
          return "Crafting", entry.profession
        end
      end
    end

    if Catalog and Catalog.GetRecipeForOutput and Catalog.GetRecipe then
      local catalogRecipeID = Catalog:GetRecipeForOutput(itemID)
      if type(catalogRecipeID) == "number" then
        local entry = Catalog:GetRecipe(catalogRecipeID)
        if type(entry) == "table" then
          if isTransmuteRecipe(entry) then
            return nil, nil
          end
          return "Crafting", entry.profession
        end
        return "Crafting", nil
      end
    end

    if type(recipeID) == "number" then
      return "Crafting", nil
    end

    return nil, nil
  end

  local function getGatheringSubSource()
    local ptRule = GetPTRuleMatch(itemID, "Gathering")
    if ptRule then
      return ptRule.subSource
    end

    if itemName and itemName:match(" Lumber$") then
      return "Lumbering"
    end
    if itemName and itemName:match(" Ore$") then
      return "Mining"
    end

    local _, _, subClassName, _, _, _, _, _, _, _, _, classID, subClassID = GetItemInfoInstant(itemID)
    local tradeClass = (Enum and Enum.ItemClass and Enum.ItemClass.Tradegoods) or LE_ITEM_CLASS_TRADEGOODS or 7
    local tg = (Enum and (Enum.ItemTradegoodsSubclass or (Enum.ItemSubClass and Enum.ItemSubClass.Tradegoods))) or {}
    local tgHerb = tg.Herb or 11
    local tgLeather = tg.Leather or 7

    if classID == tradeClass and subClassID then
      if subClassID == tgHerb then
        return "Herbalism"
      end
      if subClassID == tgLeather then
        return "Skinning"
      end
    end

    if type(subClassName) == "string" then
      local s = string.lower(subClassName)
      if string.find(s, "herb", 1, true) then
        return "Herbalism"
      end
      if string.find(s, "leather", 1, true) or string.find(s, "hide", 1, true) then
        return "Skinning"
      end
    end

    return nil
  end

  local function getCraftingSubSource()
    local source, subSource = getCraftingSource()
    if source == "Crafting" and subSource then
      return subSource
    end

    local ptRule = GetPTRuleMatch(itemID, "Crafting")
    if ptRule then
      return ptRule.subSource
    end

    local _, _, subClassName, _, _, _, _, _, _, _, _, classID, subClassID = GetItemInfoInstant(itemID)
    local tradeClass = (Enum and Enum.ItemClass and Enum.ItemClass.Tradegoods) or LE_ITEM_CLASS_TRADEGOODS or 7
    local tg = (Enum and (Enum.ItemTradegoodsSubclass or (Enum.ItemSubClass and Enum.ItemSubClass.Tradegoods))) or {}

    local tgParts = tg.Parts or 1
    local tgCloth = tg.Cloth
    local tgInscription = tg.Inscription
    local tgJewelcrafting = tg.Jewelcrafting
    local tgEnchanting = tg.Enchanting
    local tgMetal = tg.MetalAndStone or tg.MetalStone or 9

    if classID == tradeClass and subClassID then
      if subClassID == tgParts then
        return "Engineering"
      end
      if tgEnchanting and subClassID == tgEnchanting then
        return "Enchanting"
      end
      if tgCloth and subClassID == tgCloth then
        return "Tailoring"
      end
      if tgInscription and subClassID == tgInscription then
        return "Inscription"
      end
      if tgJewelcrafting and subClassID == tgJewelcrafting then
        return "Jewelcrafting"
      end
      if subClassID == tgMetal then
        return "Blacksmithing"
      end
    end

    if type(subClassName) == "string" then
      local s = string.lower(subClassName)
      if string.find(s, "part", 1, true) then
        return "Engineering"
      end
      if string.find(s, "enchant", 1, true) then
        return "Enchanting"
      end
      if string.find(s, "cloth", 1, true) then
        return "Tailoring"
      end
      if string.find(s, "inscription", 1, true) or string.find(s, "ink", 1, true) then
        return "Inscription"
      end
      if string.find(s, "jewel", 1, true) or string.find(s, "gem", 1, true) then
        return "Jewelcrafting"
      end
      if string.find(s, "metal", 1, true) or string.find(s, "stone", 1, true) then
        return "Blacksmithing"
      end
    end

    return nil
  end

  local function getTopLevelSource()
    do
      local source = getCraftingSource()
      if source then
        return source
      end
    end

    local explicitGatheringSubSource = getGatheringSubSource()
    if explicitGatheringSubSource then
      return "Gathering"
    end

    local explicitCraftingSubSource = getCraftingSubSource()
    if explicitCraftingSubSource then
      return "Crafting"
    end

    if PT then
      if PT_InSet(itemID, "Tradeskill.Mat.BySource.Gather") then
        return "Gathering"
      end
      if PT_InSet(itemID, "Tradeskill.Mat.BySource.Vendor") then
        return "Vendor"
      end
    end

    return "Other"
  end

  local topLevel = getTopLevelSource()
  if topLevel == "Gathering" then
    return "Gathering", getGatheringSubSource()
  end
  if topLevel == "Crafting" then
    return "Crafting", getCraftingSubSource()
  end
  if topLevel == "Vendor" then
    return "Vendor", nil
  end

  return "Other", nil
end

function ns.Reagents.BuildDisplayOnly(addon)
  local collapsed = (addon.db.profile.window and addon.db.profile.window.collapsed) or {}
  local flat = {}
  addon.cache = addon.cache or {}
  addon.cache._reagentMeta = addon.cache._reagentMeta or {}
  local metaCache = addon.cache._reagentMeta

  for _, reagent in pairs(addon.cache.reagents or {}) do
    local itemID = type(reagent) == "table" and reagent.itemID or nil
    local baseItemID = type(reagent) == "table" and (reagent.baseItemID or reagent.itemID) or nil
    local tierItemIDs = type(reagent) == "table" and reagent.tierItemIDs or nil
    local need = type(reagent) == "table" and reagent.need or 0
    if itemID then
      local metaKey = GetReagentMetaKey(reagent)
      local meta = metaKey and metaCache[metaKey] or nil
      if type(meta) ~= "table" then
        local tooltipItemID = (ns.Data.GetReagentTooltipItemID and ns.Data.GetReagentTooltipItemID(addon, baseItemID, tierItemIDs)) or itemID
        local rawName = ns.Data.GetItemNameWithCache(addon, tooltipItemID) or ns.Data.GetItemNameWithCache(addon, baseItemID) or ("Item " .. itemID)
        local rarity = ns.Data.GetItemRarityWithCache(addon, tooltipItemID) or ns.Data.GetItemRarityWithCache(addon, itemID) or -1
        local icon = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(tooltipItemID or itemID)) or GetItemIcon(tooltipItemID or itemID)
        local expacID = ns.Data.GetItemExpansionID(baseItemID or itemID)
        local expacName = ns.Data.GetExpansionName(expacID)
        local source, subSource = ns.Reagents.GetSource(addon, baseItemID or itemID)
        meta = {
          tooltipItemID = tooltipItemID,
          rawName = rawName,
          rarity = rarity,
          icon = icon,
          expacID = expacID,
          expacName = expacName,
          source = source,
          subSource = subSource,
        }
        if metaKey then
          metaCache[metaKey] = meta
        end
      end

      local have = (ns.Data.GetReagentHaveCount and ns.Data.GetReagentHaveCount(addon, baseItemID, tierItemIDs)) or 0
      local remaining = math.max(0, (need or 0) - (have or 0))
      local isComplete = (remaining <= 0)
      local rawName = meta.rawName
      local displayName = rawName

      table.insert(flat, {
        reagentKey = reagent.key or tostring(itemID),
        itemID = itemID,
        baseItemID = baseItemID,
        tierItemIDs = tierItemIDs,
        tooltipItemID = meta.tooltipItemID,
        name = displayName,
        rawName = rawName,
        icon = meta.icon,
        need = need or 0,
        have = have or 0,
        remaining = remaining,
        rarity = meta.rarity,
        expacID = meta.expacID,
        expacName = meta.expacName,
        source = meta.source,
        subSource = meta.subSource,
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
  if not (addon and addon.cache) then return end
  if addon.cache._reagentsStale or not addon.cache.reagents then
    if ns.RebuildReagentNeedMap then
      ns.RebuildReagentNeedMap(addon)
    else
      return
    end
  end
  if not addon.cache.reagents then return end
  addon.cache.reagentsList = addon.cache.reagentsList or {}
  addon.cache.reagentsDisplay = addon.cache.reagentsDisplay or {}
  wipeTable(addon.cache.reagentsList)
  wipeTable(addon.cache.reagentsDisplay)
  ns.Reagents.BuildDisplayOnly(addon)
end

ns.RecomputeReagentsOnly = ns.Reagents.RecomputeReagentsOnly
