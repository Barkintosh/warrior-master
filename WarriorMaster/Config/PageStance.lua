--[[
Warrior Master - Config/PageStance.lua
Stance buttons and the weapons equipped with each stance.
]]
local _, ns = ...

local UI = ns.UI
local H = ns.ConfigHelpers
local S = ns.Schema

local function itemOptions(list, filter)
	return function()
		local items = { { value = 0, text = ns.L.NONE_KEEP } }
		local stance = ns:GetModule("stance")
		local scan = stance:ScanWeapons()
		for _, entry in ipairs(scan[list]) do
			if not filter or filter(entry) then
				items[#items + 1] = { value = entry.id, text = entry.name }
			end
		end
		return items
	end
end

local function setOptions()
	local items = { { value = "", text = ns.L.NONE_KEEP } }
	for _, name in ipairs(ns.Compat.GetEquipmentSetNames()) do
		items[#items + 1] = { value = name, text = name }
	end
	return items
end

ns.Config:RegisterPage({
	key = "stance",
	titleKey = "MODULE_STANCE",
	order = 50,
	build = function(page)
		local L = ns.L
		local stance = ns:GetModule("stance")

		page:Header(L.MODULE_STANCE)
		page:Note(L.STANCE_SECURITY_NOTE, "info")
		H.Check(page, "stance.enabled", L.ENABLE)
		H.EnumDropdown(page, "stance.orientation", L.STANCE_ORIENTATION, { HORIZONTAL = "ORIENT_HORIZONTAL", VERTICAL = "ORIENT_VERTICAL" })
		H.StyleSection(page, "stance")
		page:Text({
			height = 16,
			get = function()
				if stance.pending then
					return L.COMBAT_QUEUED, "warn"
				end
				if ns.Compat.GetNumShapeshiftForms() == 0 then
					return L.STANCE_NONE_KNOWN, "warn"
				end
				return "", "dim"
			end,
		})

		page:Header(L.SECTION_LAYOUT)
		H.NumberSlider(page, "stance.buttonSize", L.STANCE_BUTTON_SIZE)
		H.NumberSlider(page, "stance.spacing", L.STANCE_SPACING)
		H.NumberSlider(page, "stance.scale", L.SCALE)
		H.NumberSlider(page, "stance.alpha", L.ALPHA_COMBAT)
		local function inLayout()
			return ns.Layout:Manages("stance")
		end
		H.AnchorDropdown(page, "stance", { disabled = inLayout })
		H.Check(page, "stance.clamp", L.CLAMP)
		page:Skip()
		local getX, setX = UI.BindPoint("stance.point", "x")
		local getY, setY = UI.BindPoint("stance.point", "y")
		page:Slider({ label = L.POS_X, min = -1500, max = 1500, step = 1, get = getX, set = setX, disabled = inLayout })
		page:Slider({ label = L.POS_Y, min = -1000, max = 1000, step = 1, get = getY, set = setY, disabled = inLayout })
		page:Button({
			text = L.RESET_POSITION,
			disabled = inLayout,
			onClick = function()
				ns.DB:Set("stance.point", S.profile.stance.point.default)
			end,
		})
		page:Skip()
		page:Text({
			height = 14,
			size = 11,
			get = function()
				return inLayout() and L.LAYOUT_MANAGED or "", "info"
			end,
		})

		page:Header(L.SECTION_APPEARANCE)
		H.EnumDropdown(page, "stance.buttonStyle", L.BUTTON_STYLE,
			{ Forever = "BUTTON_FOREVER", Pixel = "BUTTON_PIXEL", Clean = "BUTTON_CLEAN" })
		H.ColorPick(page, "stance.borderColor", L.BORDER_COLOR, {
			disabled = function()
				return ns.db.profile.stance.buttonStyle ~= "Pixel"
			end,
		})
		H.ColorPick(page, "stance.activeColor", L.STANCE_TIP_ACTIVE)
		H.Check(page, "stance.loadoutIcons", L.STANCE_LOADOUT_ICONS)
		H.Check(page, "stance.tooltips", L.STANCE_TOOLTIPS)
		page:Skip()

		page:Header(L.SECTION_HOTKEY)
		H.Check(page, "stance.showBindings", L.STANCE_LABELS)
		H.FontStyleDropdown(page, "stance", false)
		do
			local get, set = UI.Bind("stance.font")
			page:Dropdown({ label = L.FONT, options = H.FontOptions, get = get, set = set })
		end
		H.NumberSlider(page, "stance.fontSize", L.FONT_SIZE)
		H.EnumDropdown(page, "stance.fontOutline", L.FONT_OUTLINE, H.OUTLINE_LABELS)
		H.ColorPick(page, "stance.textColor", L.TEXT_COLOR)

		page:Header(L.STANCE_LOADOUTS)
		page:Note(L.STANCE_RIGHTCLICK_HINT, "info")
		H.Check(page, "stance.equipWeapons", L.STANCE_EQUIP, { full = true })
		H.Check(page, "stance.useItemNames", L.STANCE_ITEM_NAMES, { full = true })
		H.Check(page, "stance.autoMacros", L.MACRO_AUTO, { full = true })
		page:Note(L.MACRO_AUTO_NOTE)
		page:Button({
			text = L.MACRO_BAR_BUTTON,
			tooltip = L.MACRO_BAR_TIP,
			disabled = function()
				return ns.Compat.InCombatLockdown()
			end,
			onClick = function()
				local _, message = stance:PlaceMacrosOnBar()
				ns:Print(message)
			end,
		})
		page:Skip()
		local function noWeapons()
			return not ns.db.profile.stance.equipWeapons
		end
		page:Button({
			text = L.STANCE_REFRESH,
			onClick = function()
				stance:RequestConfigure()
			end,
		})
		page:Skip()

		local canUseSets = ns.Compat.CanUseEquipmentSets()
		for _, key in ipairs(stance.ORDER) do
			page:Space(4)
			page:Text({ text = L[stance.LABELS[key]], color = "accent", size = 13, height = 16 })
			local function current(field)
				local lo = stance:GetLoadout(key)
				return lo and lo[field]
			end
			page:Dropdown({
				label = L.STANCE_MAINHAND,
				options = itemOptions("mainHand"),
				disabled = noWeapons,
				get = function()
					return current("mh") or 0
				end,
				set = function(value)
					stance:SetLoadout(key, "mh", value ~= 0 and value or nil)
				end,
			})
			page:Dropdown({
				label = L.STANCE_OFFHAND,
				options = itemOptions("offHand"),
				disabled = function()
					return noWeapons() or stance:IsTwoHanded(current("mh"))
				end,
				get = function()
					return current("oh") or 0
				end,
				set = function(value)
					stance:SetLoadout(key, "oh", value ~= 0 and value or nil)
				end,
			})
			if canUseSets then
				page:Dropdown({
					label = L.STANCE_SET,
					options = setOptions,
					disabled = noWeapons,
					get = function()
						return current("set") or ""
					end,
					set = function(value)
						stance:SetLoadout(key, "set", value ~= "" and value or nil)
					end,
				})
				page:Skip()
			end
			page:Text({
				height = 70,
				color = "text",
				size = 11,
				get = function()
					local action = stance:DescribeAction(key)
					local problems = ns.db.profile.stance.equipWeapons and stance:ValidateLoadout(key) or {}
					local text = L.STANCE_PREVIEW .. ":\n" .. action
					if #problems > 0 then
						return text .. "\n|cffff6b6b" .. table.concat(problems, "\n") .. "|r", "text"
					end
					return text, "text"
				end,
			})
		end

		H.ResetModuleButton(page, "stance", "MODULE_STANCE")
	end,
})
