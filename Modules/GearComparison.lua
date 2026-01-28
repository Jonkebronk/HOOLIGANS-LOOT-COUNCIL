-- Modules/GearComparison.lua
-- Gear comparison module - shows players' equipped items for voting slots

local ADDON_NAME, NS = ...
local HooligansLoot = NS.addon
local Utils = NS.Utils

local GearComparison = HooligansLoot:NewModule("GearComparison")

-- Slot mapping: equipment location to inventory slot IDs
-- Some items can go in multiple slots (rings, trinkets, weapons)
GearComparison.SLOT_MAPPING = {
    INVTYPE_HEAD = {1},
    INVTYPE_NECK = {2},
    INVTYPE_SHOULDER = {3},
    INVTYPE_BODY = {4},          -- Shirt
    INVTYPE_CHEST = {5},
    INVTYPE_ROBE = {5},          -- Chest (robes)
    INVTYPE_WAIST = {6},
    INVTYPE_LEGS = {7},
    INVTYPE_FEET = {8},
    INVTYPE_WRIST = {9},
    INVTYPE_HAND = {10},
    INVTYPE_FINGER = {11, 12},   -- Rings (both slots)
    INVTYPE_TRINKET = {13, 14},  -- Trinkets (both slots)
    INVTYPE_CLOAK = {15},
    INVTYPE_WEAPON = {16, 17},   -- One-hand weapons (main or off)
    INVTYPE_2HWEAPON = {16},     -- Two-hand weapons
    INVTYPE_WEAPONMAINHAND = {16},
    INVTYPE_WEAPONOFFHAND = {17},
    INVTYPE_HOLDABLE = {17},     -- Off-hand items
    INVTYPE_SHIELD = {17},
    INVTYPE_RANGED = {18},       -- Classic: ranged slot
    INVTYPE_RANGEDRIGHT = {18},  -- Alternative ranged slot
    INVTYPE_THROWN = {18},
    INVTYPE_RELIC = {18},        -- TBC relics
    INVTYPE_TABARD = {19},
}

-- Tooltip scanning frame for item level extraction
local tooltipFrame = nil
local tooltipLines = {}

function GearComparison:OnEnable()
    -- Create tooltip scanning frame
    self:CreateTooltipFrame()
    HooligansLoot:Debug("GearComparison module enabled")
end

-- Create a hidden tooltip for scanning item info
function GearComparison:CreateTooltipFrame()
    if tooltipFrame then return end

    tooltipFrame = CreateFrame("GameTooltip", "HooligansLootGearTooltip", UIParent, "GameTooltipTemplate")
    tooltipFrame:SetOwner(UIParent, "ANCHOR_NONE")

    -- Create font strings for scanning
    for i = 1, 30 do
        local left = tooltipFrame:CreateFontString()
        local right = tooltipFrame:CreateFontString()
        tooltipFrame:AddFontStrings(left, right)
        tooltipLines[i] = { left = left, right = right }
    end
end

-- Get inventory slot IDs for an item based on its equip location
function GearComparison:GetSlotsForItem(itemLink)
    if not itemLink then return nil end

    local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(itemLink)
    if not equipLoc or equipLoc == "" then return nil end

    return self.SLOT_MAPPING[equipLoc]
end

-- Get item level from an item link using tooltip scanning
-- Classic WoW doesn't have GetDetailedItemLevelInfo, so we must scan tooltip
function GearComparison:GetItemLevel(itemLink)
    if not itemLink then return nil end

    -- Try to get cached item info first
    local _, _, _, itemLevel = GetItemInfo(itemLink)
    if itemLevel and itemLevel > 0 then
        return itemLevel
    end

    -- If basic GetItemInfo didn't work, scan tooltip
    if not tooltipFrame then
        self:CreateTooltipFrame()
    end

    tooltipFrame:ClearLines()
    tooltipFrame:SetHyperlink(itemLink)

    -- Scan tooltip lines for "Item Level X"
    for i = 2, tooltipFrame:NumLines() do
        local leftText = _G["HooligansLootGearTooltipTextLeft" .. i]
        if leftText then
            local text = leftText:GetText()
            if text then
                -- Match "Item Level X" pattern
                local ilvl = text:match("Item Level (%d+)")
                if ilvl then
                    return tonumber(ilvl)
                end
            end
        end
    end

    return nil
