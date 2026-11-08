-- Swing timer driven by PLAYER_SWING.

local function swing()
	return NS.modules.swing
end

local function updating()
	return swing().updater.__scripts.OnUpdate ~= nil
end

test("main-hand swing progresses and stops updating when done", function()
	WM.Boot()
	Mock.FireEvent("PLAYER_SWING", 2.6, 0)
	local timer = swing().timers.mh
	check(timer.active, "swing started")
	check(updating(), "OnUpdate running during the swing")
	Mock.Advance(1.3)
	local bar = swing().bars.mh
	near(bar.sb.__values.value, 0.5, 0.02, "half way")
	contains(bar.text:GetText(), "1.", "countdown text")
	Mock.Advance(1.4)
	check(not timer.active, "swing finished")
	check(not updating(), "OnUpdate stopped when idle")
	eq(bar.sb.__values.value, 0, "bar emptied")
end)

test("off-hand bar only with an off-hand weapon", function()
	WM.Boot({ state = { inventory = { [16] = 1001, [17] = 2001 } } })
	check(not swing().bars.oh:IsShown(), "hidden with a shield")
	Mock.state.inventory = { [16] = 1001, [17] = 2002 }
	Mock.FireEvent("WEAPON_SLOT_CHANGED")
	check(swing().bars.oh:IsShown(), "shown with a dagger in the off hand")
	Mock.FireEvent("PLAYER_SWING", 1.9, 1)
	check(swing().timers.oh.active, "off-hand swing tracked")
end)

test("secret or invalid swing data is ignored, never guessed", function()
	WM.Boot()
	Mock.FireEvent("PLAYER_SWING", Mock.Secret(2.6), 0)
	eq(swing().stats.secret, 1, "secret counted")
	check(not swing().timers.mh.active, "no timer from a secret duration")
	Mock.FireEvent("PLAYER_SWING", -1, 0)
	Mock.FireEvent("PLAYER_SWING", 99, 0)
	Mock.FireEvent("PLAYER_SWING", 2.0, 7)
	eq(swing().stats.invalid, 3, "invalid payloads counted")
	check(not swing().timers.mh.active, "still idle")
end)

test("haste change rescales the running swing", function()
	WM.Boot({ state = { attackSpeed = { 2.6, nil, nil } } })
	Mock.FireEvent("PLAYER_SWING", 2.6, 0)
	Mock.Advance(1.0)
	Mock.state.attackSpeed = { 2.0, nil, nil }
	Mock.FireEvent("UNIT_ATTACK_SPEED", "player")
	local timer = swing().timers.mh
	near(timer.finish - GetTime(), 1.6 * 2.0 / 2.6, 0.03, "remaining time rescaled")
	eq(swing().stats.rescaled, 1, "one rescale")
end)

test("hidden attack speed leaves the swing untouched", function()
	WM.Boot({ state = { attackSpeed = { 2.6, nil, nil } } })
	Mock.state.secretStats = true
	Mock.FireEvent("PLAYER_SWING", 2.6, 0)
	Mock.Advance(1.0)
	local before = swing().timers.mh.finish
	Mock.state.attackSpeed = { 2.0, nil, nil }
	Mock.FireEvent("UNIT_ATTACK_SPEED", "player")
	eq(swing().timers.mh.finish, before, "unchanged")
end)

test("weapon swap restarts the swing with the new weapon speed", function()
	WM.Boot({ state = { attackSpeed = { 2.6, nil, nil } } })
	Mock.FireEvent("PLAYER_SWING", 2.6, 0)
	Mock.Advance(0.5)
	Mock.state.inventory = { [16] = 1002, [17] = 2001 }
	Mock.state.attackSpeed = { 3.6, nil, nil }
	Mock.FireEvent("WEAPON_SLOT_CHANGED")
	local timer = swing().timers.mh
	near(timer.duration, 3.6, 1e-6, "restarted with the new speed")
	near(timer.finish - GetTime(), 3.6, 1e-6, "full swing ahead")
end)

test("swing sound plays on main-hand swings when enabled", function()
	WM.Boot()
	NS.DB:Set("swing.sound", true)
	Mock.FireEvent("PLAYER_SWING", 2.6, 0)
	Mock.FireEvent("PLAYER_SWING", 1.9, 1)
	eq(#Mock.sounds, 1, "only the main hand plays")
end)

test("range check is off by default and opt-in", function()
	WM.Boot()
	eq(#C_SwingTimer.rangeCalls, 0, "no range checks by default")
	NS.DB:Set("swing.rangeCheck", true)
	check(#C_SwingTimer.rangeCalls >= 1, "enabled on request")
	Mock.FireEvent("PLAYER_SWING_RANGE_UPDATE", 0, false, true)
	near(swing().bars.mh:GetAlpha(), 0.4, 1e-9, "dimmed when out of reach between swings")
	Mock.FireEvent("PLAYER_SWING", 2.6, 0)
	near(swing().bars.mh:GetAlpha(), 1, 1e-9, "not dimmed during a swing")
end)

test("disabled swing timer ignores swings", function()
	WM.Boot()
	NS.DB:Set("swing.enabled", false)
	Mock.FireEvent("PLAYER_SWING", 2.6, 0)
	check(not swing().timers.mh.active, "ignored")
	check(not WarriorMasterSwingFrame:IsShown(), "hidden")
end)

test("client swing option button sets the CVar out of combat only", function()
	WM.Boot()
	Mock.cvars.showSwingTimer = "0"
	Mock.EnterCombat()
	check(not swing():EnableClientSwingTimer(), "refused in combat")
	eq(Mock.cvars.showSwingTimer, "0", "unchanged in combat")
	Mock.LeaveCombat()
	check(swing():EnableClientSwingTimer(), "enabled out of combat")
	eq(Mock.cvars.showSwingTimer, "1", "CVar on")
end)

test("weapon filter shows the timer only with the chosen kind of weapon", function()
	WM.Boot({ state = { inventory = { [16] = 1001, [17] = 2001 } } })
	NS.DB:Set("swing.visibility", "always")
	local frame = WarriorMasterSwingFrame
	check(frame:IsShown(), "any weapon: shown with a one-hander")
	NS.DB:Set("swing.weaponFilter", "twoHand")
	check(not frame:IsShown(), "two-handed only: hidden with a one-hander")
	Mock.state.inventory = { [16] = 1002 }
	Mock.FireEvent("PLAYER_EQUIPMENT_CHANGED", 16, true)
	check(frame:IsShown(), "two-handed only: shown with a two-hander")
	NS.DB:Set("swing.weaponFilter", "oneHand")
	check(not frame:IsShown(), "one-handed only: hidden with a two-hander")
	Mock.state.inventory = { [16] = 1001, [17] = 2002 }
	Mock.FireEvent("WEAPON_SLOT_CHANGED")
	check(frame:IsShown(), "one-handed only: shown when dual wielding")
	Mock.state.inventory = {}
	Mock.FireEvent("PLAYER_EQUIPMENT_CHANGED", 16, false)
	check(not frame:IsShown(), "no weapon matches neither filter")
	NS.Movers:SetShown(true)
	check(frame:IsShown(), "always shown while moving frames")
	NS.Movers:SetShown(false)
	Mock.state.inventory = { [16] = 9999 } -- item information not readable
	Mock.FireEvent("PLAYER_EQUIPMENT_CHANGED", 16, true)
	check(frame:IsShown(), "unknown weapon kind: never hidden on a guess")
end)
