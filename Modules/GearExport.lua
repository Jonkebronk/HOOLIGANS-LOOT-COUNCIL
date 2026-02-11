-- Modules/GearExport.lua
-- Export player's equipped gear in Gearcheck format (minimal JSON)

local ADDON_NAME, NS = ...
local HooligansLoot = NS.addon
local Utils = NS.Utils

local GearExport = HooligansLoot:NewModule("GearExport")

-- Equipment slots: WoW slot IDs to iterate
local SLOT_IDS = { 1, 2, 3, 15, 5, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17, 18 }

-- Export dialog frame
local exportFrame = nil

function GearExport:OnEnable()
    -- Nothing to do on enable
end

-- Parse item link to extract itemID, enchantID, and gem IDs
-- Classic/TBC item link format: item:ID:enchant:gem1:gem2:gem3:gem4:suffix:unique
function GearExport:ParseItemLink(itemLink)
    if not itemLink then return nil end

    local itemString = itemLink:match("item:([%-?%d:]+)")
    if not itemString then return nil end

    local parts = {strsplit(":", itemString)}

    return {
        itemID = tonumber(parts[1]) or 0,
        enchantID = tonumber(parts[2]) or 0,
        gem1 = tonumber(parts[3]) or 0,
        gem2 = tonumber(parts[4]) or 0,
        gem3 = tonumber(parts[5]) or 0,
        gem4 = tonumber(parts[6]) or 0,
    }
end

-- Get all equipped gear as minimal items array (Gearcheck format)
function GearExport:GetEquippedGear()
    local items = {}

    for _, slotID in ipairs(SLOT_IDS) do
        local itemLink = GetInventoryItemLink("player", slotID)

        if itemLink then
            local parsed = self:ParseItemLink(itemLink)
            if parsed and parsed.itemID > 0 then
                local item = {
                    id = parsed.itemID,
                    enchant = parsed.enchantID,
                    gems = { parsed.gem1, parsed.gem2, parsed.gem3, parsed.gem4 },
                }

                table.insert(items, item)
            end
        end
    end

    return items
end

-- Export gear in Gearcheck JSON format (minimal)
function GearExport:ExportToJSON()
    local items = self:GetEquippedGear()

    local exportData = {
        items = items,
    }

    return Utils.ToJSON(exportData), #items
end

-- Create the export dialog frame
function GearExport:CreateExportFrame()
    if exportFrame then return exportFrame end

    local frame = CreateFrame("Frame", "HooligansLootGearExportFrame", UIParent, "BackdropTemplate")
    frame:SetSize(450, 400)
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

    -- Title
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.title:SetPoint("TOP", 0, -15)
    frame.title:SetText(HooligansLoot.colors.primary .. "HOOLIGANS|r Loot - Gear Export")

    -- Close button
    local closeX = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeX:SetPoint("TOPRIGHT", -2, -2)
    closeX:SetScript("OnClick", function() frame:Hide() end)

    -- Item count info
    frame.itemInfo = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.itemInfo:SetPoint("TOP", frame.title, "BOTTOM", 0, -5)
    frame.itemInfo:SetTextColor(0.7, 0.7, 0.7)

    -- Scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", "HooligansLootGearExportScroll", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 15, -55)
    scrollFrame:SetPoint("BOTTOMRIGHT", -35, 45)

    -- Edit box
    local editBox = CreateFrame("EditBox", "HooligansLootGearExportEditBox", scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetFontObject("ChatFontNormal")
    editBox:SetWidth(scrollFrame:GetWidth())
    editBox:SetAutoFocus(true)
    editBox:EnableMouse(true)
    editBox:SetScript("OnEscapePressed", function() frame:Hide() end)

    scrollFrame:SetScrollChild(editBox)
    frame.editBox = editBox

    -- Instructions
    local instructions = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    instructions:SetPoint("BOTTOMLEFT", 15, 15)
    instructions:SetText("Press Ctrl+C to copy | Paste on voting website")
    instructions:SetTextColor(0.7, 0.7, 0.7)

    tinsert(UISpecialFrames, "HooligansLootGearExportFrame")

    exportFrame = frame
    return frame
end

-- Refresh the export data
function GearExport:RefreshExport()
    if not exportFrame or not exportFrame:IsShown() then return end

    local exportString, itemCount = self:ExportToJSON()

    if exportString then
        exportFrame.editBox:SetText(exportString)
        exportFrame.editBox:HighlightText()
        exportFrame.itemInfo:SetText(itemCount .. " equipped items")
    else
        exportFrame.editBox:SetText("Error: Unknown error")
    end
end

-- Show the gear export dialog
function GearExport:ShowDialog()
    local frame = self:CreateExportFrame()
    frame:Show()
    self:RefreshExport()
end

-- Hide the dialog
function GearExport:HideDialog()
    if exportFrame then
        exportFrame:Hide()
    end
end
