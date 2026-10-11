-- Flight Paths: shows every flight master on the world map, including the
-- ones this character has not discovered yet.
--
-- The node list below is Blizzard's own TaxiNodes table from the Forever
-- client (build 1.60.1.70338), with world coordinates. At runtime each node
-- is projected onto whatever map is open with C_Map.GetMapPosFromWorldPos,
-- so no per-zone coordinate tables are needed and map IDs never have to be
-- hard coded. Nodes the game already draws itself (via its own flight point
-- provider) are skipped so nothing is shown twice.
--
-- Discovery is read from C_TaxiMap.GetTaxiNodesForMap when the client
-- reports it, and otherwise remembered per character every time a flight
-- master window is opened (UlRemedyForeverFlightDB).

local PIN_TEMPLATE = "UlRemedyFlightPinTemplate"

-- continent: 0 = Eastern Kingdoms, 1 = Kalimdor (instance IDs).
-- faction: "Alliance", "Horde" or nil for neutral.
-- druid: Nighthaven's one-way hippogryph, druids only.
local NODES = {
    { id = 2, name = "Stormwind, Elwynn", continent = 0, x = -8832.77, y = 478.62, faction = "Alliance" },
    { id = 4, name = "Sentinel Hill, Westfall", continent = 0, x = -10628.89, y = 1036.68, faction = "Alliance" },
    { id = 5, name = "Lakeshire, Redridge", continent = 0, x = -9429.10, y = -2231.40, faction = "Alliance" },
    { id = 6, name = "Ironforge, Dun Morogh", continent = 0, x = -4821.78, y = -1155.44, faction = "Alliance" },
    { id = 7, name = "Menethil Harbor, Wetlands", continent = 0, x = -3792.26, y = -783.29, faction = "Alliance" },
    { id = 8, name = "Thelsamar, Loch Modan", continent = 0, x = -5421.91, y = -2930.01, faction = "Alliance" },
    { id = 10, name = "The Sepulcher, Silverpine Forest", continent = 0, x = 478.86, y = 1536.59, faction = "Horde" },
    { id = 11, name = "Undercity, Tirisfal", continent = 0, x = 1568.62, y = 267.97, faction = "Horde" },
    { id = 12, name = "Darkshire, Duskwood", continent = 0, x = -10515.46, y = -1261.65, faction = "Alliance" },
    { id = 13, name = "Tarren Mill, Hillsbrad", continent = 0, x = -0.06, y = -859.91, faction = "Horde" },
    { id = 14, name = "Southshore, Hillsbrad", continent = 0, x = -711.48, y = -515.48, faction = "Alliance" },
    { id = 16, name = "Refuge Pointe, Arathi", continent = 0, x = -1240.53, y = -2515.11, faction = "Alliance" },
    { id = 17, name = "Hammerfall, Arathi", continent = 0, x = -916.29, y = -3496.89, faction = "Horde" },
    { id = 18, name = "Booty Bay, Stranglethorn", continent = 0, x = -14444.29, y = 509.62, faction = "Horde" },
    { id = 19, name = "Booty Bay, Stranglethorn", continent = 0, x = -14473.05, y = 464.15, faction = "Alliance" },
    { id = 20, name = "Grom'gol, Stranglethorn", continent = 0, x = -12414.18, y = 146.29, faction = "Horde" },
    { id = 21, name = "Kargath, Badlands", continent = 0, x = -6633.99, y = -2180.05, faction = "Horde" },
    { id = 22, name = "Thunder Bluff, Mulgore", continent = 1, x = -1197.21, y = 29.71, faction = "Horde" },
    { id = 23, name = "Orgrimmar, Durotar", continent = 1, x = 1677.59, y = -4315.71, faction = "Horde" },
    { id = 25, name = "Crossroads, The Barrens", continent = 1, x = -441.80, y = -2596.08, faction = "Horde" },
    { id = 26, name = "Auberdine, Darkshore", continent = 1, x = 6341.38, y = 557.68, faction = "Alliance" },
    { id = 27, name = "Rut'theran Village, Teldrassil", continent = 1, x = 8643.59, y = 841.05, faction = "Alliance" },
    { id = 28, name = "Astranaar, Ashenvale", continent = 1, x = 2827.34, y = -289.24, faction = "Alliance" },
    { id = 29, name = "Sun Rock Retreat, Stonetalon Mountains", continent = 1, x = 966.57, y = 1040.32, faction = "Horde" },
    { id = 30, name = "Freewind Post, Thousand Needles", continent = 1, x = -5407.71, y = -2414.30, faction = "Horde" },
    { id = 31, name = "Thalanaar, Feralas", continent = 1, x = -4491.88, y = -775.89, faction = "Alliance" },
    { id = 32, name = "Theramore, Dustwallow Marsh", continent = 1, x = -3825.37, y = -4516.58, faction = "Alliance" },
    { id = 33, name = "Stonetalon Peak, Stonetalon Mountains", continent = 1, x = 2681.13, y = 1461.68, faction = "Alliance" },
    { id = 37, name = "Nijel's Point, Desolace", continent = 1, x = 139.24, y = 1325.82, faction = "Alliance" },
    { id = 38, name = "Shadowprey Village, Desolace", continent = 1, x = -1767.64, y = 3263.89, faction = "Horde" },
    { id = 39, name = "Gadgetzan, Tanaris", continent = 1, x = -7223.97, y = -3734.59, faction = "Alliance" },
    { id = 40, name = "Gadgetzan, Tanaris", continent = 1, x = -7048.89, y = -3780.36, faction = "Horde" },
    { id = 41, name = "Feathermoon, Feralas", continent = 1, x = -4373.80, y = 3338.65, faction = "Alliance" },
    { id = 42, name = "Camp Mojache, Feralas", continent = 1, x = -4419.86, y = 199.31, faction = "Horde" },
    { id = 43, name = "Aerie Peak, The Hinterlands", continent = 0, x = 283.74, y = -2002.76, faction = "Alliance" },
    { id = 44, name = "Valormok, Azshara", continent = 1, x = 3661.52, y = -4390.38, faction = "Horde" },
    { id = 45, name = "Nethergarde Keep, Blasted Lands", continent = 0, x = -11112.25, y = -3435.74, faction = "Alliance" },
    { id = 48, name = "Bloodvenom Post, Felwood", continent = 1, x = 5068.40, y = -337.22, faction = "Horde" },
    { id = 49, name = "Moonglade", continent = 1, x = 7458.45, y = -2487.21, faction = "Alliance" },
    { id = 52, name = "Everlook, Winterspring", continent = 1, x = 6799.24, y = -4742.44, faction = "Alliance" },
    { id = 53, name = "Everlook, Winterspring", continent = 1, x = 6813.06, y = -4611.12, faction = "Horde" },
    { id = 55, name = "Brackenwall Village, Dustwallow Marsh", continent = 1, x = -3147.39, y = -2842.18, faction = "Horde" },
    { id = 56, name = "Stonard, Swamp of Sorrows", continent = 0, x = -10456.97, y = -3279.25, faction = "Horde" },
    { id = 58, name = "Zoram'gar Outpost, Ashenvale", continent = 1, x = 3374.71, y = 996.97, faction = "Horde" },
    { id = 61, name = "Splintertree Post, Ashenvale", continent = 1, x = 2302.39, y = -2524.55, faction = "Horde" },
    { id = 62, name = "Nighthaven, Moonglade", continent = 1, x = 7793.61, y = -2403.47, faction = "Alliance", druid = true },
    { id = 63, name = "Nighthaven, Moonglade", continent = 1, x = 7787.72, y = -2404.10, faction = "Horde", druid = true },
    { id = 64, name = "Talrendis Point, Azshara", continent = 1, x = 2721.99, y = -3880.64, faction = "Alliance" },
    { id = 65, name = "Talonbranch Glade, Felwood", continent = 1, x = 6205.88, y = -1949.63, faction = "Alliance" },
    { id = 66, name = "Chillwind Camp, Western Plaguelands", continent = 0, x = 931.32, y = -1430.11, faction = "Alliance" },
    { id = 67, name = "Light's Hope Chapel, Eastern Plaguelands", continent = 0, x = 2271.09, y = -5340.80, faction = "Alliance" },
    { id = 68, name = "Light's Hope Chapel, Eastern Plaguelands", continent = 0, x = 2327.41, y = -5286.89, faction = "Horde" },
    { id = 69, name = "Moonglade", continent = 1, x = 7470.39, y = -2123.38, faction = "Horde" },
    { id = 70, name = "Flame Crest, Burning Steppes", continent = 0, x = -7504.03, y = -2187.54, faction = "Horde" },
    { id = 71, name = "Morgan's Vigil, Burning Steppes", continent = 0, x = -8364.61, y = -2738.35, faction = "Alliance" },
    { id = 72, name = "Cenarion Hold, Silithus", continent = 1, x = -6811.39, y = 836.74, faction = "Horde" },
    { id = 73, name = "Cenarion Hold, Silithus", continent = 1, x = -6761.83, y = 772.03, faction = "Alliance" },
    { id = 74, name = "Thorium Point, Searing Gorge", continent = 0, x = -6552.59, y = -1168.27, faction = "Alliance" },
    { id = 75, name = "Thorium Point, Searing Gorge", continent = 0, x = -6554.93, y = -1100.05, faction = "Horde" },
    { id = 76, name = "Revantusk Village, The Hinterlands", continent = 0, x = -635.26, y = -4720.50, faction = "Horde" },
    { id = 77, name = "Camp Taurajo, The Barrens", continent = 1, x = -2380.67, y = -1882.67, faction = "Horde" },
    { id = 79, name = "Marshal's Refuge, Un'Goro Crater", continent = 1, x = -6113.82, y = -1142.70 },
    { id = 80, name = "Ratchet, The Barrens", continent = 1, x = -894.59, y = -3773.01 },
    { id = 559, name = "Summit of Eternity, Mount Hyjal", continent = 1, x = 5283.19, y = -3306.70 },
    { id = 3203, name = "Rog'mar, Riverglades", continent = 0, x = -7923.74, y = -4782.96, faction = "Horde" },
    { id = 3242, name = "Tainted Foothills, Mount Hyjal", continent = 1, x = 4393.52, y = -2836.35 },
    { id = 3274, name = "Powderfuse Port, Riverglades", continent = 0, x = -8157.20, y = -5724.67, faction = "Horde" },
    { id = 3275, name = "Powderfuse Port, Riverglades", continent = 0, x = -8180.05, y = -5616.26, faction = "Alliance" },
    { id = 3276, name = "Farholde Keep, Riverglades", continent = 0, x = -9104.10, y = -4830.47, faction = "Alliance" },
}

