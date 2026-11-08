--[[
Warrior Master - Config/PageMacros.lua
Visual macro builder: pick a template, set its options, preview, copy or
save. The preview can be edited by hand; whatever is saved is validated
first (length, no script commands). Saving never runs the macro.
]]
local _, ns = ...

local UI = ns.UI
local MB = ns.MacroBuilder
local T = ns.MacroTemplates
local U = ns.Util

local MAX_OPTION_SLOTS = 3

local ITEM_FILTERS = {
	twohand = { list = "mainHand", test = function(e) return e.equipLoc == "INVTYPE_2HWEAPON" end },
	mainhand = { list = "mainHand", test = function(e) return e.equipLoc ~= "INVTYPE_2HWEAPON" end },
	shield = { list = "offHand", test = function(e) return e.equipLoc == "INVTYPE_SHIELD" end },
}

ns.Config:RegisterPage({
	key = "macros",
	titleKey = "MODULE_MACROS",
	order = 60,
	build = function(page)
		local L = ns.L
		local state = { category = "all", lastBuild = nil, status = "", statusColor = "dim" }

		local function templateID()
			local id = ns.db.char.macro.template
			if not T.byId[id] then
				id = T.list[1].id
			end
			return id
		end
		local function template()
			return T.byId[templateID()]
		end

		page:Header(L.MODULE_MACROS)
		page:Note(L.MACRO_POLICY, "info")

		page:Dropdown({
			label = L.MACRO_CATEGORY,
			options = function()
				local items = { { value = "all", text = L.CAT_ALL } }
				for _, cat in ipairs(T.CATEGORIES) do
					items[#items + 1] = { value = cat, text = L[T.CATEGORY_LABELS[cat]] }
				end
				return items
			end,
			get = function()
				return state.category
			end,
			set = function(value)
				state.category = value
			end,
		})
		page:Dropdown({
			label = L.MACRO_TEMPLATE,
			options = function()
				local items = {}
				for _, t in ipairs(MB.ListTemplates(state.category)) do
					items[#items + 1] = { value = t.id, text = L[t.nameKey] }
				end
				return items
			end,
			get = templateID,
			set = function(value)
				ns.DB:SetChar("macro.template", value)
				ns.DB:SetChar("macro.name", "")
			end,
		})
		page:Text({
			height = 46,
			color = "text",
			get = function()
				return L[template().descKey], "text"
			end,
		})

		-- Option slots: each slot holds a checkbox and a dropdown at the same
		-- place; the template decides which one is visible.
		page:Header(L.MACRO_OPTIONS)
		local slots = {}
		local function optionAt(i)
			return template().options[i]
		end
		for i = 1, MAX_OPTION_SLOTS do
			local slot = {}
			slot.dropdown = page:Dropdown({
				label = "",
				options = function()
					local option = optionAt(i)
					if not option or option.kind == "bool" then
						return {}
					end
					if option.kind == "choice" then
						return UI.Options(option.values, option.labels)()
					end
					local items = { { value = 0, text = L.OPT_CHOOSE_ITEM } }
					local filter = ITEM_FILTERS[option.slot]
					if not filter then
						return items
					end
					local scan = ns:GetModule("stance"):ScanWeapons()
					for _, entry in ipairs(scan[filter.list]) do
						if filter.test(entry) then
							items[#items + 1] = { value = entry.id, text = entry.name }
						end
					end
					return items
				end,
				get = function()
					local option = optionAt(i)
					if not option then
						return nil
					end
					local value = MB.GetOptions(templateID())[option.key]
					if option.kind == "item" then
						return value or 0
					end
					return value
				end,
				set = function(value)
					local option = optionAt(i)
					if option then
						if option.kind == "item" and value == 0 then
							value = nil
						end
						MB.SetOption(templateID(), option.key, value)
					end
				end,
			}, true)
			slot.check = UI.Checkbox(page, {
				label = "",
				get = function()
					local option = optionAt(i)
					return option and MB.GetOptions(templateID())[option.key] or false
				end,
				set = function(value)
					local option = optionAt(i)
					if option then
						MB.SetOption(templateID(), option.key, value)
					end
				end,
			})
			slot.check.frame:SetPoint("TOPLEFT", slot.dropdown.frame, "TOPLEFT", 0, -10)
			slot.check.frame:SetPoint("RIGHT", slot.dropdown.frame, "RIGHT", 0, 0)
			slots[i] = slot
		end

		page:Header(L.MACRO_PREVIEW)
		local validation
		local preview = page:TextArea({
			height = 110,
			maxLetters = 1024,
			onChange = function()
				if validation then
					validation.Refresh()
				end
			end,
		})
		validation = page:Text({
			height = 46,
			size = 11,
			get = function()
				local text = preview.GetValue()
				local result = MB.Validate(text)
				local lines = { L.MACRO_LENGTH:format(result.length, MB.MAX_CHARS) }
				local _, missing = MB.Build(templateID())
				for _, key in ipairs(missing) do
					lines[#lines + 1] = L.MACRO_ERR_ITEM:format(L[key])
				end
				for _, err in ipairs(result.errors) do
					lines[#lines + 1] = err
				end
				for _, warning in ipairs(result.warnings) do
					lines[#lines + 1] = warning
				end
				if result.ok and #missing == 0 and #result.warnings == 0 then
					lines[#lines + 1] = L.MACRO_VALID
					return table.concat(lines, "  -  "), "good"
				end
				return table.concat(lines, "\n"), (result.ok and #missing == 0) and "warn" or "bad"
			end,
		})

		page:EditBox({
			label = L.MACRO_NAME,
			maxLetters = MB.MAX_NAME,
			get = function()
				local name = ns.db.char.macro.name
				if name == "" then
					name = U.Utf8Sub(L[template().nameKey], MB.MAX_NAME)
				end
				return name
			end,
			set = function(value)
				ns.DB:SetChar("macro.name", value)
			end,
		})
		page:Checkbox({
			label = L.MACRO_PERCHAR,
			get = function()
				return ns.db.char.macro.perCharacter
			end,
			set = function(value)
				ns.DB:SetChar("macro.perCharacter", value)
			end,
		})
		page:Button({
			text = L.MACRO_CREATE,
			onClick = function()
				local name = ns.db.char.macro.name
				if name == "" then
					name = U.Utf8Sub(L[template().nameKey], MB.MAX_NAME)
				end
				local ok, message = MB.Save(name, preview.GetValue(), ns.db.char.macro.perCharacter, MB.GetIcon(templateID()))
				state.status, state.statusColor = message, ok and "good" or "bad"
				ns:Print(message)
			end,
		})
		page:Button({
			text = L.MACRO_SELECT,
			onClick = function()
				preview.SelectAll()
				state.status, state.statusColor = L.MACRO_SELECT_HINT, "info"
			end,
		})
		page:Text({
			height = 32,
			get = function()
				return state.status, state.statusColor
			end,
		})

		-- Called at the end of every page refresh: show the right option
		-- controls and regenerate the preview when the template or options change.
		page.onRefresh = function()
			local t = template()
			for i, slot in ipairs(slots) do
				local option = t.options[i]
				local isBool = option and option.kind == "bool"
				slot.check.frame:SetShown(isBool and true or false)
				slot.dropdown.frame:SetShown(option ~= nil and not isBool)
				if option then
					slot.check.SetLabel(L[option.labelKey])
					slot.dropdown.SetLabel(L[option.labelKey])
					if isBool then
						slot.check.Refresh()
					else
						slot.dropdown.Refresh()
					end
				end
			end
			local options = MB.GetOptions(t.id)
			local key = t.id
			for _, option in ipairs(t.options) do
				key = key .. "|" .. tostring(options[option.key])
			end
			if key ~= state.lastBuild then
				state.lastBuild = key
				local text = MB.Build(t.id, options)
				preview.SetValue(text)
			end
			validation.Refresh()
		end
	end,
})
