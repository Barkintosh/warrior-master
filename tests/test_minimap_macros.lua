-- Automatic stance macros, minimap button and addon compartment.

local function macroNames()
	local names = {}
	for index, m in pairs(Mock.macros) do
		names[m.name] = index
	end
	return names
end

local function count(t)
	local n = 0
	for _ in pairs(t) do
		n = n + 1
	end
	return n
end

test("nothing is created before the game has loaded the macros", function()
	WM.Boot()
	eq(count(Mock.macros), 0, "no macro at boot")
end)

test("stance macros are created once the macros are loaded, without duplicates", function()
	WM.Boot()
	Mock.FireEvent("UPDATE_MACROS")
	local names = macroNames()
	check(names["WM Battle"] and names["WM Defensive"] and names["WM Berserker"], "three stance macros")
	check(names["WM Battle"] > 120, "character macros")
	eq(Mock.macros[names["WM Defensive"]].body, "#showtooltip Defensive Stance\n/cast [nostance:2] Defensive Stance", "plain stance action")
	Mock.FireEvent("UPDATE_MACROS")
	Mock.FireEvent("UPDATE_MACROS")
	eq(count(Mock.macros), 3, "no duplicates")
end)

test("the fallback timer creates them if the load event came earlier", function()
	WM.Boot()
	Mock.Advance(5.1)
	eq(count(Mock.macros), 3, "created after the fallback delay")
end)

test("only known stances get a macro", function()
	WM.Boot({ state = { forms = { { icon = 1, active = true, castable = true, spellID = 2457 } } } })
	Mock.FireEvent("UPDATE_MACROS")
	local names = macroNames()
	check(names["WM Battle"], "battle")
	check(not names["WM Defensive"] and not names["WM Berserker"], "no unknown stances")
end)

test("macros follow the setup and come back when the setup changes", function()
	WM.Boot()
	Mock.FireEvent("UPDATE_MACROS")
	local stance = NS.modules.stance
	stance:SetLoadout("defensive", "mh", 1001)
	local index = macroNames()["WM Defensive"]
	contains(Mock.macros[index].body, "/equipslot 16 item:1001", "weapon added to the macro")
	-- The player deletes a macro: it is not recreated behind their back...
	Mock.macros[macroNames()["WM Battle"]] = nil
	Mock.FireEvent("UPDATE_MACROS")
	check(not macroNames()["WM Battle"], "deleted macro stays deleted")
	-- ...but changing that stance's setup brings it back, up to date.
	stance:SetLoadout("battle", "mh", 1002)
	local battle = macroNames()["WM Battle"]
	check(battle, "recreated on a setup change")
	contains(Mock.macros[battle].body, "/equipslot 16 item:1002", "with the new weapon")
end)

test("the option turns automatic macros off and on", function()
	WM.Boot()
	NS.DB:Set("stance.autoMacros", false)
	Mock.FireEvent("UPDATE_MACROS")
	eq(count(Mock.macros), 0, "none while off")
	NS.DB:Set("stance.autoMacros", true)
	eq(count(Mock.macros), 3, "created when turned on")
end)

test("in combat, macros are created after combat", function()
	WM.Boot()
	Mock.EnterCombat()
	Mock.FireEvent("UPDATE_MACROS")
	eq(count(Mock.macros), 0, "nothing in combat")
	eq(#Mock.blocked, 0, "no protected call")
	Mock.LeaveCombat()
	eq(count(Mock.macros), 3, "created after combat")
end)

test("full macro slots are reported once, without errors", function()
	WM.Boot()
	for i = 121, 150 do
		Mock.macros[i] = { name = "x" .. i, body = "" }
	end
	Mock.FireEvent("UPDATE_MACROS")
	local notices = 0
	for _, line in ipairs(Mock.chat) do
		if line:find("could not be created", 1, true) then
			notices = notices + 1
		end
	end
	eq(notices, 1, "one notice")
end)

test("minimap button sits on the minimap edge and opens the settings", function()
	WM.Boot()
	local b = WarriorMasterMinimapButton
	check(b and b:IsShown(), "button shown")
	eq(b:GetParent(), Minimap, "child of the minimap")
	local p = b.__points[#b.__points]
	eq(p[2], Minimap, "anchored to the minimap")
	near(math.sqrt(p[4] ^ 2 + p[5] ^ 2), 78, 1e-6, "on the edge (radius 70 + 8)")
	b.__scripts.OnClick(b, "LeftButton")
	check(WarriorMasterConfig:IsShown(), "left-click opens the settings")
	b.__scripts.OnClick(b, "LeftButton")
	check(not WarriorMasterConfig:IsShown(), "left-click again closes them")
	b.__scripts.OnClick(b, "RightButton")
	eq(NS.db.profile.general.locked, false, "right-click unlocks the frames")
	b.__scripts.OnEnter(b)
	check(GameTooltip.__lines and #GameTooltip.__lines >= 3, "tooltip")
end)

test("minimap button can be dragged around the minimap and hidden", function()
	WM.Boot()
	local b = WarriorMasterMinimapButton
	Mock.cursorPos = { 500, 600 } -- straight above the minimap centre
	b.__scripts.OnDragStart(b)
	b.__scripts.OnUpdate(b, 0.01)
	b.__scripts.OnDragStop(b)
	eq(NS.db.global.minimap.angle, 90, "angle saved")
	local p = b.__points[#b.__points]
	near(p[4], 0, 1e-6, "x on top")
	near(p[5], 78, 1e-6, "y on top")
	check(b.__scripts.OnUpdate == nil, "no OnUpdate after the drag")
	NS.DB:SetGlobal("minimap.show", false)
	check(not b:IsShown(), "hidden from the settings")
end)

test("addon compartment entry opens the settings", function()
	WM.Boot()
	WarriorMaster_OnAddonCompartmentClick("WarriorMaster", "LeftButton")
	check(WarriorMasterConfig:IsShown(), "opened")
	WarriorMaster_OnAddonCompartmentEnter("WarriorMaster", UIParent)
	WarriorMaster_OnAddonCompartmentLeave("WarriorMaster", UIParent)
end)

test("no minimap button on other classes", function()
	WM.Boot({ state = { class = "PALADIN" } })
	check(WarriorMasterMinimapButton == nil, "not created")
	WarriorMaster_OnAddonCompartmentClick("WarriorMaster", "LeftButton")
	contains(Mock.chat[#Mock.chat], "only active on Warrior", "explains why")
end)
