--[[
Warrior Master - Config/MinimapButton.lua
Minimap button and addon compartment entry.

- The button sits on the edge of the minimap, like other addons' buttons,
  and can be dragged around it. Left-click opens the settings, right-click
  locks or unlocks the frames. It can be hidden on the General page.
- The addon compartment (the game's AddOns menu by the minimap) gets an
  entry through the TOC fields AddonCompartmentFunc*, which call the three
  global functions defined at the end of this file.
Both are plain, non-secure UI: they only open the settings window.
]]
local _, ns = ...

local MB = {}
ns.MinimapButton = MB

local ICON = "Interface\\Icons\\Ability_Warrior_BattleShout"

local function position(button)
	local minimap = Minimap
	if not minimap then
		return
	end
	local angle = math.rad(ns.DB:GetGlobal("minimap.angle"))
	local radius = math.max(minimap:GetWidth() or 140, minimap:GetHeight() or 140) / 2 + 8
	button:ClearAllPoints()
	button:SetPoint("CENTER", minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function angleFromCursor()
	local mx, my = Minimap:GetCenter()
	local cx, cy = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	if not (mx and cx and scale and scale > 0) then
		return nil
	end
	return math.deg(math.atan2(cy / scale - my, cx / scale - mx))
end

function MB.ShowTooltip(owner)
	if not GameTooltip then
		return
	end
	local L = ns.L
	GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
	GameTooltip:SetText("Warrior Master")
	GameTooltip:AddLine(L.MINIMAP_LEFT, 1, 1, 1)
	GameTooltip:AddLine(L.MINIMAP_RIGHT, 1, 1, 1)
	GameTooltip:AddLine(L.MINIMAP_DRAG, 0.7, 0.7, 0.7)
	GameTooltip:Show()
end

function MB.OnClick(mouseButton)
	if mouseButton == "RightButton" then
		local locked = ns.db.profile.general.locked
		ns.DB:Set("general.locked", not locked)
		ns:Print(locked and ns.L.UNLOCKED_MSG or ns.L.LOCKED_MSG)
	else
		ns.Config:Toggle()
	end
end

function MB:Create()
	if self.button or not Minimap then
		return self.button
	end
	local b = CreateFrame("Button", "WarriorMasterMinimapButton", Minimap)
	b:SetSize(31, 31)
	b:SetFrameStrata("MEDIUM")
	b:SetFrameLevel(8)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:RegisterForDrag("LeftButton")
	b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local background = b:CreateTexture(nil, "BACKGROUND")
	background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	background:SetSize(20, 20)
	background:SetPoint("TOPLEFT", 7, -5)
	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(ICON)
	icon:SetSize(17, 17)
	icon:SetPoint("TOPLEFT", 7, -6)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	b.icon = icon
	local border = b:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT")

	b:SetScript("OnClick", function(_, mouseButton)
		MB.OnClick(mouseButton)
	end)
	b:SetScript("OnEnter", function(self)
		MB.ShowTooltip(self)
	end)
	b:SetScript("OnLeave", function()
		if GameTooltip then
			GameTooltip:Hide()
		end
	end)
	b:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", function()
			local angle = angleFromCursor()
			if angle then
				ns.db.global.minimap.angle = math.floor(angle + 0.5)
				position(self)
			end
		end)
	end)
	b:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
		ns.DB:SetGlobal("minimap.angle", ns.db.global.minimap.angle)
	end)
	self.button = b
	return b
end

function MB:Refresh()
	local show = ns.db and ns.db.global.minimap.show and ns.state.isWarrior
	if show then
		local b = self:Create()
		if b then
			position(b)
			b:Show()
		end
	elseif self.button then
		self.button:Hide()
	end
end

function MB:Init()
	self:Refresh()
end

ns:RegisterMessage(MB, "GLOBAL_SETTINGS_CHANGED", function(self, _, path)
	if path:sub(1, 8) == "minimap." then
		self:Refresh()
	end
end)

-- Addon compartment (TOC: AddonCompartmentFunc, ...OnEnter, ...OnLeave).
function WarriorMaster_OnAddonCompartmentClick(_, mouseButton)
	if ns.state.ready and ns.state.isWarrior then
		MB.OnClick(mouseButton)
	elseif ns.state.ready then
		ns:Print(ns.L.WARRIOR_ONLY)
	end
end

function WarriorMaster_OnAddonCompartmentEnter(_, frame)
	MB.ShowTooltip(frame)
end

function WarriorMaster_OnAddonCompartmentLeave()
	if GameTooltip then
		GameTooltip:Hide()
	end
end
