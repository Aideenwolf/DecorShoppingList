local ADDON, ns = ...
local L = LibStub("AceLocale-3.0"):GetLocale("DecorShoppingList")

local WHITE8 = "Interface\\Buttons\\WHITE8x8"
local BORDER = "Interface\\Tooltips\\UI-Tooltip-Border"

local function FormatLastSeen(ts)
  ts = tonumber(ts) or 0
  if ts <= 0 then
    return "never"
  end
  return date("%Y-%m-%d", ts)
end

local function GetClassColor(classToken)
  if C_ClassColor and C_ClassColor.GetClassColor and classToken then
    local color = C_ClassColor.GetClassColor(classToken)
    if color then
      return color
    end
  end

  local colors = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
  return colors and classToken and colors[classToken] or nil
end

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

local function EnsureBrokerHoverFrame()
  if ns.BrokerHoverFrame then
    return ns.BrokerHoverFrame
  end

  local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  f:SetFrameStrata("TOOLTIP")
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:SetBackdrop({
    bgFile = WHITE8,
    edgeFile = BORDER,
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  f:SetBackdropColor(0.05, 0.05, 0.07, 0.95)
  f:SetBackdropBorderColor(0.75, 0.75, 0.78, 1)
  f:Hide()

  local colX = { 10, 112, 198, 252, 306 }
  local colW = { 94, 76, 44, 44, 56 }

  f.Headers = {}
  for i, label in ipairs({ "Character", "Seen", "Bags", "Bank", "Recipes" }) do
    local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", f, "TOPLEFT", colX[i], -10)
    fs:SetWidth(colW[i])
    fs:SetJustifyH("LEFT")
    fs:SetTextColor(1, 0.82, 0, 1)
    fs:SetText(label)
    f.Headers[i] = fs
  end

  f.Divider = f:CreateTexture(nil, "ARTWORK")
  f.Divider:SetTexture(WHITE8)
  f.Divider:SetColorTexture(0.65, 0.65, 0.70, 0.9)
  f.Divider:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -28)
  f.Divider:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -28)
  f.Divider:SetHeight(1)

  f.Rows = {}
  for rowIndex = 1, 12 do
    local row = {}
    local y = -34 - ((rowIndex - 1) * 18)
    for col = 1, 5 do
      local fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      fs:SetPoint("TOPLEFT", f, "TOPLEFT", colX[col], y)
      fs:SetWidth(colW[col])
      fs:SetJustifyH("LEFT")
      fs:SetTextColor(0.9, 0.9, 0.9, 1)
      row[col] = fs
    end
    f.Rows[rowIndex] = row
  end

  f:SetScript("OnEnter", function(self)
    if self._dslHideTimer and self._dslAddon and self._dslAddon.CancelTimer then
      self._dslAddon:CancelTimer(self._dslHideTimer)
      self._dslHideTimer = nil
    end
  end)

  f:SetScript("OnLeave", function(self)
    local addon = self._dslAddon
    if not (addon and addon.ScheduleTimer) then
      self:Hide()
      return
    end
    if self._dslHideTimer then
      addon:CancelTimer(self._dslHideTimer)
    end
    self._dslHideTimer = addon:ScheduleTimer(function()
      self._dslHideTimer = nil
      if not self:IsMouseOver() then
        self:Hide()
      end
    end, 0.15)
  end)

  ns.BrokerHoverFrame = f
  return f
end

local function HideBrokerHoverFrame(addon)
  local f = ns.BrokerHoverFrame
  if not f then return end
  if f._dslHideTimer and addon and addon.CancelTimer then
    addon:CancelTimer(f._dslHideTimer)
    f._dslHideTimer = nil
  end
  f:Hide()
end

local function ShowBrokerHoverFrame(owner, addon)
  if not (owner and addon and ns.GetTrackedCharacters) then return end

  local f = EnsureBrokerHoverFrame()
  f._dslAddon = addon
  if f._dslHideTimer and addon.CancelTimer then
    addon:CancelTimer(f._dslHideTimer)
    f._dslHideTimer = nil
  end

  local tracked = ns.GetTrackedCharacters(addon)
  tracked = tracked or {}
  local visibleRows = math.min(math.max(#tracked, 1), #f.Rows)

  for rowIndex, row in ipairs(f.Rows) do
    local info = tracked[rowIndex]
    if info then
      local color = GetClassColor(info.classToken)
      row[1]:SetText(tostring(info.charName or info.charKey or "?"))
      if color then
        row[1]:SetTextColor(color.r or color.R or 1, color.g or color.G or 1, color.b or color.B or 1, 1)
      else
        row[1]:SetTextColor(0.95, 0.95, 0.95, 1)
      end
      row[2]:SetText(FormatLastSeen(info.lastSeen))
      row[3]:SetText(tostring(tonumber(info.bagCount) or 0))
      row[4]:SetText(tostring(tonumber(info.bankCount) or 0))
      row[5]:SetText(tostring(tonumber(info.recipeCount) or 0))
      for col = 2, 5 do
        row[col]:SetTextColor(0.9, 0.9, 0.9, 1)
      end
      for col = 1, 5 do
        row[col]:Show()
      end
    elseif rowIndex == 1 and #tracked == 0 then
      row[1]:SetText("None")
      row[1]:SetTextColor(0.7, 0.7, 0.7, 1)
      for col = 2, 5 do
        row[col]:SetText("")
        row[col]:Show()
      end
      row[1]:Show()
    else
      for col = 1, 5 do
        row[col]:Hide()
      end
    end
  end

  local height = 38 + (math.max(visibleRows, 1) * 18) + 10
  f:SetSize(370, height)
  f:ClearAllPoints()

  local ox, oy = owner:GetCenter()
  local ux, uy = UIParent:GetCenter()
  local onRight = ox and ux and ox >= ux
  local onTop = oy and uy and oy >= uy

  if onRight and onTop then
    f:SetPoint("TOPRIGHT", owner, "BOTTOMLEFT", -8, -8)
  elseif onRight then
    f:SetPoint("BOTTOMRIGHT", owner, "TOPLEFT", -8, 8)
  elseif onTop then
    f:SetPoint("TOPLEFT", owner, "BOTTOMRIGHT", 8, -8)
  else
    f:SetPoint("BOTTOMLEFT", owner, "TOPRIGHT", 8, 8)
  end

  f:Show()
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
    OnEnter = function(frame)
      ShowBrokerHoverFrame(frame, addon)
    end,
    OnLeave = function(frame)
      local f = ns.BrokerHoverFrame
      if not f then return end
      if f._dslHideTimer and addon.CancelTimer then
        addon:CancelTimer(f._dslHideTimer)
      end
      f._dslHideTimer = addon:ScheduleTimer(function()
        f._dslHideTimer = nil
        if not (frame and frame.IsMouseOver and frame:IsMouseOver()) and not f:IsMouseOver() then
          HideBrokerHoverFrame(addon)
        end
      end, 0.15)
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
