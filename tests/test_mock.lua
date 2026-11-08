-- Self-tests: prove the mock is strict enough for the other tests to mean something.

test("mock knows the client's documented widget API", function()
	local count = 0
	for _ in pairs(FOREVER_API.methods) do
		count = count + 1
	end
	check(count > 1000, "documented methods loaded")
	check(FOREVER_API.methods.SetStatusBarColor, "StatusBar:SetStatusBarColor documented")
	check(FOREVER_API.events.PLAYER_SWING, "PLAYER_SWING documented")
	check(FOREVER_API.functions["C_SwingTimer.EnableRangeCheck"], "C_SwingTimer documented")
end)

test("undocumented widget methods raise errors", function()
	local f = CreateFrame("Frame")
	local ok = pcall(function()
		f:TotallyMadeUpMethod()
	end)
	check(not ok, "unknown method rejected")
end)

test("unknown events raise errors", function()
	local f = CreateFrame("Frame")
	check(not pcall(f.RegisterEvent, f, "COMBAT_LOG_EVENT_UNFILTERED_TYPO"), "unknown event rejected")
end)

test("protected operations on secure frames are blocked in combat", function()
	local b = CreateFrame("Button", "MockSecure", UIParent, "SecureActionButtonTemplate")
	Mock.state.lockdown = true
	check(not pcall(function()
		b:SetAttribute("type", "spell")
	end), "SetAttribute blocked")
	check(not pcall(function()
		b:Hide()
	end), "Hide blocked")
	Mock.state.lockdown = false
	Mock.blocked = {}
end)
TESTS[#TESTS].allowErrors = true

test("addon code cannot do math on secret values", function()
	local s = Mock.Secret(5)
	check(not pcall(function()
		return s + 1
	end), "arithmetic")
	check(not pcall(function()
		return s < 3
	end), "comparison")
	check(not pcall(function()
		return "x" .. s
	end), "concatenation")
	check(not pcall(tostring, s), "tostring")
	check(issecretvalue(s), "detected")
end)

test("no OnUpdate script runs while the addon is idle", function()
	WM.Boot()
	eq(Mock.CountOnUpdate(), 0, "idle")
	Mock.FireEvent("PLAYER_SWING", 2.0, 0)
	eq(Mock.CountOnUpdate(), 1, "one updater during a swing")
	Mock.Advance(2.2)
	eq(Mock.CountOnUpdate(), 0, "idle again")
end)

test("color swatch opens the game's color picker", function()
	WM.Boot()
	NS.Config:Show()
	NS.Config:ShowPage("rage")
	local page = NS.Config:GetPage("rage").instance
	local swatch
	for _, control in ipairs(page.controls) do
		for _, child in ipairs(control.frame.__children or {}) do
			if child.__kind == "FontString" and child.__text == NS.L.COLOR_SINGLE then
				swatch = control.frame
			end
		end
	end
	check(swatch, "swatch found")
	swatch.__scripts.OnClick(swatch)
	local info = ColorPickerFrame.__info
	check(info and info.swatchFunc, "picker opened")
	info.swatchFunc()
	near(NS.db.profile.rage.colorStatic.r, 0.5, 1e-9, "color applied")
	info.cancelFunc()
	near(NS.db.profile.rage.colorStatic.r, 1, 1e-9, "cancel restores")
end)
