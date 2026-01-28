-- Modules/TradeManager.lua
-- Handles auto-trade functionality

local ADDON_NAME, NS = ...
local HooligansLoot = NS.addon
local Utils = NS.Utils

local TradeManager = HooligansLoot:NewModule("TradeManager", "AceEvent-3.0")

-- State tracking
local currentTradeTarget = nil
local pendingTradeItems = {}
local itemsAddedToTrade = {}
local promptFrame = nil

function TradeManager:OnEnable()
    -- Trade window events
    self:RegisterEvent("TRADE_SHOW")
    self:RegisterEvent("TRADE_CLOSED")
    self:RegisterEvent("TRADE_ACCEPT_UPDATE")
    self:RegisterEvent("UI_INFO_MESSAGE")
    self:RegisterEvent("UI_ERROR_MESSAGE")
end

function TradeManager:OnDisable()
    self:UnregisterAllEvents()
end

function TradeManager:TRADE_SHOW()
    -- Get trade target name
    local targetName = UnitName("NPC") -- Trade target is "NPC" unit during trade
    if not targetName then
        -- Alternative method
        targetName = GetTradeTargetInfo and GetTradeTargetInfo() or nil
    end

    if not targetName then
        HooligansLoot:Debug("Trade opened but couldn't get target name")
        return
    end

    currentTradeTarget = Utils.StripRealm(targetName)
    HooligansLoot:Debug("Trade opened with: " .. currentTradeTarget)

    -- Check if we have pending items for this player
    self:CheckPendingItemsForTarget()
end

function TradeManager:TRADE_CLOSED()
    HooligansLoot:Debug("Trade closed")
    currentTradeTarget = nil
    pendingTradeItems = {}
    itemsAddedToTrade = {}

    if promptFrame then
        promptFrame:Hide()
    end
end

function TradeManager:TRADE_ACCEPT_UPDATE(event, playerAccepted, targetAccepted)
    HooligansLoot:Debug(string.format("Trade accept update: player=%s, target=%s",
        tostring(playerAccepted), tostring(targetAccepted)))
end

function TradeManager:UI_INFO_MESSAGE(event, messageType, message)
    -- Check for trade completion message
    if message and message:find("Trade complete") then
        HooligansLoot:Debug("Trade completed successfully")
        self:OnTradeComplete()
    end
end

function TradeManager:UI_ERROR_MESSAGE(event, messageType, message)
    if message then
        HooligansLoot:Debug("Trade error: " .. message)
    end
end

function TradeManager:OnTradeComplete()
    -- Mark items as awarded
    local SessionManager = HooligansLoot:GetModule("SessionManager")
    local session = SessionManager:GetCurrentSession()

    if not session then return end

    for itemGUID, _ in pairs(itemsAddedToTrade) do
        SessionManager:MarkAwarded(session.id, itemGUID)
        HooligansLoot:Print("Item awarded to " .. (currentTradeTarget or "player"))
    end

    itemsAddedToTrade = {}
end

