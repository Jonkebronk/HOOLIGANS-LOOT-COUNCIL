# HOOLIGANS Loot - Technical Architecture

Detailed technical documentation for developers and maintainers.

## Overview

HooligansLoot is built on the **Ace3 framework** and follows a modular architecture with clear separation between business logic (Modules) and presentation (UI).

## Directory Structure

```
HooligansLoot/
|-- HooligansLoot.toc    # Addon manifest
|-- Core.lua             # Main initialization, slash commands
|-- Utils.lua            # Shared utility functions
|
|-- Modules/             # Business logic modules
|   |-- Announcer.lua    # Chat message broadcasting
|   |-- Comm.lua         # Inter-player communication
|   |-- Export.lua       # Data serialization (JSON/CSV)
|   |-- Import.lua       # Data deserialization
|   |-- LootTracker.lua  # Boss/loot event handling
|   |-- SessionManager.lua # Session & award state
|   |-- TradeManager.lua # Trade window automation
|   +-- Voting.lua       # Vote state machine
|
|-- UI/                  # User interface frames
|   |-- AwardFrame.lua   # Award distribution queue
|   |-- HistoryFrame.lua # Historical award viewer
|   |-- LootFrame.lua    # Raider response interface
|   |-- MainFrame.lua    # Primary addon window
|   |-- RaidPopup.lua    # Raid entry notification
|   |-- SessionSetupFrame.lua  # Vote configuration
|   |-- SettingsFrame.lua      # Options panel
|   +-- VotingFrame.lua  # Council voting interface
|
|-- Textures/            # Custom artwork
|   +-- logo.tga         # Guild logo (minimap/header)
|
+-- Libs/                # Libraries (embedded)
    |-- LibStub/
    |-- CallbackHandler-1.0/
    |-- AceAddon-3.0/
    |-- AceComm-3.0/
    |-- AceConsole-3.0/
    |-- AceDB-3.0/
    |-- AceEvent-3.0/
    |-- AceSerializer-3.0/
    |-- AceTimer-3.0/
    |-- LibDataBroker-1.1/   # Data broker for minimap
    +-- LibDBIcon-1.0/       # Minimap button library
```

---

## Core Framework

### Ace3 Integration

The addon inherits from multiple Ace3 mixins:

```lua
local HooligansLoot = LibStub("AceAddon-3.0"):NewAddon(ADDON_NAME,
    "AceConsole-3.0",    -- Slash command handling
    "AceEvent-3.0",      -- WoW event registration
    "AceSerializer-3.0", -- Data serialization
    "AceComm-3.0",       -- Addon messaging
    "AceTimer-3.0"       -- Timer management
)
```

### Module System

Modules are registered with the addon and receive lifecycle callbacks:

```lua
local MyModule = HooligansLoot:NewModule("MyModule")

function MyModule:OnEnable()
    -- Called when addon loads
    -- Register events, initialize state
end
```

### Callback System

Custom events use CallbackHandler-1.0 for loose coupling:

```lua
-- Fire an event
HooligansLoot.callbacks:Fire("AWARD_SET", session, itemGUID, winner)

-- Register a handler
HooligansLoot.callbacks.RegisterCallback(self, "AWARD_SET", "OnAwardSet")
```

---

## Data Storage

### Database Structure

All persistent data is stored in `HooligansLootDB` SavedVariables:

```lua
HooligansLootDB = {
    profileKeys = {...},
    profiles = {
        ["CharacterName - RealmName"] = {
            settings = {
                -- User preferences
                announceChannel = "RAID",
                minQuality = 4,
                voteTimeout = 30,
                councilMode = "auto",
                councilList = {},
                autoTradeEnabled = true,
                debug = false,
                ...
            },
            sessions = {
                ["session_1234567890"] = {
                    id = "session_1234567890",
                    name = "Karazhan - 2025-01-15 20:30",
                    created = 1234567890,
                    ended = nil,
                    status = "active",  -- active, ended, completed
                    items = {...},
                    awards = {...},
                    votes = {...}
                }
            },
            currentSessionId = "session_1234567890"
        }
    }
}
```

