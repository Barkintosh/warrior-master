-- Cast bar driven by UNIT_SPELLCAST_* and UnitCastingInfo / UnitChannelInfo.

local function cast()
	return NS.modules.cast
end

local function frame()
	return WarriorMasterCastBar
end

local function updating()
	return cast().updater.__scripts.OnUpdate ~= nil
end

test("a cast shows its name, icon and progress, then fills and fades", function()
	WM.Boot()
	check(not frame():IsShown(), "hidden while not casting")
	local guid = Mock.StartCast("Hearthstone", 10)
	check(frame():IsShown(), "shown while casting")
	eq(cast().bar.label:GetText(), "Hearthstone", "spell name")
	eq(cast().icon.__texture, 134414, "spell icon")
	check(updating(), "OnUpdate during the cast")
	Mock.Advance(5)
	near(cast().bar.sb.__values.value, 0.5, 0.02, "half way")
	contains(cast().bar.text:GetText(), "5.", "remaining time")
	Mock.state.cast = nil
	Mock.FireEvent("UNIT_SPELLCAST_STOP", "player", guid, 8690)
	near(cast().bar.sb.__values.value, 1, 1e-9, "full bar when finished")
	check(frame():IsShown(), "stays a moment")
	Mock.Advance(1)
	check(not frame():IsShown(), "faded out")
	check(not updating(), "OnUpdate stopped")
	eq(cast().stats.casts, 1, "counted")
end)

test("a channel empties, and an interrupted channel shows it", function()
	WM.Boot()
	Mock.StartChannel("First Aid", 8)
	Mock.Advance(2)
	near(cast().bar.sb.__values.value, 0.75, 0.02, "channel bar empties")
	Mock.state.channel = nil
	Mock.FireEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player", "Cast-3-0-0-0-0", 746, "Creature-0-1-2-3-4-5")
	eq(cast().bar.label:GetText(), "Interrupted", "interrupted text")
	eq(cast().ending.state, "failed", "failure look")
	Mock.Advance(1)
	check(not frame():IsShown(), "gone afterwards")
end)

test("another spell failing mid-cast does not stop the bar", function()
	WM.Boot()
	local guid = Mock.StartCast("Hearthstone", 10)
	Mock.FireEvent("UNIT_SPELLCAST_FAILED", "player", "Cast-3-0-0-0-999", 78)
	check(cast().current ~= nil, "still casting")
	eq(cast().bar.label:GetText(), "Hearthstone", "name unchanged")
	Mock.state.cast = nil
	Mock.FireEvent("UNIT_SPELLCAST_INTERRUPTED", "player", guid, 8690)
	eq(cast().bar.label:GetText(), "Interrupted", "our cast interrupted")
	Mock.FireEvent("UNIT_SPELLCAST_STOP", "player", guid, 8690)
	eq(cast().ending.state, "failed", "the stop after an interrupt keeps the failure")
end)

test("a failure without readable GUIDs only counts when nothing is cast any more", function()
	WM.Boot()
	Mock.StartCast("Hearthstone", 10)
	cast().current.castID = nil
	Mock.FireEvent("UNIT_SPELLCAST_FAILED", "player", Mock.Secret("x"), 78)
	check(cast().current ~= nil, "ignored while UnitCastingInfo still reports the cast")
	Mock.state.cast = nil
	Mock.FireEvent("UNIT_SPELLCAST_FAILED", "player", Mock.Secret("x"), 8690)
	eq(cast().bar.label:GetText(), "Failed", "failed text")
end)

test("hidden cast timing is never guessed", function()
	WM.Boot()
	Mock.StartCast("Hearthstone", 10, { secret = true })
	check(not frame():IsShown(), "no bar")
	eq(cast().stats.secret, 1, "counted as hidden")
	check(not updating(), "nothing running")
	eq(#NS.errors, 0, "no error from secret values")
end)

test("pushback updates the end time", function()
	WM.Boot()
	Mock.StartCast("Hearthstone", 10)
	Mock.Advance(4)
	Mock.state.cast.finish = Mock.state.cast.finish + 1000
	Mock.FireEvent("UNIT_SPELLCAST_DELAYED", "player", Mock.state.cast.castID, 8690)
	near(cast().current.finish - GetTime(), 7, 0.03, "one second pushed back")
end)

test("a cast already running at login or after a loading screen is picked up", function()
	WM.Boot()
	local now = GetTime() * 1000
	Mock.state.cast = { name = "Hearthstone", icon = 1, start = now - 2000, finish = now + 8000, castID = "Cast-x" }
	Mock.FireEvent("PLAYER_ENTERING_WORLD", false, false)
	check(frame():IsShown(), "shown")
	near(cast().bar.sb.__values.value, 0.2, 0.02, "progress already made")
end)

test("the cast bar ends by itself if the stop event never comes", function()
	WM.Boot()
	Mock.StartCast("Hearthstone", 1)
	Mock.Advance(2)
	check(not frame():IsShown(), "hidden after the cast time")
	check(not updating(), "OnUpdate stopped")
end)

test("disabled cast bar ignores casts", function()
	WM.Boot()
	NS.DB:Set("cast.enabled", false)
	Mock.StartCast("Hearthstone", 10)
	check(not frame():IsShown(), "hidden")
	eq(cast().stats.casts, 0, "not counted")
end)

test("preview mode simulates casts and channels, unlocked frames show a placeholder", function()
	WM.Boot()
	NS.TestMode:SetActive(true)
	Mock.Advance(0.5)
	check(frame():IsShown(), "preview cast shown")
	eq(cast().bar.label:GetText(), NS.L.CAST_PREVIEW, "preview name")
	Mock.Advance(3.8)
	check(cast().preview and cast().preview.channel, "then a channel")
	NS.TestMode:SetActive(false)
	check(not frame():IsShown(), "preview ends with preview mode")
	NS.Movers:SetShown(true)
	check(frame():IsShown(), "placeholder to move it")
	eq(cast().bar.label:GetText(), NS.L.MODULE_CAST, "placeholder text")
	NS.Movers:SetShown(false)
	check(not frame():IsShown(), "hidden again")
end)

test("Forever style uses the game's casting bar art for each state", function()
	WM.Boot()
	Mock.StartCast("Hearthstone", 10)
	eq(cast().bar.sb.__atlas or cast().bar.sb.__texture, "ui-castingbar-filling-standard", "cast fill")
	Mock.state.cast = nil
	Mock.FireEvent("UNIT_SPELLCAST_INTERRUPTED", "player", Mock.state.cast and Mock.state.cast.castID or nil, 8690)
	eq(cast().bar.sb.__atlas or cast().bar.sb.__texture, "ui-castingbar-interrupted", "interrupted fill")
	Mock.StartChannel("First Aid", 5)
	eq(cast().bar.sb.__atlas or cast().bar.sb.__texture, "ui-castingbar-filling-channel", "channel fill")
	eq(cast().bar.frameTex.__atlas, "ui-castingbar-frame", "native frame")
end)

test("every style has a cast bar look and applies to it", function()
	WM.Boot()
	for _, name in ipairs(NS.Styles.ORDER) do
		check(NS:ApplyStyle(name, { "cast" }), name .. " applied")
		eq(NS.db.profile.cast.style, name, name .. " recorded")
	end
	NS:ApplyStyle("Frost", { "cast" })
	near(NS.db.profile.cast.colorCast.b, 1, 1e-9, "themed cast color")
	eq(#NS.errors, 0, "no errors")
end)