end

-- Get equipped items for specific inventory slots
function GearComparison:GetEquippedForSlots(slots)
    if not slots then return {} end

    local equipped = {}
    for _, slotId in ipairs(slots) do
        local itemLink = GetInventoryItemLink("player", slotId)
        if itemLink then
            local ilvl = self:GetItemLevel(itemLink)
            local icon = GetInventoryItemTexture("player", slotId)
            equipped[slotId] = {
                link = itemLink,
                ilvl = ilvl,
                icon = icon,
            }
        else
            -- Empty slot
            equipped[slotId] = nil
        end
    end

    return equipped
end

-- Get equipped gear for a specific item being voted on
function GearComparison:GetGearForVoteItem(itemLink)
    local slots = self:GetSlotsForItem(itemLink)
    if not slots then return nil end

    return self:GetEquippedForSlots(slots)
end

-- Calculate item level difference (positive = upgrade)
function GearComparison:GetIlvlDifference(newIlvl, equippedGear)
    if not newIlvl or not equippedGear then return nil end

    -- Find the lowest ilvl of equipped items (biggest upgrade potential)
    local lowestIlvl = nil
    for _, gear in pairs(equippedGear) do
        if gear and gear.ilvl then
            if not lowestIlvl or gear.ilvl < lowestIlvl then
                lowestIlvl = gear.ilvl
            end
        end
    end

    if not lowestIlvl then return nil end

    return newIlvl - lowestIlvl
end

-- Format item level difference for display
function GearComparison:FormatIlvlDiff(diff)
    if not diff then return "" end

    if diff > 0 then
        return string.format("|cff00ff00+%d|r", diff)
    elseif diff < 0 then
        return string.format("|cffff4444%d|r", diff)
    else
        return "|cff888888+0|r"
    end
end

