-- ListWindow.lua

local _, ns = ...
ns = ns or {}
local L = LibStub("AceLocale-3.0"):GetLocale("DecorShoppingList")
local LSM
local function GetLSM()
  if not LSM and LibStub then
    LSM = LibStub("LibSharedMedia-3.0", true)
  end
  return LSM
end

local ROWS_MAX = 60
local ROW_H = 22

-- Small inline icons for tooltips
local ICON_LMB = "|A:newplayertutorial-icon-mouse-leftbutton:14:14|a"
local ICON_RMB = "|A:newplayertutorial-icon-mouse-rightbutton:14:14|a"
local ICON_SHIFT = "|cffffd100SHIFT|r"
local ICON_CTRL  = "|cffffd100CTRL|r"
local ICON_ALT   = "|cffffd100ALT|r"
local DEFAULT_VISUAL_SETTINGS = {
  backgroundMedia = "Solid",
  backgroundColor = { 0.09, 0.09, 0.10, 0.25 },
  borderColor = { 0.75, 0.75, 0.78, 1 },
  scrollbarColor = { 0.75, 0.75, 0.78, 1 },
  titleTabColor = { 0.20, 0.20, 0.22, 0.92 },
  showRoundedBorder = true,
}

local function ColorizeCharacterName(name, classToken)
  if not name or name == "" then
    return name or ""
  end

  if C_ClassColor and C_ClassColor.GetClassColor and classToken then
    local c = C_ClassColor.GetClassColor(classToken)
    if c and c.WrapTextInColorCode then
      return c:WrapTextInColorCode(name)
    end
  end

  local palette = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)
  local c = classToken and palette and palette[classToken]
  if c then
    local r = c.r or c.R or 1
    local g = c.g or c.G or 1
    local b = c.b or c.B or 1
    return ("|cff%02x%02x%02x%s|r"):format(r * 255, g * 255, b * 255, name)
  end

  return name
end

local function ApplyQualityIcon(texture, quality)
  if not texture then return false end
  quality = ns.Data.NormalizeProfessionCraftingQuality(quality)
  if not quality then
    texture:Hide()
    return false
  end

  for _, atlas in ipairs((ns.Data.PROFESSION_CRAFTING_QUALITY_ATLAS_CANDIDATES and ns.Data.PROFESSION_CRAFTING_QUALITY_ATLAS_CANDIDATES[quality]) or {}) do
    if texture.SetAtlas and texture:SetAtlas(atlas, true) then
      texture:Show()
      return true
    end
  end

  texture:Hide()
  return false
end

local function GetVisibleRows(f)
  local scroll = f and f.Scroll
  local h = scroll and scroll.GetHeight and scroll:GetHeight() or 0
  local rows = math.floor((h / ROW_H) + 0.0001)
  if rows < 1 then rows = 1 end
  if rows > ROWS_MAX then rows = ROWS_MAX end
  return rows
end

local function GetVisualOrDefault(addon)
  return (ns.GetVisualSettings and ns.GetVisualSettings(addon)) or DEFAULT_VISUAL_SETTINGS
end

local function NowSeconds()
  if GetTimePreciseSec then
    return GetTimePreciseSec()
  end
  if GetTime then
    return GetTime()
  end
  return 0
end

function ns.ApplyWindowStateFromDB(addon)
  local db = addon.db.profile.window
  local f = ns.ListWindow
  if not f then return end

  f:ClearAllPoints()
  f:SetPoint(db.point or "CENTER", UIParent, db.relPoint or "CENTER", db.x or 0, db.y or 0)
  f:SetSize(db.w or 360, db.h or 420)
end

local function EnsureDefaults(addon)
  addon.db.profile.window = addon.db.profile.window or {}
  addon.db.profile.window.view = addon.db.profile.window.view or "recipes"
  addon.db.profile.window.reagentSort = addon.db.profile.window.reagentSort or "E"
  addon.db.profile.window.recipeSort = addon.db.profile.window.recipeSort or "N"
  addon.db.profile.window.collapsed = addon.db.profile.window.collapsed or {}
end

local function ApplyMediaTexture(tex, media)
  if not tex then return end
  if media == "Solid" then
    tex:SetTexture("Interface\\Buttons\\WHITE8x8")
    if tex.SetTexCoord then tex:SetTexCoord(0, 1, 0, 1) end
    return
  end

  local lsm = GetLSM()
  local bgPath = (lsm and lsm:Fetch("background", media, true)) or "Interface\\Buttons\\WHITE8x8"
  tex:SetTexture(bgPath)
  if tex.SetTexCoord then tex:SetTexCoord(0, 1, 0, 1) end
end

