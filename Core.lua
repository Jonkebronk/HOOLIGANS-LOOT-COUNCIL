-- Core.lua
-- Main addon initialization

local ADDON_NAME, NS = ...

-- Create addon using Ace3
local HooligansLoot = LibStub("AceAddon-3.0"):NewAddon(ADDON_NAME,
    "AceConsole-3.0",
    "AceEvent-3.0",
    "AceSerializer-3.0",
    "AceComm-3.0",
    "AceTimer-3.0"
)

-- Make addon globally accessible
_G.HooligansLoot = HooligansLoot
NS.addon = HooligansLoot

-- Addon colors
HooligansLoot.colors = {
    primary = "|cff5865F2",    -- Discord blurple
    success = "|cff00ff00",
    warning = "|cffffff00",
    error = "|cffff0000",
    white = "|cffffffff",
}

-- Default database structure
local defaults = {
    profile = {
        settings = {
            announceChannel = "RAID",
            exportFormat = "json",
            autoTradeEnabled = true,
            autoTradePrompt = true,
            announceOnAward = false,      -- Auto-announce when items are imported (disabled by default)
            useRaidWarning = true,        -- Use raid warning for announcements
            minQuality = 4, -- Epic and above
            debug = false,
        },
        minimap = {
            hide = false,
            minimapPos = 220,             -- Angle around minimap (degrees) - used by LibDBIcon
        },
        sessions = {},
        currentSessionId = nil,
    }
}

-- Create callback handler for events
HooligansLoot.callbacks = LibStub("CallbackHandler-1.0"):New(HooligansLoot)

function HooligansLoot:OnInitialize()
    -- Initialize database
    self.db = LibStub("AceDB-3.0"):New("HooligansLootDB", defaults, true)

    -- Register slash commands
    self:RegisterChatCommand("hl", "SlashCommand")
    self:RegisterChatCommand("hooligans", "SlashCommand")

    -- Create minimap button
    self:CreateMinimapButton()

    self:Print("Loaded. Type /hl for commands.")
end

-- Minimap button creation using LibDBIcon
function HooligansLoot:CreateMinimapButton()
    local LDB = LibStub("LibDataBroker-1.1")
    local LDBIcon = LibStub("LibDBIcon-1.0")

    -- Create the data broker object
    local dataObj = LDB:NewDataObject("HooligansLoot", {
        type = "launcher",
        icon = "Interface\\AddOns\\HooligansLoot\\Textures\\logo",
        OnClick = function(self, button)
            if button == "LeftButton" then
                HooligansLoot:ShowMainFrame()
            elseif button == "RightButton" then
                HooligansLoot:ShowSettings()
            end
        end,
        OnTooltipShow = function(tooltip)
            tooltip:AddLine("|cff5865F2HOOLIGANS|r Loot Council")
            tooltip:AddLine(" ")
            tooltip:AddLine("|cffffffffLeft-click:|r Open main window", 0.8, 0.8, 0.8)
            tooltip:AddLine("|cffffffffRight-click:|r Settings", 0.8, 0.8, 0.8)
            tooltip:AddLine("|cffffffffDrag:|r Move button", 0.8, 0.8, 0.8)
        end,
    })

    -- Register with LibDBIcon
    LDBIcon:Register("HooligansLoot", dataObj, self.db.profile.minimap)

    self.LDBIcon = LDBIcon
end

function HooligansLoot:ToggleMinimapButton()
    self.db.profile.minimap.hide = not self.db.profile.minimap.hide
    if self.db.profile.minimap.hide then
        self.LDBIcon:Hide("HooligansLoot")
    else
        self.LDBIcon:Show("HooligansLoot")
    end
end

function HooligansLoot:OnEnable()
    -- Modules will register their own events
end

function HooligansLoot:OnDisable()
    -- Cleanup if needed
end

