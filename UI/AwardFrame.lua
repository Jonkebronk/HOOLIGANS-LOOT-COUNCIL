-- UI/AwardFrame.lua
-- Automated award distribution dialog (Gargul-style)

local ADDON_NAME, NS = ...
local HooligansLoot = NS.addon
local Utils = NS.Utils

local AwardFrame = HooligansLoot:NewModule("AwardFrame", "AceEvent-3.0")

-- Frame references
local awardFrame = nil
local queueRows = {}
local draggedIndex = nil

-- State
local awardQueue = {}
local currentIndex = 0
local isRunning = false

-- Status constants
local STATUS = {
    PENDING = "pending",
    ANNOUNCING = "announcing",
    WAITING_TRADE = "waiting_trade",
    TRADING = "trading",
    COMPLETED = "completed",
    SKIPPED = "skipped",
}

-- Constants
local FRAME_WIDTH = 320
local FRAME_HEIGHT = 340
local ROW_HEIGHT = 26

function AwardFrame:OnEnable()
    self:RegisterEvent("TRADE_SHOW")
    self:RegisterEvent("UI_INFO_MESSAGE")
    HooligansLoot.RegisterCallback(self, "AWARD_COMPLETED", "OnAwardCompleted")
end

function AwardFrame:OnDisable()
    self:UnregisterAllEvents()
end

