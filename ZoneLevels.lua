-- Zone Levels: the level range and territory of a zone under its name
-- when the mouse rests on it on a continent map, colored for the
-- player's level.
--
-- The retail map already has the mechanism: an area label frame that
-- shows the zone name and, when C_Map.GetMapLevels knows a range, a
-- "Level x-y" line under it. The Forever client answers 0 for every zone
-- (probe 14.10.2026), so the line stays empty, and that is where ours
-- goes: the label's EvaluateLabels is post-hooked and the empty
-- description filled from UlRemedy.ZONES (ZoneData.lua, generated from
-- the ForeverChanges world map). A description the game wrote itself is
-- left alone, so the feature steps aside the day the client gets data.
--
-- If the area label frame cannot be found, a plain text of our own at the
-- bottom of the map canvas does the same job from the cursor position.
--
-- Zone names are bound to map IDs the first time they are needed, from
-- the zone maps under the player's world map. /ur zones prints the list
-- and the zone maps the data does not know.

local ZONE_TYPE = (Enum and Enum.UIMapType and Enum.UIMapType.Zone) or 3

local zoneMaps          -- list of { mapID=, name=, zone= or nil }, nil until bound
local gameLabel         -- the game's area label frame, once found
local ownLabel          -- our fallback frame
local lastError

local function Say(text)
    print(UlRemedy.name .. ": " .. text)
end

------------------------------------------------------------------------
-- Text and color
------------------------------------------------------------------------

-- How a range relates to the player's level, as a word and a color.
-- Below the range: red or orange (the game's own difficulty colors for
-- that gap). Inside: yellow. Just above: green. Far above: grey.
local function LevelFit(levels, playerLevel)
    local lo, hi = levels[1], levels[2]
    playerLevel = playerLevel or UnitLevel("player")
    if playerLevel < lo then
        if lo - playerLevel >= 5 then return "too high", 1, 0.1, 0.1 end
        return "soon", 1, 0.5, 0.25
    elseif playerLevel <= hi then
        return "fits", 1, 1, 0
    elseif playerLevel - hi <= 4 then
        return "easy", 0.25, 0.75, 0.25
    end
    return "outgrown", 0.5, 0.5, 0.5
end

local function RangeText(levels)
    if levels[1] == levels[2] then return "Level " .. levels[1] end
    return "Level " .. levels[1] .. "-" .. levels[2]
end

-- Colored "Level x-y" for a zone entry, with the territory in grey after
-- it, plus the fit word.
local function ZoneText(zone, playerLevel)
    local fit, r, g, b = LevelFit(zone.levels, playerLevel)
    local text = string.format("|cff%02x%02x%02x%s|r", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
        math.floor(b * 255 + 0.5), RangeText(zone.levels))
    if zone.territory then text = text .. ", |cffb0b0b0" .. zone.territory .. "|r" end
    return text, fit
end

------------------------------------------------------------------------
-- Zone maps
------------------------------------------------------------------------

-- The top map above the player's current one (the world map, or the
-- continent if there is nothing above it).
local function TopMap()
    local mapID = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not mapID then return nil end
    for _ = 1, 10 do
        local info = C_Map.GetMapInfo(mapID)
        if not info or not info.parentMapID or info.parentMapID == 0 then return mapID end
        mapID = info.parentMapID
    end
    return mapID
end