function ns.InitListWindow(addon)
  EnsureDefaults(addon)
  local db = addon.db.profile.window
  local function saveWindowState(self)
    local point, _, relPoint, x, y = self:GetPoint(1)
    local w, h = self:GetSize()
    db.point, db.relPoint, db.x, db.y = point, relPoint, math.floor(x + 0.5), math.floor(y + 0.5)
    db.w, db.h = math.floor(w + 0.5), math.floor(h + 0.5)
  end

  local f = CreateFrame("Frame", "DecorShoppingListWindow", UIParent, "BackdropTemplate")
  ns.ListWindow = f

  f:SetSize(db.w or 360, db.h or 420)
  f:SetPoint(db.point or "CENTER", UIParent, db.relPoint or "CENTER", db.x or 0, db.y or 0)
  f:SetMovable(true)
  if f.SetResizable then
    f:SetResizable(true)
  end
  if f.SetResizeBounds then
    f:SetResizeBounds(320, 300, 1000, 900)
  else
    if f.SetMinResize then f:SetMinResize(320, 300) end
    if f.SetMaxResize then f:SetMaxResize(1000, 900) end
  end
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetClampedToScreen(true)
  f:SetFrameStrata("MEDIUM")
  f:SetBackdropColor(0, 0, 0, 0)

  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    saveWindowState(self)
  end)
  f:SetScript("OnSizeChanged", function(self)
    saveWindowState(self)
    if ns.ApplyWindowVisuals then ns.ApplyWindowVisuals(addon) end
    if self:IsShown() then
      ns.RefreshListWindow(addon)
    end
  end)

  local function TintButtonTextures(btn, color, alphaScale)
    if not (btn and btn.GetRegions and color) then return end
    local a = (color[4] or 1) * (alphaScale or 1)
    for _, r in ipairs({ btn:GetRegions() }) do
      if r and r.GetObjectType and r:GetObjectType() == "Texture" and r.SetVertexColor then
        r:SetVertexColor(color[1] or 1, color[2] or 1, color[3] or 1, a)
      end
    end
  end

  local function TintScrollBarTextures(sb, color)
    if not (sb and color) then return end
    local a = color[4] or 1
    for _, r in ipairs({ sb:GetRegions() }) do
      if r and r.GetObjectType and r:GetObjectType() == "Texture" and r.SetVertexColor then
        r:SetVertexColor(color[1] or 1, color[2] or 1, color[3] or 1, a)
      end
    end

    if sb.ThumbTexture and sb.ThumbTexture.SetVertexColor then
      sb.ThumbTexture:SetVertexColor(color[1] or 1, color[2] or 1, color[3] or 1, a)
    end
    if sb.TrackBG and sb.TrackBG.SetVertexColor then
      sb.TrackBG:SetVertexColor(color[1] or 1, color[2] or 1, color[3] or 1, math.min(1, a * 0.4))
    end

    local up = sb.ScrollUpButton or (sb.GetName and _G[sb:GetName() .. "ScrollUpButton"]) or nil
    local down = sb.ScrollDownButton or (sb.GetName and _G[sb:GetName() .. "ScrollDownButton"]) or nil
    for _, b in ipairs({ up, down }) do
      if b then
        for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
          local fn = b[getter]
          if fn then
            local t = fn(b)
            if t and t.SetVertexColor then
              t:SetVertexColor(color[1] or 1, color[2] or 1, color[3] or 1, a)
            end
          end
        end
      end
    end
  end

  local function ApplyBackground(name)
    ApplyMediaTexture(f.BG, name or "Solid")
  end

  local function ApplyWindowVisuals()
    local v = GetVisualOrDefault(addon)
    ApplyBackground(v.backgroundMedia or "Solid")

    local bg = v.backgroundColor or { 0.09, 0.09, 0.10, 0.25 }
    local border = v.borderColor or { 0.75, 0.75, 0.78, 1 }
    local scroll = v.scrollbarColor or border
    local tabs = v.titleTabColor or { 0.20, 0.20, 0.22, 0.92 }
    local buttons = v.buttonColor or tabs

    if v.showRoundedBorder == false then
      f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        tile = false,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
      })
    else
      f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = false,
        edgeSize = 16,
        insets = { left = 5, right = 5, top = 5, bottom = 5 },
      })
    end
    f:SetBackdropColor(0, 0, 0, 0)
    f:SetBackdropBorderColor(border[1] or 1, border[2] or 1, border[3] or 1, border[4] or 1)

    if f.BG then f.BG:SetVertexColor(bg[1] or 1, bg[2] or 1, bg[3] or 1, bg[4] or 1) end
    if f.TopBar then f.TopBar:SetColorTexture(tabs[1] or 1, tabs[2] or 1, tabs[3] or 1, math.max(0, (tabs[4] or 1) * 0.8)) end
    if f.TitleBar then f.TitleBar:SetColorTexture(tabs[1] or 1, tabs[2] or 1, tabs[3] or 1, tabs[4] or 1) end
    if f.Divider then f.Divider:SetColorTexture(border[1] or 1, border[2] or 1, border[3] or 1, 0.7) end

    TintButtonTextures(f.RecipesTab, buttons, 1)
    TintButtonTextures(f.ReagentsTab, buttons, 1)
    TintButtonTextures(f.SortN, buttons, 1)
    TintButtonTextures(f.SortR, buttons, 1)
    TintButtonTextures(f.SortE, buttons, 1)
    TintButtonTextures(f.SortS, buttons, 1)
    TintScrollBarTextures(f.Scroll and (f.Scroll.ScrollBar or f.Scroll.scrollBar), scroll)
  end

  ns.ApplyWindowVisuals = function(owner)
    if owner and owner ~= addon then return end
    ApplyWindowVisuals()
  end

  f.Inset = CreateFrame("Frame", nil, f)
  f.Inset:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
  f.Inset:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
  f.Inset:SetFrameStrata(f:GetFrameStrata())
  f.Inset:SetFrameLevel(math.max(1, f:GetFrameLevel() - 1))

  local bgParent = f.Inset
  f.BG = bgParent:CreateTexture(nil, "BACKGROUND", nil, -8)
  f.BG:SetDrawLayer("BACKGROUND", -8)
  f.BG:SetPoint("TOPLEFT", bgParent, "TOPLEFT", 0, 0)
  f.BG:SetPoint("BOTTOMRIGHT", bgParent, "BOTTOMRIGHT", 0, 0)
  f.BG:SetBlendMode("BLEND")

  f.TopBar = f:CreateTexture(nil, "BACKGROUND", nil, -1)
  f.TopBar:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -28)
  f.TopBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -28)
  f.TopBar:SetHeight(50)
  f.TopBar:SetDrawLayer("BACKGROUND", -1)

  f.TitleBar = f:CreateTexture(nil, "BACKGROUND", nil, 0)
  f.TitleBar:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
  f.TitleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
  f.TitleBar:SetHeight(20)
  f.TitleBar:SetDrawLayer("BACKGROUND", 0)
  f.TitleBar:SetColorTexture(0.15, 0.15, 0.17, 0.95)

  f.Title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.Title:SetPoint("CENTER", f.TitleBar, "CENTER", 0, 0)
  f.Title:SetText(L["ADDON_NAME"])

  f.CloseButton = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  f.CloseButton:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)

  ApplyWindowVisuals()

  -- Bottom-right resize grip.
  f.ResizeGrip = CreateFrame("Button", nil, f)
  f.ResizeGrip:SetSize(16, 16)
  f.ResizeGrip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 6)
  f.ResizeGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  f.ResizeGrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  f.ResizeGrip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  f.ResizeGrip:SetScript("OnMouseDown", function()
    f:StartSizing("BOTTOMRIGHT")
  end)
  f.ResizeGrip:SetScript("OnMouseUp", function()
    f:StopMovingOrSizing()
    saveWindowState(f)
  end)

  f:Hide()

  -- Tabs
  f.RecipesTab = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  f.RecipesTab:SetSize(90, 22)
  f.RecipesTab:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -30)
  f.RecipesTab:SetText(L["RECIPES"])

  f.ReagentsTab = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  f.ReagentsTab:SetSize(90, 22)
  f.ReagentsTab:SetPoint("LEFT", f.RecipesTab, "RIGHT", 6, 0)
  f.ReagentsTab:SetText(L["REAGENTS"])

  local function setView(view)
    addon.db.profile.window.view = view
    addon:MarkDirty("display")
    if view == "reagents" and addon.cache and addon.cache._reagentsStale then
      return
    end
    ns.RefreshListWindow(addon)
  end

  f.RecipesTab:SetScript("OnClick", function() setView("recipes") end)
  f.ReagentsTab:SetScript("OnClick", function() setView("reagents") end)

  -- Include alts checkbox
  f.Alts = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
  f.Alts:SetPoint("LEFT", f.ReagentsTab, "RIGHT", 12, 0)
  f.Alts.text:SetText(L["INCLUDE_ALTS"])
  f.Alts:SetChecked(addon.db.profile.includeAlts)
  f.Alts:SetScript("OnClick", function(self)
      addon.db.profile.includeAlts = self:GetChecked() and true or false

      -- If a refresh is already pending, cancel it so the toggle always takes effect immediately.
      if addon.refreshTimer then
        addon:CancelTimer(addon.refreshTimer)
        addon.refreshTimer = nil
      end

      -- Mark + apply immediately (or defer until combat ends)
      -- Reset scroll so toggling doesn't leave you staring at a blank region
      do
        local sb = f.Scroll and (f.Scroll.ScrollBar or f.Scroll.scrollBar)
        if sb and sb.SetValue then sb:SetValue(0) end
      end

      -- Mark + apply immediately (or defer until combat ends)
      addon:MarkDirty("full")
      if addon.inCombat then
        addon.repaintAfterCombat = true
      else
        ns.RecomputeCaches(addon)
        ns.RefreshListWindow(addon)
      end
    end)

  -- Reagent sort buttons: N R E S
  f.SortBar = CreateFrame("Frame", nil, f)
  f.SortBar:SetSize(120, 18)
  f.SortBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -18, -56)

  local function makeSortBtn(letter, x)
    local b = CreateFrame("Button", nil, f.SortBar, "UIPanelButtonTemplate")
    b:SetSize(24, 18)
    b:SetPoint("LEFT", f.SortBar, "LEFT", x, 0)
    b:SetText(letter)
    b.letter = letter

    b:SetScript("OnClick", function()
      local view = addon.db.profile.window.view or "recipes"
      if view == "recipes" then
        addon.db.profile.window.recipeSort = letter
      else
        addon.db.profile.window.reagentSort = letter
      end
      addon:MarkDirty("display")
    end)

    b:SetScript("OnEnter", function(self)
      local map = {
        N = "Name",
        R = "Rarity",
        E = "Expansion",
        S = "Source",
      }
      local meaning = map[self.letter] or ""
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:AddLine(meaning, 1, 1, 1)
      GameTooltip:Show()
    end)

    b:SetScript("OnLeave", function()
      GameTooltip:Hide()
    end)

    return b
  end
  f.SortN = makeSortBtn("N", 0)
  f.SortR = makeSortBtn("R", 26)
  f.SortE = makeSortBtn("E", 52)
  f.SortS = makeSortBtn("S", 78)

  -- Gear button near close button opens standalone settings window.
  f.SettingsBtn = CreateFrame("Button", nil, f)
  f.SettingsBtn:SetSize(18, 18)
  if f.CloseButton then
    f.SettingsBtn:SetPoint("RIGHT", f.CloseButton, "LEFT", -2, 0)
  else
    f.SettingsBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -28, -6)
  end
  f.SettingsBtn.Icon = f.SettingsBtn:CreateTexture(nil, "ARTWORK")
  f.SettingsBtn.Icon:SetAllPoints()
  f.SettingsBtn.Icon:SetTexture("Interface\\Buttons\\UI-OptionsButton")
  f.SettingsBtn:SetScript("OnClick", function()
    if ns.ShowConfigWindow then
      ns.ShowConfigWindow(addon, true)
    end
  end)
  f.SettingsBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Settings", 1, 1, 1)
    GameTooltip:AddLine("Open style settings", 0.8, 0.8, 0.8)
    GameTooltip:Show()
  end)
  f.SettingsBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

  -- Scroll
  f.Scroll = CreateFrame("ScrollFrame", nil, f, "FauxScrollFrameTemplate")
  f.Scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -78)
  f.Scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -32, 16)
  -- Remove template-owned body textures so frame background media remains visible.
  for _, r in ipairs({ f.Scroll:GetRegions() }) do
    if r and r.GetObjectType and r:GetObjectType() == "Texture" then
