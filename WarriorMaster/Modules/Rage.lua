--[[
Warrior Master - Modules/Rage.lua
Rage bar. Reads rage with UnitPower / UnitPowerMax / UnitPowerPercent
(documented for client 1.60.1; may return secret values in combat).
Can be attached to the health bar.
]]
local _, ns = ...

local Compat = ns.Compat
local RAGE = Compat.POWER_RAGE

local Rage

local function healthAnchor()
	local health = ns:GetModule("health")
	if health and health.enabled and health.bar then
		return health
	end
	return nil
end

local function isAttached(cfg)
	-- The automatic layout places the rage bar itself when it is on.
	return cfg.attach.enabled and not ns.Layout:Manages("rage") and healthAnchor() ~= nil
end

Rage = ns.CreateResourceModule({
	key = "rage",
	titleKey = "MODULE_RAGE",
	frameName = "WarriorMasterRageBar",
	unitEvents = { "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER" },
	alertDirection = "above",

	read = function()
		return UnitPower("player", RAGE), UnitPowerMax("player", RAGE)
	end,

	percent = function(curve)
		return UnitPowerPercent("player", RAGE, false, curve)
	end,

	test = function()
		return ns.TestMode:GetRage()
	end,

	-- Power events carry the power token; ignore other resources.
	filter = function(event, unit, powerToken)
		if event == "UNIT_POWER_FREQUENT" or event == "UNIT_MAXPOWER" then
			if powerToken ~= nil and not Compat.IsSecret(powerToken) and powerToken ~= "RAGE" then
				return false
			end
		end
		return true
	end,

	layout = function(_, cfg)
		if isAttached(cfg) and cfg.attach.matchWidth then
			local health = healthAnchor()
			local hcfg = health:GetConfig()
			local scale = cfg.scale > 0 and cfg.scale or 1
			return { width = hcfg.width * hcfg.scale / scale }
		end
		return nil
	end,

	position = function(module, cfg)
		if not isAttached(cfg) then
			return false
		end
		local health = healthAnchor()
		local bar = module.bar
		bar:ClearAllPoints()
		if cfg.attach.position == "ABOVE" then
			bar:SetPoint("BOTTOM", health.bar, "TOP", 0, cfg.attach.gap)
		else
			bar:SetPoint("TOP", health.bar, "BOTTOM", 0, -cfg.attach.gap)
		end
		return true
	end,

	canMove = function(module)
		return not isAttached(module:GetConfig())
	end,
})

function Rage:IsAttached()
	local cfg = self:GetConfig()
	return cfg ~= nil and isAttached(cfg)
end

-- Follow the health bar when it is resized, moved, enabled or disabled.
ns:RegisterMessage(Rage, "LAYOUT_CHANGED", function(self)
	if self.enabled then
		self:ApplySettings()
		ns.Movers:Refresh()
	end
end)
