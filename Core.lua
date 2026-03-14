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
  return { full = false, goals = false, inventory = false, display = false }
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

local function ReportPerf(addon, label, startedAt)
  if not (addon and label and startedAt) then return end
  local elapsed = (NowSeconds() - startedAt) * 1000
  if elapsed < 12 then
    return
  end

  addon._dslPerfReport = addon._dslPerfReport or {}
  local lastAt = addon._dslPerfReport[label] or 0
  local now = NowSeconds()
  if (now - lastAt) < 1.0 then
    return
  end

  addon._dslPerfReport[label] = now
  if addon.Print then
    addon:Print(string.format("DSL perf: %s %.1fms", tostring(label), elapsed))
  end
end

local function HasDirtyFlags(flags)
  return flags and (flags.full or flags.goals or flags.inventory or flags.display)
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
                bags = {},
                bank = {},
                bagsByQuality = {},
                bankByQuality = {},
              }
            end
          end
        end
      end
    end
  end

  addon.lastHave = {}
  addon.cache = nil
  addon:Print(L["RESET_COUNTS"])
  addon:MarkDirty("full")
end

local function HandleInventorySnapshotEvent(addon, opts)
  if addon.inCombat then
    addon.dirty = true
    return false
  end

  if ns.SnapshotCurrentCharacter(addon, opts) then
    addon:MarkDirty("inventory")
    return true
  end

  return false
end

local function MergeSnapshotOpts(existing, incoming)
  if type(existing) ~= "table" then
    existing = nil
  end
  if type(incoming) ~= "table" then
    incoming = nil
  end

  local merged = {}

  if (existing and existing.forceBank) or (incoming and incoming.forceBank) then
    merged.forceBank = true
  end
  if (existing and existing.forceWarbank) or (incoming and incoming.forceWarbank) then
    merged.forceWarbank = true
  end

  if (existing and existing.skipQuality == false) or (incoming and incoming.skipQuality == false) then
    merged.skipQuality = false
  elseif (existing and existing.skipQuality == true) or (incoming and incoming.skipQuality == true) then
    merged.skipQuality = true
  end

  return next(merged) and merged or nil
end

local function QueueSnapshotRequest(addon, key, delay, opts)
  if not addon then return end

  addon._dslSnapshotRequests = addon._dslSnapshotRequests or {}
  local request = addon._dslSnapshotRequests[key] or {}
  addon._dslSnapshotRequests[key] = request

  request.opts = MergeSnapshotOpts(request.opts, opts)

  if request.timer then
    addon:CancelTimer(request.timer)
  end

  request.timer = addon:ScheduleTimer(function()
    local current = addon._dslSnapshotRequests and addon._dslSnapshotRequests[key]
    if current then
      current.timer = nil
    end

    if addon.inCombat then
      addon.dirty = true
      return
    end

    HandleInventorySnapshotEvent(addon, current and current.opts or opts)

    if current then
      current.opts = nil
    end
  end, delay or 0.25)
end

local function HasTrackedQualityGoals(addon)
  local goals = addon and addon.db and addon.db.profile and addon.db.profile.goals
  if type(goals) ~= "table" then
    return false
  end
  for _, goal in pairs(goals) do
    if type(goal) == "table" and goal.qualityMode == "specific" and goal.targetQuality then
      return true
    end
  end
  return false
end

local function ShouldDoExpensiveInventoryWork()
  return false
end

local function ShouldIncludeInventoryQuality(addon)
  return HasTrackedQualityGoals(addon) and ShouldDoExpensiveInventoryWork()
end

local function BuildInventorySnapshotOpts(addon, extraOpts)
  local opts = extraOpts or {}
  opts.skipQuality = not ShouldIncludeInventoryQuality(addon)
  return opts
end

local function QueueInventorySnapshot(addon, delay, extraOpts)
  if not addon then return end
  QueueSnapshotRequest(addon, "inventory", delay or 0.25, BuildInventorySnapshotOpts(addon, extraOpts))
end

ns.QueueInventorySnapshot = QueueInventorySnapshot

local function IsCraftRefreshActive(addon)
  if not addon then return false end
  local now = GetTime and GetTime() or 0
  local pending = addon._dslPendingCraft
  if type(pending) == "table" and type(pending.expiresAt) == "number" and now <= pending.expiresAt then
    return true
  end
  local recentAt = tonumber(addon._dslRecentCraftAt)
  return recentAt ~= nil and (now - recentAt) <= 1.0
