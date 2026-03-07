-- Config.lua
local _, ns = ...
ns = ns or {}

local LSM
local function GetLSM()
  if not LSM and LibStub then
    LSM = LibStub("LibSharedMedia-3.0", true)
  end
  return LSM
end
local WHITE8 = "Interface\\Buttons\\WHITE8x8"
local DIALOG_BORDER = "Interface\\DialogFrame\\UI-DialogBox-Border"
local COLOR_SECTION = { 1, 0.82, 0, 1 }
local COLOR_FIELD = { 1, 1, 1, 1 }

local BACKDROP_SQUARE = {
  bgFile = WHITE8,
  edgeFile = WHITE8,
  edgeSize = 1,
  insets = { left = 1, right = 1, top = 1, bottom = 1 },
}

local BACKDROP_ROUNDED = {
  bgFile = WHITE8,
  edgeFile = DIALOG_BORDER,
  edgeSize = 16,
  insets = { left = 5, right = 5, top = 5, bottom = 5 },
}

local function ensureColor(src)
  local c = type(src) == "table" and src or {}
  c[1] = tonumber(c[1]) or c[1] or 1
  c[2] = tonumber(c[2]) or c[2] or 1
  c[3] = tonumber(c[3]) or c[3] or 1
  c[4] = tonumber(c[4]) or c[4] or 1
  return c
end

local function applyMediaTexture(tex, media)
  if not tex then return end

  local path = WHITE8
  if media ~= "Solid" then
    local lsm = GetLSM()
    path = (lsm and lsm:Fetch("background", media, true)) or WHITE8
  end

  tex:SetTexture(path)
  if tex.SetTexCoord then tex:SetTexCoord(0, 1, 0, 1) end
end

local function setFontStringColor(fs, color)
  if not (fs and fs.SetTextColor and color) then return end
  fs:SetTextColor(color[1], color[2], color[3], color[4])
end

local function applyConfigLabelColors(frame)
  if frame.SectionLabels then
    for _, fs in ipairs(frame.SectionLabels) do
      setFontStringColor(fs, COLOR_SECTION)
    end
  end
  if frame.FieldLabels then
    for _, fs in ipairs(frame.FieldLabels) do
      setFontStringColor(fs, COLOR_FIELD)
    end
  end
  if frame.Outline and frame.Outline.text then
    setFontStringColor(frame.Outline.text, COLOR_FIELD)
  end
  if frame.Rounded and frame.Rounded.text then
    setFontStringColor(frame.Rounded.text, COLOR_FIELD)
  end
end

local function setDropdown(frame, width, buildFn, selectedName)
  UIDropDownMenu_SetWidth(frame, width)
  UIDropDownMenu_Initialize(frame, buildFn)
  UIDropDownMenu_SetSelectedName(frame, selectedName)
end

local function setNameDropdown(frame, width, names, selectedName, onSelected)
  setDropdown(frame, width, function(_, level)
    for _, name in ipairs(names) do
      local selected = name
      local info = UIDropDownMenu_CreateInfo()
      info.text = selected
      info.func = function()
        UIDropDownMenu_SetSelectedName(frame, selected)
        onSelected(selected)
      end
      UIDropDownMenu_AddButton(info, level)
    end
  end, selectedName)
end

local function getFontNames(defaultName)
  local lsm = GetLSM()
  local names = (lsm and lsm.List and lsm:List("font")) or {}
  if #names == 0 then
    names = { defaultName or "Friz Quadrata TT" }
  end
  return names
end

local function getBackgroundNames()
  local lsm = GetLSM()
  local names = (lsm and lsm.List and lsm:List("background")) or {}
  local out = { "Solid" }
  for _, n in ipairs(names) do
    if n ~= "Solid" then
      table.insert(out, n)
    end
  end
  return out
end

function ns.GetVisualSettings(addon)
  if not (addon and addon.db and addon.db.profile) then return nil end
  addon.db.profile.visual = addon.db.profile.visual or {}
  local v = addon.db.profile.visual

  v.textOutline = (v.textOutline ~= false)
  v.textSize = tonumber(v.textSize) or 10
  if v.textSize < 8 then v.textSize = 8 end
  if v.textSize > 24 then v.textSize = 24 end
  v.textFont = v.textFont or "Friz Quadrata TT"

  v.textColor = type(v.textColor) == "table" and v.textColor or {}
  v.textColor.header = ensureColor(v.textColor.header)

  v.borderColor = ensureColor(v.borderColor)
  v.backgroundColor = ensureColor(v.backgroundColor)
  v.scrollbarColor = ensureColor(v.scrollbarColor)
  v.titleTabColor = ensureColor(v.titleTabColor)

  if type(v.buttonColor) ~= "table" then
    v.buttonColor = { v.titleTabColor[1], v.titleTabColor[2], v.titleTabColor[3], v.titleTabColor[4] }
  end
  v.buttonColor = ensureColor(v.buttonColor)

  v.showRoundedBorder = (v.showRoundedBorder ~= false)
  v.backgroundMedia = v.backgroundMedia or "Solid"
  return v
