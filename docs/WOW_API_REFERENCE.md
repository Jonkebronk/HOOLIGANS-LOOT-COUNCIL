# WoW Classic TBC API Reference

## Interface Version
- **TBC Classic Anniversary**: 20504
- **TOC Format**: `## Interface: 20504`

## Important: Classic vs Retail API Differences

Classic TBC does NOT have many retail APIs. Always use the Classic versions.

### Container/Bag APIs

```lua
-- CLASSIC TBC (USE THESE)
GetContainerNumSlots(bagID)                    -- Returns number of slots in bag
GetContainerItemInfo(bagID, slotID)            -- Returns: icon, itemCount, locked, quality, readable, lootable, itemLink, isFiltered, noValue, itemID
GetContainerItemLink(bagID, slotID)            -- Returns item link string
GetContainerItemID(bagID, slotID)              -- Returns item ID
PickupContainerItem(bagID, slotID)             -- Picks up item (for trading)
UseContainerItem(bagID, slotID)                -- Uses item

-- RETAIL (DO NOT USE)
-- C_Container.GetContainerNumSlots()          -- NOT IN CLASSIC
-- C_Container.GetContainerItemInfo()          -- NOT IN CLASSIC
```

### Bag IDs
```lua
BACKPACK_CONTAINER = 0      -- Main backpack (16 slots base)
BAG_1 = 1                   -- First bag slot
BAG_2 = 2
BAG_3 = 3
BAG_4 = 4
NUM_BAG_SLOTS = 4           -- Number of equipped bag slots
```

### Loot Window APIs

```lua
-- Loot window functions
GetNumLootItems()                              -- Number of items in loot window
GetLootSlotLink(slotID)                        -- Item link for loot slot
GetLootSlotInfo(slotID)                        -- icon, name, quantity, currencyID, quality, locked, isQuestItem, questID, isActive
GetLootSlotType(slotID)                        -- LOOT_SLOT_ITEM, LOOT_SLOT_MONEY, LOOT_SLOT_CURRENCY
LootSlot(slotID)                               -- Loot the item (auto or to self)
LootSlotHasItem(slotID)                        -- Returns true if slot has item

-- Master Looter functions (CLASSIC HAS THESE)
GetMasterLootCandidate(slotID, candidateID)    -- Returns name of candidate for master loot
GetNumMasterLootCandidates()                   -- Number of people who can receive loot
GiveMasterLoot(slotID, candidateID)            -- Give loot to candidate
```

### Trade Window APIs

```lua
-- Trade window functions
GetTradePlayerItemLink(slotID)                 -- Get link of item you're trading (slots 1-6)
GetTradeTargetItemLink(slotID)                 -- Get link of item they're trading
SetTradeItem(slotID, bagID, bagSlotID)         -- Put item in trade slot (PROTECTED - needs hardware event)
PickupContainerItem(bagID, slotID)             -- Pick up item from bag
ClickTradeButton(slotID)                       -- Click trade slot (places picked up item)
AcceptTrade()                                  -- Accept the trade
CloseTrade()                                   -- Close trade window

-- Trade target info
GetTradeTargetInfo()                           -- Returns name, realm of trade target
TradeFrame:IsShown()                           -- Check if trade window is open
```

### Item Info APIs

```lua
-- Get item information
GetItemInfo(itemID or "itemLink")              
-- Returns: itemName, itemLink, itemRarity, itemLevel, itemMinLevel, itemType, 
--          itemSubType, itemStackCount, itemEquipLoc, itemTexture, sellPrice,
--          classID, subclassID, bindType, expacID, setID, isCraftingReagent

GetItemInfoInstant(itemID)                     -- Faster, returns: itemID, itemType, itemSubType, itemEquipLoc, icon, classID, subclassID

-- Item quality constants
LE_ITEM_QUALITY_POOR = 0        -- Gray
LE_ITEM_QUALITY_COMMON = 1      -- White
LE_ITEM_QUALITY_UNCOMMON = 2    -- Green
LE_ITEM_QUALITY_RARE = 3        -- Blue
LE_ITEM_QUALITY_EPIC = 4        -- Purple
LE_ITEM_QUALITY_LEGENDARY = 5   -- Orange
```

### Raid/Group APIs