-- Every zone map under the top map, bound to the data by name.
local function BindZones()
    if zoneMaps then return zoneMaps end
    local top = TopMap()
    if not top or not C_Map.GetMapChildrenInfo then return nil end
    local ok, children = pcall(C_Map.GetMapChildrenInfo, top, ZONE_TYPE, true)
    if not ok or type(children) ~= "table" or #children == 0 then return nil end
    zoneMaps = {}
    for _, child in ipairs(children) do
        zoneMaps[#zoneMaps + 1] = { mapID = child.mapID, name = child.name, zone = UlRemedy.ZONES[child.name] }
    end
    table.sort(zoneMaps, function(a, b)
        local la = a.zone and a.zone.levels[1] or 999
        local lb = b.zone and b.zone.levels[1] or 999
        if la ~= lb then return la < lb end
        return a.name < b.name
    end)
    return zoneMaps
end

------------------------------------------------------------------------
-- The game's own label
------------------------------------------------------------------------

-- The retail area label provider keeps its frame in Label (seen on
-- Forever: a provider with the fields Label and owningMap).
local function FindGameLabel()
    if not (WorldMapFrame and type(WorldMapFrame.dataProviders) == "table") then return nil end
    for provider in pairs(WorldMapFrame.dataProviders) do
        if type(provider) == "table" then
            local label = provider.Label or provider.AreaLabel
            if type(label) == "table" and type(label.EvaluateLabels) == "function"
                and label.Name and label.Description then
                return label
            end
        end
    end
    return nil
end

-- Runs after the game has laid out its label. Fills the description
-- only when the game left it empty, and clears our text again when the
-- name changes to a zone we do not know.
local function AfterEvaluate(label)
    local name = label.Name:GetText()
    local desc = label.Description
    local current = desc:GetText()
    if current ~= nil and current ~= "" and current ~= label.UlRemedyText then return end
    local zone = UlRemedy.enabled.zonelevels and name and UlRemedy.ZONES[name]
    local text = zone and ZoneText(zone) or nil
    if text == label.UlRemedyText and current == text then return end
    desc:SetText(text or "")
    label.UlRemedyText = text
    if text then desc:Show() end
end

local function HookGameLabel()
    if gameLabel then return true end
    gameLabel = FindGameLabel()
    if not gameLabel then return false end
    hooksecurefunc(gameLabel, "EvaluateLabels", function(label)
        local ok, err = pcall(AfterEvaluate, label)
        if not ok and err ~= lastError then
            lastError = err
            Say("zone level error: " .. tostring(err))
        end
    end)
    return true
end

------------------------------------------------------------------------
-- Fallback: our own text at the bottom of the canvas
------------------------------------------------------------------------

local function CursorOnMap()
    if WorldMapFrame.GetNormalizedCursorPosition then
        return WorldMapFrame:GetNormalizedCursorPosition()
    end
    local canvas = WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas()
    if not canvas then return nil end
    local cx, cy = GetCursorPosition()
    local scale = canvas:GetEffectiveScale()
    local left, top = canvas:GetLeft(), canvas:GetTop()
    local w, h = canvas:GetWidth(), canvas:GetHeight()
    if not (left and top and w and h and w > 0 and h > 0) then return nil end
    return (cx / scale - left) / w, (top - cy / scale) / h
end

local function ZoneUnderCursor()
    if not (WorldMapFrame:IsShown() and C_Map.GetMapInfoAtPosition) then return nil end
    local mapID = WorldMapFrame:GetMapID()
    local x, y = CursorOnMap()
    if not x or x < 0 or x > 1 or y < 0 or y > 1 then return nil end
    local info = C_Map.GetMapInfoAtPosition(mapID, x, y)
    if not info or info.mapID == mapID then return nil end
    return info.name, UlRemedy.ZONES[info.name]
end

local function CreateOwnLabel()
    local container = (WorldMapFrame.GetCanvasContainer and WorldMapFrame:GetCanvasContainer()) or WorldMapFrame.ScrollContainer
    if not container then return nil end
    local f = CreateFrame("Frame", nil, container)
    f:SetAllPoints()
    f:SetFrameStrata("HIGH")
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.text:SetPoint("BOTTOM", container, "BOTTOM", 0, 28)
    local elapsed = 0
    f:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed < 0.1 then return end
        elapsed = 0
        if not UlRemedy.enabled.zonelevels then self.text:SetText("") return end
        local ok, name, zone = pcall(ZoneUnderCursor)
        if not ok then
            if name ~= lastError then lastError = name; Say("zone level error: " .. tostring(name)) end
            self.text:SetText("")
        elseif zone then
            self.text:SetText(name .. ": " .. ZoneText(zone))
        else
            self.text:SetText("")
        end
    end)
    return f
end

------------------------------------------------------------------------
-- Install and refresh
------------------------------------------------------------------------

local function Install()
    if not WorldMapFrame then return end
    if HookGameLabel() then return end
    if not ownLabel then ownLabel = CreateOwnLabel() end
end

function UlRemedy.RefreshZoneLevels()
    Install()
    if ownLabel then ownLabel:SetShown(not gameLabel and UlRemedy.enabled.zonelevels and true or false) end
end

-- /ur zones
function UlRemedy.ZoneLevelsDebug()
    local maps = BindZones()
    if not maps then
        Say("zone maps not available yet; open the map once and try again.")
        return
    end
    local mode = gameLabel and "game label hooked" or (ownLabel and "own label" or "no label yet")
    Say(string.format("%d zone maps, %s. Ranges and territory from the Forever client (via ForeverChanges).", #maps, mode))
    local unknown = {}
    for _, m in ipairs(maps) do
        if m.zone then
            local text, fit = ZoneText(m.zone)
            print(string.format("  %s (%d): %s, %s", m.name, m.mapID, text, fit))
        else
            unknown[#unknown + 1] = m.name .. " (" .. m.mapID .. ")"
        end
    end
    if #unknown > 0 then
        print("  no range in the data: " .. table.concat(unknown, ", "))
    end
    print("  last error: " .. tostring(lastError))
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function()
    Install()
    -- The map's providers may be added after login; try again when the
    -- map is first shown, and prefer the game's label if it has appeared.
    if not gameLabel and WorldMapFrame and WorldMapFrame.HookScript then
        WorldMapFrame:HookScript("OnShow", function()
            if not gameLabel and ownLabel then
                if HookGameLabel() then ownLabel:Hide() end
            else
                Install()
            end
        end)
    end
end)
