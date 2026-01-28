# Implementation Guide

## Getting Started

This guide provides concrete code examples for implementing each module of HOOLIGANS Loot.

## Project Setup

### Directory Structure
```
HooligansLoot/
├── HooligansLoot.toc
├── embeds.xml
├── Core.lua
├── Utils.lua
├── Modules/
│   ├── LootTracker.lua
│   ├── SessionManager.lua
│   ├── Export.lua
│   ├── Import.lua
│   ├── TradeManager.lua
│   └── Announcer.lua
├── UI/
│   ├── MainFrame.lua
│   ├── SessionView.lua
│   ├── ExportDialog.lua
│   └── ImportDialog.lua
├── Libs/
│   ├── LibStub/
│   ├── CallbackHandler-1.0/
│   ├── AceAddon-3.0/
│   ├── AceConsole-3.0/
│   ├── AceDB-3.0/
│   ├── AceEvent-3.0/
│   └── AceSerializer-3.0/
└── docs/
    └── *.md
```

### TOC File
```toc
## Interface: 20504
## Title: |cff5865F2HOOLIGANS|r Loot
## Notes: Lightweight Award Later loot management for HOOLIGANS guild
## Author: Johnny / HOOLIGANS
## Version: 1.0.0
## SavedVariables: HooligansLootDB
## X-Category: Loot

# Libraries
embeds.xml

# Core
Core.lua
Utils.lua

# Modules
Modules\LootTracker.lua
Modules\SessionManager.lua
Modules\Export.lua
Modules\Import.lua
Modules\TradeManager.lua
Modules\Announcer.lua

# UI
UI\MainFrame.lua
UI\SessionView.lua
UI\ExportDialog.lua
UI\ImportDialog.lua
```

### embeds.xml
```xml
<Ui xmlns="http://www.blizzard.com/wow/ui/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.blizzard.com/wow/ui/ ..\FrameXML\UI.xsd">
    <Include file="Libs\LibStub\LibStub.lua"/>
    <Include file="Libs\CallbackHandler-1.0\CallbackHandler-1.0.xml"/>
    <Include file="Libs\AceAddon-3.0\AceAddon-3.0.xml"/>
    <Include file="Libs\AceConsole-3.0\AceConsole-3.0.xml"/>
    <Include file="Libs\AceDB-3.0\AceDB-3.0.xml"/>
    <Include file="Libs\AceEvent-3.0\AceEvent-3.0.xml"/>
    <Include file="Libs\AceSerializer-3.0\AceSerializer-3.0.xml"/>
</Ui>
```

---

## Core.lua Implementation

```lua
-- Core.lua
-- Main addon initialization

local ADDON_NAME, NS = ...

-- Create addon using Ace3
local HooligansLoot = LibStub("AceAddon-3.0"):NewAddon(ADDON_NAME,
    "AceConsole-3.0",
    "AceEvent-3.0",
    "AceSerializer-3.0"
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
            minQuality = 4, -- Epic and above
        },
        sessions = {},
        currentSessionId = nil,
    }
}

function HooligansLoot:OnInitialize()
    -- Initialize database
    self.db = LibStub("AceDB-3.0"):New("HooligansLootDB", defaults, true)
    
    -- Register slash commands
    self:RegisterChatCommand("hl", "SlashCommand")
    self:RegisterChatCommand("hooligans", "SlashCommand")
    
    self:Print("Loaded. Type /hl for commands.")
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
    elseif cmd == "test" then
        self:RunTest()
    elseif cmd == "help" then
        self:PrintHelp()
    else
        self:Print("Unknown command. Type /hl help")
    end
end

function HooligansLoot:HandleSessionCommand(arg)
    if not arg then
        self:Print("Usage: /hl session <new|end|list>")
        return
    end
    
    arg = arg:lower()
    if arg == "new" then
        self:GetModule("SessionManager"):NewSession()
    elseif arg == "end" then
        self:GetModule("SessionManager"):EndSession()
    elseif arg == "list" then
        self:GetModule("SessionManager"):ListSessions()
    end
end

function HooligansLoot:PrintHelp()
    self:Print("Commands:")
    print("  /hl - Show main window")
    print("  /hl session new [name] - Start new loot session")
    print("  /hl session end - End current session")
    print("  /hl export - Export current session")
    print("  /hl import - Import awards data")
    print("  /hl announce - Announce awards")
    print("  /hl trade - Show pending trades")
    print("  /hl test - Add test item (debug)")
end

function HooligansLoot:Print(msg)
    print(self.colors.primary .. "[HOOLIGANS Loot]|r " .. msg)
end

function HooligansLoot:Debug(msg)
    if self.db.profile.settings.debug then
        print(self.colors.warning .. "[HL Debug]|r " .. msg)
    end
end
```

