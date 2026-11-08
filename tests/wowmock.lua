--[[
Offline mock of the WoW Forever (1.60.1, interface 16001) addon API, used
only by the test suite. It never talks to the game.

What it simulates
- Frames, regions, status bars, font strings, animations, scripts, events,
  timers and OnUpdate, driven by a fake clock.
- Widget methods: unknown PascalCase methods raise an error unless they are
  documented for this client (tests/data/forever_api.lua) or listed in
  EXTRA_METHODS (Blizzard Lua mixins verified in the client's UI code).
- Secret values: Mock.Secret(v) returns an opaque value; any arithmetic,
  comparison, concatenation or tostring on it raises an error, like addon
  code touching a secret in the real client. Widget setters documented as
  accepting secrets store them.
- Combat lockdown: protected operations on secure frames (and their
  ancestors) raise "ADDON_ACTION_BLOCKED" while Mock.state.lockdown is true.
- Global writes are recorded so tests can verify the addon's footprint.

Known limits (documented in TESTING.md): type(secret) is "table" here but
"number"/"string" in game; equality with a secret does not error here.
]]

Mock = {
	state = {},
	events = {},
	frames = {},
	timers = {},
	chat = {},
	errors = {},
	blocked = {},
	sounds = {},
	cvars = { showSwingTimer = "1" },
	macros = {},
	globalWrites = {},
	clock = 1000,
}

local API = FOREVER_API
local DOC_METHODS = API and API.methods or {}

-- Blizzard Lua mixin methods (not in the generated C API docs).
local EXTRA_METHODS = {
	-- BackdropTemplateMixin (Blizzard_SharedXML/Backdrop.lua)
	SetBackdrop = true, SetBackdropColor = true, SetBackdropBorderColor = true,
	-- CooldownFrameTemplate / Cooldown widget
	SetHideCountdownNumbers = true,
	-- ColorPickerFrameMixin (Blizzard_ColorPickerFrame)
	SetupColorPickerAndShow = true, GetColorRGB = true, GetColorAlpha = true,
	-- GameTooltip
	SetOwner = true, SetSpellByID = true, AddLine = true, SetBagItem = true, SetInventoryItem = true,
}

local function methodExists(name)
	return DOC_METHODS[name] or EXTRA_METHODS[name]
end

-- Secret values ------------------------------------------------------------------------------
local secretRegistry = setmetatable({}, { __mode = "k" })
local function secretError()
	error("attempt to use a secret value in addon code", 2)
end
local SecretMeta = {
	__add = secretError, __sub = secretError, __mul = secretError, __div = secretError,
	__mod = secretError, __pow = secretError, __unm = secretError, __concat = secretError,
	__lt = secretError, __le = secretError, __len = secretError, __call = secretError,
	__index = function()
		secretError()
	end,
	__newindex = secretError,
	__tostring = function()
		error("attempt to convert a secret value to a string", 2)
	end,
}

function Mock.Secret(value)
	local s = setmetatable({}, SecretMeta)
	secretRegistry[s] = { value = value }
	return s
end

function Mock.Unwrap(value)
	local entry = secretRegistry[value]
	if entry then
		return entry.value, true
	end
	return value, false
end

function issecretvalue(value)
	return type(value) == "table" and secretRegistry[value] ~= nil
end

local function maybeSecret(value, secret)
	if secret then
		return Mock.Secret(value)
	end
	return value
end

-- Clock and timers ---------------------------------------------------------------------------
function GetTime()
	return Mock.clock
end

C_Timer = {}
function C_Timer.After(delay, fn)
	Mock.timers[#Mock.timers + 1] = { at = Mock.clock + delay, fn = fn }
end
function C_Timer.NewTicker(interval, fn)
	local ticker = { cancelled = false }
	function ticker:Cancel()
		self.cancelled = true
	end
	local function schedule()
		C_Timer.After(interval, function()
			if not ticker.cancelled then
				fn(ticker)
				schedule()
			end
		end)
	end
	schedule()
	return ticker
end

-- Frames ------------------------------------------------------------------------------------------
local Object = {}

local function newObject(kind, name, parent)
	local o = {
		__kind = kind,
		__name = name,
		__parent = parent,
		__children = {},
		__shown = true,
		__alpha = 1,
		__scale = 1,
		__width = 0,
		__height = 0,
		__points = {},
		__scripts = {},
		__attributes = {},
		__events = {},
		__unitEvents = {},
		__values = { min = 0, max = 1, value = 0 },
		__text = "",
	}
	if parent then
		parent.__children[#parent.__children + 1] = o
	end
	return setmetatable(o, Object)
end

local PROTECTED_OPS = {
	SetAttribute = true, Show = true, Hide = true, SetShown = true, SetPoint = true,
	ClearAllPoints = true, SetAllPoints = true, SetSize = true, SetWidth = true,
	SetHeight = true, SetScale = true, SetParent = true, RegisterForClicks = true,
	StartMoving = true, StopMovingOrSizing = true, SetUserPlaced = true, Click = true,
}

local function isProtectedFamily(o)
	if o.__protected then
		return true
	end
	local stack = { o }
	while #stack > 0 do
		local node = table.remove(stack)
		for _, child in ipairs(node.__children) do
			if child.__protected then
				return true
			end
			stack[#stack + 1] = child
		end
	end
	return false
end

local function noop()
end

-- Every PascalCase method call is checked against the client's documented
-- widget API, whether or not the mock implements it.
Object.__index = function(self, key)
	if type(key) ~= "string" or not key:match("^%u") then
		return nil
	end
	if not methodExists(key) and not rawget(Object, "__extra_" .. key) then
		error("unknown widget method for this client: " .. key, 2)
	end
	if PROTECTED_OPS[key] and Mock.state.lockdown and isProtectedFamily(self) then
		return function()
			Mock.blocked[#Mock.blocked + 1] = key
			error("ADDON_ACTION_BLOCKED: " .. key .. " on a protected frame in combat", 2)
		end
	end
	return rawget(Object, key) or noop
end

-- Region / frame basics
function Object:GetName() return self.__name end
function Object:GetParent() return self.__parent end
function Object:GetObjectType() return self.__kind end
function Object:IsObjectType(kind) return self.__kind == kind end
function Object:SetParent(parent) self.__parent = parent end
function Object:Show() self.__shown = true end
function Object:Hide()
	local was = self.__shown
	self.__shown = false
	if was and self.__scripts.OnHide then
		self.__scripts.OnHide(self)
	end
end
function Object:SetShown(shown) if shown then self:Show() else self:Hide() end end
function Object:IsShown() return self.__shown end
function Object:IsVisible()
	local node = self
	while node do
		if not node.__shown then
			return false
		end
		node = node.__parent
	end
	return true
end
function Object:SetAlpha(alpha) self.__alpha = alpha end
function Object:GetAlpha() return self.__alpha end
function Object:SetScale(scale) self.__scale = scale end
function Object:GetScale() return self.__scale end
function Object:GetEffectiveScale()
	local scale, node = 1, self
	while node do
		scale = scale * (node.__scale or 1)
		node = node.__parent
	end
	return scale
end
function Object:SetSize(w, h) self.__width, self.__height = w, h end
function Object:SetWidth(w) self.__width = w end
function Object:SetHeight(h) self.__height = h end
function Object:GetWidth() return self.__width end
function Object:GetHeight() return self.__height end
function Object:GetSize() return self.__width, self.__height end
function Object:SetPoint(...)
	local args = { ... }
	for i = 2, #args do
		if issecretvalue(args[i]) then
			error("SetPoint does not accept secret values", 2)
		end
	end
	self.__points[#self.__points + 1] = args
end
function Object:ClearAllPoints() self.__points = {} end
function Object:SetAllPoints() self.__points = { { "ALL" } } end
function Object:GetNumPoints() return #self.__points end
function Object:GetPoint(i)
	local p = self.__points[i or 1]
	if p then
		return unpack(p)
	end
end
function Object:GetCenter() return 500, 400 end
function Object:GetLeft() return 500 - self.__width / 2 end
function Object:GetRight() return 500 + self.__width / 2 end
function Object:GetTop() return 400 + self.__height / 2 end
function Object:GetBottom() return 400 - self.__height / 2 end
function Object:SetClampedToScreen(clamped) self.__clamped = clamped end
function Object:SetFrameStrata(s) self.__strata = s end
function Object:GetFrameStrata() return self.__strata or "MEDIUM" end
function Object:SetFrameLevel(l) self.__level = l end
function Object:GetFrameLevel() return self.__level or 1 end
function Object:SetScript(name, fn) self.__scripts[name] = fn end
function Object:GetScript(name) return self.__scripts[name] end
function Object:HookScript(name, fn)
	local prev = self.__scripts[name]
	self.__scripts[name] = function(...)
		if prev then
			prev(...)
		end
		fn(...)
	end
end
function Object:EnableMouse(e) self.__mouse = e end
function Object:EnableMouseWheel(e) self.__wheel = e end
function Object:EnableKeyboard(e) self.__keyboard = e end
function Object:SetPropagateKeyboardInput(propagate)
	-- Addons cannot change keyboard propagation during combat.
	if Mock.state.lockdown then
		Mock.blocked[#Mock.blocked + 1] = "SetPropagateKeyboardInput"
		error("ADDON_ACTION_BLOCKED: SetPropagateKeyboardInput in combat", 2)
	end
	self.__propagate = propagate
end
function Object:SetMovable(m) self.__movable = m end
function Object:SetToplevel() end
function Object:RegisterForDrag() end
function Object:RegisterForClicks(...) self.__clicks = { ... } end
function Object:StartMoving() self.__moving = true end
function Object:StopMovingOrSizing() self.__moving = false end
function Object:SetUserPlaced() end
function Object:IsProtected() return self.__protected == true end

-- Events
function Object:RegisterEvent(event)
	if API and API.events and not API.events[event] and not Mock.extraEvents[event] then
		error("Attempt to register unknown event \"" .. tostring(event) .. "\"", 2)
	end
	self.__events[event] = true
	Mock.events[event] = Mock.events[event] or {}
	Mock.events[event][self] = true
end
function Object:RegisterUnitEvent(event, unit)
	self:RegisterEvent(event)
	self.__unitEvents[event] = unit
end
function Object:UnregisterEvent(event)
	self.__events[event] = nil
	self.__unitEvents[event] = nil
	if Mock.events[event] then
		Mock.events[event][self] = nil
	end
end
function Object:UnregisterAllEvents()
	for event in pairs(self.__events) do
		self:UnregisterEvent(event)
	end
end
function Object:IsEventRegistered(event) return self.__events[event] == true end

-- Attributes (secure)
function Object:SetAttribute(name, value) self.__attributes[name] = value end
function Object:GetAttribute(name) return self.__attributes[name] end

-- Textures
function Object:SetTexture(t) self.__texture = t; self.__atlas = nil end
function Object:GetTexture() return self.__texture end
function Object:SetColorTexture(r, g, b, a) self.__color = { r, g, b, a }; self.__atlas = nil end
function Object:SetAtlas(atlas, useAtlasSize)
	assert(type(atlas) == "string" and atlas ~= "", "SetAtlas expects an atlas name")
	self.__atlas = atlas
	self.__texture = nil
	self.__color = nil
end
function Object:GetAtlas() return self.__atlas end
function Object:CreateMaskTexture() return newObject("MaskTexture", nil, self) end
function Object:AddMaskTexture(mask) self.__masks = self.__masks or {}; self.__masks[mask] = true end
function Object:RemoveMaskTexture(mask) if self.__masks then self.__masks[mask] = nil end end
function Object:SetShadowOffset(x, y) self.__shadow = { x, y } end
function Object:SetShadowColor() end
function Object:SetVertexColor(r, g, b, a) self.__vertex = { r, g, b, a } end
function Object:SetGradient(orientation, minColor, maxColor)
	assert(type(minColor) == "table" and minColor.GetRGBA, "SetGradient expects ColorMixin objects")
	self.__gradient = orientation
end
function Object:SetBlendMode(mode) self.__blend = mode end
function Object:SetTexCoord() end
function Object:SetDesaturated(d) self.__desaturated = d end
function Object:SetDrawLayer() end

-- Font strings
function Object:SetFont(path, size, flags)
	self.__font = { path, size, flags }
	return true
end
function Object:SetFontObject() end
function Object:SetText(text)
	if text ~= nil and not issecretvalue(text) then
		text = tostring(text)
	end
	self.__text = text
end
function Object:GetText()
	return self.__text
end
function Object:SetFormattedText(fmt, ...)
	local args = { ... }
	for i = 1, select("#", ...) do
		if issecretvalue(args[i]) then
			self.__text = Mock.Secret("<formatted secret>")
			self.__secretText = true
			return
		end
	end
	self.__secretText = false
	self.__text = string.format(fmt, ...)
end
function Object:SetTextColor(r, g, b, a) self.__textColor = { r, g, b, a } end
function Object:SetJustifyH() end
function Object:SetJustifyV() end
function Object:SetWordWrap() end
function Object:GetStringHeight() return 14 end
function Object:GetStringWidth() return 50 end

-- Status bars
function Object:SetStatusBarTexture(t)
	self.__texture = t
	self.__fill = self.__fill or newObject("Texture", nil, self)
end
function Object:GetStatusBarTexture()
	self.__fill = self.__fill or newObject("Texture", nil, self)
	return self.__fill
end
function Object:SetStatusBarColor(r, g, b, a) self.__barColor = { r, g, b, a } end
function Object:SetMinMaxValues(minValue, maxValue)
	self.__values.min, self.__values.max = minValue, maxValue
end
function Object:GetMinMaxValues() return self.__values.min, self.__values.max end
function Object:SetValue(value, interpolation)
	self.__values.value = value
	self.__interpolation = interpolation
	if self.__scripts.OnValueChanged then
		self.__scripts.OnValueChanged(self, value, false)
	end
end
function Object:GetValue() return self.__values.value end
function Object:SetReverseFill(r) self.__reverse = r end
function Object:SetOrientation(o) self.__orientation = o end

-- Sliders
function Object:SetValueStep() end
function Object:SetObeyStepOnDrag() end
function Object:SetThumbTexture()
	self.__thumb = self.__thumb or newObject("Texture", nil, self)
end
function Object:GetThumbTexture()
	self.__thumb = self.__thumb or newObject("Texture", nil, self)
	return self.__thumb
end

-- Edit boxes / scroll frames
function Object:SetAutoFocus() end
function Object:SetMultiLine() end
function Object:SetMaxLetters() end
function Object:SetTextInsets() end
function Object:HasFocus() return self.__focus == true end
function Object:SetFocus() self.__focus = true end
function Object:ClearFocus() self.__focus = false end
function Object:HighlightText() end
function Object:SetScrollChild(child) self.__scrollChild = child end
function Object:GetVerticalScroll() return self.__vscroll or 0 end
function Object:SetVerticalScroll(v) self.__vscroll = v end
function Object:GetVerticalScrollRange() return 0 end

-- Buttons
function Object:SetEnabled(e) self.__enabled = e end
function Object:Enable() self.__enabled = true end
function Object:Disable() self.__enabled = false end

-- Cooldown
function Object:SetCooldown(start, duration)
	if issecretvalue(start) or issecretvalue(duration) then
		error("Cooldown:SetCooldown rejects secret values", 2)
	end
	self.__cooldown = { start, duration }
end
function Object:Clear() self.__cooldown = nil end

-- Animations
function Object:CreateAnimationGroup()
	return newObject("AnimationGroup", nil, self)
end
function Object:CreateAnimation(kind)
	return newObject(kind or "Animation", nil, self)
end
function Object:Play() self.__playing = true end
function Object:Stop() self.__playing = false end
function Object:IsPlaying() return self.__playing == true end
function Object:SetLooping() end
function Object:SetFromAlpha() end
function Object:SetToAlpha() end
function Object:SetDuration() end
function Object:SetSmoothing() end

-- Child creation
function Object:CreateTexture()
	return newObject("Texture", nil, self)
end
function Object:CreateFontString()
	return newObject("FontString", nil, self)
end

-- Backdrop mixin
function Object:SetBackdrop(b) self.__backdrop = b end
function Object:SetBackdropColor() end
function Object:SetBackdropBorderColor() end

-- Tooltip
function Object:SetOwner(owner) self.__owner = owner end
function Object:SetSpellByID(id) self.__tooltipSpell = id end
function Object:AddLine(text) self.__lines = self.__lines or {}; self.__lines[#self.__lines + 1] = text end
function Object:SetBagItem(bag, slot) self.__tooltipBag = { bag, slot } end
function Object:SetInventoryItem(unit, slot) self.__tooltipInventory = slot end

Mock.extraEvents = {}

local SECURE_TEMPLATES = { SecureActionButtonTemplate = true }

function CreateFrame(kind, name, parent, template)
	if template and template ~= "BackdropTemplate" and template ~= "SecureActionButtonTemplate"
		and template ~= "CooldownFrameTemplate" then
		error("unknown template in mock: " .. tostring(template), 2)
	end
	if parent and Mock.state.lockdown and template and SECURE_TEMPLATES[template] then
		Mock.blocked[#Mock.blocked + 1] = "CreateFrame(secure)"
		error("ADDON_ACTION_BLOCKED: secure frame created in combat", 2)
	end
	local o = newObject(kind, name, parent or (UIParent ~= nil and UIParent or nil))
	if template and SECURE_TEMPLATES[template] then
		o.__protected = true
	end
	if name then
		rawset(_G, name, o)
	end
	Mock.frames[#Mock.frames + 1] = o
	return o
end

UIParent = newObject("Frame", "UIParent", nil)
UIParent.__width, UIParent.__height = 1000, 800
WorldFrame = newObject("Frame", "WorldFrame", nil)
GameTooltip = newObject("GameTooltip", "GameTooltip", UIParent)
GameFontNormal = newObject("Font", "GameFontNormal", nil)
GameFontHighlight = newObject("Font", "GameFontHighlight", nil)
GameFontHighlightSmall = newObject("Font", "GameFontHighlightSmall", nil)
Minimap = newObject("Frame", "Minimap", UIParent)
Minimap.__width, Minimap.__height = 140, 140
Mock.cursorPos = { 600, 400 }
function GetCursorPosition() return Mock.cursorPos[1], Mock.cursorPos[2] end
DEFAULT_CHAT_FRAME = newObject("Frame", "ChatFrame1", UIParent)
function DEFAULT_CHAT_FRAME:AddMessage(text)
	Mock.chat[#Mock.chat + 1] = text
end
ColorPickerFrame = newObject("Frame", "ColorPickerFrame", UIParent)
function ColorPickerFrame:SetupColorPickerAndShow(info) self.__info = info end
function ColorPickerFrame:GetColorRGB() return 0.5, 0.25, 0.75 end

-- Event dispatch / time ------------------------------------------------------------------------
function Mock.FireEvent(event, ...)
	local list = Mock.events[event]
	if not list then
		return 0
	end
	local targets = {}
	for frame in pairs(list) do
		targets[#targets + 1] = frame
	end
	local count = 0
	for _, frame in ipairs(targets) do
		local unit = frame.__unitEvents[event]
		local first = ...
		if not unit or unit == first then
			local script = frame.__scripts.OnEvent
			if script then
				script(frame, event, ...)
				count = count + 1
			end
		end
	end
	return count
end

function Mock.Advance(seconds, step)
	step = step or 0.02
	local remaining = seconds
	while remaining > 1e-9 do
		local dt = math.min(step, remaining)
		Mock.clock = Mock.clock + dt
		remaining = remaining - dt
		local due = {}
		local keep = {}
		for _, t in ipairs(Mock.timers) do
			if t.at <= Mock.clock then
				due[#due + 1] = t
			else
				keep[#keep + 1] = t
			end
		end
		Mock.timers = keep
		for _, t in ipairs(due) do
			t.fn()
		end
		for _, frame in ipairs(Mock.frames) do
			local script = frame.__scripts.OnUpdate
			if script and frame:IsVisible() then
				script(frame, dt)
			end
		end
	end
end

function Mock.CountOnUpdate()
	local n = 0
	for _, frame in ipairs(Mock.frames) do
		if frame.__scripts.OnUpdate then
			n = n + 1
		end
	end
	return n
end

function Mock.EnterCombat()
	Mock.FireEvent("PLAYER_REGEN_DISABLED")
	Mock.state.lockdown = true
	Mock.state.inCombat = true
end

function Mock.LeaveCombat()
	Mock.state.lockdown = false
	Mock.state.inCombat = false
	Mock.FireEvent("PLAYER_REGEN_ENABLED")
end

-- Game state ----------------------------------------------------------------------------------------
local S = Mock.state
S.class = "WARRIOR"
S.locale = "enUS"
S.lockdown = false
S.inCombat = false
S.rage, S.rageMax = 20, 100
S.health, S.healthMax = 3000, 4000
S.secretPower = false
S.secretHealth = false
S.secretStats = false
S.attackSpeed = { 2.6, 1.9, 3.0 }
S.inventory = { [16] = 1001, [17] = 2001 }
S.bags = { [0] = { 1002, 2002, 3001 } }
S.forms = {
	{ icon = 132349, active = true, castable = true, spellID = 2457 },
	{ icon = 132341, active = false, castable = true, spellID = 71 },
	{ icon = 132275, active = false, castable = true, spellID = 2458 },
}
S.items = {
	[1001] = { name = "Sword of Testing", equipLoc = "INVTYPE_WEAPON", classID = 2, icon = 1 },
	[1002] = { name = "Great Axe", equipLoc = "INVTYPE_2HWEAPON", classID = 2, icon = 2 },
	[2001] = { name = "Tower Shield", equipLoc = "INVTYPE_SHIELD", classID = 4, icon = 3 },
	[2002] = { name = "Off Dagger", equipLoc = "INVTYPE_WEAPON", classID = 2, icon = 4 },
	[3001] = { name = "Bread", equipLoc = "", classID = 0, icon = 5 },
}
S.spells = {
	[2457] = "Battle Stance", [71] = "Defensive Stance", [2458] = "Berserker Stance",
	[100] = "Charge", [20252] = "Intercept", [7384] = "Overpower", [5308] = "Execute",
	[6552] = "Pummel", [72] = "Shield Bash", [355] = "Taunt", [694] = "Mocking Blow",
	[871] = "Shield Wall", [676] = "Disarm", [6572] = "Revenge", [20230] = "Retaliation",
	[6343] = "Thunder Clap", [1719] = "Recklessness", [18499] = "Berserker Rage",
	[1680] = "Whirlwind", [1715] = "Hamstring", [7386] = "Sunder Armor", [78] = "Heroic Strike",
	[845] = "Cleave", [674] = "Dual Wield",
}
S.knownSpells = { [674] = true }

-- Unit API
function UnitClass(unit) return "Warrior", S.class, 1 end
function UnitName() return "Tester" end
function GetRealmName() return "Mockrealm" end
function GetLocale() return S.locale end
function GetBuildInfo() return "1.60.1", "70862", "Nov 7 2026", 16001 end
function InCombatLockdown() return S.lockdown end
function UnitAffectingCombat() return S.inCombat end
function UnitExists(unit) return unit == "player" or S.hasTarget == true end
function UnitPower(unit, powerType) return maybeSecret(S.rage, S.secretPower) end
function UnitPowerMax(unit, powerType) return maybeSecret(S.rageMax, S.secretPower) end
function UnitHealth(unit) return maybeSecret(S.health, S.secretHealth) end
function UnitHealthMax(unit) return maybeSecret(S.healthMax, S.secretHealth) end
function UnitAttackSpeed()
	local a = S.attackSpeed
	return maybeSecret(a[1], S.secretStats), a[2] and maybeSecret(a[2], S.secretStats), a[3] and maybeSecret(a[3], S.secretStats)
end

local function evaluate(curve, x, secret)
	local result = curve:Evaluate(x)
	if secret then
		if type(result) == "table" and result.GetRGBA then
			local r, g, b, a = result:GetRGBA()
			local color = { r = Mock.Secret(r), g = Mock.Secret(g), b = Mock.Secret(b), a = Mock.Secret(a) }
			function color:GetRGBA()
				return self.r, self.g, self.b, self.a
			end
			return color
		end
		return Mock.Secret(result)
	end
	return result
end

function UnitPowerPercent(unit, powerType, unmodified, curve)
	local frac = S.rageMax > 0 and S.rage / S.rageMax or 0
	if curve then
		return evaluate(curve, frac, S.secretPower)
	end
	return maybeSecret(frac, S.secretPower)
end
function UnitHealthPercent(unit, usePredicted, curve)
	local frac = S.healthMax > 0 and S.health / S.healthMax or 0
	if curve then
		return evaluate(curve, frac, S.secretHealth)
	end
	return maybeSecret(frac, S.secretHealth)
end

-- Curves (Blizzard semantics: input 0-1; Step keeps the value of the last point <= x)
local Curve = {}
Curve.__index = Curve
function Curve:SetType(t) self.type = t end
function Curve:AddPoint(x, y)
	assert(not issecretvalue(x), "curve point x must be plain")
	self.points[#self.points + 1] = { x = x, y = y }
	table.sort(self.points, function(a, b) return a.x < b.x end)
end
function Curve:Evaluate(x)
	local p = self.points
	if #p == 0 then
		return 0
	end
	if x <= p[1].x then
		return p[1].y
	end
	for i = 1, #p - 1 do
		local a, b = p[i], p[i + 1]
		if x >= a.x and x < b.x then
			if self.type == Enum.LuaCurveType.Step then
				return a.y
			end
			local t = (x - a.x) / (b.x - a.x)
			if type(a.y) == "table" then
				return CreateColor(a.y.r + (b.y.r - a.y.r) * t, a.y.g + (b.y.g - a.y.g) * t, a.y.b + (b.y.b - a.y.b) * t, a.y.a + (b.y.a - a.y.a) * t)
			end
			return a.y + (b.y - a.y) * t
		end
	end
	return p[#p].y
end

C_CurveUtil = {}
function C_CurveUtil.CreateCurve()
	return setmetatable({ points = {}, type = 0 }, Curve)
end
function C_CurveUtil.CreateColorCurve()
	return setmetatable({ points = {}, type = 0 }, Curve)
end
function C_CurveUtil.EvaluateColorValueFromBoolean(value, ifTrue, ifFalse)
	local raw, secret = Mock.Unwrap(value)
	return maybeSecret(raw and ifTrue or ifFalse, secret)
end

function CreateColor(r, g, b, a)
	local c = { r = r, g = g, b = b, a = a or 1 }
	function c:GetRGBA()
		return self.r, self.g, self.b, self.a
	end
	function c:GetRGB()
		return self.r, self.g, self.b
	end
	return c
end

Enum = {
	PowerType = { Mana = 0, Rage = 1 },
	StatusBarInterpolation = { Immediate = 0, ExponentialEaseOut = 1 },
	LuaCurveType = { Linear = 0, Step = 1, Cosine = 2, Cubic = 3 },
	PlayerSwingType = { MainHand = 0, OffHand = 1, Ranged = 2 },
	ItemClass = { Weapon = 2, Armor = 4 },
	ItemArmorSubclass = { Shield = 6 },
}
Constants = {
	MacroConsts = { MAX_ACCOUNT_MACROS = 120, MAX_CHARACTER_MACROS = 30 },
	InventoryConstants = { NumBagSlots = 4 },
}
CurveConstants = {}
CurveConstants.ScaleTo100 = C_CurveUtil.CreateCurve()
CurveConstants.ScaleTo100:SetType(Enum.LuaCurveType.Linear)
CurveConstants.ScaleTo100:AddPoint(0, 0)
CurveConstants.ScaleTo100:AddPoint(1, 100)

C_Secrets = {}
function C_Secrets.HasSecretRestrictions() return true end
function C_Secrets.ShouldUnitPowerBeSecret() return S.secretPower end
function C_Secrets.ShouldUnitPowerMaxBeSecret() return S.secretPower end
function C_Secrets.ShouldUnitHealthMaxBeSecret() return S.secretHealth end
function C_Secrets.ShouldUnitStatsBeSecret() return S.secretStats end

C_SwingTimer = { rangeCalls = {} }
function C_SwingTimer.EnableRangeCheck(swingType, enable)
	C_SwingTimer.rangeCalls[#C_SwingTimer.rangeCalls + 1] = { swingType, enable }
end
function C_SwingTimer.IsTargetWithinSwingRange() return nil end

-- Spells / stances
C_Spell = {}
function C_Spell.GetSpellName(id) return S.spells[id] end
function C_Spell.GetSpellTexture(id) return S.spells[id] and (100000 + id) or nil end
C_SpellBook = {}
function C_SpellBook.IsSpellKnown(id) return S.knownSpells[id] == true end
function GetNumShapeshiftForms() return #S.forms end
function GetShapeshiftFormInfo(i)
	local f = S.forms[i]
	if not f then
		return nil
	end
	return f.icon, maybeSecret(f.active, S.secretForms), f.castable, f.spellID
end
function GetShapeshiftFormCooldown() return 0, 0, 1 end
function GetBindingKey(command) return S.bindings and S.bindings[command] end

-- Items
C_Item = {}
function C_Item.GetItemInfoInstant(id)
	local item = S.items[id]
	if not item then
		return nil
	end
	return id, "Weapon", "Sub", item.equipLoc, item.icon, item.classID, 0
end
function C_Item.GetItemNameByID(id) return S.items[id] and S.items[id].name end
function C_Item.GetItemIconByID(id) return S.items[id] and S.items[id].icon end
function C_Item.RequestLoadItemDataByID() end
function C_Item.GetItemSubClassInfo(classID, subClassID)
	if classID == 4 and subClassID == 6 then
		return "Shields", false
	end
	return "Other", false
end
local function countItem(id)
	local n = 0
	for _, bag in pairs(S.bags) do
		for _, itemID in ipairs(bag) do
			if itemID == id then
				n = n + 1
			end
		end
	end
	for _, itemID in pairs(S.inventory) do
		if itemID == id then
			n = n + 1
		end
	end
	return n
end
function C_Item.GetItemCount(id) return countItem(id) end
function C_Item.IsEquippedItem(id)
	for _, itemID in pairs(S.inventory) do
		if itemID == id then
			return true
		end
	end
	return false
end
function GetInventoryItemID(unit, slot) return S.inventory[slot] end
C_Container = {}
function C_Container.GetContainerNumSlots(bag) return S.bags[bag] and #S.bags[bag] or 0 end
function C_Container.GetContainerItemID(bag, slot) return S.bags[bag] and S.bags[bag][slot] end
C_EquipmentSet = {}
function C_EquipmentSet.CanUseEquipmentSets() return S.equipmentSets ~= nil end
function C_EquipmentSet.GetEquipmentSetIDs()
	local ids = {}
	for i in ipairs(S.equipmentSets or {}) do
		ids[#ids + 1] = i
	end
	return ids
end
function C_EquipmentSet.GetEquipmentSetInfo(id) return S.equipmentSets[id] end
INVTYPE_2HWEAPON = "Two-Hand"

-- Macros
function GetNumMacros()
	local account, character = 0, 0
	for index in pairs(Mock.macros) do
		if index > 120 then
			character = character + 1
		else
			account = account + 1
		end
	end
	return account, character
end
function GetMacroInfo(index)
	local m = Mock.macros[index]
	if m then
		return m.name, m.icon, m.body
	end
end
function CreateMacro(name, icon, body, perCharacter)
	if S.lockdown then
		Mock.blocked[#Mock.blocked + 1] = "CreateMacro"
		error("ADDON_ACTION_BLOCKED: CreateMacro in combat")
	end
	local first, last = 1, 120
	if perCharacter then
		first, last = 121, 150
	end
	for i = first, last do
		if not Mock.macros[i] then
			Mock.macros[i] = { name = name, icon = icon, body = body }
			return i
		end
	end
	error("no free macro slot")
end
Mock.cursor = nil
function PickupMacro(index)
	if S.lockdown then
		Mock.blocked[#Mock.blocked + 1] = "PickupMacro"
		error("ADDON_ACTION_BLOCKED: PickupMacro in combat")
	end
	Mock.cursor = { kind = "macro", index = index }
end
function EditMacro(index, name, icon, body)
	if S.lockdown then
		Mock.blocked[#Mock.blocked + 1] = "EditMacro"
		error("ADDON_ACTION_BLOCKED: EditMacro in combat")
	end
	Mock.macros[index] = { name = name, icon = icon, body = body }
	return index
end

-- Sound / CVars / misc
SOUNDKIT = { RAID_WARNING = 8959, READY_CHECK = 8960, ALARM_CLOCK_WARNING_3 = 12889, TELL_MESSAGE = 3081, IG_MAINMENU_OPTION_CHECKBOX_ON = 856 }
function PlaySound(id, channel)
	Mock.sounds[#Mock.sounds + 1] = { id = id, channel = channel }
	return true
end
C_CVar = {}
function C_CVar.GetCVarBool(name)
	local v = Mock.cvars[name]
	if v == nil then
		return nil
	end
	return v == "1"
end
function C_CVar.SetCVar(name, value)
	Mock.cvars[name] = value
	return true
end
C_AddOns = {}
function C_AddOns.GetAddOnMetadata(addon, field)
	if field == "Version" then
		return "1.1.0"
	end
end
function geterrorhandler()
	return function(message)
		Mock.errors[#Mock.errors + 1] = tostring(message)
	end
end
SlashCmdList = {}
Settings = { categories = {} }
function Settings.RegisterCanvasLayoutCategory(frame, name)
	return { frame = frame, name = name }
end
function Settings.RegisterAddOnCategory(category)
	Settings.categories[#Settings.categories + 1] = category
end
GameMenuEscPriority = { AddOn = 8 }
UISpecialFrames = {}
Mock.escHandlers = {}
function RegisterGameMenuEscHandler(priority, handler)
	Mock.escHandlers[#Mock.escHandlers + 1] = handler
end
-- Simulates a key press the way the client delivers it: visible frames
-- with the keyboard enabled get OnKeyDown first; if one stops propagation,
-- the key never reaches the game (bindings, Escape handlers).
function Mock.PressKey(key)
	local consumed = false
	for i = #Mock.frames, 1, -1 do
		local frame = Mock.frames[i]
		if not consumed and frame.__keyboard and frame:IsVisible() then
			if frame.__scripts.OnKeyDown then
				frame.__scripts.OnKeyDown(frame, key)
			end
			if frame.__propagate == false then
				consumed = true
				if frame.__scripts.OnKeyUp then
					frame.__scripts.OnKeyUp(frame, key)
				end
			end
		end
	end
	if consumed then
		return true
	end
	Mock.gameKeys = (Mock.gameKeys or 0) + 1
	if key == "ESCAPE" then
		for _, handler in ipairs(Mock.escHandlers) do
			if handler() then
				return true
			end
		end
	end
	return false
end

function Mock.PressEscape()
	return Mock.PressKey("ESCAPE")
end

-- Events that exist on the client but are dispatched internally in 12.x
Mock.extraEvents.ADDON_ACTION_BLOCKED = true
Mock.extraEvents.ADDON_ACTION_FORBIDDEN = true

-- Global write tracking -----------------------------------------------------------------------------
function Mock.TrackGlobals()
	setmetatable(_G, {
		__newindex = function(t, key, value)
			Mock.globalWrites[key] = true
			rawset(t, key, value)
		end,
	})
end
