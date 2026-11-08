-- Positions: global offset, clamping, screen anchors, group handle; commands; fonts; layout.

local function lastPoint(frame)
	return frame.__points[#frame.__points]
end

test("the global offset moves every module together", function()
	WM.Boot()
	local rx = lastPoint(WarriorMasterRageBar)[4]
	local sx = lastPoint(WarriorMasterStanceBar)[4]
	NS.DB:Set("general.offsetX", 100)
	NS.DB:Set("general.offsetY", -50)
	near(lastPoint(WarriorMasterRageBar)[4], rx + 100, 1e-9, "rage moved")
	near(lastPoint(WarriorMasterStanceBar)[4], sx + 100, 1e-9, "stance moved")
	near(lastPoint(WarriorMasterSwingFrame)[5], NS.db.profile.swing.point.y - 50, 1e-9, "swing moved")
	eq(NS.db.profile.rage.point.x, 0, "module positions unchanged")
end)

test("global offset changes in combat move the stance bar after combat", function()
	WM.Boot()
	Mock.EnterCombat()
	NS.DB:Set("general.offsetX", 40)
	eq(#Mock.blocked, 0, "no protected call in combat")
	Mock.LeaveCombat()
	near(lastPoint(WarriorMasterStanceBar)[4], 40, 1e-9, "stance bar placed after combat")
end)

test("keep on screen per module and for everything", function()
	WM.Boot()
	eq(WarriorMasterRageBar.__clamped, true, "clamped by default")
	NS.DB:Set("rage.clamp", false)
	eq(WarriorMasterRageBar.__clamped, false, "module switch")
	eq(WarriorMasterHealthBar.__clamped, true, "others unchanged")
	NS.DB:Set("general.clampAll", false)
	eq(WarriorMasterHealthBar.__clamped, false, "global switch")
	eq(WarriorMasterStanceBar.__clamped, false, "secure bar too")
end)

test("changing the screen anchor keeps the frame in place", function()
	WM.Boot()
	local point = NS.ConvertAnchor(WarriorMasterRageBar, "TOPLEFT")
	eq(point.point, "TOPLEFT", "anchor")
	eq(point.x, 390, "left edge from the screen's left")
	eq(point.y, -394, "top edge from the screen's top")
	NS.DB:Set("rage.point", point)
	local p = lastPoint(WarriorMasterRageBar)
	eq(p[1], "TOPLEFT", "frame point")
	eq(p[3], "TOPLEFT", "screen point")
end)

test("dragging a module keeps its anchor and ignores the global offset", function()
	WM.Boot()
	NS.DB:Set("health.point", { point = "BOTTOM", relPoint = "BOTTOM", x = 0, y = 100 })
	NS.DB:Set("general.offsetY", 20)
	NS.DB:Set("general.locked", false)
	local entry
	for _, e in ipairs(NS.Movers.list) do
		if e.frame == WarriorMasterHealthBar then
			entry = e
		end
	end
	entry.overlay.__scripts.OnDragStart(entry.overlay)
	entry.overlay.__scripts.OnDragStop(entry.overlay)
	local p = NS.db.profile.health.point
	eq(p.point, "BOTTOM", "anchor kept")
	eq(p.y, 392 - 20, "bottom edge from the screen bottom, minus the global offset")
end)

test("the All modules handle sets the global offset", function()
	WM.Boot()
	NS.DB:Set("general.locked", false)
	check(WarriorMasterGroupHandle:IsShown(), "handle visible when unlocked")
	local entry = NS.Movers.groupEntry
	entry.overlay.__scripts.OnDragStart(entry.overlay)
	entry.overlay.__scripts.OnDragStop(entry.overlay)
	eq(NS.db.profile.general.offsetX, 0, "x")
	eq(NS.db.profile.general.offsetY, 150, "y relative to the handle's home")
	entry.overlay.__scripts.OnMouseUp(entry.overlay, "RightButton")
	eq(NS.db.profile.general.offsetY, 0, "right-click resets")
	NS.DB:Set("general.locked", true)
	check(not WarriorMasterGroupHandle:IsShown(), "hidden when locked")
end)

test("/warrior is the command and /wm is left to the game", function()
	WM.Boot()
	eq(SLASH_WARRIORMASTER1, "/warrior", "main command")
	eq(SLASH_WARRIORMASTER2, "/warriormaster", "long form")
	eq(SLASH_WARRIORMASTER3, "/uw", "short alias")
	eq(SLASH_WARRIORMASTER4, nil, "nothing else, and never /wm")
	SlashCmdList.WARRIORMASTER("")
	check(WarriorMasterConfig:IsShown(), "opens the settings")
end)

test("font styles set font, size, outline and shadow in one click", function()
	WM.Boot()
	local Media = NS.Media
	eq(#Media.FONT_PRESET_KEYS, 12, "twelve font styles")
	for _, key in ipairs(Media.FONT_PRESET_KEYS) do
		local p = Media.fontPresets[key]
		check(Media.fonts[p.font], key .. " uses a known font")
		check(NS.L[p.labelKey] ~= p.labelKey, key .. " has a name")
	end
	eq(Media.MatchFontPreset(NS.db.profile.rage, true), "Forever", "default matches the Forever style")
	NS.Config:Show()
	NS.Config:ShowPage("rage")
	local page = NS.Config:GetPage("rage").instance
	local dropdown
	for _, control in ipairs(page.controls) do
		for _, child in ipairs(control.frame.__children or {}) do
			if child.__kind == "FontString" and child.__text == NS.L.FONT_STYLE then
				dropdown = control
			end
		end
	end
	check(dropdown, "font style menu on the page")
	local button
	for _, child in ipairs(dropdown.frame.__children) do
		if child.__kind == "Button" then
			button = child
		end
	end
	button.__scripts.OnClick(button)
	for _, f in ipairs(Mock.frames) do
		if f.value == "Impact" and f.__scripts.OnClick then
			f.__scripts.OnClick(f)
		end
	end
	local p = NS.db.profile.rage
	eq(p.font, "Damage", "font")
	eq(p.fontSize, 14, "size")
	eq(p.fontOutline, "THICKOUTLINE", "outline")
	eq(p.style, "Custom", "a hand-picked font makes the module Custom")
end)

test("short controls share rows in the settings window", function()
	WM.Boot()
	NS.Config:Show()
	NS.Config:ShowPage("general")
	local page = NS.Config:GetPage("general").instance
	local checks = {}
	for _, control in ipairs(page.controls) do
		if control.kind == "check" then
			checks[#checks + 1] = control.frame
		end
	end
	local first, second = checks[1].__points[1], checks[2].__points[1]
	eq(first[5], second[5], "first two module checkboxes on the same row")
	check(second[4] > first[4], "side by side")
	check(checks[3].__points[1][5] == first[5], "three per row")
end)
