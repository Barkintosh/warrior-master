-- Visual styles: Forever defaults, complete and partial application, media.

local function boot(opts)
	WM.Boot(opts)
	return NS.Styles, NS.db.profile
end

local function same(a, b)
	if type(a) ~= type(b) then
		return false
	end
	if type(a) ~= "table" then
		return a == b
	end
	for k, v in pairs(a) do
		if not same(v, b[k]) then
			return false
		end
	end
	for k in pairs(b) do
		if a[k] == nil then
			return false
		end
	end
	return true
end

test("a new profile is exactly the WoW Forever style", function()
	local Styles, p = boot()
	for _, section in ipairs(Styles.SECTIONS) do
		eq(p[section].style, "Forever", section .. " style")
		for _, part in ipairs(Styles.PARTS) do
			for key, value in pairs(Styles.Get("Forever", section, part)) do
				check(same(NS.Util.GetPath(p[section], key), value), section .. "." .. key .. " is the Forever value")
			end
		end
	end
	eq(p.rage.colorStatic.r, 1, "Blizzard rage red")
	eq(p.rage.colorStatic.g, 0, "Blizzard rage red")
	eq(p.health.texture, "Forever", "personal resource bar texture")
	eq(p.swing.borderStyle, "ForeverFrame", "native swing frame")
	eq(p.stance.buttonStyle, "Forever", "action button frame")
end)

