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
    w:SetPoint("BOTTOM", createBtn, "TOP", 0, 8)
  else
    w:SetPoint("BOTTOM", sf, "BOTTOM", 0, 12)
  end
end

local function GetCurrentTrackedQty(addon, recipeID)
  local goals = addon and addon.db and addon.db.profile and addon.db.profile.goals
  if not goals or not recipeID then return 0 end
  local g = goals["r:" .. tostring(recipeID)]
  return (type(g) == "table" and tonumber(g.qty)) or 0
end

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
    if ns._dslTryAttachTrackWidget then
      ns._dslTryAttachTrackWidget()
    end

    if not addon._dslTrackSyncTicker then
      addon._dslTrackSyncTicker = addon:ScheduleRepeatingTimer(function()
        local shown = (_G.ProfessionsFrame and _G.ProfessionsFrame:IsShown())
            or (_G.TradeSkillFrame and _G.TradeSkillFrame:IsShown())
        if not shown then
          if addon._dslTrackSyncTicker then
            addon:CancelTimer(addon._dslTrackSyncTicker)
            addon._dslTrackSyncTicker = nil
          end
          return
        end
        if ns._dslTryAttachTrackWidget then
          ns._dslTryAttachTrackWidget()
        end
        RefreshTrackWidget(addon)
      end, 0.2)
    end

    -- throttle scan/refresh
    if addon._dslRecipeScanTimer then return end
    addon._dslRecipeScanTimer = addon:ScheduleTimer(function()
      addon._dslRecipeScanTimer = nil

      -- scan learned->true for THIS character only
      if ns.ScanCurrentProfessionLearned then
        ns.ScanCurrentProfessionLearned(addon)
      end

      RefreshTrackWidget(addon)

      -- update list live while the profession window is open
      addon:MarkDirty()
    end, 0.25)
  end

  f:SetScript("OnEvent", function(_, event, recipeID)
    if event == "OPEN_RECIPE_RESPONSE" then
      if type(recipeID) == "number" then
        currentRecipeID = recipeID
      end
      requestScanAndRefresh()
      return
    end

    if event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_LIST_UPDATE" then
      requestScanAndRefresh()
      return
    end

    -- TRADE_SKILL_CLOSE
    currentRecipeID = nil
    local addon = ns._dslAddonRef
    if addon and addon._dslTrackSyncTicker then
      addon:CancelTimer(addon._dslTrackSyncTicker)
      addon._dslTrackSyncTicker = nil
    end
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

local function GetSelectedRecipeID()
  if C_TradeSkillUI and C_TradeSkillUI.GetSelectedRecipeID then
    local ok, rid = pcall(C_TradeSkillUI.GetSelectedRecipeID)
    if ok and type(rid) == "number" and rid > 0 then
      currentRecipeID = rid
      return rid
    end
  end

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

RefreshTrackWidget = function(addon)
  local sf = GetActiveSchematicForm()
  local w = sf and sf.DSL_TrackWidget
  if not w or not w.Qty then return end

  local rid = GetSelectedRecipeID()
  local cur = GetCurrentTrackedQty(addon, rid)
  local selectedChanged = (w._dslLastRecipeID ~= rid)
  w._dslLastRecipeID = rid

  if selectedChanged or (not (w.Qty.HasFocus and w.Qty:HasFocus())) then
    w.Qty:SetNumber(cur)
  end

  if w.Track and w.Track.SetText then
    SetTrackButtonText(w.Track, cur)
  end
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
  w:SetSize(140, 26)

  -- Qty
  w.Qty = CreateFrame("EditBox", nil, w, "InputBoxTemplate")
  w.Qty:SetSize(44, 24)
  w.Qty:SetPoint("LEFT", w, "LEFT", -5, 0)
  w.Qty:SetAutoFocus(false)
  w.Qty:SetNumeric(true)
  w.Qty:SetNumber(0)

  -- Track (apply qty)
  w.Track = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
  w.Track:SetSize(70, 24)
  w.Track:SetPoint("LEFT", w.Qty, "RIGHT", 1, 0)
  SetTrackButtonText(w.Track, 0)

  local function getQtyAllowZero()
    local n = tonumber(w.Qty:GetText() or "")
    if n == nil then return nil end
    n = math.floor(n)
    if n < 0 then return nil end
    return n
  end

  local function getCurrentTrackedQty(addon, recipeID)
    return GetCurrentTrackedQty(addon, recipeID)
  end

  -- Works in both normal and linked mode
  local function getSelectedRecipeID()
    return GetSelectedRecipeID()
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
      PositionTrackWidget(sf, sf.DSL_TrackWidget)
      RefreshTrackWidget(addon)
      return true
    end

    local w = makeTrackWidget(sf, addon)
    PositionTrackWidget(sf, w)
    sf.DSL_TrackWidget = w
    RefreshTrackWidget(addon)

    return true
  end

  ns._dslTryAttachTrackWidget = tryAttach

  -- Try now and again shortly (UI may load later)
  if not tryAttach() then
    addon:ScheduleTimer(function() tryAttach() end, 2.0)
    addon:ScheduleTimer(function() tryAttach() end, 5.0)
  end
end

