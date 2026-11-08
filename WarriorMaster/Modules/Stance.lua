--[[
Warrior Master - Modules/Stance.lua
Stance buttons with optional weapon sets.

Security model (see SECURITY.md, "Stance & Weapon Manager"):
- Each button is a SecureActionButtonTemplate button. It performs its
  action only when the player clicks it or presses its key binding: the
  client calls the secure handler with a hardware event. The addon never
  calls :Click(), never casts spells and never equips items itself.
- The action is either type "spell" (the stance) or type "macro" with a
  short macrotext built from the player's choices:
      /cast [nostance:2] Defensive Stance
      /equipslot 16 item:12345
      /equipslot 17 item:67890
  Item and stance names are sanitized (Security.SanitizeMacroToken) and the
  text is checked against the forbidden command list.
- Buttons are created, shown, hidden, moved and re-configured only out of
  combat, through ns.Combat:Run. Changes requested in combat wait for
  PLAYER_REGEN_ENABLED. During combat only cosmetic regions are updated
  (active-stance highlight, cooldown swipe, icons).
- A stance change detected by events never triggers any action: it only
  updates the highlight.
]]
local _, ns = ...

local Compat = ns.Compat
local Media = ns.Media
local S = ns.Schema
local Security = ns.Security

local format, concat, pcall = string.format, table.concat, pcall

local Stance = ns:NewModule("stance", "MODULE_STANCE")

local MAX_BUTTONS = 3
local KNOWN_FORMS = { [2457] = "battle", [71] = "defensive", [2458] = "berserker" }
local DEFAULT_IDS = { battle = 2457, defensive = 71, berserker = 2458 }
local ORDER = S.STANCE_KEYS
local LABELS = { battle = "STANCE_BATTLE", defensive = "STANCE_DEFENSIVE", berserker = "STANCE_BERSERKER" }
local DUAL_WIELD_SPELL = 674

Stance.ORDER = ORDER
Stance.LABELS = LABELS
Stance.DEFAULT_IDS = DEFAULT_IDS

local MAIN_HAND_LOCS = { INVTYPE_WEAPON = true, INVTYPE_2HWEAPON = true, INVTYPE_WEAPONMAINHAND = true }
local OFF_HAND_LOCS = { INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true, INVTYPE_WEAPONOFFHAND = true }

function Stance:OnInitialize()
	self.buttons = {}
	self.forms = {}
	self.queuedNotice = false
end

function Stance:OnEnable()
	self:RegisterEvent("UPDATE_SHAPESHIFT_FORMS", "OnConfigEvent")
	self:RegisterEvent("SPELLS_CHANGED", "OnConfigEvent")
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnConfigEvent")
	self:RegisterEvent("BAG_UPDATE_DELAYED", "OnConfigEvent")
	self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", "OnConfigEvent")
	self:RegisterEvent("GET_ITEM_INFO_RECEIVED", "OnItemInfo")
	self:RegisterEvent("UPDATE_SHAPESHIFT_FORM", "UpdateState")
	self:RegisterEvent("UPDATE_SHAPESHIFT_USABLE", "UpdateState")
	self:RegisterEvent("UPDATE_SHAPESHIFT_COOLDOWN", "UpdateState")
	self:RegisterEvent("UPDATE_BINDINGS", "UpdateBindings")
	self:RegisterEvent("UPDATE_MACROS")
	-- Fallback if the game loaded the macros before this module was enabled.
	C_Timer.After(5, function()
		if self.enabled and not self.macrosReady then
			self:UPDATE_MACROS()
		end
	end)
	self:RequestConfigure()
end

function Stance:OnDisable()
	self:UnregisterAllEvents()
	-- Same queue key as Configure: if disabled in combat, the disable wins.
	ns.Combat:Run("stance:configure", function()
		self:DisableButtons()
	end)
end

--- Rebuilds the secure setup now, or after combat. Returns true if applied now.
-- reason "user": the player changed a setting, so a queued change is announced.
function Stance:RequestConfigure(reason)
	local applied = ns.Combat:Run("stance:configure", function()
		self:Configure()
	end)
	if not applied then
		self.pending = true
		if reason == "user" and not self.queuedNotice then
			self.queuedNotice = true
			ns:Print(ns.L.COMBAT_QUEUED)
		end
	end
	return applied
