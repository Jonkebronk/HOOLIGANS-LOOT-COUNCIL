-- UI/PackMuleFrame.lua
-- PackMule Settings UI

local ADDON_NAME, NS = ...
local HooligansLoot = NS.addon
local Utils = NS.Utils

local PackMuleFrame = HooligansLoot:NewModule("PackMuleFrame")

-- Frame references
local mainFrame = nil
local rulesFrame = nil
local ignoredFrame = nil

-- Quality options for dropdowns
local QUALITY_OPTIONS = {
    { value = 0, text = "|cff9d9d9dPoor|r", color = {0.62, 0.62, 0.62} },
    { value = 1, text = "|cffffffffCommon|r", color = {1, 1, 1} },
    { value = 2, text = "|cff1eff00Uncommon|r", color = {0.12, 1, 0} },
    { value = 3, text = "|cff0070ddRare|r", color = {0, 0.44, 0.87} },
    { value = 4, text = "|cffa335eeEpic|r", color = {0.64, 0.21, 0.93} },
    { value = 5, text = "|cffff8000Legendary|r", color = {1, 0.5, 0} },
}

local OPERATOR_OPTIONS = {
    { value = "<=", text = "and LOWER" },
    { value = ">=", text = "and HIGHER" },
    { value = "==", text = "exactly" },
}

function PackMuleFrame:OnEnable()
    -- Nothing to do on enable
end

-- ============================================================================
-- Main Settings Frame
-- ============================================================================

