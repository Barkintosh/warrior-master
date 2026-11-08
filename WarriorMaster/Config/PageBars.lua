--[[
Warrior Master - Config/PageBars.lua
Rage bar and health bar pages, plus section builders reused by the swing
timer page (size & position, appearance, text).
]]
local _, ns = ...

local UI = ns.UI
local Media = ns.Media
local S = ns.Schema

local H = {}
ns.ConfigHelpers = H

local function leaf(path)
	return S.GetLeaf(S.profile, path)
end

--- Slider bound to a numeric profile setting, range taken from the schema.
function H.NumberSlider(page, path, label, opts)
	local spec = leaf(path)
	local get, set = UI.Bind(path)
	opts = opts or {}
	return page:Slider({
		label = label, min = spec.min, max = spec.max, step = spec.step,
		get = get, set = set, disabled = opts.disabled, refreshPage = opts.refreshPage,
	}, opts.full)
end

function H.EnumDropdown(page, path, label, labels, opts)
	local spec = leaf(path)
	local get, set = UI.Bind(path)
	opts = opts or {}
	return page:Dropdown({
		label = label, options = UI.Options(spec.values, labels),
		get = get, set = set, disabled = opts.disabled,
	}, opts.full)
end

function H.Check(page, path, label, opts)
	local get, set = UI.Bind(path)
	opts = opts or {}
	return page:Checkbox({ label = label, get = get, set = set, disabled = opts.disabled, tooltip = opts.tooltip }, opts.full)
end

function H.ColorPick(page, path, label, opts)
	local get, set = UI.Bind(path)
	opts = opts or {}
	return page:Color({ label = label, get = get, set = set, disabled = opts.disabled })
end

-- Built-in media first, then anything another addon shares through LibSharedMedia.
local function fontOptions()
	return Media.ListFonts()
end

local function textureOptions()
	return Media.ListTextures()
end
H.FontOptions = fontOptions
H.TextureOptions = textureOptions

local VISIBILITY_LABELS = { always = "VIS_ALWAYS", combat = "VIS_COMBAT", target = "VIS_TARGET", combatOrTarget = "VIS_COMBATORTARGET" }
local SHADE_LABELS = { None = "SHADE_NONE", Gloss = "SHADE_GLOSS", Shadow = "SHADE_SHADOW" }
local BORDER_LABELS = {
	Forever = "BORDER_FOREVER", ForeverFrame = "BORDER_FOREVER_FRAME",
	None = "BORDER_NONE", Pixel = "BORDER_PIXEL", Tooltip = "BORDER_TOOLTIP",
}
local OUTLINE_LABELS = { NONE = "OUTLINE_NONE", OUTLINE = "OUTLINE_THIN", THICKOUTLINE = "OUTLINE_THICK" }
local ALIGN_LABELS = { LEFT = "ALIGN_LEFT", CENTER = "ALIGN_CENTER", RIGHT = "ALIGN_RIGHT" }
local COLOR_MODE_LABELS = { static = "COLOR_STATIC", threshold = "COLOR_THRESHOLD", gradient = "COLOR_GRADIENT" }
local FORMAT_LABELS = { none = "FMT_NONE", value = "FMT_VALUE", percent = "FMT_PERCENT", valueMax = "FMT_VALUEMAX", valuePercent = "FMT_VALUEPERCENT" }
local SOUND_LABELS = {}
for key, entry in pairs(Media.sounds) do
	SOUND_LABELS[key] = entry.labelKey
end
local ANCHOR_LABELS = {}
for _, anchor in ipairs(S.ANCHORS) do
	ANCHOR_LABELS[anchor] = "ANCHOR_" .. anchor
end

local MODULE_FRAMES = {
	health = function(m) return m.bar end,
	rage = function(m) return m.bar end,
	swing = function(m) return m.holder end,
	stance = function(m) return m.bar end,
}

