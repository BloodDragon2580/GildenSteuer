GildenSteuerSettings = {}

-- Helper: Änderungen sofort anwenden, optional speichern, GUI refresh & Chatinfo
local function GS_Commit(msg, doSave)
    -- GUI live aktualisieren, falls offen (z. B. Tabellenwerte/Warnungen)
    if GildenSteuer and GildenSteuer.GUI and GildenSteuer.GUI.IsShown and GildenSteuer.GUI:IsShown() then
        if GildenSteuer.GUI.RefreshTable then
            GildenSteuer.GUI:RefreshTable()
        end
        if GildenSteuer.GUI.UpdatePayedStatus then
            GildenSteuer.GUI:UpdatePayedStatus()
        end
    end

    -- Optional: SavedVariables sofort schreiben (Retail/TWW: SaveAddOns() vorhanden)
    if doSave and type(SaveAddOns) == "function" then
        -- kurze Verzögerung vermeidet Kollisionen, falls mehrere Optionen schnell nacheinander gesetzt werden
        C_Timer.After(0, SaveAddOns)
    end

    -- Chat-Bestätigung
    if GildenSteuer and GildenSteuer.Print then
        GildenSteuer:Print("|cff00ff00" .. (msg or GT_CHAT_SETTING_APPLIED or "Setting applied.") .. "|r")
    end
end

GildenSteuerSettings.AceConfig = {
    name = GT_CONFIG_TITLE;
    handler = nil;
    type = "group";
    args = {
        taxGroup = {
            type = "header";
            name = GT_CONFIG_TAXES_TITLE;
            order = 100;
        };
        rate = {
            type = "range";
            name = GT_CONFIG_TAXES_RANGE;
            desc = GT_CONFIG_TAXES_RANGE_DESC;
            descStyle = "inline";
            min = 0;
            max = 1;
            step = 0.05;
            isPercent = true;
            order = 101;
            set = function(info, val)
                GildenSteuer.db.char.rate = val
                -- Anzeige sofort aktualisieren (z. B. „zu zahlen“-Status)
                GS_Commit((GT_CHAT_SETTING_RATE_CHANGED and GT_CHAT_SETTING_RATE_CHANGED:format(val*100)) or ("Rate set to " .. tostring(val*100) .. "%"), true)
            end;
            get = function(info) return GildenSteuer.db.char.rate end;
        };
        autopay = {
            type = "toggle";
            name = GT_CONFIG_TAXES_AUTOPAY;
            desc = GT_CONFIG_TAXES_AUTOPAY_DESC;
            descStyle = "inline";
            width = "full";
            order = 102;
            set = function(info, val)
                GildenSteuer.db.profile.autopay = val
                GS_Commit("Autopay: " .. (val and "ON" or "OFF"), true)
            end;
            get = function(info) return GildenSteuer.db.profile.autopay end;
        };
        direct = {
            type = "toggle";
            name = GT_CONFIG_TAXES_DIRECT;
            desc = GT_CONFIG_TAXES_DIRECT_DESC;
            descStyle = "inline";
            width = "full";
            order = 103;
            set = function(info, val)
                GildenSteuer.db.profile.direct = val
                GS_Commit("Direct payment: " .. (val and "ON" or "OFF"), true)
            end;
            get = function(info) return GildenSteuer.db.profile.direct end;
        };
        ignoreMailIncome = {
            type = "toggle";
            name = GT_CONFIG_TAXES_IGNORE_MAIL;
            desc = GT_CONFIG_TAXES_IGNORE_MAIL_DESC;
            descStyle = "inline";
            width = "full";
            order = 104;
            set = function(info, val)
                GildenSteuer.db.profile.ignoreMailIncome = val
                GS_Commit("Ignore Mail Income: " .. (val and "ON" or "OFF"), true)
            end;
            get = function(info) return GildenSteuer.db.profile.ignoreMailIncome end;
        };
        ignoreTradeIncome = {
            type = "toggle";
            name = GT_CONFIG_TAXES_IGNORE_TRADE;
            desc = GT_CONFIG_TAXES_IGNORE_TRADE_DESC;
            descStyle = "inline";
            width = "full";
            order = 105;
            set = function(info, val)
                GildenSteuer.db.profile.ignoreTradeIncome = val
                -- Hinweis: Die Logik in PLAYER_MONEY priorisiert Trade bereits
                GS_Commit("Ignore Trade Income: " .. (val and "ON" or "OFF"), true)
            end;
            get = function(info) return GildenSteuer.db.profile.ignoreTradeIncome end;
        };
        showMinimap = {
            type = "toggle";
            name = GT_CONFIG_MINIMAP_SHOW;
            desc = GT_CONFIG_MINIMAP_SHOW_DESC;
            descStyle = "inline";
            width = "full";
            order = 106;
            set = function(info, val)
                local db = GildenSteuer.db.profile.minimap
                db.hide = not val
                local icon = LibStub("LibDBIcon-1.0", true)
                if icon then
                    if db.hide then icon:Hide("GildenSteuer") else icon:Show("GildenSteuer") end
                end
                -- Falls der Button noch nie registriert war (sehr selten), bleibt er nach Show evtl. unsichtbar.
                -- In dem Fall hilft ein Reload – aber wir versuchen, ohne auszukommen:
                GS_Commit("Minimap Icon: " .. (val and "ON" or "OFF"), true)
            end;
            get = function(info)
                local db = GildenSteuer.db.profile.minimap
                return not db.hide
            end;
        };
        loggingGroup = {
            type = "header";
            name = GT_CONFIG_LOGGING_TITLE;
            order = 200;
        };
        logging = {
            type = "toggle";
            name = GT_CONFIG_LOGGING_LOG;
            desc = GT_CONFIG_LOGGING_LOG_DESC;
            descStyle = "inline";
            width = "full";
            order = 201;
            set = function(info, val)
                GildenSteuer.db.profile.logging = val
                GS_Commit("Logging: " .. (val and "ON" or "OFF"), true)
            end;
            get = function(info) return GildenSteuer.db.profile.logging end;
        };
        verbose = {
            type = "toggle";
            name = GT_CONFIG_VERBOSE_LOG;
            desc = GT_CONFIG_VERBOSE_LOG_DESC;
            descStyle = "inline";
            width = "full";
            order = 202;
            set = function(info, val)
                GildenSteuer.db.profile.verbose = val
                GS_Commit("Verbose: " .. (val and "ON" or "OFF"), true)
            end;
            get = function(info) return GildenSteuer.db.profile.verbose end;
        };
        debug = {
            type = "toggle";
            name = GT_CONFIG_DEBUG_LOG;
            desc = GT_CONFIG_DEBUG_LOG_DESC;
            descStyle = "inline";
            width = "full";
            order = 203;
            set = function(info, val)
                GildenSteuer.db.profile.debug = val
                GS_Commit("Debug: " .. (val and "ON" or "OFF"), true)
            end;
            get = function(info) return GildenSteuer.db.profile.debug end;
        };
    }
}

GildenSteuerSettings.AceOptionsTable = LibStub("AceConfig-3.0")
GildenSteuerSettings.AceOptionsTable:RegisterOptionsTable("GildenSteuer", GildenSteuerSettings.AceConfig)

GildenSteuerSettings.AceConfigDialog = LibStub("AceConfigDialog-3.0")
GildenSteuerSettings.AceConfigDialog:AddToBlizOptions("GildenSteuer", GT_CONFIG_TITLE);
