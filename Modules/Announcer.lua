-- Modules/Announcer.lua
-- Announces awards to chat

local ADDON_NAME, NS = ...
local HooligansLoot = NS.addon
local Utils = NS.Utils

local Announcer = HooligansLoot:NewModule("Announcer")

function Announcer:OnEnable()
    -- Register for award callbacks to auto-announce
    HooligansLoot.RegisterCallback(self, "AWARD_SET", "OnAwardSet")
end

-- Called when an award is set (item assigned to player)
-- Only raid leader can announce to raid
function Announcer:OnAwardSet(event, session, itemGUID, playerName)
    -- Only raid leader should announce
    if IsInRaid() and not UnitIsGroupLeader("player") then
        return
    end

    -- Find the item and award
    local item = nil
    for _, sessionItem in ipairs(session.items) do
        if sessionItem.guid == itemGUID then
            item = sessionItem
            break
        end
    end

    if not item then
        HooligansLoot:Debug("OnAwardSet: Could not find item " .. itemGUID)
        return
    end

    -- Get class from award data
    local award = session.awards[itemGUID]
    local playerClass = award and award.class or nil

    -- Always announce with raid warning format
    self:AnnounceAwardWithClass(item, playerName, playerClass, true)
end

-- Announce single award with class info and optional raid warning
function Announcer:AnnounceAwardWithClass(item, winner, playerClass, useRaidWarning)
    if not item or not winner then return end

    if useRaidWarning then
        self:AnnounceAwardRaidWarning(item, winner, playerClass)
    else
        self:AnnounceItem(item, winner)
    end
end

function Announcer:GetChannel()
    local channel = HooligansLoot.db.profile.settings.announceChannel

    -- Validate channel based on group status
    if channel == "RAID" or channel == "RAID_WARNING" then
        if not IsInRaid() then
            if IsInGroup() then
                return "PARTY"
            else
                return "SAY"
            end
        end
    elseif channel == "PARTY" then
        if not IsInGroup() then
            return "SAY"
        end
    end

    return channel
end

function Announcer:SendMessage(msg, channel)
    channel = channel or self:GetChannel()

    -- Limit channel to valid options
    local validChannels = {
        SAY = true,
        YELL = true,
        PARTY = true,
        RAID = true,
        RAID_WARNING = true,
        GUILD = true,
    }

    if not validChannels[channel] then
        channel = "SAY"
    end

    SendChatMessage(msg, channel)
end

function Announcer:AnnounceItem(item, winner, channel)
    if not item or not winner then return end

    local msg = string.format("%s -> %s", item.link or item.name, winner)
    self:SendMessage(msg, channel)
end

-- Send a raid warning when an item is awarded
-- Only raid leader can announce
function Announcer:AnnounceAwardRaidWarning(item, winner, playerClass)
    if not item or not winner then return end

    -- Only raid leader can announce to raid
    local inRaid = IsInRaid()
    if inRaid and not UnitIsGroupLeader("player") then
        return
    end

    local isAssist = UnitIsGroupAssistant("player") or UnitIsGroupLeader("player")

    -- Plain text for chat (no color codes in raid warning channel)
    local chatMsg = string.format("%s awarded to %s - Please trade!", item.link or item.name, winner)

    if inRaid and isAssist then
        -- Send as raid warning
        SendChatMessage(chatMsg, "RAID_WARNING")
    elseif inRaid then
        -- Send to raid chat
        SendChatMessage(chatMsg, "RAID")
    elseif IsInGroup() then
        -- Send to party
        SendChatMessage(chatMsg, "PARTY")
    else
        -- Print locally if solo (with class colors)
        local coloredName = Utils.GetColoredPlayerName(winner, playerClass)
        HooligansLoot:Print(string.format("%s awarded to %s", item.link or item.name, coloredName))
    end

    -- Show local raid warning frame with class-colored name
    local coloredName = Utils.GetColoredPlayerName(winner, playerClass)
    local localMsg = string.format("%s -> %s", item.link or item.name, coloredName)
    RaidNotice_AddMessage(RaidWarningFrame, localMsg, ChatTypeInfo["RAID_WARNING"])
end

-- Announce single award with optional raid warning
function Announcer:AnnounceAward(item, winner, useRaidWarning)
    if not item or not winner then return end

    if useRaidWarning then
        self:AnnounceAwardRaidWarning(item, winner)
    else
        self:AnnounceItem(item, winner)
    end
end

function Announcer:AnnounceAwards(sessionId)
    -- Only raid leader can announce to raid
    if IsInRaid() and not UnitIsGroupLeader("player") then
        HooligansLoot:Print("Only the Raid Leader can announce to raid.")
        return 0
    end

    local SessionManager = HooligansLoot:GetModule("SessionManager")
    local session = sessionId and SessionManager:GetSession(sessionId) or SessionManager:GetCurrentSession()

    if not session then
        HooligansLoot:Print("No session to announce.")
        return 0
    end

    -- Get all awards (pending and completed)
    local awards = session.awards
    if Utils.TableSize(awards) == 0 then
        HooligansLoot:Print("No awards to announce.")
        return 0
    end

    local channel = self:GetChannel()
    local announced = 0

    -- Header
    self:SendMessage("Awards from " .. session.name .. ":", channel)

    -- Collect and sort awards
    local awardList = {}
    for itemGUID, award in pairs(awards) do
        local item = SessionManager:GetItemByGUID(session.id, itemGUID)
        if item then
            table.insert(awardList, {
                item = item,
                winner = award.winner,
                awarded = award.awarded,
            })
        end
    end

    -- Sort by item name for consistent output
    table.sort(awardList, function(a, b)
        return (a.item.name or "") < (b.item.name or "")
    end)

    -- Announce each award
    for _, data in ipairs(awardList) do
        local status = ""
        if data.awarded then
            status = " [Traded]"
        end

        local msg = string.format("%s -> %s%s",
            data.item.link or data.item.name,
            data.winner,
            status
        )
        self:SendMessage(msg, channel)
        announced = announced + 1
    end

    HooligansLoot:Print(string.format("Announced %d awards to %s", announced, channel))
    return announced
