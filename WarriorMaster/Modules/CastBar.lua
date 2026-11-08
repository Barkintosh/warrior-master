--[[
Warrior Master - Modules/CastBar.lua
Player cast bar: every spell cast and channel, including the items that
cast (Hearthstone, bandages, food and drink, quest items...).

Data source: UnitCastingInfo("player") and UnitChannelInfo("player"), read
on the UNIT_SPELLCAST_* events, exactly as Blizzard's own CastingBarFrame
does on client 1.60.1. Start and end times come from the client; nothing is
estimated.

- Hidden values: when the client hides cast timing (secret values), the bar
  is not drawn for that cast. Addons may not do arithmetic on secret values
  and StatusBar:SetTimerDuration only accepts them from Blizzard's code, so
  showing a bar would mean guessing.
- Failed or interrupted casts flash in the failure color. When another spell
  fails while a cast is still running (pressing a key mid-cast), the running
  cast is left alone.
- Display only: it never casts, cancels or reacts to anything, and it never
  changes the game's own cast bar.
- The OnUpdate script only runs while the bar is shown.
]]
local _, ns = ...

local Compat = ns.Compat
local Media = ns.Media
local S = ns.Schema

local GetTime, pcall, format = GetTime, pcall, string.format

local CastBar = ns:NewModule("cast", "MODULE_CAST")
CastBar.stats = { casts = 0, channels = 0, secret = 0, failed = 0, done = 0 }

local HOLD_TIME = 0.35 -- the finished or failed bar stays this long...
local FADE_TIME = 0.45 -- ...then fades out over this long
local TEXT_INTERVAL = 0.05
local ICON_GAP = 4
local PREVIEW_ICON = "Interface\\Icons\\INV_Misc_Rune_01" -- Hearthstone

local EVENTS = {
	"UNIT_SPELLCAST_START",
	"UNIT_SPELLCAST_STOP",
	"UNIT_SPELLCAST_FAILED",
	"UNIT_SPELLCAST_INTERRUPTED",
	"UNIT_SPELLCAST_DELAYED",
	"UNIT_SPELLCAST_CHANNEL_START",
	"UNIT_SPELLCAST_CHANNEL_STOP",
	"UNIT_SPELLCAST_CHANNEL_UPDATE",
}

-- Fill color and Forever texture variant for each state.
local STATE_COLORS = { cast = "colorCast", channel = "colorChannel", done = "colorSuccess", failed = "colorFailed" }

--- Reads the player's current cast (or channel).
-- Returns a table, or nil plus a reason: "none", "secret" or "invalid".
local function readCast(channel)
	local fn = channel and UnitChannelInfo or UnitCastingInfo
	if type(fn) ~= "function" then
		return nil, "none"
	end
	local ok, name, text, texture, startMs, endMs, _, seventh = pcall(fn, "player")
	if not ok then
		return nil, "none"
	end
	if Compat.IsSecret(startMs) or Compat.IsSecret(endMs) then
		return nil, "secret"
	end
	if not Compat.IsSecret(name) and name == nil then
		return nil, "none"
	end
	startMs, endMs = Compat.ReadableNumber(startMs), Compat.ReadableNumber(endMs)
	if not startMs or not endMs or endMs <= startMs or endMs - startMs > 3600000 then
		return nil, "invalid"
	end
	local label = text
	if not Compat.IsSecret(label) and (label == nil or label == "") then
		label = name
	end
	-- The seventh value is the cast's GUID for casts (notInterruptible for
	-- channels); it is only compared when it is a readable string.
	local castID = nil
	if not channel and not Compat.IsSecret(seventh) and type(seventh) == "string" then
		castID = seventh
	end
	return {
		label = label,
		icon = texture,
		start = startMs / 1000,
		finish = endMs / 1000,
		channel = channel and true or false,
		castID = castID,
	}
end

--- True when the client still reports a cast or channel in progress.
local function stillCasting()
	for _, channel in ipairs({ false, true }) do
		local info, reason = readCast(channel)
		if info or reason == "secret" then
			return true
		end
	end
	return false
end

--- A readable GUID from an event payload, or nil.
local function readableGUID(value)
	if Compat.IsSecret(value) or type(value) ~= "string" then
		return nil
	end
	return value
end

