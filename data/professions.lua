local ADDON, ns = ...
ns = ns or {}
ns.Data = ns.Data or {}

local professionsTried = false

local function EnsureProfessionsLoaded()
---@diagnostic disable-next-line: undefined-global
  if not professionsTried and type(LoadAddOn) == "function" and not (C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic) then
    professionsTried = true
---@diagnostic disable-next-line: undefined-global
    pcall(LoadAddOn, "Blizzard_Professions")
  end
  return (C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic) and true or false
end

local function ceilDiv(a, b)
  if not b or b <= 0 then return 0 end
  return math.floor((a + b - 1) / b)
end

local function playerKey()
  local name, realm = UnitFullName("player")
  if not name or name == "" then
    return nil, nil
  end

  realm = realm or GetRealmName()
  if not realm or realm == "" then
    return nil, nil
  end

  return realm, (name .. "-" .. realm)
end

local function NormalizeProfessionName(name)
  if not name or name == "" then return "Unknown" end

  name = name:gsub("^Dragon Isles%s+", "")
  name = name:gsub("^Khaz Algar%s+", "")
  name = name:gsub("^Zandalari%s+", "")
  name = name:gsub("^Kul Tiran%s+", "")
  name = name:gsub("^Northrend%s+", "")
  name = name:gsub("^Outland%s+", "")
  name = name:gsub("^Pandaria%s+", "")
  name = name:gsub("^Draenor%s+", "")
  name = name:gsub("^Legion%s+", "")
  name = name:gsub("^Shadowlands%s+", "")
  name = name:gsub("^Cataclysm%s+", "")
  name = name:gsub("^Wrath%s+of%s+the%s+Lich%s+King%s+", "")
  name = name:gsub("^Battle%s+for%s+Azeroth%s+", "")

  for _, prof in ipairs({
    "Alchemy","Blacksmithing","Enchanting","Engineering","Herbalism","Inscription",
    "Jewelcrafting","Leatherworking","Mining","Skinning","Tailoring","Cooking","Fishing","First Aid"
  }) do
    if name:find(prof, 1, true) then
      return prof
    end
  end

  return name
end

local function GetRecipeSchematicSafe(recipeID)
  if not recipeID then return nil end
  if not EnsureProfessionsLoaded() then return nil end
  return C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
end

local function EnsureRecipeCache(addon)
  if not (addon and addon.db and addon.db.profile) then return nil end
  addon.db.profile.recipeCache = addon.db.profile.recipeCache or {}
  return addon.db.profile.recipeCache
end

ns.Data.EnsureProfessionsLoaded = EnsureProfessionsLoaded
ns.Data.ceilDiv = ceilDiv
ns.Data.playerKey = playerKey
ns.Data.NormalizeProfessionName = NormalizeProfessionName
ns.Data.GetRecipeSchematicSafe = GetRecipeSchematicSafe
ns.Data.EnsureRecipeCache = EnsureRecipeCache
