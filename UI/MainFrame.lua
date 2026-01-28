-- UI/MainFrame.lua
-- Main addon window

local ADDON_NAME, NS = ...
local HooligansLoot = NS.addon
local Utils = NS.Utils

local MainFrame = HooligansLoot:NewModule("MainFrame")

-- Frame references
local mainFrame = nil
local itemRows = {}
local updateTimer = nil
local isRefreshing = false  -- Guard against recursive refresh

-- Constants
local ROW_HEIGHT = 50
local MAX_VISIBLE_ROWS = 8
local PLAYER_PANEL_WIDTH = 160
local FRAME_WIDTH = 850 + PLAYER_PANEL_WIDTH
local FRAME_HEIGHT = 550

-- Player panel references
local playerRows = {}

function MainFrame:OnEnable()
    HooligansLoot:Debug("MainFrame:OnEnable - Registering callbacks")

    -- Register for callbacks
    HooligansLoot.RegisterCallback(self, "ITEM_ADDED", "Refresh")
    HooligansLoot.RegisterCallback(self, "ITEM_REMOVED", "Refresh")
    HooligansLoot.RegisterCallback(self, "SESSION_STARTED", "Refresh")
    HooligansLoot.RegisterCallback(self, "SESSION_ENDED", "Refresh")
    HooligansLoot.RegisterCallback(self, "SESSION_UPDATED", "Refresh") -- For icon updates
    HooligansLoot.RegisterCallback(self, "SESSION_SYNCED", "Refresh")  -- When session synced from ML
    HooligansLoot.RegisterCallback(self, "AWARD_SET", "Refresh")
    HooligansLoot.RegisterCallback(self, "AWARD_COMPLETED", "Refresh")
    HooligansLoot.RegisterCallback(self, "AWARDS_IMPORTED", "Refresh")
    -- Vote callbacks
    HooligansLoot.RegisterCallback(self, "VOTE_STARTED", "Refresh")
    HooligansLoot.RegisterCallback(self, "VOTE_UPDATED", "OnVoteUpdated")
    HooligansLoot.RegisterCallback(self, "VOTE_RESPONSE_SUBMITTED", "OnVoteUpdated")  -- When you submit a response
    HooligansLoot.RegisterCallback(self, "VOTE_RESPONSE_RECEIVED", "OnVoteUpdated")   -- When others submit responses
    HooligansLoot.RegisterCallback(self, "VOTE_COLLECTION_ENDED", "OnVoteUpdated")
    HooligansLoot.RegisterCallback(self, "VOTE_ENDED", "Refresh")
    HooligansLoot.RegisterCallback(self, "VOTE_CONFIRMED", "OnVoteConfirmed")
    -- Sync callbacks
    HooligansLoot.RegisterCallback(self, "PLAYER_SYNCED", "OnPlayerSynced")

    HooligansLoot:Debug("MainFrame:OnEnable - Callbacks registered")
end

function MainFrame:OnVoteUpdated(event, voteId)
    HooligansLoot:Debug("MainFrame:OnVoteUpdated triggered for " .. tostring(voteId))
    -- Force refresh if frame is shown
    if mainFrame and mainFrame:IsShown() then
        HooligansLoot:Debug("MainFrame refreshing...")
        self:Refresh()
    else
        HooligansLoot:Debug("MainFrame not shown, skipping refresh")
    end
end

function MainFrame:OnPlayerSynced(event, playerName, data)
    -- Refresh player panel when someone syncs
    if mainFrame and mainFrame:IsShown() then
        self:RefreshPlayerPanel()
    end
end

function MainFrame:OnVoteConfirmed(event, playerName)
    -- Refresh player panel when someone confirms their vote
    if mainFrame and mainFrame:IsShown() then
        self:RefreshPlayerPanel()
    end
end