---

## Utils.lua Implementation

```lua
-- Utils.lua
-- Utility functions

local ADDON_NAME, NS = ...
local Utils = {}
NS.Utils = Utils

-- Parse item ID from item link
function Utils.GetItemID(itemLink)
    if not itemLink then return nil end
    local itemID = string.match(itemLink, "item:(%d+)")
    return itemID and tonumber(itemID) or nil
end

-- Parse item string from item link
function Utils.GetItemString(itemLink)
    if not itemLink then return nil end
    return string.match(itemLink, "(item:[%-?%d:]+)")
end

-- Generate a unique ID for an item instance
-- In Classic, we use itemLink + bag + slot + time as identifier
function Utils.GenerateItemGUID(itemLink, bagId, slotId)
    local itemString = Utils.GetItemString(itemLink) or "unknown"
    return string.format("%s:%d:%d:%d", itemString, bagId or 0, slotId or 0, time())
end

-- Get item quality color
function Utils.GetQualityColor(quality)
    local colors = {
        [0] = "9d9d9d", -- Poor (gray)
        [1] = "ffffff", -- Common (white)
        [2] = "1eff00", -- Uncommon (green)
        [3] = "0070dd", -- Rare (blue)
        [4] = "a335ee", -- Epic (purple)
        [5] = "ff8000", -- Legendary (orange)
    }
    return colors[quality] or "ffffff"
end

-- Format timestamp for display
function Utils.FormatTime(timestamp)
    return date("%Y-%m-%d %H:%M:%S", timestamp)
end

-- Format remaining time (for trade timer)
function Utils.FormatTimeRemaining(seconds)
    if seconds <= 0 then
        return "|cffff0000Expired|r"
    elseif seconds < 60 then
        return string.format("|cffff0000%ds|r", seconds)
    elseif seconds < 300 then -- Less than 5 min
        return string.format("|cffffff00%dm %ds|r", math.floor(seconds / 60), seconds % 60)
    elseif seconds < 3600 then
        return string.format("|cff00ff00%dm|r", math.floor(seconds / 60))
    else
        return string.format("|cff00ff00%dh %dm|r", math.floor(seconds / 3600), math.floor((seconds % 3600) / 60))
    end
end

-- Check if player is Master Looter
function Utils.IsMasterLooter()
    local lootMethod, masterLooterPartyID, masterLooterRaidID = GetLootMethod()
    if lootMethod ~= "master" then
        return false
    end
    
    local playerName = UnitName("player")
    if masterLooterRaidID then
        local mlName = GetRaidRosterInfo(masterLooterRaidID)
        return mlName == playerName
    elseif masterLooterPartyID == 0 then
        return true -- Player is the ML
    end
    
    return false
end

-- Get raid/party members
function Utils.GetGroupMembers()
    local members = {}
    
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local name, _, _, _, _, _, _, online = GetRaidRosterInfo(i)
            if name and online then
                table.insert(members, name)
            end
        end
    elseif IsInGroup() then
        table.insert(members, UnitName("player"))
        for i = 1, GetNumGroupMembers() - 1 do
            local name = UnitName("party" .. i)
            if name then
                table.insert(members, name)
            end
        end
    else
        table.insert(members, UnitName("player"))
    end
    
    return members
end

-- Simple JSON encoder (for export)
function Utils.ToJSON(tbl, indent)
    indent = indent or 0
    local spaces = string.rep("  ", indent)
    local result = {}
    
    if type(tbl) ~= "table" then
        if type(tbl) == "string" then
            return '"' .. tbl:gsub('"', '\\"'):gsub("\n", "\\n") .. '"'
        else
            return tostring(tbl)
        end
    end
    
    -- Check if array or object
    local isArray = #tbl > 0
    local bracket = isArray and "[" or "{"
    local closeBracket = isArray and "]" or "}"
    
    table.insert(result, bracket)
    
    local first = true
    if isArray then
        for _, v in ipairs(tbl) do
            if not first then table.insert(result, ",") end
            first = false
            table.insert(result, "\n" .. spaces .. "  " .. Utils.ToJSON(v, indent + 1))
        end
    else
        for k, v in pairs(tbl) do
            if not first then table.insert(result, ",") end
            first = false
            table.insert(result, "\n" .. spaces .. '  "' .. tostring(k) .. '": ' .. Utils.ToJSON(v, indent + 1))
        end
    end
    
    if not first then
        table.insert(result, "\n" .. spaces)
    end
    table.insert(result, closeBracket)
    
    return table.concat(result)
end

-- Simple JSON decoder (for import)
-- Note: This is a basic implementation. For production, consider a library.
function Utils.FromJSON(str)
    -- Remove whitespace
    str = str:gsub("^%s+", ""):gsub("%s+$", "")
    
    local pos = 1
    
    local function parseValue()
        -- Skip whitespace
        while str:sub(pos, pos):match("%s") do pos = pos + 1 end
        
        local char = str:sub(pos, pos)
        
        if char == '"' then
            -- String
            pos = pos + 1
            local startPos = pos
            while str:sub(pos, pos) ~= '"' or str:sub(pos - 1, pos - 1) == "\\" do
                pos = pos + 1
            end
            local value = str:sub(startPos, pos - 1):gsub('\\"', '"'):gsub("\\n", "\n")
            pos = pos + 1
            return value
            
        elseif char == "{" then
            -- Object
            pos = pos + 1
            local obj = {}
            while true do
                while str:sub(pos, pos):match("%s") do pos = pos + 1 end
                if str:sub(pos, pos) == "}" then
                    pos = pos + 1
                    return obj
                end
                if str:sub(pos, pos) == "," then pos = pos + 1 end
                while str:sub(pos, pos):match("%s") do pos = pos + 1 end
                
                -- Parse key
                local key = parseValue()
                while str:sub(pos, pos):match("%s") do pos = pos + 1 end
                pos = pos + 1 -- Skip ':'
                
                -- Parse value
                obj[key] = parseValue()
            end
            
        elseif char == "[" then
            -- Array
            pos = pos + 1
            local arr = {}
            while true do
                while str:sub(pos, pos):match("%s") do pos = pos + 1 end
                if str:sub(pos, pos) == "]" then
                    pos = pos + 1
                    return arr
                end
                if str:sub(pos, pos) == "," then pos = pos + 1 end
                table.insert(arr, parseValue())
            end
            
        elseif char:match("[%d%-]") then
            -- Number
            local startPos = pos
            while str:sub(pos, pos):match("[%d%.%-eE%+]") do pos = pos + 1 end
            return tonumber(str:sub(startPos, pos - 1))
            
        elseif str:sub(pos, pos + 3) == "true" then
            pos = pos + 4
            return true
            
        elseif str:sub(pos, pos + 4) == "false" then
            pos = pos + 5
            return false
            
        elseif str:sub(pos, pos + 3) == "null" then
            pos = pos + 4
            return nil
        end
        
        return nil
    end
    
    local success, result = pcall(parseValue)
    return success and result or nil
end

-- Convert table to CSV
function Utils.ToCSV(headers, rows)
    local lines = {}
    table.insert(lines, table.concat(headers, ","))
    
    for _, row in ipairs(rows) do
        local values = {}
        for _, header in ipairs(headers) do
            local val = row[header] or ""
            -- Escape commas and quotes
            if type(val) == "string" and (val:find(",") or val:find('"')) then
                val = '"' .. val:gsub('"', '""') .. '"'
            end
            table.insert(values, tostring(val))
        end
        table.insert(lines, table.concat(values, ","))
    end
    
    return table.concat(lines, "\n")
end

-- Parse CSV to table
function Utils.FromCSV(str)
    local lines = {}
    for line in str:gmatch("[^\r\n]+") do
        table.insert(lines, line)
    end
    
    if #lines < 1 then return nil end
    
    -- Parse headers
    local headers = {}
    for header in lines[1]:gmatch("[^,]+") do
        table.insert(headers, header:match("^%s*(.-)%s*$")) -- Trim
    end
    
    -- Parse rows
    local rows = {}
    for i = 2, #lines do
        local row = {}
        local col = 1
        for value in lines[i]:gmatch("[^,]+") do
            row[headers[col]] = value:match("^%s*(.-)%s*$") -- Trim
            col = col + 1
        end
        table.insert(rows, row)
    end
    
    return rows
end

-- Deep copy a table
function Utils.DeepCopy(orig)
    local copy
    if type(orig) == "table" then
        copy = {}
        for k, v in pairs(orig) do
            copy[Utils.DeepCopy(k)] = Utils.DeepCopy(v)
        end
        setmetatable(copy, Utils.DeepCopy(getmetatable(orig)))
    else
        copy = orig
    end
    return copy
end
```