### Item Structure

```lua
item = {
    guid = "item:12345:0:1:1234567890",  -- Unique identifier
    id = 12345,                           -- WoW item ID
    name = "Epic Sword",
    link = "|cff...|Hitem:12345::...|h[Epic Sword]|h|r",
    quality = 4,                          -- 0-5 (Poor-Legendary)
    icon = "Interface\\Icons\\...",
    boss = "Prince Malchezaar",
    timestamp = 1234567890,
    tradeable = true,
    tradeExpires = 1234575090             -- timestamp + 7200
}
```

### Award Structure

```lua
awards = {
    ["item_guid_here"] = {
        winner = "PlayerName",
        class = "WARRIOR",
        awarded = false,       -- true after trade completes
        awardedAt = nil        -- timestamp when traded
    }
}
```

---

## Module Documentation

### LootTracker

**Purpose:** Detects and captures loot from raid encounters.

**Events Monitored:**
- `ENCOUNTER_END` - Boss kill detection
- `LOOT_OPENED` / `LOOT_CLOSED` - Loot window scanning
- `BAG_UPDATE_DELAYED` - Item received tracking
- `GET_ITEM_INFO_RECEIVED` - Icon cache updates

**Key Functions:**
```lua
LootTracker:OnLootOpened()      -- Scan loot window
LootTracker:TrackLootedItem()   -- Record item to session
LootTracker:RequestItemInfo()   -- Async icon loading
```

### SessionManager

**Purpose:** Manages session lifecycle and award tracking.

**Key Functions:**
```lua
SessionManager:NewSession(name)           -- Create session
SessionManager:EndSession()               -- Mark ended
SessionManager:GetCurrentSession()        -- Active session
SessionManager:SetAward(sid, guid, winner) -- Assign item
SessionManager:MarkAwarded(sid, guid)     -- Complete trade
SessionManager:GetPendingAwards(sid)      -- Untrade items
```

### Voting

**Purpose:** Three-phase voting state machine.

**Vote Status:**
```lua
Voting.Status = {
    COLLECTING = "COLLECTING",  -- Raiders responding
    VOTING = "VOTING",          -- Council deciding
    DECIDED = "DECIDED",        -- Winner selected
    CANCELLED = "CANCELLED"     -- Vote aborted
}
```

**Response Types:**
```lua
Voting.ResponseTypes = {
    BIS = { text = "BiS", color = "00ff00", priority = 6 },
    GREATER = { text = "Greater Upgrade", color = "00cc66", priority = 5 },
    MINOR = { text = "Minor Upgrade", color = "00ccff", priority = 4 },
    OFFSPEC = { text = "Offspec", color = "ff9900", priority = 3 },
    PVP = { text = "PvP", color = "cc66ff", priority = 2 }
}
```

**Key Functions:**
```lua
Voting:StartVote(items, timeout)           -- Initiate vote
Voting:SubmitResponse(voteId, type, note)  -- Raider response
Voting:CastVote(voteId, targetPlayer)      -- Council vote
Voting:AwardWinner(voteId, winner)         -- Finalize
Voting:CountVotes(voteId)                  -- Tally results
```

### Comm

**Purpose:** Distributed communication between raid members.

**Protocol:**
- Prefix: `HLoot`
- Version: 1
- Channel: RAID or WHISPER

**Message Types:**
```lua
MessageTypes = {
    VOTE_START = "VS",       -- ML -> All: Start voting
    VOTE_RESPONSE = "VR",    -- Raider -> ML: Submit response
    VOTE_CAST = "VC",        -- Council -> ML: Cast vote
    VOTE_UPDATE = "VU",      -- ML -> All: Status update
    VOTE_END = "VE",         -- ML -> All: Vote ended
    VOTE_CANCEL = "VX",      -- ML -> All: Vote cancelled
    SYNC_REQUEST = "SR",     -- Request state sync
    SYNC_RESPONSE = "SS",    -- State payload response
    COUNCIL_SYNC = "CS",     -- ML -> All: Council list
    SESSION_SYNC = "SY",     -- ML -> All: Full session data
    ITEM_REMOVE = "IR",      -- ML -> All: Item removed (lightweight)
    ITEM_ADD = "IA"          -- ML -> All: Item added (lightweight)
}
```

