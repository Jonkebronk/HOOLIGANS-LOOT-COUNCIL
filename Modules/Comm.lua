-- Modules/Comm.lua
-- Communication handler for addon messaging

local ADDON_NAME, NS = ...
local HooligansLoot = NS.addon
local Utils = NS.Utils

local Comm = HooligansLoot:NewModule("Comm")

-- Constants
local COMM_PREFIX = "HLoot"
local PROTOCOL_VERSION = 1

-- Message types
Comm.MessageTypes = {
    VOTE_START = "VS",      -- Master Looter starts a vote
    VOTE_RESPONSE = "VR",   -- Raider responds with preference
    VOTE_CAST = "VC",       -- Council member casts a vote
    VOTE_UPDATE = "VU",     -- Status update broadcast
    VOTE_END = "VE",        -- Vote ended, winner announced
    VOTE_CANCEL = "VX",     -- Vote cancelled
    SYNC_REQUEST = "SR",    -- Request sync from ML
    SYNC_RESPONSE = "SS",   -- Sync data response
    COUNCIL_SYNC = "CS",    -- ML broadcasts council list to group
    SESSION_SYNC = "SY",    -- ML broadcasts session data to group
    ITEM_REMOVE = "IR",     -- ML removed an item from session (lightweight)
    ITEM_ADD = "IA",        -- ML added an item to session (lightweight)
    SESSION_REQUEST = "SQ", -- Raider requests session sync from ML
    SYNC_ACK = "SA",        -- Raider acknowledges session sync received
    VOTE_CONFIRMED = "VF",  -- Raider confirmed their votes (done voting)
    GEAR_SYNC = "GS",       -- Raider sends equipped gear to ML
}

-- Track pending messages for throttling
local pendingMessages = {}
local messageQueue = {}
local isProcessingQueue = false

function Comm:OnEnable()
    -- Register comm prefix
    HooligansLoot:RegisterComm(COMM_PREFIX, function(prefix, message, distribution, sender)
        self:OnCommReceived(prefix, message, distribution, sender)
    end)

    HooligansLoot:Debug("Comm module enabled, prefix: " .. COMM_PREFIX)
end

function Comm:OnDisable()
    -- Nothing to clean up
end

-- Message types that should use ALERT priority for real-time delivery
local ALERT_PRIORITY_TYPES = {
    [Comm.MessageTypes.VOTE_START] = true,
    [Comm.MessageTypes.VOTE_RESPONSE] = true,
    [Comm.MessageTypes.VOTE_UPDATE] = true,
    [Comm.MessageTypes.VOTE_END] = true,
    [Comm.MessageTypes.VOTE_CANCEL] = true,
    [Comm.MessageTypes.SESSION_SYNC] = true,
    [Comm.MessageTypes.ITEM_REMOVE] = true,
    [Comm.MessageTypes.ITEM_ADD] = true,
    [Comm.MessageTypes.VOTE_CONFIRMED] = true,
    [Comm.MessageTypes.GEAR_SYNC] = true,
}

-- Get priority for message type (ALERT for real-time, NORMAL for bulk)
function Comm:GetPriority(msgType)
    return ALERT_PRIORITY_TYPES[msgType] and "ALERT" or "NORMAL"
end

-- Send a message to a specific player
function Comm:SendMessage(msgType, data, target)
    local message = self:PackMessage(msgType, data)
    if not message then return false end

    local priority = self:GetPriority(msgType)
    HooligansLoot:SendCommMessage(COMM_PREFIX, message, "WHISPER", target, priority)
    HooligansLoot:Debug("Sent " .. msgType .. " to " .. target .. " (priority: " .. priority .. ")")
    return true
end

-- Broadcast a message to the raid/party
function Comm:BroadcastMessage(msgType, data)
    local message = self:PackMessage(msgType, data)
    if not message then return false end

    local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY" or nil)
    if not channel then
        -- Solo mode - handle locally for testing
        HooligansLoot:Debug("Solo mode - handling message locally: " .. msgType)
        -- Simulate receiving our own message for testing
        C_Timer.After(0.1, function()
            self:OnCommReceived(COMM_PREFIX, message, "WHISPER", UnitName("player"))
        end)
        return true
    end

    local priority = self:GetPriority(msgType)
    HooligansLoot:SendCommMessage(COMM_PREFIX, message, channel, nil, priority)
    HooligansLoot:Debug("Broadcast " .. msgType .. " to " .. channel .. " (priority: " .. priority .. ")")
    return true
end

