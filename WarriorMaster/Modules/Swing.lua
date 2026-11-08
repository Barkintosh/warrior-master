--[[
Warrior Master - Modules/Swing.lua
Main-hand, off-hand and ranged swing timer.

Data source: the client event PLAYER_SWING(swingDuration, swingType),
documented in Blizzard's SwingTimerDocumentation for client 1.60.1 and used
by Blizzard's own Blizzard_SwingTimer addon. The client sends the exact
duration of each swing, so nothing is inferred from the combat log (which
addons cannot read on WoW Forever) and nothing is approximated.

- Haste changes: if UNIT_ATTACK_SPEED fires during a swing and both the old
  and new attack speeds are readable, the remaining time is rescaled. When
  attack speed is hidden (secret), the running swing is left untouched.
- Weapon swaps: WEAPON_SLOT_CHANGED restarts a running swing with the new
  weapon speed when it is readable (as Blizzard's own timer does), otherwise
  the bar is cleared and waits for the next PLAYER_SWING.
- Weapon filter: the timer can be limited to two-handed or one-handed main
  hands. The kind comes from the item's equip location
  (C_Item.GetItemInfoInstant); when it cannot be read the timer stays shown.
- Enemy swing timer: UNSUPPORTED on this client (would need the combat log).
- The OnUpdate script only runs while at least one swing is in progress.
]]
local _, ns = ...

local Compat = ns.Compat
local Media = ns.Media
local S = ns.Schema

local GetTime, pcall, format = GetTime, pcall, string.format

local Swing = ns:NewModule("swing", "MODULE_SWING")
Swing.stats = { events = 0, secret = 0, invalid = 0, rescaled = 0, lastDuration = nil }

local TYPES = {
	{ key = "mh", enumName = "MainHand", fallback = 0, slot = 16, show = "showMainHand", color = "colorMainHand", label = "SWING_MH_SHORT" },
	{ key = "oh", enumName = "OffHand", fallback = 1, slot = 17, show = "showOffHand", color = "colorOffHand", label = "SWING_OH_SHORT" },
	{ key = "ranged", enumName = "Ranged", fallback = 2, slot = 18, show = "showRanged", color = "colorRanged", label = "SWING_RANGED_SHORT" },
}
Swing.TYPES = TYPES

local byEnum = {}
for index, t in ipairs(TYPES) do
	t.index = index
	t.enum = (Enum and Enum.PlayerSwingType and Enum.PlayerSwingType[t.enumName]) or t.fallback
	byEnum[t.enum] = t
end

local WEAPON_CLASS = (Enum and Enum.ItemClass and Enum.ItemClass.Weapon) or 2
local TEXT_INTERVAL = 0.05
local RANGE_DIM_ALPHA = 0.4

--- Attack speed for a swing type, or nil when hidden or unavailable.
local function readableSpeed(t)
	if not UnitAttackSpeed then
		return nil
	end
	local ok, mh, oh, ranged = pcall(UnitAttackSpeed, "player")
	if not ok then
		return nil
	end
	local value = (t.key == "mh" and mh) or (t.key == "oh" and oh) or ranged
	value = Compat.ReadableNumber(value)
	if value and value > 0 then
		return value
	end
	return nil
end

--- Whether a weapon able to swing is equipped for this swing type.
local function hasWeapon(t)
	if t.key == "mh" then
		return true -- unarmed attacks also swing
	end
	local itemID = Compat.GetInventoryItemID(t.slot)
	if not itemID then
		return false
	end
	local _, _, _, _, _, classID = Compat.GetItemInfoInstant(itemID)
	return classID == WEAPON_CLASS
end

local ONE_HAND_LOCS = { INVTYPE_WEAPON = true, INVTYPE_WEAPONMAINHAND = true }

--- Kind of the equipped main hand: "twoHand", "oneHand", "none" (no weapon),
-- or nil when the item information cannot be read.
local function mainHandKind()
	local itemID = Compat.GetInventoryItemID(16)
	if not itemID then
		return "none"
	end
	local _, _, _, equipLoc, _, classID = Compat.GetItemInfoInstant(itemID)
	if equipLoc == "INVTYPE_2HWEAPON" then
		return "twoHand"
	end
	if ONE_HAND_LOCS[equipLoc] then
		return "oneHand"
	end
	if classID ~= nil and classID ~= WEAPON_CLASS then
		return "none"
	end
	return nil
end
Swing.MainHandKind = mainHandKind

-- Frames ---------------------------------------------------------------------------------------
function Swing:OnInitialize()
	self.timers = {}
	self.weapons = {}
	local holder = CreateFrame("Frame", "WarriorMasterSwingFrame", UIParent)
	holder:SetSize(220, 40)
	holder:SetFrameStrata("MEDIUM")
	holder:Hide()
	self.holder = holder
	self.bars = {}
	for _, t in ipairs(TYPES) do
		local bar = ns.CreateBar(nil, holder)
		bar:SetRange(0, 1)
		self.bars[t.key] = bar
		self.timers[t.key] = { active = false }
	end
	self.updater = CreateFrame("Frame")
	self.mover = ns.Movers:Register(holder, {
		labelKey = "MODULE_SWING",
		getPoint = function()
			return ns.DB:Get("swing.point")
		end,
		setPoint = function(point)
			ns.DB:Set("swing.point", point)
		end,
		resetPoint = function()
			ns.DB:Set("swing.point", S.profile.swing.point.default)
		end,
		canMove = function()
			return self.enabled
		end,
	})
end

function Swing:OnEnable()
	if not Compat.hasNativeSwing then
		self.unsupported = true
		self.holder:Hide()
		return
	end
	self.unsupported = false
	self:RegisterEvent("PLAYER_SWING")
	self:RegisterEvent("WEAPON_SLOT_CHANGED")
	self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
	self:RegisterEvent("PLAYER_ENTERING_WORLD")
	self:RegisterEvent("PLAYER_ENTER_COMBAT")
	self:RegisterEvent("PLAYER_LEAVE_COMBAT")
	self:RegisterUnitEvent("UNIT_ATTACK_SPEED", "player")
	self:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
	self:ApplySettings()
end

function Swing:OnDisable()
	self:UnregisterAllEvents()
	self:SetRangeChecks(false)
	for _, t in ipairs(TYPES) do
		self:ClearSwing(t)
	end
	self.updater:SetScript("OnUpdate", nil)
	self.holder:Hide()
end

function Swing:ApplySettings()
	if self.unsupported then
		return
	end
	local cfg = self:GetConfig()
	self.holder:SetScale(cfg.scale)
	ns.PlaceModuleFrame("swing", self.holder, cfg)
	for _, t in ipairs(TYPES) do
		local bar = self.bars[t.key]
		bar:ApplyStyle(cfg, { width = cfg.width, height = cfg.height, variant = t.key })
		bar:SetScale(1) -- the holder carries the scale
		bar:SetReverseFill(false)
		local c = cfg[t.color]
		bar:SetFillColor(c.r, c.g, c.b, c.a)
		bar.label:SetText(cfg.labels and ns.L[t.label] or "")
		bar:ConfigureGlow(false, c, false)
	end
	if cfg.rangeCheck and Compat.hasRangeCheck then
		self:RegisterEvent("PLAYER_SWING_RANGE_UPDATE")
		self:SetRangeChecks(true)
	else
		self:UnregisterEvent("PLAYER_SWING_RANGE_UPDATE")
		self:SetRangeChecks(false)
	end
	self:UpdateWeapons()
	self:Layout()
	for _, t in ipairs(TYPES) do
		self:Draw(t, GetTime())
	end
end

--- Stacks the visible bars inside the holder.
function Swing:Layout()
	local cfg = self:GetConfig()
	local shown, y = 0, 0
	for _, t in ipairs(TYPES) do
		local bar = self.bars[t.key]
		if self:IsTypeShown(t) then
			bar:ClearAllPoints()
			bar:SetPoint("TOP", self.holder, "TOP", 0, -y)
			bar:Show()
			y = y + cfg.height + cfg.spacing
			shown = shown + 1
		else
			bar:Hide()
		end
	end
	self.holder:SetSize(cfg.width, math.max(cfg.height, y - cfg.spacing))
	self:UpdateVisibility()
end

function Swing:IsTypeShown(t)
	local cfg = self:GetConfig()
	if not cfg[t.show] then
		return false
	end
	if ns.state.testMode or ns.state.moversShown then
		return true
	end
	if not self.weapons[t.key] then
		return false
	end
	if cfg.hideIdle and not ns.state.inCombat and not self.timers[t.key].active then
		return false
	end
	return true
end

--- Whether the equipped main hand matches the weapon filter.
function Swing:WeaponFilterPasses()
	local filter = self:GetConfig().weaponFilter
	if filter == "any" or ns.state.testMode or ns.state.moversShown then
		return true
	end
	local kind = self.mainHandKind
	if kind == nil then
		return true -- unknown: never hide on a guess
	end
	return kind == filter
end

function Swing:UpdateVisibility()
	local cfg = self:GetConfig()
	if not self.enabled or self.unsupported or not cfg then
		self.holder:Hide()
		return
	end
	self.holder:SetShown(ns:ShouldShow(cfg.visibility) and self:WeaponFilterPasses())
	self.holder:SetAlpha(ns:CurrentAlpha(cfg))
end

-- Timers -----------------------------------------------------------------------------------------
function Swing:StartSwing(t, duration)
	local timer = self.timers[t.key]
	local now = GetTime()
	timer.active = true
	timer.start = now
	timer.duration = duration
	timer.finish = now + duration
	timer.speed = readableSpeed(t)
	timer.itemID = Compat.GetInventoryItemID(t.slot)
	self.lastText = 0
	if self:GetConfig().hideIdle then
		self:Layout()
	end
	self:Draw(t, now)
	self:EnsureUpdating()
end

function Swing:ClearSwing(t)
	local timer = self.timers[t.key]
	timer.active = false
	timer.duration = nil
	timer.finish = nil
	timer.speed = nil
	local bar = self.bars[t.key]
	if bar then
		bar:SetBarValue(0, false)
		bar:SetPlainText("")
		bar.spark:SetAlpha(0)
	end
end

function Swing:EnsureUpdating()
	if not self.updating then
		self.updating = true
		self.updater:SetScript("OnUpdate", function()
			self:OnUpdate()
		end)
	end
end

function Swing:StopUpdating()
	self.updating = false
	self.updater:SetScript("OnUpdate", nil)
end

function Swing:Draw(t, now)
	local cfg = self:GetConfig()
	local timer = self.timers[t.key]
	local bar = self.bars[t.key]
	if not timer.active then
		bar:SetBarValue(0, false)
		bar:SetPlainText("")
		bar.spark:SetAlpha(0)
		self:ApplyRangeAlpha(t)
		return
	end
	local remaining = timer.finish - now
	if remaining < 0 then
		remaining = 0
	end
	local progress = 1 - remaining / timer.duration
	if cfg.fill == "deplete" then
		progress = 1 - progress
	end
	bar:SetBarValue(progress, false)
	bar.spark:SetAlpha(1)
	if cfg.textMode == "remaining" then
		bar:SetPlainText(format("%.1f", remaining))
	elseif cfg.textMode == "both" then
		bar:SetPlainText(format("%.1f / %.1f", remaining, timer.duration))
	else
		bar:SetPlainText("")
	end
	self:ApplyRangeAlpha(t)
end

function Swing:OnUpdate()
	local now = GetTime()
	local anyActive = false
	local drawText = now - (self.lastText or 0) >= TEXT_INTERVAL
	for _, t in ipairs(TYPES) do
		local timer = self.timers[t.key]
		if timer.active then
			if now >= timer.finish then
				self:ClearSwing(t)
				if self:GetConfig().hideIdle then
					self:Layout()
				end
			else
				anyActive = true
				if drawText then
					self:Draw(t, now)
				else
					-- Bar position every frame, text at most 20 times per second.
					local cfg = self:GetConfig()
					local progress = 1 - (timer.finish - now) / timer.duration
					if cfg.fill == "deplete" then
						progress = 1 - progress
					end
					self.bars[t.key]:SetBarValue(progress, false)
				end
			end
		end
	end
	if drawText then
		self.lastText = now
	end
	if not anyActive then
		self:StopUpdating()
	end
end

-- Events -----------------------------------------------------------------------------------------
function Swing:PLAYER_SWING(_, duration, swingType)
	self.stats.events = self.stats.events + 1
	if Compat.IsSecret(duration) or Compat.IsSecret(swingType) then
		-- Cannot be timed without arithmetic: skip rather than guess.
		self.stats.secret = self.stats.secret + 1
		return
	end
	local t = byEnum[swingType]
	duration = Compat.ReadableNumber(duration)
	if not t or not duration or duration <= 0 or duration > 20 then
		self.stats.invalid = self.stats.invalid + 1
		return
	end
	self.stats.lastDuration = duration
	if ns.state.testMode then
		return
	end
	self:StartSwing(t, duration)
	local cfg = self:GetConfig()
	if cfg.sound and t.key == "mh" then
		Media.PlayAlert(cfg.soundKey)
	end
end

function Swing:UNIT_ATTACK_SPEED()
	if not self:GetConfig().hasteRescale then
		return
	end
	local now = GetTime()
	for _, t in ipairs(TYPES) do
		local timer = self.timers[t.key]
		if timer.active and timer.speed then
			local newSpeed = readableSpeed(t)
			if newSpeed and newSpeed ~= timer.speed then
				local remaining = timer.finish - now
				if remaining > 0 then
					remaining = remaining * newSpeed / timer.speed
					timer.duration = (now - timer.start) + remaining
					timer.finish = now + remaining
					self.stats.rescaled = self.stats.rescaled + 1
				end
				timer.speed = newSpeed
			end
		end
	end
end

function Swing:WEAPON_SLOT_CHANGED()
	self:UpdateWeapons()
	local now = GetTime()
	for _, t in ipairs(TYPES) do
		local timer = self.timers[t.key]
		if timer.active then
			local itemID = Compat.GetInventoryItemID(t.slot)
			if itemID ~= timer.itemID then
				local speed = readableSpeed(t)
				if speed and self.weapons[t.key] then
					self:StartSwing(t, speed)
				else
					self:ClearSwing(t)
				end
			end
		end
	end
	self:Layout()
	for _, t in ipairs(TYPES) do
		self:Draw(t, now)
	end
end

function Swing:PLAYER_EQUIPMENT_CHANGED(_, slot)
	if slot == 16 or slot == 17 or slot == 18 then
		self:UpdateWeapons()
		self:Layout()
	end
end

function Swing:UNIT_INVENTORY_CHANGED()
	self:UpdateWeapons()
	self:Layout()
end

function Swing:PLAYER_ENTERING_WORLD()
	self:UpdateWeapons()
	self:Layout()
end

function Swing:PLAYER_ENTER_COMBAT()
	self.autoAttacking = true
end

function Swing:PLAYER_LEAVE_COMBAT()
	self.autoAttacking = false
end

function Swing:UpdateWeapons()
	for _, t in ipairs(TYPES) do
		self.weapons[t.key] = hasWeapon(t)
	end
	self.mainHandKind = mainHandKind()
	-- The automatic layout keeps room for the bars these weapons can show.
	local signature = (self.weapons.oh and "1" or "0") .. (self.weapons.ranged and "1" or "0")
	if signature ~= self.weaponSignature then
		self.weaponSignature = signature
		ns.Layout:Request()
	end
end

-- Optional out-of-reach dimming (experimental, off by default) -------------------------------------
-- C_SwingTimer.EnableRangeCheck is shared with Blizzard's own swing bars, so
-- the addon only switches it off when the game's swing timer option is off.
function Swing:SetRangeChecks(enable)
	if not Compat.hasRangeCheck then
		return
	end
	self.rangeState = self.rangeState or {}
	for _, t in ipairs(TYPES) do
		if enable then
			if not self.rangeEnabled then
				pcall(C_SwingTimer.EnableRangeCheck, t.enum, true)
			end
		else
			self.rangeState[t.key] = nil
			if self.rangeEnabled and Compat.GetCVarBool("showSwingTimer") == false then
				pcall(C_SwingTimer.EnableRangeCheck, t.enum, false)
			end
		end
	end
	self.rangeEnabled = enable and true or false
	for _, t in ipairs(TYPES) do
		self:ApplyRangeAlpha(t)
	end
end

function Swing:PLAYER_SWING_RANGE_UPDATE(_, swingType, isInRange, checksRange)
	local t = not Compat.IsSecret(swingType) and byEnum[swingType]
	if not t then
		return
	end
	local inRange = Compat.ReadableBool(isInRange)
	local checked = Compat.ReadableBool(checksRange)
	self.rangeState = self.rangeState or {}
	self.rangeState[t.key] = (checked and inRange == false) and "out" or nil
	self:ApplyRangeAlpha(t)
end

function Swing:ApplyRangeAlpha(t)
	local bar = self.bars and self.bars[t.key]
	if not bar then
		return
	end
	local out = self.rangeEnabled and self.rangeState and self.rangeState[t.key] == "out"
	-- Like Blizzard's bars, dim only between swings.
	if out and not self.timers[t.key].active then
		bar:SetAlpha(RANGE_DIM_ALPHA)
	else
		bar:SetAlpha(1)
	end
end

-- Preview mode ------------------------------------------------------------------------------------
function Swing:SimulateSwing(key, duration)
	for _, t in ipairs(TYPES) do
		if t.key == key then
			self:StartSwing(t, duration)
		end
	end
end

function Swing:GetCVarState()
	return Compat.GetCVarBool("showSwingTimer")
end

--- Turns on the game's own swing timer option (explicit player click only).
function Swing:EnableClientSwingTimer()
	if Compat.InCombatLockdown() then
		return false
	end
	local setter = C_CVar and C_CVar.SetCVar -- wm-audit: allow SetCVar (player clicks a dedicated button)
	if not setter then
		return false
	end
	local ok, result = pcall(setter, "showSwingTimer", "1")
	return ok and result ~= false
end

ns:RegisterMessage(Swing, "SETTINGS_CHANGED", function(self, _, path)
	if self.enabled and (path == "swing" or path:sub(1, 6) == "swing.") then
		self:ApplySettings()
	end
end)
ns:RegisterMessage(Swing, "STATE_CHANGED", function(self, _, reason)
	if not self.enabled or self.unsupported then
		return
	end
	if reason == "test" and not ns.state.testMode then
		for _, t in ipairs(TYPES) do
			self:ClearSwing(t)
		end
	end
	self:Layout()
end)
