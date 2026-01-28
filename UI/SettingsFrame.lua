-- UI/SettingsFrame.lua
-- Settings/Options panel

local ADDON_NAME, NS = ...
local HooligansLoot = NS.addon

local SettingsFrame = HooligansLoot:NewModule("SettingsFrame")

-- Frame reference
local settingsFrame = nil

-- Quality options
local QUALITY_OPTIONS = {
    { value = 2, text = "|cff1eff00Uncommon|r (Green+)", color = {0.12, 1, 0} },
    { value = 3, text = "|cff0070ddRare|r (Blue+)", color = {0, 0.44, 0.87} },
    { value = 4, text = "|cffa335eeEpic|r (Purple+)", color = {0.64, 0.21, 0.93} },
    { value = 5, text = "|cffff8000Legendary|r (Orange)", color = {1, 0.5, 0} },
}

function SettingsFrame:OnEnable()
    -- Nothing to do on enable
end

function SettingsFrame:CreateFrame()
    if settingsFrame then return settingsFrame end

    -- Main frame
    local frame = CreateFrame("Frame", "HooligansLootSettingsFrame", UIParent, "BackdropTemplate")
    frame:SetSize(400, 200)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("DIALOG")
    frame:Hide()

    -- Backdrop (matching main frame style)
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
    tinsert(UISpecialFrames, "HooligansLootSettingsFrame")

    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("|cffffffffHOOLIGANS Loot Council|r - Settings")

    -- Divider
    local divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", 15, -40)
    divider:SetPoint("TOPRIGHT", -15, -40)
    divider:SetHeight(1)
    divider:SetColorTexture(0.4, 0.4, 0.4, 1)

    -- === LOOT TRACKING SECTION ===
    local sectionLoot = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sectionLoot:SetPoint("TOPLEFT", 20, -55)
    sectionLoot:SetText("|cffffcc00Loot Tracking|r")

    -- Minimum Quality
    local qualityLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    qualityLabel:SetPoint("TOPLEFT", 25, -80)
    qualityLabel:SetText("Minimum Item Quality:")

    -- Quality Dropdown
    local qualityDropdown = CreateFrame("Frame", "HooligansLootQualityDropdown", frame, "UIDropDownMenuTemplate")
    qualityDropdown:SetPoint("TOPLEFT", qualityLabel, "BOTTOMLEFT", -15, -5)

    local function QualityDropdown_OnClick(self, arg1, arg2, checked)
        HooligansLoot.db.profile.settings.minQuality = arg1
        UIDropDownMenu_SetText(qualityDropdown, arg2)
        HooligansLoot:Print("Minimum quality set to: " .. arg2)
    end

    local function QualityDropdown_Initialize(self, level)
        local info = UIDropDownMenu_CreateInfo()
        for _, option in ipairs(QUALITY_OPTIONS) do
            info.text = option.text
            info.arg1 = option.value
            info.arg2 = option.text
            info.func = QualityDropdown_OnClick
            info.checked = (HooligansLoot.db.profile.settings.minQuality == option.value)
            UIDropDownMenu_AddButton(info, level)
        end
    end

    UIDropDownMenu_SetWidth(qualityDropdown, 180)
    UIDropDownMenu_Initialize(qualityDropdown, QualityDropdown_Initialize)
    frame.qualityDropdown = qualityDropdown

    -- === BUTTONS ===
    -- Close button at bottom
    local closeBtnBottom = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    closeBtnBottom:SetSize(100, 26)
    closeBtnBottom:SetPoint("BOTTOM", 0, 15)
    closeBtnBottom:SetText("Close")
    closeBtnBottom:SetScript("OnClick", function() frame:Hide() end)

    -- OnShow - refresh values and center
    frame:SetScript("OnShow", function(self)
        -- Always center when shown
        self:ClearAllPoints()
        self:SetPoint("CENTER")
        SettingsFrame:RefreshValues()
    end)

    settingsFrame = frame
    return frame
end

function SettingsFrame:RefreshValues()
    if not settingsFrame then return end

    local settings = HooligansLoot.db.profile.settings

    -- Update quality dropdown text
    for _, option in ipairs(QUALITY_OPTIONS) do
        if option.value == settings.minQuality then
            UIDropDownMenu_SetText(settingsFrame.qualityDropdown, option.text)
            break
        end
    end
end

function SettingsFrame:Show()
    local frame = self:CreateFrame()
    self:RefreshValues()
    frame:Show()
end

function SettingsFrame:Hide()
    if settingsFrame then
        settingsFrame:Hide()
    end
end

function SettingsFrame:Toggle()
    if settingsFrame and settingsFrame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end
