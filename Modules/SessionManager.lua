-- Modules/SessionManager.lua
-- Manages loot sessions

local ADDON_NAME, NS = ...
local HooligansLoot = NS.addon
local Utils = NS.Utils

local SessionManager = HooligansLoot:NewModule("SessionManager", "AceEvent-3.0")

-- Centralized UI refresh function - call this after any data change
-- Instant refresh with no delay for real-time updates
function SessionManager:RefreshAllUI()
    -- Refresh MainFrame
    local MainFrame = HooligansLoot:GetModule("MainFrame", true)
    if MainFrame and MainFrame:IsShown() then
        MainFrame:Refresh()
    end

    -- Refresh LootFrame (voting popup)
    local LootFrame = HooligansLoot:GetModule("LootFrame", true)
    if LootFrame and LootFrame:IsShown() then
        LootFrame:Refresh()
    end

    -- Refresh VotingFrame if exists
    local VotingFrame = HooligansLoot:GetModule("VotingFrame", true)
    if VotingFrame and VotingFrame.Refresh and VotingFrame:IsShown() then
        VotingFrame:Refresh()
    end
end

-- Refresh only response displays (MainFrame, VotingFrame) but NOT LootFrame
-- Use this when other players' responses come in to avoid closing the dropdown
function SessionManager:RefreshResponseDisplays()
    -- Refresh MainFrame (shows responses in the RESPONSES column)
    local MainFrame = HooligansLoot:GetModule("MainFrame", true)
    if MainFrame and MainFrame:IsShown() then
        MainFrame:Refresh()
    end

    -- Refresh VotingFrame (council voting UI)
    local VotingFrame = HooligansLoot:GetModule("VotingFrame", true)
    if VotingFrame and VotingFrame.Refresh and VotingFrame:IsShown() then
        VotingFrame:Refresh()
    end
    -- NOTE: LootFrame is intentionally NOT refreshed here to avoid closing dropdowns
end

-- Stale session threshold (4 hours in seconds)
local STALE_SESSION_THRESHOLD = 4 * 60 * 60

function SessionManager:OnEnable()
    -- Register for callbacks to auto-broadcast session changes
    HooligansLoot.RegisterCallback(self, "ITEM_ADDED", "OnSessionChanged")
    HooligansLoot.RegisterCallback(self, "ITEM_REMOVED", "OnSessionChanged")
    HooligansLoot.RegisterCallback(self, "AWARD_SET", "OnSessionChanged")
    HooligansLoot.RegisterCallback(self, "AWARD_COMPLETED", "OnSessionChanged")
    HooligansLoot.RegisterCallback(self, "VOTE_STARTED", "OnSessionChanged")
    HooligansLoot.RegisterCallback(self, "VOTE_UPDATED", "OnSessionChanged")
    HooligansLoot.RegisterCallback(self, "VOTE_ENDED", "OnSessionChanged")
    HooligansLoot.RegisterCallback(self, "SESSION_UPDATED", "OnSessionChanged")

    -- Register for group roster changes to auto-sync when new members join
    self:RegisterEvent("GROUP_ROSTER_UPDATE", "OnGroupRosterUpdate")

    -- Register for zone changes to check for stale sessions
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA", "OnZoneChanged")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnZoneChanged")

    -- Track group size for detecting new members
    self.lastGroupSize = GetNumGroupMembers()

    -- Check for stale sessions on enable
    C_Timer.After(2, function()
        self:CheckForStaleSessions()
    end)
end

-- Check and clear stale synced sessions
function SessionManager:CheckForStaleSessions()
    if not syncedSession then return end

    local now = time()
    local sessionAge = now - (syncedSession.created or now)

    -- Clear if older than threshold
    if sessionAge > STALE_SESSION_THRESHOLD then
        HooligansLoot:Print("|cffff8800Cleared stale session:|r " .. (syncedSession.name or "Unknown") .. " (over 4 hours old)")
        self:SetSyncedSession(nil)
        return true
    end

    -- Clear if session was already ended
    if syncedSession.status == "ended" then
        HooligansLoot:Debug("Cleared ended synced session")
        self:SetSyncedSession(nil)
        return true
    end

    return false
end