-- Pack a message for sending
function Comm:PackMessage(msgType, data)
    local payload = {
        v = PROTOCOL_VERSION,
        t = msgType,
        d = data,
        ts = time(),
    }

    local success, serialized = pcall(function()
        return HooligansLoot:Serialize(payload)
    end)

    if not success then
        HooligansLoot:Debug("Failed to serialize message: " .. tostring(serialized))
        return nil
    end

    return serialized
end

-- Unpack a received message
function Comm:UnpackMessage(message)
    local success, payload = HooligansLoot:Deserialize(message)

    if not success then
        HooligansLoot:Debug("Failed to deserialize message")
        return nil
    end

    -- Version check
    if payload.v ~= PROTOCOL_VERSION then
        HooligansLoot:Debug("Protocol version mismatch: " .. tostring(payload.v) .. " vs " .. PROTOCOL_VERSION)
        -- Still try to process for forward compatibility
    end

    return payload
end

-- Handle received communication
function Comm:OnCommReceived(prefix, message, distribution, sender)
    if prefix ~= COMM_PREFIX then return end

    -- Don't process our own messages in group (except in solo mode or debug mode)
    local playerName = UnitName("player")
    local isSolo = not IsInGroup()
    if sender == playerName and not isSolo and not HooligansLoot.db.profile.settings.debug then
        return
    end

    local payload = self:UnpackMessage(message)
    if not payload then return end

    HooligansLoot:Debug("Received " .. tostring(payload.t) .. " from " .. sender)

    -- Route to appropriate handler
    local msgType = payload.t
    local data = payload.d

    if msgType == self.MessageTypes.VOTE_START then
        self:HandleVoteStart(data, sender)
    elseif msgType == self.MessageTypes.VOTE_RESPONSE then
        self:HandleVoteResponse(data, sender)
    elseif msgType == self.MessageTypes.VOTE_CAST then
        self:HandleVoteCast(data, sender)
    elseif msgType == self.MessageTypes.VOTE_UPDATE then
        self:HandleVoteUpdate(data, sender)
    elseif msgType == self.MessageTypes.VOTE_END then
        self:HandleVoteEnd(data, sender)
    elseif msgType == self.MessageTypes.VOTE_CANCEL then
        self:HandleVoteCancel(data, sender)
    elseif msgType == self.MessageTypes.SYNC_REQUEST then
        self:HandleSyncRequest(data, sender)
    elseif msgType == self.MessageTypes.SYNC_RESPONSE then
        self:HandleSyncResponse(data, sender)
    elseif msgType == self.MessageTypes.COUNCIL_SYNC then
        self:HandleCouncilSync(data, sender)
    elseif msgType == self.MessageTypes.SESSION_SYNC then
        self:HandleSessionSync(data, sender)
    elseif msgType == self.MessageTypes.ITEM_REMOVE then
        self:HandleItemRemove(data, sender)
    elseif msgType == self.MessageTypes.ITEM_ADD then
        self:HandleItemAdd(data, sender)
    elseif msgType == self.MessageTypes.SESSION_REQUEST then
        self:HandleSessionRequest(data, sender)
    elseif msgType == self.MessageTypes.SYNC_ACK then
        self:HandleSyncAck(data, sender)
    elseif msgType == self.MessageTypes.VOTE_CONFIRMED then
        self:HandleVoteConfirmed(data, sender)
    elseif msgType == self.MessageTypes.GEAR_SYNC then
        self:HandleGearSync(data, sender)
    else
        HooligansLoot:Debug("Unknown message type: " .. tostring(msgType))
    end
end

-- Message handlers (delegate to Voting module)
function Comm:HandleVoteStart(data, sender)
    local Voting = HooligansLoot:GetModule("Voting", true)
    if Voting then
        Voting:OnVoteStart(data, sender)
    end
end

function Comm:HandleVoteResponse(data, sender)
    local Voting = HooligansLoot:GetModule("Voting", true)
    if Voting then
        Voting:OnVoteResponse(data, sender)
    end
end

function Comm:HandleVoteCast(data, sender)
    local Voting = HooligansLoot:GetModule("Voting", true)
    if Voting then
        Voting:OnVoteCast(data, sender)
    end
end

function Comm:HandleVoteUpdate(data, sender)
    local Voting = HooligansLoot:GetModule("Voting", true)
    if Voting then
        Voting:OnVoteUpdate(data, sender)
    end
end

function Comm:HandleVoteEnd(data, sender)
    local Voting = HooligansLoot:GetModule("Voting", true)
    if Voting then
        Voting:OnVoteEnd(data, sender)
    end
end

function Comm:HandleVoteCancel(data, sender)
    local Voting = HooligansLoot:GetModule("Voting", true)
    if Voting then
        Voting:OnVoteCancel(data, sender)
    end
end