--- Screen anchor menu: changing it keeps the frame where it is on screen.
function H.AnchorDropdown(page, key, opts)
	local L = ns.L
	opts = opts or {}
	return page:Dropdown({
		label = L.ANCHOR,
		options = UI.Options(S.ANCHORS, ANCHOR_LABELS),
		disabled = opts.disabled,
		get = function()
			return ns.DB:Get(key .. ".point").point
		end,
		set = function(value)
			local module = ns:GetModule(key)
			local frame = module and MODULE_FRAMES[key](module)
			local point = frame and frame:IsShown() and ns.ConvertAnchor(frame, value)
			if not point then
				local old = ns.DB:Get(key .. ".point")
				point = { point = value, relPoint = value, x = value == old.point and old.x or 0, y = value == old.point and old.y or 0 }
			end
			ns.DB:Set(key .. ".point", point)
		end,
	})
end

--- Font style menu: font, size, outline (and shadow) in one click.
function H.FontStyleDropdown(page, key, withShadow)
	local L = ns.L
	return page:Dropdown({
		label = L.FONT_STYLE,
		options = function()
			local items = {}
			for _, preset in ipairs(Media.FONT_PRESET_KEYS) do
				items[#items + 1] = { value = preset, text = L[Media.fontPresets[preset].labelKey] }
			end
			items[#items + 1] = { value = "custom", text = L.PRESET_CUSTOM }
			return items
		end,
		get = function()
			return Media.MatchFontPreset(ns.db.profile[key], withShadow) or "custom"
		end,
		set = function(value)
			local preset = Media.fontPresets[value]
			if not preset then
				return
			end
			ns.DB:Set(key .. ".font", preset.font)
			ns.DB:Set(key .. ".fontSize", preset.fontSize)
			ns.DB:Set(key .. ".fontOutline", preset.fontOutline)
			if withShadow then
				ns.DB:Set(key .. ".fontShadow", preset.fontShadow)
			end
		end,
	})
end

H.VISIBILITY_LABELS = VISIBILITY_LABELS
H.SOUND_LABELS = SOUND_LABELS
H.OUTLINE_LABELS = OUTLINE_LABELS

--- Style row at the top of a module page: pick a style, apply it to this
-- module only (all parts), and see which style the module shows now.
function H.StyleSection(page, key)
	local L = ns.L
	local Presets = ns.Presets
	local choice
	page:Header(L.SECTION_STYLE)
	page:Dropdown({
		label = L.PRESET,
		options = ns.UI.Options(Presets.ORDER, Presets.LABEL_KEYS),
		get = function()
			return choice or ns.db.profile[key].style
		end,
		set = function(value)
			choice = value
		end,
	})
	page:Button({
		text = L.STYLE_APPLY_MODULE,
		onClick = function()
			local name = choice or ns.db.profile[key].style
			if ns:ApplyStyle(name, { key }) then
				ns:Print(L.STYLE_APPLIED:format(L[Presets.LABEL_KEYS[name]], L[ns.Styles.SECTION_LABELS[key]]))
			end
			choice = nil
		end,
	})
	page:Text({
		height = 16,
		size = 11,
		get = function()
			return L.STYLE_CURRENT:format(L[Presets.LABEL_KEYS[ns.db.profile[key].style]]), "dim"
		end,
	})
end

function H.VisibilityDropdown(page, key)
	return H.EnumDropdown(page, key .. ".visibility", ns.L.VISIBILITY, VISIBILITY_LABELS)
end

function H.LayoutSection(page, key, opts)
	local L = ns.L
	opts = opts or {}
	page:Header(L.SECTION_LAYOUT)
	H.NumberSlider(page, key .. ".width", L.WIDTH, { disabled = opts.widthDisabled })
	H.NumberSlider(page, key .. ".height", L.HEIGHT)
	H.NumberSlider(page, key .. ".scale", L.SCALE)
	H.NumberSlider(page, key .. ".alpha", L.ALPHA_COMBAT)
	H.NumberSlider(page, key .. ".oocAlpha", L.ALPHA_OOC)
	page:Skip()
	H.AnchorDropdown(page, key, { disabled = opts.positionDisabled })
	H.Check(page, key .. ".clamp", L.CLAMP)
	page:Skip()
	local getX, setX = UI.BindPoint(key .. ".point", "x")
	local getY, setY = UI.BindPoint(key .. ".point", "y")
	page:Slider({ label = L.POS_X, min = -1500, max = 1500, step = 1, get = getX, set = setX, disabled = opts.positionDisabled })
	page:Slider({ label = L.POS_Y, min = -1000, max = 1000, step = 1, get = getY, set = setY, disabled = opts.positionDisabled })
	page:Button({
		text = L.RESET_POSITION,
		disabled = opts.positionDisabled,
		onClick = function()
			ns.DB:Set(key .. ".point", S.profile[key].point.default)
		end,
	})
	page:Skip()
end

function H.AppearanceSection(page, key, opts)
	local L = ns.L
	opts = opts or {}
	page:Header(L.SECTION_APPEARANCE)
	do
		local get, set = UI.Bind(key .. ".texture")
		page:Dropdown({ label = L.TEXTURE, options = textureOptions, get = get, set = set })
	end
	H.EnumDropdown(page, key .. ".shade", L.SHADE, SHADE_LABELS)
	H.EnumDropdown(page, key .. ".borderStyle", L.BORDER_STYLE, BORDER_LABELS)
	local function atlasBorder()
		return ns.IsAtlasBorder(ns.DB:Get(key .. ".borderStyle"))
	end
	H.NumberSlider(page, key .. ".borderSize", L.BORDER_SIZE, {
		disabled = function()
			return ns.DB:Get(key .. ".borderStyle") ~= "Pixel"
		end,
	})
	H.ColorPick(page, key .. ".borderColor", L.BORDER_COLOR, {
		disabled = function()
			local style = ns.DB:Get(key .. ".borderStyle")
			return style ~= "Pixel" and style ~= "Tooltip"
		end,
	})
	H.ColorPick(page, key .. ".bgColor", L.BG_COLOR, { disabled = atlasBorder })
	do
		local get, set = UI.BindAlpha(key .. ".bgColor")
		page:Slider({ label = L.BG_ALPHA, min = 0, max = 1, step = 0.05, get = get, set = set, disabled = atlasBorder })
	end
	page:Note(L.ATLAS_BG_NOTE)
	H.Check(page, key .. ".spark", L.SPARK)
	if opts.smooth then
		H.Check(page, key .. ".smooth", L.SMOOTH)
	end
end

function H.TextSection(page, key, opts)
	local L = ns.L
	opts = opts or {}
	page:Header(L.SECTION_TEXT)
	H.FontStyleDropdown(page, key, true)
	if opts.formatPath then
		H.EnumDropdown(page, opts.formatPath, opts.formatLabel or L.TEXT_FORMAT, opts.formatLabels or FORMAT_LABELS)
	end
	do
		local get, set = UI.Bind(key .. ".font")
		page:Dropdown({ label = L.FONT, options = fontOptions, get = get, set = set })
	end
	H.NumberSlider(page, key .. ".fontSize", L.FONT_SIZE)
	H.EnumDropdown(page, key .. ".fontOutline", L.FONT_OUTLINE, OUTLINE_LABELS)
	H.EnumDropdown(page, key .. ".textAlign", L.TEXT_ALIGN, ALIGN_LABELS)
	H.ColorPick(page, key .. ".textColor", L.TEXT_COLOR)
	H.Check(page, key .. ".fontShadow", L.FONT_SHADOW)
	page:Note(L.FONT_NOTE)
end

--- Sound selector with a preview button.
function H.SoundPicker(page, path, label, opts)
	local L = ns.L
	opts = opts or {}
	H.EnumDropdown(page, path, label, SOUND_LABELS, { disabled = opts.disabled })
	page:Button({
		text = L.SOUND_PREVIEW,
		disabled = opts.disabled,
		onClick = function()
			ns.Compat.PlaySound(Media.GetSoundID(ns.DB:Get(path)), ns.db.profile.general.soundChannel)
		end,
	})
end

function H.ResetModuleButton(page, key, titleKey)
	local L = ns.L
	page:Header(L.SECTION_MAINTENANCE)
	page:Button({
		text = L.RESET_MODULE,
		confirm = true,
		onClick = function()
			ns.DB:ResetSection(key)
			ns:Print(L.MODULE_RESET_DONE:format(L[titleKey]))
		end,
	})
end

-- Rage / health pages ------------------------------------------------------------------------------------
local function buildResourcePage(key, titleKey, isRage)
	return function(page)
		local L = ns.L

		page:Header(L[titleKey])
		H.Check(page, key .. ".enabled", L.ENABLE)
		H.VisibilityDropdown(page, key)
		H.StyleSection(page, key)

		local positionDisabled
		if isRage then
			local function attached()
				return ns.db.profile.rage.attach.enabled
			end
			positionDisabled = attached
			page:Header(L.ATTACH_HEALTH)
			H.Check(page, "rage.attach.enabled", L.ATTACH_HEALTH)
			H.EnumDropdown(page, "rage.attach.position", L.ATTACH_POSITION,
				{ ABOVE = "ATTACH_ABOVE", BELOW = "ATTACH_BELOW" },
				{ disabled = function() return not attached() end })
			H.NumberSlider(page, "rage.attach.gap", L.ATTACH_GAP, { disabled = function() return not attached() end })
			H.Check(page, "rage.attach.matchWidth", L.ATTACH_MATCH_WIDTH, { disabled = function() return not attached() end })
			page:Note(L.ATTACHED_NOTE)
		end

		H.LayoutSection(page, key, {
			positionDisabled = positionDisabled,
			widthDisabled = isRage and function()
				local a = ns.db.profile.rage.attach
				return a.enabled and a.matchWidth
			end or nil,
		})
		H.AppearanceSection(page, key, { smooth = true })
		H.TextSection(page, key, { formatPath = key .. ".textFormat" })

		page:Header(L.SECTION_COLORS)
		H.EnumDropdown(page, key .. ".colorMode", L.COLOR_MODE, COLOR_MODE_LABELS)
		local function notStatic()
			return ns.db.profile[key].colorMode ~= "static"
		end
		local function isStatic()
			return ns.db.profile[key].colorMode == "static"
		end
		H.ColorPick(page, key .. ".colorStatic", L.COLOR_SINGLE, { disabled = notStatic })
		H.ColorPick(page, key .. ".colorLow", L.COLOR_LOW, { disabled = isStatic })
		H.ColorPick(page, key .. ".colorMid", L.COLOR_MID, { disabled = isStatic })
		H.ColorPick(page, key .. ".colorHigh", L.COLOR_HIGH, { disabled = isStatic })
		page:Skip()
		H.NumberSlider(page, key .. ".midAt", L.MID_AT, { disabled = isStatic })
		H.NumberSlider(page, key .. ".highAt", L.HIGH_AT, { disabled = isStatic })

		page:Header(L.SECTION_ALERTS)
		page:Note(isRage and L.RAGE_ALERT_DESC or L.HEALTH_ALERT_DESC, "text")
		H.NumberSlider(page, key .. ".alert.threshold", L.ALERT_THRESHOLD)
		H.ColorPick(page, key .. ".alert.color", L.ALERT_COLOR)
		H.Check(page, key .. ".alert.glow", L.ALERT_GLOW)
		H.Check(page, key .. ".alert.pulse", L.ALERT_PULSE, {
			disabled = function()
				return not ns.db.profile[key].alert.glow
			end,
		})
		H.Check(page, key .. ".alert.sound", L.ALERT_SOUND)
		page:Skip()
		H.SoundPicker(page, key .. ".alert.soundKey", L.ALERT_SOUND_CHOICE, {
			disabled = function()
				return not ns.db.profile[key].alert.sound
			end,
		})
		page:Note(L.SECRET_NOTE, "info")

		H.ResetModuleButton(page, key, titleKey)
	end
end

ns.Config:RegisterPage({ key = "health", titleKey = "MODULE_HEALTH", order = 20, build = buildResourcePage("health", "MODULE_HEALTH", false) })
ns.Config:RegisterPage({ key = "rage", titleKey = "MODULE_RAGE", order = 30, build = buildResourcePage("rage", "MODULE_RAGE", true) })
