--[[
Warrior Master - Core/Combat.lua
Combat lockdown queue.

Secure frames (the stance buttons) cannot be created, shown, hidden, moved
or have their attributes changed while the client is in combat lockdown.
Every such change goes through Combat:Run(key, fn):
  - out of combat it runs immediately;
  - in combat it is stored (one entry per key, latest wins) and runs once
    PLAYER_REGEN_ENABLED fires.
Nothing here triggers a game action: queued functions only configure frames.
]]
local _, ns = ...

local Combat = ns.EventMixin.Embed({})
ns.Combat = Combat

local queue = {}
local order = {}

function Combat:IsLocked()
	return ns.Compat.InCombatLockdown()
end

--- Runs fn now, or after combat. Returns true if it ran immediately.
function Combat:Run(key, fn)
	if not self:IsLocked() then
		local ok, err = pcall(fn)
		if not ok then
			ns:ReportError(err)
		end
		return true
	end
	if not queue[key] then
		order[#order + 1] = key
	end
	queue[key] = fn
	return false
end

function Combat:HasPending()
	return #order > 0
end

function Combat:PendingCount()
	return #order
end

function Combat:Flush()
	if self:IsLocked() then
		return
	end
	local keys = order
	order = {}
	for i = 1, #keys do
		local key = keys[i]
		local fn = queue[key]
		queue[key] = nil
		if fn then
			local ok, err = pcall(fn)
			if not ok then
				ns:ReportError(err)
			end
		end
	end
end

function Combat:PLAYER_REGEN_ENABLED()
	self:Flush()
end

function Combat:Start()
	self:RegisterEvent("PLAYER_REGEN_ENABLED")
end
