--[[
Warrior Master - Core/Database.lua
Saved variables and profiles.

WarriorMasterDB (account-wide)
  schemaVersion  number
  global         { language }
  profiles       { [name] = profile }   -- see Core/Schema.lua
  profileKeys    { ["Name - Realm"] = profileName }
WarriorMasterCharDB (per character)
  loadouts       weapons chosen for each stance (item IDs belong to a character)
  macro          last macro builder state

At login every table is rebuilt through the schema, so a corrupted or
hand-edited file can never feed invalid values to the modules.
]]
local _, ns = ...

local U = ns.Util
local S = ns.Schema

local DB = {}
ns.DB = DB

DB.SCHEMA_VERSION = 1
DB.DEFAULT_PROFILE = "Default"
DB.MAX_PROFILES = 40
DB.MAX_NAME = 32

--- Cleans a profile name; returns nil if nothing usable is left.
function DB.CleanProfileName(name)
	if type(name) ~= "string" then
		return nil
	end
	local clean = U.Utf8Sub(U.Trim(U.StripControl(name)), DB.MAX_NAME)
	clean = U.Trim(clean)
	if clean == "" then
		return nil
	end
	return clean
end

local function characterKey()
	local name = UnitName and UnitName("player")
	local realm = GetRealmName and GetRealmName()
	if ns.Compat.IsSecret(name) or type(name) ~= "string" then
		name = "Unknown"
	end
	if ns.Compat.IsSecret(realm) or type(realm) ~= "string" then
		realm = "Realm"
	end
	return name .. " - " .. realm
end

function DB:Init()
	local raw = WarriorMasterDB
	if type(raw) ~= "table" then
		raw = {}
	end

	local store = {
		schemaVersion = DB.SCHEMA_VERSION,
		global = S.Sanitize(S.global, raw.global),
		profiles = {},
		profileKeys = {},
	}

	if type(raw.profiles) == "table" then
		local count = 0
		for _, name in ipairs(U.SortedKeys(raw.profiles)) do
			local clean = DB.CleanProfileName(name)
			if clean and not store.profiles[clean] and count < DB.MAX_PROFILES then
				store.profiles[clean] = S.Sanitize(S.profile, raw.profiles[name])
				count = count + 1
			end
		end
	end
	if not store.profiles[DB.DEFAULT_PROFILE] then
		store.profiles[DB.DEFAULT_PROFILE] = S.Defaults(S.profile)
	end

	if type(raw.profileKeys) == "table" then
		for key, value in pairs(raw.profileKeys) do
			if type(key) == "string" and #key <= 128 and type(value) == "string" and store.profiles[value] then
				store.profileKeys[key] = value
			end
		end
	end

	WarriorMasterDB = store

	local char = S.Sanitize(S.char, WarriorMasterCharDB)
	char.schemaVersion = DB.SCHEMA_VERSION
	WarriorMasterCharDB = char

	self.charKey = characterKey()
	local active = store.profileKeys[self.charKey]
	if not active or not store.profiles[active] then
		active = DB.DEFAULT_PROFILE
		store.profileKeys[self.charKey] = active
	end

	ns.db = {
		store = store,
		global = store.global,
		char = char,
		profile = store.profiles[active],
		profileName = active,
	}
end

-- Settings access ------------------------------------------------------------------------
function DB:Get(path)
	return U.GetPath(ns.db.profile, path)
end

--- Validates and stores one profile value, then notifies the modules.
function DB:Set(path, value)
	local leaf = S.GetLeaf(S.profile, path)
	if not leaf then
		error("unknown setting: " .. tostring(path), 2)
	end
	local clean = S.SanitizeLeaf(leaf, value)
	if type(clean) == "table" then
		clean = U.DeepCopy(clean)
	end
	local profile = ns.db.profile
	U.SetPath(profile, path, clean)
	-- Changing a styled setting by hand makes that module "Custom".
	if ns.Presets.IsVisualPath(path) then
		profile[path:match("^(%w+)")].style = "Custom"
	end
	ns:SendMessage("SETTINGS_CHANGED", path)
	return clean
end

function DB:GetChar(path)
	return U.GetPath(ns.db.char, path)
end

function DB:SetChar(path, value)
	local leaf = S.GetLeaf(S.char, path)
	if not leaf then
		error("unknown character setting: " .. tostring(path), 2)
	end
	U.SetPath(ns.db.char, path, U.DeepCopy(S.SanitizeLeaf(leaf, value)))
	ns:SendMessage("CHAR_SETTINGS_CHANGED", path)
end

-- Profiles ----------------------------------------------------------------------------------
function DB:ListProfiles()
	return U.SortedKeys(ns.db.store.profiles)
end

