--[[
Warrior Master - Core/Slash.lua
/warriormaster (and the short alias /uw) commands, plus diagnostics.
/wm is not used: on WoW Forever it is the game's own world-marker command,
and the game always runs its built-in commands before any addon's.
]]
local ADDON_NAME, ns = ...

local Compat = ns.Compat
local format = string.format

SLASH_WARRIORMASTER1 = "/warriormaster"
SLASH_WARRIORMASTER2 = "/uw"

local function yesNo(value)
	if value == nil then
		return "?"
	end
	return value and "yes" or "no"
end

function ns:PrintDiagnostics()
	local L = self.L
	local db = self.db
	self:Print(format("Warrior Master %s | client %s build %s | interface %d | Forever: %s",
		self.VERSION, Compat.clientVersion, Compat.clientBuild, Compat.interface, yesNo(Compat.isForever)))
	self:Print(format("Class: %s | profile: %s | in combat: %s | combat lockdown: %s | queued secure changes: %d",
		tostring(Compat.GetPlayerClass()), db and db.profileName or "?", yesNo(self.state.inCombat),
		yesNo(Compat.InCombatLockdown()), ns.Combat:PendingCount()))
	local s = Compat.DescribeSecrecy()
	self:Print(format("Hidden values: restrictions %s | rage %s | rage max %s | health max %s | attack speed %s",
		s.restrictions, s.power, s.powerMax, s.healthMax, s.stats))
	self:Print(format("APIs: curves %s | native swing %s | range check %s | bar interpolation %s | CreateMacro %s | equipment sets %s",
		yesNo(Compat.hasCurves), yesNo(Compat.hasNativeSwing), yesNo(Compat.hasRangeCheck),
		yesNo(Compat.hasInterpolation), yesNo(type(CreateMacro) == "function"), yesNo(Compat.CanUseEquipmentSets())))
	for _, key in ipairs({ "rage", "health" }) do
		local m = self:GetModule(key)
		if m then
			self:Print(format("%s: enabled %s | value hidden now %s | hidden updates %d | curve failures %d | sounds %d",
				key, yesNo(m.enabled), yesNo(m.hidden), m.stats.secretUpdates, m.stats.curveFailures, m.stats.sounds))
		end
	end
	local swing = self:GetModule("swing")
	if swing then
		local st = swing.stats
		local cvar = Compat.GetCVarBool("showSwingTimer")
		self:Print(format("Swing: enabled %s | PLAYER_SWING events %d (hidden %d, invalid %d) | rescaled %d | last duration %s | showSwingTimer %s",
			yesNo(swing.enabled), st.events, st.secret, st.invalid, st.rescaled,
			st.lastDuration and format("%.2f", st.lastDuration) or "-", yesNo(cvar)))
	end
	local stance = self:GetModule("stance")
	if stance then
		self:Print(format("Stances: enabled %s | forms %d | active %s | pending %s",
			yesNo(stance.enabled), Compat.GetNumShapeshiftForms(), tostring(stance.activeKey), yesNo(stance.pending)))
	end
	self:Print(format("Errors: %d | blocked actions: %d", #self.errors, self.blockedActions or 0))
	if not self.state.isWarrior then
		self:Print(L.WARRIOR_ONLY)
	end
end

function ns:PrintErrors()
	if #self.errors == 0 then
		self:Print(self.L.ERRORS_NONE)
		return
	end
	self:Print(self.L.ERRORS_HEADER)
	for i, entry in ipairs(self.errors) do
		self:Print(format("%d. (x%d) %s", i, entry.count, entry.message))
	end
end

--- Resets the position of every frame (useful if one ends up off screen).
function ns:ResetPositions()
	local S = self.Schema
	for _, key in ipairs({ "health", "rage", "swing", "stance" }) do
		self.DB:Set(key .. ".point", S.profile[key].point.default)
	end
end

local function findPreset(name)
	name = name:lower():gsub("%s+", "")
	for _, key in ipairs(ns.Presets.ORDER) do
		local label = ns.L[ns.Presets.LABEL_KEYS[key]]:lower():gsub("%s+", "")
		if key:lower() == name or label == name then
			return key
		end
	end
	return nil
end

local MODULE_ALIASES = {
	health = "health", hp = "health", vie = "health",
	rage = "rage",
	swing = "swing", attaque = "swing",
	stance = "stance", stances = "stance", posture = "stance", postures = "stance",
}

--- Applies a style to some modules and parts, then refreshes everything.
-- sections: list of module keys (nil = all); parts: set of parts (nil = all).
function ns:ApplyStyle(key, sections, parts)
	if ns.Presets.Apply(self.db.profile, key, { sections = sections, parts = parts }) then
		self:SendMessage("PROFILE_CHANGED", self.db.profileName)
		return true
	end
	return false
end

--- Applies a complete style to every module.
function ns:ApplyPreset(key)
	return self:ApplyStyle(key)
end

--- "/uw preset <style> [module]"
local function presetCommand(rest)
	local words = {}
	for word in rest:gmatch("%S+") do
		words[#words + 1] = word
	end
	local section
	if #words > 1 then
		section = MODULE_ALIASES[words[#words]:lower()]
		if section then
			table.remove(words)
		end
	end
	return findPreset(table.concat(words, " ")), section
end

function ns:HandleSlash(input)
	local L = self.L
	local command, rest = tostring(input or ""):match("^%s*(%S*)%s*(.-)%s*$")
	command = (command or ""):lower()

	if command == "help" then
		self:Print(L.SLASH_HELP)
		return
	elseif command == "diag" then
		self:PrintDiagnostics()
		return
	elseif command == "errors" then
		self:PrintErrors()
		return
	end

	if not self.state.ready then
		return
	end
	if not self.state.isWarrior then
		self:Print(L.WARRIOR_ONLY)
		return
	end

	if command == "" or command == "config" or command == "options" then
		self.Config:Toggle()
	elseif command == "lock" then
		self.DB:Set("general.locked", true)
		self:Print(L.LOCKED_MSG)
	elseif command == "unlock" then
		self.DB:Set("general.locked", false)
		self:Print(L.UNLOCKED_MSG)
	elseif command == "test" or command == "preview" then
		self.TestMode:Toggle()
	elseif command == "reset" then
		self:ResetPositions()
	elseif command == "preset" or command == "style" then
		local key, section = presetCommand(rest)
		if key and self:ApplyStyle(key, section and { section } or nil) then
			local target = section and L[ns.Styles.SECTION_LABELS[section]] or L.TARGET_ALL
			self:Print(L.STYLE_APPLIED:format(L[ns.Presets.LABEL_KEYS[key]], target))
		else
			self:Print(L.UNKNOWN_COMMAND)
		end
	elseif command == "profile" then
		local ok, err = self.DB:SetProfile(rest)
		self:Print(ok and L.PROFILE_SWITCHED:format(rest) or L[err])
	else
		self:Print(L.UNKNOWN_COMMAND)
	end
end

SlashCmdList.WARRIORMASTER = function(input)
	ns:HandleSlash(input)
end
