# HOOLIGANS Loot - Project Specification

## Overview

A lightweight World of Warcraft addon for Classic TBC Anniversary (Interface 20504) designed for the HOOLIGANS guild's "Award Later" loot council workflow.

## Core Workflow

```
DURING RAID                    AFTER RAID                     BACK IN-GAME
┌─────────────┐               ┌──────────────┐               ┌──────────────┐
│ ML collects │   Export      │ Guild        │   Import      │ Announce     │
│ all loot to │ ──────────>   │ Platform     │ ──────────>   │ winners &    │
│ self        │   (JSON/CSV)  │ LC decisions │   (JSON/CSV)  │ Auto-trade   │
└─────────────┘               └──────────────┘               └──────────────┘
```

### Phase 1: During Raid
- Master Looter (ML) loots all items to themselves
- Addon tracks what dropped, from which boss, timestamp
- Tracks 2-hour trade window timer per item
- Simple UI showing collected loot

### Phase 2: Export (After Raid)
- Export collected loot to JSON or CSV format
- Format compatible with external guild platform/website
- Include: itemID, itemLink, itemName, boss, timestamp, bagSlot

### Phase 3: External Loot Council
- Decisions made on guild website/Discord
- Not part of this addon

### Phase 4: Import & Distribute
- Import decisions (itemID -> playerName mapping)
- Announce winners in raid/guild chat
- Track who needs to receive what
- Auto-trade feature: when trading with winner, auto-add their items

## Target Game Version

- **WoW Classic TBC Anniversary**
- **Interface Version**: 20504
- **Master Looter system**: YES (available in Classic)
- **Trade window timer**: 2 hours for raid loot

## Key Differences from Existing Addons

### vs RCLootCouncil Classic
- NO in-game voting UI
- NO real-time council communication
- NO response collection from raiders
- SIMPLER - just track, export, import, distribute

### vs Gargul
- NO GDKP/bidding features
- NO SoftRes integration
- NO TMB integration
- FOCUSED on "Award Later" workflow only

## Technical Requirements

### Dependencies (Embedded)
- Ace3 (AceAddon, AceEvent, AceComm, AceSerializer, AceDB, AceConsole)
- LibStub
- CallbackHandler

### SavedVariables
```lua
HooligansLootDB = {
    profile = {
        sessions = {}, -- Raid sessions with loot data
        settings = {
            announceChannel = "RAID",
            exportFormat = "json",
            autoTradeEnabled = true,
        }
    }
}
```

### Data Structures

#### LootSession
```lua
{
    id = "session_timestamp",
    name = "Karazhan - 2024-01-15",
    created = timestamp,
    status = "active|exported|completed",
    items = { -- Array of LootItem
        [1] = LootItem,
        [2] = LootItem,
    },
    awards = { -- Filled after import
        [itemGUID] = {
            winner = "PlayerName",
            awarded = false, -- becomes true after trade
        }
    }
}
```

#### LootItem
```lua
{
    guid = "item:12345:...",  -- Unique item identifier
    id = 12345,               -- Item ID
    link = "|cff...|h[Item]|h|r",
    name = "Tier Token",
    quality = 4,              -- 4 = Epic
    boss = "Prince Malchezaar",
    timestamp = 1234567890,
    bagId = 0,
    slotId = 5,
    tradeable = true,
    tradeExpires = 1234567890 + 7200, -- 2 hours
}
```

## Slash Commands

- `/hl` or `/hooligans` - Open main UI
- `/hl session new [name]` - Start new loot session
- `/hl session end` - End current session
- `/hl export` - Export current session
- `/hl import` - Open import dialog
- `/hl announce` - Announce all pending awards
- `/hl trade` - Show items pending trade

## UI Requirements

### Main Frame
- Session list (left panel)
- Current session loot (main area)
- Buttons: New Session, Export, Import, Announce

### Session View
- List of items with icons, names, boss source
- Trade timer countdown (green > yellow > red)
- Award status (pending/awarded)
- Winner name (after import)