**Priority:**
- ALERT priority (real-time): VOTE_*, SESSION_SYNC, ITEM_ADD, ITEM_REMOVE
- NORMAL priority (bulk): SYNC_REQUEST, SYNC_RESPONSE

### Export / Import

**Export Formats:**
- JSON (platform integration)
- CSV (spreadsheet compatible)

**Import Formats:**
- JSON with `items[]` or `awards[]`
- CSV with Player, ItemID columns

---

## Callback Events

### Session Events
```lua
SESSION_STARTED      -- New session created
SESSION_ENDED        -- Session marked ended
SESSION_UPDATED      -- Session data changed
SESSION_DELETED      -- Session removed
SESSION_ACTIVATED    -- Historical session reactivated
SESSION_COMPLETED    -- All awards finished
```

### Item Events
```lua
ITEM_ADDED           -- Item added to session
ITEM_REMOVED         -- Item removed from session
```

### Award Events
```lua
AWARD_SET            -- Winner assigned
AWARD_COMPLETED      -- Trade finished
AWARD_CLEARED        -- Award removed
AWARDS_IMPORTED      -- External awards loaded
```

### Vote Events
```lua
VOTE_STARTED         -- Voting initiated
VOTE_UPDATED         -- Vote state changed
VOTE_RESPONSE_SUBMITTED  -- Local response sent
VOTE_RESPONSE_RECEIVED   -- Other response received
VOTE_CAST_SUBMITTED      -- Local council vote
VOTE_CAST_RECEIVED       -- Other council vote
VOTE_COLLECTION_ENDED    -- Response phase timeout
VOTE_ENDED              -- Winner determined
VOTE_CANCELLED          -- Vote aborted
```

---

## Role-Based User Interface

The addon provides different interfaces for **Master Looter/Raid Leader** vs **Raiders** to keep the raider experience clean and simple.

### Permission Check
```lua
local Voting = HooligansLoot:GetModule("Voting", true)
local isML = Voting and Voting:IsMasterLooter()
```

### MainFrame Role Differences

| Feature | Master Looter | Raiders |
|---------|---------------|---------|
| Header buttons | Auto-Loot, History, Settings | None |
| Session bar | Name, New, Rename | Name only |
| Columns | ITEM, RESPONSES, AWARDED TO, TIMER | ITEM, AWARDED TO |
| Bottom buttons | All (Export, Import, Start Vote, etc.) | Refresh, Open Vote (centered) |
| Item remove button | Visible on hover | Hidden |
| Empty session text | "Use Test Kara to add items" | Empty |

### LootFrame (Vote Response)

- **Position**: Opens to the right of MainFrame (if visible)
- **Footer**: Shows "Total Items: X" + Close button
- **Both roles** see the same response interface

### Implementation Pattern

```lua
function MainFrame:Refresh()
    local Voting = HooligansLoot:GetModule("Voting", true)
    local isML = Voting and Voting:IsMasterLooter()

    -- Show/hide ML-only buttons
    if isML then
        mainFrame.settingsBtn:Show()
        mainFrame.historyBtn:Show()
        mainFrame.testKaraBtn:Show()
        -- ... all ML buttons
    else
        mainFrame.settingsBtn:Hide()
        mainFrame.historyBtn:Hide()
        mainFrame.testKaraBtn:Hide()
        -- Reposition remaining buttons centered
        mainFrame.refreshBtn:SetPoint("BOTTOM", mainFrame.buttonBar, "BOTTOM", -45, 0)
        mainFrame.openVoteBtn:SetPoint("BOTTOM", mainFrame.buttonBar, "BOTTOM", 45, 0)
    end

    -- Show/hide TIMER column header
    if isML then
        mainFrame.colTimer:Show()
    else
        mainFrame.colTimer:Hide()
    end
end
```

### Item Row Remove Button