function AwardFrame:CreateFrame()
    if awardFrame then return awardFrame end

    local frame = CreateFrame("Frame", "HooligansLootAwardFrame", UIParent, "BackdropTemplate")
    frame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    frame:SetPoint("CENTER", 0, 50)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("HIGH")
    frame:Hide()

    -- Dark backdrop like Gargul
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    frame:SetBackdropColor(0.05, 0.05, 0.07, 0.95)
    frame:SetBackdropBorderColor(0.15, 0.15, 0.15, 1)

    -- Title bar
    local titleBar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    titleBar:SetPoint("TOPLEFT", 0, 0)
    titleBar:SetPoint("TOPRIGHT", 0, 0)
    titleBar:SetHeight(22)
    titleBar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
    })
    titleBar:SetBackdropColor(0.1, 0.1, 0.12, 1)

    -- Logo
    local logo = titleBar:CreateTexture(nil, "OVERLAY")
    logo:SetSize(18, 18)
    logo:SetPoint("LEFT", 4, 0)
    logo:SetTexture("Interface\\AddOns\\HooligansLoot\\Textures\\logo")

    -- Title
    local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("LEFT", logo, "RIGHT", 6, 0)
    title:SetText("Award Distribution")
    title:SetTextColor(0.9, 0.9, 0.9)

    -- Close button
    local closeBtn = CreateFrame("Button", nil, titleBar)
    closeBtn:SetSize(18, 18)
    closeBtn:SetPoint("RIGHT", -3, 0)
    closeBtn:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
    closeBtn:SetHighlightTexture("Interface\\Buttons\\UI-StopButton")
    closeBtn:GetHighlightTexture():SetVertexColor(1, 0.3, 0.3)
    closeBtn:SetScript("OnClick", function()
        AwardFrame:Stop()
        frame:Hide()
    end)

    tinsert(UISpecialFrames, "HooligansLootAwardFrame")

    -- Current item section
    local itemSection = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    itemSection:SetPoint("TOPLEFT", 8, -30)
    itemSection:SetPoint("TOPRIGHT", -8, -30)
    itemSection:SetHeight(50)
    itemSection:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    itemSection:SetBackdropColor(0.08, 0.08, 0.1, 1)
    itemSection:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
    frame.itemSection = itemSection

    -- Item icon
    itemSection.icon = itemSection:CreateTexture(nil, "ARTWORK")
    itemSection.icon:SetSize(40, 40)
    itemSection.icon:SetPoint("LEFT", 5, 0)

    -- Item name
    itemSection.itemName = itemSection:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    itemSection.itemName:SetPoint("TOPLEFT", itemSection.icon, "TOPRIGHT", 8, -2)
    itemSection.itemName:SetPoint("RIGHT", -5, 0)
    itemSection.itemName:SetJustifyH("LEFT")

    -- Winner / Status line
    itemSection.winner = itemSection:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    itemSection.winner:SetPoint("BOTTOMLEFT", itemSection.icon, "BOTTOMRIGHT", 8, 2)
    itemSection.winner:SetTextColor(0.7, 0.7, 0.7)

    -- Action buttons row
    local btnWidth = 58
    local btnHeight = 22
    local btnSpacing = 4
    local btnY = -88

    local function CreateActionButton(text, xOffset)
        local btn = CreateFrame("Button", nil, frame, "BackdropTemplate")
        btn:SetSize(btnWidth, btnHeight)
        btn:SetPoint("TOPLEFT", xOffset, btnY)
        btn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        btn:SetBackdropColor(0.6, 0.2, 0.2, 1)
        btn:SetBackdropBorderColor(0.3, 0.1, 0.1, 1)

        btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        btn.text:SetPoint("CENTER")
        btn.text:SetText(text)
        btn.text:SetTextColor(1, 1, 1)

        btn:SetScript("OnEnter", function(self)
            self:SetBackdropColor(0.7, 0.25, 0.25, 1)
        end)
        btn:SetScript("OnLeave", function(self)
            if self.disabled then
                self:SetBackdropColor(0.3, 0.3, 0.3, 1)
            else
                self:SetBackdropColor(0.6, 0.2, 0.2, 1)
            end
        end)

        btn.SetEnabled = function(self, enabled)
            self.disabled = not enabled
            if enabled then
                self:SetBackdropColor(0.6, 0.2, 0.2, 1)
                self.text:SetTextColor(1, 1, 1)
                self:EnableMouse(true)
            else
                self:SetBackdropColor(0.3, 0.3, 0.3, 1)
                self.text:SetTextColor(0.5, 0.5, 0.5)
                self:EnableMouse(false)
            end
        end

        return btn
    end

    local startX = 8
    frame.startBtn = CreateActionButton("Start", startX)
    frame.startBtn:SetScript("OnClick", function()
        if isRunning then
            AwardFrame:Stop()
        else
            AwardFrame:Start()
        end
    end)

    frame.skipBtn = CreateActionButton("Skip", startX + (btnWidth + btnSpacing))
    frame.skipBtn:SetScript("OnClick", function() AwardFrame:SkipCurrent() end)

    frame.nextBtn = CreateActionButton("Next", startX + 2 * (btnWidth + btnSpacing))
    frame.nextBtn:SetScript("OnClick", function() AwardFrame:AdvanceToNext() end)

    frame.announceBtn = CreateActionButton("Announce", startX + 3 * (btnWidth + btnSpacing))
    frame.announceBtn:SetScript("OnClick", function() AwardFrame:AnnounceCurrentOnly() end)

    frame.tradeBtn = CreateActionButton("Trade", startX + 4 * (btnWidth + btnSpacing))
    frame.tradeBtn:SetScript("OnClick", function() AwardFrame:InitiateTrade() end)

    -- Queue label
    local queueLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    queueLabel:SetPoint("TOPLEFT", 10, -118)
    queueLabel:SetText("|cff888888Queue (drag to reorder)|r")

    -- Queue list area
    local listBg = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    listBg:SetPoint("TOPLEFT", 8, -134)
    listBg:SetPoint("BOTTOMRIGHT", -8, 40)
    listBg:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    listBg:SetBackdropColor(0.04, 0.04, 0.05, 1)
    listBg:SetBackdropBorderColor(0.15, 0.15, 0.15, 1)
    frame.listBg = listBg

    -- Scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", "HooligansLootAwardScroll", listBg, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 2, -2)
    scrollFrame:SetPoint("BOTTOMRIGHT", -22, 2)
    frame.scrollFrame = scrollFrame

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(scrollFrame:GetWidth(), 1)
    scrollFrame:SetScrollChild(content)
    frame.content = content

    -- Bottom buttons
    local haltBtn = CreateFrame("Button", nil, frame, "BackdropTemplate")
    haltBtn:SetSize(145, 26)
    haltBtn:SetPoint("BOTTOMLEFT", 8, 8)
    haltBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    haltBtn:SetBackdropColor(0.5, 0.15, 0.15, 1)
    haltBtn:SetBackdropBorderColor(0.25, 0.1, 0.1, 1)

    haltBtn.text = haltBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    haltBtn.text:SetPoint("CENTER")
    haltBtn.text:SetText("Halt")

    haltBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.6, 0.2, 0.2, 1) end)
    haltBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.5, 0.15, 0.15, 1) end)
    haltBtn:SetScript("OnClick", function()
        AwardFrame:Stop()
        frame:Hide()
    end)
    frame.haltBtn = haltBtn

    local clearBtn = CreateFrame("Button", nil, frame, "BackdropTemplate")
    clearBtn:SetSize(145, 26)
    clearBtn:SetPoint("BOTTOMRIGHT", -8, 8)
    clearBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    clearBtn:SetBackdropColor(0.5, 0.15, 0.15, 1)
    clearBtn:SetBackdropBorderColor(0.25, 0.1, 0.1, 1)

    clearBtn.text = clearBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    clearBtn.text:SetPoint("CENTER")
    clearBtn.text:SetText("Clear")

    clearBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.6, 0.2, 0.2, 1) end)
    clearBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.5, 0.15, 0.15, 1) end)
    clearBtn:SetScript("OnClick", function()
        awardQueue = {}
        currentIndex = 0
        isRunning = false
        AwardFrame:Refresh()
    end)
    frame.clearBtn = clearBtn

    awardFrame = frame
    return frame