end

function Stance:ApplySettings()
	self:RequestConfigure()
end

-- Game events (bags, spells, forms, item data) refresh the setup silently.
-- Bursts of events (looting, item data streaming in) are coalesced into a
-- single rebuild a moment later.
function Stance:ScheduleConfigure()
	if self.configureScheduled then
		return
	end
	self.configureScheduled = true
	C_Timer.After(0.25, function()
		self.configureScheduled = false
		if self.enabled then
			self:RequestConfigure()
		end
	end)
end

function Stance:OnConfigEvent()
	self:ScheduleConfigure()
end

function Stance:OnItemInfo()
	if self:GetConfig().useItemNames then
		self:ScheduleConfigure()
	end
end

-- Frames (created out of combat only) ----------------------------------------------------------------
local function makeEdgeFrame(parent, size)
	local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	frame:SetBackdrop({ edgeFile = Media.WHITE, edgeSize = size })
	return frame
end

function Stance:CreateButton(index)
	local btn = CreateFrame("Button", "WarriorMasterStanceButton" .. index, self.bar, "SecureActionButtonTemplate")
	btn:RegisterForClicks("AnyUp", "AnyDown")
	btn:SetAttribute("type", nil)
	-- Right-click performs no game action ("none" is not a secure action
	-- type); PostClick then opens the weapon picker, which is plain UI.
	btn:SetAttribute("type2", "none")
	btn:SetScript("PostClick", function(button, mouseButton, down)
		if mouseButton == "RightButton" and not down and ns.StancePicker then
			ns.StancePicker:Toggle(button)
		end
	end)

	btn.bg = btn:CreateTexture(nil, "BACKGROUND")
	btn.bg:SetAllPoints()
	btn.bg:SetColorTexture(0, 0, 0, 0.6)

	btn.icon = btn:CreateTexture(nil, "ARTWORK")
	btn.icon:SetPoint("TOPLEFT", 1, -1)
	btn.icon:SetPoint("BOTTOMRIGHT", -1, 1)
	btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	btn.highlight = btn:CreateTexture(nil, "HIGHLIGHT")
	btn.highlight:SetAllPoints(btn.icon)
	btn.highlight:SetColorTexture(1, 1, 1, 0.15)

	local ok, cooldown = pcall(CreateFrame, "Cooldown", nil, btn, "CooldownFrameTemplate")
	if not ok then
		ok, cooldown = pcall(CreateFrame, "Cooldown", nil, btn)
	end
	if ok and cooldown then
		cooldown:SetAllPoints(btn.icon)
		pcall(cooldown.SetHideCountdownNumbers, cooldown, true)
		btn.cooldown = cooldown
	end

	btn.border = makeEdgeFrame(btn, 1)
	btn.border:SetAllPoints()
	btn.activeFrame = makeEdgeFrame(btn, 2)
	btn.activeFrame:SetPoint("TOPLEFT", -1, 1)
	btn.activeFrame:SetPoint("BOTTOMRIGHT", 1, -1)
	btn.activeFrame:SetAlpha(0)

	-- WoW Forever action-button look: atlas frame and masked icon.
	btn.frameTex = btn:CreateTexture(nil, "OVERLAY")
	btn.frameTex:SetAllPoints()
	btn.frameTex:Hide()
	local okMask, mask = pcall(btn.CreateMaskTexture, btn)
	if okMask and mask then
		mask:SetAllPoints(btn)
		if not pcall(mask.SetAtlas, mask, Media.buttonAtlas.mask) then
			mask = nil
		end
	end
	btn.mask = okMask and mask or nil

	local overlay = CreateFrame("Frame", nil, btn)
	overlay:SetAllPoints()
	overlay:SetFrameLevel(btn:GetFrameLevel() + 5)
	btn.overlay = overlay

	btn.activeGlow = overlay:CreateTexture(nil, "ARTWORK")
	btn.activeGlow:SetAllPoints(btn)
	btn.activeGlow:SetAlpha(0)

	btn.hotkey = overlay:CreateFontString(nil, "OVERLAY")
	btn.hotkey:SetPoint("TOPRIGHT", -2, -2)
	Media.SetFont(btn.hotkey, "Arial", 11, "OUTLINE")

	btn.warn = overlay:CreateFontString(nil, "OVERLAY")
	btn.warn:SetPoint("TOPLEFT", 2, -1)
	Media.SetFont(btn.warn, "Friz", 12, "OUTLINE")
	btn.warn:SetTextColor(1, 0.3, 0.3)
	btn.warn:SetText("!")
	btn.warn:Hide()

	btn.mhIcon = overlay:CreateTexture(nil, "OVERLAY")
	btn.mhIcon:SetPoint("BOTTOMLEFT", 1, 1)
	btn.ohIcon = overlay:CreateTexture(nil, "OVERLAY")
	btn.ohIcon:SetPoint("BOTTOMRIGHT", -1, 1)

	btn:SetScript("OnEnter", function(button)
		Stance:ShowTooltip(button)
	end)
	btn:SetScript("OnLeave", function()
		if GameTooltip then
			GameTooltip:Hide()
		end
	end)
	btn:Hide()
	return btn