function TradeManager:CheckPendingItemsForTarget()
    if not currentTradeTarget then return end

    local SessionManager = HooligansLoot:GetModule("SessionManager")
    local session = SessionManager:GetCurrentSession()

    if not session then return end

    -- Get items pending for this player
    pendingTradeItems = SessionManager:GetAwardsForPlayer(session.id, currentTradeTarget)

    if #pendingTradeItems > 0 then
        HooligansLoot:Debug("Found " .. #pendingTradeItems .. " pending items for " .. currentTradeTarget)

        -- Auto-add items to trade window
        for _, item in ipairs(pendingTradeItems) do
            self:AddItemToTrade(item)
        end
    end
end

function TradeManager:CreatePromptFrame()
    if promptFrame then return promptFrame end

    local frame = CreateFrame("Frame", "HooligansLootTradePrompt", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(300, 200)
    frame:SetPoint("TOP", 0, -100)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(100)
    frame:Hide()

    -- Title
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.title:SetPoint("TOP", 0, -5)
    frame.title:SetText(HooligansLoot.colors.primary .. "HOOLIGANS|r Loot")

    -- Target name
    frame.targetText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.targetText:SetPoint("TOP", 0, -30)
    frame.targetText:SetText("Trading with: ")

    -- Items list
    frame.itemsText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.itemsText:SetPoint("TOP", 0, -50)
    frame.itemsText:SetWidth(260)
    frame.itemsText:SetJustifyH("LEFT")

    -- Add All button
    local addAllBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    addAllBtn:SetSize(100, 25)
    addAllBtn:SetPoint("BOTTOMLEFT", 15, 10)
    addAllBtn:SetText("Add All")
    addAllBtn:SetScript("OnClick", function()
        TradeManager:AddAllItemsToTrade()
    end)
    frame.addAllBtn = addAllBtn

    -- Skip button
    local skipBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    skipBtn:SetSize(80, 25)
    skipBtn:SetPoint("BOTTOMRIGHT", -15, 10)
    skipBtn:SetText("Skip")
    skipBtn:SetScript("OnClick", function()
        frame:Hide()
    end)

    promptFrame = frame
    return frame
end

function TradeManager:ShowTradePrompt()
    local frame = self:CreatePromptFrame()

    frame.targetText:SetText("Trading with: " .. HooligansLoot.colors.success .. currentTradeTarget .. "|r")

    -- Build items list
    local itemLines = {}
    for i, item in ipairs(pendingTradeItems) do
        if i <= 6 then -- Max 6 trade slots
            table.insert(itemLines, item.link or item.name)
        end
    end

    local itemsText = "Pending items:\n" .. table.concat(itemLines, "\n")
    if #pendingTradeItems > 6 then
        itemsText = itemsText .. "\n" .. HooligansLoot.colors.warning .. "(+" .. (#pendingTradeItems - 6) .. " more)|r"
    end

    frame.itemsText:SetText(itemsText)

    -- Adjust frame height based on content
    local height = 100 + (#itemLines * 15)
    frame:SetHeight(math.max(150, math.min(height, 300)))

    frame:Show()
end

function TradeManager:AddAllItemsToTrade()
    for _, item in ipairs(pendingTradeItems) do
        self:AddItemToTrade(item)
    end

    if promptFrame then
        promptFrame:Hide()
    end
end

function TradeManager:AddItemToTrade(item)
    if not item then return false end

    -- Refresh item location first
    local LootTracker = HooligansLoot:GetModule("LootTracker")
    local session = HooligansLoot:GetModule("SessionManager"):GetCurrentSession()

    if session then
        LootTracker:RefreshItemLocations(session)
    end

    -- Find the item in bags
    local bagId, slotId = item.bagId, item.slotId

    -- Verify item is still there
    local bagLink = C_Container.GetContainerItemLink(bagId, slotId)
    if not bagLink then
        -- Item may have moved, try to find it
        bagId, slotId, bagLink = LootTracker:FindItemInBags(item.id)
        if not bagLink then
            HooligansLoot:Print(HooligansLoot.colors.error .. "Could not find item in bags: " .. (item.name or "Unknown") .. "|r")
            return false
        end
    end

    -- Find an empty trade slot
    local tradeSlot = nil
    for i = 1, 6 do
        local tradeLink = GetTradePlayerItemLink(i)
        if not tradeLink then
            tradeSlot = i
            break
        end
    end

    if not tradeSlot then
        HooligansLoot:Print(HooligansLoot.colors.warning .. "No empty trade slots available|r")
        return false
    end

    -- Add item to trade
    -- Note: PickupContainerItem + ClickTradeButton is the safe way to do this
    C_Container.PickupContainerItem(bagId, slotId)
    ClickTradeButton(tradeSlot)

    -- Track that we added this item
    itemsAddedToTrade[item.guid] = true

    HooligansLoot:Debug("Added to trade: " .. (item.name or "item"))
    return true
end

function TradeManager:GetPendingItemsForPlayer(playerName)
    local SessionManager = HooligansLoot:GetModule("SessionManager")
    local session = SessionManager:GetCurrentSession()

    if not session then return {} end

    return SessionManager:GetAwardsForPlayer(session.id, playerName)
end

function TradeManager:GetCurrentTradeTarget()
    return currentTradeTarget
end

function TradeManager:IsTradeWindowOpen()
    return currentTradeTarget ~= nil
end
