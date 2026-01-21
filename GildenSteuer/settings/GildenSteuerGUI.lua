local AceAddon = LibStub("AceAddon-3.0")
local Addon = AceAddon:GetAddon("GildenSteuer", true)
if not Addon then return end
local GildenSteuer = Addon

-- AceGUI ist seit einiger Zeit NICHT mehr garantiert als globale Variable vorhanden.
-- In neueren Clients (z.B. Prepatches) ist "AceGUI" global oft nil.
-- Daher immer sauber über LibStub holen.
local AceGUI = LibStub("AceGUI-3.0", true)
if not AceGUI then
  -- Wenn AceGUI nicht geladen werden kann, bricht die GUI sauber ab,
  -- damit das restliche Addon (Steuerlogik/Sync) nicht komplett stirbt.
  (GildenSteuer and GildenSteuer.Debug or function() end)(GildenSteuer, "AceGUI-3.0 fehlt/ist nicht geladen – GUI deaktiviert")
  return
end

local TABLE_UPDATE_THRESHOLD = 5

local GUI = {
  frame = nil,
  status = "-",
  data = {},
  updated = nil,
}
GildenSteuer.GUI = GUI

AceGUI:RegisterLayout("Static", function(content, children) end)

-- =============== Helfer ===============
local function safe_fmt(fmt, ...)
  if type(fmt) ~= "string" or fmt == "" then return "" end
  local ok, out = pcall(string.format, fmt, ...)
  if ok then return out end
  return ""
end

local function clamp(v, a, b)
  if v < a then return a end
  if v > b then return b end
  return v
end

local function GetUIAlpha()
  local prof = (GildenSteuer and GildenSteuer.db and GildenSteuer.db.profile) or {}
  local a = tonumber(prof.uiAlpha) or 0.85   -- Idle-Standard
  return clamp(a, 0.2, 1.0)
end

local function GetUIAlphaMoving()
  local prof = (GildenSteuer and GildenSteuer.db and GildenSteuer.db.profile) or {}
  local a = tonumber(prof.uiAlphaMoving) or 0.55 -- Beim Laufen
  return clamp(a, 0.2, 1.0)
end

local function GetClassHexByFile(classFileName)
  if classFileName and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFileName] then
    local c = RAID_CLASS_COLORS[classFileName]
    return string.format("%02x%02x%02x", c.r*255, c.g*255, c.b*255)
  end
  return "ffffff"
end

local function Colorize(hex, text)
  return ("|cff%s%s|r"):format(hex or "ffffff", text or "")
end

local function IsPlayerMoving()
  if GetUnitSpeed then
    return (GetUnitSpeed("player") or 0) > 0
  end
  return false
end