end

local function setAtlas(texture, atlas)
	return pcall(texture.SetAtlas, texture, atlas)
end

--- Applies the button style (cosmetic regions only; called out of combat).
--   Forever  Blizzard's action-button frame, background and masked icon
--   Pixel    thin colored border around a cropped icon
--   Clean    cropped icon only
local function applyButtonStyle(btn, cfg)
	local A = Media.buttonAtlas
	local style = cfg.buttonStyle
	local active = cfg.activeColor
	btn.icon:ClearAllPoints()
	if style == "Forever" then
		btn.icon:SetAllPoints(btn)
		btn.icon:SetTexCoord(0, 1, 0, 1)
		if btn.mask and not btn.masked then
			btn.masked = pcall(btn.icon.AddMaskTexture, btn.icon, btn.mask)
		end
		if not setAtlas(btn.bg, A.background) then
			btn.bg:SetColorTexture(0, 0, 0, 0.6)
		end
		btn.frameTex:SetShown(setAtlas(btn.frameTex, A.frame))
		if not setAtlas(btn.highlight, A.highlight) then
			btn.highlight:SetColorTexture(1, 1, 1, 0.15)
		end
		btn.border:Hide()
		if setAtlas(btn.activeGlow, A.highlight) then
			btn.activeIndicator = btn.activeGlow
		else
			btn.activeIndicator = btn.activeFrame
		end
	else
		if btn.masked then
			pcall(btn.icon.RemoveMaskTexture, btn.icon, btn.mask)
			btn.masked = false
		end
		local inset = style == "Pixel" and 1 or 0
		btn.icon:SetPoint("TOPLEFT", inset, -inset)
		btn.icon:SetPoint("BOTTOMRIGHT", -inset, inset)
		btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		btn.bg:SetColorTexture(0, 0, 0, style == "Pixel" and 0.6 or 0)
		btn.frameTex:Hide()
		btn.highlight:SetColorTexture(1, 1, 1, 0.15)
		btn.border:SetShown(style == "Pixel")
		btn.border:SetBackdropBorderColor(cfg.borderColor.r, cfg.borderColor.g, cfg.borderColor.b, cfg.borderColor.a)
		btn.activeIndicator = btn.activeFrame
	end
	btn.activeGlow:SetVertexColor(active.r, active.g, active.b, active.a)
	btn.activeFrame:SetBackdropBorderColor(active.r, active.g, active.b, active.a)
	if btn.activeIndicator == btn.activeGlow then
		btn.activeFrame:SetAlpha(0)
	else
		btn.activeGlow:SetAlpha(0)
	end
	Media.SetFont(btn.hotkey, cfg.font, cfg.fontSize, cfg.fontOutline)
	btn.hotkey:SetTextColor(cfg.textColor.r, cfg.textColor.g, cfg.textColor.b, cfg.textColor.a)
end
Stance.ApplyButtonStyle = applyButtonStyle

