--  DecorShoppingList/Core.lua
local ADDON, ns = ...
ns = ns or {}
local L = LibStub("AceLocale-3.0"):GetLocale("DecorShoppingList")

local DSL = LibStub("AceAddon-3.0"):NewAddon("DecorShoppingList", "AceEvent-3.0", "AceConsole-3.0", "AceTimer-3.0")
ns.DSL = DSL

local defaults = {
  profile = {
    window = {
      point="CENTER", relPoint="CENTER", x=0, y=0, w=360, h=420,
      minimized=false,
      view="recipes",

      -- ADD THESE:
      reagentSort = "E",
      collapsed = {},
    },
    minimap = { hide = false },
    includeAlts = false,
    visual = {
      textOutline = true,
      textSize = 10,
      textFont = "Friz Quadrata TT",
      textColor = {
        header = { 1, 0.82, 0, 1 },
      },
      borderColor = { 0.75, 0.75, 0.78, 1 },
      backgroundColor = { 0.09, 0.09, 0.10, 0.25 },
      scrollbarColor = { 0.75, 0.75, 0.78, 1 },
      titleTabColor = { 0.20, 0.20, 0.22, 0.92 },
      showRoundedBorder = true,
      backgroundMedia = "Solid",
    },

    goals = {},
    recipeByItem = {},
    metaByItem = {},
  },
  global = {
    realms = {}
  }
}

local function NewDirtyFlags()
  return { full = false, inventory = false, display = false }
end

local function HasDirtyFlags(flags)
  return flags and (flags.full or flags.inventory or flags.display)
end

local function SnapshotNow(addon)
  ns.SnapshotCurrentCharacter(addon)
  addon._dslLastSnapshot = GetTime()
end

local function SnapshotIfStale(addon, seconds)
  local threshold = seconds or 0.15
  if not addon._dslLastSnapshot or (GetTime() - addon._dslLastSnapshot) > threshold then
    SnapshotNow(addon)
  end
end

local function HandleInventorySnapshotEvent(addon)
  if addon.inCombat then
    addon.dirty = true
    return
  end

  SnapshotNow(addon)
  addon:MarkDirty("inventory")
end

function DSL:OnInitialize()
  self.db = LibStub("AceDB-3.0"):New("DecorShoppingListDB", defaults, true)

  -- One-time fix: wipe any bad collapsed state so newly-created profession groups actually show
  self.db.profile.migrations = self.db.profile.migrations or {}
  if not self.db.profile.migrations.resetCollapsedV1 then
    if self.db.profile.window then
      self.db.profile.window.collapsed = {}
    end
    self.db.profile.migrations.resetCollapsedV1 = true
  end

  self.inCombat = InCombatLockdown()
  self.dirty = false
  self.dirtyFlags = NewDirtyFlags()
  self.repaintAfterCombat = false
  self.refreshTimer = nil

  self.lastHave = {} -- itemID -> last known have (current char only; alt sums computed on demand)

  self:RegisterChatCommand("dsl", "SlashCommand")

  ns.InitListWindow(self)
  if ns.InitConfig then
    ns.InitConfig(self)
  end
  ns.InitProfessions(self)
  ns.InitBroker(self)

  if ns.InitPlugins then
    ns.InitPlugins(self)
  end

  self:MarkDirty("full")
end

function DSL:OnEnable()
  self:RegisterEvent("PLAYER_REGEN_DISABLED")
  self:RegisterEvent("PLAYER_REGEN_ENABLED")
  self:RegisterEvent("PLAYER_LOGOUT", "OnPlayerLogout")

  self:RegisterEvent("BAG_UPDATE_DELAYED", "OnInventoryChanged")
  self:RegisterEvent("BANKFRAME_OPENED", "OnBankOpened")
  self:RegisterEvent("PLAYERBANKSLOTS_CHANGED", "OnInventoryChanged")
  self:RegisterEvent("ITEM_DATA_LOAD_RESULT", "OnItemDataLoaded")
  self:RegisterEvent("TRADE_SKILL_LIST_UPDATE", "OnTradeSkillListUpdate")
  self:RegisterEvent("TRADE_SKILL_SHOW", "OnTradeSkillListUpdate")
  self:RegisterEvent("NEW_RECIPE_LEARNED", "OnTradeSkillListUpdate")
  self:RegisterEvent("SKILL_LINES_CHANGED", "OnTradeSkillListUpdate")
  self:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "OnInteractionFrameShow")
end

function DSL:PLAYER_REGEN_DISABLED()
  self.inCombat = true
end

