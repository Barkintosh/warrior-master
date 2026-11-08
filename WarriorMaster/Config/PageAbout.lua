--[[
Warrior Master - Config/PageAbout.lua
Version, principles and the feature safety classification (Core/Security.lua).
]]
local _, ns = ...

ns.Config:RegisterPage({
	key = "about",
	titleKey = "PAGE_ABOUT",
	order = 80,
	build = function(page)
		local L = ns.L
		local Compat = ns.Compat
		local Security = ns.Security

		page:Header("Warrior Master")
		page:Text({
			height = 16,
			color = "text",
			get = function()
				return L.ABOUT_VERSION:format(ns.VERSION, Compat.clientVersion, tostring(Compat.interface)), "text"
			end,
		})
		page:Note(L.ABOUT_PRINCIPLES, "text")

		page:Header(L.ABOUT_COMPLIANCE)
		for _, feature in ipairs(Security.features) do
			local c = Security.statusColor[feature.status]
			local hex = string.format("%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255)
			page:Note(string.format("|cff%s%s|r  %s", hex, L[Security.statusLabelKey[feature.status]], L[feature.key]), "text")
			page:Note("      " .. L[feature.key .. "_NOTE"])
		end
		page:Space(6)
		page:Note(L.ABOUT_DOCS)
	end,
})