```lua
row:SetScript("OnEnter", function(self)
    local canRemove = Voting and (Voting:IsMasterLooter() or Voting:IsCouncilMember())
    if canRemove then
        self.removeBtn:Show()
    end
    -- ... highlight effects
end)
```

---

## Lightweight Item Sync

For fast real-time updates when items are added/removed, the addon uses lightweight messages instead of full session broadcasts.

### Message Types
```lua
ITEM_REMOVE = "IR"  -- When ML removes item from session
ITEM_ADD = "IA"     -- When ML adds item to session
```

### Flow

**Item Added:**
```
ML: LootTracker:AddItem(item)
    └─> SessionManager:AddItemToSession(item)
    └─> Comm:SendMessage("ITEM_ADD", itemData, "RAID", nil, "ALERT")

Raiders: Comm:HandleItemAdd(data, sender)
    └─> Add item to local session.items
    └─> Fire "ITEM_ADDED" callback
    └─> UI refreshes instantly
```

**Item Removed:**
```
ML: SessionManager:RemoveItem(itemGUID)
    └─> Remove from session.items
    └─> Comm:SendMessage("ITEM_REMOVE", {itemGUID, sessionId}, "RAID", nil, "ALERT")

Raiders: Comm:HandleItemRemove(data, sender)
    └─> Remove item from local session.items
    └─> Fire "ITEM_REMOVED" callback
    └─> UI refreshes instantly
```

### Benefits
- **Faster sync**: ~100 bytes vs ~2KB for full session
- **ALERT priority**: Bypasses message queue
- **Instant UI update**: No 10-20 second delays

---

## UI Frame Lifecycle

Each UI module follows a consistent pattern:

```lua
local MyFrame = HooligansLoot:NewModule("MyFrame")
local frame = nil  -- Local frame reference

function MyFrame:OnEnable()
    -- Register callbacks
    HooligansLoot.callbacks.RegisterCallback(self, "EVENT", "Refresh")
end

function MyFrame:CreateFrame()
    if frame then return frame end
    -- Create frame once, cache reference
    frame = CreateFrame("Frame", "HooligansMyFrame", UIParent, ...)
    -- Configure frame
    return frame
end

function MyFrame:Show()
    local f = self:CreateFrame()
    f:Show()
    self:Refresh()
end

function MyFrame:Refresh()
    if not frame or not frame:IsShown() then return end
    -- Update UI from current data
end
```

---

## Utility Functions (Utils.lua)

### Item Utilities
```lua
Utils.GetItemID(itemLink)           -- Extract ID from link
Utils.GetItemLink(itemId)           -- Generate basic link
Utils.GenerateItemGUID(item, bag, slot) -- Unique identifier
Utils.GetQualityColor(quality)      -- Quality hex color
```

### Time Utilities
```lua
Utils.FormatTimeRemaining(seconds)  -- "1h 23m" format
Utils.GetTradeTimeRemaining(expires) -- Seconds until untradeable
Utils.FormatTimestamp(timestamp)    -- ISO 8601 format
```

### Player Utilities
```lua
Utils.GetPlayerClass(name)          -- Class from roster
Utils.GetClassColorHex(class)       -- WARRIOR -> "c79c6e"
Utils.GetColoredPlayerName(name, class) -- Colored string
Utils.StripRealm(name)              -- Remove "-Realm"
Utils.GetGroupMembers()             -- Raid/party list
```

### Data Utilities
```lua
Utils.TableCopy(tbl)                -- Deep copy
Utils.TableContains(tbl, value)     -- Check membership
Utils.TableSize(tbl)                -- Count keys
Utils.ToJSON(data)                  -- Serialize
Utils.FromJSON(str)                 -- Deserialize
Utils.ToCSV(data, headers)          -- CSV encode
```

---

## Communication Flow

### Vote Lifecycle

