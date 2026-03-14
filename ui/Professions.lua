-- DecorShoppingList/Professions.lua
local ADDON, ns = ...
ns = ns or {}

local L = LibStub("AceLocale-3.0"):GetLocale("DecorShoppingList")

-- Single, deterministic profession icons (no API lookups)
local PROF_ICON = {
  Alchemy        = "Interface\\ICONS\\Trade_Alchemy",
  Blacksmithing  = "Interface\\ICONS\\Trade_BlackSmithing",
  Enchanting     = "Interface\\ICONS\\Trade_Engraving",
  Engineering    = "Interface\\ICONS\\Trade_Engineering",
  Inscription    = "Interface\\ICONS\\INV_Inscription_Tradeskill01",
  Jewelcrafting  = "Interface\\ICONS\\INV_Misc_Gem_01",
  Leatherworking = "Interface\\ICONS\\Trade_LeatherWorking",
  Tailoring      = "Interface\\ICONS\\Trade_Tailoring",
  Cooking        = "Interface\\ICONS\\INV_Misc_Food_15",
  Fishing        = "Interface\\ICONS\\Trade_Fishing",
  Herbalism      = "Interface\\ICONS\\Trade_Herbalism",
  Mining         = "Interface\\ICONS\\Trade_Mining",
  Skinning       = "Interface\\ICONS\\INV_Misc_Pelt_Wolf_01",
}