end

-- Announce all pending awards with raid warnings (used by "Award Announce" button)
function Announcer:AnnounceAwardsWithRaidWarning(sessionId)
    -- Only raid leader can announce to raid
    if IsInRaid() and not UnitIsGroupLeader("player") then
        HooligansLoot:Print("Only the Raid Leader can announce to raid.")
        return 0
    end

    local SessionManager = HooligansLoot:GetModule("SessionManager")
    local session = sessionId and SessionManager:GetSession(sessionId) or SessionManager:GetCurrentSession()

    if not session then
        HooligansLoot:Print("No session to announce.")
        return 0
    end

    -- Get pending awards only (not yet traded)
    local pending = SessionManager:GetPendingAwards(session.id)
    if Utils.TableSize(pending) == 0 then
        HooligansLoot:Print("No pending awards to announce.")
        return 0
    end

    local announced = 0

    -- Announce each pending award with raid warning
    for itemGUID, data in pairs(pending) do
        local award = session.awards[itemGUID]
        local playerClass = award and award.class or nil

        self:AnnounceAwardRaidWarning(data.item, data.winner, playerClass)
        announced = announced + 1

        -- Small delay between announcements to avoid spam
        if announced < Utils.TableSize(pending) then
            -- Note: In WoW, we can't actually delay in a loop, but we can print
        end
    end

    HooligansLoot:Print(string.format("Announced %d pending awards with raid warning", announced))
    return announced
end

function Announcer:AnnouncePendingAwards(sessionId)
    local SessionManager = HooligansLoot:GetModule("SessionManager")
    local session = sessionId and SessionManager:GetSession(sessionId) or SessionManager:GetCurrentSession()

    if not session then
        HooligansLoot:Print("No session to announce.")
        return 0
    end

    local pending = SessionManager:GetPendingAwards(session.id)
    if Utils.TableSize(pending) == 0 then
        HooligansLoot:Print("No pending awards to announce.")
        return 0
    end

    local channel = self:GetChannel()
    local announced = 0

    -- Header
    self:SendMessage("Pending awards from " .. session.name .. ":", channel)

    -- Collect and sort
    local pendingList = {}
    for itemGUID, data in pairs(pending) do
        table.insert(pendingList, data)
    end

    table.sort(pendingList, function(a, b)
        return (a.item.name or "") < (b.item.name or "")
    end)

    -- Announce each
    for _, data in ipairs(pendingList) do
        local tradeTime = Utils.GetTradeTimeRemaining(data.item.tradeExpires)
        local timeStr = Utils.FormatTimeRemaining(tradeTime)

        local msg = string.format("%s -> %s (Trade: %s)",
            data.item.link or data.item.name,
            data.winner,
            Utils.StripColor(timeStr)
        )
        self:SendMessage(msg, channel)
        announced = announced + 1
    end

    HooligansLoot:Print(string.format("Announced %d pending awards to %s", announced, channel))
    return announced
end

function Announcer:AnnounceToPlayer(playerName, sessionId)
    local SessionManager = HooligansLoot:GetModule("SessionManager")
    local session = sessionId and SessionManager:GetSession(sessionId) or SessionManager:GetCurrentSession()

    if not session then return 0 end

    local items = SessionManager:GetAwardsForPlayer(session.id, playerName)
    if #items == 0 then
        return 0
    end

    -- Whisper the player
    SendChatMessage("You have been awarded:", "WHISPER", nil, playerName)

    for _, item in ipairs(items) do
        local tradeTime = Utils.GetTradeTimeRemaining(item.tradeExpires)
        local msg = string.format("  %s (Trade expires: %s)",
            item.link or item.name,
            Utils.StripColor(Utils.FormatTimeRemaining(tradeTime))
        )
        SendChatMessage(msg, "WHISPER", nil, playerName)
    end

    SendChatMessage("Please trade with the Raid Leader to receive your item(s).", "WHISPER", nil, playerName)

    return #items
end

function Announcer:AnnounceTradeReminder(sessionId)
    local SessionManager = HooligansLoot:GetModule("SessionManager")
    local session = sessionId and SessionManager:GetSession(sessionId) or SessionManager:GetCurrentSession()

    if not session then return end

    local pending = SessionManager:GetPendingAwards(session.id)
    if Utils.TableSize(pending) == 0 then
        return
    end

    -- Group by player
    local byPlayer = {}
    for itemGUID, data in pairs(pending) do
        local winner = data.winner
        if not byPlayer[winner] then
            byPlayer[winner] = {}
        end
        table.insert(byPlayer[winner], data.item)
    end

    -- Whisper each player with pending items
    for player, items in pairs(byPlayer) do
        self:AnnounceToPlayer(player, session.id)
    end

    HooligansLoot:Print("Sent trade reminders to " .. Utils.TableSize(byPlayer) .. " players")
end
