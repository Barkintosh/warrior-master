--[[
Warrior Master - Config/PageProfiles.lua
Profile selection, creation, copy, deletion, reset, import and export.
]]
local _, ns = ...

local function profileOptions(exclude)
	return function()
		local items = {}
		for _, name in ipairs(ns.DB:ListProfiles()) do
			if name ~= exclude then
				items[#items + 1] = { value = name, text = name }
			end
		end
		return items
	end
end

ns.Config:RegisterPage({
	key = "profiles",
	titleKey = "PAGE_PROFILES",
	order = 70,
	build = function(page)
		local L = ns.L
		local DB = ns.DB
		local state = { newName = "", copyFrom = nil, importName = "", status = "", statusColor = "dim" }

		local function report(ok, message)
			state.status = message or ""
			state.statusColor = ok and "good" or "bad"
			if message and message ~= "" then
				ns:Print(message)
			end
		end

		page:Header(L.PAGE_PROFILES)
		page:Dropdown({
			label = L.PROFILE_CURRENT,
			options = profileOptions(),
			get = function()
				return DB:GetProfileName()
			end,
			set = function(value)
				local ok, err = DB:SetProfile(value)
				report(ok, ok and L.PROFILE_SWITCHED:format(value) or L[err])
			end,
		})
		page:Button({
			text = L.PROFILE_CHAR,
			onClick = function()
				local ok, result = DB:CreateProfile(DB.charKey, DB:GetProfileName())
				report(ok, ok and L.PROFILE_CREATED:format(result) or L[result])
			end,
		})
		page:EditBox({
			label = L.PROFILE_NEW,
			maxLetters = DB.MAX_NAME,
			commitOnBlur = true,
			get = function()
				return state.newName
			end,
			set = function(value)
				state.newName = value
			end,
		})
		page:Button({
			text = L.PROFILE_CREATE,
			onClick = function()
				local ok, result = DB:CreateProfile(state.newName)
				if ok then
					state.newName = ""
				end
				report(ok, ok and L.PROFILE_CREATED:format(result) or L[result])
			end,
		})
		page:Dropdown({
			label = L.PROFILE_COPY,
			options = function()
				return profileOptions(DB:GetProfileName())()
			end,
			get = function()
				return state.copyFrom
			end,
			set = function(value)
				state.copyFrom = value
			end,
		})
		page:Button({
			text = L.PROFILE_COPY,
			confirm = true,
			disabled = function()
				return state.copyFrom == nil or state.copyFrom == DB:GetProfileName()
			end,
			onClick = function()
				local ok, err = DB:CopyIntoActive(state.copyFrom)
				report(ok, ok and L.PROFILE_COPIED:format(state.copyFrom) or L[err])
			end,
		})
		page:Button({
			text = L.PROFILE_RESET,
			confirm = true,
			onClick = function()
				DB:ResetProfile()
				report(true, L.RESET_DONE)
			end,
		})
		page:Button({
			text = L.PROFILE_DELETE,
			confirm = true,
			disabled = function()
				return DB:GetProfileName() == DB.DEFAULT_PROFILE
			end,
			onClick = function()
				local name = DB:GetProfileName()
				local ok, err = DB:DeleteProfile(name)
				report(ok, ok and L.PROFILE_DELETED:format(name) or L[err])
			end,
		})
		page:Text({
			height = 18,
			get = function()
				return state.status, state.statusColor
			end,
		})

		page:Header(L.PROFILE_EXPORT)
		page:Note(L.PROFILE_EXPORT_HINT)
		local export = page:TextArea({ height = 80, readOnly = true })
		page:Button({
			text = L.PROFILE_EXPORT,
			onClick = function()
				export.SetValue(DB:ExportProfile())
				export.SelectAll()
			end,
		})
		page:Skip()

		page:Header(L.PROFILE_IMPORT)
		page:Note(L.PROFILE_IMPORT_HINT)
		local import = page:TextArea({ height = 80, maxLetters = ns.Serializer.MAX_INPUT })
		page:EditBox({
			label = L.PROFILE_IMPORT_NAME,
			maxLetters = DB.MAX_NAME,
			get = function()
				return state.importName
			end,
			set = function(value)
				state.importName = value
			end,
		})
		page:Button({
			text = L.PROFILE_IMPORT,
			onClick = function()
				local ok, result = DB:ImportProfile(import.GetValue(), state.importName)
				if ok then
					import.SetValue("")
					state.importName = ""
					report(true, L.PROFILE_IMPORTED:format(result))
				else
					local reason = L[result]
					if result:match("^IMPORT_ERR") then
						reason = L.PROFILE_IMPORT_FAILED:format(L[result])
					end
					report(false, reason)
				end
			end,
		})
	end,
})
