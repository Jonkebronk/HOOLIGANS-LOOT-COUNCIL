-- Modules/LootTracker.lua
-- Tracks looted items and trade timers

local ADDON_NAME, NS = ...
local HooligansLoot = NS.addon
local Utils = NS.Utils

local LootTracker = HooligansLoot:NewModule("LootTracker", "AceEvent-3.0")

-- Trade window duration in seconds (2 hours)
local TRADE_DURATION = 2 * 60 * 60

-- Current boss name (set during encounters)
local currentBoss = nil

-- Scanning tooltip (created once)
local scanTooltip = nil

-- Create event frame for reliable event registration (same fix as PackMule)
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ENCOUNTER_END")
eventFrame:RegisterEvent("LOOT_OPENED")
eventFrame:RegisterEvent("LOOT_CLOSED")
eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
eventFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if LootTracker[event] then
        LootTracker[event](LootTracker, event, ...)
    end
end)

function LootTracker:OnEnable()
    -- Track last loot scan
    self.lastLootScan = {}
    self.pendingItems = {}
    self.recentlyLooted = {} -- Track items recently looted to avoid duplicates
    self.pendingIconUpdates = {} -- Items waiting for icon data
    self.trackedItemKeys = {} -- Track by itemString to prevent duplicates across bag moves
    self.lootWindowItems = {} -- Items seen in loot window (for tracking without trade timer)
    self.announcedItems = {} -- Track items already announced to avoid duplicates

    -- Register for session events to clear tracking data
    HooligansLoot.RegisterCallback(self, "SESSION_STARTED", "OnSessionStarted")
    HooligansLoot.RegisterCallback(self, "SESSION_ENDED", "OnSessionEnded")

    HooligansLoot:Debug("LootTracker module enabled")
end

function LootTracker:OnSessionStarted(event, session)
    -- Clear tracking tables for new session
    self:ClearTrackingData()
    HooligansLoot:Debug("LootTracker: Cleared tracking data for new session")
end

function LootTracker:OnSessionEnded(event, session)
    -- Clear tracking tables when session ends
    self:ClearTrackingData()
    HooligansLoot:Debug("LootTracker: Cleared tracking data after session end")
end

function LootTracker:ClearTrackingData()
    self.lastLootScan = {}
    self.recentlyLooted = {}
    self.trackedItemKeys = {}
    self.lootWindowItems = {}
    self.announcedItems = {}
end

function LootTracker:OnDisable()
    self:UnregisterAllEvents()
end

function LootTracker:ENCOUNTER_END(event, encounterID, encounterName, difficultyID, groupSize, success)
    if success == 1 then
        currentBoss = encounterName
        HooligansLoot:Debug("Boss killed: " .. encounterName)

        -- Clear boss after 60 seconds (in case of trash loot)
        C_Timer.After(60, function()
            if currentBoss == encounterName then
                currentBoss = nil
                HooligansLoot:Debug("Boss context cleared: " .. encounterName)
            end
        end)
    end
end

function LootTracker:LOOT_OPENED(event, autoLoot)
    -- Allow tracking even if not ML for testing
    local session = HooligansLoot:GetModule("SessionManager"):GetCurrentSession()
    if not session then
        -- Don't spam messages
        return
    end

    -- Scan loot window
    self.lastLootScan = {}
    self.lootWindowItems = {} -- Reset loot window tracking
    local numItems = GetNumLootItems()
    local itemsToAnnounce = {}

    HooligansLoot:Debug("Loot window opened with " .. numItems .. " items")

    for i = 1, numItems do
        local lootIcon, lootName, lootQuantity, currencyID, lootQuality, locked, isQuestItem = GetLootSlotInfo(i)
        local itemLink = GetLootSlotLink(i)

        if itemLink and lootQuality and lootQuality >= HooligansLoot.db.profile.settings.minQuality then
            local itemID = Utils.GetItemID(itemLink)
            local itemString = Utils.GetItemString(itemLink)
            self.lastLootScan[i] = {
                link = itemLink,
                id = itemID,
                name = lootName,
                quality = lootQuality,
                icon = lootIcon,
                boss = currentBoss or "Unknown",
            }
            -- Mark this item as seen in loot window (for tracking even without trade timer)
            if itemID then
                self.lootWindowItems[itemID] = {
                    link = itemLink,
                    name = lootName,
                    quality = lootQuality,
                    icon = lootIcon,
                    boss = currentBoss or "Unknown",
                    timestamp = time(),
                }
            end
            -- Queue for announcement
            table.insert(itemsToAnnounce, itemLink)
            HooligansLoot:Debug("Scanned loot slot " .. i .. ": " .. (lootName or "unknown"))
        end
    end

    -- Announce all items immediately from loot window
    if #itemsToAnnounce > 0 then
        self:AnnounceLootItems(itemsToAnnounce)
    end
