local VERSION = "3.2"
local DEVELOPMENT = false
local SLASH_COMMAND = "gt"
local MESSAGE_PREFIX = "GT"
local REFRESH_ALL_PERIOD = 1 * 60
local REFRESH_PLAYER_STATUS_PERIOD = 3 * 60 * 60
local PURGE_DATA_PERIOD = 3 * 60
local QUEUE_ITERATION = 15

local DEFAULTS = {
	realm = {
		history = {},
		status = {}
	},
	profile = {
		version = 0,
		debug = false,
		verbose = false,
		logging = true,
		autopay = true,
		direct = true,
	},
	char = {
		rate = 0.10,
	},
}


GildenSteuer = LibStub("AceAddon-3.0"):NewAddon("GildenSteuer", "AceConsole-3.0", "AceEvent-3.0", "AceComm-3.0", "AceHook-3.0")

getmetatable(GildenSteuer).__tostring = function (self)
	return GT_CHAT_PREFIX
end

function GildenSteuer:OnInitialize()
	self.db = LibStub("AceDB-3.0"):New("GildenSteuerDB", DEFAULTS, true)

	self.playerName = nil
	self.playerRealm = nil
	self.playerFullName = nil
	self.playerMoney = 0
	self.guildId = nil
	self.guildName = nil
	self.guildRealm = nil
	self.numberMembers = nil
	self.numberMembersOnline = nil
	self.isMailOpened = false
	self.isBankOpened = false
	self.isPayingTax = false
	self.isReady = false
	self.outgoingQueue = {}
	self.nextSyncTimestamp = time()
	self.nextPurgeTimestamp = time()
end


function GildenSteuer:HistoryKey(year, month)
	if string.len(tostring(month)) == 1 then
		return year .. "-0" .. month
	else
		return year .. "-" .. month
	end
end

function GildenSteuer:Debug(message, n)
	if (DEVELOPMENT or self.db.profile.debug) then
		self:Print("|cff999999" .. message .. "|r")
	end
end

function GildenSteuer:FormatMoney(amount, color)
	if amount < 0 then
		return "-" .. GetCoinTextureString(-amount)
	else
		return GetCoinTextureString(amount)
	end
end

function GildenSteuer:PrintGeneralInfo()
	self:Printf(GT_CHAT_GENERAL_INFO, 100 * self.db.char.rate, self.guildName, self.guildRealm)
end

function GildenSteuer:PrintTax()
	local message
	if self:GetTax() >= 1 then
		message = format(GT_CHAT_TAX, self:FormatMoney(self:GetTax()))
		if (self.isBankOpened and not self.db.profile.autopay) then
			message = message .. " |Hitem:GildenSteuer:create:|h|cffff8000[" .. GT_CHAT_TAX_CLICK .. "]|r|h"
		end
	else
		message = GT_CHAT_ALL_PAYED
	end
	self:Print(message)
end

function GildenSteuer:PrintTransaction(income, tax)
	if self.db.profile.logging then
		self:Printf(GT_CHAT_TRANSACTION, self:FormatMoney(income), self:FormatMoney(tax))
	end
end

function GildenSteuer:PrintPayingTax(tax)
	self:Printf(GT_CHAT_PAYING_TAX, self:FormatMoney(tax))
end

function GildenSteuer:PrintNothingToPay()
	self:Print(GT_CHAT_NOTHING_TO_PAY)
end

function GildenSteuer:PrintNotReady()
	GildenSteuer:Print(GT_CHAT_NOT_READY)
end

function GildenSteuer:GetTax()
	return self.db.char[self.guildId].tax
end

function GildenSteuer:GetRate()
	return GildenSteuer.db.char.rate
end

function GildenSteuer:GetGuildDB()
	local guildDB = self.db.realm[self.guildId]
	if not guildDB then
		guildDB = {
			["history"] = {},
			["status"] = {}
		}
		self.db.realm[self.guildId] = guildDB
	end
	return guildDB
end

