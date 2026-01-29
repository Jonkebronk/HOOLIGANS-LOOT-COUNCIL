-- Modules/Export.lua
-- Export session data to JSON/CSV

local ADDON_NAME, NS = ...
local HooligansLoot = NS.addon
local Utils = NS.Utils

local Export = HooligansLoot:NewModule("Export")

-- Export dialog frame
local exportFrame = nil

function Export:OnEnable()
    -- Nothing to do on enable
end

function Export:GetExportData(sessionId)
    local SessionManager = HooligansLoot:GetModule("SessionManager")
    local session = sessionId and SessionManager:GetSession(sessionId) or SessionManager:GetCurrentSession()

    if not session then
        return nil, "No session found"
    end

    local exportData = {
        session = session.name,
        sessionId = session.id,
        guild = "HOOLIGANS",
        exported = Utils.FormatISO8601(time()),
        created = Utils.FormatISO8601(session.created),
        status = session.status,
        items = {},
    }

    for _, item in ipairs(session.items) do
        local itemExport = {
            id = item.id,
            name = item.name,
            link = item.link,
            boss = item.boss,
            quality = item.quality,
            timestamp = item.timestamp,
            tradeable = item.tradeable,
            tradeExpires = item.tradeExpires,
        }

        -- Include award info if available
        local award = session.awards[item.guid]
        if award then
            itemExport.winner = award.winner
            itemExport.awarded = award.awarded
        end

        table.insert(exportData.items, itemExport)
    end

    return exportData, nil
end

-- Get export data formatted for HOOLIGANS platform import
function Export:GetPlatformExportData(sessionId)
    local SessionManager = HooligansLoot:GetModule("SessionManager")
    local session = sessionId and SessionManager:GetSession(sessionId) or SessionManager:GetCurrentSession()

    if not session then
        return nil, "No session found"
    end

    -- Get GearComparison for slot mapping
    local GearComparison = HooligansLoot:GetModule("GearComparison", true)

    -- Format for HOOLIGANS platform /api/loot/import-rc endpoint
    local exportData = {
        teamId = "", -- User fills this in on platform or we could make it configurable
        items = {},
    }

    -- Get vote responses if voting module is available
    local Voting = HooligansLoot:GetModule("Voting", true)
    local activeVotes = Voting and Voting:GetActiveVotes() or {}

    for _, item in ipairs(session.items) do
        -- Get item level if available (TBC items are typically 100-150 range)
        local ilvl = 0
        if item.id then
            local _, _, _, itemLevel = GetItemInfo(item.id)
            ilvl = itemLevel or 0
        end

        -- Get relevant slots for this item
        local relevantSlots = {}
        if GearComparison and item.link then
            local slots = GearComparison:GetSlotsForItem(item.link)
            if slots then
                for _, slotId in ipairs(slots) do
                    relevantSlots[slotId] = true
                end
            end
        end

        local itemExport = {
            itemName = item.name or "Unknown",
            wowheadId = item.id,
            link = item.link,  -- Full WoW item link for Wowhead tooltip parsing
            quality = item.quality or 4,
            ilvl = ilvl,
            -- Extra fields for context (platform can ignore if not needed)
            boss = item.boss,
            timestamp = item.timestamp,
            responses = {},
        }

        -- Helper to build currentGear filtered by relevant slots
        local function buildCurrentGear(playerGear)
            if not playerGear then return nil end
            local gearList = {}
            for slotId, gearInfo in pairs(playerGear) do
                local numSlot = tonumber(slotId)
                -- Only include slots relevant to this item
                if numSlot and relevantSlots[numSlot] and gearInfo and gearInfo.l then
                    local itemName = gearInfo.l:match("%[(.-)%]") or "Unknown"
                    table.insert(gearList, {
                        slot = numSlot,
                        item = itemName,
                        link = gearInfo.l,
                        ilvl = gearInfo.i,
                    })
                end
            end
            return #gearList > 0 and gearList or nil
        end

        -- Helper to find player gear (handles realm name differences)
        local function findPlayerGear(playerGear, playerName)
            if not playerGear then return nil end
            -- Try exact match first
            if playerGear[playerName] then return playerGear[playerName] end
            -- Try without realm suffix
            local shortName = playerName:match("([^%-]+)") or playerName
            for gearPlayer, data in pairs(playerGear) do
                local shortGearPlayer = gearPlayer:match("([^%-]+)") or gearPlayer
                if shortName == shortGearPlayer then
                    return data
                end
            end
            return nil
        end

        -- Find vote responses for this item
        for voteId, vote in pairs(activeVotes) do
            if vote.itemGUID == item.guid then
                for playerName, response in pairs(vote.responses or {}) do
                    local responseData = {
                        player = playerName,
                        class = response.class,
                        response = response.response,
                        note = response.note,
                    }
                    -- Add player's equipped gear if available
                    local gearData = findPlayerGear(vote.playerGear, playerName)
                    local currentGear = buildCurrentGear(gearData)
                    if currentGear then
                        responseData.currentGear = currentGear
                    end
                    table.insert(itemExport.responses, responseData)
                end
                break
            end
        end

        -- Also check session.votes if stored there
        if session.votes then
            for voteId, vote in pairs(session.votes) do
                if vote.itemGUID == item.guid and #itemExport.responses == 0 then
                    for playerName, response in pairs(vote.responses or {}) do
                        local responseData = {
                            player = playerName,
                            class = response.class,
                            response = response.response,
                            note = response.note,
                        }
                        -- Add player's equipped gear if available
                        local gearData = findPlayerGear(vote.playerGear, playerName)
                        local currentGear = buildCurrentGear(gearData)
                        if currentGear then
                            responseData.currentGear = currentGear
                        end
                        table.insert(itemExport.responses, responseData)
                    end
                    break
                end
            end
        end

        table.insert(exportData.items, itemExport)
    end

    return exportData, nil
