-- Transports: boats, zeppelins, the Deeprun Tram and the Darnassus portals
-- on the world map, each with a tooltip naming the destination.
--
-- Dock and tower positions are the stops (nodes with a wait time) in the
-- Forever client's transport routes, TaxiPathNode table, build
-- 1.60.1.70338. Tram entrances and portals come from its AreaTrigger
-- table. World coordinates are projected onto whatever map is open with
-- UlRemedy.ProjectWorldNodes from FlightPaths.lua.

local PIN_TEMPLATE = "UlRemedyTransportPinTemplate"

local KIND = {
    boat     = { atlas = "islands-allianceboat",            size = 26, label = "Boat" },
    hboat    = { atlas = "islands-hordeboat",               size = 26, label = "Boat" },
    zeppelin = { atlas = "vehicle-air-horde",               size = 26, label = "Zeppelin" },
    tram     = { atlas = "vehicle-silvershardmines-minecart", size = 22, label = "Deeprun Tram" },
    portal   = { atlas = "mageportalalliance",              size = 22, label = "Portal" },
}

-- continent: 0 = Eastern Kingdoms, 1 = Kalimdor, 2991 = Zephras Isle.
local STOPS = {
    -- Eastern Kingdoms
    { kind = "boat",     continent = 0, x = -14277.7, y = 582.9,   name = "Booty Bay", to = "Ratchet" },
    { kind = "zeppelin", continent = 0, x = -12464.0, y = 231.6,   name = "Grom'gol Base Camp", to = "Orgrimmar" },
    { kind = "zeppelin", continent = 0, x = -12406.9, y = 211.8,   name = "Grom'gol Base Camp", to = "Undercity" },
    { kind = "boat",     continent = 0, x = -3905.2,  y = -585.8,  name = "Menethil Harbor", to = "Theramore Isle" },
    { kind = "boat",     continent = 0, x = -3709.5,  y = -575.1,  name = "Menethil Harbor", to = "Auberdine and Southshore" },
    { kind = "boat",     continent = 0, x = -1102.6,  y = -554.7,  name = "Southshore", to = "Menethil Harbor and Auberdine", forever = true },
    { kind = "zeppelin", continent = 0, x = 2062.6,   y = 235.3,   name = "Undercity", to = "Grom'gol Base Camp" },
    { kind = "zeppelin", continent = 0, x = 2062.4,   y = 293.0,   name = "Undercity", to = "Orgrimmar" },
    { kind = "boat",     continent = 0, x = -8654.5,  y = 1344.4,  name = "Stormwind Harbor", to = "Auberdine", forever = true },
    { kind = "boat",     continent = 0, x = -8232.3,  y = -5800.8, name = "Powderfuse Port", to = "Steamwheedle Port, Tanaris", forever = true },
    { kind = "boat",     continent = 0, x = 544.8,    y = 424.2,   name = "Silverpine Forest", to = "Zephras Isle", forever = true },
    { kind = "tram",     continent = 0, x = -8346.5,  y = 514.0,   name = "Stormwind City", to = "Ironforge" },
    { kind = "tram",     continent = 0, x = -4840.3,  y = -1330.5, name = "Ironforge", to = "Stormwind City" },

    -- Kalimdor
    { kind = "boat",     continent = 1, x = -1005.6,  y = -3841.6, name = "Ratchet", to = "Booty Bay" },
    { kind = "zeppelin", continent = 1, x = 1360.9,   y = -4631.3, name = "Orgrimmar", to = "Grom'gol Base Camp" },
    { kind = "zeppelin", continent = 1, x = 1318.1,   y = -4658.0, name = "Orgrimmar", to = "Undercity" },
    { kind = "boat",     continent = 1, x = -4016.4,  y = -4740.6, name = "Theramore Isle", to = "Menethil Harbor" },
    { kind = "boat",     continent = 1, x = 8532.0,   y = 1023.7,  name = "Rut'theran Village", to = "Auberdine" },
    { kind = "boat",     continent = 1, x = 6594.4,   y = 759.8,   name = "Auberdine", to = "Rut'theran Village" },
    { kind = "boat",     continent = 1, x = 6406.2,   y = 823.1,   name = "Auberdine", to = "Menethil Harbor and Southshore" },
    { kind = "boat",     continent = 1, x = 6548.3,   y = 942.2,   name = "Auberdine", to = "Stormwind Harbor", forever = true },
    { kind = "boat",     continent = 1, x = -4197.3,  y = 3286.6,  name = "Feathermoon Stronghold", to = "the Feralas mainland" },
    { kind = "boat",     continent = 1, x = -4347.8,  y = 2444.4,  name = "Feralas", to = "Feathermoon Stronghold" },
    { kind = "boat",     continent = 1, x = -6932.6,  y = -4950.8, name = "Steamwheedle Port", to = "Powderfuse Port, Riverglades", forever = true },
    { kind = "boat",     continent = 1, x = -802.0,   y = 366.5,   name = "Mulgore", to = "Zephras Isle", forever = true },
    { kind = "portal",   continent = 1, x = 8799.4,   y = 969.8,   name = "Rut'theran Village", to = "Darnassus" },
    { kind = "portal",   continent = 1, x = 9947.5,   y = 2630.0,  name = "Darnassus", to = "Rut'theran Village" },

    -- Zephras Isle (new in Forever)
    { kind = "boat",     continent = 2991, x = 1848.3, y = 569.1,  name = "Zephras Isle", to = "Silverpine Forest", forever = true },
    { kind = "boat",     continent = 2991, x = 1952.5, y = 1019.1, name = "Zephras Isle", to = "Mulgore", forever = true },
}

