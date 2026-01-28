# Existing Addon Research - Gargul & RCLootCouncil

## Overview

This document contains research on two existing loot management addons to inform the design of HOOLIGANS Loot. Both are much more complex than what we need, but contain useful patterns.

## Gargul

**Source**: https://github.com/papa-smurf/Gargul
**CurseForge**: https://www.curseforge.com/wow/addons/gargul (15M+ downloads)

### Relevant Features for Our Use Case

1. **Trade Timer Tracking** (`Classes/TradeTime.lua`)
   - Tracks 2-hour trade window for raid loot
   - Shows countdown timers
   - Double-click to initiate trade

2. **Award History** (`Classes/AwardedLoot.lua`)
   - Stores who got what
   - Exportable data

3. **PackMule Auto-Loot** (`Classes/PackMule.lua`)
   - Auto-loots items to master looter
   - Configurable rules

4. **Trade Window Integration** (`Classes/TradeWindow.lua`)
   - Detects trade window open/close
   - Can auto-add items to trade

5. **Export System**
   - Custom export formats with placeholders like `@ITEMID`, `@ITEMNAME`, `@WOWHEAD`
   - CSV and custom format support

### Gargul File Structure
```
Gargul/
├── Gargul.toc
├── bootstrap.lua           -- Main initialization
├── Classes/
│   ├── AwardedLoot.lua     -- Award tracking
│   ├── PackMule.lua        -- Auto-loot system
│   ├── DroppedLoot.lua     -- Dropped loot detection
│   ├── TradeWindow.lua     -- Trade window hooks
│   ├── TradeTime.lua       -- Trade timer tracking
│   ├── BagInspector.lua    -- Bag scanning
│   ├── Player.lua          -- Player data
│   └── Comm.lua            -- Addon communication
├── Interface/
│   ├── Award/
│   │   ├── Award.lua
│   │   └── Overview.lua
│   ├── TradeTime/
│   │   └── Broadcast.lua
│   └── Importer.lua
└── Libs/                   -- Ace3 libraries
```

### Key Gargul Patterns

#### Trade Timer Storage
```lua
-- Gargul stores trade timers like this:
TradeTime = {
    [itemGUID] = {
        itemLink = "...",
        expiresAt = timestamp,
        bagId = 0,
        slotId = 5,
    }
}
```

#### Award Tracking
```lua
-- Award structure
AwardedLoot = {
    [timestamp] = {
        itemLink = "...",
        itemId = 12345,
        awardedTo = "PlayerName",
        awardedBy = "MasterLooter",
        timestamp = 1234567890,
    }
}
```

---

## RCLootCouncil Classic

**Source**: https://github.com/evil-morfar/RCLootCouncil_Classic
**CurseForge**: https://www.curseforge.com/wow/addons/rclootcouncil-classic (8M+ downloads)

### Architecture

RCLootCouncil Classic is a wrapper/extension of the retail RCLootCouncil (`RCLootCouncil2`), with Classic-specific patches.

### Relevant Components

1. **ML Core** (`ml_core.lua`)
   - Master Looter logic
   - Loot distribution
   - Session management

2. **Loot Table Structure**
   - How items are stored and tracked
   - Session-based organization

3. **Award Later Feature**
   - This is exactly what we need!
   - Allows deferring loot decisions

### RCLootCouncil Data Structures

#### Loot Table Entry
```lua
lootTable[session] = {
    bagged = false,           -- Is item in ML's bags
    baggedInSlot = {bag, slot},
    link = "itemLink",
    ilvl = 200,
    texture = "path",
    equipLoc = "INVTYPE_HEAD",
    typeID = 4,               -- Armor
    subTypeID = 1,            -- Cloth
    classes = 0xFFFF,         -- Bitmask of classes that can use
    isTier = false,
    awarded = false,
}
```

#### Award Entry
```lua
award = {
    date = "15/01/24",
    time = "21:30:45",
    lootWon = "itemLink",
    itemReplaced1 = "itemLink",
    itemReplaced2 = "itemLink",
    instance = "Karazhan",
    boss = "Prince Malchezaar",
    votes = 5,
    response = "Mainspec",
    responseID = 1,
    color = {r, g, b, a},
    class = "WARRIOR",
    isAwardReason = false,
}
```

