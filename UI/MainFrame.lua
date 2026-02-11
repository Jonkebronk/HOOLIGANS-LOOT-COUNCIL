-- UI/MainFrame.lua
-- Main addon window (ML-only mode)

local ADDON_NAME, NS = ...
local HooligansLoot = NS.addon
local Utils = NS.Utils

local MainFrame = HooligansLoot:NewModule("MainFrame")

-- Frame references
local mainFrame = nil
local itemRows = {}
local updateTimer = nil
local isRefreshing = false

-- Constants
local ROW_HEIGHT = 50
local MAX_VISIBLE_ROWS = 8
local FRAME_WIDTH = 700
local FRAME_HEIGHT = 520

function MainFrame:OnEnable()
    HooligansLoot:Debug("MainFrame:OnEnable - Registering callbacks")

    -- Register for callbacks
    HooligansLoot.RegisterCallback(self, "ITEM_ADDED", "Refresh")
    HooligansLoot.RegisterCallback(self, "ITEM_REMOVED", "Refresh")
    HooligansLoot.RegisterCallback(self, "SESSION_STARTED", "Refresh")
    HooligansLoot.RegisterCallback(self, "SESSION_ENDED", "Refresh")
    HooligansLoot.RegisterCallback(self, "SESSION_UPDATED", "Refresh")
    HooligansLoot.RegisterCallback(self, "AWARD_SET", "Refresh")
    HooligansLoot.RegisterCallback(self, "AWARD_COMPLETED", "Refresh")
    HooligansLoot.RegisterCallback(self, "AWARDS_IMPORTED", "Refresh")

    HooligansLoot:Debug("MainFrame:OnEnable - Callbacks registered")
end