---@diagnostic disable-next-line: undefined-field
      if r.SetTexture then r:SetTexture(nil) end
      if r.SetAlpha then r:SetAlpha(0) end
      if r.Hide then r:Hide() end
    end
  end

  f.Divider = f:CreateTexture(nil, "ARTWORK")
  f.Divider:SetPoint("BOTTOMLEFT", f.Scroll, "TOPLEFT", -2, 2)
  f.Divider:SetPoint("BOTTOMRIGHT", f.Scroll, "TOPRIGHT", 2, 2)
  f.Divider:SetHeight(1)
  ApplyWindowVisuals()

  f.Rows = {}
  for i = 1, ROWS_MAX do
    local row = CreateFrame("Button", nil, f)
    row:SetHeight(ROW_H)
    row:SetPoint("LEFT", f, "LEFT", 18, 0)
    row:SetPoint("RIGHT", f, "RIGHT", -36, 0)

    if i == 1 then
      row:SetPoint("TOP", f.Scroll, "TOP", 0, 0)
    else
      row:SetPoint("TOP", f.Rows[i - 1], "BOTTOM", 0, 0)
    end

    -- Icon + text, icon = profession icon or item icons
	  row.StatusIcon = row:CreateTexture(nil, "ARTWORK")
	  row.StatusIcon:SetSize(14, 14)
	
	  row.StatusIcon:Hide()

	  row.Icon = row:CreateTexture(nil, "ARTWORK")
	  row.Icon:SetSize(16, 16)
	  row.Icon:SetPoint("LEFT", row.StatusIcon, "RIGHT", 2, 0)
	  row.Icon:Hide()

    row.QualityIcon = row:CreateTexture(nil, "ARTWORK")
    row.QualityIcon:SetSize(12, 12)
    row.QualityIcon:Hide()

    row.Name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.Name:SetPoint("LEFT", row.Icon, "RIGHT", 4, 0)
    row.Name:SetJustifyH("LEFT")

    row.Val = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.Val:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    row.Val:SetJustifyH("RIGHT")

    row.HeaderShade = row:CreateTexture(nil, "BACKGROUND")
    row.HeaderShade:SetTexture("Interface\\Buttons\\WHITE8x8")
    row.HeaderShade:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -1)
    row.HeaderShade:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 1)
    row.HeaderShade:SetColorTexture(0.04, 0.08, 0.18, 0.32)
    row.HeaderShade:Hide()

    row.HeaderLine = row:CreateTexture(nil, "ARTWORK")
    row.HeaderLine:SetTexture("Interface\\Buttons\\WHITE8x8")
    row.HeaderLine:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    row.HeaderLine:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    row.HeaderLine:SetHeight(1)
    row.HeaderLine:SetColorTexture(0.82, 0.66, 0.10, 0.72)
    row.HeaderLine:Hide()

