--[[
Warrior Master - Modules/MacroBuilder.lua
Turns templates into macro text, validates it and (on request) saves it.

- Build/Validate are pure text operations (covered by offline tests).
- Save uses CreateMacro / EditMacro (legacy globals present in the 1.60.1
  client, used by Blizzard_MacroUI). It runs only from a button click,
  only out of combat, only after validation, and never runs the macro.
]]
local _, ns = ...

local Compat = ns.Compat
local Security = ns.Security
local U = ns.Util
local T = ns.MacroTemplates

local MB = {}
ns.MacroBuilder = MB

MB.MAX_CHARS = 255 -- Blizzard_MacroUI: MacroFrameText letters="255"
MB.MAX_NAME = 16
MB.ICON_DEFAULT = 134400 -- INV_Misc_QuestionMark

local function macroLimits()
	local consts = Constants and Constants.MacroConsts
	local account = consts and Compat.ReadableNumber(consts.MAX_ACCOUNT_MACROS) or 120
	local character = consts and Compat.ReadableNumber(consts.MAX_CHARACTER_MACROS) or 30
	return account, character
end
MB.GetLimits = macroLimits

function MB.GetTemplate(id)
	return T.byId[id]
end

--- Templates of a category (or all), in definition order.
function MB.ListTemplates(category)
	local out = {}
	for _, template in ipairs(T.list) do
		if not category or category == "all" or template.category == category then
			out[#out + 1] = template
		end
	end
	return out
end

--- Saved options merged over the template defaults.
function MB.GetOptions(id)
	local template = T.byId[id]
	local saved = ns.db and ns.db.char.macro.options[id] or {}
	local out = {}
	if not template then
		return out
	end
	for _, option in ipairs(template.options) do
		local value = saved[option.key]
		if option.kind == "bool" then
			if type(value) ~= "boolean" then
				value = option.default
			end
		elseif option.kind == "choice" then
			if not U.IndexOf(option.values, value) then
				value = option.default
			end
		elseif option.kind == "item" then
			if not (type(value) == "number" and value >= 1 and math.floor(value) == value) then
				value = nil
			end
		end
		out[option.key] = value
	end
	return out
end

function MB.SetOption(id, key, value)
	local options = U.DeepCopy(ns.db.char.macro.options)
	options[id] = options[id] or {}
	options[id][key] = value
	ns.DB:SetChar("macro.options", options)
end

-- Name resolution ------------------------------------------------------------------------------
function MB.SpellName(key)
	local id = T.SPELLS[key]
	local name = id and Compat.GetSpellName(id)
	if not name then
		name = ns.L["SPELL_" .. key:upper()]
	end
	return Security.SanitizeMacroToken(name, 64)
end

function MB.ShieldsName()
	local armor = (Enum and Enum.ItemClass and Enum.ItemClass.Armor) or 4
	local shield = (Enum and Enum.ItemArmorSubclass and Enum.ItemArmorSubclass.Shield) or 6
	return Security.SanitizeMacroToken(Compat.GetItemSubClassName(armor, shield) or ns.L.EQUIP_SHIELDS, 32)
end

function MB.TwoHandName()
	local name = INVTYPE_2HWEAPON
	if type(name) ~= "string" or name == "" then
		name = ns.L.EQUIP_TWOHAND
	end
	return Security.SanitizeMacroToken(name, 32)
end

--- Item text for a macro line: the item name when known, else "item:ID".
function MB.ItemText(itemID)
	if type(itemID) ~= "number" then
		return nil
	end
	local name = Compat.GetItemName(itemID)
	local token = name and Security.SanitizeMacroToken(name, 80)
	if token and token ~= "" then
		return token
	end
	return "item:" .. string.format("%d", itemID)
end

-- Build -----------------------------------------------------------------------------------------------
--- Returns the macro text and a list of option labels that still need a value.
function MB.Build(id, options)
	local template = T.byId[id]
	if not template then
		return "", {}
	end
	options = options or MB.GetOptions(id)
	local missing = {}
	local ctx = {
		shields = MB.ShieldsName(),
		twoHand = MB.TwoHandName(),
	}
	function ctx.spell(key)
		return MB.SpellName(key)
	end
	function ctx.opt(key)
		return options[key]
	end
	function ctx.item(key)
		local text = MB.ItemText(options[key])
		if text then
			return text
		end
		for _, option in ipairs(template.options) do
			if option.key == key then
				missing[#missing + 1] = option.labelKey
			end
		end
		return "?"
	end
	local lines = template.build(ctx)
	return table.concat(lines, "\n"), missing
end

--- Icon for the macro: the main spell's icon, or the question mark.
function MB.GetIcon(id)
	local template = T.byId[id]
	local spell = template and template.iconSpell and T.SPELLS[template.iconSpell]
	return (spell and Compat.GetSpellIcon(spell)) or MB.ICON_DEFAULT
end

-- Validate -------------------------------------------------------------------------------------------
--- Returns { ok, length, errors = {localized}, warnings = {localized} }.
function MB.Validate(text)
	local L = ns.L
	text = tostring(text or "")
	local result = { ok = true, length = U.Utf8Len(text), errors = {}, warnings = {} }
	local function fail(message)
		result.ok = false
		result.errors[#result.errors + 1] = message
	end
	if U.Trim(text) == "" then
		fail(L.MACRO_ERR_EMPTY)
	end
	if result.length > MB.MAX_CHARS then
		fail(L.MACRO_ERR_LENGTH:format(MB.MAX_CHARS))
	end
	local forbidden = Security.FindForbiddenCommand(text)
	if forbidden then
		fail(L.MACRO_ERR_FORBIDDEN:format(forbidden))
	end
	for i, line in ipairs(U.SplitLines(text)) do
		if U.Trim(line) ~= "" and not line:match("^%s*[/#]") then
			result.warnings[#result.warnings + 1] = L.MACRO_WARN_LINE:format(i)
		end
	end
	return result
end

function MB.CleanName(name)
	local clean = Security.SanitizeMacroToken(name, MB.MAX_NAME)
	if clean == "" or U.Utf8Len(clean) > MB.MAX_NAME then
		return nil
	end
	return clean
end

--- Finds an existing macro by exact name in the account or character range.
function MB.FindMacro(name, perCharacter)
	if type(GetMacroInfo) ~= "function" then
		return nil
	end
	local account, character = macroLimits()
	local first, last = 1, account
	if perCharacter then
		first, last = account + 1, account + character
	end
	for index = first, last do
		local ok, existing = pcall(GetMacroInfo, index)
		if ok and existing == name then
			return index
		end
	end
	return nil
end

--- Creates or updates a macro. Returns ok, localized message.
function MB.Save(name, text, perCharacter, icon)
	local L = ns.L
	if Compat.InCombatLockdown() then
		return false, L.MACRO_ERR_COMBAT
	end
	local check = MB.Validate(text)
	if not check.ok then
		return false, check.errors[1]
	end
	local clean = MB.CleanName(name)
	if not clean then
		return false, L.MACRO_ERR_NAME
	end
	if type(CreateMacro) ~= "function" or type(EditMacro) ~= "function" or type(GetNumMacros) ~= "function" then
		return false, L.MACRO_ERR_API
	end
	icon = icon or MB.ICON_DEFAULT
	perCharacter = perCharacter and true or false

	local index = MB.FindMacro(clean, perCharacter)
	if index then
		local ok, err = pcall(EditMacro, index, clean, icon, text)
		if not ok then
			return false, L.MACRO_ERR_FAILED:format(tostring(err))
		end
		return true, L.MACRO_UPDATED:format(clean)
	end

	local okCount, numAccount, numCharacter = pcall(GetNumMacros)
	numAccount = okCount and Compat.ReadableNumber(numAccount) or 0
	numCharacter = okCount and Compat.ReadableNumber(numCharacter) or 0
	local maxAccount, maxCharacter = macroLimits()
	if perCharacter and numCharacter >= maxCharacter then
		return false, L.MACRO_ERR_FULL:format(numCharacter, maxCharacter)
	elseif not perCharacter and numAccount >= maxAccount then
		return false, L.MACRO_ERR_FULL:format(numAccount, maxAccount)
	end
	local ok, result = pcall(CreateMacro, clean, icon, text, perCharacter)
	if not ok or not result then
		return false, L.MACRO_ERR_FAILED:format(tostring(result))
	end
	return true, L.MACRO_CREATED:format(clean)
end
