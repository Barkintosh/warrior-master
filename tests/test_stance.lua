-- Secure stance buttons, weapon sets and combat lockdown.

local function stance()
	return NS.modules.stance
end

local function button(i)
	return _G["WarriorMasterStanceButton" .. i]
end

local function lines(text)
	local out = {}
	for line in (text or ""):gmatch("[^\n]+") do
		out[#out + 1] = line
	end
	return out
end

test("one secure spell button per known stance", function()
	WM.Boot()
	for i, name in ipairs({ "Battle Stance", "Defensive Stance", "Berserker Stance" }) do
		local b = button(i)
		check(b.__protected, "button " .. i .. " is a secure button")
		eq(b:GetAttribute("type"), "spell", "plain stance action")
		eq(b:GetAttribute("spell"), name, "stance spell")
		check(b:IsShown(), "shown")
	end
	check(button(1).__clicks ~= nil, "registered for clicks")
end)

test("only known stances get buttons", function()
	WM.Boot({ state = { forms = { { icon = 1, active = true, castable = true, spellID = 2457 } } } })
	check(button(1):IsShown(), "battle stance button")
	check(not button(2):IsShown(), "no defensive button")
	eq(button(2):GetAttribute("type"), nil, "no action on unused buttons")
end)

test("stance weapons build a short click macro", function()
	WM.Boot()
	stance():SetLoadout("defensive", "mh", 1001)
	stance():SetLoadout("defensive", "oh", 2001)
	local b = button(2)
	eq(b:GetAttribute("type"), "macro", "macro action")
	local l = lines(b:GetAttribute("macrotext"))
	eq(#l, 3, "three lines")
	eq(l[1], "/cast [nostance:2] Defensive Stance", "stance line")
	eq(l[2], "/equipslot 16 item:1001", "main hand line")
	eq(l[3], "/equipslot 17 item:2001", "off hand line")
	eq(b:GetAttribute("spell"), nil, "no stale spell attribute")
end)

test("two-handed main hand drops the off-hand line and reports it", function()
	WM.Boot()
	stance():SetLoadout("battle", "mh", 1002)
	stance():SetLoadout("battle", "oh", 2001)
	local l = lines(button(1):GetAttribute("macrotext"))
	eq(#l, 2, "stance and main hand only")
	eq(l[2], "/equipslot 16 item:1002", "two-hander")
	local problems = stance():ValidateLoadout("battle")
	eq(#problems, 1, "one problem")
	contains(problems[1], "two-handed", "conflict reported")
end)

test("missing items are skipped and reported", function()
	WM.Boot()
	stance():SetLoadout("berserker", "mh", 9999)
	eq(button(3):GetAttribute("type"), "spell", "falls back to the plain stance action")
	local problems = stance():ValidateLoadout("berserker")
	contains(problems[1], "Not found", "missing item reported")
	check(button(3).warn:IsShown(), "warning marker on the button")
end)

test("item names are sanitized before use", function()
	WM.Boot()
	Mock.state.items[1001].name = "Evil\n/run Boom()|cff [x];"
	NS.DB:Set("stance.useItemNames", true)
	stance():SetLoadout("defensive", "mh", 1001)
	local l = lines(button(2):GetAttribute("macrotext"))
	eq(#l, 2, "no injected line")
	eq(l[2], "/equipslot 16 Evil /run Boom() cff x", "sanitized name")
	eq(NS.Security.FindForbiddenCommand(button(2):GetAttribute("macrotext")), nil, "no forbidden command at line start")
end)

test("changes during combat wait for the end of combat", function()
	WM.Boot()
	Mock.EnterCombat()
	stance():SetLoadout("defensive", "mh", 1001)
	NS.DB:Set("stance.buttonSize", 50)
	eq(button(2):GetAttribute("type"), "spell", "unchanged in combat")
	check(stance().pending, "change pending")
	check(NS.Combat:HasPending(), "queued")
	eq(#Mock.blocked, 0, "no protected call attempted")
	Mock.LeaveCombat()
	eq(button(2):GetAttribute("type"), "macro", "applied after combat")
	eq(button(2):GetWidth(), 50, "resized after combat")
	check(not stance().pending, "nothing pending")
end)

test("disabling in combat clears the buttons after combat", function()
	WM.Boot()
	Mock.EnterCombat()
	NS.DB:Set("stance.enabled", false)
	eq(button(1):GetAttribute("type"), "spell", "still configured during combat")
	Mock.LeaveCombat()
	eq(button(1):GetAttribute("type"), nil, "action cleared")
	check(not WarriorMasterStanceBar:IsShown(), "bar hidden")
end)

test("stance change in combat only updates the highlight", function()
	WM.Boot()
	Mock.EnterCombat()
	Mock.state.forms[1].active = false
	Mock.state.forms[3].active = true
	Mock.FireEvent("UPDATE_SHAPESHIFT_FORM")
	eq(button(3).activeIndicator:GetAlpha(), 1, "berserker highlighted")
	eq(button(1).activeIndicator:GetAlpha(), 0, "battle not highlighted")
	eq(stance().activeKey, "berserker", "active stance tracked")
	eq(#Mock.blocked, 0, "no protected call")
	Mock.LeaveCombat()
end)

test("secret stance state uses the client's boolean evaluator", function()
	WM.Boot()
	Mock.state.secretForms = true
	Mock.FireEvent("UPDATE_SHAPESHIFT_FORM")
	local alpha = button(1).activeIndicator:GetAlpha()
	check(issecretvalue(alpha), "alpha derived from a secret boolean")
	eq(Mock.Unwrap(alpha), 1, "still the right value")
end)

test("the stance bar cannot be dragged in combat", function()
	WM.Boot()
	NS.DB:Set("general.locked", false)
	local entry
	for _, e in ipairs(NS.Movers.list) do
		if e.frame == WarriorMasterStanceBar then
			entry = e
		end
	end
	check(entry and entry.overlay:IsShown(), "mover shown when unlocked")
	Mock.EnterCombat()
	check(not entry.overlay:IsShown(), "movers hidden when combat starts")
	entry.overlay.__scripts.OnDragStart(entry.overlay)
	check(not WarriorMasterStanceBar.__moving, "drag refused in combat")
	eq(#Mock.blocked, 0, "no protected call")
	Mock.LeaveCombat()
end)

test("equipment sets are used when available", function()
	WM.Boot({ state = { equipmentSets = { "Tank" } } })
	stance():SetLoadout("defensive", "set", "Tank")
	local l = lines(button(2):GetAttribute("macrotext"))
	eq(l[2], "/equipset Tank", "equipment set line")
end)

test("key binding labels and tooltips", function()
	WM.Boot({ state = { bindings = { ["CLICK WarriorMasterStanceButton1:LeftButton"] = "SHIFT-1" } } })
	Mock.FireEvent("UPDATE_BINDINGS")
	eq(button(1).hotkey:GetText(), "S-1", "short binding text")
	button(1).__scripts.OnEnter(button(1))
	eq(GameTooltip.__tooltipSpell, 2457, "spell tooltip")
end)
