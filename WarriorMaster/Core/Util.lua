--[[
Warrior Master - Core/Util.lua
Small pure-Lua helpers (no game API calls) shared by every module.
Being pure, they are covered directly by the offline unit tests.
]]
local _, ns = ...

local U = {}
ns.Util = U

local floor, min, max = math.floor, math.min, math.max
local type, pairs, next = type, pairs, next

function U.Clamp(value, low, high)
	if value < low then
		return low
	elseif value > high then
		return high
	end
	return value
end

function U.Round(value, decimals)
	local m = 10 ^ (decimals or 0)
	return floor(value * m + 0.5) / m
end

--- True for a finite Lua number (rejects NaN and infinities).
function U.IsFiniteNumber(value)
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function U.DeepCopy(value, seen)
	if type(value) ~= "table" then
		return value
	end
	seen = seen or {}
	if seen[value] then
		return seen[value]
	end
	local copy = {}
	seen[value] = copy
	for k, v in pairs(value) do
		copy[U.DeepCopy(k, seen)] = U.DeepCopy(v, seen)
	end
	return copy
end

function U.Wipe(t)
	for k in pairs(t) do
		t[k] = nil
	end
	return t
end

function U.IsEmpty(t)
	return next(t) == nil
end

function U.Trim(s)
	return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Counts UTF-8 characters (the macro editor limit is expressed in characters).
function U.Utf8Len(s)
	local _, count = tostring(s or ""):gsub("[^\128-\191]", "")
	return count
end

--- Truncates to at most n UTF-8 characters without splitting a character.
function U.Utf8Sub(s, n)
	s = tostring(s or "")
	if U.Utf8Len(s) <= n then
		return s
	end
	local count, i = 0, 1
	local len = #s
	while i <= len do
		local c = s:byte(i)
		local size = c < 0x80 and 1 or c < 0xE0 and 2 or c < 0xF0 and 3 or 4
		if count + 1 > n then
			break
		end
		count = count + 1
		i = i + size
	end
	return s:sub(1, i - 1)
end

--- Removes control characters and the WoW escape character "|".
function U.StripControl(s)
	return (tostring(s or ""):gsub("[%c|]", ""))
end

function U.SplitLines(text)
	local lines = {}
	text = tostring(text or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
	for line in (text .. "\n"):gmatch("(.-)\n") do
		lines[#lines + 1] = line
	end
	if lines[#lines] == "" then
		lines[#lines] = nil
	end
	return lines
end

function U.LerpColor(a, b, t)
	t = U.Clamp(t, 0, 1)
	return a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, (a.a or 1) + ((b.a or 1) - (a.a or 1)) * t
end

--- Resolves a nested value from a dotted path, e.g. "rage.alert.threshold".
function U.GetPath(root, path)
	local node = root
	for part in path:gmatch("[^%.]+") do
		if type(node) ~= "table" then
			return nil
		end
		node = node[part]
	end
	return node
end

function U.SetPath(root, path, value)
	local node = root
	local parts = {}
	for part in path:gmatch("[^%.]+") do
		parts[#parts + 1] = part
	end
	for i = 1, #parts - 1 do
		local key = parts[i]
		if type(node[key]) ~= "table" then
			node[key] = {}
		end
		node = node[key]
	end
	node[parts[#parts]] = value
end

function U.IndexOf(list, value)
	for i = 1, #list do
		if list[i] == value then
			return i
		end
	end
	return nil
end

function U.SortedKeys(t)
	local keys = {}
	for k in pairs(t) do
		keys[#keys + 1] = k
	end
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)
	return keys
end

function U.Max(a, b)
	return max(a, b)
end

function U.Min(a, b)
	return min(a, b)
end
