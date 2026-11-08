--[[
Warrior Master - Core/Security.lua
Feature safety classification and guards.

Every feature is classified as described in SECURITY.md:
  SAFE         documented, supported APIs only, no protected behaviour
  RESTRICTED   needs secure, player-initiated interaction (or out-of-combat only)
  UNSUPPORTED  cannot be done compliantly on this client: not implemented
  UNVERIFIED   implemented defensively but awaiting in-game confirmation;
               anything risky in this group is off by default

The list is shown on the "Safety & About" page and printed by /uw diag, so
the player can always see what the addon does and does not do.
]]
local _, ns = ...

local Security = {}
ns.Security = Security

Security.SAFE = "SAFE"
Security.RESTRICTED = "RESTRICTED"
Security.UNSUPPORTED = "UNSUPPORTED"
Security.UNVERIFIED = "UNVERIFIED"

-- Order matters: it is the display order.
Security.features = {
	{ key = "FEAT_RAGE", status = "SAFE" },
	{ key = "FEAT_HEALTH", status = "SAFE" },
	{ key = "FEAT_CURVES", status = "UNVERIFIED" },
	{ key = "FEAT_SOUNDS", status = "RESTRICTED" },
	{ key = "FEAT_SWING", status = "UNVERIFIED" },
	{ key = "FEAT_SWING_RANGE", status = "UNVERIFIED" },
	{ key = "FEAT_ENEMY_SWING", status = "UNSUPPORTED" },
	{ key = "FEAT_CAST", status = "UNVERIFIED" },
	{ key = "FEAT_STANCE", status = "RESTRICTED" },
	{ key = "FEAT_WEAPONS", status = "RESTRICTED" },
	{ key = "FEAT_PICKER", status = "SAFE" },
	{ key = "FEAT_STANCE_MACROS", status = "RESTRICTED" },
	{ key = "FEAT_MACRO_BAR", status = "RESTRICTED" },
	{ key = "FEAT_MINIMAP", status = "SAFE" },
	{ key = "FEAT_LAYOUT", status = "SAFE" },
	{ key = "FEAT_FLAIR", status = "SAFE" },
	{ key = "FEAT_AUTO_SWAP", status = "UNSUPPORTED" },
	{ key = "FEAT_MACRO_TEXT", status = "SAFE" },
	{ key = "FEAT_MACRO_CREATE", status = "RESTRICTED" },
	{ key = "FEAT_PROFILES", status = "SAFE" },
}

Security.statusColor = {
	SAFE = { 0.35, 0.85, 0.45 },
	RESTRICTED = { 1.0, 0.78, 0.30 },
	UNSUPPORTED = { 1.0, 0.38, 0.38 },
	UNVERIFIED = { 0.55, 0.75, 1.0 },
}

Security.statusLabelKey = {
	SAFE = "STATUS_SAFE",
	RESTRICTED = "STATUS_RESTRICTED",
	UNSUPPORTED = "STATUS_UNSUPPORTED",
	UNVERIFIED = "STATUS_UNVERIFIED",
}

--- Slash commands that generated macros and click actions must never contain.
-- They would let a macro run arbitrary code, which is outside the scope of
-- this addon (and a common vector for unsafe automation).
-- /castsequence and /click are excluded too: they chain several actions
-- behind one key, which goes against the "one action per press" policy.
Security.FORBIDDEN_COMMANDS = {
	"/run", "/script", "/console", "/dump", "/tinspect", "/eventtrace", "/fstack",
	"/framestack", "/api", "/reload", "/rl", "/logout", "/camp", "/quit", "/exit",
	"/castsequence", "/click",
}

--- Returns the first forbidden command found in the text, if any.
function Security.FindForbiddenCommand(text)
	for line in (tostring(text or "") .. "\n"):gmatch("(.-)\n") do
		local command = line:match("^%s*(/[%w_]+)")
		if command then
			command = command:lower()
			for _, forbidden in ipairs(Security.FORBIDDEN_COMMANDS) do
				if command == forbidden then
					return forbidden
				end
			end
		end
	end
	return nil
end

--- Cleans a user- or game-provided name before it is placed in a macro line:
-- removes line breaks, control characters, the escape character "|", macro
-- syntax characters ([ ] ;) and leading slashes, so a name can never inject
-- another command or condition.
function Security.SanitizeMacroToken(text, maxLen)
	local s = tostring(text or "")
	s = s:gsub("[%c|]", " ")
	s = s:gsub("[%[%];]", "")
	s = s:gsub("^[%s/]+", "")
	s = s:gsub("%s+", " ")
	s = ns.Util.Trim(s)
	return ns.Util.Utf8Sub(s, maxLen or 64)
end

--- Asserts that a secure configuration change happens outside combat.
-- Callers always go through ns.Combat:Run, so this is a second line of
-- defence: if it ever fires, it is a bug that must be fixed, not hidden.
function Security.AssertOutOfCombat(what)
	if ns.Compat.InCombatLockdown() then
		error("secure change attempted in combat: " .. tostring(what), 2)
	end
end