function MainFrame:CreateFrame()
    if mainFrame then return mainFrame end

    local frame = CreateFrame("Frame", "HooligansLootMainFrame", UIParent, "BackdropTemplate")
    frame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    frame:SetPoint("TOP", UIParent, "TOP", 0, -50)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("HIGH")
    frame:Hide()

    -- Backdrop
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        edgeSize = 20,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0.08, 0.08, 0.1, 0.85)
    frame:SetBackdropBorderColor(0.6, 0.5, 0.3, 1)

    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)

    -- Settings button
    local settingsBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    settingsBtn:SetSize(80, 22)
    settingsBtn:SetPoint("TOPRIGHT", -35, -15)
    settingsBtn:SetText("Settings")
    settingsBtn:SetScript("OnClick", function()
        HooligansLoot:ShowSettings()
    end)
    frame.settingsBtn = settingsBtn

    -- History button
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

    -- Title bar background
    local titleBg = frame:CreateTexture(nil, "ARTWORK")
    titleBg:SetPoint("TOPLEFT", 4, -4)
    titleBg:SetPoint("TOPRIGHT", -4, -4)
    titleBg:SetHeight(50)
    titleBg:SetColorTexture(0.15, 0.12, 0.08, 0.9)

    -- Guild logo
    local logo = frame:CreateTexture(nil, "OVERLAY")
    logo:SetSize(44, 44)
    logo:SetPoint("TOPLEFT", 12, -6)
    logo:SetTexture("Interface\\AddOns\\HooligansLoot\\Textures\\logo")
    frame.logo = logo

    -- Title
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.title:SetPoint("LEFT", logo, "RIGHT", 8, 6)
    frame.title:SetText("|cffffffffHOOLIGANS Loot Council|r")

    -- Version text
    local addonVersion = Utils.GetAddonVersion()
    frame.versionText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.versionText:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -6)
    frame.versionText:SetText("|cffaaaaaa v" .. addonVersion .. "|r")

    -- Session info bar
    local sessionBar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    sessionBar:SetPoint("TOPLEFT", 10, -56)
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

    -- Session name
    sessionBar.name = sessionBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    sessionBar.name:SetPoint("LEFT", 10, 0)
    sessionBar.name:SetText("No active session")
    sessionBar.name:SetTextColor(1, 0.82, 0)

    -- Session status
    sessionBar.status = sessionBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sessionBar.status:SetPoint("RIGHT", -10, 0)

    -- New Session button
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
    renameBtn:SetScript("OnClick", function()
        MainFrame:ShowRenameDialog()
    end)
    sessionBar.renameBtn = renameBtn

    -- Column headers
    local headerBar = CreateFrame("Frame", nil, frame)
    headerBar:SetPoint("TOPLEFT", 10, -93)
    headerBar:SetPoint("TOPRIGHT", -30, -93)
    headerBar:SetHeight(20)

    local colItem = headerBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    colItem:SetPoint("LEFT", 5, 0)
    colItem:SetText("ITEM")
    colItem:SetTextColor(0.9, 0.8, 0.5)

    local colAwarded = headerBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    colAwarded:SetPoint("LEFT", 350, 0)
    colAwarded:SetWidth(120)
    colAwarded:SetJustifyH("CENTER")
    colAwarded:SetText("AWARDED TO")
    colAwarded:SetTextColor(0.9, 0.8, 0.5)

    local colTimer = headerBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    colTimer:SetPoint("RIGHT", -40, 0)
    colTimer:SetWidth(80)
    colTimer:SetJustifyH("CENTER")
    colTimer:SetText("TIMER")
    colTimer:SetTextColor(0.9, 0.8, 0.5)

    -- Divider line
    local divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", 10, -113)
    divider:SetPoint("TOPRIGHT", -10, -113)
    divider:SetHeight(1)
    divider:SetColorTexture(0.3, 0.3, 0.3, 1)

    -- Scroll frame for items
    local scrollFrame = CreateFrame("ScrollFrame", "HooligansLootItemScroll", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 10, -118)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 80)
    frame.scrollFrame = scrollFrame

    -- Scroll child
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(640, 1)
    scrollFrame:SetScrollChild(content)
    frame.content = content

    -- Bottom divider
    local bottomDivider = frame:CreateTexture(nil, "ARTWORK")
    bottomDivider:SetPoint("BOTTOMLEFT", 10, 75)
    bottomDivider:SetPoint("BOTTOMRIGHT", -10, 75)
    bottomDivider:SetHeight(1)
    bottomDivider:SetColorTexture(0.3, 0.3, 0.3, 1)

    -- Button bar at bottom
    local buttonBar = CreateFrame("Frame", nil, frame)
    buttonBar:SetPoint("BOTTOMLEFT", 10, 8)
    buttonBar:SetPoint("BOTTOMRIGHT", -10, 8)
    buttonBar:SetHeight(55)
    frame.buttonBar = buttonBar

    -- Stats display
    frame.stats = buttonBar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.stats:SetPoint("TOP", 0, 0)
    frame.stats:SetJustifyH("CENTER")

    -- Button row
    local btnHeight = 26
    local btnSpacing = 4

    -- Left side buttons
    local exportBtn = CreateFrame("Button", nil, buttonBar, "UIPanelButtonTemplate")
    exportBtn:SetSize(60, btnHeight)
    exportBtn:SetPoint("BOTTOMLEFT", 0, 0)
    exportBtn:SetText("Export")
    exportBtn:SetScript("OnClick", function()
        HooligansLoot:ShowExportDialog()
    end)
    frame.exportBtn = exportBtn

    local importBtn = CreateFrame("Button", nil, buttonBar, "UIPanelButtonTemplate")
    importBtn:SetSize(60, btnHeight)
    importBtn:SetPoint("LEFT", exportBtn, "RIGHT", btnSpacing, 0)
    importBtn:SetText("Import")
    importBtn:SetScript("OnClick", function()
        HooligansLoot:ShowImportDialog()
    end)
    frame.importBtn = importBtn

    local announceBtn = CreateFrame("Button", nil, buttonBar, "UIPanelButtonTemplate")
    announceBtn:SetSize(75, btnHeight)
    announceBtn:SetPoint("LEFT", importBtn, "RIGHT", btnSpacing, 0)
    announceBtn:SetText("Announce")
    announceBtn:SetScript("OnClick", function()
        HooligansLoot:AnnounceAwardsWithRaidWarning()
    end)
    frame.announceBtn = announceBtn

    local addItemBtn = CreateFrame("Button", nil, buttonBar, "UIPanelButtonTemplate")
    addItemBtn:SetSize(50, btnHeight)
    addItemBtn:SetPoint("LEFT", announceBtn, "RIGHT", btnSpacing, 0)
    addItemBtn:SetText("Add")
    addItemBtn:SetScript("OnClick", function()
        MainFrame:ShowAddItemDialog()
    end)
    frame.addItemBtn = addItemBtn

    local refreshBtn = CreateFrame("Button", nil, buttonBar, "UIPanelButtonTemplate")
    refreshBtn:SetSize(60, btnHeight)
    refreshBtn:SetPoint("LEFT", addItemBtn, "RIGHT", btnSpacing, 0)
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

    -- Right side buttons
    local endSessionBtn = CreateFrame("Button", nil, buttonBar, "UIPanelButtonTemplate")
    endSessionBtn:SetSize(50, btnHeight)
    endSessionBtn:SetPoint("BOTTOMRIGHT", 0, 0)
    endSessionBtn:SetText("End")
    endSessionBtn:SetScript("OnClick", function()
        HooligansLoot:GetModule("SessionManager"):EndSession()
        MainFrame:Refresh()
    end)
    frame.endSessionBtn = endSessionBtn

    local testBtn = CreateFrame("Button", nil, buttonBar, "UIPanelButtonTemplate")
    testBtn:SetSize(50, btnHeight)
    testBtn:SetPoint("RIGHT", endSessionBtn, "LEFT", -btnSpacing, 0)
    testBtn:SetText("Test")
    testBtn:SetScript("OnClick", function()
        HooligansLoot:RunTest("kara")
        MainFrame:Refresh()
    end)
    frame.testBtn = testBtn

    -- OnShow/OnHide handlers
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