```
1. Master Looter starts vote
   ML: Voting:StartVote(items)
   -> Comm:SendMessage(VOTE_START, voteData, "RAID")

2. Raiders receive and respond
   Raider: OnVoteReceived() -> Show LootFrame
   Raider: SubmitResponse()
   -> Comm:SendMessage(VOTE_RESPONSE, response, "WHISPER", ML)

3. ML collects responses
   ML: OnVoteResponse() -> Update vote.responses
   -> Comm:SendMessage(VOTE_UPDATE, summary, "RAID")

4. Collection ends (timeout or manual)
   ML: EndCollection()
   -> Comm:SendMessage(VOTE_UPDATE, status=VOTING, "RAID")

5. Council votes
   Council: CastVote()
   -> Comm:SendMessage(VOTE_CAST, vote, "WHISPER", ML)

6. ML awards winner
   ML: AwardWinner()
   -> Comm:SendMessage(VOTE_END, winner, "RAID")
   -> SessionManager:SetAward()
```

---

## Classic WoW Compatibility

### API Differences
- No `C_Item.GetItemInfo()` - use `GetItemInfo()`
- Icon loading may require retries
- Master Loot removed in Anniversary - uses raid assist permissions

### Permission Checks
```lua
Utils.IsMasterLooter()  -- Checks raid lead/assist
Utils.IsRaidLeader()    -- UnitIsGroupLeader("player")
Utils.IsRaidAssist()    -- UnitIsGroupAssistant("player")
```

---

## Debug Mode

Enable with `/hl debug`:

```lua
HooligansLoot:Debug(msg)  -- Only prints when debug=true
```

Debug commands:
- `/hl debug session` - Session state dump
- `/hl debug votes` - Active vote details
- `/hl debug clear` - Wipe vote data

---

## Extension Points

### Adding New Response Types

In `Voting.lua`:
```lua
Voting.ResponseTypes.TRANSMOG = {
    text = "Transmog",
    color = "ff69b4",
    priority = 1
}
```

### Adding New Export Formats

In `Export.lua`:
```lua
function Export:ExportToXML(session)
    -- Custom serialization
end
```

### Custom Council Logic

In `Voting.lua`, modify:
```lua
function Voting:IsCouncilMember(playerName)
    -- Custom permission logic
end
```

---

## Performance Considerations

1. **Icon Loading**: Uses async `GetItemInfo()` with retry queue
2. **Frame Creation**: Lazy initialization, frames created on first use
3. **Refresh Throttling**: UI updates check `IsShown()` before work
4. **Callback System**: Loose coupling prevents circular dependencies
5. **Timer Management**: Centralized via AceTimer, cleaned up on hide

---

## UI Refresh Optimization

### The Problem
When multiple players submit vote responses, the UI needs to update. However, calling `RefreshAllUI()` on every response would:
- Close open dropdown menus (frustrating for users mid-selection)
- Cause unnecessary refreshes of frames not visible
- Create a jarring experience during active voting

### Solution: Selective Refresh

**SessionManager** provides two refresh methods:

```lua
-- Full refresh - use sparingly (e.g., after YOUR OWN response)
function SessionManager:RefreshAllUI()
    local MainFrame = HooligansLoot:GetModule("MainFrame", true)
    if MainFrame and MainFrame:IsShown() then MainFrame:Refresh() end

    local VotingFrame = HooligansLoot:GetModule("VotingFrame", true)
    if VotingFrame and VotingFrame:IsShown() then VotingFrame:Refresh() end

    local LootFrame = HooligansLoot:GetModule("LootFrame", true)
    if LootFrame and LootFrame:IsShown() then LootFrame:Refresh() end
end

-- Selective refresh - preserves LootFrame dropdowns
function SessionManager:RefreshResponseDisplays()
    local MainFrame = HooligansLoot:GetModule("MainFrame", true)
    if MainFrame and MainFrame:IsShown() then MainFrame:Refresh() end

    local VotingFrame = HooligansLoot:GetModule("VotingFrame", true)
    if VotingFrame and VotingFrame:IsShown() then VotingFrame:Refresh() end

    -- NOTE: LootFrame intentionally NOT refreshed to preserve dropdowns
end
```

### When to Use Each