-- Called on zone change
function SessionManager:OnZoneChanged()
    -- Only check for stale sessions if we're a raider (have synced session)
    if self:IsSyncedSession() then
        -- Check if session is stale
        self:CheckForStaleSessions()
    end
end

-- Check if a session is stale
function SessionManager:IsSessionStale(session)
    if not session then return true end

    local now = time()
    local sessionAge = now - (session.created or now)

    -- Consider stale if older than threshold
    if sessionAge > STALE_SESSION_THRESHOLD then
        return true, "Session is over 4 hours old"
    end

    -- Consider stale if already ended
    if session.status == "ended" then
        return true, "Session has ended"
    end

    return false
end

-- Auto-broadcast session when group roster changes (new members join)
function SessionManager:OnGroupRosterUpdate()
    local currentSize = GetNumGroupMembers()
    local previousSize = self.lastGroupSize or 0
    self.lastGroupSize = currentSize

    -- Only broadcast if group grew (new members joined) and we're ML with active session
    if currentSize > previousSize then
        local Voting = HooligansLoot:GetModule("Voting", true)
        if Voting and Voting:IsMasterLooter() then
            local session = self:GetCurrentSession()
            if session and not self:IsSyncedSession() then
                HooligansLoot:Debug("Group grew from " .. previousSize .. " to " .. currentSize .. ", broadcasting session")
                -- Small delay to let the new member's addon initialize
                C_Timer.After(1, function()
                    self:BroadcastSession()
                end)
            end
        end
    end
end

-- Request session sync from ML (convenience wrapper for raiders)
function SessionManager:RequestSync()
    local Comm = HooligansLoot:GetModule("Comm", true)
    if Comm then
        return Comm:RequestSessionSync()
    end
    return false
end

-- Auto-broadcast session when changes occur (for awards only)
-- Item add/remove and vote updates are handled with lightweight messages
function SessionManager:OnSessionChanged(event)
    -- Skip session broadcast for events handled by lightweight messages
    if event == "VOTE_UPDATED" or event == "VOTE_STARTED" or event == "VOTE_ENDED" then
        return
    end
    if event == "ITEM_ADDED" or event == "ITEM_REMOVED" then
        -- Handled by lightweight ITEM_ADD/ITEM_REMOVE messages
        return
    end

    HooligansLoot:Debug("OnSessionChanged triggered for: " .. tostring(event))

    -- Minimal throttle (0.2s) for session broadcasts (awards only now)
    local now = GetTime()
    if self.lastBroadcastTime and (now - self.lastBroadcastTime) < 0.2 then
        if not self.pendingBroadcast then
            self.pendingBroadcast = true
            C_Timer.After(0.2, function()
                self.pendingBroadcast = false
                self:BroadcastSession()
            end)
        end
        return
    end
    self.lastBroadcastTime = now
    self:BroadcastSession()
end

function SessionManager:NewSession(name)
    -- Only ML/RL can start sessions when in a group
    if IsInGroup() then
        local Voting = HooligansLoot:GetModule("Voting", true)
        if Voting and not Voting:IsMasterLooter() then
            HooligansLoot:Print("Only the Raid Leader can start sessions.")
            return nil
        end
    end

    -- Clear synced players from previous session
    self:ClearSyncedPlayers()

    -- Auto-generate name if not provided
    if not name or name == "" then
        local zoneName = GetRealZoneText() or "Unknown"
        name = zoneName .. " - " .. date("%Y-%m-%d %H:%M")
    end

    local sessionId = "session_" .. time()

    local session = {
        id = sessionId,
        name = name,
        created = time(),
        status = "active",
        items = {},
        awards = {},
    }

    HooligansLoot.db.profile.sessions[sessionId] = session
    HooligansLoot.db.profile.currentSessionId = sessionId

    HooligansLoot:Print("Started new session: " .. HooligansLoot.colors.success .. name .. "|r")
    HooligansLoot.callbacks:Fire("SESSION_STARTED", session)

    -- Broadcast to group
    self:BroadcastSession()

    return session
end

