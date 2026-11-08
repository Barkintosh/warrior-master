--[[
Warrior Master - Core/Styles.lua
Visual style presets ("styles").

A style is a complete look for every module, split into four parts that can
be applied together or separately, to all modules or to one:
  look    textures, shading, background and border (button frame for stances)
  colors  bar colors, color mode, glow color, text color
  fonts   font, size, outline, shadow
  sizes   width and height (button size and spacing for stances)
Positions, thresholds, alerts, visibility and behaviour are never part of a
style.

"Forever" reproduces the default WoW Forever interface: Blizzard's personal
resource bar texture and colors, the native framed swing timer, action-button
frames, and Friz Quadrata bar text. It is also the source of the defaults in
Core/Schema.lua, so a new profile looks exactly like the Forever style.
]]
local _, ns = ...

local Styles = {}
ns.Styles = Styles

Styles.ORDER = { "Forever", "Classic", "Modern", "Minimal", "Compact", "HighVisibility", "Ember", "Frost", "Gladiator", "Berserker", "Void" }
Styles.LABEL_KEYS = {
	Forever = "PRESET_FOREVER",
	Classic = "PRESET_CLASSIC",
	Modern = "PRESET_MODERN",
	Minimal = "PRESET_MINIMAL",
	Compact = "PRESET_COMPACT",
	HighVisibility = "PRESET_HIGHVIS",
	Ember = "PRESET_EMBER",
	Frost = "PRESET_FROST",
	Gladiator = "PRESET_GLADIATOR",
	Berserker = "PRESET_BERSERKER",
	Void = "PRESET_VOID",
	Custom = "PRESET_CUSTOM",
}

Styles.SECTIONS = { "health", "rage", "swing", "stance" }
Styles.PARTS = { "look", "colors", "fonts", "sizes" }
Styles.PART_LABELS = { look = "PART_LOOK", colors = "PART_COLORS", fonts = "PART_FONTS", sizes = "PART_SIZES" }
Styles.SECTION_LABELS = { health = "MODULE_HEALTH", rage = "MODULE_RAGE", swing = "MODULE_SWING", stance = "MODULE_STANCE" }

-- Setting keys covered by each part (dotted keys are nested settings).
local BAR_KEYS = {
	look = { "texture", "shade", "borderStyle", "borderSize", "borderColor", "bgColor", "spark" },
	fonts = { "font", "fontSize", "fontOutline", "fontShadow", "textAlign" },
	sizes = { "width", "height" },
}
local RESOURCE_COLORS = { "textColor", "colorMode", "colorStatic", "colorLow", "colorMid", "colorHigh", "alert.color" }
local KEYS = {
	health = { look = BAR_KEYS.look, fonts = BAR_KEYS.fonts, sizes = BAR_KEYS.sizes, colors = RESOURCE_COLORS },
	rage = { look = BAR_KEYS.look, fonts = BAR_KEYS.fonts, sizes = BAR_KEYS.sizes, colors = RESOURCE_COLORS },
	swing = {
		look = BAR_KEYS.look,
		fonts = BAR_KEYS.fonts,
		sizes = { "width", "height", "spacing" },
		colors = { "textColor", "colorMainHand", "colorOffHand", "colorRanged" },
	},
	stance = {
		look = { "buttonStyle", "borderColor" },
		colors = { "activeColor", "textColor" },
		fonts = { "font", "fontSize", "fontOutline" },
		sizes = { "buttonSize", "spacing" },
	},
}

function Styles.Keys(section, part)
	return KEYS[section] and KEYS[section][part] or {}
end

