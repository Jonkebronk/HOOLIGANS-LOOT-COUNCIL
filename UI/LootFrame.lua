-- UI/LootFrame.lua
-- Raider response frame for voting with dropdown menus

local ADDON_NAME, NS = ...
local HooligansLoot = NS.addon
local Utils = NS.Utils

local LootFrame = HooligansLoot:NewModule("LootFrame")

-- Frame references
local lootFrame = nil
local itemRows = {}
local updateTimer = nil
local dropdownCounter = 0
-- Constants
local ROW_HEIGHT = 75  -- Increased to fit comment field below timer
local FRAME_WIDTH = 500  -- Wider for comment field
local FRAME_HEIGHT = 1000

function LootFrame:OnEnable()
    -- Register for callbacks
    -- NOTE: VOTE_UPDATED is intentionally NOT registered here to avoid closing
    -- the dropdown when other players respond. LootFrame updates via SubmitResponse.
    HooligansLoot.RegisterCallback(self, "VOTE_RECEIVED", "OnVoteReceived")
    HooligansLoot.RegisterCallback(self, "VOTE_ENDED", "OnVoteEnded")
    HooligansLoot.RegisterCallback(self, "VOTE_CANCELLED", "OnVoteCancelled")
    HooligansLoot.RegisterCallback(self, "VOTE_COLLECTION_ENDED", "OnCollectionEnded")
end

function LootFrame:CreateFrame()
    if lootFrame then return lootFrame end

    local frame = CreateFrame("Frame", "HooligansLootLootFrame", UIParent, "BackdropTemplate")
    frame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)

    -- Position to the right of MainFrame if it exists, otherwise center
    local mainFrame = _G["HooligansLootMainFrame"]
    if mainFrame then
        frame:SetPoint("TOPLEFT", mainFrame, "TOPRIGHT", 5, 0)
    else
        frame:SetPoint("CENTER", 300, 0)
    end

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

    -- Close button (top right X)
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)

    -- Make closable with Escape
    tinsert(UISpecialFrames, "HooligansLootLootFrame")

    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -18)
    title:SetText("|cff5865F2HOOLIGANS|r |cffffffffLoot Vote|r")
    frame.title = title

    -- Subtitle
    local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    subtitle:SetPoint("TOP", title, "BOTTOM", 0, -5)
    subtitle:SetText("Select your preference for each item")
    subtitle:SetTextColor(0.9, 0.8, 0.5)
    frame.subtitle = subtitle

    -- Hint text (auto-pass info)
    local hintText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hintText:SetPoint("TOP", subtitle, "BOTTOM", 0, -2)
    hintText:SetText("|cff888888Items without selection will auto-pass|r")
    frame.hintText = hintText

    -- Footer bar
    local footer = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    footer:SetHeight(35)
    footer:SetPoint("BOTTOMLEFT", 8, 8)
    footer:SetPoint("BOTTOMRIGHT", -8, 8)
    footer:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    footer:SetBackdropColor(0.1, 0.1, 0.12, 0.9)
    footer:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
    frame.footer = footer

    -- Total Items text (left side of footer)
    local totalItemsText = footer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    totalItemsText:SetPoint("LEFT", 12, 0)
    totalItemsText:SetText("Total Items: 0")
    totalItemsText:SetTextColor(0.8, 0.8, 0.8)
    frame.totalItemsText = totalItemsText

    -- Close button in footer (right side)
    local footerCloseBtn = CreateFrame("Button", nil, footer, "UIPanelButtonTemplate")
    footerCloseBtn:SetSize(70, 24)
    footerCloseBtn:SetPoint("RIGHT", -8, 0)
    footerCloseBtn:SetText("Close")
    footerCloseBtn:SetScript("OnClick", function() frame:Hide() end)
    frame.footerCloseBtn = footerCloseBtn

    -- Confirm button in footer (next to Close)
    local confirmBtn = CreateFrame("Button", nil, footer, "UIPanelButtonTemplate")
    confirmBtn:SetSize(90, 24)
    confirmBtn:SetPoint("RIGHT", footerCloseBtn, "LEFT", -5, 0)
    confirmBtn:SetText("Confirm All")
    confirmBtn:SetScript("OnClick", function()
        LootFrame:ConfirmAllResponses()
    end)
    confirmBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Confirm All")
        GameTooltip:AddLine("Submit all responses with their notes", 1, 1, 1, true)
        GameTooltip:AddLine("Items without selection will auto-pass", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    confirmBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.confirmBtn = confirmBtn

    -- Scroll frame for items (adjusted to leave room for header and footer)
    local scrollFrame = CreateFrame("ScrollFrame", "HooligansLootLootScroll", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 10, -68)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 50)  -- Leave room for footer
    frame.scrollFrame = scrollFrame

    -- Scroll child
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(scrollFrame:GetWidth(), 1)
    scrollFrame:SetScrollChild(content)
    frame.content = content

    -- OnShow handler
    frame:SetScript("OnShow", function()
        -- Re-anchor to MainFrame if it exists and we're not being dragged
        local mainFrame = _G["HooligansLootMainFrame"]
        if mainFrame and mainFrame:IsShown() then
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", mainFrame, "TOPRIGHT", 5, 0)
        end
        LootFrame:Refresh()
        LootFrame:StartUpdateTimer()
    end)

    frame:SetScript("OnHide", function()
        LootFrame:StopUpdateTimer()
    end)

    lootFrame = frame
    return frame