function PackMuleFrame:CreateMainFrame()
    if mainFrame then return mainFrame end

    local frame = CreateFrame("Frame", "HooligansPackMuleFrame", UIParent, "BackdropTemplate")
    frame:SetSize(450, 520)
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

    -- Make closable with Escape
    tinsert(UISpecialFrames, "HooligansPackMuleFrame")

    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("|cffffffffPackMule|r - Auto-Loot Settings")

    -- Divider
    local divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", 15, -40)
    divider:SetPoint("TOPRIGHT", -15, -40)
    divider:SetHeight(1)
    divider:SetColorTexture(0.4, 0.4, 0.4, 1)

    -- === ENABLE SECTION ===
    local sectionEnable = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sectionEnable:SetPoint("TOPLEFT", 20, -55)
    sectionEnable:SetText("|cffffcc00Enable PackMule|r")

    -- Master Checkbox (main enable)
    local enableCheck = self:CreateCheckbox(frame, "Enable PackMule Auto-Loot", 25, -80)
    enableCheck:SetScript("OnClick", function(self)
        local PackMule = HooligansLoot:GetModule("PackMule", true)
        if PackMule then
            local settings = PackMule:GetSettings()
            settings.enabled = self:GetChecked()
        end
    end)
    frame.enableCheck = enableCheck

    -- Enable for Master Loot
    local masterLootCheck = self:CreateCheckbox(frame, "Enable for Master Loot mode", 40, -105)
    masterLootCheck:SetScript("OnClick", function(self)
        local PackMule = HooligansLoot:GetModule("PackMule", true)
        if PackMule then
            local settings = PackMule:GetSettings()
            settings.enabledForMasterLoot = self:GetChecked()
        end
    end)
    frame.masterLootCheck = masterLootCheck

    -- Enable for Group Loot
    local groupLootCheck = self:CreateCheckbox(frame, "Enable for Group Loot mode", 40, -130)
    groupLootCheck:SetScript("OnClick", function(self)
        local PackMule = HooligansLoot:GetModule("PackMule", true)
        if PackMule then
            local settings = PackMule:GetSettings()
            settings.enabledForGroupLoot = self:GetChecked()
        end
    end)
    frame.groupLootCheck = groupLootCheck

    -- === OPTIONS SECTION ===
    local sectionOptions = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sectionOptions:SetPoint("TOPLEFT", 20, -165)
    sectionOptions:SetText("|cffffcc00Options|r")

    -- Need without Assist
    local needCheck = self:CreateCheckbox(frame, "Also NEED when not lead/assist", 25, -190)
    needCheck:SetScript("OnClick", function(self)
        local PackMule = HooligansLoot:GetModule("PackMule", true)
        if PackMule then
            local settings = PackMule:GetSettings()
            settings.needWithoutAssist = self:GetChecked()
        end
    end)
    frame.needCheck = needCheck

    -- Auto disable on leave
    local autoDisableCheck = self:CreateCheckbox(frame, "Disable Group Loot mode when leaving group", 25, -215)
    autoDisableCheck:SetScript("OnClick", function(self)
        local PackMule = HooligansLoot:GetModule("PackMule", true)
        if PackMule then
            local settings = PackMule:GetSettings()
            settings.autoDisableOnLeave = self:GetChecked()
        end
    end)
    frame.autoDisableCheck = autoDisableCheck

    -- Auto confirm solo
    local confirmSoloCheck = self:CreateCheckbox(frame, "Auto confirm loot when solo", 25, -240)
    confirmSoloCheck:SetScript("OnClick", function(self)
        local PackMule = HooligansLoot:GetModule("PackMule", true)
        if PackMule then
            local settings = PackMule:GetSettings()
            settings.autoConfirmSolo = self:GetChecked()
        end
    end)
    frame.confirmSoloCheck = confirmSoloCheck

    -- Auto confirm group
    local confirmGroupCheck = self:CreateCheckbox(frame, "Auto confirm loot when in group", 25, -265)
    confirmGroupCheck:SetScript("OnClick", function(self)
        local PackMule = HooligansLoot:GetModule("PackMule", true)
        if PackMule then
            local settings = PackMule:GetSettings()
            settings.autoConfirmGroup = self:GetChecked()
        end
    end)
    frame.confirmGroupCheck = confirmGroupCheck

    -- Loot gold
    local goldCheck = self:CreateCheckbox(frame, "Auto loot gold/currency", 25, -290)
    goldCheck:SetScript("OnClick", function(self)
        local PackMule = HooligansLoot:GetModule("PackMule", true)
        if PackMule then
            local settings = PackMule:GetSettings()
            settings.lootGold = self:GetChecked()
        end
    end)
    frame.goldCheck = goldCheck

    -- Shift bypass
    local shiftCheck = self:CreateCheckbox(frame, "Hold SHIFT to bypass PackMule", 25, -315)
    shiftCheck:SetScript("OnClick", function(self)
        local PackMule = HooligansLoot:GetModule("PackMule", true)
        if PackMule then
            local settings = PackMule:GetSettings()
            settings.shiftBypass = self:GetChecked()
        end
    end)
    frame.shiftCheck = shiftCheck

    -- === DISENCHANTER SECTION ===
    local sectionDE = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sectionDE:SetPoint("TOPLEFT", 20, -350)
    sectionDE:SetText("|cffffcc00Disenchanter|r")

    local deLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    deLabel:SetPoint("TOPLEFT", 25, -375)
    deLabel:SetText("Player name:")

    local deEditBox = CreateFrame("EditBox", "HooligansPackMuleDEEditBox", frame, "InputBoxTemplate")
    deEditBox:SetSize(150, 20)
    deEditBox:SetPoint("LEFT", deLabel, "RIGHT", 10, 0)
    deEditBox:SetAutoFocus(false)
    deEditBox:SetScript("OnEnterPressed", function(self)
        local PackMule = HooligansLoot:GetModule("PackMule", true)
        if PackMule then
            local name = self:GetText()
            if name and name ~= "" then
                PackMule:SetDisenchanter(name)
            else
                PackMule:ClearDisenchanter()
            end
        end
        self:ClearFocus()
    end)
    deEditBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    frame.deEditBox = deEditBox

    local deSetBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    deSetBtn:SetSize(60, 22)
    deSetBtn:SetPoint("LEFT", deEditBox, "RIGHT", 5, 0)
    deSetBtn:SetText("Set")
    deSetBtn:SetScript("OnClick", function()
        local PackMule = HooligansLoot:GetModule("PackMule", true)
        if PackMule then
            local name = deEditBox:GetText()
            if name and name ~= "" then
                PackMule:SetDisenchanter(name)
            end
        end
    end)

    local deClearBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    deClearBtn:SetSize(60, 22)
    deClearBtn:SetPoint("LEFT", deSetBtn, "RIGHT", 5, 0)
    deClearBtn:SetText("Clear")
    deClearBtn:SetScript("OnClick", function()
        local PackMule = HooligansLoot:GetModule("PackMule", true)
        if PackMule then
            PackMule:ClearDisenchanter()
            deEditBox:SetText("")
        end
    end)

    -- === BUTTONS SECTION ===
    local btnWidth = 120
    local btnHeight = 26

    -- Item Rules button (toggles rules panel)
    local rulesBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    rulesBtn:SetSize(btnWidth, btnHeight)
    rulesBtn:SetPoint("TOPLEFT", 25, -420)
    rulesBtn:SetText("Item Rules")
    rulesBtn:SetScript("OnClick", function()
        PackMuleFrame:ToggleRulesFrame()
    end)

    -- Ignored Items button (toggles ignored panel)
    local ignoredBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    ignoredBtn:SetSize(btnWidth, btnHeight)
    ignoredBtn:SetPoint("LEFT", rulesBtn, "RIGHT", 10, 0)
    ignoredBtn:SetText("Ignored Items")
    ignoredBtn:SetScript("OnClick", function()
        PackMuleFrame:ToggleIgnoredFrame()
    end)

    -- Status indicator
    local statusLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    statusLabel:SetPoint("BOTTOMLEFT", 20, 50)
    frame.statusLabel = statusLabel

    -- Close button at bottom (closes all panels)
    local closeBtnBottom = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    closeBtnBottom:SetSize(100, btnHeight)
    closeBtnBottom:SetPoint("BOTTOM", 0, 15)
    closeBtnBottom:SetText("Close")
    closeBtnBottom:SetScript("OnClick", function()
        PackMuleFrame:Hide()
    end)

    -- OnShow - refresh values
    frame:SetScript("OnShow", function()
        PackMuleFrame:RefreshMainValues()
    end)

    mainFrame = frame
    return frame
