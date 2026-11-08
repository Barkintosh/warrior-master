-- Rage and health bars: readable values, secret values, alerts.

local function rage()
	return NS.modules.rage
end

local function health()
	return NS.modules.health
end

test("rage bar shows readable values with threshold colors", function()
	WM.Boot({ state = { rage = 20 } })
	NS.DB:Set("rage.colorMode", "threshold")
	local bar = rage().bar
	eq(bar.sb.__values.value, 20, "bar value")
	eq(bar.text:GetText(), "20", "text")
	local low = NS.db.profile.rage.colorLow
	eq(bar.sb.__barColor[1], low.r, "low color")
	Mock.state.rage = 75
	Mock.FireEvent("UNIT_POWER_FREQUENT", "player", "RAGE")
	eq(bar.text:GetText(), "75", "updated text")
	eq(bar.sb.__barColor[1], NS.db.profile.rage.colorHigh.r, "high color")
	eq(bar.glowGate:GetAlpha(), 1, "glow on above threshold")
	Mock.state.rage = 10
	Mock.FireEvent("UNIT_POWER_FREQUENT", "player", "RAGE")
	eq(bar.glowGate:GetAlpha(), 0, "glow off below threshold")
end)

test("rage bar ignores other power types", function()
	WM.Boot({ state = { rage = 20 } })
	Mock.state.rage = 55
	Mock.FireEvent("UNIT_POWER_FREQUENT", "player", "MANA")
	eq(rage().bar.text:GetText(), "20", "unchanged for mana events")
end)

test("rage bar handles secret values without Lua math", function()
	WM.Boot({ state = { rage = 30 } })
	NS.DB:Set("rage.colorMode", "threshold")
	Mock.state.secretPower = true
	Mock.state.rage = 80
	Mock.FireEvent("UNIT_POWER_FREQUENT", "player", "RAGE")
	local bar = rage().bar
	check(rage().hidden, "module knows values are hidden")
	check(issecretvalue(bar.sb.__values.value), "secret value passed to the status bar")
	check(issecretvalue(bar.text:GetText()), "secret text displayed by the widget")
	check(issecretvalue(bar.sb.__barColor[1]), "color comes from the client's curve")
	check(issecretvalue(bar.glowGate:GetAlpha()), "glow driven by the client's curve")
	eq(Mock.Unwrap(bar.glowGate:GetAlpha()), 1, "curve says glow on at 80 rage")
	eq(rage().stats.curveFailures, 0, "no curve failures")
end)

test("secret values with percent text use the percent curve", function()
	WM.Boot({ state = { rage = 30 } })
	NS.DB:Set("rage.textFormat", "percent")
	Mock.state.secretPower = true
	Mock.FireEvent("UNIT_POWER_FREQUENT", "player", "RAGE")
	check(issecretvalue(rage().bar.text:GetText()), "percent text from curve")
end)

test("threshold curve matches the Lua color rules", function()
	WM.Boot()
	NS.DB:Set("rage.colorMode", "threshold")
	local cfg = NS.db.profile.rage
	local curve = NS.BuildResourceColorCurve(cfg)
	for _, frac in ipairs({ 0, 0.1, 0.29, 0.3, 0.45, 0.59, 0.6, 0.9, 1 }) do
		local r = NS.ResourceColor(cfg, frac)
		local c = curve:Evaluate(frac)
		near(c.r, r, 1e-6, "red at " .. frac)
	end
	NS.DB:Set("rage.colorMode", "gradient")
	cfg = NS.db.profile.rage
	curve = NS.BuildResourceColorCurve(cfg)
	for _, frac in ipairs({ 0, 0.15, 0.3, 0.45, 0.6, 0.8, 1 }) do
		local r, g = NS.ResourceColor(cfg, frac)
		local c = curve:Evaluate(frac)
		near(c.r, r, 1e-6, "gradient red at " .. frac)
		near(c.g, g, 1e-6, "gradient green at " .. frac)
	end
end)