local provider
local positions = {}     -- mapID -> projected stops

local function PositionsFor(mapID)
    local list = positions[mapID]
    if list then return list end
    list = UlRemedy.ProjectWorldNodes(mapID, STOPS)
    positions[mapID] = list
    return list
end

------------------------------------------------------------------------
-- Pin
------------------------------------------------------------------------

UlRemedyTransportPinMixin = CreateFromMixins(MapCanvasPinMixin)

function UlRemedyTransportPinMixin:OnLoad()
    self:SetScalingLimits(1, 1.0, 1.2)
    self:UseFrameLevelType("PIN_FRAME_LEVEL_FLIGHT_POINT")
end

function UlRemedyTransportPinMixin:OnAcquired(entry)
    self.entry = entry
    local kind = KIND[entry.node.kind] or KIND.boat
    self.Texture:SetAtlas(kind.atlas)
    self.Texture:SetSize(kind.size, kind.size)
    self.Highlight:SetAtlas(kind.atlas)
    self.Highlight:SetSize(kind.size, kind.size)
    self:SetSize(kind.size, kind.size)
    self:SetPosition(entry.x, entry.y)
end

function UlRemedyTransportPinMixin:CanSetWaypoint()
    local map = self:GetMap()
    return map ~= nil and C_Map.SetUserWaypoint ~= nil and C_Map.CanSetUserWaypointOnMap ~= nil
        and C_Map.CanSetUserWaypointOnMap(map:GetMapID())
end

function UlRemedyTransportPinMixin:OnMouseEnter()
    local node = self.entry.node
    local kind = KIND[node.kind] or KIND.boat
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(kind.label .. " to " .. node.to, 1, 1, 1)
    GameTooltip:AddLine(node.name, 0.8, 0.8, 0.8)
    if node.forever then
        GameTooltip:AddLine("New in Forever", 0.6, 0.6, 0.6)
    end
    if self:CanSetWaypoint() then
        GameTooltip:AddLine("Click to set a waypoint", 0.4, 0.8, 1)
    end
    GameTooltip:Show()
end

function UlRemedyTransportPinMixin:OnMouseLeave()
    GameTooltip:Hide()
end

function UlRemedyTransportPinMixin:OnMouseClickAction(button)
    if button ~= "LeftButton" or not self:CanSetWaypoint() then return end
    local point = { uiMapID = self:GetMap():GetMapID(), position = CreateVector2D(self.entry.x, self.entry.y) }
    local ok = pcall(C_Map.SetUserWaypoint, point)
    if ok and C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
        C_SuperTrack.SetSuperTrackedUserWaypoint(true)
    end
end

------------------------------------------------------------------------
-- Data provider
------------------------------------------------------------------------

local ProviderMixin = CreateFromMixins(MapCanvasDataProviderMixin)

function ProviderMixin:RemoveAllData()
    self:GetMap():RemoveAllPinsByTemplate(PIN_TEMPLATE)
end

function ProviderMixin:RefreshAllData()
    self:RemoveAllData()
    if not UlRemedy.enabled.transports then return end

    local map = self:GetMap()
    local mapID = map:GetMapID()
    if not mapID then return end

    for _, entry in ipairs(PositionsFor(mapID)) do
        map:AcquirePin(PIN_TEMPLATE, entry)
    end
end

function UlRemedy.RefreshTransports()
    if provider and WorldMapFrame and WorldMapFrame:IsShown() then
        provider:RefreshAllData()
    end
end

local function InstallProvider()
    if provider or not WorldMapFrame or not WorldMapFrame.AddDataProvider then return end
    provider = CreateFromMixins(ProviderMixin)
    WorldMapFrame:AddDataProvider(provider)
end

local frame = CreateFrame("Frame", "UlRemedyTransportFrame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self, event)
    InstallProvider()
    if provider then
        self:UnregisterEvent("ADDON_LOADED")
        self:UnregisterEvent("PLAYER_LOGIN")
    end
end)
