local ADDON, ns = ...
ns = ns or {}

ns.Reagents = ns.Reagents or {}

function ns.Reagents.SortAndBuildDisplay(flat, mode, collapsed, getExpansionName)
  if ns.Sorting and ns.Sorting.SortReagentFlat then
    return ns.Sorting.SortReagentFlat(flat, mode, collapsed, getExpansionName)
  end
  return flat or {}, flat or {}
end