end

local function refreshVisuals(addon)
  if ns.ApplyConfigWindowVisuals then ns.ApplyConfigWindowVisuals(addon) end
  if ns.ApplyWindowVisuals then ns.ApplyWindowVisuals(addon) end
  if ns.RefreshListWindow then ns.RefreshListWindow(addon) end
end

local function updateVisual(addon, mutator)
  local v = ns.GetVisualSettings(addon)
  if not v then return end
  if mutator then mutator(v) end
  refreshVisuals(addon)
end

local function openColorPicker(color, onChanged, allowAlpha)
  if not (ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow) then return end

  local prev = {
    r = color[1] or 1,
    g = color[2] or 1,
    b = color[3] or 1,
    a = color[4] or 1,
  }

  local function getAlpha()
    if not allowAlpha then
      return color[4] or prev.a
    end

    if ColorPickerFrame.GetColorAlpha then
      local ok, picked = pcall(ColorPickerFrame.GetColorAlpha, ColorPickerFrame)
      if ok and type(picked) == "number" then
        return picked
      end
    end

---@diagnostic disable-next-line: undefined-global
    if OpacitySliderFrame and OpacitySliderFrame.GetValue then
---@diagnostic disable-next-line: undefined-global
      local v = OpacitySliderFrame:GetValue()
      if type(v) == "number" then
        return  v
      end
    end

    return color[4] or prev.a
  end

  local function applyColor()
    local r, g, b = ColorPickerFrame:GetColorRGB()
    color[1], color[2], color[3] = r, g, b
    onChanged()
  end

  local function applyAlpha()
    local a = getAlpha()
    color[4] = a
    onChanged()
  end

  ColorPickerFrame:SetupColorPickerAndShow({
    r = prev.r,
    g = prev.g,
    b = prev.b,
    opacity = prev.a,
    hasOpacity = allowAlpha,
    swatchFunc = applyColor,
    opacityFunc = allowAlpha and applyAlpha or nil,
    cancelFunc = function()
      color[1], color[2], color[3], color[4] = prev.r, prev.g, prev.b, prev.a
      onChanged()
    end,
  })
end

