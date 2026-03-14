local ADDON, ns = ...
ns = ns or {}
ns.Data = ns.Data or {}

local function NormalizeProfessionCraftingQuality(quality)
  quality = tonumber(quality)
  if quality == nil then return nil end
  quality = math.floor(quality)
  if quality < 1 or quality > 3 then return nil end
  return quality
end

local PROFESSION_CRAFTING_QUALITY_LABELS = {
  [1] = "Bronze",
  [2] = "Silver",
  [3] = "Gold",
}

local PROFESSION_CRAFTING_QUALITY_ATLAS_CANDIDATES = {
  [1] = { "Professions-Icon-Quality-Tier1-Small", "Professions-Icon-Quality-Tier1" },
  [2] = { "Professions-Icon-Quality-Tier2-Small", "Professions-Icon-Quality-Tier2" },
  [3] = { "Professions-Icon-Quality-Tier3-Small", "Professions-Icon-Quality-Tier3" },
}

local function GetProfessionCraftingQualityLabel(quality)
  quality = NormalizeProfessionCraftingQuality(quality)
  return quality and PROFESSION_CRAFTING_QUALITY_LABELS[quality] or nil
end

local function GetTrackedReagentQualityFromItemInfo(itemInfo)
  local api = C_TradeSkillUI
  if api then
    for _, fn in pairs({
      api.GetItemReagentQualityInfo,
    }) do
      if type(fn) == "function" then
        local ok, info = pcall(fn, itemInfo)
        local quality = NormalizeProfessionCraftingQuality(ok and type(info) == "table" and info.quality or nil)
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
        quality = NormalizeProfessionCraftingQuality(ok and quality or nil)
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
        quality = NormalizeProfessionCraftingQuality(ok and type(info) == "table" and info.quality or nil)
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
        quality = NormalizeProfessionCraftingQuality(ok and quality or nil)
        if quality then
          return quality
        end
      end
    end
  end

  return nil
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

local function GetTrackedQualityFromOwnedItemID(itemID)
  local quality = NormalizeProfessionCraftingQuality(GetTrackedReagentQualityFromItemInfo(itemID))
  if quality then
    return quality
  end

  return nil
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
      local quality = NormalizeProfessionCraftingQuality(GetTrackedReagentQualityFromItemInfo(reagent.itemID))
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

ns.Data.NormalizeProfessionCraftingQuality = NormalizeProfessionCraftingQuality
ns.Data.GetProfessionCraftingQualityLabel = GetProfessionCraftingQualityLabel
ns.Data.PROFESSION_CRAFTING_QUALITY_ATLAS_CANDIDATES = PROFESSION_CRAFTING_QUALITY_ATLAS_CANDIDATES
ns.Data.GetTrackedQualityFromContainerItem = GetTrackedQualityFromContainerItem
ns.Data.GetTrackedQualityFromOwnedItemID = GetTrackedQualityFromOwnedItemID
ns.Data.PickRequiredReagent = PickRequiredReagent
ns.Data.GetRequiredReagentTierItemIDs = GetRequiredReagentTierItemIDs
