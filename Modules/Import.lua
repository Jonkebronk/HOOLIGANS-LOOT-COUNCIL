-- Modules/Import.lua
-- Import award decisions from external source

local ADDON_NAME, NS = ...
local HooligansLoot = NS.addon
local Utils = NS.Utils

local Import = HooligansLoot:NewModule("Import")

-- Import dialog frame
local importFrame = nil

function Import:OnEnable()
    -- Nothing to do on enable
end

function Import:ParseJSON(str)
    local data = Utils.FromJSON(str)
    if not data then
        return nil, "Invalid JSON format"
    end

    local awards = {}

    -- Format 1: HooligansLoot export { "items": [{"id": 123, "winner": "Name"}, ...] }
    if data.items and type(data.items) == "table" then
        for _, item in ipairs(data.items) do
            if item.id and item.winner then
                table.insert(awards, {
                    itemId = tonumber(item.id),
                    winner = tostring(item.winner),
                    itemLink = item.link,
                    boss = item.boss,
                })
            end
        end
    -- Format 2: Simple awards array { "awards": [{"itemId": 123, "winner": "Name"}, ...] }
    elseif data.awards and type(data.awards) == "table" then
        for _, award in ipairs(data.awards) do
            if award.itemId and award.winner then
                table.insert(awards, {
                    itemId = tonumber(award.itemId),
                    winner = tostring(award.winner),
                })
            end
        end
    else
        return nil, "JSON must contain 'items' or 'awards' array"
    end

    if #awards == 0 then
        return nil, "No awarded items found in JSON"
    end

    return awards, nil
end

-- Helper function to split CSV line properly (handles empty fields and quoted values)
function Import:SplitCSVLine(line)
    local fields = {}
    local field = ""
    local inQuotes = false
    local i = 1
    local len = #line

    while i <= len do
        local c = line:sub(i, i)

        if c == '"' then
            -- Check for escaped quote ""
            if inQuotes and i < len and line:sub(i + 1, i + 1) == '"' then
                field = field .. '"'
                i = i + 1
            else
                inQuotes = not inQuotes
            end
        elseif c == ',' and not inQuotes then
            -- End of field
            table.insert(fields, field)
            field = ""
        else
            field = field .. c
        end

        i = i + 1
    end

    -- Don't forget the last field
    table.insert(fields, field)

    return fields
end

