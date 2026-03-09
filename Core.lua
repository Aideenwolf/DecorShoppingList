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

local function FormatLastSeen(ts)
  ts = tonumber(ts) or 0
  if ts <= 0 then
    return "never"
  end
  return date("%Y-%m-%d %H:%M", ts)
end

local function PrintTrackedCharacters(addon)
  if not (addon and ns.GetTrackedCharacters) then return end

  local tracked, realm = ns.GetTrackedCharacters(addon)
  if not tracked or #tracked == 0 then
    addon:Print(string.format(L["TRACKED_NONE"], tostring(realm or "Unknown")))
    return
  end

  addon:Print(string.format(L["TRACKED_HEADER"], tostring(realm or "Unknown"), #tracked))
  for _, info in ipairs(tracked) do
    addon:Print(string.format(
      L["TRACKED_LINE"],
      tostring(info.charKey or "?"),
      FormatLastSeen(info.lastSeen),
      tonumber(info.bagCount) or 0,
      tonumber(info.bankCount) or 0,
      tonumber(info.recipeCount) or 0
    ))
  end
end

local function ResetCountData(addon)
  if not (addon and addon.db and addon.db.profile and addon.db.global) then return end

  local realms = addon.db.global.realms
  if type(realms) == "table" then
    for _, realmData in pairs(realms) do
      if type(realmData) == "table" then
        realmData.warbank = {}
        realmData.warbankByQuality = {}

        local chars = realmData.chars
        if type(chars) == "table" then
          for charKey, entry in pairs(chars) do
            if type(entry) == "table" then
              chars[charKey] = {
                recipes = entry.recipes or {},
                profs = entry.profs or {},
                lastSeen = entry.lastSeen or 0,
                lastRecipeScan = entry.lastRecipeScan or 0,
                className = entry.className,
                classToken = entry.classToken,
                items = {},
                bags = {},
                bank = {},
                warbank = {},
                bagsByQuality = {},
                bankByQuality = {},
                warbankByQuality = {},
              }
            end
          end
        end
      end
    end
  end

  addon.lastHave = {}
  addon._dslLastSnapshot = nil
  addon.cache = nil
  addon:Print(L["RESET_COUNTS"])
  addon:MarkDirty("full")
end

local function SnapshotNow(addon, opts)
  ns.SnapshotCurrentCharacter(addon, opts)
  addon._dslLastSnapshot = GetTime()
end

local function SnapshotIfStale(addon, seconds, opts)
  local threshold = seconds or 0.15
  if not addon._dslLastSnapshot or (GetTime() - addon._dslLastSnapshot) > threshold then
    SnapshotNow(addon, opts)
  end
end

local function HandleInventorySnapshotEvent(addon, opts)
  if addon.inCombat then
    addon.dirty = true
    return
  end

  SnapshotNow(addon, opts)
  addon:MarkDirty("inventory")
end

local function GetBankSnapshotOpts(addon)
  local mode = addon and addon._dslBankInteractionMode
  if mode == "warbank" then
    return { forceWarbank = true }
  end
  if mode == "bank" then
    return { forceBank = true, forceWarbank = true }
  end
  return nil
end

local function FlushBankSnapshot(addon)
  if not addon then return end
  if addon._dslBankSnapshotTimer then
    addon:CancelTimer(addon._dslBankSnapshotTimer)
    addon._dslBankSnapshotTimer = nil
  end
  HandleInventorySnapshotEvent(addon, GetBankSnapshotOpts(addon))
end

local function QueueBankSnapshot(addon, delay)
  if not addon then return end
  if addon._dslBankSnapshotTimer then
    addon:CancelTimer(addon._dslBankSnapshotTimer)
  end
  addon._dslBankSnapshotTimer = addon:ScheduleTimer(function()
    addon._dslBankSnapshotTimer = nil
    if addon._dslBankInteractionOpen then
      HandleInventorySnapshotEvent(addon, GetBankSnapshotOpts(addon))
    end
  end, delay or 0.75)
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
  self:RegisterEvent("BANKFRAME_CLOSED", "OnBankClosed")
  self:RegisterEvent("PLAYERBANKSLOTS_CHANGED", "OnInventoryChanged")
  self:RegisterEvent("ITEM_DATA_LOAD_RESULT", "OnItemDataLoaded")
  self:RegisterEvent("TRADE_SKILL_LIST_UPDATE", "OnTradeSkillListUpdate")
  self:RegisterEvent("TRADE_SKILL_SHOW", "OnTradeSkillListUpdate")
  self:RegisterEvent("NEW_RECIPE_LEARNED", "OnTradeSkillListUpdate")
  self:RegisterEvent("SKILL_LINES_CHANGED", "OnTradeSkillListUpdate")
  self:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "OnInteractionFrameShow")
  self:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", "OnInteractionFrameHide")

  self:ScheduleTimer(function()
    if self.inCombat then return end
    SnapshotNow(self)
    self:MarkDirty("inventory")
  end, 1.0)

  self:ScheduleTimer(function()
    if self.inCombat then return end
    SnapshotNow(self)
    self:MarkDirty("inventory")
  end, 3.0)
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

function DSL:OnBankClosed()
  if self._dslBankSnapshotTimer then
    FlushBankSnapshot(self)
  end
  self._dslBankInteractionOpen = nil
  self._dslBankInteractionMode = nil
end

function DSL:OnBankOpened(mode)
  self._dslBankInteractionOpen = true
  self._dslBankInteractionMode = mode or "bank"
  QueueBankSnapshot(self, 0.75)
end

function DSL:OnInventoryChanged()
  if self._dslBankInteractionOpen then
    QueueBankSnapshot(self, 0.75)
    return
  end
  HandleInventorySnapshotEvent(self)
end

function DSL:OnInteractionFrameShow(_, interactionType)
  local pit = Enum and Enum.PlayerInteractionType
  if not pit then return end

  if interactionType == pit.AccountBank then
    self:OnBankOpened("warbank")
  elseif interactionType == pit.Banker then
    self:OnBankOpened("bank")
  end
end

function DSL:OnInteractionFrameHide(_, interactionType)
  local pit = Enum and Enum.PlayerInteractionType
  if not pit then return end

  if interactionType == pit.AccountBank or interactionType == pit.Banker then
    self:OnBankClosed()
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
  elseif input == "tracked" then
    PrintTrackedCharacters(self)
    return
  elseif input == "resetcounts" or input == "resetcounters" then
    ResetCountData(self)
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
