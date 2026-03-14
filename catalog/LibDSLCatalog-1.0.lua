local ADDON, ns = ...
ns = ns or {}

local MAJOR, MINOR = "LibDSLCatalog-1.0", 2
local Catalog = LibStub:NewLibrary(MAJOR, MINOR)
if not Catalog then
  return
end

Catalog.version = MINOR
Catalog.schemaVersion = 1

Catalog.RecipeCatalog = Catalog.RecipeCatalog or {}
Catalog.ItemCatalog = Catalog.ItemCatalog or {}
Catalog.OutputToRecipe = Catalog.OutputToRecipe or {}
Catalog.OutputToRecipes = Catalog.OutputToRecipes or {}
Catalog.SourceOverrides = Catalog.SourceOverrides or {}

local wipeTable = wipe

local function CopyArray(src)
  if type(src) ~= "table" then
    return nil
  end

  local copy = {}
  for index = 1, #src do
    copy[index] = src[index]
  end
  return copy
end

local function CopyTableShallow(src)
  if type(src) ~= "table" then
    return src
  end

  local copy = {}
  for key, value in pairs(src) do
    copy[key] = value
  end
  return copy
end

local function NormalizeNumber(value)
  if type(value) == "number" then
    return value
  end
  if type(value) == "string" and value ~= "" then
    return tonumber(value)
  end
  return nil
end

local function NormalizeReagent(reagent)
  if type(reagent) ~= "table" then
    return nil
  end

  local itemID = NormalizeNumber(reagent.itemID or reagent.item_id)
  if not itemID then
    return nil
  end

  local normalized = {
    itemID = itemID,
    quantity = NormalizeNumber(reagent.quantity or reagent.qty) or 0,
  }

  local tierItemIDs = reagent.tierItemIDs or reagent.tier_item_ids
  if type(tierItemIDs) == "table" then
    normalized.tierItemIDs = CopyTableShallow(tierItemIDs)
  end

  local targetQuality = NormalizeNumber(reagent.targetQuality or reagent.target_quality)
  if targetQuality then
    normalized.targetQuality = targetQuality
  end

  return normalized
end

