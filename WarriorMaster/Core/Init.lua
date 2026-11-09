--[[
Warrior Master - Core/Init.lua
Creates the addon namespace, the localization table and the module registry.

Design notes
- Everything lives in the private namespace table `ns` passed by the client
  to every file listed in the TOC. The addon creates no global variables other
  than its SavedVariables, slash command and key binding labels.
- Modules are plain tables with lifecycle callbacks:
    OnInitialize()  once, after saved variables are ready
    OnEnable()      when the module is switched on in the active profile
    OnDisable()     when it is switched off (must release events / actions)
    ApplySettings() when profile values change
]]
local ADDON_NAME, ns = ...

ns.ADDON_NAME = ADDON_NAME
ns.TITLE = "Warrior Master"
ns.VERSION = "1.3.0"

ns.modules = {}
ns.moduleOrder = {}
ns.Locales = {}

-- Localization: missing keys fall back to the key itself so a missing
-- translation never produces a Lua error or an empty label.
ns.L = setmetatable({}, {
	__index = function(_, key)
		return key
	end,
})

-- Runtime state shared by modules (combat, target, preview flags).
ns.state = {
	inCombat = false,
	hasTarget = false,
	ready = false,
	isWarrior = false,
}

local Module = {}
Module.__index = Module

function Module:GetConfig()
	local profile = ns.db and ns.db.profile
	return profile and profile[self.key]
end

function Module:IsEnabledInProfile()
	local cfg = self:GetConfig()
	return cfg ~= nil and cfg.enabled == true
end

ns.ModulePrototype = Module

--- Registers a new feature module.
-- @param key   string, also the profile section name (e.g. "rage")
-- @param title localization key of the display name
function ns:NewModule(key, titleKey)
	assert(type(key) == "string" and key ~= "", "module key required")
	assert(not self.modules[key], "duplicate module " .. key)
	local module = setmetatable({ key = key, titleKey = titleKey or key, enabled = false }, Module)
	if self.EventMixin then
		self.EventMixin.Embed(module)
	end
	self.modules[key] = module
	self.moduleOrder[#self.moduleOrder + 1] = key
	return module
end

function ns:GetModule(key)
	return self.modules[key]
end
