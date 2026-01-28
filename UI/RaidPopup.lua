-- UI/RaidPopup.lua
-- Popup dialog when entering raids

local ADDON_NAME, NS = ...
local HooligansLoot = NS.addon

local RaidPopup = HooligansLoot:NewModule("RaidPopup", "AceEvent-3.0")

-- Frame reference
local popupFrame = nil
local hasShownForCurrentRaid = false
local lastZone = nil

function RaidPopup:OnEnable()
    -- Register for zone change events
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA", "OnZoneChanged")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnZoneChanged")
end

function RaidPopup:OnDisable()
    self:UnregisterAllEvents()
end

function RaidPopup:OnZoneChanged()
    -- Small delay to let the game update instance info
    C_Timer.After(1, function()
        self:CheckForRaid()
    end)
end

function RaidPopup:CheckForRaid()
    -- Check if we're in a raid instance
    local inInstance, instanceType = IsInInstance()
    local zoneName = GetRealZoneText() or "Unknown"

    -- Reset flag if we changed zones
    if zoneName ~= lastZone then
        hasShownForCurrentRaid = false
        lastZone = zoneName
    end

    -- Only show popup if:
    -- 1. We're in a raid instance
    -- 2. We haven't shown the popup for this raid yet
    -- 3. We're in a raid group
    -- 4. No active session exists
    -- 5. We're the Master Looter or Raid Leader
    if inInstance and instanceType == "raid" and not hasShownForCurrentRaid and IsInRaid() then
        -- Only ML/RL can start sessions
        local Voting = HooligansLoot:GetModule("Voting", true)
        if not Voting or not Voting:IsMasterLooter() then
            return
        end

        local SessionManager = HooligansLoot:GetModule("SessionManager", true)
        local currentSession = SessionManager and SessionManager:GetCurrentSession()

        -- Only show if no active session
        if not currentSession or currentSession.status ~= "active" then
            hasShownForCurrentRaid = true
            self:ShowPopup(zoneName)
        end
    end
end

function RaidPopup:CreatePopupFrame()
    if popupFrame then return popupFrame end

    -- Main popup frame - wider and taller for better readability
    local frame = CreateFrame("Frame", "HooligansLootRaidPopup", UIParent, "BackdropTemplate")
    frame:SetSize(360, 160)
    frame:SetPoint("CENTER", 0, 100)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(100)
    frame:Hide()

    -- Clean dark backdrop
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        edgeSize = 24,
        insets = { left = 6, right = 6, top = 6, bottom = 6 },
    })
    frame:SetBackdropColor(0.08, 0.08, 0.1, 0.95)

    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", 0, 0)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)

    -- Logo centered at top
    local logo = frame:CreateTexture(nil, "OVERLAY")
    logo:SetSize(36, 36)
    logo:SetPoint("TOP", 0, -14)
    logo:SetTexture("Interface\\AddOns\\HooligansLoot\\Textures\\logo")

    -- Question text - clean single line
    frame.question = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.question:SetPoint("TOP", 0, -58)
    frame.question:SetText("Would you like to use HOOLIGANS Loot Council\nwith this group?")
    frame.question:SetTextColor(0.9, 0.9, 0.9)

    -- Yes button
    local yesBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    yesBtn:SetSize(120, 28)
    yesBtn:SetPoint("BOTTOMLEFT", 50, 22)
    yesBtn:SetText("Yes")
    yesBtn:SetScript("OnClick", function()
        RaidPopup:OnYesClicked()
    end)

    -- No button
    local noBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    noBtn:SetSize(120, 28)
    noBtn:SetPoint("BOTTOMRIGHT", -50, 22)
    noBtn:SetText("No")
    noBtn:SetScript("OnClick", function()
        frame:Hide()
    end)

    -- Make closable with Escape
    tinsert(UISpecialFrames, "HooligansLootRaidPopup")

    popupFrame = frame
    return frame
end

function RaidPopup:ShowPopup(zoneName)
    local frame = self:CreatePopupFrame()
    frame:Show()

    -- Play a subtle sound
    PlaySound(SOUNDKIT.IG_MAINMENU_OPEN)
end

function RaidPopup:HidePopup()
    if popupFrame then
        popupFrame:Hide()
    end
end

function RaidPopup:OnYesClicked()
    -- Hide popup
    self:HidePopup()

    -- Start a new session
    local SessionManager = HooligansLoot:GetModule("SessionManager", true)
    if SessionManager then
        SessionManager:NewSession()
    end

    -- Show main frame
    HooligansLoot:ShowMainFrame()

    HooligansLoot:Print("Session started! Ready to track loot.")
end

-- Manual trigger for testing
function RaidPopup:Test()
    hasShownForCurrentRaid = false
    self:ShowPopup("Test Raid")
end
