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
    minimap = { hide = true },
    includeAlts = false,

    goals = {},
    recipeByItem = {},
    metaByItem = {},
  },
  global = {
    realms = {}
  }
}

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
  self.dirtyFlags = { full = false, inventory = false, display = false }
  self.repaintAfterCombat = false
  self.refreshTimer = nil

  self.lastHave = {} -- itemID -> last known have (current char only; alt sums computed on demand)

  self:RegisterChatCommand("dsl", "SlashCommand")

  ns.InitListWindow(self)
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

end

function DSL:PLAYER_REGEN_DISABLED()
  self.inCombat = true
end

function DSL:PLAYER_REGEN_ENABLED()
  self.inCombat = false

  local f = self.dirtyFlags
    if f and (f.full or f.inventory or f.display) then
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
  if self.inCombat then
    self.dirty = true
    return
  end

  ns.SnapshotCurrentCharacter(self)
  self._dslLastSnapshot = GetTime()

  self:MarkDirty("inventory")
end

function DSL:OnInventoryChanged()
  if self.inCombat then
    self.dirty = true
    return
  end

  ns.SnapshotCurrentCharacter(self)
  self._dslLastSnapshot = GetTime()

  self:MarkDirty("inventory")
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

  -- Cheap repaint for names/icons; avoid full recompute storms.
  if ns.ListWindow and ns.ListWindow:IsShown() then
    ns.RefreshListWindow(self)
  end
end

function DSL:OnTradeSkillListUpdate()
  if self.inCombat then
    self.dirtyFlags = self.dirtyFlags or { full = false, inventory = false, display = false }
    self.dirtyFlags.full = true
    return
  end

  if ns.SnapshotLearnedRecipes and ns.SnapshotLearnedRecipes(self) then
    self:MarkDirty("full")
    return
  end

  self:MarkDirty("full")
end

function DSL:MarkDirty(reason)
  self.dirtyFlags = self.dirtyFlags or { full = false, inventory = false, display = false }

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
    local f = self.dirtyFlags
	if f and (f.full or f.inventory or f.display) then
	  self:RecomputeAndRefresh()
	end
  end, 0.2)
end

function DSL:RecomputeAndRefresh()
  local f = self.dirtyFlags or { full = false, inventory = false, display = false }
  self.dirtyFlags = { full = false, inventory = false, display = false }

  if f.full then
    -- Full rebuild (goals/learned/display changes)
    if not self._dslLastSnapshot or (GetTime() - self._dslLastSnapshot) > 0.15 then
      ns.SnapshotCurrentCharacter(self)
      self._dslLastSnapshot = GetTime()
    end

    ns.ApplyCompletionByInventoryDelta(self)
    ns.RecomputeCaches(self)
    ns.RefreshListWindow(self)
    return
  end

  if f.inventory then
    -- Inventory-only refresh: keep recipe/reagent NEEDS, refresh HAVE/remaining/completion
    if not self._dslLastSnapshot or (GetTime() - self._dslLastSnapshot) > 0.15 then
      ns.SnapshotCurrentCharacter(self)
      self._dslLastSnapshot = GetTime()
    end
    ns.ApplyCompletionByInventoryDelta(self)

    if ns.RecomputeReagentsOnly then
      ns.RecomputeReagentsOnly(self)
    else
      ns.RecomputeCaches(self)
    end

    ns.RefreshListWindow(self)
    return
  end
  
  if f.display then
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
    ns.ShowListWindow(self, not ns.ListWindow:IsShown()); return
  elseif input == "show" then
    ns.ShowListWindow(self, true); return
  elseif input == "hide" then
    ns.ShowListWindow(self, false); return
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
