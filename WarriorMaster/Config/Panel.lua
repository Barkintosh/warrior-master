--[[
Warrior Master - Config/Panel.lua
Main settings window (/uw): title bar, page navigation, scrolling content
and a footer with quick toggles. Pages register themselves with
Config:RegisterPage and are built the first time they are shown.
]]
local ADDON_NAME, ns = ...

local Theme = ns.Theme
local UI = ns.UI
local U = ns.Util

local Config = {}
ns.Config = Config

Config.pages = {}
Config.WIDTH = 860
Config.HEIGHT = 640
Config.NAV_WIDTH = 168

function Config:RegisterPage(def)
	self.pages[#self.pages + 1] = def
	table.sort(self.pages, function(a, b)
		return a.order < b.order
	end)
end

local function navButton(parent)
	local b = CreateFrame("Button", nil, parent)
	b:SetHeight(26)
	b.bg = b:CreateTexture(nil, "BACKGROUND")
	b.bg:SetAllPoints()
	b.bg:SetColorTexture(0, 0, 0, 0)
	b.bar = b:CreateTexture(nil, "ARTWORK")
	b.bar:SetPoint("TOPLEFT")
	b.bar:SetPoint("BOTTOMLEFT")
	b.bar:SetWidth(3)
	b.bar:SetColorTexture(Theme.Color("accent"))
	b.text = Theme.Text(b, Theme.SIZE_TEXT)
	b.text:SetPoint("LEFT", 14, 0)
	b.text:SetPoint("RIGHT", -8, 0)
	b.text:SetWordWrap(false)
	b:SetScript("OnEnter", function(self)
		if not self.selected then
			self.bg:SetColorTexture(1, 1, 1, 0.04)
		end
	end)
	b:SetScript("OnLeave", function(self)
		if not self.selected then
			self.bg:SetColorTexture(0, 0, 0, 0)
		end
	end)
	return b
end

local function setSelected(b, selected)
	b.selected = selected
	b.bar:SetShown(selected)
	if selected then
		b.bg:SetColorTexture(Theme.Color("accentSoft"))
		b.text:SetTextColor(Theme.Color("text"))
	else
		b.bg:SetColorTexture(0, 0, 0, 0)
		b.text:SetTextColor(Theme.Color("dim"))
	end
end

local function footerButton(parent, onClick)
	local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
	b:SetSize(150, 22)
	Theme.Border(b)
	b.text = Theme.Text(b, Theme.SIZE_SMALL)
	b.text:SetPoint("CENTER")
	b:SetScript("OnClick", onClick)
	b:SetScript("OnEnter", function(self)
		self:SetBackdropBorderColor(Theme.Color("accent"))
	end)
	b:SetScript("OnLeave", function(self)
		self:SetBackdropBorderColor(Theme.Color("border"))
	end)
	return b
end

function Config:Create()
	if self.frame then
		return self.frame
	end
	local f = CreateFrame("Frame", "WarriorMasterConfig", UIParent, "BackdropTemplate")
	f:SetSize(self.WIDTH, self.HEIGHT)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:SetBackdrop({ bgFile = ns.Media.WHITE, edgeFile = ns.Media.WHITE, edgeSize = 1 })
	f:SetBackdropColor(Theme.Color("bg"))
	f:SetBackdropBorderColor(Theme.Color("border"))
	f:Hide()
	self.frame = f

	-- Title bar (drag to move)
	local title = CreateFrame("Frame", nil, f)
	title:SetPoint("TOPLEFT", 1, -1)
	title:SetPoint("TOPRIGHT", -1, -1)
	title:SetHeight(36)
	Theme.Fill(title, "panel")
	title:EnableMouse(true)
	title:RegisterForDrag("LeftButton")
	title:SetScript("OnDragStart", function()
		f:StartMoving()
	end)
	title:SetScript("OnDragStop", function()
		f:StopMovingOrSizing()
	end)
	local icon = title:CreateTexture(nil, "ARTWORK")
	icon:SetSize(24, 24)
	icon:SetPoint("LEFT", 14, 0)
	icon:SetTexture("Interface\\Icons\\Ability_Warrior_BattleShout")
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local name = Theme.Text(title, Theme.SIZE_TITLE, "accent")
	name:SetPoint("LEFT", icon, "RIGHT", 10, 0)
	name:SetText("Warrior Master")
	self.versionText = Theme.Text(title, Theme.SIZE_SMALL, "dim")
	self.versionText:SetPoint("LEFT", name, "RIGHT", 10, -1)

	local close = CreateFrame("Button", nil, title)
	close:SetSize(32, 32)
	close:SetPoint("RIGHT", -6, 0)
	local closeText = Theme.Text(close, 18, "dim")
	closeText:SetPoint("CENTER")
	closeText:SetText("x")
	close:SetScript("OnClick", function()
		Config:Hide()
	end)
	close:SetScript("OnEnter", function()
		closeText:SetTextColor(Theme.Color("text"))
	end)
	close:SetScript("OnLeave", function()
		closeText:SetTextColor(Theme.Color("dim"))
	end)

	-- Navigation
	local nav = CreateFrame("Frame", nil, f)
	nav:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -1)
	nav:SetPoint("BOTTOMLEFT", 1, 1)
	nav:SetWidth(self.NAV_WIDTH)
	Theme.Fill(nav, "panel")
	self.nav = nav
	self.navButtons = {}

	-- Footer
	local footer = CreateFrame("Frame", nil, f)
	footer:SetPoint("BOTTOMLEFT", nav, "BOTTOMRIGHT", 1, 0)
	footer:SetPoint("BOTTOMRIGHT", -1, 1)
	footer:SetHeight(34)
	Theme.Fill(footer, "panel")
	self.lockButton = footerButton(footer, function()
		ns.DB:Set("general.locked", not ns.db.profile.general.locked)
		Config:RefreshCurrent()
	end)
	self.lockButton:SetPoint("LEFT", 14, 0)
	self.testButton = footerButton(footer, function()
		ns.TestMode:Toggle()
		Config:RefreshCurrent()
	end)
	self.testButton:SetPoint("LEFT", self.lockButton, "RIGHT", 10, 0)
	self.footerText = Theme.Text(footer, Theme.SIZE_SMALL, "warn")
	self.footerText:SetPoint("LEFT", self.testButton, "RIGHT", 14, 0)
	self.footerText:SetPoint("RIGHT", -14, 0)
	self.footerText:SetWordWrap(false)

	-- Content
	local scroll = CreateFrame("ScrollFrame", nil, f)
	scroll:SetPoint("TOPLEFT", nav, "TOPRIGHT", 1, 0)
	scroll:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", -12, 1)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local range = self:GetVerticalScrollRange()
		self:SetVerticalScroll(U.Clamp(self:GetVerticalScroll() - delta * 40, 0, range))
		Config:UpdateScrollThumb()
	end)
	self.scroll = scroll

	local track = CreateFrame("Frame", nil, f)
	track:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 4, -4)
	track:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 4, 4)
	track:SetWidth(4)
	Theme.Fill(track, "field")
	self.thumb = track:CreateTexture(nil, "ARTWORK")
	self.thumb:SetWidth(4)
	self.thumb:SetColorTexture(Theme.Color("accent"))
	self.track = track

	-- Escape closes the dropdown first, then the window. This is handled by
	-- the window's own keyboard script (UI.EscapeToClose), never by adding
	-- to Blizzard's Escape handler list or UISpecialFrames: writing to those
	-- tables from addon code taints Blizzard's Escape handling, which then
	-- gets SpellStopCasting()/SpellStopTargeting() blocked.
	UI.EscapeToClose(f, function()
		if not UI.CloseMenu() then
			Config:Hide()
		end
	end)

	f:SetScript("OnHide", function()
		UI.CloseMenu()
	end)

	ns:RegisterMessage(self, "PROFILE_CHANGED", function()
		Config:RefreshAll()
	end)
	ns:RegisterMessage(self, "STATE_CHANGED", function()
		Config:RefreshFooter()
	end)
	ns:RegisterMessage(self, "STANCE_CONFIGURED", function()
		Config:RefreshCurrent()
	end)
	ns:RegisterMessage(self, "LANGUAGE_CHANGED", function()
		Config:Rebuild()
	end)
	self:BuildNav()
	return f
