--[[
Warrior Master - Config/Flair.lua
A bit of warrior fun in the settings window (General page > Warrior fun).

- Execute: pressing a button sometimes (chance set by the player, 15% by
  default) plays an execute sound, splashes blood over the window and shouts
  a battle line. A confirmed destructive button (reset...) always does.
- Battle cry: closing the settings sounds a war horn and shows a battle cry
  where the window was.

Purely cosmetic: textures already in the client (a round mask tinted red,
the low-health screen glow, the Execute icon), PlaySound with sound kits
listed in the client's own SOUNDKIT table, and OnUpdate scripts that only
run while an effect plays (about a second). It respects the addon's sound
switch and channel, and can be turned off entirely.
]]
local _, ns = ...

local Media = ns.Media

local Flair = {}
ns.Flair = Flair

-- Sound kits from Blizzard_SharedXML/Mainline/SoundKitConstants.lua on
-- WoW Forever 1.60.1 (name first, number as a fallback).
Flair.SOUNDS = {
	execute = { { kit = "UI_ADVENTURES_DEATH_ENEMY", id = 165951 }, { kit = "UI_73_ARTIFACT_OVERLOADED_ORB_IMPACT_MEDIUM", id = 97597 } },
	shout = { { kit = "UI_WARMODE_ACTIVATE", id = 118563 }, { kit = "PVP_THROUGH_QUEUE", id = 8459 } },
}
Flair.EXECUTE_LINES = 8
Flair.SHOUT_LINES = 5

local DROP_TEXTURE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local FLASH_TEXTURE = "Interface\\FullScreenTextures\\LowHealth"
local EXECUTE_ICON = "Interface\\Icons\\INV_Sword_48"
local DROPS = 14
local SPLASH_TIME = 1.25
local SHOUT_TIME = 1.6
local GRAVITY = -260

--- Random source (tests replace it to get a known result).
Flair.Random = math.random

local function config()
	return ns.db and ns.db.profile.general.flair
end

function Flair:IsEnabled()
	local cfg = config()
	return cfg ~= nil and cfg.enabled == true
end

--- Plays the first sound kit of a list the client knows.
function Flair:Play(which)
	local general = ns.db and ns.db.profile.general
	if not general or not general.sounds then
		return false
	end
	for _, entry in ipairs(self.SOUNDS[which] or {}) do
		local id = (SOUNDKIT and type(SOUNDKIT[entry.kit]) == "number") and SOUNDKIT[entry.kit] or entry.id
		local ok, result = ns.Compat.PlaySound(id, general.soundChannel)
		if ok and result ~= false then
			return true
		end
	end
	return false
end

function Flair:Line(prefix, count)
	return ns.L[prefix .. self.Random(1, count)] or ""
end

-- Execute splash -------------------------------------------------------------------------------
function Flair:CreateSplash(parent)
	if self.splash then
		self.splash:SetParent(parent)
		self.splash:SetAllPoints(parent)
		return self.splash
	end
	local f = CreateFrame("Frame", nil, parent)
	f:SetAllPoints(parent)
	f:SetFrameLevel(parent:GetFrameLevel() + 60)
	f:EnableMouse(false) -- clicks go through to the settings
	f:Hide()
	f.flash = f:CreateTexture(nil, "BACKGROUND")
	f.flash:SetAllPoints(f)
	f.flash:SetTexture(FLASH_TEXTURE)
	f.flash:SetBlendMode("ADD")
	f.drops = {}
	for i = 1, DROPS do
		local t = f:CreateTexture(nil, "ARTWORK")
		t:SetTexture(DROP_TEXTURE)
		f.drops[i] = { tex = t }
	end
	f.icon = f:CreateTexture(nil, "OVERLAY")
	f.icon:SetSize(36, 36)
	f.icon:SetTexture(EXECUTE_ICON)
	f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	f.text = f:CreateFontString(nil, "OVERLAY")
	Media.SetFont(f.text, "Friz", 26, "THICKOUTLINE", false)
	f.text:SetTextColor(0.9, 0.1, 0.06, 1)
	f.text:SetPoint("CENTER", f, "CENTER", 18, 40)
	f.icon:SetPoint("RIGHT", f.text, "LEFT", -8, 0)
	self.splash = f
	return f
end