end

local function QueueCraftSettleRefresh(addon, delay)
  if not addon then return end
  if addon._dslCraftSettleTimer then
    addon:CancelTimer(addon._dslCraftSettleTimer)
  end

  addon._dslCraftSettleTimer = addon:ScheduleTimer(function()
    addon._dslCraftSettleTimer = nil
    addon._dslRecentCraftAt = nil
    addon._dslPendingCraft = nil

    if addon.inCombat then
      addon.dirtyFlags = addon.dirtyFlags or NewDirtyFlags()
      addon.dirtyFlags.goals = true
      if addon._dslPendingInventorySnapshot then
        addon.dirtyFlags.inventory = true
      end
      return
    end

    addon:MarkDirty("goals")
    if addon._dslPendingInventorySnapshot then
      addon._dslPendingInventorySnapshot = nil
      QueueInventorySnapshot(addon, 0.05)
    end
  end, delay or 0.5)
end

local function ShouldSkipReagentRebuild(addon)
  local view = addon and addon.db and addon.db.profile and addon.db.profile.window and addon.db.profile.window.view
  return view == "recipes"
end

local function TableHasEntries(t)
  return type(t) == "table" and next(t) ~= nil
end

local function ShouldScheduleStartupInventorySnapshot(addon)
  if not (addon and addon.db and addon.db.global and ns.Data and ns.Data.playerKey) then
    return true
  end

  local realm, charKey = ns.Data.playerKey()
  if not realm or not charKey then
    return true
  end

  local realms = addon.db.global.realms
  local realmEntry = type(realms) == "table" and realms[realm] or nil
  local chars = realmEntry and realmEntry.chars
  local entry = type(chars) == "table" and chars[charKey] or nil
  if type(entry) ~= "table" then
    return true
  end

  if TableHasEntries(entry.bags) or TableHasEntries(entry.bank) then
    return false
  end

  if TableHasEntries(entry.bagsByQuality) or TableHasEntries(entry.bankByQuality) then
    return false
  end

  return true
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
  addon._dslSnapshotRequests = addon._dslSnapshotRequests or {}
  local request = addon._dslSnapshotRequests.bank
  if request and request.timer then
    addon:CancelTimer(request.timer)
    request.timer = nil
  end
  HandleInventorySnapshotEvent(addon, GetBankSnapshotOpts(addon))
end

local function QueueBankSnapshot(addon, delay)
  if not addon then return end
  local opts = BuildInventorySnapshotOpts(addon, GetBankSnapshotOpts(addon) or {})

  addon._dslSnapshotRequests = addon._dslSnapshotRequests or {}
  local request = addon._dslSnapshotRequests.bank or {}
  addon._dslSnapshotRequests.bank = request
  request.opts = MergeSnapshotOpts(request.opts, opts)

  if request.timer then
    addon:CancelTimer(request.timer)
  end

  request.timer = addon:ScheduleTimer(function()
    local current = addon._dslSnapshotRequests and addon._dslSnapshotRequests.bank
    if current then
      current.timer = nil
    end
    if addon._dslBankInteractionOpen then
      HandleInventorySnapshotEvent(addon, current and current.opts or opts)
    end
    if current then
      current.opts = nil
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
end

function DSL:OnEnable()
  self:RegisterEvent("PLAYER_REGEN_DISABLED")
  self:RegisterEvent("PLAYER_REGEN_ENABLED")
  self:RegisterEvent("PLAYER_LOGOUT", "OnPlayerLogout")
  self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", "OnUnitSpellcastSucceeded")

  self:RegisterEvent("BAG_UPDATE_DELAYED", "OnInventoryChanged")
  self:RegisterEvent("BANKFRAME_OPENED", "OnBankOpened")
  self:RegisterEvent("BANKFRAME_CLOSED", "OnBankClosed")
  self:RegisterEvent("PLAYERBANKSLOTS_CHANGED", "OnInventoryChanged")
  self:RegisterEvent("TRADE_SKILL_SHOW", "OnTradeSkillListUpdate")
  self:RegisterEvent("NEW_RECIPE_LEARNED", "OnTradeSkillListUpdate")
  self:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "OnInteractionFrameShow")
  self:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", "OnInteractionFrameHide")

  self:ScheduleTimer(function()
    if self.inCombat then
      self.dirtyFlags = self.dirtyFlags or NewDirtyFlags()
      self.dirtyFlags.full = true
      return
    end
    self:MarkDirty("full")
  end, 1.5)

  if ShouldScheduleStartupInventorySnapshot(self) then
    self:ScheduleTimer(function()
      if self.inCombat then return end
      QueueInventorySnapshot(self, 0.05)
    end, 3.0)
  end
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
  if self._dslSnapshotRequests and self._dslSnapshotRequests.bank and self._dslSnapshotRequests.bank.timer then
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

  if IsCraftRefreshActive(self) then
    self._dslPendingInventorySnapshot = true
    QueueCraftSettleRefresh(self, 0.5)
    return
  end

  QueueInventorySnapshot(self, 0.25)
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

