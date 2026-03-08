local ADDON, ns = ...
ns = ns or {}

ns.Sorting = ns.Sorting or {}

function ns.Sorting.NameKey(x)
  return tostring(x and (x.rawName or x.name or "") or ""):lower()
end

function ns.Sorting.CompareNames(a, b)
  local aKey = ns.Sorting.NameKey(a)
  local bKey = ns.Sorting.NameKey(b)
  if aKey ~= bKey then
    return aKey < bKey
  end

  local aName = tostring(a and (a.name or a.rawName or "") or "")
  local bName = tostring(b and (b.name or b.rawName or "") or "")
  if aName ~= bName then
    return aName < bName
  end

  local aID = tostring(a and (a.recipeID or a.itemID or a.groupKey or "") or "")
  local bID = tostring(b and (b.recipeID or b.itemID or b.groupKey or "") or "")
  return aID < bID
end

function ns.Sorting.SortRecipeList(list, mode)
  list = list or {}
  mode = mode or "N"

  if mode == "E" then
    table.sort(list, function(a, b)
      local ae, be = (a.expacID or -1), (b.expacID or -1)
      if ae ~= be then return ae > be end
      return ns.Sorting.CompareNames(a, b)
    end)
    return list
  end

  table.sort(list, ns.Sorting.CompareNames)
  return list
end

function ns.Sorting.BuildRecipeSortSignature(list, mode)
  local parts = { tostring(mode or "N"), tostring(#(list or {})) }
  for _, row in ipairs(list or {}) do
    parts[#parts + 1] = table.concat({
      tostring(row.recipeID or ""),
      tostring(row.itemID or ""),
      tostring(row.expacID or ""),
      tostring(row.rawName or row.name or ""),
    }, "\30")
  end
  return table.concat(parts, "\31")
end

function ns.Sorting.SortReagentFlat(flat, mode, collapsed, getExpansionName)
  flat = flat or {}
  collapsed = collapsed or {}
  mode = mode or "E"

  local function nameKey(x) return ns.Sorting.NameKey(x) end
  local function rarityKey(x) return (x.rarity or -1) end

  local function completeAwareCompare(a, b, innerCompare)
    if a.isComplete ~= b.isComplete then
      return (a.isComplete == false)
    end
    if a.isComplete and b.isComplete then
      return ns.Sorting.CompareNames(a, b)
    end
    return innerCompare(a, b)
  end

  local function sortN(a, b)
    return ns.Sorting.CompareNames(a, b)
  end

  local function sortR(a, b)
    local ar, br = rarityKey(a), rarityKey(b)
    if ar ~= br then return ar > br end
    return ns.Sorting.CompareNames(a, b)
  end

  local function sortEInner(a, b)
    local ae, be = (a.expacID or -1), (b.expacID or -1)
    if ae ~= be then return ae > be end
    local ar, br = rarityKey(a), rarityKey(b)
    if ar ~= br then return ar > br end
    return ns.Sorting.CompareNames(a, b)
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
    return ns.Sorting.CompareNames(a, b)
  end

  if mode == "N" then
    table.sort(flat, function(a, b) return completeAwareCompare(a, b, sortN) end)
    return flat, flat
  end

  if mode == "R" then
    table.sort(flat, function(a, b) return completeAwareCompare(a, b, sortR) end)
    return flat, flat
  end

  if mode == "E" then
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
        local headerName = getExpansionName and getExpansionName(id) or ("Expansion " .. tostring(id))
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

    return flat, display
  end

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

  return flat, display
end