### Export Dialog
- Format selector (JSON/CSV)
- Copy-to-clipboard button
- Preview area

### Import Dialog
- Paste area for data
- Validation feedback
- Import button

## Events to Hook

```lua
-- Loot tracking
"LOOT_OPENED"           -- Loot window opened
"LOOT_SLOT_CLEARED"     -- Item looted
"LOOT_CLOSED"           -- Loot window closed

-- Boss detection
"ENCOUNTER_END"         -- Boss killed (name, success)
"BOSS_KILL"             -- Alternative boss detection

-- Bag scanning
"BAG_UPDATE"            -- Bag contents changed
"ITEM_PUSH"             -- Item added to bag

-- Trade window
"TRADE_SHOW"            -- Trade window opened
"TRADE_PLAYER_ITEM_CHANGED" -- Item added to trade
"TRADE_ACCEPT_UPDATE"   -- Trade accepted
"TRADE_CLOSED"          -- Trade window closed
"UI_INFO_MESSAGE"       -- Trade completed message

-- Raid info
"GROUP_ROSTER_UPDATE"   -- Raid composition changed
```

## Export Format Examples

### JSON Export
```json
{
    "session": "Karazhan - 2024-01-15",
    "guild": "HOOLIGANS",
    "exported": "2024-01-15T23:45:00Z",
    "items": [
        {
            "id": 28770,
            "name": "Nathrezim Mindblade",
            "link": "...",
            "boss": "Prince Malchezaar",
            "quality": 4
        }
    ]
}
```

### CSV Export
```csv
itemId,itemName,boss,quality,timestamp
28770,Nathrezim Mindblade,Prince Malchezaar,4,1705362300
28772,Sunfury Bow of the Phoenix,Prince Malchezaar,4,1705362300
```

## Import Format Examples

### JSON Import
```json
{
    "awards": [
        {"itemId": 28770, "winner": "Thunderfury"},
        {"itemId": 28772, "winner": "Legolas"}
    ]
}
```

### CSV Import
```csv
itemId,winner
28770,Thunderfury
28772,Legolas
```

## Auto-Trade Feature

When ML opens trade window with a player:
1. Check if player has pending items to receive
2. If yes, show prompt: "Add [Item] to trade? (Y/N)"
3. On confirm, automatically add item to trade window
4. Mark item as awarded after successful trade

## Announcement Format

```
[HOOLIGANS Loot] Awards from Karazhan:
[Nathrezim Mindblade] -> Thunderfury
[Sunfury Bow of the Phoenix] -> Legolas
[Helm of the Fallen Champion] -> Swiftheal
```

## File Structure

```
HooligansLoot/
├── HooligansLoot.toc
├── embeds.xml
├── Core.lua              -- Main addon initialization
├── Utils.lua             -- Helper functions
├── Modules/
│   ├── LootTracker.lua   -- Track looted items
│   ├── SessionManager.lua -- Manage loot sessions
│   ├── Export.lua        -- Export functionality
│   ├── Import.lua        -- Import functionality
│   ├── TradeManager.lua  -- Auto-trade handling
│   └── Announcer.lua     -- Chat announcements
├── UI/
│   ├── MainFrame.lua     -- Main addon window
│   ├── SessionView.lua   -- Session/loot display
│   ├── ExportDialog.lua  -- Export UI
│   └── ImportDialog.lua  -- Import UI
└── Libs/                 -- Ace3 libraries
```

## Development Notes

### Testing Without Raid
- Add `/hl test` command to simulate loot events
- Add test items to session manually

### Classic TBC API Considerations
- Use `GetContainerItemInfo()` not `C_Container` (that's retail)
- Use `GetLootSlotLink()` for loot window items
- Master Looter APIs: `GetMasterLootCandidate()`, `GiveMasterLoot()`
- Trade APIs: `PickupContainerItem()`, `ClickTradeButton()`

### Item GUID in Classic
- Classic doesn't have true item GUIDs like retail
- Use combination of: itemID + bagID + slotID + timestamp
- Or use item link which includes unique instance data
