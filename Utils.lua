-- Utils.lua
-- Utility functions

local ADDON_NAME, NS = ...
local Utils = {}
NS.Utils = Utils

-- Parse item ID from item link
function Utils.GetItemID(itemLink)
    if not itemLink then return nil end
    local itemID = string.match(itemLink, "item:(%d+)")
    return itemID and tonumber(itemID) or nil
end

-- Parse item string from item link
function Utils.GetItemString(itemLink)
    if not itemLink then return nil end
    return string.match(itemLink, "(item:[%-?%d:]+)")
end

-- Generate a unique ID for an item instance
-- In Classic, we use itemLink + bag + slot + time as identifier
function Utils.GenerateItemGUID(itemLink, bagId, slotId)
    local itemString = Utils.GetItemString(itemLink) or "unknown"
    return string.format("%s:%d:%d:%d", itemString, bagId or 0, slotId or 0, time())
end

-- Get item quality color hex
function Utils.GetQualityColor(quality)
    local colors = {
        [0] = "9d9d9d", -- Poor (gray)
        [1] = "ffffff", -- Common (white)
        [2] = "1eff00", -- Uncommon (green)
        [3] = "0070dd", -- Rare (blue)
        [4] = "a335ee", -- Epic (purple)
        [5] = "ff8000", -- Legendary (orange)
    }
    return colors[quality] or "ffffff"
end

-- Get quality name
function Utils.GetQualityName(quality)
    local names = {
        [0] = "Poor",
        [1] = "Common",
        [2] = "Uncommon",
        [3] = "Rare",
        [4] = "Epic",
        [5] = "Legendary",
    }
    return names[quality] or "Unknown"
end

-- Format timestamp for display
function Utils.FormatTime(timestamp)
    return date("%Y-%m-%d %H:%M:%S", timestamp)
end

-- Format ISO 8601 timestamp for export
function Utils.FormatISO8601(timestamp)
    return date("!%Y-%m-%dT%H:%M:%SZ", timestamp)
end

-- Format remaining time (for trade timer)
function Utils.FormatTimeRemaining(seconds)
    if seconds <= 0 then
        return "|cffff0000Expired|r"
    elseif seconds < 60 then
        return string.format("|cffff0000%ds|r", seconds)
    elseif seconds < 300 then -- Less than 5 min
        return string.format("|cffffff00%dm %ds|r", math.floor(seconds / 60), seconds % 60)
    elseif seconds < 3600 then
        return string.format("|cff00ff00%dm|r", math.floor(seconds / 60))
    else
        return string.format("|cff00ff00%dh %dm|r", math.floor(seconds / 3600), math.floor((seconds % 3600) / 60))
    end
end

-- Get trade time remaining for an item
function Utils.GetTradeTimeRemaining(tradeExpires)
    if not tradeExpires then return 0 end
    return math.max(0, tradeExpires - time())
end

-- Check if player is Master Looter (or has equivalent permissions)
-- Note: GetLootMethod doesn't exist in Classic Anniversary - Master Loot was removed
-- Instead, we check if player is raid leader or assistant
function Utils.IsMasterLooter()
    -- If GetLootMethod exists (older Classic versions), use it
    if GetLootMethod then
        local lootMethod, masterLooterPartyID, masterLooterRaidID = GetLootMethod()
        if lootMethod == "master" then
            local playerName = UnitName("player")
            if masterLooterRaidID then
                local mlName = GetRaidRosterInfo(masterLooterRaidID)
                return mlName == playerName
            elseif masterLooterPartyID == 0 then
                return true -- Player is the ML
            end
        end
    end

    -- Fallback: Check if player is raid leader or assistant (for Classic Anniversary)
    if IsInRaid() then
        return UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
    elseif IsInGroup() then
        return UnitIsGroupLeader("player")
    end

    -- Solo - always allowed
    return true
end

-- Get raid/party members
function Utils.GetGroupMembers()
    local members = {}

    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local name, _, _, _, _, _, _, online = GetRaidRosterInfo(i)
            if name and online then
                table.insert(members, name)
            end
        end
    elseif IsInGroup() then
        table.insert(members, UnitName("player"))
        for i = 1, GetNumGroupMembers() - 1 do
            local name = UnitName("party" .. i)
            if name then
                table.insert(members, name)
            end
        end
    else
        table.insert(members, UnitName("player"))
    end

    return members
end

-- Strip realm name from player name
function Utils.StripRealm(name)
    if not name then return nil end
    return string.match(name, "([^%-]+)") or name
end