function DB:GetProfileName()
	return ns.db.profileName
end

function DB:CountProfiles()
	local n = 0
	for _ in pairs(ns.db.store.profiles) do
		n = n + 1
	end
	return n
end

local function activate(name)
	ns.db.profileName = name
	ns.db.profile = ns.db.store.profiles[name]
	ns.db.store.profileKeys[DB.charKey] = name
	ns:SendMessage("PROFILE_CHANGED", name)
end

function DB:SetProfile(name)
	if not ns.db.store.profiles[name] then
		return false, "PROFILE_ERR_MISSING"
	end
	activate(name)
	return true
end

--- Creates a profile (empty defaults, or a copy of another one) and activates it.
function DB:CreateProfile(name, copyFrom)
	local clean = DB.CleanProfileName(name)
	if not clean then
		return false, "PROFILE_ERR_NAME"
	end
	if ns.db.store.profiles[clean] then
		return false, "PROFILE_ERR_EXISTS"
	end
	if self:CountProfiles() >= DB.MAX_PROFILES then
		return false, "PROFILE_ERR_NAME"
	end
	local source = copyFrom and ns.db.store.profiles[copyFrom]
	ns.db.store.profiles[clean] = S.Sanitize(S.profile, source)
	activate(clean)
	return true, clean
end

function DB:CopyIntoActive(fromName)
	local source = ns.db.store.profiles[fromName]
	if not source then
		return false, "PROFILE_ERR_MISSING"
	end
	local name = ns.db.profileName
	ns.db.store.profiles[name] = S.Sanitize(S.profile, source)
	activate(name)
	return true
end

function DB:DeleteProfile(name)
	if name == DB.DEFAULT_PROFILE then
		return false, "PROFILE_ERR_DEFAULT"
	end
	if not ns.db.store.profiles[name] then
		return false, "PROFILE_ERR_MISSING"
	end
	ns.db.store.profiles[name] = nil
	for key, value in pairs(ns.db.store.profileKeys) do
		if value == name then
			ns.db.store.profileKeys[key] = DB.DEFAULT_PROFILE
		end
	end
	if ns.db.profileName == name then
		activate(DB.DEFAULT_PROFILE)
	end
	return true
end

function DB:ResetProfile()
	local name = ns.db.profileName
	ns.db.store.profiles[name] = S.Defaults(S.profile)
	activate(name)
end

--- Restores one section ("rage", "health", "swing", "stance") to defaults.
function DB:ResetSection(section)
	local spec = S.profile[section]
	if type(spec) ~= "table" or S.IsLeaf(spec) then
		return false
	end
	ns.db.profile[section] = S.Defaults(spec)
	ns:SendMessage("SETTINGS_CHANGED", section)
	return true
end

-- Import / export ------------------------------------------------------------------------------
function DB:ExportProfile()
	local data = U.DeepCopy(ns.db.profile)
	data.customVisual = nil
	return ns.Serializer.Export({ kind = "WarriorMasterProfile", version = DB.SCHEMA_VERSION, data = data })
end

local IMPORT_ERRORS = {
	format = "IMPORT_ERR_FORMAT",
	checksum = "IMPORT_ERR_CHECKSUM",
	parse = "IMPORT_ERR_PARSE",
	size = "IMPORT_ERR_SIZE",
}

--- Imports a profile under a new name. Returns ok, nameOrErrorKey, fixedCount.
function DB:ImportProfile(text, name)
	local clean = DB.CleanProfileName(name)
	if not clean then
		return false, "PROFILE_ERR_NAME"
	end
	if ns.db.store.profiles[clean] then
		return false, "PROFILE_ERR_EXISTS"
	end
	if self:CountProfiles() >= DB.MAX_PROFILES then
		return false, "PROFILE_ERR_NAME"
	end
	local ok, payload = ns.Serializer.Import(text)
	if not ok then
		return false, IMPORT_ERRORS[payload] or "IMPORT_ERR_PARSE"
	end
	if payload.kind ~= "WarriorMasterProfile" or type(payload.data) ~= "table" then
		return false, "IMPORT_ERR_FORMAT"
	end
	local stats = { fixed = 0 }
	local profile = S.Sanitize(S.profile, payload.data, stats)
	profile.customVisual = nil
	ns.db.store.profiles[clean] = profile
	activate(clean)
	return true, clean, stats.fixed
end

-- Account-wide settings -------------------------------------------------------------------------
function DB:SetLanguage(code)
	if not U.IndexOf(S.LANGUAGES, code) then
		return false
	end
	ns.db.global.language = code
	ns:ApplyLocale(code == "auto" and (GetLocale and GetLocale()) or code)
	ns:SendMessage("LANGUAGE_CHANGED", code)
	return true
end
