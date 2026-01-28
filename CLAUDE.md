# HOOLIGANS Loot Council - Project Notes

## Repository Location

The actual git repository is located at:
```
C:\Program Files (x86)\World of Warcraft\_anniversary_\Interface\AddOns\HooligansLoot
```

GitHub: https://github.com/Jonkebronk/HOOLIGANSLOOT.git

## Project Structure

This is a World of Warcraft addon for loot council management.

### Core Files
- `Core.lua` - Main addon initialization, slash commands, minimap button
- `Utils.lua` - Utility functions
- `HooligansLoot.toc` - Addon manifest
- `embeds.xml` - Library loading manifest

### Modules (Modules/)
- `LootTracker.lua` - Tracks looted items and trade timers
- `SessionManager.lua` - Manages loot sessions, syncing between ML and raiders
- `Export.lua` - Export functionality (JSON/CSV)
- `Import.lua` - Import functionality
- `TradeManager.lua` - Trade window management
- `Announcer.lua` - Raid announcements
- `Comm.lua` - Addon communication (VOTE_START, VOTE_RESPONSE, etc.)
- `Voting.lua` - Voting system with council member management

### UI Files (UI/)
- `MainFrame.lua` - Main addon window with item list and responses
- `RaidPopup.lua` - Raid popup
- `SettingsFrame.lua` - Settings panel with council management
- `HistoryFrame.lua` - Loot history
- `LootFrame.lua` - Raider response popup (dropdown menus)
- `VotingFrame.lua` - Council voting UI
- `SessionSetupFrame.lua` - Vote setup with timeout slider
- `AwardFrame.lua` - Award frame

### Libraries (Libs/)
- Ace3 framework (AceAddon, AceDB, AceComm, etc.)
- LibDataBroker-1.1 - Data broker for minimap integration
- LibDBIcon-1.0 - Standard minimap button library

### Textures (Textures/)
- `logo.tga` - Guild logo used in minimap button and main frame header

## Slash Commands

- `/hl` - Show main window
- `/hl start` - Start new session
- `/hl vote` - Open vote window (auto-detects context)
- `/hl vote setup` - Open vote setup (ML only)
- `/hl vote council` - Open council voting frame
- `/hl vote respond` - Open raider response frame
- `/hl settings` - Settings panel
- `/hl history` - Loot history
- `/hl export` - Export session data
- `/hl import` - Import awards
- `/hl sync` - Show session sync status (who's synced)
- `/hl sync resync` - Force resync to all raiders (ML only)
- `/hl sync request` - Request sync from ML
- `/hl sync clear` - Clear stale session data
- `/hl debug` - Toggle debug mode
- `/hl debug session` - Debug session state
- `/hl debug votes` - Debug vote state
- `/hl help` - Show all commands

## Key Features

- **Minimap Button**: LibDBIcon integration with custom guild logo
- **Vote Timeout**: Configurable 10 seconds to 5 minutes
- **Council Mode**: Auto (raid assists) or Manual (custom list)
- **Response Visibility**: Non-council members only see own response
- **Session Sync**: ML broadcasts session to raiders
- **Sync Tracking**: ML can see which raiders are synced with current session
- **Resync Button**: ML can force re-broadcast session to all raiders
- **Auto-Clear Stale**: Sessions older than 4 hours are auto-cleared
- **Open Vote Button**: Reopen vote popup if accidentally closed

## Session Sync System

### How Sync Works
1. ML starts session → stored locally in `db.profile.sessions`
2. ML broadcasts `SESSION_SYNC` to group
3. Raiders receive sync → stored in `syncedSession` (in-memory only)
4. Raiders send `SYNC_ACK` back to ML
5. ML tracks who has acknowledged via `syncedPlayers` table

### Troubleshooting Sync Issues
- **Raider has old session**: Use `/hl sync clear` to clear stale data
- **Raiders not receiving**: ML uses "Resync" button or `/hl sync resync`
- **Check sync status**: `/hl sync` shows who's synced and session age

### Stale Session Detection
- Sessions older than 4 hours are auto-cleared on zone change
- Ended sessions are auto-cleared
- `/hl sync clear` manually clears synced session

## Working Directories

Additional working directories configured:
- `C:\Program Files (x86)\World of Warcraft\_anniversary_\Interface\AddOns\HooligansLoot\UI`
- `C:\Program Files (x86)\World of Warcraft\_anniversary_\Interface\AddOns\HooligansLoot\Modules`
- `C:\Program Files (x86)\World of Warcraft\_anniversary_\Interface\AddOns\HooligansLoot`