-- Simple JSON encoder (for export)
function Utils.ToJSON(tbl, indent)
    indent = indent or 0
    local spaces = string.rep("  ", indent)
    local result = {}

    if type(tbl) ~= "table" then
        if type(tbl) == "string" then
            -- Escape special characters
            local escaped = tbl:gsub('\\', '\\\\')
                              :gsub('"', '\\"')
                              :gsub('\n', '\\n')
                              :gsub('\r', '\\r')
                              :gsub('\t', '\\t')
            return '"' .. escaped .. '"'
        elseif type(tbl) == "boolean" then
            return tbl and "true" or "false"
        elseif tbl == nil then
            return "null"
        else
            return tostring(tbl)
        end
    end

    -- Check if array or object
    local isArray = false
    local maxIndex = 0
    for k, v in pairs(tbl) do
        if type(k) == "number" and k > 0 and math.floor(k) == k then
            maxIndex = math.max(maxIndex, k)
        end
    end
    isArray = maxIndex > 0 and maxIndex == #tbl

    local bracket = isArray and "[" or "{"
    local closeBracket = isArray and "]" or "}"

    table.insert(result, bracket)

    local first = true
    if isArray then
        for i = 1, #tbl do
            if not first then table.insert(result, ",") end
            first = false
            table.insert(result, "\n" .. spaces .. "  " .. Utils.ToJSON(tbl[i], indent + 1))
        end
    else
        -- Sort keys for consistent output
        local keys = {}
        for k in pairs(tbl) do
            table.insert(keys, k)
        end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)

        for _, k in ipairs(keys) do
            if not first then table.insert(result, ",") end
            first = false
            table.insert(result, "\n" .. spaces .. '  "' .. tostring(k) .. '": ' .. Utils.ToJSON(tbl[k], indent + 1))
        end
    end

    if not first then
        table.insert(result, "\n" .. spaces)
    end
    table.insert(result, closeBracket)

    return table.concat(result)
end

-- Simple JSON decoder (for import)
function Utils.FromJSON(str)
    if not str or str == "" then return nil end

    -- Remove leading/trailing whitespace
    str = str:gsub("^%s+", ""):gsub("%s+$", "")

    local pos = 1
    local len = #str

    local function skipWhitespace()
        while pos <= len and str:sub(pos, pos):match("%s") do
            pos = pos + 1
        end
    end

    local function parseValue()
        skipWhitespace()
        if pos > len then return nil end

        local char = str:sub(pos, pos)

        if char == '"' then
            -- String
            pos = pos + 1
            local startPos = pos
            local result = {}
            while pos <= len do
                local c = str:sub(pos, pos)
                if c == '"' then
                    pos = pos + 1
                    return table.concat(result)
                elseif c == '\\' and pos < len then
                    pos = pos + 1
                    local escaped = str:sub(pos, pos)
                    if escaped == 'n' then
                        table.insert(result, '\n')
                    elseif escaped == 'r' then
                        table.insert(result, '\r')
                    elseif escaped == 't' then
                        table.insert(result, '\t')
                    elseif escaped == '"' then
                        table.insert(result, '"')
                    elseif escaped == '\\' then
                        table.insert(result, '\\')
                    else
                        table.insert(result, escaped)
                    end
                else
                    table.insert(result, c)
                end
                pos = pos + 1
            end
            return nil -- Unterminated string

        elseif char == "{" then
            -- Object
            pos = pos + 1
            local obj = {}
            skipWhitespace()
            if str:sub(pos, pos) == "}" then
                pos = pos + 1
                return obj
            end
            while true do
                skipWhitespace()
                if str:sub(pos, pos) == "}" then
                    pos = pos + 1
                    return obj
                end
                if str:sub(pos, pos) == "," then
                    pos = pos + 1
                    skipWhitespace()
                end

                -- Parse key
                local key = parseValue()
                if not key then return nil end

                skipWhitespace()
                if str:sub(pos, pos) ~= ":" then return nil end
                pos = pos + 1

                -- Parse value
                local value = parseValue()
                obj[key] = value

                skipWhitespace()
                local next = str:sub(pos, pos)
                if next == "}" then
                    pos = pos + 1
                    return obj
                elseif next ~= "," then
                    return nil
                end
            end

        elseif char == "[" then
            -- Array
            pos = pos + 1
            local arr = {}
            skipWhitespace()
            if str:sub(pos, pos) == "]" then
                pos = pos + 1
                return arr
            end
            while true do
                skipWhitespace()
                if str:sub(pos, pos) == "]" then
                    pos = pos + 1
                    return arr
                end
                if str:sub(pos, pos) == "," then
                    pos = pos + 1
                end
                local value = parseValue()
                table.insert(arr, value)

                skipWhitespace()
                local next = str:sub(pos, pos)
                if next == "]" then
                    pos = pos + 1
                    return arr
                elseif next ~= "," then
                    return nil
                end
            end

        elseif char:match("[%d%-]") then
            -- Number
            local startPos = pos
            if str:sub(pos, pos) == "-" then pos = pos + 1 end
            while pos <= len and str:sub(pos, pos):match("[%d%.eE%+%-]") do
                pos = pos + 1
            end
            return tonumber(str:sub(startPos, pos - 1))

        elseif str:sub(pos, pos + 3) == "true" then
            pos = pos + 4
            return true

        elseif str:sub(pos, pos + 4) == "false" then
            pos = pos + 5
            return false

        elseif str:sub(pos, pos + 3) == "null" then
            pos = pos + 4
            return nil
        end

        return nil
    end

    local success, result = pcall(parseValue)
    return success and result or nil
