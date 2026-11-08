--[[
Warrior Master - Core/Media.lua
Textures, fonts and sounds.

Only media shipped with the game client is used (no copied artwork):
- atlases used by Blizzard's own WoW Forever UI (1.60.1): the personal
  resource bar (UI-HUD-CoolDownManager-Bar*), the native swing timer
  (ui-swingtimerbar-*), the casting bar (ui-castingbar-*) and action
  buttons (UI-HUD-ActionBar-IconFrame*);
- long-standing interface files and the Latin fonts the client ships
  (Friz Quadrata, Arial Narrow, Morpheus, Skurri).

Optional: when another addon has loaded LibSharedMedia-3.0, its status bar
textures and fonts are offered too. This is a read-only lookup of file
paths; Warrior Master works the same without it.
]]
local _, ns = ...

local Media = {}
ns.Media = Media

Media.WHITE = "Interface\\Buttons\\WHITE8X8"
Media.SPARK = "Interface\\CastingBar\\UI-CastingBar-Spark"
Media.TOOLTIP_BORDER = "Interface\\Tooltips\\UI-Tooltip-Border"
Media.SWING_PIP_ATLAS = "ui-swingtimerbar-pip"

-- Bar fill textures. "atlas" entries come from Blizzard's Forever UI.
Media.textures = {
	Forever = { atlas = "UI-HUD-CoolDownManager-Bar", labelKey = "TEX_FOREVER" },
	ForeverSwing = {
		atlas = "ui-swingtimerbar-filling-mainhand",
		variants = {
			mh = "ui-swingtimerbar-filling-mainhand",
			oh = "ui-swingtimerbar-filling-offhand",
			ranged = "ui-swingtimerbar-filling-ranged",
		},
		pip = "ui-swingtimerbar-pip",
		labelKey = "TEX_FOREVER_SWING",
	},
	ForeverCast = {
		atlas = "ui-castingbar-filling-standard",
		variants = {
			cast = "ui-castingbar-filling-standard",
			channel = "ui-castingbar-filling-channel",
			done = "ui-castingbar-full-standard",
			failed = "ui-castingbar-interrupted",
		},
		pip = "ui-castingbar-pip",
		labelKey = "TEX_FOREVER_CAST",
	},
	Flat = { file = "Interface\\Buttons\\WHITE8X8", labelKey = "TEX_FLAT" },
	Blizzard = { file = "Interface\\TargetingFrame\\UI-StatusBar", labelKey = "TEX_CLASSIC" },
	BarFill = { file = "Interface\\TargetingFrame\\UI-TargetingFrame-BarFill", labelKey = "TEX_SMOOTH" },
	Raid = { file = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill", labelKey = "TEX_RAID" },
	Skills = { file = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar", labelKey = "TEX_SKILLS" },
}
Media.TEXTURE_KEYS = { "Forever", "ForeverSwing", "ForeverCast", "Flat", "Blizzard", "BarFill", "Raid", "Skills" }
Media.DEFAULT_TEXTURE = "Forever"

-- Every font file below is referenced by Blizzard_Fonts_Shared in client
-- 1.60.1. The first four are the Western fonts; the others are the client's
-- Korean and Chinese fonts, which also contain Latin letters and digits.
-- Their accented letters (é, è, ç...) are not guaranteed, so they are
-- listed after the Western fonts and are best used for numbers.
Media.fonts = {
	Friz = "Fonts\\FRIZQT__.TTF",
	Arial = "Fonts\\ARIALN.TTF",
	Morpheus = "Fonts\\MORPHEUS.TTF",
	Skurri = "Fonts\\SKURRI.TTF",
	Gothic = "Fonts\\2002.TTF",
	Damage = "Fonts\\K_Damage.ttf",
	PageText = "Fonts\\K_Pagetext.ttf",
	Kai = "Fonts\\ARKai_T.ttf",
	HeiBold = "Fonts\\bHEI01B.TTF",
	Hei = "Fonts\\ARHei.ttf",
}
Media.FONT_KEYS = { "Friz", "Arial", "Morpheus", "Skurri", "Gothic", "Damage", "PageText", "Kai", "HeiBold", "Hei" }
Media.FONT_LABELS = {
	Friz = "Friz Quadrata",
	Arial = "Arial Narrow",
	Morpheus = "Morpheus",
	Skurri = "Skurri",
	Gothic = "Gothic (2002)",
	Damage = "Damage",
	PageText = "Page Text",
	Kai = "Kai Brush",
	HeiBold = "Hei Bold",
	Hei = "Hei",
}
Media.DEFAULT_FONT = "Friz"

-- Font styles: one-click font + size + outline + shadow combinations.
Media.FONT_PRESET_KEYS = {
	"Forever", "Classic", "Clean", "Crisp", "Fantasy", "Runic", "Bold",
	"Impact", "Storybook", "Brush", "Heavy", "Large",
}
Media.fontPresets = {
	Forever = { font = "Friz", fontSize = 10, fontOutline = "OUTLINE", fontShadow = false, labelKey = "FONTSTYLE_FOREVER" },
	Classic = { font = "Friz", fontSize = 12, fontOutline = "OUTLINE", fontShadow = false, labelKey = "FONTSTYLE_CLASSIC" },
	Clean = { font = "Arial", fontSize = 12, fontOutline = "OUTLINE", fontShadow = false, labelKey = "FONTSTYLE_CLEAN" },
	Crisp = { font = "Arial", fontSize = 11, fontOutline = "NONE", fontShadow = true, labelKey = "FONTSTYLE_CRISP" },
	Fantasy = { font = "Morpheus", fontSize = 13, fontOutline = "OUTLINE", fontShadow = false, labelKey = "FONTSTYLE_FANTASY" },
	Runic = { font = "Skurri", fontSize = 13, fontOutline = "OUTLINE", fontShadow = false, labelKey = "FONTSTYLE_RUNIC" },
	Bold = { font = "Gothic", fontSize = 12, fontOutline = "OUTLINE", fontShadow = false, labelKey = "FONTSTYLE_BOLD" },
	Impact = { font = "Damage", fontSize = 14, fontOutline = "THICKOUTLINE", fontShadow = false, labelKey = "FONTSTYLE_IMPACT" },
	Storybook = { font = "PageText", fontSize = 12, fontOutline = "NONE", fontShadow = true, labelKey = "FONTSTYLE_STORYBOOK" },
	Brush = { font = "Kai", fontSize = 13, fontOutline = "OUTLINE", fontShadow = false, labelKey = "FONTSTYLE_BRUSH" },
	Heavy = { font = "HeiBold", fontSize = 12, fontOutline = "OUTLINE", fontShadow = true, labelKey = "FONTSTYLE_HEAVY" },
	Large = { font = "Friz", fontSize = 16, fontOutline = "THICKOUTLINE", fontShadow = false, labelKey = "FONTSTYLE_LARGE" },
}

--- Name of the font style matching these settings, or nil.
function Media.MatchFontPreset(cfg, withShadow)
	for _, key in ipairs(Media.FONT_PRESET_KEYS) do
		local p = Media.fontPresets[key]
		if p.font == cfg.font and p.fontSize == cfg.fontSize and p.fontOutline == cfg.fontOutline
			and (not withShadow or p.fontShadow == cfg.fontShadow) then
			return key
		end
	end
	return nil
end

-- Background and border styles of the bars. The two Forever styles use the
-- atlases and offsets of Blizzard's personal resource display and swing timer.
Media.frameStyles = {
	Forever = { bgAtlas = "UI-HUD-CoolDownManager-Bar-BG", bgOffsets = { -2, 3, 6, -7 }, insetX = 0, insetY = 0 },
	ForeverFrame = { bgAtlas = "ui-swingtimerbar-background", frameAtlas = "ui-swingtimerbar-frame", insetX = 5, insetY = 4, pip = "ui-swingtimerbar-pip" },
	ForeverCast = { bgAtlas = "ui-castingbar-background", frameAtlas = "ui-castingbar-frame", insetX = 2, insetY = 2, pip = "ui-castingbar-pip" },
}

-- Stance button atlases (Blizzard's action button frame on Forever).
Media.buttonAtlas = {
	background = "UI-HUD-ActionBar-IconFrame-Background",
	frame = "UI-HUD-ActionBar-IconFrame",
	mask = "UI-HUD-ActionBar-IconFrame-Mask",
	highlight = "UI-HUD-ActionBar-IconFrame-Mouseover",
}

-- Sound kits are resolved through the client's SOUNDKIT table when present;
-- the numeric IDs are the long-standing values of the same entries.
Media.sounds = {
	RaidWarning = { kit = "RAID_WARNING", id = 8959, labelKey = "SOUND_RAIDWARNING" },
	ReadyCheck = { kit = "READY_CHECK", id = 8960, labelKey = "SOUND_READYCHECK" },
	Alarm = { kit = "ALARM_CLOCK_WARNING_3", id = 12889, labelKey = "SOUND_ALARM" },
	Whisper = { kit = "TELL_MESSAGE", id = 3081, labelKey = "SOUND_WHISPER" },
	Tick = { kit = "IG_MAINMENU_OPTION_CHECKBOX_ON", id = 856, labelKey = "SOUND_TICK" },
}
Media.SOUND_KEYS = { "RaidWarning", "ReadyCheck", "Alarm", "Whisper", "Tick" }

Media.SOUND_CHANNELS = { "Master", "SFX", "Dialog", "Ambience" }
Media.CHANNEL_LABELS = { Master = "CH_MASTER", SFX = "CH_SFX", Dialog = "CH_DIALOG", Ambience = "CH_AMBIENCE" }

-- Optional LibSharedMedia (provided by other addons) --------------------------------------
local SHARED_PREFIX = "lsm:"
Media.SHARED_PREFIX = SHARED_PREFIX

local function sharedMedia()
	local libStub = LibStub
	if type(libStub) ~= "function" and type(libStub) ~= "table" then
		return nil
	end
	local ok, lib = pcall(libStub, "LibSharedMedia-3.0", true)
	if ok and type(lib) == "table" and type(lib.Fetch) == "function" and type(lib.List) == "function" then
		return lib
	end
	return nil
end

local function sharedList(mediaType)
	local lib = sharedMedia()
	if not lib then
		return {}
	end
	local ok, list = pcall(lib.List, lib, mediaType)
	if not ok or type(list) ~= "table" then
		return {}
	end
	local out = {}
	for _, name in ipairs(list) do
		if type(name) == "string" and name ~= "" and #name <= 60 then
			out[#out + 1] = name
		end
	end
	return out
end

local function sharedFetch(mediaType, name)
	local lib = sharedMedia()
	if not lib then
		return nil
	end
	local ok, path = pcall(lib.Fetch, lib, mediaType, name, true)
	if ok and (type(path) == "string" or type(path) == "number") then
		return path
	end
	return nil
end

-- Lookups ------------------------------------------------------------------------------------
--- Returns the asset for a bar texture key (atlas name or file path) and
-- whether it is an atlas. variant picks a swing type for ForeverSwing.
function Media.ResolveTexture(key, variant)
	local entry = Media.textures[key]
	if not entry and type(key) == "string" and key:sub(1, #SHARED_PREFIX) == SHARED_PREFIX then
		local path = sharedFetch("statusbar", key:sub(#SHARED_PREFIX + 1))
		if path then
			return path, false
		end
	end
	entry = entry or Media.textures[Media.DEFAULT_TEXTURE]
	if entry.atlas then
		return (variant and entry.variants and entry.variants[variant]) or entry.atlas, true
	end
	return entry.file, false
end

function Media.GetFont(key)
	if Media.fonts[key] then
		return Media.fonts[key]
	end
	if type(key) == "string" and key:sub(1, #SHARED_PREFIX) == SHARED_PREFIX then
		local path = sharedFetch("font", key:sub(#SHARED_PREFIX + 1))
		if type(path) == "string" then
			return path
		end
	end
	return Media.fonts[Media.DEFAULT_FONT]
end

--- Dropdown items for bar textures (built-in first, then SharedMedia).
function Media.ListTextures()
	local items = {}
	for _, key in ipairs(Media.TEXTURE_KEYS) do
		items[#items + 1] = { value = key, text = ns.L[Media.textures[key].labelKey] }
	end
	for _, name in ipairs(sharedList("statusbar")) do
		items[#items + 1] = { value = SHARED_PREFIX .. name, text = ns.L.MEDIA_SHARED:format(name) }
	end
	return items
end

function Media.ListFonts()
	local items = {}
	for _, key in ipairs(Media.FONT_KEYS) do
		items[#items + 1] = { value = key, text = Media.FONT_LABELS[key] }
	end
	for _, name in ipairs(sharedList("font")) do
		items[#items + 1] = { value = SHARED_PREFIX .. name, text = ns.L.MEDIA_SHARED:format(name) }
	end
	return items
end

function Media.GetSoundID(key)
	local entry = Media.sounds[key]
	if not entry then
		return nil
	end
	local kit = SOUNDKIT and SOUNDKIT[entry.kit]
	if type(kit) == "number" then
		return kit
	end
	return entry.id
end

--- Plays a configured sound if sounds are enabled in the profile.
function Media.PlayAlert(key)
	local profile = ns.db and ns.db.profile
	if not profile or not profile.general.sounds then
		return false
	end
	return ns.Compat.PlaySound(Media.GetSoundID(key), profile.general.soundChannel)
end

--- Applies a font safely; falls back to the default game font on failure.
-- shadow: draws a 1px black drop shadow (as Blizzard's small fonts do).
function Media.SetFont(fontString, key, size, outline, shadow)
	local flags = (outline == "NONE" or outline == nil) and "" or outline
	local ok, applied = pcall(fontString.SetFont, fontString, Media.GetFont(key), size, flags)
	if (not ok or applied == false) and GameFontNormal then
		pcall(fontString.SetFontObject, fontString, GameFontNormal)
	end
	if shadow ~= nil then
		fontString:SetShadowOffset(shadow and 1 or 0, shadow and -1 or 0)
		fontString:SetShadowColor(0, 0, 0, shadow and 1 or 0)
	end
end
