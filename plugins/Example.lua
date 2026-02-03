local ADDON, ns = ...
local Example = {}

function Example:IsAvailable()
  return false
end

function Example:OnInit(addon) end

ns:RegisterPlugin("Example", Example)
