--[[
Warrior Master - Modules/ResourceBar.lua
Shared implementation of the rage and health bars.

Two display paths:
  readable values  -> colors, text, glow and sound are computed in Lua;
  secret values    -> the raw values go straight to the widgets, colors and
                      glow come from the client's curve objects evaluated by
                      UnitPowerPercent / UnitHealthPercent, and sound alerts
                      pause (they need a comparison that addon code cannot do
                      on a secret value). Nothing is guessed or approximated.
Both paths use the same thresholds so the bar looks the same either way.
]]
local _, ns = ...

local Compat = ns.Compat
local U = ns.Util
local Media = ns.Media
local S = ns.Schema

local floor, format = math.floor, string.format

--- Visibility rule shared by every non-secure display.
function ns:ShouldShow(visibility)
	local state = self.state
	if state.testMode or state.moversShown then
		return true
	end
	if visibility == "combat" then
		return state.inCombat
	elseif visibility == "target" then
		return state.hasTarget
	elseif visibility == "combatOrTarget" then
		return state.inCombat or state.hasTarget
	end
	return true
end

function ns:CurrentAlpha(cfg)
	if self.state.inCombat or self.state.testMode or self.state.moversShown then
		return cfg.alpha
	end
	return cfg.oocAlpha
end

-- Colors ------------------------------------------------------------------------------------
local function thresholds(cfg)
	local midAt = U.Clamp(cfg.midAt / 100, 0, 1)
	local highAt = U.Clamp(cfg.highAt / 100, 0, 1)
	if highAt < midAt then
		midAt, highAt = highAt, midAt
	end
	return midAt, highAt
end

--- Color for a readable fraction (0-1). Mirrors the curve built below.
function ns.ResourceColor(cfg, frac)
	if cfg.colorMode == "static" then
		local c = cfg.colorStatic
		return c.r, c.g, c.b, c.a
	end
	local midAt, highAt = thresholds(cfg)
	local low, mid, high = cfg.colorLow, cfg.colorMid, cfg.colorHigh
	if cfg.colorMode == "threshold" then
		local c = (frac >= highAt and high) or (frac >= midAt and mid) or low
		return c.r, c.g, c.b, c.a
	end
	if frac <= midAt then
		return U.LerpColor(low, mid, midAt > 0 and frac / midAt or 1)
	elseif frac <= highAt then
		local span = highAt - midAt
		return U.LerpColor(mid, high, span > 0 and (frac - midAt) / span or 1)
	end
	return high.r, high.g, high.b, high.a
end

