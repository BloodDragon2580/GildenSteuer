local AceGUI = LibStub("AceGUI-3.0")

local TABLE_UPDATE_THRESHOLD = 5

local GUI = {
	frame = nil,
	status = "-",
	data = {},
	updated = nil,
}
GildenSteuer.GUI = GUI


AceGUI:RegisterLayout("Static", function(content, children) end);


function GUI:Create()
	self.frame = AceGUI:Create("Frame")
	self.frame:Hide()
	self.frame:SetTitle(GT_GUI_TITLE)
	self.frame:SetLayout("Static")
	self.frame:SetStatusText(self.status)

	local width = 500
	if GildenSteuer.db.profile.mainFrameWidth ~= nil then
		width = GildenSteuer.db.profile.mainFrameWidth
	end
	self.frame:SetWidth(width)

	local height = 600
	if GildenSteuer.db.profile.mainFrameHeight ~= nil then
		height = GildenSteuer.db.profile.mainFrameHeight
	end
	self.frame:SetHeight(height)

	self.frame.frame:SetScript("OnSizeChanged", function()
		GildenSteuer.db.profile.mainFrameWidth = GUI.frame.frame:GetWidth()
		GildenSteuer.db.profile.mainFrameHeight = GUI.frame.frame:GetHeight()
	end)

	self.frame:SetCallback("OnClose", function (self) AceGUI:Release(self) end)

	self.table = AceGUI:Create("Mitglieder")
	self.table:SetPoint("TOPLEFT", self.frame.content)
	self.table:SetPoint("BOTTOMRIGHT", self.frame.content, "BOTTOMRIGHT", 0, 50)
	self.table:SetOnlineOnly(GildenSteuer.db.profile.onlineOnly)
	self.frame:AddChild(self.table)

	self.filterGroup = AceGUI:Create("SimpleGroup")
	self.filterGroup:SetLayout("Flow")
	self.filterGroup:SetPoint("BOTTOMLEFT", self.frame.content, "BOTTOMLEFT", 0, 10)
	self.filterGroup:SetPoint("BOTTOMRIGHT", self.frame.content, "BOTTOMRIGHT", 0, 10)
	self.frame:AddChild(self.filterGroup)

	self.onlineCheckBox = AceGUI:Create("CheckBox")
	self.onlineCheckBox:SetLabel(GT_GUI_ONLINE_ONLY)
	self.onlineCheckBox:SetValue(GildenSteuer.db.profile.onlineOnly)
	self.onlineCheckBox:SetCallback("OnValueChanged", self.OnOnlineValueChanged)
	self.onlineCheckBox:SetValue(GildenSteuer.db.profile.onlineOnly)
	self.filterGroup:AddChild(self.onlineCheckBox)
end

function GUI:Toggle()
	if GUI.frame:IsShown() then
		GUI.frame:Hide()
	else
		GUI:Create()
		GUI.frame:Show()
	end
end

function GUI:IsShown()
	local shown = false
	if GUI.frame ~= nil then
		shown = GUI.frame:IsShown()
	end
	return shown
end

function GUI:OnOnlineValueChanged(event, value)
	GildenSteuer.db.profile.onlineOnly = value
	GUI.table:SetOnlineOnly(value)
end

function GUI:UpdatePayedStatus()
	local guild = GildenSteuer.guildName
	local tax = GildenSteuer:GetTax()
	local rate = GildenSteuer:GetRate()
	if floor(tax) > 0 then
		self.status = format(GT_GUI_TAX, GildenSteuer:FormatMoney(tax))
	else
		self.status = GT_GUI_ALL_PAYED
	end
	self.status = self.status .. format(GT_GUI_GENERAL_INFO, rate * 100, guild)
	if self:IsShown() then
		GUI.frame:SetStatusText(self.status)
	end
end

function GUI:RefreshTable()
	local now = time()

	if self.updated ~= nil and self.updated + TABLE_UPDATE_THRESHOLD > now then
		return
	end

	local statusDB = GildenSteuer:GetStatusDB()
	local historyDB = GildenSteuer:GetHistoryDB()

	for index = 1, GildenSteuer.numberMembers do
		local fullName, rank, rankIndex, online
		fullName, rank, rankIndex, _, _, _, _, _, online, _, _, _, _, _, _, _ = GetGuildRosterInfo(index)

		local r
		for i, row in pairs(self.data) do
			if row.fullName == fullName then
				r = row
				break
			end
		end

		if r == nil then
			r = {}
			table.insert(self.data, r)
		end

		r.fullName = fullName
		r.rank = rank
		r.rankIndex = rankIndex
		r.online = online

		local shortName = Ambiguate(r.fullName, "guild")

		local userStatus = statusDB[shortName]
		if userStatus ~= nil then
			r.timestamp = userStatus.timestamp
			r.version = userStatus.version
			r.tax = userStatus.tax
			r.rate = userStatus.rate
		end

		r.months = {}
		local userHistory = historyDB[shortName]
		if userHistory ~= nil then
			local month = tonumber(date("%m"))
			local year = tonumber(date("%Y"))
			for i=1, 3 do
				r.months[i] = userHistory[GildenSteuer:HistoryKey(year, month)]
				month = month - 1
				if month == 0 then
					month = 12
					year = year - 1
				end
			end
			r.total = userHistory.total
		end

		r.updated = now
	end

	for i, row in pairs(self.data) do
		if row.updated ~= now then
			table.remove(self.data, i)
		end
	end

	self.updated = now
	self.table:SetData(self.data)
end