-- Send gear sync to ML for the given vote items
function GearComparison:SendGearSync(voteIds, mlName, items)
    if not voteIds or #voteIds == 0 then return end
    if not mlName then return end

    -- Don't send to ourselves
    if mlName == UnitName("player") then return end

    -- Collect gear for all vote item slots
    local gearData = {}
    local processedSlots = {}  -- Avoid duplicates

    for _, item in ipairs(items or {}) do
        local slots = self:GetSlotsForItem(item.link or item.l)
        if slots then
            for _, slotId in ipairs(slots) do
                if not processedSlots[slotId] then
                    processedSlots[slotId] = true
                    local itemLink = GetInventoryItemLink("player", slotId)
                    if itemLink then
                        local ilvl = self:GetItemLevel(itemLink)
                        gearData[slotId] = {
                            l = itemLink,
                            i = ilvl,
                        }
                    end
                end
            end
        end
    end

    -- Only send if we have gear data
    if next(gearData) then
        local Comm = HooligansLoot:GetModule("Comm", true)
        if Comm then
            Comm:SendMessage(Comm.MessageTypes.GEAR_SYNC, {
                v = voteIds,
                g = gearData,
            }, mlName)
            HooligansLoot:Debug("Sent gear sync to " .. mlName .. " for " .. #voteIds .. " votes")
        end
    end
end

-- Process received gear sync data (ML only)
function GearComparison:ProcessGearSync(data, sender)
    if not data then return end

    local Voting = HooligansLoot:GetModule("Voting", true)
    if not Voting then return end

    -- Only ML processes gear syncs
    if not Voting:IsMasterLooter() then return end

    local voteIds = data.v
    local gearData = data.g

    if not voteIds or not gearData then return end

    HooligansLoot:Debug("Processing gear sync from " .. sender)

    -- Store gear in each vote's playerGear table
    for _, voteId in ipairs(voteIds) do
        local vote = Voting:GetVote(voteId)
        if vote then
            if not vote.playerGear then
                vote.playerGear = {}
            end
            vote.playerGear[sender] = gearData
            HooligansLoot:Debug("Stored gear from " .. sender .. " for vote " .. voteId)
        end
    end

    -- Broadcast vote update so other clients get the gear data
    for _, voteId in ipairs(voteIds) do
        Voting:BroadcastVoteUpdate(voteId)
    end
end

-- Get equipped gear for a specific player from vote data
function GearComparison:GetPlayerGearFromVote(vote, playerName)
    if not vote or not vote.playerGear then return nil end
    return vote.playerGear[playerName]
end

-- Build gear display info for UI
function GearComparison:GetGearDisplayInfo(vote, playerName, newItemLink)
    if not vote or not playerName then return nil end

    local gearData = self:GetPlayerGearFromVote(vote, playerName)
    if not gearData then return nil end

    -- Get slots for the new item
    local slots = self:GetSlotsForItem(newItemLink)
    if not slots then return nil end

    local newIlvl = self:GetItemLevel(newItemLink)

    -- Build display info for each relevant slot
    local displayInfo = {}
    for _, slotId in ipairs(slots) do
        local equipped = gearData[slotId]
        if equipped then
            local diff = nil
            if newIlvl and equipped.i then
                diff = newIlvl - equipped.i
            end

            table.insert(displayInfo, {
                slotId = slotId,
                link = equipped.l,
                ilvl = equipped.i,
                diff = diff,
                diffText = self:FormatIlvlDiff(diff),
            })
        else
            -- Empty slot
            table.insert(displayInfo, {
                slotId = slotId,
                link = nil,
                ilvl = nil,
                diff = newIlvl,  -- Full upgrade if slot is empty
                diffText = newIlvl and self:FormatIlvlDiff(newIlvl) or "",
            })
        end
    end

    return displayInfo
end

-- Get own equipped gear display info (for LootFrame)
function GearComparison:GetOwnGearDisplayInfo(newItemLink)
    if not newItemLink then return nil end

    local slots = self:GetSlotsForItem(newItemLink)
    if not slots then return nil end

    local newIlvl = self:GetItemLevel(newItemLink)
    local equipped = self:GetEquippedForSlots(slots)

    -- Build display info
    local displayInfo = {}
    for _, slotId in ipairs(slots) do
        local gear = equipped[slotId]
        if gear then
            local diff = nil
            if newIlvl and gear.ilvl then
                diff = newIlvl - gear.ilvl
            end

            table.insert(displayInfo, {
                slotId = slotId,
                link = gear.link,
                ilvl = gear.ilvl,
                icon = gear.icon,
                diff = diff,
                diffText = self:FormatIlvlDiff(diff),
            })
        else
            -- Empty slot
            table.insert(displayInfo, {
                slotId = slotId,
                link = nil,
                ilvl = nil,
                icon = nil,
                diff = newIlvl,
                diffText = newIlvl and self:FormatIlvlDiff(newIlvl) or "",
            })
        end
    end

    return displayInfo
end

-- Get slot name for display
function GearComparison:GetSlotName(slotId)
    local slotNames = {
        [1] = "Head",
        [2] = "Neck",
        [3] = "Shoulder",
        [4] = "Shirt",
        [5] = "Chest",
        [6] = "Waist",
        [7] = "Legs",
        [8] = "Feet",
        [9] = "Wrist",
        [10] = "Hands",
        [11] = "Ring 1",
        [12] = "Ring 2",
        [13] = "Trinket 1",
        [14] = "Trinket 2",
        [15] = "Back",
        [16] = "Main Hand",
        [17] = "Off Hand",
        [18] = "Ranged",
        [19] = "Tabard",
    }
    return slotNames[slotId] or "Unknown"
end