function MainFrame:CreateFrame()
    if mainFrame then return mainFrame end

    -- Main frame with transparent background like Gargul
    local frame = CreateFrame("Frame", "HooligansLootMainFrame", UIParent, "BackdropTemplate")
    frame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    frame:SetPoint("TOP", UIParent, "TOP", 0, -50)  -- Position at top of screen
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("HIGH")
    frame:Hide()

    -- Transparent backdrop like Gargul
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        edgeSize = 20,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0.08, 0.08, 0.1, 0.85)
    frame:SetBackdropBorderColor(0.6, 0.5, 0.3, 1)

    -- === PLAYER SYNC PANEL (Left side) ===
    local playerPanel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    playerPanel:SetPoint("TOPLEFT", 8, -56)
    playerPanel:SetPoint("BOTTOMLEFT", 8, 8)
    playerPanel:SetWidth(PLAYER_PANEL_WIDTH - 10)
    playerPanel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    playerPanel:SetBackdropColor(0.05, 0.05, 0.08, 0.9)
    playerPanel:SetBackdropBorderColor(0.3, 0.3, 0.4, 1)
    frame.playerPanel = playerPanel

    -- Player panel title
    local playerPanelTitle = playerPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    playerPanelTitle:SetPoint("TOP", 0, -8)
    playerPanelTitle:SetText("|cffffcc00Raid Members|r")
    frame.playerPanelTitle = playerPanelTitle

    -- Sync count text
    local syncCount = playerPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    syncCount:SetPoint("TOP", playerPanelTitle, "BOTTOM", 0, -2)
    syncCount:SetText("")
    frame.syncCount = syncCount

    -- Player list scroll frame
    local playerScrollFrame = CreateFrame("ScrollFrame", "HooligansLootPlayerScroll", playerPanel, "UIPanelScrollFrameTemplate")
    playerScrollFrame:SetPoint("TOPLEFT", 5, -38)
    playerScrollFrame:SetPoint("BOTTOMRIGHT", -25, 5)
    frame.playerScrollFrame = playerScrollFrame

    -- Player list content frame
    local playerContent = CreateFrame("Frame", nil, playerScrollFrame)
    playerContent:SetSize(PLAYER_PANEL_WIDTH - 40, 1)
    playerScrollFrame:SetScrollChild(playerContent)
    frame.playerContent = playerContent

    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)

    -- Settings button (gear icon) - ML only
    local settingsBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    settingsBtn:SetSize(80, 22)
    settingsBtn:SetPoint("TOPRIGHT", -35, -15)
    settingsBtn:SetText("Settings")
    settingsBtn:SetScript("OnClick", function()
        HooligansLoot:ShowSettings()
    end)
    frame.settingsBtn = settingsBtn

    -- History button - ML only
    local historyBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    historyBtn:SetSize(80, 22)
    historyBtn:SetPoint("RIGHT", settingsBtn, "LEFT", -5, 0)
    historyBtn:SetText("History")
    historyBtn:SetScript("OnClick", function()
        HooligansLoot:ShowHistoryFrame()
    end)
    frame.historyBtn = historyBtn

    -- Make closable with Escape
    tinsert(UISpecialFrames, "HooligansLootMainFrame")

    -- Title bar background (taller for logo)
    local titleBg = frame:CreateTexture(nil, "ARTWORK")
    titleBg:SetPoint("TOPLEFT", 4, -4)
    titleBg:SetPoint("TOPRIGHT", -4, -4)
    titleBg:SetHeight(50)
    titleBg:SetColorTexture(0.15, 0.12, 0.08, 0.9)

    -- Guild logo (custom texture)
    local logo = frame:CreateTexture(nil, "OVERLAY")
    logo:SetSize(44, 44)
    logo:SetPoint("TOPLEFT", 12, -6)
    logo:SetTexture("Interface\\AddOns\\HooligansLoot\\Textures\\logo")
    frame.logo = logo

    -- Title (next to logo, centered in header)
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.title:SetPoint("LEFT", logo, "RIGHT", 8, 6)
    frame.title:SetText("|cffffffffHOOLIGANS Loot Council|r")

    -- Version text (below title)
    local addonVersion = Utils.GetAddonVersion()
    frame.versionText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.versionText:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -6)
    frame.versionText:SetText("|cffaaaaaa v" .. addonVersion .. "|r")

    -- Session info bar (styled box) - offset for player panel
    local sessionBar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    sessionBar:SetPoint("TOPLEFT", PLAYER_PANEL_WIDTH + 5, -56)
    sessionBar:SetPoint("TOPRIGHT", -10, -56)
    sessionBar:SetHeight(32)
    sessionBar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    sessionBar:SetBackdropColor(0.1, 0.1, 0.15, 0.9)
    sessionBar:SetBackdropBorderColor(0.3, 0.3, 0.4, 1)
    frame.sessionBar = sessionBar

    -- Session name (left side, prominent)
    sessionBar.name = sessionBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    sessionBar.name:SetPoint("LEFT", 10, 0)
    sessionBar.name:SetText("No active session")
    sessionBar.name:SetTextColor(1, 0.82, 0)

    -- Session status badge (right side)
    sessionBar.status = sessionBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sessionBar.status:SetPoint("RIGHT", -10, 0)

    -- New Session button (right of name)
    local newSessionBtn = CreateFrame("Button", nil, sessionBar, "UIPanelButtonTemplate")
    newSessionBtn:SetSize(60, 22)
    newSessionBtn:SetPoint("LEFT", sessionBar.name, "RIGHT", 15, 0)
    newSessionBtn:SetText("New")
    newSessionBtn:SetScript("OnClick", function()
        HooligansLoot:GetModule("SessionManager"):NewSession()
        MainFrame:Refresh()
    end)
    sessionBar.newBtn = newSessionBtn

    -- Rename button
    local renameBtn = CreateFrame("Button", nil, sessionBar, "UIPanelButtonTemplate")
    renameBtn:SetSize(60, 22)
    renameBtn:SetPoint("LEFT", newSessionBtn, "RIGHT", 5, 0)
    renameBtn:SetText("Rename")
    renameBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Rename Session")
        GameTooltip:Show()
    end)
    renameBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    renameBtn:SetScript("OnClick", function()
        MainFrame:ShowRenameDialog()
    end)
    sessionBar.renameBtn = renameBtn

    -- Column headers - moved down for logo
    local headerBar = CreateFrame("Frame", nil, frame)
    headerBar:SetPoint("TOPLEFT", PLAYER_PANEL_WIDTH + 5, -93)
    headerBar:SetPoint("TOPRIGHT", -30, -93)
    headerBar:SetHeight(20)

    local colItem = headerBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    colItem:SetPoint("LEFT", 5, 0)
    colItem:SetText("ITEM")
    colItem:SetTextColor(0.9, 0.8, 0.5)

    local colResponses = headerBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    colResponses:SetPoint("LEFT", 270, 0)
    colResponses:SetWidth(180)
    colResponses:SetJustifyH("LEFT")
    colResponses:SetText("RESPONSES")
    colResponses:SetTextColor(0.9, 0.8, 0.5)
    frame.colResponses = colResponses  -- Store reference for visibility toggle

    local colAwarded = headerBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    colAwarded:SetPoint("RIGHT", -200, 0)
    colAwarded:SetWidth(100)
    colAwarded:SetJustifyH("CENTER")
    colAwarded:SetText("AWARDED TO")
    colAwarded:SetTextColor(0.9, 0.8, 0.5)

    local colTimer = headerBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    colTimer:SetPoint("RIGHT", -40, 0)
    colTimer:SetWidth(80)
    colTimer:SetJustifyH("CENTER")
    colTimer:SetText("TIMER")
    colTimer:SetTextColor(0.9, 0.8, 0.5)
    frame.colTimer = colTimer  -- Store reference to show/hide for raiders

    -- Divider line - moved down for logo
    local divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", PLAYER_PANEL_WIDTH + 5, -113)
    divider:SetPoint("TOPRIGHT", -10, -113)
    divider:SetHeight(1)
    divider:SetColorTexture(0.3, 0.3, 0.3, 1)

    -- Scroll frame for items - moved down for logo
    local scrollFrame = CreateFrame("ScrollFrame", "HooligansLootItemScroll", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", PLAYER_PANEL_WIDTH + 5, -118)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 80)
    frame.scrollFrame = scrollFrame

    -- Scroll child (content frame)
    local content = CreateFrame("Frame", nil, scrollFrame)
    -- Calculate width: FRAME_WIDTH(1010) - left offset(165) - right offset(30) = 815
    content:SetSize(815, 1)
    scrollFrame:SetScrollChild(content)
    frame.content = content

    -- Bottom divider
    local bottomDivider = frame:CreateTexture(nil, "ARTWORK")
    bottomDivider:SetPoint("BOTTOMLEFT", PLAYER_PANEL_WIDTH + 5, 75)
    bottomDivider:SetPoint("BOTTOMRIGHT", -10, 75)
    bottomDivider:SetHeight(1)
    bottomDivider:SetColorTexture(0.3, 0.3, 0.3, 1)

    -- Button bar at bottom
    local buttonBar = CreateFrame("Frame", nil, frame)
    buttonBar:SetPoint("BOTTOMLEFT", PLAYER_PANEL_WIDTH + 5, 8)
    buttonBar:SetPoint("BOTTOMRIGHT", -10, 8)
    buttonBar:SetHeight(55)
    frame.buttonBar = buttonBar

    -- Stats display (top of button bar)
    frame.stats = buttonBar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.stats:SetPoint("TOP", 0, 0)
    frame.stats:SetJustifyH("CENTER")

    -- Button row - compact layout
    local btnHeight = 26
    local btnSpacing = 2

    -- ML-only buttons (will be hidden for raiders)
    -- Left side: Export, Import, Announce, Add, Vote
    local exportBtn = CreateFrame("Button", nil, buttonBar, "UIPanelButtonTemplate")
    exportBtn:SetSize(55, btnHeight)
    exportBtn:SetPoint("BOTTOMLEFT", 0, 0)
    exportBtn:SetText("Export")
    exportBtn:SetScript("OnClick", function()
        HooligansLoot:ShowExportDialog()
    end)
    frame.exportBtn = exportBtn

    local importBtn = CreateFrame("Button", nil, buttonBar, "UIPanelButtonTemplate")
    importBtn:SetSize(55, btnHeight)
    importBtn:SetPoint("LEFT", exportBtn, "RIGHT", btnSpacing, 0)
    importBtn:SetText("Import")
    importBtn:SetScript("OnClick", function()
        HooligansLoot:ShowImportDialog()
    end)
    frame.importBtn = importBtn

    local announceBtn = CreateFrame("Button", nil, buttonBar, "UIPanelButtonTemplate")
    announceBtn:SetSize(70, btnHeight)
    announceBtn:SetPoint("LEFT", importBtn, "RIGHT", btnSpacing, 0)
    announceBtn:SetText("Announce")
    announceBtn:SetScript("OnClick", function()
        HooligansLoot:AnnounceAwardsWithRaidWarning()
    end)
    announceBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Announce Awards")
        GameTooltip:AddLine("Announce awarded items in raid", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    announceBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.announceBtn = announceBtn

    local addItemBtn = CreateFrame("Button", nil, buttonBar, "UIPanelButtonTemplate")
    addItemBtn:SetSize(50, btnHeight)
    addItemBtn:SetPoint("LEFT", announceBtn, "RIGHT", btnSpacing, 0)
    addItemBtn:SetText("Add")
    addItemBtn:SetScript("OnClick", function()
        MainFrame:ShowAddItemDialog()
    end)
    addItemBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Add Item")
        GameTooltip:AddLine("Manually add an item to the session", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    addItemBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.addItemBtn = addItemBtn

    -- Start Vote button
    local startVoteBtn = CreateFrame("Button", nil, buttonBar, "UIPanelButtonTemplate")
    startVoteBtn:SetSize(50, btnHeight)
    startVoteBtn:SetPoint("LEFT", addItemBtn, "RIGHT", btnSpacing, 0)
    startVoteBtn:SetText("Vote")
    startVoteBtn:SetScript("OnClick", function()
        local SessionSetupFrame = HooligansLoot:GetModule("SessionSetupFrame", true)
        if SessionSetupFrame then
            SessionSetupFrame:Show()
        end
    end)
    startVoteBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Start Vote")
        GameTooltip:AddLine("Select items to send for voting", 1, 1, 1, true)
        GameTooltip:AddLine("Raiders can respond with Need/Greed/Minor/Pass", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Council members can then vote on winners", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    startVoteBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.startVoteBtn = startVoteBtn

    -- Resync button (ML only - force resync to all raiders)
    local resyncBtn = CreateFrame("Button", nil, buttonBar, "UIPanelButtonTemplate")
    resyncBtn:SetSize(55, btnHeight)
    resyncBtn:SetPoint("LEFT", startVoteBtn, "RIGHT", btnSpacing, 0)
    resyncBtn:SetText("Resync")
    resyncBtn:SetScript("OnClick", function()
        local SessionManager = HooligansLoot:GetModule("SessionManager")
        SessionManager:ForceResync()
    end)
    resyncBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Force Resync")
        GameTooltip:AddLine("Re-broadcast session to all raiders", 1, 1, 1, true)
        GameTooltip:AddLine("Use if a raider has old/stale session data", 0.8, 0.8, 0.8, true)
        local SessionManager = HooligansLoot:GetModule("SessionManager")
        local status = SessionManager:GetSyncStatus()
        if status then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(string.format("Synced: %d/%d players", #status.syncedPlayers, status.totalRaidMembers), 0, 1, 0)
        end
        GameTooltip:Show()
    end)
    resyncBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.resyncBtn = resyncBtn

    -- Right side buttons (anchored from right edge)
    -- End, Test, Open Vote
    local endSessionBtn = CreateFrame("Button", nil, buttonBar, "UIPanelButtonTemplate")
    endSessionBtn:SetSize(50, btnHeight)
    endSessionBtn:SetPoint("BOTTOMRIGHT", 0, 0)
    endSessionBtn:SetText("End")
    endSessionBtn:SetScript("OnClick", function()
        HooligansLoot:GetModule("SessionManager"):EndSession()
        MainFrame:Refresh()
    end)
    endSessionBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("End Session")
        GameTooltip:Show()
    end)
    endSessionBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.endSessionBtn = endSessionBtn

    local testBtn = CreateFrame("Button", nil, buttonBar, "UIPanelButtonTemplate")
    testBtn:SetSize(50, btnHeight)
    testBtn:SetPoint("RIGHT", endSessionBtn, "LEFT", -btnSpacing, 0)
    testBtn:SetText("Test")
    testBtn:SetScript("OnClick", function()
        HooligansLoot:RunTest("kara")
        MainFrame:Refresh()
    end)
    testBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Test Karazhan")
        GameTooltip:AddLine("Add test items for testing", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    testBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.testBtn = testBtn

    -- Open Vote button - reopens the vote popup if closed (visible for all)
    local openVoteBtn = CreateFrame("Button", nil, buttonBar, "UIPanelButtonTemplate")
    openVoteBtn:SetSize(70, btnHeight)
    openVoteBtn:SetPoint("RIGHT", testBtn, "LEFT", -btnSpacing, 0)
    openVoteBtn:SetText("Open Vote")
    openVoteBtn:SetScript("OnClick", function()
        local LootFrame = HooligansLoot:GetModule("LootFrame", true)
        if LootFrame then
            LootFrame:Show()
        end
    end)
    openVoteBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Open Vote Popup")
        GameTooltip:AddLine("Reopen the voting popup to respond to items", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    openVoteBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.openVoteBtn = openVoteBtn

    -- Refresh button (between the two groups)
    local refreshBtn = CreateFrame("Button", nil, buttonBar, "UIPanelButtonTemplate")
    refreshBtn:SetSize(55, btnHeight)
    refreshBtn:SetPoint("RIGHT", openVoteBtn, "LEFT", -btnSpacing, 0)
    refreshBtn:SetText("Refresh")
    refreshBtn:SetScript("OnClick", function()
        local LootTracker = HooligansLoot:GetModule("LootTracker", true)
        local SessionManager = HooligansLoot:GetModule("SessionManager")
        local session = SessionManager:GetCurrentSession()
        if session and LootTracker then
            for _, item in ipairs(session.items) do
                if not item.icon or item.icon == "Interface\\Icons\\INV_Misc_QuestionMark" then
                    LootTracker:RequestItemInfo(item.id)
                end
            end
            LootTracker:RetryPendingIcons()
        end
        MainFrame:Refresh()
    end)
    frame.refreshBtn = refreshBtn

    -- Sync button - request session sync from ML (visible for raiders only)
    local syncBtn = CreateFrame("Button", nil, buttonBar, "UIPanelButtonTemplate")
    syncBtn:SetSize(55, btnHeight)
    syncBtn:SetPoint("RIGHT", refreshBtn, "LEFT", -btnSpacing, 0)
    syncBtn:SetText("Sync")
    syncBtn:SetScript("OnClick", function()
        local SessionManager = HooligansLoot:GetModule("SessionManager")
        if SessionManager:RequestSync() then
            HooligansLoot:Print("Requesting session sync from Raid Leader...")
        else
            HooligansLoot:Print("Cannot sync - not in a group or you are the Raid Leader")
        end
    end)
    syncBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Sync Session")
        GameTooltip:AddLine("Request session data from the Raid Leader", 1, 1, 1, true)
        GameTooltip:AddLine("Use this if you joined mid-session or items are missing", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    syncBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    syncBtn:Hide() -- Hidden by default, shown for raiders only
    frame.syncBtn = syncBtn

    -- OnShow handler
    frame:SetScript("OnShow", function()
        MainFrame:Refresh()
        MainFrame:StartUpdateTimer()
    end)

    frame:SetScript("OnHide", function()
        MainFrame:StopUpdateTimer()
    end)

    mainFrame = frame
    return frame
end

function MainFrame:CreatePlayerRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(18)
    row:SetPoint("TOPLEFT", 0, -((index - 1) * 18))
    row:SetPoint("TOPRIGHT", 0, -((index - 1) * 18))

    -- Sync status icon
    row.statusIcon = row:CreateTexture(nil, "ARTWORK")
    row.statusIcon:SetSize(12, 12)
    row.statusIcon:SetPoint("LEFT", 2, 0)

    -- Vote confirmation checkmark (shown when player has confirmed their vote)
    row.confirmIcon = row:CreateTexture(nil, "ARTWORK")
    row.confirmIcon:SetSize(12, 12)
    row.confirmIcon:SetPoint("LEFT", row.statusIcon, "RIGHT", 2, 0)
    row.confirmIcon:SetTexture("Interface\\RAIDFRAME\\ReadyCheck-Ready")
    row.confirmIcon:SetVertexColor(0, 1, 0, 1)  -- Green checkmark
    row.confirmIcon:Hide()

    -- Player name (position adjusts based on whether confirmIcon is shown)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.name:SetPoint("LEFT", row.statusIcon, "RIGHT", 4, 0)
    row.name:SetPoint("RIGHT", -2, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    -- Tooltip on hover
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        if self.tooltipText then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.playerName or "")
            GameTooltip:AddLine(self.tooltipText, 1, 1, 1, true)
            if self.voteConfirmed then
                GameTooltip:AddLine("|cff00ff00Vote confirmed|r", 1, 1, 1, true)
            end
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    row:Hide()
    return row
end

function MainFrame:RefreshPlayerPanel()
    if not mainFrame or not mainFrame.playerPanel then return end

    local SessionManager = HooligansLoot:GetModule("SessionManager", true)
    local Voting = HooligansLoot:GetModule("Voting", true)

    -- Show player panel for everyone (ML and raiders)
    mainFrame.playerPanel:Show()

    -- Get sync status
    local status = SessionManager:GetSyncStatus()

    -- Check if there's an active vote to show confirmation status
    local hasActiveVote = false
    local confirmedCount = 0
    local totalSynced = 0
    if Voting then
        local activeVotes = Voting:GetActiveVotes()
        for _, vote in pairs(activeVotes) do
            if vote.status == Voting.Status.COLLECTING then
                hasActiveVote = true
                break
            end
        end
    end

    -- Update sync count / vote status
    if status then
        local syncedCount = #status.syncedPlayers
        local totalCount = status.totalRaidMembers

        -- Count Raid Leader as synced if they're in unsynced list (they're the source of truth)
        for _, p in ipairs(status.unsyncedPlayers) do
            -- Check if this unsynced player is the raid leader
            local numMembers = GetNumGroupMembers()
            local isRaid = IsInRaid()
            for i = 1, numMembers do
                local unit = isRaid and ("raid" .. i) or (i == 1 and "player" or ("party" .. (i - 1)))
                local name = UnitName(unit)
                if name == p.name and UnitIsGroupLeader(unit) then
                    syncedCount = syncedCount + 1
                    break
                end
            end
        end
        totalSynced = syncedCount

        if hasActiveVote and Voting then
            -- Count confirmed players from synced list
            for _, p in ipairs(status.syncedPlayers) do
                if Voting:HasPlayerConfirmed(p.name) then
                    confirmedCount = confirmedCount + 1
                end
            end
            -- Also count confirmed players from unsynced list who are leaders (they're always considered synced)
            for _, p in ipairs(status.unsyncedPlayers) do
                local numMembers = GetNumGroupMembers()
                local isRaid = IsInRaid()
                for i = 1, numMembers do
                    local unit = isRaid and ("raid" .. i) or (i == 1 and "player" or ("party" .. (i - 1)))
                    local name = UnitName(unit)
                    if name == p.name and UnitIsGroupLeader(unit) then
                        if Voting:HasPlayerConfirmed(p.name) then
                            confirmedCount = confirmedCount + 1
                        end
                        break
                    end
                end
            end
            -- Show vote confirmation status
            mainFrame.syncCount:SetText(string.format("|cff00ff00%d|r / %d voted", confirmedCount, syncedCount))
            mainFrame.playerPanelTitle:SetText("|cffffcc00Vote Status|r")
        else
            mainFrame.syncCount:SetText(string.format("|cff00ff00%d|r / %d synced", syncedCount, totalCount))
            mainFrame.playerPanelTitle:SetText("|cffffcc00Raid Members|r")
        end
    else
        mainFrame.syncCount:SetText("No session")
        mainFrame.playerPanelTitle:SetText("|cffffcc00Raid Members|r")
    end

    -- Clear existing rows
    for _, row in ipairs(playerRows) do
        row:Hide()
    end

    if not status then return end

    -- Build combined player list (synced first, then unsynced)
    local allPlayers = {}

    -- Helper to check if player is raid/party leader
    local function isPlayerLeader(playerName)
        local numMembers = GetNumGroupMembers()
        local isRaid = IsInRaid()
        for i = 1, numMembers do
            local unit = isRaid and ("raid" .. i) or (i == 1 and "player" or ("party" .. (i - 1)))
            local name = UnitName(unit)
            if name == playerName then
                return UnitIsGroupLeader(unit)
            end
        end
        return false
    end

    -- Get our own version for comparison
    local myVersion = Utils.GetAddonVersion()

    -- Add synced players
    for _, p in ipairs(status.syncedPlayers) do
        local playerIsLeader = isPlayerLeader(p.name)
        table.insert(allPlayers, {
            name = p.name,
            class = p.class,
            synced = true,
            isML = p.isML or false,
            isLeader = playerIsLeader,
            zone = p.zone,
            version = p.version,
        })
    end

    -- Add unsynced players
    for _, p in ipairs(status.unsyncedPlayers) do
        local playerIsLeader = isPlayerLeader(p.name)
        -- Raid Leader is always considered synced (they are the source of truth)
        local isSynced = playerIsLeader
        table.insert(allPlayers, {
            name = p.name,
            class = p.class,
            synced = isSynced,
            isML = p.isML,
            isLeader = playerIsLeader,
            oldSession = p.oldSession,
            version = p.version,
        })
    end

    -- Sort: Leader first, then synced, then unsynced
    table.sort(allPlayers, function(a, b)
        if a.isLeader ~= b.isLeader then return a.isLeader end
        if a.synced ~= b.synced then return a.synced end
        return a.name < b.name
    end)

    -- Create/update rows
    for i, player in ipairs(allPlayers) do
        if not playerRows[i] then
            playerRows[i] = self:CreatePlayerRow(mainFrame.playerContent, i)
        end

        local row = playerRows[i]

        -- Check if player has confirmed their vote
        local voteConfirmed = false
        if hasActiveVote and Voting and player.synced then
            voteConfirmed = Voting:HasPlayerConfirmed(player.name)
        end
        row.voteConfirmed = voteConfirmed

        -- Set status icon based on context
        if hasActiveVote then
            -- During voting: show vote confirmation status
            if voteConfirmed then
                row.statusIcon:SetTexture("Interface\\RAIDFRAME\\ReadyCheck-Ready")
                row.statusIcon:SetVertexColor(0, 1, 0, 1)  -- Green
                row.tooltipText = "|cff00ff00Vote confirmed|r"
            elseif player.synced then
                row.statusIcon:SetTexture("Interface\\RAIDFRAME\\ReadyCheck-Waiting")
                row.statusIcon:SetVertexColor(1, 1, 0, 1)  -- Yellow
                row.tooltipText = "Waiting for response..."
            else
                row.statusIcon:SetTexture("Interface\\RAIDFRAME\\ReadyCheck-NotReady")
                row.statusIcon:SetVertexColor(1, 0.3, 0.3, 1)  -- Red
                row.tooltipText = "Not synced - cannot vote"
            end
        else
            -- Normal sync status display
            row.statusIcon:SetVertexColor(1, 1, 1, 1)  -- Reset color
            local leaderSuffix = player.isLeader and " |cffffcc00(Raid Leader)|r" or ""

            -- Version info for tooltip
            local versionText = ""
            if player.version then
                if player.version == myVersion then
                    versionText = "\n|cff00ff00v" .. player.version .. "|r"
                else
                    versionText = "\n|cffff6600v" .. player.version .. " (different!)|r"
                end
            elseif player.synced and not player.isML then
                versionText = "\n|cff888888v?|r"
            end

            if player.isML then
                row.statusIcon:SetTexture("Interface\\RAIDFRAME\\ReadyCheck-Ready")
                row.tooltipText = "Raid Leader (you)" .. leaderSuffix .. "\n|cff00ff00v" .. myVersion .. "|r"
            elseif player.synced then
                row.statusIcon:SetTexture("Interface\\RAIDFRAME\\ReadyCheck-Ready")
                row.tooltipText = "Synced" .. (player.zone and (" - " .. player.zone) or "") .. leaderSuffix .. versionText
            elseif player.oldSession then
                row.statusIcon:SetTexture("Interface\\RAIDFRAME\\ReadyCheck-NotReady")
                row.tooltipText = "|cffff0000Has OLD session!|r\nNeeds to /hl sync clear" .. leaderSuffix
            else
                row.statusIcon:SetTexture("Interface\\RAIDFRAME\\ReadyCheck-Waiting")
                row.tooltipText = "Not synced yet" .. leaderSuffix
            end
        end

        -- Hide the separate confirmIcon (we're using statusIcon for both now)
        if row.confirmIcon then
            row.confirmIcon:Hide()
        end

        -- Set name with class color, leader indicator, and version indicator
        local classColor = RAID_CLASS_COLORS[player.class] or { r = 0.5, g = 0.5, b = 0.5 }
        local colorCode = string.format("|cff%02x%02x%02x", classColor.r * 255, classColor.g * 255, classColor.b * 255)
        local displayName = colorCode .. player.name .. "|r"
        if player.isLeader then
            displayName = displayName .. " |cffffcc00(RL)|r"
        end
        -- Add version mismatch indicator (orange dot) if version differs
        if player.version and player.version ~= myVersion then
            displayName = displayName .. " |cffff6600*|r"
        end
        row.name:SetText(displayName)
        row.playerName = player.name

        row:Show()
    end

    -- Set content height
    mainFrame.playerContent:SetHeight(#allPlayers * 18)
end

function MainFrame:CreateItemRow(parent, index)
    -- Must be "Button" not "Frame" to support RegisterForClicks and OnClick
    local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -((index - 1) * ROW_HEIGHT))
    row:SetPoint("TOPRIGHT", 0, -((index - 1) * ROW_HEIGHT))  -- MUST have both anchors like SessionSetupFrame

    -- Background (same pattern as SessionSetupFrame)
    row:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
    })
    if index % 2 == 0 then
        row:SetBackdropColor(0.12, 0.12, 0.14, 0.6)
    else
        row:SetBackdropColor(0.06, 0.06, 0.08, 0.4)
    end

    -- Hover highlight
    row.highlight = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.highlight:SetAllPoints()
    row.highlight:SetColorTexture(0.4, 0.35, 0.2, 0.4)
    row.highlight:Hide()

    -- Item icon
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(38, 38)
    row.icon:SetPoint("LEFT", 8, 0)

    -- Icon border
    row.iconBorder = row:CreateTexture(nil, "OVERLAY")
    row.iconBorder:SetSize(40, 40)
    row.iconBorder:SetPoint("CENTER", row.icon, "CENTER", 0, 0)
    row.iconBorder:SetTexture("Interface\\Buttons\\UI-Slot-Background")
    row.iconBorder:SetVertexColor(1, 1, 1, 0.3)

    -- Item name
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 55, -8)
    row.name:SetWidth(200)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    -- Boss name (below item name)
    row.boss = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.boss:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
    row.boss:SetJustifyH("LEFT")
    row.boss:SetTextColor(0.5, 0.5, 0.5)

    -- Responses display (shows player names by response type)
    row.responses = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.responses:SetPoint("LEFT", 270, 0)
    row.responses:SetWidth(220)
    row.responses:SetJustifyH("LEFT")
    row.responses:SetSpacing(1)

    -- Awarded player (middle column) - aligned with header
    row.awardedTo = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.awardedTo:SetPoint("RIGHT", -200, 0)
    row.awardedTo:SetWidth(100)
    row.awardedTo:SetJustifyH("CENTER")

    -- Trade timer (right side) - aligned with header (ML only)
    row.timer = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.timer:SetPoint("RIGHT", -40, 0)
    row.timer:SetWidth(80)
    row.timer:SetJustifyH("CENTER")

    -- Remove button (X)
    row.removeBtn = CreateFrame("Button", nil, row)
    row.removeBtn:SetSize(18, 18)
    row.removeBtn:SetPoint("RIGHT", -2, 0)
    row.removeBtn:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
    row.removeBtn:SetHighlightTexture("Interface\\Buttons\\UI-StopButton")
    row.removeBtn:GetHighlightTexture():SetVertexColor(1, 0.3, 0.3, 0.8)
    row.removeBtn:SetScript("OnClick", function(self)
        local itemGUID = self:GetParent().itemGUID
        if itemGUID then
            -- Confirm removal
            StaticPopupDialogs["HOOLIGANS_CONFIRM_REMOVE_ITEM"] = {
                text = "Remove this item from the session?",
                button1 = "Yes",
                button2 = "No",
                OnAccept = function()
                    local SessionManager = HooligansLoot:GetModule("SessionManager")
                    SessionManager:RemoveItem(nil, itemGUID)
                    MainFrame:Refresh()
                end,
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
            }
            StaticPopup_Show("HOOLIGANS_CONFIRM_REMOVE_ITEM")
        end
    end)
    row.removeBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Remove Item")
        GameTooltip:Show()
    end)
    row.removeBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.removeBtn:Hide() -- Hidden by default, shown when item has data

    -- Tooltip on hover and right-click menu
    row:EnableMouse(true)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnEnter", function(self)
        self.highlight:Show()
        -- Only show remove button for ML/council
        if self.removeBtn then
            local Voting = HooligansLoot:GetModule("Voting", true)
            local canRemove = Voting and (Voting:IsMasterLooter() or Voting:IsCouncilMember())
            if canRemove then
                self.removeBtn:Show()
            end
        end
        if self.itemLink then
            GameTooltip:SetOwner(self.name, "ANCHOR_TOPRIGHT")
            GameTooltip:SetHyperlink(self.itemLink)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function(self)
        self.highlight:Hide()
        if self.removeBtn and not self.removeBtn:IsMouseOver() then
            self.removeBtn:Hide()
        end
        GameTooltip:Hide()
        -- Hide WoW's extra tooltips
        if ShoppingTooltip1 then ShoppingTooltip1:Hide() end
        if ShoppingTooltip2 then ShoppingTooltip2:Hide() end
        if ItemRefTooltip then ItemRefTooltip:Hide() end
    end)
    row:SetScript("OnClick", function(self, button)
        if button == "RightButton" and self.itemGUID then
            MainFrame:ShowAwardMenu(self, self.itemGUID, self.itemLink)
        end
    end)

    row:Hide()
    return row
end

-- Right-click menu for manual award
function MainFrame:ShowAwardMenu(row, itemGUID, itemLink)
    local menu = CreateFrame("Frame", "HooligansLootAwardMenu", UIParent, "UIDropDownMenuTemplate")

    UIDropDownMenu_Initialize(menu, function(self, level)
        local info = UIDropDownMenu_CreateInfo()

        -- Header
        info.isTitle = true
        info.notCheckable = true
        info.text = "Award to:"
        UIDropDownMenu_AddButton(info, level)

        -- Get raid/party members
        local members = {}
        if IsInRaid() then
            for i = 1, GetNumGroupMembers() do
                local name, _, _, _, _, classFile = GetRaidRosterInfo(i)
                if name then
                    local cleanName = name:match("([^-]+)") or name
                    table.insert(members, { name = cleanName, class = classFile })
                end
            end
        elseif IsInGroup() then
            -- Add self
            local playerName = UnitName("player")
            local _, playerClass = UnitClass("player")
            table.insert(members, { name = playerName, class = playerClass })
            -- Add party members
            for i = 1, GetNumGroupMembers() - 1 do
                local name = UnitName("party" .. i)
                local _, classFile = UnitClass("party" .. i)
                if name then
                    table.insert(members, { name = name, class = classFile })
                end
            end
        else
            -- Solo - just add self
            local playerName = UnitName("player")
            local _, playerClass = UnitClass("player")
            table.insert(members, { name = playerName, class = playerClass })
        end

        -- Sort alphabetically
        table.sort(members, function(a, b) return a.name < b.name end)

        -- Add player options
        for _, member in ipairs(members) do
            info = UIDropDownMenu_CreateInfo()
            info.isTitle = false
            info.notCheckable = true
            info.text = Utils.GetColoredPlayerName(member.name, member.class)
            info.arg1 = member.name
            info.arg2 = member.class
            info.func = function(_, playerName, playerClass)
                local SessionManager = HooligansLoot:GetModule("SessionManager")
                local session = SessionManager:GetCurrentSession()
                if session then
                    SessionManager:SetAward(session.id, itemGUID, playerName, playerClass)
                    HooligansLoot:Print("Awarded " .. (itemLink or "item") .. " to " .. playerName)
                    MainFrame:Refresh()
                end
            end
            UIDropDownMenu_AddButton(info, level)
        end

        -- Cancel option
        info = UIDropDownMenu_CreateInfo()
        info.isTitle = false
        info.notCheckable = true
        info.text = "|cff888888Cancel|r"
        info.func = function() CloseDropDownMenus() end
        UIDropDownMenu_AddButton(info, level)
    end, "MENU")

    ToggleDropDownMenu(1, nil, menu, "cursor", 0, 0)
end

function MainFrame:UpdateItemRow(row, item, award)
    if not item then
        row:Hide()
        return
    end

    if not row then
        return
    end

    -- Icon (request load if not available)
    if item.icon and item.icon ~= "Interface\\Icons\\INV_Misc_QuestionMark" then
        row.icon:SetTexture(item.icon)
    else
        row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        -- Try to load the icon
        if item.id then
            local LootTracker = HooligansLoot:GetModule("LootTracker", true)
            if LootTracker then
                LootTracker:RequestItemInfo(item.id)
            end
        end
    end

    -- Name (with quality color, truncate if needed)
    local qualityColor = Utils.GetQualityColor(item.quality or 4)
    local displayName = item.name or "Unknown Item"
    row.name:SetText("|cff" .. qualityColor .. displayName .. "|r")

    -- Boss (with icon indicator)
    row.boss:SetText(item.boss or "Unknown")

    -- Check for vote responses - check both active votes and session.votes
    local Voting = HooligansLoot:GetModule("Voting", true)
    local responseText = ""
    local foundVote = nil

    if Voting then
        local success, err = pcall(function()
            local activeVotes = Voting:GetActiveVotes()
            local SessionManager = HooligansLoot:GetModule("SessionManager")
            local currentSession = SessionManager:GetCurrentSession()
            local currentSessionId = currentSession and currentSession.id

            -- Match votes by item name or GUID
            local debugNoMatch = HooligansLoot.db.profile.settings.debug
            for voteId, vote in pairs(activeVotes) do
                -- For synced sessions, sessionId might not match exactly - skip the check for raiders
                local sessionMatches = (vote.sessionId == currentSessionId) or (not currentSessionId)
                if sessionMatches then
                    local voteName = vote.item and vote.item.name
                    -- Match by GUID first (most reliable)
                    if vote.itemGUID and item.guid and vote.itemGUID == item.guid then
                        foundVote = vote
                        break
                    end
                    -- Match by item name (case-insensitive)
                    if voteName and item.name and voteName:lower() == item.name:lower() then
                        foundVote = vote
                        break
                    end
                end
            end
            -- Debug: log unmatched items
            if debugNoMatch and not foundVote and item.name then
                HooligansLoot:Debug("No vote match for item: " .. item.name .. " (guid: " .. tostring(item.guid) .. ")")
            end

            -- Also check session.votes if not found in activeVotes
            if not foundVote and currentSession and currentSession.votes then
                for voteId, vote in pairs(currentSession.votes) do
                    local sessionMatches = (vote.sessionId == currentSessionId) or (not currentSessionId)
                    if sessionMatches then
                        local voteName = vote.item and vote.item.name
                        -- Match by GUID first (most reliable)
                        if vote.itemGUID and item.guid and vote.itemGUID == item.guid then
                            foundVote = vote
                            break
                        end
                        if voteName and item.name and voteName:lower() == item.name:lower() then
                            foundVote = vote
                            break
                        end
                    end
                end
            end
        end)

        if not success then
            HooligansLoot:Debug("Error in vote matching: " .. tostring(err))
        end
    end

    -- Process responses if vote found
    -- Only council members/ML/raid leader can see responses
    local canSeeResponses = false
    if Voting then
        canSeeResponses = Voting:IsCouncilMember() or Voting:IsMasterLooter()
    end

    if foundVote and foundVote.responses and canSeeResponses then
        -- Group players by response type with class colors
        local byType = { bis = {}, greater = {}, minor = {}, offspec = {}, pvp = {} }
        local GearComparison = HooligansLoot:GetModule("GearComparison", true)

        for playerName, response in pairs(foundVote.responses) do
            local respType = response.response and response.response:lower() or ""
            if byType[respType] then
                -- Use full player name with class color
                local classColor = Utils.GetClassColorHex(response.class) or "ffffff"
                local displayName = "|cff" .. classColor .. playerName .. "|r"

                -- Add equipped item links if available
                if GearComparison and foundVote.playerGear and foundVote.playerGear[playerName] then
                    local gearInfo = GearComparison:GetGearDisplayInfo(foundVote, playerName, item.link)
                    if gearInfo and #gearInfo > 0 then
                        -- Show actual item links for equipped gear
                        local gearParts = {}
                        for _, gear in ipairs(gearInfo) do
                            if gear.link then
                                -- Extract short item name from link
                                local itemName = gear.link:match("%[(.-)%]") or "?"
                                -- Truncate long names
                                if #itemName > 15 then
                                    itemName = itemName:sub(1, 12) .. "..."
                                end
                                table.insert(gearParts, gear.link)
                            else
                                table.insert(gearParts, "|cff666666[Empty]|r")
                            end
                        end
                        if #gearParts > 0 then
                            displayName = displayName .. " " .. table.concat(gearParts, " ")
                        end
                    end
                end

                -- Add note if present
                if response.note and response.note ~= "" then
                    displayName = displayName .. " |cff888888(" .. response.note .. ")|r"
                end
                table.insert(byType[respType], displayName)
            end
        end

        local parts = {}
        -- Show priority responses first (BiS > Greater > Minor > Offspec > PvP)
        if #byType.bis > 0 then
            table.insert(parts, "|cff00ff00BiS:|r " .. table.concat(byType.bis, ", "))
        end
        if #byType.greater > 0 then
            table.insert(parts, "|cff00cc66Greater:|r " .. table.concat(byType.greater, ", "))
        end
        if #byType.minor > 0 then
            table.insert(parts, "|cff00ccffMinor:|r " .. table.concat(byType.minor, ", "))
        end
        if #byType.offspec > 0 then
            table.insert(parts, "|cffff9900Offspec:|r " .. table.concat(byType.offspec, ", "))
        end
        if #byType.pvp > 0 then
            table.insert(parts, "|cffcc66ffPvP:|r " .. table.concat(byType.pvp, ", "))
        end

        if #parts > 0 then
            -- Join with newlines for multi-line display
            responseText = table.concat(parts, "\n")
        end
    end
    row.responses:SetText(responseText)

    -- Trade timer with color coding (ML only)
    local Voting = HooligansLoot:GetModule("Voting", true)
    local isML = Voting and Voting:IsMasterLooter()

    if isML then
        local timeRemaining = Utils.GetTradeTimeRemaining(item.tradeExpires)
        local timerText = Utils.FormatTimeRemaining(timeRemaining)

        if timeRemaining <= 0 then
            row.timer:SetText("|cff888888Exp|r")
        elseif timeRemaining < 600 then -- Less than 10 min
            row.timer:SetText("|cffff4444" .. timerText .. "|r")
        elseif timeRemaining < 1800 then -- Less than 30 min
            row.timer:SetText("|cffffaa00" .. timerText .. "|r")
        else
            row.timer:SetText("|cff88ff88" .. timerText .. "|r")
        end
        row.timer:Show()
    else
        row.timer:Hide()
    end

    -- Award status with better formatting
    if award then
        -- Show awarded player name with class color
        local coloredName = Utils.GetColoredPlayerName(award.winner, award.class)
        row.awardedTo:SetText(coloredName)
    else
        row.awardedTo:SetText("|cff666666---|r")
    end

    -- Store item link and GUID for tooltip and remove button
    row.itemLink = item.link
    row.itemGUID = item.guid

    row:Show()
end

function MainFrame:Refresh()
    if not mainFrame or not mainFrame:IsShown() then return end

    -- Guard against recursive refresh
    if isRefreshing then
        HooligansLoot:Debug("MainFrame:Refresh - SKIPPING (already refreshing)")
        return
    end
    isRefreshing = true

    -- Use pcall to ensure isRefreshing is always reset even if there's an error
    local success, err = pcall(function()
        self:DoRefresh()
    end)

    isRefreshing = false

    if not success then
        HooligansLoot:Debug("MainFrame:Refresh - ERROR: " .. tostring(err))
        print("|cffff0000[HL Error]|r MainFrame:Refresh failed: " .. tostring(err))
    end
end

function MainFrame:DoRefresh()
    local SessionManager = HooligansLoot:GetModule("SessionManager")
    local session = SessionManager:GetCurrentSession()

    -- Refresh the player sync panel (ML only)
    self:RefreshPlayerPanel()

    -- Show/hide RESPONSES column header based on permissions
    local Voting = HooligansLoot:GetModule("Voting", true)
    local canSeeResponses = Voting and (Voting:IsCouncilMember() or Voting:IsMasterLooter())
    local isML = Voting and Voting:IsMasterLooter()
    if mainFrame.colResponses then
        if canSeeResponses then
            mainFrame.colResponses:Show()
        else
            mainFrame.colResponses:Hide()
        end
    end

    -- Show/hide TIMER column (only ML needs to see trade timers)
    if mainFrame.colTimer then
        if isML then
            mainFrame.colTimer:Show()
        else
            mainFrame.colTimer:Hide()
        end
    end

    -- Show/hide ML-only buttons (raiders only see Sync and Open Vote)
    if isML then
        -- Show ML-only header buttons
        if mainFrame.settingsBtn then mainFrame.settingsBtn:Show() end
        if mainFrame.historyBtn then mainFrame.historyBtn:Show() end
        -- Show ML-only session bar buttons
        if mainFrame.sessionBar.newBtn then mainFrame.sessionBar.newBtn:Show() end
        if mainFrame.sessionBar.renameBtn then mainFrame.sessionBar.renameBtn:Show() end
        -- Show ML-only bottom buttons
        if mainFrame.exportBtn then mainFrame.exportBtn:Show() end
        if mainFrame.importBtn then mainFrame.importBtn:Show() end
        if mainFrame.announceBtn then mainFrame.announceBtn:Show() end
        if mainFrame.addItemBtn then mainFrame.addItemBtn:Show() end
        if mainFrame.startVoteBtn then mainFrame.startVoteBtn:Show() end
        if mainFrame.resyncBtn then mainFrame.resyncBtn:Show() end
        if mainFrame.refreshBtn then mainFrame.refreshBtn:Show() end
        if mainFrame.testBtn then mainFrame.testBtn:Show() end
        if mainFrame.endSessionBtn then mainFrame.endSessionBtn:Show() end
        if mainFrame.openVoteBtn then mainFrame.openVoteBtn:Show() end
        -- Hide sync button for ML (they don't need it)
        if mainFrame.syncBtn then mainFrame.syncBtn:Hide() end
    else
        -- Raiders: hide ML-only header buttons
        if mainFrame.settingsBtn then mainFrame.settingsBtn:Hide() end
        if mainFrame.historyBtn then mainFrame.historyBtn:Hide() end
        -- Raiders: hide ML-only session bar buttons
        if mainFrame.sessionBar.newBtn then mainFrame.sessionBar.newBtn:Hide() end
        if mainFrame.sessionBar.renameBtn then mainFrame.sessionBar.renameBtn:Hide() end
        -- Raiders: hide ML-only bottom buttons
        if mainFrame.exportBtn then mainFrame.exportBtn:Hide() end
        if mainFrame.importBtn then mainFrame.importBtn:Hide() end
        if mainFrame.announceBtn then mainFrame.announceBtn:Hide() end
        if mainFrame.addItemBtn then mainFrame.addItemBtn:Hide() end
        if mainFrame.startVoteBtn then mainFrame.startVoteBtn:Hide() end
        if mainFrame.resyncBtn then mainFrame.resyncBtn:Hide() end
        if mainFrame.testBtn then mainFrame.testBtn:Hide() end
        if mainFrame.endSessionBtn then mainFrame.endSessionBtn:Hide() end
        -- Show raider buttons (Sync, Open Vote only)
        if mainFrame.refreshBtn then mainFrame.refreshBtn:Hide() end
        if mainFrame.syncBtn then mainFrame.syncBtn:Show() end
        if mainFrame.openVoteBtn then mainFrame.openVoteBtn:Show() end
        -- Reposition for raider layout (centered - just 2 buttons)
        if mainFrame.syncBtn then
            mainFrame.syncBtn:ClearAllPoints()
            mainFrame.syncBtn:SetPoint("BOTTOM", mainFrame.buttonBar, "BOTTOM", -40, 0)
        end
        if mainFrame.openVoteBtn then
            mainFrame.openVoteBtn:ClearAllPoints()
            mainFrame.openVoteBtn:SetPoint("LEFT", mainFrame.syncBtn, "RIGHT", 5, 0)
        end
    end

    -- Check if this is a synced session (from ML)
    local isSynced = SessionManager:IsSyncedSession()

    -- Update session bar
    if session then
        -- Session name with date
        local dateStr = session.created and date("%Y-%m-%d %H:%M", session.created) or ""
        local syncIndicator = isSynced and " |cff88ccff(Synced)|r" or ""
        mainFrame.sessionBar.name:SetText(session.name .. " - " .. dateStr .. syncIndicator)

        -- Status badge
        local statusColor, statusText
        if session.status == "ended" then
            statusColor = "|cffffaa00"
            statusText = "[Ended]"
        elseif session.status == "completed" then
            statusColor = "|cff5865F2"
            statusText = "[Completed]"
        else
            statusColor = "|cff00ff00"
            statusText = "[Active]"
        end
        mainFrame.sessionBar.status:SetText(statusColor .. statusText .. "|r")

        -- Disable ML-only buttons for synced sessions (raiders can't modify)
        if isSynced then
            mainFrame.endSessionBtn:SetEnabled(false)
            mainFrame.sessionBar.renameBtn:SetEnabled(false)
            mainFrame.addItemBtn:SetEnabled(false)
            mainFrame.startVoteBtn:SetEnabled(false)
            mainFrame.sessionBar.newBtn:SetEnabled(false)
        else
            mainFrame.endSessionBtn:SetEnabled(session.status == "active")
            mainFrame.sessionBar.renameBtn:SetEnabled(true)
            mainFrame.addItemBtn:SetEnabled(true)
            mainFrame.startVoteBtn:SetEnabled(#session.items > 0)
            mainFrame.sessionBar.newBtn:SetEnabled(true)
        end
    else
        mainFrame.sessionBar.name:SetText("No active session")
        -- Check if player can start sessions (ML/RL only in groups)
        local Voting = HooligansLoot:GetModule("Voting", true)
        local canStartSession = not IsInGroup() or (Voting and Voting:IsMasterLooter())
        if canStartSession then
            mainFrame.sessionBar.status:SetText("|cff888888Click 'New' to start|r")
        else
            mainFrame.sessionBar.status:SetText("|cff888888Waiting for ML to start session|r")
        end
        mainFrame.sessionBar.newBtn:SetEnabled(canStartSession)
        mainFrame.endSessionBtn:SetEnabled(false)
        mainFrame.sessionBar.renameBtn:SetEnabled(false)
        mainFrame.addItemBtn:SetEnabled(false)
        mainFrame.startVoteBtn:SetEnabled(false)
    end

    -- Destroy and clear existing rows to force recreation with correct dimensions
    for _, row in ipairs(itemRows) do
        row:Hide()
        row:SetParent(nil)
    end
    wipe(itemRows)

    -- Populate items
    if session and session.items and #session.items > 0 then
        -- Sort items by timestamp (newest first)
        local sortedItems = {}
        for _, item in ipairs(session.items) do
            table.insert(sortedItems, item)
        end
        table.sort(sortedItems, function(a, b) return (a.timestamp or 0) > (b.timestamp or 0) end)

        -- Create/update rows
        for i, item in ipairs(sortedItems) do
            if not itemRows[i] then
                itemRows[i] = self:CreateItemRow(mainFrame.content, i)
            end

            local award = session.awards and session.awards[item.guid] or nil
            self:UpdateItemRow(itemRows[i], item, award)
        end

        -- Set content height
        mainFrame.content:SetHeight(#sortedItems * ROW_HEIGHT)

        -- Update stats with better formatting
        local stats = SessionManager:GetSessionStats(session.id)
        if stats then
            local statsText = string.format(
                "|cffffffffItems:|r %d  |cff88ff88Awarded:|r %d/%d  |cffff8888Traded:|r %d  |cff888888Expired:|r %d",
                stats.totalItems,
                stats.totalAwards,
                stats.totalItems,
                stats.completedAwards,
                stats.expiredItems
            )
            mainFrame.stats:SetText(statsText)
        end
    else
        mainFrame.content:SetHeight(ROW_HEIGHT)

        -- Different messages for ML vs raiders
        local Voting = HooligansLoot:GetModule("Voting", true)
        local isMLForStats = Voting and Voting:IsMasterLooter()

        if session then
            if isMLForStats then
                mainFrame.stats:SetText("|cff888888Session is empty - use 'Test Kara' to add test items|r")
            else
                mainFrame.stats:SetText("")  -- Raiders: no message needed
            end
        else
            if isMLForStats then
                mainFrame.stats:SetText("|cff888888No session active|r")
            else
                mainFrame.stats:SetText("")  -- Raiders: no message needed
            end
        end

        -- Show empty message (ML only - raiders see nothing)
        if isMLForStats then
            if not itemRows[1] then
                itemRows[1] = self:CreateItemRow(mainFrame.content, 1)
            end
            itemRows[1].icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            itemRows[1].name:SetText("|cff666666No items tracked|r")
            itemRows[1].boss:SetText(session and "Use 'Test Kara' or loot items in a raid" or "Create a session first")
            itemRows[1].awardedTo:SetText("")
            itemRows[1].timer:SetText("")
            itemRows[1].itemLink = nil
            itemRows[1]:Show()
        end
    end

end

function MainFrame:StartUpdateTimer()
    if updateTimer then return end

    -- Update every second for trade timers (ML only)
    updateTimer = C_Timer.NewTicker(1, function()
        if mainFrame and mainFrame:IsShown() then
            -- Only ML needs timer updates
            local Voting = HooligansLoot:GetModule("Voting", true)
            local isML = Voting and Voting:IsMasterLooter()
            if not isML then return end

            -- Just update timers, not full refresh
            local SessionManager = HooligansLoot:GetModule("SessionManager")
            local session = SessionManager:GetCurrentSession()

            if session then
                for _, row in ipairs(itemRows) do
                    if row:IsShown() and row.itemGUID then
                        -- Find item by GUID since items may be sorted differently
                        for _, item in ipairs(session.items) do
                            if item.guid == row.itemGUID then
                                local timeRemaining = Utils.GetTradeTimeRemaining(item.tradeExpires)
                                local timerText = Utils.FormatTimeRemaining(timeRemaining)
                                if timeRemaining <= 0 then
                                    row.timer:SetText("|cff888888Exp|r")
                                elseif timeRemaining < 600 then
                                    row.timer:SetText("|cffff4444" .. timerText .. "|r")
                                elseif timeRemaining < 1800 then
                                    row.timer:SetText("|cffffaa00" .. timerText .. "|r")
                                else
                                    row.timer:SetText("|cff88ff88" .. timerText .. "|r")
                                end
                                break
                            end
                        end
                    end
                end
            end
        end
    end)
end

function MainFrame:StopUpdateTimer()
    if updateTimer then
        updateTimer:Cancel()
        updateTimer = nil
    end
end

function MainFrame:Show()
    local frame = self:CreateFrame()
    frame:Show()
    self:Refresh()
end

function MainFrame:Hide()
    if mainFrame then
        mainFrame:Hide()
    end
end

function MainFrame:Toggle()
    if mainFrame and mainFrame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

function MainFrame:IsShown()
    return mainFrame and mainFrame:IsShown()
end

-- Rename dialog
local renameDialog = nil

function MainFrame:ShowRenameDialog()
    local SessionManager = HooligansLoot:GetModule("SessionManager")
    local session = SessionManager:GetCurrentSession()

    if not session then
        HooligansLoot:Print("No active session to rename.")
        return
    end

    if not renameDialog then
        local dialog = CreateFrame("Frame", "HooligansLootRenameDialog", UIParent, "BackdropTemplate")
        dialog:SetSize(350, 120)
        dialog:SetPoint("CENTER")
        dialog:SetMovable(true)
        dialog:EnableMouse(true)
        dialog:RegisterForDrag("LeftButton")
        dialog:SetScript("OnDragStart", dialog.StartMoving)
        dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)
        dialog:SetFrameStrata("DIALOG")
        dialog:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            edgeSize = 20,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        dialog:SetBackdropColor(0.08, 0.08, 0.1, 0.95)
        dialog:SetBackdropBorderColor(0.6, 0.5, 0.3, 1)
        dialog:Hide()

        local title = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", 0, -15)
        title:SetText("Rename Session")

        local closeBtn = CreateFrame("Button", nil, dialog, "UIPanelCloseButton")
        closeBtn:SetPoint("TOPRIGHT", -2, -2)
        closeBtn:SetScript("OnClick", function() dialog:Hide() end)

        -- Edit box for new name
        local editBox = CreateFrame("EditBox", nil, dialog, "InputBoxTemplate")
        editBox:SetSize(300, 22)
        editBox:SetPoint("TOP", 0, -45)
        editBox:SetAutoFocus(true)
        editBox:SetScript("OnEscapePressed", function() dialog:Hide() end)
        editBox:SetScript("OnEnterPressed", function(self)
            local newName = self:GetText()
            if newName and newName ~= "" then
                local SessionManager = HooligansLoot:GetModule("SessionManager")
                SessionManager:RenameSession(nil, newName)
                MainFrame:Refresh()
            end
            dialog:Hide()
        end)
        dialog.editBox = editBox

        -- Save button
        local saveBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
        saveBtn:SetSize(80, 22)
        saveBtn:SetPoint("BOTTOMRIGHT", -15, 15)
        saveBtn:SetText("Save")
        saveBtn:SetScript("OnClick", function()
            local newName = editBox:GetText()
            if newName and newName ~= "" then
                local SessionManager = HooligansLoot:GetModule("SessionManager")
                SessionManager:RenameSession(nil, newName)
                MainFrame:Refresh()
            end
            dialog:Hide()
        end)

        -- Cancel button
        local cancelBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
        cancelBtn:SetSize(80, 22)
        cancelBtn:SetPoint("RIGHT", saveBtn, "LEFT", -5, 0)
        cancelBtn:SetText("Cancel")
        cancelBtn:SetScript("OnClick", function() dialog:Hide() end)

        tinsert(UISpecialFrames, "HooligansLootRenameDialog")
        renameDialog = dialog
    end

    -- Set current session name in edit box
    renameDialog.editBox:SetText(session.name)
    renameDialog.editBox:HighlightText()
    renameDialog:Show()
end

-- Add Item dialog
local addItemDialog = nil

function MainFrame:ShowAddItemDialog()
    local SessionManager = HooligansLoot:GetModule("SessionManager")
    local session = SessionManager:GetCurrentSession()

    if not session then
        HooligansLoot:Print("No active session. Create one first.")
        return
    end

    if not addItemDialog then
        local dialog = CreateFrame("Frame", "HooligansLootAddItemDialog", UIParent, "BackdropTemplate")
        dialog:SetSize(400, 150)
        dialog:SetPoint("CENTER")
        dialog:SetMovable(true)
        dialog:EnableMouse(true)
        dialog:RegisterForDrag("LeftButton")
        dialog:SetScript("OnDragStart", dialog.StartMoving)
        dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)
        dialog:SetFrameStrata("DIALOG")
        dialog:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            edgeSize = 20,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        dialog:SetBackdropColor(0.08, 0.08, 0.1, 0.95)
        dialog:SetBackdropBorderColor(0.6, 0.5, 0.3, 1)
        dialog:Hide()

        local title = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", 0, -15)
        title:SetText("Add Item")

        local closeBtn = CreateFrame("Button", nil, dialog, "UIPanelCloseButton")
        closeBtn:SetPoint("TOPRIGHT", -2, -2)
        closeBtn:SetScript("OnClick", function() dialog:Hide() end)

        -- Item link label
        local linkLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        linkLabel:SetPoint("TOPLEFT", 20, -45)
        linkLabel:SetText("Item Link:")
        linkLabel:SetTextColor(0.9, 0.8, 0.5)

        -- Edit box for item link (paste from chat)
        local linkEditBox = CreateFrame("EditBox", "HooligansLootAddItemEditBox", dialog, "InputBoxTemplate")
        linkEditBox:SetSize(350, 22)
        linkEditBox:SetPoint("TOP", 0, -60)
        linkEditBox:SetAutoFocus(true)
        linkEditBox:SetScript("OnEscapePressed", function() dialog:Hide() end)
        linkEditBox:SetScript("OnEnterPressed", function(self)
            local itemLink = self:GetText()
            if itemLink and itemLink ~= "" then
                local LootTracker = HooligansLoot:GetModule("LootTracker")
                if LootTracker:AddItemManually(itemLink) then
                    MainFrame:Refresh()
                    self:SetText("") -- Clear for next item
                    self:SetFocus()
                end
            end
        end)
        dialog.linkEditBox = linkEditBox

        -- Hook to allow shift-clicking items into this edit box
        -- Hook HandleModifiedItemClick for Classic/TBC compatibility
        local originalHandleModifiedItemClick = HandleModifiedItemClick
        HandleModifiedItemClick = function(link, ...)
            if linkEditBox:IsVisible() and linkEditBox:HasFocus() and link then
                linkEditBox:SetText(link)
                return true
            end
            return originalHandleModifiedItemClick(link, ...)
        end

        -- Also hook ChatEdit_InsertLink as backup
        local originalChatEdit_InsertLink = ChatEdit_InsertLink
        ChatEdit_InsertLink = function(link)
            if linkEditBox:IsVisible() and linkEditBox:HasFocus() and link then
                linkEditBox:SetText(link)
                return true
            end
            return originalChatEdit_InsertLink(link)
        end

        -- Also support drag-and-drop of items
        linkEditBox:SetScript("OnReceiveDrag", function(self)
            local infoType, itemID, itemLink = GetCursorInfo()
            if infoType == "item" and itemLink then
                self:SetText(itemLink)
                ClearCursor()
            end
        end)
        linkEditBox:SetScript("OnMouseDown", function(self, button)
            if button == "LeftButton" then
                local infoType, itemID, itemLink = GetCursorInfo()
                if infoType == "item" and itemLink then
                    self:SetText(itemLink)
                    ClearCursor()
                end
            end
        end)

        -- Instructions
        local instructions = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        instructions:SetPoint("TOP", linkEditBox, "BOTTOM", 0, -5)
        instructions:SetText("Shift-click or drag an item here, then press Enter or Add")
        instructions:SetTextColor(0.6, 0.6, 0.6)

        -- Done button (closes dialog)
        local doneBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
        doneBtn:SetSize(70, 22)
        doneBtn:SetPoint("BOTTOMRIGHT", -15, 15)
        doneBtn:SetText("Done")
        doneBtn:SetScript("OnClick", function() dialog:Hide() end)

        -- Add button (adds item and clears for next)
        local addBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
        addBtn:SetSize(70, 22)
        addBtn:SetPoint("RIGHT", doneBtn, "LEFT", -5, 0)
        addBtn:SetText("Add")
        addBtn:SetScript("OnClick", function()
            local itemLink = linkEditBox:GetText()
            if itemLink and itemLink ~= "" then
                local LootTracker = HooligansLoot:GetModule("LootTracker")
                if LootTracker:AddItemManually(itemLink) then
                    MainFrame:Refresh()
                    linkEditBox:SetText("") -- Clear for next item
                    linkEditBox:SetFocus()
                end
            end
        end)

        tinsert(UISpecialFrames, "HooligansLootAddItemDialog")
        addItemDialog = dialog
    end

    -- Clear and show
    addItemDialog.linkEditBox:SetText("")
    addItemDialog:Show()
end
