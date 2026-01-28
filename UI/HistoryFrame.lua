-- UI/HistoryFrame.lua
-- Loot History window - displays all awarded items across all sessions

local ADDON_NAME, NS = ...
local HooligansLoot = NS.addon
local Utils = NS.Utils

local HistoryFrame = HooligansLoot:NewModule("HistoryFrame")

-- Frame references
local historyFrame = nil
local historyRows = {}

-- Constants
local ROW_HEIGHT = 32
local MAX_VISIBLE_ROWS = 12
local FRAME_WIDTH = 550
local FRAME_HEIGHT = 500

-- Filter state (session only)
-- nil = no session selected (empty view), "all" = all sessions, string = specific session id
local currentFilters = {
    session = nil,
}

function HistoryFrame:OnEnable()
    -- Nothing to do on enable
end

function HistoryFrame:CreateFrame()
    if historyFrame then return historyFrame end

    -- Main frame - will be positioned relative to MainFrame in Show()
    local frame = CreateFrame("Frame", "HooligansLootHistoryFrame", UIParent, "BackdropTemplate")
    frame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    frame:SetPoint("CENTER", 400, 0) -- Default position, will be updated in Show()
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("HIGH")
    frame:Hide()

    -- Backdrop (matching MainFrame style)
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

    -- Make closable with Escape
    tinsert(UISpecialFrames, "HooligansLootHistoryFrame")

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

    -- Title
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.title:SetPoint("LEFT", logo, "RIGHT", 8, 0)
    frame.title:SetText("|cffffffffHOOLIGANS Loot Council - History|r")

    -- Filter bar
    local filterBar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    filterBar:SetPoint("TOPLEFT", 10, -56)
    filterBar:SetPoint("TOPRIGHT", -10, -56)
    filterBar:SetHeight(32)
    filterBar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    filterBar:SetBackdropColor(0.1, 0.1, 0.15, 0.9)
    filterBar:SetBackdropBorderColor(0.3, 0.3, 0.4, 1)
    frame.filterBar = filterBar

    -- Session label and dropdown only
    local sessionLabel = filterBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sessionLabel:SetPoint("LEFT", 8, 0)
    sessionLabel:SetText("Session:")
    sessionLabel:SetTextColor(0.9, 0.8, 0.5)

    -- Session dropdown
    frame.sessionDropdown = self:CreateDropdown(filterBar, "session", "Select Session...", 55, 3, 130)

    -- Delete All button
    local deleteAllBtn = CreateFrame("Button", nil, filterBar, "UIPanelButtonTemplate")
    deleteAllBtn:SetSize(70, 20)
    deleteAllBtn:SetPoint("RIGHT", -5, 0)
    deleteAllBtn:SetText("Delete All")
    deleteAllBtn:SetScript("OnClick", function()
        local SessionManager = HooligansLoot:GetModule("SessionManager")
        local sessionCount = Utils.TableSize(HooligansLoot.db.profile.sessions)

        if sessionCount == 0 then
            HooligansLoot:Print("No sessions to delete.")
            return
        end

        StaticPopupDialogs["HOOLIGANS_CONFIRM_DELETE_ALL_SESSIONS"] = {
            text = "Delete ALL " .. sessionCount .. " sessions?\n\nThis will permanently remove all loot history and cannot be undone!",
            button1 = "Delete All",
            button2 = "Cancel",
            OnAccept = function()
                -- Delete all sessions
                for sessionId in pairs(HooligansLoot.db.profile.sessions) do
                    SessionManager:DeleteSession(sessionId)
                end
                currentFilters.session = nil
                UIDropDownMenu_SetText(historyFrame.sessionDropdown, "Select Session...")
                HistoryFrame:UpdateDeleteButton()
                HistoryFrame:PopulateFilterDropdowns()
                HistoryFrame:Refresh()
                HooligansLoot:Print("All sessions deleted.")
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }
        StaticPopup_Show("HOOLIGANS_CONFIRM_DELETE_ALL_SESSIONS")
    end)
    deleteAllBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Delete all sessions")
        GameTooltip:Show()
    end)
    deleteAllBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.deleteAllBtn = deleteAllBtn

    -- Delete session button
    local deleteBtn = CreateFrame("Button", nil, filterBar, "UIPanelButtonTemplate")
    deleteBtn:SetSize(60, 20)
    deleteBtn:SetPoint("RIGHT", deleteAllBtn, "LEFT", -5, 0)
    deleteBtn:SetText("Delete")
    deleteBtn:SetScript("OnClick", function()
        -- Only allow delete when a specific session is selected (not nil and not "all")
        if currentFilters.session and currentFilters.session ~= "all" then
            local SessionManager = HooligansLoot:GetModule("SessionManager")
            local session = SessionManager:GetSession(currentFilters.session)
            local sessionName = session and session.name or "this session"

            StaticPopupDialogs["HOOLIGANS_CONFIRM_DELETE_SESSION"] = {
                text = "Delete session: " .. sessionName .. "?\n\nThis will permanently remove all items and awards in this session.",
                button1 = "Delete",
                button2 = "Cancel",
                OnAccept = function()
                    SessionManager:DeleteSession(currentFilters.session)
                    currentFilters.session = nil
                    UIDropDownMenu_SetText(historyFrame.sessionDropdown, "Select Session...")
                    HistoryFrame:UpdateDeleteButton()
                    HistoryFrame:PopulateFilterDropdowns()
                    HistoryFrame:Refresh()
                end,
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
            }
            StaticPopup_Show("HOOLIGANS_CONFIRM_DELETE_SESSION")
        end
    end)
    deleteBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        if currentFilters.session and currentFilters.session ~= "all" then
            GameTooltip:SetText("Delete selected session")
        else
            GameTooltip:SetText("Select a session to delete")
        end
        GameTooltip:Show()
    end)
    deleteBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.deleteBtn = deleteBtn

    -- Column headers
    local headerBar = CreateFrame("Frame", nil, frame)
    headerBar:SetPoint("TOPLEFT", 10, -93)
    headerBar:SetPoint("TOPRIGHT", -30, -93)
    headerBar:SetHeight(20)

    local colItem = headerBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    colItem:SetPoint("LEFT", 5, 0)
    colItem:SetText("ITEM")
    colItem:SetTextColor(0.9, 0.8, 0.5)

    local colWinner = headerBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    colWinner:SetPoint("LEFT", 190, 0)
    colWinner:SetWidth(90)
    colWinner:SetText("WINNER")
    colWinner:SetTextColor(0.9, 0.8, 0.5)

    local colBoss = headerBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    colBoss:SetPoint("LEFT", 290, 0)
    colBoss:SetWidth(90)
    colBoss:SetText("BOSS")
    colBoss:SetTextColor(0.9, 0.8, 0.5)

    local colDate = headerBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    colDate:SetPoint("RIGHT", 0, 0)
    colDate:SetWidth(60)
    colDate:SetJustifyH("CENTER")
    colDate:SetText("DATE")
    colDate:SetTextColor(0.9, 0.8, 0.5)

    -- Divider line
    local divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", 10, -113)
    divider:SetPoint("TOPRIGHT", -10, -113)
    divider:SetHeight(1)
    divider:SetColorTexture(0.3, 0.3, 0.3, 1)

    -- Scroll frame for history rows
    local scrollFrame = CreateFrame("ScrollFrame", "HooligansLootHistoryScroll", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 10, -118)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 70)
    frame.scrollFrame = scrollFrame

    -- Scroll child (content frame)
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(scrollFrame:GetWidth(), 1)
    scrollFrame:SetScrollChild(content)
    frame.content = content

    -- Bottom divider
    local bottomDivider = frame:CreateTexture(nil, "ARTWORK")
    bottomDivider:SetPoint("BOTTOMLEFT", 10, 65)
    bottomDivider:SetPoint("BOTTOMRIGHT", -10, 65)
    bottomDivider:SetHeight(1)
    bottomDivider:SetColorTexture(0.3, 0.3, 0.3, 1)

    -- Stats bar
    frame.stats = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.stats:SetPoint("BOTTOMLEFT", 15, 40)
    frame.stats:SetJustifyH("LEFT")

    -- Bottom buttons
    local exportBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    exportBtn:SetSize(80, 26)
    exportBtn:SetPoint("BOTTOMRIGHT", -100, 10)
    exportBtn:SetText("Export")
    exportBtn:SetScript("OnClick", function()
        HistoryFrame:ShowExportMenu()
    end)

    local closeButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    closeButton:SetSize(80, 26)
    closeButton:SetPoint("BOTTOMRIGHT", -10, 10)
    closeButton:SetText("Close")
    closeButton:SetScript("OnClick", function() frame:Hide() end)

    -- OnShow handler
    frame:SetScript("OnShow", function()
        HistoryFrame:PopulateFilterDropdowns()
        HistoryFrame:Refresh()
    end)

    historyFrame = frame
    return frame