end

function PackMuleFrame:CreateCheckbox(parent, label, x, y)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetPoint("TOPLEFT", x, y)
    check:SetSize(26, 26)

    local checkLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    checkLabel:SetPoint("LEFT", check, "RIGHT", 5, 0)
    checkLabel:SetText(label)

    return check
end

function PackMuleFrame:RefreshMainValues()
    if not mainFrame then return end

    local PackMule = HooligansLoot:GetModule("PackMule", true)
    if not PackMule then return end

    local settings = PackMule:GetSettings()

    -- Update checkboxes
    mainFrame.enableCheck:SetChecked(settings.enabled)
    mainFrame.masterLootCheck:SetChecked(settings.enabledForMasterLoot)
    mainFrame.groupLootCheck:SetChecked(settings.enabledForGroupLoot)
    mainFrame.needCheck:SetChecked(settings.needWithoutAssist)
    mainFrame.autoDisableCheck:SetChecked(settings.autoDisableOnLeave)
    mainFrame.confirmSoloCheck:SetChecked(settings.autoConfirmSolo)
    mainFrame.confirmGroupCheck:SetChecked(settings.autoConfirmGroup)
    mainFrame.goldCheck:SetChecked(settings.lootGold)
    mainFrame.shiftCheck:SetChecked(settings.shiftBypass)

    -- Update disenchanter
    mainFrame.deEditBox:SetText(settings.disenchanter or "")

    -- Update status
    local statusText
    if settings.enabled then
        statusText = "|cff00ff00PackMule is ENABLED|r"
    else
        statusText = "|cffff0000PackMule is DISABLED|r"
    end
    mainFrame.statusLabel:SetText(statusText)
end

-- ============================================================================
-- Rules Frame
-- ============================================================================

