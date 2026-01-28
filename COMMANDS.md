# HOOLIGANS Loot - Command Reference

Complete reference for all slash commands available in the HooligansLoot addon.

## Quick Reference

| Command | Description | Permission |
|---------|-------------|------------|
| `/hl` | Open main window | All |
| `/hl start` | Start new session | ML only |
| `/hl settings` | Open settings panel | ML only |
| `/hl history` | View loot history | ML only |
| `/hl export` | Export current session | All |
| `/hl import` | Import awards | All |
| `/hl announce` | Announce awards to chat | ML only |
| `/hl trade` | Show pending trades | ML only |
| `/hl vote` | Open vote (context-aware) | All |
| `/hl pm` | PackMule settings | ML only |
| `/hl help` | Show command list | All |

## General Commands

### `/hl` or `/hl show`
Opens the main addon window showing the current session, tracked items, and action buttons.

### `/hl start`
Creates a new loot session (auto-named with zone and timestamp) and opens the main window. Equivalent to clicking "New" in the session bar.

### `/hl help`
Displays a list of all available commands in chat.

---

## Session Management

### `/hl session new [name]`
Creates a new loot session. If no name is provided, auto-generates one using the current zone and timestamp.

**Examples:**
```
/hl session new                    # Auto-name: "Karazhan - 2025-01-15 20:30"
/hl session new Tuesday Kara Run   # Custom name
```

### `/hl session end`
Ends the current active session. Items can still be viewed and exported, but new loot won't be added.

### `/hl session list`
Lists all sessions with their names, item counts, and award status.

**Output example:**
```
Sessions:
  Karazhan - 2025-01-15 20:30 [ACTIVE] - 12 items (8/10 awarded)
  Gruul's Lair - 2025-01-14 - 5 items (5/5 awarded)
```

---

## Data Management

### `/hl export`
Opens the export dialog to save session data in JSON or CSV format. Useful for:
- Backing up loot data
- Sharing with external tools
- Platform integration

### `/hl import`
Opens the import dialog to load award decisions from external sources. Supports:
- JSON format (HooligansLoot native)
- CSV format (spreadsheet exports)
- RCLootCouncil compatible format

### `/hl announce`
Announces all pending awards to the configured chat channel (RAID, RAID_WARNING, etc.).

### `/hl trade`
Lists all pending trades (items awarded but not yet traded) in chat.

**Output example:**
```
Pending trades:
  [Tier Token] -> PlayerName
  [Epic Weapon] -> OtherPlayer
```

---

## User Interface

### `/hl settings` or `/hl options`
Opens the settings panel to configure:
- Loot tracking options
- Voting preferences
- Announcement channels
- Trade automation
- Debug settings

### `/hl history`
Opens the history frame to view awarded items across all sessions.

---

## Voting Commands

### `/hl vote` or `/hl vote setup`
Opens the vote setup dialog where you can:
- Select items to put up for vote
- Configure vote timeout
- Start the voting process

**Requirements:** Must have raid assist or be raid leader

### `/hl vote council`
Opens the council voting frame where officers can:
- View raider responses
- Cast votes for candidates
- Award items to winners

**Requirements:** Must be a council member (raid assist or in council list)

### `/hl vote respond`
Opens the raider response frame to submit your preference for items in an active vote.

**Note:** You can also use the "Open Vote" button in the main window to reopen the vote popup if you accidentally closed it.

---

## PackMule Commands (ML Only)

PackMule handles automatic loot distribution during raids.

### `/hl pm` or `/hl packmule`
Opens the PackMule settings frame where you can configure:
- Auto-loot rules by item quality
- Disenchanter assignment
- Item type filters

### `/hl sd <player>` or `/hl setdisenchanter <player>`
Sets the designated disenchanter for auto-looting.

**Example:**
```
/hl sd Enchantername    # Set Enchantername as disenchanter
```

### `/hl cd` or `/hl cleardisenchanter`
Clears the current disenchanter assignment.

---

## Testing & Debug Commands

### `/hl test kara [count]`
Simulates Karazhan boss drops for testing. Adds realistic test items to the current session.

**Examples:**
```
/hl test kara        # Add 8 random Karazhan drops
/hl test kara 5      # Add 5 random Karazhan drops
```

### `/hl test item`
Adds a single random test item to the current session.

### `/hl debug`
Toggles debug mode on/off. When enabled, detailed logging appears in chat for troubleshooting.

### `/hl debug session`
Prints detailed information about the current session:
- Session ID and name
- Item count
- Vote state
- First few items

### `/hl debug votes`
Prints detailed information about active votes:
- Vote IDs and status
- Response counts
- Player responses

### `/hl debug clear`
Clears all active votes. Use with caution - this removes vote data from memory.

---

## Alternative Slash Command

All commands can also be accessed via `/hooligans` instead of `/hl`:
```
/hooligans
/hooligans start
/hooligans settings
```

---

## Command Permissions

### Master Looter / Raid Leader Commands

| Command | Description |
|---------|-------------|
| `/hl start` | Create new session |
| `/hl settings` | Open settings panel |
| `/hl history` | View loot history |
| `/hl vote` | Open vote setup |
| `/hl vote setup` | Open vote setup |
| `/hl vote council` | Open council voting frame |
| `/hl test kara` | Add test items (for testing) |
| `/hl test item` | Add single test item |
| `/hl pm` | PackMule auto-loot settings |
| `/hl sd <player>` | Set disenchanter |
| `/hl cd` | Clear disenchanter |
| `/hl debug *` | All debug commands |

### Raider Commands

| Command | Description |
|---------|-------------|
| `/hl` | Open main window (minimal interface) |
| `/hl vote` | Open vote response popup |
| `/hl vote respond` | Open vote response popup |
| `/hl export` | Export session data |
| `/hl import` | Import awards |
| `/hl help` | Show command list |

### UI Differences

**Master Looter sees:**
- Full button bar (New, Rename, Export, Import, Start Vote, Test Kara, etc.)
- Auto-Loot, History, Settings buttons in header
- TIMER column showing trade window expiration
- RESPONSES column showing raider preferences
- Remove button on items (hover)

**Raiders see:**
- Clean minimal interface
- Only Refresh and Open Vote buttons (centered)
- AWARDED TO column only
- No admin controls or test buttons

---

## Tips

1. **Quick Start**: Use `/hl start` at the beginning of a raid to create a session and open the UI in one command.

2. **During Raid**: Leave the main window open to see items as they drop. Use `/hl vote` to initiate voting.

3. **After Raid**: Use `/hl export` to save data, then `/hl import` after LC decisions are made externally.

4. **Troubleshooting**: Enable debug mode with `/hl debug` to see detailed logging, then use `/hl debug session` or `/hl debug votes` for specific information.
