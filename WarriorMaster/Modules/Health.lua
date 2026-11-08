--[[
Warrior Master - Modules/Health.lua
Personal health bar with a low-health warning. Reads health with
UnitHealth / UnitHealthMax / UnitHealthPercent (documented for client
1.60.1; UnitHealth is marked as possibly secret).
]]
local _, ns = ...

local Health = ns.CreateResourceModule({
	key = "health",
	titleKey = "MODULE_HEALTH",
	frameName = "WarriorMasterHealthBar",
	unitEvents = { "UNIT_HEALTH", "UNIT_MAXHEALTH" },
	alertDirection = "below",

	read = function()
		return UnitHealth("player"), UnitHealthMax("player")
	end,

	percent = function(curve)
		return UnitHealthPercent("player", true, curve)
	end,

	test = function()
		return ns.TestMode:GetHealth()
	end,
})

-- Anything that moves or resizes the health bar must re-anchor an attached rage bar.
local baseApply = Health.ApplySettings
function Health:ApplySettings()
	baseApply(self)
	ns:SendMessage("LAYOUT_CHANGED", "health")
end

local baseDisable = Health.OnDisable
function Health:OnDisable()
	baseDisable(self)
	ns:SendMessage("LAYOUT_CHANGED", "health")
end
