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
            -- Voting settings
            votingEnabled = true,
            voteTimeout = 300,            -- Seconds for raiders to respond (5 minutes)
            councilMode = "auto",         -- "auto" (raid assists) or "manual" (council list)
            councilList = {},             -- Manual council member list
            allowSelfVote = false,        -- Allow council members to vote for themselves
            announceResults = true,       -- Announce vote results in raid
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
        elseif arg == "votes" then
            self:DebugVotes()
        elseif arg == "scan" then
            -- Manual bag scan for debugging tracking issues
            local LootTracker = self:GetModule("LootTracker", true)
            if LootTracker then
                LootTracker:ManualScan()
            end
        elseif arg == "clear" then
            local Voting = self:GetModule("Voting", true)
            if Voting then
                Voting:ClearAllVotes()
                self:Print("Cleared all votes")
            end
        else
            self:ToggleDebug()
        end
    elseif cmd == "vote" then
        self:HandleVoteCommand(arg)
    elseif cmd == "sync" then
        self:HandleSyncCommand(arg)
    elseif cmd == "help" then
        self:PrintHelp()
    else
        self:Print("Unknown command. Type /hl help")
    end
end

function HooligansLoot:HandleVoteCommand(arg)
    local subCmd = arg and arg:lower() or ""

    if subCmd == "" then
        -- Smart default: if there are active votes to respond to, show LootFrame
        -- Otherwise show the setup dialog (for ML)
        local hasActiveVotes = self:HasActiveVotesToRespond()
        if hasActiveVotes then
            local LootFrame = self:GetModule("LootFrame", true)
            if LootFrame then
                LootFrame:Show()
            end
        else
            local SessionSetupFrame = self:GetModule("SessionSetupFrame", true)
            if SessionSetupFrame then
                SessionSetupFrame:Show()
            end
        end
    elseif subCmd == "setup" then
        -- Show vote setup dialog
        local SessionSetupFrame = self:GetModule("SessionSetupFrame", true)
        if SessionSetupFrame then
            SessionSetupFrame:Show()
        end
    elseif subCmd == "respond" then
        -- Show raider response frame
        local LootFrame = self:GetModule("LootFrame", true)
        if LootFrame then
            LootFrame:Show()
        end
    else
        self:Print("Vote commands:")
        print("  |cff88ccff/hl vote|r - Open vote frame (auto-detects active votes)")
        print("  |cff88ccff/hl vote setup|r - Open vote setup dialog (ML)")
        print("  |cff88ccff/hl vote respond|r - Open raider response frame")
    end
end

function HooligansLoot:HandleSyncCommand(arg)
    local subCmd = arg and arg:lower() or ""

    local SessionManager = self:GetModule("SessionManager", true)
    if not SessionManager then
        self:Print("SessionManager not loaded")
        return
    end

    if subCmd == "" or subCmd == "status" then
        self:ShowSyncStatus()
    elseif subCmd == "resync" or subCmd == "force" then
        SessionManager:ForceResync()
    elseif subCmd == "request" then
        -- Request sync from ML (for raiders)
        SessionManager:RequestSync()
        self:Print("Requested session sync from Raid Leader")
    elseif subCmd == "clear" then
        -- Clear ALL session data (synced + local) for raiders
        SessionManager:SetSyncedSession(nil)
        -- Also clear any old local session ID (from when player was ML before)
        if HooligansLoot.db.profile.currentSessionId then
            HooligansLoot:Print("Cleared old local session: " .. tostring(HooligansLoot.db.profile.currentSessionId))
            HooligansLoot.db.profile.currentSessionId = nil
        end
        self:Print("Cleared all session data. Use /hl sync request to get current session from Raid Leader.")
    else
        self:Print("Sync commands:")
        print("  |cff88ccff/hl sync|r - Show sync status")
        print("  |cff88ccff/hl sync resync|r - Force resync to all raiders (RL only)")
        print("  |cff88ccff/hl sync request|r - Request sync from Raid Leader")
        print("  |cff88ccff/hl sync clear|r - Clear stale session data")
    end
end

