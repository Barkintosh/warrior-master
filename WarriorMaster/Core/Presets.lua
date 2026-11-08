--[[
Warrior Master - Core/Presets.lua
Applies the visual styles of Core/Styles.lua to a profile.

- A style can be applied to every module or to one, and in full or only
  some of its parts (look, colors, fonts, sizes).
- Each module remembers which style it shows (profile.<module>.style).
  Changing any styled setting by hand turns that module into "Custom".
- The player's own look is never lost: before a style replaces a "Custom"
  module, its current look is stored in profile.customVisual[module], and
  applying "Custom" brings it back.
- Positions, thresholds, alerts, visibility and behaviour are never touched.
]]
local _, ns = ...

local U = ns.Util
local S = ns.Schema
local Styles = ns.Styles

local P = {}
ns.Presets = P

P.ORDER = S.PRESET_KEYS
P.LABEL_KEYS = Styles.LABEL_KEYS
P.SECTIONS = Styles.SECTIONS
P.PARTS = Styles.PARTS

local function allParts()
	local set = {}
	for _, part in ipairs(Styles.PARTS) do
		set[part] = true
	end
	return set
end

local function isStyledKey(section, key)
	for _, k in ipairs(Styles.AllKeys(section)) do
		if k == key then
			return true
		end
	end
	return false
end

--- True if a setting path ("rage.texture", "health.alert.color") is styled.
function P.IsVisualPath(path)
	local section, key = path:match("^(%w+)%.(.+)$")
	if not section or not U.IndexOf(Styles.SECTIONS, section) then
		return false
	end
	return isStyledKey(section, key)
end

--- Copies the styled settings of one module.
function P.ExtractSection(profile, section)
	local out = {}
	for _, key in ipairs(Styles.AllKeys(section)) do
		out[key] = U.DeepCopy(U.GetPath(profile[section], key))
	end
	return out
end

local function sanitizeSection(section, values)
	if type(values) ~= "table" then
		return nil
	end
	local out = {}
	for _, key in ipairs(Styles.AllKeys(section)) do
		local leaf = S.GetLeaf(S.profile, section .. "." .. key)
		if leaf and values[key] ~= nil then
			out[key] = S.SanitizeLeaf(leaf, values[key])
		end
	end
	return out
end

--- Keeps only known styled fields of known modules, each validated.
function P.SanitizeVisual(value)
	if type(value) ~= "table" then
		return nil
	end
	local out = {}
	for _, section in ipairs(Styles.SECTIONS) do
		out[section] = sanitizeSection(section, value[section])
	end
	return out
end

local function writeValues(profile, section, values)
	for key, value in pairs(values) do
		local leaf = S.GetLeaf(S.profile, section .. "." .. key)
		if leaf then
			U.SetPath(profile[section], key, U.DeepCopy(S.SanitizeLeaf(leaf, value)))
		end
	end
end

--- Applies a style.
-- opts.sections: list of modules (default: all); opts.parts: set of parts (default: all).
-- Returns true on success, false for an unknown style or an empty part set.
function P.Apply(profile, name, opts)
	opts = opts or {}
	if name ~= "Custom" and not Styles.data[name] then
		return false
	end
	local sections = opts.sections or Styles.SECTIONS
	local parts = opts.parts or allParts()
	local complete, any = true, false
	for _, part in ipairs(Styles.PARTS) do
		if parts[part] then
			any = true
		else
			complete = false
		end
	end
	if not any then
		return false
	end
	profile.customVisual = profile.customVisual or {}
	for _, section in ipairs(sections) do
		local cfg = profile[section]
		if cfg then
			if name == "Custom" then
				local saved = profile.customVisual[section]
				if saved then
					writeValues(profile, section, saved)
				end
				cfg.style = "Custom"
			else
				if cfg.style == "Custom" then
					profile.customVisual[section] = P.ExtractSection(profile, section)
				end
				for _, part in ipairs(Styles.PARTS) do
					if parts[part] then
						writeValues(profile, section, Styles.Get(name, section, part))
					end
				end
				cfg.style = complete and name or "Custom"
			end
		end
	end
	return true
end
