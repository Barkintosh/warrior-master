--[[
Warrior Master - Widgets/Layout.lua
Automatic vertical layout (the "Layout" section of the General page).

When it is on, the modules are stacked from top to bottom in the chosen
order, centered (or left / right aligned) on one column, with the same gap
between them. Each module keeps its own size, scale and style; only its
position comes from here. The stack follows the global offset, so the
"All modules" handle, the position sliders and dragging any bar move it.

- Space is kept for every enabled module even while its frame is hidden
  (out of combat, no cast running), so nothing jumps around.
- Every frame is anchored to the screen, never to another module's frame.
  The secure stance bar is only moved out of combat (ns.Combat:Run); the
  other frames are plain UI and follow at once.
- A rage bar "attached to the health bar" is placed by the layout instead.
]]
local _, ns = ...

local U = ns.Util

local Layout = {}
ns.Layout = Layout

Layout.KEYS = { "health", "rage", "swing", "cast", "stance" }
Layout.TOP_Y = -160 -- top of the stack, before the global offset

local POINTS = { LEFT = "TOPLEFT", CENTER = "TOP", RIGHT = "TOPRIGHT" }

-- Frame placed for each module.
local FRAMES = {
	health = function(m) return m.bar end,
	rage = function(m) return m.bar end,
	swing = function(m) return m.holder end,
	cast = function(m) return m.holder end,
	stance = function(m) return m.bar end,
}
Layout.FRAMES = FRAMES

--- Height a module takes in the stack, in UIParent units.
local function moduleHeight(key, module, cfg, frame)
	local scale = (cfg.scale and cfg.scale > 0) and cfg.scale or 1
	if key == "swing" then
		-- Bars the equipped weapons can show (ignores "hide idle bars").
		local n = 0
		for _, t in ipairs(module.TYPES or {}) do
			if cfg[t.show] and (not module.weapons or module.weapons[t.key] ~= false) then
				n = n + 1
			end
		end
		n = math.max(1, n)
		return (n * cfg.height + (n - 1) * cfg.spacing) * scale
	elseif key == "stance" then
		local h = frame:GetHeight()
		if not h or h <= 0 then
			h = cfg.buttonSize
		end
		return h * scale
	end
	return cfg.height * scale
end

--- Sanitizer for the saved order: every module exactly once.
function Layout.SanitizeOrder(value)
	local out, seen = {}, {}
	if type(value) == "table" then
		for _, key in ipairs(value) do
			if type(key) == "string" and U.IndexOf(Layout.KEYS, key) and not seen[key] then
				out[#out + 1] = key
				seen[key] = true
			end
		end
	end
	for _, key in ipairs(Layout.KEYS) do
		if not seen[key] then
			out[#out + 1] = key
		end
	end
	return out
end

function Layout:Config()
	return ns.db and ns.db.profile.general.layout
end

function Layout:IsEnabled()
	local cfg = self:Config()
	return cfg ~= nil and cfg.enabled == true
end

--- True when a module has no frame of its own to place (the stance
-- buttons sit on the game's stance bar).
local function onGameBar(key)
	local module = ns.modules[key]
	return key == "stance" and module ~= nil and module.UsesGameBar ~= nil and module:UsesGameBar()
end

--- Whether the layout places this module's frame.
function Layout:Manages(key)
	return FRAMES[key] ~= nil and self:IsEnabled() and not onGameBar(key)
end

--- Places every enabled module. Returns the list of placed module keys.
function Layout:Apply()
	if not self:IsEnabled() or self.applying then
		return nil
	end
	self.applying = true
	local cfg = self:Config()
	local point = POINTS[cfg.align] or "TOP"
	local y = self.TOP_Y
	local placed = {}
	for _, key in ipairs(cfg.order) do
		local module = ns.modules[key]
		local frame = module and module.enabled and not onGameBar(key) and FRAMES[key](module)
		if frame then
			local mcfg = module:GetConfig()
			local spot = { point = point, relPoint = "CENTER", x = 0, y = y }
			local clamp = mcfg.clamp
			if key == "stance" then
				ns.Combat:Run("layout:stance", function()
					-- The layout may have been switched off before combat ended.
					if Layout:Manages("stance") then
						ns.PlaceFrame(frame, spot, clamp)
					end
				end)
			else
				ns.PlaceFrame(frame, spot, clamp)
			end
			placed[#placed + 1] = key
			y = y - moduleHeight(key, module, mcfg, frame) - cfg.gap
		end
	end
	self.applying = false
	self.lastPlaced = placed
	return placed
end

--- Module key whose frame this is, or nil.
function Layout:KeyForFrame(frame)
	for key, getFrame in pairs(FRAMES) do
		local module = ns.modules[key]
		if module and getFrame(module) == frame then
			return key
		end
	end
	return nil
end

--- Asks for a new layout (a module changed size, or was switched on or off).
function Layout:Request()
	if self:IsEnabled() then
		self:Apply()
	end
end

--- Places a module: by the layout when it is on, else from its own point.
function ns.PlaceModuleFrame(key, frame, cfg)
	if Layout:Manages(key) then
		Layout:Apply()
		return
	end
	ns.PlaceFrame(frame, cfg.point, cfg.clamp)
end

--- Moves a module up (step < 0) or down (step > 0) in the order.
function Layout:Move(key, step)
	local cfg = self:Config()
	if not cfg then
		return false
	end
	local order = U.DeepCopy(cfg.order)
	local index = U.IndexOf(order, key)
	local target = index and index + step
	if not index or target < 1 or target > #order then
		return false
	end
	table.remove(order, index)
	table.insert(order, target, key)
	ns.DB:Set("general.layout.order", order)
	return true
end
