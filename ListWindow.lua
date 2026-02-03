-- ListWindow.lua

local ADDON, ns = ...
ns = ns or {}
local L = LibStub("AceLocale-3.0"):GetLocale("DecorShoppingList")

local ROWS = 14
local ROW_H = 22

-- Small inline icons for tooltips
local ICON_LMB = "|A:newplayertutorial-icon-mouse-leftbutton:14:14|a"
local ICON_RMB = "|A:newplayertutorial-icon-mouse-rightbutton:14:14|a"
local ICON_SHIFT = "|cffffd100SHIFT|r"

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
  addon.db.profile.window.collapsed = addon.db.profile.window.collapsed or {}
end

function ns.InitListWindow(addon)
  EnsureDefaults(addon)
  local db = addon.db.profile.window

  local f = CreateFrame("Frame", "DecorShoppingListWindow", UIParent, "UIPanelDialogTemplate")
  ns.ListWindow = f

  f:SetSize(db.w or 360, db.h or 420)
  f:SetPoint(db.point or "CENTER", UIParent, db.relPoint or "CENTER", db.x or 0, db.y or 0)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetClampedToScreen(true)
  f:SetFrameStrata("MEDIUM")

  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint(1)
    local w, h = self:GetSize()
    db.point, db.relPoint, db.x, db.y = point, relPoint, math.floor(x + 0.5), math.floor(y + 0.5)
    db.w, db.h = math.floor(w + 0.5), math.floor(h + 0.5)
  end)

  f:Hide()
  f.Title:SetText(L["ADDON_NAME"])

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
    addon.db.profile.window.reagentSort = letter
    addon:MarkDirty("display")
  end)

  return b
  end

  f.SortN = makeSortBtn("N", 0)
  f.SortR = makeSortBtn("R", 26)
  f.SortE = makeSortBtn("E", 52)
  f.SortS = makeSortBtn("S", 78)

  -- Scroll
  f.Scroll = CreateFrame("ScrollFrame", nil, f, "FauxScrollFrameTemplate")
  f.Scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -78)
  f.Scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -32, 16)

  f.Rows = {}
  for i = 1, ROWS do
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

      if self.data.isHeader then
        GameTooltip:AddLine(self.data.name or "", 1, 1, 1)
        GameTooltip:Show()
        return
      end

      local view = addon.db.profile.window.view or "recipes"

      if view == "reagents" and self.data.itemID then
        GameTooltip:SetItemByID(self.data.itemID)
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine(L["HAVE"], tostring(self.data.have or 0), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine(L["NEED"], tostring(self.data.need or 0), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine(L["REMAINING"], tostring(self.data.remaining or 0), 1, 1, 1, 1, 1, 1)
      else
        GameTooltip:AddLine(self.data.name or "", 1, 1, 1)
        GameTooltip:AddDoubleLine(L["REMAINING"], tostring(self.data.remaining or 0), 1, 1, 1, 1, 1, 1)
      end

      -- Help text for recipe rows (recipes view only)
      if view == "recipes" and self.data.recipeID then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(ICON_SHIFT .. " " .. ICON_LMB .. " Remove 1 from this recipe", 0.8, 0.8, 0.8)
        GameTooltip:AddLine(ICON_SHIFT .. " " .. ICON_RMB .. " Add 1 to this recipe",    0.8, 0.8, 0.8)
      end
      GameTooltip:Show()

    end)

    row:SetScript("OnLeave", function()
      GameTooltip:Hide()
    end)

    -- Clicks: header collapse + shift +/-1 for recipes
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

      -- Shift-click +/-1 on recipe rows
      if view ~= "recipes" then return end
      if not IsShiftKeyDown() then return end

      local rid = d.recipeID
      if not rid then return end

      if button == "LeftButton" then
        ns.SetGoalForRecipe(addon, rid, -1)
      elseif button == "RightButton" then
        ns.SetGoalForRecipe(addon, rid, 1)
      else
        return
      end

      addon:MarkDirty("full")
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

  local view = addon.db.profile.window.view or "recipes"

  f.RecipesTab:SetEnabled(view ~= "recipes")
  f.ReagentsTab:SetEnabled(view ~= "reagents")
  f.Alts:SetChecked(addon.db.profile.includeAlts)

  -- Sort bar only visible on Reagents view
  f.SortBar:SetShown(view == "reagents")

  if view == "reagents" then
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

  FauxScrollFrame_Update(f.Scroll, total, ROWS, ROW_H)

  local offset = FauxScrollFrame_GetOffset(f.Scroll) or 0
  local maxOffset = math.max(0, (total or 0) - ROWS)

  -- Clamp offset so the list can't "blank" when the dataset shrinks/grows
  if offset > maxOffset then
    offset = 0
    local sb = f.Scroll.ScrollBar or f.Scroll.scrollBar
    if sb and sb.SetValue then
      sb:SetValue(0)
    end
    FauxScrollFrame_Update(f.Scroll, total, ROWS, ROW_H)
  end

  for i = 1, ROWS do
    local idx = i + offset
    local row = f.Rows[i]
    local entry = data[idx]
    row.data = entry

    if not entry then
      row:Hide()
    else
      row:Show()

      if entry.isHeader then
	    row.StatusIcon:Hide()
        row.Icon:Hide()

        -- Header text should start at the far left (not after icon)
        row.Name:ClearAllPoints()
        row.Name:SetPoint("LEFT", row, "LEFT", 2, 0)

        local key = entry.groupKey or entry.profession or entry.name
        local collapsed = addon.db.profile.window
          and addon.db.profile.window.collapsed
          and addon.db.profile.window.collapsed[key]

        local prefix = collapsed and "+ " or "- "
        row.Name:SetText(prefix .. (entry.name or ""))
        row.Val:SetText("")
        row.Name:SetTextColor(1, 0.82, 0)
        row.Val:SetTextColor(1, 1, 1)

      else
        -- Non-headers: restore normal anchor (after icon)
        row.Name:ClearAllPoints()
        row.Name:SetPoint("LEFT", row.Icon, "RIGHT", 4, 0)

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

        -- Name (with indent levels for grouped reagent views)
        if view == "recipes" and entry.missing then
          row.Name:SetText("|TInterface\\RaidFrame\\ReadyCheck-NotReady:14:14|t " .. (entry.name or ""))
        else
          local lvl = entry.level or 0
          local indent = string.rep("  ", lvl)
          row.Name:SetText(indent .. (entry.name or ""))
        end

        row.Val:SetText(tostring(entry.remaining or 0))

        local isZero = (entry.remaining or 0) <= 0
        if isZero then
          row.Name:SetTextColor(0.5, 0.5, 0.5)
          row.Val:SetTextColor(0.5, 0.5, 0.5)
        else
          row.Name:SetTextColor(1, 1, 1)
          row.Val:SetTextColor(1, 1, 1)
        end
      end
    end
  end
end