end

function Export:ExportToJSON(sessionId)
    -- Use platform format by default for HOOLIGANS platform compatibility
    local data, err = self:GetPlatformExportData(sessionId)
    if not data then
        return nil, err
    end

    return Utils.ToJSON(data), nil
end

function Export:ExportToJSONFull(sessionId)
    -- Full export with all item details (for backup/debugging)
    local data, err = self:GetExportData(sessionId)
    if not data then
        return nil, err
    end

    return Utils.ToJSON(data), nil
end

-- Helper to escape CSV fields (quote if contains comma, quote, or newline)
local function csvEscape(value)
    if value == nil then return "" end
    value = tostring(value)
    -- If field contains comma, quote, or newline, wrap in quotes and escape internal quotes
    if value:find('[,"\n]') then
        return '"' .. value:gsub('"', '""') .. '"'
    end
    return value
end

function Export:ExportToCSV(sessionId)
    local data, err = self:GetExportData(sessionId)
    if not data then
        return nil, err
    end

    -- RCLootCouncil-compatible CSV format
    local lines = {}

    -- Header row (exactly matching RCLootCouncil)
    table.insert(lines, "player,date,time,id,item,itemID,itemString,response,votes,class,instance,boss,difficultyID,mapID,groupSize,gear1,gear2,responseID,isAwardReason,subType,equipLoc,note,owner")

    for _, item in ipairs(data.items) do
        -- Format date and time (RCLootCouncil uses dd/mm/yy format)
        local dateStr = item.timestamp and date("%d/%m/%y", item.timestamp) or ""
        local timeStr = item.timestamp and date("%H:%M:%S", item.timestamp) or ""

        -- Build item link in proper format
        local itemLink = item.link or ""
        -- Make sure link has proper color codes for epic items
        if item.id and (not itemLink or itemLink == "") then
            -- Default to epic quality color if unknown
            local qualityColor = "ffa335ee"  -- Epic purple
            if item.quality == 5 then
                qualityColor = "ffff8000"  -- Legendary orange
            elseif item.quality == 3 then
                qualityColor = "ff0070dd"  -- Rare blue
            elseif item.quality == 2 then
                qualityColor = "ff1eff00"  -- Uncommon green
            end
            itemLink = "|c" .. qualityColor .. "|Hitem:" .. item.id .. "::::::::70:::::|h[" .. (item.name or "Unknown") .. "]|h|r"
        end

        -- Build itemString (RCLootCouncil format)
        local itemString = ""
        if item.id then
            itemString = "item:" .. item.id .. ":0:0:0:0:0:0:0"
        end

        -- Build CSV row with proper escaping
        -- Fields: player,date,time,id,item,itemID,itemString,response,votes,class,instance,boss,difficultyID,mapID,groupSize,gear1,gear2,responseID,isAwardReason,subType,equipLoc,note,owner
        local fields = {
            csvEscape(item.winner or ""),           -- player (empty if not awarded yet)
            csvEscape(dateStr),                     -- date
            csvEscape(timeStr),                     -- time
            "",                                     -- id (RCLootCouncil internal ID, empty)
            csvEscape(itemLink),                    -- item (full hyperlink)
            csvEscape(item.id or ""),               -- itemID
            csvEscape(itemString),                  -- itemString
            csvEscape(item.winner and "awarded" or "awaiting"), -- response
            "0",                                    -- votes
            "",                                     -- class
            csvEscape(data.session or ""),          -- instance
            csvEscape(item.boss or ""),             -- boss
            "",                                     -- difficultyID
            "",                                     -- mapID
            "25",                                   -- groupSize
            "",                                     -- gear1
            "",                                     -- gear2
            csvEscape(item.winner and "1" or ""),   -- responseID
            "false",                                -- isAwardReason
            "",                                     -- subType
            "",                                     -- equipLoc
            "",                                     -- note
            "",                                     -- owner
        }

        table.insert(lines, table.concat(fields, ","))
    end

    return table.concat(lines, "\n"), nil