```lua
-- Raid functions
IsInRaid()                                     -- Returns true if in raid
GetNumGroupMembers()                           -- Number of people in group/raid
UnitInRaid("unit")                             -- Returns raid index or nil
GetRaidRosterInfo(raidIndex)                   
-- Returns: name, rank, subgroup, level, class, fileName, zone, online, isDead, role, isML, combatRole

-- Loot method
GetLootMethod()                                -- Returns "master", "freeforall", "roundrobin", "group", "needbeforegreed"
GetMasterLootCandidate(slot, index)            -- Name of person who can receive master loot
IsMasterLooter()                               -- Returns true if you are ML

-- Unit functions
UnitName("target")                             -- Returns name, realm
UnitClass("unit")                              -- Returns localizedClass, englishClass, classIndex
UnitGUID("unit")                               -- Returns GUID string
```

### Encounter/Boss APIs

```lua
-- Boss detection (TBC Classic)
-- ENCOUNTER_END event provides:
--   encounterID, encounterName, difficultyID, groupSize, success

-- Alternative: BOSS_KILL event (less reliable)
--   encounterID, encounterName

-- Getting boss name from target
UnitName("boss1")                              -- Name of boss unit 1
UnitExists("boss1")                            -- Check if boss unit exists
```

### Chat/Communication APIs

```lua
-- Send chat message
SendChatMessage(msg, chatType, language, target)
-- chatType: "SAY", "YELL", "PARTY", "RAID", "RAID_WARNING", "GUILD", "WHISPER"
-- target: required for "WHISPER"

-- Addon communication
C_ChatInfo.SendAddonMessage(prefix, message, chatType, target)
C_ChatInfo.RegisterAddonMessagePrefix(prefix)
-- OR use AceComm which wraps these
```

## Events Reference

### Loot Events
```lua
"LOOT_READY"                -- Loot window is ready (auto-loot compatible)
"LOOT_OPENED"               -- Loot window opened
  -- arg1: autoLoot (1 if auto-loot enabled)
"LOOT_SLOT_CLEARED"         -- Item was looted from slot
  -- arg1: slotID
"LOOT_SLOT_CHANGED"         -- Loot slot changed
  -- arg1: slotID
"LOOT_CLOSED"               -- Loot window closed

"OPEN_MASTER_LOOT_LIST"     -- ML loot list opened
"UPDATE_MASTER_LOOT_LIST"   -- ML loot list updated
```

### Bag Events
```lua
"BAG_UPDATE"                -- Bag contents changed
  -- arg1: bagID
"BAG_UPDATE_DELAYED"        -- Fired after all BAG_UPDATE events (good for scanning)
"ITEM_PUSH"                 -- Item pushed to bag
  -- arg1: bagID, arg2: iconFileID
"ITEM_LOCKED"               -- Item locked (being moved)
  -- arg1: bagID, arg2: slotID
"ITEM_UNLOCKED"             -- Item unlocked
  -- arg1: bagID, arg2: slotID
```

### Trade Events
```lua
"TRADE_SHOW"                -- Trade window opened
"TRADE_CLOSED"              -- Trade window closed
"TRADE_REQUEST"             -- Someone wants to trade
  -- arg1: playerName
"TRADE_REQUEST_CANCEL"      -- Trade request cancelled
"TRADE_ACCEPT_UPDATE"       -- Trade accept status changed
  -- arg1: playerAccepted, arg2: targetAccepted
"TRADE_PLAYER_ITEM_CHANGED" -- Player's trade item changed
  -- arg1: slotID
"TRADE_TARGET_ITEM_CHANGED" -- Target's trade item changed
  -- arg1: slotID
"TRADE_MONEY_CHANGED"       -- Trade money changed
"TRADE_UPDATE"              -- General trade update
"UI_INFO_MESSAGE"           -- System message (includes trade complete)
  -- arg1: messageType, arg2: message
"UI_ERROR_MESSAGE"          -- Error message
  -- arg1: messageType, arg2: message
```

