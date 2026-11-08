--[[
Warrior Master - Widgets/Bar.lua
Customizable status bar shared by the rage, health and swing modules.

All value setters accept "secret" values: StatusBar:SetMinMaxValues/SetValue,
StatusBar:SetStatusBarColor, FontString:SetText/SetFormattedText and
Region:SetAlpha are documented as accepting secret arguments from addon code
on this client (SecretArguments = "AllowedWhenTainted"). The widget never
does arithmetic on the values it displays; each call is wrapped in pcall so
an unexpected client behaviour degrades the display instead of erroring.

Layering (bottom to top):
  frame (backdrop border) > bg texture > status bar fill > shade overlay >
  spark > text; the glow sits around the frame on its own child frames:
  glowGate (alpha = alert on/off, may be driven by a curve) > glow (pulse).
]]
local _, ns = ...

local Media = ns.Media
local Compat = ns.Compat

local pcall = pcall

local Bar = {}
ns.BarMixin = Bar

local GLOW_SIZE = 3

local function createGlowEdge(parent)
	local t = parent:CreateTexture(nil, "ARTWORK")
	t:SetTexture(Media.WHITE)
	t:SetBlendMode("ADD")
	return t
end

--- Creates a bar. name may be nil (frames used by movers have names).
function ns.CreateBar(name, parent)
	local f = CreateFrame("Frame", name, parent or UIParent, "BackdropTemplate")
	for key, fn in pairs(Bar) do
		f[key] = fn
	end
	f:SetSize(200, 16)
	f:SetFrameStrata("MEDIUM")

	f.bg = f:CreateTexture(nil, "BACKGROUND")
	-- Atlas frame drawn around the fill (WoW Forever swing timer style).
	f.frameTex = f:CreateTexture(nil, "BACKGROUND", nil, 1)
	f.frameTex:Hide()

	f.sb = CreateFrame("StatusBar", nil, f)
	f.sb:SetMinMaxValues(0, 1)
	f.sb:SetValue(0)
	f.sb:SetStatusBarTexture(Media.WHITE)

	f.shade = f.sb:CreateTexture(nil, "ARTWORK", nil, 3)
	f.shade:SetTexture(Media.WHITE)

	f.spark = f.sb:CreateTexture(nil, "OVERLAY")
	f.spark:SetTexture(Media.SPARK)
	f.spark:SetBlendMode("ADD")

	f.textFrame = CreateFrame("Frame", nil, f)
	f.textFrame:SetAllPoints(f)
	f.textFrame:SetFrameLevel(f.sb:GetFrameLevel() + 4)
	f.text = f.textFrame:CreateFontString(nil, "OVERLAY")
	f.label = f.textFrame:CreateFontString(nil, "OVERLAY")

	-- Glow: gate frame (on/off) > pulsing frame > four edge textures.
	f.glowGate = CreateFrame("Frame", nil, f)
	f.glowGate:SetPoint("TOPLEFT", f, "TOPLEFT", -GLOW_SIZE, GLOW_SIZE)
	f.glowGate:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", GLOW_SIZE, -GLOW_SIZE)
	f.glowGate:SetFrameLevel(math.max(0, f:GetFrameLevel() - 1))
	f.glowGate:SetAlpha(0)
	f.glow = CreateFrame("Frame", nil, f.glowGate)
	f.glow:SetAllPoints(f.glowGate)
	f.glowEdges = {
		top = createGlowEdge(f.glow),
		bottom = createGlowEdge(f.glow),
		left = createGlowEdge(f.glow),
		right = createGlowEdge(f.glow),
	}
	local e = f.glowEdges
	e.top:SetPoint("TOPLEFT")
	e.top:SetPoint("TOPRIGHT")
	e.top:SetHeight(GLOW_SIZE)
	e.bottom:SetPoint("BOTTOMLEFT")
	e.bottom:SetPoint("BOTTOMRIGHT")
	e.bottom:SetHeight(GLOW_SIZE)
	e.left:SetPoint("TOPLEFT", e.top, "BOTTOMLEFT")
	e.left:SetPoint("BOTTOMLEFT", e.bottom, "TOPLEFT")
	e.left:SetWidth(GLOW_SIZE)
	e.right:SetPoint("TOPRIGHT", e.top, "BOTTOMRIGHT")
	e.right:SetPoint("BOTTOMRIGHT", e.bottom, "TOPRIGHT")
	e.right:SetWidth(GLOW_SIZE)

	f.pulse = f.glow:CreateAnimationGroup()
	f.pulse:SetLooping("BOUNCE")
	local fade = f.pulse:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0.25)
	fade:SetDuration(0.55)
	fade:SetSmoothing("IN_OUT")

	f.insetX, f.insetY = 0, 0
	f.glowEnabled = false
	f:Hide()
	return f