-- =========================
-- Moderner Container im FGT-Stil (mit zuverlässigem Alpha-State)
-- =========================
local function CreateModernContainer()
  local f = CreateFrame("Frame", "GildenSteuerFrame", UIParent, "BackdropTemplate")

  -- Größe/Position aus DB (Fallbacks)
  local prof = (GildenSteuer and GildenSteuer.db and GildenSteuer.db.profile) or {}
  local width  = prof.mainFrameWidth  or 680
  local height = prof.mainFrameHeight or 500

  f:SetSize(width, height)
  f:ClearAllPoints()
  if prof.position then
    f:SetPoint(unpack(prof.position))
  else
    f:SetPoint("CENTER")
  end

  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, r, rp, x, y = self:GetPoint()
    GildenSteuer.db = GildenSteuer.db or { profile = {} }
    GildenSteuer.db.profile.position = { p, r, rp, x, y }
  end)
  f:SetClampedToScreen(true)
  f:SetFrameStrata("MEDIUM")
  f:Hide()

  -- Hintergrund (dunkel)
  local bg = f:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0.08, 0.09, 0.10, 0.95)

  -- 1px-Rand
  local border = CreateFrame("Frame", nil, f, "BackdropTemplate")
  border:SetPoint("TOPLEFT", 1, -1)
  border:SetPoint("BOTTOMRIGHT", -1, 1)
  border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  border:SetBackdropBorderColor(0, 0, 0, 1)

  -- Soft-Shadow
  local shadow = f:CreateTexture(nil, "BACKGROUND", nil, -1)
  shadow:SetPoint("TOPLEFT", -6, 6)
  shadow:SetPoint("BOTTOMRIGHT", 6, -6)
  shadow:SetTexture("Interface\\Buttons\\WHITE8x8")
  shadow:SetVertexColor(0, 0, 0, 0.30)

  -- Titlebar
  local bar = f:CreateTexture(nil, "ARTWORK")
  bar:SetPoint("TOPLEFT", 0, 0)
  bar:SetPoint("TOPRIGHT", 0, 0)
  bar:SetHeight(36)
  bar:SetColorTexture(0.12, 0.14, 0.18, 1)

  local underline = f:CreateTexture(nil, "ARTWORK")
  underline:SetPoint("TOPLEFT", 0, -36)
  underline:SetPoint("TOPRIGHT", 0, -36)
  underline:SetHeight(1)
  underline:SetColorTexture(0, 0, 0, 1)

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", f, "TOP", 0, -9)
  title:SetText(GT_GUI_TITLE or "GildenSteuer")
  title:SetJustifyH("CENTER")
  title:SetTextColor(1, 1, 1, 1)
  title:SetShadowColor(0, 0, 0, 1)
  title:SetShadowOffset(1, -1)
  f.TitleText = title

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)
  close:SetScale(0.9)

  -- Inhaltsbereich
  local content = CreateFrame("Frame", nil, f)
  content:SetPoint("TOPLEFT", 12, -44)
  content:SetPoint("TOPRIGHT", -12, -44)
  content:SetPoint("BOTTOMLEFT", 12, 40)
  content:SetPoint("BOTTOMRIGHT", -12, 40)
  f.content = content

  -- Statuszeile unten
  local statusBar = CreateFrame("Frame", nil, f)
  statusBar:SetPoint("BOTTOMLEFT", 12, 12)
  statusBar:SetPoint("BOTTOMRIGHT", -12, 12)
  statusBar:SetHeight(20)

  local statusBg = statusBar:CreateTexture(nil, "ARTWORK")
  statusBg:SetAllPoints()
  statusBg:SetColorTexture(0.16, 0.18, 0.22, 1)

  local statusText = statusBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  statusText:SetPoint("LEFT", statusBar, "LEFT", 8, 0)
  statusText:SetJustifyH("LEFT")
  statusText:SetTextColor(0.9, 0.9, 0.9, 1)
  statusText:SetText("-")
  f.StatusText = statusText

  -- Größe speichern
  f:SetScript("OnSizeChanged", function(self)
    GildenSteuer.db = GildenSteuer.db or { profile = {} }
    GildenSteuer.db.profile.mainFrameWidth  = self:GetWidth()
    GildenSteuer.db.profile.mainFrameHeight = self:GetHeight()
  end)

  -- ===== Alpha-State-Handling =====
  local function ApplyAlpha(isMoving)
    local target = isMoving and GetUIAlphaMoving() or GetUIAlpha()
    if math.abs((f._currentAlpha or -1) - target) > 0.001 then
      f._currentAlpha = target
      f:SetAlpha(target)
    end
    f._isMoving = not not isMoving
  end

  -- Initial setzen
  ApplyAlpha(IsPlayerMoving())

  -- Event-Frame + OnUpdate-Backup (falls Events mal nicht feuern)
  local ev = CreateFrame("Frame", nil, f)
  ev:RegisterEvent("PLAYER_STARTED_MOVING")
  ev:RegisterEvent("PLAYER_STOPPED_MOVING")
  ev:RegisterEvent("PLAYER_ENTERING_WORLD")
  ev:SetScript("OnEvent", function(_, event)
    if not f:IsShown() then return end
    if event == "PLAYER_STARTED_MOVING" then
      ApplyAlpha(true)
    elseif event == "PLAYER_STOPPED_MOVING" or event == "PLAYER_ENTERING_WORLD" then
      ApplyAlpha(IsPlayerMoving())
    end
  end)

  local acc = 0
  ev:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + elapsed
    if acc < 0.2 then return end  -- alle 0.2s prüfen
    acc = 0
    if not f:IsShown() then return end
    local moving = IsPlayerMoving()
    if moving ~= f._isMoving then
      ApplyAlpha(moving)
    end
  end)

  f:SetScript("OnShow", function()
    ApplyAlpha(IsPlayerMoving())
  end)

  -- ===== Resize-Handle (unten rechts) =====
  f:SetResizable(true)
  -- moderne API bevorzugen
  if f.SetResizeBounds then
    f:SetResizeBounds(400, 300, 1200, 900)
  else
    -- Fallback für ältere Clients
    if f.SetMinResize then f:SetMinResize(400, 300) end
    if f.SetMaxResize then f:SetMaxResize(1200, 900) end
  end

  local resizer = CreateFrame("Frame", nil, f)
  resizer:SetSize(16, 16)
  resizer:SetPoint("BOTTOMRIGHT", -2, 2)
  resizer:EnableMouse(true)
  resizer:SetFrameLevel(f:GetFrameLevel() + 10)

  local tex = resizer:CreateTexture(nil, "OVERLAY")
  tex:SetAllPoints()
  tex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  tex:SetVertexColor(1, 1, 1, 0.6)

  resizer:SetScript("OnEnter", function() tex:SetVertexColor(1, 1, 1, 1) end)
  resizer:SetScript("OnLeave", function() tex:SetVertexColor(1, 1, 1, 0.6) end)

  resizer:SetScript("OnMouseDown", function(_, button)
    if button == "LeftButton" then
      f:StartSizing("BOTTOMRIGHT")
      f:SetUserPlaced(true)
    end
  end)

  resizer:SetScript("OnMouseUp", function()
    f:StopMovingOrSizing()
    -- Größe speichern
    GildenSteuer.db = GildenSteuer.db or { profile = {} }
    GildenSteuer.db.profile.mainFrameWidth  = f:GetWidth()
    GildenSteuer.db.profile.mainFrameHeight = f:GetHeight()
  end)

  return f
