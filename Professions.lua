-- DecorShoppingList/Professions.lua
local ADDON, ns = ...
ns = ns or {}

local L = LibStub("AceLocale-3.0"):GetLocale("DecorShoppingList")

-- Tracks the last recipe the player viewed/selected in any professions UI (normal or linked)
local currentRecipeID = nil

-- -------------------------
-- Event hook (best-effort)
-- -------------------------

local function ensureRecipeEventHook()
  if ns._dslRecipeEventFrame then return end

  local f = CreateFrame("Frame")
  f:RegisterEvent("OPEN_RECIPE_RESPONSE")     -- often fires in normal mode
  f:RegisterEvent("TRADE_SKILL_SHOW")         -- profession UI opened
  f:RegisterEvent("TRADE_SKILL_LIST_UPDATE")  -- list updates while open
  f:RegisterEvent("TRADE_SKILL_CLOSE")

  local function requestScanAndRefresh()
    local addon = ns._dslAddonRef
    if not addon then return end
    if addon.inCombat or InCombatLockdown() then return end

    -- throttle scan/refresh
    if addon._dslRecipeScanTimer then return end
    addon._dslRecipeScanTimer = addon:ScheduleTimer(function()
      addon._dslRecipeScanTimer = nil

      -- scan learned->true for THIS character only
      if ns.ScanCurrentProfessionLearned then
        ns.ScanCurrentProfessionLearned(addon)
      end

      -- update list live while the profession window is open
      addon:MarkDirty()
    end, 0.25)
  end

  f:SetScript("OnEvent", function(_, event, recipeID)
    if event == "OPEN_RECIPE_RESPONSE" then
      if type(recipeID) == "number" then
        currentRecipeID = recipeID
      end
      return
    end

    if event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_LIST_UPDATE" then
      requestScanAndRefresh()
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

-- -------------------------
-- Track widget
-- -------------------------

local function makeTrackWidget(parent, addon)
  local w = CreateFrame("Frame", nil, parent)
  w:SetSize(210, 26)

  -- Untrack
  w.Untrack = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
  w.Untrack:SetSize(80, 24)
  w.Untrack:SetPoint("LEFT", w, "LEFT", 0, 0)
  w.Untrack:SetText(L["UNTRACK"] or "Untrack")

  -- Qty
  w.Qty = CreateFrame("EditBox", nil, w, "InputBoxTemplate")
  w.Qty:SetSize(44, 24)
  w.Qty:SetPoint("LEFT", w.Untrack, "RIGHT", 6, 0)
  w.Qty:SetAutoFocus(false)
  w.Qty:SetNumeric(true)
  w.Qty:SetNumber(1)

  -- Track
  w.Track = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
  w.Track:SetSize(70, 24)
  w.Track:SetPoint("LEFT", w.Qty, "RIGHT", 6, 0)
  w.Track:SetText(L["TRACK"] or "Track")

  local function getQty()
    local n = tonumber(w.Qty:GetText() or "")
    if not n or n < 1 then return nil end
    return math.floor(n)
  end

  -- Works in both normal and linked mode
  local function getSelectedRecipeID()
    local sf = GetActiveSchematicForm()
    if sf and type(sf.GetRecipeInfo) == "function" then
      local ok, info = pcall(sf.GetRecipeInfo, sf)
      if ok and type(info) == "table" and type(info.recipeID) == "number" then
        currentRecipeID = info.recipeID
        return info.recipeID
      end
    end

    -- Fallback (linked mode / edge cases)
    return currentRecipeID
  end

  w.Track:SetScript("OnClick", function()
    local q = getQty()
    if not q then addon:Print(L["INVALID_QTY"]); return end
    local rid = getSelectedRecipeID()
    if not rid then addon:Print(L["NO_RECIPE_SELECTED"]); return end
    ns.SetGoalForRecipe(addon, rid, q)
  end)

  w.Untrack:SetScript("OnClick", function()
    local q = getQty()
    if not q then addon:Print(L["INVALID_QTY"]); return end
    local rid = getSelectedRecipeID()
    if not rid then addon:Print(L["NO_RECIPE_SELECTED"]); return end
    ns.SetGoalForRecipe(addon, rid, -q)
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
      return true
    end

    local w = makeTrackWidget(sf, addon)
    w:SetPoint("TOPRIGHT", sf, "TOPRIGHT", -18, -40)
    sf.DSL_TrackWidget = w

    return true
  end

  -- Try now and again shortly (UI may load later)
  if not tryAttach() then
    addon:ScheduleTimer(function() tryAttach() end, 2.0)
    addon:ScheduleTimer(function() tryAttach() end, 5.0)
  end
end
