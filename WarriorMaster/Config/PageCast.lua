--[[
Warrior Master - Config/PageCast.lua
Cast bar page.
]]
local _, ns = ...

local H = ns.ConfigHelpers

ns.Config:RegisterPage({
	key = "cast",
	titleKey = "MODULE_CAST",
	order = 45,
	build = function(page)
		local L = ns.L

		page:Header(L.MODULE_CAST)
		page:Note(L.CAST_SOURCE_NOTE, "info")
		H.Check(page, "cast.enabled", L.ENABLE)
		H.VisibilityDropdown(page, "cast")
		H.StyleSection(page, "cast")

		page:Header(L.SECTION_BEHAVIOR)
		H.Check(page, "cast.showIcon", L.CAST_SHOW_ICON)
		H.Check(page, "cast.showName", L.CAST_SHOW_NAME)
		H.Check(page, "cast.fadeOut", L.CAST_FADE)
		H.ColorPick(page, "cast.colorCast", L.CAST_COLOR_CAST)
		H.ColorPick(page, "cast.colorChannel", L.CAST_COLOR_CHANNEL)
		H.ColorPick(page, "cast.colorSuccess", L.CAST_COLOR_SUCCESS)
		H.ColorPick(page, "cast.colorFailed", L.CAST_COLOR_FAILED)
		page:Note(L.CAST_COLOR_NOTE)

		H.LayoutSection(page, "cast")
		H.AppearanceSection(page, "cast")
		H.TextSection(page, "cast", {
			formatPath = "cast.textMode",
			formatLabel = L.CAST_TEXT,
			formatLabels = { none = "SWING_TEXT_NONE", remaining = "SWING_TEXT_REMAINING", both = "SWING_TEXT_BOTH" },
		})
		page:Note(L.CAST_GAME_BAR_NOTE)

		H.ResetModuleButton(page, "cast", "MODULE_CAST")
	end,
})
