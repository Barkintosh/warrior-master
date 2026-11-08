--[[
Warrior Master - Modules/TestMode.lua
Preview mode: shows every bar with simulated values so the player can style
and place them out of combat. It only feeds numbers to the displays; it never
touches secure frames or game actions, and it switches itself off when combat
starts so real information is never hidden behind simulated values.
]]
local _, ns = ...

local TestMode = ns.EventMixin.Embed({})
ns.TestMode = TestMode

local TICK = 0.05
local SWING_MH, SWING_OH = 2.6, 1.9

function TestMode:IsActive()
	return ns.state.testMode == true
end

function TestMode:GetRage()
	local t = self.elapsed or 0
	local rage = 50 + 50 * math.sin(t * 0.9)
	return math.floor(rage + 0.5), 100
end

function TestMode:GetHealth()
	local t = self.elapsed or 0
	local frac = 0.6 + 0.4 * math.sin(t * 0.45)
	return math.floor(4200 * frac + 0.5), 4200
end

function TestMode:SetActive(active, silent)
	active = active and true or false
	if active and ns.Compat.InCombatLockdown() then
		ns:Print(ns.L.COMBAT_BLOCKED)
		return false
	end
	if active == self:IsActive() then
		return true
	end
	ns.state.testMode = active
	if active then
		self.elapsed = 0
		self.sinceTick = 0
		self.nextMH, self.nextOH = 0, 0.4
		self:RegisterEvent("PLAYER_REGEN_DISABLED")
		self.frame = self.frame or CreateFrame("Frame")
		self.frame:SetScript("OnUpdate", function(_, elapsed)
			self:OnUpdate(elapsed)
		end)
	else
		self:UnregisterEvent("PLAYER_REGEN_DISABLED")
		if self.frame then
			self.frame:SetScript("OnUpdate", nil)
		end
	end
	if not silent then
		ns:Print(active and ns.L.TEST_ON or ns.L.TEST_OFF)
	end
	ns:SendMessage("STATE_CHANGED", "test")
	return true
end

function TestMode:Toggle()
	return self:SetActive(not self:IsActive())
end

function TestMode:OnUpdate(elapsed)
	self.elapsed = self.elapsed + elapsed
	self.sinceTick = self.sinceTick + elapsed
	if self.sinceTick < TICK then
		return
	end
	self.sinceTick = 0
	ns:SendMessage("TEST_TICK")
	local swing = ns:GetModule("swing")
	if swing and swing.enabled and not swing.unsupported then
		if self.elapsed >= self.nextMH then
			self.nextMH = self.elapsed + SWING_MH
			swing:SimulateSwing("mh", SWING_MH)
		end
		if self.elapsed >= self.nextOH then
			self.nextOH = self.elapsed + SWING_OH
			swing:SimulateSwing("oh", SWING_OH)
		end
	end
end

function TestMode:PLAYER_REGEN_DISABLED()
	self:SetActive(false, true)
	ns:Print(ns.L.TEST_COMBAT_OFF)
end
