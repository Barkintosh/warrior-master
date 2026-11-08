--[[
Warrior Master - Config/PageSwing.lua
Swing timer page.
]]
local _, ns = ...

local H = ns.ConfigHelpers

ns.Config:RegisterPage({
	key = "swing",
	titleKey = "MODULE_SWING",
	order = 40,
	build = function(page)
		local L = ns.L
		local Compat = ns.Compat

		page:Header(L.MODULE_SWING)
		if not Compat.hasNativeSwing then
			page:Note(L.SWING_UNSUPPORTED, "bad")
		end
		page:Note(L.SWING_SOURCE_NOTE, "info")
		H.Check(page, "swing.enabled", L.ENABLE)
		H.VisibilityDropdown(page, "swing")
		H.StyleSection(page, "swing")
		H.Check(page, "swing.hideIdle", L.SWING_HIDE_IDLE, { full = true })

		page:Header(L.SECTION_BEHAVIOR)
		H.Check(page, "swing.showMainHand", L.SWING_SHOW_MH)
		H.ColorPick(page, "swing.colorMainHand", L.SWING_COLOR_MH)
		H.Check(page, "swing.showOffHand", L.SWING_SHOW_OH)
		H.ColorPick(page, "swing.colorOffHand", L.SWING_COLOR_OH)
		H.Check(page, "swing.showRanged", L.SWING_SHOW_RANGED)
		H.ColorPick(page, "swing.colorRanged", L.SWING_COLOR_RANGED)
		H.EnumDropdown(page, "swing.fill", L.SWING_FILL, { fill = "SWING_FILL_FILL", deplete = "SWING_FILL_DEPLETE" })
		H.NumberSlider(page, "swing.spacing", L.SWING_SPACING)
		H.Check(page, "swing.hasteRescale", L.SWING_HASTE, { full = true })
		H.Check(page, "swing.sound", L.SWING_SOUND, { full = true })
		H.SoundPicker(page, "swing.soundKey", L.ALERT_SOUND_CHOICE, {
			disabled = function()
				return not ns.db.profile.swing.sound
			end,
		})
		H.Check(page, "swing.rangeCheck", L.SWING_RANGE, {
			full = true,
			disabled = function()
				return not Compat.hasRangeCheck
			end,
		})

		H.LayoutSection(page, "swing")
		H.AppearanceSection(page, "swing")
		H.TextSection(page, "swing", {
			formatPath = "swing.textMode",
			formatLabel = L.SWING_TEXT,
			formatLabels = { none = "SWING_TEXT_NONE", remaining = "SWING_TEXT_REMAINING", both = "SWING_TEXT_BOTH" },
		})
		H.Check(page, "swing.labels", L.SWING_LABELS)

		page:Header(L.SWING_CVAR)
		page:Text({
			height = 16,
			color = "text",
			get = function()
				local state = Compat.GetCVarBool("showSwingTimer")
				local text = state == nil and L.SWING_CVAR_UNKNOWN or (state and L.SWING_CVAR_ON or L.SWING_CVAR_OFF)
				return L.SWING_CVAR_STATE:format(text), state and "good" or "warn"
			end,
		})
		page:Button({
			text = L.SWING_CVAR_ENABLE,
			disabled = function()
				return Compat.GetCVarBool("showSwingTimer") == true
			end,
			onClick = function()
				local swing = ns:GetModule("swing")
				if swing and swing:EnableClientSwingTimer() then
					ns:Print(L.SWING_CVAR_DONE)
				else
					ns:Print(L.COMBAT_BLOCKED)
				end
			end,
		})
		page:Skip()
		page:Note(L.SWING_CVAR_HINT)
		page:Note(L.SWING_ENEMY_NOTE, "bad")

		H.ResetModuleButton(page, "swing", "MODULE_SWING")
	end,
})
