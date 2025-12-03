local VERSION = "14.0"
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
		ignoreMailIncome = false, -- 🆕 neue Option
		ignoreTradeIncome = false, -- 🆕 NEUE OPTION HINZUFÜGEN
		minimap = { hide = false }, -- 🆕 HINZUFÜGEN (LibDBIcon speichert hier)
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

    -- 🆕 Minimap-Button via LibDataBroker + LibDBIcon
    do
        local ldb     = LibStub("LibDataBroker-1.1", true)
        local ldbIcon = LibStub("LibDBIcon-1.0", true)

        if ldb and ldbIcon then
            local dataObj = ldb:NewDataObject("GildenSteuer", {
                type = "data source",
                text = "GT",
                icon = "Interface\\Icons\\INV_Misc_NoteFolded2A",
                OnClick = function(_, button)
                    if button == "LeftButton" then
                        GildenSteuer:OnGUICommand()
                    end
                end,
                OnTooltipShow = function(tt)
				    -- Titel: nimmt bevorzugt deine neue Übersetzung, sonst GT_CHAT_PREFIX, sonst Fallback
                    tt:AddLine(GT_MINIMAP_TT_HEADER or GT_CHAT_PREFIX or "GildenSteuer")
				    -- Linksklick-Hinweis lokalisiert, mit englischem Fallback
                    tt:AddLine(GT_MINIMAP_TT_LEFTCLICK or "Left-click to toggle window", 0.2, 1, 0.2)
                end,
            })
            if dataObj then
                ldbIcon:Register("GildenSteuer", dataObj, self.db.profile.minimap)
                self.ldbIcon = ldbIcon
            end
        end
    end

    self.playerName = nil
    self.playerRealm = nil
    self.playerFullName = nil
    self.playerMoney = 0
    self.guildId = nil
    self.guildName = nil
    self.guildRealm = nil
    self.numberMembers = nil
    self.numberMembersOnline = nil
    self.isBankOpened = false
    self.isPayingTax = false
    self.isReady = false
    self.isMailOpened = false -- 🆕 Mail-Status-Flag
    self.isTradeOpened = false       -- Trade-Fenster offen?
    self.tradeGraceUntil = 0         -- Nachlauf-Kulanz für Trade
    self.outgoingQueue = {}
    self.isNormalIncomeWindow = false -- Variable für die Kulanzfrist
    self.nextSyncTimestamp = time()
    self.nextPurgeTimestamp = time()

    -- 🆕 NEU: Hook ...
    if QuestInfoRewardsFrame then
        GildenSteuer:HookScript(QuestInfoRewardsFrame, "OnShow", function(self)
            GildenSteuer:SetNormalIncomeWindow(5.0)
        end)
    end
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
    if not self.guildId then return 0 end
    if not self.db.char[self.guildId] then return 0 end
    return self.db.char[self.guildId].tax or 0
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
		status.version = C_AddOns.GetAddOnMetadata("GildenSteuer", "Version")
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
	if playerName == nil then
		playerName = GildenSteuer.playerName
	end

	GildenSteuer:Debug("Add status request for " .. playerName .. " to queue")

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
			if fullName ~= nil then
			table.insert(guildPlayers, Ambiguate(fullName, "guild"))
			end
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

-- Erweiterte Grace Zeit für Kriegsmeuten-Bank
local BANK_GRACE_SECONDS = 10

-- Deaktivierte Guild-Bank API für TWW (funktioniert nicht mit Kriegsmeuten-Bank)
local function GuildBankAPIAvailable()
    return false -- Komplett deaktiviert für TWW
end

-- Überarbeitete Funktion für bessere Kriegsmeuten-Bank-Erkennung
function GildenSteuer:WasLastTransactionBankWithdraw()
    self:Debug("WasLastTransactionBankWithdraw called; isBankOpened=" .. tostring(self.isBankOpened) .. ", lastBankInteraction=" .. tostring(self.lastBankInteraction))

    local last = self.lastBankInteraction or 0
    local since = GetTime() - last
    self:Debug("Time since last bank interaction: " .. tostring(since) .. "s")

    -- Für Kriegsmeuten-Bank: verwende nur Grace-Period-basierte Erkennung
    if self.isBankOpened or since <= BANK_GRACE_SECONDS then
        self:Debug("Bank is open or within grace period -> treat as bank withdraw")
        return true
    end
    
    self:Debug("Not in bank and grace period expired -> assume not bank withdraw")
    return false