function Comm:HandleSyncRequest(data, sender)
    local Voting = HooligansLoot:GetModule("Voting", true)
    if Voting then
        Voting:OnSyncRequest(data, sender)
    end
end

function Comm:HandleSyncResponse(data, sender)
    local Voting = HooligansLoot:GetModule("Voting", true)
    if Voting then
        Voting:OnSyncResponse(data, sender)
    end
end

function Comm:HandleCouncilSync(data, sender)
    local Voting = HooligansLoot:GetModule("Voting", true)
    if Voting then
        Voting:OnCouncilSync(data, sender)
    end
end

function Comm:HandleSessionSync(data, sender)
    local SessionManager = HooligansLoot:GetModule("SessionManager", true)
    if SessionManager then
        -- Check if WE are the ML - if so, ignore syncs from others
        local Voting = HooligansLoot:GetModule("Voting", true)
        local iAmML = Voting and Voting:IsMasterLooter()

        if iAmML then
            -- We're ML, ignore session syncs from others
            HooligansLoot:Debug("Ignoring SESSION_SYNC from " .. sender .. " - I am ML")
            return
        end

        -- We're NOT the ML - clear any old local session and accept the sync
        if HooligansLoot.db.profile.currentSessionId then
            HooligansLoot:Debug("Clearing old local session to accept sync from " .. sender)
            HooligansLoot.db.profile.currentSessionId = nil
        end

        -- Process the sync
        if true then
            -- Check if session was ended by ML
            if data.session and data.session.status == "ended" then
                -- Clear the synced session when ML ends it
                SessionManager:SetSyncedSession(nil)
                HooligansLoot:Debug("Session ended by " .. sender)

                -- Hide LootFrame when session ends
                local LootFrame = HooligansLoot:GetModule("LootFrame", true)
                if LootFrame then
                    LootFrame:Hide()
                end

                -- Clear any active votes
                local Voting = HooligansLoot:GetModule("Voting", true)
                if Voting then
                    Voting:ClearAllVotes()
                end
            else
                -- Reconstruct full session data from minimal format
                local session = data.session
                local fullSession = {
                    id = session.id,
                    name = session.name or session.n,  -- support both formats
                    status = session.status,
                    items = {},
                    awards = {},
                }

                -- Reconstruct items from minimal format (i) or old format (items)
                local itemsData = session.i or session.items or {}
                for _, item in ipairs(itemsData) do
                    -- Support both old format (full data) and new format (minimal)
                    local itemLink = item.l or item.link
                    local itemGuid = item.g or item.guid
                    local itemBoss = item.b or item.boss

                    -- Reconstruct full item data from link
                    local itemName, _, itemQuality, _, _, _, _, _, _, itemIcon = GetItemInfo(itemLink or "")
                    local itemId = itemLink and tonumber(itemLink:match("item:(%d+)"))

                    -- Fallback if item not cached
                    if not itemName and itemLink then
                        itemName = itemLink:match("%[(.-)%]") or "Unknown Item"
                    end

                    table.insert(fullSession.items, {
                        guid = itemGuid,
                        id = itemId or item.id,
                        link = itemLink,
                        name = itemName or item.name or "Unknown Item",
                        quality = itemQuality or item.quality or 4,
                        icon = itemIcon or item.icon or "Interface\\Icons\\INV_Misc_QuestionMark",
                        boss = itemBoss,
                    })
                end

                -- Reconstruct awards from minimal format (a) or old format (awards)
                local awardsData = session.a or session.awards or {}
                for guid, award in pairs(awardsData) do
                    if type(award) == "string" then
                        -- New minimal format: just winner name
                        fullSession.awards[guid] = { winner = award }
                    else
                        -- Old format: full award object
                        fullSession.awards[guid] = award
                    end
                end

                SessionManager:SetSyncedSession(fullSession)
                HooligansLoot:Debug("Session synced from " .. sender .. " (" .. #fullSession.items .. " items)")

                -- Send acknowledgment back to ML
                self:SendSyncAck(fullSession.id, sender)
            end
        end
    end
    -- Also process council data if included
    if data.council then
        local Voting = HooligansLoot:GetModule("Voting", true)
        if Voting then
            Voting:OnCouncilSync(data.council, sender)
        end
    end
end

-- Handle lightweight item removal
function Comm:HandleItemRemove(data, sender)
    local SessionManager = HooligansLoot:GetModule("SessionManager", true)
    if not SessionManager then return end

    -- Only process if we have a synced session (we're not ML)
    if HooligansLoot.db.profile.currentSessionId then return end

    local syncedSession = SessionManager:GetSyncedSession()
    if not syncedSession then return end

    -- Remove the item from synced session
    local itemGUID = data.guid
    if itemGUID then
        for i, item in ipairs(syncedSession.items) do
            if item.guid == itemGUID then
                table.remove(syncedSession.items, i)
                HooligansLoot:Debug("Item removed from synced session: " .. tostring(itemGUID))
                break
            end
        end

        -- Also remove award if any
        if syncedSession.awards[itemGUID] then
            syncedSession.awards[itemGUID] = nil
        end

        -- Refresh UI immediately
        SessionManager:RefreshAllUI()
    end
end

-- Handle lightweight item addition
function Comm:HandleItemAdd(data, sender)
    local SessionManager = HooligansLoot:GetModule("SessionManager", true)
    if not SessionManager then return end

    -- Only process if we have a synced session (we're not ML)
    if HooligansLoot.db.profile.currentSessionId then return end

    local syncedSession = SessionManager:GetSyncedSession()
    if not syncedSession then return end

    -- Add the item to synced session
    if data.item then
        -- Reconstruct item data
        local itemLink = data.item.link or data.item.l
        local itemName, _, itemQuality, _, _, _, _, _, _, itemIcon = GetItemInfo(itemLink)

        local newItem = {
            guid = data.item.guid or data.item.g,
            id = data.item.id,
            link = itemLink,
            name = itemName or data.item.name or "Unknown Item",
            quality = itemQuality or data.item.quality or 4,
            icon = itemIcon or data.item.icon or "Interface\\Icons\\INV_Misc_QuestionMark",
            boss = data.item.boss or data.item.b,
        }

        table.insert(syncedSession.items, newItem)
        HooligansLoot:Debug("Item added to synced session: " .. tostring(newItem.name))

        -- Refresh UI immediately
        SessionManager:RefreshAllUI()
    end
end

-- Utility: Get communication channel
function Comm:GetChannel()
    if IsInRaid() then
        return "RAID"
    elseif IsInGroup() then
        return "PARTY"
    end
    return nil
end

-- Utility: Check if we can communicate
function Comm:CanCommunicate()
    return IsInGroup() or IsInRaid()
end

-- Handle session request from raider - ML responds with session data
function Comm:HandleSessionRequest(data, sender)
    local Voting = HooligansLoot:GetModule("Voting", true)
    if not Voting or not Voting:IsMasterLooter() then
        -- Only ML/RL responds to session requests
        return
    end

    HooligansLoot:Debug("Session request received from: " .. sender)

    -- Broadcast session to the group (will reach the requester)
    local SessionManager = HooligansLoot:GetModule("SessionManager", true)
    if SessionManager then
        SessionManager:BroadcastSession()
    end
end

-- Request session sync from ML (for raiders)
function Comm:RequestSessionSync()
    if not IsInGroup() then
        HooligansLoot:Debug("RequestSessionSync: Not in group")
        return false
    end

    -- Don't request if we're the ML (we have the session locally)
    local Voting = HooligansLoot:GetModule("Voting", true)
    if Voting and Voting:IsMasterLooter() then
        HooligansLoot:Debug("RequestSessionSync: We are ML, no need to request")
        return false
    end

    HooligansLoot:Debug("Requesting session sync from ML")
    self:BroadcastMessage(self.MessageTypes.SESSION_REQUEST, {})
    return true
end

-- Send sync acknowledgment to ML
function Comm:SendSyncAck(sessionId, mlName)
    local playerName = UnitName("player")
    local _, playerClass = UnitClass("player")
    local zone = GetRealZoneText() or "Unknown"
    local addonVersion = Utils.GetAddonVersion()

    self:SendMessage(self.MessageTypes.SYNC_ACK, {
        sessionId = sessionId,
        player = playerName,
        class = playerClass,
        zone = zone,
        version = addonVersion,
    }, mlName)

    HooligansLoot:Debug("Sent sync ACK for session " .. tostring(sessionId) .. " to " .. mlName)
end

-- Handle sync acknowledgment from raider (ML only)
function Comm:HandleSyncAck(data, sender)
    local Voting = HooligansLoot:GetModule("Voting", true)
    if not Voting or not Voting:IsMasterLooter() then
        -- Only ML processes sync ACKs
        return
    end

    local SessionManager = HooligansLoot:GetModule("SessionManager", true)
    if SessionManager then
        SessionManager:OnPlayerSynced(sender, data)
    end
end

function Comm:HandleVoteConfirmed(data, sender)
    local Voting = HooligansLoot:GetModule("Voting", true)
    if Voting then
        Voting:ReceiveVoteConfirmation(sender, data.class)
    end
end

function Comm:HandleGearSync(data, sender)
    local GearComparison = HooligansLoot:GetModule("GearComparison", true)
    if GearComparison then
        GearComparison:ProcessGearSync(data, sender)
    end
end