end

-- =========================
-- GUI-Erstellung (ersetzt AceGUI-Frame)
-- =========================
function GUI:Create()
  if self and self.frame and self.frame:IsShown() then return end

  self = self or GUI
  self.frame = CreateModernContainer()

  -- AceGUI-Container in den Content-Bereich einbetten
  self._contentGroup = AceGUI:Create("SimpleGroup")
  self._contentGroup.frame:SetParent(self.frame.content)
  self._contentGroup.frame:ClearAllPoints()
  self._contentGroup.frame:SetPoint("TOPLEFT", self.frame.content, "TOPLEFT", 0, 0)
  self._contentGroup.frame:SetPoint("BOTTOMRIGHT", self.frame.content, "BOTTOMRIGHT", 0, 0)
  self._contentGroup:SetLayout("Static")

  -- Mitglieder-Tabelle (dein Custom-Widget)
  self.table = AceGUI:Create("Mitglieder")
  self.table.frame:SetParent(self._contentGroup.frame) -- wichtig fürs Hide
  self.table:SetPoint("TOPLEFT", self._contentGroup.frame, "TOPLEFT", 0, 0)
  self.table:SetPoint("BOTTOMRIGHT", self._contentGroup.frame, "BOTTOMRIGHT", 0, 28)
  self.table:SetOnlineOnly(GildenSteuer.db.profile.onlineOnly)

  -- Filter/Checkbox-Leiste unten
  self.filterGroup = AceGUI:Create("SimpleGroup")
  self.filterGroup.frame:SetParent(self._contentGroup.frame)
  self.filterGroup:SetLayout("Flow")
  self.filterGroup.frame:ClearAllPoints()
  self.filterGroup.frame:SetPoint("BOTTOMLEFT", self._contentGroup.frame, "BOTTOMLEFT", 0, 0)
  self.filterGroup.frame:SetPoint("BOTTOMRIGHT", self._contentGroup.frame, "BOTTOMRIGHT", 0, 0)
  self.filterGroup.frame:SetHeight(24)

  self.onlineCheckBox = AceGUI:Create("CheckBox")
  self.onlineCheckBox:SetLabel(GT_GUI_ONLINE_ONLY)
  self.onlineCheckBox:SetValue(GildenSteuer.db.profile.onlineOnly)
  self.onlineCheckBox:SetCallback("OnValueChanged", GUI.OnOnlineValueChanged)
  self.filterGroup:AddChild(self.onlineCheckBox)

  self:UpdatePayedStatus()