function DSL:PLAYER_REGEN_ENABLED()
  self.inCombat = false

  local flags = self.dirtyFlags
  if HasDirtyFlags(flags) then
    self:RecomputeAndRefresh()
    return
  end

  if self.repaintAfterCombat then
    self.repaintAfterCombat = false
    if ns.ListWindow and ns.ListWindow:IsShown() then
      ns.RefreshListWindow(self)
    end
  end
end

function DSL:OnBankOpened()
  HandleInventorySnapshotEvent(self)
end

function DSL:OnInventoryChanged()
  HandleInventorySnapshotEvent(self)
end

function DSL:OnInteractionFrameShow(_, interactionType)
  local pit = Enum and Enum.PlayerInteractionType
  if not pit then return end

  if interactionType == pit.AccountBank or interactionType == pit.Banker then
    self:OnBankOpened()
  end
end

function DSL:OnPlayerLogout()
  -- One last snapshot so counts persist across sessions (bank is only captured if it's open)
  if ns.SnapshotCurrentCharacter then
    ns.SnapshotCurrentCharacter(self)
  end
end

function DSL:OnItemDataLoaded()
  if self.inCombat then
    self.repaintAfterCombat = true
    return
  end

  -- Item data arriving can change cached display names/source classification.
  -- Use debounced dirty path instead of repaint-only.
  if ns.ListWindow and ns.ListWindow:IsShown() then
    self:MarkDirty("full")
  end
end

function DSL:OnTradeSkillListUpdate()
  if self.inCombat then
    self.dirtyFlags = self.dirtyFlags or NewDirtyFlags()
    self.dirtyFlags.full = true
    return
  end

  if ns.SnapshotLearnedRecipes and ns.SnapshotLearnedRecipes(self) then
    self:MarkDirty("full")
    return
  end

  -- No learned-state change: avoid full rebuild and refresh display only.
  self:MarkDirty("display")
end

function DSL:MarkDirty(reason)
  self.dirtyFlags = self.dirtyFlags or NewDirtyFlags()

  if reason == "inventory" then
    self.dirtyFlags.inventory = true
  elseif reason == "display" then
    self.dirtyFlags.display = true
  else
    self.dirtyFlags.full = true
  end

  if self.inCombat then return end
  if self.refreshTimer then return end

  self.refreshTimer = self:ScheduleTimer(function()
    self.refreshTimer = nil
    if self.inCombat then return end
    if HasDirtyFlags(self.dirtyFlags) then
      self:RecomputeAndRefresh()
    end
  end, 0.2)
end

function DSL:RecomputeAndRefresh()
  local flags = self.dirtyFlags or NewDirtyFlags()
  self.dirtyFlags = NewDirtyFlags()

  if flags.full then
    -- Full rebuild (goals/learned/display changes)
    SnapshotIfStale(self, 0.15)

    ns.ApplyCompletionByInventoryDelta(self)
    ns.RecomputeCaches(self)
    ns.RefreshListWindow(self)
    return
  end

  if flags.inventory then
    -- Inventory-only refresh: keep recipe/reagent NEEDS, refresh HAVE/remaining/completion
    SnapshotIfStale(self, 0.15)
    ns.ApplyCompletionByInventoryDelta(self)

    if ns.RecomputeReagentsOnly then
      ns.RecomputeReagentsOnly(self)
    else
      ns.RecomputeCaches(self)
    end

    ns.RefreshListWindow(self)
    return
  end

  if flags.display then
    -- Display-only refresh: collapse/sort/view changes should not touch math/state.
    if ns.RecomputeDisplayOnly then
      ns.RecomputeDisplayOnly(self)
    else
      ns.RecomputeCaches(self)
    end
    ns.RefreshListWindow(self)
    return
  end
end

function DSL:SlashCommand(input)
  input = strtrim(input or ""):lower()

  if input == "" or input == "toggle" then
    ns.ShowListWindow(self, not ns.ListWindow:IsShown())
    self:Print(L["SLASH_HELP"])
    return
  elseif input == "show" then
    ns.ShowListWindow(self, true); return
  elseif input == "hide" then
    ns.ShowListWindow(self, false); return
  elseif input == "config" or input == "settings" then
    if ns.ShowConfigWindow then
      ns.ShowConfigWindow(self, true)
    end
    return
  elseif input == "alts" then
    self.db.profile.includeAlts = not self.db.profile.includeAlts
    self:Print((L["INCLUDE_ALTS"] .. ": " .. (self.db.profile.includeAlts and "ON" or "OFF")))
    self:MarkDirty("full")
    return
  elseif input == "reset" then
    local w = self.db.profile.window
    w.point, w.relPoint, w.x, w.y = "CENTER", "CENTER", 0, 0
    self:Print(L["RESET_POS"])
    ns.ApplyWindowStateFromDB(self)
    return
  end

  self:Print(L["SLASH_HELP"])
end