local function makeColorButton(parent, x, y, color, onChanged, allowAlpha)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetSize(18, 18)
  b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  b:EnableMouse(true)
  b:RegisterForClicks("LeftButtonUp")
  b:SetBackdrop({
    bgFile = WHITE8,
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = false, edgeSize = 10,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  b:SetFrameLevel(parent:GetFrameLevel() + 5)

  local function paint()
    b:SetBackdropColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
  end

  b:SetScript("OnClick", function()
    openColorPicker(color, function()
      paint()
      onChanged()
    end, allowAlpha)
  end)

  paint()
  return b
end

local function buildConfigWindow(addon)
  local v = ns.GetVisualSettings(addon)
  local f = CreateFrame("Frame", "DecorShoppingListConfigWindow", UIParent, "BackdropTemplate")
  ns.ConfigWindow = f
  f:SetSize(320, 500)
  f:SetPoint("CENTER", UIParent, "CENTER", 340, 0)
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

  f.TitleBar = f:CreateTexture(nil, "ARTWORK")
  f.TitleBar:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -6)
  f.TitleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)
  f.TitleBar:SetHeight(20)

  f.Title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.Title:SetPoint("CENTER", f.TitleBar, "CENTER", 0, 0)
  f.Title:SetText("Decor Shopping List Settings")

  f.CloseButton = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  f.CloseButton:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)

  f.BG = f:CreateTexture(nil, "BACKGROUND")
  f.BG:SetDrawLayer("BACKGROUND", -7)
  f.BG:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -30)
  f.BG:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 10)

  local left = 16
  local y = -40
  f.SectionLabels = {}
  f.FieldLabels = {}

  local function onVisualChanged()
    updateVisual(addon)
  end

  local function addSectionLabel(text, x, yy)
    local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", f, "TOPLEFT", x, yy)
    fs:SetText(text)
    setFontStringColor(fs, COLOR_SECTION)
    table.insert(f.SectionLabels, fs)
    return fs
  end

  local function addFieldLabel(text, x, yy)
    local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", f, "TOPLEFT", x, yy)
    fs:SetText(text)
    setFontStringColor(fs, COLOR_FIELD)
    table.insert(f.FieldLabels, fs)
    return fs
  end

  addSectionLabel("Texts", left, y)
  y = y - 24

  f.Outline = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
  f.Outline:SetPoint("TOPLEFT", f, "TOPLEFT", left - 2, y)
  f.Outline.text:SetText("Text Outline")
  setFontStringColor(f.Outline.text, COLOR_FIELD)
  f.Outline:SetScript("OnClick", function(self)
    updateVisual(addon, function(v)
      v.textOutline = not not self:GetChecked()
    end)
  end)
  y = y - 30

  local sizeLabel = addFieldLabel("Text Size", left, y)

  f.SizeBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
  f.SizeBox:SetSize(60, 20)
  f.SizeBox:SetPoint("LEFT", sizeLabel, "RIGHT", 8, 0)
  f.SizeBox:SetAutoFocus(false)
  f.SizeBox:SetNumeric(true)
  f.SizeBox:SetScript("OnEnterPressed", function(self)
    local n = tonumber(self:GetText() or "")
    if n then
      if n < 8 then n = 8 end
      if n > 24 then n = 24 end
      n = math.floor(n)
      self:SetNumber(n)
      updateVisual(addon, function(v)
        v.textSize = n
      end)
    end
    self:ClearFocus()
  end)
  y = y - 34

  local fontLabel = addFieldLabel("Text Font", left, y)

  f.FontDrop = CreateFrame("Frame", nil, f, "UIDropDownMenuTemplate")
  f.FontDrop:SetPoint("TOPLEFT", fontLabel, "BOTTOMLEFT", -16, -2)
  y = y - 64

  addFieldLabel("Header Color", left + 20, y)
  f.HeaderColor = makeColorButton(f, left, y + 2, v.textColor.header, onVisualChanged)
  y = y - 38

  addSectionLabel("Settings", left, y)
  y = y - 24

  addFieldLabel("Border Color", left + 20, y)
  f.BorderColor = makeColorButton(f, left, y + 2, v.borderColor, onVisualChanged, true)
  y = y - 26

  addFieldLabel("Background Color", left + 20, y)
  f.BackgroundColor = makeColorButton(f, left, y + 2, v.backgroundColor, onVisualChanged, true)
  y = y - 26


  addFieldLabel("Title Tabs Color", left + 20, y)
  f.TitleTabColor = makeColorButton(f, left, y + 2, v.titleTabColor, onVisualChanged, true)
  y = y - 26

  addFieldLabel("Button Color", left + 20, y)
  f.ButtonColor = makeColorButton(f, left, y + 2, v.buttonColor, onVisualChanged, true)
  y = y - 30

  f.Rounded = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
  f.Rounded:SetPoint("TOPLEFT", f, "TOPLEFT", left - 2, y)
  f.Rounded.text:SetText("Show Rounded Border")
  setFontStringColor(f.Rounded.text, COLOR_FIELD)
  f.Rounded:SetScript("OnClick", function(self)
    updateVisual(addon, function(v)
      v.showRoundedBorder = not not self:GetChecked()
    end)
  end)
  y = y - 34

  local bgMediaLabel = addFieldLabel("Background Media", left, y)

  f.BgDrop = CreateFrame("Frame", nil, f, "UIDropDownMenuTemplate")
  f.BgDrop:SetPoint("TOPLEFT", bgMediaLabel, "BOTTOMLEFT", -16, -2)

  ns.ApplyConfigWindowVisuals = function(owner)
    if owner and owner ~= addon then return end
    local v = ns.GetVisualSettings(addon)
    if not v then return end

    f:SetBackdrop((v.showRoundedBorder == false) and BACKDROP_SQUARE or BACKDROP_ROUNDED)

    f:SetBackdropColor(0, 0, 0, 0)
    f:SetBackdropBorderColor(v.borderColor[1], v.borderColor[2], v.borderColor[3], v.borderColor[4])

    applyMediaTexture(f.BG, v.backgroundMedia)
    f.BG:SetVertexColor(v.backgroundColor[1], v.backgroundColor[2], v.backgroundColor[3], v.backgroundColor[4])
    f.TitleBar:SetColorTexture(v.titleTabColor[1], v.titleTabColor[2], v.titleTabColor[3], v.titleTabColor[4])
    applyConfigLabelColors(f)
  end
end

function ns.InitConfig(addon)
  ns.GetVisualSettings(addon)
end

function ns.ShowConfigWindow(addon, show)
  if not addon then return end
  local v = ns.GetVisualSettings(addon)
  if not v then return end

  if not ns.ConfigWindow then
    buildConfigWindow(addon)
  end
  local f = ns.ConfigWindow

  f.Outline:SetChecked(v.textOutline)
  f.SizeBox:SetNumber(v.textSize)
  f.Rounded:SetChecked(v.showRoundedBorder)

  setNameDropdown(f.FontDrop, 255, getFontNames(v.textFont), v.textFont, function(name)
    updateVisual(addon, function(visual)
      visual.textFont = name
    end)
  end)

  setNameDropdown(f.BgDrop, 255, getBackgroundNames(), v.backgroundMedia, function(name)
    updateVisual(addon, function(visual)
      visual.backgroundMedia = name
    end)
  end)

  refreshVisuals(addon)

  f:SetShown(show ~= false)
end