test("every style defines every part, and every value is valid", function()
	local Styles = boot()
	local S = NS.Schema
	eq(#Styles.ORDER, 11, "eleven styles")
	for _, name in ipairs(Styles.ORDER) do
		for _, section in ipairs(Styles.SECTIONS) do
			for _, part in ipairs(Styles.PARTS) do
				local values = Styles.Get(name, section, part)
				for _, key in ipairs(Styles.Keys(section, part)) do
					local value = values[key]
					check(value ~= nil, name .. " defines " .. section .. "." .. key)
					local leaf = S.GetLeaf(S.profile, section .. "." .. key)
					check(leaf, "schema knows " .. section .. "." .. key)
					local stats = { fixed = 0 }
					S.SanitizeLeaf(leaf, value, stats)
					eq(stats.fixed, 0, name .. " " .. section .. "." .. key .. " is within range")
				end
			end
		end
		check(NS.L[Styles.LABEL_KEYS[name]] ~= Styles.LABEL_KEYS[name], name .. " has a name")
	end
end)

test("every style renders on every module without errors", function()
	local Styles = boot()
	NS.TestMode:SetActive(true)
	for _, name in ipairs(Styles.ORDER) do
		check(NS:ApplyPreset(name), name .. " applied")
		Mock.Advance(0.2)
		eq(NS.db.profile.rage.style, name, name .. " recorded")
	end
	NS.TestMode:SetActive(false)
end)

test("apply only some parts of a style", function()
	local _, p = boot()
	check(NS:ApplyStyle("Ember", nil, { colors = true }), "colors only")
	p = NS.db.profile
	eq(p.rage.texture, "Forever", "texture kept")
	eq(p.rage.font, "Friz", "font kept")
	eq(p.rage.colorMode, "gradient", "Ember color mode")
	near(p.rage.colorHigh.g, 0.6, 1e-9, "Ember colors")
	eq(p.rage.style, "Custom", "a partial style makes the module Custom")
	check(NS:ApplyStyle("Gladiator", nil, { fonts = true, sizes = true }), "fonts and sizes")
	eq(NS.db.profile.health.font, "Morpheus", "Gladiator font")
	eq(NS.db.profile.health.height, 20, "Gladiator size")
	near(NS.db.profile.rage.colorHigh.g, 0.6, 1e-9, "earlier colors kept")
	check(not NS:ApplyStyle("Frost", nil, {}), "nothing selected does nothing")
end)

test("apply a style to one module only", function()
	local _, p = boot()
	check(NS:ApplyStyle("Frost", { "rage" }), "rage only")
	p = NS.db.profile
	eq(p.rage.style, "Frost", "rage is Frost")
	eq(p.health.style, "Forever", "health untouched")
	eq(p.health.texture, "Forever", "health texture untouched")
	eq(p.rage.borderStyle, "Pixel", "Frost border on rage")
	eq(WarriorMasterRageBar.bg.__atlas, nil, "rage bar redrawn without the atlas background")
	eq(WarriorMasterHealthBar.bg.__atlas, "UI-HUD-CoolDownManager-Bar-BG", "health bar still Forever")
end)

test("Custom brings back each module's own look", function()
	local _, p = boot()
	NS.DB:Set("health.width", 333)
	NS.DB:Set("health.texture", "Raid")
	eq(NS.db.profile.health.style, "Custom", "custom")
	NS:ApplyPreset("Berserker")
	eq(NS.db.profile.health.width, 240, "Berserker width")
	NS:ApplyPreset("Void")
	NS:ApplyStyle("Custom", { "health" })
	p = NS.db.profile
	eq(p.health.width, 333, "own width back")
	eq(p.health.texture, "Raid", "own texture back")
	eq(p.rage.style, "Void", "other modules keep their style")
end)

test("only styled settings switch a module to Custom", function()
	boot()
	NS.DB:Set("rage.alert.threshold", 80)
	eq(NS.db.profile.rage.style, "Forever", "threshold is not a style setting")
	NS.DB:Set("rage.point", { point = "CENTER", relPoint = "CENTER", x = 5, y = 5 })
	eq(NS.db.profile.rage.style, "Forever", "position is not a style setting")
	NS.DB:Set("rage.alert.color", { r = 0, g = 1, b = 0, a = 1 })
	eq(NS.db.profile.rage.style, "Custom", "glow color is a style setting")
end)

test("Forever style draws Blizzard's atlases", function()
	boot({ state = { inventory = { [16] = 1001, [17] = 2002 } } })
	local rage = WarriorMasterRageBar
	eq(rage.sb.__texture, "UI-HUD-CoolDownManager-Bar", "resource bar fill")
	eq(rage.bg.__atlas, "UI-HUD-CoolDownManager-Bar-BG", "resource bar background")
	local swing = NS.modules.swing
	eq(swing.bars.mh.sb.__texture, "ui-swingtimerbar-filling-mainhand", "main-hand fill")
	eq(swing.bars.oh.sb.__texture, "ui-swingtimerbar-filling-offhand", "off-hand fill")
	eq(swing.bars.mh.frameTex.__atlas, "ui-swingtimerbar-frame", "swing frame")
	eq(swing.bars.mh.spark.__atlas, "ui-swingtimerbar-pip", "swing pip")
	local btn = WarriorMasterStanceButton1
	eq(btn.frameTex.__atlas, "UI-HUD-ActionBar-IconFrame", "action button frame")
	check(btn.icon.__masks and btn.icon.__masks[btn.mask], "icon masked")
	NS.DB:Set("stance.buttonStyle", "Pixel")
	check(not btn.frameTex:IsShown(), "frame hidden in Pixel style")
	check(not btn.icon.__masks[btn.mask], "mask removed")
	check(btn.border:IsShown(), "thin border shown")
end)

test("switching away from an atlas border uses the background color", function()
	boot()
	NS.DB:Set("rage.borderStyle", "Pixel")
	local bar = WarriorMasterRageBar
	eq(bar.bg.__atlas, nil, "no atlas")
	near(bar.bg.__color[4], NS.db.profile.rage.bgColor.a, 1e-9, "background color used")
	check(NS.IsAtlasBorder("Forever") and NS.IsAtlasBorder("ForeverFrame"), "atlas styles known")
	check(not NS.IsAtlasBorder("Pixel"), "pixel is not an atlas style")
end)

test("SharedMedia textures and fonts are offered when present", function()
	local paths = { statusbar = { Shiny = "Interface\\Addons\\X\\shiny.tga" }, font = { Bold = "Interface\\Addons\\X\\bold.ttf" } }
	local lib = {}
	function lib:List(kind)
		local out = {}
		for name in pairs(paths[kind] or {}) do
			out[#out + 1] = name
		end
		return out
	end
	function lib:Fetch(kind, name)
		return paths[kind] and paths[kind][name]
	end
	rawset(_G, "LibStub", function(major, silent)
		return major == "LibSharedMedia-3.0" and lib or nil
	end)
	boot()
	local Media = NS.Media
	local found = false
	for _, item in ipairs(Media.ListTextures()) do
		found = found or item.value == "lsm:Shiny"
	end
	check(found, "shared texture listed")
	eq(Media.ResolveTexture("lsm:Shiny"), "Interface\\Addons\\X\\shiny.tga", "shared texture resolved")
	eq(Media.GetFont("lsm:Bold"), "Interface\\Addons\\X\\bold.ttf", "shared font resolved")
	eq(Media.ResolveTexture("lsm:Missing"), "UI-HUD-CoolDownManager-Bar", "missing media falls back")
	NS.DB:Set("rage.texture", "lsm:Shiny")
	eq(WarriorMasterRageBar.sb.__texture, "Interface\\Addons\\X\\shiny.tga", "bar uses it")
end)

test("without SharedMedia only built-in media is listed", function()
	boot()
	local count = 0
	for _, item in ipairs(NS.Media.ListTextures()) do
		check(not item.value:find("lsm:", 1, true), "no shared entries")
		count = count + 1
	end
	eq(count, 8, "eight built-in textures")
	eq(#NS.Media.ListFonts(), 10, "ten built-in fonts")
end)

test("style picker on the General page applies the chosen parts and modules", function()
	boot()
	NS.DB:Set("general.styleChoice", "Frost")
	NS.DB:Set("general.styleTarget", "swing")
	NS.DB:Set("general.styleParts.sizes", false)
	NS.Config:Show()
	NS.Config:ShowPage("general")
	local page = NS.Config:GetPage("general").instance
	for _, control in ipairs(page.controls) do
		for _, child in ipairs(control.frame.__children or {}) do
			if child.__kind == "FontString" and child.__text == NS.L.STYLE_APPLY then
				control.frame.__scripts.OnClick(control.frame)
			end
		end
	end
	local p = NS.db.profile
	eq(p.swing.borderStyle, "Pixel", "Frost look on swing")
	eq(p.swing.height, 20, "sizes left alone")
	eq(p.rage.borderStyle, "Forever", "rage untouched")
	eq(p.swing.style, "Custom", "partial style is Custom")
end)