end

function LootTracker:LOOT_CLOSED()
    -- Clear last scan after a brief delay (items should be in bags now if looted)
    C_Timer.After(0.5, function()
        self.lastLootScan = {}
    end)
    -- Keep lootWindowItems for longer (60 seconds) to allow bag scanning to catch up
    C_Timer.After(60, function()
        self.lootWindowItems = {}
    end)
end

function LootTracker:GET_ITEM_INFO_RECEIVED(event, itemID, success)
    if not itemID then return end

    -- Check if we have pending items waiting for this icon
    if self.pendingIconUpdates and self.pendingIconUpdates[itemID] then
        self:TryUpdateItemIcon(itemID)
    end
end

function LootTracker:TryUpdateItemIcon(itemID)
    local session = HooligansLoot:GetModule("SessionManager"):GetCurrentSession()
    if not session then return false end

    local name, link, quality, _, _, _, _, _, _, icon = GetItemInfo(itemID)
    if not name then return false end

    local updated = false
    for _, item in ipairs(session.items) do
        if item.id == itemID and (not item.icon or item.icon == "Interface\\Icons\\INV_Misc_QuestionMark") then
            item.name = name
            item.link = link
            item.quality = quality or 4
            item.icon = icon
            updated = true
            HooligansLoot:Debug("Updated icon for: " .. name)
        end
    end

    if updated then
        HooligansLoot.callbacks:Fire("SESSION_UPDATED", session)
        if self.pendingIconUpdates then
            self.pendingIconUpdates[itemID] = nil
        end
    end

    return updated
end

-- Periodically retry loading missing icons (for Classic compatibility)
function LootTracker:RetryPendingIcons(retryCount)
    retryCount = retryCount or 0
    if not self.pendingIconUpdates then return end
    if retryCount > 10 then return end -- Max 10 retries

    local session = HooligansLoot:GetModule("SessionManager"):GetCurrentSession()
    if not session then return end

    local stillPending = {}
    local updated = false

    for itemID, _ in pairs(self.pendingIconUpdates) do
        -- Try to get the info
        local name, link, quality, _, _, _, _, _, _, icon = GetItemInfo(itemID)
        if name and icon then
            -- Update the item in session
            for _, item in ipairs(session.items) do
                if item.id == itemID then
                    item.name = name
                    item.link = link
                    item.quality = quality or 4
                    item.icon = icon
                    updated = true
                end
            end
        else
            -- Still pending, re-request
            stillPending[itemID] = true
            -- Re-query to trigger cache
            GetItemInfo(itemID)
        end
    end

    self.pendingIconUpdates = stillPending

    if updated then
        HooligansLoot.callbacks:Fire("SESSION_UPDATED", session)
    end

    -- If still have pending items, schedule another retry (increasing delay)
    if next(stillPending) then
        local delay = 0.5 + (retryCount * 0.5) -- 0.5s, 1s, 1.5s, etc.
        C_Timer.After(delay, function()
            self:RetryPendingIcons(retryCount + 1)
        end)
    end
end

-- Request item info to cache it (triggers GET_ITEM_INFO_RECEIVED when ready)
function LootTracker:RequestItemInfo(itemID)
    if not itemID then return nil end

    if not self.pendingIconUpdates then
        self.pendingIconUpdates = {}
    end

    -- Check if already cached
    local name, link, quality, _, _, _, _, _, _, icon = GetItemInfo(itemID)
    if name and icon then
        return name, link, quality, icon
    end

    -- Mark as pending
    self.pendingIconUpdates[itemID] = true

    -- Request the item info using multiple methods for compatibility
    -- Method 1: Query via item link (works in most versions)
    local itemLink = "item:" .. itemID
    GetItemInfo(itemLink)

    -- Method 2: Tooltip query (forces client to request item data)
    local tooltip = self:GetScanTooltip()
    tooltip:ClearLines()
    tooltip:SetHyperlink(itemLink)

    return nil, nil, nil, nil
end

function LootTracker:BAG_UPDATE_DELAYED()
    local session = HooligansLoot:GetModule("SessionManager"):GetCurrentSession()
    if not session then return end

    -- Scan bags for new epic+ items with trade timer
    self:ScanBagsForNewItems(session)
end