function HooligansLoot:ShowSyncStatus()
    local SessionManager = self:GetModule("SessionManager", true)
    local Voting = self:GetModule("Voting", true)

    self:Print("=== Session Sync Status ===")

    -- Check if we're ML
    local isML = Voting and Voting:IsMasterLooter()

    local session = SessionManager:GetCurrentSession()
    if not session then
        print("  No active session")
        print("=== End Sync Status ===")
        return
    end

    local isSynced = SessionManager:IsSyncedSession()
    print("  Session: " .. self.colors.primary .. session.name .. "|r")
    print("  Session ID: " .. session.id)
    print("  Status: " .. (session.status or "unknown"))
    print("  Type: " .. (isSynced and "Synced from ML" or "Local (I am ML)"))

    -- Show session age
    local age = time() - (session.created or time())
    local ageStr
    if age < 60 then
        ageStr = age .. " seconds"
    elseif age < 3600 then
        ageStr = math.floor(age / 60) .. " minutes"
    else
        ageStr = string.format("%.1f hours", age / 3600)
    end
    print("  Age: " .. ageStr)

    -- If ML, show who's synced
    if isML then
        local status = SessionManager:GetSyncStatus()
        if status then
            print("  ---")
            print("  |cff00ff00Synced players:|r " .. #status.syncedPlayers .. "/" .. status.totalRaidMembers)
            for _, p in ipairs(status.syncedPlayers) do
                local classColor = RAID_CLASS_COLORS[p.class] or { r = 1, g = 1, b = 1 }
                local colorCode = string.format("|cff%02x%02x%02x", classColor.r * 255, classColor.g * 255, classColor.b * 255)
                local zoneInfo = p.zone and (" (" .. p.zone .. ")") or ""
                print("    " .. colorCode .. p.name .. "|r" .. zoneInfo)
            end

            if #status.unsyncedPlayers > 0 then
                print("  |cffff0000Not synced:|r")
                for _, p in ipairs(status.unsyncedPlayers) do
                    local classColor = RAID_CLASS_COLORS[p.class] or { r = 1, g = 1, b = 1 }
                    local colorCode = string.format("|cff%02x%02x%02x", classColor.r * 255, classColor.g * 255, classColor.b * 255)
                    local extra = ""
                    if p.isML then
                        extra = " (ML - self)"
                    elseif p.oldSession then
                        extra = " |cffff8800(OLD SESSION!)|r"
                    end
                    print("    " .. colorCode .. p.name .. "|r" .. extra)
                end
            end

            print("  ---")
            print("  Use |cff88ccff/hl sync resync|r to force resync")
        end
    else
        -- Raider view
        print("  ---")
        print("  Use |cff88ccff/hl sync request|r to request sync from ML")
        print("  Use |cff88ccff/hl sync clear|r to clear stale session")
    end

    print("=== End Sync Status ===")
end

-- Check if there are active votes the player can respond to
function HooligansLoot:HasActiveVotesToRespond()
    local Voting = self:GetModule("Voting", true)
    if not Voting then return false end

    local activeVotes = Voting:GetActiveVotes()
    for voteId, vote in pairs(activeVotes) do
        if vote.status == Voting.Status.COLLECTING or vote.status == Voting.Status.VOTING then
            return true
        end
    end
    return false
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
    print("  |cffffcc00-- Voting --|r")
    print("  |cff88ccff/hl vote|r - Reopen vote window (auto-detects active votes)")
    print("  |cff88ccff/hl vote setup|r - Open vote setup dialog (ML)")
    print("  |cff88ccff/hl vote respond|r - Open raider response frame")
    print("  |cffffcc00-- Sync --|r")
    print("  |cff88ccff/hl sync|r - Show session sync status")
    print("  |cff88ccff/hl sync resync|r - Force resync to all raiders (ML)")
    print("  |cff88ccff/hl sync request|r - Request sync from ML")
    print("  |cff88ccff/hl sync clear|r - Clear stale session data")
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

function HooligansLoot:DebugVotes()
    self:Print("=== Votes Debug Info ===")

    local Voting = self:GetModule("Voting", true)
    if not Voting then
        print("  Voting module: NOT LOADED")
        return
    end

    local activeVotes = Voting:GetActiveVotes()
    local count = 0
    for _ in pairs(activeVotes) do count = count + 1 end
    print("  Active votes count: " .. count)

    local SessionManager = self:GetModule("SessionManager", true)
    local session = SessionManager and SessionManager:GetCurrentSession()
    local currentSessionId = session and session.id or "NONE"
    print("  Current session ID: " .. tostring(currentSessionId))

    -- Count session votes
    local sessionVoteCount = 0
    if session and session.votes then
        for _ in pairs(session.votes) do sessionVoteCount = sessionVoteCount + 1 end
    end
    print("  Session.votes count: " .. sessionVoteCount)

    -- Show session items
    if session then
        print("  Session items count: " .. #session.items)
    end

    local shown = 0
    for voteId, vote in pairs(activeVotes) do
        print("  ---")
        print("  VoteId: " .. tostring(voteId))
        print("  SessionId: " .. tostring(vote.sessionId))
        print("  MatchesCurrent: " .. tostring(vote.sessionId == currentSessionId))
        print("  ItemGUID: " .. tostring(vote.itemGUID))
        print("  Item name: " .. tostring(vote.item and vote.item.name))
        print("  Status: " .. tostring(vote.status))
        local respCount = vote.responses and NS.Utils.TableSize(vote.responses) or 0
        print("  Responses: " .. respCount)
        if respCount > 0 then
            for playerName, resp in pairs(vote.responses) do
                print("    " .. playerName .. ": " .. tostring(resp.response))
            end
        end
        -- Only show first 5 votes
        shown = shown + 1
        if shown >= 5 then
            print("  ... (" .. (count - shown) .. " more votes)")
            break
        end
    end
    print("=== End Debug ===")
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

    -- Check votes
    local voteCount = session.votes and NS.Utils.TableSize(session.votes) or 0
    print("  Votes in session: " .. tostring(voteCount))

    if session.votes and voteCount > 0 then
        for voteId, vote in pairs(session.votes) do
            local respCount = vote.responses and NS.Utils.TableSize(vote.responses) or 0
            print("    Vote " .. voteId .. ": status=" .. tostring(vote.status) .. ", responses=" .. tostring(respCount))
            if vote.responses and respCount > 0 then
                for playerName, resp in pairs(vote.responses) do
                    print("      " .. playerName .. ": " .. tostring(resp.response))
                end
            end
            break -- Just show first vote
        end
    end

    -- Check active votes
    local Voting = self:GetModule("Voting", true)
    if Voting then
        local activeVotes = Voting:GetActiveVotes()
        local activeCount = NS.Utils.TableSize(activeVotes)
        print("  Active votes (in memory): " .. tostring(activeCount))
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