end

function AwardFrame:CreateQueueRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -((index - 1) * ROW_HEIGHT))
    row:SetPoint("TOPRIGHT", 0, -((index - 1) * ROW_HEIGHT))
    row:EnableMouse(true)
    row:RegisterForDrag("LeftButton")

    -- Background (alternating)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(0.08, 0.08, 0.1, index % 2 == 0 and 0.5 or 0.3)

    -- Highlight
    row.highlight = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.highlight:SetAllPoints()
    row.highlight:SetColorTexture(0.3, 0.3, 0.1, 0.4)
    row.highlight:Hide()

    -- Item icon
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(22, 22)
    row.icon:SetPoint("LEFT", 4, 0)

    -- Item name
    row.itemName = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.itemName:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.itemName:SetWidth(130)
    row.itemName:SetJustifyH("LEFT")

    -- Winner
    row.winner = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.winner:SetPoint("LEFT", row.itemName, "RIGHT", 4, 0)
    row.winner:SetWidth(80)
    row.winner:SetJustifyH("LEFT")

    -- Status dot
    row.statusDot = row:CreateTexture(nil, "ARTWORK")
    row.statusDot:SetSize(10, 10)
    row.statusDot:SetPoint("RIGHT", -4, 0)

    -- Drag handlers
    row:SetScript("OnDragStart", function(self)
        if isRunning then return end
        draggedIndex = self.queueIndex
        self.highlight:Show()
        SetCursor("Interface\\Cursor\\UI-Cursor-Move")
    end)

    row:SetScript("OnDragStop", function(self)
        if draggedIndex then
            SetCursor(nil)
            self.highlight:Hide()
            AwardFrame:Refresh()
        end
        draggedIndex = nil
    end)

    row:SetScript("OnEnter", function(self)
        if draggedIndex and draggedIndex ~= self.queueIndex then
            AwardFrame:MoveItem(draggedIndex, self.queueIndex)
            draggedIndex = self.queueIndex
        end
        self.highlight:Show()
    end)

    row:SetScript("OnLeave", function(self)
        if not draggedIndex then
            self.highlight:Hide()
        end
    end)

    row:Hide()
    return row
end

function AwardFrame:UpdateQueueRow(row, data, index)
    row.queueIndex = index

    row.icon:SetTexture(data.item.icon or "Interface\\Icons\\INV_Misc_QuestionMark")

    local qualityColor = Utils.GetQualityColor(data.item.quality or 4)
    local shortName = data.item.name or "Unknown"
    if #shortName > 18 then shortName = shortName:sub(1, 16) .. ".." end
    row.itemName:SetText("|cff" .. qualityColor .. shortName .. "|r")

    local coloredWinner = Utils.GetColoredPlayerName(data.winner, data.class)
    row.winner:SetText(coloredWinner)

    -- Status dot color
    if data.status == STATUS.COMPLETED then
        row.statusDot:SetColorTexture(0.2, 0.8, 0.2, 1)
    elseif data.status == STATUS.SKIPPED then
        row.statusDot:SetColorTexture(0.5, 0.5, 0.5, 1)
    elseif data.status == STATUS.WAITING_TRADE or data.status == STATUS.TRADING then
        row.statusDot:SetColorTexture(1, 0.8, 0.2, 1)
    else
        row.statusDot:SetColorTexture(0.4, 0.4, 0.4, 0.5)
    end

    row:Show()
end

