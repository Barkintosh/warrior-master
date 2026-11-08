--[[
Warrior Master - Widgets/Mover.lua
Positioning: drag and drop, screen anchors, clamping, global offset.

- Each module stores a point: an anchor of the screen (TOPLEFT ... CENTER
  ... BOTTOMRIGHT) and an offset from it, in UIParent units, so positions
  survive scale and resolution changes.
- A global offset (General page, or the "All modules" handle) moves every
  module together without touching their own positions.
- "Keep on screen" (clamping) can be set per module and for everything.
- When frames are unlocked, each one gets a translucent overlay to drag it
  (right-click resets it), plus one "All modules" handle that moves the group.

Secure frames (the stance bar) only move out of combat: their overlay
refuses to start a drag in combat, and every mover is locked again as soon
as combat starts (PLAYER_REGEN_DISABLED fires before the lockdown begins).
]]
local _, ns = ...

local Movers = ns.EventMixin.Embed({})
ns.Movers = Movers

Movers.list = {}
Movers.shown = false

local ACCENT = { 0.78, 0.61, 0.43 }
local GROUP_HANDLE_Y = -150 -- default height of the "All modules" handle

local function globalOffset()
	local g = ns.db and ns.db.profile.general
	if not g then
		return 0, 0
	end
	return g.offsetX, g.offsetY
end

local function clampAll()
	local g = ns.db and ns.db.profile.general
	return not g or g.clampAll
end

--- Coordinates of an anchor point of a frame, in UIParent units.
local function anchorCoords(frame, point, parent)
	local left, right, top, bottom = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
	if not (left and right and top and bottom) then
		return nil
	end
	local s = 1
	if parent ~= frame then
		s = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
	end
	left, right, top, bottom = left * s, right * s, top * s, bottom * s
	local x = point:find("LEFT") and left or point:find("RIGHT") and right or (left + right) / 2
	local y = point:find("TOP") and top or point:find("BOTTOM") and bottom or (top + bottom) / 2
	return x, y
end

--- Point describing where a frame is now, relative to a screen anchor.
-- raw: do not subtract the global offset (used by the group handle).
function ns.PointFromFrame(frame, anchor, raw)
	anchor = anchor or "CENTER"
	local fx, fy = anchorCoords(frame, anchor, nil)
	local px, py = anchorCoords(UIParent, anchor, UIParent)
	if not (fx and px) then
		return nil
	end
	local gx, gy = 0, 0
	if not raw then
		gx, gy = globalOffset()
	end
	return {
		point = anchor,
		relPoint = anchor,
		x = math.floor(fx - px - gx + 0.5),
		y = math.floor(fy - py - gy + 0.5),
	}
end

--- Places a frame from a stored point, adding the global offset.
-- clamp: keep it on screen (combined with the global setting).
-- raw: ignore the global offset.
function ns.PlaceFrame(frame, point, clamp, raw)
	local scale = frame:GetScale()
	if not scale or scale <= 0 then
		scale = 1
	end
	local gx, gy = 0, 0
	if not raw then
		gx, gy = globalOffset()
	end
	frame:ClearAllPoints()
	frame:SetPoint(point.point, UIParent, point.relPoint, (point.x + gx) / scale, (point.y + gy) / scale)
	frame:SetClampedToScreen((clamp ~= false) and clampAll())
end

--- Same position on screen, expressed from another anchor (for the anchor menu).
function ns.ConvertAnchor(frame, anchor)
	return ns.PointFromFrame(frame, anchor)
end

local function savePosition(entry)
	local current = entry.getPoint and entry.getPoint()
	local point = ns.PointFromFrame(entry.frame, current and current.point or "CENTER", entry.raw)
	if point then
		entry.setPoint(point)
	end
end