| Event | Method | Reason |
|-------|--------|--------|
| Your own response submitted | `RefreshAllUI()` | User expects UI to update after action |
| Other player's response received | `RefreshResponseDisplays()` | Don't interrupt user's dropdown selection |
| Vote started | `RefreshAllUI()` | New vote requires full UI update |
| Vote ended | `RefreshAllUI()` | Final state needs all frames updated |
| Session synced from ML | `RefreshAllUI()` | New session data requires full update |

### IsShown() Pattern

Each UI module implements `IsShown()` to prevent unnecessary work:

```lua
function LootFrame:IsShown()
    return lootFrame and lootFrame:IsShown()
end
```

This allows refresh calls to short-circuit when frames aren't visible.

---

## Session Sync Architecture

### ML -> Raiders Sync Flow

When the Master Looter starts a session or vote, data is broadcast to all raiders:

```
ML: SessionManager:NewSession()
    └─> Comm:BroadcastSession(session)
        └─> SendAddonMessage("SESSION_SYNC", sessionData, "RAID")

Raiders: Comm:OnSessionSync(data, sender)
    └─> SessionManager:OnSessionSynced(data, sender)
        └─> Store as "synced session" (read-only for raiders)
        └─> Fire "SESSION_SYNCED" callback
        └─> RefreshAllUI()
```

### Vote Sync Flow

```
ML: Voting:StartVote(items, timeout)
    └─> Comm:BroadcastVoteStart(voteData)

Raiders: OnVoteStart()
    └─> Store vote locally
    └─> Show LootFrame for response

Raider: Voting:SubmitResponse(voteId, response)
    └─> Comm:SendVoteResponse(response) -> WHISPER to ML
    └─> RefreshAllUI() (own response)

ML: OnVoteResponse(response, sender)
    └─> Store in vote.responses
    └─> Comm:BroadcastVoteUpdate(vote) -> RAID

All: OnVoteUpdate(voteData)
    └─> Merge responses (preserve local responses)
    └─> RefreshResponseDisplays() (not LootFrame!)
```

### Response Preservation

When receiving VOTE_UPDATE broadcasts, local responses are preserved:

```lua
function Voting:OnVoteUpdate(data, sender)
    local existingVote = activeVotes[data.voteId]
    if existingVote and existingVote.responses then
        -- Preserve local responses not yet in broadcast
        for player, response in pairs(existingVote.responses) do
            if not data.responses[player] then
                data.responses[player] = response
            end
        end
    end
    activeVotes[data.voteId] = data
    SessionManager:RefreshResponseDisplays()  -- Not RefreshAllUI!
end
```

---

## Council Sync

When ML starts a vote, council list is broadcast so raiders know who can see responses:

```lua
function Voting:BroadcastCouncil()
    local councilData = {
        mode = settings.councilMode,
        list = settings.councilList,
        masterLooter = UnitName("player")
    }
    Comm:SendMessage("COUNCIL_SYNC", councilData, "RAID")
end
```

Raiders store this and use it for `IsCouncilMember()` checks:
- Council members see all responses
- Non-council raiders only see their own response

---

## Testing

### Simulated Data
```lua
/hl test kara 8    -- Add Karazhan drops
/hl test item      -- Single random item
```

### Debug Output
```lua
/hl debug          -- Toggle verbose logging
/hl debug session  -- Dump session state
/hl debug votes    -- Dump vote state
```

### Solo Testing
The addon supports solo mode for development - votes and responses work without a raid group.

---

## Minimap Button

The addon uses **LibDBIcon-1.0** for the minimap button, which is the standard library for WoW addon minimap integration.

### Setup
```lua
local LDB = LibStub("LibDataBroker-1.1")
local LDBIcon = LibStub("LibDBIcon-1.0")

local dataObj = LDB:NewDataObject("HooligansLoot", {
    type = "launcher",
    icon = "Interface\\AddOns\\HooligansLoot\\Textures\\logo",
    OnClick = function(self, button) ... end,
    OnTooltipShow = function(tooltip) ... end,
})

LDBIcon:Register("HooligansLoot", dataObj, db.minimap)
```

### Database
Position is stored in `db.profile.minimap.minimapPos` (angle in degrees).