end

function LootFrame:CreateItemRow(parent, index)
    local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -((index - 1) * ROW_HEIGHT))
    row:SetPoint("TOPRIGHT", 0, -((index - 1) * ROW_HEIGHT))

    -- Background
    row:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
    })
    if index % 2 == 0 then
        row:SetBackdropColor(0.12, 0.12, 0.14, 0.8)
    else
        row:SetBackdropColor(0.08, 0.08, 0.1, 0.8)
    end

    -- Item icon
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(40, 40)
    row.icon:SetPoint("LEFT", 8, 0)

    -- Item name
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 10, -2)
    row.name:SetPoint("RIGHT", -160, 0)
    row.name:SetJustifyH("LEFT")

    -- Timer
    row.timer = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.timer:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
    row.timer:SetTextColor(0.7, 0.7, 0.7)

    -- Comment edit box (positioned below timer)
    local commentBox = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    commentBox:SetSize(200, 18)
    commentBox:SetPoint("TOPLEFT", row.timer, "BOTTOMLEFT", 0, -2)
    commentBox:SetAutoFocus(false)
    commentBox:SetMaxLetters(50)
    commentBox:SetFontObject("GameFontHighlightSmall")
    commentBox:SetTextInsets(5, 5, 0, 0)
    commentBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    commentBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    -- Save pending comment on text change so it persists through refreshes
    commentBox:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            row.pendingComment = self:GetText()
        end
        -- Update placeholder visibility
        if self:GetText() == "" then
            row.commentPlaceholder:Show()
        else
            row.commentPlaceholder:Hide()
        end
    end)
    row.commentBox = commentBox

    -- Comment placeholder text
    local commentPlaceholder = commentBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    commentPlaceholder:SetPoint("LEFT", 6, 0)
    commentPlaceholder:SetText("Note...")
    row.commentPlaceholder = commentPlaceholder

    commentBox:SetScript("OnEditFocusGained", function(self)
        commentPlaceholder:Hide()
    end)
    commentBox:SetScript("OnEditFocusLost", function(self)
        if self:GetText() == "" then
            commentPlaceholder:Show()
        end
    end)

    -- Dropdown menu for response
    dropdownCounter = dropdownCounter + 1
    local dropdownName = "HooligansLootResponseDropdown" .. dropdownCounter
    local dropdown = CreateFrame("Frame", dropdownName, row, "UIDropDownMenuTemplate")
    dropdown:SetPoint("TOPRIGHT", -5, -5)
    UIDropDownMenu_SetWidth(dropdown, 100)
    row.dropdown = dropdown

    -- Gear comparison frame - positioned below dropdown, within row bounds
    local gearFrame = CreateFrame("Frame", nil, row)
    gearFrame:SetSize(130, 22)
    gearFrame:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -25, 8)
    row.gearFrame = gearFrame

    -- "Current:" label
    local gearLabel = gearFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    gearLabel:SetPoint("LEFT", 0, 0)
    gearLabel:SetText("|cff888888Current:|r")
    gearFrame.label = gearLabel

    -- Gear icon slots (up to 2 for dual-slot items like rings)
    row.gearIcons = {}
    for i = 1, 2 do
        local gearIcon = CreateFrame("Button", nil, gearFrame)
        gearIcon:SetSize(20, 20)
        gearIcon:SetPoint("LEFT", gearLabel, "RIGHT", 2 + ((i - 1) * 22), 0)

        -- Icon texture
        local iconTexture = gearIcon:CreateTexture(nil, "ARTWORK")
        iconTexture:SetAllPoints()
        iconTexture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        gearIcon.icon = iconTexture

        -- Simple dark border (1px)
        local borderBg = gearIcon:CreateTexture(nil, "BACKGROUND")
        borderBg:SetPoint("TOPLEFT", -1, 1)
        borderBg:SetPoint("BOTTOMRIGHT", 1, -1)
        borderBg:SetColorTexture(0, 0, 0, 0.8)
        gearIcon.borderBg = borderBg

        -- Tooltip on hover
        gearIcon:SetScript("OnEnter", function(self)
            if self.itemLink then
                GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                GameTooltip:SetHyperlink(self.itemLink)
                GameTooltip:Show()
            elseif self.isEmpty then
                GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                GameTooltip:SetText("Empty Slot")
                GameTooltip:AddLine("No item equipped in this slot", 1, 1, 1)
                GameTooltip:Show()
            end
        end)
        gearIcon:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        gearIcon:Hide()
        row.gearIcons[i] = gearIcon
    end

    -- Initialize dropdown (saves selection locally until Confirm All)
    UIDropDownMenu_Initialize(dropdown, function(self, level)
        local Voting = HooligansLoot:GetModule("Voting")
        local info = UIDropDownMenu_CreateInfo()

        -- Add "Select..." option (Pass)
        info.text = "Select..."
        info.value = nil
        info.colorCode = "|cff888888"
        info.func = function()
            UIDropDownMenu_SetText(dropdown, "|cff888888Select...|r")
            row.selectedResponse = nil
        end
        UIDropDownMenu_AddButton(info, level)

        -- Add response options
        for _, respKey in ipairs(Voting.ResponseOrder) do
            local resp = Voting.ResponseTypes[respKey]
            info = UIDropDownMenu_CreateInfo()
            info.text = resp.text
            info.value = resp.id
            info.colorCode = "|cff" .. resp.color
            info.func = function()
                local voteId = row.voteId
                if voteId then
                    -- Just save locally, don't submit yet - user must click "Confirm All"
                    UIDropDownMenu_SetText(dropdown, "|cff" .. resp.color .. resp.text .. "|r")
                    row.selectedResponse = resp.id
                end
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    UIDropDownMenu_SetText(dropdown, "|cff888888Select...|r")

    -- Tooltip on hover
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        if self.itemLink then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(self.itemLink)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)

    row:Hide()
    return row