function PackMuleFrame:CreateRulesFrame()
    if rulesFrame then return rulesFrame end

    local frame = CreateFrame("Frame", "HooligansPackMuleRulesFrame", UIParent, "BackdropTemplate")
    frame:SetSize(550, 500)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("DIALOG")
    frame:Hide()

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

    tinsert(UISpecialFrames, "HooligansPackMuleRulesFrame")

    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("|cffffffffPackMule|r - Item Rules")

    local divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", 15, -40)
    divider:SetPoint("TOPRIGHT", -15, -40)
    divider:SetHeight(1)
    divider:SetColorTexture(0.4, 0.4, 0.4, 1)

    -- === ADD QUALITY RULE SECTION ===
    local sectionQuality = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sectionQuality:SetPoint("TOPLEFT", 20, -55)
    sectionQuality:SetText("|cffffcc00Add Quality Rule|r")

    -- Quality dropdown
    local qualityLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    qualityLabel:SetPoint("TOPLEFT", 25, -80)
    qualityLabel:SetText("Quality:")

    local qualityDropdown = CreateFrame("Frame", "HooligansPackMuleQualityDropdown", frame, "UIDropDownMenuTemplate")
    qualityDropdown:SetPoint("LEFT", qualityLabel, "RIGHT", 0, -3)

    local function QualityDropdown_Initialize(self, level)
        local info = UIDropDownMenu_CreateInfo()
        for _, option in ipairs(QUALITY_OPTIONS) do
            info.text = option.text
            info.arg1 = option.value
            info.func = function(_, arg1)
                frame.selectedQuality = arg1
                UIDropDownMenu_SetText(qualityDropdown, option.text)
            end
            info.checked = (frame.selectedQuality == option.value)
            UIDropDownMenu_AddButton(info, level)
        end
    end

    UIDropDownMenu_SetWidth(qualityDropdown, 100)
    UIDropDownMenu_Initialize(qualityDropdown, QualityDropdown_Initialize)
    UIDropDownMenu_SetText(qualityDropdown, QUALITY_OPTIONS[3].text) -- Default to Uncommon
    frame.selectedQuality = 2
    frame.qualityDropdown = qualityDropdown

    -- Operator dropdown
    local operatorDropdown = CreateFrame("Frame", "HooligansPackMuleOperatorDropdown", frame, "UIDropDownMenuTemplate")
    operatorDropdown:SetPoint("LEFT", qualityDropdown, "RIGHT", 0, 0)

    local function OperatorDropdown_Initialize(self, level)
        local info = UIDropDownMenu_CreateInfo()
        for _, option in ipairs(OPERATOR_OPTIONS) do
            info.text = option.text
            info.arg1 = option.value
            info.func = function(_, arg1)
                frame.selectedOperator = arg1
                UIDropDownMenu_SetText(operatorDropdown, option.text)
            end
            info.checked = (frame.selectedOperator == option.value)
            UIDropDownMenu_AddButton(info, level)
        end
    end

    UIDropDownMenu_SetWidth(operatorDropdown, 90)
    UIDropDownMenu_Initialize(operatorDropdown, OperatorDropdown_Initialize)
    UIDropDownMenu_SetText(operatorDropdown, OPERATOR_OPTIONS[1].text) -- Default to "and LOWER"
    frame.selectedOperator = "<="
    frame.operatorDropdown = operatorDropdown

    -- Target input
    local targetLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    targetLabel:SetPoint("TOPLEFT", 25, -115)
    targetLabel:SetText("Target:")

    local qualityTargetBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    qualityTargetBox:SetSize(120, 20)
    qualityTargetBox:SetPoint("LEFT", targetLabel, "RIGHT", 10, 0)
    qualityTargetBox:SetAutoFocus(false)
    qualityTargetBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    frame.qualityTargetBox = qualityTargetBox

    local targetHint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    targetHint:SetPoint("LEFT", qualityTargetBox, "RIGHT", 10, 0)
    targetHint:SetText("")

    -- Add quality rule button
    local addQualityBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    addQualityBtn:SetSize(100, 22)
    addQualityBtn:SetPoint("TOPLEFT", 25, -145)
    addQualityBtn:SetText("Add Rule")
    addQualityBtn:SetScript("OnClick", function()
        local PackMule = HooligansLoot:GetModule("PackMule", true)
        if PackMule then
            local target = qualityTargetBox:GetText()
            if not target or target == "" then
                HooligansLoot:Print("Please enter a target")
                return
            end
            PackMule:AddRule({
                quality = frame.selectedQuality,
                qualityOperator = frame.selectedOperator,
                target = target,
            })
            qualityTargetBox:SetText("")
            PackMuleFrame:RefreshRulesList()
        end
    end)

    -- === ADD ITEM RULE SECTION ===
    local sectionItem = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sectionItem:SetPoint("TOPLEFT", 20, -180)
    sectionItem:SetText("|cffffcc00Add Item Rule|r")

    local itemLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    itemLabel:SetPoint("TOPLEFT", 25, -205)
    itemLabel:SetText("Item (ID, link, or *pattern*):")

    local itemBox = CreateFrame("EditBox", "HooligansPackMuleItemBox", frame, "InputBoxTemplate")
    itemBox:SetSize(200, 20)
    itemBox:SetPoint("TOPLEFT", 25, -225)
    itemBox:SetAutoFocus(false)
    itemBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    frame.itemBox = itemBox

    -- Support shift-clicking items into the edit box
    local originalHandleModifiedItemClick = HandleModifiedItemClick
    HandleModifiedItemClick = function(link, ...)
        if itemBox:IsVisible() and itemBox:HasFocus() and link then
            itemBox:SetText(link)
            return true
        end
        return originalHandleModifiedItemClick(link, ...)
    end

    -- Also hook ChatEdit_InsertLink as backup
    local originalChatEdit_InsertLink = ChatEdit_InsertLink
    ChatEdit_InsertLink = function(link)
        if itemBox:IsVisible() and itemBox:HasFocus() and link then
            itemBox:SetText(link)
            return true
        end
        return originalChatEdit_InsertLink(link)
    end

    -- Support drag-and-drop of items
    itemBox:SetScript("OnReceiveDrag", function(self)
        local infoType, itemID, itemLink = GetCursorInfo()
        if infoType == "item" and itemLink then
            self:SetText(itemLink)
            ClearCursor()
        end
    end)
    itemBox:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            local infoType, itemID, itemLink = GetCursorInfo()
            if infoType == "item" and itemLink then
                self:SetText(itemLink)
                ClearCursor()
            end
        end
    end)

    -- Instructions hint
    local itemHint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    itemHint:SetPoint("TOPLEFT", itemBox, "BOTTOMLEFT", 0, -2)
    itemHint:SetText("Shift-click or drag item here")

    local itemTargetLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    itemTargetLabel:SetPoint("LEFT", itemBox, "RIGHT", 15, 0)
    itemTargetLabel:SetText("Target:")

    local itemTargetBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    itemTargetBox:SetSize(120, 20)
    itemTargetBox:SetPoint("LEFT", itemTargetLabel, "RIGHT", 10, 0)
    itemTargetBox:SetAutoFocus(false)
    itemTargetBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    frame.itemTargetBox = itemTargetBox

    local addItemBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    addItemBtn:SetSize(100, 22)
    addItemBtn:SetPoint("TOPLEFT", 25, -260)
    addItemBtn:SetText("Add Rule")
    addItemBtn:SetScript("OnClick", function()
        local PackMule = HooligansLoot:GetModule("PackMule", true)
        if PackMule then
            local itemInput = itemBox:GetText()
            local target = itemTargetBox:GetText()

            if not itemInput or itemInput == "" then
                HooligansLoot:Print("Please enter an item ID, link, or pattern")
                return
            end
            if not target or target == "" then
                HooligansLoot:Print("Please enter a target")
                return
            end

            local rule = { target = target }

            -- Check if it's an item ID
            local itemId = tonumber(itemInput)
            if itemId then
                rule.itemId = itemId
            -- Check if it's an item link
            elseif itemInput:match("|H") then
                rule.itemLink = itemInput
                rule.itemId = Utils.GetItemID(itemInput)
            -- Otherwise treat as wildcard pattern
            else
                rule.itemName = itemInput
            end

            PackMule:AddRule(rule)
            itemBox:SetText("")
            itemTargetBox:SetText("")
            PackMuleFrame:RefreshRulesList()
        end
    end)

    -- === RULES LIST SECTION ===
    local sectionList = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sectionList:SetPoint("TOPLEFT", 20, -295)
    sectionList:SetText("|cffffcc00Current Rules|r")

    -- Scroll frame for rules list
    local scrollFrame = CreateFrame("ScrollFrame", "HooligansPackMuleRulesScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 20, -315)
    scrollFrame:SetPoint("BOTTOMRIGHT", -40, 50)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(490, 1) -- Height will be set dynamically
    scrollFrame:SetScrollChild(scrollChild)
    frame.scrollChild = scrollChild
    frame.ruleRows = {}

    -- Clear all button
    local clearBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clearBtn:SetSize(100, 22)
    clearBtn:SetPoint("BOTTOMLEFT", 20, 15)
    clearBtn:SetText("Clear All")
    clearBtn:SetScript("OnClick", function()
        local PackMule = HooligansLoot:GetModule("PackMule", true)
        if PackMule then
            PackMule:ClearRules()
            PackMuleFrame:RefreshRulesList()
        end
    end)

    -- Close button
    local closeBtnBottom = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    closeBtnBottom:SetSize(100, 22)
    closeBtnBottom:SetPoint("BOTTOMRIGHT", -20, 15)
    closeBtnBottom:SetText("Close")
    closeBtnBottom:SetScript("OnClick", function() frame:Hide() end)

    frame:SetScript("OnShow", function()
        PackMuleFrame:RefreshRulesList()
    end)

    rulesFrame = frame
    return frame
end

function PackMuleFrame:RefreshRulesList()
    if not rulesFrame then return end

    local PackMule = HooligansLoot:GetModule("PackMule", true)
    if not PackMule then return end

    local rules = PackMule:GetRules()
    local scrollChild = rulesFrame.scrollChild

    -- Hide existing rows
    for _, row in ipairs(rulesFrame.ruleRows) do
        row:Hide()
    end

    local yOffset = 0
    local rowHeight = 28

    for i, rule in ipairs(rules) do
        local row = rulesFrame.ruleRows[i]

        if not row then
            row = CreateFrame("Frame", nil, scrollChild, "BackdropTemplate")
            row:SetHeight(rowHeight - 2)
            row:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8x8",
            })

            -- Enable checkbox
            local enableCheck = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
            enableCheck:SetSize(20, 20)
            enableCheck:SetPoint("LEFT", 5, 0)
            row.enableCheck = enableCheck

            -- Rule text
            local ruleText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            ruleText:SetPoint("LEFT", enableCheck, "RIGHT", 5, 0)
            ruleText:SetPoint("RIGHT", -70, 0)
            ruleText:SetJustifyH("LEFT")
            row.ruleText = ruleText

            -- Delete button
            local deleteBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            deleteBtn:SetSize(50, 18)
            deleteBtn:SetPoint("RIGHT", -5, 0)
            deleteBtn:SetText("Delete")
            row.deleteBtn = deleteBtn

            rulesFrame.ruleRows[i] = row
        end

        row:SetPoint("TOPLEFT", 0, -yOffset)
        row:SetPoint("TOPRIGHT", 0, -yOffset)

        -- Alternate row colors
        if i % 2 == 0 then
            row:SetBackdropColor(0.15, 0.15, 0.18, 0.8)
        else
            row:SetBackdropColor(0.1, 0.1, 0.12, 0.8)
        end

        -- Build rule description
        local desc = ""
        if rule.itemId then
            local name = GetItemInfo(rule.itemId)
            desc = "Item ID: " .. rule.itemId .. (name and (" (" .. name .. ")") or "")
        elseif rule.itemLink then
            desc = "Item: " .. rule.itemLink
        elseif rule.itemName then
            desc = "Pattern: " .. rule.itemName
        elseif rule.quality then
            local qualityName = Utils.GetQualityName(rule.quality)
            local opText = rule.qualityOperator == "<=" and "and lower" or
                          (rule.qualityOperator == ">=" and "and higher" or "exactly")
            desc = "Quality: " .. qualityName .. " " .. opText
        end
        desc = desc .. " -> |cff00ff00" .. (rule.target or "?") .. "|r"

        row.ruleText:SetText(desc)

        -- Enable checkbox
        row.enableCheck:SetChecked(rule.enabled ~= false)
        row.enableCheck:SetScript("OnClick", function(self)
            PackMule:UpdateRule(rule.id, { enabled = self:GetChecked() })
        end)

        -- Delete button
        row.deleteBtn:SetScript("OnClick", function()
            PackMule:RemoveRule(rule.id)
            PackMuleFrame:RefreshRulesList()
        end)

        row:Show()
        yOffset = yOffset + rowHeight
    end

    scrollChild:SetHeight(math.max(yOffset, 100))
