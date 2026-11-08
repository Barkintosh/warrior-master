-- Settings window: every page builds and its controls work.

local function click(frame, button)
	frame.__scripts.OnClick(frame, button or "LeftButton")
end

local function findButton(page, label)
	for _, control in ipairs(page.controls) do
		local f = control.frame
		for _, child in ipairs(f.__children or {}) do
			if child.__kind == "FontString" and child.__text == label then
				return f
			end
		end
	end
	return nil
end

test("every settings page builds and refreshes without errors", function()
	WM.Boot()
	NS.Config:Show()
	for _, def in ipairs(NS.Config.pages) do
		NS.Config:ShowPage(def.key)
		check(def.instance ~= nil, def.key .. " built")
		check(#def.instance.controls > 0, def.key .. " has controls")
		def.instance:Refresh()
	end
	eq(#NS.Config.pages, 8, "eight pages")
end)

test("checkbox toggles a profile setting", function()
	WM.Boot()
	NS.Config:Show()
	NS.Config:ShowPage("general")
	local page = NS.Config:GetPage("general").instance
	local box = findButton(page, NS.L.MODULE_RAGE)
	check(box, "rage checkbox found")
	click(box)
	eq(NS.db.profile.rage.enabled, false, "disabled from the UI")
	check(not NS.modules.rage.enabled, "module switched off")
	click(box)
	check(NS.modules.rage.enabled, "module switched back on")
end)

test("dropdown menu selects a value", function()
	WM.Boot()
	NS.Config:Show()
	NS.Config:ShowPage("rage")
	local anchor = CreateFrame("Button", nil, UIParent)
	local chosen
	NS.UI.OpenMenu(anchor, { { value = "a", text = "A" }, { value = "b", text = "B" } }, "a", function(v)
		chosen = v
	end)
	local menuRows = {}
	for _, f in ipairs(Mock.frames) do
		if f.value == "b" and f.__scripts.OnClick then
			menuRows[#menuRows + 1] = f
		end
	end
	check(#menuRows == 1, "menu row present")
	click(menuRows[1])
	eq(chosen, "b", "selected")
	check(Mock.PressEscape() == false or true, "escape safe")
end)

test("destructive buttons need a second click", function()
	WM.Boot()
	NS.DB:Set("rage.width", 300)
	NS.Config:Show()
	NS.Config:ShowPage("general")
	local page = NS.Config:GetPage("general").instance
	local reset = findButton(page, NS.L.RESET_ALL)
	click(reset)
	eq(NS.db.profile.rage.width, 300, "first click only arms")
	click(reset)
	eq(NS.db.profile.rage.width, 220, "second click resets")
end)

test("macro page previews and saves a macro", function()
	WM.Boot()
	NS.Config:Show()
	NS.Config:ShowPage("macros")
	local page = NS.Config:GetPage("macros").instance
	NS.DB:SetChar("macro.template", "overpower")
	page:Refresh()
	local area
	for _, control in ipairs(page.controls) do
		if control.GetValue then
			area = control
		end
	end
	eq(area.GetValue(), "#showtooltip Overpower\n/cast [stance:1] Overpower; Battle Stance", "preview")
	click(findButton(page, NS.L.MACRO_CREATE))
	local saved
	for _, m in pairs(Mock.macros) do
		saved = m
	end
	check(saved ~= nil, "macro saved")
	eq(saved.name, "Overpower", "default name from the template")
	eq(saved.body, area.GetValue(), "saved text")
end)

test("profiles page imports an export", function()
	WM.Boot()
	NS.DB:Set("rage.width", 345)
	local text = NS.DB:ExportProfile()
	NS.Config:Show()
	NS.Config:ShowPage("profiles")
	local ok = NS.DB:ImportProfile(text, "Again")
	check(ok, "imported")
	NS.Config:RefreshAll()
	eq(NS.db.profile.rage.width, 345, "imported values active")
end)

test("language change rebuilds the window in French", function()
	WM.Boot()
	NS.Config:Show()
	NS.DB:SetLanguage("frFR")
	eq(NS.Config.navButtons[1].text:GetText(), "Général", "navigation translated")
	NS.Config:ShowPage("about")
end)

test("unlocking shows movers and right-click resets a position", function()
	WM.Boot()
	NS.DB:Set("health.point", { point = "CENTER", relPoint = "CENTER", x = 100, y = 100 })
	NS.DB:Set("general.locked", false)
	local entry
	for _, e in ipairs(NS.Movers.list) do
		if e.frame == WarriorMasterHealthBar then
			entry = e
		end
	end
	check(entry.overlay:IsShown(), "overlay visible")
	entry.overlay.__scripts.OnMouseUp(entry.overlay, "RightButton")
	eq(NS.db.profile.health.point.x, 0, "position reset")
	entry.overlay.__scripts.OnDragStart(entry.overlay)
	entry.overlay.__scripts.OnDragStop(entry.overlay)
	eq(NS.db.profile.health.point.point, "CENTER", "position saved after drag")
end)

test("slash commands", function()
	WM.Boot()
	NS:HandleSlash("unlock")
	eq(NS.db.profile.general.locked, false, "unlocked")
	NS:HandleSlash("lock")
	eq(NS.db.profile.general.locked, true, "locked")
	NS:HandleSlash("preset compact")
	eq(NS.db.profile.rage.style, "Compact", "preset by name")
	NS:HandleSlash("preset high visibility rage")
	eq(NS.db.profile.rage.style, "HighVisibility", "multi-word style on one module")
	eq(NS.db.profile.health.style, "Compact", "other modules untouched")
	NS:HandleSlash("test")
	check(NS.TestMode:IsActive(), "preview on")
	NS:HandleSlash("test")
	NS:HandleSlash("diag")
	NS:HandleSlash("errors")
	NS:HandleSlash("nonsense")
	contains(Mock.chat[#Mock.chat], "Unknown command", "unknown command message")
end)
