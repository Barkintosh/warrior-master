-- Macro templates, validation and saving.

local MB, T

local function boot(opts)
	WM.Boot(opts)
	MB, T = NS.MacroBuilder, NS.MacroTemplates
end

test("every template builds a valid macro once its items are chosen", function()
	boot()
	eq(#T.list, 21, "template count")
	for _, template in ipairs(T.list) do
		for _, option in ipairs(template.options) do
			if option.kind == "item" then
				MB.SetOption(template.id, option.key, option.slot == "shield" and 2001 or (option.slot == "twohand" and 1002 or 1001))
			end
		end
		local text, missing = MB.Build(template.id)
		eq(#missing, 0, template.id .. " has no missing items")
		local result = MB.Validate(text)
		check(result.ok, template.id .. " valid: " .. table.concat(result.errors, "; "))
		eq(#result.warnings, 0, template.id .. " has no warnings")
		check(result.length <= 255, template.id .. " within the length limit")
		check(not text:find("?", 1, true), template.id .. " has no placeholder")
		eq(NS.Security.FindForbiddenCommand(text), nil, template.id .. " has no forbidden command")
		check(NS.L[template.nameKey] ~= template.nameKey, template.id .. " has a name")
		check(NS.L[template.descKey] ~= template.descKey, template.id .. " has a description")
	end
end)

test("templates report missing items instead of guessing", function()
	boot()
	local _, missing = MB.Build("weapon_toggle")
	eq(#missing, 3, "three items needed")
end)

test("stance dance templates use client spell names", function()
	boot()
	eq(MB.Build("overpower"), "#showtooltip Overpower\n/cast [stance:1] Overpower; Battle Stance", "overpower")
	eq(MB.Build("interrupt"), "#showtooltip\n/cast [stance:3] Pummel; [equipped:Shields] Shield Bash; Berserker Stance", "interrupt")
	MB.SetOption("execute", "stance", "battle")
	eq(MB.Build("execute"), "#showtooltip Execute\n/cast [stance:1/3] Execute; Battle Stance", "execute option")
	MB.SetOption("stance_toggle", "first", "defensive")
	MB.SetOption("stance_toggle", "second", "battle")
	eq(MB.Build("stance_toggle"), "#showtooltip\n/cast [stance:2] Battle Stance; Defensive Stance", "toggle")
end)

test("French locale fallback names are used when the client has none", function()
	boot({ state = { locale = "frFR", spells = {} } })
	eq(MB.Build("overpower"), "#showtooltip Fulgurance\n/cast [stance:1] Fulgurance; Posture de combat", "french names")
end)

test("validation rejects scripts, chains and oversized macros", function()
	boot()
	check(not MB.Validate("/run print(1)").ok, "/run rejected")
	check(not MB.Validate("#showtooltip\n/script x()").ok, "/script rejected")
	check(not MB.Validate("/castsequence a, b").ok, "/castsequence rejected")
	check(not MB.Validate("/click SomeButton").ok, "/click rejected")
	check(not MB.Validate(string.rep("a", 256)).ok, "too long rejected")
	check(not MB.Validate("   ").ok, "empty rejected")
	check(MB.Validate("/cast Charge").ok, "plain cast accepted")
	eq(#MB.Validate("hello").warnings, 1, "line warning")
	eq(MB.Validate(string.rep("é", 200)).length, 200, "length counted in characters")
end)

test("saving creates then updates a macro, out of combat only", function()
	boot()
	local ok, message = MB.Save("WM Charge", "/cast Charge", true, 1)
	check(ok, message)
	eq(Mock.macros[121].body, "/cast Charge", "character macro created")
	ok = MB.Save("WM Charge", "/cast Intercept", true, 1)
	check(ok, "updated")
	eq(Mock.macros[121].body, "/cast Intercept", "same slot updated")
	Mock.EnterCombat()
	ok, message = MB.Save("WM Other", "/cast Charge", true, 1)
	check(not ok, "refused in combat")
	contains(message, "combat", "combat message")
	eq(#Mock.blocked, 0, "CreateMacro never called in combat")
	Mock.LeaveCombat()
end)

test("saving validates name, content and free slots", function()
	boot()
	check(not MB.Save("", "/cast Charge", false), "empty name refused")
	check(not MB.Save("Name", "/run x()", false), "script refused")
	for i = 1, 120 do
		Mock.macros[i] = { name = "m" .. i, body = "" }
	end
	local ok, message = MB.Save("New", "/cast Charge", false)
	check(not ok, "account macros full")
	contains(message, "120/120", "limit shown")
end)

test("option values are stored per character and sanitized", function()
	boot()
	MB.SetOption("heroic_cleave", "modifier", "ctrl")
	eq(MB.GetOptions("heroic_cleave").modifier, "ctrl", "stored")
	MB.SetOption("heroic_cleave", "modifier", "bogus")
	eq(MB.GetOptions("heroic_cleave").modifier, "shift", "invalid value falls back to the default")
end)