end

function Export:GetExportString(sessionId, format)
    format = format or HooligansLoot.db.profile.settings.exportFormat

    if format == "csv" then
        return self:ExportToCSV(sessionId)
    else
        return self:ExportToJSON(sessionId)
    end
end

function Export:CreateExportFrame()
    if exportFrame then return exportFrame end

    -- Create simple, clean dialog matching History export style
    local frame = CreateFrame("Frame", "HooligansLootExportFrame", UIParent, "BackdropTemplate")
    frame:SetSize(450, 350)
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
    frame.title:SetText(HooligansLoot.colors.primary .. "HOOLIGANS|r Loot - Export")

    -- Close button (X)
    local closeX = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeX:SetPoint("TOPRIGHT", -2, -2)
    closeX:SetScript("OnClick", function() frame:Hide() end)

    -- Session info below title
    frame.sessionInfo = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.sessionInfo:SetPoint("TOP", frame.title, "BOTTOM", 0, -5)
    frame.sessionInfo:SetTextColor(0.7, 0.7, 0.7)

    -- Scroll frame for export text
    local scrollFrame = CreateFrame("ScrollFrame", "HooligansLootExportScroll", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 15, -55)
    scrollFrame:SetPoint("BOTTOMRIGHT", -35, 45)

    -- Edit box for export text
    local editBox = CreateFrame("EditBox", "HooligansLootExportEditBox", scrollFrame)
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
    instructions:SetText("Press Ctrl+C to copy")
    instructions:SetTextColor(0.7, 0.7, 0.7)

    -- Make closable with Escape
    tinsert(UISpecialFrames, "HooligansLootExportFrame")

    exportFrame = frame
    return frame
end

function Export:RefreshExport()
    if not exportFrame or not exportFrame:IsShown() then return end

    -- Always use platform JSON format
    local exportString, err = self:ExportToJSON()

    if exportString then
        exportFrame.editBox:SetText(exportString)
        exportFrame.editBox:HighlightText()

        local session = HooligansLoot:GetModule("SessionManager"):GetCurrentSession()
        if session then
            exportFrame.sessionInfo:SetText(session.name .. " (" .. #session.items .. " items)")
        end
    else
        exportFrame.editBox:SetText("Error: " .. (err or "Unknown error"))
    end
end

function Export:ShowDialog(sessionId)
    local frame = self:CreateExportFrame()

    local SessionManager = HooligansLoot:GetModule("SessionManager")
    local session = sessionId and SessionManager:GetSession(sessionId) or SessionManager:GetCurrentSession()

    if not session then
        HooligansLoot:Print("No session to export. Create one with /hl session new")
        return
    end

    if #session.items == 0 then
        HooligansLoot:Print("Session has no items to export.")
        return
    end

    frame:Show()
    self:RefreshExport()
end

function Export:HideDialog()
    if exportFrame then
        exportFrame:Hide()
    end
end