function GildenSteuer:GetStatusDB()
	local guildDB = self:GetGuildDB()
	if guildDB.status == nil then
		guildDB.status = {}
	end
	return guildDB.status
end

function GildenSteuer:GetHistoryDB()
	local guildDB = self:GetGuildDB()
	if guildDB.history == nil then
		guildDB.history = {}
	end
	return guildDB.history
end

function GildenSteuer:GetPlayerStatusDB(playerName, create)
	local statusDB = self:GetStatusDB()
	local playerStatus = statusDB[playerName]
	if playerStatus == nil and create == true then
		playerStatus = {}
		statusDB[playerName] = playerStatus
	end
	return playerStatus
end

function GildenSteuer:GetPlayerHistoryDB(playerName, create)
	local historyDB = self:GetHistoryDB()
	local playerHistory = historyDB[playerName]
	if playerHistory == nil and create == true then
		playerHistory = {}
		historyDB[playerName] = playerHistory
	end
	return playerHistory
end

function GildenSteuer:GetStatus(playerName)
	local statusDB = self:GetStatusDB()
	local historyDB = self:GetHistoryDB()

	local status = {}

	if playerName == GildenSteuer.playerName then
		status.version = GetAddOnMetadata("GildenSteuer", "Version")
		status.timestamp = time()
		status.rate = GildenSteuer:GetRate()
		status.tax = GildenSteuer:GetTax()
		status.updated = time()
	else
		local playerStatus = statusDB[playerName]
		if not playerStatus then
			statusDB[playerName] = {}
			return
		end
		status.version = playerStatus.version
		status.timestamp = playerStatus.timestamp
		status.rate = playerStatus.rate
		status.tax = playerStatus.tax
		status.updated = playerStatus.updated
	end

	local playerHistory = historyDB[playerName]
	if not playerHistory then
		playerHistory = {}
	end

	status.history= {}

	local month = tonumber(date("%m"))
	local year = tonumber(date("%Y"))
	for i=1, 3 do
		local key = GildenSteuer:HistoryKey(year, month)
		local value = playerHistory[key]
		if value == nil then
			value = 0
		end
		status.history[key] = value
		month = month - 1
		if month == 0 then
			month = 12
			year = year - 1
		end
	end

	local total = playerHistory["total"]
	if total == nil then
		total = 0
	end
	status.total = total

	return status
end

function GildenSteuer:MigrateDatabase()
	local oldGuildId = format("%s-%s", self.guildName, self.guildRealm):lower()
	if self.db.char[oldGuildId] then
		self.db.char[self.guildId] = self.db.char[oldGuildId]
		self.db.char[oldGuildId] = nil
	end

	if not self.db.char[self.guildId] then
		self.db.char[self.guildId] = {
			tax = 0;
		}
	end

	if self.db.char[self.guildId].amount ~= nil then
		self.db.char[self.guildId].tax = self.db.char[self.guildId].amount
		self.db.char[self.guildId].amount = nil
	end

	if not self.db.realm then
		self.db.realm = {}
	end
	if not self.db.realm[self.guildId] then
		self.db.realm[self.guildId] = {}
	end

	if self.db.char[self.guildId].status ~= nil then
		for i, v in ipairs(self.db.char[self.guildId].status) do
			self.db.realm[self.guildId].status[k] = v
		end
		self.db.char[self.guildId].status = nil
	end
	if self.db.char[self.guildId].history ~= nil then
		for i, v in ipairs(self.db.char[self.guildId].history) do
			self.db.realm[self.guildId].history[k] = v
		end
		self.db.char[self.guildId].history = nil
	end

	if self.db.profile.direct == nil then
		self.db.profile.direct = true
	end
end

function GildenSteuer:UpdatePlayerName()
	self.playerName = UnitName("player")
	self.playerRealm = GetRealmName()
	self.playerFullName = self.playerName .. "-" .. self.playerRealm
end