### Raid/Encounter Events
```lua
"ENCOUNTER_START"           -- Boss encounter started
  -- encounterID, encounterName, difficultyID, groupSize
"ENCOUNTER_END"             -- Boss encounter ended
  -- encounterID, encounterName, difficultyID, groupSize, success
"BOSS_KILL"                 -- Boss killed
  -- encounterID, encounterName

"GROUP_ROSTER_UPDATE"       -- Group/raid composition changed
"RAID_ROSTER_UPDATE"        -- Raid roster changed (deprecated, use GROUP_ROSTER_UPDATE)
"PARTY_LOOT_METHOD_CHANGED" -- Loot method changed
"PARTY_LEADER_CHANGED"      -- Party/raid leader changed
```

## Ace3 Library Usage

### AceAddon
```lua
local addon = LibStub("AceAddon-3.0"):NewAddon("HooligansLoot", 
    "AceConsole-3.0",   -- Slash commands
    "AceEvent-3.0",     -- Event handling
    "AceComm-3.0",      -- Addon communication
    "AceSerializer-3.0" -- Data serialization
)

function addon:OnInitialize()
    -- Called when addon loads
    self.db = LibStub("AceDB-3.0"):New("HooligansLootDB", defaults, true)
end

function addon:OnEnable()
    -- Called when addon is enabled
    self:RegisterEvent("LOOT_OPENED")
end
```

### AceEvent
```lua
-- Register for event
self:RegisterEvent("LOOT_OPENED")
self:RegisterEvent("LOOT_OPENED", "CustomHandler")
self:RegisterEvent("LOOT_OPENED", function(event, ...) end)

-- Event handler (default is same name as event)
function addon:LOOT_OPENED(event, autoLoot)
    -- Handle event
end

-- Unregister
self:UnregisterEvent("LOOT_OPENED")
```

### AceDB Default Structure
```lua
local defaults = {
    profile = {
        -- Per-character settings that can be shared
        settings = {},
        sessions = {},
    },
    char = {
        -- Per-character only settings
    },
    global = {
        -- Account-wide settings
    },
}
```

### AceComm
```lua
-- Register prefix
self:RegisterComm("HoolLoot")

-- Send message
self:SendCommMessage("HoolLoot", serializedData, "RAID")
self:SendCommMessage("HoolLoot", serializedData, "WHISPER", "PlayerName")

-- Receive handler
function addon:OnCommReceived(prefix, message, distribution, sender)
    local success, data = self:Deserialize(message)
end
```

## Useful Utility Functions

```lua
-- Time
time()                      -- Current Unix timestamp
date("%Y-%m-%d %H:%M:%S")   -- Formatted date string
GetServerTime()             -- Server time (more reliable in some cases)
GetTime()                   -- Game time in seconds (with milliseconds)

-- String
strsplit(delimiter, str)    -- Split string
strjoin(delimiter, ...)     -- Join strings
format(formatString, ...)   -- Format string (like printf)

-- Table
tinsert(table, value)       -- Insert into table
tremove(table, index)       -- Remove from table
wipe(table)                 -- Clear table
CopyTable(table)            -- Deep copy table

-- Item link parsing
local itemID = GetItemInfoFromHyperlink(itemLink)
-- Or manually parse: |cff9d9d9d|Hitem:7073::::::::20:257::::::|h[Broken Fang]|h|r
local itemString = string.match(itemLink, "item[%-?%d:]+")
local itemID = string.match(itemLink, "item:(%d+)")
```

## Frame/UI Basics

```lua
-- Create frame
local frame = CreateFrame("Frame", "HooligansLootFrame", UIParent, "BasicFrameTemplateWithInset")
frame:SetSize(400, 300)
frame:SetPoint("CENTER")
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

-- Add title
frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
frame.title:SetPoint("TOP", 0, -5)
frame.title:SetText("HOOLIGANS Loot")

-- Create button
local btn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
btn:SetSize(100, 25)
btn:SetPoint("BOTTOM", 0, 10)
btn:SetText("Export")
btn:SetScript("OnClick", function() 
    -- Handle click
end)

-- Create editbox (for import/export)
local editbox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
editbox:SetSize(350, 20)
editbox:SetPoint("TOP", 0, -30)
editbox:SetAutoFocus(false)
editbox:SetMultiLine(true)

-- Create scroll frame
local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
scrollFrame:SetSize(360, 200)
scrollFrame:SetPoint("TOP", 0, -60)
```