--- Registers a movable frame.
-- opts: labelKey, getPoint(), setPoint(point), resetPoint(), isSecure, canMove(), raw
function Movers:Register(frame, opts)
	local overlay = CreateFrame("Frame", nil, frame)
	overlay:SetAllPoints(frame)
	overlay:SetFrameLevel(frame:GetFrameLevel() + 20)
	overlay:EnableMouse(true)
	overlay:RegisterForDrag("LeftButton")
	overlay:Hide()

	local bg = overlay:CreateTexture(nil, "OVERLAY")
	bg:SetAllPoints()
	bg:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], opts.alpha or 0.35)
	local label = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	label:SetPoint("CENTER")
	overlay.label = label

	local entry = {
		frame = frame,
		overlay = overlay,
		getPoint = opts.getPoint,
		setPoint = opts.setPoint,
		resetPoint = opts.resetPoint,
		labelKey = opts.labelKey,
		isSecure = opts.isSecure,
		canMove = opts.canMove,
		raw = opts.raw,
	}
	self.list[#self.list + 1] = entry

	frame:SetMovable(true)

	overlay:SetScript("OnDragStart", function()
		if entry.isSecure and ns.Compat.InCombatLockdown() then
			return
		end
		if entry.canMove and not entry.canMove() then
			return
		end
		entry.moving = true
		frame:StartMoving()
	end)
	overlay:SetScript("OnDragStop", function()
		if not entry.moving then
			return
		end
		entry.moving = false
		frame:StopMovingOrSizing()
		-- Positions live in the profile, not in the client's layout cache.
		pcall(frame.SetUserPlaced, frame, false)
		savePosition(entry)
	end)
	overlay:SetScript("OnMouseUp", function(_, button)
		if button == "RightButton" and entry.resetPoint then
			if entry.isSecure and ns.Compat.InCombatLockdown() then
				return
			end
			entry.resetPoint()
		end
	end)
	overlay:SetScript("OnEnter", function()
		if GameTooltip then
			GameTooltip:SetOwner(overlay, "ANCHOR_TOP")
			GameTooltip:SetText(ns.L[entry.labelKey] or "")
			GameTooltip:AddLine(ns.L.MOVER_HINT, 1, 1, 1)
			GameTooltip:Show()
		end
	end)
	overlay:SetScript("OnLeave", function()
		if GameTooltip then
			GameTooltip:Hide()
		end
	end)
	return entry
end

--- The "All modules" handle: dragging it changes the global offset.
function Movers:CreateGroupHandle()
	if self.groupHandle then
		return self.groupHandle
	end
	local handle = CreateFrame("Frame", "WarriorMasterGroupHandle", UIParent)
	handle:SetSize(170, 18)
	handle:SetFrameStrata("HIGH")
	self.groupHandle = handle
	self.groupEntry = self:Register(handle, {
		labelKey = "MOVE_ALL",
		raw = true,
		alpha = 0.7,
		getPoint = function()
			return { point = "CENTER" }
		end,
		setPoint = function(point)
			ns.DB:Set("general.offsetX", math.floor(point.x + 0.5))
			ns.DB:Set("general.offsetY", math.floor(point.y - GROUP_HANDLE_Y + 0.5))
		end,
		resetPoint = function()
			ns.DB:Set("general.offsetX", 0)
			ns.DB:Set("general.offsetY", 0)
		end,
	})
	self:PlaceGroupHandle()
	return handle
end

function Movers:PlaceGroupHandle()
	if not self.groupHandle then
		return
	end
	local gx, gy = globalOffset()
	ns.PlaceFrame(self.groupHandle, { point = "CENTER", relPoint = "CENTER", x = gx, y = GROUP_HANDLE_Y + gy }, true, true)
end

function Movers:Refresh()
	for _, entry in ipairs(self.list) do
		local movable = self.shown and (not entry.canMove or entry.canMove())
		entry.overlay.label:SetText(ns.L[entry.labelKey] or "")
		entry.overlay:SetShown(movable and true or false)
	end
	if self.groupHandle then
		self.groupHandle:SetShown(self.shown)
	end
end

function Movers:SetShown(shown)
	self.shown = shown and true or false
	ns.state.moversShown = self.shown
	self:Refresh()
	ns:SendMessage("STATE_CHANGED", "movers")
end

--- Stops any drag in progress (called before combat lockdown begins).
function Movers:StopAll()
	for _, entry in ipairs(self.list) do
		if entry.moving then
			entry.moving = false
			entry.frame:StopMovingOrSizing()
			pcall(entry.frame.SetUserPlaced, entry.frame, false)
			savePosition(entry)
		end
	end
end

function Movers:PLAYER_REGEN_DISABLED()
	self:StopAll()
	if self.shown then
		if ns.db then
			ns.db.profile.general.locked = true
		end
		self:SetShown(false)
	end
end

function Movers:Start()
	self:RegisterEvent("PLAYER_REGEN_DISABLED")
	self:CreateGroupHandle()
	self.groupHandle:Hide()
end
