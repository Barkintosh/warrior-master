--[[
Warrior Master - Modules/StancePicker.lua
Weapon picker opened by right-clicking a stance button.

Shows the weapons (as icons) that fit each hand, and the equipment sets if
the character has any. Clicking an icon assigns it to that stance; the next
left-click on the stance button switches stance and equips it.

The picker is plain, non-secure UI: it only changes saved choices. The
stance button itself is reconfigured by the stance module, out of combat
(a change made in combat applies when combat ends).

It only switches weapons: nothing else is shown.
]]
local _, ns = ...

local Compat = ns.Compat
local Media = ns.Media

local Picker = ns.EventMixin.Embed({})
ns.StancePicker = Picker

local ICON = 30
local GAP = 4
local PER_ROW = 8
local PAD = 10
local EMPTY_ICONS = {
	mh = "Interface\\PaperDoll\\UI-PaperDoll-Slot-MainHand",
	oh = "Interface\\PaperDoll\\UI-PaperDoll-Slot-SecondaryHand",
	set = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Chest",
}

local function color(name)
	return ns.Theme.Color(name)
end

local function showItemTooltip(owner, entry)
	if not GameTooltip then
		return
	end
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	local loc = entry.location
	local ok = false
	if loc and loc.bag then
		ok = pcall(GameTooltip.SetBagItem, GameTooltip, loc.bag, loc.slot)
	elseif loc and loc.inventory then
		ok = pcall(GameTooltip.SetInventoryItem, GameTooltip, "player", loc.inventory)
	end
	if not ok then
		GameTooltip:SetText(entry.name or "")
	end
	GameTooltip:Show()
end

local function makeIconButton(parent)
	local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
	b:SetSize(ICON, ICON)
	b:SetBackdrop({ edgeFile = Media.WHITE, edgeSize = 1 })
	b:SetBackdropBorderColor(0, 0, 0, 1)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetPoint("TOPLEFT", 1, -1)
	b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	b.hl = b:CreateTexture(nil, "HIGHLIGHT")
	b.hl:SetAllPoints(b.icon)
	b.hl:SetColorTexture(1, 1, 1, 0.2)
	b:SetScript("OnLeave", function()
		if GameTooltip then
			GameTooltip:Hide()
		end
	end)
	return b
end

local function makeRow(frame, labelKey)
	local row = { buttons = {} }
	row.label = ns.Theme.Text(frame, ns.Theme.SIZE_SMALL, "dim")
	row.label:SetText(ns.L[labelKey])
	row.note = ns.Theme.Text(frame, ns.Theme.SIZE_SMALL, "warn")
	return row
end

function Picker:Create()
	if self.frame then
		return self.frame
	end
	local catcher = CreateFrame("Button", nil, UIParent)
	catcher:SetAllPoints(UIParent)
	catcher:SetFrameStrata("DIALOG")
	catcher:RegisterForClicks("AnyUp")
	catcher:SetScript("OnClick", function()
		Picker:Hide()
	end)
	catcher:Hide()

	local f = CreateFrame("Frame", "WarriorMasterWeaponPicker", UIParent, "BackdropTemplate")
	f:SetFrameStrata("DIALOG")
	f:SetFrameLevel(catcher:GetFrameLevel() + 10)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:SetBackdrop({ bgFile = Media.WHITE, edgeFile = Media.WHITE, edgeSize = 1 })
	f:SetBackdropColor(color("bg"))
	f:SetBackdropBorderColor(color("accent"))
	f:Hide()
	f:SetScript("OnHide", function()
		catcher:Hide()
		Picker:UnregisterAllEvents()
	end)
	f.catcher = catcher
	self.frame = f

	f.title = ns.Theme.Text(f, ns.Theme.SIZE_HEADER, "accent")
	f.title:SetPoint("TOPLEFT", PAD, -PAD)
	local close = CreateFrame("Button", nil, f)
	close:SetSize(20, 20)
	close:SetPoint("TOPRIGHT", -4, -4)
	local x = ns.Theme.Text(close, 14, "dim")
	x:SetPoint("CENTER")
	x:SetText("x")
	close:SetScript("OnClick", function()
		Picker:Hide()
	end)

	self.rows = {
		mh = makeRow(f, "STANCE_MAINHAND"),
		oh = makeRow(f, "STANCE_OFFHAND"),
		set = makeRow(f, "STANCE_SET"),
	}

	-- Escape closes the picker through its own keyboard script (see
	-- UI.EscapeToClose); Blizzard's Escape handler list is never touched.
	ns.UI.EscapeToClose(f, function()
		Picker:Hide()
	end)
	return f
end

function Picker:IsShown()
	return self.frame ~= nil and self.frame:IsShown()
end

function Picker:Hide()
	if self.frame then
		self.frame:Hide()
	end