function GildenSteuer:UpdatePlayerMoney(playerMoney)
	if not playerMoney then
		playerMoney = GetMoney()
	end
	self.playerMoney = playerMoney
end

function GildenSteuer:UpdateGuildInfo()
	self:Debug("Updating guild info")
	if IsInGuild() then
		if not self.guildId then
			self.guildName, self.guildRealm = GetGuildInfo("player"), GetRealmName()
			if self.guildName and self.guildRealm then
				self.guildId = format("%s - %s", self.guildName, self.guildRealm)
			end
		end
		if self.guildId then
			self:MigrateDatabase()
			self.GUI:UpdatePayedStatus()
		end
	else
		self.guildId = nil
	end
end

function GildenSteuer:Ready()
	if not self.isReady then
		if self.guildId and self.numberMembers ~= nil and self.numberMembers ~= 0 then
			self.isReady = true
			self:PrintGeneralInfo()
			self:NotifyStatus(self.playerName)
		else
			self.isReady = false
		end
	end
end

function GildenSteuer:AccrueTax(income, tax)
	self:Debug("Accrue tax with " .. tax)
	self.db.char[self.guildId].tax = self:GetTax() + tax
	self:PrintTransaction(income, tax)
	self.GUI:UpdatePayedStatus()
end

function GildenSteuer:ReduceTax(tax)
	self:Debug("Reduce tax with " .. tax)
	self.db.char[self.guildId].tax = self:GetTax() - tax
	self.GUI:UpdatePayedStatus()
end

function GildenSteuer:PayTax()
	self:Debug("Paying tax")
	if not self.isBankOpened then
		self:Print(GT_CHAT_OPEN_BANK)
		return
	end
	self.isPayingTax = true
	self:PrintPayingTax(self:GetTax())
	C_Timer.After(0.5, function() DepositGuildBankMoney(tonumber(self:GetTax())) end)
	self.GUI:UpdatePayedStatus()
end

function GildenSteuer:WritePaymentToHistory(tax)
	local month = tonumber(date("%m"))
	local year = tonumber(date("%Y"))
	local key = self:HistoryKey(year, month)
	local playerHistory = self:GetPlayerHistoryDB(self.playerName, true)
	if playerHistory[key] == nil then
		playerHistory[key] = 0
	end
	if playerHistory["total"] == nil then
		playerHistory["total"] = 0
	end
	playerHistory[key] = playerHistory[key] + tax
	playerHistory["total"] = playerHistory["total"] + tax
end

