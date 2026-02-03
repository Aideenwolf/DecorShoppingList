local ADDON, ns = ...
local L = LibStub("AceLocale-3.0"):GetLocale("DecorShoppingList")

function ns.InitBroker(addon)
  local LDB = LibStub("LibDataBroker-1.1", true)
  local DBIcon = LibStub("LibDBIcon-1.0", true)
  if not LDB or not DBIcon then return end

  local iconPath = "Interface\\AddOns\\DecorShoppingList\\assets\\icons\\minimap.tga"

  local obj = LDB:NewDataObject("DecorShoppingList", {
    type = "launcher",
    text = L["ADDON_NAME"],
    icon = iconPath,
    OnClick = function(_, button)
      if button == "LeftButton" then
        ns.ShowListWindow(addon, not ns.ListWindow:IsShown())
      end
    end,
    OnTooltipShow = function(tt)
      tt:AddLine(L["ADDON_NAME"])
      tt:AddLine(L["MINIMAP_TOGGLE"])
      tt:AddLine(L["SLASH_HELP"])
    end,
  })

  DBIcon:Register("DecorShoppingList", obj, addon.db.profile.minimap)
end
