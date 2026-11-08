-- Automatic vertical layout (General page > Layout).

local FRAMES = {
	health = "WarriorMasterHealthBar",
	rage = "WarriorMasterRageBar",
	swing = "WarriorMasterSwingFrame",
	cast = "WarriorMasterCastBar",
	stance = "WarriorMasterStanceBar",
}

local function point(key)
	local f = _G[FRAMES[key]]
	return f.__points[#f.__points]
end

local function y(key)
	return point(key)[5]
end

local function layoutOn()
	NS.DB:Set("general.layout.enabled", true)
end

test("layout is off by default: modules keep their own positions", function()
	WM.Boot()
	eq(NS.db.profile.general.layout.enabled, false, "off")
	local p = point("health")
	eq(p[1], "CENTER", "own anchor")
	eq(p[5], -180, "own height on screen")
end)

test("layout stacks every module top to bottom with the gap", function()
	WM.Boot()
	check(WarriorMasterStanceBar ~= nil, "stance bar exists")
	layoutOn()
	for key, name in pairs(FRAMES) do
		local p = point(key)
		eq(p[1], "TOP", key .. " anchored by its top")
		eq(p[2], UIParent, key .. " anchored to the screen, never to another module")
		eq(p[3], "CENTER", key .. " from the screen center")
		eq(p[4], 0, key .. " centered")
	end
	-- Forever sizes: health 16, rage 12, swing 20 (one bar: a shield is no
	-- weapon), cast 16, then the stance bar; gap 4.
	eq(y("health"), -160, "health first")
	eq(y("rage"), -180, "rage below health")
	eq(y("swing"), -196, "swing below rage")
	eq(y("cast"), -220, "cast below swing")
	eq(y("stance"), -240, "stance last")
	NS.DB:Set("general.layout.gap", 10)
	eq(y("rage"), -186, "bigger gap")
	eq(y("stance"), -264, "everything follows")
end)

test("modules can be reordered and switched-off modules take no room", function()
	WM.Boot()
	layoutOn()
	check(NS.Layout:Move("stance", -1), "stance up")
	check(NS.Layout:Move("stance", -1), "stance up again")
	check(not NS.Layout:Move("health", -1), "first one cannot go higher")
	eq(table.concat(NS.db.profile.general.layout.order, ","), "health,rage,stance,swing,cast", "new order saved")
	eq(y("stance"), -196, "stance now third")
	eq(y("swing"), -196 - 36 - 4, "swing below the stance bar")
	NS.DB:Set("rage.enabled", false)
	eq(y("stance"), -180, "rage switched off: no room kept")
end)

test("layout order list on the General page moves modules", function()
	WM.Boot()
	layoutOn()
	NS.Config:Show()
	NS.Config:ShowPage("general")
	local page = NS.Config:GetPage("general").instance
	local list
	for _, control in ipairs(page.controls) do
		if control.kind == "order" then
			list = control
		end
	end
	check(list, "order list present")
	eq(#list.rows, 5, "one row per module")
	eq(list.rows[1].label:GetText(), "Health Bar", "health on top")
	list.rows[1].down.__scripts.OnClick(list.rows[1].down)
	eq(NS.db.profile.general.layout.order[1], "rage", "rage moved up")
	eq(list.rows[1].label:GetText(), "Rage Bar", "list redrawn")
	NS.DB:Set("cast.enabled", false)
	page:Refresh()
	local castRow
	for _, row in ipairs(list.rows) do
		if row.label:GetText():find("Cast", 1, true) then
			castRow = row
		end
	end
	contains(castRow.label:GetText(), NS.L.LAYOUT_OFF, "switched-off module marked")
end)

test("saved or imported orders are repaired", function()
	WM.Boot()
	NS.DB:Set("general.layout.order", { "stance", "stance", "bogus", 42, "cast" })
	eq(table.concat(NS.db.profile.general.layout.order, ","), "stance,cast,health,rage,swing", "duplicates and junk dropped, missing added")
	NS.DB:Set("general.layout.order", "nope")
	eq(#NS.db.profile.general.layout.order, 5, "default order for a bad value")
end)

test("in combat the stance bar waits, the other bars follow at once", function()
	WM.Boot()
	layoutOn()
	Mock.EnterCombat()
	NS.Layout:Move("stance", -4)
	eq(#Mock.blocked, 0, "no protected call in combat")
	eq(y("health"), -160 - 36 - 4, "plain bars moved at once")
	eq(y("stance"), -240, "stance bar not moved in combat")
	Mock.LeaveCombat()
	eq(y("stance"), -160, "stance bar moved after combat")
end)

test("dragging any bar moves the whole stack", function()
	WM.Boot()
	layoutOn()
	NS.DB:Set("general.locked", false)
	local entry
	for _, e in ipairs(NS.Movers.list) do
		if e.frame == WarriorMasterRageBar then
			entry = e
		end
	end
	entry.overlay.__scripts.OnDragStart(entry.overlay)
	local f = WarriorMasterRageBar
	rawset(f, "GetLeft", function() return 500 - f.__width / 2 + 30 end)
	rawset(f, "GetRight", function() return 500 + f.__width / 2 + 30 end)
	rawset(f, "GetTop", function() return 400 + f.__height / 2 - 20 end)
	rawset(f, "GetBottom", function() return 400 - f.__height / 2 - 20 end)
	entry.overlay.__scripts.OnDragStop(entry.overlay)
	eq(NS.db.profile.general.offsetX, 30, "stack moved right")
	eq(NS.db.profile.general.offsetY, -20, "stack moved down")
	eq(point("health")[4], 30, "health follows")
	eq(y("stance"), -260, "stance follows")
	eq(NS.db.profile.rage.point.x, 0, "rage's own position untouched")
	entry.overlay.__scripts.OnMouseUp(entry.overlay, "RightButton")
	eq(NS.db.profile.general.offsetX, 0, "right-click puts the stack back")
end)

test("an attached rage bar is placed by the layout instead", function()
	WM.Boot()
	NS.DB:Set("rage.attach.enabled", true)
	eq(point("rage")[2], WarriorMasterHealthBar, "attached without layout")
	layoutOn()
	eq(point("rage")[2], UIParent, "layout places it")
	NS.DB:Set("general.layout.enabled", false)
	eq(point("rage")[2], WarriorMasterHealthBar, "attached again when the layout is off")
end)

test("module position controls are disabled while the layout places them", function()
	WM.Boot()
	layoutOn()
	NS.Config:Show()
	for _, key in ipairs({ "rage", "cast", "stance" }) do
		NS.Config:ShowPage(key)
		local page = NS.Config:GetPage(key).instance
		local found = false
		for _, control in ipairs(page.controls) do
			if control.fs and control.fs:GetText() == NS.L.LAYOUT_MANAGED then
				found = true
			end
		end
		check(found, key .. " page says the layout places it")
	end
end)

test("switching the layout off in combat never leaves the stance bar in the stack", function()
	WM.Boot()
	layoutOn()
	Mock.EnterCombat()
	NS.Layout:Move("stance", -4)
	NS.DB:Set("general.layout.enabled", false)
	Mock.LeaveCombat()
	eq(#Mock.blocked, 0, "no protected call")
	local p = point("stance")
	eq(p[1], "CENTER", "back on its own anchor")
	eq(p[5], -285, "its own position")
end)