local ATLAS = {
    Alliance = "TaxiNode_Alliance",
    Horde    = "TaxiNode_Horde",
    Neutral  = "TaxiNode_Neutral",
}

local DB                 -- UlRemedyForeverFlightDB (per character)
local provider           -- our data provider on WorldMapFrame
local positions = {}     -- mapID -> { { node=, x=, y= }, ... }

-- The Forever client has so far reported every node as discovered, so its
-- discovery flags are ignored until it is seen reporting an undiscovered
-- node at least once. Until then the only source of truth is the list of
-- nodes seen at flight masters, saved per character.
local clientReportsUndiscovered = false
local syncHintShown = false

------------------------------------------------------------------------
-- Node placement
------------------------------------------------------------------------

-- Projects every node (with .continent, .x, .y in world coordinates) on
-- the map's continent onto the map and returns the ones that land inside
-- it as { node=, x=, y= } with normalized map coordinates. Shared with the
-- transport module.
function UlRemedy.ProjectWorldNodes(mapID, nodes)
    local list = {}

    -- Continent and zone maps only; the Azeroth and cosmic maps span more
    -- than one continent and the game draws no flight points there either.
    local mapInfo = C_Map.GetMapInfo(mapID)
    local tooBig = mapInfo and (mapInfo.mapType == Enum.UIMapType.World or mapInfo.mapType == Enum.UIMapType.Cosmic)

    local continentID = (not tooBig) and C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(0.5, 0.5))
    if continentID then
        for _, node in ipairs(nodes) do
            if node.continent == continentID then
                local _, pos = C_Map.GetMapPosFromWorldPos(continentID, CreateVector2D(node.x, node.y), mapID)
                if pos then
                    local x, y = pos:GetXY()
                    if x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
                        list[#list + 1] = { node = node, x = x, y = y }
                    end
                end
            end
        end
    end

    return list
end

-- Cached per map; the projection never changes.
local function PositionsFor(mapID)
    local list = positions[mapID]
    if list then return list end
    list = UlRemedy.ProjectWorldNodes(mapID, NODES)
    positions[mapID] = list
    return list
end

-- What the client itself knows about taxi nodes on this map. Returns a set
-- of node IDs the game's own provider is drawing (so we skip them), a set
-- of node IDs the client reports as discovered, and a summary for /ur fp.
local function QueryClient(mapID)
    local shownByGame, discovered, info = {}, {}, nil
    if C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap then
        local ok, nodes = pcall(C_TaxiMap.GetTaxiNodesForMap, mapID)
        if ok and type(nodes) == "table" then
            local gameDraws = C_TaxiMap.ShouldMapShowTaxiNodes and C_TaxiMap.ShouldMapShowTaxiNodes(mapID)
            info = { returned = #nodes, undiscovered = 0, gameDraws = gameDraws and true or false }
            for _, n in ipairs(nodes) do
                if n.isUndiscovered then
                    info.undiscovered = info.undiscovered + 1
                    clientReportsUndiscovered = true
                else
                    discovered[n.nodeID] = true
                end
                if gameDraws then shownByGame[n.nodeID] = true end
            end
        end
    end
    return shownByGame, discovered, info
end

local function IsDiscovered(nodeID, clientDiscovered)
    if clientReportsUndiscovered and clientDiscovered and clientDiscovered[nodeID] then return true end
    return DB ~= nil and DB.discovered[nodeID] == true
end

-- For the game's own pins: its poiInfo carries the client's flag, which
-- only counts once the client has proven it reports undiscovered nodes.
local function IsGamePinDiscovered(poiInfo)
    if not poiInfo or not poiInfo.nodeID then return true end
    if clientReportsUndiscovered and not poiInfo.isUndiscovered then return true end
    return DB ~= nil and DB.discovered[poiInfo.nodeID] == true
end

------------------------------------------------------------------------
-- Look of undiscovered points
------------------------------------------------------------------------

local lastError      -- last Lua error from the pin styling, shown by /ur fp

-- Undiscovered: the icon is tinted red, drawn a bit larger, and a red
-- ring pulses behind it. Discovered: the plain faction icon. Works on our
-- own pins and on the game's own flight point pins alike; the ring and
-- its animation are created in Lua on first use and reused when the pin
-- is recycled.
local function ApplyLook(pin, undiscovered)
    local icon = pin.Texture
    if not icon then return end

    if undiscovered then
        icon:SetDesaturated(true)
        icon:SetVertexColor(1, 0.35, 0.35)
        icon:SetScale(1.25)
    else
        icon:SetDesaturated(false)
        icon:SetVertexColor(1, 1, 1)
        icon:SetScale(1)
    end

    if not pin.UlRemedyRing then
        if not undiscovered then return end
        local ring = pin:CreateTexture(nil, "BACKGROUND")
        ring:SetAtlas("UI-QuestPoi-OuterGlow")
        ring:SetSize(40, 40)
        ring:SetPoint("CENTER")
        ring:SetBlendMode("ADD")
        ring:SetVertexColor(1, 0.3, 0.3)
        pin.UlRemedyRing = ring

        local group = ring:CreateAnimationGroup()
        group:SetLooping("BOUNCE")
        local alpha = group:CreateAnimation("Alpha")
        alpha:SetFromAlpha(1)
        alpha:SetToAlpha(0.3)
        alpha:SetDuration(0.8)
        alpha:SetSmoothing("IN_OUT")
        pin.UlRemedyPulse = group
    end
    if undiscovered then
        pin.UlRemedyRing:Show()
        pin.UlRemedyPulse:Play()
    else
        pin.UlRemedyPulse:Stop()
        pin.UlRemedyRing:Hide()
    end
end

-- The client hides Lua errors by default, so catch our own and report
-- them once in chat; /ur fp repeats the last one.
local function SafeApplyLook(pin, undiscovered)
    local ok, err = pcall(ApplyLook, pin, undiscovered)
    if not ok and err ~= lastError then
        lastError = err
        print(UlRemedy.name .. ": flight path pin error: " .. tostring(err))
    end
end

-- When the game draws undiscovered flight points itself, style its pins
-- instead of ours. Hooking the mixin covers every pin created after this
-- file loads, and no pins exist before the map is first opened.
local function HookGamePins()
    if FlightPointPinMixin and not FlightPointPinMixin.UlRemedyHooked then
        FlightPointPinMixin.UlRemedyHooked = true
        hooksecurefunc(FlightPointPinMixin, "OnAcquired", function(pin, poiInfo)
            if poiInfo and poiInfo.isUndiscovered then clientReportsUndiscovered = true end
            SafeApplyLook(pin, UlRemedy.enabled.flightpaths and not IsGamePinDiscovered(poiInfo))
        end)
    end
end

------------------------------------------------------------------------
-- Pin
------------------------------------------------------------------------

UlRemedyFlightPinMixin = CreateFromMixins(MapCanvasPinMixin)

function UlRemedyFlightPinMixin:OnLoad()
    self:SetScalingLimits(1, 1.0, 1.2)
    self:UseFrameLevelType("PIN_FRAME_LEVEL_FLIGHT_POINT")
end

function UlRemedyFlightPinMixin:OnAcquired(entry, discovered)
    self.entry = entry
    self.discovered = discovered

    local atlas = ATLAS[entry.node.faction or "Neutral"]
    self.Texture:SetAtlas(atlas, true)
    self.Highlight:SetAtlas(atlas, true)
    self:SetSize(self.Texture:GetSize())

    SafeApplyLook(self, not discovered)

    self:SetPosition(entry.x, entry.y)
end

function UlRemedyFlightPinMixin:OnReleased()
    SafeApplyLook(self, false)
    MapCanvasPinMixin.OnReleased(self)
end

function UlRemedyFlightPinMixin:CanSetWaypoint()
    local map = self:GetMap()
    return map ~= nil and C_Map.SetUserWaypoint ~= nil and C_Map.CanSetUserWaypointOnMap ~= nil
        and C_Map.CanSetUserWaypointOnMap(map:GetMapID())
end

function UlRemedyFlightPinMixin:OnMouseEnter()
    local node = self.entry.node
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(node.name, 1, 1, 1)
    if self.discovered then
        GameTooltip:AddLine("Flight path", 0.8, 0.8, 0.8)
    else
        GameTooltip:AddLine("Undiscovered flight path", 0.6, 0.6, 0.6)
    end
    if node.druid then
        GameTooltip:AddLine("Druids only, one way to Rut'theran Village", 0.6, 0.6, 0.6)
    end
    if self:CanSetWaypoint() then
        GameTooltip:AddLine("Click to set a waypoint", 0.4, 0.8, 1)
    end
    GameTooltip:Show()
end

function UlRemedyFlightPinMixin:OnMouseLeave()
    GameTooltip:Hide()
end

function UlRemedyFlightPinMixin:OnMouseClickAction(button)
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
    if not UlRemedy.enabled.flightpaths then return end

    local map = self:GetMap()
    local mapID = map:GetMapID()
    if not mapID then return end

    local shownByGame, clientDiscovered = QueryClient(mapID)
    local playerFaction = UnitFactionGroup("player")
    local isDruid = select(2, UnitClass("player")) == "DRUID"

    for _, entry in ipairs(PositionsFor(mapID)) do
        local node = entry.node
        local forMe = (node.faction == nil or node.faction == playerFaction) and (not node.druid or isDruid)
        if forMe and not shownByGame[node.id] then
            map:AcquirePin(PIN_TEMPLATE, entry, IsDiscovered(node.id, clientDiscovered))
        end
    end

    -- Until this character has talked to a flight master, nothing is
    -- known and every point shows as undiscovered. Say so once.
    if not syncHintShown and DB and next(DB.discovered) == nil then
        syncHintShown = true
        print(UlRemedy.name .. ": flight paths will show as undiscovered until you open a flight master once; known paths are read from there.")
    end
end

function UlRemedy.RefreshFlightPaths()
    if provider and WorldMapFrame and WorldMapFrame:IsShown() then
        provider:RefreshAllData()
        -- Re-style the game's own pins after a toggle or a sync.
        for pin in WorldMapFrame:EnumeratePinsByTemplate("FlightPointPinTemplate") do
            SafeApplyLook(pin, UlRemedy.enabled.flightpaths and not IsGamePinDiscovered(pin.poiInfo))
        end
    end
end

local function InstallProvider()
    HookGamePins()
    if provider or not WorldMapFrame or not WorldMapFrame.AddDataProvider then return end
    provider = CreateFromMixins(ProviderMixin)
    WorldMapFrame:AddDataProvider(provider)
end

------------------------------------------------------------------------
-- Discovery tracking at flight masters
------------------------------------------------------------------------

local function RecordKnownNodes()
    if not DB or not C_TaxiMap or not C_TaxiMap.GetAllTaxiNodes then return end
    local mapID = (GetTaxiMapID and GetTaxiMapID()) or C_Map.GetBestMapForUnit("player")
    if not mapID then return end
    local ok, nodes = pcall(C_TaxiMap.GetAllTaxiNodes, mapID)
    if not ok or type(nodes) ~= "table" then return end
    -- Only nodes you can actually fly to (or stand at) count as known.
    -- "Unreachable" is what the flight map uses for nodes it lists but
    -- has no route to, which may include ones never discovered.
    local unreachable = Enum.FlightPathState and Enum.FlightPathState.Unreachable
    local added, ignored = 0, 0
    for _, n in ipairs(nodes) do
        if n.nodeID then
            if unreachable ~= nil and n.state == unreachable then
                ignored = ignored + 1
            elseif not DB.discovered[n.nodeID] then
                DB.discovered[n.nodeID] = true
                added = added + 1
            end
        end
    end
    if added > 0 then
        local note = ignored > 0 and string.format(" (%d unreachable ignored)", ignored) or ""
        print(UlRemedy.name .. ": " .. added .. " known flight path(s) synced from the flight master" .. note .. ".")
        UlRemedy.RefreshFlightPaths()
    end
end

-- /ur fpreset: forget every known flight path for this character, so the
-- next flight master visit rebuilds the list from scratch.
function UlRemedy.ResetFlightPaths()
    if not DB then return end
    DB.discovered = {}
    syncHintShown = false
    print(UlRemedy.name .. ": known flight paths cleared for this character. Open a flight master to sync again.")
    UlRemedy.RefreshFlightPaths()
end

------------------------------------------------------------------------
-- Debug command: /ur fp
------------------------------------------------------------------------

function UlRemedy.FlightPathDebug()
    local mapOpen = WorldMapFrame and WorldMapFrame:IsShown()
    local mapID = (mapOpen and WorldMapFrame:GetMapID()) or C_Map.GetBestMapForUnit("player")
    if not mapID then
        print(UlRemedy.name .. ": no map to inspect.")
        return
    end
    local info = C_Map.GetMapInfo(mapID)
    local continentID = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(0.5, 0.5))
    local _, _, clientInfo = QueryClient(mapID)
    local placed = PositionsFor(mapID)
    local shown, gamePins, gameUndiscovered, styled = 0, 0, 0, 0
    if mapOpen then
        for pin in WorldMapFrame:EnumeratePinsByTemplate(PIN_TEMPLATE) do
            shown = shown + 1
            if pin.UlRemedyRing and pin.UlRemedyRing:IsShown() then styled = styled + 1 end
        end
        for pin in WorldMapFrame:EnumeratePinsByTemplate("FlightPointPinTemplate") do
            gamePins = gamePins + 1
            if pin.poiInfo and pin.poiInfo.isUndiscovered then gameUndiscovered = gameUndiscovered + 1 end
            if pin.UlRemedyRing and pin.UlRemedyRing:IsShown() then styled = styled + 1 end
        end
    end
    local remembered = 0
    if DB then
        for _ in pairs(DB.discovered) do remembered = remembered + 1 end
    end

    print(string.format("|cffffcc00%s|r flight paths on %s (map %d, continent %s):",
        UlRemedy.name, info and info.name or "?", mapID, tostring(continentID)))
    print(string.format("  provider installed: %s, feature enabled: %s",
        tostring(provider ~= nil), tostring(UlRemedy.enabled.flightpaths)))
    if clientInfo then
        print(string.format("  client returns %d node(s), %d undiscovered, game draws them itself: %s, client flags trusted: %s",
            clientInfo.returned, clientInfo.undiscovered, tostring(clientInfo.gameDraws), tostring(clientReportsUndiscovered)))
    else
        print("  client taxi API unavailable or errored")
    end
    print(string.format("  addon nodes on this map: %d, addon pins shown now: %d, nodes remembered as discovered: %d",
        #placed, shown, remembered))
    print(string.format("  game's own pins shown now: %d (%d undiscovered), pins styled as undiscovered: %d, game pin hook: %s",
        gamePins, gameUndiscovered, styled, tostring(FlightPointPinMixin ~= nil and FlightPointPinMixin.UlRemedyHooked == true)))
    print("  last pin error: " .. tostring(lastError))
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------

local frame = CreateFrame("Frame", "UlRemedyFlightFrame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("TAXIMAP_OPENED")
frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == UlRemedy.name then
            if not UlRemedyForeverFlightDB then UlRemedyForeverFlightDB = {} end
            DB = UlRemedyForeverFlightDB
            -- Version 1 recorded "unreachable" nodes as known, which on
            -- Forever includes undiscovered ones. Start over once.
            if (DB.version or 1) < 2 then
                DB.discovered = {}
                DB.version = 2
            end
            DB.discovered = DB.discovered or {}
        end
        -- Blizzard_WorldMap may load after us; try on every addon load
        -- until the map frame exists.
        InstallProvider()
        if provider then self:UnregisterEvent("ADDON_LOADED") end
    elseif event == "PLAYER_LOGIN" then
        InstallProvider()
    elseif event == "TAXIMAP_OPENED" then
        RecordKnownNodes()
    end
end)