function MainFrame:CreateItemRow(parent, index)
    local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -((index - 1) * ROW_HEIGHT))
    row:SetPoint("TOPRIGHT", 0, -((index - 1) * ROW_HEIGHT))

    -- Background
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
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 10, 8)
    row.name:SetWidth(280)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    -- Boss name
    row.boss = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.boss:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
    row.boss:SetJustifyH("LEFT")
    row.boss:SetTextColor(0.5, 0.5, 0.5)

    -- Awarded player
    row.awardedTo = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.awardedTo:SetPoint("LEFT", 350, 0)
    row.awardedTo:SetWidth(120)
    row.awardedTo:SetJustifyH("CENTER")

    -- Trade timer
    row.timer = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.timer:SetPoint("RIGHT", -40, 0)
    row.timer:SetWidth(80)
    row.timer:SetJustifyH("CENTER")

    -- Remove button
    row.removeBtn = CreateFrame("Button", nil, row)
    row.removeBtn:SetSize(18, 18)
    row.removeBtn:SetPoint("RIGHT", -2, 0)
    row.removeBtn:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
    row.removeBtn:SetHighlightTexture("Interface\\Buttons\\UI-StopButton")
    row.removeBtn:GetHighlightTexture():SetVertexColor(1, 0.3, 0.3, 0.8)
    row.removeBtn:SetScript("OnClick", function(self)
        local itemGUID = self:GetParent().itemGUID
        if itemGUID then
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
    row.removeBtn:Hide()

    -- Tooltip and click handlers
    row:EnableMouse(true)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnEnter", function(self)
        self.highlight:Show()
        if self.removeBtn then
            self.removeBtn:Show()
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
            local playerName = UnitName("player")
            local _, playerClass = UnitClass("player")
            table.insert(members, { name = playerName, class = playerClass })
            for i = 1, GetNumGroupMembers() - 1 do
                local name = UnitName("party" .. i)
                local _, classFile = UnitClass("party" .. i)
                if name then
                    table.insert(members, { name = name, class = classFile })
                end
            end
        else
            local playerName = UnitName("player")
            local _, playerClass = UnitClass("player")
            table.insert(members, { name = playerName, class = playerClass })
        end

        table.sort(members, function(a, b) return a.name < b.name end)

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

        -- Cancel
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
    if not item or not row then
        if row then row:Hide() end
        return
    end

    -- Icon
    if item.icon and item.icon ~= "Interface\\Icons\\INV_Misc_QuestionMark" then
        row.icon:SetTexture(item.icon)
    else
        row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        if item.id then
            local LootTracker = HooligansLoot:GetModule("LootTracker", true)
            if LootTracker then
                LootTracker:RequestItemInfo(item.id)
            end
        end
    end

    -- Name with quality color
    local qualityColor = Utils.GetQualityColor(item.quality or 4)
    local displayName = item.name or "Unknown Item"
    row.name:SetText("|cff" .. qualityColor .. displayName .. "|r")

    -- Boss
    row.boss:SetText(item.boss or "Unknown")

    -- Trade timer with color coding
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

    -- Award status
    if award then
        local coloredName = Utils.GetColoredPlayerName(award.winner, award.class)
        row.awardedTo:SetText(coloredName)
    else
        row.awardedTo:SetText("|cff666666---|r")
    end

    row.itemLink = item.link
    row.itemGUID = item.guid

    row:Show()
end

function MainFrame:Refresh()
    if not mainFrame or not mainFrame:IsShown() then return end

    if isRefreshing then
        return
    end
    isRefreshing = true

    local success, err = pcall(function()
        self:DoRefresh()
    end)

    isRefreshing = false

    if not success then
        HooligansLoot:Debug("MainFrame:Refresh - ERROR: " .. tostring(err))
    end
end

function MainFrame:DoRefresh()
    local SessionManager = HooligansLoot:GetModule("SessionManager")
    local session = SessionManager:GetCurrentSession()

    -- Update session bar
    if session then
        local dateStr = session.created and date("%Y-%m-%d %H:%M", session.created) or ""
        mainFrame.sessionBar.name:SetText(session.name .. " - " .. dateStr)

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

        mainFrame.endSessionBtn:SetEnabled(session.status == "active")
        mainFrame.sessionBar.renameBtn:SetEnabled(true)
        mainFrame.addItemBtn:SetEnabled(true)
        mainFrame.sessionBar.newBtn:SetEnabled(true)
    else
        mainFrame.sessionBar.name:SetText("No active session")
        mainFrame.sessionBar.status:SetText("|cff888888Click 'New' to start|r")
        mainFrame.sessionBar.newBtn:SetEnabled(true)
        mainFrame.endSessionBtn:SetEnabled(false)
        mainFrame.sessionBar.renameBtn:SetEnabled(false)
        mainFrame.addItemBtn:SetEnabled(false)
    end

    -- Clear existing rows
    for _, row in ipairs(itemRows) do
        row:Hide()
        row:SetParent(nil)
    end
    wipe(itemRows)

    -- Populate items
    if session and session.items and #session.items > 0 then
        local sortedItems = {}
        for _, item in ipairs(session.items) do
            table.insert(sortedItems, item)
        end
        table.sort(sortedItems, function(a, b) return (a.timestamp or 0) > (b.timestamp or 0) end)

        for i, item in ipairs(sortedItems) do
            if not itemRows[i] then
                itemRows[i] = self:CreateItemRow(mainFrame.content, i)
            end

            local award = session.awards and session.awards[item.guid] or nil
            self:UpdateItemRow(itemRows[i], item, award)
        end

        mainFrame.content:SetHeight(#sortedItems * ROW_HEIGHT)

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

        if session then
            mainFrame.stats:SetText("|cff888888Session is empty - use 'Test' to add test items|r")
        else
            mainFrame.stats:SetText("|cff888888No session active|r")
        end

        if not itemRows[1] then
            itemRows[1] = self:CreateItemRow(mainFrame.content, 1)
        end
        itemRows[1].icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        itemRows[1].name:SetText("|cff666666No items tracked|r")
        itemRows[1].boss:SetText(session and "Use 'Test' or loot items in a raid" or "Create a session first")
        itemRows[1].awardedTo:SetText("")
        itemRows[1].timer:SetText("")
        itemRows[1].itemLink = nil
        itemRows[1]:Show()
    end
end

function MainFrame:StartUpdateTimer()
    if updateTimer then return end

    updateTimer = C_Timer.NewTicker(1, function()
        if mainFrame and mainFrame:IsShown() then
            local SessionManager = HooligansLoot:GetModule("SessionManager")
            local session = SessionManager:GetCurrentSession()

            if session then
                for _, row in ipairs(itemRows) do
                    if row:IsShown() and row.itemGUID then
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

        local editBox = CreateFrame("EditBox", nil, dialog, "InputBoxTemplate")
        editBox:SetSize(300, 22)
        editBox:SetPoint("TOP", 0, -45)
        editBox:SetAutoFocus(true)
        editBox:SetScript("OnEscapePressed", function() dialog:Hide() end)
        editBox:SetScript("OnEnterPressed", function(self)
            local newName = self:GetText()
            if newName and newName ~= "" then
                SessionManager:RenameSession(nil, newName)
                MainFrame:Refresh()
            end
            dialog:Hide()
        end)
        dialog.editBox = editBox

        local saveBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
        saveBtn:SetSize(80, 22)
        saveBtn:SetPoint("BOTTOMRIGHT", -15, 15)
        saveBtn:SetText("Save")
        saveBtn:SetScript("OnClick", function()
            local newName = editBox:GetText()
            if newName and newName ~= "" then
                SessionManager:RenameSession(nil, newName)
                MainFrame:Refresh()
            end
            dialog:Hide()
        end)

        local cancelBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
        cancelBtn:SetSize(80, 22)
        cancelBtn:SetPoint("RIGHT", saveBtn, "LEFT", -5, 0)
        cancelBtn:SetText("Cancel")
        cancelBtn:SetScript("OnClick", function() dialog:Hide() end)

        tinsert(UISpecialFrames, "HooligansLootRenameDialog")
        renameDialog = dialog
    end

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

        local linkLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        linkLabel:SetPoint("TOPLEFT", 20, -45)
        linkLabel:SetText("Item Link:")
        linkLabel:SetTextColor(0.9, 0.8, 0.5)

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
                    self:SetText("")
                    self:SetFocus()
                end
            end
        end)
        dialog.linkEditBox = linkEditBox

        -- Hook for shift-click
        local originalHandleModifiedItemClick = HandleModifiedItemClick
        HandleModifiedItemClick = function(link, ...)
            if linkEditBox:IsVisible() and linkEditBox:HasFocus() and link then
                linkEditBox:SetText(link)
                return true
            end
            return originalHandleModifiedItemClick(link, ...)
        end

        local originalChatEdit_InsertLink = ChatEdit_InsertLink
        ChatEdit_InsertLink = function(link)
            if linkEditBox:IsVisible() and linkEditBox:HasFocus() and link then
                linkEditBox:SetText(link)
                return true
            end
            return originalChatEdit_InsertLink(link)
        end

        -- Drag and drop support
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

        local instructions = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        instructions:SetPoint("TOP", linkEditBox, "BOTTOM", 0, -5)
        instructions:SetText("Shift-click or drag an item here, then press Enter or Add")
        instructions:SetTextColor(0.6, 0.6, 0.6)

        local doneBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
        doneBtn:SetSize(70, 22)
        doneBtn:SetPoint("BOTTOMRIGHT", -15, 15)
        doneBtn:SetText("Done")
        doneBtn:SetScript("OnClick", function() dialog:Hide() end)

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
                    linkEditBox:SetText("")
                    linkEditBox:SetFocus()
                end
            end
        end)

        tinsert(UISpecialFrames, "HooligansLootAddItemDialog")
        addItemDialog = dialog
    end

    addItemDialog.linkEditBox:SetText("")
    addItemDialog:Show()
end