function Import:ParseCSV(str)
    local lines = {}
    for line in str:gmatch("[^\r\n]+") do
        -- Skip empty lines
        if line and line:match("%S") then
            table.insert(lines, line)
        end
    end

    if #lines < 2 then
        return nil, "CSV must have header and at least one data row"
    end

    -- Parse header using proper CSV splitting
    local headers = self:SplitCSVLine(lines[1])

    -- Clean up headers
    for i, h in ipairs(headers) do
        local cleaned = h:match("^%s*(.-)%s*$") or "" -- Trim whitespace
        cleaned = cleaned:gsub('^"', ''):gsub('"$', '') -- Remove quotes
        headers[i] = cleaned
    end

    HooligansLoot:Debug("CSV Headers (" .. #headers .. "): " .. table.concat(headers, " | "))

    -- Find column indices for the fields we need (case-insensitive)
    local playerCol, itemIdCol, itemCol, bossCol, instanceCol = nil, nil, nil, nil, nil
    for i, h in ipairs(headers) do
        local lower = h:lower()
        if lower == "player" or lower == "winner" then
            playerCol = i
        elseif lower == "itemid" then
            itemIdCol = i
        elseif lower == "item" then
            itemCol = i
        elseif lower == "boss" then
            bossCol = i
        elseif lower == "instance" then
            instanceCol = i
        end
    end

    HooligansLoot:Debug(string.format("Columns - player:%s itemId:%s item:%s boss:%s instance:%s",
        tostring(playerCol), tostring(itemIdCol), tostring(itemCol), tostring(bossCol), tostring(instanceCol)))

    if not playerCol then
        return nil, "Missing 'player' column in CSV header"
    end

    if not itemIdCol and not itemCol then
        return nil, "Missing 'itemID' or 'item' column in CSV header"
    end

    -- Parse data rows
    local awards = {}
    for i = 2, #lines do
        local line = lines[i]
        local fields = self:SplitCSVLine(line)

        -- Extract values safely
        local player = playerCol and fields[playerCol] or nil
        local itemId = itemIdCol and fields[itemIdCol] or nil
        local itemLink = itemCol and fields[itemCol] or nil
        local boss = bossCol and fields[bossCol] or nil
        local instance = instanceCol and fields[instanceCol] or nil

        -- Clean up player name
        if player then
            player = player:match("^%s*(.-)%s*$") -- Trim
            player = player:gsub('^"', ''):gsub('"$', '') -- Remove quotes
        end

        -- Try to get itemId from itemLink if itemId column is empty
        if (not itemId or itemId == "") and itemLink then
            itemId = itemLink:match("item:(%d+)")
        end

        -- Parse itemId - handle both numeric and string formats
        if itemId then
            local numId = tonumber(itemId)
            if not numId then
                -- Try extracting from item link format
                numId = tonumber(itemId:match("item:(%d+)"))
            end
            itemId = numId
        end

        -- Debug each row
        HooligansLoot:Debug(string.format("Row %d: player=%s itemId=%s",
            i, tostring(player), tostring(itemId)))

        if player and player ~= "" and itemId then
            table.insert(awards, {
                itemId = itemId,
                winner = player,
                itemLink = itemLink,
                boss = boss,
                instance = instance,
            })
        end
    end

    if #awards == 0 then
        return nil, "No valid awards found (check player and itemID columns)"
    end

    return awards, nil
end

function Import:DetectFormat(str)
    str = str:gsub("^%s+", "") -- Trim leading whitespace
    if str:sub(1, 1) == "{" or str:sub(1, 1) == "[" then
        return "json"
    else
        return "csv"
    end
end

function Import:ParseImportData(str)
    if not str or str == "" then
        return nil, "No data provided"
    end

    local format = self:DetectFormat(str)

    if format == "json" then
        return self:ParseJSON(str)
    else
        return self:ParseCSV(str)
    end
end

function Import:ValidateAwards(awards, session, createItems)
    local results = {
        valid = {},
        invalid = {},
        matched = 0,
        unmatched = 0,
        created = 0,
    }

    for _, award in ipairs(awards) do
        -- Find matching items in session
        local matchedItems = HooligansLoot:GetModule("SessionManager"):GetItemsByItemID(session.id, award.itemId)

        if #matchedItems > 0 then
            -- Find first unassigned item with this ID
            local targetItem = nil
            for _, item in ipairs(matchedItems) do
                if not session.awards[item.guid] then
                    targetItem = item
                    break
                end
            end

            if targetItem then
                table.insert(results.valid, {
                    itemId = award.itemId,
                    itemGUID = targetItem.guid,
                    itemName = targetItem.name,
                    itemLink = targetItem.link,
                    winner = award.winner,
                })
                results.matched = results.matched + 1
            else
                -- All items with this ID already have awards
                table.insert(results.invalid, {
                    itemId = award.itemId,
                    winner = award.winner,
                    reason = "All items with this ID already assigned",
                })
                results.unmatched = results.unmatched + 1
            end
        elseif createItems then
            -- Create the item in the session
            local newItem = self:CreateItemFromAward(award, session)
            if newItem then
                table.insert(results.valid, {
                    itemId = award.itemId,
                    itemGUID = newItem.guid,
                    itemName = newItem.name,
                    itemLink = newItem.link or award.itemLink,
                    winner = award.winner,
                    created = true,
                })
                results.matched = results.matched + 1
                results.created = results.created + 1
            else
                table.insert(results.invalid, {
                    itemId = award.itemId,
                    winner = award.winner,
                    reason = "Could not create item",
                })
                results.unmatched = results.unmatched + 1
            end
        else
            table.insert(results.invalid, {
                itemId = award.itemId,
                winner = award.winner,
                reason = "Item not found in session",
            })
            results.unmatched = results.unmatched + 1
        end
    end

    return results
end

function Import:CreateItemFromAward(award, session)
    -- Create a new item entry from import data
    local itemId = award.itemId
    local itemLink = award.itemLink
    local itemName, _, itemQuality, _, _, _, _, _, _, itemTexture

    -- Try to get item info
    if itemLink then
        itemName, _, itemQuality, _, _, _, _, _, _, itemTexture = GetItemInfo(itemLink)
    end
    if not itemName then
        itemName, _, itemQuality, _, _, _, _, _, _, itemTexture = GetItemInfo(itemId)
    end

    -- Fallback values
    itemName = itemName or ("Item " .. itemId)
    itemQuality = itemQuality or 4
    itemTexture = itemTexture or "Interface\\Icons\\INV_Misc_QuestionMark"

    local newItem = {
        guid = "import:" .. itemId .. ":" .. time() .. ":" .. math.random(10000),
        id = itemId,
        link = itemLink or ("|cffa335ee|Hitem:" .. itemId .. "::::::::70:::::|h[" .. itemName .. "]|h|r"),
        name = itemName,
        quality = itemQuality,
        icon = itemTexture,
        boss = award.boss or award.instance or "Imported",
        timestamp = time(),
        bagId = -1, -- Not in bags (imported)
        slotId = -1,
        tradeable = false, -- Imported items are already traded
        tradeExpires = 0,
        imported = true,
    }

    -- Request item info if icon is missing (will update via callback)
    if itemTexture == "Interface\\Icons\\INV_Misc_QuestionMark" then
        local LootTracker = HooligansLoot:GetModule("LootTracker", true)
        if LootTracker then
            LootTracker:RequestItemInfo(itemId)
        end
    end

    table.insert(session.items, newItem)
    HooligansLoot:Debug("Created item from import: " .. newItem.name)

    return newItem
end

function Import:ApplyAwards(validAwards, sessionId)
    local SessionManager = HooligansLoot:GetModule("SessionManager")
    local applied = 0

    for _, award in ipairs(validAwards) do
        if SessionManager:SetAward(sessionId, award.itemGUID, award.winner) then
            -- If this was imported as already traded, mark it as awarded
            if award.created then
                SessionManager:MarkAwarded(sessionId, award.itemGUID)
            end
            applied = applied + 1
        end
    end

    return applied
end

function Import:ImportAwards(str, sessionId, createItems)
    local SessionManager = HooligansLoot:GetModule("SessionManager")
    local session = sessionId and SessionManager:GetSession(sessionId) or SessionManager:GetCurrentSession()

    if not session then
        return nil, "No session available"
    end

    -- Parse the import data
    local awards, parseErr = self:ParseImportData(str)
    if not awards then
        return nil, parseErr
    end

    -- Validate against session (with option to create items)
    local validation = self:ValidateAwards(awards, session, createItems)

    -- Apply valid awards
    local applied = self:ApplyAwards(validation.valid, session.id)

    return {
        applied = applied,
        total = #awards,
        matched = validation.matched,
        unmatched = validation.unmatched,
        created = validation.created,
        invalid = validation.invalid,
        valid = validation.valid,
    }, nil
end

function Import:CreateImportFrame()
    if importFrame then return importFrame end

    -- Create main frame (matching Export style)
    local frame = CreateFrame("Frame", "HooligansLootImportFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(500, 400)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("DIALOG")
    frame:Hide()

    -- Title
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    frame.title:SetPoint("TOP", 0, -5)
    frame.title:SetText(HooligansLoot.colors.primary .. "HOOLIGANS|r Loot - Import")

    -- Format label
    local formatLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    formatLabel:SetPoint("TOPLEFT", 15, -35)
    formatLabel:SetText("Format: CSV (RCLootCouncil)")

    -- Session info (right side, matching Export)
    frame.sessionInfo = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.sessionInfo:SetPoint("TOPRIGHT", -15, -35)
    frame.sessionInfo:SetJustifyH("RIGHT")

    -- Scroll frame for import text
    local scrollFrame = CreateFrame("ScrollFrame", "HooligansLootImportScroll", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 15, -65)
    scrollFrame:SetPoint("BOTTOMRIGHT", -35, 75)

    -- Edit box for import text
    local editBox = CreateFrame("EditBox", "HooligansLootImportEditBox", scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetFontObject("ChatFontNormal")
    editBox:SetWidth(scrollFrame:GetWidth())
    editBox:SetAutoFocus(false)
    editBox:EnableMouse(true)
    editBox:SetScript("OnEscapePressed", function() editBox:ClearFocus() end)
    editBox:SetScript("OnTextChanged", function(self)
        Import:OnTextChanged()
    end)

    scrollFrame:SetScrollChild(editBox)
    frame.editBox = editBox

    -- Create items checkbox
    local createCheck = CreateFrame("CheckButton", "HooligansLootImportCreateCheck", frame, "UICheckButtonTemplate")
    createCheck:SetPoint("BOTTOMLEFT", 10, 48)
    createCheck:SetChecked(true)
    createCheck:SetSize(24, 24)
    frame.createCheck = createCheck

    local createLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    createLabel:SetPoint("LEFT", createCheck, "RIGHT", 2, 0)
    createLabel:SetText("Create items if not in session")

    -- Status text
    frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.status:SetPoint("BOTTOMLEFT", 15, 28)
    frame.status:SetWidth(350)
    frame.status:SetJustifyH("LEFT")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    closeBtn:SetSize(80, 22)
    closeBtn:SetPoint("BOTTOMRIGHT", -10, 10)
    closeBtn:SetText("Close")
    closeBtn:SetScript("OnClick", function() frame:Hide() end)

    -- Import button
    local importBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    importBtn:SetSize(80, 22)
    importBtn:SetPoint("RIGHT", closeBtn, "LEFT", -5, 0)
    importBtn:SetText("Import")
    importBtn:SetScript("OnClick", function()
        Import:DoImport()
    end)
    frame.importBtn = importBtn

    -- Clear button
    local clearBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clearBtn:SetSize(80, 22)
    clearBtn:SetPoint("RIGHT", importBtn, "LEFT", -5, 0)
    clearBtn:SetText("Clear")
    clearBtn:SetScript("OnClick", function()
        editBox:SetText("")
        frame.status:SetText("")
    end)

    importFrame = frame
    return frame
end

function Import:OnTextChanged()
    if not importFrame then return end

    local text = importFrame.editBox:GetText()
    local hasText = text and text ~= ""

    -- Update status based on parse result
    if hasText then
        local awards, parseErr = self:ParseImportData(text)
        if awards then
            importFrame.status:SetText("|cff88ff88Found " .. #awards .. " award(s)|r")
            importFrame.importBtn:Enable()
        else
            importFrame.status:SetText("|cffff4444" .. (parseErr or "Parse error") .. "|r")
            importFrame.importBtn:Disable()
        end
    else
        importFrame.status:SetText("")
        importFrame.importBtn:Disable()
    end
end

function Import:DoValidate()
    -- Validation now happens automatically in OnTextChanged/UpdatePreview
    -- This function kept for backwards compatibility
    if not importFrame then return end
    self:OnTextChanged()
end

function Import:DoImport()
    if not importFrame then return end

    local text = importFrame.editBox:GetText()
    if not text or text == "" then
        importFrame.status:SetText("|cffff4444No data to import|r")
        return
    end

    local createItems = importFrame.createCheck:GetChecked()
    local result, err = self:ImportAwards(text, nil, createItems)

    if not result then
        importFrame.status:SetText("|cffff4444Error: " .. err .. "|r")
        return
    end

    -- Show success/failure status
    if result.applied > 0 then
        local statusText = "|cff00ff00Success!|r "
        statusText = statusText .. string.format("Imported %d/%d awards", result.applied, result.total)

        if result.created > 0 then
            statusText = statusText .. string.format(" |cff88ccff(%d new)|r", result.created)
        end

        importFrame.status:SetText(statusText)

        -- Print details to chat
        HooligansLoot:Print("|cff00ff00Import successful!|r")
        for _, v in ipairs(result.valid) do
            local created = v.created and " |cff88ccff[new]|r" or ""
            print(string.format("  %s -> |cff00ff00%s|r%s", v.itemLink or v.itemName, v.winner, created))
        end

        -- Refresh UI via callback
        HooligansLoot.callbacks:Fire("AWARDS_IMPORTED", result)

        -- Also directly refresh MainFrame to ensure "Awarded To" column updates
        local MainFrame = HooligansLoot:GetModule("MainFrame", true)
        if MainFrame and MainFrame.Refresh then
            MainFrame:Refresh()
        end

        -- Clear the input after successful import
        C_Timer.After(1.5, function()
            if importFrame and importFrame:IsShown() then
                importFrame.editBox:SetText("")
                importFrame.importBtn:Disable()
                importFrame.status:SetText("|cff00ff00Import complete!|r")

                -- Update session info
                local session = HooligansLoot:GetModule("SessionManager"):GetCurrentSession()
                if session then
                    importFrame.sessionInfo:SetText(session.name .. " (" .. #session.items .. " items)")
                end
            end
        end)
    else
        importFrame.status:SetText("|cffffcc00No awards could be imported|r")
    end

    if #result.invalid > 0 then
        HooligansLoot:Print("|cffffcc00" .. #result.invalid .. " award(s) skipped:|r")
        for _, v in ipairs(result.invalid) do
            print(string.format("  Item %s: %s", v.itemId or "?", v.reason))
        end
    end
end

function Import:ShowDialog(sessionId)
    local frame = self:CreateImportFrame()

    local SessionManager = HooligansLoot:GetModule("SessionManager")
    local session = sessionId and SessionManager:GetSession(sessionId) or SessionManager:GetCurrentSession()

    if not session then
        HooligansLoot:Print("|cffffcc00No session available.|r Create one with |cff88ccff/hl session new|r")
        return
    end

    -- Update session info (matching Export style)
    local itemCount = #session.items
    local awardCount = 0
    for _ in pairs(session.awards or {}) do
        awardCount = awardCount + 1
    end

    frame.sessionInfo:SetText(session.name .. " (" .. itemCount .. " items)")

    -- Reset state
    frame.status:SetText("")
    frame.editBox:SetText("")
    frame.importBtn:Disable()

    frame:Show()
    frame.editBox:SetFocus()
end

function Import:HideDialog()
    if importFrame then
        importFrame:Hide()
    end
end
