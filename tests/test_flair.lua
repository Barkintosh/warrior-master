-- Warrior fun in the settings window: execute splash and battle cry.

local function openGeneral()
	NS.Config:Show()
	NS.Config:ShowPage("general")
	return NS.Config:GetPage("general").instance
end

local function findButton(page, text)
	for _, control in ipairs(page.controls) do
		if control.kind == "button" then
			for _, child in ipairs(control.frame.__children) do
				if child.__kind == "FontString" and child.__text == text then
					return control.frame
				end
			end
		end
	end
	return nil
end

local function soundIDs()
	local ids = {}
	for _, s in ipairs(Mock.sounds) do
		ids[#ids + 1] = s.id
	end
	return ids
end

local function has(list, value)
	for _, v in ipairs(list) do
		if v == value then
			return true
		end
	end
	return false
end

test("a button press can execute: sound, blood and a battle line", function()
	WM.Boot()
	local page = openGeneral()
	NS.DB:Set("general.flair.chance", 100)
	local button = findButton(page, NS.L.DIAGNOSTICS)
	check(button, "diagnostics button")
	button.__scripts.OnClick(button)
	local splash = NS.Flair.splash
	check(splash and splash:IsShown(), "blood splash shown")
	check(has(soundIDs(), 165951), "execute sound")
	local line = splash.text:GetText()
	check(line ~= nil and line ~= "", "battle line")
	eq(splash.__scripts.OnUpdate ~= nil, true, "animating")
	Mock.Advance(1.5)
	check(not splash:IsShown(), "gone after the effect")
	check(splash.__scripts.OnUpdate == nil, "no OnUpdate left")
	eq(splash.__mouse, false, "never catches clicks")
end)

test("execute chance 0 never triggers on ordinary buttons", function()
	WM.Boot()
	local page = openGeneral()
	NS.DB:Set("general.flair.chance", 0)
	for _ = 1, 20 do
		local button = findButton(page, NS.L.DIAGNOSTICS)
		button.__scripts.OnClick(button)
	end
	check(not (NS.Flair.splash and NS.Flair.splash:IsShown()), "no splash")
	check(not has(soundIDs(), 165951), "no execute sound")
end)

test("a confirmed destructive button always executes", function()
	WM.Boot()
	local page = openGeneral()
	NS.DB:Set("general.flair.chance", 0)
	local button = findButton(page, NS.L.RESET_ALL)
	check(button, "reset button")
	button.__scripts.OnClick(button) -- arms
	check(not (NS.Flair.splash and NS.Flair.splash:IsShown()), "nothing on the first click")
	button.__scripts.OnClick(button) -- confirms
	check(NS.Flair.splash and NS.Flair.splash:IsShown(), "execute on the confirmed reset")
end)

test("closing the settings sounds a battle cry", function()
	WM.Boot()
	openGeneral()
	NS.Config:Hide()
	check(has(soundIDs(), 118563), "war horn")
	local shout = NS.Flair.shout
	check(shout and shout:IsShown(), "battle cry shown")
	Mock.Advance(2)
	check(not shout:IsShown(), "fades away")
	check(shout.__scripts.OnUpdate == nil, "no OnUpdate left")
	local before = #Mock.sounds
	NS.Config:Hide()
	eq(#Mock.sounds, before, "nothing when already closed")
	NS.DB:Set("general.flair.closeShout", false)
	openGeneral()
	NS.Config:Hide()
	eq(#Mock.sounds, before, "battle cry can be turned off")
end)

test("the Sound switch silences the effects, the switch turns them off", function()
	WM.Boot()
	local page = openGeneral()
	NS.DB:Set("general.sounds", false)
	NS.DB:Set("general.flair.chance", 100)
	local button = findButton(page, NS.L.DIAGNOSTICS)
	button.__scripts.OnClick(button)
	check(NS.Flair.splash:IsShown(), "still splashes")
	eq(#Mock.sounds, 0, "but silently")
	NS.Flair.splash:Hide()
	NS.DB:Set("general.flair.enabled", false)
	button.__scripts.OnClick(button)
	check(not NS.Flair.splash:IsShown(), "no effect when off")
	NS.Config:Hide()
	check(not (NS.Flair.shout and NS.Flair.shout:IsShown()), "no battle cry when off")
end)

test("the try button executes once", function()
	WM.Boot()
	local page = openGeneral()
	NS.DB:Set("general.flair.chance", 100)
	local button = findButton(page, NS.L.FLAIR_TRY)
	button.__scripts.OnClick(button)
	local count = 0
	for _, s in ipairs(Mock.sounds) do
		if s.id == 165951 then
			count = count + 1
		end
	end
	eq(count, 1, "one execute, not two")
end)
