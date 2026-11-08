--[[
Warrior Master - Config/PageGeneral.lua
Modules, frame locking, preview mode, presets, sounds, language, maintenance.
]]
local _, ns = ...

local UI = ns.UI
local Media = ns.Media

ns.Config:RegisterPage({
	key = "general",
	titleKey = "PAGE_GENERAL",
	order = 10,
	build = function(page)
		local L = ns.L

		page:Header(L.SECTION_MODULES)
		for _, entry in ipairs({
			{ "health", "MODULE_HEALTH" },
			{ "rage", "MODULE_RAGE" },
			{ "swing", "MODULE_SWING" },
			{ "stance", "MODULE_STANCE" },
		}) do
			local get, set = UI.Bind(entry[1] .. ".enabled")
			page:Checkbox({ label = L[entry[2]], get = get, set = set })
		end

		page:Header(L.SECTION_FRAMES)
		page:Checkbox({
			label = L.UNLOCK,
			get = function()
				return not ns.db.profile.general.locked
			end,
			set = function(value)
				ns.DB:Set("general.locked", not value)
			end,
		})
		page:Button({
			text = L.RESET_POSITION,
			onClick = function()
				ns:ResetPositions()
			end,
		})
		page:Note(L.LOCKED_HINT)
		page:Checkbox({
			label = L.TEST_MODE,
			get = function()
				return ns.TestMode:IsActive()
			end,
			set = function(value)
				ns.TestMode:SetActive(value)
			end,
		}, true)
		page:Note(L.TEST_MODE_DESC)

		page:Header(L.SECTION_POSITION_ALL)
		page:Note(L.MOVE_ALL_HINT)
		do
			local get, set = UI.Bind("general.offsetX")
			page:Slider({ label = L.OFFSET_X, min = -2000, max = 2000, step = 1, get = get, set = set })
		end
		do
			local get, set = UI.Bind("general.offsetY")
			page:Slider({ label = L.OFFSET_Y, min = -2000, max = 2000, step = 1, get = get, set = set })
		end
		do
			local get, set = UI.Bind("general.clampAll")
			page:Checkbox({ label = L.CLAMP_ALL, get = get, set = set })
		end
		page:Button({
			text = L.RESET_POSITION,
			onClick = function()
				ns.DB:Set("general.offsetX", 0)
				ns.DB:Set("general.offsetY", 0)
			end,
		})

		-- Style picker: which style, which modules, which parts.
		local Styles = ns.Styles
		page:Header(L.SECTION_PRESETS)
		page:Note(L.PRESET_NOTE)
		do
			local get, set = UI.Bind("general.styleChoice")
			page:Dropdown({ label = L.PRESET, options = UI.Options(ns.Presets.ORDER, ns.Presets.LABEL_KEYS), get = get, set = set })
		end
		do
			local get, set = UI.Bind("general.styleTarget")
			page:Dropdown({
				label = L.STYLE_TARGET,
				options = function()
					local items = { { value = "all", text = L.TARGET_ALL } }
					for _, section in ipairs(Styles.SECTIONS) do
						items[#items + 1] = { value = section, text = L[Styles.SECTION_LABELS[section]] }
					end
					return items
				end,
				get = get,
				set = set,
			})
		end
		page:Text({ text = L.STYLE_PARTS, color = "text", height = 16 })
		for _, part in ipairs(Styles.PARTS) do
			local get, set = UI.Bind("general.styleParts." .. part)
			page:Checkbox({ label = L[Styles.PART_LABELS[part]], get = get, set = set })
		end
		page:Button({
			text = L.STYLE_APPLY,
			onClick = function()
				local g = ns.db.profile.general
				local parts, any = {}, false
				for _, part in ipairs(Styles.PARTS) do
					parts[part] = g.styleParts[part] and true or nil
					any = any or g.styleParts[part]
				end
				if not any then
					ns:Print(L.STYLE_NOTHING)
					return
				end
				local sections = g.styleTarget ~= "all" and { g.styleTarget } or nil
				if ns:ApplyStyle(g.styleChoice, sections, parts) then
					local target = sections and L[Styles.SECTION_LABELS[g.styleTarget]] or L.TARGET_ALL
					ns:Print(L.STYLE_APPLIED:format(L[ns.Presets.LABEL_KEYS[g.styleChoice]], target))
				end
			end,
		})
		page:Skip()
		page:Text({
			height = 30,
			color = "dim",
			size = 11,
			get = function()
				local list = {}
				for _, section in ipairs(Styles.SECTIONS) do
					local style = ns.db.profile[section].style
					list[#list + 1] = L[Styles.SECTION_LABELS[section]] .. ": " .. L[ns.Presets.LABEL_KEYS[style]]
				end
				return L.STYLE_CURRENT_ALL:format(table.concat(list, "  -  ")), "dim"
			end,
		})

		page:Header(L.SECTION_SOUND)
		do
			local get, set = UI.Bind("general.sounds")
			page:Checkbox({ label = L.SOUNDS, get = get, set = set })
		end
		do
			local get, set = UI.Bind("general.soundChannel")
			page:Dropdown({
				label = L.SOUND_CHANNEL,
				options = UI.Options(Media.SOUND_CHANNELS, Media.CHANNEL_LABELS),
				get = get,
				set = set,
				disabled = function()
					return not ns.db.profile.general.sounds
				end,
			})
		end

		page:Header(L.SECTION_INTERFACE)
		page:Dropdown({
			label = L.LANGUAGE,
			options = function()
				return {
					{ value = "auto", text = L.LANG_AUTO },
					{ value = "enUS", text = "English" },
					{ value = "frFR", text = "Français" },
				}
			end,
			get = function()
				return ns.db.global.language
			end,
			set = function(value)
				if value ~= ns.db.global.language then
					ns.DB:SetLanguage(value)
					ns:Print(ns.L.RELOAD_REQUIRED)
				end
			end,
		})
		page:Skip()

		page:Header(L.SECTION_MAINTENANCE)
		page:Button({
			text = L.DIAGNOSTICS,
			onClick = function()
				ns:PrintDiagnostics()
			end,
		})
		page:Button({
			text = L.RESET_ALL,
			confirm = true,
			onClick = function()
				ns.DB:ResetProfile()
				ns:Print(L.RESET_DONE)
			end,
		})
	end,
})