function DSL:OnUnitSpellcastSucceeded(_, unit)
  if unit ~= "player" then
    return
  end

  local pending = self._dslPendingCraft
  if type(pending) ~= "table" or not pending.recipeID then
    return
  end

  local now = GetTime and GetTime() or 0
  if pending.expiresAt and now > pending.expiresAt then
    self._dslPendingCraft = nil
    return
  end

  if ns.NoteCraftSucceeded and ns.NoteCraftSucceeded(self, pending.recipeID, pending.quantity or 1) then
    self._dslRecentCraftAt = now
    pending.lastSuccessAt = now
    pending.expiresAt = now + 2.0
    QueueCraftSettleRefresh(self, 0.5)
    return
  end

  self._dslPendingCraft = nil
end

function DSL:OnTradeSkillListUpdate(event)
  if self.inCombat then
    self.dirtyFlags = self.dirtyFlags or NewDirtyFlags()
    self.dirtyFlags.full = true
    return
  end

  if self._dslProfessionRefreshTimer then
    self:CancelTimer(self._dslProfessionRefreshTimer)
  end

  self._dslProfessionRefreshTimer = self:ScheduleTimer(function()
    self._dslProfessionRefreshTimer = nil
    local forceRecipeScan = (event == "NEW_RECIPE_LEARNED")
    if not forceRecipeScan and IsCraftRefreshActive(self) then
      QueueCraftSettleRefresh(self, 0.5)
      return
    end
    if ns.SnapshotLearnedRecipes and ns.SnapshotLearnedRecipes(self, forceRecipeScan) then
      self:MarkDirty("full")
      return
    end

    self:MarkDirty("display")
  end, 0.05)
end

function DSL:MarkDirty(reason)
  self.dirtyFlags = self.dirtyFlags or NewDirtyFlags()

  if reason == "inventory" then
    self.dirtyFlags.inventory = true
  elseif reason == "goals" then
    self.dirtyFlags.goals = true
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
  local startedAt = NowSeconds()
  local flags = self.dirtyFlags or NewDirtyFlags()
  self.dirtyFlags = NewDirtyFlags()

  if flags.full then
    -- Full rebuild (goals/learned/display changes)
    ns.RecomputeCaches(self)
    ns.RefreshListWindow(self)
    ReportPerf(self, "full refresh", startedAt)
    return
  end

  if flags.goals then
    -- Goal-only refresh: rebuild recipe/reagent goal state without inventory completion pass.
    ns.RecomputeCaches(self, { skipReagents = ShouldSkipReagentRebuild(self) })
    ns.RefreshListWindow(self)
    ReportPerf(self, "goal refresh", startedAt)
    return
  end

  if flags.inventory then
    -- Inventory-only refresh: update inventory-driven caches only.
    if ShouldSkipReagentRebuild(self) then
      if self.cache then
        self.cache._reagentsStale = true
      end
      ReportPerf(self, "inventory refresh", startedAt)
      return
    end

    if ns.RecomputeReagentsOnly then
      ns.RecomputeReagentsOnly(self)
    else
      ns.RecomputeCaches(self)
    end

    ns.RefreshListWindow(self)
    ReportPerf(self, "inventory refresh", startedAt)
    return
  end

  if flags.display then
    -- Display-only refresh: collapse/sort/view changes should not touch math/state.
    local view = self.db and self.db.profile and self.db.profile.window and self.db.profile.window.view
    if view == "reagents" and self.cache and self.cache._reagentsStale and ns.RecomputeReagentsOnly then
      ns.RecomputeReagentsOnly(self)
    elseif ns.RecomputeDisplayOnly then
      ns.RecomputeDisplayOnly(self)
    else
      ns.RecomputeCaches(self)
    end
    ns.RefreshListWindow(self)
    ReportPerf(self, "display refresh", startedAt)
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
