--[[
Warrior Master - Core/Events.lua
Event plumbing and error reporting.

- EventMixin gives each module its own hidden event frame, so disabling a
  module is a single UnregisterAllEvents() and no handler of a disabled module
  can ever run.
- Handlers run through pcall. A failing handler never breaks other modules;
  the error is recorded and forwarded once to the game's error handler, so it
  is visible (BugSack, script errors) rather than silently swallowed.
- Internal messages (SETTINGS_CHANGED, PROFILE_CHANGED, STATE_CHANGED, ...)
  use a tiny callback registry with a recursion guard to stop runaway loops.
]]
local ADDON_NAME, ns = ...

local pcall, type, tostring = pcall, type, tostring

-- Error reporting ------------------------------------------------------------
ns.errors = {}
local seenErrors = {}
local MAX_ERRORS = 50
local noticePrinted = false

function ns:ReportError(err)
	local message = tostring(err)
	local entry = seenErrors[message]
	if entry then
		entry.count = entry.count + 1
		return
	end
	entry = { message = message, count = 1, time = GetTime and GetTime() or 0 }
	seenErrors[message] = entry
	if #self.errors < MAX_ERRORS then
		self.errors[#self.errors + 1] = entry
	end
	-- Forward once to the standard error handler: never hide errors.
	local handler = geterrorhandler and geterrorhandler()
	if handler then
		pcall(handler, "Warrior Master: " .. message)
	end
	if not noticePrinted and self.Print then
		noticePrinted = true
		self:Print(self.L.ERROR_NOTICE)
	end
end

--- Calls fn(...) and reports any error. Returns ok plus fn's first result.
function ns:SafeCall(fn, ...)
	local ok, result = pcall(fn, ...)
	if not ok then
		self:ReportError(result)
		return false
	end
	return true, result
end

function ns:Print(message)
	local frame = DEFAULT_CHAT_FRAME
	if frame and frame.AddMessage then
		frame:AddMessage("|cffc79c6eWarrior Master|r: " .. tostring(message))
	end
end

-- Per-object event frames ------------------------------------------------------
local EventMixin = {}
ns.EventMixin = EventMixin

local function dispatch(frame, event, ...)
	local owner = frame.owner
	local handler = owner.__events[event]
	if not handler then
		return
	end
	local fn = handler
	if type(handler) == "string" then
		fn = owner[handler]
	end
	if type(fn) ~= "function" then
		return
	end
	local ok, err = pcall(fn, owner, event, ...)
	if not ok then
		ns:ReportError(err)
	end
end

local function getFrame(owner)
	local frame = owner.__eventFrame
	if not frame then
		frame = CreateFrame("Frame")
		frame.owner = owner
		frame:SetScript("OnEvent", dispatch)
		owner.__eventFrame = frame
	end
	return frame
end

--- Registers an event. handler defaults to the method named like the event.
-- Returns false if the client does not know the event (no error raised).
function EventMixin:RegisterEvent(event, handler)
	local frame = getFrame(self)
	local ok = pcall(frame.RegisterEvent, frame, event)
	if ok then
		self.__events[event] = handler or event
	end
	return ok
end

function EventMixin:RegisterUnitEvent(event, unit, handler)
	local frame = getFrame(self)
	local ok = pcall(frame.RegisterUnitEvent, frame, event, unit)
	if ok then
		self.__events[event] = handler or event
	end
	return ok
end

function EventMixin:UnregisterEvent(event)
	if self.__eventFrame and self.__events[event] then
		pcall(self.__eventFrame.UnregisterEvent, self.__eventFrame, event)
	end
	self.__events[event] = nil
end

function EventMixin:UnregisterAllEvents()
	if self.__eventFrame then
		self.__eventFrame:UnregisterAllEvents()
	end
	for event in pairs(self.__events) do
		self.__events[event] = nil
	end
end

function EventMixin:IsEventRegistered(event)
	return self.__events[event] ~= nil
end

function EventMixin.Embed(target)
	target.__events = target.__events or {}
	for name, fn in pairs(EventMixin) do
		if name ~= "Embed" then
			target[name] = fn
		end
	end
	return target
end

-- Internal messages ---------------------------------------------------------------
local callbacks = {}
local depth = 0
local MAX_DEPTH = 8

function ns:RegisterMessage(owner, message, fn)
	callbacks[message] = callbacks[message] or {}
	callbacks[message][owner] = fn
end

function ns:UnregisterMessage(owner, message)
	if callbacks[message] then
		callbacks[message][owner] = nil
	end
end

function ns:SendMessage(message, ...)
	local list = callbacks[message]
	if not list then
		return
	end
	if depth >= MAX_DEPTH then
		self:ReportError("message loop stopped at " .. tostring(message))
		return
	end
	depth = depth + 1
	for owner, fn in pairs(list) do
		local ok, err = pcall(fn, owner, message, ...)
		if not ok then
			self:ReportError(err)
		end
	end
	depth = depth - 1
end

-- Core state tracking (combat, target) -------------------------------------------
local core = EventMixin.Embed({})
ns.coreEvents = core

function core:PLAYER_REGEN_DISABLED()
	ns.state.inCombat = true
	ns:SendMessage("STATE_CHANGED", "combat")
end

function core:PLAYER_REGEN_ENABLED()
	ns.state.inCombat = false
	ns:SendMessage("STATE_CHANGED", "combat")
end

function core:PLAYER_TARGET_CHANGED()
	ns.state.hasTarget = ns.Compat.UnitExists("target")
	ns:SendMessage("STATE_CHANGED", "target")
end

function core:PLAYER_ENTERING_WORLD()
	ns.state.inCombat = UnitAffectingCombat and ns.Compat.ReadableBool(UnitAffectingCombat("player")) == true or false
	ns.state.hasTarget = ns.Compat.UnitExists("target")
	ns:SendMessage("STATE_CHANGED", "world")
end

-- Blizzard reports blocked protected calls with these events. We listen only
-- to surface problems caused by this addon; nothing is retried or bypassed.
function core:ADDON_ACTION_BLOCKED(event, addon, func)
	if addon == ADDON_NAME then
		ns.blockedActions = (ns.blockedActions or 0) + 1
		ns:Print(ns.L.ACTION_BLOCKED:format(tostring(func)))
	end
end
core.ADDON_ACTION_FORBIDDEN = core.ADDON_ACTION_BLOCKED

function ns:StartCoreEvents()
	core:RegisterEvent("PLAYER_REGEN_DISABLED")
	core:RegisterEvent("PLAYER_REGEN_ENABLED")
	core:RegisterEvent("PLAYER_TARGET_CHANGED")
	core:RegisterEvent("PLAYER_ENTERING_WORLD")
	core:RegisterEvent("ADDON_ACTION_BLOCKED")
	core:RegisterEvent("ADDON_ACTION_FORBIDDEN")
	core:PLAYER_ENTERING_WORLD()
end
