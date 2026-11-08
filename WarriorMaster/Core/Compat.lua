--[[
Warrior Master - Core/Compat.lua
Single place where version-sensitive game APIs are looked up.

Every API the addon relies on was checked against Blizzard's generated API
documentation for client 1.60.1.70862 (World of Warcraft Forever, interface
16001) or against Blizzard's own UI code of that build (see COMPATIBILITY.md).
Each lookup is still guarded at runtime: when something is missing, the
dependent feature turns itself off instead of failing.

"Secret values": since the Midnight engine, the client can hand addons
opaque values during combat. They can be passed to widget setters
(StatusBar:SetValue, FontString:SetText, Region:SetAlpha, ...) but any Lua
arithmetic, comparison or concatenation on them raises an error. The helpers
below let the rest of the code test for them before doing math.
]]
local _, ns = ...

local C = {}
ns.Compat = C

local type, pcall, select = type, pcall, select

-- Build information ---------------------------------------------------------
do
	local version, build, date, interface = "?", "?", "?", 0
	if GetBuildInfo then
		version, build, date, interface = GetBuildInfo()
	end
	C.clientVersion = version or "?"
	C.clientBuild = build or "?"
	C.clientDate = date or "?"
	C.interface = tonumber(interface) or 0
	-- Forever builds use interface numbers 16000-19999.
	C.isForever = C.interface >= 16000 and C.interface < 20000
end

-- Secret values ---------------------------------------------------------------
local issecretvalue = issecretvalue

function C.IsSecret(value)
	if issecretvalue then
		return issecretvalue(value) == true
	end
	return false
end

--- Returns the value only if it is an ordinary, finite number.
function C.ReadableNumber(value)
	if C.IsSecret(value) or type(value) ~= "number" then
		return nil
	end
	if value ~= value or value == math.huge or value == -math.huge then
		return nil
	end
	return value
end

--- Returns the value only if it is an ordinary boolean.
function C.ReadableBool(value)
	if C.IsSecret(value) or type(value) ~= "boolean" then
		return nil
	end
	return value
end

function C.HasSecretRestrictions()
	if C_Secrets and C_Secrets.HasSecretRestrictions then
		local ok, result = pcall(C_Secrets.HasSecretRestrictions)
		if ok and C.ReadableBool(result) ~= nil then
			return result
		end
	end
	return issecretvalue ~= nil
end

local function probe(fn, ...)
	if type(fn) ~= "function" then
		return "n/a"
	end
	local ok, result = pcall(fn, ...)
	if not ok then
		return "error"
	end
	local b = C.ReadableBool(result)
	if b == nil then
		return "unknown"
	end
	return b and "yes" or "no"
end

--- Diagnostic: does the client currently hide this information?
function C.DescribeSecrecy()
	local S = C_Secrets
	local rage = C.POWER_RAGE
	return {
		restrictions = C.HasSecretRestrictions() and "yes" or "no",
		power = probe(S and S.ShouldUnitPowerBeSecret, "player", rage),
		powerMax = probe(S and S.ShouldUnitPowerMaxBeSecret, "player", rage),
		healthMax = probe(S and S.ShouldUnitHealthMaxBeSecret, "player"),
		stats = probe(S and S.ShouldUnitStatsBeSecret),
	}
end

-- Enumerations ----------------------------------------------------------------
C.POWER_RAGE = (Enum and Enum.PowerType and Enum.PowerType.Rage) or 1

C.hasInterpolation = Enum and Enum.StatusBarInterpolation ~= nil
C.INTERP_SMOOTH = C.hasInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut or nil
C.INTERP_IMMEDIATE = C.hasInterpolation and Enum.StatusBarInterpolation.Immediate or nil

C.hasCurves = C_CurveUtil ~= nil
	and type(C_CurveUtil.CreateCurve) == "function"
	and type(C_CurveUtil.CreateColorCurve) == "function"
	and Enum ~= nil and Enum.LuaCurveType ~= nil
	and type(CreateColor) == "function"

C.hasNativeSwing = C_SwingTimer ~= nil and Enum ~= nil and Enum.PlayerSwingType ~= nil
C.hasRangeCheck = C.hasNativeSwing and type(C_SwingTimer.EnableRangeCheck) == "function"

-- Curves ------------------------------------------------------------------------

--- Builds a color curve. points: array of { x (0-1), {r,g,b,a} }.
function C.NewColorCurve(points, smooth)
	if not C.hasCurves then
		return nil
	end
	local ok, curve = pcall(function()
		local c = C_CurveUtil.CreateColorCurve()
		c:SetType(smooth and Enum.LuaCurveType.Linear or Enum.LuaCurveType.Step)
		for i = 1, #points do
			local p = points[i]
			local col = p[2]
			c:AddPoint(p[1], CreateColor(col.r, col.g, col.b, col.a or 1))
		end
		return c
	end)
	return ok and curve or nil