function LootTracker:ScanBagsForNewItems(session)
    local minQuality = HooligansLoot.db.profile.settings.minQuality

    for bagID = 0, NUM_BAG_SLOTS do
        local numSlots = C_Container.GetContainerNumSlots(bagID)
        for slotID = 1, numSlots do
            local itemLink = C_Container.GetContainerItemLink(bagID, slotID)

            if itemLink then
                local itemName, _, quality = GetItemInfo(itemLink)
                local itemID = Utils.GetItemID(itemLink)

                -- Debug: Log items we're checking
                if quality and quality >= minQuality then
                    HooligansLoot:Debug("Checking bag item: " .. (itemName or "unknown") .. " quality=" .. tostring(quality) .. " minQ=" .. tostring(minQuality))
                end

                if quality and quality >= minQuality then
                    -- Check if this item is already tracked
                    local alreadyTracked = self:IsItemTracked(session, bagID, slotID, itemLink)
                    if not alreadyTracked then
                        local hasTradeTimer = self:HasTradeTimer(bagID, slotID)
                        local wasInLootWindow = self.lootWindowItems and itemID and self.lootWindowItems[itemID]

                        HooligansLoot:Debug("  hasTradeTimer=" .. tostring(hasTradeTimer) .. " wasInLootWindow=" .. tostring(wasInLootWindow and true or false))

                        -- Track if: has trade timer OR was just looted from loot window
                        if hasTradeTimer or wasInLootWindow then
                            self:AddItem(session, itemLink, bagID, slotID, hasTradeTimer)
                            -- Clear from loot window tracking once added
                            if wasInLootWindow then
                                self.lootWindowItems[itemID] = nil
                            end
                        end
                    else
                        HooligansLoot:Debug("  Already tracked, skipping")
                    end
                end
            end
        end
    end
end

function LootTracker:GetScanTooltip()
    if not scanTooltip then
        scanTooltip = CreateFrame("GameTooltip", "HooligansLootScanTooltip", nil, "GameTooltipTemplate")
        scanTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
    end
    return scanTooltip
end

function LootTracker:HasTradeTimer(bagID, slotID)
    local tooltip = self:GetScanTooltip()
    tooltip:ClearLines()
    tooltip:SetBagItem(bagID, slotID)

    local numLines = tooltip:NumLines()
    HooligansLoot:Debug("HasTradeTimer: Scanning " .. numLines .. " tooltip lines for bag " .. bagID .. " slot " .. slotID)

    for i = 1, numLines do
        local line = _G["HooligansLootScanTooltipTextLeft" .. i]
        if line then
            local text = line:GetText()
            if text then
                -- Check for trade timer text (multiple patterns for compatibility)
                if text:find("You may trade this item") or text:find("trade this item") then
                    HooligansLoot:Debug("  Found trade timer text: " .. text)
                    return true
                end
            end
        end
    end

    HooligansLoot:Debug("  No trade timer found")
    return false
end

function LootTracker:IsItemTracked(session, bagID, slotID, itemLink)
    local itemString = Utils.GetItemString(itemLink)
    local itemID = Utils.GetItemID(itemLink)

    -- Primary check: by itemString (unique item identifier) - prevents duplicates across bag moves
    if itemString and self.trackedItemKeys and self.trackedItemKeys[itemString] then
        return true
    end

    -- Secondary check: by itemID in session (for items with same base but different suffixes)
    for _, item in ipairs(session.items) do
        -- Check if same itemID and same bag position (handles stacks/moved items)
        if item.id == itemID then
            -- If item was manually added or distributed, allow new tracking
            if item.manualEntry or item.distributed then
                -- Continue checking
            else
                -- Same itemID already tracked - likely a duplicate
                -- Check itemString for exact match
                local trackedItemString = Utils.GetItemString(item.link)
                if trackedItemString == itemString then
                    return true
                end
            end
        end
    end

    -- Also check recently looted to avoid duplicates during rapid bag updates
    if itemString and self.recentlyLooted and self.recentlyLooted[itemString] then
        return true
    end

    return false
end

