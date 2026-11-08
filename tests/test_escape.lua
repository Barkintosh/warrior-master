-- Escape handling must never taint Blizzard's own Escape actions
-- (SpellStopCasting / SpellStopTargeting, the game menu).

local function openEverything()
	WM.Boot()
	NS.Config:Show()
	for _, def in ipairs(NS.Config.pages) do
		NS.Config:ShowPage(def.key)
	end
	local b = WarriorMasterStanceButton1
	b.__scripts.PostClick(b, "RightButton", false)
end

test("never adds to Blizzard's Escape handler list or UISpecialFrames", function()
	openEverything()
	eq(#Mock.escHandlers, 0, "no Blizzard Escape handler registered")
	eq(#UISpecialFrames, 0, "UISpecialFrames untouched")
	NS.StancePicker:Hide()
	NS.Config:Hide()
end)

test("Escape closes the dropdown, then the window, and never reaches the game", function()
	WM.Boot()
	NS.Config:Show()
	local anchor = CreateFrame("Button", nil, UIParent)
	NS.UI.OpenMenu(anchor, { { value = 1, text = "one" } }, 1, function() end)
	local before = Mock.gameKeys or 0
	check(Mock.PressEscape(), "consumed")
	check(WarriorMasterConfig:IsShown(), "first Escape only closes the dropdown")
	check(Mock.PressEscape(), "consumed")
	check(not WarriorMasterConfig:IsShown(), "second Escape closes the window")
	eq(Mock.gameKeys or 0, before, "the game never received Escape")
end)

test("other keys keep working while the window is open", function()
	WM.Boot()
	NS.Config:Show()
	local before = Mock.gameKeys or 0
	Mock.PressKey("W")
	eq(Mock.gameKeys, before + 1, "movement key reaches the game")
	check(WarriorMasterConfig:IsShown(), "window stays open")
end)

test("in combat Escape is left to the game and nothing protected is touched", function()
	WM.Boot()
	NS.Config:Show()
	Mock.EnterCombat()
	check(not WarriorMasterConfig.__keyboard, "keyboard capture off in combat")
	local before = Mock.gameKeys or 0
	Mock.PressEscape()
	eq(Mock.gameKeys, before + 1, "Escape goes to the game (stop casting, menu)")
	check(WarriorMasterConfig:IsShown(), "window stays; close it with its X")
	NS.Config:Hide()
	NS.Config:Show()
	eq(#Mock.blocked, 0, "no keyboard call blocked in combat")
	Mock.LeaveCombat()
	check(WarriorMasterConfig.__keyboard, "keyboard capture back after combat")
	check(Mock.PressEscape(), "Escape closes again")
	check(not WarriorMasterConfig:IsShown(), "closed")
end)