end

--- Builds a numeric step curve. points: array of { x (0-1), y }.
function C.NewStepCurve(points)
	if not C.hasCurves then
		return nil
	end
	local ok, curve = pcall(function()
		local c = C_CurveUtil.CreateCurve()
		c:SetType(Enum.LuaCurveType.Step)
		for i = 1, #points do
			c:AddPoint(points[i][1], points[i][2])
		end
		return c
	end)
	return ok and curve or nil
end

local percentCurve
--- Curve mapping a 0-1 fraction to 0-100 (Blizzard ships one in CurveConstants).
function C.GetPercentCurve()
	if percentCurve == nil then
		if CurveConstants and CurveConstants.ScaleTo100 then
			percentCurve = CurveConstants.ScaleTo100
		elseif C.hasCurves then
			local ok, curve = pcall(function()
				local c = C_CurveUtil.CreateCurve()
				c:SetType(Enum.LuaCurveType.Linear)
				c:AddPoint(0, 0)
				c:AddPoint(1, 100)
				return c
			end)
			percentCurve = ok and curve or false
		else
			percentCurve = false
		end
	end
	return percentCurve or nil
end

--- Converts a possibly secret boolean to an alpha value usable by SetAlpha.
function C.AlphaFromBoolean(value, ifTrue, ifFalse)
	local readable = C.ReadableBool(value)
	if readable ~= nil then
		return readable and ifTrue or ifFalse
	end
	if C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean then
		local ok, alpha = pcall(C_CurveUtil.EvaluateColorValueFromBoolean, value, ifTrue, ifFalse)
		if ok then
			return alpha
		end
	end
	return nil
end

-- Spells and items --------------------------------------------------------------

function C.GetSpellName(spellID)
	if type(spellID) ~= "number" then
		return nil
	end
	local name
	if C_Spell and C_Spell.GetSpellName then
		local ok, result = pcall(C_Spell.GetSpellName, spellID)
		name = ok and result or nil
	end
	if C.IsSecret(name) or type(name) ~= "string" or name == "" then
		return nil
	end
	return name
end

function C.GetSpellIcon(spellID)
	if type(spellID) ~= "number" or not (C_Spell and C_Spell.GetSpellTexture) then
		return nil
	end
	local ok, icon = pcall(C_Spell.GetSpellTexture, spellID)
	if ok and not C.IsSecret(icon) and icon ~= nil then
		return icon
	end
	return nil
end

function C.IsSpellKnown(spellID)
	if C_SpellBook and C_SpellBook.IsSpellKnown then
		local ok, known = pcall(C_SpellBook.IsSpellKnown, spellID)
		if ok then
			return C.ReadableBool(known)
		end
	end
	return nil
end

--- itemID, itemType, itemSubType, equipLoc, icon, classID, subClassID
function C.GetItemInfoInstant(item)
	if item == nil or not (C_Item and C_Item.GetItemInfoInstant) then
		return nil
	end
	local ok, itemID, itemType, itemSubType, equipLoc, icon, classID, subClassID = pcall(C_Item.GetItemInfoInstant, item)
	if not ok or itemID == nil then
		return nil
	end
	return itemID, itemType, itemSubType, equipLoc, icon, classID, subClassID
end

function C.GetItemName(itemID)
	if type(itemID) ~= "number" then
		return nil
	end
	if C_Item and C_Item.GetItemNameByID then
		local ok, name = pcall(C_Item.GetItemNameByID, itemID)
		if ok and type(name) == "string" and name ~= "" then
			return name
		end
	end
	if C_Item and C_Item.RequestLoadItemDataByID then
		pcall(C_Item.RequestLoadItemDataByID, itemID)
	end
	return nil
end

function C.GetItemIcon(itemID)
	if type(itemID) ~= "number" then
		return nil
	end
	if C_Item and C_Item.GetItemIconByID then
		local ok, icon = pcall(C_Item.GetItemIconByID, itemID)
		if ok and icon then
			return icon
		end
	end
	local _, _, _, _, icon = C.GetItemInfoInstant(itemID)
	return icon
end

function C.GetItemCount(itemID)
	if C_Item and C_Item.GetItemCount then
		local ok, count = pcall(C_Item.GetItemCount, itemID)
		if ok then
			return C.ReadableNumber(count) or 0
		end
	end
	return 0
end

function C.IsEquippedItem(itemID)
	if C_Item and C_Item.IsEquippedItem then
		local ok, equipped = pcall(C_Item.IsEquippedItem, itemID)
		if ok then
			return C.ReadableBool(equipped) == true
		end
	end
	return false
end

function C.GetInventoryItemID(slot)
	if not GetInventoryItemID then
		return nil
	end
	local ok, itemID = pcall(GetInventoryItemID, "player", slot)
	if ok then
		return C.ReadableNumber(itemID)
	end
	return nil
