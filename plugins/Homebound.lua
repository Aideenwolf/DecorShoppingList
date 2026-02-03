local ADDON, ns = ...
ns = ns or {}
local Homebound = {}

local function IsAddonLoadedSafe(name)
  if C_AddOns and C_AddOns.IsAddOnLoaded then
    return C_AddOns.IsAddOnLoaded(name)
  end
  -- very old fallback (likely unnecessary on Retail, but safe)
  if _G.IsAddOnLoaded then
    return _G.IsAddOnLoaded(name)
  end
  return false
end

function Homebound:IsAvailable()
  return IsAddonLoadedSafe("Homebound") or IsAddonLoadedSafe("homebound")
end

function Homebound:OnInit(addon)
  -- TODO (future): parse Homebound links, register link handlers, import/export
end

ns:RegisterPlugin("Homebound", Homebound)
