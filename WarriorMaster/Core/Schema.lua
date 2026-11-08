--[[
Warrior Master - Core/Schema.lua
Single source of truth for every saved setting: default value, type and
allowed range. It is used to
  - build default profiles,
  - validate and repair saved variables at login (wrong types, NaN,
    out-of-range numbers, unknown enum values, oversized strings),
  - validate imported profiles before they are stored,
  - drive the ranges of the settings controls.
Unknown keys are dropped, so stale or hostile data never reaches the modules.
]]
local _, ns = ...

local U = ns.Util
local Media = ns.Media

local S = {}
ns.Schema = S

-- Leaf constructors ------------------------------------------------------------------
local function N(default, min, max, step)
	return { kind = "number", default = default, min = min, max = max, step = step or 1 }
end
local function B(default)
	return { kind = "boolean", default = default }
end
local function E(default, values)
	return { kind = "enum", default = default, values = values }
end
local function C(r, g, b, a)
	return { kind = "color", default = { r = r, g = g, b = b, a = a or 1 } }
end
local function P(point, relPoint, x, y)
	return { kind = "point", default = { point = point, relPoint = relPoint, x = x, y = y } }
end
local function T(default, maxLen)
	return { kind = "string", default = default, maxLen = maxLen }
end
local function X(default, sanitize)
	return { kind = "custom", default = default, sanitize = sanitize }
end
--- Texture or font name: a built-in key or a SharedMedia name ("lsm:...").
-- Any short plain string is kept, so a choice survives even if the addon
-- providing it is disabled for a while; Media falls back when drawing.
local function M(default)
	return { kind = "media", default = default, maxLen = 80 }
end

S.N, S.B, S.E, S.C, S.P, S.T, S.X, S.M = N, B, E, C, P, T, X, M

local function merge(a, b)
	local out = {}
	for k, v in pairs(a) do
		out[k] = v
	end
	for k, v in pairs(b) do
		out[k] = v
	end
	return out
end

local Styles = ns.Styles

--- Leaf for a styled setting, with its default taken from the Forever style.
local function styled(section, key, ctor, ...)
	local value = Styles.Default(section, key)
	if ctor == C then
		return C(value.r, value.g, value.b, value.a)
	end
	if ctor == N or ctor == E then
		return ctor(value, ...)
	end
	return ctor(value)
end