-- Frames ---------------------------------------------------------------------------------------
function CastBar:OnInitialize()
	local holder = CreateFrame("Frame", "WarriorMasterCastBar", UIParent)
	holder:SetSize(212, 16)
	holder:SetFrameStrata("MEDIUM")
	holder:Hide()
	self.holder = holder
	self.icon = holder:CreateTexture(nil, "ARTWORK")
	self.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	self.iconBorder = holder:CreateTexture(nil, "BACKGROUND")
	self.iconBorder:SetColorTexture(0, 0, 0, 1)
	self.bar = ns.CreateBar(nil, holder)
	self.bar:SetRange(0, 1)
	self.bar:Show()
	self.updater = CreateFrame("Frame")
	self.mover = ns.Movers:Register(holder, {
		labelKey = "MODULE_CAST",
		getPoint = function()
			return ns.DB:Get("cast.point")
		end,
		setPoint = function(point)
			ns.DB:Set("cast.point", point)
		end,
		resetPoint = function()
			ns.DB:Set("cast.point", S.profile.cast.point.default)
		end,
		canMove = function()
			return self.enabled
		end,
	})
end

function CastBar:OnEnable()
	for _, event in ipairs(EVENTS) do
		self:RegisterUnitEvent(event, "player")
	end
	self:RegisterEvent("PLAYER_ENTERING_WORLD")
	self:ApplySettings()
	self:PLAYER_ENTERING_WORLD()
end

function CastBar:OnDisable()
	self:UnregisterAllEvents()
	self.current, self.ending, self.preview = nil, nil, nil
	self:StopUpdating()
	self.holder:Hide()
end

function CastBar:ApplySettings()
	local cfg = self:GetConfig()
	self.holder:SetScale(cfg.scale)
	ns.PlaceModuleFrame("cast", self.holder, cfg)
	local iconSize = cfg.showIcon and cfg.height or 0
	local barWidth = math.max(20, cfg.width - (cfg.showIcon and (iconSize + ICON_GAP) or 0))
	self.holder:SetSize(cfg.width, cfg.height)
	self.icon:ClearAllPoints()
	self.icon:SetPoint("TOPLEFT", self.holder, "TOPLEFT", 1, -1)
	self.icon:SetSize(math.max(1, iconSize - 2), math.max(1, iconSize - 2))
	self.iconBorder:ClearAllPoints()
	self.iconBorder:SetPoint("TOPLEFT", self.holder, "TOPLEFT", 0, 0)
	self.iconBorder:SetSize(math.max(1, iconSize), math.max(1, iconSize))
	self.icon:SetShown(cfg.showIcon and true or false)
	self.iconBorder:SetShown(cfg.showIcon and true or false)
	self.bar:ClearAllPoints()
	self.bar:SetPoint("TOPRIGHT", self.holder, "TOPRIGHT", 0, 0)
	self.variant = nil
	self.bar:ApplyStyle(cfg, { width = barWidth, height = cfg.height, variant = "cast" })
	self.bar:SetScale(1) -- the holder carries the scale
	self.bar:SetReverseFill(false)
	self.bar:ConfigureGlow(false, cfg.colorCast, false)
	self:Redraw()
end

--- Fill texture variant and color for a state ("cast", "channel", "done", "failed").
function CastBar:SetState(state)
	local cfg = self:GetConfig()
	if self.variant ~= state then
		self.variant = state
		local asset = Media.ResolveTexture(cfg.texture, state)
		if not pcall(self.bar.sb.SetStatusBarTexture, self.bar.sb, asset) then
			self.bar.sb:SetStatusBarTexture(Media.WHITE)
		end
	end
	local c = cfg[STATE_COLORS[state]]
	self.bar:SetFillColor(c.r, c.g, c.b, c.a)
	self.bar.spark:SetShown((cfg.spark and (state == "cast" or state == "channel")) and true or false)
end

-- Drawing -----------------------------------------------------------------------------------------
function CastBar:UpdateVisibility()
	local cfg = self:GetConfig()
	if not self.enabled or not cfg then
		self.holder:Hide()
		return
	end
	local active = self.current or self.ending or self.preview or ns.state.moversShown
	self.holder:SetShown((active and ns:ShouldShow(cfg.visibility)) and true or false)
	self.holder:SetAlpha(ns:CurrentAlpha(cfg) * (self.fade or 1))
end