end

-- robust gegen Aufruf per GUI.Toggle() und GUI:Toggle()
function GUI:Toggle()
  local obj = self or GUI
  if obj.frame and obj.frame:IsShown() then
    obj.frame:Hide()
  else
    if not (obj.frame and obj.frame.GetObjectType) then
      obj:Create()
    end
    obj.frame:Show()
  end
end

-- robust gegen Aufruf per GUI.IsShown() und GUI:IsShown()
function GUI:IsShown()
  local obj = self or GUI
  local f = obj and obj.frame
  if f and f.IsShown then
    return f:IsShown()
  end
  return false
end

-- Callback (widget,event,value), arbeitet mit GUI
function GUI.OnOnlineValueChanged(widget, event, value)
  GildenSteuer.db.profile.onlineOnly = not not value
  if GUI.table and GUI.table.SetOnlineOnly then
    GUI.table:SetOnlineOnly(GildenSteuer.db.profile.onlineOnly)
  end
  if GUI.RefreshTable then
    GUI:RefreshTable()
  end
end

function GUI:UpdatePayedStatus()
  local guild = GildenSteuer.guildName
  if not guild and GetGuildInfo then
    local gName = GetGuildInfo("player")
    if gName then guild = gName end
  end
  guild = guild or ""

  local tax  = tonumber(GildenSteuer:GetTax()) or 0
  local rate = tonumber(GildenSteuer:GetRate()) or 0

  if tax > 0 then
    self.status = safe_fmt(GT_GUI_TAX, GildenSteuer:FormatMoney(tax))
    if self.status == "" then
      self.status = "Ausstehend: " .. (GildenSteuer:FormatMoney(tax) or "")
    end
  else
    self.status = GT_GUI_ALL_PAYED or "Alles bezahlt"
  end

  local info = safe_fmt(GT_GUI_GENERAL_INFO, rate * 100, guild)
  if info ~= "" then
    self.status = (self.status or "-") .. info
  end

  local obj = self or GUI
  if obj.frame and obj.frame.StatusText then
    obj.frame.StatusText:SetText(self.status or "-")
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
    -- Klasseninfos mit abholen
    local fullName, rank, rankIndex, level, classLoc, zone, note, officernote, online,
          status, classFileName, achievementPoints, achievementRank, isMobile,
          canSoR, rep, guid = GetGuildRosterInfo(index)

    local r
    for i, row in pairs(self.data) do
      if row.fullNameRaw == fullName or row.fullName == fullName then
        r = row
        break
      end
    end

    if r == nil then
      r = {}
      table.insert(self.data, r)
    end

    r.fullNameRaw   = fullName
    r.rank          = rank
    r.rankIndex     = rankIndex
    r.online        = online
    r.classFileName = classFileName
    r.classLoc      = classLoc

    local shortName = Ambiguate(fullName, "guild")

    -- Daten aus Status/History
    local userStatus = statusDB[shortName]
    if userStatus ~= nil then
      r.timestamp = userStatus.timestamp
      r.version   = userStatus.version
      r.tax       = userStatus.tax
      r.rate      = userStatus.rate
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

    -- Name in Klassenfarbe (für alle)
    local hex = GetClassHexByFile(classFileName)
    local label = Ambiguate(fullName, "guild") or fullName or ""
    r.fullName = Colorize(hex, label)

    r.updated = now
  end

  -- Alte Zeilen entfernen
  for i, row in pairs(self.data) do
    if row.updated ~= now then
      table.remove(self.data, i)
    end
  end

  self.updated = now
  if self.table then
    self.table:SetData(self.data)
  end
end