-- Adds a curve point, replacing a previous point at the same x.
local function addPoint(points, x, y)
	local last = points[#points]
	if last and last[1] >= x then
		last[2] = y
	else
		points[#points + 1] = { x, y }
	end
end

function ns.BuildResourceColorCurve(cfg)
	if cfg.colorMode == "static" then
		return nil
	end
	local midAt, highAt = thresholds(cfg)
	local points = {}
	addPoint(points, 0, cfg.colorLow)
	addPoint(points, midAt, cfg.colorMid)
	addPoint(points, highAt, cfg.colorHigh)
	if cfg.colorMode == "gradient" then
		addPoint(points, 1, cfg.colorHigh)
	end
	return Compat.NewColorCurve(points, cfg.colorMode == "gradient")
end

--- Glow on/off curve: 1 when the alert condition holds, 0 otherwise.
function ns.BuildAlertCurve(fraction, direction)
	if direction == "below" then
		return Compat.NewStepCurve({ { 0, 1 }, { fraction + 0.0001, 0 } })
	end
	return Compat.NewStepCurve({ { 0, 0 }, { fraction, 1 } })
end

function ns.AlertActive(frac, fraction, direction)
	if direction == "below" then
		return frac <= fraction
	end
	return frac >= fraction
end

-- Module factory --------------------------------------------------------------------------------
--[[ def fields
  key, titleKey, frameName
  unitEvents   list of unit events registered for "player"
  read()       -> current, maximum (may be secret)
  percent(curve) -> curve result for the current fraction (may be secret)
  test()       -> current, maximum while preview mode is on (plain numbers)
  filter(event, ...) -> false to ignore an event
  alertDirection "above" | "below"
  formats      table of text format handlers
  position(module, cfg) -> true if it placed the frame itself (optional)
  layout(module, cfg)   -> size overrides for ApplyStyle (optional)
  canMove(module)       -> false to disable dragging (optional)
]]
function ns.CreateResourceModule(def)
	local M = ns:NewModule(def.key, def.titleKey)
	M.def = def
	M.hidden = false
	M.stats = { secretUpdates = 0, curveFailures = 0, sounds = 0 }

	function M:OnInitialize()
		self.bar = ns.CreateBar(def.frameName, UIParent)
		local key = def.key
		self.mover = ns.Movers:Register(self.bar, {
			labelKey = def.titleKey,
			getPoint = function()
				return ns.DB:Get(key .. ".point")
			end,
			setPoint = function(point)
				ns.DB:Set(key .. ".point", point)
			end,
			resetPoint = function()
				ns.DB:Set(key .. ".point", S.profile[key].point.default)
			end,
			canMove = function()
				return self.enabled and (not def.canMove or def.canMove(self))
			end,
		})
	end

	function M:OnEnable()
		for _, event in ipairs(def.unitEvents) do
			self:RegisterUnitEvent(event, "player", "OnValueEvent")
		end
		self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnValueEvent")
		self:ApplySettings()
	end

	function M:OnDisable()
		self:UnregisterAllEvents()
		self.bar:StopEffects()
		self.bar:Hide()
		self.lastFrac = nil
	end

	function M:OnValueEvent(event, ...)
		if def.filter and def.filter(event, ...) == false then
			return
		end
		self:Refresh(false)
	end

	function M:ApplySettings()
		local cfg = self:GetConfig()
		local bar = self.bar
		bar:ApplyStyle(cfg, def.layout and def.layout(self, cfg) or nil)
		if def.position and def.position(self, cfg) then
			bar:SetClampedToScreen(cfg.clamp and ns.db.profile.general.clampAll)
		else
			ns.PlaceModuleFrame(self.key, bar, cfg)
		end
		self.colorCurve = ns.BuildResourceColorCurve(cfg)
		self.alertCurve = ns.BuildAlertCurve(cfg.alert.threshold / 100, def.alertDirection)
		bar:ConfigureGlow(cfg.alert.glow, cfg.alert.color, cfg.alert.pulse)
		self.lastFrac = nil
		self:UpdateVisibility()
		self:Refresh(true)
	end

	function M:UpdateVisibility()
		local cfg = self:GetConfig()
		if not self.enabled or not cfg then
			self.bar:Hide()
			return
		end
		self.bar:SetShown(ns:ShouldShow(cfg.visibility))
		self.bar:SetAlpha(ns:CurrentAlpha(cfg))
	end

	function M:Refresh(instant)
		if not self.enabled then
			return
		end
		local cfg = self:GetConfig()
		local current, maximum
		if ns.state.testMode then
			current, maximum = def.test()
		else
			local ok
			ok, current, maximum = pcall(def.read)
			if not ok then
				current, maximum = 0, 1
			end
		end
		local bar = self.bar
		bar:SetRange(0, maximum)
		bar:SetBarValue(current, cfg.smooth and not instant)

		local rc, rm = Compat.ReadableNumber(current), Compat.ReadableNumber(maximum)
		if rc and rm then
			self:UpdateReadable(cfg, rc, rm)
		else
			self:UpdateSecret(cfg, current, maximum)
		end
	end

	function M:UpdateReadable(cfg, current, maximum)
		local bar = self.bar
		local frac = maximum > 0 and U.Clamp(current / maximum, 0, 1) or 0
		self.hidden = false
		bar:SetFillColor(ns.ResourceColor(cfg, frac))

		local mode = cfg.textFormat
		local value = floor(current + 0.5)
		local pct = floor(frac * 100 + 0.5)
		if mode == "value" then
			bar:SetPlainText(tostring(value))
		elseif mode == "percent" then
			bar:SetPlainText(format("%d%%", pct))
		elseif mode == "valueMax" then
			bar:SetPlainText(format("%d / %d", value, floor(maximum + 0.5)))
		elseif mode == "valuePercent" then
			bar:SetPlainText(format("%d (%d%%)", value, pct))
		else
			bar:SetPlainText("")
		end

		local threshold = cfg.alert.threshold / 100
		local active = ns.AlertActive(frac, threshold, def.alertDirection)
		bar:SetGlowGate(active and 1 or 0)

		-- Sound on the transition into the alert zone only (edge-triggered),
		-- never on the first reading and at most once every two seconds.
		if cfg.alert.sound and self.lastFrac ~= nil and not ns.state.testMode then
			local wasActive = ns.AlertActive(self.lastFrac, threshold, def.alertDirection)
			local now = GetTime()
			if active and not wasActive and now - (self.lastSound or 0) >= 2 then
				self.lastSound = now
				self.stats.sounds = self.stats.sounds + 1
				Media.PlayAlert(cfg.alert.soundKey)
			end
		end
		self.lastFrac = frac
	end

	function M:UpdateSecret(cfg, current, maximum)
		local bar = self.bar
		self.hidden = true
		self.lastFrac = nil -- unknown while hidden: no sound edge can be detected
		self.stats.secretUpdates = self.stats.secretUpdates + 1

		if cfg.colorMode == "static" or not self.colorCurve then
			local c = cfg.colorStatic
			bar:SetFillColor(c.r, c.g, c.b, c.a)
		else
			local ok, color = pcall(def.percent, self.colorCurve)
			if not (ok and bar:SetFillColorObject(color)) then
				self.stats.curveFailures = self.stats.curveFailures + 1
				local c = cfg.colorStatic
				bar:SetFillColor(c.r, c.g, c.b, c.a)
			end
		end

		local mode = cfg.textFormat
		if mode == "value" then
			bar:SetTextSafe("%d", current)
		elseif mode == "valueMax" then
			bar:SetTextSafe("%d / %d", current, maximum)
		elseif mode == "percent" or mode == "valuePercent" then
			local curve = Compat.GetPercentCurve()
			local ok, pct = false, nil
			if curve then
				ok, pct = pcall(def.percent, curve)
			end
			if not ok then
				bar:SetPlainText("")
			elseif mode == "percent" then
				bar:SetTextSafe("%.0f%%", pct)
			else
				bar:SetTextSafe("%d (%.0f%%)", current, pct)
			end
		else
			bar:SetPlainText("")
		end

		if self.alertCurve then
			local ok, alpha = pcall(def.percent, self.alertCurve)
			if ok then
				bar:SetGlowGate(alpha)
			else
				bar:SetGlowGate(0)
			end
		else
			bar:SetGlowGate(0)
		end
	end

	function M:OnSettingsChanged(path)
		if path == def.key or path:sub(1, #def.key + 1) == def.key .. "." then
			if self.enabled then
				self:ApplySettings()
			end
		end
	end

	ns:RegisterMessage(M, "SETTINGS_CHANGED", function(self, _, path)
		self:OnSettingsChanged(path)
	end)
	ns:RegisterMessage(M, "STATE_CHANGED", function(self, _, reason)
		if self.enabled then
			self:UpdateVisibility()
			if reason == "test" then
				self.lastFrac = nil
				self:Refresh(true)
			end
		end
	end)
	ns:RegisterMessage(M, "TEST_TICK", function(self)
		if self.enabled then
			self:Refresh(false)
		end
	end)

	return M
end