---

## Module: LootTracker.lua

```lua
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

function LootTracker:OnEnable()
    -- Boss detection
    self:RegisterEvent("ENCOUNTER_END")
    
    -- Loot tracking
    self:RegisterEvent("LOOT_OPENED")
    self:RegisterEvent("LOOT_CLOSED")
    
    -- Bag monitoring (for detecting when ML receives items)
    self:RegisterEvent("BAG_UPDATE_DELAYED")
    
    -- Track last loot scan
    self.lastLootScan = {}
    self.pendingItems = {}
end

function LootTracker:ENCOUNTER_END(event, encounterID, encounterName, difficultyID, groupSize, success)
    if success == 1 then
        currentBoss = encounterName
        HooligansLoot:Debug("Boss killed: " .. encounterName)
        
        -- Clear boss after 60 seconds (in case of trash loot)
        C_Timer.After(60, function()
            if currentBoss == encounterName then
                currentBoss = nil
            end
        end)
    end
end

function LootTracker:LOOT_OPENED(event, autoLoot)
    if not Utils.IsMasterLooter() then return end
    
    local session = HooligansLoot:GetModule("SessionManager"):GetCurrentSession()
    if not session then
        HooligansLoot:Print("No active session. Start one with /hl session new")
        return
    end
    
    -- Scan loot window
    self.lastLootScan = {}
    local numItems = GetNumLootItems()
    
    for i = 1, numItems do
        local lootIcon, lootName, lootQuantity, currencyID, lootQuality, locked, isQuestItem = GetLootSlotInfo(i)
        local itemLink = GetLootSlotLink(i)
        
        if itemLink and lootQuality >= HooligansLoot.db.profile.settings.minQuality then
            local itemID = Utils.GetItemID(itemLink)
            self.lastLootScan[i] = {
                link = itemLink,
                id = itemID,
                name = lootName,
                quality = lootQuality,
                icon = lootIcon,
                boss = currentBoss or "Unknown",
            }
            HooligansLoot:Debug("Scanned loot slot " .. i .. ": " .. lootName)
        end
    end
end

function LootTracker:LOOT_CLOSED()
    -- Clear last scan (items should be in bags now if looted)
    C_Timer.After(0.5, function()
        self.lastLootScan = {}
    end)
end

function LootTracker:BAG_UPDATE_DELAYED()
    if not Utils.IsMasterLooter() then return end
    
    local session = HooligansLoot:GetModule("SessionManager"):GetCurrentSession()
    if not session then return end
    
    -- Scan bags for new epic+ items with trade timer
    self:ScanBagsForNewItems(session)
end

function LootTracker:ScanBagsForNewItems(session)
    local minQuality = HooligansLoot.db.profile.settings.minQuality
    
    for bagID = 0, NUM_BAG_SLOTS do
        local numSlots = GetContainerNumSlots(bagID)
        for slotID = 1, numSlots do
            local icon, itemCount, locked, quality, readable, lootable, itemLink = GetContainerItemInfo(bagID, slotID)
            
            if itemLink and quality and quality >= minQuality then
                -- Check if this item is already tracked
                local itemGUID = Utils.GenerateItemGUID(itemLink, bagID, slotID)
                
                if not self:IsItemTracked(session, bagID, slotID, itemLink) then
                    -- Check if item is tradeable (has trade timer tooltip)
                    if self:HasTradeTimer(bagID, slotID) then
                        self:AddItem(session, itemLink, bagID, slotID)
                    end
                end
            end
        end
    end
end

function LootTracker:HasTradeTimer(bagID, slotID)
    -- Create tooltip to scan for trade timer text
    local tooltip = CreateFrame("GameTooltip", "HooligansLootScanTooltip", nil, "GameTooltipTemplate")
    tooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
    tooltip:SetBagItem(bagID, slotID)
    
    for i = 1, tooltip:NumLines() do
        local line = _G["HooligansLootScanTooltipTextLeft" .. i]
        if line then
            local text = line:GetText()
            if text and text:find("You may trade this item") then
                return true
            end
        end
    end
    
    return false
end

function LootTracker:IsItemTracked(session, bagID, slotID, itemLink)
    for _, item in ipairs(session.items) do
        if item.bagId == bagID and item.slotId == slotID then
            return true
        end
    end
    return false
end

function LootTracker:AddItem(session, itemLink, bagID, slotID)
    local itemID = Utils.GetItemID(itemLink)
    local itemName, _, itemQuality, _, _, _, _, _, _, itemTexture = GetItemInfo(itemLink)
    
    local item = {
        guid = Utils.GenerateItemGUID(itemLink, bagID, slotID),
        id = itemID,
        link = itemLink,
        name = itemName or "Unknown Item",
        quality = itemQuality or 4,
        icon = itemTexture,
        boss = currentBoss or "Unknown",
        timestamp = time(),
        bagId = bagID,
        slotId = slotID,
        tradeable = true,
        tradeExpires = time() + TRADE_DURATION,
    }
    
    table.insert(session.items, item)
    HooligansLoot:Print("Tracked: " .. itemLink .. " (from " .. item.boss .. ")")
    
    -- Fire callback for UI update
    HooligansLoot.callbacks:Fire("ITEM_ADDED", item)
end

function LootTracker:RemoveItem(session, itemGUID)
    for i, item in ipairs(session.items) do
        if item.guid == itemGUID then
            table.remove(session.items, i)
            HooligansLoot.callbacks:Fire("ITEM_REMOVED", item)
            return true
        end
    end
    return false
end

function LootTracker:UpdateItemLocation(session, itemGUID, newBagID, newSlotID)
    for _, item in ipairs(session.items) do
        if item.guid == itemGUID then
            item.bagId = newBagID
            item.slotId = newSlotID
            return true
        end
    end
    return false
end

-- Manual add for testing
function LootTracker:AddTestItem()
    local session = HooligansLoot:GetModule("SessionManager"):GetCurrentSession()
    if not session then
        HooligansLoot:Print("No active session!")
        return
    end
    
    -- Add a fake item for testing
    local testItem = {
        guid = "test:" .. time(),
        id = 28770, -- Nathrezim Mindblade
        link = "|cffa335ee|Hitem:28770::::::::70:::::|h[Nathrezim Mindblade]|h|r",
        name = "Nathrezim Mindblade",
        quality = 4,
        icon = 135344,
        boss = "Test Boss",
        timestamp = time(),
        bagId = 0,
        slotId = 1,
        tradeable = true,
        tradeExpires = time() + TRADE_DURATION,
    }
    
    table.insert(session.items, testItem)
    HooligansLoot:Print("Added test item: " .. testItem.link)
    HooligansLoot.callbacks:Fire("ITEM_ADDED", testItem)
end
```