--- Blood, sound and a battle line. guaranteed: skip the chance roll.
-- anchor: the pressed button (the blood starts there).
function Flair:Execute(guaranteed, anchor)
	local cfg = config()
	if not cfg or not cfg.enabled then
		return false
	end
	if not guaranteed and self.Random(1, 100) > cfg.chance then
		return false
	end
	local window = ns.Config and ns.Config.frame
	if not window or not window:IsShown() then
		return false
	end
	local f = self:CreateSplash(window)
	self:Play("execute")
	f.text:SetText(self:Line("FLAIR_EXECUTE", self.EXECUTE_LINES))

	-- Start point: the pressed button, else the middle of the window.
	local cx, cy = 0, 0
	if anchor and anchor.GetCenter and window.GetCenter then
		local ax, ay = anchor:GetCenter()
		local wx, wy = window:GetCenter()
		if ax and wx then
			cx, cy = ax - wx, ay - wy
		end
	end
	for _, drop in ipairs(f.drops) do
		local size = self.Random(5, 22)
		drop.x = cx + self.Random(-30, 30)
		drop.y = cy + self.Random(-12, 12)
		drop.vx = self.Random(-140, 140)
		drop.vy = self.Random(20, 170)
		drop.tex:SetSize(size, size)
		local dark = self.Random(45, 80) / 100
		drop.tex:SetVertexColor(dark, 0.02, 0.02, 0.95)
		drop.tex:ClearAllPoints()
		drop.tex:SetPoint("CENTER", f, "CENTER", drop.x, drop.y)
	end
	f.elapsed = 0
	f.flash:SetAlpha(0.8)
	f:SetAlpha(1)
	f:Show()
	f:SetScript("OnUpdate", function(frame, elapsed)
		Flair:AnimateSplash(frame, elapsed)
	end)
	return true
end

function Flair:AnimateSplash(f, elapsed)
	f.elapsed = f.elapsed + (elapsed or 0)
	local t = f.elapsed
	if t >= SPLASH_TIME then
		f:SetScript("OnUpdate", nil)
		f:Hide()
		return
	end
	local dt = elapsed or 0
	for _, drop in ipairs(f.drops) do
		drop.vy = drop.vy + GRAVITY * dt
		drop.x = drop.x + drop.vx * dt
		drop.y = drop.y + drop.vy * dt
		drop.tex:ClearAllPoints()
		drop.tex:SetPoint("CENTER", f, "CENTER", drop.x, drop.y)
	end
	local fade = 1 - t / SPLASH_TIME
	f.flash:SetAlpha(0.8 * fade * fade)
	f:SetAlpha(math.min(1, fade * 1.6))
end

-- Battle cry on close ---------------------------------------------------------------------------
function Flair:Shout(window)
	local cfg = config()
	if not cfg or not cfg.enabled or not cfg.closeShout then
		return false
	end
	self:Play("shout")
	local f = self.shout
	if not f then
		f = CreateFrame("Frame", nil, UIParent)
		f:SetSize(400, 60)
		f:SetFrameStrata("DIALOG")
		f:EnableMouse(false)
		f.text = f:CreateFontString(nil, "OVERLAY")
		Media.SetFont(f.text, "Friz", 30, "THICKOUTLINE", false)
		f.text:SetTextColor(1, 0.82, 0.25, 1)
		f.text:SetPoint("CENTER")
		f:Hide()
		self.shout = f
	end
	f:ClearAllPoints()
	local x, y
	if window and window.GetCenter then
		x, y = window:GetCenter()
	end
	if x and y then
		local s = window:GetEffectiveScale() / UIParent:GetEffectiveScale()
		f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x * s, y * s)
	else
		f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
	end
	f.text:SetText(self:Line("FLAIR_SHOUT", self.SHOUT_LINES))
	f.elapsed = 0
	f:SetAlpha(1)
	f:Show()
	f:SetScript("OnUpdate", function(frame, elapsed)
		frame.elapsed = frame.elapsed + (elapsed or 0)
		if frame.elapsed >= SHOUT_TIME then
			frame:SetScript("OnUpdate", nil)
			frame:Hide()
			return
		end
		local p = frame.elapsed / SHOUT_TIME
		frame:SetAlpha(1 - p * p)
		frame.text:SetPoint("CENTER", frame, "CENTER", 0, 30 * p)
	end)
	return true
end

--- Called by every settings button after its action.
function Flair:OnButton(o, button)
	if o and o.noFlair then
		return false
	end
	return self:Execute(o and o.confirm and true or false, button)
end