--- Every styled key of a section (all parts).
function Styles.AllKeys(section)
	local out = {}
	for _, part in ipairs(Styles.PARTS) do
		for _, key in ipairs(Styles.Keys(section, part)) do
			out[#out + 1] = key
		end
	end
	return out
end

local function c(r, g, b, a)
	return { r = r, g = g, b = b, a = a or 1 }
end
local WHITE = c(1, 1, 1)
local BLACK = c(0, 0, 0)

-- Style data -----------------------------------------------------------------------------------
-- bar: shared by the three bars; health/rage/swing/stance: per module (overrides bar).
Styles.data = {
	Forever = {
		bar = {
			look = { texture = "Forever", shade = "None", borderStyle = "Forever", borderSize = 1, borderColor = BLACK, bgColor = c(0, 0, 0, 0.5), spark = false },
			fonts = { font = "Friz", fontSize = 10, fontOutline = "OUTLINE", fontShadow = false },
		},
		health = {
			colors = { textColor = WHITE, colorMode = "static", colorStatic = c(0, 1, 0), colorLow = c(0.86, 0.13, 0.12), colorMid = c(0.95, 0.76, 0.16), colorHigh = c(0, 1, 0), ["alert.color"] = c(1, 0.15, 0.1) },
			sizes = { width = 220, height = 16 },
		},
		rage = {
			colors = { textColor = WHITE, colorMode = "static", colorStatic = c(1, 0, 0), colorLow = c(0.6, 0, 0), colorMid = c(0.85, 0.05, 0.05), colorHigh = c(1, 0.3, 0.1), ["alert.color"] = c(1, 0.82, 0.25) },
			sizes = { width = 220, height = 12 },
		},
		swing = {
			look = { texture = "ForeverSwing", borderStyle = "ForeverFrame", spark = true },
			fonts = { fontOutline = "NONE", fontShadow = true, textAlign = "RIGHT" },
			colors = { textColor = WHITE, colorMainHand = WHITE, colorOffHand = WHITE, colorRanged = WHITE },
			sizes = { width = 220, height = 20, spacing = 2 },
		},
		stance = {
			look = { buttonStyle = "Forever", borderColor = BLACK },
			colors = { activeColor = c(1, 0.82, 0.25), textColor = c(0.85, 0.85, 0.85) },
			fonts = { font = "Arial", fontSize = 11, fontOutline = "OUTLINE" },
			sizes = { buttonSize = 36, spacing = 4 },
		},
	},

	Classic = {
		bar = {
			look = { texture = "Blizzard", shade = "None", borderStyle = "Tooltip", borderSize = 1, borderColor = c(0.75, 0.75, 0.75), bgColor = c(0, 0, 0, 0.5), spark = true },
			fonts = { font = "Friz", fontSize = 12, fontOutline = "OUTLINE", fontShadow = false },
		},
		health = {
			colors = { textColor = WHITE, colorMode = "gradient", colorStatic = c(0, 1, 0), colorLow = c(1, 0, 0), colorMid = c(1, 1, 0), colorHigh = c(0, 1, 0), ["alert.color"] = c(1, 0.1, 0.1) },
			sizes = { width = 230, height = 22 },
		},
		rage = {
			colors = { textColor = WHITE, colorMode = "static", colorStatic = c(1, 0, 0), colorLow = c(0.6, 0.1, 0.1), colorMid = c(0.85, 0.2, 0.1), colorHigh = c(1, 0.45, 0.1), ["alert.color"] = c(1, 0.82, 0) },
			sizes = { width = 230, height = 20 },
		},
		swing = {
			colors = { textColor = WHITE, colorMainHand = c(0.86, 0.83, 0.76), colorOffHand = c(0.55, 0.66, 0.96), colorRanged = c(0.46, 0.86, 0.46) },
			sizes = { width = 230, height = 14, spacing = 3 },
		},
		stance = {
			look = { buttonStyle = "Pixel", borderColor = c(0.75, 0.75, 0.75) },
			colors = { activeColor = c(1, 0.82, 0), textColor = c(0.85, 0.85, 0.85) },
			fonts = { font = "Arial", fontSize = 11, fontOutline = "OUTLINE" },
			sizes = { buttonSize = 36, spacing = 4 },
		},
	},

	Modern = {
		bar = {
			look = { texture = "Flat", shade = "Gloss", borderStyle = "Pixel", borderSize = 1, borderColor = BLACK, bgColor = c(0.04, 0.04, 0.05, 0.65), spark = true },
			fonts = { font = "Friz", fontSize = 12, fontOutline = "OUTLINE", fontShadow = false },
		},
		health = {
			colors = { textColor = WHITE, colorMode = "gradient", colorStatic = c(0.2, 0.75, 0.25), colorLow = c(0.86, 0.13, 0.12), colorMid = c(0.95, 0.76, 0.16), colorHigh = c(0.22, 0.78, 0.27), ["alert.color"] = c(1, 0.15, 0.1) },
			sizes = { width = 220, height = 18 },
		},
		rage = {
			colors = { textColor = WHITE, colorMode = "threshold", colorStatic = c(0.78, 0.15, 0.12), colorLow = c(0.6, 0.12, 0.1), colorMid = c(0.86, 0.22, 0.1), colorHigh = c(1, 0.46, 0.1), ["alert.color"] = c(1, 0.82, 0.25) },
			sizes = { width = 220, height = 16 },
		},
		swing = {
			colors = { textColor = WHITE, colorMainHand = c(0.86, 0.83, 0.76), colorOffHand = c(0.55, 0.66, 0.96), colorRanged = c(0.46, 0.86, 0.46) },
			sizes = { width = 220, height = 12, spacing = 3 },
		},
		stance = {
			look = { buttonStyle = "Pixel", borderColor = BLACK },
			colors = { activeColor = c(1, 0.82, 0.25), textColor = c(0.9, 0.9, 0.9) },
			fonts = { font = "Arial", fontSize = 10, fontOutline = "OUTLINE" },
			sizes = { buttonSize = 34, spacing = 4 },
		},
	},

	Minimal = {
		bar = {
			look = { texture = "Flat", shade = "None", borderStyle = "None", borderSize = 1, borderColor = BLACK, bgColor = c(0, 0, 0, 0.35), spark = false },
			fonts = { font = "Arial", fontSize = 10, fontOutline = "OUTLINE", fontShadow = false },
		},
		health = {
			colors = { textColor = c(0.92, 0.92, 0.92), colorMode = "static", colorStatic = c(0.36, 0.74, 0.46), colorLow = c(0.8, 0.3, 0.3), colorMid = c(0.85, 0.75, 0.35), colorHigh = c(0.36, 0.74, 0.46), ["alert.color"] = c(0.9, 0.3, 0.3) },
			sizes = { width = 200, height = 10 },
		},
		rage = {
			colors = { textColor = c(0.92, 0.92, 0.92), colorMode = "static", colorStatic = c(0.76, 0.26, 0.23), colorLow = c(0.55, 0.2, 0.2), colorMid = c(0.7, 0.25, 0.2), colorHigh = c(0.85, 0.35, 0.25), ["alert.color"] = c(0.95, 0.8, 0.45) },
			sizes = { width = 200, height = 8 },
		},
		swing = {
			colors = { textColor = c(0.92, 0.92, 0.92), colorMainHand = c(0.8, 0.8, 0.8), colorOffHand = c(0.6, 0.7, 0.9), colorRanged = c(0.6, 0.85, 0.6) },
			sizes = { width = 200, height = 5, spacing = 2 },
		},
		stance = {
			look = { buttonStyle = "Clean", borderColor = c(0, 0, 0, 0) },
			colors = { activeColor = c(0.95, 0.8, 0.45), textColor = c(0.8, 0.8, 0.8) },
			fonts = { font = "Arial", fontSize = 9, fontOutline = "OUTLINE" },
			sizes = { buttonSize = 28, spacing = 2 },
		},
	},

	Compact = {
		bar = {
			look = { texture = "Flat", shade = "Shadow", borderStyle = "Pixel", borderSize = 1, borderColor = BLACK, bgColor = c(0, 0, 0, 0.6), spark = false },
			fonts = { font = "Arial", fontSize = 9, fontOutline = "OUTLINE", fontShadow = false },
		},
		health = {
			colors = { textColor = WHITE, colorMode = "gradient", colorStatic = c(0.2, 0.75, 0.25), colorLow = c(0.86, 0.13, 0.12), colorMid = c(0.95, 0.76, 0.16), colorHigh = c(0.22, 0.78, 0.27), ["alert.color"] = c(1, 0.15, 0.1) },
			sizes = { width = 160, height = 12 },
		},
		rage = {
			colors = { textColor = WHITE, colorMode = "threshold", colorStatic = c(0.78, 0.15, 0.12), colorLow = c(0.6, 0.12, 0.1), colorMid = c(0.86, 0.22, 0.1), colorHigh = c(1, 0.46, 0.1), ["alert.color"] = c(1, 0.82, 0.25) },
			sizes = { width = 160, height = 10 },
		},
		swing = {
			colors = { textColor = WHITE, colorMainHand = c(0.86, 0.83, 0.76), colorOffHand = c(0.55, 0.66, 0.96), colorRanged = c(0.46, 0.86, 0.46) },
			sizes = { width = 160, height = 6, spacing = 2 },
		},
		stance = {
			look = { buttonStyle = "Pixel", borderColor = BLACK },
			colors = { activeColor = c(1, 0.82, 0.25), textColor = c(0.85, 0.85, 0.85) },
			fonts = { font = "Arial", fontSize = 9, fontOutline = "OUTLINE" },
			sizes = { buttonSize = 26, spacing = 2 },
		},
	},

	HighVisibility = {
		bar = {
			look = { texture = "Raid", shade = "Gloss", borderStyle = "Pixel", borderSize = 2, borderColor = WHITE, bgColor = c(0, 0, 0, 0.85), spark = true },
			fonts = { font = "Friz", fontSize = 16, fontOutline = "THICKOUTLINE", fontShadow = false },
		},
		health = {
			colors = { textColor = WHITE, colorMode = "threshold", colorStatic = c(0, 1, 0), colorLow = c(1, 0, 0), colorMid = c(1, 1, 0), colorHigh = c(0, 1, 0), ["alert.color"] = c(1, 0, 0) },
			sizes = { width = 280, height = 28 },
		},
		rage = {
			colors = { textColor = WHITE, colorMode = "static", colorStatic = c(1, 0.1, 0.1), colorLow = c(0.8, 0, 0), colorMid = c(1, 0.3, 0), colorHigh = c(1, 0.8, 0), ["alert.color"] = c(1, 1, 0) },
			sizes = { width = 280, height = 26 },
		},
		swing = {
			colors = { textColor = WHITE, colorMainHand = WHITE, colorOffHand = c(0.4, 0.7, 1), colorRanged = c(0.4, 1, 0.4) },
			sizes = { width = 280, height = 16, spacing = 4 },
		},
		stance = {
			look = { buttonStyle = "Pixel", borderColor = WHITE },
			colors = { activeColor = c(1, 1, 0), textColor = WHITE },
			fonts = { font = "Friz", fontSize = 13, fontOutline = "THICKOUTLINE" },
			sizes = { buttonSize = 44, spacing = 6 },
		},
	},

	Ember = {
		bar = {
			look = { texture = "BarFill", shade = "Gloss", borderStyle = "Pixel", borderSize = 1, borderColor = c(0.35, 0.08, 0.02), bgColor = c(0.12, 0.03, 0.01, 0.8), spark = true },
			fonts = { font = "Morpheus", fontSize = 13, fontOutline = "OUTLINE", fontShadow = false },
		},
		health = {
			colors = { textColor = c(1, 0.9, 0.7), colorMode = "gradient", colorStatic = c(1, 0.45, 0.05), colorLow = c(0.7, 0.05, 0.02), colorMid = c(1, 0.45, 0.05), colorHigh = c(1, 0.75, 0.2), ["alert.color"] = c(1, 0.3, 0.05) },
			sizes = { width = 220, height = 18 },
		},
		rage = {
			colors = { textColor = c(1, 0.9, 0.7), colorMode = "gradient", colorStatic = c(0.9, 0.25, 0.02), colorLow = c(0.45, 0.05, 0.02), colorMid = c(0.9, 0.25, 0.02), colorHigh = c(1, 0.6, 0.1), ["alert.color"] = c(1, 0.55, 0.1) },
			sizes = { width = 220, height = 16 },
		},
		swing = {
			colors = { textColor = c(1, 0.9, 0.7), colorMainHand = c(1, 0.55, 0.15), colorOffHand = c(0.9, 0.3, 0.1), colorRanged = c(1, 0.8, 0.3) },
			sizes = { width = 220, height = 12, spacing = 3 },
		},
		stance = {
			look = { buttonStyle = "Pixel", borderColor = c(0.45, 0.12, 0.03) },
			colors = { activeColor = c(1, 0.55, 0.1), textColor = c(1, 0.85, 0.6) },
			fonts = { font = "Morpheus", fontSize = 12, fontOutline = "OUTLINE" },
			sizes = { buttonSize = 36, spacing = 4 },
		},
	},

	Frost = {
		bar = {
			look = { texture = "Flat", shade = "Gloss", borderStyle = "Pixel", borderSize = 1, borderColor = c(0.55, 0.8, 1), bgColor = c(0.02, 0.06, 0.12, 0.8), spark = true },
			fonts = { font = "Friz", fontSize = 12, fontOutline = "OUTLINE", fontShadow = true },
		},
		health = {
			colors = { textColor = c(0.92, 0.97, 1), colorMode = "gradient", colorStatic = c(0.4, 0.75, 1), colorLow = c(0.35, 0.45, 0.9), colorMid = c(0.4, 0.75, 1), colorHigh = c(0.75, 0.95, 1), ["alert.color"] = c(0.6, 0.9, 1) },
			sizes = { width = 220, height = 16 },
		},
		rage = {
			colors = { textColor = c(0.92, 0.97, 1), colorMode = "threshold", colorStatic = c(0.45, 0.6, 1), colorLow = c(0.3, 0.4, 0.85), colorMid = c(0.45, 0.6, 1), colorHigh = c(0.75, 0.85, 1), ["alert.color"] = c(0.8, 0.95, 1) },
			sizes = { width = 220, height = 14 },
		},
		swing = {
			colors = { textColor = c(0.92, 0.97, 1), colorMainHand = c(0.7, 0.9, 1), colorOffHand = c(0.5, 0.7, 1), colorRanged = c(0.6, 1, 0.95) },
			sizes = { width = 220, height = 10, spacing = 3 },
		},
		stance = {
			look = { buttonStyle = "Pixel", borderColor = c(0.55, 0.8, 1) },
			colors = { activeColor = c(0.7, 0.95, 1), textColor = c(0.85, 0.95, 1) },
			fonts = { font = "Friz", fontSize = 11, fontOutline = "OUTLINE" },
			sizes = { buttonSize = 34, spacing = 4 },
		},
	},

	Gladiator = {
		bar = {
			look = { texture = "Skills", shade = "Shadow", borderStyle = "Tooltip", borderSize = 1, borderColor = c(1, 0.82, 0.1), bgColor = c(0, 0, 0, 0.75), spark = true },
			fonts = { font = "Morpheus", fontSize = 13, fontOutline = "OUTLINE", fontShadow = false },
		},
		health = {
			colors = { textColor = c(1, 0.88, 0.45), colorMode = "gradient", colorStatic = c(0.3, 0.75, 0.2), colorLow = c(0.7, 0.1, 0.05), colorMid = c(0.9, 0.65, 0.1), colorHigh = c(0.3, 0.75, 0.2), ["alert.color"] = c(1, 0.82, 0.1) },
			sizes = { width = 230, height = 20 },
		},
		rage = {
			colors = { textColor = c(1, 0.88, 0.45), colorMode = "static", colorStatic = c(0.8, 0.08, 0.05), colorLow = c(0.5, 0.05, 0.03), colorMid = c(0.8, 0.08, 0.05), colorHigh = c(1, 0.3, 0.1), ["alert.color"] = c(1, 0.82, 0.1) },
			sizes = { width = 230, height = 18 },
		},
		swing = {
			colors = { textColor = c(1, 0.88, 0.45), colorMainHand = c(1, 0.82, 0.3), colorOffHand = c(0.85, 0.65, 0.25), colorRanged = c(0.9, 0.75, 0.4) },
			sizes = { width = 230, height = 12, spacing = 3 },
		},
		stance = {
			look = { buttonStyle = "Pixel", borderColor = c(1, 0.82, 0.1) },
			colors = { activeColor = c(1, 0.95, 0.6), textColor = c(1, 0.88, 0.45) },
			fonts = { font = "Morpheus", fontSize = 12, fontOutline = "OUTLINE" },
			sizes = { buttonSize = 38, spacing = 5 },
		},
	},

	Berserker = {
		bar = {
			look = { texture = "Raid", shade = "Shadow", borderStyle = "Pixel", borderSize = 2, borderColor = c(0.25, 0, 0), bgColor = c(0.08, 0, 0, 0.85), spark = true },
			fonts = { font = "Skurri", fontSize = 14, fontOutline = "THICKOUTLINE", fontShadow = false },
		},
		health = {
			colors = { textColor = c(1, 0.85, 0.8), colorMode = "threshold", colorStatic = c(0.45, 0.7, 0.2), colorLow = c(1, 0.15, 0.05), colorMid = c(0.9, 0.6, 0.1), colorHigh = c(0.45, 0.7, 0.2), ["alert.color"] = c(1, 0.2, 0.1) },
			sizes = { width = 240, height = 20 },
		},
		rage = {
			colors = { textColor = c(1, 0.85, 0.8), colorMode = "gradient", colorStatic = c(0.75, 0.02, 0.02), colorLow = c(0.4, 0, 0), colorMid = c(0.75, 0.02, 0.02), colorHigh = c(1, 0.1, 0.05), ["alert.color"] = c(1, 0.35, 0.1) },
			sizes = { width = 240, height = 18 },
		},
		swing = {
			colors = { textColor = c(1, 0.85, 0.8), colorMainHand = c(0.95, 0.25, 0.2), colorOffHand = c(0.75, 0.2, 0.2), colorRanged = c(0.9, 0.5, 0.3) },
			sizes = { width = 240, height = 12, spacing = 3 },
		},
		stance = {
			look = { buttonStyle = "Pixel", borderColor = c(0.35, 0, 0) },
			colors = { activeColor = c(1, 0.25, 0.1), textColor = c(1, 0.8, 0.75) },
			fonts = { font = "Skurri", fontSize = 12, fontOutline = "OUTLINE" },
			sizes = { buttonSize = 36, spacing = 4 },
		},
	},

	Void = {
		bar = {
			look = { texture = "Flat", shade = "Gloss", borderStyle = "Pixel", borderSize = 1, borderColor = c(0.45, 0.2, 0.75), bgColor = c(0.05, 0.02, 0.1, 0.85), spark = true },
			fonts = { font = "Skurri", fontSize = 12, fontOutline = "OUTLINE", fontShadow = false },
		},
		health = {
			colors = { textColor = c(0.92, 0.85, 1), colorMode = "gradient", colorStatic = c(0.4, 0.85, 0.75), colorLow = c(0.6, 0.1, 0.5), colorMid = c(0.55, 0.35, 0.9), colorHigh = c(0.4, 0.85, 0.75), ["alert.color"] = c(0.85, 0.3, 0.9) },
			sizes = { width = 220, height = 16 },
		},
		rage = {
			colors = { textColor = c(0.92, 0.85, 1), colorMode = "threshold", colorStatic = c(0.6, 0.2, 0.85), colorLow = c(0.35, 0.1, 0.55), colorMid = c(0.6, 0.2, 0.85), colorHigh = c(0.85, 0.4, 1), ["alert.color"] = c(0.8, 0.45, 1) },
			sizes = { width = 220, height = 14 },
		},
		swing = {
			colors = { textColor = c(0.92, 0.85, 1), colorMainHand = c(0.75, 0.5, 1), colorOffHand = c(0.55, 0.35, 0.9), colorRanged = c(0.45, 0.85, 0.8) },
			sizes = { width = 220, height = 10, spacing = 3 },
		},
		stance = {
			look = { buttonStyle = "Pixel", borderColor = c(0.45, 0.2, 0.75) },
			colors = { activeColor = c(0.85, 0.55, 1), textColor = c(0.9, 0.85, 1) },
			fonts = { font = "Skurri", fontSize = 11, fontOutline = "OUTLINE" },
			sizes = { buttonSize = 34, spacing = 4 },
		},
	},
}

-- Bar text is centered unless a style says otherwise.
for _, style in pairs(Styles.data) do
	style.bar.fonts.textAlign = style.bar.fonts.textAlign or "CENTER"
end

--- Values of one part of a style for one module (bar values merged with
-- the module's own). Returns nil for an unknown style.
function Styles.Get(name, section, part)
	local style = Styles.data[name]
	if not style then
		return nil
	end
	local out = {}
	if section ~= "stance" and style.bar and style.bar[part] then
		for key, value in pairs(style.bar[part]) do
			out[key] = value
		end
	end
	local own = style[section] and style[section][part]
	if own then
		for key, value in pairs(own) do
			out[key] = value
		end
	end
	return out
end

--- Default value of a styled setting: the Forever style.
function Styles.Default(section, key)
	for _, part in ipairs(Styles.PARTS) do
		local values = Styles.Get("Forever", section, part)
		if values[key] ~= nil then
			return values[key]
		end
	end
	error("no Forever default for " .. section .. "." .. key)
end
