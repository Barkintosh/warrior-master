--[[
Test harness: loads the addon files (in TOC order) into the mocked client
and provides a tiny assertion library. Test code only - never shipped.
]]

NS = {}
TESTS = {}

function test(name, fn)
	TESTS[#TESTS + 1] = { name = name, fn = fn }
end

function check(condition, message)
	if not condition then
		error(message or "check failed", 2)
	end
end

local function show(value)
	if issecretvalue(value) then
		return "<secret>"
	end
	return tostring(value)
end

function eq(actual, expected, message)
	if actual ~= expected then
		error(string.format("%s: expected %s, got %s", message or "eq", show(expected), show(actual)), 2)
	end
end

function near(actual, expected, tolerance, message)
	if math.abs(actual - expected) > (tolerance or 1e-6) then
		error(string.format("%s: expected ~%s, got %s", message or "near", tostring(expected), tostring(actual)), 2)
	end
end

function contains(haystack, needle, message)
	if type(haystack) ~= "string" or not haystack:find(needle, 1, true) then
		error(string.format("%s: %q not found in %q", message or "contains", tostring(needle), show(haystack)), 2)
	end
end

WM = {}

function WM.Load()
	for i = 1, #ADDON_FILE_PATHS do
		local path = ADDON_FILE_PATHS[i]
		local chunk, err = loadstring(ADDON_FILE_SOURCES[i], "@WarriorMaster/" .. path)
		if not chunk then
			error("syntax error: " .. tostring(err))
		end
		chunk("WarriorMaster", NS)
	end
end

--- Loads and starts the addon like the client would.
-- opts.state: Mock.state overrides; opts.savedVars / opts.charVars: saved variables.
function WM.Boot(opts)
	opts = opts or {}
	for key, value in pairs(opts.state or {}) do
		Mock.state[key] = value
	end
	if opts.savedVars ~= nil then
		rawset(_G, "WarriorMasterDB", opts.savedVars)
	end
	if opts.charVars ~= nil then
		rawset(_G, "WarriorMasterCharDB", opts.charVars)
	end
	Mock.TrackGlobals()
	WM.Load()
	Mock.FireEvent("ADDON_LOADED", "WarriorMaster")
	Mock.FireEvent("PLAYER_LOGIN")
	Mock.FireEvent("PLAYER_ENTERING_WORLD", true, false)
	return NS
end

function WM.ErrorSummary()
	local lines = {}
	for _, e in ipairs(NS.errors or {}) do
		lines[#lines + 1] = "addon: " .. e.message
	end
	for _, e in ipairs(Mock.errors) do
		lines[#lines + 1] = "handler: " .. e
	end
	for _, b in ipairs(Mock.blocked) do
		lines[#lines + 1] = "blocked: " .. b
	end
	return table.concat(lines, "\n")
end

function WM.IsClean()
	return #(NS.errors or {}) == 0 and #Mock.errors == 0 and #Mock.blocked == 0
end

--- Runs test i; returns ok, message. Fails if the addon reported any error
-- or the mock recorded a blocked protected action, unless the test opts out.
function RUN_TEST(i)
	local t = TESTS[i]
	local ok, err = xpcall(t.fn, debug.traceback)
	if not ok then
		return false, tostring(err)
	end
	if not t.allowErrors and not WM.IsClean() then
		return false, "test passed but problems were recorded:\n" .. WM.ErrorSummary()
	end
	return true, ""
end
