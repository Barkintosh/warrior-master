-- Start-up, module lifecycle and addon footprint.

test("boots on a warrior and enables the default modules", function()
	WM.Boot()
	check(NS.state.ready, "addon ready")
	check(NS.state.isWarrior, "warrior detected")
	for _, key in ipairs({ "rage", "health", "swing", "stance" }) do
		check(NS.modules[key].enabled, key .. " enabled")
	end
	check(WarriorMasterRageBar and WarriorMasterRageBar:IsShown(), "rage bar shown")
	check(WarriorMasterHealthBar and WarriorMasterHealthBar:IsShown(), "health bar shown")
	check(WarriorMasterStanceBar and WarriorMasterStanceBar:IsShown(), "stance bar shown")
	eq(WarriorMasterStanceButton1:GetAttribute("type"), "spell", "stance 1 action")
	eq(WarriorMasterStanceButton1:GetAttribute("spell"), "Battle Stance", "stance 1 spell")
end)

test("stays idle on other classes", function()
	WM.Boot({ state = { class = "MAGE" } })
	check(NS.state.ready, "ready")
	check(not NS.state.isWarrior, "not a warrior")
	for _, key in ipairs(NS.moduleOrder) do
		check(not NS.modules[key].enabled, key .. " stays disabled")
	end
	check(WarriorMasterStanceButton1 == nil, "no secure buttons created")
	NS:HandleSlash("")
	contains(Mock.chat[#Mock.chat], "only active on Warrior", "warning printed")
end)

test("creates only the expected globals", function()
	WM.Boot()
	local allowed = {
		WarriorMasterDB = true, WarriorMasterCharDB = true,
		SLASH_WARRIORMASTER1 = true, SLASH_WARRIORMASTER2 = true, SLASH_WARRIORMASTER3 = true,
		WarriorMaster_OnAddonCompartmentClick = true,
		WarriorMaster_OnAddonCompartmentEnter = true,
		WarriorMaster_OnAddonCompartmentLeave = true,
		BINDING_HEADER_WARRIORMASTER = true,
		["BINDING_NAME_CLICK WarriorMasterStanceButton1:LeftButton"] = true,
		["BINDING_NAME_CLICK WarriorMasterStanceButton2:LeftButton"] = true,
		["BINDING_NAME_CLICK WarriorMasterStanceButton3:LeftButton"] = true,
	}
	for name in pairs(Mock.globalWrites) do
		check(allowed[name], "unexpected global written: " .. tostring(name))
	end
	check(SlashCmdList.WARRIORMASTER ~= nil, "slash command registered")
end)

test("disabling a module releases its events and hides it", function()
	WM.Boot()
	NS.DB:Set("rage.enabled", false)
	check(not NS.modules.rage.enabled, "rage disabled")
	check(not WarriorMasterRageBar:IsShown(), "rage bar hidden")
	local frame = NS.modules.rage.__eventFrame
	check(next(frame.__events) == nil, "no events left registered")
	NS.DB:Set("stance.enabled", false)
	eq(WarriorMasterStanceButton1:GetAttribute("type"), nil, "stance action cleared")
	check(not WarriorMasterStanceBar:IsShown(), "stance bar hidden")
end)

test("registers an Options entry and closes with Escape", function()
	WM.Boot()
	eq(#Settings.categories, 1, "settings category")
	NS.Config:Show()
	check(WarriorMasterConfig:IsShown(), "config shown")
	check(Mock.PressEscape(), "escape handled")
	eq(#Mock.escHandlers, 0, "without touching Blizzard's Escape list")
	check(not WarriorMasterConfig:IsShown(), "config closed by escape")
end)
