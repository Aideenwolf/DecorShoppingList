local ADDON, ns = ...
local Template = {}

function Template:IsAvailable()
  return false
end

function Template:OnInit(addon) end

ns:RegisterPlugin("Template", Template)
