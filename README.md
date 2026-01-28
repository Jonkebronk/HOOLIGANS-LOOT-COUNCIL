# HOOLIGANS Loot Council

A comprehensive loot council management addon for World of Warcraft Classic Anniversary Edition, designed for the HOOLIGANS guild.

## Overview

HooligansLoot provides a complete loot distribution system with:
- **Automated Loot Tracking** - Captures boss drops automatically
- **Voting System** - Raider responses with council decision making
- **Session Management** - Organize loot by raid instance
- **Trade Automation** - Streamlined item distribution
- **Import/Export** - CSV and JSON support for external tools
- **Role-Based UI** - Different interfaces for ML vs Raiders

## Features

### Minimap Button
- Quick access to the addon via minimap icon
- Left-click to open main window
- Right-click to open settings
- Draggable to any position around minimap
- Uses LibDBIcon for proper integration

### Loot Tracking
- Automatically detects and tracks loot from raid encounters
- Configurable minimum quality threshold (default: Epic)
- Tracks trade window expiration (2-hour timer)
- Boss attribution for each drop
- Real-time sync to all raiders

### Voting System

1. **Response Collection** (Raiders)
   - BiS (Best in Slot)
   - Greater Upgrade
   - Minor Upgrade
   - Offspec
   - PvP

2. **Award Distribution**
   - Winners announced to raid (clean format, no addon prefix)
   - Automatic trade prompts
   - Award tracking and history

### Role-Based Interface

**Raid Leader sees:**
- Full control panel with all buttons
- Auto-Loot, History, Settings in header
- New, Rename session buttons
- Export, Import, Award Announce, Add Item, Start Vote, Test Kara, End Session
- TIMER column (trade timers)
- RESPONSES column (all raider responses)
- Remove button on items

**Raiders see:**
- Clean, minimal interface
- Only Refresh and Open Vote buttons (centered)
- AWARDED TO column only
- No confusing admin messages

### Session Management
- Create sessions per raid instance
- Track multiple items per session
- View session history (RL only)
- Resume or review past sessions

### Real-Time Sync
- Instant item add/remove updates to all raiders
- Lightweight message protocol for fast sync
- Session state synchronized across raid

### Import/Export
- **Export**: JSON or CSV format for external tracking
- **Import**: Load award decisions from spreadsheets or external tools
- Compatible with RCLootCouncil export format

### Trade Management
- Auto-detect trade targets
- Prompt with pending items for that player
- Mark items as awarded after successful trade

### PackMule Auto-Loot (RL only)
- Automatic loot distribution rules
- Configurable by item quality and type
- Disenchanter assignment

## Installation

1. Download or clone this repository
2. Copy the `HooligansLoot` folder to:
   ```
   World of Warcraft\_anniversary_\Interface\AddOns\
   ```
3. Restart WoW or `/reload`

## Quick Start

### For Raid Leader:
1. **Start a Session**: `/hl start` or click "New" in the main window
2. **Track Loot**: Loot is captured automatically from boss kills
3. **Start Voting**: Select items and click "Start Vote"
4. **Collect Responses**: Wait for raiders to respond
5. **Award Items**: Select winner and initiate trade

### For Raiders:
1. **Open Window**: `/hl` to see current session items
2. **Respond to Votes**: Click "Open Vote" when voting is active
3. **Select Preference**: Use dropdown for each item
4. **Wait**: Council will award items

## Commands

| Command | Description |
|---------|-------------|
| `/hl` | Open main window |
| `/hl start` | Create new session and open window |
| `/hl settings` | Open settings panel (RL only) |
| `/hl history` | View loot history (RL only) |
| `/hl export` | Export current session |
| `/hl import` | Import awards |
| `/hl vote` | Open vote setup (ML) / Open vote response (Raider) |
| `/hl pm` | PackMule auto-loot settings |
| `/hl help` | Show all commands |

See [COMMANDS.md](COMMANDS.md) for complete command reference.

## Configuration

Access settings via `/hl settings` or the Settings button (ML only):

### Loot Tracking
- **Minimum Quality**: Filter items by quality (Uncommon -> Legendary)

### Voting
- **Vote Timeout**: Response collection duration (10 seconds to 5 minutes)
- **Council Mode**: Auto (raid assists) or Manual (specific players)
- **Council Members**: Manually configure council list when in manual mode
- **Response Visibility**: Non-council members only see their own response

### Announcements
- **Channel**: SAY, RAID, RAID_WARNING, PARTY, GUILD
- **Auto-Announce**: Announce when awards are set

### Trading
- **Auto-Trade**: Automatically prompt trades
- **Trade Prompt**: Confirm before initiating trades