end

function Config:BuildNav()
	for _, b in ipairs(self.navButtons) do
		b:Hide()
	end
	local y = -8
	for i, page in ipairs(self.pages) do
		local b = self.navButtons[i] or navButton(self.nav)
		self.navButtons[i] = b
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", self.nav, "TOPLEFT", 0, y)
		b:SetPoint("TOPRIGHT", self.nav, "TOPRIGHT", 0, y)
		b.text:SetText(ns.L[page.titleKey])
		b.pageKey = page.key
		b:SetScript("OnClick", function()
			Config:ShowPage(page.key)
		end)
		b:Show()
		setSelected(b, page.key == self.currentKey)
		y = y - 27
	end
end

function Config:GetPage(key)
	for _, page in ipairs(self.pages) do
		if page.key == key then
			return page
		end
	end
	return nil
end

function Config:ShowPage(key)
	local def = self:GetPage(key) or self.pages[1]
	UI.CloseMenu()
	if self.current and self.current.content then
		self.current.content:Hide()
	end
	if not def.instance then
		local width = self.WIDTH - self.NAV_WIDTH - 20
		local content = CreateFrame("Frame", nil, self.scroll)
		content:SetSize(width, 100)
		local page = UI.NewPage(content, width)
		def.instance = page
		local ok, err = pcall(def.build, page)
		if not ok then
			ns:ReportError(err)
		end
		page:Finish()
	end
	self.current = def.instance
	self.currentKey = def.key
	self.scroll:SetScrollChild(def.instance.content)
	def.instance.content:Show()
	self.scroll:SetVerticalScroll(0)
	for _, b in ipairs(self.navButtons) do
		setSelected(b, b.pageKey == def.key)
	end
	def.instance:Refresh()
	self:RefreshFooter()
	self:UpdateScrollThumb()
