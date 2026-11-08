-- Right-click weapon picker and stance macros for action bars.

local function button(i)
	return _G["WarriorMasterStanceButton" .. i]
end

local function rightClick(b)
	b.__scripts.PostClick(b, "RightButton", true)
	b.__scripts.PostClick(b, "RightButton", false)
end

local function picker()
	return NS.StancePicker
end

local function rowItems(row)
	local shown = {}
	for _, b in ipairs(row.buttons) do
		if b:IsShown() then
			shown[#shown + 1] = b
		end
	end
	return shown
end

local function lines(text)
	local out = {}
	for line in (text or ""):gmatch("[^\n]+") do
		out[#out + 1] = line
	end
	return out
end

test("right-click opens the weapon picker and performs no game action", function()
	WM.Boot()
	local b = button(2)
	eq(b:GetAttribute("type2"), "none", "right button has no secure action")
	b.__scripts.PostClick(b, "LeftButton", false)
	check(not picker():IsShown(), "left click does not open it")
	rightClick(b)
	check(picker():IsShown(), "picker open")
	eq(picker().key, "defensive", "for the clicked stance")
	eq(WarriorMasterWeaponPicker.title:GetText(), "Defensive Stance", "title")
	rightClick(b)
	check(not picker():IsShown(), "right-click again closes it")
end)

test("picker lists the weapons that fit each hand", function()
	WM.Boot()
	rightClick(button(1))
	local mh = rowItems(picker().rows.mh)
	local oh = rowItems(picker().rows.oh)
	eq(#mh, 4, "none + two one-handers + the two-hander")
	eq(#oh, 4, "none + shield + two one-handers (Dual Wield known)")
	mh[2].__scripts.OnEnter(mh[2])
	check(GameTooltip.__tooltipInventory == 16 or GameTooltip.__tooltipBag ~= nil, "item tooltip")
end)

test("clicking an icon assigns it and updates the stance button", function()
	WM.Boot()
	rightClick(button(2))
	local mh = rowItems(picker().rows.mh)
	local oh = rowItems(picker().rows.oh)
	local sword, shield
	for _, b in ipairs(mh) do
		if b.icon.__texture == 1 then
			sword = b
		end
	end
	for _, b in ipairs(oh) do
		if b.icon.__texture == 3 then
			shield = b
		end
	end
	sword.__scripts.OnClick(sword)
	shield.__scripts.OnClick(shield)
	local lo = NS.modules.stance:GetLoadout("defensive")
	eq(lo.mh, 1001, "main hand chosen")
	eq(lo.oh, 2001, "shield chosen")
	eq(button(2):GetAttribute("type"), "macro", "button now equips")
	local l = lines(button(2):GetAttribute("macrotext"))
	eq(l[2], "/equipslot 16 item:1001", "main hand line")
	eq(l[3], "/equipslot 17 item:2001", "off hand line")
	mh[1].__scripts.OnClick(mh[1])
	eq(NS.modules.stance:GetLoadout("defensive").mh, nil, "first icon clears the main hand")
end)

test("a two-hander disables the off-hand row", function()
	WM.Boot()
	NS.modules.stance:SetLoadout("battle", "mh", 1002)
	rightClick(button(1))
	local row = picker().rows.oh
	check(row.note:IsShown(), "note shown")
	local oh = rowItems(row)
	oh[2].__scripts.OnClick(oh[2])
	eq(NS.modules.stance:GetLoadout("battle").oh, nil, "off hand not assignable")
end)

test("picking weapons in combat changes the button after combat", function()
	WM.Boot()
	rightClick(button(2))
	Mock.EnterCombat()
	local mh = rowItems(picker().rows.mh)
	mh[2].__scripts.OnClick(mh[2])
	eq(button(2):GetAttribute("type"), "spell", "unchanged during combat")
	eq(#Mock.blocked, 0, "no protected call")
	Mock.LeaveCombat()
	eq(button(2):GetAttribute("type"), "macro", "applied after combat")
end)

test("equipment sets replace single weapons and the other way round", function()
	WM.Boot({ state = { equipmentSets = { "Tank", "Dps" } } })
	local stance = NS.modules.stance
	stance:SetLoadout("defensive", "mh", 1001)
	rightClick(button(2))
	local sets = rowItems(picker().rows.set)
	eq(#sets, 3, "none + two sets")
	sets[3].__scripts.OnClick(sets[3])
	local lo = stance:GetLoadout("defensive")
	eq(lo.set, "Tank", "set chosen (sorted by name)")
	eq(lo.mh, nil, "single weapon cleared")
	stance:SetLoadout("defensive", "oh", 2001)
	eq(stance:GetLoadout("defensive").set, nil, "set cleared by a weapon")
end)

test("Escape closes the picker", function()
	WM.Boot()
	rightClick(button(1))
	check(Mock.PressEscape(), "handled")
	check(not picker():IsShown(), "closed")
end)

test("stance macro goes on the cursor and follows the weapons", function()
	WM.Boot()
	local stance = NS.modules.stance
	stance:SetLoadout("defensive", "mh", 1001)
	local ok, message = stance:PickupMacro("defensive")
	check(ok, message)
	local macro = Mock.macros[121]
	eq(macro.name, "WM Defensive", "character macro")
	eq(Mock.cursor.index, 121, "on the cursor")
	local l = lines(macro.body)
	eq(l[1], "#showtooltip Defensive Stance", "tooltip line")
	eq(l[2], "/cast [nostance:2] Defensive Stance", "stance line")
	eq(l[3], "/equipslot 16 item:1001", "weapon line")
	check(NS.MacroBuilder.Validate(macro.body).ok, "valid macro")
	stance:SetLoadout("defensive", "oh", 2001)
	l = lines(Mock.macros[121].body)
	eq(l[4], "/equipslot 17 item:2001", "macro updated with the new weapon")
	Mock.EnterCombat()
	stance:SetLoadout("defensive", "oh", nil)
	eq(#lines(Mock.macros[121].body), 4, "not edited during combat")
	ok = stance:PickupMacro("battle")
	check(not ok, "no new macro in combat")
	eq(#Mock.blocked, 0, "no protected call")
	Mock.LeaveCombat()
	eq(#lines(Mock.macros[121].body), 3, "updated after combat")
end)

test("picker macro icon puts the stance macro on the cursor", function()
	WM.Boot()
	rightClick(button(3))
	local f = WarriorMasterWeaponPicker
	f.macro.__scripts.OnDragStart(f.macro)
	eq(Mock.macros[121].name, "WM Berserker", "macro created")
	eq(Mock.cursor.index, 121, "picked up")
	check(not picker():IsShown(), "picker closes so you can drop it")
end)

test("stances page has a put-on-action-bar button per stance", function()
	WM.Boot()
	NS.Config:Show()
	NS.Config:ShowPage("stance")
	local page = NS.Config:GetPage("stance").instance
	local count = 0
	for _, control in ipairs(page.controls) do
		for _, child in ipairs(control.frame.__children or {}) do
			if child.__kind == "FontString" and child.__text == NS.L.STANCE_MACRO_BUTTON then
				count = count + 1
				if count == 1 then
					control.frame.__scripts.OnClick(control.frame)
				end
			end
		end
	end
	eq(count, 3, "one per stance")
	eq(Mock.macros[121].name, "WM Battle", "created from the page")
end)
