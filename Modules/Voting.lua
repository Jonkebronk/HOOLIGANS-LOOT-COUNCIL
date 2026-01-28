-- Modules/Voting.lua
-- Core voting logic and state management

local ADDON_NAME, NS = ...
local HooligansLoot = NS.addon
local Utils = NS.Utils

local Voting = HooligansLoot:NewModule("Voting")

-- Vote status constants
Voting.Status = {
    COLLECTING = "collecting",  -- Waiting for raider responses
    VOTING = "voting",          -- Council voting phase
    DECIDED = "decided",        -- Winner determined
    CANCELLED = "cancelled",    -- Vote was cancelled
}

-- Response types matching HOOLIGANS platform (no Pass - no response = pass)
Voting.ResponseTypes = {
    BIS = { id = "bis", text = "BiS", color = "00ff00", priority = 6 },
    GREATER = { id = "greater", text = "Greater Upgrade", color = "00cc66", priority = 5 },
    MINOR = { id = "minor", text = "Minor Upgrade", color = "00ccff", priority = 4 },
    OFFSPEC = { id = "offspec", text = "Offspec", color = "ff9900", priority = 3 },
    PVP = { id = "pvp", text = "PvP", color = "cc66ff", priority = 2 },
}

-- Ordered list for dropdown menu
Voting.ResponseOrder = { "BIS", "GREATER", "MINOR", "OFFSPEC", "PVP" }

-- Local state
local activeVotes = {}      -- Currently active votes (keyed by voteId)
local voteTimers = {}       -- Active timers for vote timeouts (deprecated - kept for compatibility)
local confirmedPlayers = {} -- Players who have confirmed their votes (keyed by player name)
local currentMasterLooter = nil
local receivedCouncilList = nil  -- Council list received from ML (for non-ML raiders)

function Voting:OnEnable()
    -- Register callbacks
    HooligansLoot.RegisterCallback(self, "SESSION_STARTED", "OnSessionStarted")
    HooligansLoot.RegisterCallback(self, "SESSION_ENDED", "OnSessionEnded")

    -- Restore votes from session after reload
    self:RestoreVotesFromSession()

    HooligansLoot:Debug("Voting module enabled")
end

-- Restore votes from session.votes into activeVotes (after /reload)
-- Only restores votes that are still active (for display in MainFrame)
function Voting:RestoreVotesFromSession()
    local SessionManager = HooligansLoot:GetModule("SessionManager", true)
    if not SessionManager then return end

    local session = SessionManager:GetCurrentSession()
    if not session or not session.votes then return end

    local restored = 0
    local now = time()

    for voteId, vote in pairs(session.votes) do
        -- Only restore if not already in activeVotes
        -- Only restore votes from the CURRENT session (strict check)
        if not activeVotes[voteId] and vote.sessionId and vote.sessionId == session.id then
            -- Check if the vote timer has expired and update status accordingly
            if vote.status == self.Status.COLLECTING and vote.endsAt and vote.endsAt <= now then
                vote.status = self.Status.VOTING
                HooligansLoot:Debug("Vote " .. voteId .. " timer expired during reload, updating status to VOTING")
            end

            activeVotes[voteId] = vote
            restored = restored + 1
        end
    end

    if restored > 0 then
        HooligansLoot:Debug("Restored " .. restored .. " votes from session " .. tostring(session.id))
    end
end

function Voting:OnDisable()
    -- Cancel all active timers
    for voteId, timer in pairs(voteTimers) do
        if timer then
            HooligansLoot:CancelTimer(timer)
        end
    end
    voteTimers = {}
    activeVotes = {}
end

function Voting:OnSessionStarted(event, session)
    HooligansLoot:Debug("Voting:OnSessionStarted - session=" .. tostring(session and session.id))

    -- Clear old votes when a new session starts
    self:ClearAllVotes()

    -- Hide LootFrame if it's showing (old session's votes)
    local LootFrame = HooligansLoot:GetModule("LootFrame", true)
    if LootFrame then
        LootFrame:Hide()
    end

    -- Initialize votes storage in session if not exists
    if session and not session.votes then
        session.votes = {}
    end

    HooligansLoot:Debug("Voting:OnSessionStarted complete - activeVotes cleared")
end

-- Clear all votes (for new session or cleanup)
function Voting:ClearAllVotes()
    -- Cancel all active timers
    for voteId, timer in pairs(voteTimers) do
        if timer then
            HooligansLoot:CancelTimer(timer)
        end
    end
    voteTimers = {}
    activeVotes = {}
    HooligansLoot:Debug("Cleared all votes")
end