### RCLootCouncil Communication Protocol

Uses AceComm with prefix "RCLootCouncil":
```lua
-- Message types
"lootTable"     -- Send loot table to council
"response"      -- Player response
"awarded"       -- Item awarded
"offline_award" -- Award made offline
"change_response" -- Change response
```

---

## What We Should Take From Each

### From Gargul
1. **Trade timer tracking pattern** - Simple and effective
2. **Auto-trade concept** - Detect trade window, suggest items
3. **Export format flexibility** - Support multiple formats
4. **Minimal raid member requirements** - Only ML needs addon

### From RCLootCouncil
1. **Session-based organization** - Clean data structure
2. **Award Later workflow** - Proven concept
3. **Loot table structure** - Good metadata to track

### What We DON'T Need
- Voting system (Gargul)
- Council member sync (RCLootCouncil)
- SoftRes integration (Gargul)
- TMB/DFT integration (Gargul)
- GDKP features (Gargul)
- Real-time responses (RCLootCouncil)
- Complex UI frames (both)

---

## Implementation Recommendations

### Keep It Simple

Our addon should be ~500-1000 lines of code total, compared to:
- Gargul: ~20,000+ lines
- RCLootCouncil: ~30,000+ lines

### Minimal Dependencies

Only essential Ace3 libs:
- AceAddon-3.0
- AceEvent-3.0
- AceDB-3.0
- AceConsole-3.0
- AceSerializer-3.0 (for export/import)

### Single-Purpose Modules

```lua
-- Core.lua: ~100 lines
-- Initialize addon, load modules

-- LootTracker.lua: ~150 lines
-- Hook loot events, track items with trade timers

-- SessionManager.lua: ~100 lines
-- Create/end sessions, store data

-- Export.lua: ~100 lines
-- Generate JSON/CSV from session

-- Import.lua: ~100 lines
-- Parse JSON/CSV, populate awards

-- TradeManager.lua: ~150 lines
-- Detect trades, auto-add items

-- Announcer.lua: ~50 lines
-- Post awards to chat

-- UI/MainFrame.lua: ~200 lines
-- Simple list UI
```

### Data Flow

```
LOOT_OPENED
    ↓
Scan loot window
    ↓
Track items looted to ML
    ↓
Store in session with trade timer
    ↓
[Export button] → JSON/CSV to clipboard
    ↓
[External LC decisions]
    ↓
[Import button] ← JSON/CSV from clipboard
    ↓
Populate awards in session
    ↓
[Announce button] → Post to chat
    ↓
TRADE_SHOW → Check for pending items
    ↓
Prompt to add items → Complete trade → Mark awarded
```

---

## TBC Classic Boss List (for Reference)

### Karazhan
- Attumen the Huntsman
- Moroes
- Maiden of Virtue
- Opera Event (Oz/R&J/BBW)
- The Curator
- Shade of Aran
- Terestian Illhoof
- Netherspite
- Chess Event
- Prince Malchezaar
- Nightbane

### Gruul's Lair
- High King Maulgar
- Gruul the Dragonkiller

### Magtheridon's Lair
- Magtheridon

### Serpentshrine Cavern
- Hydross the Unstable
- The Lurker Below
- Leotheras the Blind
- Fathom-Lord Karathress
- Morogrim Tidewalker
- Lady Vashj

### Tempest Keep: The Eye
- Al'ar
- Void Reaver
- High Astromancer Solarian
- Kael'thas Sunstrider

### Hyjal Summit
- Rage Winterchill
- Anetheron
- Kaz'rogal
- Azgalor
- Archimonde

### Black Temple
- High Warlord Naj'entus
- Supremus
- Shade of Akama
- Teron Gorefiend
- Gurtogg Bloodboil
- Reliquary of Souls
- Mother Shahraz
- Illidari Council
- Illidan Stormrage

### Sunwell Plateau
- Kalecgos
- Brutallus
- Felmyst
- Eredar Twins
- M'uru
- Kil'jaeden