end

-- Robustere Mail-Detektion: prüft Frame-Visibility und räumt Flag auf, falls Events ausbleiben.

-- Helper: prüfe echtes Mail-Frame-Visibility (arbeitet mit Classic/Retails Varianten)
local function IsMailFrameOpen()
    -- Viele Clients benutzen InboxFrame / MailFrame, teste beide falls vorhanden
    if InboxFrame and InboxFrame:IsShown() then return true end
    if MailFrame and MailFrame:IsShown() then return true end
    -- Fallback: falls es andere custom frames gibt, erweitere hier
    return false
end

function GildenSteuer:MAIL_SHOW()
    self:Debug("MAIL_SHOW -> Mailbox geöffnet (event)")
    self.isMailOpened = true

    -- Hook sicherheitshalber das OnHide des InboxFrame / MailFrame falls verfügbar,
    -- damit wir das Flag auch säubern, wenn MAIL_CLOSED nicht kommt.
    if InboxFrame and not self._mailHooked then
        self._mailHooked = true
        InboxFrame:HookScript("OnHide", function()
            self:Debug("InboxFrame OnHide -> Mailbox geschlossen (hook)")
            self.isMailOpened = false
        end)
    end
    if MailFrame and not self._mailHookedMailFrame then
        self._mailHookedMailFrame = true
        MailFrame:HookScript("OnHide", function()
            self:Debug("MailFrame OnHide -> Mailbox geschlossen (hook)")
            self.isMailOpened = false
        end)
    end

    -- Safety-timer: überprüfe nach kurzer Zeit, ob das Frame wirklich offen ist.
    C_Timer.After(1, function()
        if not IsMailFrameOpen() then
            self:Debug("MAIL_SHOW: Mailframe nicht sichtbar -> Flag bereinigt")
            self.isMailOpened = false
        end
    end)
end

function GildenSteuer:MAIL_CLOSED()
    self:Debug("MAIL_CLOSED -> Mailbox geschlossen (event)")
    self.isMailOpened = false
end

-- ===== Spieler-Handel (Trade) =====
local TRADE_GRACE_SECONDS = 5
function GildenSteuer:TRADE_SHOW()
    self:Debug("TRADE_SHOW -> Trade geöffnet")
    self.isTradeOpened = true
    -- Sicherheits-Reset (falls Blizzard-Events ausbleiben)
    C_Timer.After(1, function()
        if not TradeFrame or not TradeFrame:IsShown() then
            self:Debug("TradeFrame nicht sichtbar -> Trade-Flag zurückgesetzt")
            self.isTradeOpened = false
        end
    end)
end
function GildenSteuer:TRADE_CLOSED()
    self:Debug("TRADE_CLOSED -> Trade geschlossen")
    self.isTradeOpened = false
    self.tradeGraceUntil = GetTime() + TRADE_GRACE_SECONDS
end
local function IsTradeIncomeActive(self)
    if self.isTradeOpened then return true end
    return (self.tradeGraceUntil or 0) > GetTime()
end

-- ===== Ende Spieler-Handel (Trade) =====

local NORMAL_INCOME_GRACE_SECONDS = 2.0

function GildenSteuer:SetNormalIncomeWindow(seconds)
    self:Debug("Normal Income window set for " .. tostring(seconds) .. "s")
    self.isNormalIncomeWindow = true
    C_Timer.After(seconds, function()
        if self.isNormalIncomeWindow then -- Nur ausschalten, wenn es nicht direkt wieder gesetzt wurde
            self:Debug("Normal Income window closed")
            self.isNormalIncomeWindow = false
        end
    end)
end

function GildenSteuer:LOOT_OPENED()
    self:SetNormalIncomeWindow(NORMAL_INCOME_GRACE_SECONDS)
end

function GildenSteuer:MERCHANT_SHOW()
    -- NEU: Setze eine lange Kulanzfrist (60 Sekunden), um die gesamte Händlersitzung abzudecken.
    self:SetNormalIncomeWindow(60.0) 
end

