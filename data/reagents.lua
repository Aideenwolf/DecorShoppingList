local ADDON, ns = ...
ns = ns or {}
ns.Data = ns.Data or {}

local function ResolveItemGroupName(addon, itemIDOrName)
  if type(itemIDOrName) == "string" and itemIDOrName ~= "" then
    return itemIDOrName
  end
  if type(itemIDOrName) == "number" then
    return ns.Data.GetItemNameWithCache(addon, itemIDOrName)
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
      local candidateName = ns.Data.GetItemNameWithCache(addon, candidateItemID)
      if candidateName == targetName then
        total = total + count
      end
    end
  end
  return total
end

local function SumQualityBucketByName(addon, bucket, targetName, targetQuality, breakdown)
  if type(bucket) ~= "table" or not targetName or targetName == "" then
    return 0
  end

  targetQuality = ns.Data.NormalizeProfessionCraftingQuality(targetQuality)
  local total = 0
  for candidateItemID, byQuality in pairs(bucket) do
    if type(candidateItemID) == "number" and type(byQuality) == "table" then
      local candidateName = ns.Data.GetItemNameWithCache(addon, candidateItemID)
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
  if not ns.Data.UsesModernReagentQuality(itemID) then
    return itemID
  end

  targetQuality = ns.Data.NormalizeProfessionCraftingQuality(targetQuality)
  local targetName = ResolveItemGroupName(addon, itemID)
  if not targetName or targetName == "" then
    return itemID
  end

  local realms = addon.db.global and addon.db.global.realms
  local realm = select(1, ns.Data.playerKey())
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
          local candidateQuality = ns.Data.GetTrackedQualityFromOwnedItemID(candidateItemID)
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

local function GetTrackedTierItemIDs(tierItemIDs)
  if type(tierItemIDs) ~= "table" then
    return nil
  end

  local trackedItemIDs = {}
  for quality = 1, 3 do
    local trackedItemID = tierItemIDs[quality]
    if type(trackedItemID) == "number" then
      trackedItemIDs[quality] = trackedItemID
    end
  end

  return next(trackedItemIDs) and trackedItemIDs or nil
end

local function NewQualityCounts()
  return { [1] = 0, [2] = 0, [3] = 0, total = 0 }
end

local function GetReagentTooltipItemID(addon, baseItemID, tierItemIDs)
  local trackedItemIDs = GetTrackedTierItemIDs(tierItemIDs)
  if trackedItemIDs and trackedItemIDs[1] then
    return trackedItemIDs[1]
  end
  return (SelectTooltipItemID(addon, baseItemID, nil) or baseItemID)
end

local function GetReagentHaveCount(addon, baseItemID, tierItemIDs)
  local trackedItemIDs = GetTrackedTierItemIDs(tierItemIDs)
  if trackedItemIDs then
    local ids = {}
    for _, trackedItemID in ipairs(trackedItemIDs) do
      if type(trackedItemID) == "number" then
        ids[#ids + 1] = trackedItemID
      end
    end
    return ns.GetHaveCountForItemIDs(addon, ids)
  end
  return ns.GetHaveCountByName(addon, baseItemID)
end

local function GetReagentSourceCounts(addon, bucket, qualityBucket, baseItemID, tierItemIDs)
  local counts = NewQualityCounts()
  if type(bucket) ~= "table" then
    return counts
  end

  local trackedItemIDs = GetTrackedTierItemIDs(tierItemIDs)
  if trackedItemIDs then
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

  if not ns.Data.UsesModernReagentQuality(baseItemID) then
    counts.total = bucket[baseItemID] or 0
    return counts
  end

  local targetName = ResolveItemGroupName(addon, baseItemID)
  if not targetName or targetName == "" then
    return counts
  end

  if type(qualityBucket) == "table" then
    SumQualityBucketByName(addon, qualityBucket, targetName, nil, counts)
    counts.total = (counts[1] or 0) + (counts[2] or 0) + (counts[3] or 0)
  end

  return counts
end

local function FormatReagentQualityBreakdown(counts, tierItemIDs)
  counts = type(counts) == "table" and counts or {}
  local bronze = counts[1] or 0
  local silver = counts[2] or 0
  local gold = counts[3] or 0
  local total = counts.total or (bronze + silver + gold)
  if bronze == 0 and silver == 0 and gold == 0 then
    return tostring(total)
  end

  local function iconForQuality(quality)
    local atlases = ns.Data.PROFESSION_CRAFTING_QUALITY_ATLAS_CANDIDATES[quality]
    local atlas = atlases and atlases[1]
    if atlas then
      return string.format("|A:%s:14:14|a", atlas)
    end
    return tostring(quality)
  end

  local qualityMap = { 1, 2, 3 }
  local tierCount = 0
  if type(tierItemIDs) == "table" then
    for idx = 1, 3 do
      if type(tierItemIDs[idx]) == "number" then
        tierCount = tierCount + 1
      end
    end
  end
  if tierCount == 2 and gold == 0 then
    qualityMap = { 2, 3 }
  end

  local parts = {}
  local values = { bronze, silver, gold }
  for index, amount in ipairs(values) do
    if amount > 0 then
      local displayQuality = qualityMap[index] or index
      parts[#parts + 1] = string.format("%s %d", iconForQuality(displayQuality), amount)
    end
  end

  return string.format("%s    %d", table.concat(parts, " | "), total)
end

ns.Data.ResolveItemGroupName = ResolveItemGroupName
ns.Data.SumBucketByName = SumBucketByName
ns.Data.SumQualityBucketByName = SumQualityBucketByName
ns.Data.SumBucketExact = SumBucketExact
ns.Data.GetReagentTooltipItemID = GetReagentTooltipItemID
ns.Data.GetReagentHaveCount = GetReagentHaveCount
ns.Data.GetReagentSourceCounts = GetReagentSourceCounts
ns.Data.FormatReagentQualityBreakdown = FormatReagentQualityBreakdown