end

function LootFrame:UpdateItemRow(row, vote)
    if not vote then
        row:Hide()
        return
    end

    local item = vote.item
    local Voting = HooligansLoot:GetModule("Voting")

    -- Icon
    row.icon:SetTexture(item.icon or "Interface\\Icons\\INV_Misc_QuestionMark")

    -- Name with quality color
    local qualityColor = Utils.GetQualityColor(item.quality or 4)
    row.name:SetText("|cff" .. qualityColor .. (item.name or "Unknown Item") .. "|r")

    -- Check if we already responded
    local playerName = UnitName("player")
    local myResponse = vote.responses and vote.responses[playerName]

    -- Status text (no timer - voting is open until ML closes it)
    if vote.status == Voting.Status.COLLECTING then
        if myResponse then
            -- Show the response type
            local responseText = myResponse.response or "Unknown"
            for _, respKey in ipairs(Voting.ResponseOrder) do
                local resp = Voting.ResponseTypes[respKey]
                if resp.id == myResponse.response then
                    responseText = resp.text
                    row.timer:SetText("|cff00ff00Response: " .. responseText .. "|r")
                    break
                end
            end
        else
            row.timer:SetText("|cffffcc00Select your response|r")
        end
    elseif vote.status == Voting.Status.VOTING then
        row.timer:SetText("|cff88ff88Voting in progress|r")
    elseif vote.status == Voting.Status.DECIDED then
        row.timer:SetText(string.format("|cff00ff00Awarded to %s|r", vote.winner or "Unknown"))
    else
        row.timer:SetText("|cff888888Cancelled|r")
    end

    -- Update dropdown display and comment box
    local canRespond = vote.status == Voting.Status.COLLECTING
    if canRespond then
        row.dropdown:Show()
        row.commentBox:Show()
        row.commentBox:Enable()

        if myResponse then
            local respKey = myResponse.response:upper()
            local resp = Voting.ResponseTypes[respKey]
            if resp then
                UIDropDownMenu_SetText(row.dropdown, "|cff" .. resp.color .. resp.text .. "|r")
            else
                UIDropDownMenu_SetText(row.dropdown, myResponse.response)
            end
            row.selectedResponse = myResponse.response

            -- Restore comment if exists
            if myResponse.note and myResponse.note ~= "" then
                row.commentBox:SetText(myResponse.note)
                row.commentPlaceholder:Hide()
            end
        else
            -- Preserve pending selection if user already picked from dropdown but hasn't confirmed yet
            if not row.selectedResponse then
                UIDropDownMenu_SetText(row.dropdown, "|cff888888Select...|r")
            else
                -- Restore the dropdown display for pending selection
                local respKey = row.selectedResponse:upper()
                local resp = Voting.ResponseTypes[respKey]
                if resp then
                    UIDropDownMenu_SetText(row.dropdown, "|cff" .. resp.color .. resp.text .. "|r")
                end
            end
            -- Restore pending comment if exists, otherwise clear
            if row.pendingComment and row.pendingComment ~= "" then
                row.commentBox:SetText(row.pendingComment)
                row.commentPlaceholder:Hide()
            elseif not row.selectedResponse then
                row.commentBox:SetText("")
                row.commentPlaceholder:Show()
            end
        end
        UIDropDownMenu_EnableDropDown(row.dropdown)
    else
        if myResponse then
            local respKey = myResponse.response:upper()
            local resp = Voting.ResponseTypes[respKey]
            if resp then
                UIDropDownMenu_SetText(row.dropdown, "|cff" .. resp.color .. resp.text .. "|r")
            end
            -- Show comment if exists (read-only)
            if myResponse.note and myResponse.note ~= "" then
                row.commentBox:SetText(myResponse.note)
                row.commentPlaceholder:Hide()
            end
        else
            UIDropDownMenu_SetText(row.dropdown, "|cffaaaaaaNo response|r")
        end
        UIDropDownMenu_DisableDropDown(row.dropdown)
        row.dropdown:Show()
        row.commentBox:Show()
        row.commentBox:Disable()
    end

    row.voteId = vote.voteId
    row.itemLink = item.link

    -- Update gear comparison display
    local GearComparison = HooligansLoot:GetModule("GearComparison", true)
    if GearComparison and row.gearIcons then
        local gearInfo = GearComparison:GetOwnGearDisplayInfo(item.link)

        -- Hide all gear icons first
        for _, icon in ipairs(row.gearIcons) do
            icon:Hide()
            icon.itemLink = nil
            icon.isEmpty = nil
        end

        if gearInfo and #gearInfo > 0 then
            row.gearFrame:Show()
            for i, gear in ipairs(gearInfo) do
                if row.gearIcons[i] then
                    local gearIcon = row.gearIcons[i]
                    if gear.link then
                        -- Has equipped item
                        gearIcon.icon:SetTexture(gear.icon or GetItemIcon(gear.link))
                        gearIcon.itemLink = gear.link
                        gearIcon.isEmpty = false
                    else
                        -- Empty slot
                        gearIcon.icon:SetTexture("Interface\\PaperDoll\\UI-Backpack-EmptySlot")
                        gearIcon.itemLink = nil
                        gearIcon.isEmpty = true
                    end
                    gearIcon:Show()
                end
            end
        else
            row.gearFrame:Hide()
        end
    elseif row.gearFrame then
        row.gearFrame:Hide()
    end

    row:Show()
