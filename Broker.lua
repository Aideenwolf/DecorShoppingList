local ADDON, ns = ...
local L = LibStub("AceLocale-3.0"):GetLocale("DecorShoppingList")

local function SetMinimapVisibility(addon)
  local DBIcon = LibStub("LibDBIcon-1.0", true)
  if not (addon and addon.db and addon.db.profile and DBIcon) then return end

  addon.db.profile.minimap = addon.db.profile.minimap or {}
  local hidden = addon.db.profile.minimap.hide == true
  if hidden then
    DBIcon:Hide("DecorShoppingList")
  else
    DBIcon:Show("DecorShoppingList")
  end
end

function ns.InitBroker(addon)
  local LDB = LibStub("LibDataBroker-1.1", true)
  local DBIcon = LibStub("LibDBIcon-1.0", true)
  if not LDB or not DBIcon then return end

  addon.db.profile.minimap = addon.db.profile.minimap or {}

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
    end,
  })

  DBIcon:Register("DecorShoppingList", obj, addon.db.profile.minimap)
  SetMinimapVisibility(addon)
end

function ns.SetMinimapButtonEnabled(addon, enabled)
  if not (addon and addon.db and addon.db.profile) then return end
  addon.db.profile.minimap = addon.db.profile.minimap or {}
  addon.db.profile.minimap.hide = not not (enabled == false)
  SetMinimapVisibility(addon)
end

function ns.IsMinimapButtonEnabled(addon)
  if not (addon and addon.db and addon.db.profile) then return false end
  addon.db.profile.minimap = addon.db.profile.minimap or {}
  return addon.db.profile.minimap.hide ~= true
end