---

## Module: SessionManager.lua

```lua
-- Modules/SessionManager.lua
-- Manages loot sessions

local ADDON_NAME, NS = ...
local HooligansLoot = NS.addon
local Utils = NS.Utils

local SessionManager = HooligansLoot:NewModule("SessionManager")

function SessionManager:OnEnable()
    -- Nothing to do on enable
end

function SessionManager:NewSession(name)
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
    
    HooligansLoot:Print("Started new session: " .. name)
    HooligansLoot.callbacks:Fire("SESSION_STARTED", session)
    
    return session
end

function SessionManager:EndSession()
    local session = self:GetCurrentSession()
    if not session then
        HooligansLoot:Print("No active session to end.")
        return
    end
    
    session.status = "ended"
    session.ended = time()
    HooligansLoot.db.profile.currentSessionId = nil
    
    HooligansLoot:Print("Ended session: " .. session.name .. " (" .. #session.items .. " items)")
    HooligansLoot.callbacks:Fire("SESSION_ENDED", session)
end

function SessionManager:GetCurrentSession()
    local sessionId = HooligansLoot.db.profile.currentSessionId
    if not sessionId then return nil end
    return HooligansLoot.db.profile.sessions[sessionId]
end

function SessionManager:GetSession(sessionId)
    return HooligansLoot.db.profile.sessions[sessionId]
end

function SessionManager:GetAllSessions()
    return HooligansLoot.db.profile.sessions
end

function SessionManager:ListSessions()
    local sessions = self:GetAllSessions()
    local count = 0
    
    HooligansLoot:Print("Sessions:")
    for id, session in pairs(sessions) do
        count = count + 1
        local status = session.status == "active" and "|cff00ff00[ACTIVE]|r" or ""
        print(string.format("  %s %s (%d items)", session.name, status, #session.items))
    end
    
    if count == 0 then
        print("  No sessions found. Start one with /hl session new")
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

function SessionManager:SetAward(sessionId, itemGUID, playerName)
    local session = self:GetSession(sessionId)
    if not session then return false end
    
    session.awards[itemGUID] = {
        winner = playerName,
        awarded = false,
        awardedAt = nil,
    }
    
    HooligansLoot.callbacks:Fire("AWARD_SET", session, itemGUID, playerName)
    return true
end

function SessionManager:MarkAwarded(sessionId, itemGUID)
    local session = self:GetSession(sessionId)
    if not session or not session.awards[itemGUID] then return false end
    
    session.awards[itemGUID].awarded = true
    session.awards[itemGUID].awardedAt = time()
    
    HooligansLoot.callbacks:Fire("AWARD_COMPLETED", session, itemGUID)
    return true
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
    
    local items = {}
    for itemGUID, award in pairs(session.awards) do
        if award.winner == playerName and not award.awarded then
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
```

---

## Continue in Next Files...

The remaining modules (Export, Import, TradeManager, Announcer, UI) follow similar patterns. See the individual file templates in this project.

## Testing Checklist

1. [ ] Addon loads without errors
2. [ ] `/hl` shows main frame
3. [ ] `/hl session new` creates session
4. [ ] Looting epic+ items in raid adds them to session
5. [ ] Trade timers display correctly
6. [ ] Export generates valid JSON/CSV
7. [ ] Import parses JSON/CSV correctly
8. [ ] Announce posts to correct channel
9. [ ] Auto-trade prompts when trading with award winner
10. [ ] Data persists across sessions