function GildenSteuer:MERCHANT_CLOSED()
    self:Debug("Merchant closed. Resetting Normal Income window flag.")
    self.isNormalIncomeWindow = false
end

function GildenSteuer:GOSSIP_SHOW()
    self:SetNormalIncomeWindow(NORMAL_INCOME_GRACE_SECONDS)
end

function GildenSteuer:REWARD_SHOW()
    self:SetNormalIncomeWindow(NORMAL_INCOME_GRACE_SECONDS)
end

function GildenSteuer:QUEST_TURNED_IN() -- Beibehalten
    self:SetNormalIncomeWindow(NORMAL_INCOME_GRACE_SECONDS)
end

-- In PLAYER_MONEY: benutze live-prüfung statt allein dem Flag, um 'hängende' Flags zu vermeiden.
function GildenSteuer:PLAYER_MONEY(...)
    local newPlayerMoney = GetMoney()
    local delta = newPlayerMoney - self.playerMoney

    self:Debug("PLAYER_MONEY triggered; delta=" .. tostring(delta) .. ", playerMoney(before) = " .. tostring(self.playerMoney))

    if not self.isReady then
        self:Debug("Addon is not ready, transaction ignored")
        self:UpdatePlayerMoney(newPlayerMoney)
        return
    end

    if delta > 0 then
        if not self.guildId then
            self:Debug("Not in guild, transaction ignored")
            self:UpdatePlayerMoney(newPlayerMoney)
            return
        end

        -- ===== 1) TRADE hat höchste Priorität =====
        local tradeActive  = IsTradeIncomeActive(self)         -- true, wenn TradeFrame offen oder Grace aktiv
        local ignoreTrade  = self.db.profile.ignoreTradeIncome == true

        if tradeActive then
            if ignoreTrade then
                self:Debug("Trade income detected and ignoreTradeIncome=true -> skipping tax")
                self:UpdatePlayerMoney(newPlayerMoney)
                return
            else
                self:Debug("Trade income detected and ignoreTradeIncome=false -> tax WILL apply (forcing normal taxation)")
                local taxAmount = math.floor(delta * (self.db.char.rate or 0))
                self:AccrueTax(delta, taxAmount)
                self:NotifyStatus(self.playerName)
                self:UpdatePlayerMoney(newPlayerMoney)
                return
            end
        end
        -- ===== Ende Trade-Priorität =====

        -- 2) MAIL-Check (nur relevant, wenn Option aktiv)
        local isMailIncome = self.db.profile.ignoreMailIncome and (self.isMailOpened or (IsMailFrameOpen and IsMailFrameOpen()))
        if isMailIncome and self.isNormalIncomeWindow then
            -- Normal-Income-Fenster (Loot/Quest/Vendor) überschreibt Mail-Ignorieren
            self:Debug("Mail income flag active, but Normal Income Grace Period active -> NOT mail income, tax is due.")
            isMailIncome = false
            self.isNormalIncomeWindow = false
        elseif isMailIncome then
            self:Debug("Mail income detected and ignoreMailIncome=true -> will skip tax unless other rules force it")
        end

        -- 3) BANK-Check
        local isBankWithdraw = false
        local timeSinceBank = GetTime() - (self.lastBankInteraction or 0)

        if self.isPayingTax then
            self:Debug("Currently paying tax -> treating as bank withdraw")
            isBankWithdraw = true
        elseif self.isBankOpened then
            self:Debug("Bank is currently open -> treating as bank withdraw")
            isBankWithdraw = true
        elseif timeSinceBank <= 10 then -- BANK_GRACE_SECONDS
            self:Debug("Within bank grace period (" .. tostring(timeSinceBank) .. "s) -> treating as bank withdraw")
            isBankWithdraw = true
        end

        if delta > 1000000 and not isBankWithdraw and not isMailIncome then
            self:Debug("Large amount detected and no bank/mail -> treating as normal income")
        end

        -- 4) Finale Entscheidung (ohne Trade, da oben schon behandelt)
        if isBankWithdraw or isMailIncome then
            self:Debug("Detected special transaction (Bank or MailIgnored) -> skipping tax for delta " .. tostring(delta))
        else
            self:Debug("Treating as normal income -> accruing tax for delta " .. tostring(delta))
            local taxAmount = math.floor(delta * (self.db.char.rate or 0))
            self:AccrueTax(delta, taxAmount)
            self:NotifyStatus(self.playerName)
        end

    elseif delta < 0 then
        -- Steuerzahlung (nur wenn Bank offen und aktuell Steuern bezahlt werden)
        if self.isBankOpened and self.isPayingTax then
            self:ReduceTax(-delta)
            self.isPayingTax = false
            self:PrintTax()
            self:WritePaymentToHistory(-delta)
            self:NotifyStatus(self.playerName)
        else
            self:Debug("Ignoring withdraw or other transaction (delta=" .. tostring(delta) .. ")")
        end
    end

    self:UpdatePlayerMoney(newPlayerMoney)
