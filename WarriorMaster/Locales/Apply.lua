--[[
Warrior Master - Locales/Apply.lua
Fills ns.L from the reference locale (enUS) and the active locale.
Called once at load with the game locale, and again at login if the
player chose a different addon language in the settings.
]]
local _, ns = ...

ns.SUPPORTED_LOCALES = { "enUS", "frFR" }

function ns:ApplyLocale(code)
	local L = self.L
	for key in pairs(L) do
		L[key] = nil
	end
	local base = self.Locales.enUS or {}
	for key, value in pairs(base) do
		L[key] = value
	end
	if code == "frCA" then
		code = "frFR"
	end
	local active = code and self.Locales[code]
	if active and active ~= base then
		for key, value in pairs(active) do
			if type(value) == "string" then
				L[key] = value
			end
		end
	end
	self.activeLocale = active and code or "enUS"
end

ns:ApplyLocale(GetLocale and GetLocale() or "enUS")