end

function LootFrame:Refresh()
    if not lootFrame or not lootFrame:IsShown() then return end

    local Voting = HooligansLoot:GetModule("Voting")
    local activeVotes = Voting:GetActiveVotes()

    -- Get current session ID
    local SessionManager = HooligansLoot:GetModule("SessionManager")
    local currentSession = SessionManager:GetCurrentSession()
    local currentSessionId = currentSession and currentSession.id


    -- Clear existing rows
    for _, row in ipairs(itemRows) do
        row:Hide()
    end

    -- Filter to votes that are still collecting responses
    local pendingVotes = {}
    local playerName = UnitName("player")

    for voteId, vote in pairs(activeVotes) do
        -- Only show votes that are still COLLECTING
        -- ML: only show votes from current session
        -- Raiders: show all votes (they receive votes from ML's session, not their own)
        local iAmML = vote.masterLooter == playerName
        local isValidSession = true
        if iAmML then
            -- ML only sees their own session's votes
            isValidSession = vote.sessionId and currentSessionId and (vote.sessionId == currentSessionId)
        else
            -- Raiders see all votes they receive (they have sessionId from ML)
            isValidSession = vote.sessionId ~= nil
        end
        local isCollecting = vote.status == Voting.Status.COLLECTING

        if isValidSession and isCollecting then
            table.insert(pendingVotes, vote)
        end
    end

    -- If no pending votes to show
    if #pendingVotes == 0 then
        lootFrame.subtitle:SetText("|cff888888No items pending your response|r")
        if lootFrame.totalItemsText then
            lootFrame.totalItemsText:SetText("Total Items: 0")
        end
        -- Auto-hide after collection is done (only if no items at all)
        C_Timer.After(1, function()
            if lootFrame and lootFrame:IsShown() then
                local stillPending = false
                for _, v in pairs(Voting:GetActiveVotes()) do
                    if v.status == Voting.Status.COLLECTING then
                        stillPending = true
                        break
                    end
                end
                if not stillPending then
                    self:Hide()
                end
            end
        end)
        lootFrame.content:SetHeight(ROW_HEIGHT)
        return
    end

    -- Sort by end time, with voteId as tiebreaker for stable ordering
    table.sort(pendingVotes, function(a, b)
        local aTime = a.endsAt or 0
        local bTime = b.endsAt or 0
        if aTime ~= bTime then
            return aTime < bTime
        end
        -- Stable sort: use voteId as tiebreaker
        return (a.voteId or "") < (b.voteId or "")
    end)

    -- Update subtitle and footer
    lootFrame.subtitle:SetText(string.format("%d item(s) need your response", #pendingVotes))

    -- Update footer total items count
    if lootFrame.totalItemsText then
        lootFrame.totalItemsText:SetText(string.format("Total Items: %d", #pendingVotes))
    end

    -- Create/update rows
    for i, vote in ipairs(pendingVotes) do
        if not itemRows[i] then
            itemRows[i] = self:CreateItemRow(lootFrame.content, i)
        end
        self:UpdateItemRow(itemRows[i], vote)
    end

    lootFrame.content:SetHeight(#pendingVotes * ROW_HEIGHT)
end

function LootFrame:RefreshForVote(voteId)
    self:Refresh()
end

-- Check for vote status changes (no longer time-based)
function LootFrame:UpdateTimers()
    if not lootFrame or not lootFrame:IsShown() then return end

    local Voting = HooligansLoot:GetModule("Voting")
    local needsRefresh = false

    for _, row in ipairs(itemRows) do
        if row:IsShown() and row.voteId then
            local vote = Voting:GetVote(row.voteId)
            if vote then
                -- Check if vote status changed (no longer collecting)
                if vote.status ~= Voting.Status.COLLECTING then
                    needsRefresh = true
                end
            end
        end
    end

    -- If any votes changed status, refresh to update display
    if needsRefresh then
        self:Refresh()
    end
end

function LootFrame:StartUpdateTimer()
    if updateTimer then return end

    updateTimer = C_Timer.NewTicker(1, function()
        if lootFrame and lootFrame:IsShown() then
            self:UpdateTimers()
        end
    end)
end

function LootFrame:StopUpdateTimer()
    if updateTimer then
        updateTimer:Cancel()
        updateTimer = nil
    end
end

function LootFrame:Show()
    -- Clean up any old session votes before showing
    local Voting = HooligansLoot:GetModule("Voting", true)
    if Voting then
        Voting:ClearOldSessionVotes()
    end

    local frame = self:CreateFrame()
    frame:Show()
    self:Refresh()
end

function LootFrame:Hide()
    if lootFrame then
        lootFrame:Hide()
    end
end

function LootFrame:IsShown()
    return lootFrame and lootFrame:IsShown()
end

function LootFrame:Toggle()
    if lootFrame and lootFrame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

-- Re-submit all responses with their current comments (useful for updating comments)
-- Items without a selection are automatically set to PASS
function LootFrame:ConfirmAllResponses()
    local Voting = HooligansLoot:GetModule("Voting")
    local submitted = 0
    local autoPassed = 0

    for _, row in ipairs(itemRows) do
        if row:IsShown() and row.voteId then
            local response = row.selectedResponse
            local comment = row.commentBox and row.commentBox:GetText() or ""

            -- If no response selected, auto-pass
            if not response then
                response = "PASS"
                autoPassed = autoPassed + 1
            end

            -- Submit/update the response with the comment
            local success = Voting:SubmitResponse(row.voteId, response, comment)
            if success then
                submitted = submitted + 1
                -- Clear pending state after successful submission
                row.pendingComment = nil
                row.selectedResponse = nil
            end
        end
    end

    if submitted > 0 or autoPassed > 0 then
        local msg = string.format("Submitted %d response(s)", submitted)
        if autoPassed > 0 then
            msg = msg .. string.format(" (%d auto-passed)", autoPassed)
        end
        HooligansLoot:Print(msg .. ".")
    end

    -- Mark votes as confirmed and broadcast to group
    Voting:ConfirmVotes()

    -- Close the loot frame after confirming
    self:Hide()
end

-- Callbacks
function LootFrame:OnVoteReceived(event, votes)
    self:Show()
end

function LootFrame:OnVoteEnded(event, voteId, winner)
    self:Refresh()

    -- Hide if no more pending votes
    local Voting = HooligansLoot:GetModule("Voting")
    local activeVotes = Voting:GetActiveVotes()
    local hasPending = false
    for _, vote in pairs(activeVotes) do
        if vote.status ~= Voting.Status.CANCELLED and vote.status ~= Voting.Status.DECIDED then
            hasPending = true
            break
        end
    end

    if not hasPending then
        C_Timer.After(3, function()
            if lootFrame and lootFrame:IsShown() then
                local stillHasPending = false
                for _, vote in pairs(Voting:GetActiveVotes()) do
                    if vote.status ~= Voting.Status.CANCELLED and vote.status ~= Voting.Status.DECIDED then
                        stillHasPending = true
                        break
                    end
                end
                if not stillHasPending then
                    self:Hide()
                end
            end
        end)
    end
end

function LootFrame:OnVoteCancelled(event, voteId)
    self:Refresh()
end

function LootFrame:OnCollectionEnded(event, voteId)
    -- Force immediate refresh to remove the completed vote
    self:Refresh()

    -- Check if all votes have finished collecting - if so, hide the frame
    local Voting = HooligansLoot:GetModule("Voting")
    local activeVotes = Voting:GetActiveVotes()
    local SessionManager = HooligansLoot:GetModule("SessionManager")
    local currentSession = SessionManager:GetCurrentSession()
    local currentSessionId = currentSession and currentSession.id
    local hasCollecting = false

    for _, vote in pairs(activeVotes) do
        -- Only count votes from current session
        if vote.sessionId == currentSessionId and vote.status == Voting.Status.COLLECTING then
            hasCollecting = true
            break
        end
    end

    if not hasCollecting then
        -- All votes done collecting, hide after a short delay
        C_Timer.After(1, function()
            if lootFrame and lootFrame:IsShown() then
                self:Hide()
            end
        end)
    end
end
