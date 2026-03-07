-- ListWindow.lua

local _, ns = ...
ns = ns or {}
local L = LibStub("AceLocale-3.0"):GetLocale("DecorShoppingList")
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

local ROWS_MAX = 60
local ROW_H = 22

-- Small inline icons for tooltips
local ICON_LMB = "|A:newplayertutorial-icon-mouse-leftbutton:14:14|a"
local ICON_RMB = "|A:newplayertutorial-icon-mouse-rightbutton:14:14|a"
local ICON_SHIFT = "|cffffd100SHIFT|r"
local ICON_CTRL  = "|cffffd100CTRL|r"
local ICON_ALT   = "|cffffd100ALT|r"

local function GetVisibleRows(f)
  local scroll = f and f.Scroll
  local h = scroll and scroll.GetHeight and scroll:GetHeight() or 0
  local rows = math.floor((h / ROW_H) + 0.0001)
  if rows < 1 then rows = 1 end
  if rows > ROWS_MAX then rows = ROWS_MAX end
  return rows
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

  local bgPath = (LSM and LSM:Fetch("background", media, true)) or "Interface\\Buttons\\WHITE8x8"
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

  local function getVisual()
    local fallback = {
      backgroundMedia = "Solid",
      backgroundColor = { 0.09, 0.09, 0.10, 0.25 },
      borderColor = { 0.75, 0.75, 0.78, 1 },
      scrollbarColor = { 0.75, 0.75, 0.78, 1 },
      titleTabColor = { 0.20, 0.20, 0.22, 0.92 },
      showRoundedBorder = true,
    }
    return (ns.GetVisualSettings and ns.GetVisualSettings(addon)) or fallback
  end

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
    local v = getVisual()
    ApplyBackground(v.backgroundMedia or "Solid")

    local bg = v.backgroundColor or { 0.09, 0.09, 0.10, 0.25 }
    local border = v.borderColor or { 0.75, 0.75, 0.78, 1 }
    local scroll = v.scrollbarColor or border
    local tabs = v.titleTabColor or { 0.20, 0.20, 0.22, 0.92 }

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

    TintButtonTextures(f.RecipesTab, tabs, 1)
    TintButtonTextures(f.ReagentsTab, tabs, 1)
    TintButtonTextures(f.SortN, tabs, 1)
    TintButtonTextures(f.SortR, tabs, 1)
    TintButtonTextures(f.SortE, tabs, 1)
    TintButtonTextures(f.SortS, tabs, 1)
    TintScrollBarTextures(f.Scroll and (f.Scroll.ScrollBar or f.Scroll.scrollBar), scroll)
  end

  ns.ApplyWindowVisuals = function(owner)
    if owner and owner ~= addon then return end
    ApplyWindowVisuals()
  end

  f.Inset = CreateFrame("Frame", nil, f)
  f.Inset:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -26)
  f.Inset:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 6)

  local bgParent = f.Inset
  f.BG = bgParent:CreateTexture(nil, "ARTWORK", nil, 7)
  f.BG:SetDrawLayer("BACKGROUND", 1)
  if bgParent == f.Inset then
    f.BG:SetPoint("TOPLEFT", bgParent, "TOPLEFT", 4, -4)
    f.BG:SetPoint("BOTTOMRIGHT", bgParent, "BOTTOMRIGHT", -4, 4)
  else
    f.BG:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -30)
    f.BG:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 10)
  end
  f.BG:SetBlendMode("BLEND")

  f.TopBar = f:CreateTexture(nil, "ARTWORK", nil, -1)
  f.TopBar:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -28)
  f.TopBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -28)
  f.TopBar:SetHeight(50)

  f.TitleBar = f:CreateTexture(nil, "ARTWORK")
  f.TitleBar:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -6)
  f.TitleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)
  f.TitleBar:SetHeight(20)
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
    ns.RefreshListWindow(addon)
  end

  f.RecipesTab:SetScript("OnClick", function() setView("recipes") end)
  f.ReagentsTab:SetScript("OnClick", function() setView("reagents") end)

  -- Include alts checkbox
  f.Alts = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
  f.Alts:ClearAllPoints()
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

    -- Icon + text
	  row.StatusIcon = row:CreateTexture(nil, "ARTWORK")
	  row.StatusIcon:SetSize(14, 14)
	  row.StatusIcon:SetPoint("LEFT", row, "LEFT", 2, 0)
	  row.StatusIcon:Hide()

	  row.Icon = row:CreateTexture(nil, "ARTWORK")
	  row.Icon:SetSize(16, 16)
	  row.Icon:SetPoint("LEFT", row.StatusIcon, "RIGHT", 2, 0)
	  row.Icon:Hide()

    row.Name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.Name:SetPoint("LEFT", row.Icon, "RIGHT", 4, 0)
    row.Name:SetJustifyH("LEFT")

    row.Val = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.Val:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    row.Val:SetJustifyH("RIGHT")

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
        GameTooltip:SetItemByID(self.data.itemID)
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine(L["HAVE"], tostring(self.data.have or 0), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine(L["NEED"], tostring(self.data.need or 0), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine(L["REMAINING"], tostring(self.data.remaining or 0), 1, 1, 1, 1, 1, 1)

      else
        -- Recipes: show crafted item tooltip
        GameTooltip:AddLine(self.data.name or "", 1, 1, 1)

        if view == "recipes" and self.data.recipeID then
          local outID = self.data.outputItemID or self.data.itemID
          if outID then
            GameTooltip:AddLine(" ")
            GameTooltip:SetItemByID(outID)
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
        addon:MarkDirty("full")
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

  ns.RefreshListWindow(addon)
end

function ns.ShowListWindow(addon, show)
  local f = ns.ListWindow
  if not f then return end

  if show then
    ns.ApplyWindowStateFromDB(addon)
    f:Show()
    addon:MarkDirty("display")
  else
    f:Hide()
  end
end

function ns.RefreshListWindow(addon)
  EnsureDefaults(addon)
  local f = ns.ListWindow
  if not f then return end
  if not (f.RecipesTab and f.ReagentsTab and f.Alts and f.SortBar and f.Scroll and f.Rows) then return end

  local view = addon.db.profile.window.view or "recipes"
  local visual = (ns.GetVisualSettings and ns.GetVisualSettings(addon)) or {}
  local textSize = tonumber(visual.textSize) or 10
  local fontName = visual.textFont or "Friz Quadrata TT"
  local fontPath = (LSM and LSM:Fetch("font", fontName, true)) or STANDARD_TEXT_FONT
  local fontFlags = (visual.textOutline == false) and "" or "OUTLINE"
  local cHeader = (visual.textColor and visual.textColor.header) or { 1, 0.82, 0, 1 }

  f.RecipesTab:SetEnabled(view ~= "recipes")
  f.ReagentsTab:SetEnabled(view ~= "reagents")
  f.Alts:SetChecked(addon.db.profile.includeAlts)

  -- Sort bar visible on Recipes + Reagents views
  f.SortBar:SetShown(view == "reagents" or view == "recipes")

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
    row.Name:SetFont(fontPath, textSize, fontFlags)
    row.Val:SetFont(fontPath, textSize, fontFlags)

    if i > visibleRows then
      row.data = nil
      row:Hide()
    else
    local idx = i + offset
    local entry = data[idx]
    row.data = entry

    if not entry then
      row:Hide()
    else
      row:Show()

      if entry.isHeader then
        row.StatusIcon:Hide()

        -- Header icon: ONLY show for profession headers (not expansion/source/etc.)
        local isProfHeader = false
        if view == "recipes" then
          isProfHeader = (entry.groupKey and entry.groupKey:match("^PROF:")) or (type(entry.profession) == "string" and entry.profession ~= "")
        elseif view == "reagents" then
          isProfHeader = (type(entry.profession) == "string" and entry.profession ~= "" and entry.profession:match("^PROF:"))
        end

        local headerIcon
        local profName

        if isProfHeader then
          if view == "recipes" and entry.groupKey and entry.groupKey:match("^PROF:") then
            profName = entry.name
          elseif type(entry.profession) == "string" and entry.profession ~= "" then
            profName = entry.profession:gsub("^PROF:", "")
          end

          if profName and ns.GetProfessionInfo then
            local pInfo = ns.GetProfessionInfo(profName)
            headerIcon = pInfo and pInfo.icon or nil
          end
        end

        -- Headers should NEVER appear indented: force icon + name anchors flush-left
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
        local collapsed = addon.db.profile.window
          and addon.db.profile.window.collapsed
          and addon.db.profile.window.collapsed[key]

        local prefix = collapsed and "+ " or "- "
        local headerName = (entry.name or ""):gsub("^%s+", "")
        row.Name:SetText(prefix .. headerName)
        row.Val:SetText("")
        row.Name:SetTextColor(cHeader[1] or 1, cHeader[2] or 0.82, cHeader[3] or 0, cHeader[4] or 1)
        row.Val:SetTextColor(1, 1, 1, 1)

      else
        -- Non-headers: items are ALWAYS indented (including the icon)
        local ITEM_INDENT = 12

        row.Icon:ClearAllPoints()
        row.Icon:SetPoint("LEFT", row, "LEFT", 2 + ITEM_INDENT, 0)

        row.StatusIcon:ClearAllPoints()
        row.StatusIcon:SetPoint("RIGHT", row, "RIGHT", -4, 0)

        row.Name:ClearAllPoints()

        -- Icon selection
        local tex
        if view == "reagents" and entry.itemID then
          tex = C_Item.GetItemIconByID(entry.itemID)
        elseif view == "recipes" and entry.outputItemID then
          tex = C_Item.GetItemIconByID(entry.outputItemID)
        elseif entry.iconTexture then
          tex = entry.iconTexture
        end

        -- Status icon (reagents view only): show check when complete
        if view == "reagents" and entry.isComplete then
          row.StatusIcon:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
          row.StatusIcon:Show()
        else
          row.StatusIcon:Hide()
        end

        if tex then
          row.Icon:SetTexture(tex)
          row.Icon:Show()
        else
          row.Icon:Hide()
        end

        -- Name: items ALWAYS have one fixed indent (headers never do)
        local indentPx = 12

        row.Name:ClearAllPoints()
        if row.Icon:IsShown() then
          row.Name:SetPoint("LEFT", row.Icon, "RIGHT", 4 + indentPx, 0)
        else
          row.Name:SetPoint("LEFT", row, "LEFT", 2 + indentPx, 0)
        end

        if view == "recipes" and entry.recipeID and (not ns.IsRecipeLearned(addon, entry.recipeID)) then
          row.Name:SetText("|TInterface\\RaidFrame\\ReadyCheck-NotReady:14:14|t " .. (entry.name or ""))
        else
          row.Name:SetText(entry.name or "")
        end

        row.Val:SetText(tostring(entry.remaining or 0))

        local isZero = (entry.remaining or 0) <= 0
        if isZero then
          row.Name:SetTextColor(0.5, 0.5, 0.5, 1)
          row.Val:SetTextColor(0.5, 0.5, 0.5, 1)
        else
          row.Name:SetTextColor(1, 1, 1, 1)
          row.Val:SetTextColor(1, 1, 1, 1)
        end
      end
    end
    end
  end
end