function Stance:Build()
	if self.bar then
		return
	end
	Security.AssertOutOfCombat("stance build")
	local bar = CreateFrame("Frame", "WarriorMasterStanceBar", UIParent)
	bar:SetSize(40, 40)
	bar:SetFrameStrata("MEDIUM")
	bar:Hide()
	self.bar = bar
	for i = 1, MAX_BUTTONS do
		self.buttons[i] = self:CreateButton(i)
	end
	self.mover = ns.Movers:Register(bar, {
		labelKey = "MODULE_STANCE",
		isSecure = true,
		getPoint = function()
			return ns.DB:Get("stance.point")
		end,
		setPoint = function(point)
			ns.DB:Set("stance.point", point)
		end,
		resetPoint = function()
			ns.DB:Set("stance.point", S.profile.stance.point.default)
		end,
		canMove = function()
			return self.enabled and not Compat.InCombatLockdown()
		end,
	})
end

-- Forms ------------------------------------------------------------------------------------------------
function Stance:ReadForms()
	local forms = {}
	local count = math.min(Compat.GetNumShapeshiftForms(), MAX_BUTTONS)
	for i = 1, count do
		local icon, _, _, spellID = Compat.GetShapeshiftFormInfo(i)
		local id = Compat.ReadableNumber(spellID)
		local key = (id and KNOWN_FORMS[id]) or ORDER[i]
		id = id or DEFAULT_IDS[key]
		local name = Compat.GetSpellName(id) or ns.L["SPELL_" .. key:upper()]
		if Compat.IsSecret(icon) or icon == nil then
			icon = Compat.GetSpellIcon(id)
		end
		forms[i] = { index = i, key = key, spellID = id, spellName = name, icon = icon }
	end
	return forms
end

-- Weapons -------------------------------------------------------------------------------------------------
function Stance:KnowsDualWield()
	local known = Compat.IsSpellKnown(DUAL_WIELD_SPELL)
	if known == nil then
		return true -- unknown: do not hide choices the player may need
	end
	return known
end

function Stance:OwnsItem(itemID)
	return Compat.GetItemCount(itemID) > 0 or Compat.IsEquippedItem(itemID)
end

function Stance:GetEquipLoc(itemID)
	local _, _, _, equipLoc = Compat.GetItemInfoInstant(itemID)
	return equipLoc
end

function Stance:IsTwoHanded(itemID)
	return itemID ~= nil and self:GetEquipLoc(itemID) == "INVTYPE_2HWEAPON"
end

--- Text used for an item in the click action ("item:ID" or the item name).
function Stance:ItemToken(itemID)
	if self:GetConfig().useItemNames then
		local name = Compat.GetItemName(itemID)
		local token = name and Security.SanitizeMacroToken(name, 80)
		if token and token ~= "" then
			return token
		end
		return nil
	end
	return "item:" .. format("%d", itemID)
end

