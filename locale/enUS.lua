local ADDON, ns = ...

local L = LibStub("AceLocale-3.0"):NewLocale("DecorShoppingList", "enUS", true)
if not L then return end

L["ADDON_NAME"] = "Decor Shopping List"
L["SLASH_HELP"] = "Commands: /dsl (toggle + help), /dsl show, /dsl hide, /dsl config, /dsl settings, /dsl reset, /dsl alts"
L["COMPLETED_RECIPE"] = "Decor Shopping List: %s completed."
L["RECIPES"] = "Recipes"
L["REAGENTS"] = "Reagents"
L["NEED"] = "Need"
L["HAVE"] = "Have"
L["REMAINING"] = "Remaining"
L["INCLUDE_ALTS"] = "Include alts"
L["MINIMAP_TOGGLE"] = "Toggle window"
L["TRACK"] = "Track"
L["UNTRACK"] = "Untrack"
L["QTY"] = "Qty"
L["RESET_POS"] = "Window position reset."
L["UPDATED"] = "Updated."
L["NO_RECIPE_SELECTED"] = "No recipe selected."
L["INVALID_QTY"] = "Invalid quantity."
L["CLEAR"] = "Clear"