test("low health sound plays once when crossing the threshold", function()
	WM.Boot({ state = { health = 3000, healthMax = 4000 } })
	eq(#Mock.sounds, 0, "no sound at login")
	Mock.state.health = 1000
	Mock.FireEvent("UNIT_HEALTH", "player")
	eq(#Mock.sounds, 1, "sound when dropping below 30%")
	eq(Mock.sounds[1].id, 8959, "raid warning sound")
	Mock.state.health = 900
	Mock.FireEvent("UNIT_HEALTH", "player")
	eq(#Mock.sounds, 1, "no repeat while still low")
	Mock.state.health = 3000
	Mock.FireEvent("UNIT_HEALTH", "player")
	Mock.state.health = 1000
	Mock.FireEvent("UNIT_HEALTH", "player")
	eq(#Mock.sounds, 1, "throttled within two seconds")
	Mock.Advance(2.5)
	Mock.state.health = 3000
	Mock.FireEvent("UNIT_HEALTH", "player")
	Mock.state.health = 1000
	Mock.FireEvent("UNIT_HEALTH", "player")
	eq(#Mock.sounds, 2, "plays again after the throttle")
	eq(health().bar.text:GetText(), "1000 (25%)", "value and percent text")
end)

test("no sound and no guessing while health is secret", function()
	WM.Boot({ state = { health = 3000, healthMax = 4000 } })
	Mock.state.secretHealth = true
	Mock.state.health = 500
	Mock.FireEvent("UNIT_HEALTH", "player")
	eq(#Mock.sounds, 0, "sound paused while hidden")
	check(health().hidden, "hidden flag set")
	eq(Mock.Unwrap(health().bar.glowGate:GetAlpha()), 1, "glow from curve below 30%")
end)

test("global sound switch silences alerts", function()
	WM.Boot({ state = { health = 3000, healthMax = 4000 } })
	NS.DB:Set("general.sounds", false)
	Mock.state.health = 1000
	Mock.FireEvent("UNIT_HEALTH", "player")
	eq(#Mock.sounds, 0, "muted")
end)

test("visibility follows combat and target rules", function()
	WM.Boot()
	NS.DB:Set("rage.visibility", "combat")
	check(not rage().bar:IsShown(), "hidden out of combat")
	Mock.EnterCombat()
	check(rage().bar:IsShown(), "shown in combat")
	Mock.LeaveCombat()
	NS.DB:Set("rage.visibility", "target")
	check(not rage().bar:IsShown(), "hidden without target")
	Mock.state.hasTarget = true
	Mock.FireEvent("PLAYER_TARGET_CHANGED")
	check(rage().bar:IsShown(), "shown with target")
	NS.DB:Set("rage.oocAlpha", 0.4)
	near(rage().bar:GetAlpha(), 0.4, 1e-9, "out of combat opacity")
end)

test("rage bar attaches to the health bar", function()
	WM.Boot()
	NS.DB:Set("rage.attach.enabled", true)
	local p = WarriorMasterRageBar.__points[1]
	eq(p[1], "TOP", "anchored by top")
	eq(p[2], WarriorMasterHealthBar, "relative to health bar")
	eq(WarriorMasterRageBar:GetWidth(), WarriorMasterHealthBar:GetWidth(), "matched width")
	NS.DB:Set("health.enabled", false)
	eq(WarriorMasterRageBar.__points[1][2], UIParent, "falls back to its own position")
end)

test("preview mode simulates values and stops in combat", function()
	WM.Boot()
	NS.DB:Set("rage.visibility", "combat")
	NS.TestMode:SetActive(true)
	check(rage().bar:IsShown(), "visible in preview")
	Mock.Advance(1)
	check(rage().bar.text:GetText() ~= "20", "simulated rage")
	Mock.EnterCombat()
	check(not NS.TestMode:IsActive(), "preview stopped by combat")
	Mock.LeaveCombat()
	eq(Mock.CountOnUpdate() <= 1, true, "no idle OnUpdate left running")
end)