end

-- Korrigierte Bank-Event-Handler für Kriegsmeuten-Bank
local function OnGuildBankShow(self, event, frameType)
    if frameType == 10 then  -- nur Gildenbank
        self:Debug("Gildenbank geöffnet (frameType=10)")
        self.isBankOpened = true
        self.lastBankInteraction = GetTime()

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
    elseif frameType == 8 then
        self:Debug("Kriegsmeutenbank geöffnet - nur überwachen, keine Meldung")
        self.isBankOpened = true
        self.lastBankInteraction = GetTime()
    else
        self:Debug("Andere Bank/Interaktion (frameType=" .. tostring(frameType) .. ") ignoriert")
    end
end

local function OnGuildBankHide(self, event, frameType)
    if frameType == 10 or frameType == 8 then
        self:Debug("Bank geschlossen (frameType=" .. tostring(frameType) .. ")")
        self.isBankOpened = false
        self.lastBankInteraction = GetTime()
        C_Timer.After(2, function()
            if not self.isBankOpened then
                self.isPayingTax = false
                self:Debug("Bank interaction cleanup completed")
            end
        end)
    end
end

-- Registriere die neuen Interaction-Events in einem eigenen Frame
do
    local frame = CreateFrame("Frame", "GildenSteuer_BankListener")
    frame:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
    frame:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE")
    frame:SetScript("OnEvent", function(_, event, ...)
        if event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
            OnGuildBankShow(GildenSteuer, event, ...)
        elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
            OnGuildBankHide(GildenSteuer, event, ...)
        end
    end)
    GildenSteuer.bankFrameListener = frame
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

-- Kompatibler Hyperlink-Hook:
-- Ältere Clients hatten eine globale Funktion ChatFrame_OnHyperlinkShow,
-- in TWW / 11.2.7 ist sie nicht mehr global verfügbar.
if ChatFrame_OnHyperlinkShow then
    -- Falls sie (z.B. in älteren Versionen oder anderen Clients) noch existiert:
    GildenSteuer:Hook("ChatFrame_OnHyperlinkShow", true)
else
    -- Retail 11.2.7+: an SetItemRef anhängen, das wird bei Link-Klicks im Chat aufgerufen
    hooksecurefunc("SetItemRef", function(link, text, button, chatFrame)
        -- Verwende deine bestehende Logik
        GildenSteuer:ChatFrame_OnHyperlinkShow(chatFrame, link, text, button)
    end)
end

GildenSteuer:RegisterComm(MESSAGE_PREFIX)

GildenSteuer:RegisterChatCommand(SLASH_COMMAND, "OnSlashCommand")

GildenSteuer:RegisterEvent("PLAYER_ENTERING_WORLD")
GildenSteuer:RegisterEvent("PLAYER_MONEY")
GildenSteuer:RegisterEvent("PLAYER_GUILD_UPDATE")
GildenSteuer:RegisterEvent("GUILD_ROSTER_UPDATE")
GildenSteuer:RegisterEvent("MAIL_SHOW")
GildenSteuer:RegisterEvent("MAIL_CLOSED")
GildenSteuer:RegisterEvent("TRADE_SHOW")   -- 🆕 NEU
GildenSteuer:RegisterEvent("TRADE_CLOSED") -- 🆕 NEU
GildenSteuer:RegisterEvent("LOOT_OPENED")     -- Für Loot
GildenSteuer:RegisterEvent("MERCHANT_SHOW")   -- Für Vendor-Verkauf
GildenSteuer:RegisterEvent("MERCHANT_CLOSED")