function GildenSteuer:SendData(data)
	local message = table.concat(data, "\t")
	self:Debug("Send (still " .. #self.outgoingQueue .. " in queue): " .. message)
	C_ChatInfo.SendAddonMessage(MESSAGE_PREFIX, message, "GUILD")
end

function GildenSteuer:NotifyStatus(playerName)
	local status = self:GetStatus(playerName)
	if status.version ~= nil then
		self:Debug("Add status message for " .. playerName .. " to queue")
		data = {"T", status.version, status.timestamp, playerName, status.rate, math.floor(status.tax)}
		for key, value in pairs(status.history) do
			table.insert(data, key)
			table.insert(data, value)
		end
		table.insert(data, status.total)
		table.insert(self.outgoingQueue, 1, data)
	else
		self:Debug("No status for " .. playerName .. ", ignoring")
	end
end

function GildenSteuer:RequestStatus(playerName, timestamp)
	self:Debug("Add status request for " .. playerName .. " to queue")
	if timestamp == nil then
		timestamp = self:GetPlayerStatusDB(playerName, true).timestamp
	end
	local data = {"S", playerName}
	if timestamp ~= nil then
		table.insert(data, timestamp)
	end
	table.insert(self.outgoingQueue, data)
end

function GildenSteuer:RemoveQueueS(playerName)
	for i=#self.outgoingQueue, 1, -1 do
		local data=self.outgoingQueue[i]
		if data[1] == "S" and data[2] == playerName then
			table.remove(self.outgoingQueue, i)
		end
	end
end

function GildenSteuer:RemoveQueueT(playerName)
	for i=#self.outgoingQueue, 1, -1 do
		local data=self.outgoingQueue[i]
		if data[1] == "T" and data[4] == playerName then
			table.remove(self.outgoingQueue, i)
		end
	end
end

function GildenSteuer:FillOutgoingQueue()
	self:Debug("Filling outgoung queue")

	local statusDB = GildenSteuer:GetStatusDB()

	if self.numberMembers ~= nil and self.numberMembers > 0 then
		for index = 1, self.numberMembers do
			local playerName = GetGuildRosterInfo(index)
			
			if playerName ~= nil then
			playerName = Ambiguate(playerName, "guild")
			end
			
			local playerStatus = self:GetPlayerStatusDB(playerName)
			if playerStatus == nil or playerStatus.updated == nil then
				self:RequestStatus(playerName)
			elseif playerStatus.updated + REFRESH_PLAYER_STATUS_PERIOD < time() then
				self:RequestStatus(playerName, playerStatus.timestamp)
			end
		end
	end

	self.nextSyncTimestamp = time() + REFRESH_ALL_PERIOD
end

function GildenSteuer:QueueIteration()
	if GildenSteuer.isReady and not InCombatLockdown() then
		if #GildenSteuer.outgoingQueue > 0 then
			local data = table.remove(GildenSteuer.outgoingQueue, 1)
			if data[1] == "S" then
				local playerName = data[2]
				if playerName then
					local playerStatus = GildenSteuer:GetPlayerStatusDB(playerName, true)
					playerStatus.updated = time()
				end
			end
			GildenSteuer:SendData(data)
		else
			if GildenSteuer.nextPurgeTimestamp < time() then
				GildenSteuer:PurgeOldData()
			end
			if GildenSteuer.nextSyncTimestamp < time() then
				GildenSteuer:FillOutgoingQueue()
			end
		end
	end
	C_Timer.After(QUEUE_ITERATION, GildenSteuer.QueueIteration)
end

function GildenSteuer:PurgeOldData()
	self:Debug("Purging old data")
	if self.numberMembers ~= nil and self.numberMembers > 0 then
		local statusDB = self:GetStatusDB()
		local guildPlayers = {}
		for index = 1, GildenSteuer.numberMembers do
			local fullName = GetGuildRosterInfo(index)
			table.insert(guildPlayers, Ambiguate(fullName, "guild"))
		end
		self.nextPurgeTimestamp = time() + PURGE_DATA_PERIOD
	end
end

GildenSteuer.commands = {
	[""]       = "OnGUICommand";
	["sync"]   = "OnSyncCommand";
	["status"] = "OnPrintTaxCommand";
}

function GildenSteuer:OnPrintTaxCommand()
	if self.isReady then
		self:PrintTax()
	else
		self.PrintNotReady()
	end
end

function GildenSteuer:OnGUICommand()
	if self.isReady then
		self.GUI:Toggle()
		if self.GUI:IsShown() then
			self.GUI:RefreshTable()
		end
	else
		self.PrintNotReady()
	end
end

function GildenSteuer:OnSyncCommand()
	self:SendData({"S"})
end

function GildenSteuer:OnSlashCommand(input, val)
	local args = {}
	for word in input:gmatch("%S+") do
		table.insert(args, word)
	end

	local _, operation = next(args)
	if operation == nil then
		operation = ""
	end

	if self.commands[operation] then
		self[self.commands[operation]](self)
	else
		self:Debug("Unknown command: " .. operation)
	end
end

GildenSteuer.events = {

	["S"] = function (sender, ...)
		local playerName = select(1, ...)
		if playerName == nil then
			playerName = GildenSteuer.playerName
		end
		local timestamp = select(2, ...)
		if timestamp ~= nil then
			timestamp = tonumber(timestamp)
		end

		local playerStatus = GildenSteuer:GetPlayerStatusDB(playerName, true)
		if playerStatus.timestamp ~= nil then
			if timestamp == nil or timestamp < playerStatus.timestamp then
				GildenSteuer:Debug("Recieved request for " .. playerName)
				GildenSteuer:NotifyStatus(playerName)
			elseif timestamp == playerStatus.timestamp then
				GildenSteuer:Debug("Recieved request for " .. playerName .. ", have same, ignoring")
			else
				GildenSteuer:Debug("Recieved request for " .. playerName .. ", have older, ignoring")
			end
		else
			GildenSteuer:Debug("Recieved request for " .. playerName .. ", have no status, ignoring")
		end
		playerStatus.updated = time()
		GildenSteuer:RemoveQueueS(playerName)
	end,

	["T"] = function (sender, version, timestamp, playerName, rate, tax, ...)


		timestamp = tonumber(timestamp)
		if timestamp == nil then
			GildenSteuer:Debug("Incorrect T-message received from " .. sender)
			return
		end

		rate = tonumber(rate)
		if rate == nil then
			GildenSteuer:Debug("Incorrect T-message received from " .. sender)
			return
		end

		tax = tonumber(tax)
		if tax == nil then
			GildenSteuer:Debug("Incorrect T-message received from " .. sender)
			return
		end

		local playerStatus = GildenSteuer:GetPlayerStatusDB(playerName, true)
		if playerStatus.timestamp == nil or playerStatus.timestamp < timestamp or (sender == playerName and playerStatus.timestamp ~= timestamp) then
			GildenSteuer:Debug("Receive status for " .. tostring(playerName) .. ", updating")
			playerStatus.timestamp = timestamp
			playerStatus.version = version
			playerStatus.rate = rate
			playerStatus.tax = tax
			playerStatus.updated = timestamp
			GildenSteuer:RemoveQueueS(playerName)
			GildenSteuer:RemoveQueueT(playerName)

			local playerHistory = GildenSteuer:GetPlayerHistoryDB(playerName, true)
			for i=1, #... - 1, 2 do
				local key = select(i, ...)
				if key ~= nil then
					local val = tonumber(select(i+1, ...), 10)
					if val == nil then
						val = 0
					end
					playerHistory[key] = val
				end
			end

			local total = tonumber(select(-1, ...), 10)
			if total == nil then
				total = 0
			end
			playerHistory["total"] = total

			if GildenSteuer.GUI.IsShown() then
				GildenSteuer.GUI:RefreshTable()
			end

		elseif playerStatus.timestamp == timestamp then
			GildenSteuer:Debug("Receive status for " .. tostring(playerName) .. ", have same, ignoring")

		else
			GildenSteuer:Debug("Receive status for " .. tostring(playerName) .. ", have newer, ignoring")
		end
	end,
}

function GildenSteuer:OnCommReceived(prefix, message, channel, sender)
	if prefix == MESSAGE_PREFIX and message and channel == "GUILD" then
		if not GildenSteuer.isReady then
			GildenSteuer:Debug("Addon not ready, ignoring incoming message")
			return
		end
		local data = {}
		for word in string.gmatch(message, "[^\t]+") do
			data[#data + 1] = word
		end
		if #data > 0 then
			local command = table.remove(data, 1)
			local handler = GildenSteuer.events[command]
			if handler then
				handler(sender, unpack(data))
			else
				GildenSteuer:Debug("Unknown command received from " .. sender .. ": ".. command)
			end
		end
	end
end

function GildenSteuer:ChatFrame_OnHyperlinkShow(chat, link, text, button)
	local command = strsub(link, 1, 4);
	if command == "item" then
		local _, addonName = strsplit(":", link)
		if addonName == "GildenSteuer" then
			if GildenSteuer.isReady then
				local tax = floor(self:GetTax())
				if tax > 0 then
					self:PayTax()
				else
					self:PrintNothingToPay()
				end
			else
				self:PrintNotReady()
			end
		end
	end
end

function GildenSteuer:PLAYER_ENTERING_WORLD( ... )
	self.GUI:Create()

	self:UpdatePlayerName()
	self:UpdatePlayerMoney()
	self:UpdateGuildInfo()

	C_GuildInfo.GuildRoster()

	C_Timer.After(QUEUE_ITERATION, self.QueueIteration)
end

function GildenSteuer:PLAYER_MONEY( ... )

	local newPlayerMoney = GetMoney()
	local delta = newPlayerMoney - self.playerMoney

	self:Debug("Player money, delta=" .. tostring(delta))

	if not self.isReady then
		self:Debug("Addon is not ready, transaction ignored")

	elseif delta > 0 then
		if not self.guildId then
			self:Debug("Not in guild, transaction ignored")
		elseif self.isMailOpened then
			self:Debug("Mailbox is open, transaction ignored")
		elseif self.isBankOpened then
			self:Debug("Guild bank is open, transaction ignored")
		else
			self:AccrueTax(delta, delta * self.db.char.rate)
			self:NotifyStatus(self.playerName)
		end

	elseif self.isBankOpened and self.isPayingTax then
		self:ReduceTax(-delta)
		self.isPayingTax = false
		self:PrintTax()
		self:WritePaymentToHistory(-delta)
		self:NotifyStatus(self.playerName)

	else
		self:Debug("Ignoring withdraw")
	end

	self:UpdatePlayerMoney(newPlayerMoney)
end

function GildenSteuer:GUILDBANKBAGSLOTS_CHANGED( ... )
	self:Debug("Guild bank opened")
	self.isBankOpened = true

	if self.isReady then
		local tax = floor(self:GetTax())
		if tax >= 1 and self.db.profile.autopay then
			self:PayTax()
		else
			self:PrintTax()
		end
		if self.db.profile.direct then
			self.isPayingTax = true
		end
	else
		self:PrintNotReady()
	end

end

function GildenSteuer:MAIL_SHOW( ... )
	self:Debug("Mailbox opened")
	self.isMailOpened = true
end

function GildenSteuer:MAIL_CLOSED( ... )
	if self.isMailOpened then
		self:Debug("Mailbox closed")
		self.isMailOpened = false
	end
end

function GildenSteuer:PLAYER_GUILD_UPDATE(event, unit)
	if unit == "player" then
		self:Debug("Player guild info updated")
		self:UpdateGuildInfo()
		self:Ready()
	end
end

function GildenSteuer:GUILD_ROSTER_UPDATE( ... )
	local needRefresh = false
	local numMembers, numOnline, _ = GetNumGuildMembers()
	if self.numberMembers ~= numMembers then
		self:Debug("Number of guild members changed: " .. tostring(self.numberMembers) .. " -> " .. numMembers)
		self.numberMembers = numMembers
		needRefresh = true
	end
	if self.numberMembersOnline ~= numOnline then
		self:Debug("Number of online members changed: " .. tostring(self.numberMembersOnline) .. " -> " .. numOnline)
		self.numberMembersOnline = numOnline
		needRefresh = true
	end
	if needRefresh then
		if self.GUI:IsShown() then
			self.GUI:RefreshTable()
		end
	end
	self:Ready()
end

GildenSteuer:Hook("ChatFrame_OnHyperlinkShow", true)

GildenSteuer:RegisterComm(MESSAGE_PREFIX)

GildenSteuer:RegisterChatCommand(SLASH_COMMAND, "OnSlashCommand")

GildenSteuer:RegisterEvent("PLAYER_ENTERING_WORLD")
GildenSteuer:RegisterEvent("PLAYER_MONEY")
GildenSteuer:RegisterEvent("GUILDBANKBAGSLOTS_CHANGED")
GildenSteuer:RegisterEvent("MAIL_SHOW")
GildenSteuer:RegisterEvent("MAIL_CLOSED")
GildenSteuer:RegisterEvent("PLAYER_GUILD_UPDATE")
GildenSteuer:RegisterEvent("GUILD_ROSTER_UPDATE")