end

function HistoryFrame:CreateDropdown(parent, filterType, defaultText, xOffset, yOffset, width)
    local dropdown = CreateFrame("Frame", "HooligansHistoryDropdown_" .. filterType, parent, "UIDropDownMenuTemplate")
    dropdown:SetPoint("TOPLEFT", xOffset, yOffset)
    UIDropDownMenu_SetWidth(dropdown, width or 90)
    UIDropDownMenu_SetText(dropdown, defaultText)
    return dropdown
end

function HistoryFrame:UpdateDeleteButton()
    if not historyFrame or not historyFrame.deleteBtn then return end

    -- Enable/disable delete button based on selection
    local canDelete = currentFilters.session and currentFilters.session ~= "all"
    if canDelete then
        historyFrame.deleteBtn:Enable()
        historyFrame.deleteBtn:SetAlpha(1)
    else
        historyFrame.deleteBtn:Disable()
        historyFrame.deleteBtn:SetAlpha(0.5)
    end
end

function HistoryFrame:PopulateFilterDropdowns()
    if not historyFrame then return end

    -- Collect unique sessions
    local sessions = {}
    for sessionId, session in pairs(HooligansLoot.db.profile.sessions) do
        sessions[sessionId] = session.name
    end

    -- Session dropdown
    UIDropDownMenu_Initialize(historyFrame.sessionDropdown, function(frame, level)
        local info = UIDropDownMenu_CreateInfo()

        -- All sessions option
        info.text = "All Sessions"
        info.value = "all"
        info.checked = (currentFilters.session == "all")
        info.func = function()
            currentFilters.session = "all"
            UIDropDownMenu_SetText(historyFrame.sessionDropdown, "All Sessions")
            HistoryFrame:UpdateDeleteButton()
            HistoryFrame:Refresh()
        end
        UIDropDownMenu_AddButton(info)

        -- Individual sessions (sorted by date, newest first)
        local sortedSessions = {}
        for id, name in pairs(sessions) do
            local session = HooligansLoot.db.profile.sessions[id]
            table.insert(sortedSessions, { id = id, name = name, created = session and session.created or 0 })
        end
        table.sort(sortedSessions, function(a, b) return a.created > b.created end)

        for _, sess in ipairs(sortedSessions) do
            info.text = sess.name
            info.value = sess.id
            info.checked = (currentFilters.session == sess.id)
            info.func = function()
                currentFilters.session = sess.id
                UIDropDownMenu_SetText(historyFrame.sessionDropdown, sess.name)
                HistoryFrame:UpdateDeleteButton()
                HistoryFrame:Refresh()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    -- Update delete button state
    self:UpdateDeleteButton()
end

function HistoryFrame:GetAllHistoryRecords()
    local records = {}
    local sessions = HooligansLoot.db.profile.sessions

    for sessionId, session in pairs(sessions) do
        for _, item in ipairs(session.items) do
            local award = session.awards[item.guid]
            if award then
                table.insert(records, {
                    item = item,
                    award = award,
                    session = session,
                    timestamp = award.awardedAt or item.timestamp or session.created,
                })
            end
        end
    end

    -- Sort by timestamp (newest first)
    table.sort(records, function(a, b) return (a.timestamp or 0) > (b.timestamp or 0) end)

    return records
end

function HistoryFrame:PassesFilters(record)
    -- nil = no session selected, show nothing
    if currentFilters.session == nil then
        return false
    end
    -- "all" = show all sessions
    if currentFilters.session == "all" then
        return true
    end
    -- Specific session filter
    if record.session.id ~= currentFilters.session then
        return false
    end
    return true
end

function HistoryFrame:GetFilteredRecords()
    local allRecords = self:GetAllHistoryRecords()
    local filtered = {}

    for _, record in ipairs(allRecords) do
        if self:PassesFilters(record) then
            table.insert(filtered, record)
        end
    end

    return filtered
end

function HistoryFrame:CalculateStats(records)
    local players = {}
    local sessions = {}
    local traded = 0
    local pending = 0

    for _, r in ipairs(records) do
        players[r.award.winner] = true
        sessions[r.session.id] = true
        if r.award.awarded then
            traded = traded + 1
        else
            pending = pending + 1
        end
    end

    local total = traded + pending
    local tradePercent = total > 0 and math.floor((traded / total) * 100) or 0

    return {
        totalItems = #records,
        uniquePlayers = Utils.TableSize(players),
        uniqueSessions = Utils.TableSize(sessions),
        tradedCount = traded,
        pendingCount = pending,
        tradePercent = tradePercent,
    }
end

function HistoryFrame:CreateHistoryRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -((index - 1) * ROW_HEIGHT))
    row:SetPoint("TOPRIGHT", 0, -((index - 1) * ROW_HEIGHT))

    -- Background (alternating)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    if index % 2 == 0 then
        row.bg:SetColorTexture(0.12, 0.12, 0.14, 0.6)
    else
        row.bg:SetColorTexture(0.06, 0.06, 0.08, 0.4)
    end

    -- Hover highlight
    row.highlight = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.highlight:SetAllPoints()
    row.highlight:SetColorTexture(0.4, 0.35, 0.2, 0.4)
    row.highlight:Hide()

    -- Item icon
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(24, 24)
    row.icon:SetPoint("LEFT", 5, 0)

    -- Item name
    row.itemName = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.itemName:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
    row.itemName:SetWidth(150)
    row.itemName:SetJustifyH("LEFT")
    row.itemName:SetWordWrap(false)

    -- Winner name (class-colored)
    row.winner = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.winner:SetPoint("LEFT", 190, 0)
    row.winner:SetWidth(90)
    row.winner:SetJustifyH("LEFT")

    -- Boss name
    row.boss = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.boss:SetPoint("LEFT", 290, 0)
    row.boss:SetWidth(90)
    row.boss:SetJustifyH("LEFT")
    row.boss:SetTextColor(0.6, 0.6, 0.6)

    -- Date
    row.date = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.date:SetPoint("RIGHT", 0, 0)
    row.date:SetWidth(60)
    row.date:SetJustifyH("CENTER")
    row.date:SetTextColor(0.6, 0.6, 0.6)

    -- Tooltip and highlight on hover
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        self.highlight:Show()
        if self.itemLink then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(self.itemLink)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function(self)
        self.highlight:Hide()
        GameTooltip:Hide()
    end)

    row:Hide()
    return row
