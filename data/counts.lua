local ADDON, ns = ...
ns = ns or {}
ns.Data = ns.Data or {}

local playerKey = ns.Data.playerKey
local NormalizeProfessionCraftingQuality = ns.Data.NormalizeProfessionCraftingQuality
local ResolveItemGroupName = ns.Data.ResolveItemGroupName
local SumBucketByName = ns.Data.SumBucketByName
local SumQualityBucketByName = ns.Data.SumQualityBucketByName
local SumBucketExact = ns.Data.SumBucketExact
local UsesModernReagentQuality = ns.Data.UsesModernReagentQuality
local GetTrackedQualityFromOwnedItemID = ns.Data.GetTrackedQualityFromOwnedItemID

function ns.GetHaveCount(addon, itemID)
  if not (addon and addon.db and itemID) then return 0 end

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
  quality = NormalizeProfessionCraftingQuality(quality)
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
    local quality = NormalizeProfessionCraftingQuality(GetTrackedQualityFromOwnedItemID(itemID)) or 1
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