local function NormalizeRecipeData(recipeData)
  if type(recipeData) ~= "table" then
    return nil
  end

  local normalized = {
    profession = recipeData.profession,
    professionID = NormalizeNumber(recipeData.professionID or recipeData.profession_id),
    outputItemID = NormalizeNumber(recipeData.outputItemID or recipeData.output_item_id),
    expansionID = NormalizeNumber(recipeData.expansionID or recipeData.expansion_id),
    recipeName = recipeData.recipeName or recipeData.recipe_name,
  }

  local outputQuantity = NormalizeNumber(recipeData.outputQuantity or recipeData.output_quantity)
  local yieldMin = NormalizeNumber(recipeData.yieldMin or recipeData.yield_min)
  local yieldMax = NormalizeNumber(recipeData.yieldMax or recipeData.yield_max)

  if outputQuantity then
    normalized.outputQuantity = outputQuantity
  end
  if yieldMin then
    normalized.yieldMin = yieldMin
  end
  if yieldMax then
    normalized.yieldMax = yieldMax
  end

  local reagents = recipeData.reagents
  if type(reagents) == "table" then
    local reagentList = {}
    for index = 1, #reagents do
      local normalizedReagent = NormalizeReagent(reagents[index])
      if normalizedReagent then
        reagentList[#reagentList + 1] = normalizedReagent
      end
    end
    normalized.reagents = reagentList
  else
    normalized.reagents = {}
  end

  return normalized
end

local function NormalizeItemData(itemData)
  if type(itemData) ~= "table" then
    return nil
  end

  return {
    name = itemData.name,
    icon = NormalizeNumber(itemData.icon),
    rarity = NormalizeNumber(itemData.rarity),
    expansionID = NormalizeNumber(itemData.expansionID or itemData.expansion_id),
  }
end

local function NormalizeSourceOverride(sourceData)
  if type(sourceData) ~= "table" then
    return nil
  end

  return {
    source = sourceData.source,
    subSource = sourceData.subSource or sourceData.sub_source,
  }
end

local function NormalizeRecipeIDList(recipeIDs)
  if type(recipeIDs) ~= "table" then
    return nil
  end

  local normalized = {}
  for index = 1, #recipeIDs do
    local recipeID = NormalizeNumber(recipeIDs[index])
    if recipeID then
      normalized[#normalized + 1] = recipeID
    end
  end
  return normalized
end

local function EnsureOutputRecipeList(self, itemID)
  local recipeIDs = self.OutputToRecipes[itemID]
  if type(recipeIDs) ~= "table" then
    recipeIDs = {}
    self.OutputToRecipes[itemID] = recipeIDs
  end
  return recipeIDs
end

local function AddRecipeIDUnique(recipeIDs, recipeID)
  for index = 1, #recipeIDs do
    if recipeIDs[index] == recipeID then
      return
    end
  end
  recipeIDs[#recipeIDs + 1] = recipeID
end

function Catalog:GetVersion()
  return self.version
end

function Catalog:GetSchemaVersion()
  return self.schemaVersion
end

function Catalog:GetRecipeStore()
  return self.RecipeCatalog
end

function Catalog:GetItemStore()
  return self.ItemCatalog
end

function Catalog:GetOutputRecipeStore()
  return self.OutputToRecipe
end

function Catalog:GetOutputRecipesStore()
  return self.OutputToRecipes
end

function Catalog:GetSourceOverrideStore()
  return self.SourceOverrides
end

function Catalog:HasRecipe(recipeID)
  return recipeID and self.RecipeCatalog[recipeID] ~= nil or false
end

function Catalog:GetRecipe(recipeID)
  return recipeID and self.RecipeCatalog[recipeID] or nil
end

function Catalog:SetRecipe(recipeID, recipeData)
  recipeID = NormalizeNumber(recipeID)
  if not recipeID then
    return
  end

  local normalized = NormalizeRecipeData(recipeData)
  if not normalized then
    return
  end

  self.RecipeCatalog[recipeID] = normalized

  local outputItemID = normalized.outputItemID
  if outputItemID then
    self.OutputToRecipe[outputItemID] = recipeID
    AddRecipeIDUnique(EnsureOutputRecipeList(self, outputItemID), recipeID)
  end
end

function Catalog:HasItem(itemID)
  return itemID and self.ItemCatalog[itemID] ~= nil or false
end

function Catalog:GetItem(itemID)
  return itemID and self.ItemCatalog[itemID] or nil
end

function Catalog:SetItem(itemID, itemData)
  itemID = NormalizeNumber(itemID)
  if not itemID then
    return
  end

  local normalized = NormalizeItemData(itemData)
  if not normalized then
    return
  end

  self.ItemCatalog[itemID] = normalized
end

function Catalog:GetRecipeForOutput(itemID)
  return itemID and self.OutputToRecipe[itemID] or nil
end

function Catalog:GetPreferredRecipeForOutput(itemID)
  return self:GetRecipeForOutput(itemID)
end

function Catalog:GetRecipesForOutput(itemID)
  local recipeIDs = itemID and self.OutputToRecipes[itemID] or nil
  if type(recipeIDs) ~= "table" then
    return nil
  end
  return CopyArray(recipeIDs)
end

function Catalog:SetRecipeForOutput(itemID, recipeID)
  itemID = NormalizeNumber(itemID)
  recipeID = NormalizeNumber(recipeID)
  if not itemID or not recipeID then
    return
  end

  self.OutputToRecipe[itemID] = recipeID
  AddRecipeIDUnique(EnsureOutputRecipeList(self, itemID), recipeID)
end

function Catalog:SetPreferredRecipeForOutput(itemID, recipeID)
  self:SetRecipeForOutput(itemID, recipeID)
end

function Catalog:SetRecipesForOutput(itemID, recipeIDs)
  itemID = NormalizeNumber(itemID)
  local normalized = NormalizeRecipeIDList(recipeIDs)
  if not itemID or type(normalized) ~= "table" then
    return
  end

  self.OutputToRecipes[itemID] = normalized
  self.OutputToRecipe[itemID] = normalized[1]
end

function Catalog:IsCraftable(itemID)
  return self:GetRecipeForOutput(itemID) ~= nil
end

function Catalog:GetOutputItemForRecipe(recipeID)
  local recipe = self:GetRecipe(recipeID)
  return recipe and recipe.outputItemID or nil
end

function Catalog:GetReagentsForRecipe(recipeID)
  local recipe = self:GetRecipe(recipeID)
  local reagents = recipe and recipe.reagents or nil
  if type(reagents) ~= "table" then
    return nil
  end

  local copy = {}
  for index = 1, #reagents do
    copy[index] = CopyTableShallow(reagents[index])
  end
  return copy
end

function Catalog:GetProfessionForRecipe(recipeID)
  local recipe = self:GetRecipe(recipeID)
  if not recipe then
    return nil, nil
  end
  return recipe.profession, recipe.professionID
end

function Catalog:GetYieldRangeForRecipe(recipeID)
  local recipe = self:GetRecipe(recipeID)
  if not recipe then
    return nil, nil
  end

  if recipe.yieldMin or recipe.yieldMax then
    return recipe.yieldMin or recipe.yieldMax, recipe.yieldMax or recipe.yieldMin
  end

  if recipe.outputQuantity then
    return recipe.outputQuantity, recipe.outputQuantity
  end

  return nil, nil
end

function Catalog:GetSourceOverride(itemID)
  return itemID and self.SourceOverrides[itemID] or nil
end

function Catalog:SetSourceOverride(itemID, sourceData)
  itemID = NormalizeNumber(itemID)
  if not itemID then
    return
  end

  local normalized = NormalizeSourceOverride(sourceData)
  if not normalized then
    return
  end

  self.SourceOverrides[itemID] = normalized
end

function Catalog:IterateRecipes()
  return next, self.RecipeCatalog, nil
end

function Catalog:IterateItems()
  return next, self.ItemCatalog, nil
end

function Catalog:ResetRuntime()
  wipeTable(self.RecipeCatalog)
  wipeTable(self.ItemCatalog)
  wipeTable(self.OutputToRecipe)
  wipeTable(self.OutputToRecipes)
  wipeTable(self.SourceOverrides)
end

function Catalog:IsLoaded()
  return next(self.RecipeCatalog) ~= nil
      or next(self.ItemCatalog) ~= nil
      or next(self.OutputToRecipe) ~= nil
      or next(self.OutputToRecipes) ~= nil
      or next(self.SourceOverrides) ~= nil
end

-- DSLCATALOG_DATA_START
-- Generated by populate_lib_dsl_catalog.py. Do not edit by hand.
Catalog:ResetRuntime()

-- Recipes
Catalog:SetRecipe(1228939, {
    expansionID = 11,
    outputItemID = 239700,
    profession = "Tailoring",
    professionID = 2918,
    reagents = {
      {
        itemID = 251665,
        quantity = 4,
        tierItemIDs = {
          251665,
                },
            },
      {
        itemID = 236963,
        quantity = 1,
        tierItemIDs = {
          236963,
          236965,
                },
            },
      {
        itemID = 246447,
        quantity = 1,
        tierItemIDs = {
          246447,
          246448,
          246449,
                },
            },
        },
    recipeName = "Bright Linen Bolt",
    yieldMin = 1,
  })

Catalog:SetRecipe(1228941, {
    expansionID = 11,
    outputItemID = 239711,
    profession = "Tailoring",
    professionID = 2918,
    reagents = {
      {
        itemID = 239700,
        quantity = 1,
        tierItemIDs = {
          239700,
          239701,
                },
            },
      {
        itemID = 246447,
        quantity = 1,
        tierItemIDs = {
          246447,
          246448,
          246449,
                },
            },
        },
    recipeName = "Bright Linen Bandage",
    yieldMin = 1,
  })

Catalog:SetRecipe(1228952, {
    expansionID = 11,
    outputItemID = 239669,
    profession = "Tailoring",
    professionID = 2918,
    reagents = {
      {
        itemID = 251665,
        quantity = 3,
        tierItemIDs = {
          251665,
                },
            },
      {
        itemID = 239700,
        quantity = 3,
        tierItemIDs = {
          239700,
          239701,
                },
            },
      {
        itemID = 244603,
        quantity = 1,
        tierItemIDs = {
          244607,
          244608,
                },
            },
      {
        itemID = 245781,
        quantity = 1,
        tierItemIDs = {
          245783,
          245784,
                },
            },
      {
        itemID = 246447,
        quantity = 1,
        tierItemIDs = {
          246447,
          246448,
          246449,
                },
            },
        },
    recipeName = "Courtly Gloves",
    yieldMin = 1,
  })

Catalog:SetRecipe(1228953, {
    expansionID = 11,
    outputItemID = 239670,
    profession = "Tailoring",
    professionID = 2918,
    reagents = {
      {
        itemID = 251665,
        quantity = 3,
        tierItemIDs = {
          251665,
                },
            },
      {
        itemID = 251691,
        quantity = 2,
        tierItemIDs = {
          251691,
                },
            },
      {
        itemID = 239700,
        quantity = 2,
        tierItemIDs = {
          239700,
          239701,
                },
            },
      {
        itemID = 244603,
        quantity = 1,
        tierItemIDs = {
          244607,
          244608,
                },
            },
      {
        itemID = 245781,
        quantity = 1,
        tierItemIDs = {
          245783,
          245784,
                },
            },
      {
        itemID = 246447,
        quantity = 1,
        tierItemIDs = {
          246447,
          246448,
          246449,
                },
            },
      {
        itemID = 246211,
        quantity = 1,
        tierItemIDs = {
          246211,
          246212,
                },
            },
        },
    recipeName = "Courtly Belt",
    yieldMin = 1,
  })

Catalog:SetRecipe(1228956, {
    expansionID = 11,
    outputItemID = 239676,
    profession = "Tailoring",
    professionID = 2918,
    reagents = {
      {
        itemID = 251665,
        quantity = 4,
        tierItemIDs = {
          251665,
                },
            },
      {
        itemID = 251691,
        quantity = 3,
        tierItemIDs = {
          251691,
                },
            },
      {
        itemID = 239700,
        quantity = 3,
        tierItemIDs = {
          239700,
          239701,
                },
            },
      {
        itemID = 244603,
        quantity = 1,
        tierItemIDs = {
          244607,
          244608,
                },
            },
      {
        itemID = 245781,
        quantity = 1,
        tierItemIDs = {
          245783,
          245784,
                },
            },
      {
        itemID = 246447,
        quantity = 1,
        tierItemIDs = {
          246447,
          246448,
          246449,
                },
            },
        },
    recipeName = "Courtly Pants",
    yieldMin = 1,
  })

Catalog:SetRecipe(1229624, {
    expansionID = 11,
    outputItemID = 237922,
    profession = "Blacksmithing",
    professionID = 2907,
    reagents = {
      {
        itemID = 243060,
        quantity = 1,
        tierItemIDs = {
          243060,
                },
            },
      {
        itemID = 238197,
        quantity = 3,
        tierItemIDs = {
          238197,
          238198,
                },
            },
      {
        itemID = 244603,
        quantity = 1,
        tierItemIDs = {
          244607,
          244608,
                },
            },
      {
        itemID = 245781,
        quantity = 1,
        tierItemIDs = {
          245783,
          245784,
                },
            },
      {
        itemID = 246447,
        quantity = 1,
        tierItemIDs = {
          246447,
          246448,
          246449,
                },
            },
        },
    recipeName = "Blood-Tempered Leggings",
    yieldMin = 1,
  })

Catalog:SetRecipe(1229666, {
    expansionID = 11,
    outputItemID = 237830,
    profession = "Blacksmithing",
    professionID = 2907,
    reagents = {
      {
        itemID = 237366,
        quantity = 1,
        tierItemIDs = {
          237366,
                },
            },
      {
        itemID = 251283,
        quantity = 1,
        tierItemIDs = {
          251283,
                },
            },
      {
        itemID = 238204,
        quantity = 8,
        tierItemIDs = {
          238204,
          238205,
                },
            },
      {
        itemID = 238202,
        quantity = 8,
        tierItemIDs = {
          238202,
          238203,
                },
            },
      {
        itemID = 244635,
        quantity = 1,
        tierItemIDs = {
          244635,
          244636,
                },
            },
      {
        itemID = 232875,
        quantity = 2,
        tierItemIDs = {
          232875,
                },
            },
      {
        itemID = 244603,
        quantity = 1,
        tierItemIDs = {
          244607,
          244608,
                },
            },
      {
        itemID = 245781,
        quantity = 1,
        tierItemIDs = {
          245783,
          245784,
                },
            },
      {
        itemID = 246447,
        quantity = 1,
        tierItemIDs = {
          246447,
          246448,
          246449,
                },
            },
      {
        itemID = 246211,
        quantity = 1,
        tierItemIDs = {
          246211,
          246212,
                },
            },
        },
    recipeName = "Spellbreaker's Girdle",
    yieldMin = 1,
  })

Catalog:SetRecipe(1229856, {
    expansionID = 11,
    outputItemID = 244701,
    profession = "Engineering",
    professionID = 2910,
    reagents = {
      {
        itemID = 253303,
        quantity = 5,
        tierItemIDs = {
          253303,
                },
            },
      {
        itemID = 236952,
        quantity = 1,
        tierItemIDs = {
          236952,
                },
            },
      {
        itemID = 243574,
        quantity = 2,
        tierItemIDs = {
          243574,
          243575,
                },
            },
      {
        itemID = 243576,
        quantity = 1,
        tierItemIDs = {
          243576,
          243577,
                },
            },
      {
        itemID = 246447,
        quantity = 1,
        tierItemIDs = {
          246447,
          246448,
          246449,
                },
            },
        },
    recipeName = "Perfected Cogwheel",
    yieldMin = 1,
  })

Catalog:SetRecipe(1229859, {
    expansionID = 11,
    outputItemID = 244697,
    profession = "Engineering",
    professionID = 2910,
    reagents = {
      {
        itemID = 253303,
        quantity = 5,
        tierItemIDs = {
          253303,
                },
            },
      {
        itemID = 236950,
        quantity = 1,
        tierItemIDs = {
          236950,
                },
            },
      {
        itemID = 243574,
        quantity = 2,
        tierItemIDs = {
          243574,
          243575,
                },
            },
      {
        itemID = 243576,
        quantity = 1,
        tierItemIDs = {
          243576,
          243577,
                },
            },
      {
        itemID = 246447,
        quantity = 1,
        tierItemIDs = {
          246447,
          246448,
          246449,
                },
            },
        },
    recipeName = "Flux Cogwheel",
    yieldMin = 1,
  })

Catalog:SetRecipe(1230018, {
    expansionID = 11,
    outputItemID = 245764,
    profession = "Inscription",
    professionID = 2913,
    reagents = {
      {
        itemID = 236950,
        quantity = 1,
        tierItemIDs = {
          236950,
                },
            },
      {
        itemID = 236951,
        quantity = 1,
        tierItemIDs = {
          236951,
                },
            },
      {
        itemID = 245766,
        quantity = 1,
        tierItemIDs = {
          245766,
          245767,
                },
            },
      {
        itemID = 236774,
        quantity = 8,
        tierItemIDs = {
          236774,
          236775,
                },
            },
      {
        itemID = 246447,
        quantity = 1,
        tierItemIDs = {
          246447,
          246448,
          246449,
                },
            },
        },
    recipeName = "Codified Azeroot",
    yieldMin = 1,
  })

Catalog:SetRecipe(1230019, {
    expansionID = 11,
    outputItemID = 245766,
    profession = "Inscription",
    professionID = 2913,
    reagents = {
      {
        itemID = 236952,
        quantity = 1,
        tierItemIDs = {
          236952,
                },
            },
      {
        itemID = 236949,
        quantity = 1,
        tierItemIDs = {
          236949,
                },
            },
      {
        itemID = 242788,
        quantity = 1,
        tierItemIDs = {
          242788,
          242789,
                },
            },
      {
        itemID = 245801,
        quantity = 1,
        tierItemIDs = {
          245801,
          245802,
                },
            },
      {
        itemID = 245805,
        quantity = 1,
        tierItemIDs = {
          245805,
          245806,
                },
            },
      {
        itemID = 246447,
        quantity = 1,
        tierItemIDs = {
          246447,
          246448,
          246449,
                },
            },
        },
    recipeName = "Soul Cipher",
    yieldMin = 1,
  })

Catalog:SetRecipe(1230763, {
    expansionID = 11,
    outputItemID = 238204,
    profession = "Blacksmithing",
    professionID = 2907,
    reagents = {
      {
        itemID = 243060,
        quantity = 4,
        tierItemIDs = {
          243060,
                },
            },
      {
        itemID = 237364,
        quantity = 6,
        tierItemIDs = {
          237364,
          237365,
                },
            },
      {
        itemID = 238197,
        quantity = 3,
        tierItemIDs = {
          238197,
          238198,
                },
            },
      {
        itemID = 246447,
        quantity = 1,
        tierItemIDs = {
          246447,
          246448,
          246449,
                },
            },
        },
    recipeName = "Sterling Alloy",
    yieldMin = 1,
  })

Catalog:SetRecipe(1230858, {
    expansionID = 11,
    outputItemID = 241287,
    profession = "Alchemy",
    professionID = 2906,
    reagents = {
      {
        itemID = 236949,
        quantity = 2,
        tierItemIDs = {
          236949,
                },
            },
      {
        itemID = 240991,
        quantity = 5,
        tierItemIDs = {
          240991,
          240990,
                },
            },
      {
        itemID = 236761,
        quantity = 4,
        tierItemIDs = {
          236761,
          236767,
                },
            },
      {
        itemID = 236774,
        quantity = 3,
        tierItemIDs = {
          236774,
          236775,
                },
            },
      {
        itemID = 246447,
        quantity = 1,
        tierItemIDs = {
          246447,
          246448,
          246449,
                },
            },
        },
    recipeName = "Light's Preservation",
    yieldMin = 5,
  })

Catalog:SetRecipe(1230865, {
    expansionID = 11,
    outputItemID = 241301,
    profession = "Alchemy",
    professionID = 2906,
    reagents = {
      {
        itemID = 240991,
        quantity = 5,
        tierItemIDs = {
          240991,
          240990,
                },
            },
      {
        itemID = 236761,
        quantity = 8,
        tierItemIDs = {
          236761,
          236767,
                },
            },
      {
        itemID = 236778,
        quantity = 3,
        tierItemIDs = {
          236778,
          236779,
                },
            },
      {
        itemID = 246447,
        quantity = 1,
        tierItemIDs = {
          246447,
          246448,
          246449,
                },
            },
        },
    recipeName = "Lightfused Mana Potion",
    yieldMin = 5,
  })

Catalog:SetRecipe(1230869, {
    expansionID = 11,
    outputItemID = 241309,
    profession = "Alchemy",
    professionID = 2906,
    reagents = {
      {
        itemID = 236949,
        quantity = 1,
        tierItemIDs = {
          236949,
                },
            },
      {
        itemID = 240991,
        quantity = 5,
        tierItemIDs = {
          240991,
          240990,
                },
            },
      {
        itemID = 236761,
        quantity = 8,
        tierItemIDs = {
          236761,
          236767,
                },
            },
      {
        itemID = 236776,
        quantity = 3,
        tierItemIDs = {
          236776,
          236777,
                },
            },
      {
        itemID = 236774,
        quantity = 3,
        tierItemIDs = {
          236774,
          236775,
                },
            },
      {
        itemID = 246447,
        quantity = 1,
        tierItemIDs = {
          246447,
          246448,
          246449,
                },
            },
        },
    recipeName = "Light's Potential",
    yieldMin = 5,
  })

Catalog:SetRecipe(1233130, {
    expansionID = 11,
    outputItemID = 242638,
    profession = "Alchemy",
    professionID = 2906,
    reagents = {
      {
        itemID = 247811,
        quantity = 2,
        tierItemIDs = {
          247811,
                },
            },
        },
    recipeName = "Recycle Flasks",
    yieldMin = 1,
  })

Catalog:SetRecipe(1236087, {
    profession = "Enchanting",
    professionID = 2909,
    reagents = {
      {
        itemID = 243599,
        quantity = 5,
        tierItemIDs = {
          243599,
          243600,
                },
            },
      {
        itemID = 246447,
        quantity = 1,
        tierItemIDs = {
          246447,
          246448,
          246449,
                },
            },
        },
    recipeName = "Enchant Ring - Thalassian Versatility",
    yieldMin = 1,
  })

Catalog:SetRecipe(1236486, {
    expansionID = 11,
    outputItemID = 244175,
    profession = "Enchanting",
    professionID = 2909,
    reagents = {
      {
        itemID = 244174,
        quantity = 1,
        tierItemIDs = {
          244174,
                },
            },
      {
        itemID = 243599,
        quantity = 5,
        tierItemIDs = {
          243599,
          243600,
                },
            },
      {
        itemID = 245820,
        quantity = 1,
        tierItemIDs = {
          245814,
          245815,
                },
            },
      {
        itemID = 246447,
        quantity = 1,
        tierItemIDs = {
          246447,
          246448,
          246449,
                },
            },
        },
    recipeName = "Runed Refulgent Copper Rod",
    yieldMin = 1,
  })

Catalog:SetRecipe(1237511, {
    expansionID = 11,
    outputItemID = 244574,
    profession = "Leatherworking",
    professionID = 2915,
    reagents = {
      {
        itemID = 251283,
        quantity = 1,
        tierItemIDs = {
          251283,
                },
            },
      {
        itemID = 238511,
        quantity = 150,
        tierItemIDs = {
          238511,
          238512,
                },
            },
      {
        itemID = 238513,
        quantity = 75,
        tierItemIDs = {
          238513,
          238514,
                },
            },
      {
        itemID = 244635,
        quantity = 2,
        tierItemIDs = {
          244635,
          244636,
                },
            },
      {
        itemID = 244633,
        quantity = 1,
        tierItemIDs = {
          244633,
          244634,
                },
            },
      {
        itemID = 232875,
        quantity = 2,
        tierItemIDs = {
          232875,
                },
            },
      {
        itemID = 244603,
        quantity = 1,
        tierItemIDs = {
          244607,
          244608,
                },
            },
      {
        itemID = 245781,
        quantity = 1,
        tierItemIDs = {
          245783,
          245784,
                },
            },
      {
        itemID = 246447,
        quantity = 1,
        tierItemIDs = {
          246447,
          246448,
          246449,
                },
            },
        },
    recipeName = "Silvermoon Agent's Leggings",
    yieldMin = 1,
  })

Catalog:SetRecipe(1237572, {
    expansionID = 11,
    outputItemID = 244631,
    profession = "Leatherworking",
    professionID = 2915,
    reagents = {
      {
        itemID = 238518,
        quantity = 1,
        tierItemIDs = {
          238518,
          238519,
                },
            },
      {
        itemID = 238520,
        quantity = 1,
        tierItemIDs = {
          238520,
          238521,
                },
            },
      {
        itemID = 246447,
        quantity = 1,
        tierItemIDs = {
          246447,
          246448,
          246449,
                },
            },
        },
    recipeName = "Scalewoven Hide",
    yieldMin = 1,
  })

Catalog:SetRecipe(1237577, {
    expansionID = 11,
    outputItemID = 244603,
    profession = "Leatherworking",
    professionID = 2915,
    reagents = {
      {
        itemID = 236951,
        quantity = 10,
        tierItemIDs = {
          236951,
                },
            },
      {
        itemID = 238523,
        quantity = 1,
        tierItemIDs = {
          238523,
                },
            },
      {
        itemID = 238522,
        quantity = 1,
        tierItemIDs = {
          238522,
                },
            },
      {
        itemID = 242788,
        quantity = 2,
        tierItemIDs = {
          242788,
          242789,
                },
            },
      {
        itemID = 238518,
        quantity = 1,
        tierItemIDs = {
          238518,
          238519,
                },
            },
      {
        itemID = 246447,
        quantity = 1,
        tierItemIDs = {
          246447,
          246448,
          246449,
                },
            },
        },
    recipeName = "Blessed Pango Charm",
    yieldMin = 1,
  })

Catalog:SetRecipe(1263553, {
    expansionID = 4,
    outputItemID = 258302,
    profession = "Tailoring",
    professionID = 2536,
    reagents = {
      {
        itemID = 251763,
        quantity = 8,
        tierItemIDs = {
          251763,
                },
            },
      {
        itemID = 82441,
        quantity = 5,
        tierItemIDs = {
          82441,
                },
            },
      {
        itemID = 74866,
        quantity = 10,
        tierItemIDs = {
          74866,
                },
            },
        },
    recipeName = "Pandaren Fishing Net",
    yieldMin = 1,
  })

-- Items
Catalog:SetItem(74866, {
    expansionID = 4,
    icon = 633440,
    name = "Golden Carp",
    rarity = 1,
  })

Catalog:SetItem(82441, {
    expansionID = 4,
    icon = 629486,
    name = "Bolt of Windwool Cloth",
    rarity = 1,
  })

Catalog:SetItem(232875, {
    expansionID = 11,
    icon = 7551418,
    name = "Spark of Radiance",
    rarity = 4,
  })

Catalog:SetItem(236761, {
    expansionID = 11,
    icon = 7290677,
    name = "Tranquility Bloom",
    rarity = 1,
  })

Catalog:SetItem(236774, {
    expansionID = 11,
    icon = 7291441,
    name = "Azeroot",
    rarity = 2,
  })

Catalog:SetItem(236776, {
    expansionID = 11,
    icon = 6658327,
    name = "Argentleaf",
    rarity = 2,
  })

Catalog:SetItem(236778, {
    expansionID = 11,
    icon = 7292343,
    name = "Mana Lily",
    rarity = 2,
  })

Catalog:SetItem(236949, {
    expansionID = 11,
    icon = 7549438,
    name = "Mote of Light",
    rarity = 3,
  })

Catalog:SetItem(236950, {
    icon = 7549437,
    name = "Mote of Primal Energy",
    rarity = 3,
  })

Catalog:SetItem(236951, {
    expansionID = 11,
    icon = 7549442,
    name = "Mote of Wild Magic",
    rarity = 3,
  })

Catalog:SetItem(236952, {
    expansionID = 11,
    icon = 7549440,
    name = "Mote of Pure Void",
    rarity = 3,
  })

Catalog:SetItem(236963, {
    expansionID = 11,
    icon = 7549247,
    name = "Bright Linen",
    rarity = 2,
  })

Catalog:SetItem(237364, {
    expansionID = 11,
    icon = 6725347,
    name = "Brilliant Silver Ore",
    rarity = 2,
  })

Catalog:SetItem(237366, {
    expansionID = 11,
    icon = 7549223,
    name = "Dazzling Thorium",
    rarity = 3,
  })

Catalog:SetItem(237830, {
    expansionID = 11,
    icon = 7195179,
    name = "Spellbreaker's Girdle",
    rarity = 4,
  })

Catalog:SetItem(237922, {
    expansionID = 11,
    icon = 7195218,
    name = "Blood-Tempered Leggings",
    rarity = 3,
  })

Catalog:SetItem(238197, {
    expansionID = 11,
    icon = 7548922,
    name = "Refulgent Copper Ingot",
    rarity = 2,
  })

Catalog:SetItem(238202, {
    expansionID = 11,
    icon = 7548920,
    name = "Gloaming Alloy",
    rarity = 2,
  })

Catalog:SetItem(238204, {
    expansionID = 11,
    icon = 7548919,
    name = "Sterling Alloy",
    rarity = 2,
  })

Catalog:SetItem(238511, {
    expansionID = 11,
    icon = 7549241,
    name = "Void-Tempered Leather",
    rarity = 1,
  })

Catalog:SetItem(238513, {
    expansionID = 11,
    icon = 7549246,
    name = "Void-Tempered Scales",
    rarity = 1,
  })

Catalog:SetItem(238518, {
    expansionID = 11,
    icon = 7549238,
    name = "Void-Tempered Hide",
    rarity = 3,
  })

Catalog:SetItem(238520, {
    expansionID = 11,
    icon = 7549234,
    name = "Void-Tempered Plating",
    rarity = 3,
  })

Catalog:SetItem(238522, {
    expansionID = 11,
    icon = 7549228,
    name = "Peerless Plumage",
    rarity = 2,
  })

Catalog:SetItem(238523, {
    expansionID = 11,
    icon = 7549231,
    name = "Carving Canine",
    rarity = 2,
  })

Catalog:SetItem(239669, {
    expansionID = 11,
    icon = 7266378,
    name = "Courtly Gloves",
    rarity = 3,
  })

Catalog:SetItem(239670, {
    expansionID = 11,
    icon = 7266372,
    name = "Courtly Belt",
    rarity = 3,
  })

Catalog:SetItem(239676, {
    expansionID = 11,
    icon = 7266381,
    name = "Courtly Pants",
    rarity = 3,
  })

Catalog:SetItem(239700, {
    expansionID = 11,
    icon = 7549249,
    name = "Bright Linen Bolt",
    rarity = 2,
  })

Catalog:SetItem(239711, {
    expansionID = 11,
    icon = 5976252,
    name = "Bright Linen Bandage",
    rarity = 1,
  })

Catalog:SetItem(240991, {
    expansionID = 11,
    icon = 7548906,
    name = "Sunglass Vial",
    rarity = 1,
  })

Catalog:SetItem(241287, {
    expansionID = 11,
    icon = 2057578,
    name = "Light's Preservation",
    rarity = 1,
  })

Catalog:SetItem(241301, {
    expansionID = 11,
    icon = 7548907,
    name = "Lightfused Mana Potion",
    rarity = 1,
  })

Catalog:SetItem(241309, {
    expansionID = 11,
    icon = 7548911,
    name = "Light's Potential",
    rarity = 1,
  })

Catalog:SetItem(242638, {
    expansionID = 11,
    icon = 7548894,
    name = "Recycle Flasks",
    rarity = 1,
  })

Catalog:SetItem(242788, {
    expansionID = 11,
    icon = 7549160,
    name = "Duskshrouded Stone",
    rarity = 1,
  })

Catalog:SetItem(243060, {
    expansionID = 11,
    icon = 4622294,
    name = "Luminant Flux",
    rarity = 1,
  })

Catalog:SetItem(243574, {
    expansionID = 11,
    icon = 7548994,
    name = "Song Gear",
    rarity = 2,
  })

Catalog:SetItem(243576, {
    expansionID = 11,
    icon = 7548996,
    name = "Soul Sprocket",
    rarity = 3,
  })

Catalog:SetItem(243599, {
    expansionID = 11,
    icon = 7548974,
    name = "Eversinging Dust",
    rarity = 1,
  })

Catalog:SetItem(244174, {
    expansionID = 11,
    icon = 7457449,
    name = "Refulgent Copper Rod",
    rarity = 1,
  })

Catalog:SetItem(244175, {
    expansionID = 11,
    icon = 7457449,
    name = "Runed Refulgent Copper Rod",
    rarity = 2,
  })

Catalog:SetItem(244574, {
    expansionID = 11,
    icon = 7287094,
    name = "Silvermoon Agent's Leggings",
    rarity = 4,
  })

Catalog:SetItem(244603, {
    expansionID = 11,
    icon = 804957,
    name = "Blessed Pango Charm",
    rarity = 3,
  })

Catalog:SetItem(244631, {
    expansionID = 11,
    icon = 7549204,
    name = "Scalewoven Hide",
    rarity = 3,
  })

Catalog:SetItem(244633, {
    expansionID = 11,
    icon = 7549201,
    name = "Infused Scalewoven Hide",
    rarity = 3,
  })

Catalog:SetItem(244635, {
    expansionID = 11,
    icon = 7549199,
    name = "Sin'dorei Armor Banding",
    rarity = 2,
  })

Catalog:SetItem(244697, {
    expansionID = 11,
    icon = 4548895,
    name = "Flux Cogwheel",
    rarity = 2,
  })

Catalog:SetItem(244701, {
    expansionID = 11,
    icon = 4548892,
    name = "Perfected Cogwheel",
    rarity = 2,
  })

Catalog:SetItem(245764, {
    expansionID = 11,
    icon = 960689,
    name = "Codified Azeroot",
    rarity = 3,
  })

Catalog:SetItem(245766, {
    expansionID = 11,
    icon = 4643991,
    name = "Soul Cipher",
    rarity = 3,
  })

Catalog:SetItem(245781, {
    expansionID = 11,
    icon = 4549168,
    name = "Thalassian Missive of the Aurora",
    rarity = 2,
  })

Catalog:SetItem(245801, {
    expansionID = 11,
    icon = 7549076,
    name = "Munsell Ink",
    rarity = 3,
  })

Catalog:SetItem(245805, {
    expansionID = 11,
    icon = 7549077,
    name = "Sienna Ink",
    rarity = 3,
  })

Catalog:SetItem(245820, {
    expansionID = 11,
    icon = 4549162,
    name = "Thalassian Missive of Crafting Speed",
    rarity = 2,
  })

Catalog:SetItem(246211, {
    icon = 134400,
  })

Catalog:SetItem(246447, {
    expansionID = 11,
    icon = 134391,
    name = "Apprentice's Scribbles",
    rarity = 1,
  })

Catalog:SetItem(247811, {
    expansionID = 11,
    icon = 2032169,
    name = "Oil of Heartwood",
    rarity = 1,
  })

Catalog:SetItem(251283, {
    expansionID = 11,
    icon = 4622301,
    name = "Tormented Tantalum",
    rarity = 3,
  })

Catalog:SetItem(251665, {
    expansionID = 11,
    icon = 7549368,
    name = "Silverleaf Thread",
    rarity = 1,
  })

Catalog:SetItem(251691, {
    expansionID = 11,
    icon = 7549316,
    name = "Embroidery Floss",
    rarity = 2,
  })

Catalog:SetItem(251763, {
    expansionID = 4,
    icon = 7467223,
    name = "Bamboo Lumber",
    rarity = 2,
  })

Catalog:SetItem(253303, {
    expansionID = 11,
    icon = 6383560,
    name = "Pile of Junk",
    rarity = 2,
  })

Catalog:SetItem(258302, {
    expansionID = 4,
    icon = 7467929,
    name = "Pandaren Fishing Net",
    rarity = 2,
  })

-- Preferred output recipes
Catalog:SetRecipeForOutput(237830, 1229666)
Catalog:SetRecipeForOutput(237922, 1229624)
Catalog:SetRecipeForOutput(238204, 1230763)
Catalog:SetRecipeForOutput(239669, 1228952)
Catalog:SetRecipeForOutput(239670, 1228953)
Catalog:SetRecipeForOutput(239676, 1228956)
Catalog:SetRecipeForOutput(239700, 1228939)
Catalog:SetRecipeForOutput(239711, 1228941)
Catalog:SetRecipeForOutput(241287, 1230858)
Catalog:SetRecipeForOutput(241301, 1230865)
Catalog:SetRecipeForOutput(241309, 1230869)
Catalog:SetRecipeForOutput(242638, 1233130)
Catalog:SetRecipeForOutput(244175, 1236486)
Catalog:SetRecipeForOutput(244574, 1237511)
Catalog:SetRecipeForOutput(244603, 1237577)
Catalog:SetRecipeForOutput(244631, 1237572)
Catalog:SetRecipeForOutput(244697, 1229859)
Catalog:SetRecipeForOutput(244701, 1229856)
Catalog:SetRecipeForOutput(245764, 1230018)
Catalog:SetRecipeForOutput(245766, 1230019)
Catalog:SetRecipeForOutput(258302, 1263553)

-- Output recipe lists
Catalog:SetRecipesForOutput(237830, {
    1229666,
  })

Catalog:SetRecipesForOutput(237922, {
    1229624,
  })

Catalog:SetRecipesForOutput(238204, {
    1230763,
  })

Catalog:SetRecipesForOutput(239669, {
    1228952,
  })

Catalog:SetRecipesForOutput(239670, {
    1228953,
  })

Catalog:SetRecipesForOutput(239676, {
    1228956,
  })

Catalog:SetRecipesForOutput(239700, {
    1228939,
  })

Catalog:SetRecipesForOutput(239711, {
    1228941,
  })

Catalog:SetRecipesForOutput(241287, {
    1230858,
  })

Catalog:SetRecipesForOutput(241301, {
    1230865,
  })

Catalog:SetRecipesForOutput(241309, {
    1230869,
  })

Catalog:SetRecipesForOutput(242638, {
    1233130,
  })

Catalog:SetRecipesForOutput(244175, {
    1236486,
  })

Catalog:SetRecipesForOutput(244574, {
    1237511,
  })

Catalog:SetRecipesForOutput(244603, {
    1237577,
  })

Catalog:SetRecipesForOutput(244631, {
    1237572,
  })

Catalog:SetRecipesForOutput(244697, {
    1229859,
  })

Catalog:SetRecipesForOutput(244701, {
    1229856,
  })

Catalog:SetRecipesForOutput(245764, {
    1230018,
  })

Catalog:SetRecipesForOutput(245766, {
    1230019,
  })

Catalog:SetRecipesForOutput(258302, {
    1263553,
  })
-- DSLCATALOG_DATA_END