function CastBar:ShowInfo(info)
	local cfg = self:GetConfig()
	self.bar.label:SetText(cfg.showName and info.label or "")
	if cfg.showIcon then
		if not pcall(self.icon.SetTexture, self.icon, info.icon) then
			self.icon:SetTexture(nil)
		end
	end
end

function CastBar:Draw(now)
	local cfg = self:GetConfig()
	local cast = self.current or self.preview
	if not cast then
		return
	end
	local total = cast.finish - cast.start
	local remaining = cast.finish - now
	if remaining < 0 then
		remaining = 0
	elseif remaining > total then
		remaining = total
	end
	local progress = cast.channel and (remaining / total) or (1 - remaining / total)
	self.bar:SetBarValue(progress, false)
	if cfg.textMode == "remaining" then
		self.bar:SetPlainText(format("%.1f", remaining))
	elseif cfg.textMode == "both" then
		self.bar:SetPlainText(format("%.1f / %.1f", remaining, total))
	else
		self.bar:SetPlainText("")
	end
end

--- Redraws from the current state (after a settings change).
function CastBar:Redraw()
	local cast = self.current or self.preview
	if cast then
		self:SetState(cast.channel and "channel" or "cast")
		self:ShowInfo(cast)
		self:Draw(GetTime())
	elseif self.ending then
		self:SetState(self.ending.state)
	elseif ns.state.moversShown then
		self:SetState("cast")
		self:ShowInfo({ label = ns.L.MODULE_CAST, icon = PREVIEW_ICON })
		self.bar:SetBarValue(0.6, false)
		self.bar:SetPlainText("")
	end
	if not (cast or self.ending) then
		self:StopUpdating()
	end
	self:UpdateVisibility()
end

function CastBar:EnsureUpdating()
	if not self.updating then
		self.updating = true
		self.updater:SetScript("OnUpdate", function()
			self:OnUpdate()
		end)
	end
end

function CastBar:StopUpdating()
	self.updating = false
	self.updater:SetScript("OnUpdate", nil)
end

function CastBar:OnUpdate()
	local now = GetTime()
	local cast = self.current or self.preview
	if cast then
		if now >= cast.finish then
			if self.preview then
				self.preview = nil
				self:Finish("done")
			else
				-- The client's STOP event normally arrives first; if it does
				-- not, the bar still ends exactly when the cast does.
				self:Finish(cast.channel and "channelDone" or "done")
			end
			return
		end
		if now - (self.lastText or 0) >= TEXT_INTERVAL then
			self.lastText = now
			self:Draw(now)
		else
			local total = cast.finish - cast.start
			local remaining = cast.finish - now
			self.bar:SetBarValue(cast.channel and (remaining / total) or (1 - remaining / total), false)
		end
		return
	end
	local ending = self.ending
	if ending then
		local age = now - ending.at
		if age < HOLD_TIME then
			return
		end
		local cfg = self:GetConfig()
		if not cfg.fadeOut or age >= HOLD_TIME + FADE_TIME then
			self.ending, self.fade = nil, nil
			self:StopUpdating()
			self:UpdateVisibility()
			return
		end
		self.fade = 1 - (age - HOLD_TIME) / FADE_TIME
		self:UpdateVisibility()
		return
	end
	self:StopUpdating()
end

-- Cast states -----------------------------------------------------------------------------------
function CastBar:Begin(channel)
	local info, reason = readCast(channel)
	if not info then
		if reason == "secret" then
			self.stats.secret = self.stats.secret + 1
		end
		self.current = nil
		if not self.ending then
			self:UpdateVisibility()
		end
		return
	end
	if channel then
		self.stats.channels = self.stats.channels + 1
	else
		self.stats.casts = self.stats.casts + 1
	end
	self.preview = nil
	self.current, self.ending, self.fade = info, nil, nil
	self.lastText = 0
	self:SetState(channel and "channel" or "cast")
	self:ShowInfo(info)
	self:Draw(GetTime())
	self:UpdateVisibility()
	self:EnsureUpdating()
end