--- Lists equippable weapons and shields from bags and equipped slots.
function Stance:ScanWeapons()
	local seen, mainHand, offHand = {}, {}, {}
	local dualWield = self:KnowsDualWield()
	local function consider(itemID, location)
		if not itemID or seen[itemID] then
			return
		end
		seen[itemID] = true
		local equipLoc = self:GetEquipLoc(itemID)
		if not equipLoc then
			return
		end
		local entry = {
			id = itemID,
			name = Compat.GetItemName(itemID) or ns.L.UNKNOWN_ITEM:format(itemID),
			icon = Compat.GetItemIcon(itemID),
			equipLoc = equipLoc,
			location = location,
		}
		if MAIN_HAND_LOCS[equipLoc] then
			mainHand[#mainHand + 1] = entry
		end
		if OFF_HAND_LOCS[equipLoc] or (equipLoc == "INVTYPE_WEAPON" and dualWield) then
			offHand[#offHand + 1] = entry
		end
	end
	consider(Compat.GetInventoryItemID(16), { inventory = 16 })
	consider(Compat.GetInventoryItemID(17), { inventory = 17 })
	for bag = 0, Compat.GetNumBagSlots() do
		for slot = 1, Compat.GetContainerNumSlots(bag) do
			consider(Compat.GetContainerItemID(bag, slot), { bag = bag, slot = slot })
		end
	end
	local byName = function(a, b)
		return a.name < b.name
	end
	table.sort(mainHand, byName)
	table.sort(offHand, byName)
	return { mainHand = mainHand, offHand = offHand }
end

function Stance:GetLoadout(key)
	return ns.db.char.loadouts[key]
end

--- Updates one field (mh, oh or set) of a stance's weapons.
function Stance:SetLoadout(key, field, value)
	local loadouts = ns.Util.DeepCopy(ns.db.char.loadouts)
	local entry = loadouts[key] or {}
	entry[field] = value
	if value ~= nil and field == "set" then
		entry.mh, entry.oh = nil, nil
	elseif value ~= nil then
		entry.set = nil
	end
	loadouts[key] = entry
	ns.DB:SetChar("loadouts", loadouts) -- CHAR_SETTINGS_CHANGED reconfigures the buttons
	return not Compat.InCombatLockdown()
end

--- Problems with a stance's weapons, as localized strings.
function Stance:ValidateLoadout(key)
	local problems = {}
	local lo = self:GetLoadout(key)
	if not lo then
		return problems
	end
	if lo.set and not Compat.CanUseEquipmentSets() then
		problems[#problems + 1] = ns.L.EQUIPSET_UNAVAILABLE
	end
	for _, itemID in ipairs({ lo.mh or false, lo.oh or false }) do
		if itemID and not self:OwnsItem(itemID) then
			problems[#problems + 1] = ns.L.STANCE_MISSING_ITEM:format(Compat.GetItemName(itemID) or ns.L.UNKNOWN_ITEM:format(itemID))
		end
	end
	if lo.oh and self:IsTwoHanded(lo.mh) then
		problems[#problems + 1] = ns.L.STANCE_TWOHAND_CONFLICT
	end
	if lo.oh and self:GetEquipLoc(lo.oh) == "INVTYPE_WEAPON" and not self:KnowsDualWield() then
		problems[#problems + 1] = ns.L.STANCE_NO_DW
	end
	return problems
end

function Stance:EquipLines(lo)
	local lines = {}
	if lo.set and Compat.CanUseEquipmentSets() then
		local name = Security.SanitizeMacroToken(lo.set, 64)
		if name ~= "" then
			lines[#lines + 1] = "/equipset " .. name
		end
		return lines
	end
	if lo.mh and self:OwnsItem(lo.mh) then
		local token = self:ItemToken(lo.mh)
		if token then
			lines[#lines + 1] = "/equipslot 16 " .. token
		end
	end
	if lo.oh and not self:IsTwoHanded(lo.mh) and self:OwnsItem(lo.oh) then
		local token = self:ItemToken(lo.oh)
		if token then
			lines[#lines + 1] = "/equipslot 17 " .. token
		end
	end
	return lines
end

--- Macro text for a stance button, or nil when a plain spell action is enough.
function Stance:BuildClickMacro(form)
	local cfg = self:GetConfig()
	if not cfg.equipWeapons then
		return nil
	end
	local lo = self:GetLoadout(form.key)
	if not lo then
		return nil
	end
	local stanceName = Security.SanitizeMacroToken(form.spellName, 64)
	if stanceName == "" then
		return nil
	end
	local equip = self:EquipLines(lo)
	if #equip == 0 then
		return nil
	end
	local lines = { format("/cast [nostance:%d] %s", form.index, stanceName) }
	for _, line in ipairs(equip) do
		lines[#lines + 1] = line
	end
	local text = concat(lines, "\n")
	if Security.FindForbiddenCommand(text) or #text > 1000 then
		return nil
	end
	return text
end

--- Human-readable click action for the settings page.
function Stance:DescribeAction(key)
	for _, form in ipairs(self:ReadForms()) do
		if form.key == key then
			return self:BuildClickMacro(form) or ("/cast " .. (form.spellName or "?"))
		end
	end
	local id = DEFAULT_IDS[key]
	return "/cast " .. (Compat.GetSpellName(id) or ns.L["SPELL_" .. key:upper()])
end

-- Stance macros for action bars ------------------------------------------------------------------------
-- One character macro per stance, with the same text as the button's click
-- action. The player drags it onto an action bar (and binds it like any
-- action button). It is created only from a click, and kept in sync with
-- the chosen weapons, out of combat only. The addon never runs it.
Stance.MACRO_NAMES = { battle = "WM Battle", defensive = "WM Defensive", berserker = "WM Berserker" }

function Stance:GetForm(key)
	for _, form in ipairs(self:ReadForms()) do
		if form.key == key then
			return form
		end
	end
	return nil
end

function Stance:StanceMacroText(key)
	local form = self:GetForm(key)
	local name = form and form.spellName or Compat.GetSpellName(DEFAULT_IDS[key]) or ns.L["SPELL_" .. key:upper()]
	name = Security.SanitizeMacroToken(name, 64)
	local body = form and self:BuildClickMacro(form)
	if not body then
		if form then
			body = format("/cast [nostance:%d] %s", form.index, name)
		else
			body = "/cast " .. name
		end
	end
	return "#showtooltip " .. name .. "\n" .. body
end

--- Creates or updates the stance macro and puts it on the cursor.
-- Only from a click, only out of combat. Returns ok, message.
function Stance:PickupMacro(key)
	local L = ns.L
	if Compat.InCombatLockdown() then
		return false, L.MACRO_ERR_COMBAT
	end
	local MB = ns.MacroBuilder
	local name = self.MACRO_NAMES[key]
	local icon = Compat.GetSpellIcon(DEFAULT_IDS[key])
	local text = self:StanceMacroText(key)
	local ok, message = MB.Save(name, text, true, icon)
	if not ok then
		return false, message
	end
	self.syncedText = self.syncedText or {}
	self.syncedText[key] = text
	self.macrosReady = true
	local index = MB.FindMacro(name, true)
	if index and type(PickupMacro) == "function" then
		pcall(PickupMacro, index)
		return true, L.MACRO_PICKED:format(name)
	end
	return true, message
end

--- Creates the stance macros and keeps them in line with the chosen weapons.
-- Runs out of combat only, and only once the game has loaded the player's
-- macros (UPDATE_MACROS), so it can never create duplicates at login.
--   create: also create missing macros (at login, when the setup changes,
--           or on request). Other macro updates only refresh existing ones,
--           so a macro the player deleted is not recreated behind their back.
function Stance:SyncMacros(create)
	if Compat.InCombatLockdown() or type(EditMacro) ~= "function" or type(CreateMacro) ~= "function" then
		return
	end
	if not self.macrosReady then
		return
	end
	local cfg = self:GetConfig()
	local MB = ns.MacroBuilder
	self.syncedText = self.syncedText or {}
	for _, form in ipairs(self:ReadForms()) do
		local key = form.key
		local name = self.MACRO_NAMES[key]
		local text = self:StanceMacroText(key)
		local known = self.syncedText[key]
		local changed = known ~= nil and known ~= text
		local index = MB.FindMacro(name, true)
		if index and known ~= text then
			local _, _, body = GetMacroInfo(index)
			if body ~= text and MB.Validate(text).ok then
				pcall(EditMacro, index, name, Compat.GetSpellIcon(form.spellID), text)
			end
			self.syncedText[key] = text
		elseif not index and cfg.autoMacros and (create or changed) and MB.Validate(text).ok then
			local _, numCharacter = GetNumMacros()
			local _, maxCharacter = MB.GetLimits()
			if (Compat.ReadableNumber(numCharacter) or 0) < maxCharacter then
				pcall(CreateMacro, name, Compat.GetSpellIcon(form.spellID) or MB.ICON_DEFAULT, text, true)
				self.syncedText[key] = text
			elseif not self.macroFullNotice then
				self.macroFullNotice = true
				ns:Print(ns.L.MACRO_AUTO_FULL)
			end
		else
			self.syncedText[key] = text
		end
	end
end

function Stance:UPDATE_MACROS()
	local first = not self.macrosReady
	self.macrosReady = true
	if first then
		-- First load of the player's macros this session: create missing ones.
		ns.Combat:Run("stance:macros", function()
			self:SyncMacros(true)
		end)
	end
end

-- Secure configuration (out of combat only) -----------------------------------------------------------
local function setAttributeIfChanged(btn, name, value)
	if btn:GetAttribute(name) ~= value then
		btn:SetAttribute(name, value)
	end
end

function Stance:DisableButtons()
	Security.AssertOutOfCombat("stance disable")
	for _, btn in ipairs(self.buttons) do
		setAttributeIfChanged(btn, "type", nil)
		setAttributeIfChanged(btn, "macrotext", nil)
		setAttributeIfChanged(btn, "spell", nil)
		btn.form = nil
		btn:Hide()
	end
	if self.bar then
		self.bar:Hide()
	end
	self.pending = false
	self.queuedNotice = false
	ns.Movers:Refresh()
end

function Stance:Configure()
	Security.AssertOutOfCombat("stance configure")
	self.pending = false
	self.queuedNotice = false
	self:Build()
	if not self.enabled then
		self:DisableButtons()
		return
	end
	local cfg = self:GetConfig()
	self.forms = self:ReadForms()

	local size, spacing = cfg.buttonSize, cfg.spacing
	local horizontal = cfg.orientation == "HORIZONTAL"
	local shown = 0
	for i = 1, MAX_BUTTONS do
		local btn = self.buttons[i]
		local form = self.forms[i]
		if form then
			btn.form = form
			local macro = self:BuildClickMacro(form)
			btn.macroText = macro
			if macro then
				setAttributeIfChanged(btn, "spell", nil)
				setAttributeIfChanged(btn, "type", "macro")
				setAttributeIfChanged(btn, "macrotext", macro)
			else
				setAttributeIfChanged(btn, "macrotext", nil)
				setAttributeIfChanged(btn, "type", "spell")
				setAttributeIfChanged(btn, "spell", form.spellName or form.spellID)
			end
			btn:SetSize(size, size)
			btn:ClearAllPoints()
			local offset = shown * (size + spacing)
			if horizontal then
				btn:SetPoint("TOPLEFT", self.bar, "TOPLEFT", offset, 0)
			else
				btn:SetPoint("TOPLEFT", self.bar, "TOPLEFT", 0, -offset)
			end
			applyButtonStyle(btn, cfg)
			btn.icon:SetTexture(form.icon)
			btn:Show()
			shown = shown + 1
		else
			btn.form = nil
			btn.macroText = nil
			setAttributeIfChanged(btn, "type", nil)
			setAttributeIfChanged(btn, "macrotext", nil)
			setAttributeIfChanged(btn, "spell", nil)
			btn:Hide()
		end
	end

	local length = math.max(1, shown * size + math.max(0, shown - 1) * spacing)
	if horizontal then
		self.bar:SetSize(length, size)
	else
		self.bar:SetSize(size, length)
	end
	self.bar:SetScale(cfg.scale)
	self.bar:SetAlpha(cfg.alpha)
	ns.PlaceFrame(self.bar, cfg.point, cfg.clamp)
	self.bar:SetShown(shown > 0)

	self:UpdateLoadoutVisuals()
	self:UpdateState()
	self:UpdateBindings()
	self:SyncMacros(false)
	ns.Movers:Refresh()
	ns:SendMessage("STANCE_CONFIGURED")
end

-- Cosmetic updates (allowed in combat: no protected frame is touched) ---------------------------------
function Stance:UpdateLoadoutVisuals()
	local cfg = self:GetConfig()
	local iconSize = math.max(8, math.floor(cfg.buttonSize * 0.36))
	for _, btn in ipairs(self.buttons) do
		local form = btn.form
		local lo = form and self:GetLoadout(form.key)
		local showIcons = cfg.loadoutIcons and cfg.equipWeapons and lo ~= nil and not lo.set
		btn.mhIcon:SetSize(iconSize, iconSize)
		btn.ohIcon:SetSize(iconSize, iconSize)
		if showIcons and lo.mh then
			btn.mhIcon:SetTexture(Compat.GetItemIcon(lo.mh))
			btn.mhIcon:Show()
		else
			btn.mhIcon:Hide()
		end
		if showIcons and lo.oh and not self:IsTwoHanded(lo.mh) then
			btn.ohIcon:SetTexture(Compat.GetItemIcon(lo.oh))
			btn.ohIcon:Show()
		else
			btn.ohIcon:Hide()
		end
		local hasProblem = form ~= nil and cfg.equipWeapons and #self:ValidateLoadout(form.key) > 0
		btn.warn:SetShown(hasProblem and true or false)
	end
end

function Stance:UpdateState()
	if not self.bar then
		return
	end
	self.activeKey = nil
	for _, btn in ipairs(self.buttons) do
		local form = btn.form
		if form then
			local _, isActive, isCastable = Compat.GetShapeshiftFormInfo(form.index)
			local indicator = btn.activeIndicator or btn.activeFrame
			local alpha = Compat.AlphaFromBoolean(isActive, 1, 0)
			if alpha == nil or not pcall(indicator.SetAlpha, indicator, alpha) then
				indicator:SetAlpha(0)
			end
			if Compat.ReadableBool(isActive) then
				self.activeKey = form.key
			end
			local castable = Compat.ReadableBool(isCastable)
			if castable ~= nil then
				btn.icon:SetDesaturated(not castable)
			end
			if btn.cooldown and GetShapeshiftFormCooldown then
				local ok, start, duration = pcall(GetShapeshiftFormCooldown, form.index)
				start, duration = Compat.ReadableNumber(start), Compat.ReadableNumber(duration)
				if ok and start and duration and duration > 1.5 then
					pcall(btn.cooldown.SetCooldown, btn.cooldown, start, duration)
				else
					pcall(btn.cooldown.Clear, btn.cooldown)
				end
			end
		end
	end
end

local function shortKey(key)
	key = key:gsub("SHIFT%-", "S-"):gsub("CTRL%-", "C-"):gsub("ALT%-", "A-")
	return key
end

function Stance:GetBindingText(index)
	if not GetBindingKey then
		return nil
	end
	local ok, key = pcall(GetBindingKey, "CLICK WarriorMasterStanceButton" .. index .. ":LeftButton")
	if ok and type(key) == "string" and key ~= "" then
		return key
	end
	return nil
end

function Stance:UpdateBindings()
	local cfg = self:GetConfig()
	for i, btn in ipairs(self.buttons) do
		local key = self:GetBindingText(i)
		btn.hotkey:SetText((cfg.showBindings and key) and shortKey(key) or "")
	end
end

function Stance:ShowTooltip(btn)
	local cfg = self:GetConfig()
	local form = btn.form
	if not (cfg and cfg.tooltips and form and GameTooltip) then
		return
	end
	GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
	local ok = form.spellID and pcall(GameTooltip.SetSpellByID, GameTooltip, form.spellID)
	if not ok then
		GameTooltip:SetText(form.spellName or ns.L[LABELS[form.key]])
	end
	GameTooltip:AddLine(" ")
	if btn.macroText then
		GameTooltip:AddLine(ns.L.STANCE_TIP_CLICK_EQUIP, 0.78, 0.61, 0.43)
		for line in btn.macroText:gmatch("[^\n]+") do
			local itemID = tonumber(line:match("item:(%d+)"))
			if line:match("^/equip") then
				local text = itemID and (Compat.GetItemName(itemID) or ns.L.UNKNOWN_ITEM:format(itemID))
					or line:gsub("^/equip%w*%s*%d*%s*", "")
				GameTooltip:AddLine("  " .. text, 1, 1, 1)
			end
		end
	else
		GameTooltip:AddLine(ns.L.STANCE_TIP_CLICK, 0.78, 0.61, 0.43)
	end
	GameTooltip:AddLine(ns.L.STANCE_TIP_RIGHTCLICK, 0.7, 0.7, 0.7)
	for _, problem in ipairs(self:ValidateLoadout(form.key)) do
		GameTooltip:AddLine(problem, 1, 0.4, 0.4, true)
	end
	local key = self:GetBindingText(form.index)
	if key then
		GameTooltip:AddLine(ns.L.STANCE_TIP_BINDING:format(key), 0.7, 0.7, 0.7)
	end
	GameTooltip:Show()
end

ns:RegisterMessage(Stance, "SETTINGS_CHANGED", function(self, _, path)
	if self.enabled and (path == "stance" or path:sub(1, 7) == "stance.") then
		self:RequestConfigure("user")
		if path == "stance.autoMacros" and self:GetConfig().autoMacros then
			ns.Combat:Run("stance:macros", function()
				self:SyncMacros(true)
			end)
		end
	end
end)
ns:RegisterMessage(Stance, "CHAR_SETTINGS_CHANGED", function(self, _, path)
	if self.enabled and path == "loadouts" then
		self:RequestConfigure("user")
	end
end)
