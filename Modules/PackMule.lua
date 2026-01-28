-- Modules/PackMule.lua
-- Auto-loot distribution system for HooligansLoot

local ADDON_NAME, NS = ...
local HooligansLoot = NS.addon
local Utils = NS.Utils

local PackMule = HooligansLoot:NewModule("PackMule", "AceEvent-3.0")

-- Default settings
local defaults = {
    enabled = false,
    enabledForMasterLoot = false,
    enabledForGroupLoot = false,
    needWithoutAssist = false,
    autoDisableOnLeave = true,
    autoConfirmSolo = false,
    autoConfirmGroup = false,
    lootGold = true,
    shiftBypass = true,
    disenchanter = nil,
    roundRobinIndex = 0,
    roundRobinList = {},
    rules = {},
    ignoredItems = {},
}

-- Quality constants
local QUALITY_POOR = 0
local QUALITY_COMMON = 1
local QUALITY_UNCOMMON = 2
local QUALITY_RARE = 3
local QUALITY_EPIC = 4
local QUALITY_LEGENDARY = 5

-- Special target keywords
local SPECIAL_TARGETS = {
    SELF = true,
    DE = true,
    RR = true,
    RANDOM = true,
    IGNORE = true,
}

-- Items to always ignore (quest items, special items, etc.)
local DEFAULT_IGNORED_CLASSES = {
    [12] = true, -- Quest items (itemClassID)
}

-- Scanning tooltip
local scanTooltip = nil

-- Create event frame for reliable event registration
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("LOOT_OPENED")
eventFrame:RegisterEvent("LOOT_CLOSED")
eventFrame:RegisterEvent("GROUP_LEFT")
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "LOOT_OPENED" then
        PackMule:LOOT_OPENED(event, ...)
    elseif event == "LOOT_CLOSED" then
        PackMule:LOOT_CLOSED(event, ...)
    elseif event == "GROUP_LEFT" then
        PackMule:GROUP_LEFT(event, ...)
    end
end)

function PackMule:OnInitialize()
    -- Initialize settings in database if not present
    if not HooligansLoot.db.profile.packMule then
        HooligansLoot.db.profile.packMule = Utils.DeepCopy(defaults)
    end

    -- Ensure all default keys exist (for upgrades)
    for key, value in pairs(defaults) do
        if HooligansLoot.db.profile.packMule[key] == nil then
            HooligansLoot.db.profile.packMule[key] = value
        end
    end

    HooligansLoot:Debug("PackMule module initialized")
end

function PackMule:OnEnable()
    HooligansLoot:Debug("PackMule module enabled")
end

function PackMule:OnDisable()
    self:UnregisterAllEvents()
end

function PackMule:GetSettings()
    return HooligansLoot.db.profile.packMule
end

-- ============================================================================
-- Event Handlers
-- ============================================================================

function PackMule:LOOT_OPENED(event, autoLoot)
    HooligansLoot:Debug("PackMule: LOOT_OPENED fired!")

    local settings = self:GetSettings()
    if not settings then
        HooligansLoot:Debug("PackMule: No settings found!")
        return
    end

    -- Check if enabled
    if not settings.enabled then
        HooligansLoot:Debug("PackMule: Not enabled (settings.enabled = false)")
        return
    end

    -- Check shift bypass
    if settings.shiftBypass and IsShiftKeyDown() then
        HooligansLoot:Debug("PackMule: Shift bypass active, skipping auto-loot")
        return
    end

    -- Determine loot method
    local lootMethod = self:GetCurrentLootMethod()
    HooligansLoot:Debug("PackMule: Loot method = " .. tostring(lootMethod))

    -- Check if we should process based on loot method
    -- Process if EITHER master or group loot mode is enabled (more flexible)
    local shouldProcess = false
    if lootMethod == "master" and settings.enabledForMasterLoot then
        shouldProcess = true
    elseif lootMethod == "group" and settings.enabledForGroupLoot then
        shouldProcess = true
    elseif lootMethod == "solo" or lootMethod == "ffa" then
        -- Solo/FFA always allowed if main toggle is on
        shouldProcess = true
    elseif settings.enabledForMasterLoot or settings.enabledForGroupLoot then
        -- Fallback: if either mode is enabled, process anyway (handles detection issues)
        HooligansLoot:Debug("PackMule: Loot method detection unclear, but a mode is enabled - processing")
        shouldProcess = true
    end

    if not shouldProcess then
        HooligansLoot:Debug("PackMule: No loot mode enabled for method: " .. tostring(lootMethod))
        return
    end

    HooligansLoot:Debug("PackMule: All checks passed, processing loot window")
    -- Process loot window
    self:ProcessLootWindow()