function HooligansLoot:SlashCommand(input)
    local cmd, arg = self:GetArgs(input, 2)
    cmd = cmd and cmd:lower() or ""

    if cmd == "" or cmd == "show" then
        self:ShowMainFrame()
    elseif cmd == "start" then
        self:StartSession()
    elseif cmd == "session" then
        self:HandleSessionCommand(arg)
    elseif cmd == "export" then
        self:ShowExportDialog()
    elseif cmd == "import" then
        self:ShowImportDialog()
    elseif cmd == "announce" then
        self:AnnounceAwards()
    elseif cmd == "trade" then
        self:ShowPendingTrades()
    elseif cmd == "settings" or cmd == "options" then
        self:ShowSettings()
    elseif cmd == "history" then
        self:ShowHistoryFrame()
    elseif cmd == "test" then
        self:RunTest(arg)
    elseif cmd == "debug" then
        if arg == "session" then
            self:DebugSession()
        elseif arg == "scan" then
            -- Manual bag scan for debugging tracking issues
            local LootTracker = self:GetModule("LootTracker", true)
            if LootTracker then
                LootTracker:ManualScan()
            end
        else
            self:ToggleDebug()
        end
    elseif cmd == "help" then
        self:PrintHelp()
    else
        self:Print("Unknown command. Type /hl help")
    end
end

function HooligansLoot:StartSession()
    -- Start a new session and show main frame
    local SessionManager = self:GetModule("SessionManager", true)
    if SessionManager then
        SessionManager:NewSession()
    end
    self:ShowMainFrame()
end

function HooligansLoot:HandleSessionCommand(arg)
    if not arg then
        self:Print("Usage: /hl session <new|end|list>")
        return
    end

    local subCmd, sessionName = self:GetArgs(arg, 2)
    subCmd = subCmd and subCmd:lower() or ""

    if subCmd == "new" then
        self:GetModule("SessionManager"):NewSession(sessionName)
    elseif subCmd == "end" then
        self:GetModule("SessionManager"):EndSession()
    elseif subCmd == "list" then
        self:GetModule("SessionManager"):ListSessions()
    else
        self:Print("Usage: /hl session <new|end|list>")
    end
end

function HooligansLoot:PrintHelp()
    self:Print("Commands:")
    print("  |cff88ccff/hl|r - Show main window")
    print("  |cff88ccff/hl start|r - Start new session and open window")
    print("  |cff88ccff/hl settings|r - Open settings panel")
    print("  |cff88ccff/hl history|r - View loot history")
    print("  |cff88ccff/hl session new [name]|r - Start new loot session")
    print("  |cff88ccff/hl session end|r - End current session")
    print("  |cff88ccff/hl session list|r - List all sessions")
    print("  |cff88ccff/hl export|r - Export current session")
    print("  |cff88ccff/hl import|r - Import awards data")
    print("  |cff88ccff/hl announce|r - Announce awards")
    print("  |cff88ccff/hl trade|r - Show pending trades")
    print("  |cffffcc00-- Testing --|r")
    print("  |cff88ccff/hl test kara [count]|r - Simulate Karazhan drops (default 8)")
    print("  |cff88ccff/hl test item|r - Add single random test item")
    print("  |cff88ccff/hl debug|r - Toggle debug mode")
end

function HooligansLoot:Print(msg)
    print(self.colors.primary .. "[HOOLIGANS Loot]|r " .. msg)
end

function HooligansLoot:Debug(msg)
    if self.db and self.db.profile.settings.debug then
        print(self.colors.warning .. "[HL Debug]|r " .. msg)
    end
end

function HooligansLoot:ToggleDebug()
    self.db.profile.settings.debug = not self.db.profile.settings.debug
    if self.db.profile.settings.debug then
        self:Print("Debug mode " .. self.colors.success .. "enabled|r")
    else
        self:Print("Debug mode " .. self.colors.error .. "disabled|r")
    end
end