## User Interface

### Main Window (`/hl`)

**For Raid Leader:**
- Header: Auto-Loot, History, Settings buttons
- Session bar: Name, New, Rename buttons, Status
- Columns: ITEM, RESPONSES, AWARDED TO, TIMER
- Full button bar at bottom
- Stats display (Items, Awarded, Traded, Expired)

**For Raiders:**
- Clean header (no admin buttons)
- Session bar: Name and Status only
- Columns: ITEM, AWARDED TO
- Centered Refresh and Open Vote buttons only

### Loot Frame (Vote Response)
Popup for raiders to submit preferences:
- Opens to the right of main window
- Dropdown menu for each item (selection saved locally)
- Optional note/comment field per item
- Response options with color coding
- Timer showing response deadline
- "Confirm All" button submits all responses with notes and closes window
- Footer with item count, Confirm All, and Close buttons

### History Frame (`/hl history`) - ML Only
Review past awards:
- Filter by session
- Search by player or item
- View award timestamps

## Architecture

```
HooligansLoot/
|-- Core.lua              # Addon initialization, minimap button
|-- Utils.lua             # Utility functions
|-- Modules/
|   |-- Announcer.lua     # Chat announcements (no prefix)
|   |-- Comm.lua          # Player communication (ITEM_ADD, ITEM_REMOVE, etc.)
|   |-- Export.lua        # Data export
|   |-- Import.lua        # Data import
|   |-- LootTracker.lua   # Loot detection with fast sync
|   |-- SessionManager.lua # Session handling
|   |-- TradeManager.lua  # Trade automation
|   |-- Voting.lua        # Voting system
|   +-- PackMule.lua      # Auto-loot distribution
|-- UI/
|   |-- AwardFrame.lua    # Award queue
|   |-- HistoryFrame.lua  # Loot history
|   |-- LootFrame.lua     # Raider responses (positioned right of main)
|   |-- MainFrame.lua     # Main window (role-based UI)
|   |-- RaidPopup.lua     # Raid entry prompt
|   |-- SessionSetupFrame.lua  # Vote setup
|   |-- SettingsFrame.lua # Configuration
|   +-- PackMuleFrame.lua # Auto-loot settings
|-- Textures/             # Custom artwork
|   +-- logo.tga          # Guild logo
+-- Libs/                 # Libraries (Ace3, LibDBIcon, etc.)
```

See [ARCHITECTURE.md](ARCHITECTURE.md) for detailed technical documentation.

## Troubleshooting

### Items not tracking
- Ensure minimum quality is set appropriately
- Check that you're in a raid instance
- Use `/hl debug` to enable logging

### Votes not syncing
- Verify you're in a raid/party group
- Check that the vote initiator is raid lead/assist
- Use `/hl debug votes` to inspect state

### Trade window issues
- Ensure auto-trade is enabled in settings
- Check that items are still tradeable (2-hour window)
- Manually trade if automation fails

## Testing

Use test commands to simulate loot (ML only):
```
/hl test kara      # Add simulated Karazhan drops
/hl test item      # Add a random test item
```

## Version

- **Version**: 1.2.0
- **Interface**: 11503, 11504, 20505 (Classic Anniversary / TBC Anniversary)
- **Author**: Johnny / HOOLIGANS Guild
- **GitHub**: https://github.com/Jonkebronk/HOOLIGANSLOOT

## Recent Changes

### v1.2.0
- **Version display**: Shows addon version in main window header (v1.2.0)
- **Player version tracking**: Player panel shows version for each synced player
- **Version mismatch indicator**: Orange asterisk (*) next to players with different versions
- **Version in tooltips**: Hover over player to see their version (green = same, orange = different)
- **Vote confirmation system**: Replaced timer with player confirmation checkmarks
- **Terminology update**: "Master Looter" renamed to "Raid Leader" throughout
- **Raid Leader highlighting**: (RL) suffix shown in player panel
- **Voting fixes**: Fixed itemGUID broadcast, response matching, confirmation sync

### v1.1.0
- **MainFrame item display fix**: Items now properly show in main window
- **Vote UX improvements**: "Confirm All" submits responses AND closes window
- **No auto-submit**: Dropdown selection saves locally, must click "Confirm All" to send
- **Settings centered**: Settings window always opens in center of screen
- Role-based UI: Raiders see clean minimal interface
- Faster sync: Lightweight ITEM_ADD/ITEM_REMOVE messages
- Cleaner announcements: Removed [HOOLIGANS Loot] prefix
- LootFrame improvements: Taller, positioned right of main window
- MainFrame: Opens at top of screen

## License

MIT License - Feel free to modify for your guild!
