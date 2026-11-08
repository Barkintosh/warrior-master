--[[
Warrior Master - Config/Controls.lua
Self-contained widget kit for the settings window: checkbox, slider,
dropdown, color swatch, button, single- and multi-line text fields, and a
two-column layout helper.

Built only from basic frame types (no UIDropDownMenu or other shared
Blizzard menu code), so the settings window cannot taint Blizzard UI.
Every control is bound through get/set functions and exposes Refresh(), so a
page can redraw itself after a profile change.
]]
local _, ns = ...

local Theme = ns.Theme
local Media = ns.Media
local U = ns.Util

local UI = {}
ns.UI = UI

local ROW_GAP = 6
local PAD = 14
local COL_GAP = 12

-- Binding helpers --------------------------------------------------------------------------------
function UI.Bind(path)
	return function()
		return ns.DB:Get(path)
	end, function(value)
		ns.DB:Set(path, value)
	end
end

--- Binds the alpha component of a color setting (for opacity sliders).
function UI.BindAlpha(path)
	return function()
		local c = ns.DB:Get(path)
		return c and c.a or 1
	end, function(value)
		local c = U.DeepCopy(ns.DB:Get(path))
		c.a = value
		ns.DB:Set(path, c)
	end
end

--- Binds one coordinate of a stored point.
function UI.BindPoint(path, axis)
	return function()
		local p = ns.DB:Get(path)
		return p and p[axis] or 0
	end, function(value)
		local p = U.DeepCopy(ns.DB:Get(path))
		p.point, p.relPoint = "CENTER", "CENTER"
		p[axis] = value
		ns.DB:Set(path, p)
	end
end

local function attachTooltip(frame, text)
	if not text then
		return
	end
	frame:HookScript("OnEnter", function(self)
		if GameTooltip then
			GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
			GameTooltip:SetText(text, 1, 1, 1, 1, true)
			GameTooltip:Show()
		end
	end)
	frame:HookScript("OnLeave", function()
		if GameTooltip then
			GameTooltip:Hide()
		end
	end)
end

