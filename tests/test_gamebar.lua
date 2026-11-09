-- Stance actions on the game's own stance bar (option "Use the game's stance bar").

local function gameBar(count)
	local buttons = {}
	for i = 1, count or 3 do
		local b = CreateFrame("CheckButton", "StanceButton" .. i, UIParent)
		rawset(b, "__protected", true) -- the game's buttons are secure
		b:SetFrameLevel(72)
		b:SetSize(30, 30)
		b:Show()
		buttons[i] = b
	end
	return buttons
end

local function wm(i)
	return _G["WarriorMasterStanceButton" .. i]
end

test("off by default: Warrior Master keeps its own stance bar", function()
	gameBar()
	WM.Boot()
	eq(NS.db.profile.stance.useGameBar, false, "off")
	eq(wm(1):GetParent(), WarriorMasterStanceBar, "own bar")
	check(WarriorMasterStanceBar:IsShown(), "own bar shown")
end)

test("on: the actions sit invisibly on the game's stance buttons", function()
	local game = gameBar()
	WM.Boot()
	NS.DB:Set("stance.useGameBar", true)
	check(not WarriorMasterStanceBar:IsShown(), "own bar hidden")
	for i = 1, 3 do
		local b = wm(i)
		eq(b:GetParent(), game[i], "button " .. i .. " is a child of the game's button")
		eq(b.__points[1][1], "ALL", "covers it")
		eq(b.__points[1][2], game[i], "exactly that button")
		check(b:GetFrameLevel() > game[i]:GetFrameLevel(), "on top, so it gets the clicks")
		check(b:IsVisible(), "clickable")
		check(not b.icon:IsShown() and not b.bg:IsShown() and not b.hotkey:IsShown(), "the game's button draws itself")
		eq(b:GetAttribute("type2"), "none", "right-click is still no game action")
	end
	eq(wm(2):GetAttribute("type"), "spell", "left-click changes stance")
	eq(#Mock.blocked, 0, "no protected call")
	eq(#NS.errors, 0, "no error")
end)

test("on the game's bar, left-click equips and right-click picks weapons", function()
	gameBar()
	WM.Boot()
	NS.DB:Set("stance.useGameBar", true)
	NS.modules.stance:SetLoadout("defensive", "mh", 1001)
	local b = wm(2)
	eq(b:GetAttribute("type"), "macro", "stance and weapons in one click")
	contains(b:GetAttribute("macrotext"), "/equipslot 16 item:1001", "weapon line")
	check(b.mhIcon:IsShown(), "weapon icon shown on the game's button")
	b.__scripts.PostClick(b, "RightButton", false)
	check(NS.StancePicker:IsShown(), "picker open")
	eq(NS.StancePicker.key, "defensive", "for that stance")
end)

test("hiding the game's stance bar hides the actions with it", function()
	local game = gameBar()
	WM.Boot()
	NS.DB:Set("stance.useGameBar", true)
	game[1]:Hide()
	check(not wm(1):IsVisible(), "follows the game's button")
	check(wm(2):IsVisible(), "the others stay")
end)

test("turning it off brings Warrior Master's own bar back", function()
	gameBar()
	WM.Boot()
	NS.DB:Set("stance.useGameBar", true)
	NS.DB:Set("stance.useGameBar", false)
	eq(wm(1):GetParent(), WarriorMasterStanceBar, "back on its own bar")
	check(wm(1).icon:IsShown(), "draws itself again")
	check(WarriorMasterStanceBar:IsShown(), "own bar shown")
end)

test("switched on in combat, it moves after combat", function()
	local game = gameBar()
	WM.Boot()
	Mock.EnterCombat()
	NS.DB:Set("stance.useGameBar", true)
	eq(wm(1):GetParent(), WarriorMasterStanceBar, "unchanged in combat")
	eq(#Mock.blocked, 0, "no protected call")
	Mock.LeaveCombat()
	eq(wm(1):GetParent(), game[1], "moved after combat")
end)

test("without the game's stance buttons, its own bar is used and you are told once", function()
	WM.Boot()
	NS.DB:Set("stance.useGameBar", true)
	eq(wm(1):GetParent(), WarriorMasterStanceBar, "own bar")
	check(WarriorMasterStanceBar:IsShown(), "shown")
	local notices = 0
	for _, line in ipairs(Mock.chat) do
		if line:find(NS.L.STANCE_GAME_BAR_MISSING, 1, true) then
			notices = notices + 1
		end
	end
	eq(notices, 1, "one notice")
end)

test("the automatic layout leaves the stance bar to the game", function()
	gameBar()
	WM.Boot()
	NS.DB:Set("general.layout.enabled", true)
	NS.Layout:Move("stance", -4) -- stance first in the order
	NS.DB:Set("stance.useGameBar", true)
	check(not NS.Layout:Manages("stance"), "not placed by the layout")
	eq(WarriorMasterHealthBar.__points[1][5], -160, "no room kept for it")
	NS.Config:Show()
	NS.Config:ShowPage("stance")
	local page = NS.Config:GetPage("stance").instance
	local found = false
	for _, control in ipairs(page.controls) do
		if control.fs and control.fs:GetText() == NS.L.STANCE_GAME_BAR_PLACED then
			found = true
		end
	end
	check(found, "the Stances page says where the buttons are")
end)
