-- LibDataBroker-1.1
-- Standard data broker library for WoW addons

local MAJOR, MINOR = "LibDataBroker-1.1", 4
local lib, oldminor = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end
oldminor = oldminor or 0

lib.callbacks = lib.callbacks or LibStub("CallbackHandler-1.0"):New(lib)
lib.attributestorage = lib.attributestorage or {}
lib.namestorage = lib.namestorage or {}
lib.proxystorage = lib.proxystorage or {}

local attributestorage = lib.attributestorage
local namestorage = lib.namestorage
local proxystorage = lib.proxystorage
local callbacks = lib.callbacks

if oldminor < 2 then
    lib.domt = {
        __metatable = "access denied",
        __index = function(self, key) return attributestorage[self] and attributestorage[self][key] end,
    }
end

if oldminor < 3 then
    lib.domt.__newindex = function(self, key, value)
        if not attributestorage[self] then attributestorage[self] = {} end
        if attributestorage[self][key] == value then return end
        attributestorage[self][key] = value
        local name = namestorage[self]
        if name then
            callbacks:Fire("LibDataBroker_AttributeChanged", name, key, value, self)
            callbacks:Fire("LibDataBroker_AttributeChanged_"..name, name, key, value, self)
            callbacks:Fire("LibDataBroker_AttributeChanged_"..name.."_"..key, name, key, value, self)
            callbacks:Fire("LibDataBroker_AttributeChanged__"..key, name, key, value, self)
        end
    end
end

if oldminor < 4 then
    function lib:NewDataObject(name, dataobj)
        if self.proxystorage[name] then return end

        if dataobj then
            assert(type(dataobj) == "table", "Invalid dataobj, must be nil or a table")
            self.attributestorage[dataobj] = {}
            for i,v in pairs(dataobj) do
                self.attributestorage[dataobj][i] = v
                dataobj[i] = nil
            end
        end
        dataobj = dataobj or {}
        self.proxystorage[name] = dataobj
        self.namestorage[dataobj] = name
        setmetatable(dataobj, self.domt)
        self.callbacks:Fire("LibDataBroker_DataObjectCreated", name, dataobj)
        return dataobj
    end
end

function lib:DataObjectIterator()
    return pairs(self.proxystorage)
end

function lib:GetDataObjectByName(dataobjectname)
    return self.proxystorage[dataobjectname]
end

function lib:GetNameByDataObject(dataobject)
    return self.namestorage[dataobject]
end
