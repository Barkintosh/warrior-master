--[[
Warrior Master - Config/Theme.lua
Colors and small drawing helpers for the settings window.
Flat, dark and quiet, with the Warrior class color as the only accent.
]]
local _, ns = ...

local Media = ns.Media

local Theme = {}
ns.Theme = Theme

Theme.colors = {
	bg = { 0.055, 0.055, 0.07, 0.97 },
	panel = { 0.085, 0.085, 0.105, 1 },
	field = { 0.12, 0.12, 0.15, 1 },
	fieldHover = { 0.16, 0.16, 0.20, 1 },
	border = { 0.22, 0.22, 0.27, 1 },
	accent = { 0.78, 0.61, 0.43, 1 },
	accentSoft = { 0.78, 0.61, 0.43, 0.18 },
	text = { 0.92, 0.92, 0.94, 1 },
	dim = { 0.60, 0.60, 0.66, 1 },
	good = { 0.38, 0.85, 0.48, 1 },
	warn = { 1.0, 0.78, 0.32, 1 },
	bad = { 1.0, 0.42, 0.42, 1 },
	info = { 0.55, 0.75, 1.0, 1 },
}

Theme.FONT = Media.fonts.Friz
Theme.SIZE_TEXT = 12
Theme.SIZE_SMALL = 11
Theme.SIZE_HEADER = 14
Theme.SIZE_TITLE = 16

function Theme.Color(name)
	local c = Theme.colors[name] or Theme.colors.text
	return c[1], c[2], c[3], c[4]
end

function Theme.Fill(frame, colorName, layer)
	local t = frame:CreateTexture(nil, layer or "BACKGROUND")
	t:SetAllPoints()
	t:SetColorTexture(Theme.Color(colorName))
	return t
end

--- Requires a frame created with "BackdropTemplate".
function Theme.Border(frame, colorName, size)
	frame:SetBackdrop({ bgFile = Media.WHITE, edgeFile = Media.WHITE, edgeSize = size or 1 })
	frame:SetBackdropColor(Theme.Color("field"))
	frame:SetBackdropBorderColor(Theme.Color(colorName or "border"))
end

function Theme.Text(parent, size, colorName, layer)
	local fs = parent:CreateFontString(nil, layer or "OVERLAY")
	local ok = pcall(fs.SetFont, fs, Theme.FONT, size or Theme.SIZE_TEXT, "")
	if not ok and GameFontHighlight then
		fs:SetFontObject(GameFontHighlight)
	end
	fs:SetTextColor(Theme.Color(colorName or "text"))
	fs:SetJustifyH("LEFT")
	return fs
end