end

-- ============================================================================
-- Ignored Items Frame
-- ============================================================================

function PackMuleFrame:CreateIgnoredFrame()
    if ignoredFrame then return ignoredFrame end

    local frame = CreateFrame("Frame", "HooligansPackMuleIgnoredFrame", UIParent, "BackdropTemplate")
    frame:SetSize(400, 380)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("DIALOG")
    frame:Hide()

    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        edgeSize = 20,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0.08, 0.08, 0.1, 0.95)
    frame:SetBackdropBorderColor(0.6, 0.5, 0.3, 1)

    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)

    tinsert(UISpecialFrames, "HooligansPackMuleIgnoredFrame")

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("|cffffffffPackMule|r - Ignored Items")

    local divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", 15, -40)
    divider:SetPoint("TOPRIGHT", -15, -40)
    divider:SetHeight(1)
    divider:SetColorTexture(0.4, 0.4, 0.4, 1)

    -- Add ignored item section
    local addLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    addLabel:SetPoint("TOPLEFT", 20, -55)
    addLabel:SetText("|cffffcc00Add Ignored Item|r")

    local itemLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    itemLabel:SetPoint("TOPLEFT", 25, -80)
    itemLabel:SetText("Item ID or Link:")

    local itemBox = CreateFrame("EditBox", "HooligansPackMuleIgnoredItemBox", frame, "InputBoxTemplate")
    itemBox:SetSize(200, 20)
    itemBox:SetPoint("LEFT", itemLabel, "RIGHT", 10, 0)
    itemBox:SetAutoFocus(false)
    itemBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    frame.itemBox = itemBox

    -- Support shift-clicking items into the edit box
    local origIgnoredHandleModifiedItemClick = HandleModifiedItemClick
    HandleModifiedItemClick = function(link, ...)
        if itemBox:IsVisible() and itemBox:HasFocus() and link then
            itemBox:SetText(link)
            return true
        end
        return origIgnoredHandleModifiedItemClick(link, ...)
    end

    -- Also hook ChatEdit_InsertLink as backup
    local origIgnoredChatEdit_InsertLink = ChatEdit_InsertLink
    ChatEdit_InsertLink = function(link)
        if itemBox:IsVisible() and itemBox:HasFocus() and link then
            itemBox:SetText(link)
            return true
        end
        return origIgnoredChatEdit_InsertLink(link)
    end

    -- Support drag-and-drop of items
    itemBox:SetScript("OnReceiveDrag", function(self)
        local infoType, itemID, itemLink = GetCursorInfo()
        if infoType == "item" and itemLink then
            self:SetText(itemLink)
            ClearCursor()
        end
    end)
    itemBox:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            local infoType, itemID, itemLink = GetCursorInfo()
            if infoType == "item" and itemLink then
                self:SetText(itemLink)
                ClearCursor()
            end
        end
    end)

    -- Hint text
    local itemHint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    itemHint:SetPoint("TOPLEFT", 25, -100)
    itemHint:SetText("Shift-click or drag item here")

    local addBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    addBtn:SetSize(80, 22)
    addBtn:SetPoint("TOPLEFT", 25, -115)
    addBtn:SetText("Add")
    addBtn:SetScript("OnClick", function()
        local PackMule = HooligansLoot:GetModule("PackMule", true)
        if PackMule then
            local input = itemBox:GetText()
            local itemId = tonumber(input) or Utils.GetItemID(input)
            if itemId then
                PackMule:AddIgnoredItem(itemId)
                itemBox:SetText("")
                PackMuleFrame:RefreshIgnoredList()
            else
                HooligansLoot:Print("Please enter a valid item ID or link")
            end
        end
    end)

    -- Check item section
    local checkLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    checkLabel:SetPoint("TOPLEFT", 20, -150)
    checkLabel:SetText("|cffffcc00Check Item|r")

    local checkBox = CreateFrame("EditBox", "HooligansPackMuleCheckItemBox", frame, "InputBoxTemplate")
    checkBox:SetSize(200, 20)
    checkBox:SetPoint("TOPLEFT", 25, -175)
    checkBox:SetAutoFocus(false)
    checkBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    frame.checkBox = checkBox

    -- Support shift-clicking and drag-drop for check box too
    local origCheckHandleModifiedItemClick = HandleModifiedItemClick
    HandleModifiedItemClick = function(link, ...)
        if checkBox:IsVisible() and checkBox:HasFocus() and link then
            checkBox:SetText(link)
            return true
        end
        return origCheckHandleModifiedItemClick(link, ...)
    end

    local origCheckChatEdit_InsertLink = ChatEdit_InsertLink
    ChatEdit_InsertLink = function(link)
        if checkBox:IsVisible() and checkBox:HasFocus() and link then
            checkBox:SetText(link)
            return true
        end
        return origCheckChatEdit_InsertLink(link)
    end

    checkBox:SetScript("OnReceiveDrag", function(self)
        local infoType, itemID, itemLink = GetCursorInfo()
        if infoType == "item" and itemLink then
            self:SetText(itemLink)
            ClearCursor()
        end
    end)
    checkBox:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            local infoType, itemID, itemLink = GetCursorInfo()
            if infoType == "item" and itemLink then
                self:SetText(itemLink)
                ClearCursor()
            end
        end
    end)

    local checkBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    checkBtn:SetSize(80, 22)
    checkBtn:SetPoint("LEFT", checkBox, "RIGHT", 10, 0)
    checkBtn:SetText("Check")

    local checkResult = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    checkResult:SetPoint("TOPLEFT", 25, -205)
    frame.checkResult = checkResult

    checkBtn:SetScript("OnClick", function()
        local PackMule = HooligansLoot:GetModule("PackMule", true)
        if PackMule then
            local input = checkBox:GetText()
            local itemId = tonumber(input) or Utils.GetItemID(input)
            if itemId then
                local itemName = GetItemInfo(itemId) or "Unknown"
                if PackMule:IsItemIgnored(itemId, itemName, input) then
                    checkResult:SetText("|cffff0000Item " .. itemId .. " IS ignored|r")
                else
                    checkResult:SetText("|cff00ff00Item " .. itemId .. " is NOT ignored|r")
                end
            else
                checkResult:SetText("|cffffff00Please enter a valid item ID or link|r")
            end
        end
    end)

    -- Ignored items list section
    local listLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    listLabel:SetPoint("TOPLEFT", 20, -235)
    listLabel:SetText("|cffffcc00Custom Ignored Items|r")

    local scrollFrame = CreateFrame("ScrollFrame", "HooligansPackMuleIgnoredScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 20, -255)
    scrollFrame:SetPoint("BOTTOMRIGHT", -40, 50)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(320, 1)
    scrollFrame:SetScrollChild(scrollChild)
    frame.scrollChild = scrollChild
    frame.itemRows = {}

    local closeBtnBottom = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    closeBtnBottom:SetSize(100, 22)
    closeBtnBottom:SetPoint("BOTTOM", 0, 15)
    closeBtnBottom:SetText("Close")
    closeBtnBottom:SetScript("OnClick", function() frame:Hide() end)

    frame:SetScript("OnShow", function()
        PackMuleFrame:RefreshIgnoredList()
    end)

    ignoredFrame = frame
    return frame
end

function PackMuleFrame:RefreshIgnoredList()
    if not ignoredFrame then return end

    local PackMule = HooligansLoot:GetModule("PackMule", true)
    if not PackMule then return end

    local ignored = PackMule:GetIgnoredItems()
    local scrollChild = ignoredFrame.scrollChild

    -- Hide existing rows
    for _, row in ipairs(ignoredFrame.itemRows) do
        row:Hide()
    end

    local yOffset = 0
    local rowHeight = 24
    local i = 0

    for itemId, _ in pairs(ignored) do
        i = i + 1
        local row = ignoredFrame.itemRows[i]

        if not row then
            row = CreateFrame("Frame", nil, scrollChild, "BackdropTemplate")
            row:SetHeight(rowHeight - 2)
            row:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8x8",
            })

            local itemText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            itemText:SetPoint("LEFT", 10, 0)
            itemText:SetPoint("RIGHT", -60, 0)
            itemText:SetJustifyH("LEFT")
            row.itemText = itemText

            local removeBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            removeBtn:SetSize(50, 18)
            removeBtn:SetPoint("RIGHT", -5, 0)
            removeBtn:SetText("Remove")
            row.removeBtn = removeBtn

            ignoredFrame.itemRows[i] = row
        end

        row:SetPoint("TOPLEFT", 0, -yOffset)
        row:SetPoint("TOPRIGHT", 0, -yOffset)

        if i % 2 == 0 then
            row:SetBackdropColor(0.15, 0.15, 0.18, 0.8)
        else
            row:SetBackdropColor(0.1, 0.1, 0.12, 0.8)
        end

        local itemName = GetItemInfo(itemId) or "Loading..."
        row.itemText:SetText(itemId .. " - " .. itemName)

        local currentItemId = itemId -- Capture for closure
        row.removeBtn:SetScript("OnClick", function()
            PackMule:RemoveIgnoredItem(currentItemId)
            PackMuleFrame:RefreshIgnoredList()
        end)

        row:Show()
        yOffset = yOffset + rowHeight
    end

    scrollChild:SetHeight(math.max(yOffset, 50))