end

function HistoryFrame:UpdateHistoryRow(row, record)
    if not record then
        row:Hide()
        return
    end

    local item = record.item
    local award = record.award
    local session = record.session

    -- Item icon
    if item.icon and item.icon ~= "" then
        row.icon:SetTexture(item.icon)
    else
        row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end

    -- Item name (with quality color)
    local qualityColor = Utils.GetQualityColor(item.quality or 4)
    row.itemName:SetText("|cff" .. qualityColor .. (item.name or "Unknown Item") .. "|r")

    -- Winner (with class color)
    row.winner:SetText(Utils.GetColoredPlayerName(award.winner, award.class))

    -- Boss
    row.boss:SetText(item.boss or "Unknown")

    -- Date (MM/DD format)
    local timestamp = record.timestamp or item.timestamp or session.created
    if timestamp then
        row.date:SetText(date("%m/%d", timestamp))
    else
        row.date:SetText("")
    end

    -- Store item link for tooltip
    row.itemLink = item.link

    row:Show()
end

function HistoryFrame:Refresh()
    if not historyFrame or not historyFrame:IsShown() then return end

    -- Clear existing rows
    for _, row in ipairs(historyRows) do
        row:Hide()
    end

    -- Get filtered records
    local records = self:GetFilteredRecords()

    if #records == 0 then
        -- Show empty message
        if not historyRows[1] then
            historyRows[1] = self:CreateHistoryRow(historyFrame.content, 1)
        end
        historyRows[1].icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")

        -- Different message based on filter state
        if currentFilters.session == nil then
            historyRows[1].itemName:SetText("|cff888888Select a session to view history|r")
            historyFrame.stats:SetText("|cff888888Select a session from the dropdown above|r")
        else
            historyRows[1].itemName:SetText("|cff666666No history to display|r")
            historyFrame.stats:SetText("|cff888888No awarded items found|r")
        end

        historyRows[1].winner:SetText("")
        historyRows[1].boss:SetText("")
        historyRows[1].date:SetText("")
        historyRows[1].itemLink = nil
        historyRows[1]:Show()

        historyFrame.content:SetHeight(ROW_HEIGHT)
        return
    end

    -- Populate rows
    for i, record in ipairs(records) do
        if not historyRows[i] then
            historyRows[i] = self:CreateHistoryRow(historyFrame.content, i)
        end
        self:UpdateHistoryRow(historyRows[i], record)
    end

    -- Set content height
    historyFrame.content:SetHeight(#records * ROW_HEIGHT)

    -- Update stats
    local stats = self:CalculateStats(records)
    local statsText = string.format(
        "|cffffffffItems:|r %d  |cff88ccffPlayers:|r %d  |cffffff88Sessions:|r %d",
        stats.totalItems,
        stats.uniquePlayers,
        stats.uniqueSessions
    )
    historyFrame.stats:SetText(statsText)
end

function HistoryFrame:ShowExportMenu()
    local records = self:GetFilteredRecords()
    if #records == 0 then
        HooligansLoot:Print("No history records to export.")
        return
    end

    -- Export to platform JSON format
    local exportData = {
        items = {},
    }

    for _, record in ipairs(records) do
        -- Get item level if available
        local ilvl = 0
        if record.item.id then
            local _, _, _, itemLevel = GetItemInfo(record.item.id)
            ilvl = itemLevel or 0
        end

        table.insert(exportData.items, {
            itemName = record.item.name or "Unknown",
            wowheadId = record.item.id,
            quality = record.item.quality or 4,
            ilvl = ilvl,
            boss = record.item.boss,
            timestamp = record.timestamp or record.item.timestamp,
            winner = record.award.winner,
            status = record.award.awarded and "traded" or "pending",
        })
    end

    local jsonData = Utils.ToJSON(exportData)
    self:ShowExportDialog(jsonData, #records)
end

-- Reusable export dialog for history
local historyExportDialog = nil

function HistoryFrame:ShowExportDialog(text, itemCount)
    if not historyExportDialog then
        local dialog = CreateFrame("Frame", "HooligansHistoryExportDialog", UIParent, "BackdropTemplate")
        dialog:SetSize(450, 350)
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

        local title = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", 0, -15)
        title:SetText(HooligansLoot.colors.primary .. "HOOLIGANS|r History - Export")
        dialog.title = title

        dialog.info = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        dialog.info:SetPoint("TOP", title, "BOTTOM", 0, -5)
        dialog.info:SetTextColor(0.7, 0.7, 0.7)

        local closeBtn = CreateFrame("Button", nil, dialog, "UIPanelCloseButton")
        closeBtn:SetPoint("TOPRIGHT", -2, -2)
        closeBtn:SetScript("OnClick", function() dialog:Hide() end)

        local scrollFrame = CreateFrame("ScrollFrame", nil, dialog, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", 15, -55)
        scrollFrame:SetPoint("BOTTOMRIGHT", -35, 45)

        local editBox = CreateFrame("EditBox", nil, scrollFrame)
        editBox:SetMultiLine(true)
        editBox:SetFontObject("ChatFontNormal")
        editBox:SetWidth(scrollFrame:GetWidth())
        editBox:SetAutoFocus(true)
        editBox:EnableMouse(true)
        editBox:SetScript("OnEscapePressed", function() dialog:Hide() end)
        scrollFrame:SetScrollChild(editBox)
        dialog.editBox = editBox

        local copyLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        copyLabel:SetPoint("BOTTOMLEFT", 15, 15)
        copyLabel:SetText("Press Ctrl+C to copy")
        copyLabel:SetTextColor(0.7, 0.7, 0.7)

        tinsert(UISpecialFrames, "HooligansHistoryExportDialog")
        historyExportDialog = dialog
    end

    historyExportDialog.info:SetText(itemCount .. " items")
    historyExportDialog.editBox:SetText(text)
    historyExportDialog.editBox:HighlightText()
    historyExportDialog:Show()
end

function HistoryFrame:Show()
    local frame = self:CreateFrame()

    -- Position to the right of MainFrame if it exists and is shown
    local mainFrame = _G["HooligansLootMainFrame"]
    if mainFrame and mainFrame:IsShown() then
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", mainFrame, "TOPRIGHT", 10, 0)
    else
        -- Default position if main frame isn't shown
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", 200, 0)
    end

    frame:Show()
end

function HistoryFrame:Hide()
    if historyFrame then
        historyFrame:Hide()
    end
end

function HistoryFrame:Toggle()
    if historyFrame and historyFrame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

function HistoryFrame:IsShown()
    return historyFrame and historyFrame:IsShown()
end