function SessionManager:EndSession()
    local session = self:GetCurrentSession()
    if not session then
        HooligansLoot:Print("No active session to end.")
        return nil
    end

    session.status = "ended"
    session.ended = time()

    -- Broadcast the ended session to raiders BEFORE clearing local session
    self:BroadcastSession()

    HooligansLoot.db.profile.currentSessionId = nil

    HooligansLoot:Print("Ended session: " .. session.name .. " (" .. #session.items .. " items)")
    HooligansLoot.callbacks:Fire("SESSION_ENDED", session)

    return session
end

-- Synced session from ML (for non-ML raiders)
local syncedSession = nil

-- Track which players have acknowledged receiving the session sync (ML only)
local syncedPlayers = {}

function SessionManager:GetCurrentSession()
    -- First check for local session (ML has this)
    local sessionId = HooligansLoot.db.profile.currentSessionId
    if sessionId then
        return HooligansLoot.db.profile.sessions[sessionId]
    end
    -- Fall back to synced session from ML
    return syncedSession
end

-- Set synced session received from ML
function SessionManager:SetSyncedSession(session)
    syncedSession = session
    HooligansLoot:Debug("Synced session set: " .. (session and session.name or "nil"))
    HooligansLoot.callbacks:Fire("SESSION_SYNCED", session)

    -- Force all UI refresh
    self:RefreshAllUI()
end

-- Get synced session (for checking if we have one)
function SessionManager:GetSyncedSession()
    return syncedSession
end

-- Check if current session is synced (not local)
function SessionManager:IsSyncedSession()
    local sessionId = HooligansLoot.db.profile.currentSessionId
    return sessionId == nil and syncedSession ~= nil
end

-- Called when a player acknowledges receiving session sync (ML only)
function SessionManager:OnPlayerSynced(playerName, data)
    local session = self:GetCurrentSession()
    if not session then return end

    -- Verify it's for the current session
    if data.sessionId ~= session.id then
        HooligansLoot:Debug("Sync ACK for wrong session: " .. tostring(data.sessionId) .. " vs " .. tostring(session.id))
        return
    end

    syncedPlayers[playerName] = {
        syncedAt = time(),
        class = data.class,
        zone = data.zone,
        sessionId = data.sessionId,
        version = data.version,
    }

    HooligansLoot:Debug("Player synced: " .. playerName .. " (zone: " .. tostring(data.zone) .. ", version: " .. tostring(data.version) .. ")")
    HooligansLoot.callbacks:Fire("PLAYER_SYNCED", playerName, data)
end

-- Get list of synced players
function SessionManager:GetSyncedPlayers()
    return syncedPlayers
end

-- Clear synced players (called when starting new session)
function SessionManager:ClearSyncedPlayers()
    syncedPlayers = {}
end

-- Get sync status for all raid members (ML only)
function SessionManager:GetSyncStatus()
    local session = self:GetCurrentSession()
    if not session then
        return nil, "No active session"
    end

    local status = {
        sessionId = session.id,
        sessionName = session.name,
        sessionCreated = session.created,
        syncedPlayers = {},
        unsyncedPlayers = {},
        totalRaidMembers = 0,
    }

    -- Get all raid/party members
    local numMembers = GetNumGroupMembers()
    local isRaid = IsInRaid()

    -- Check if we are the ML or a raider with synced session
    local Voting = HooligansLoot:GetModule("Voting", true)
    local weAreML = Voting and Voting:IsMasterLooter()
    local playerName = UnitName("player")
    local weHaveSyncedSession = self:IsSyncedSession()  -- Raider with synced session from ML

    for i = 1, numMembers do
        local unit = isRaid and ("raid" .. i) or (i == 1 and "player" or ("party" .. (i - 1)))
        local name = UnitName(unit)
        local _, class = UnitClass(unit)

        if name then
            status.totalRaidMembers = status.totalRaidMembers + 1
            local playerData = syncedPlayers[name]

            local isSelf = (name == playerName)

            -- Get our own addon version
            local myVersion = Utils.GetAddonVersion()

            -- ML always counts as synced (they are the source of truth)
            if weAreML and isSelf then
                table.insert(status.syncedPlayers, {
                    name = name,
                    class = class,
                    syncedAt = session.created,
                    zone = GetRealZoneText(),
                    isML = true,
                    version = myVersion,
                })
            -- Raider with synced session counts themselves as synced
            elseif weHaveSyncedSession and isSelf then
                table.insert(status.syncedPlayers, {
                    name = name,
                    class = class,
                    syncedAt = time(),
                    zone = GetRealZoneText(),
                    version = myVersion,
                })
            -- ML can see who has acknowledged
            elseif weAreML and playerData and playerData.sessionId == session.id then
                table.insert(status.syncedPlayers, {
                    name = name,
                    class = class,
                    syncedAt = playerData.syncedAt,
                    zone = playerData.zone,
                    version = playerData.version,
                })
            else
                table.insert(status.unsyncedPlayers, {
                    name = name,
                    class = class,
                    isML = false,
                    oldSession = playerData and playerData.sessionId or nil,
                })
            end
        end
    end

    return status
end

-- Force resync session to all members
function SessionManager:ForceResync()
    local Voting = HooligansLoot:GetModule("Voting", true)
    if not Voting or not Voting:IsMasterLooter() then
        HooligansLoot:Print("Only Raid Leader can force resync")
        return false
    end

    local session = self:GetCurrentSession()
    if not session or self:IsSyncedSession() then
        HooligansLoot:Print("No local session to resync")
        return false
    end

    -- Clear synced players to get fresh acknowledgments
    self:ClearSyncedPlayers()

    -- Broadcast session
    self:BroadcastSession()

    HooligansLoot:Print("Session resync broadcast sent")
    return true
end

-- Broadcast current session to group (ML only)
function SessionManager:BroadcastSession()
    HooligansLoot:Debug("BroadcastSession called")

    -- Only broadcast if we're the ML/RL and have a local session
    local Voting = HooligansLoot:GetModule("Voting", true)
    if not Voting or not Voting:IsMasterLooter() then
        HooligansLoot:Debug("BroadcastSession: Not ML/RL, skipping")
        return
    end

    local session = self:GetCurrentSession()
    if not session or self:IsSyncedSession() then
        HooligansLoot:Debug("BroadcastSession: No local session, skipping")
        return
    end

    -- Only broadcast if in a group
    if not IsInGroup() then
        HooligansLoot:Debug("BroadcastSession: Not in group, skipping")
        return
    end

    local Comm = HooligansLoot:GetModule("Comm", true)
    if not Comm then return end

    -- For ended sessions, send minimal "ended" message only
    if session.status == "ended" then
        Comm:BroadcastMessage(Comm.MessageTypes.SESSION_SYNC, {
            session = {
                id = session.id,
                status = "ended",
            },
        })
        HooligansLoot:Debug("Broadcast session END: " .. session.name)
        return
    end

    -- Build MINIMAL session data - only item links, reconstruct rest on receiver
    local minimalItems = {}
    for _, item in ipairs(session.items) do
        table.insert(minimalItems, {
            g = item.guid,         -- shortened keys
            l = item.link,         -- link contains all item info
            b = item.boss,         -- boss name if tracked
        })
    end

    -- Minimal awards - just guid -> winner mapping
    local minimalAwards = {}
    if session.awards then
        for guid, award in pairs(session.awards) do
            minimalAwards[guid] = award.winner  -- just the winner name
        end
    end

    local sessionData = {
        id = session.id,
        n = session.name,          -- shortened key
        status = session.status,
        i = minimalItems,          -- shortened key
        a = minimalAwards,         -- shortened key
    }

    Comm:BroadcastMessage(Comm.MessageTypes.SESSION_SYNC, {
        session = sessionData,
    })
    HooligansLoot:Debug("Broadcast session sync: " .. session.name .. " (" .. #session.items .. " items)")
end

function SessionManager:GetSession(sessionId)
    return HooligansLoot.db.profile.sessions[sessionId]
end

function SessionManager:GetAllSessions()
    return HooligansLoot.db.profile.sessions
end

function SessionManager:GetSessionsSorted()
    local sessions = {}
    for id, session in pairs(HooligansLoot.db.profile.sessions) do
        table.insert(sessions, session)
    end
    -- Sort by creation time, newest first
    table.sort(sessions, function(a, b) return a.created > b.created end)
    return sessions
end

function SessionManager:ListSessions()
    local sessions = self:GetSessionsSorted()

    HooligansLoot:Print("Sessions:")
    if #sessions == 0 then
        print("  No sessions found. Start one with /hl session new")
        return
    end

    for _, session in ipairs(sessions) do
        local status = ""
        if session.status == "active" then
            status = HooligansLoot.colors.success .. " [ACTIVE]|r"
        elseif session.status == "completed" then
            status = HooligansLoot.colors.primary .. " [COMPLETED]|r"
        end

        local awarded = 0
        local total = #session.items
        for _, award in pairs(session.awards) do
            if award.awarded then
                awarded = awarded + 1
            end
        end

        local awardInfo = ""
        if Utils.TableSize(session.awards) > 0 then
            awardInfo = string.format(" (%d/%d awarded)", awarded, Utils.TableSize(session.awards))
        end

        print(string.format("  %s%s - %d items%s", session.name, status, total, awardInfo))
    end
end

function SessionManager:DeleteSession(sessionId)
    local session = HooligansLoot.db.profile.sessions[sessionId]
    if not session then return false end

    if HooligansLoot.db.profile.currentSessionId == sessionId then
        HooligansLoot.db.profile.currentSessionId = nil
    end

    HooligansLoot.db.profile.sessions[sessionId] = nil
    HooligansLoot:Print("Deleted session: " .. session.name)
    HooligansLoot.callbacks:Fire("SESSION_DELETED", sessionId)

    return true
end

function SessionManager:RenameSession(sessionId, newName)
    -- If no sessionId provided, use current session
    local session
    if sessionId then
        session = self:GetSession(sessionId)
    else
        session = self:GetCurrentSession()
    end

    if not session then return false end
    if not newName or newName == "" then return false end

    local oldName = session.name
    session.name = newName

    HooligansLoot:Print("Renamed session: " .. oldName .. " -> " .. newName)
    HooligansLoot.callbacks:Fire("SESSION_UPDATED", session)

    return true
end

function SessionManager:SetSessionActive(sessionId)
    local session = self:GetSession(sessionId)
    if not session then return false end

    -- End any current active session first
    local current = self:GetCurrentSession()
    if current and current.id ~= sessionId then
        current.status = "ended"
        if not current.ended then
            current.ended = time()
        end
    end

    session.status = "active"
    HooligansLoot.db.profile.currentSessionId = sessionId

    HooligansLoot:Print("Activated session: " .. session.name)
    HooligansLoot.callbacks:Fire("SESSION_ACTIVATED", session)

    return true
end

function SessionManager:SetAward(sessionId, itemGUID, playerName, playerClass)
    local session = self:GetSession(sessionId)
    if not session then return false end

    -- Try to get class from raid roster if not provided
    if not playerClass then
        playerClass = Utils.GetPlayerClass(playerName)
    end

    session.awards[itemGUID] = {
        winner = playerName,
        class = playerClass,
        awarded = false,
        awardedAt = nil,
    }

    HooligansLoot:Debug("Award set: " .. itemGUID .. " -> " .. playerName .. " (" .. (playerClass or "unknown") .. ")")
    HooligansLoot.callbacks:Fire("AWARD_SET", session, itemGUID, playerName)
    return true
end

function SessionManager:ClearAward(sessionId, itemGUID)
    local session = self:GetSession(sessionId)
    if not session then return false end

    session.awards[itemGUID] = nil

    HooligansLoot:Debug("Award cleared: " .. itemGUID)
    HooligansLoot.callbacks:Fire("AWARD_CLEARED", session, itemGUID)
    return true
end

function SessionManager:MarkAwarded(sessionId, itemGUID)
    local session = self:GetSession(sessionId)
    if not session or not session.awards[itemGUID] then return false end

    session.awards[itemGUID].awarded = true
    session.awards[itemGUID].awardedAt = time()

    HooligansLoot:Debug("Award completed: " .. itemGUID)
    HooligansLoot.callbacks:Fire("AWARD_COMPLETED", session, itemGUID)

    -- Check if all items are awarded
    self:CheckSessionComplete(sessionId)

    return true
end

function SessionManager:CheckSessionComplete(sessionId)
    local session = self:GetSession(sessionId)
    if not session then return end

    -- Check if all awards are completed
    local allAwarded = true
    for itemGUID, award in pairs(session.awards) do
        if not award.awarded then
            allAwarded = false
            break
        end
    end

    if allAwarded and Utils.TableSize(session.awards) > 0 then
        session.status = "completed"
        HooligansLoot:Print("Session completed: " .. session.name)
        HooligansLoot.callbacks:Fire("SESSION_COMPLETED", session)
    end
end

function SessionManager:GetPendingAwards(sessionId)
    local session = self:GetSession(sessionId)
    if not session then return {} end

    local pending = {}
    for itemGUID, award in pairs(session.awards) do
        if not award.awarded then
            -- Find the item
            for _, item in ipairs(session.items) do
                if item.guid == itemGUID then
                    pending[itemGUID] = {
                        item = item,
                        winner = award.winner,
                    }
                    break
                end
            end
        end
    end

    return pending
end

function SessionManager:GetAwardsForPlayer(sessionId, playerName)
    local session = self:GetSession(sessionId)
    if not session then return {} end

    -- Normalize player name (strip realm if present)
    playerName = Utils.StripRealm(playerName)

    local items = {}
    for itemGUID, award in pairs(session.awards) do
        local awardWinner = Utils.StripRealm(award.winner)
        if awardWinner == playerName and not award.awarded then
            for _, item in ipairs(session.items) do
                if item.guid == itemGUID then
                    table.insert(items, item)
                    break
                end
            end
        end
    end

    return items
end

function SessionManager:GetItemByGUID(sessionId, itemGUID)
    local session = self:GetSession(sessionId)
    if not session then return nil end

    for _, item in ipairs(session.items) do
        if item.guid == itemGUID then
            return item
        end
    end

    return nil
end

function SessionManager:RemoveItem(sessionId, itemGUID)
    local session
    if sessionId then
        session = self:GetSession(sessionId)
    else
        session = self:GetCurrentSession()
        sessionId = session and session.id
    end

    if not session then return false end

    -- Find and remove the item
    local removedItem = nil
    for i, item in ipairs(session.items) do
        if item.guid == itemGUID then
            removedItem = table.remove(session.items, i)
            break
        end
    end

    if not removedItem then return false end

    -- Also remove any award for this item
    if session.awards[itemGUID] then
        session.awards[itemGUID] = nil
    end

    HooligansLoot:Print("Removed: " .. (removedItem.link or removedItem.name or "Unknown Item"))
    HooligansLoot.callbacks:Fire("ITEM_REMOVED", session, removedItem)

    -- Send lightweight ITEM_REMOVE message for faster sync
    if IsInGroup() then
        local Comm = HooligansLoot:GetModule("Comm", true)
        if Comm then
            Comm:BroadcastMessage(Comm.MessageTypes.ITEM_REMOVE, {
                guid = itemGUID,
            })
        end
    end

    -- Refresh local UI immediately
    self:RefreshAllUI()

    return true
end

function SessionManager:GetItemsByItemID(sessionId, itemID)
    local session = self:GetSession(sessionId)
    if not session then return {} end

    local items = {}
    for _, item in ipairs(session.items) do
        if item.id == itemID then
            table.insert(items, item)
        end
    end

    return items
end

function SessionManager:GetAwardForItem(sessionId, itemGUID)
    local session = self:GetSession(sessionId)
    if not session then return nil end

    return session.awards[itemGUID]
end

function SessionManager:GetSessionStats(sessionId)
    local session = self:GetSession(sessionId)
    if not session then return nil end

    local stats = {
        totalItems = #session.items,
        totalAwards = Utils.TableSize(session.awards),
        pendingAwards = 0,
        completedAwards = 0,
        expiredItems = 0,
    }

    local now = time()
    for _, item in ipairs(session.items) do
        if item.tradeExpires and item.tradeExpires < now then
            stats.expiredItems = stats.expiredItems + 1
        end
    end

    for _, award in pairs(session.awards) do
        if award.awarded then
            stats.completedAwards = stats.completedAwards + 1
        else
            stats.pendingAwards = stats.pendingAwards + 1
        end
    end

    return stats
end