local function newControl(page, frame, height)
	local control = { frame = frame, height = height, page = page }
	page.controls[#page.controls + 1] = control
	return control
end

local function isDisabled(o)
	return o.disabled ~= nil and o.disabled() == true
end

local function setDimmed(frame, dimmed)
	frame:SetAlpha(dimmed and 0.4 or 1)
end

-- Checkbox -----------------------------------------------------------------------------------------
function UI.Checkbox(page, o)
	local f = CreateFrame("Button", nil, page.content)
	f:SetHeight(20)
	local box = CreateFrame("Frame", nil, f, "BackdropTemplate")
	box:SetSize(14, 14)
	box:SetPoint("LEFT", 0, 0)
	Theme.Border(box)
	local check = box:CreateTexture(nil, "ARTWORK")
	check:SetPoint("TOPLEFT", 3, -3)
	check:SetPoint("BOTTOMRIGHT", -3, 3)
	check:SetColorTexture(Theme.Color("accent"))
	local label = Theme.Text(f, Theme.SIZE_TEXT)
	label:SetPoint("LEFT", box, "RIGHT", 8, 0)
	label:SetPoint("RIGHT", f, "RIGHT", 0, 0)
	label:SetWordWrap(false)
	label:SetText(o.label)

	local control = newControl(page, f, 20)
	control.kind = "check"
	control.measure = function()
		return label:GetStringWidth() + 26
	end
	function control.SetLabel(text)
		label:SetText(text)
	end
	f:SetScript("OnClick", function()
		if isDisabled(o) then
			return
		end
		o.set(not o.get())
		page:Refresh()
	end)
	f:SetScript("OnEnter", function()
		box:SetBackdropBorderColor(Theme.Color("accent"))
	end)
	f:SetScript("OnLeave", function()
		box:SetBackdropBorderColor(Theme.Color("border"))
	end)
	attachTooltip(f, o.tooltip)
	function control.Refresh()
		check:SetShown(o.get() and true or false)
		setDimmed(f, isDisabled(o))
	end
	return control
end

-- Slider ---------------------------------------------------------------------------------------------
local function formatNumber(value, step)
	if step and step < 1 then
		local decimals = step < 0.1 and 2 or 1
		return string.format("%." .. decimals .. "f", value)
	end
	return string.format("%d", math.floor(value + 0.5))
end

function UI.Slider(page, o)
	local f = CreateFrame("Frame", nil, page.content)
	f:SetHeight(36)
	local label = Theme.Text(f, Theme.SIZE_TEXT)
	label:SetPoint("TOPLEFT", 0, 0)
	label:SetText(o.label)

	local box = CreateFrame("EditBox", nil, f, "BackdropTemplate")
	box:SetSize(50, 16)
	box:SetPoint("TOPRIGHT", 0, 2)
	Theme.Border(box)
	box:SetAutoFocus(false)
	box:SetFont(Theme.FONT, Theme.SIZE_SMALL, "")
	box:SetTextColor(Theme.Color("text"))
	box:SetJustifyH("CENTER")
	box:SetMaxLetters(8)

	local slider = CreateFrame("Slider", nil, f)
	slider:SetOrientation("HORIZONTAL")
	slider:SetPoint("TOPLEFT", 0, -19)
	slider:SetPoint("TOPRIGHT", 0, -19)
	slider:SetHeight(16)
	slider:SetMinMaxValues(o.min, o.max)
	slider:SetValueStep(o.step or 1)
	slider:SetObeyStepOnDrag(true)
	slider:EnableMouseWheel(true)

	local track = slider:CreateTexture(nil, "BACKGROUND")
	track:SetPoint("LEFT", 0, 0)
	track:SetPoint("RIGHT", 0, 0)
	track:SetHeight(4)
	track:SetColorTexture(Theme.Color("field"))
	slider:SetThumbTexture(Media.WHITE)
	local thumb = slider:GetThumbTexture()
	thumb:SetSize(8, 16)
	thumb:SetVertexColor(Theme.Color("accent"))
	local fill = slider:CreateTexture(nil, "ARTWORK")
	fill:SetPoint("LEFT", track, "LEFT", 0, 0)
	fill:SetPoint("RIGHT", thumb, "CENTER", 0, 0)
	fill:SetHeight(4)
	fill:SetColorTexture(Theme.Color("accentSoft"))

	local control = newControl(page, f, 36)
	local updating = false
	local step = o.step or 1

	local function snap(value)
		value = U.Clamp(value, o.min, o.max)
		return U.Round(value / step) * step
	end

	local function commit(value)
		if isDisabled(o) then
			control.Refresh()
			return
		end
		value = snap(value)
		if value ~= o.get() then
			o.set(value)
		end
		box:SetText(formatNumber(value, step))
		if o.refreshPage then
			page:Refresh()
		end
	end

	slider:SetScript("OnValueChanged", function(_, value)
		if updating then
			return
		end
		commit(value)
	end)
	slider:SetScript("OnMouseWheel", function(_, delta)
		if isDisabled(o) then
			return
		end
		updating = true
		local value = snap(o.get() + delta * step)
		slider:SetValue(value)
		updating = false
		commit(value)
	end)
	box:SetScript("OnEnterPressed", function(self)
		local value = tonumber(self:GetText())
		self:ClearFocus()
		if value then
			updating = true
			slider:SetValue(snap(value))
			updating = false
			commit(value)
		else
			control.Refresh()
		end
	end)
	box:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
		control.Refresh()
	end)
	attachTooltip(f, o.tooltip)

	function control.Refresh()
		local value = o.get() or o.min
		updating = true
		slider:SetValue(value)
		updating = false
		box:SetText(formatNumber(value, step))
		local disabled = isDisabled(o)
		slider:EnableMouse(not disabled)
		box:EnableMouse(not disabled)
		setDimmed(f, disabled)
	end
	return control