end

-- Style ---------------------------------------------------------------------------------
local function setBackdrop(f, style, size, color)
	if style == "Pixel" then
		f:SetBackdrop({ edgeFile = Media.WHITE, edgeSize = size })
		f:SetBackdropBorderColor(color.r, color.g, color.b, color.a)
		return size
	elseif style == "Tooltip" then
		f:SetBackdrop({ edgeFile = Media.TOOLTIP_BORDER, edgeSize = 12 })
		f:SetBackdropBorderColor(color.r, color.g, color.b, color.a)
		return 3
	end
	f:SetBackdrop(nil)
	return 0
end

--- True when a border style is drawn with Blizzard atlases.
function ns.IsAtlasBorder(style)
	return Media.frameStyles[style] ~= nil
end

local function setAtlas(texture, atlas, useSize)
	local ok = pcall(texture.SetAtlas, texture, atlas, useSize and true or false)
	return ok
end

--- Applies background and border; returns the horizontal and vertical insets.
local function applyFrame(self, cfg)
	local frameStyle = Media.frameStyles[cfg.borderStyle]
	self.bg:ClearAllPoints()
	if frameStyle then
		self:SetBackdrop(nil)
		local o = frameStyle.bgOffsets
		if o then
			self.bg:SetPoint("TOPLEFT", self, "TOPLEFT", o[1], o[2])
			self.bg:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", o[3], o[4])
		else
			self.bg:SetAllPoints(self)
		end
		if setAtlas(self.bg, frameStyle.bgAtlas) then
			self.bg:SetVertexColor(1, 1, 1, 1)
		else
			self.bg:SetColorTexture(0, 0, 0, 0.5)
		end
		if frameStyle.frameAtlas and setAtlas(self.frameTex, frameStyle.frameAtlas) then
			self.frameTex:ClearAllPoints()
			self.frameTex:SetAllPoints(self)
			self.frameTex:Show()
		else
			self.frameTex:Hide()
		end
		return frameStyle.insetX, frameStyle.insetY
	end
	self.frameTex:Hide()
	local inset = setBackdrop(self, cfg.borderStyle, cfg.borderSize, cfg.borderColor)
	self.bg:SetPoint("TOPLEFT", inset, -inset)
	self.bg:SetPoint("BOTTOMRIGHT", -inset, inset)
	self.bg:SetColorTexture(cfg.bgColor.r, cfg.bgColor.g, cfg.bgColor.b, cfg.bgColor.a)
	self.bg:SetVertexColor(1, 1, 1, 1)
	return inset, inset
end

