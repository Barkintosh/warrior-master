--[[
Warrior Master - Core/Boot.lua
Start-up sequence and module switching.

ADDON_LOADED   saved variables of this addon are available
PLAYER_LOGIN   character data is available: build the database, apply the
               chosen language, then initialise and enable the modules that
               are switched on in the active profile.
The addon stays idle on characters that are not Warriors.
]]
local ADDON_NAME, ns = ...

local Compat = ns.Compat

local boot = ns.EventMixin.Embed({})

-- Key binding labels shown in the game's Key Bindings window (Bindings.xml).
BINDING_HEADER_WARRIORMASTER = "Warrior Master"
for i = 1, 3 do
	_G["BINDING_NAME_CLICK WarriorMasterStanceButton" .. i .. ":LeftButton"] = ns.L.BINDING_STANCE:format(i)
end

--- Switches a module on or off. Disabled modules release all their events
-- and secure actions in OnDisable, so they can no longer act.
function ns:SetModuleEnabled(key, enabled)
	local module = self.modules[key]
	if not module then
		return
	end
	enabled = (enabled and self.state.isWarrior) and true or false
	if enabled == module.enabled then
		return
	end
	module.enabled = enabled
	if enabled then
		self:SafeCall(module.OnEnable, module)
	else
		self:SafeCall(module.OnDisable, module)
	end
	self.Movers:Refresh()
end

--- Re-applies the active profile to every module (after a profile switch).
function ns:RefreshModules()
	for _, key in ipairs(self.moduleOrder) do
		local module = self.modules[key]
		local wanted = module:IsEnabledInProfile()
		if wanted ~= module.enabled then
			self:SetModuleEnabled(key, wanted)
		elseif wanted and module.ApplySettings then
			self:SafeCall(module.ApplySettings, module)
		end
	end
	self.Movers:SetShown(not self.db.profile.general.locked)
end

ns:RegisterMessage(boot, "SETTINGS_CHANGED", function(_, _, path)
	local section = path:match("^(%w+)%.enabled$")
	if section and ns.modules[section] then
		ns:SetModuleEnabled(section, ns.db.profile[section].enabled)
	elseif path == "general.locked" then
		ns.Movers:SetShown(not ns.db.profile.general.locked)
	elseif path == "general.offsetX" or path == "general.offsetY" or path == "general.clampAll" then
		-- Global position or clamping changed: place every module again.
		ns.Movers:PlaceGroupHandle()
		ns:RefreshModules()
	end
end)

ns:RegisterMessage(boot, "PROFILE_CHANGED", function()
	if ns.state.ready and ns.state.isWarrior then
		ns:RefreshModules()
	end
end)

-- Re-apply settings so labels drawn by the modules switch language too.
ns:RegisterMessage(boot, "LANGUAGE_CHANGED", function()
	if ns.state.ready and ns.state.isWarrior then
		ns:RefreshModules()
	end
end)

function boot:ADDON_LOADED(_, name)
	if name == ADDON_NAME then
		self.loaded = true
		self:UnregisterEvent("ADDON_LOADED")
	end
end

function boot:PLAYER_LOGIN()
	self:UnregisterEvent("PLAYER_LOGIN")
	ns.DB:Init()
	local language = ns.db.global.language
	if language ~= "auto" then
		ns:ApplyLocale(language)
	end
	ns.VERSION = Compat.GetAddOnVersion(ADDON_NAME) or ns.VERSION
	ns.state.isWarrior = Compat.GetPlayerClass() == "WARRIOR"

	ns.Combat:Start()
	ns.Movers:Start()
	ns:StartCoreEvents()
	if ns.Config and ns.Config.RegisterSettingsCategory then
		ns:SafeCall(ns.Config.RegisterSettingsCategory, ns.Config)
	end

	if ns.state.isWarrior then
		for _, key in ipairs(ns.moduleOrder) do
			local module = ns.modules[key]
			if module.OnInitialize then
				ns:SafeCall(module.OnInitialize, module)
			end
		end
		for _, key in ipairs(ns.moduleOrder) do
			if ns.modules[key]:IsEnabledInProfile() then
				ns:SetModuleEnabled(key, true)
			end
		end
		ns.Movers:SetShown(not ns.db.profile.general.locked)
		ns:SafeCall(ns.MinimapButton.Init, ns.MinimapButton)
	end
	ns.state.ready = true
end

boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_LOGIN")