end

function PackMule:LOOT_CLOSED()
    -- Cleanup if needed
end

function PackMule:GROUP_LEFT()
    local settings = self:GetSettings()

    if settings.autoDisableOnLeave then
        settings.enabledForGroupLoot = false
        HooligansLoot:Print("PackMule: Group loot auto-disabled on leaving group")
    end
end

-- ============================================================================
-- Loot Processing
-- ============================================================================

function PackMule:GetCurrentLootMethod()
    -- Check if GetLootMethod exists (older Classic versions)
    if GetLootMethod then
        local lootMethod = GetLootMethod()
        if lootMethod == "master" then
            return "master"
        elseif lootMethod == "group" or lootMethod == "needbeforegreed" then
            return "group"
        elseif lootMethod == "freeforall" then
            return "ffa"
        end
    end

    -- Default fallback
    if IsInRaid() then
        return "group"
    elseif IsInGroup() then
        return "group"
    else
        return "solo"
    end
end

function PackMule:ProcessLootWindow()
    local settings = self:GetSettings()
    local numItems = GetNumLootItems()

    HooligansLoot:Debug("PackMule: Processing " .. numItems .. " loot items")

    -- Process slots immediately (no delay) to avoid timing issues
    for slot = 1, numItems do
        self:ProcessLootSlot(slot)
    end

    -- Loot gold if enabled
    if settings.lootGold then
        self:LootGold()
    end
end

function PackMule:ProcessLootSlot(slot)
    local settings = self:GetSettings()

    -- Get slot info
    local slotType = GetLootSlotType(slot)

    -- Skip gold/currency
    if slotType == LOOT_SLOT_CURRENCY or slotType == LOOT_SLOT_MONEY then
        return
    end

    local lootIcon, lootName, lootQuantity, currencyID, lootQuality, locked, isQuestItem = GetLootSlotInfo(slot)
    local itemLink = GetLootSlotLink(slot)

    if not itemLink then
        HooligansLoot:Debug("PackMule: No item link for slot " .. slot)
        return
    end

    local itemID = Utils.GetItemID(itemLink)

    -- Check if item should be ignored
    if self:IsItemIgnored(itemID, lootName, itemLink) then
        HooligansLoot:Debug("PackMule: Ignoring item: " .. (lootName or "unknown"))
        return
    end

    -- Find matching rule
    local rule = self:FindMatchingRule(itemID, lootName, lootQuality, itemLink)

    if not rule then
        HooligansLoot:Debug("PackMule: No matching rule for: " .. (lootName or "unknown"))
        return
    end

    -- Get target player
    local target = self:GetTargetPlayer(rule, itemLink)

    if not target then
        HooligansLoot:Debug("PackMule: No valid target for: " .. (lootName or "unknown"))
        return
    end

    if target == "IGNORE" then
        HooligansLoot:Debug("PackMule: Rule says ignore: " .. (lootName or "unknown"))
        return
    end

    -- Assign loot based on loot method
    self:AssignLoot(slot, target, itemLink)
end

