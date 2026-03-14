-- DecorShoppingList/Data.lua
local ADDON, ns = ...
ns = ns or {}
ns.Data = ns.Data or {}

ns.GetPlayerProfessionSet = ns.Snapshots.GetPlayerProfessionSet
ns.PlayerHasProfession = ns.Snapshots.PlayerHasProfession
ns.AnyCharHasProfession = ns.Snapshots.AnyCharHasProfession
ns.SnapshotCurrentCharacter = ns.Snapshots.SnapshotCurrentCharacter

ns.SnapshotLearnedRecipes = ns.Snapshots.SnapshotLearnedRecipes
ns.IsRecipeLearned = ns.Snapshots.IsRecipeLearned
ns.ScanCurrentProfessionLearned = ns.Snapshots.ScanCurrentProfessionLearned

ns.GetRecipeOutputItemID = ns.Recipes.GetRecipeOutputItemID
ns.SetGoalForRecipe = ns.Recipes.SetGoalForRecipe
ns.ApplyCompletionByInventoryDelta = ns.Recipes.ApplyCompletionByInventoryDelta
ns.RecomputeReagentsOnly = ns.Reagents.RecomputeReagentsOnly
ns.RecomputeDisplayOnly = ns.Recipes.RecomputeDisplayOnly
ns.RecomputeCaches = ns.Recipes.RecomputeCaches
ns.AccumulateReagentsForRecipe = ns.Recipes.AccumulateReagentsForRecipe