-- Announce multiple loot items to raid chat (like Gargul)
function LootTracker:AnnounceLootItems(itemLinks)
    if not itemLinks or #itemLinks == 0 then
        HooligansLoot:Debug("AnnounceLootItems: No items to announce")
        return
    end

    if not IsInGroup() then
        HooligansLoot:Debug("AnnounceLootItems: Not in group")
        return
    end

    -- Determine channel
    local inRaid = IsInRaid()
    local isAssist = UnitIsGroupAssistant("player") or UnitIsGroupLeader("player")
    local channel

    if inRaid and isAssist then
        channel = "RAID_WARNING"
    elseif inRaid then
        channel = "RAID"
    else
        channel = "PARTY"
    end

    HooligansLoot:Debug("AnnounceLootItems: Announcing " .. #itemLinks .. " items to " .. channel)

    -- Initialize announced items table
    if not self.announcedItems then
        self.announcedItems = {}
    end

    -- Announce each item
    for _, itemLink in ipairs(itemLinks) do
        local itemID = Utils.GetItemID(itemLink)
        local itemString = Utils.GetItemString(itemLink)

        -- Check if already announced (by itemID or itemString)
        local alreadyAnnounced = false
        if itemID and self.announcedItems["id:" .. itemID] then
            alreadyAnnounced = true
        end
        if itemString and self.announcedItems[itemString] then
            alreadyAnnounced = true
        end

        if not alreadyAnnounced then
            -- Mark as announced by both ID and string
            if itemID then
                self.announcedItems["id:" .. itemID] = time()
            end
            if itemString then
                self.announcedItems[itemString] = time()
            end

            -- Format: {Star} HOOLIGANS: [Item Link]
            local msg = "{Star} HOOLIGANS: " .. itemLink
            SendChatMessage(msg, channel)
        else
            HooligansLoot:Debug("AnnounceLootItems: Already announced itemID=" .. tostring(itemID))
        end
    end
end

function LootTracker:AddItem(session, itemLink, bagID, slotID, hasTradeTimer)
    local itemID = Utils.GetItemID(itemLink)
    local itemName, _, itemQuality, _, _, _, _, _, _, itemTexture = GetItemInfo(itemLink)
    local itemString = Utils.GetItemString(itemLink)

    -- Get boss from last scan or loot window items if available
    local boss = currentBoss or "Unknown"
    for _, scanData in pairs(self.lastLootScan) do
        if scanData.id == itemID then
            boss = scanData.boss
            break
        end
    end
    -- Also check lootWindowItems for boss info
    if boss == "Unknown" and self.lootWindowItems and self.lootWindowItems[itemID] then
        boss = self.lootWindowItems[itemID].boss or "Unknown"
    end

    local item = {
        guid = Utils.GenerateItemGUID(itemLink, bagID, slotID),
        id = itemID,
        link = itemLink,
        name = itemName or Utils.GetItemName(itemLink),
        quality = itemQuality or 4,
        icon = itemTexture,
        boss = boss,
        timestamp = time(),
        bagId = bagID,
        slotId = slotID,
        tradeable = hasTradeTimer ~= false, -- Default true unless explicitly false
        tradeExpires = hasTradeTimer ~= false and (time() + TRADE_DURATION) or nil,
    }

    table.insert(session.items, item)

    -- Mark as tracked by itemString to prevent duplicates across bag moves
    if itemString then
        if not self.trackedItemKeys then
            self.trackedItemKeys = {}
        end
        self.trackedItemKeys[itemString] = time()

        -- Also mark in recentlyLooted by itemString (not bag position)
        if not self.recentlyLooted then
            self.recentlyLooted = {}
        end
        self.recentlyLooted[itemString] = time()

        -- Clean up old entries after 5 minutes
        C_Timer.After(300, function()
            if self.recentlyLooted then
                self.recentlyLooted[itemString] = nil
            end
        end)
    end

    HooligansLoot:Print("Tracked: " .. item.link .. " (from " .. item.boss .. ")")

    -- Fire callback for UI update
    HooligansLoot.callbacks:Fire("ITEM_ADDED", item)

    -- Send lightweight ITEM_ADD message for faster sync
    if IsInGroup() then
        local Comm = HooligansLoot:GetModule("Comm", true)
        if Comm then
            Comm:BroadcastMessage(Comm.MessageTypes.ITEM_ADD, {
                item = {
                    g = item.guid,
                    id = item.id,
                    l = item.link,
                    b = item.boss,
                },
            })
        end
    end

    -- Refresh local UI
    local SessionManager = HooligansLoot:GetModule("SessionManager", true)
    if SessionManager then
        SessionManager:RefreshAllUI()
    end
end

function LootTracker:RemoveItem(session, itemGUID)
    for i, item in ipairs(session.items) do
        if item.guid == itemGUID then
            local removed = table.remove(session.items, i)
            HooligansLoot.callbacks:Fire("ITEM_REMOVED", removed)

            -- Immediately broadcast to raiders
            local SessionManager = HooligansLoot:GetModule("SessionManager", true)
            if SessionManager then
                SessionManager:BroadcastSession()
                SessionManager:RefreshAllUI()
            end

            return true
        end
    end
    return false
end

-- Manually add an item by item link
function LootTracker:AddItemManually(itemLink, bossName)
    local SessionManager = HooligansLoot:GetModule("SessionManager")
    local session = SessionManager:GetCurrentSession()

    if not session then
        HooligansLoot:Print("No active session. Create one first with /hl session new")
        return false
    end

    if not itemLink or itemLink == "" then
        HooligansLoot:Print("Invalid item link.")
        return false
    end

    -- Parse item info from link
    local itemID = Utils.GetItemID(itemLink)
    if not itemID then
        HooligansLoot:Print("Could not parse item ID from link.")
        return false
    end

    local itemName, _, itemQuality, _, _, _, _, _, _, itemTexture = GetItemInfo(itemLink)

    -- If item info not cached, request it
    if not itemName then
        itemName = Utils.GetItemName(itemLink)
        itemQuality = 4 -- Default to epic
        -- Request item info for icon update
        self:RequestItemInfo(itemID)
    end

    local item = {
        guid = "manual_" .. itemID .. "_" .. time() .. "_" .. math.random(1000, 9999),
        id = itemID,
        link = itemLink,
        name = itemName or "Unknown Item",
        quality = itemQuality or 4,
        icon = itemTexture or "Interface\\Icons\\INV_Misc_QuestionMark",
        boss = bossName or "Manual Entry",
        timestamp = time(),
        bagId = nil,
        slotId = nil,
        tradeable = true,
        tradeExpires = time() + TRADE_DURATION,
        manualEntry = true, -- Flag to indicate this was manually added
    }

    table.insert(session.items, item)

    HooligansLoot:Print("Added: " .. (item.link or item.name))
    HooligansLoot.callbacks:Fire("ITEM_ADDED", item)

    -- Send lightweight ITEM_ADD message for faster sync
    if IsInGroup() then
        local Comm = HooligansLoot:GetModule("Comm", true)
        if Comm then
            Comm:BroadcastMessage(Comm.MessageTypes.ITEM_ADD, {
                item = {
                    g = item.guid,
                    id = item.id,
                    l = item.link,
                    b = item.boss,
                },
            })
        end
    end

    -- Refresh local UI
    local SessionManager = HooligansLoot:GetModule("SessionManager", true)
    if SessionManager then
        SessionManager:RefreshAllUI()
    end

    return true
end

-- Track an item that was distributed via PackMule or Master Loot
-- This adds the item to the session and marks who received it
function LootTracker:TrackDistributedItem(itemLink, recipientName, bossName)
    local SessionManager = HooligansLoot:GetModule("SessionManager")
    local session = SessionManager:GetCurrentSession()

    if not session then
        HooligansLoot:Debug("LootTracker: No active session, not tracking item")
        return false
    end

    if not itemLink then
        return false
    end

    local itemID = Utils.GetItemID(itemLink)
    if not itemID then
        return false
    end

    local itemName, _, itemQuality, _, _, _, _, _, _, itemTexture = GetItemInfo(itemLink)

    -- If item info not cached, request it
    if not itemName then
        itemName = Utils.GetItemName(itemLink)
        itemQuality = itemQuality or 2 -- Default to uncommon if unknown
        self:RequestItemInfo(itemID)
    end

    local item = {
        guid = "dist_" .. itemID .. "_" .. time() .. "_" .. math.random(1000, 9999),
        id = itemID,
        link = itemLink,
        name = itemName or "Unknown Item",
        quality = itemQuality or 2,
        icon = itemTexture or "Interface\\Icons\\INV_Misc_QuestionMark",
        boss = bossName or currentBoss or "Unknown",
        timestamp = time(),
        bagId = nil,
        slotId = nil,
        tradeable = false, -- Already distributed
        distributed = true, -- Flag to indicate this was auto-distributed
        awardedTo = recipientName,
    }

    table.insert(session.items, item)

    HooligansLoot:Debug("LootTracker: Tracked distributed item: " .. (item.link or item.name) .. " -> " .. recipientName)
    HooligansLoot.callbacks:Fire("ITEM_ADDED", item)

    -- Send lightweight ITEM_ADD message for sync
    if IsInGroup() then
        local Comm = HooligansLoot:GetModule("Comm", true)
        if Comm then
            Comm:BroadcastMessage(Comm.MessageTypes.ITEM_ADD, {
                item = {
                    g = item.guid,
                    id = item.id,
                    l = item.link,
                    b = item.boss,
                    a = recipientName, -- awarded to
                },
            })
        end
    end

    -- Refresh UI
    if SessionManager then
        SessionManager:RefreshAllUI()
    end

    return true
end

function LootTracker:UpdateItemLocation(session, itemGUID, newBagID, newSlotID)
    for _, item in ipairs(session.items) do
        if item.guid == itemGUID then
            item.bagId = newBagID
            item.slotId = newSlotID
            HooligansLoot:Debug("Updated item location: " .. item.name)
            return true
        end
    end
    return false
end

function LootTracker:RefreshItemLocations(session)
    -- Re-scan bags to update item locations (items may have been moved)
    local minQuality = HooligansLoot.db.profile.settings.minQuality

    for _, item in ipairs(session.items) do
        local found = false

        -- Search all bags for this item
        for bagID = 0, NUM_BAG_SLOTS do
            local numSlots = C_Container.GetContainerNumSlots(bagID)
            for slotID = 1, numSlots do
                local bagLink = C_Container.GetContainerItemLink(bagID, slotID)
                if bagLink then
                    local bagItemID = Utils.GetItemID(bagLink)
                    if bagItemID == item.id then
                        -- Check if still tradeable
                        if self:HasTradeTimer(bagID, slotID) then
                            item.bagId = bagID
                            item.slotId = slotID
                            item.tradeable = true
                            found = true
                            break
                        end
                    end
                end
            end
            if found then break end
        end

        if not found then
            -- Item may have been traded or moved
            item.tradeable = false
        end
    end
end

function LootTracker:GetTradeableItems(session)
    local tradeable = {}
    local now = time()

    for _, item in ipairs(session.items) do
        if item.tradeable and item.tradeExpires and item.tradeExpires > now then
            table.insert(tradeable, item)
        end
    end

    return tradeable
end

function LootTracker:FindItemInBags(itemID)
    -- Find an item by ID in player's bags
    for bagID = 0, NUM_BAG_SLOTS do
        local numSlots = C_Container.GetContainerNumSlots(bagID)
        for slotID = 1, numSlots do
            local itemLink = C_Container.GetContainerItemLink(bagID, slotID)
            if itemLink then
                local bagItemID = Utils.GetItemID(itemLink)
                if bagItemID == itemID then
                    return bagID, slotID, itemLink
                end
            end
        end
    end
    return nil, nil, nil
end

-- Karazhan loot table for testing
local KARAZHAN_LOOT = {
    -- Attumen the Huntsman
    { id = 28477, name = "Harbinger Bands", boss = "Attumen the Huntsman" },
    { id = 28454, name = "Stalker's War Bands", boss = "Attumen the Huntsman" },
    { id = 28453, name = "Bracers of the White Stag", boss = "Attumen the Huntsman" },
    { id = 28481, name = "Gloves of Saintly Blessings", boss = "Attumen the Huntsman" },
    { id = 28478, name = "Fiery Warhorse's Reins", boss = "Attumen the Huntsman" },

    -- Moroes
    { id = 28529, name = "Royal Cloak of Arathi Kings", boss = "Moroes" },
    { id = 28528, name = "Moroes' Lucky Pocket Watch", boss = "Moroes" },
    { id = 28525, name = "Signet of Unshakable Faith", boss = "Moroes" },
    { id = 28527, name = "Emerald Ripper", boss = "Moroes" },
    { id = 28524, name = "Edgewalker Longboots", boss = "Moroes" },

    -- Maiden of Virtue
    { id = 28520, name = "Bracers of Maliciousness", boss = "Maiden of Virtue" },
    { id = 28517, name = "Boots of Foretelling", boss = "Maiden of Virtue" },
    { id = 28522, name = "Shard of the Virtuous", boss = "Maiden of Virtue" },
    { id = 28521, name = "Mitts of the Treemender", boss = "Maiden of Virtue" },

    -- Opera (Romulo and Julianne)
    { id = 28578, name = "Masquerade Gown", boss = "Opera Event" },
    { id = 28572, name = "Blade of the Unrequited", boss = "Opera Event" },
    { id = 28573, name = "Despair", boss = "Opera Event" },
    { id = 28587, name = "Legacy", boss = "Opera Event" },

    -- Curator
    { id = 28633, name = "Staff of Infinite Mysteries", boss = "The Curator" },
    { id = 28631, name = "Dragon-Quake Shoulderguards", boss = "The Curator" },
    { id = 28647, name = "Forest Wind Shoulderpads", boss = "The Curator" },
    { id = 28649, name = "Garona's Signet Ring", boss = "The Curator" },
    { id = 29757, name = "Gloves of the Fallen Champion", boss = "The Curator" },
    { id = 29758, name = "Gloves of the Fallen Defender", boss = "The Curator" },
    { id = 29756, name = "Gloves of the Fallen Hero", boss = "The Curator" },

    -- Shade of Aran
    { id = 28726, name = "Mantle of the Mind Flayer", boss = "Shade of Aran" },
    { id = 28727, name = "Pendant of the Violet Eye", boss = "Shade of Aran" },
    { id = 28728, name = "Aran's Soothing Sapphire", boss = "Shade of Aran" },
    { id = 28744, name = "Drape of the Dark Reavers", boss = "Shade of Aran" },

    -- Netherspite
    { id = 28744, name = "Uni-Mind Headdress", boss = "Netherspite" },
    { id = 28752, name = "Cowl of Defiance", boss = "Netherspite" },
    { id = 28751, name = "Heart-Flame Leggings", boss = "Netherspite" },
    { id = 28745, name = "Mithril Band of the Unscarred", boss = "Netherspite" },

    -- Chess Event
    { id = 28756, name = "Headdress of the High Potentate", boss = "Chess Event" },
    { id = 28755, name = "Bladed Shoulderpads of the Merciless", boss = "Chess Event" },
    { id = 28750, name = "Girdle of Treachery", boss = "Chess Event" },
    { id = 28754, name = "Triptych Shield of the Ancients", boss = "Chess Event" },

    -- Prince Malchezaar
    { id = 28770, name = "Nathrezim Mindblade", boss = "Prince Malchezaar" },
    { id = 28772, name = "Sunfury Bow of the Phoenix", boss = "Prince Malchezaar" },
    { id = 28773, name = "Gorehowl", boss = "Prince Malchezaar" },
    { id = 28763, name = "Jade Ring of the Everliving", boss = "Prince Malchezaar" },
    { id = 28762, name = "Adornment of Stolen Souls", boss = "Prince Malchezaar" },
    { id = 28765, name = "Stainless Cloak of the Pure Hearted", boss = "Prince Malchezaar" },
    { id = 28764, name = "Farstrider Wildercloak", boss = "Prince Malchezaar" },
    { id = 29760, name = "Helm of the Fallen Champion", boss = "Prince Malchezaar" },
    { id = 29761, name = "Helm of the Fallen Defender", boss = "Prince Malchezaar" },
    { id = 29759, name = "Helm of the Fallen Hero", boss = "Prince Malchezaar" },

    -- Nightbane
    { id = 28602, name = "Robe of the Elder Scribes", boss = "Nightbane" },
    { id = 28601, name = "Chestguard of the Conniver", boss = "Nightbane" },
    { id = 28608, name = "Ironstriders of Urgency", boss = "Nightbane" },
    { id = 28609, name = "Emberspur Talisman", boss = "Nightbane" },
    { id = 28611, name = "Dragonheart Flameshield", boss = "Nightbane" },
}

-- Manual add for testing (single item)
function LootTracker:AddTestItem()
    local session = HooligansLoot:GetModule("SessionManager"):GetCurrentSession()
    if not session then
        HooligansLoot:Print("No active session! Creating one...")
        session = HooligansLoot:GetModule("SessionManager"):NewSession("Test Session")
    end

    -- Pick a random Karazhan item
    local testData = KARAZHAN_LOOT[math.random(#KARAZHAN_LOOT)]

    local testItem = {
        guid = "test:" .. testData.id .. ":" .. time() .. ":" .. math.random(10000),
        id = testData.id,
        link = "|cffa335ee|Hitem:" .. testData.id .. "::::::::70:::::|h[" .. testData.name .. "]|h|r",
        name = testData.name,
        quality = 4,
        icon = "Interface\\Icons\\INV_Misc_QuestionMark",
        boss = testData.boss,
        timestamp = time(),
        bagId = 0,
        slotId = math.random(1, 16),
        tradeable = true,
        tradeExpires = time() + TRADE_DURATION,
    }

    -- Try to get real item info if cached
    local name, link, quality, _, _, _, _, _, _, icon = GetItemInfo(testData.id)
    if name then
        testItem.name = name
        testItem.link = link
        testItem.quality = quality
        testItem.icon = icon
    end

    table.insert(session.items, testItem)
    HooligansLoot:Print("Added test item: " .. testItem.link)
    HooligansLoot.callbacks:Fire("ITEM_ADDED", testItem)

    -- Send lightweight ITEM_ADD message for faster sync
    if IsInGroup() then
        local Comm = HooligansLoot:GetModule("Comm", true)
        if Comm then
            Comm:BroadcastMessage(Comm.MessageTypes.ITEM_ADD, {
                item = {
                    g = testItem.guid,
                    id = testItem.id,
                    l = testItem.link,
                    b = testItem.boss,
                },
            })
        end
    end

    -- Refresh local UI
    local SessionManager = HooligansLoot:GetModule("SessionManager", true)
    if SessionManager then
        SessionManager:RefreshAllUI()
    end

    return testItem
end

-- Simulate a full Karazhan raid with multiple drops
function LootTracker:SimulateKarazhanRaid(numItems)
    numItems = numItems or 8 -- Default to 8 items

    local session = HooligansLoot:GetModule("SessionManager"):GetCurrentSession()
    if not session then
        HooligansLoot:Print("Creating new session: Karazhan Run")
        session = HooligansLoot:GetModule("SessionManager"):NewSession("Karazhan - " .. date("%m/%d %H:%M"))
    end

    HooligansLoot:Print("|cff00ff00Simulating Karazhan raid with " .. numItems .. " drops...|r")

    -- Shuffle and pick items
    local shuffled = {}
    for i, item in ipairs(KARAZHAN_LOOT) do
        shuffled[i] = item
    end

    -- Fisher-Yates shuffle
    for i = #shuffled, 2, -1 do
        local j = math.random(i)
        shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
    end

    -- Add items
    local added = 0
    local itemsToLoad = {}

    for i = 1, math.min(numItems, #shuffled) do
        local testData = shuffled[i]

        local testItem = {
            guid = "test:" .. testData.id .. ":" .. time() .. ":" .. math.random(10000),
            id = testData.id,
            link = "|cffa335ee|Hitem:" .. testData.id .. "::::::::70:::::|h[" .. testData.name .. "]|h|r",
            name = testData.name,
            quality = 4,
            icon = "Interface\\Icons\\INV_Misc_QuestionMark",
            boss = testData.boss,
            timestamp = time(),
            bagId = 0,
            slotId = i,
            tradeable = true,
            tradeExpires = time() + TRADE_DURATION,
        }

        -- Try to get real item info if cached
        local name, link, quality, _, _, _, _, _, _, icon = GetItemInfo(testData.id)
        if name then
            testItem.name = name
            testItem.link = link
            testItem.quality = quality
            testItem.icon = icon
        else
            -- Queue for async loading
            table.insert(itemsToLoad, testData.id)
        end

        table.insert(session.items, testItem)
        added = added + 1

        print(string.format("  |cff888888[%s]|r %s", testItem.boss, testItem.link))
    end

    -- Request item info for all uncached items
    if #itemsToLoad > 0 then
        HooligansLoot:Print("|cffffcc00Loading " .. #itemsToLoad .. " item icons...|r")
        for _, itemID in ipairs(itemsToLoad) do
            self:RequestItemInfo(itemID)
        end
        -- Start retry loop for Classic compatibility
        C_Timer.After(0.5, function()
            self:RetryPendingIcons()
        end)
    end

    HooligansLoot:Print("|cff00ff00Added " .. added .. " items to session!|r")
    HooligansLoot:Print("Use |cff88ccff/hl export|r to export, then import awards with |cff88ccff/hl import|r")

    HooligansLoot.callbacks:Fire("SESSION_UPDATED", session)

    -- Explicitly broadcast session to sync items to raiders
    local SessionManager = HooligansLoot:GetModule("SessionManager", true)
    if SessionManager then
        SessionManager:BroadcastSession()
    end

    return added
end

-- List available test raids
function LootTracker:ListTestRaids()
    HooligansLoot:Print("Available test raids:")
    print("  |cff88ccff/hl test kara [count]|r - Simulate Karazhan (default 8 items)")
    print("  |cff88ccff/hl test item|r - Add single random item")
end

-- Set current boss manually (for testing or manual override)
function LootTracker:SetCurrentBoss(bossName)
    currentBoss = bossName
    HooligansLoot:Debug("Boss set manually: " .. (bossName or "nil"))
end

function LootTracker:GetCurrentBoss()
    return currentBoss
end

-- Manual bag scan command for debugging
function LootTracker:ManualScan()
    local session = HooligansLoot:GetModule("SessionManager"):GetCurrentSession()
    if not session then
        HooligansLoot:Print("No active session!")
        return
    end

    HooligansLoot:Print("Scanning bags for tradeable items...")
    local minQuality = HooligansLoot.db.profile.settings.minQuality
    HooligansLoot:Print("Minimum quality setting: " .. tostring(minQuality) .. " (3=Rare, 4=Epic)")

    local found = 0
    for bagID = 0, NUM_BAG_SLOTS do
        local numSlots = C_Container.GetContainerNumSlots(bagID)
        for slotID = 1, numSlots do
            local itemLink = C_Container.GetContainerItemLink(bagID, slotID)
            if itemLink then
                local itemName, _, quality = GetItemInfo(itemLink)
                if quality and quality >= minQuality then
                    local hasTradeTimer = self:HasTradeTimer(bagID, slotID)
                    local alreadyTracked = self:IsItemTracked(session, bagID, slotID, itemLink)

                    HooligansLoot:Print(string.format(
                        "  [%d,%d] %s (q=%d) timer=%s tracked=%s",
                        bagID, slotID,
                        itemName or "?",
                        quality,
                        tostring(hasTradeTimer),
                        tostring(alreadyTracked)
                    ))

                    if hasTradeTimer and not alreadyTracked then
                        self:AddItem(session, itemLink, bagID, slotID, true)
                        found = found + 1
                    end
                end
            end
        end
    end

    if found > 0 then
        HooligansLoot:Print("Added " .. found .. " items!")
    else
        HooligansLoot:Print("No new tradeable items found.")
    end
end