-- Shared value lists -----------------------------------------------------------------
S.ANCHORS = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }
S.SHADES = { "None", "Gloss", "Shadow" }
S.BORDERS = { "Forever", "ForeverFrame", "None", "Pixel", "Tooltip" }
S.BUTTON_STYLES = { "Forever", "Pixel", "Clean" }
S.OUTLINES = { "NONE", "OUTLINE", "THICKOUTLINE" }
S.ALIGNS = { "LEFT", "CENTER", "RIGHT" }
S.VISIBILITIES = { "always", "combat", "target", "combatOrTarget" }
S.COLOR_MODES = { "static", "threshold", "gradient" }
S.PRESET_KEYS = {}
for _, key in ipairs(Styles.ORDER) do
	S.PRESET_KEYS[#S.PRESET_KEYS + 1] = key
end
S.PRESET_KEYS[#S.PRESET_KEYS + 1] = "Custom"
S.STYLE_TARGETS = { "all", "health", "rage", "swing", "stance" }
S.STANCE_KEYS = { "battle", "defensive", "berserker" }
S.LANGUAGES = { "auto", "enUS", "frFR" }

--- Visual settings shared by the rage, health and swing bars.
local function barVisual(section, o)
	return {
		style = E("Forever", S.PRESET_KEYS),
		width = styled(section, "width", N, 40, 800, 1),
		height = styled(section, "height", N, 4, 80, 1),
		scale = N(1, 0.5, 3, 0.05),
		alpha = N(1, 0.05, 1, 0.05),
		oocAlpha = N(1, 0, 1, 0.05),
		texture = styled(section, "texture", M),
		shade = styled(section, "shade", E, S.SHADES),
		bgColor = styled(section, "bgColor", C),
		borderStyle = styled(section, "borderStyle", E, S.BORDERS),
		borderSize = styled(section, "borderSize", N, 1, 6, 1),
		borderColor = styled(section, "borderColor", C),
		spark = styled(section, "spark", B),
		font = styled(section, "font", M),
		fontSize = styled(section, "fontSize", N, 6, 32, 1),
		fontOutline = styled(section, "fontOutline", E, S.OUTLINES),
		fontShadow = styled(section, "fontShadow", B),
		textAlign = styled(section, "textAlign", E, S.ALIGNS),
		textColor = styled(section, "textColor", C),
		point = P("CENTER", "CENTER", o.x, o.y),
		clamp = B(true),
		visibility = E(o.visibility or "always", S.VISIBILITIES),
	}
end

--- Colors of a resource bar (health, rage), from the Forever style.
local function resourceColors(section)
	return {
		colorMode = styled(section, "colorMode", E, S.COLOR_MODES),
		colorStatic = styled(section, "colorStatic", C),
		colorLow = styled(section, "colorLow", C),
		colorMid = styled(section, "colorMid", C),
		colorHigh = styled(section, "colorHigh", C),
	}
end

-- Custom validators -----------------------------------------------------------------------
local function validItemID(v)
	return type(v) == "number" and v == v and v >= 1 and v <= 10000000 and math.floor(v) == v
end

local function sanitizeLoadouts(value)
	local out = {}
	if type(value) ~= "table" then
		return out
	end
	for _, key in ipairs(S.STANCE_KEYS) do
		local entry = value[key]
		if type(entry) == "table" then
			local clean = {}
			if validItemID(entry.mh) then
				clean.mh = entry.mh
			end
			if validItemID(entry.oh) then
				clean.oh = entry.oh
			end
			if type(entry.set) == "string" and entry.set ~= "" then
				clean.set = U.Utf8Sub(U.StripControl(entry.set), 64)
			end
			if next(clean) then
				out[key] = clean
			end
		end
	end
	return out
end

local MAX_OPTION_TEMPLATES = 64
local MAX_OPTIONS_PER_TEMPLATE = 16

local function sanitizeMacroOptions(value)
	local out = {}
	if type(value) ~= "table" then
		return out
	end
	local templates = 0
	for templateID, options in pairs(value) do
		if type(templateID) == "string" and templateID:match("^[%w_]+$") and #templateID <= 40 and type(options) == "table" then
			templates = templates + 1
			if templates > MAX_OPTION_TEMPLATES then
				break
			end
			local clean, count = {}, 0
			for key, v in pairs(options) do
				if type(key) == "string" and key:match("^[%w_]+$") and #key <= 40 then
					local t = type(v)
					local ok = t == "boolean" or (t == "number" and U.IsFiniteNumber(v)) or t == "string"
					if ok then
						count = count + 1
						if count > MAX_OPTIONS_PER_TEMPLATE then
							break
						end
						if t == "string" then
							v = U.Utf8Sub(U.StripControl(v), 64)
						end
						clean[key] = v
					end
				end
			end
			out[templateID] = clean
		end
	end
	return out
end

S.sanitizeLoadouts = sanitizeLoadouts
S.sanitizeMacroOptions = sanitizeMacroOptions

-- Profile specification ----------------------------------------------------------------------
S.profile = {
	general = {
		locked = B(true),
		sounds = B(true),
		soundChannel = E("Master", Media.SOUND_CHANNELS),
		-- Last choices made in the style picker (General page).
		styleChoice = E("Forever", S.PRESET_KEYS),
		styleTarget = E("all", S.STYLE_TARGETS),
		styleParts = { look = B(true), colors = B(true), fonts = B(true), sizes = B(true) },
		-- Moves every module together, and keeps them all on screen.
		offsetX = N(0, -2000, 2000, 1),
		offsetY = N(0, -2000, 2000, 1),
		clampAll = B(true),
	},

	health = merge(barVisual("health", { x = 0, y = -180 }), merge(resourceColors("health"), {
		enabled = B(true),
		smooth = B(true),
		textFormat = E("valuePercent", { "none", "value", "percent", "valueMax", "valuePercent" }),
		midAt = N(35, 0, 100, 1),
		highAt = N(70, 0, 100, 1),
		alert = {
			glow = B(true),
			pulse = B(true),
			threshold = N(30, 1, 99, 1),
			color = styled("health", "alert.color", C),
			sound = B(true),
			soundKey = E("RaidWarning", Media.SOUND_KEYS),
		},
	})),

	rage = merge(barVisual("rage", { x = 0, y = -201 }), merge(resourceColors("rage"), {
		enabled = B(true),
		smooth = B(true),
		textFormat = E("value", { "none", "value", "percent", "valueMax" }),
		midAt = N(30, 0, 100, 1),
		highAt = N(60, 0, 100, 1),
		alert = {
			glow = B(true),
			pulse = B(true),
			threshold = N(50, 1, 100, 1),
			color = styled("rage", "alert.color", C),
			sound = B(false),
			soundKey = E("Tick", Media.SOUND_KEYS),
		},
		attach = {
			enabled = B(false),
			position = E("BELOW", { "ABOVE", "BELOW" }),
			gap = N(2, 0, 40, 1),
			matchWidth = B(true),
		},
	})),

	swing = merge(barVisual("swing", { x = 0, y = -232, visibility = "combat" }), {
		enabled = B(true),
		showMainHand = B(true),
		showOffHand = B(true),
		showRanged = B(false),
		spacing = styled("swing", "spacing", N, 0, 30, 1),
		textMode = E("remaining", { "none", "remaining", "both" }),
		labels = B(true),
		fill = E("fill", { "fill", "deplete" }),
		hideIdle = B(false),
		sound = B(false),
		soundKey = E("Tick", Media.SOUND_KEYS),
		hasteRescale = B(true),
		rangeCheck = B(false),
		colorMainHand = styled("swing", "colorMainHand", C),
		colorOffHand = styled("swing", "colorOffHand", C),
		colorRanged = styled("swing", "colorRanged", C),
	}),

	stance = {
		enabled = B(true),
		style = E("Forever", S.PRESET_KEYS),
		buttonStyle = styled("stance", "buttonStyle", E, S.BUTTON_STYLES),
		buttonSize = styled("stance", "buttonSize", N, 20, 72, 1),
		spacing = styled("stance", "spacing", N, 0, 30, 1),
		orientation = E("HORIZONTAL", { "HORIZONTAL", "VERTICAL" }),
		scale = N(1, 0.5, 3, 0.05),
		alpha = N(1, 0.1, 1, 0.05),
		point = P("CENTER", "CENTER", 0, -285),
		clamp = B(true),
		equipWeapons = B(true),
		useItemNames = B(false),
		loadoutIcons = B(true),
		tooltips = B(true),
		showBindings = B(true),
		borderColor = styled("stance", "borderColor", C),
		activeColor = styled("stance", "activeColor", C),
		textColor = styled("stance", "textColor", C),
		font = styled("stance", "font", M),
		fontSize = styled("stance", "fontSize", N, 6, 24, 1),
		fontOutline = styled("stance", "fontOutline", E, S.OUTLINES),
	},

	-- The player's own look per module (the "Custom" style), kept while a
	-- built-in style is applied. Only known style fields survive, each one
	-- validated by its own leaf.
	customVisual = X(nil, function(value)
		return ns.Presets and ns.Presets.SanitizeVisual(value) or nil
	end),
}

S.char = {
	loadouts = X({}, sanitizeLoadouts),
	macro = {
		template = T("charge_intercept", 40),
		name = T("", 16),
		perCharacter = B(true),
		options = X({}, sanitizeMacroOptions),
	},
}

S.global = {
	language = E("auto", S.LANGUAGES),
}

-- Validation --------------------------------------------------------------------------------
local function isLeaf(spec)
	return type(spec) == "table" and spec.kind ~= nil
end
S.IsLeaf = isLeaf

local function count(stats)
	if stats then
		stats.fixed = (stats.fixed or 0) + 1
	end
end

local function sanitizeColor(leaf, value, stats)
	local d = leaf.default
	if type(value) ~= "table" then
		count(stats)
		return { r = d.r, g = d.g, b = d.b, a = d.a }
	end
	local out = {}
	for _, c in ipairs({ "r", "g", "b", "a" }) do
		local v = value[c]
		if U.IsFiniteNumber(v) then
			out[c] = U.Clamp(v, 0, 1)
		else
			if c ~= "a" or v ~= nil then
				count(stats)
			end
			out[c] = d[c] or 1
		end
	end
	return out
end

local function sanitizePoint(leaf, value, stats)
	local d = leaf.default
	if type(value) ~= "table" then
		count(stats)
		return { point = d.point, relPoint = d.relPoint, x = d.x, y = d.y }
	end
	local out = {}
	out.point = U.IndexOf(S.ANCHORS, value.point) and value.point or d.point
	out.relPoint = U.IndexOf(S.ANCHORS, value.relPoint) and value.relPoint or d.relPoint
	out.x = U.IsFiniteNumber(value.x) and U.Clamp(value.x, -5000, 5000) or d.x
	out.y = U.IsFiniteNumber(value.y) and U.Clamp(value.y, -5000, 5000) or d.y
	return out
end

--- Returns a valid value for one leaf (the default when the input is invalid).
function S.SanitizeLeaf(leaf, value, stats)
	local kind = leaf.kind
	if kind == "number" then
		if U.IsFiniteNumber(value) then
			local clamped = U.Clamp(value, leaf.min, leaf.max)
			if clamped ~= value then
				count(stats)
			end
			return clamped
		end
		if value ~= nil then
			count(stats)
		end
		return leaf.default
	elseif kind == "boolean" then
		if type(value) == "boolean" then
			return value
		end
		if value ~= nil then
			count(stats)
		end
		return leaf.default
	elseif kind == "enum" then
		if type(value) == "string" and U.IndexOf(leaf.values, value) then
			return value
		end
		if value ~= nil then
			count(stats)
		end
		return leaf.default
	elseif kind == "string" or kind == "media" then
		if type(value) == "string" then
			local clean = U.Utf8Sub(U.StripControl(value), leaf.maxLen or 64)
			if clean ~= value then
				count(stats)
			end
			return clean
		end
		if value ~= nil then
			count(stats)
		end
		return leaf.default
	elseif kind == "color" then
		return sanitizeColor(leaf, value, stats)
	elseif kind == "point" then
		return sanitizePoint(leaf, value, stats)
	elseif kind == "custom" then
		local ok, result = pcall(leaf.sanitize, value)
		if ok then
			return result
		end
		count(stats)
		return U.DeepCopy(leaf.default)
	end
	return nil
end

--- Returns a new, fully valid table for spec built from (possibly hostile) data.
function S.Sanitize(spec, data, stats)
	local out = {}
	if type(data) ~= "table" then
		data = {}
	end
	for key, sub in pairs(spec) do
		if isLeaf(sub) then
			local value = S.SanitizeLeaf(sub, data[key], stats)
			if type(value) == "table" then
				value = U.DeepCopy(value)
			end
			out[key] = value
		elseif type(sub) == "table" then
			out[key] = S.Sanitize(sub, data[key], stats)
		end
	end
	return out
end

function S.Defaults(spec)
	return S.Sanitize(spec, nil)
end

--- Finds the leaf describing a dotted path such as "rage.alert.threshold".
function S.GetLeaf(spec, path)
	local node = spec
	for part in path:gmatch("[^%.]+") do
		if type(node) ~= "table" or isLeaf(node) then
			return nil
		end
		node = node[part]
	end
	if isLeaf(node) then
		return node
	end
	return nil
end