--- Ends the running cast: "done" (full bar), "channelDone" (empty bar),
-- "failed" or "interrupted" (failure color and text).
function CastBar:Finish(how)
	local cfg = self:GetConfig()
	local cast = self.current or self.preview
	self.current, self.preview = nil, nil
	if how == "failed" or how == "interrupted" then
		self.stats.failed = self.stats.failed + 1
		self:SetState("failed")
		self.bar:SetBarValue(1, false)
		self.bar.label:SetText(how == "failed" and ns.L.CAST_FAILED or ns.L.CAST_INTERRUPTED)
		self.ending = { state = "failed", at = GetTime() }
	else
		self.stats.done = self.stats.done + 1
		self:SetState("done")
		self.bar:SetBarValue((how == "channelDone" or (cast and cast.channel)) and 0 or 1, false)
		self.ending = { state = "done", at = GetTime() }
	end
	if cfg.textMode ~= "none" then
		self.bar:SetPlainText("")
	end
	self.fade = nil
	self:UpdateVisibility()
	self:EnsureUpdating()
end

-- Events -----------------------------------------------------------------------------------------
function CastBar:UNIT_SPELLCAST_START()
	self:Begin(false)
end

function CastBar:UNIT_SPELLCAST_CHANNEL_START()
	self:Begin(true)
end

function CastBar:UNIT_SPELLCAST_DELAYED()
	if self.current and not self.current.channel then
		local info = readCast(false)
		if info then
			self.current.start, self.current.finish = info.start, info.finish
			self:Draw(GetTime())
		end
	end
end

function CastBar:UNIT_SPELLCAST_CHANNEL_UPDATE()
	if self.current and self.current.channel then
		local info = readCast(true)
		if info then
			self.current.start, self.current.finish = info.start, info.finish
			self:Draw(GetTime())
		end
	end
end

--- True when an event's cast GUID belongs to another cast than ours.
function CastBar:IsOtherCast(castGUID)
	local theirs = readableGUID(castGUID)
	local ours = self.current and self.current.castID
	return theirs ~= nil and ours ~= nil and theirs ~= ours
end

function CastBar:UNIT_SPELLCAST_STOP(_, _, castGUID)
	if self.current and not self.current.channel and not self:IsOtherCast(castGUID) then
		self:Finish("done")
	end
end

function CastBar:UNIT_SPELLCAST_CHANNEL_STOP(_, _, _, _, interruptedBy)
	if self.current and self.current.channel then
		local cut = not Compat.IsSecret(interruptedBy) and interruptedBy ~= nil
		self:Finish(cut and "interrupted" or "channelDone")
	end
end

function CastBar:OnCastFailure(how, castGUID)
	if not self.current or self:IsOtherCast(castGUID) then
		return
	end
	-- Another spell failed while ours keeps going: leave it alone.
	if readableGUID(castGUID) == nil or self.current.castID == nil then
		if stillCasting() then
			return
		end
	end
	self:Finish(how)
end

function CastBar:UNIT_SPELLCAST_FAILED(_, _, castGUID)
	self:OnCastFailure("failed", castGUID)
end

function CastBar:UNIT_SPELLCAST_INTERRUPTED(_, _, castGUID)
	self:OnCastFailure("interrupted", castGUID)
end

--- Picks up a cast already running (after a loading screen or /reload).
function CastBar:PLAYER_ENTERING_WORLD()
	local channel = readCast(true)
	if channel then
		self:Begin(true)
	elseif readCast(false) then
		self:Begin(false)
	else
		self:UpdateVisibility()
	end
end

-- Preview mode ------------------------------------------------------------------------------------
--- Shows a simulated cast (preview mode only; no game data involved).
function CastBar:SimulateCast(duration, channel)
	if not self.enabled or self.current then
		return
	end
	local now = GetTime()
	self.preview = {
		label = channel and ns.L.CAST_PREVIEW_CHANNEL or ns.L.CAST_PREVIEW,
		icon = PREVIEW_ICON,
		start = now,
		finish = now + duration,
		channel = channel and true or false,
	}
	self.ending, self.fade = nil, nil
	self.lastText = 0
	self:SetState(channel and "channel" or "cast")
	self:ShowInfo(self.preview)
	self:Draw(now)
	self:UpdateVisibility()
	self:EnsureUpdating()
end

ns:RegisterMessage(CastBar, "SETTINGS_CHANGED", function(self, _, path)
	if self.enabled and (path == "cast" or path:sub(1, 5) == "cast.") then
		self:ApplySettings()
	end
end)
ns:RegisterMessage(CastBar, "STATE_CHANGED", function(self, _, reason)
	if not self.enabled then
		return
	end
	if reason == "test" and not ns.state.testMode then
		self.preview = nil
	end
	self:Redraw()
end)
