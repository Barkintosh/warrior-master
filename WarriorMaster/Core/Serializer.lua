--[[
Warrior Master - Core/Serializer.lua
Profile import/export without code execution.

Imported text is never passed to loadstring or any other evaluator. It is
decoded by a small hand-written parser that only understands nil, booleans,
finite numbers, strings and nested tables, with hard limits on size, depth
and item count. The decoded table is then validated field by field by the
schema (Core/Schema.lua) before anything is stored.

Export format:  WM1:<adler32 checksum>:<base64 payload>
Pure Lua 5.1 (no bit library), so it runs unchanged in the offline tests.
]]
local _, ns = ...

local Ser = {}
ns.Serializer = Ser

local byte, char, sub, format = string.byte, string.char, string.sub, string.format
local floor, concat = math.floor, table.concat

Ser.PREFIX = "WM1"
Ser.MAX_INPUT = 65536
Ser.MAX_DEPTH = 12
Ser.MAX_ITEMS = 4000
Ser.MAX_STRING = 1024

-- Encoding --------------------------------------------------------------------------
local function encodeValue(value, out, depth)
	local t = type(value)
	if t == "nil" then
		out[#out + 1] = "n"
	elseif t == "boolean" then
		out[#out + 1] = value and "T" or "F"
	elseif t == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			out[#out + 1] = "n"
		else
			out[#out + 1] = "N" .. format("%.10g", value) .. ";"
		end
	elseif t == "string" then
		out[#out + 1] = "S" .. #value .. ":" .. value
	elseif t == "table" then
		if depth >= Ser.MAX_DEPTH then
			error("table too deep")
		end
		out[#out + 1] = "{"
		local keys = {}
		for k in pairs(value) do
			local kt = type(k)
			if kt == "string" or kt == "number" then
				keys[#keys + 1] = k
			end
		end
		table.sort(keys, function(a, b)
			local ta, tb = type(a), type(b)
			if ta ~= tb then
				return ta < tb
			end
			return a < b
		end)
		for _, k in ipairs(keys) do
			encodeValue(k, out, depth + 1)
			encodeValue(value[k], out, depth + 1)
		end
		out[#out + 1] = "}"
	else
		out[#out + 1] = "n"
	end
end

function Ser.Encode(value)
	local out = {}
	encodeValue(value, out, 0)
	return concat(out)
end

-- Decoding ----------------------------------------------------------------------------
-- Returns value, nextIndex  or raises a plain error string on malformed input.
local function decodeValue(s, i, depth, budget)
	budget.items = budget.items + 1
	if budget.items > Ser.MAX_ITEMS then
		error("too many items")
	end
	local c = sub(s, i, i)
	if c == "n" then
		return nil, i + 1
	elseif c == "T" then
		return true, i + 1
	elseif c == "F" then
		return false, i + 1
	elseif c == "N" then
		local stop = s:find(";", i + 1, true)
		if not stop or stop - i > 32 then
			error("bad number")
		end
		local text = sub(s, i + 1, stop - 1)
		if not text:match("^%-?[%d%.]+[eE]?[%+%-]?%d*$") then
			error("bad number")
		end
		local n = tonumber(text)
		if not n or n ~= n or n == math.huge or n == -math.huge then
			error("bad number")
		end
		return n, stop + 1
	elseif c == "S" then
		local colon = s:find(":", i + 1, true)
		if not colon or colon - i > 8 then
			error("bad string")
		end
		local len = tonumber(sub(s, i + 1, colon - 1))
		if not len or len < 0 or floor(len) ~= len or len > Ser.MAX_STRING then
			error("bad string")
		end
		local first = colon + 1
		local last = first + len - 1
		if last > #s then
			error("truncated string")
		end
		return sub(s, first, last), last + 1
	elseif c == "{" then
		if depth >= Ser.MAX_DEPTH then
			error("too deep")
		end
		local t = {}
		i = i + 1
		while true do
			local nextChar = sub(s, i, i)
			if nextChar == "}" then
				return t, i + 1
			elseif nextChar == "" then
				error("unterminated table")
			end
			local key
			key, i = decodeValue(s, i, depth + 1, budget)
			local kt = type(key)
			if kt ~= "string" and kt ~= "number" then
				error("bad key")
			end
			local value
			value, i = decodeValue(s, i, depth + 1, budget)
			t[key] = value
		end
	end
	error("unexpected data")
end

function Ser.Decode(s)
	if type(s) ~= "string" then
		return false, "parse"
	end
	local ok, value, stop = pcall(decodeValue, s, 1, 0, { items = 0 })
	if not ok then
		return false, "parse"
	end
	if stop ~= #s + 1 then
		return false, "parse"
	end
	return true, value
end

-- Base64 (arithmetic only) ----------------------------------------------------------------
local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local DECODE = {}
for i = 1, #ALPHABET do
	DECODE[byte(ALPHABET, i)] = i - 1
end

function Ser.ToBase64(data)
	local out = {}
	for i = 1, #data, 3 do
		local a, b, c = byte(data, i, i + 2)
		local n = a * 65536 + (b or 0) * 256 + (c or 0)
		local c1 = floor(n / 262144) % 64
		local c2 = floor(n / 4096) % 64
		local c3 = floor(n / 64) % 64
		local c4 = n % 64
		out[#out + 1] = sub(ALPHABET, c1 + 1, c1 + 1) .. sub(ALPHABET, c2 + 1, c2 + 1)
			.. (b and sub(ALPHABET, c3 + 1, c3 + 1) or "=")
			.. (c and sub(ALPHABET, c4 + 1, c4 + 1) or "=")
	end
	return concat(out)
end

function Ser.FromBase64(text)
	text = text:gsub("%s", "")
	if #text % 4 ~= 0 or text:find("[^%w%+/=]") then
		return nil
	end
	local out = {}
	for i = 1, #text, 4 do
		local values, pad = {}, 0
		for j = 0, 3 do
			local ch = byte(text, i + j)
			if ch == 61 then -- "="
				pad = pad + 1
				values[j + 1] = 0
			else
				if pad > 0 then
					return nil
				end
				local v = DECODE[ch]
				if not v then
					return nil
				end
				values[j + 1] = v
			end
		end
		if pad > 2 or (pad > 0 and i + 4 <= #text) then
			return nil
		end
		local n = values[1] * 262144 + values[2] * 4096 + values[3] * 64 + values[4]
		local a = floor(n / 65536) % 256
		local b = floor(n / 256) % 256
		local c = n % 256
		out[#out + 1] = char(a)
		if pad < 2 then
			out[#out + 1] = char(b)
		end
		if pad < 1 then
			out[#out + 1] = char(c)
		end
	end
	return concat(out)
end

-- Checksum (Adler-32, arithmetic only) -------------------------------------------------------
function Ser.Checksum(data)
	local a, b = 1, 0
	for i = 1, #data do
		a = (a + byte(data, i)) % 65521
		b = (b + a) % 65521
	end
	return format("%08x", b * 65536 + a)
end

-- Public API -------------------------------------------------------------------------------------
function Ser.Export(value)
	local payload = Ser.Encode(value)
	return Ser.PREFIX .. ":" .. Ser.Checksum(payload) .. ":" .. Ser.ToBase64(payload)
end

--- Returns true, table  or  false, errorCode ("format"|"checksum"|"parse"|"size").
function Ser.Import(text)
	if type(text) ~= "string" then
		return false, "format"
	end
	if #text > Ser.MAX_INPUT then
		return false, "size"
	end
	text = text:gsub("^%s+", ""):gsub("%s+$", "")
	local prefix, checksum, body = text:match("^(%w+):(%x+):(.+)$")
	if prefix ~= Ser.PREFIX or not checksum then
		return false, "format"
	end
	local payload = Ser.FromBase64(body)
	if not payload then
		return false, "format"
	end
	if Ser.Checksum(payload) ~= checksum:lower() then
		return false, "checksum"
	end
	local ok, value = Ser.Decode(payload)
	if not ok or type(value) ~= "table" then
		return false, "parse"
	end
	return true, value
end
