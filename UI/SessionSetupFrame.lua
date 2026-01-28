-- UI/SessionSetupFrame.lua
-- Minimalistic vote setup dialog

local ADDON_NAME, NS = ...
local HooligansLoot = NS.addon
local Utils = NS.Utils

local SessionSetupFrame = HooligansLoot:NewModule("SessionSetupFrame")

-- Frame references
local setupFrame = nil
local itemRows = {}
local selectedItems = {}

-- Constants
local FRAME_WIDTH = 400
local FRAME_HEIGHT = 400
local ROW_HEIGHT = 40

function SessionSetupFrame:OnEnable()
    -- Nothing to do on enable
end

function SessionSetupFrame:CreateFrame()
    if setupFrame then return setupFrame end

    local frame = CreateFrame("Frame", "HooligansLootSessionSetupFrame", UIParent, "BackdropTemplate")
    frame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("DIALOG")
    frame:Hide()

    -- Backdrop
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        edgeSize = 20,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0.08, 0.08, 0.1, 0.95)
    frame:SetBackdropBorderColor(0.6, 0.5, 0.3, 1)

    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)

    tinsert(UISpecialFrames, "HooligansLootSessionSetupFrame")

    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("|cffffffffStart Vote|r")
    frame.title = title

    -- Item count subtitle
    local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    subtitle:SetPoint("TOP", title, "BOTTOM", 0, -5)
    subtitle:SetTextColor(0.8, 0.8, 0.8)
    frame.subtitle = subtitle

    -- Scroll frame for items
    local scrollFrame = CreateFrame("ScrollFrame", "HooligansLootSetupScroll", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 15, -50)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 60)
    frame.scrollFrame = scrollFrame

    -- Scroll child
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(scrollFrame:GetWidth(), 1)
    scrollFrame:SetScrollChild(content)
    frame.content = content

    -- NOTE: Timeout slider removed - voting now stays open until RL ends collection
    -- Players confirm their votes via "Confirm All" button, shown as checkmarks in player panel

    -- Start button (green-ish)
    local startBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    startBtn:SetSize(100, 28)
    startBtn:SetPoint("BOTTOMLEFT", 20, 20)
    startBtn:SetText("Start")
    startBtn:SetScript("OnClick", function()
        SessionSetupFrame:StartVote()
    end)
    frame.startBtn = startBtn

    -- Cancel button
    local cancelBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    cancelBtn:SetSize(100, 28)
    cancelBtn:SetPoint("BOTTOMRIGHT", -20, 20)
    cancelBtn:SetText("Cancel")
    cancelBtn:SetScript("OnClick", function()
        frame:Hide()
    end)

    -- OnShow
    frame:SetScript("OnShow", function()
        SessionSetupFrame:Refresh()
    end)

    setupFrame = frame
    return frame
end

function SessionSetupFrame:CreateItemRow(parent, index)
    local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -((index - 1) * ROW_HEIGHT))
    row:SetPoint("TOPRIGHT", 0, -((index - 1) * ROW_HEIGHT))

    -- Background
    row:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
    })
    if index % 2 == 0 then
        row:SetBackdropColor(0.15, 0.15, 0.18, 0.6)
    else
        row:SetBackdropColor(0.1, 0.1, 0.12, 0.4)
    end

    -- Remove button (X) on left
    row.removeBtn = CreateFrame("Button", nil, row)
    row.removeBtn:SetSize(20, 20)
    row.removeBtn:SetPoint("LEFT", 5, 0)
    row.removeBtn:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
    row.removeBtn:SetHighlightTexture("Interface\\Buttons\\UI-StopButton")
    row.removeBtn:GetHighlightTexture():SetVertexColor(1, 0.3, 0.3, 0.8)
    row.removeBtn:SetScript("OnClick", function(self)
        local itemGUID = self:GetParent().itemGUID
        if itemGUID then
            SessionSetupFrame:RemoveItem(itemGUID)
        end
    end)

    -- Icon
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(32, 32)
    row.icon:SetPoint("LEFT", row.removeBtn, "RIGHT", 8, 0)

    -- Item name
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 10, 0)
    row.name:SetPoint("RIGHT", -10, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    -- Tooltip on hover
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        if self.itemLink then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(self.itemLink)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    row:Hide()
    return row
end

function SessionSetupFrame:RemoveItem(itemGUID)
    -- Remove from selectedItems
    for i, item in ipairs(selectedItems) do
        if item.guid == itemGUID then
            table.remove(selectedItems, i)
            break
        end
    end
    self:RefreshDisplay()
end

function SessionSetupFrame:Refresh()
    if not setupFrame or not setupFrame:IsShown() then return end

    local SessionManager = HooligansLoot:GetModule("SessionManager")
    local session = SessionManager:GetCurrentSession()

    -- Clear selected items
    selectedItems = {}

    if not session then
        setupFrame.subtitle:SetText("|cffff4444No active session|r")
        setupFrame.startBtn:SetEnabled(false)
        return
    end

    -- Get unawarded items (all items that don't have awards)
    for _, item in ipairs(session.items) do
        local award = session.awards[item.guid]
        if not award then
            table.insert(selectedItems, item)
        end
    end

    -- Sort by timestamp (newest first)
    table.sort(selectedItems, function(a, b)
        return (a.timestamp or 0) > (b.timestamp or 0)
    end)

    self:RefreshDisplay()
end

function SessionSetupFrame:RefreshDisplay()
    -- Clear existing rows
    for _, row in ipairs(itemRows) do
        row:Hide()
    end

    if #selectedItems == 0 then
        setupFrame.subtitle:SetText("|cff888888No items to vote on|r")
        setupFrame.startBtn:SetEnabled(false)
        setupFrame.content:SetHeight(ROW_HEIGHT)
        return
    end

    setupFrame.subtitle:SetText(string.format("%d item(s)", #selectedItems))
    setupFrame.startBtn:SetEnabled(true)

    -- Create/update rows
    for i, item in ipairs(selectedItems) do
        if not itemRows[i] then
            itemRows[i] = self:CreateItemRow(setupFrame.content, i)
        end

        local row = itemRows[i]

        -- Icon
        row.icon:SetTexture(item.icon or "Interface\\Icons\\INV_Misc_QuestionMark")

        -- Name with quality color
        local qualityColor = Utils.GetQualityColor(item.quality or 4)
        row.name:SetText("|cff" .. qualityColor .. (item.name or "Unknown Item") .. "|r")

        row.itemLink = item.link
        row.itemGUID = item.guid
        row:Show()
    end

    setupFrame.content:SetHeight(#selectedItems * ROW_HEIGHT)
end

function SessionSetupFrame:StartVote()
    if #selectedItems == 0 then
        HooligansLoot:Print("No items to vote on.")
        return
    end

    HooligansLoot:Debug("Starting vote for " .. #selectedItems .. " items")

    -- Start the vote (no timeout - stays open until RL ends collection)
    local Voting = HooligansLoot:GetModule("Voting", true)
    if not Voting then
        HooligansLoot:Print("Error: Voting module not loaded!")
        return
    end

    local success = Voting:StartVote(selectedItems, 0)

    if success then
        setupFrame:Hide()
    else
        HooligansLoot:Print("Failed to start vote. Check if you have permission.")
    end
end

function SessionSetupFrame:Show()
    local frame = self:CreateFrame()
    frame:Show()
    self:Refresh()
end

function SessionSetupFrame:Hide()
    if setupFrame then
        setupFrame:Hide()
    end
end

function SessionSetupFrame:Toggle()
    if setupFrame and setupFrame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end