--- Applies the visual settings shared by every bar (see barVisual in Schema).
-- opts: { width, height } size overrides, { variant } swing type for the
-- WoW Forever swing texture ("mh", "oh", "ranged").
function Bar:ApplyStyle(cfg, opts)
	opts = opts or {}
	local width, height = opts.width or cfg.width, opts.height or cfg.height
	self:SetSize(width, height)
	self:SetScale(cfg.scale or 1)

	local insetX, insetY = applyFrame(self, cfg)
	self.insetX, self.insetY = insetX, insetY

	self.sb:ClearAllPoints()
	self.sb:SetPoint("TOPLEFT", insetX, -insetY)
	self.sb:SetPoint("BOTTOMRIGHT", -insetX, insetY)
	local asset = Media.ResolveTexture(cfg.texture, opts.variant)
	if not pcall(self.sb.SetStatusBarTexture, self.sb, asset) then
		self.sb:SetStatusBarTexture(Media.WHITE)
	end

	local fill = self.sb:GetStatusBarTexture()
	self.shade:ClearAllPoints()
	self.shade:SetAllPoints(fill)
	if cfg.shade == "Gloss" and CreateColor then
		self.shade:SetGradient("VERTICAL", CreateColor(0, 0, 0, 0.18), CreateColor(1, 1, 1, 0.22))
		self.shade:Show()
	elseif cfg.shade == "Shadow" and CreateColor then
		self.shade:SetGradient("VERTICAL", CreateColor(0, 0, 0, 0.35), CreateColor(0, 0, 0, 0))
		self.shade:Show()
	else
		self.shade:Hide()
	end

	-- Spark: the native "pip" of the Forever swing timer or casting bar
	-- with their frame or texture, the classic casting-bar spark otherwise.
	local h = height - insetY * 2
	self.spark:ClearAllPoints()
	local frameStyle = Media.frameStyles[cfg.borderStyle]
	local texture = Media.textures[cfg.texture]
	local pip = (frameStyle and frameStyle.pip) or (texture and texture.pip)
	if pip and setAtlas(self.spark, pip, true) then
		self.spark:SetBlendMode("BLEND")
		self.spark:SetHeight(math.max(4, h))
		self.spark:SetPoint("RIGHT", fill, "RIGHT", 0, 0)
	else
		self.spark:SetTexture(Media.SPARK)
		self.spark:SetBlendMode("ADD")
		self.spark:SetSize(math.max(8, h * 0.8), math.max(4, h * 2.2))
		self.spark:SetPoint("CENTER", fill, "RIGHT", 0, 0)
	end
	self.spark:SetShown(cfg.spark and true or false)

	Media.SetFont(self.text, cfg.font, cfg.fontSize, cfg.fontOutline, cfg.fontShadow)
	Media.SetFont(self.label, cfg.font, cfg.fontSize, cfg.fontOutline, cfg.fontShadow)
	self.text:ClearAllPoints()
	local align = cfg.textAlign or "CENTER"
	local pad = 4 + insetX
	if align == "LEFT" then
		self.text:SetPoint("LEFT", pad, 0)
	elseif align == "RIGHT" then
		self.text:SetPoint("RIGHT", -pad, 0)
	else
		self.text:SetPoint("CENTER", 0, 0)
	end
	self.text:SetJustifyH(align)
	self.text:SetTextColor(cfg.textColor.r, cfg.textColor.g, cfg.textColor.b, cfg.textColor.a)
	self.label:ClearAllPoints()
	self.label:SetPoint("LEFT", pad, 0)
	self.label:SetJustifyH("LEFT")
	self.label:SetTextColor(cfg.textColor.r, cfg.textColor.g, cfg.textColor.b, (cfg.textColor.a or 1) * 0.8)
end

function Bar:SetReverseFill(reverse)
	pcall(self.sb.SetReverseFill, self.sb, reverse and true or false)
end

-- Values (secret-safe) ----------------------------------------------------------------------
function Bar:SetRange(minValue, maxValue)
	return pcall(self.sb.SetMinMaxValues, self.sb, minValue, maxValue)
end

--- smooth: use the client's native interpolation (works with secret values).
function Bar:SetBarValue(value, smooth)
	local interp = smooth and Compat.INTERP_SMOOTH or Compat.INTERP_IMMEDIATE
	if interp ~= nil then
		local ok = pcall(self.sb.SetValue, self.sb, value, interp)
		if ok then
			return true
		end
	end
	return pcall(self.sb.SetValue, self.sb, value)
end

function Bar:SetFillColor(r, g, b, a)
	return pcall(self.sb.SetStatusBarColor, self.sb, r, g, b, a or 1)
end

--- Applies a color object returned by a color curve (may hold secret values).
function Bar:SetFillColorObject(color)
	if color == nil then
		return false
	end
	return pcall(function()
		self.sb:SetStatusBarColor(color:GetRGBA())
	end)
end

--- Shows text from a format string; arguments may be secret values.
function Bar:SetTextSafe(fmt, ...)
	local ok = pcall(self.text.SetFormattedText, self.text, fmt, ...)
	if not ok then
		self.text:SetText("")
	end
	return ok
end

function Bar:SetPlainText(text)
	self.text:SetText(text or "")
end

-- Glow -------------------------------------------------------------------------------------
function Bar:ConfigureGlow(enabled, color, pulse)
	self.glowEnabled = enabled and true or false
	for _, edge in pairs(self.glowEdges) do
		edge:SetVertexColor(color.r, color.g, color.b, 0.9)
	end
	if self.glowEnabled and pulse then
		if not self.pulse:IsPlaying() then
			self.pulse:Play()
		end
	else
		self.pulse:Stop()
		self.glow:SetAlpha(1)
	end
	if not self.glowEnabled then
		self.glowGate:SetAlpha(0)
	end
end

--- alpha may be a plain number or a secret value produced by a curve.
function Bar:SetGlowGate(alpha)
	if not self.glowEnabled then
		self.glowGate:SetAlpha(0)
		return true
	end
	local ok = pcall(self.glowGate.SetAlpha, self.glowGate, alpha)
	if not ok then
		self.glowGate:SetAlpha(0)
	end
	return ok
end

function Bar:StopEffects()
	self.pulse:Stop()
	self.glowGate:SetAlpha(0)
end
