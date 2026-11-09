--[[
Warrior Master - Config/PageGeneral.lua
Modules, frame locking, preview mode, position, automatic layout, presets,
sounds, warrior fun, language, maintenance.
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
			{ "cast", "MODULE_CAST" },
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

		-- Automatic vertical layout: on/off, gap, alignment, order.
		page:Header(L.SECTION_AUTO_LAYOUT)
		do
			local get, set = UI.Bind("general.layout.enabled")
			page:Checkbox({ label = L.LAYOUT_ENABLE, get = get, set = set }, true)
		end
		local function layoutOff()
			return not ns.db.profile.general.layout.enabled
		end
		do
			local get, set = UI.Bind("general.layout.gap")
			page:Slider({ label = L.LAYOUT_GAP, min = 0, max = 60, step = 1, get = get, set = set, disabled = layoutOff })
		end
		do
			local get, set = UI.Bind("general.layout.align")
			page:Dropdown({
				label = L.LAYOUT_ALIGN,
				options = UI.Options({ "LEFT", "CENTER", "RIGHT" }, { LEFT = "ALIGN_LEFT", CENTER = "ALIGN_CENTER", RIGHT = "ALIGN_RIGHT" }),
				get = get,
				set = set,
				disabled = layoutOff,
			})
		end
		page:OrderList({
			count = #ns.Layout.KEYS,
			disabled = layoutOff,
			items = function()
				local items = {}
				for _, key in ipairs(ns.db.profile.general.layout.order) do
					local module = ns.modules[key]
					local on = ns.db.profile[key].enabled
					local text = L[module and module.titleKey or key] or key
					local elsewhere = on and key == "stance" and module and module:UsesGameBar()
					if not on then
						text = text .. "  " .. L.LAYOUT_OFF
					elseif elsewhere then
						text = text .. "  " .. L.LAYOUT_GAME_BAR
					end
					items[#items + 1] = { value = key, text = text, dim = not on or elsewhere }
				end
				return items
			end,
			move = function(key, step)
				return ns.Layout:Move(key, step)
			end,
		})
		page:Skip()
		page:Note(L.LAYOUT_NOTE)

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

		page:Header(L.SECTION_FLAIR)
		do
			local get, set = UI.Bind("general.flair.enabled")
			page:Checkbox({ label = L.FLAIR_ENABLE, get = get, set = set }, true)
		end
		local function flairOff()
			return not ns.db.profile.general.flair.enabled
		end
		do
			local get, set = UI.Bind("general.flair.chance")
			page:Slider({ label = L.FLAIR_CHANCE, min = 0, max = 100, step = 5, get = get, set = set, disabled = flairOff })
		end
		do
			local get, set = UI.Bind("general.flair.closeShout")
			page:Checkbox({ label = L.FLAIR_CLOSE, get = get, set = set, disabled = flairOff })
		end
		page:Button({
			text = L.FLAIR_TRY,
			disabled = flairOff,
			noFlair = true,
			onClick = function()
				ns.Flair:Execute(true)
			end,
		})
		page:Note(L.FLAIR_NOTE)

		page:Header(L.SECTION_INTERFACE)
		page:Checkbox({
			label = L.MINIMAP_SHOW,
			get = function()
				return ns.db.global.minimap.show
			end,
			set = function(value)
				ns.DB:SetGlobal("minimap.show", value)
			end,
		})
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
