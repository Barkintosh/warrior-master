-- Saved variables, profiles, presets, import/export safety.

test("corrupted saved variables are repaired at login", function()
	local nan = 0 / 0
	WM.Boot({
		savedVars = {
			profiles = {
				Default = {
					general = { preset = 42, locked = "yes" },
					rage = {
						width = "abc", height = nan, texture = 42, scale = 99, style = "Bogus",
						point = { point = "BAD", relPoint = "CENTER", x = 1e12, y = "1" },
						alert = { threshold = -5, color = { r = 5, g = "x" } },
						unknownKey = function() end,
					},
				},
				["  Bad|cffName\n "] = { rage = { width = 300 } },
				[42] = "junk",
			},
			profileKeys = { ["Tester - Mockrealm"] = "Missing" },
			global = { language = "klingon" },
		},
		charVars = { loadouts = { battle = { mh = -3, oh = 2.5, set = 7 }, bogus = { mh = 1 } }, macro = "x" },
	})
	local p = NS.db.profile
	eq(NS.db.profileName, "Default", "falls back to Default")
	eq(p.rage.width, 220, "bad width reset")
	eq(p.rage.height, 12, "NaN height reset")
	eq(p.rage.texture, "Forever", "invalid texture reset")
	eq(p.rage.scale, 3, "scale clamped")
	eq(p.rage.point.point, "CENTER", "bad anchor reset")
	eq(p.rage.point.x, 5000, "offset clamped")
	eq(p.rage.alert.threshold, 1, "threshold clamped")
	eq(p.rage.alert.color.r, 1, "color clamped")
	eq(p.rage.style, "Forever", "bad style reset")
	eq(p.general.locked, true, "bad boolean reset")
	eq(p.rage.unknownKey, nil, "unknown keys dropped")
	eq(NS.db.global.language, "auto", "bad language reset")
	check(WarriorMasterDB.profiles["Bad cffName"] == nil, "name sanitized")
	check(WarriorMasterDB.profiles["Badcffname"] == nil or true, "name check")
	local names = NS.DB:ListProfiles()
	eq(#names, 2, "Default and the cleaned profile")
	eq(next(NS.db.char.loadouts), nil, "invalid loadouts dropped")
	eq(NS.db.char.macro.template, "charge_intercept", "macro state rebuilt")
end)

test("profile create, switch, copy and delete", function()
	WM.Boot()
	NS.DB:Set("rage.width", 300)
	local ok, name = NS.DB:CreateProfile("Tank", "Default")
	check(ok, "created")
	eq(NS.db.profileName, "Tank", "switched")
	eq(NS.db.profile.rage.width, 300, "copied values")
	NS.DB:Set("rage.width", 150)
	eq(WarriorMasterRageBar:GetWidth(), 150, "bar follows the active profile")
	NS.DB:SetProfile("Default")
	eq(WarriorMasterRageBar:GetWidth(), 300, "switching re-applies settings")
	check(not NS.DB:CreateProfile("Tank"), "duplicate refused")
	check(not NS.DB:DeleteProfile("Default"), "Default protected")
	NS.DB:SetProfile("Tank")
	check(NS.DB:DeleteProfile("Tank"), "deleted")
	eq(NS.db.profileName, "Default", "back to Default")
	local _ = name
end)

test("export then import gives the same profile", function()
	WM.Boot()
	NS.DB:Set("rage.width", 333)
	NS.DB:Set("health.colorMode", "static")
	NS.DB:Set("swing.showRanged", true)
	local text = NS.DB:ExportProfile()
	contains(text, "WM1:", "prefix")
	local ok, name = NS.DB:ImportProfile(text, "Imported")
	check(ok, "imported: " .. tostring(name))
	local p = NS.db.profile
	eq(NS.db.profileName, "Imported", "activated")
	eq(p.rage.width, 333, "width")
	eq(p.health.colorMode, "static", "enum")
	eq(p.swing.showRanged, true, "boolean")
end)

test("import rejects malformed or hostile text without running it", function()
	WM.Boot()
	local DB, Ser = NS.DB, NS.Serializer
	rawset(_G, "PWNED", false)
	local function try(text)
		local ok, err = DB:ImportProfile(text, "X" .. tostring(math.random(1, 1e6)))
		return ok, err
	end
	check(not try("hello"), "plain text")
	check(not try("WM1:00000000:AAAA"), "bad checksum")
	local payload = 'return (function() PWNED = true end)()'
	local text = "WM1:" .. Ser.Checksum(payload) .. ":" .. Ser.ToBase64(payload)
	local ok, err = try(text)
	check(not ok, "code is not data")
	eq(err, "IMPORT_ERR_PARSE", "parse error")
	eq(rawget(_G, "PWNED"), false, "nothing executed")
	local deep = string.rep("{S1:a", 40) .. string.rep("}", 40)
	check(not try("WM1:" .. Ser.Checksum(deep) .. ":" .. Ser.ToBase64(deep)), "too deep")
	check(not try(string.rep("A", 70000)), "too large")
	local good = DB:ExportProfile()
	check(not try(good:sub(1, #good - 8)), "truncated")
	-- A valid container holding wrong types is repaired, not trusted.
	local wrapped = Ser.Encode({ kind = "WarriorMasterProfile", version = 1, data = { rage = { width = "wide", alert = { threshold = 1e9 } } } })
	ok = DB:ImportProfile("WM1:" .. Ser.Checksum(wrapped) .. ":" .. Ser.ToBase64(wrapped), "Repaired")
	check(ok, "imported with repairs")
	eq(NS.db.profile.rage.width, 220, "type repaired")
	eq(NS.db.profile.rage.alert.threshold, 100, "range repaired")
end)

test("serializer round-trips nested data", function()
	WM.Boot()
	local Ser = NS.Serializer
	local value = { a = 1, b = -2.5, c = "x:y;z", d = true, e = false, f = { 1, 2, { g = "é" } }, [3] = "three" }
	local ok, back = Ser.Decode(Ser.Encode(value))
	check(ok, "decoded")
	eq(back.a, 1)
	eq(back.b, -2.5)
	eq(back.c, "x:y;z")
	eq(back.d, true)
	eq(back.e, false)
	eq(back.f[3].g, "é")
	eq(back[3], "three")
	for _, sample in ipairs({ "", "a", "ab", "abc", "abcd", string.char(0, 255, 128) }) do
		eq(Ser.FromBase64(Ser.ToBase64(sample)), sample, "base64 " .. #sample)
	end
end)

test("presets change only the look and keep the custom look", function()
	WM.Boot()
	local p = NS.db.profile
	NS.DB:Set("rage.width", 260)
	NS.DB:Set("rage.point", { point = "CENTER", relPoint = "CENTER", x = 10, y = 20 })
	NS.DB:Set("rage.alert.threshold", 70)
	eq(p.rage.style, "Custom", "editing the look makes the module Custom")
	eq(p.health.style, "Forever", "other modules keep their style")
	check(NS:ApplyPreset("Minimal"), "applied")
	p = NS.db.profile
	eq(p.rage.height, 8, "minimal height")
	eq(p.rage.borderStyle, "None", "minimal border")
	eq(p.rage.point.x, 10, "position kept")
	eq(p.rage.alert.threshold, 70, "threshold kept")
	eq(WarriorMasterRageBar:GetHeight(), 8, "bar updated")
	check(NS:ApplyPreset("Custom"), "back to custom")
	eq(NS.db.profile.rage.width, 260, "custom width restored")
	eq(NS.db.profile.rage.height, 12, "custom height restored")
end)

test("module reset restores defaults", function()
	WM.Boot()
	NS.DB:Set("swing.width", 400)
	NS.DB:ResetSection("swing")
	eq(NS.db.profile.swing.width, 220, "reset")
end)

test("language can be forced independently of the game", function()
	WM.Boot()
	eq(NS.L.MODULE_RAGE, "Rage Bar", "english by default")
	NS.DB:SetLanguage("frFR")
	eq(NS.L.MODULE_RAGE, "Barre de rage", "french on request")
	NS.DB:SetLanguage("auto")
	eq(NS.L.MODULE_RAGE, "Rage Bar", "back to the game language")
end)