function PackMule:LootGold()
    local numItems = GetNumLootItems()

    for slot = 1, numItems do
        local slotType = GetLootSlotType(slot)
        if slotType == LOOT_SLOT_MONEY then
            LootSlot(slot)
        end
    end
end

-- ============================================================================
-- Rule Matching
-- ============================================================================

function PackMule:FindMatchingRule(itemID, itemName, quality, itemLink)
    local settings = self:GetSettings()
    local rules = settings.rules

    if not rules or #rules == 0 then
        return nil
    end

    -- Priority 1: Specific item ID rules
    for _, rule in ipairs(rules) do
        if rule.enabled ~= false and rule.itemId and rule.itemId == itemID then
            return rule
        end
    end

    -- Priority 2: Item link match (exact)
    for _, rule in ipairs(rules) do
        if rule.enabled ~= false and rule.itemLink and rule.itemLink == itemLink then
            return rule
        end
    end

    -- Priority 3: Name wildcard rules
    for _, rule in ipairs(rules) do
        if rule.enabled ~= false and rule.itemName then
            if self:MatchesWildcard(itemName, rule.itemName) then
                return rule
            end
        end
    end

    -- Priority 4: Quality rules (sorted by specificity)
    local qualityRules = {}
    for _, rule in ipairs(rules) do
        if rule.enabled ~= false and rule.quality and rule.qualityOperator then
            local matches = false
            if rule.qualityOperator == "<=" and quality <= rule.quality then
                matches = true
            elseif rule.qualityOperator == ">=" and quality >= rule.quality then
                matches = true
            elseif rule.qualityOperator == "==" and quality == rule.quality then
                matches = true
            end

            if matches then
                table.insert(qualityRules, rule)
            end
        end
    end

    -- Return first matching quality rule (rules should be ordered by priority)
    if #qualityRules > 0 then
        return qualityRules[1]
    end

    return nil
end

function PackMule:MatchesWildcard(text, pattern)
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

-- ============================================================================
-- Target Resolution
-- ============================================================================

function PackMule:GetTargetPlayer(rule, itemLink)
    local settings = self:GetSettings()
    local target = rule.target

    if not target then return nil end

    -- Check for special targets
    if target == "SELF" then
        return UnitName("player")

    elseif target == "DE" then
        if settings.disenchanter and settings.disenchanter ~= "" then
            return settings.disenchanter
        else
            HooligansLoot:Print("PackMule: No disenchanter set! Use /hl sd <player>")
            return nil
        end

    elseif target == "RR" then
        return self:GetNextRoundRobin()

    elseif target == "RANDOM" then
        return self:GetRandomEligible()

    elseif target == "IGNORE" then
        return "IGNORE"

    elseif target:match("^!") then
        -- List format: !Player1,!Player2,SELF
        return self:GetFirstAvailable(target)

    else
        -- Direct player name
        return target
    end
end

function PackMule:GetNextRoundRobin()
    local settings = self:GetSettings()
    local list = settings.roundRobinList

    if not list or #list == 0 then
        -- Use raid members if no list configured
        list = Utils.GetGroupMembers()
    end

    if #list == 0 then
        return UnitName("player")
    end

    -- Increment index
    settings.roundRobinIndex = settings.roundRobinIndex + 1
    if settings.roundRobinIndex > #list then
        settings.roundRobinIndex = 1
    end

    local target = list[settings.roundRobinIndex]

    -- Resolve SELF in the list
    if target == "SELF" then
        target = UnitName("player")
    end

    return target
end

