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
  w:SetSize(140, 26)

  -- Qty
  w.Qty = CreateFrame("EditBox", nil, w, "InputBoxTemplate")
  w.Qty:SetSize(44, 24)
  w.Qty:SetPoint("LEFT", w, "LEFT", 0, 0)
  w.Qty:SetAutoFocus(false)
  w.Qty:SetNumeric(true)
  w.Qty:SetNumber(1)

  -- Track (apply qty)
  w.Track = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
  w.Track:SetSize(70, 24)
  w.Track:SetPoint("LEFT", w.Qty, "RIGHT", 6, 0)
  w.Track:SetText(L["TRACK"] or "Track")

  local function getQtyAllowZero()
    local n = tonumber(w.Qty:GetText() or "")
    if n == nil then return nil end
    n = math.floor(n)
    if n < 0 then return nil end
    return n
  end

  local function getCurrentTrackedQty(addon, recipeID)
    local goals = addon.db and addon.db.profile and addon.db.profile.goals
    if not goals then return 0 end
    local g = goals["r:" .. tostring(recipeID)]
    return (type(g) == "table" and tonumber(g.qty)) or 0
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
    return currentRecipeID
  end

  w.Track:SetScript("OnClick", function()
    local q = getQtyAllowZero()
    if q == nil then addon:Print(L["INVALID_QTY"]); return end

    local rid = getSelectedRecipeID()
    if not rid then addon:Print(L["NO_RECIPE_SELECTED"]); return end

    local cur = getCurrentTrackedQty(addon, rid)
    local delta = q - cur
    if delta == 0 then return end

    ns.SetGoalForRecipe(addon, rid, delta)
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