-- Tooltip
    row:SetScript("OnEnter", function(self)
      if not self.data then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:ClearLines()

      if self.data.isHeader then
        GameTooltip:AddLine(self.data.name or "", 1, 1, 1)
        GameTooltip:Show()
        return
      end

      local view = addon.db.profile.window.view or "recipes"

      -- Reagents: show item tooltip + counts (keep existing info)
      if view == "reagents" and self.data.itemID then
        local tooltipItemID = (self.data.tooltipItemID)
          or self.data.itemID
        GameTooltip:SetItemByID(tooltipItemID)
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine(L["HAVE"], tostring(self.data.have or 0), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine(L["NEED"], tostring(self.data.need or 0), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine(L["REMAINING"], tostring(self.data.remaining or 0), 1, 1, 1, 1, 1, 1)

        if ns.GetTrackedItemBreakdown then
          local owners, warbank = ns.GetTrackedItemBreakdown(addon, self.data.baseItemID or self.data.itemID, self.data.tierItemIDs)
          if (#owners > 0) or (type(warbank) == "table" and (warbank.total or 0) > 0) then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L["OWNERSHIP_BREAKDOWN"] or "Ownership Breakdown", 1, 0.82, 0)

            if type(warbank) == "table" and (warbank.total or 0) > 0 then
              GameTooltip:AddDoubleLine(
                L["WARBANK"] or "Warbank",
                (ns.Data.FormatReagentQualityBreakdown and ns.Data.FormatReagentQualityBreakdown(warbank, self.data.tierItemIDs)) or tostring((warbank and warbank.total) or 0),
                1, 1, 1, 0.9, 0.9, 0.9
              )
            end

            for _, info in ipairs(owners) do
              local label = ColorizeCharacterName(info.charName or info.charKey or "?", info.classToken)
              local value = (ns.Data.FormatReagentQualityBreakdown and ns.Data.FormatReagentQualityBreakdown(info.counts, self.data.tierItemIDs))
                or tostring((info.counts and info.counts.total) or 0)
              GameTooltip:AddDoubleLine(label, value, 1, 1, 1, 0.9, 0.9, 0.9)
            end
          end
        end

      else
        -- Recipes: show crafted item tooltip
        GameTooltip:AddLine(self.data.name or "", 1, 1, 1)

        if view == "recipes" and self.data.recipeID then
          local outID = self.data.outputItemID or self.data.itemID
          if outID then
            GameTooltip:AddLine(" ")
            GameTooltip:SetItemByID(outID)
          end

          local goal = ns.Recipes and ns.Recipes.GetGoalForRecipe and ns.Recipes.GetGoalForRecipe(addon, self.data.recipeID) or nil
          if goal and outID then
            local qualityMode, targetQuality = ns.Recipes.GetGoalQualityTracking(goal)
            local have = ns.Recipes.GetTrackedHaveCount(addon, goal, outID)
            local breakdown = ns.Recipes.GetGoalQualityBreakdown(addon, goal, outID)
            GameTooltip:AddLine(" ")

            if qualityMode == "specific" and targetQuality then
              local qualityLabel = ns.Data.GetProfessionCraftingQualityLabel(targetQuality) or tostring(targetQuality)
              GameTooltip:AddDoubleLine(
                L["QUALITY"] or "Quality",
                string.format("%s (%d)", qualityLabel, have or 0),
                1, 1, 1, 1, 0.82, 0
              )
            else
              GameTooltip:AddDoubleLine(
                L["QUALITY"] or "Quality",
                string.format(
                  "%s (%d) | %s (%d) | %s (%d)",
                  ns.Data.GetProfessionCraftingQualityLabel(1) or "Bronze", breakdown[1] or 0,
                  ns.Data.GetProfessionCraftingQualityLabel(2) or "Silver", breakdown[2] or 0,
                  ns.Data.GetProfessionCraftingQualityLabel(3) or "Gold", breakdown[3] or 0
                ),
                1, 1, 1, 0.9, 0.9, 0.9
              )
            end

            GameTooltip:AddDoubleLine(L["HAVE"], tostring(have or 0), 1, 1, 1, 1, 1, 1)
            GameTooltip:AddDoubleLine(L["NEED"], tostring(goal.qty or self.data.need or 0), 1, 1, 1, 1, 1, 1)
            GameTooltip:AddDoubleLine(L["REMAINING"], tostring(goal.remaining or self.data.remaining or 0), 1, 1, 1, 1, 1, 1)
          end
        end
      end

      -- Shared "Made with profession" line (recipes + reagents)
      if self.data.profession then
        local p = self.data.profession
        local profName = (type(p) == "table" and (p.name or p.text)) or p

        -- Single icon source (no fallbacks): row-provided icon, else profession table icon
        local profIcon = self.data.professionIcon
        if not profIcon and type(p) == "table" then
          profIcon = p.icon
        end

        local learned = false
        if self.data.recipeID then
          learned = ns.IsRecipeLearned(addon, self.data.recipeID) and true or false
        end

        local statusText, r, g, b
        if learned then
          statusText = "Recipe Learned"
          r, g, b = 0.2, 1.0, 0.2
        else
          statusText = "Recipe Not Learned"
          r, g, b = 1.0, 0.2, 0.2
        end

        local scrollIcon = "Interface\\ICONS\\INV_Scroll_03"
        GameTooltip:AddLine(" ")
        if profIcon then
          GameTooltip:AddLine(
            ("|T%s:16:16:0:0|t Made with |T%s:16:16:0:0|t %s (%s)"):format(scrollIcon, profIcon, tostring(profName or ""), statusText),
            r, g, b
          )
        else
          GameTooltip:AddLine(
            ("|T%s:16:16:0:0|t Made with %s (%s)"):format(scrollIcon, tostring(profName or ""), statusText),
            r, g, b
          )
        end
      end

      -- Help text for recipe rows (recipes view only)
      if view == "recipes" and self.data.recipeID then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(ICON_SHIFT .. " " .. ICON_RMB .. " Open recipe", 0.8, 0.8, 0.8)
        GameTooltip:AddLine(ICON_SHIFT .. " " .. ICON_LMB .. " Link recipe", 0.8, 0.8, 0.8)
        GameTooltip:AddLine(ICON_CTRL  .. " " .. ICON_LMB .. " Add 1 to this recipe", 0.8, 0.8, 0.8)
        GameTooltip:AddLine(ICON_CTRL  .. " " .. ICON_RMB .. " Remove 1 from this recipe", 0.8, 0.8, 0.8)
        GameTooltip:AddLine(ICON_ALT   .. " " .. ICON_RMB .. " Attempt to craft", 0.8, 0.8, 0.8)
      end

      GameTooltip:Show()
    end)

    row:SetScript("OnLeave", function()
      GameTooltip:Hide()
    end)

    -- Clicks: header collapse + modifiers for recipes
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", function(self, button)
      local d = self.data
      if not d then return end

      local view = addon.db.profile.window.view or "recipes"

      -- Header click: collapse/expand (recipes + reagents)
      if d.isHeader then
        local key = d.groupKey or d.profession or d.name
        if not key then return end

        addon.db.profile.window.collapsed = addon.db.profile.window.collapsed or {}
        addon.db.profile.window.collapsed[key] = not addon.db.profile.window.collapsed[key]
        addon:MarkDirty("display")
        return
      end

      if view ~= "recipes" then return end

      local rid = d.recipeID
      if not rid then return end

      -- Priority: ALT > CTRL > SHIFT
      if IsAltKeyDown() then
        -- Alt + Right: attempt craft (current character, UI-dependent)
        if button ~= "RightButton" then return end
        if ns.TryCraftRecipe then
          ns.TryCraftRecipe(addon, rid)
        end
        return
      end

      if IsControlKeyDown() then
        -- Ctrl + Left: Add 1, Ctrl + Right: Remove 1
        if button == "LeftButton" then
          ns.SetGoalForRecipe(addon, rid, 1)
        elseif button == "RightButton" then
          ns.SetGoalForRecipe(addon, rid, -1)
        else
          return
        end
        return
      end

      if IsShiftKeyDown() then
        -- Shift + Right: open recipe/profession, Shift + Left: link recipe
        if button == "RightButton" then
          if ns.OpenRecipeIfPossible then
            ns.OpenRecipeIfPossible(addon, rid)
          end
        elseif button == "LeftButton" then
          if ns.LinkRecipe then
            ns.LinkRecipe(rid, addon)
          end
        end
        return
      end
    end)

    f.Rows[i] = row
  end

  f.Scroll:SetScript("OnVerticalScroll", function(self, offset)
    FauxScrollFrame_OnVerticalScroll(self, offset, ROW_H, function()
      ns.RefreshListWindow(addon)
    end)
  end)
end

function ns.ShowListWindow(addon, show)
  local f = ns.ListWindow
  if not f then return end

  if show then
    local view = addon and addon.db and addon.db.profile and addon.db.profile.window and addon.db.profile.window.view or "recipes"
    local hasRecipes = addon and addon.cache and addon.cache.recipesDisplay and #addon.cache.recipesDisplay > 0
    local hasReagents = addon and addon.cache and addon.cache.reagentsDisplay and #addon.cache.reagentsDisplay > 0
    local hasRenderableCache = (view == "recipes" and hasRecipes) or (view == "reagents" and hasReagents)

    ns.ApplyWindowStateFromDB(addon)
    f:Show()

    if hasRenderableCache then
      ns.RefreshListWindow(addon)
    else
      addon:MarkDirty("full")
    end
  else
    f:Hide()
  end
end

local function GetHeaderIcon(view, entry)
  local isProfHeader = false
  if view == "recipes" then
    isProfHeader = (entry.groupKey and entry.groupKey:match("^PROF:")) or (type(entry.profession) == "string" and entry.profession ~= "")
  elseif view == "reagents" then
    isProfHeader = (type(entry.profession) == "string" and entry.profession ~= "" and entry.profession:match("^PROF:"))
  end

  if not isProfHeader then
    return nil
  end

  local profName
  if view == "recipes" and entry.groupKey and entry.groupKey:match("^PROF:") then
    profName = entry.name
  elseif type(entry.profession) == "string" and entry.profession ~= "" then
    profName = entry.profession:gsub("^PROF:", "")
  end

  if profName and ns.GetProfessionInfo then
    local pInfo = ns.GetProfessionInfo(profName)
    return pInfo and pInfo.icon or nil
  end

  return nil
end

local function RenderHeaderRow(row, entry, view, cHeader, collapsedMap)
  row.StatusIcon:Hide()
  row.QualityIcon:Hide()
  row.HeaderShade:Show()
  row.HeaderLine:Show()

  local headerIcon = GetHeaderIcon(view, entry)

  row.Icon:ClearAllPoints()
  row.Icon:SetPoint("LEFT", row, "LEFT", 2, 0)
  row.Name:ClearAllPoints()

  if headerIcon then
    row.Icon:SetTexture(headerIcon)
    row.Icon:Show()
    row.Name:SetPoint("LEFT", row.Icon, "RIGHT", 4, 0)
  else
    row.Icon:Hide()
    row.Name:SetPoint("LEFT", row, "LEFT", 2, 0)
  end

  local key = entry.groupKey or entry.profession or entry.name
  local collapsed = collapsedMap and collapsedMap[key]
  local prefix = collapsed and "+ " or "- "
  local headerName = (entry.name or ""):gsub("^%s+", "")

  row.Name:SetText(prefix .. headerName)
  row.Val:SetText("")
  row.Name:SetTextColor(cHeader[1] or 1, cHeader[2] or 0.82, cHeader[3] or 0, cHeader[4] or 1)
  row.Val:SetTextColor(1, 1, 1, 1)
end

local function RenderDataRow(row, entry, view, addon)
  local ITEM_INDENT = 12
  local indentPx = 12
  local LEFT_GAP = 4
  row.HeaderShade:Hide()
  row.HeaderLine:Hide()

  row.Icon:ClearAllPoints()
  row.QualityIcon:ClearAllPoints()
  row.StatusIcon:ClearAllPoints()

  local tex
  if entry.icon then
    tex = entry.icon
  elseif view == "reagents" and entry.itemID then
    tex = C_Item.GetItemIconByID(entry.itemID)
  elseif view == "recipes" and entry.outputItemID then
    tex = C_Item.GetItemIconByID(entry.outputItemID)
  elseif entry.iconTexture then
    tex = entry.iconTexture
  end

  local isUnknownRecipe = (view == "recipes" and entry.recipeID and entry.learned == false)

  if view == "reagents" and entry.isComplete then
    row.StatusIcon:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    row.StatusIcon:Show()
    row.StatusIcon:SetPoint("RIGHT", row, "RIGHT", -22, 0)
  else
    row.StatusIcon:Hide()
  end

  if tex then
    row.Icon:SetTexture(tex)
    row.Icon:Show()
  else
    row.Icon:Hide()
  end

  local showQualityIcon = ApplyQualityIcon(row.QualityIcon, entry.targetQuality)

  row.Name:ClearAllPoints()
  if view == "recipes" then
    local iconLeft = 2 + ITEM_INDENT
    local markerWidth = 18
    row.Icon:SetPoint("LEFT", row, "LEFT", iconLeft + markerWidth, 0)

    if isUnknownRecipe then
      row.StatusIcon:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")
      row.StatusIcon:SetPoint("LEFT", row, "LEFT", iconLeft, 0)
      row.StatusIcon:Show()
    else
      row.StatusIcon:Hide()
    end

    if row.Icon:IsShown() then
      row.Name:SetPoint("LEFT", row.Icon, "RIGHT", LEFT_GAP + indentPx, 0)
    else
      row.Name:SetPoint("LEFT", row, "LEFT", iconLeft + markerWidth + indentPx, 0)
    end
  elseif view == "reagents" and row.Icon:IsShown() then
    local itemLeft = 2 + ITEM_INDENT + 16
    row.Icon:SetPoint("LEFT", row, "LEFT", itemLeft, 0)
    if showQualityIcon then
      row.QualityIcon:SetPoint("RIGHT", row.Icon, "LEFT", -LEFT_GAP, 0)
      row.Name:SetPoint("LEFT", row.Icon, "RIGHT", LEFT_GAP + indentPx, 0)
    else
      row.QualityIcon:Hide()
      row.Name:SetPoint("LEFT", row.Icon, "RIGHT", LEFT_GAP + indentPx, 0)
    end
  elseif row.Icon:IsShown() then
    row.Icon:SetPoint("LEFT", row, "LEFT", 2 + ITEM_INDENT, 0)
    row.Name:SetPoint("LEFT", row.Icon, "RIGHT", LEFT_GAP + indentPx, 0)
  else
    row.Name:SetPoint("LEFT", row, "LEFT", 2 + indentPx, 0)
  end

  row.Name:SetText(entry.name or "")

  if view == "recipes" and showQualityIcon then
    local nameWidth = row.Name:GetStringWidth() or 0
    row.QualityIcon:SetPoint("LEFT", row.Name, "LEFT", nameWidth + 6, 0)
  end

  if view ~= "reagents" and not isUnknownRecipe then
    row.StatusIcon:SetPoint("RIGHT", row, "RIGHT", -10, 0)
  end
  row.Val:SetText(tostring(entry.remaining or 0))

  local isZero = (entry.remaining or 0) <= 0
  if isZero then
    row.Name:SetTextColor(0.5, 0.5, 0.5, 1)
    row.Val:SetTextColor(0.5, 0.5, 0.5, 1)
  else
    local nr, ng, nb = 1, 1, 1
    if type(entry.rarity) == "number" and entry.rarity >= 0 and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[entry.rarity] then
      local qc = ITEM_QUALITY_COLORS[entry.rarity]
      nr, ng, nb = qc.r or 1, qc.g or 1, qc.b or 1
    end
    row.Name:SetTextColor(nr, ng, nb, 1)
    row.Val:SetTextColor(1, 1, 1, 1)
  end
end

function ns.RefreshListWindow(addon)
  local startedAt = NowSeconds()
  EnsureDefaults(addon)
  local f = ns.ListWindow
  if not f then return end
  if not (f.RecipesTab and f.ReagentsTab and f.Alts and f.SortBar and f.Scroll and f.Rows) then return end

  local view = addon.db.profile.window.view or "recipes"
  local visual = GetVisualOrDefault(addon)
  local textSize = tonumber(visual.textSize) or 10
  local fontName = visual.textFont or "Friz Quadrata TT"
  local lsm = GetLSM()
  local fontPath = (lsm and lsm:Fetch("font", fontName, true)) or STANDARD_TEXT_FONT
  local fontFlags = (visual.textOutline == false) and "" or "OUTLINE"
  local fontSignature = table.concat({ tostring(fontPath), tostring(textSize), tostring(fontFlags) }, "\31")
  local cHeader = (visual.textColor and visual.textColor.header) or { 1, 0.82, 0, 1 }
  local collapsedMap = addon.db.profile.window and addon.db.profile.window.collapsed

  f.RecipesTab:SetEnabled(view ~= "recipes")
  f.ReagentsTab:SetEnabled(view ~= "reagents")
  f.Alts:SetChecked(addon.db.profile.includeAlts)

  -- Sort bar visible on Recipes + Reagents views
  f.SortBar:Show()

  if view == "recipes" then
    -- Only N/E apply to recipes
    f.SortN:Show()
    f.SortE:Show()
    f.SortR:Hide()
    f.SortS:Hide()

    local mode = addon.db.profile.window.recipeSort or "N"
    f.SortN:SetEnabled(mode ~= "N")
    f.SortE:SetEnabled(mode ~= "E")

  elseif view == "reagents" then
    -- N/R/E/S apply to reagents
    f.SortN:Show()
    f.SortR:Show()
    f.SortE:Show()
    f.SortS:Show()

    local mode = addon.db.profile.window.reagentSort or "E"
    f.SortN:SetEnabled(mode ~= "N")
    f.SortR:SetEnabled(mode ~= "R")
    f.SortE:SetEnabled(mode ~= "E")
    f.SortS:SetEnabled(mode ~= "S")
  end

  local data, total
  if view == "recipes" then
    data = addon.cache and addon.cache.recipesDisplay or {}
    total = #data
  else
    data = addon.cache and addon.cache.reagentsDisplay or {}
    total = #data
  end

  local visibleRows = GetVisibleRows(f)
  FauxScrollFrame_Update(f.Scroll, total, visibleRows, ROW_H)

  local offset = FauxScrollFrame_GetOffset(f.Scroll) or 0
  local maxOffset = math.max(0, (total or 0) - visibleRows)

  -- Clamp offset so the list can't "blank" when the dataset shrinks/grows
  if offset > maxOffset then
    offset = 0
    local sb = f.Scroll.ScrollBar or f.Scroll.scrollBar
    if sb and sb.SetValue then
      sb:SetValue(0)
    end
    FauxScrollFrame_Update(f.Scroll, total, visibleRows, ROW_H)
  end

  for i = 1, ROWS_MAX do
    local row = f.Rows[i]
    if row._dslFontSignature ~= fontSignature then
      row.Name:SetFont(fontPath, textSize, fontFlags)
      row.Val:SetFont(fontPath, textSize, fontFlags)
      row._dslFontSignature = fontSignature
    end

    if i > visibleRows then
      row.data = nil
      row.HeaderShade:Hide()
      row.HeaderLine:Hide()
      row:Hide()
    else
    local idx = i + offset
    local entry = data[idx]
    row.data = entry

    if not entry then
      row.HeaderShade:Hide()
      row.HeaderLine:Hide()
      row:Hide()
    else
      row:Show()

      if entry.isHeader then
        RenderHeaderRow(row, entry, view, cHeader, collapsedMap)
      else
        RenderDataRow(row, entry, view, addon)
      end
    end
    end
  end

  local elapsed = (NowSeconds() - startedAt) * 1000
  if addon and addon.Print and elapsed >= 8 then
    addon._dslPerfReport = addon._dslPerfReport or {}
    local lastAt = addon._dslPerfReport["list repaint"] or 0
    local now = NowSeconds()
    if (now - lastAt) >= 1.0 then
      addon._dslPerfReport["list repaint"] = now
      addon:Print(string.format("DSL perf: list repaint %.1fms", elapsed))
    end
  end
end