function HooligansLoot:DebugSession()
    self:Print("=== Session Debug Info ===")

    local SessionManager = self:GetModule("SessionManager", true)
    if not SessionManager then
        print("  SessionManager: NOT LOADED")
        return
    end

    local sessionId = self.db.profile.currentSessionId
    print("  currentSessionId: " .. tostring(sessionId))

    local session = SessionManager:GetCurrentSession()
    if not session then
        print("  Current session: NONE")
        print("  Total sessions in db: " .. tostring(NS.Utils.TableSize(self.db.profile.sessions)))
        return
    end

    print("  Session name: " .. tostring(session.name))
    print("  Session status: " .. tostring(session.status))
    print("  Items count: " .. tostring(#session.items))

    if #session.items > 0 then
        print("  First 3 items:")
        for i = 1, math.min(3, #session.items) do
            local item = session.items[i]
            print("    " .. i .. ": " .. tostring(item.name) .. " (guid: " .. tostring(item.guid) .. ")")
        end
    end

    print("=== End Debug ===")
end

-- Wrapper functions that delegate to modules/UI
function HooligansLoot:ShowMainFrame()
    local MainFrame = self:GetModule("MainFrame", true)
    if MainFrame then
        MainFrame:Show()
    else
        self:Print("UI not loaded. Try /reload")
    end
end

function HooligansLoot:ShowExportDialog()
    local Export = self:GetModule("Export", true)
    if Export then
        Export:ShowDialog()
    end
end

function HooligansLoot:ShowImportDialog()
    local Import = self:GetModule("Import", true)
    if Import then
        Import:ShowDialog()
    end
end

function HooligansLoot:ShowSettings()
    local SettingsFrame = self:GetModule("SettingsFrame", true)
    if SettingsFrame then
        SettingsFrame:Show()
    end
end

function HooligansLoot:ShowHistoryFrame()
    local HistoryFrame = self:GetModule("HistoryFrame", true)
    if HistoryFrame then
        HistoryFrame:Show()
    end
end

function HooligansLoot:AnnounceAwards()
    local Announcer = self:GetModule("Announcer", true)
    if Announcer then
        local session = self:GetModule("SessionManager"):GetCurrentSession()
        if session then
            Announcer:AnnounceAwards(session.id)
        else
            self:Print("No active session.")
        end
    end
end

function HooligansLoot:AnnounceAwardsWithRaidWarning()
    local Announcer = self:GetModule("Announcer", true)
    if Announcer then
        local session = self:GetModule("SessionManager"):GetCurrentSession()
        if session then
            Announcer:AnnounceAwardsWithRaidWarning(session.id)
        else
            self:Print("No active session.")
        end
    end
end

function HooligansLoot:ShowPendingTrades()
    local session = self:GetModule("SessionManager"):GetCurrentSession()
    if not session then
        self:Print("No active session.")
        return
    end

    local pending = self:GetModule("SessionManager"):GetPendingAwards(session.id)
    local count = 0

    self:Print("Pending trades:")
    for itemGUID, data in pairs(pending) do
        count = count + 1
        print(string.format("  %s -> %s", data.item.link, data.winner))
    end

    if count == 0 then
        print("  No pending trades.")
    end
end

function HooligansLoot:RunTest(arg)
    local LootTracker = self:GetModule("LootTracker", true)
    if not LootTracker then
        self:Print("LootTracker module not loaded!")
        return
    end

    if not arg or arg == "" then
        -- Show help
        LootTracker:ListTestRaids()
        return
    end

    local subCmd, countStr = self:GetArgs(arg, 2)
    subCmd = subCmd and subCmd:lower() or ""

    if subCmd == "kara" or subCmd == "karazhan" then
        local count = tonumber(countStr) or 8
        LootTracker:SimulateKarazhanRaid(count)
    elseif subCmd == "item" then
        LootTracker:AddTestItem()
    else
        LootTracker:ListTestRaids()
    end
end