end

function Picker:Toggle(button)
	if self:IsShown() and self.button == button then
		self:Hide()
		return
	end
	self:Open(button)
end

function Picker:Open(button)
	local form = button and button.form
	local stance = ns:GetModule("stance")
	if not form or not stance or not stance.enabled then
		return
	end
	self:Create()
	self.button, self.form, self.key = button, form, form.key
	local f = self.frame
	f:ClearAllPoints()
	f:SetPoint("BOTTOMLEFT", button, "TOPLEFT", 0, 6)
	self:Refresh()
	f.catcher:Show()
	f:Show()
	self:RegisterEvent("BAG_UPDATE_DELAYED", "Refresh")
	self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", "Refresh")
end

--- Lays out one row of icons; returns the y position after it.
function Picker:LayoutRow(row, items, current, field, y, disabledNote)
	local f = self.frame
	row.label:ClearAllPoints()
	row.label:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
	y = y - 16
	for i, item in ipairs(items) do
		local b = row.buttons[i]
		if not b then
			b = makeIconButton(f)
			row.buttons[i] = b
		end
		local col = (i - 1) % PER_ROW
		local line = math.floor((i - 1) / PER_ROW)
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + col * (ICON + GAP), y - line * (ICON + GAP))
		b.icon:SetTexture(item.icon or EMPTY_ICONS[field])
		local selected = item.value == current
		if selected then
			b:SetBackdropBorderColor(color("accent"))
		else
			b:SetBackdropBorderColor(0, 0, 0, 1)
		end
		b.icon:SetDesaturated(disabledNote ~= nil and true or false)
		b:SetAlpha(disabledNote and 0.4 or 1)
		b:SetScript("OnClick", function()
			if disabledNote then
				return
			end
			ns:GetModule("stance"):SetLoadout(self.key, field, item.value)
			self:Refresh()
		end)
		b:SetScript("OnEnter", function(owner)
			if item.entry then
				showItemTooltip(owner, item.entry)
			elseif GameTooltip then
				GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
				GameTooltip:SetText(item.text or ns.L.NONE_KEEP)
				GameTooltip:Show()
			end
		end)
		b:Show()
	end
	for i = #items + 1, #row.buttons do
		row.buttons[i]:Hide()
	end
	local lines = math.max(1, math.ceil(#items / PER_ROW))
	y = y - lines * (ICON + GAP)
	row.note:ClearAllPoints()
	if disabledNote then
		row.note:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
		row.note:SetText(disabledNote)
		row.note:Show()
		y = y - 16
	else
		row.note:Hide()
	end
	return y - 6
end

function Picker:Refresh()
	if not self:IsShown() and not self.frame then
		return
	end
	local L = ns.L
	local stance = ns:GetModule("stance")
	local f = self.frame
	local key = self.key
	local lo = stance:GetLoadout(key) or {}
	local scan = stance:ScanWeapons()
	f.title:SetText(L[stance.LABELS[key]])

	local function itemsFrom(list, field, filter)
		local items = { { value = nil, text = L.NONE_KEEP } }
		for _, entry in ipairs(list) do
			if not filter or filter(entry) then
				items[#items + 1] = { value = entry.id, icon = entry.icon, entry = entry }
			end
		end
		return items
	end

	local y = -PAD - 22
	local mhItems = itemsFrom(scan.mainHand, "mh")
	y = self:LayoutRow(self.rows.mh, mhItems, not lo.set and lo.mh or nil, "mh", y)
	local ohNote = stance:IsTwoHanded(lo.mh) and not lo.set and L.PICKER_TWOHAND or nil
	local ohItems = itemsFrom(scan.offHand, "oh")
	y = self:LayoutRow(self.rows.oh, ohItems, not lo.set and lo.oh or nil, "oh", y, ohNote)

	local sets = Compat.GetEquipmentSets()
	local setRow = self.rows.set
	if #sets > 0 then
		local items = { { value = nil, text = L.NONE_KEEP } }
		for _, set in ipairs(sets) do
			items[#items + 1] = { value = set.name, icon = set.icon, text = set.name }
		end
		setRow.label:Show()
		y = self:LayoutRow(setRow, items, lo.set, "set", y)
	else
		setRow.label:Hide()
		setRow.note:Hide()
		for _, b in ipairs(setRow.buttons) do
			b:Hide()
		end
	end

	local width = PAD * 2 + PER_ROW * (ICON + GAP) - GAP
	y = y + 6 - PAD
	f:SetSize(width, -y)
end

-- Keep the picker in step with changes made elsewhere (settings page).
ns:RegisterMessage(Picker, "CHAR_SETTINGS_CHANGED", function(self, _, path)
	if path == "loadouts" and self:IsShown() then
		self:Refresh()
	end
end)
