GildenSteuerSettings = {}

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
            set = function(info, val) GildenSteuer.db.char.rate = val end;
            get = function(info) return GildenSteuer.db.char.rate end;
            isPercent = true;
            order = 101;
        };
        autopay = {
            type = "toggle";
            name = GT_CONFIG_TAXES_AUTOPAY;
            desc = GT_CONFIG_TAXES_AUTOPAY_DESC;
            descStyle = "inline";
            set = function(info, val) GildenSteuer.db.profile.autopay = val end;
            get = function(info) return GildenSteuer.db.profile.autopay end;
            width = "full";
            order = 102;
        };
        direct = {
            type = "toggle";
            name = GT_CONFIG_TAXES_DIRECT;
            desc = GT_CONFIG_TAXES_DIRECT_DESC;
            descStyle = "inline";
            set = function(info, val) GildenSteuer.db.profile.direct = val end;
            get = function(info) return GildenSteuer.db.profile.direct end;
            width = "full";
            order = 103;
        };
        ignoreMailIncome = {
            type = "toggle";
            name = GT_CONFIG_TAXES_IGNORE_MAIL;
            desc = GT_CONFIG_TAXES_IGNORE_MAIL_DESC;
            descStyle = "inline";
            set = function(info, val) GildenSteuer.db.profile.ignoreMailIncome = val end;
            get = function(info) return GildenSteuer.db.profile.ignoreMailIncome end;
            width = "full";
            order = 104;
        };
        ignoreTradeIncome = {
            type = "toggle";
            name = GT_CONFIG_TAXES_IGNORE_TRADE;
            desc = GT_CONFIG_TAXES_IGNORE_TRADE_DESC;
            descStyle = "inline";
            set = function(info, val) GildenSteuer.db.profile.ignoreTradeIncome = val end;
            get = function(info) return GildenSteuer.db.profile.ignoreTradeIncome end;
            width = "full";
            order = 105;
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
            set = function(info, val) GildenSteuer.db.profile.logging = val end;
            get = function(info) return GildenSteuer.db.profile.logging end;
            width = "full";
            order = 201;
        };
        verbose = {
            type = "toggle";
            name = GT_CONFIG_VERBOSE_LOG;
            desc = GT_CONFIG_VERBOSE_LOG_DESC;
            descStyle = "inline";
            set = function(info, val) GildenSteuer.db.profile.verbose = val end;
            get = function(info) return GildenSteuer.db.profile.verbose end;
            width = "full";
            order = 202;
        };
        debug = {
            type = "toggle";
            name = GT_CONFIG_DEBUG_LOG;
            desc = GT_CONFIG_DEBUG_LOG_DESC;
            descStyle = "inline";
            set = function(info, val) GildenSteuer.db.profile.debug = val end;
            get = function(info) return GildenSteuer.db.profile.debug end;
            width = "full";
            order = 203;
        };
    }
}

GildenSteuerSettings.AceOptionsTable = LibStub("AceConfig-3.0")
GildenSteuerSettings.AceOptionsTable:RegisterOptionsTable("GildenSteuer", GildenSteuerSettings.AceConfig)

GildenSteuerSettings.AceConfigDialog = LibStub("AceConfigDialog-3.0")
GildenSteuerSettings.AceConfigDialog:AddToBlizOptions("GildenSteuer", GT_CONFIG_TITLE);