function AwardFrame:Refresh()
    if not awardFrame then return end

    local section = awardFrame.itemSection
    local current = awardQueue[currentIndex]

    if current then
        section.icon:SetTexture(current.item.icon or "Interface\\Icons\\INV_Misc_QuestionMark")

        local qualityColor = Utils.GetQualityColor(current.item.quality or 4)
        section.itemName:SetText("|cff" .. qualityColor .. (current.item.name or "Unknown") .. "|r")

        local coloredWinner = Utils.GetColoredPlayerName(current.winner, current.class)
        local statusText
        if current.status == STATUS.ANNOUNCING then
            statusText = "Announcing..."
        elseif current.status == STATUS.WAITING_TRADE then
            statusText = "-> " .. coloredWinner .. " |cffffcc00(waiting)|r"
        elseif current.status == STATUS.TRADING then
            statusText = "-> " .. coloredWinner .. " |cff00ff00(trading)|r"
        elseif current.status == STATUS.COMPLETED then
            statusText = "-> " .. coloredWinner .. " |cff00ff00(done)|r"
        else
            statusText = "-> " .. coloredWinner
        end
        section.winner:SetText(statusText)
    else
        section.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        section.itemName:SetText("|cff666666No items|r")
        section.winner:SetText("")
    end

    -- Update buttons
    awardFrame.startBtn.text:SetText(isRunning and "Stop" or "Start")
    awardFrame.startBtn:SetEnabled(#awardQueue > 0)
    awardFrame.skipBtn:SetEnabled(currentIndex > 0)
    awardFrame.nextBtn:SetEnabled(currentIndex > 0 and currentIndex < #awardQueue)
    awardFrame.announceBtn:SetEnabled(currentIndex > 0)
    awardFrame.tradeBtn:SetEnabled(currentIndex > 0 and current and current.status == STATUS.WAITING_TRADE)

    -- Update queue rows
    for _, row in ipairs(queueRows) do row:Hide() end

    local rowIndex = 0
    for i, data in ipairs(awardQueue) do
        if i ~= currentIndex then
            rowIndex = rowIndex + 1
            if not queueRows[rowIndex] then
                queueRows[rowIndex] = self:CreateQueueRow(awardFrame.content, rowIndex)
            end
            self:UpdateQueueRow(queueRows[rowIndex], data, i)
        end
    end

    awardFrame.content:SetHeight(math.max(1, rowIndex * ROW_HEIGHT))
end

function AwardFrame:LoadPendingAwards(sessionId)
    local SessionManager = HooligansLoot:GetModule("SessionManager")
    local session = sessionId and SessionManager:GetSession(sessionId) or SessionManager:GetCurrentSession()

    if not session then
        HooligansLoot:Print("No session found")
        return
    end

    awardQueue = {}
    currentIndex = 0
    isRunning = false

    local pending = SessionManager:GetPendingAwards(session.id)

    for itemGUID, data in pairs(pending) do
        local award = session.awards[itemGUID]
        table.insert(awardQueue, {
            itemGUID = itemGUID,
            item = data.item,
            winner = data.winner,
            class = award and award.class or nil,
            status = STATUS.PENDING,
        })
    end

    table.sort(awardQueue, function(a, b)
        return (a.item.name or "") < (b.item.name or "")
    end)

    if #awardQueue > 0 then currentIndex = 1 end
end

function AwardFrame:MoveItem(fromIndex, toIndex)
    if fromIndex == toIndex or fromIndex < 1 or toIndex < 1 then return end
    if fromIndex > #awardQueue or toIndex > #awardQueue then return end

    local item = table.remove(awardQueue, fromIndex)
    table.insert(awardQueue, toIndex, item)

    if currentIndex == fromIndex then
        currentIndex = toIndex
    elseif fromIndex < currentIndex and toIndex >= currentIndex then
        currentIndex = currentIndex - 1
    elseif fromIndex > currentIndex and toIndex <= currentIndex then
        currentIndex = currentIndex + 1
    end

    self:Refresh()
end

function AwardFrame:Start()
    if #awardQueue == 0 then return end

    currentIndex = 0
    for i, data in ipairs(awardQueue) do
        if data.status == STATUS.PENDING then
            currentIndex = i
            break
        end
    end

    if currentIndex == 0 then
        HooligansLoot:Print("All items processed")
        return
    end

    isRunning = true
    self:ProcessCurrent()
end

function AwardFrame:Stop()
    isRunning = false
    self:Refresh()
end

function AwardFrame:ProcessCurrent()
    if not isRunning then return end

    local current = awardQueue[currentIndex]
    if not current or current.status ~= STATUS.PENDING then
        self:AdvanceToNext()
        return
    end

    current.status = STATUS.ANNOUNCING
    self:Refresh()

    local Announcer = HooligansLoot:GetModule("Announcer")
    Announcer:AnnounceAwardWithClass(current.item, current.winner, current.class, true)

    C_Timer.After(0.5, function()
        if not isRunning or awardQueue[currentIndex] ~= current then return end

        current.status = STATUS.WAITING_TRADE
        self:Refresh()

        SendChatMessage(string.format("[HOOLIGANS] Please trade me for: %s",
            current.item.link or current.item.name), "WHISPER", nil, current.winner)
    end)
end

function AwardFrame:AnnounceCurrentOnly()
    local current = awardQueue[currentIndex]
    if not current then return end

    local Announcer = HooligansLoot:GetModule("Announcer")
    Announcer:AnnounceAwardWithClass(current.item, current.winner, current.class, true)
end

function AwardFrame:InitiateTrade()
    local current = awardQueue[currentIndex]
    if not current then return end

    -- Target the winner and initiate trade
    TargetUnit(current.winner)
    if UnitExists("target") and UnitName("target") == current.winner then
        InitiateTrade("target")
    else
        HooligansLoot:Print("Could not target " .. current.winner .. " - are they nearby?")
    end
end

function AwardFrame:SkipCurrent()
    local current = awardQueue[currentIndex]
    if not current then return end

    current.status = STATUS.SKIPPED
    self:AdvanceToNext()
end

function AwardFrame:AdvanceToNext()
    local nextIndex = 0
    for i = currentIndex + 1, #awardQueue do
        if awardQueue[i].status == STATUS.PENDING then
            nextIndex = i
            break
        end
    end

    if nextIndex == 0 then
        for i, data in ipairs(awardQueue) do
            if data.status == STATUS.PENDING then
                nextIndex = i
                break
            end
        end
    end

    if nextIndex == 0 then
        isRunning = false
        HooligansLoot:Print("|cff00ff00All awards distributed!|r")
        self:Refresh()
        return
    end

    currentIndex = nextIndex
    self:Refresh()

    if isRunning then
        C_Timer.After(1.5, function() self:ProcessCurrent() end)
    end
end

-- Events
function AwardFrame:TRADE_SHOW()
    if not isRunning then return end

    local current = awardQueue[currentIndex]
    if not current or current.status ~= STATUS.WAITING_TRADE then return end

    local targetName = UnitName("NPC") or (GetTradeTargetInfo and GetTradeTargetInfo())
    if targetName and Utils.StripRealm(targetName) == Utils.StripRealm(current.winner) then
        current.status = STATUS.TRADING
        self:Refresh()
    end
end

function AwardFrame:UI_INFO_MESSAGE(event, messageType, message)
    if not isRunning or not message or not message:find("Trade complete") then return end

    local current = awardQueue[currentIndex]
    if not current or current.status ~= STATUS.TRADING then return end

    current.status = STATUS.COMPLETED
    self:Refresh()

    local SessionManager = HooligansLoot:GetModule("SessionManager")
    local session = SessionManager:GetCurrentSession()
    if session then SessionManager:MarkAwarded(session.id, current.itemGUID) end

    HooligansLoot:Print("|cff00ff00Traded:|r " .. (current.item.link or current.item.name))

    C_Timer.After(1, function() self:AdvanceToNext() end)
end

function AwardFrame:OnAwardCompleted(event, session, itemGUID)
    for i, data in ipairs(awardQueue) do
        if data.itemGUID == itemGUID and data.status ~= STATUS.COMPLETED then
            data.status = STATUS.COMPLETED
            if i == currentIndex and isRunning then
                C_Timer.After(0.5, function() self:AdvanceToNext() end)
            end
            break
        end
    end
    self:Refresh()
end

-- Public API
function AwardFrame:Show(sessionId)
    local frame = self:CreateFrame()
    self:LoadPendingAwards(sessionId)
    self:Refresh()
    frame:Show()
end

function AwardFrame:Hide()
    if awardFrame then awardFrame:Hide() end
end

function AwardFrame:Toggle(sessionId)
    if awardFrame and awardFrame:IsShown() then
        self:Hide()
    else
        self:Show(sessionId)
    end
end