end

function C.GetNumBagSlots()
	local n = Constants and Constants.InventoryConstants and Constants.InventoryConstants.NumBagSlots
	return C.ReadableNumber(n) or 4
end

function C.GetContainerNumSlots(bag)
	if C_Container and C_Container.GetContainerNumSlots then
		local ok, n = pcall(C_Container.GetContainerNumSlots, bag)
		return ok and C.ReadableNumber(n) or 0
	end
	return 0
end

function C.GetContainerItemID(bag, slot)
	if C_Container and C_Container.GetContainerItemID then
		local ok, id = pcall(C_Container.GetContainerItemID, bag, slot)
		return ok and C.ReadableNumber(id) or nil
	end
	return nil
end

--- Localized item subclass name (e.g. "Shields"), used in macro conditionals.
function C.GetItemSubClassName(classID, subClassID)
	if C_Item and C_Item.GetItemSubClassInfo then
		local ok, name = pcall(C_Item.GetItemSubClassInfo, classID, subClassID)
		if ok and type(name) == "string" and name ~= "" then
			return name
		end
	end
	return nil
end

-- Equipment sets ------------------------------------------------------------------

function C.CanUseEquipmentSets()
	if not (C_EquipmentSet and C_EquipmentSet.CanUseEquipmentSets and C_EquipmentSet.GetEquipmentSetIDs) then
		return false
	end
	local ok, can = pcall(C_EquipmentSet.CanUseEquipmentSets)
	return ok and C.ReadableBool(can) == true
end

--- Equipment sets as { name, icon } (sorted by name).
function C.GetEquipmentSets()
	local sets = {}
	if not C.CanUseEquipmentSets() then
		return sets
	end
	local ok, ids = pcall(C_EquipmentSet.GetEquipmentSetIDs)
	if not ok or type(ids) ~= "table" then
		return sets
	end
	for _, id in ipairs(ids) do
		local okInfo, name, icon = pcall(C_EquipmentSet.GetEquipmentSetInfo, id)
		if okInfo and type(name) == "string" and name ~= "" then
			sets[#sets + 1] = { name = name, icon = icon }
		end
	end
	table.sort(sets, function(a, b)
		return a.name < b.name
	end)
	return sets
end

function C.GetEquipmentSetNames()
	local names = {}
	for _, set in ipairs(C.GetEquipmentSets()) do
		names[#names + 1] = set.name
	end
	return names
end

-- Stances ---------------------------------------------------------------------------

function C.GetNumShapeshiftForms()
	if not GetNumShapeshiftForms then
		return 0
	end
	local ok, n = pcall(GetNumShapeshiftForms)
	return ok and C.ReadableNumber(n) or 0
end

--- icon, isActive, isCastable, spellID (any of them may be secret or nil)
function C.GetShapeshiftFormInfo(index)
	if not GetShapeshiftFormInfo then
		return nil
	end
	local ok, icon, isActive, isCastable, spellID = pcall(GetShapeshiftFormInfo, index)
	if not ok then
		return nil
	end
	return icon, isActive, isCastable, spellID
end

-- Sounds -------------------------------------------------------------------------------

function C.PlaySound(soundKitID, channel)
	if type(soundKitID) ~= "number" then
		return false
	end
	if PlaySound then
		return pcall(PlaySound, soundKitID, channel or "Master")
	elseif C_Sound and C_Sound.PlaySound then
		return pcall(C_Sound.PlaySound, soundKitID)
	end
	return false
end

-- Misc ---------------------------------------------------------------------------------

function C.InCombatLockdown()
	return InCombatLockdown and InCombatLockdown() == true or false
end

function C.GetCVarBool(name)
	local getter = (C_CVar and C_CVar.GetCVarBool) or GetCVarBool
	if not getter then
		return nil
	end
	local ok, value = pcall(getter, name)
	if ok then
		return C.ReadableBool(value)
	end
	return nil
end

function C.GetAddOnVersion(addon)
	local getter = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
	if getter then
		local ok, version = pcall(getter, addon, "Version")
		if ok and type(version) == "string" and version ~= "" then
			return version
		end
	end
	return nil
end

--- Unit class token ("WARRIOR"), or nil if hidden/unavailable.
function C.GetPlayerClass()
	if not UnitClass then
		return nil
	end
	local ok, _, token = pcall(UnitClass, "player")
	if ok and not C.IsSecret(token) and type(token) == "string" then
		return token
	end
	return nil
end

function C.UnitExists(unit)
	if not UnitExists then
		return false
	end
	local ok, exists = pcall(UnitExists, unit)
	if not ok then
		return false
	end
	local readable = C.ReadableBool(exists)
	if readable == nil then
		-- Hidden by the client: assume a unit is present (safer for visibility).
		return true
	end
	return readable
end
