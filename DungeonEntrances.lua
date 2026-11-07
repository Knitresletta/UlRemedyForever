-- Dungeon Entrances: every instance entrance on the world map, with the
-- level range Forever gives it in the tooltip, colored for your level.
--
-- Ported from UlDungeonCompanion (retired 07.11.2026); the entrance pins
-- were the one part of it worth keeping. Pins are drawn by our own
-- MapCanvasDataProvider, so nothing of Blizzard's map is touched. The
-- retail map can draw dungeon entrances itself
-- (C_EncounterJournal.GetDungeonEntrancesForMap); where it does, our pin
-- is skipped and the level line is added to the game's own tooltip, so
-- nothing shows twice.
--
-- Forever sources only (Jonatan, 06.11.2026):
--  * Level ranges are ForeverChanges' (https://foreverchanges.pro, the
--    dungeon list on every /dungeons/<slug> page, read 06.11.2026), wings
--    with their own ranges where the site lists them.
--  * Entrance positions are map percentages on retail map IDs (map, mx,
--    my), converted to world positions at runtime. They are the client's
--    own entrance points as ForeverDB reads them
--    (https://foreverdb.net/dungeon/<id>, 06.11.2026), except where Jonatan
--    has stood at the entrance in game, which wins (noted per entry). An
--    instance without a position has none in any Forever source yet: it is
--    listed by /ur dungeons but gets no pin.
--
-- /ur dungeons prints the list sorted by level, /ur dpins prints what
-- happened on the open map.

local PIN_TEMPLATE = "UlRemedyDungeonPinTemplate"
local NEAR = 0.025  -- normalized map distance under which a game pin counts as ours

local ATLAS = { dungeon = "Dungeon", raid = "Raid" }
local FALLBACK_TEXTURE = "Interface\\Icons\\INV_Misc_Map_01"

-- faction limits who can reach the city the entrance sits in.
local DUNGEONS = {
    -- Dungeons, by level.
    { name = "The Hall of Thanes", kind = "dungeon", levels = { 13, 18 }, zone = "Ironforge", faction = "Alliance",
      map = 1455, mx = 43.5, my = 52.0, label = "Passage from the High Seat",
      note = "Enter the throne room, turn left into the web-covered passage, follow the stairs down past the lava to the bridge. Position seen in game 14.10.2026; the client's own point (77.1, 51.3) is the portal under the city." },
    { name = "Ragefire Chasm", kind = "dungeon", levels = { 13, 18 }, zone = "Orgrimmar", faction = "Horde",
      map = 1454, mx = 53.0, my = 48.9 },
    { name = "Ruins of Lordaeron", kind = "dungeon", levels = { 15, 20 }, zone = "Tirisfal Glades",
      map = 1420, mx = 63.3, my = 67.5, note = "The ruined capital above the Undercity." },
    { name = "Wailing Caverns", kind = "dungeon", levels = { 17, 24 }, zone = "The Barrens",
      map = 1413, mx = 47.7, my = 35.0 },
    { name = "The Deadmines", kind = "dungeon", levels = { 17, 26 }, zone = "Westfall",
      map = 1436, mx = 41.8, my = 72.5, label = "Mine house in Moonbrook",
      note = "Where you walk in, seen in game 14.10.2026; the client's own point (38.2, 77.5) is the portal at the end of the tunnel." },
    { name = "Shadowfang Keep", kind = "dungeon", levels = { 22, 30 }, zone = "Silverpine Forest" },
    { name = "Blackfathom Deeps", kind = "dungeon", levels = { 24, 32 }, zone = "Ashenvale",
      map = 1440, mx = 16.5, my = 11.0 },
    { name = "The Stockade", kind = "dungeon", levels = { 24, 32 }, zone = "Stormwind City", faction = "Alliance" },
    { name = "Excavation Site: Wetlands", kind = "dungeon", levels = { 26, 31 }, zone = "Wetlands",
      map = 1437, mx = 47.7, my = 61.8,
      note = "In the hills south of the road, between Whelgar's Excavation Site and Dun Algaz. Seen in game 14.10.2026; the client's own point (24.5, 73.4) is far to the south-west." },
    { name = "City of Dalaran", kind = "dungeon", levels = { 28, 33 }, zone = "Silverpine Forest",
      map = 1421, mx = 69.6, my = 46.1, label = "Sewer gate",
      note = "Through the sewers; the gate needs the Dalaran Sewer Key (Heart of Disruption). Alliance enters from inside the city." },
    { name = "Gnomeregan", kind = "dungeon", levels = { 29, 38 }, zone = "Dun Morogh",
      map = 1426, mx = 17.7, my = 39.1 },
    { name = "Razorfen Kraul", kind = "dungeon", levels = { 29, 38 }, zone = "The Barrens",
      map = 1413, mx = 42.3, my = 89.9 },
    { name = "Scarlet Monastery", kind = "dungeon", levels = { 30, 46 }, zone = "Tirisfal Glades",
      map = 1420, mx = 85.1, my = 31.4,
      wings = {
          { name = "Graveyard", levels = { 30, 38 } },
          { name = "Library",   levels = { 33, 41 } },
          { name = "Armory",    levels = { 36, 44 } },
          { name = "Cathedral", levels = { 38, 46 } },
      } },
    { name = "The Drowned City", kind = "dungeon", levels = { 35, 40 }, zone = "Stranglethorn Vale" },
    { name = "Razorfen Downs", kind = "dungeon", levels = { 37, 46 }, zone = "The Barrens",
      map = 1413, mx = 50.9, my = 92.9 },
    { name = "Krol'dok Stronghold", kind = "dungeon", levels = { 40, 45 }, zone = "Riverglades" },
    { name = "Uldaman", kind = "dungeon", levels = { 41, 51 }, zone = "Badlands",
      map = 1418, mx = 35.2, my = 10.3 },
    { name = "Zul'Farrak", kind = "dungeon", levels = { 44, 54 }, zone = "Tanaris",
      map = 1446, mx = 38.7, my = 19.9 },
    { name = "Maraudon", kind = "dungeon", levels = { 46, 55 }, zone = "Desolace",
      map = 1443, mx = 29.1, my = 62.9 },
    { name = "Alcaz Prison", kind = "dungeon", levels = { 48, 53 }, zone = "Dustwallow Marsh" },
    { name = "The Temple of Atal'Hakkar", kind = "dungeon", levels = { 50, 60 }, zone = "Swamp of Sorrows",
      map = 1435, mx = 77.3, my = 35.9 },
    { name = "Blackrock Depths", kind = "dungeon", levels = { 52, 60 }, zone = "Searing Gorge",
      map = 1427, mx = 27.1, my = 72.5 },
    { name = "Dire Maul", kind = "dungeon", levels = { 54, 60 }, zone = "Feralas",
      map = 1444, mx = 62.0, my = 33.3,
      wings = {
          { name = "East",  levels = { 54, 60 } },
          { name = "North", levels = { 56, 60 } },
          { name = "West",  levels = { 56, 60 } },
      } },
    { name = "Blackmaw Hold", kind = "dungeon", levels = { 55, 60 }, zone = "Azshara" },
    { name = "Blackrock Spire", kind = "dungeon", levels = { 55, 60 }, zone = "Burning Steppes",
      map = 1428, mx = 33.0, my = 25.2,
      wings = {
          { name = "Lower", levels = { 55, 60 } },
          { name = "Upper", levels = { 59, 60 } },
      },
      note = "Blackwing Lair is entered from Upper Blackrock Spire." },
    { name = "Scholomance", kind = "dungeon", levels = { 58, 60 }, zone = "Western Plaguelands",
      map = 1422, mx = 69.0, my = 73.0 },
    { name = "Shaper's Terrace", kind = "dungeon", levels = { 58, 60 }, zone = "Un'Goro Crater" },
    { name = "Stratholme", kind = "dungeon", levels = { 58, 60 }, zone = "Eastern Plaguelands",
      wings = {
          { name = "Main Gate",    levels = { 58, 60 } },
          { name = "Service Gate", levels = { 58, 60 } },
      } },
    -- Raids. Level ranges from ForeverChanges' quest categories (all 60).
    { name = "Onyxia's Lair", kind = "raid", levels = { 60, 60 }, zone = "Dustwallow Marsh",
      map = 1445, mx = 52.9, my = 77.7 },
    { name = "Molten Core", kind = "raid", levels = { 60, 60 }, zone = "Burning Steppes",
      map = 1428, mx = 26.3, my = 24.6,
      note = "The window in Blackrock Mountain; the walk goes through Blackrock Depths." },
    { name = "Blackwing Lair", kind = "raid", levels = { 60, 60 }, zone = "Burning Steppes",
      note = "Entered from Upper Blackrock Spire." },
    { name = "Zul'Gurub", kind = "raid", levels = { 60, 60 }, zone = "Stranglethorn Vale" },
    { name = "Ruins of Ahn'Qiraj", kind = "raid", levels = { 60, 60 }, zone = "Silithus",
      map = 1451, mx = 29.0, my = 92.8 },
    { name = "Temple of Ahn'Qiraj", kind = "raid", levels = { 60, 60 }, zone = "Silithus",
      map = 1451, mx = 29.0, my = 92.7 },
    { name = "Naxxramas", kind = "raid", levels = { 60, 60 }, zone = "Eastern Plaguelands" },
}

local provider
local positions = {}     -- mapID -> { { node=, x=, y= }, ... }
local lastError
local lastDebug = {}     -- what the last refresh did, for /ur dpins

local function Print(msg) print(UlRemedy.name .. ": " .. msg) end

------------------------------------------------------------------------
-- Level text and color (the fit logic is shared with Zone Levels)
------------------------------------------------------------------------

local function LevelFit(levels)
    return UlRemedy.LevelFit(levels)
end

local function LevelText(levels)
    if levels[1] == levels[2] then return tostring(levels[1]) end
    return levels[1] .. "-" .. levels[2]
end

local function ColorCode(r, g, b)
    return string.format("|cff%02x%02x%02x", math.floor(r * 255), math.floor(g * 255), math.floor(b * 255))
end

------------------------------------------------------------------------
-- Placement
------------------------------------------------------------------------

-- Entrances are stored as map percentages; turn them into world
-- positions the first time they are needed, then project onto any map.
local function ResolveNodes()
    if not (C_Map.GetWorldPosFromMapPos and CreateVector2D) then return end
    for _, node in ipairs(DUNGEONS) do
        if node.map and not node.x then
            local continentID, world = C_Map.GetWorldPosFromMapPos(node.map, CreateVector2D(node.mx / 100, node.my / 100))
            if continentID and world then
                local wx, wy = world:GetXY()
                if wx and wy then node.continent, node.x, node.y = continentID, wx, wy end
            end
        end
    end
end

local function ProjectNodes(mapID)
    local list = {}
    ResolveNodes()
    local mapInfo = C_Map.GetMapInfo(mapID)
    local tooBig = mapInfo and (mapInfo.mapType == Enum.UIMapType.World or mapInfo.mapType == Enum.UIMapType.Cosmic)
    local continentID = (not tooBig) and C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(0.5, 0.5))
    if not continentID then return list end

    for _, node in ipairs(DUNGEONS) do
        if node.continent == continentID and node.x then
            local _, pos = C_Map.GetMapPosFromWorldPos(continentID, CreateVector2D(node.x, node.y), mapID)
            if pos then
                local x, y = pos:GetXY()
                if x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
                    list[#list + 1] = { node = node, x = x, y = y }
                end
            end
        end
    end
    return list
end

local function PositionsFor(mapID)
    local list = positions[mapID]
    if list then return list end
    list = ProjectNodes(mapID)
    positions[mapID] = list
    return list
end

-- Entrances the game draws itself on this map, as normalized positions
-- with names. Empty when the client has no such API.
local function GameEntrances(mapID)
    local list = {}
    if C_EncounterJournal and C_EncounterJournal.GetDungeonEntrancesForMap then
        local ok, entrances = pcall(C_EncounterJournal.GetDungeonEntrancesForMap, mapID)
        if ok and type(entrances) == "table" then
            for _, e in ipairs(entrances) do
                if e.position then
                    local x, y = e.position:GetXY()
                    list[#list + 1] = { name = e.name, x = x, y = y }
                end
            end
        end
    end
    return list
end

local function NearGamePin(entry, gamePins)
    for _, g in ipairs(gamePins) do
        local dx, dy = entry.x - g.x, entry.y - g.y
        if dx * dx + dy * dy < NEAR * NEAR then return g end
    end
    return nil
end

------------------------------------------------------------------------
-- Tooltip lines
------------------------------------------------------------------------

local function AddLevelLines(node)
    local fit, r, g, b = LevelFit(node.levels)
    local kind = node.kind == "raid" and "Raid" or "Dungeon"
    GameTooltip:AddDoubleLine(kind .. ", level " .. LevelText(node.levels), fit, 0.8, 0.8, 0.8, r, g, b)
    if node.wings then
        for _, wing in ipairs(node.wings) do
            local _, wr, wg, wb = LevelFit(wing.levels)
            GameTooltip:AddDoubleLine("  " .. wing.name, LevelText(wing.levels), 0.7, 0.7, 0.7, wr, wg, wb)
        end
    end
    if node.note then
        GameTooltip:AddLine(node.note, 0.6, 0.6, 0.6, true)
    end
end

-- The game's own entrance pins: append our level lines to their tooltip.
-- Matched by name, so an entrance we do not know is left as it is.
local byName = {}
for _, node in ipairs(DUNGEONS) do
    byName[node.name] = byName[node.name] or node
end

local function HookGamePins()
    if DungeonEntrancePinMixin and not DungeonEntrancePinMixin.UlRemedyHooked then
        DungeonEntrancePinMixin.UlRemedyHooked = true
        hooksecurefunc(DungeonEntrancePinMixin, "OnMouseEnter", function(pin)
            if not UlRemedy.enabled.dungeons or not GameTooltip:IsShown() then return end
            local name = pin.name or (pin.poiInfo and pin.poiInfo.name)
            local node = name and byName[name]
            if not node then return end
            local ok, err = pcall(AddLevelLines, node)
            if ok then
                GameTooltip:Show()
            elseif err ~= lastError then
                lastError = err
                Print("dungeon tooltip error: " .. tostring(err))
            end
        end)
    end
end

------------------------------------------------------------------------
-- Pin
------------------------------------------------------------------------

UlRemedyDungeonPinMixin = CreateFromMixins(MapCanvasPinMixin)

function UlRemedyDungeonPinMixin:OnLoad()
    self:SetScalingLimits(1, 1.0, 1.2)
    -- The dungeon entrance level exists on retail; fall back to the flight
    -- point level, which the Forever client is known to have.
    if not pcall(self.UseFrameLevelType, self, "PIN_FRAME_LEVEL_DUNGEON_ENTRANCE") then
        self:UseFrameLevelType("PIN_FRAME_LEVEL_FLIGHT_POINT")
    end
end

-- AcquirePin ends with CheckMouseButtonPassthrough, which calls the
-- protected SetPassThroughButtons; from an addon in combat the client
-- refuses it (same as the flight path pins, 06.11.2026). A pin taken in
-- combat keeps what it has, and the map is refreshed once combat ends.
local acquiredInCombat = false

function UlRemedyDungeonPinMixin:CheckMouseButtonPassthrough(...)
    if InCombatLockdown() then
        acquiredInCombat = true
        return
    end
    MapCanvasPinMixin.CheckMouseButtonPassthrough(self, ...)
end

local function SetIcon(texture, kind)
    local atlas = ATLAS[kind] or ATLAS.dungeon
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
        texture:SetAtlas(atlas, true)
        return true
    end
    texture:SetTexture(FALLBACK_TEXTURE)
    texture:SetSize(20, 20)
    return false
end

-- On continent maps the pins are drawn smaller than on zone maps, where
-- the full atlas size stays (same rule as the flight path pins).
local CONTINENT_SCALE = 0.75

local function PinScale(map)
    local mapID = map and map.GetMapID and map:GetMapID()
    local info = mapID and C_Map.GetMapInfo(mapID)
    if info and info.mapType == Enum.UIMapType.Continent then return CONTINENT_SCALE end
    return 1
end

function UlRemedyDungeonPinMixin:OnAcquired(entry)
    self.entry = entry
    local ok, err = pcall(function()
        SetIcon(self.Texture, entry.node.kind)
        SetIcon(self.Highlight, entry.node.kind)
        local scale = PinScale(self:GetMap())
        if scale ~= 1 then
            local w, h = self.Texture:GetSize()
            self.Texture:SetSize(w * scale, h * scale)
            self.Highlight:SetSize(w * scale, h * scale)
        end
        self:SetSize(self.Texture:GetSize())
        local fit = LevelFit(entry.node.levels)
        self.Texture:SetDesaturated(fit == "outgrown")
        self:SetAlpha(fit == "outgrown" and 0.6 or 1)
    end)
    if not ok and err ~= lastError then
        lastError = err
        Print("dungeon pin error: " .. tostring(err))
    end
    self:SetPosition(entry.x, entry.y)
end

function UlRemedyDungeonPinMixin:CanSetWaypoint()
    local map = self:GetMap()
    return map ~= nil and C_Map.SetUserWaypoint ~= nil and C_Map.CanSetUserWaypointOnMap ~= nil
        and C_Map.CanSetUserWaypointOnMap(map:GetMapID())
end

function UlRemedyDungeonPinMixin:OnMouseEnter()
    local node = self.entry.node
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local title = node.name
    if node.label then title = title .. " (" .. node.label .. ")" end
    GameTooltip:AddLine(title, 1, 1, 1)
    AddLevelLines(node)
    if self:CanSetWaypoint() then
        GameTooltip:AddLine("Click to set a waypoint", 0.4, 0.8, 1)
    end
    GameTooltip:Show()
end

function UlRemedyDungeonPinMixin:OnMouseLeave()
    GameTooltip:Hide()
end

function UlRemedyDungeonPinMixin:OnMouseClickAction(button)
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
    if not UlRemedy.enabled.dungeons then return end

    local map = self:GetMap()
    local mapID = map:GetMapID()
    if not mapID then return end

    local gamePins = GameEntrances(mapID)
    local playerFaction = UnitFactionGroup("player")
    local placed, skipped = 0, 0
    for _, entry in ipairs(PositionsFor(mapID)) do
        local node = entry.node
        if node.faction == nil or node.faction == playerFaction then
            if NearGamePin(entry, gamePins) then
                skipped = skipped + 1
            else
                map:AcquirePin(PIN_TEMPLATE, entry)
                placed = placed + 1
            end
        end
    end
    lastDebug = { mapID = mapID, gamePins = #gamePins, placed = placed, skipped = skipped }
end

function UlRemedy.RefreshDungeonEntrances()
    if provider and WorldMapFrame and WorldMapFrame:IsShown() then
        provider:RefreshAllData()
    end
end

local function InstallProvider()
    HookGamePins()
    if provider or not WorldMapFrame or not WorldMapFrame.AddDataProvider then return end
    provider = CreateFromMixins(ProviderMixin)
    WorldMapFrame:AddDataProvider(provider)
end

------------------------------------------------------------------------
-- /ur dungeons and /ur dpins
------------------------------------------------------------------------

function UlRemedy.PrintDungeonList()
    local level = UnitLevel("player")
    local playerFaction = UnitFactionGroup("player")
    local list = {}
    for _, node in ipairs(DUNGEONS) do
        if node.faction == nil or node.faction == playerFaction then list[#list + 1] = node end
    end
    table.sort(list, function(a, b)
        if a.levels[1] ~= b.levels[1] then return a.levels[1] < b.levels[1] end
        return a.name < b.name
    end)
    Print("dungeons and raids for level " .. level .. " (yellow fits, green easy, orange soon, red too high, grey outgrown):")
    for _, node in ipairs(list) do
        local _, r, g, b = LevelFit(node.levels)
        local kind = node.kind == "raid" and " (raid)" or ""
        local pin = node.map and "" or "  (no entrance position known on Forever yet)"
        print(string.format("  %s%s %s|r  %s%s%s", ColorCode(r, g, b), LevelText(node.levels), node.name, node.zone or "", kind, pin))
    end
end

function UlRemedy.DungeonEntrancesDebug()
    local mapOpen = WorldMapFrame and WorldMapFrame:IsShown()
    local mapID = (mapOpen and WorldMapFrame:GetMapID()) or C_Map.GetBestMapForUnit("player")
    if not mapID then
        Print("no map to inspect.")
        return
    end
    local info = C_Map.GetMapInfo(mapID)
    local continentID = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(0.5, 0.5))
    local projected = PositionsFor(mapID)
    local gamePins = GameEntrances(mapID)
    local shown = 0
    if mapOpen then
        for _ in WorldMapFrame:EnumeratePinsByTemplate(PIN_TEMPLATE) do shown = shown + 1 end
    end
    Print(string.format("map %d (%s, type %s), continent %s", mapID, info and info.name or "?",
        info and tostring(info.mapType) or "?", tostring(continentID)))
    print(string.format("  entrances projected onto this map: %d, our pins shown: %d, game entrance pins: %d",
        #projected, shown, #gamePins))
    if lastDebug.mapID == mapID then
        print(string.format("  last refresh: placed %d, skipped %d (near a game pin)", lastDebug.placed, lastDebug.skipped))
    end
    for _, entry in ipairs(projected) do
        local near = NearGamePin(entry, gamePins)
        print(string.format("  %s at %.3f, %.3f%s", entry.node.name, entry.x, entry.y,
            near and (" (game draws: " .. tostring(near.name) .. ")") or ""))
    end
    for _, g in ipairs(gamePins) do
        print(string.format("  game: %s at %.3f, %.3f", tostring(g.name), g.x, g.y))
    end
    print("  provider installed: " .. tostring(provider ~= nil) .. ", enabled: " .. tostring(UlRemedy.enabled.dungeons)
        .. ", atlas Dungeon: " .. tostring(C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("Dungeon") ~= nil)
        .. ", last error: " .. tostring(lastError))
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LEVEL_UP")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        InstallProvider()
    elseif event == "PLAYER_LEVEL_UP" then
        -- Colors and dimming depend on the level; redraw if the map is open.
        UlRemedy.RefreshDungeonEntrances()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if acquiredInCombat then
            acquiredInCombat = false
            UlRemedy.RefreshDungeonEntrances()
        end
    end
end)