function PackMule:GetRandomEligible()
    local members = Utils.GetGroupMembers()

    if #members == 0 then
        return UnitName("player")
    end

    return members[math.random(#members)]
end

function PackMule:GetFirstAvailable(targetString)
    -- Parse !Player1,!Player2,SELF format
    local targets = {}
    for target in targetString:gmatch("!?([^,]+)") do
        target = target:match("^%s*(.-)%s*$") -- Trim whitespace
        if target ~= "" then
            table.insert(targets, target)
        end
    end

    local members = Utils.GetGroupMembers()
    local memberSet = {}
    for _, m in ipairs(members) do
        memberSet[m:lower()] = m
    end

    -- Find first available
    for _, target in ipairs(targets) do
        if target == "SELF" then
            return UnitName("player")
        elseif memberSet[target:lower()] then
            return memberSet[target:lower()]
        end
    end

    return nil
end

-- ============================================================================
-- Item Ignore Logic
-- ============================================================================

function PackMule:IsItemIgnored(itemID, itemName, itemLink)
    local settings = self:GetSettings()

    -- Check custom ignored items
    if settings.ignoredItems and settings.ignoredItems[itemID] then
        return true
    end

    -- Check item class (quest items, etc.)
    if itemID then
        local _, _, _, _, _, itemClassID, itemSubClassID = GetItemInfoInstant(itemID)
        if DEFAULT_IGNORED_CLASSES[itemClassID] then
            return true
        end
    end

    -- Check for untradeable items via tooltip
    if itemLink and self:IsUntradeable(itemLink) then
        return true
    end

    return false
end

function PackMule:IsUntradeable(itemLink)
    local tooltip = self:GetScanTooltip()
    tooltip:ClearLines()
    tooltip:SetHyperlink(itemLink)

    for i = 1, tooltip:NumLines() do
        local line = _G["HooligansPackMuleScanTooltipTextLeft" .. i]
        if line then
            local text = line:GetText()
            if text then
                -- Check for soulbound without trade timer
                if text:find("Soulbound") and not text:find("trade") then
                    -- Check if there's a trade timer on a subsequent line
                    local hasTradeTimer = false
                    for j = i + 1, tooltip:NumLines() do
                        local nextLine = _G["HooligansPackMuleScanTooltipTextLeft" .. j]
                        if nextLine then
                            local nextText = nextLine:GetText()
                            if nextText and nextText:find("You may trade this item") then
                                hasTradeTimer = true
                                break
                            end
                        end
                    end
                    if not hasTradeTimer then
                        return true
                    end
                end
            end
        end
    end

    return false
end

function PackMule:GetScanTooltip()
    if not scanTooltip then
        scanTooltip = CreateFrame("GameTooltip", "HooligansPackMuleScanTooltip", nil, "GameTooltipTemplate")
        scanTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
    end
    return scanTooltip
end

-- ============================================================================
-- Loot Assignment
-- ============================================================================

function PackMule:AssignLoot(slot, targetPlayer, itemLink)
    local settings = self:GetSettings()
    local lootMethod = self:GetCurrentLootMethod()
    local isSelf = (targetPlayer == UnitName("player"))

    HooligansLoot:Debug("PackMule: Assigning " .. (itemLink or "item") .. " to " .. targetPlayer .. " (isSelf=" .. tostring(isSelf) .. ")")

    -- If Master Loot is enabled and target is not self, try GiveMasterLoot first
    if settings.enabledForMasterLoot and not isSelf then
        HooligansLoot:Debug("PackMule: Trying Master Loot assignment")
        local success = self:GiveMasterLootItem(slot, targetPlayer, itemLink)
        if success then
            return
        end
        HooligansLoot:Debug("PackMule: Master Loot failed, falling back to other methods")
    end

    -- For items going to SELF, try direct loot (note: LootSlot is blocked in Classic Anniversary)
    if isSelf then
        HooligansLoot:Debug("PackMule: Target is self, trying direct loot for slot " .. slot)

        -- Try to loot the slot
        if LootSlot then
            if ConfirmLootSlot then
                ConfirmLootSlot(slot)
            end
            LootSlot(slot)
            HooligansLoot:Debug("PackMule: Called LootSlot(" .. slot .. ")")
        end

        return
    end

    if lootMethod == "master" then
        -- Master loot - use GiveMasterLoot
        self:GiveMasterLootItem(slot, targetPlayer, itemLink)

    elseif lootMethod == "group" then
        -- Group loot - can't give to others
        HooligansLoot:Debug("PackMule: Group loot - can't assign to others, skipping")

    elseif lootMethod == "solo" or lootMethod == "ffa" then
        -- Solo or FFA - already handled above for self
        HooligansLoot:Debug("PackMule: Solo/FFA mode, item skipped (target not self)")
    end
end

function PackMule:GiveMasterLootItem(slot, targetPlayer, itemLink)
    -- Find candidate index for target player
    for candidateIndex = 1, 40 do
        local candidate = GetMasterLootCandidate(slot, candidateIndex)
        if candidate then
            local candidateName = Utils.StripRealm(candidate)
            local targetName = Utils.StripRealm(targetPlayer)

            if candidateName:lower() == targetName:lower() then
                -- Give loot to this candidate
                GiveMasterLoot(slot, candidateIndex)
                HooligansLoot:Print("PackMule: Gave " .. (itemLink or "item") .. " to " .. targetPlayer)

                -- Track the distributed item in the session
                local LootTracker = HooligansLoot:GetModule("LootTracker", true)
                if LootTracker and LootTracker.TrackDistributedItem then
                    LootTracker:TrackDistributedItem(itemLink, targetPlayer)
                end

                return true
            end
        end
    end

    HooligansLoot:Print("PackMule: Could not find " .. targetPlayer .. " in loot candidates")
    return false
end

function PackMule:AutoRollNeed(slot, itemLink)
    -- Note: In Classic, auto-rolling may be restricted
    -- This attempts to roll need on the item
    if RollOnLoot then
        RollOnLoot(slot, 1) -- 1 = Need
        HooligansLoot:Debug("PackMule: Rolled Need on " .. (itemLink or "item"))
    elseif ConfirmLootSlot then
        ConfirmLootSlot(slot)
        HooligansLoot:Debug("PackMule: Confirmed loot slot " .. slot)
    end
end

function PackMule:AutoRollPass(slot, itemLink)
    if RollOnLoot then
        RollOnLoot(slot, 0) -- 0 = Pass
        HooligansLoot:Debug("PackMule: Passed on " .. (itemLink or "item"))
    end
end

function PackMule:HasLootPermission()
    return UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
end

-- ============================================================================
-- Rule Management
-- ============================================================================

function PackMule:AddRule(rule)
    local settings = self:GetSettings()
    if not settings.rules then
        settings.rules = {}
    end

    -- Assign an ID if not present
    if not rule.id then
        rule.id = time() .. "_" .. math.random(1000, 9999)
    end

    -- Default to enabled
    if rule.enabled == nil then
        rule.enabled = true
    end

    table.insert(settings.rules, rule)
    HooligansLoot:Print("PackMule: Added rule for target: " .. (rule.target or "unknown"))

    HooligansLoot.callbacks:Fire("PACKMULE_RULES_CHANGED")
    return rule.id
end

function PackMule:RemoveRule(ruleId)
    local settings = self:GetSettings()
    if not settings.rules then return false end

    for i, rule in ipairs(settings.rules) do
        if rule.id == ruleId then
            table.remove(settings.rules, i)
            HooligansLoot.callbacks:Fire("PACKMULE_RULES_CHANGED")
            return true
        end
    end

    return false
end

function PackMule:UpdateRule(ruleId, updates)
    local settings = self:GetSettings()
    if not settings.rules then return false end

    for _, rule in ipairs(settings.rules) do
        if rule.id == ruleId then
            for key, value in pairs(updates) do
                rule[key] = value
            end
            HooligansLoot.callbacks:Fire("PACKMULE_RULES_CHANGED")
            return true
        end
    end

    return false
end

function PackMule:GetRules()
    local settings = self:GetSettings()
    return settings.rules or {}
end

function PackMule:ClearRules()
    local settings = self:GetSettings()
    settings.rules = {}
    HooligansLoot.callbacks:Fire("PACKMULE_RULES_CHANGED")
end

-- ============================================================================
-- Disenchanter Management
-- ============================================================================

function PackMule:SetDisenchanter(playerName)
    local settings = self:GetSettings()
    settings.disenchanter = playerName
    HooligansLoot:Print("PackMule: Disenchanter set to: " .. (playerName or "none"))
end

function PackMule:ClearDisenchanter()
    local settings = self:GetSettings()
    settings.disenchanter = nil
    HooligansLoot:Print("PackMule: Disenchanter cleared")
end

function PackMule:GetDisenchanter()
    local settings = self:GetSettings()
    return settings.disenchanter
end

-- ============================================================================
-- Round Robin Management
-- ============================================================================

function PackMule:SetRoundRobinList(playerList)
    local settings = self:GetSettings()
    settings.roundRobinList = playerList
    settings.roundRobinIndex = 0
end

function PackMule:ResetRoundRobin()
    local settings = self:GetSettings()
    settings.roundRobinIndex = 0
end

-- ============================================================================
-- Ignored Items Management
-- ============================================================================

function PackMule:AddIgnoredItem(itemID)
    local settings = self:GetSettings()
    if not settings.ignoredItems then
        settings.ignoredItems = {}
    end
    settings.ignoredItems[itemID] = true
    HooligansLoot:Print("PackMule: Added item " .. itemID .. " to ignore list")
end

function PackMule:RemoveIgnoredItem(itemID)
    local settings = self:GetSettings()
    if settings.ignoredItems then
        settings.ignoredItems[itemID] = nil
    end
end

function PackMule:GetIgnoredItems()
    local settings = self:GetSettings()
    return settings.ignoredItems or {}
end

-- ============================================================================
-- Enable/Disable Shortcuts
-- ============================================================================

function PackMule:EnableAutoLoot()
    local settings = self:GetSettings()
    settings.enabled = true
    HooligansLoot:Print("PackMule: |cff00ff00Enabled|r")
end

function PackMule:DisableAutoLoot()
    local settings = self:GetSettings()
    settings.enabled = false
    HooligansLoot:Print("PackMule: |cffff0000Disabled|r")
end

function PackMule:ToggleAutoLoot()
    local settings = self:GetSettings()
    if settings.enabled then
        self:DisableAutoLoot()
    else
        self:EnableAutoLoot()
    end
end

function PackMule:IsAutoLootEnabled()
    local settings = self:GetSettings()
    return settings.enabled
end

-- ============================================================================
-- Debug/Testing
-- ============================================================================

function PackMule:TestRule(itemLink)
    if not itemLink then
        HooligansLoot:Print("Usage: /hl pm test [itemlink]")
        return
    end

    local itemID = Utils.GetItemID(itemLink)
    local itemName = Utils.GetItemName(itemLink)
    local _, _, quality = GetItemInfo(itemLink)

    HooligansLoot:Print("Testing PackMule rules for: " .. itemLink)
    print("  Item ID: " .. (itemID or "unknown"))
    print("  Item Name: " .. (itemName or "unknown"))
    print("  Quality: " .. (quality or "unknown"))

    if self:IsItemIgnored(itemID, itemName, itemLink) then
        print("  |cffff0000Result: IGNORED|r")
        return
    end

    local rule = self:FindMatchingRule(itemID, itemName, quality, itemLink)

    if rule then
        print("  |cff00ff00Result: Rule matched|r")
        print("  Target: " .. (rule.target or "none"))

        local resolvedTarget = self:GetTargetPlayer(rule, itemLink)
        print("  Resolved target: " .. (resolvedTarget or "none"))
    else
        print("  |cffffff00Result: No matching rule|r")
    end
end