end

-- Convert table to CSV
function Utils.ToCSV(headers, rows)
    local lines = {}
    table.insert(lines, table.concat(headers, ","))

    for _, row in ipairs(rows) do
        local values = {}
        for _, header in ipairs(headers) do
            local val = row[header]
            if val == nil then
                val = ""
            elseif type(val) == "string" then
                -- Escape commas, quotes, and newlines
                if val:find(",") or val:find('"') or val:find("\n") then
                    val = '"' .. val:gsub('"', '""') .. '"'
                end
            else
                val = tostring(val)
            end
            table.insert(values, val)
        end
        table.insert(lines, table.concat(values, ","))
    end

    return table.concat(lines, "\n")
end

-- Parse CSV to table
function Utils.FromCSV(str)
    if not str or str == "" then return nil end

    local lines = {}
    for line in str:gmatch("[^\r\n]+") do
        table.insert(lines, line)
    end

    if #lines < 1 then return nil end

    -- Parse headers
    local headers = {}
    for header in lines[1]:gmatch("([^,]+)") do
        table.insert(headers, header:match("^%s*(.-)%s*$")) -- Trim
    end

    -- Parse rows
    local rows = {}
    for i = 2, #lines do
        local row = {}
        local col = 1
        local line = lines[i]

        -- Simple CSV parsing (doesn't handle all edge cases)
        for value in line:gmatch("([^,]*)") do
            if col <= #headers then
                local trimmed = value:match("^%s*(.-)%s*$")
                -- Try to convert to number
                local num = tonumber(trimmed)
                row[headers[col]] = num or trimmed
                col = col + 1
            end
        end
        if col > 1 then
            table.insert(rows, row)
        end
    end

    return rows
end

-- Deep copy a table
function Utils.DeepCopy(orig)
    local copy
    if type(orig) == "table" then
        copy = {}
        for k, v in pairs(orig) do
            copy[Utils.DeepCopy(k)] = Utils.DeepCopy(v)
        end
        setmetatable(copy, Utils.DeepCopy(getmetatable(orig)))
    else
        copy = orig
    end
    return copy
end

-- Table contains value
function Utils.Contains(tbl, value)
    for _, v in pairs(tbl) do
        if v == value then
            return true
        end
    end
    return false
end

-- Get table size (for non-array tables)
function Utils.TableSize(tbl)
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

-- Strip color codes from text
function Utils.StripColor(text)
    if not text then return "" end
    return text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h", ""):gsub("|h", "")
end

-- Get clean item name from link
function Utils.GetItemName(itemLink)
    if not itemLink then return "Unknown" end
    local name = itemLink:match("%[(.-)%]")
    return name or "Unknown"
end

-- Wildcard pattern matching
-- Supports * (any characters) and ? (single character)
function Utils.MatchesWildcard(text, pattern)
    if not text or not pattern then return false end

    -- Convert wildcard pattern to Lua pattern
    -- * matches any characters
    -- ? matches single character
    local luaPattern = pattern
        :gsub("([%.%+%-%^%$%(%)%%])", "%%%1") -- Escape special chars
        :gsub("%*", ".*")  -- * -> .*
        :gsub("%?", ".")   -- ? -> .

    -- Case insensitive match
    return string.lower(text):match("^" .. string.lower(luaPattern) .. "$") ~= nil
end

-- Check if player is online and in our group
function Utils.IsPlayerInGroup(playerName)
    if not playerName then return false end

    playerName = Utils.StripRealm(playerName):lower()

    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local name, _, _, _, _, _, _, online = GetRaidRosterInfo(i)
            if name and Utils.StripRealm(name):lower() == playerName and online then
                return true
            end
        end
    elseif IsInGroup() then
        if UnitName("player"):lower() == playerName then
            return true
        end
        for i = 1, GetNumGroupMembers() - 1 do
            local name = UnitName("party" .. i)
            if name and Utils.StripRealm(name):lower() == playerName then
                return true
            end
        end
    else
        return UnitName("player"):lower() == playerName
    end

    return false
end

-- Parse a comma-separated list of player names
function Utils.ParsePlayerList(listString)
    if not listString then return {} end

    local players = {}
    for player in listString:gmatch("([^,]+)") do
        player = player:match("^%s*(.-)%s*$") -- Trim whitespace
        if player and player ~= "" then
            table.insert(players, player)
        end
    end
    return players
end

-- Get addon version safely (handles different WoW API versions)
function Utils.GetAddonVersion()
    local version = "?"
    -- Try C_AddOns.GetAddOnMetadata first (newer API)
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        local success, result = pcall(C_AddOns.GetAddOnMetadata, "HooligansLoot", "Version")
        if success and result then
            version = result
        end
    -- Fall back to GetAddOnMetadata (Classic API)
    elseif GetAddOnMetadata then
        local success, result = pcall(GetAddOnMetadata, "HooligansLoot", "Version")
        if success and result then
            version = result
        end
    end
    return version
end

-- Class colors (using WoW's RAID_CLASS_COLORS format)
Utils.ClassColors = {
    WARRIOR = { r = 0.78, g = 0.61, b = 0.43, hex = "C79C6E" },
    PALADIN = { r = 0.96, g = 0.55, b = 0.73, hex = "F58CBA" },
    HUNTER = { r = 0.67, g = 0.83, b = 0.45, hex = "ABD473" },
    ROGUE = { r = 1.00, g = 0.96, b = 0.41, hex = "FFF569" },
    PRIEST = { r = 1.00, g = 1.00, b = 1.00, hex = "FFFFFF" },
    SHAMAN = { r = 0.00, g = 0.44, b = 0.87, hex = "0070DE" },
    MAGE = { r = 0.41, g = 0.80, b = 0.94, hex = "69CCF0" },
    WARLOCK = { r = 0.58, g = 0.51, b = 0.79, hex = "9482C9" },
    DRUID = { r = 1.00, g = 0.49, b = 0.04, hex = "FF7D0A" },
    DEATHKNIGHT = { r = 0.77, g = 0.12, b = 0.23, hex = "C41F3B" },
    -- Default for unknown class
    UNKNOWN = { r = 0.6, g = 0.6, b = 0.6, hex = "999999" },
}

-- Get class for a player name from current group
function Utils.GetPlayerClass(playerName)
    if not playerName then return nil end

    playerName = Utils.StripRealm(playerName)

    -- Check if it's the player
    local myName = UnitName("player")
    if playerName == myName then
        local _, classFile = UnitClass("player")
        return classFile
    end

    -- Check raid roster
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local name, _, _, _, _, classFile = GetRaidRosterInfo(i)
            if name then
                local cleanName = Utils.StripRealm(name)
                if cleanName == playerName then
                    return classFile
                end
            end
        end
    elseif IsInGroup() then
        -- Check party members
        for i = 1, GetNumGroupMembers() - 1 do
            local unit = "party" .. i
            local name = UnitName(unit)
            if name and Utils.StripRealm(name) == playerName then
                local _, classFile = UnitClass(unit)
                return classFile
            end
        end
    end

    return nil
end

-- Get class color for a player (returns color table)
function Utils.GetClassColor(classFile)
    if classFile and Utils.ClassColors[classFile] then
        return Utils.ClassColors[classFile]
    end
    return Utils.ClassColors.UNKNOWN
end

-- Get class color hex string
function Utils.GetClassColorHex(classFile)
    local color = Utils.GetClassColor(classFile)
    return color.hex
end

-- Get class-colored player name
function Utils.GetColoredPlayerName(playerName, classFile)
    if not playerName then return "Unknown" end

    -- If classFile not provided, try to look it up
    if not classFile then
        classFile = Utils.GetPlayerClass(playerName)
    end

    local color = Utils.GetClassColor(classFile)
    return string.format("|cff%s%s|r", color.hex, playerName)
end

-- Get all group members with their classes
function Utils.GetGroupMembersWithClass()
    local members = {}

    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local name, _, _, _, _, classFile, _, online = GetRaidRosterInfo(i)
            if name then
                members[Utils.StripRealm(name)] = classFile
            end
        end
    elseif IsInGroup() then
        -- Player
        local _, playerClass = UnitClass("player")
        members[UnitName("player")] = playerClass

        -- Party members
        for i = 1, GetNumGroupMembers() - 1 do
            local unit = "party" .. i
            local name = UnitName(unit)
            if name then
                local _, classFile = UnitClass(unit)
                members[Utils.StripRealm(name)] = classFile
            end
        end
    else
        local _, playerClass = UnitClass("player")
        members[UnitName("player")] = playerClass
    end

    return members
end
