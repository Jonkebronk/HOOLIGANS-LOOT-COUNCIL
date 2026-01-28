-- LibDBIcon-1.0
-- Minimap icon library for World of Warcraft addons

local MAJOR, MINOR = "LibDBIcon-1.0", 55
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

lib.objects = lib.objects or {}
lib.callbackRegistered = lib.callbackRegistered or nil
lib.notCreated = lib.notCreated or {}
lib.radius = lib.radius or 80
lib.tooltip = lib.tooltip or GameTooltip

local ldb = LibStub("LibDataBroker-1.1")

local function getAnchors(frame)
    local x, y = frame:GetCenter()
    if not x or not y then return "CENTER" end
    local hhalf = (x > UIParent:GetWidth()*2/3) and "RIGHT" or (x < UIParent:GetWidth()/3) and "LEFT" or ""
    local vhalf = (y > UIParent:GetHeight()/2) and "TOP" or "BOTTOM"
    return vhalf..hhalf, frame, (vhalf == "TOP" and "BOTTOM" or "TOP")..hhalf
end

local function onEnter(self)
    if self.isMoving then return end
    local obj = self.dataObject
    if obj.OnTooltipShow then
        lib.tooltip:SetOwner(self, "ANCHOR_NONE")
        lib.tooltip:SetPoint(getAnchors(self))
        obj.OnTooltipShow(lib.tooltip)
        lib.tooltip:Show()
    elseif obj.OnEnter then
        obj.OnEnter(self)
    end
end

local function onLeave(self)
    local obj = self.dataObject
    lib.tooltip:Hide()
    if obj.OnLeave then obj.OnLeave(self) end
end

local function onClick(self, button)
    local obj = self.dataObject
    if obj.OnClick then
        obj.OnClick(self, button)
    end
end

local function onDragStart(self)
    self.isMoving = true
    self:SetScript("OnUpdate", function(self)
        local mx, my = Minimap:GetCenter()
        local px, py = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        px, py = px / scale, py / scale
        local angle = math.deg(math.atan2(py - my, px - mx))
        self.db.minimapPos = angle
        lib:SetButtonToPosition(self, angle)
    end)
    lib.tooltip:Hide()
end

local function onDragStop(self)
    self.isMoving = nil
    self:SetScript("OnUpdate", nil)
end

local function updateCoord(button)
    local angle = math.rad(button.db.minimapPos or 225)
    local x, y = math.cos(angle), math.sin(angle)
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x * lib.radius, y * lib.radius)
end

function lib:SetButtonToPosition(button, position)
    local angle = math.rad(position)
    local x, y = math.cos(angle), math.sin(angle)
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x * lib.radius, y * lib.radius)
end

local function createButton(name, obj, db)
    local button = CreateFrame("Button", "LibDBIcon10_"..name, Minimap)
    button.dataObject = obj
    button.db = db
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:SetSize(32, 32)
    button:SetHighlightTexture(136477) -- Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight

    local overlay = button:CreateTexture(nil, "OVERLAY")
    overlay:SetSize(50, 50)
    overlay:SetTexture(136430) -- Interface\\Minimap\\MiniMap-TrackingBorder
    overlay:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    button.overlay = overlay

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetSize(24, 24)
    background:SetTexture(136467) -- Interface\\Minimap\\UI-Minimap-Background
    background:SetPoint("CENTER", button, "CENTER", 0, 1)
    button.background = background

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetPoint("CENTER", button, "CENTER", 0, 1)
    icon:SetTexture(obj.icon)
    button.icon = icon

    button:RegisterForClicks("anyUp")
    button:RegisterForDrag("LeftButton")

    button:SetScript("OnEnter", onEnter)
    button:SetScript("OnLeave", onLeave)
    button:SetScript("OnClick", onClick)
    button:SetScript("OnDragStart", onDragStart)
    button:SetScript("OnDragStop", onDragStop)

    button:SetMovable(true)
    lib.objects[name] = button

    if db.hide then
        button:Hide()
    else
        button:Show()
    end

    updateCoord(button)

    if obj.icon then
        button.icon:SetTexture(obj.icon)
    end

    return button
end

function lib:Register(name, obj, db)
    if self.objects[name] then return end
    db = db or {}
    db.minimapPos = db.minimapPos or 220
    if not db.hide then
        createButton(name, obj, db)
    else
        self.notCreated[name] = {obj, db}
    end
end

function lib:Lock(name)
    if not self.objects[name] then return end
    self.objects[name]:SetScript("OnDragStart", nil)
    self.objects[name]:SetScript("OnDragStop", nil)
end

function lib:Unlock(name)
    if not self.objects[name] then return end
    self.objects[name]:SetScript("OnDragStart", onDragStart)
    self.objects[name]:SetScript("OnDragStop", onDragStop)
end

function lib:Hide(name)
    if not self.objects[name] then return end
    self.objects[name]:Hide()
end

function lib:Show(name)
    if self.notCreated[name] then
        createButton(name, self.notCreated[name][1], self.notCreated[name][2])
        self.notCreated[name] = nil
    end
    if self.objects[name] then
        self.objects[name]:Show()
    end
end

function lib:IsRegistered(name)
    return self.objects[name] or self.notCreated[name]
end

function lib:GetMinimapButton(name)
    return self.objects[name]
end

function lib:Refresh(name, db)
    local button = self.objects[name]
    if button then
        button.db = db or button.db
        updateCoord(button)
    end
end

function lib:GetButtonList()
    local list = {}
    for name in pairs(self.objects) do
        table.insert(list, name)
    end
    for name in pairs(self.notCreated) do
        table.insert(list, name)
    end
    return list
end

function lib:SetButtonRadius(radius)
    if type(radius) == "number" then
        lib.radius = radius
        for name, button in pairs(lib.objects) do
            updateCoord(button)
        end
    end
end