end

function Config:UpdateScrollThumb()
	if not self.scroll then
		return
	end
	local range = self.scroll:GetVerticalScrollRange() or 0
	local height = self.track:GetHeight() or 1
	if range <= 1 then
		self.thumb:Hide()
		return
	end
	local visible = self.scroll:GetHeight()
	local total = visible + range
	local thumbHeight = math.max(24, height * visible / total)
	local offset = (height - thumbHeight) * (self.scroll:GetVerticalScroll() / range)
	self.thumb:ClearAllPoints()
	self.thumb:SetPoint("TOP", self.track, "TOP", 0, -offset)
	self.thumb:SetHeight(thumbHeight)
	self.thumb:Show()
end

function Config:RefreshCurrent()
	if self.frame and self.frame:IsShown() and self.current then
		self.current:Refresh()
	end
	self:RefreshFooter()
end

function Config:RefreshAll()
	for _, def in ipairs(self.pages) do
		if def.instance then
			def.instance:Refresh()
		end
	end
	self:RefreshFooter()
end

--- Rebuilds every page (after a language change).
function Config:Rebuild()
	if not self.frame then
		return
	end
	for _, def in ipairs(self.pages) do
		if def.instance then
			def.instance.content:Hide()
			def.instance = nil
		end
	end
	self.current = nil
	self:BuildNav()
	if self.frame:IsShown() then
		self:ShowPage(self.currentKey)
	end
end

function Config:RefreshFooter()
	if not self.frame then
		return
	end
	local L = ns.L
	self.versionText:SetText(ns.VERSION)
	self.lockButton.text:SetText(ns.db.profile.general.locked and L.UNLOCK or L.LOCK)
	self.testButton.text:SetText(L.TEST_MODE .. ": " .. (ns.TestMode:IsActive() and L.STATE_ON or L.STATE_OFF))
	if ns.Combat:HasPending() then
		self.footerText:SetText(L.COMBAT_QUEUED)
	else
		self.footerText:SetText("")
	end
end

function Config:Show()
	if not ns.state.isWarrior then
		ns:Print(ns.L.WARRIOR_ONLY)
		return
	end
	self:Create()
	self.frame:Show()
	self:ShowPage(self.currentKey or (self.pages[1] and self.pages[1].key))
end

function Config:Hide()
	if self.frame then
		self.frame:Hide()
	end
end

function Config:Toggle()
	if self.frame and self.frame:IsShown() then
		self:Hide()
	else
		self:Show()
	end
end

--- Small entry in the game's Options > AddOns list that opens this window.
function Config:RegisterSettingsCategory()
	if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then
		return
	end
	local panel = CreateFrame("Frame")
	panel:Hide()
	local title = Theme.Text(panel, Theme.SIZE_TITLE, "accent")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("Warrior Master")
	local text = Theme.Text(panel, Theme.SIZE_TEXT, "text")
	text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
	text:SetWidth(520)
	text:SetText(ns.L.ABOUT_PRINCIPLES)
	local button = CreateFrame("Button", nil, panel, "BackdropTemplate")
	button:SetSize(260, 28)
	button:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -16)
	Theme.Border(button, "accent")
	local label = Theme.Text(button, Theme.SIZE_TEXT)
	label:SetPoint("CENTER")
	label:SetText(ns.L.OPEN_SETTINGS)
	button:SetScript("OnClick", function()
		Config:Show()
	end)
	local category = Settings.RegisterCanvasLayoutCategory(panel, "Warrior Master")
	Settings.RegisterAddOnCategory(category)
	self.category = category
end