-- Clear votes that don't belong to the current session
function Voting:ClearOldSessionVotes()
    local SessionManager = HooligansLoot:GetModule("SessionManager", true)
    if not SessionManager then return end

    local session = SessionManager:GetCurrentSession()
    local currentSessionId = session and session.id

    -- Only ML should clear votes - raiders keep all votes they receive
    -- Check if we're the ML by seeing if we created any of the active votes
    local isMasterLooter = false
    local playerName = UnitName("player")
    for _, vote in pairs(activeVotes) do
        if vote.masterLooter == playerName then
            isMasterLooter = true
            break
        end
    end

    if not isMasterLooter then
        print("|cff00ff00[HL DEBUG]|r Not ML - keeping all received votes")
        return
    end

    -- No current session, nothing to compare against
    if not currentSessionId then
        HooligansLoot:Debug("No current session - keeping all votes")
        return
    end

    local toRemove = {}
    for voteId, vote in pairs(activeVotes) do
        -- Remove votes without sessionId or from different sessions
        local shouldRemove = false
        if not vote.sessionId then
            shouldRemove = true
            HooligansLoot:Debug("Vote " .. voteId .. " has no sessionId, removing")
        elseif vote.sessionId ~= currentSessionId then
            shouldRemove = true
            HooligansLoot:Debug("Vote " .. voteId .. " sessionId=" .. tostring(vote.sessionId) .. " != current " .. tostring(currentSessionId) .. ", removing")
        end

        if shouldRemove then
            table.insert(toRemove, voteId)
        end
    end

    for _, voteId in ipairs(toRemove) do
        if voteTimers[voteId] then
            HooligansLoot:CancelTimer(voteTimers[voteId])
            voteTimers[voteId] = nil
        end
        activeVotes[voteId] = nil
    end

    if #toRemove > 0 then
        HooligansLoot:Debug("Removed " .. #toRemove .. " old session votes")
    end
end

-- Clean up finished votes (DECIDED or CANCELLED)
function Voting:CleanupFinishedVotes()
    local toRemove = {}
    for voteId, vote in pairs(activeVotes) do
        if vote.status == self.Status.DECIDED or vote.status == self.Status.CANCELLED then
            table.insert(toRemove, voteId)
        end
    end

    for _, voteId in ipairs(toRemove) do
        if voteTimers[voteId] then
            HooligansLoot:CancelTimer(voteTimers[voteId])
            voteTimers[voteId] = nil
        end
        activeVotes[voteId] = nil
    end

    if #toRemove > 0 then
        HooligansLoot:Debug("Cleaned up " .. #toRemove .. " finished votes")
    end
end

function Voting:OnSessionEnded(event, session)
    -- Cancel any active votes for this session
    for voteId, vote in pairs(activeVotes) do
        if vote.sessionId == session.id then
            self:CancelVote(voteId)
        end
    end
end

-- Check if player is Master Looter or has appropriate permissions
function Voting:IsMasterLooter()
    -- Allow solo testing
    if not IsInGroup() then
        return true
    end
    return Utils.IsMasterLooter() or (IsInRaid() and (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player"))) or UnitIsGroupLeader("player")
end

-- Check if player is on the council
function Voting:IsCouncilMember(playerName)
    playerName = playerName or UnitName("player")
    playerName = Utils.StripRealm(playerName)

    -- Solo mode - player is always council
    if not IsInGroup() then
        return playerName == UnitName("player")
    end

    -- If we're the ML, use our local settings
    if self:IsMasterLooter() then
        local settings = HooligansLoot.db.profile.settings

        if settings.councilMode == "auto" then
            -- Auto mode: ML, raid leader, and assistants are council
            if IsInRaid() then
                for i = 1, GetNumGroupMembers() do
                    local name, rank = GetRaidRosterInfo(i)
                    if name then
                        local cleanName = Utils.StripRealm(name)
                        if cleanName == playerName and rank > 0 then
                            return true
                        end
                    end
                end
            end
            -- Also check if player is the group leader
            if UnitIsGroupLeader("player") and playerName == UnitName("player") then
                return true
            end
        else
            -- Manual mode: check council list
            for _, councilName in ipairs(settings.councilList) do
                if Utils.StripRealm(councilName) == playerName then
                    return true
                end
            end
        end
    else
        -- Non-ML: check receivedCouncilList from the ML
        if receivedCouncilList then
            -- ML is always council
            if receivedCouncilList.masterLooter and Utils.StripRealm(receivedCouncilList.masterLooter) == playerName then
                return true
            end
            -- Check the council list
            if receivedCouncilList.list then
                for _, councilName in ipairs(receivedCouncilList.list) do
                    if Utils.StripRealm(councilName) == playerName then
                        return true
                    end
                end
            end
        end
    end

    return false
end

-- Broadcast council list to group (called by ML when starting a vote)
function Voting:BroadcastCouncil()
    -- Only ML should broadcast
    if not self:IsMasterLooter() then return end

    local settings = HooligansLoot.db.profile.settings
    local councilData = {
        mode = settings.councilMode,
        list = {},
        masterLooter = UnitName("player"),
    }

    if settings.councilMode == "auto" then
        -- Auto mode: build list from raid assistants
        if IsInRaid() then
            for i = 1, GetNumGroupMembers() do
                local name, rank = GetRaidRosterInfo(i)
                if name and rank > 0 then
                    table.insert(councilData.list, Utils.StripRealm(name))
                end
            end
        end
        -- Include party leader
        if UnitIsGroupLeader("player") then
            local leaderName = UnitName("player")
            local found = false
            for _, n in ipairs(councilData.list) do
                if n == leaderName then found = true; break end
            end
            if not found then
                table.insert(councilData.list, leaderName)
            end
        end
    else
        -- Manual mode: use the saved council list
        for _, name in ipairs(settings.councilList) do
            table.insert(councilData.list, Utils.StripRealm(name))
        end
    end

    -- Broadcast to group
    local Comm = HooligansLoot:GetModule("Comm", true)
    if Comm then
        Comm:BroadcastMessage(Comm.MessageTypes.COUNCIL_SYNC, councilData)
        HooligansLoot:Debug("Broadcast council list: " .. #councilData.list .. " members, mode=" .. councilData.mode)
    end
end

-- Get council data for including in messages
function Voting:GetCouncilData()
    local settings = HooligansLoot.db.profile.settings
    local councilData = {
        mode = settings.councilMode,
        list = {},
        masterLooter = UnitName("player"),
    }

    if settings.councilMode == "auto" then
        -- Auto mode: build list from raid assistants
        if IsInRaid() then
            for i = 1, GetNumGroupMembers() do
                local name, rank = GetRaidRosterInfo(i)
                if name and rank > 0 then
                    table.insert(councilData.list, Utils.StripRealm(name))
                end
            end
        end
        -- Include party leader
        if UnitIsGroupLeader("player") then
            local leaderName = UnitName("player")
            local found = false
            for _, n in ipairs(councilData.list) do
                if n == leaderName then found = true; break end
            end
            if not found then
                table.insert(councilData.list, leaderName)
            end
        end
    else
        -- Manual mode: use the saved council list
        for _, name in ipairs(settings.councilList) do
            table.insert(councilData.list, Utils.StripRealm(name))
        end
    end

    return councilData
end

-- Handle council sync message from ML
function Voting:OnCouncilSync(data, sender)
    if not data then return end

    -- Store the received council list
    receivedCouncilList = {
        mode = data.mode,
        list = data.list or {},
        masterLooter = data.masterLooter or sender,
    }

    HooligansLoot:Debug("Received council list from " .. sender .. ": " .. #receivedCouncilList.list .. " members")

    -- Fire callback so UI can update if needed
    HooligansLoot.callbacks:Fire("COUNCIL_SYNC_RECEIVED", receivedCouncilList)
end

-- Get the received council list (for non-ML raiders)
function Voting:GetReceivedCouncilList()
    return receivedCouncilList
end

-- Get all council members
function Voting:GetCouncilMembers()
    local council = {}
    local settings = HooligansLoot.db.profile.settings

    if settings.councilMode == "auto" then
        if IsInRaid() then
            for i = 1, GetNumGroupMembers() do
                local name, rank, _, _, _, classFile = GetRaidRosterInfo(i)
                if name and rank > 0 then
                    table.insert(council, {
                        name = Utils.StripRealm(name),
                        class = classFile,
                        rank = rank,
                    })
                end
            end
        else
            -- In party, just the leader
            local playerName = UnitName("player")
            local _, playerClass = UnitClass("player")
            if UnitIsGroupLeader("player") then
                table.insert(council, {
                    name = playerName,
                    class = playerClass,
                    rank = 2,
                })
            end
        end
    else
        -- Manual mode
        for _, councilName in ipairs(settings.councilList) do
            local classFile = Utils.GetPlayerClass(councilName)
            table.insert(council, {
                name = councilName,
                class = classFile or "UNKNOWN",
                rank = 1,
            })
        end
    end

    return council
end

-- Generate a unique vote ID
function Voting:GenerateVoteId(itemGUID)
    return string.format("vote_%s_%d", itemGUID, time())
end

-- Start a vote for items
function Voting:StartVote(items, timeout)
    -- Wrap entire function in error handling
    local success, result = pcall(function()
        HooligansLoot:Debug("Voting:StartVote called with " .. tostring(#items) .. " items")

        -- Clean up any old session votes and finished votes first
        self:ClearOldSessionVotes()
        self:CleanupFinishedVotes()

        -- Clear vote confirmations for new vote
        self:ClearConfirmations()

        -- Simplified permission check - allow anyone to start in solo, or leader/ML in group
        local canStart = true
        if IsInGroup() then
            canStart = UnitIsGroupLeader("player") or UnitIsGroupAssistant("player") or Utils.IsMasterLooter()
        end

        HooligansLoot:Debug("Permission check: " .. tostring(canStart))

        if not canStart then
            HooligansLoot:Print("Only the Raid Leader can start votes.")
            return false
        end

        local SessionManager = HooligansLoot:GetModule("SessionManager")
        if not SessionManager then
            HooligansLoot:Print("Error: SessionManager not loaded")
            return false
        end

        local session = SessionManager:GetCurrentSession()
        if not session then
            HooligansLoot:Print("No active session. Start a session first.")
            return false
        end

        HooligansLoot:Debug("Session found: " .. tostring(session.id))

        timeout = timeout or HooligansLoot.db.profile.settings.voteTimeout

        -- Create votes for each item
        local votes = {}
        HooligansLoot:Debug("StartVote: Creating " .. #items .. " votes for session " .. tostring(session.id))

        for _, item in ipairs(items) do
            local voteId = self:GenerateVoteId(item.guid)
            HooligansLoot:Debug("Creating vote for item: " .. tostring(item.name) .. ", guid: " .. tostring(item.guid) .. ", sessionId: " .. tostring(session.id))
            local vote = {
                voteId = voteId,
                itemGUID = item.guid,
                item = {
                    id = item.id,
                    link = item.link,
                    name = item.name,
                    icon = item.icon,
                    quality = item.quality,
                },
                sessionId = session.id,
                status = self.Status.COLLECTING,
                startedAt = time(),
                endsAt = time() + timeout,
                timeout = timeout,
                responses = {},
                councilVotes = {},
                winner = nil,
                masterLooter = UnitName("player"),
            }

            activeVotes[voteId] = vote
            votes[voteId] = vote

            -- Store in session
            if not session.votes then
                session.votes = {}
            end
            session.votes[voteId] = vote

            -- NOTE: Vote timeout timer removed - voting is now open until ML manually ends collection
            -- Players confirm when done via "Confirm All" button, shown as checkmarks in player panel

            HooligansLoot:Debug("Created vote: " .. voteId)
        end

        -- Capture ML's own gear for the votes
        local GearComparison = HooligansLoot:GetModule("GearComparison", true)
        if GearComparison then
            local mlName = UnitName("player")
            local gearData = {}
            local processedSlots = {}

            for _, item in ipairs(items) do
                local slots = GearComparison:GetSlotsForItem(item.link)
                if slots then
                    for _, slotId in ipairs(slots) do
                        if not processedSlots[slotId] then
                            processedSlots[slotId] = true
                            local itemLink = GetInventoryItemLink("player", slotId)
                            if itemLink then
                                local ilvl = GearComparison:GetItemLevel(itemLink)
                                gearData[slotId] = {
                                    l = itemLink,
                                    i = ilvl,
                                }
                            end
                        end
                    end
                end
            end

            -- Store ML's gear in all votes
            if next(gearData) then
                for voteId, vote in pairs(votes) do
                    if not vote.playerGear then
                        vote.playerGear = {}
                    end
                    vote.playerGear[mlName] = gearData
                end
                HooligansLoot:Debug("Stored ML's own gear for " .. #items .. " votes")
            end
        end

        -- Build MINIMAL vote data for broadcast (reduces message size for faster delivery)
        -- Send only item link - raiders reconstruct full item data locally
        local voteData = {}
        for voteId, vote in pairs(votes) do
            table.insert(voteData, {
                v = vote.voteId,           -- shortened key names
                g = vote.itemGUID,         -- MUST include GUID for response matching
                l = vote.item.link,        -- item link only (contains all info)
                t = vote.timeout,
                e = vote.endsAt,
            })
        end

        HooligansLoot:Debug("Created " .. #voteData .. " vote entries (optimized)")

        -- In solo mode, skip comm broadcast
        if IsInGroup() then
            -- Build minimal council data - just the list
            local councilData = self:GetCouncilData()

            local Comm = HooligansLoot:GetModule("Comm", true)
            if Comm then
                HooligansLoot:Debug("Broadcasting vote start to group (optimized)")
                -- Minimal message for faster delivery
                Comm:BroadcastMessage(Comm.MessageTypes.VOTE_START, {
                    votes = voteData,
                    s = session.id,                    -- shortened key
                    m = UnitName("player"),            -- shortened key
                    c = councilData.list,              -- just the list, not full object
                })
            end
        else
            HooligansLoot:Debug("Solo mode - skipping comm broadcast")
        end

        HooligansLoot:Print(string.format("Started vote for %d item(s). Watch player panel for confirmations.", #items))
        HooligansLoot.callbacks:Fire("VOTE_STARTED", votes)

        -- Show LootFrame for raider responses
        local LootFrame = HooligansLoot:GetModule("LootFrame", true)
        if LootFrame then
            HooligansLoot:Debug("Showing LootFrame")
            LootFrame:Show()
        else
            HooligansLoot:Debug("LootFrame module not found!")
        end

        return true
    end)

    if not success then
        HooligansLoot:Print("Error starting vote: " .. tostring(result))
        return false
    end

    return result
end

-- Submit a response as a raider
function Voting:SubmitResponse(voteId, responseType, note)
    local vote = activeVotes[voteId]
    if not vote then
        HooligansLoot:Debug("Vote not found: " .. voteId)
        return false
    end

    if vote.status ~= self.Status.COLLECTING then
        HooligansLoot:Print("Voting has closed for this item.")
        return false
    end

    local playerName = UnitName("player")
    local _, playerClass = UnitClass("player")

    local response = {
        response = responseType,
        note = note or "",
        class = playerClass,
        timestamp = time(),
    }

    -- Always record response locally for immediate UI feedback
    vote.responses[playerName] = response
    HooligansLoot:Debug(string.format("Recorded response locally for vote %s, itemGUID=%s, response=%s",
        voteId, tostring(vote.itemGUID), tostring(responseType)))

    -- If we're the ML, broadcast the update to the group
    if vote.masterLooter == playerName then
        self:BroadcastVoteUpdate(voteId)
    else
        -- Send response to ML so it gets shared with council
        local Comm = HooligansLoot:GetModule("Comm")
        Comm:SendMessage(Comm.MessageTypes.VOTE_RESPONSE, {
            voteId = voteId,
            response = responseType,
            note = note or "",
            class = playerClass,
        }, vote.masterLooter)
    end

    HooligansLoot:Debug("Submitted response: " .. responseType .. " for vote " .. voteId)
    HooligansLoot.callbacks:Fire("VOTE_RESPONSE_SUBMITTED", voteId, responseType)

    -- Force all UI refresh
    local SessionManager = HooligansLoot:GetModule("SessionManager")
    SessionManager:RefreshAllUI()

    return true
end

-- Mark a player as having confirmed their votes
function Voting:ConfirmVotes(playerName)
    playerName = playerName or UnitName("player")
    confirmedPlayers[playerName] = time()

    HooligansLoot:Debug("Player confirmed votes: " .. playerName)
    HooligansLoot.callbacks:Fire("VOTE_CONFIRMED", playerName)

    -- Broadcast confirmation to everyone so all players see the checkmark
    if IsInGroup() then
        local Comm = HooligansLoot:GetModule("Comm")
        local _, playerClass = UnitClass("player")
        Comm:BroadcastMessage(Comm.MessageTypes.VOTE_CONFIRMED, {
            player = playerName,
            class = playerClass,
        })
    end

    -- Refresh UI
    local SessionManager = HooligansLoot:GetModule("SessionManager")
    SessionManager:RefreshAllUI()
end

-- Receive vote confirmation from another player
function Voting:ReceiveVoteConfirmation(playerName, playerClass)
    confirmedPlayers[playerName] = time()
    HooligansLoot:Debug("Received vote confirmation from: " .. playerName)
    HooligansLoot.callbacks:Fire("VOTE_CONFIRMED", playerName)

    -- Refresh UI
    local SessionManager = HooligansLoot:GetModule("SessionManager")
    SessionManager:RefreshAllUI()
end

-- Check if a player has confirmed their votes
function Voting:HasPlayerConfirmed(playerName)
    return confirmedPlayers[playerName] ~= nil
end

-- Get all confirmed players
function Voting:GetConfirmedPlayers()
    return confirmedPlayers
end

-- Clear confirmations (when new vote starts)
function Voting:ClearConfirmations()
    wipe(confirmedPlayers)
    HooligansLoot:Debug("Cleared all vote confirmations")
end

-- Cast a council vote
function Voting:CastVote(voteId, targetPlayer)
    if not self:IsCouncilMember() then
        HooligansLoot:Print("Only council members can cast votes.")
        return false
    end

    local vote = activeVotes[voteId]
    if not vote then
        HooligansLoot:Debug("Vote not found: " .. voteId)
        return false
    end

    if vote.status ~= self.Status.VOTING and vote.status ~= self.Status.COLLECTING then
        HooligansLoot:Print("Cannot vote at this time.")
        return false
    end

    local playerName = UnitName("player")

    -- Check self-vote restriction
    if not HooligansLoot.db.profile.settings.allowSelfVote and targetPlayer == playerName then
        HooligansLoot:Print("Self-voting is not allowed.")
        return false
    end

    -- If we're the ML, record locally
    if vote.masterLooter == playerName then
        vote.councilVotes[playerName] = {
            votedFor = targetPlayer,
            timestamp = time(),
        }
        self:BroadcastVoteUpdate(voteId)
    else
        -- Send vote to ML
        local Comm = HooligansLoot:GetModule("Comm")
        Comm:SendMessage(Comm.MessageTypes.VOTE_CAST, {
            voteId = voteId,
            votedFor = targetPlayer,
        }, vote.masterLooter)
    end

    HooligansLoot:Debug("Cast vote for " .. targetPlayer .. " on vote " .. voteId)
    HooligansLoot.callbacks:Fire("VOTE_CAST_SUBMITTED", voteId, targetPlayer)

    return true
end

-- End collection phase and move to council voting
function Voting:EndCollection(voteId)
    local vote = activeVotes[voteId]
    if not vote then return false end

    if vote.status ~= self.Status.COLLECTING then
        return false
    end

    vote.status = self.Status.VOTING

    -- Cancel the timeout timer
    if voteTimers[voteId] then
        HooligansLoot:CancelTimer(voteTimers[voteId])
        voteTimers[voteId] = nil
    end

    -- Save to session
    local SessionManager = HooligansLoot:GetModule("SessionManager")
    local session = SessionManager:GetCurrentSession()
    if session then
        if not session.votes then session.votes = {} end
        session.votes[voteId] = vote
    end

    self:BroadcastVoteUpdate(voteId)
    HooligansLoot.callbacks:Fire("VOTE_COLLECTION_ENDED", voteId)
    HooligansLoot.callbacks:Fire("VOTE_UPDATED", voteId)  -- For immediate MainFrame refresh

    return true
end

-- Award item to winner
function Voting:AwardWinner(voteId, winnerName)
    local vote = activeVotes[voteId]
    if not vote then return false end

    vote.winner = winnerName
    vote.status = self.Status.DECIDED
    vote.decidedAt = time()

    -- Cancel any timer
    if voteTimers[voteId] then
        HooligansLoot:CancelTimer(voteTimers[voteId])
        voteTimers[voteId] = nil
    end

    -- Set award in session manager
    local SessionManager = HooligansLoot:GetModule("SessionManager")
    local winnerClass = vote.responses[winnerName] and vote.responses[winnerName].class or Utils.GetPlayerClass(winnerName)
    SessionManager:SetAward(vote.sessionId, vote.itemGUID, winnerName, winnerClass)

    -- Broadcast end
    local Comm = HooligansLoot:GetModule("Comm")
    Comm:BroadcastMessage(Comm.MessageTypes.VOTE_END, {
        voteId = voteId,
        winner = winnerName,
        item = vote.item,
    })

    -- Announce in raid if enabled
    if HooligansLoot.db.profile.settings.announceResults then
        local item = vote.item
        local coloredWinner = Utils.GetColoredPlayerName(winnerName, winnerClass)
        SendChatMessage(string.format("[HooligansLoot] %s awarded to %s", item.link or item.name, winnerName), IsInRaid() and "RAID" or "PARTY")
    end

    HooligansLoot:Print(string.format("%s awarded to %s", vote.item.link or vote.item.name, winnerName))
    HooligansLoot.callbacks:Fire("VOTE_ENDED", voteId, winnerName)

    return true
end

-- Cancel a vote
function Voting:CancelVote(voteId)
    local vote = activeVotes[voteId]
    if not vote then return false end

    vote.status = self.Status.CANCELLED

    -- Cancel timer
    if voteTimers[voteId] then
        HooligansLoot:CancelTimer(voteTimers[voteId])
        voteTimers[voteId] = nil
    end

    -- Broadcast cancellation
    local Comm = HooligansLoot:GetModule("Comm")
    Comm:BroadcastMessage(Comm.MessageTypes.VOTE_CANCEL, {
        voteId = voteId,
    })

    HooligansLoot:Print("Vote cancelled for " .. (vote.item.link or vote.item.name))
    HooligansLoot.callbacks:Fire("VOTE_CANCELLED", voteId)

    return true
end

-- Broadcast vote update
function Voting:BroadcastVoteUpdate(voteId)
    local vote = activeVotes[voteId]
    if not vote then return end

    -- Also update session.votes to keep them in sync
    local SessionManager = HooligansLoot:GetModule("SessionManager")
    local session = SessionManager:GetCurrentSession()
    if session then
        if not session.votes then session.votes = {} end
        session.votes[voteId] = vote
    end

    -- Keep message small - only send essential vote data
    local Comm = HooligansLoot:GetModule("Comm")
    Comm:BroadcastMessage(Comm.MessageTypes.VOTE_UPDATE, {
        voteId = voteId,
        status = vote.status,
        responses = vote.responses,
        endsAt = vote.endsAt,
        playerGear = vote.playerGear,  -- Include gear data for council display
    })

    -- Fire callback to update UI (MainFrame listens for this)
    HooligansLoot:Debug("Firing VOTE_UPDATED callback for " .. tostring(voteId))
    HooligansLoot.callbacks:Fire("VOTE_UPDATED", voteId)

    -- Refresh response displays only (not LootFrame) to avoid closing dropdowns
    SessionManager:RefreshResponseDisplays()
end

-- Handle vote timeout
function Voting:OnVoteTimeout(voteId)
    local vote = activeVotes[voteId]
    if not vote then return end

    if vote.status == self.Status.COLLECTING then
        -- Move to voting phase
        self:EndCollection(voteId)

        -- Save to session
        local SessionManager = HooligansLoot:GetModule("SessionManager")
        local session = SessionManager:GetCurrentSession()
        if session then
            if not session.votes then session.votes = {} end
            session.votes[voteId] = vote
        end

        HooligansLoot:Print(string.format("Response time ended for %s.", vote.item.link or vote.item.name))

        -- Fire callback to refresh MainFrame
        HooligansLoot.callbacks:Fire("VOTE_UPDATED", voteId)
    end
end

-- Get active votes
function Voting:GetActiveVotes()
    return activeVotes
end

-- Get vote by ID
function Voting:GetVote(voteId)
    return activeVotes[voteId]
end

-- Get votes for current session
function Voting:GetSessionVotes(sessionId)
    local votes = {}
    for voteId, vote in pairs(activeVotes) do
        if vote.sessionId == sessionId then
            votes[voteId] = vote
        end
    end
    return votes
end

-- Count votes for each candidate
function Voting:CountVotes(voteId)
    local vote = activeVotes[voteId]
    if not vote then return {} end

    local counts = {}
    for _, councilVote in pairs(vote.councilVotes) do
        local target = councilVote.votedFor
        counts[target] = (counts[target] or 0) + 1
    end

    return counts
end

-- Get leading candidate
function Voting:GetLeader(voteId)
    local counts = self:CountVotes(voteId)
    local leader = nil
    local maxVotes = 0

    for player, count in pairs(counts) do
        if count > maxVotes then
            maxVotes = count
            leader = player
        end
    end

    return leader, maxVotes
end

-- === Message Handlers (called from Comm module) ===

function Voting:OnVoteStart(data, sender)
    if not data or not data.votes then return end

    -- Support both old format (sessionId) and new optimized format (s)
    local sessionId = data.sessionId or data.s
    local masterLooter = data.masterLooter or data.m or sender

    HooligansLoot:Debug("OnVoteStart from " .. sender .. ", sessionId=" .. tostring(sessionId) .. ", votes=" .. #data.votes)

    -- Process council data - support both old format (council object) and new format (c = list only)
    if data.council then
        receivedCouncilList = {
            mode = data.council.mode,
            list = data.council.list or {},
            masterLooter = data.council.masterLooter or masterLooter,
        }
        HooligansLoot:Debug("Received council with vote: " .. #receivedCouncilList.list .. " members")
    elseif data.c then
        -- New optimized format: c is just the list
        receivedCouncilList = {
            mode = "auto",
            list = data.c,
            masterLooter = masterLooter,
        }
        HooligansLoot:Debug("Received council list: " .. #receivedCouncilList.list .. " members")
    end

    local playerName = UnitName("player")

    for _, voteData in ipairs(data.votes) do
        -- Support both old format and new optimized format
        local voteId = voteData.voteId or voteData.v
        local itemLink = voteData.l or (voteData.item and voteData.item.link)
        local timeout = voteData.timeout or voteData.t
        local endsAt = voteData.endsAt or voteData.e

        -- Skip if we already have this vote (we're the ML who created it)
        if activeVotes[voteId] then
            HooligansLoot:Debug("Vote already exists: " .. voteId)
        else
            -- Reconstruct item data from link (new format) or use provided item (old format)
            local itemData
            if voteData.item then
                -- Old format - use as-is
                itemData = voteData.item
            else
                -- New optimized format - reconstruct from link
                local itemName, _, itemQuality, _, _, _, _, _, _, itemIcon = GetItemInfo(itemLink)
                local itemId = tonumber(itemLink:match("item:(%d+)"))

                -- If item isn't cached, extract name from link
                if not itemName then
                    itemName = itemLink:match("%[(.-)%]") or "Unknown Item"
                end

                itemData = {
                    id = itemId,
                    link = itemLink,
                    name = itemName or "Unknown Item",
                    icon = itemIcon or "Interface\\Icons\\INV_Misc_QuestionMark",
                    quality = itemQuality or 4,
                }
            end

            local vote = {
                voteId = voteId,
                itemGUID = voteData.g or voteData.itemGUID or ((itemData.id or 0) .. "_" .. voteId),
                item = itemData,
                sessionId = sessionId,
                status = self.Status.COLLECTING,
                startedAt = time(),
                endsAt = endsAt,
                timeout = timeout,
                responses = {},
                councilVotes = {},
                winner = nil,
                masterLooter = masterLooter,
            }

            activeVotes[voteId] = vote
            HooligansLoot:Debug("Created vote: " .. voteId .. ", item=" .. tostring(itemData.name))
        end
    end

    -- Show loot frame for raiders to respond
    local LootFrame = HooligansLoot:GetModule("LootFrame", true)
    if LootFrame then
        LootFrame:Show()
    end

    HooligansLoot.callbacks:Fire("VOTE_RECEIVED", data.votes)

    -- Send gear sync to ML for equipped items in vote slots
    local GearComparison = HooligansLoot:GetModule("GearComparison", true)
    if GearComparison and masterLooter ~= UnitName("player") then
        -- Collect vote IDs and items for gear sync
        local voteIdList = {}
        local itemsList = {}
        for _, voteData in ipairs(data.votes) do
            local voteId = voteData.voteId or voteData.v
            table.insert(voteIdList, voteId)
            table.insert(itemsList, {
                link = voteData.l or (voteData.item and voteData.item.link),
            })
        end
        -- Send gear sync after a short delay to ensure items are cached
        C_Timer.After(0.5, function()
            GearComparison:SendGearSync(voteIdList, masterLooter, itemsList)
        end)
    end

    -- Force all UI refresh
    local SessionManager = HooligansLoot:GetModule("SessionManager")
    SessionManager:RefreshAllUI()
end

function Voting:OnVoteResponse(data, sender)
    if not data or not data.voteId then return end

    local vote = activeVotes[data.voteId]
    if not vote then return end

    -- Only ML should process responses
    if vote.masterLooter ~= UnitName("player") then return end

    vote.responses[sender] = {
        response = data.response,
        note = data.note or "",
        class = data.class,
        timestamp = time(),
    }

    HooligansLoot:Debug("Response from " .. sender .. ": " .. data.response)

    -- IMMEDIATE broadcast to all raiders - no throttle for responses
    self:BroadcastVoteUpdate(data.voteId)

    HooligansLoot.callbacks:Fire("VOTE_RESPONSE_RECEIVED", data.voteId, sender, data.response)

    -- IMMEDIATE UI refresh for ML
    local MainFrame = HooligansLoot:GetModule("MainFrame", true)
    if MainFrame and MainFrame:IsShown() then
        MainFrame:Refresh()
    end
end

function Voting:OnVoteCast(data, sender)
    if not data or not data.voteId then return end

    local vote = activeVotes[data.voteId]
    if not vote then return end

    -- Only ML should process votes
    if vote.masterLooter ~= UnitName("player") then return end

    -- Verify sender is council member
    if not self:IsCouncilMember(sender) then
        HooligansLoot:Debug("Non-council member tried to vote: " .. sender)
        return
    end

    vote.councilVotes[sender] = {
        votedFor = data.votedFor,
        timestamp = time(),
    }

    HooligansLoot:Debug("Council vote from " .. sender .. " for " .. data.votedFor)
    self:BroadcastVoteUpdate(data.voteId)
    HooligansLoot.callbacks:Fire("VOTE_CAST_RECEIVED", data.voteId, sender, data.votedFor)
end

function Voting:OnVoteUpdate(data, sender)
    if not data or not data.voteId then return end

    local vote = activeVotes[data.voteId]
    if not vote then
        -- Skip if we don't have this vote (we'll get full data from VOTE_START)
        HooligansLoot:Debug("Vote update for unknown vote: " .. data.voteId)
        return
    end

    -- Update only the changed data
    if data.status then vote.status = data.status end
    if data.endsAt then vote.endsAt = data.endsAt end
    if data.playerGear then vote.playerGear = data.playerGear end  -- Sync gear data

    -- Merge responses - preserve our own local response and add others from ML
    if data.responses then
        local playerName = UnitName("player")
        local myLocalResponse = vote.responses and vote.responses[playerName]

        -- Update with ML's data
        vote.responses = data.responses

        -- Preserve our local response if we had one and ML doesn't have it yet
        if myLocalResponse and not vote.responses[playerName] then
            vote.responses[playerName] = myLocalResponse
            HooligansLoot:Debug("Preserved local response during VOTE_UPDATE merge")
        end
    end

    -- Update synced session votes if we have one
    local SessionManager = HooligansLoot:GetModule("SessionManager")
    local syncedSession = SessionManager:GetSyncedSession()
    if syncedSession then
        if not syncedSession.votes then syncedSession.votes = {} end
        syncedSession.votes[data.voteId] = vote
    end

    HooligansLoot.callbacks:Fire("VOTE_UPDATED", data.voteId)

    -- IMMEDIATE UI refresh - don't wait for callbacks
    -- Directly refresh MainFrame for instant response visibility
    local MainFrame = HooligansLoot:GetModule("MainFrame", true)
    if MainFrame and MainFrame:IsShown() then
        MainFrame:Refresh()
    end
end

function Voting:OnVoteEnd(data, sender)
    if not data or not data.voteId then return end

    local vote = activeVotes[data.voteId]
    if vote then
        vote.status = self.Status.DECIDED
        vote.winner = data.winner
    end

    -- Refresh LootFrame for this vote
    local LootFrame = HooligansLoot:GetModule("LootFrame", true)
    if LootFrame then
        LootFrame:RefreshForVote(data.voteId)
    end

    HooligansLoot:Print(string.format("%s awarded to %s", data.item.link or data.item.name, data.winner))
    HooligansLoot.callbacks:Fire("VOTE_ENDED", data.voteId, data.winner)

    -- Force all UI refresh
    local SessionManager = HooligansLoot:GetModule("SessionManager")
    SessionManager:RefreshAllUI()
end

function Voting:OnVoteCancel(data, sender)
    if not data or not data.voteId then return end

    local vote = activeVotes[data.voteId]
    if vote then
        vote.status = self.Status.CANCELLED
    end

    HooligansLoot.callbacks:Fire("VOTE_CANCELLED", data.voteId)

    -- Force all UI refresh
    local SessionManager = HooligansLoot:GetModule("SessionManager")
    SessionManager:RefreshAllUI()
end

function Voting:OnSyncRequest(data, sender)
    -- ML sends current vote state to requesting player
    if not self:IsMasterLooter() then return end

    local Comm = HooligansLoot:GetModule("Comm")
    Comm:SendMessage(Comm.MessageTypes.SYNC_RESPONSE, {
        votes = activeVotes,
    }, sender)
end

function Voting:OnSyncResponse(data, sender)
    if not data or not data.votes then return end

    -- Merge received votes
    for voteId, vote in pairs(data.votes) do
        if not activeVotes[voteId] then
            activeVotes[voteId] = vote
        end
    end

    HooligansLoot.callbacks:Fire("VOTES_SYNCED")
end