end

-- ============================================================================
-- Public API
-- ============================================================================

function PackMuleFrame:Show()
    -- Create all frames
    local frame = self:CreateMainFrame()
    local rules = self:CreateRulesFrame()
    local ignored = self:CreateIgnoredFrame()

    -- Position main frame in center
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

    -- Position rules frame to the RIGHT of main frame
    rules:ClearAllPoints()
    rules:SetPoint("TOPLEFT", frame, "TOPRIGHT", 5, 0)

    -- Position ignored frame to the LEFT of main frame
    ignored:ClearAllPoints()
    ignored:SetPoint("TOPRIGHT", frame, "TOPLEFT", -5, 0)

    -- Refresh and show all
    self:RefreshMainValues()
    self:RefreshRulesList()
    self:RefreshIgnoredList()

    frame:Show()
    rules:Show()
    ignored:Show()
end

function PackMuleFrame:Hide()
    if mainFrame then
        mainFrame:Hide()
    end
    if rulesFrame then
        rulesFrame:Hide()
    end
    if ignoredFrame then
        ignoredFrame:Hide()
    end
end

function PackMuleFrame:Toggle()
    if mainFrame and mainFrame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

function PackMuleFrame:ShowRulesFrame()
    local frame = self:CreateRulesFrame()

    -- Position relative to main frame if visible
    if mainFrame and mainFrame:IsShown() then
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", mainFrame, "TOPRIGHT", 5, 0)
    end

    self:RefreshRulesList()
    frame:Show()
end

function PackMuleFrame:HideRulesFrame()
    if rulesFrame then
        rulesFrame:Hide()
    end
end

function PackMuleFrame:ToggleRulesFrame()
    if rulesFrame and rulesFrame:IsShown() then
        self:HideRulesFrame()
    else
        self:ShowRulesFrame()
    end
end

function PackMuleFrame:ShowIgnoredFrame()
    local frame = self:CreateIgnoredFrame()

    -- Position relative to main frame if visible
    if mainFrame and mainFrame:IsShown() then
        frame:ClearAllPoints()
        frame:SetPoint("TOPRIGHT", mainFrame, "TOPLEFT", -5, 0)
    end

    self:RefreshIgnoredList()
    frame:Show()
end

function PackMuleFrame:HideIgnoredFrame()
    if ignoredFrame then
        ignoredFrame:Hide()
    end
end

function PackMuleFrame:ToggleIgnoredFrame()
    if ignoredFrame and ignoredFrame:IsShown() then
        self:HideIgnoredFrame()
    else
        self:ShowIgnoredFrame()
    end
end