function ns.GetProfessionInfo(profName)
  profName = tostring(profName or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if profName == "" then return nil end
  return { name = profName, icon = PROF_ICON[profName] }
end

-- Tracks the last recipe the player viewed/selected in any professions UI (normal or linked)
local currentRecipeID = nil
local RefreshTrackWidget
local QueueProfessionWidgetRefresh
local HookSchematicForm
local QUALITY_ATLAS_CANDIDATES = {
  [1] = { "Professions-Icon-Quality-Tier1-Small", "Professions-Icon-Quality-Tier1" },
  [2] = { "Professions-Icon-Quality-Tier2-Small", "Professions-Icon-Quality-Tier2" },
  [3] = { "Professions-Icon-Quality-Tier3-Small", "Professions-Icon-Quality-Tier3" },
}
local QUALITY_ACCENT = {
  [1] = { 0.78, 0.54, 0.30 },
  [2] = { 0.78, 0.78, 0.82 },
  [3] = { 1.00, 0.82, 0.20 },
}

local function GetCurrentTrackedGoal(addon, recipeID)
  return ns.Recipes and ns.Recipes.GetGoalForRecipe and ns.Recipes.GetGoalForRecipe(addon, recipeID) or nil
end

local function GetGoalQualityTracking(goal)
  if ns.Recipes and ns.Recipes.GetGoalQualityTracking then
    return ns.Recipes.GetGoalQualityTracking(goal)
  end
  return "any", nil
end

local function GetRecipeOutputItemID(recipeID)
  if not recipeID then return nil end
  return ns.GetRecipeOutputItemID and ns.GetRecipeOutputItemID(recipeID) or nil
end

local function SetTrackButtonText(btn, qty)
  if not (btn and btn.SetText) then return end
  if (qty or 0) > 0 then
    btn:SetText("Update")
  else
    btn:SetText(L["TRACK"] or "Track")
  end
end

local function PositionTrackWidget(sf, w)
  if not (sf and w) then return end
  w:ClearAllPoints()

  local createBtn = sf.CreateButton
      or (_G.ProfessionsFrame and _G.ProfessionsFrame.CraftingPage and _G.ProfessionsFrame.CraftingPage.CreateButton)
      or (_G.TradeSkillFrame and _G.TradeSkillFrame.CreateButton)

  if createBtn then
    if w.Track then
      w:SetPoint("BOTTOMRIGHT", createBtn, "TOPRIGHT", 0, 8)
    else
      w:SetPoint("BOTTOM", createBtn, "TOP", 0, 8)
    end
  else
    if w.Track then
      w:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", -12, 12)
    else
      w:SetPoint("BOTTOM", sf, "BOTTOM", 0, 12)
    end
  end
end

local function GetCurrentTrackedQty(addon, recipeID)
  local g = GetCurrentTrackedGoal(addon, recipeID)
  return (type(g) == "table" and tonumber(g.qty)) or 0
end

local function UpdateQualityButtons(w)
  if not (w and w.QualityButtons) then return end

  local enabled = (w._dslQualityEnabled == true)
  for quality, button in ipairs(w.QualityButtons) do
    if button.SetEnabled then
      button:SetEnabled(enabled)
    end
    if enabled and quality == w._dslDraftTargetQuality then
      button:LockHighlight()
      if button.Selected then
        local color = QUALITY_ACCENT[quality] or QUALITY_ACCENT[3]
        button.Selected:SetVertexColor(color[1], color[2], color[3], 0.22)
        button.Selected:Show()
      end
    else
      button:UnlockHighlight()
      if button.Selected then
        button.Selected:Hide()
      end
    end

    if button.Icon then
      button.Icon:SetAlpha(enabled and 1 or 0.45)
    end
  end

  if w.QualityCheck then
    w.QualityCheck:SetChecked(enabled)
  end
end

local function ApplyQualityButtonArt(button, quality)
  if not button then return end

  local icon = button.Icon
  local atlasApplied = false
  if icon and icon.SetAtlas then
    for _, atlas in ipairs(QUALITY_ATLAS_CANDIDATES[quality] or {}) do
      if icon:SetAtlas(atlas, true) then
        atlasApplied = true
        break
      end
    end
  end

  if atlasApplied then
    button:SetText("")
    icon:Show()
  else
    button:SetText(tostring(quality))
    if icon then
      icon:Hide()
    end
  end
end

local function SyncQualityControls(w, recipeID, goal)
  local itemID = (type(goal) == "table" and goal.itemID) or GetRecipeOutputItemID(recipeID)
  local isDecor = itemID and ns.Data.IsDecorItem(itemID) or false
  local qualityMode, targetQuality = GetGoalQualityTracking(goal)

  if w._dslDraftUseQuality == nil then
    w._dslDraftUseQuality = (qualityMode == "specific")
  end
  if w._dslDraftTargetQuality == nil then
    w._dslDraftTargetQuality = targetQuality or 3
  end

  if isDecor then
    w._dslDraftUseQuality = false
  end

  w._dslDraftTargetQuality = ns.Data.NormalizeProfessionCraftingQuality(w._dslDraftTargetQuality) or 3
  w._dslQualityEnabled = (not isDecor) and (w._dslDraftUseQuality == true)

  if w.QualityCheck then
    w.QualityCheck:SetEnabled(not isDecor)
  end

  if w.QualityLabel then
    if isDecor then
      w.QualityLabel:SetText(L["DECOR_ANY_QUALITY"] or "Decor item: any quality")
    else
      w.QualityLabel:SetText(L["USE_REAGENT_QUALITY"] or "Use Reagent Quality")
    end
  end

  UpdateQualityButtons(w)
end

-- -------------------------
-- Event hook (best-effort)
-- -------------------------

local function ensureRecipeEventHook()
  if ns._dslRecipeEventFrame then return end

  local f = CreateFrame("Frame")
  f:RegisterEvent("OPEN_RECIPE_RESPONSE")     -- often fires in normal mode
  f:RegisterEvent("TRADE_SKILL_SHOW")         -- profession UI opened
  f:RegisterEvent("TRADE_SKILL_LIST_UPDATE")  -- recipe selection changed / schematic refreshed
  f:RegisterEvent("TRADE_SKILL_CLOSE")

  local function syncTrackWidget()
    local addon = ns._dslAddonRef
    if not addon then return end
    if addon.inCombat or InCombatLockdown() then return end
    if ns._dslTryAttachTrackWidget then
      ns._dslTryAttachTrackWidget()
    end

    if addon._dslRecipeScanTimer then return end
    addon._dslRecipeScanTimer = addon:ScheduleTimer(function()
      addon._dslRecipeScanTimer = nil

      -- scan learned->true for THIS character only
      local changed = false
      if ns.ScanCurrentProfessionLearned then
        changed = ns.ScanCurrentProfessionLearned(addon) and true or false
      end

      RefreshTrackWidget(addon)
      if changed then
        addon:MarkDirty("full")
      end
    end, 0.05)
  end

  local function refreshWidgetOnly()
    local addon = ns._dslAddonRef
    if not addon then return end
    QueueProfessionWidgetRefresh(addon, 0.05, false)
  end

  f:SetScript("OnEvent", function(_, event, recipeID)
    if event == "OPEN_RECIPE_RESPONSE" then
      if type(recipeID) == "number" then
        currentRecipeID = recipeID
      end
      syncTrackWidget()
      return
    end

    if event == "TRADE_SKILL_SHOW" then
      syncTrackWidget()
      return
    end

    if event == "TRADE_SKILL_LIST_UPDATE" then
      refreshWidgetOnly()
      return
    end

    -- TRADE_SKILL_CLOSE
    currentRecipeID = nil
  end)

  ns._dslRecipeEventFrame = f
end

-- -------------------------
-- Find active schematic form
-- -------------------------

local function GetActiveSchematicForm()
  -- Modern Professions UI (player's own)
  if _G.ProfessionsFrame and _G.ProfessionsFrame.CraftingPage and _G.ProfessionsFrame.CraftingPage.SchematicForm then
    return _G.ProfessionsFrame.CraftingPage.SchematicForm
  end

  -- Linked Trade Skill UI (guild/community / linked professions)
  if _G.TradeSkillFrame and _G.TradeSkillFrame.DetailsFrame and _G.TradeSkillFrame.DetailsFrame.SchematicForm then
    return _G.TradeSkillFrame.DetailsFrame.SchematicForm
  end

  return nil
end

QueueProfessionWidgetRefresh = function(addon, delay, clearRecipeID)
  if not addon then return end
  if addon.inCombat or InCombatLockdown() then return end
  if clearRecipeID then
    currentRecipeID = nil
  end
  if addon._dslWidgetRefreshTimer then
    addon:CancelTimer(addon._dslWidgetRefreshTimer)
  end
  addon._dslWidgetRefreshTimer = addon:ScheduleTimer(function()
    addon._dslWidgetRefreshTimer = nil
    if addon.inCombat or InCombatLockdown() then return end
    if ns._dslTryAttachTrackWidget then
      ns._dslTryAttachTrackWidget()
    end
    RefreshTrackWidget(addon)
  end, delay or 0.05)
end

HookSchematicForm = function(sf, addon)
  if not (sf and addon) then return end
  if sf._dslTrackHooksInstalled then return end
  sf._dslTrackHooksInstalled = true

  local function onRecipeChanged(self)
    local rid = nil
    if type(self.GetRecipeInfo) == "function" then
      local ok, info = pcall(self.GetRecipeInfo, self)
      if ok and type(info) == "table" and type(info.recipeID) == "number" and info.recipeID > 0 then
        rid = info.recipeID
      end
    end
    if not rid and type(self.recipeID) == "number" and self.recipeID > 0 then
      rid = self.recipeID
    end
    currentRecipeID = rid
    QueueProfessionWidgetRefresh(addon, 0.01, not rid)
  end

  for _, methodName in ipairs({ "SetRecipeInfo", "Init", "Refresh", "UpdateDetailsForRecipe" }) do
    if type(sf[methodName]) == "function" then
      hooksecurefunc(sf, methodName, onRecipeChanged)
    end
  end

  sf:HookScript("OnShow", function(self)
    onRecipeChanged(self)
  end)
end

local function GetSelectedRecipeID()
  local sf = GetActiveSchematicForm()
  if sf and type(sf.GetRecipeInfo) == "function" then
    local ok, info = pcall(sf.GetRecipeInfo, sf)
    if ok and type(info) == "table" and type(info.recipeID) == "number" then
      currentRecipeID = info.recipeID
      return info.recipeID
    end
  end

  if C_TradeSkillUI and C_TradeSkillUI.GetSelectedRecipeID then
    local ok, rid = pcall(C_TradeSkillUI.GetSelectedRecipeID)
    if ok and type(rid) == "number" and rid > 0 then
      currentRecipeID = rid
      return rid
    end
  end
  return currentRecipeID
end

RefreshTrackWidget = function(addon)
  local sf = GetActiveSchematicForm()
  local w = sf and sf.DSL_TrackWidget
  if not w or not w.Qty then return end

  local rid = GetSelectedRecipeID()
  local cur = GetCurrentTrackedQty(addon, rid)
  local selectedChanged = (w._dslLastRecipeID ~= rid)
  w._dslLastRecipeID = rid
  local goal = GetCurrentTrackedGoal(addon, rid)

  if selectedChanged then
    w._dslDraftQty = nil
    w._dslDraftUseQuality = nil
    w._dslDraftTargetQuality = nil
    w.Qty:SetNumber(cur)
  elseif not (w.Qty.HasFocus and w.Qty:HasFocus()) then
    if w._dslDraftQty ~= nil then
      w.Qty:SetNumber(w._dslDraftQty)
    else
      w.Qty:SetNumber(cur)
    end
  end

  if w.Track and w.Track.SetText then
    SetTrackButtonText(w.Track, cur)
  end

  SyncQualityControls(w, rid, goal)
end

local function IsAnyProfessionUIOpen()
  return (_G.ProfessionsFrame and _G.ProfessionsFrame:IsShown())
      or (_G.TradeSkillFrame and _G.TradeSkillFrame:IsShown())
end

local function GetSkillLineIDForRecipe(recipeID)
  if not recipeID then return nil end
  if not C_TradeSkillUI then return nil end

  if C_TradeSkillUI.GetTradeSkillLineForRecipe then
    local ok, skillLineID = pcall(C_TradeSkillUI.GetTradeSkillLineForRecipe, recipeID)
    if ok and type(skillLineID) == "number" and skillLineID > 0 then
      return skillLineID
    end
  end

  if C_TradeSkillUI.GetRecipeSchematic then
    local ok, schematic = pcall(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
    local skillLineID = ok and schematic and schematic.tradeSkillLineID
    if type(skillLineID) == "number" and skillLineID > 0 then
      return skillLineID
    end
  end

  if C_TradeSkillUI.GetRecipeInfo then
    local ok, info = pcall(C_TradeSkillUI.GetRecipeInfo, recipeID)
    local skillLineID = ok and info and info.tradeSkillLineID
    if type(skillLineID) == "number" and skillLineID > 0 then
      return skillLineID
    end
  end

  return nil
end

local function OpenProfessionForRecipe(addon, recipeID)
  local skillLineID = GetSkillLineIDForRecipe(recipeID)
  if not skillLineID then return false end
  if not (C_TradeSkillUI and C_TradeSkillUI.OpenTradeSkill) then return false end

  local ok = pcall(C_TradeSkillUI.OpenTradeSkill, skillLineID)
  if ok then return true end

  if addon and addon.Print then
    addon:Print("Couldn't open the profession for that recipe.")
  end
  return false
end

local function OpenRecipeNow(recipeID)
  if not recipeID then return false end

  if C_TradeSkillUI and C_TradeSkillUI.OpenRecipe then
    local ok = pcall(C_TradeSkillUI.OpenRecipe, recipeID)
    if ok then return true end
  end

  local sf = GetActiveSchematicForm()
  if sf and sf.SetRecipeID then
    local ok = pcall(sf.SetRecipeID, sf, recipeID)
    if ok then return true end
  end

  return false
end

local function TryInsertLinkToChat(link)
  if type(link) ~= "string" or link == "" then return false end

  if ChatEdit_InsertLink and ChatEdit_InsertLink(link) then
    return true
  end

  local editBox = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
  if editBox and editBox.Insert then
    editBox:Insert(link)
    return true
  end

  if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
    DEFAULT_CHAT_FRAME:AddMessage(link)
    return true
  end

  return false
end

-- Shift + Left: insert recipe link into chat (or print in chat fallback).
function ns.LinkRecipe(recipeID, addon)
  if not recipeID then return false end
  if not (C_TradeSkillUI and C_TradeSkillUI.GetRecipeLink) then
    if addon and addon.Print then addon:Print("Recipe linking is not available right now.") end
    return false
  end

  local ok, link = pcall(C_TradeSkillUI.GetRecipeLink, recipeID)
  if not ok or type(link) ~= "string" or link == "" then
    if addon and addon.Print then addon:Print("Couldn't build a recipe link for that entry.") end
    return false
  end

  if TryInsertLinkToChat(link) then
    return true
  end

  if addon and addon.Print then addon:Print("Open chat first to insert the recipe link.") end
  return false
end

-- Shift + Right: open/highlight recipe in the active profession UI when possible.
function ns.OpenRecipeIfPossible(addon, recipeID)
  if not recipeID then return false end
  if OpenRecipeNow(recipeID) then return true end

  if not OpenProfessionForRecipe(addon, recipeID) then
    if addon and addon.Print then addon:Print("Couldn't open that recipe right now.") end
    return false
  end

  if addon and addon.ScheduleTimer then
    addon:ScheduleTimer(function()
      OpenRecipeNow(recipeID)
    end, 0.25)
  end

  return true
end

function ns.TryCraftRecipe(addon, recipeID, attempt)
  if not recipeID then return false end
  attempt = tonumber(attempt) or 0

  if not IsAnyProfessionUIOpen() then
    if OpenProfessionForRecipe(addon, recipeID) and addon and addon.ScheduleTimer and attempt < 3 then
      addon:ScheduleTimer(function()
        ns.TryCraftRecipe(addon, recipeID, attempt + 1)
      end, 0.35)
      return true
    end
    if addon and addon.Print then addon:Print("Open your profession window to craft this recipe.") end
    return false
  end

  OpenRecipeNow(recipeID)

  if C_TradeSkillUI and C_TradeSkillUI.CraftRecipe then
    local ok = pcall(C_TradeSkillUI.CraftRecipe, recipeID, 1)
    if ok then return true end
  end

  if addon and addon.ScheduleTimer and attempt < 3 then
    addon:ScheduleTimer(function()
      ns.TryCraftRecipe(addon, recipeID, attempt + 1)
    end, 0.25)
    return true
  end

  if addon and addon.Print then addon:Print("Couldn't start crafting that recipe.") end
  return false
end

-- -------------------------
-- Track widget
-- -------------------------

local function makeTrackWidget(parent, addon)
  local w = CreateFrame("Frame", nil, parent)
  w:SetSize(500, 26)

  -- Track (apply qty)
  w.Track = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
  w.Track:SetSize(70, 24)
  w.Track:SetPoint("RIGHT", w, "RIGHT", 0, 0)
  SetTrackButtonText(w.Track, 0)

  -- Qty
  w.Qty = CreateFrame("EditBox", nil, w, "InputBoxTemplate")
  w.Qty:SetSize(44, 24)
  w.Qty:SetPoint("RIGHT", w.Track, "LEFT", -4, 0)
  w.Qty:SetAutoFocus(false)
  w.Qty:SetNumeric(true)
  w.Qty:SetNumber(0)

  w.QualityCheck = CreateFrame("CheckButton", nil, w, "UICheckButtonTemplate")
  w.QualityCheck:SetPoint("LEFT", w, "LEFT", -6, 0)

  w.QualityLabel = w:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  w.QualityLabel:SetPoint("LEFT", w.QualityCheck, "RIGHT", -2, 0)
  w.QualityLabel:SetJustifyH("LEFT")
  w.QualityLabel:SetText(L["USE_REAGENT_QUALITY"] or "Use Reagent Quality")

  w.QualityButtons = {}
  for quality = 1, 3 do
    local b = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
    b:SetSize(28, 20)
    b.Icon = b:CreateTexture(nil, "ARTWORK")
    b.Icon:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.Icon:SetSize(16, 16)
    b.Selected = b:CreateTexture(nil, "BACKGROUND")
    b.Selected:SetTexture("Interface\\Buttons\\WHITE8X8")
    b.Selected:SetPoint("TOPLEFT", b, "TOPLEFT", 3, -3)
    b.Selected:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -3, 3)
    b.Selected:Hide()
    ApplyQualityButtonArt(b, quality)
    b:SetScript("OnClick", function()
      w._dslDraftTargetQuality = quality
      UpdateQualityButtons(w)
    end)
    b:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:AddLine(ns.Data.GetProfessionCraftingQualityLabel(quality) or tostring(quality), 1, 1, 1)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function()
      GameTooltip:Hide()
    end)
    w.QualityButtons[quality] = b
  end

  w.QualityButtons[1]:ClearAllPoints()
  w.QualityButtons[2]:ClearAllPoints()
  w.QualityButtons[3]:ClearAllPoints()
  w.QualityButtons[3]:SetPoint("RIGHT", w.Qty, "LEFT", -8, 0)
  w.QualityButtons[2]:SetPoint("RIGHT", w.QualityButtons[3], "LEFT", -2, 0)
  w.QualityButtons[1]:SetPoint("RIGHT", w.QualityButtons[2], "LEFT", -2, 0)

  w.QualityLabel:ClearAllPoints()
  w.QualityLabel:SetPoint("RIGHT", w.QualityButtons[1], "LEFT", -8, 0)
  w.QualityCheck:ClearAllPoints()
  w.QualityCheck:SetPoint("RIGHT", w.QualityLabel, "LEFT", 0, 0)

  w.QualityCheck:SetScript("OnClick", function(self)
    w._dslDraftUseQuality = self:GetChecked() and true or false
    if w._dslDraftUseQuality and not ns.Data.NormalizeProfessionCraftingQuality(w._dslDraftTargetQuality) then
      w._dslDraftTargetQuality = 3
    end
    w._dslQualityEnabled = w._dslDraftUseQuality == true
    UpdateQualityButtons(w)
  end)

  local function getQtyAllowZero()
    local n = tonumber(w.Qty:GetText() or "")
    if n == nil then return nil end
    n = math.floor(n)
    if n < 0 then return nil end
    return n
  end

  local function readDraftQty()
    local n = getQtyAllowZero()
    if n == nil then
      w._dslDraftQty = nil
      return nil
    end
    w._dslDraftQty = n
    return n
  end

  -- Works in both normal and linked mode.
  w.Qty:SetScript("OnTextChanged", function(_, userInput)
    if not userInput then return end
    readDraftQty()
  end)
  w.Qty:SetScript("OnEditFocusLost", function()
    local n = readDraftQty()
    if n ~= nil then
      w.Qty:SetNumber(n)
    end
  end)
  w.Qty:SetScript("OnEnterPressed", function()
    w.Track:Click()
  end)

  w.Track:SetScript("OnClick", function()
    local q = w._dslDraftQty
    if q == nil then
      q = getQtyAllowZero()
    end
    if q == nil then addon:Print(L["INVALID_QTY"]); return end

    local rid = GetSelectedRecipeID()
    if not rid then addon:Print(L["NO_RECIPE_SELECTED"]); return end

    local goal = GetCurrentTrackedGoal(addon, rid)
    local cur = GetCurrentTrackedQty(addon, rid)
    local delta = q - cur
    local itemID = (goal and goal.itemID) or GetRecipeOutputItemID(rid)
    local isDecor = itemID and ns.Data.IsDecorItem(itemID) or false
    local qualityMode = (not isDecor and w._dslDraftUseQuality) and "specific" or "any"
    local targetQuality = (qualityMode == "specific") and (ns.Data.NormalizeProfessionCraftingQuality(w._dslDraftTargetQuality) or 3) or nil
    local prevMode, prevTarget = GetGoalQualityTracking(goal)

    if delta == 0 and prevMode == qualityMode and prevTarget == targetQuality then
      return
    end

    ns.SetGoalForRecipe(addon, rid, delta, {
      qualityMode = qualityMode,
      targetQuality = targetQuality,
    })
    w._dslDraftQty = nil
    w.Qty:SetNumber(q)
    SetTrackButtonText(w.Track, q)
    RefreshTrackWidget(addon)
  end)

  return w
end

-- -------------------------
-- Init / attach
-- -------------------------

function ns.InitProfessions(addon)
  ns._dslAddonRef = addon
  ensureRecipeEventHook()

  local function tryAttach()
    local sf = GetActiveSchematicForm()
    if not sf then return false end

    if sf.DSL_TrackWidget then
      HookSchematicForm(sf, addon)
      PositionTrackWidget(sf, sf.DSL_TrackWidget)
      RefreshTrackWidget(addon)
      return true
    end

    local w = makeTrackWidget(sf, addon)
    HookSchematicForm(sf, addon)
    PositionTrackWidget(sf, w)
    sf.DSL_TrackWidget = w
    RefreshTrackWidget(addon)

    return true
  end

  ns._dslTryAttachTrackWidget = tryAttach

  -- Try now and again shortly (UI may load later)
  if not tryAttach() then
    addon:ScheduleTimer(tryAttach, 2.0)
    addon:ScheduleTimer(tryAttach, 5.0)
  end
end