end

-- Dropdown menu (one shared popup) ---------------------------------------------------------------------
local menu
local MENU_ROW = 20
local MENU_MAX_ROWS = 14

local function ensureMenu()
	if menu then
		return menu
	end
	local catcher = CreateFrame("Button", nil, UIParent)
	catcher:SetAllPoints(UIParent)
	catcher:SetFrameStrata("FULLSCREEN_DIALOG")
	catcher:RegisterForClicks("AnyUp")
	catcher:Hide()

	menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
	menu:SetFrameStrata("FULLSCREEN_DIALOG")
	menu:SetFrameLevel(catcher:GetFrameLevel() + 10)
	menu:SetClampedToScreen(true)
	Theme.Border(menu, "accent")
	menu:SetBackdropColor(Theme.Color("panel"))
	menu:EnableMouseWheel(true)
	menu:Hide()
	menu.catcher = catcher
	menu.rows = {}
	menu.offset = 0

	catcher:SetScript("OnClick", function()
		UI.CloseMenu()
	end)
	menu:SetScript("OnMouseWheel", function(_, delta)
		local maxOffset = math.max(0, #menu.items - MENU_MAX_ROWS)
		menu.offset = U.Clamp(menu.offset - delta, 0, maxOffset)
		UI.DrawMenu()
	end)
	menu:SetScript("OnHide", function()
		catcher:Hide()
	end)
	return menu
end

function UI.CloseMenu()
	if menu and menu:IsShown() then
		menu:Hide()
		return true
	end
	return false
end

function UI.DrawMenu()
	local count = math.min(#menu.items, MENU_MAX_ROWS)
	for i = 1, math.max(count, #menu.rows) do
		local row = menu.rows[i]
		if i <= count then
			if not row then
				row = CreateFrame("Button", nil, menu)
				row:SetHeight(MENU_ROW)
				row.hl = row:CreateTexture(nil, "HIGHLIGHT")
				row.hl:SetAllPoints()
				row.hl:SetColorTexture(Theme.Color("accentSoft"))
				row.text = Theme.Text(row, Theme.SIZE_TEXT)
				row.text:SetPoint("LEFT", 8, 0)
				row.text:SetPoint("RIGHT", -8, 0)
				row.text:SetWordWrap(false)
				row:SetScript("OnClick", function(self)
					local callback, value = menu.onSelect, self.value
					UI.CloseMenu()
					callback(value)
				end)
				menu.rows[i] = row
			end
			local item = menu.items[i + menu.offset]
			row.value = item.value
			row.text:SetText(item.text)
			if item.value == menu.current then
				row.text:SetTextColor(Theme.Color("accent"))
			else
				row.text:SetTextColor(Theme.Color("text"))
			end
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", 2, -2 - (i - 1) * MENU_ROW)
			row:SetPoint("TOPRIGHT", -2, -2 - (i - 1) * MENU_ROW)
			row:Show()
		elseif row then
			row:Hide()
		end
	end
	menu:SetHeight(count * MENU_ROW + 4)
end

function UI.OpenMenu(anchor, items, current, onSelect)
	ensureMenu()
	if menu:IsShown() and menu.anchor == anchor then
		UI.CloseMenu()
		return
	end
	menu.anchor = anchor
	menu.items = items
	menu.current = current
	menu.onSelect = onSelect
	menu.offset = 0
	local index = nil
	for i, item in ipairs(items) do
		if item.value == current then
			index = i
		end
	end
	if index and index > MENU_MAX_ROWS then
		menu.offset = math.min(index - 1, #items - MENU_MAX_ROWS)
	end
	menu:ClearAllPoints()
	menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
	menu:SetWidth(math.max(anchor:GetWidth(), 140))
	UI.DrawMenu()
	menu.catcher:Show()
	menu:Show()
end

-- Dropdown ------------------------------------------------------------------------------------------
--- o.options: function returning { { value = v, text = "..." }, ... }
function UI.Dropdown(page, o)
	local f = CreateFrame("Frame", nil, page.content)
	f:SetHeight(38)
	local label = Theme.Text(f, Theme.SIZE_TEXT)
	label:SetPoint("TOPLEFT", 0, 0)
	label:SetText(o.label)

	local button = CreateFrame("Button", nil, f, "BackdropTemplate")
	button:SetPoint("TOPLEFT", 0, -15)
	button:SetPoint("TOPRIGHT", 0, -15)
	button:SetHeight(22)
	Theme.Border(button)
	local text = Theme.Text(button, Theme.SIZE_TEXT)
	text:SetPoint("LEFT", 8, 0)
	text:SetPoint("RIGHT", -22, 0)
	text:SetWordWrap(false)
	local arrow = Theme.Text(button, Theme.SIZE_SMALL, "accent")
	arrow:SetPoint("RIGHT", -8, 0)
	arrow:SetText("v")

	local control = newControl(page, f, 38)
	function control.SetLabel(text)
		label:SetText(text)
	end
	button:SetScript("OnClick", function(self)
		if isDisabled(o) then
			return
		end
		UI.OpenMenu(self, o.options(), o.get(), function(value)
			o.set(value)
			page:Refresh()
		end)
	end)
	button:SetScript("OnEnter", function(self)
		self:SetBackdropBorderColor(Theme.Color("accent"))
	end)
	button:SetScript("OnLeave", function(self)
		self:SetBackdropBorderColor(Theme.Color("border"))
	end)
	attachTooltip(button, o.tooltip)

	function control.Refresh()
		local current = o.get()
		local shown = ""
		for _, item in ipairs(o.options()) do
			if item.value == current then
				shown = item.text
			end
		end
		text:SetText(shown)
		setDimmed(f, isDisabled(o))
	end
	return control
end

--- Builds dropdown items from a list of values and a value -> label key map.
function UI.Options(values, labelKeys)
	return function()
		local items = {}
		for _, value in ipairs(values) do
			local key = labelKeys and labelKeys[value]
			items[#items + 1] = { value = value, text = key and ns.L[key] or tostring(value) }
		end
		return items
	end
end

-- Color swatch ------------------------------------------------------------------------------------------
function UI.Color(page, o)
	local f = CreateFrame("Button", nil, page.content)
	f:SetHeight(20)
	local swatch = CreateFrame("Frame", nil, f, "BackdropTemplate")
	swatch:SetSize(26, 14)
	swatch:SetPoint("LEFT", 0, 0)
	Theme.Border(swatch)
	local color = swatch:CreateTexture(nil, "ARTWORK")
	color:SetPoint("TOPLEFT", 2, -2)
	color:SetPoint("BOTTOMRIGHT", -2, 2)
	local label = Theme.Text(f, Theme.SIZE_TEXT)
	label:SetPoint("LEFT", swatch, "RIGHT", 8, 0)
	label:SetPoint("RIGHT", f, "RIGHT", 0, 0)
	label:SetWordWrap(false)
	label:SetText(o.label)

	local control = newControl(page, f, 20)
	control.kind = "color"
	control.measure = function()
		return label:GetStringWidth() + 38
	end
	f:SetScript("OnClick", function()
		if isDisabled(o) then
			return
		end
		local picker = ColorPickerFrame
		if not (picker and picker.SetupColorPickerAndShow and picker.GetColorRGB) then
			return
		end
		local start = U.DeepCopy(o.get())
		picker:SetupColorPickerAndShow({
			r = start.r,
			g = start.g,
			b = start.b,
			hasOpacity = false,
			swatchFunc = function()
				local r, g, b = picker:GetColorRGB()
				o.set({ r = r, g = g, b = b, a = start.a })
				control.Refresh()
			end,
			cancelFunc = function()
				o.set(start)
				control.Refresh()
			end,
		})
	end)
	f:SetScript("OnEnter", function()
		swatch:SetBackdropBorderColor(Theme.Color("accent"))
	end)
	f:SetScript("OnLeave", function()
		swatch:SetBackdropBorderColor(Theme.Color("border"))
	end)
	attachTooltip(f, o.tooltip)

	function control.Refresh()
		local c = o.get()
		if c then
			color:SetColorTexture(c.r, c.g, c.b, 1)
		end
		setDimmed(f, isDisabled(o))
	end
	return control
end

-- Button ----------------------------------------------------------------------------------------------
--- o.confirm: require a second click within 4 seconds (destructive actions).
function UI.Button(page, o)
	local b = CreateFrame("Button", nil, page.content, "BackdropTemplate")
	b:SetHeight(22)
	Theme.Border(b)
	local text = Theme.Text(b, Theme.SIZE_TEXT)
	text:SetPoint("CENTER")
	text:SetText(o.text)
	local control = newControl(page, b, 22)
	control.kind = "button"
	control.measure = function()
		return text:GetStringWidth() + 24
	end
	local armed = false

	local function reset()
		armed = false
		text:SetText(o.text)
		text:SetTextColor(Theme.Color("text"))
	end

	b:SetScript("OnClick", function()
		if isDisabled(o) then
			return
		end
		if o.confirm and not armed then
			armed = true
			text:SetText(ns.L.CONFIRM_CLICK)
			text:SetTextColor(Theme.Color("warn"))
			C_Timer.After(4, function()
				if armed then
					reset()
				end
			end)
			return
		end
		reset()
		o.onClick()
		page:Refresh()
	end)
	b:SetScript("OnEnter", function(self)
		self:SetBackdropColor(Theme.Color("fieldHover"))
		self:SetBackdropBorderColor(Theme.Color("accent"))
	end)
	b:SetScript("OnLeave", function(self)
		self:SetBackdropColor(Theme.Color("field"))
		self:SetBackdropBorderColor(Theme.Color("border"))
	end)
	attachTooltip(b, o.tooltip)

	function control.Refresh()
		if o.dynamicText then
			o.text = o.dynamicText()
			if not armed then
				text:SetText(o.text)
			end
		end
		setDimmed(b, isDisabled(o))
	end
	return control
end

-- Single-line text field ------------------------------------------------------------------------------
function UI.EditBox(page, o)
	local f = CreateFrame("Frame", nil, page.content)
	f:SetHeight(38)
	local label = Theme.Text(f, Theme.SIZE_TEXT)
	label:SetPoint("TOPLEFT", 0, 0)
	label:SetText(o.label)
	local box = CreateFrame("EditBox", nil, f, "BackdropTemplate")
	box:SetPoint("TOPLEFT", 0, -15)
	box:SetPoint("TOPRIGHT", 0, -15)
	box:SetHeight(22)
	Theme.Border(box)
	box:SetAutoFocus(false)
	box:SetFont(Theme.FONT, Theme.SIZE_TEXT, "")
	box:SetTextColor(Theme.Color("text"))
	box:SetTextInsets(8, 8, 0, 0)
	box:SetMaxLetters(o.maxLetters or 64)

	local control = newControl(page, f, 38)
	local function commit(self)
		self:ClearFocus()
		if not isDisabled(o) then
			o.set(self:GetText())
		end
		control.Refresh()
	end
	box:SetScript("OnEnterPressed", commit)
	box:SetScript("OnEditFocusLost", function(self)
		if o.commitOnBlur ~= false then
			if not isDisabled(o) then
				o.set(self:GetText())
			end
		end
	end)
	box:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
		control.Refresh()
	end)
	control.box = box
	function control.Refresh()
		if not box:HasFocus() then
			box:SetText(o.get() or "")
		end
		setDimmed(f, isDisabled(o))
	end
	return control
end

-- Multi-line text area ------------------------------------------------------------------------------------
function UI.TextArea(page, o)
	local f = CreateFrame("Frame", nil, page.content, "BackdropTemplate")
	f:SetHeight(o.height or 120)
	Theme.Border(f)
	local scroll = CreateFrame("ScrollFrame", nil, f)
	scroll:SetPoint("TOPLEFT", 8, -6)
	scroll:SetPoint("BOTTOMRIGHT", -8, 6)
	local box = CreateFrame("EditBox", nil, scroll)
	box:SetMultiLine(true)
	box:SetAutoFocus(false)
	box:SetFont(Theme.FONT, Theme.SIZE_SMALL, "")
	box:SetTextColor(Theme.Color("text"))
	box:SetMaxLetters(o.maxLetters or 0)
	box:SetWidth(200)
	scroll:SetScrollChild(box)

	local control = newControl(page, f, o.height or 120)
	control.box = box
	control.value = ""

	scroll:SetScript("OnSizeChanged", function(self, width)
		box:SetWidth(math.max(50, width))
	end)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local range = self:GetVerticalScrollRange()
		self:SetVerticalScroll(U.Clamp(self:GetVerticalScroll() - delta * 24, 0, range))
	end)
	box:SetScript("OnCursorChanged", function(_, _, y, _, h)
		local offset = scroll:GetVerticalScroll()
		local height = scroll:GetHeight()
		y = -y
		if y < offset then
			scroll:SetVerticalScroll(y)
		elseif y + h > offset + height then
			scroll:SetVerticalScroll(y + h - height)
		end
	end)
	box:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)
	box:SetScript("OnTextChanged", function(self, userInput)
		if not userInput then
			return
		end
		if o.readOnly then
			self:SetText(control.value)
			self:HighlightText()
		else
			control.value = self:GetText()
			if o.onChange then
				o.onChange(control.value)
			end
		end
	end)
	f:EnableMouse(true)
	f:SetScript("OnMouseDown", function()
		box:SetFocus()
	end)

	function control.SetValue(text)
		control.value = text or ""
		box:SetText(control.value)
		scroll:SetVerticalScroll(0)
	end
	function control.GetValue()
		return control.value
	end
	function control.SelectAll()
		box:SetFocus()
		box:HighlightText()
	end
	function control.Refresh()
		if o.get and not box:HasFocus() then
			control.SetValue(o.get())
		end
	end
	return control
end

-- Text (static or dynamic) -------------------------------------------------------------------------------
--- o.text: string, or o.get: function returning text, colorName
function UI.Text(page, o)
	local f = CreateFrame("Frame", nil, page.content)
	local fs = Theme.Text(f, o.size or Theme.SIZE_TEXT, o.color or "dim")
	fs:SetPoint("TOPLEFT", 0, 0)
	fs:SetPoint("TOPRIGHT", 0, 0)
	fs:SetJustifyH("LEFT")
	fs:SetJustifyV("TOP")
	fs:SetWordWrap(true)
	local control = newControl(page, f, o.height or 16)
	control.fs = fs
	control.fixedHeight = o.height
	function control.Refresh()
		if o.get then
			local text, color = o.get()
			fs:SetText(text or "")
			if color then
				fs:SetTextColor(Theme.Color(color))
			end
		end
	end
	if o.text then
		fs:SetText(o.text)
	end
	return control
end

-- Page and layout --------------------------------------------------------------------------------------------
-- Controls flow left to right on a 6-unit grid: sliders, dropdowns and text
-- fields take half a row; checkboxes, color swatches and buttons take a
-- third (or half, or a full row, if their label needs it). A row wraps when
-- the next control does not fit.
local UNITS = 6
local Page = {}
Page.__index = Page

function UI.NewPage(content, width)
	local page = setmetatable({ content = content, width = width, controls = {} }, Page)
	page.innerWidth = width - PAD * 2
	page.unitWidth = (page.innerWidth - (UNITS - 1) * COL_GAP) / UNITS
	page.colWidth = math.floor(page:SpanWidth(3))
	page.y = -10
	page.used = 0
	page.rowHeight = 0
	return page
end

function Page:SpanWidth(span)
	return span * self.unitWidth + (span - 1) * COL_GAP
end

function Page:Refresh()
	for _, control in ipairs(self.controls) do
		if control.Refresh then
			local ok, err = pcall(control.Refresh)
			if not ok then
				ns:ReportError(err)
			end
		end
	end
	if self.onRefresh then
		self.onRefresh()
	end
end

function Page:EndRow()
	if self.used > 0 then
		self.y = self.y - self.rowHeight - ROW_GAP
		self.used = 0
		self.rowHeight = 0
	end
end

local function defaultSpan(page, control)
	if control.measure then
		local need = control.measure()
		for _, span in ipairs({ 2, 3, 6 }) do
			if page:SpanWidth(span) >= need then
				return span
			end
		end
		return UNITS
	end
	return 3
end

--- Places a control. full = true (or 6) spans the row; a number sets the span.
function Page:Place(control, full)
	local frame = control.frame
	frame:ClearAllPoints()
	local span = (full == true and UNITS) or (type(full) == "number" and full) or defaultSpan(self, control)
	span = math.max(1, math.min(UNITS, span))
	if span == UNITS then
		self:EndRow()
		frame:SetPoint("TOPLEFT", self.content, "TOPLEFT", PAD, self.y)
		frame:SetWidth(self.innerWidth)
		local height = control.height
		if control.fs and not control.fixedHeight then
			control.fs:SetWidth(self.innerWidth)
			if control.Refresh then
				control.Refresh()
			end
			height = math.max(12, math.ceil(control.fs:GetStringHeight()))
		end
		frame:SetHeight(height)
		self.y = self.y - height - ROW_GAP
		return control
	end
	if self.used + span > UNITS then
		self:EndRow()
	end
	local x = PAD + self.used * (self.unitWidth + COL_GAP)
	frame:SetPoint("TOPLEFT", self.content, "TOPLEFT", x, self.y)
	frame:SetWidth(math.floor(self:SpanWidth(span)))
	frame:SetHeight(control.height)
	self.rowHeight = math.max(self.rowHeight, control.height)
	self.used = self.used + span
	if self.used >= UNITS then
		self:EndRow()
	end
	return control
end

function Page:Header(text)
	self:EndRow()
	self.y = self.y - 4
	local fs = Theme.Text(self.content, Theme.SIZE_HEADER, "accent")
	fs:SetPoint("TOPLEFT", self.content, "TOPLEFT", PAD, self.y)
	fs:SetText(text)
	local line = self.content:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(Theme.Color("border"))
	line:SetHeight(1)
	line:SetPoint("TOPLEFT", self.content, "TOPLEFT", PAD, self.y - 17)
	line:SetPoint("TOPRIGHT", self.content, "TOPRIGHT", -PAD, self.y - 17)
	self.y = self.y - 24
end

function Page:Space(height)
	self:EndRow()
	self.y = self.y - (height or 4)
end

function Page:Finish()
	self:EndRow()
	self.content:SetHeight(-self.y + 12)
end

-- Convenience: create and place in one call.
function Page:Checkbox(o, full) return self:Place(UI.Checkbox(self, o), full) end
function Page:Slider(o, full) return self:Place(UI.Slider(self, o), full) end
function Page:Dropdown(o, full) return self:Place(UI.Dropdown(self, o), full) end
function Page:Color(o, full) return self:Place(UI.Color(self, o), full) end
function Page:Button(o, full) return self:Place(UI.Button(self, o), full) end
function Page:EditBox(o, full) return self:Place(UI.EditBox(self, o), full) end
function Page:TextArea(o) return self:Place(UI.TextArea(self, o), true) end
function Page:Text(o) return self:Place(UI.Text(self, o), true) end
function Page:Note(text, color) return self:Place(UI.Text(self, { text = text, color = color or "dim", size = Theme.SIZE_SMALL }), true) end

--- Ends the current row (the rest of it stays empty).
function Page:Skip()
	self:EndRow()
end
