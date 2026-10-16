-- Minimap Button: one button on the minimap for the whole Ul family.
--
-- Left-click opens a menu with rows for the inventory browser and the
-- playtime window, and one per installed sibling addon; right-click
-- opens this addon's options (the options window is not in the menu,
-- the right click is its row). Hovering lists them. This addon is the
-- master: it owns the button and a registry, and the sibling addons
-- (UlDungeonCompanion, UlSource) call UlRemedy.Register at login with an
-- id, a title, an icon and a function that opens their window. The
-- button knows nothing about them beyond that, so a new sibling needs no
-- change here. Dragging moves the button around the minimap's edge; the
-- angle is saved in UlRemedyForeverDB.minimapAngle (Core exempts that key
-- from its cleanup of unknown keys).
--
-- Own code, no LibDBIcon or LibDataBroker. The menu is a small frame of
-- ours rather than the client's MenuUtil, so there is one code path to
-- test and nothing that depends on the retail menu system being present
-- and untainted on Forever. The button is an unprotected frame of ours,
-- so moving it in combat is allowed. Textures are Blizzard's own minimap
-- button ring and background, the same ones every minimap button uses.

local BUTTON_SIZE = 31
local DEFAULT_ANGLE = 220     -- degrees, counter-clockwise from the right; lower left
local EDGE = 5                -- how far outside the minimap's edge the button sits
local MENU_W = 180
local ROW_H = 22
local MENU_PAD = 8
local MENU_TITLE_H = 18
local MENU_GRACE = 0.6        -- seconds the menu stays after the mouse leaves it

local ICON = "Interface\\AddOns\\UlRemedyForever\\media\\icon"

local button, menu
local dragging = false
local registered = {}         -- in registration order
local byId = {}
local lastError
local BuildMenu               -- defined below, used by Register

local function Enabled()
    return UlRemedy.enabled and UlRemedy.enabled.minimap
end

------------------------------------------------------------------------
-- Registry
------------------------------------------------------------------------

-- Called by the sibling addons at PLAYER_LOGIN. Registering the same id
-- again replaces the entry, so a sibling can update its open function.
function UlRemedy.Register(entry)
    if type(entry) ~= "table" or type(entry.id) ~= "string" or type(entry.open) ~= "function" then
        return false
    end
    local rec = byId[entry.id]
    if not rec then
        rec = { id = entry.id }
        byId[entry.id] = rec
        registered[#registered + 1] = rec
    end
    rec.title = type(entry.title) == "string" and entry.title or entry.id
    rec.icon = type(entry.icon) == "string" and entry.icon or nil
    rec.open = entry.open
    if menu and menu:IsShown() then BuildMenu() end
    return true
end

-- The rows in the order they arrived: this addon's own windows first
-- (registered below, at file load), then the siblings, which register at
-- PLAYER_LOGIN. The options window is not listed: the right click is its row.
local function Entries()
    local list = {}
    for _, rec in ipairs(registered) do
        if rec.id ~= UlRemedy.name then list[#list + 1] = rec end
    end
    return list
end

-- The inventory browser is a window of its own and gets a row. The
-- function is resolved at click time, since InventoryTracker.lua loads
-- after this file.
UlRemedy.Register({
    id = UlRemedy.name .. ".inventory",
    title = "Inventory",
    icon = "Interface\\Icons\\INV_Misc_Bag_10",
    open = function()
        if UlRemedy.ToggleInventoryWindow then UlRemedy.ToggleInventoryWindow() end
    end,
})

-- The playtime window, one bar per character.
UlRemedy.Register({
    id = UlRemedy.name .. ".playtime",
    title = "Playtime",
    icon = "Interface\\Icons\\INV_Misc_PocketWatch_01",
    open = function()
        if UlRemedy.TogglePlaytimeWindow then UlRemedy.TogglePlaytimeWindow() end
    end,
})

------------------------------------------------------------------------
-- Position on the minimap's edge
------------------------------------------------------------------------

local function Angle()
    local a = UlRemedyForeverDB and tonumber(UlRemedyForeverDB.minimapAngle)
    return a or DEFAULT_ANGLE
end

local function SaveAngle(a)
    if UlRemedyForeverDB then UlRemedyForeverDB.minimapAngle = a end
end

-- Minimap addons that square the minimap define GetMinimapShape.
local function Shape()
    if type(GetMinimapShape) == "function" then
        local ok, s = pcall(GetMinimapShape)
        if ok and type(s) == "string" then return s end
    end
    return "ROUND"
end

local function ApplyPosition()
    if not button or not Minimap then return end
    local a = math.rad(Angle())
    local w = Minimap:GetWidth() / 2 + EDGE
    local h = Minimap:GetHeight() / 2 + EDGE
    local x, y = math.cos(a), math.sin(a)
    if Shape() == "SQUARE" then
        -- Push the point out to the square's edge instead of the circle's.
        local q = 1 / math.max(math.abs(x), math.abs(y))
        x, y = x * q, y * q
    end
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x * w, y * h)
end

-- While dragging, the angle follows the cursor around the minimap's center.
local function FollowCursor()
    local mx, my = Minimap:GetCenter()
    if not mx then return end
    local scale = Minimap:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    cx, cy = cx / scale, cy / scale
    local a = math.deg(math.atan2(cy - my, cx - mx))
    SaveAngle(a % 360)
    ApplyPosition()
end

------------------------------------------------------------------------
-- Menu
------------------------------------------------------------------------

local function OpenEntry(rec)
    if not rec or not rec.open then return end
    local ok, err = pcall(rec.open)
    if not ok then
        print(UlRemedy.name .. ": " .. tostring(rec.title) .. " could not open: " .. tostring(err))
    end
end

local function CreateMenu()
    local f = CreateFrame("Frame", "UlRemedyMinimapMenu", UIParent, "BackdropTemplate")
    f:SetFrameStrata("TOOLTIP")
    f:SetClampedToScreen(true)
    f:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0.07, 0.06, 0.05, 0.95)
    f:SetBackdropBorderColor(0.8, 0.8, 0.8, 1)
    f.rows = {}

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", MENU_PAD + 4, -MENU_PAD)
    f.title:SetText("Ul addons")

    -- Closes itself a moment after the mouse has left both it and the button.
    f:SetScript("OnUpdate", function(self, elapsed)
        if self:IsMouseOver() or (button and button:IsMouseOver()) then
            self.away = 0
        else
            self.away = (self.away or 0) + elapsed
            if self.away > MENU_GRACE then self:Hide() end
        end
    end)
    f:SetScript("OnShow", function(self) self.away = 0 end)
    f:Hide()
    tinsert(UISpecialFrames, "UlRemedyMinimapMenu")
    return f
end

local function GetRow(i)
    local row = menu.rows[i]
    if row then return row end
    row = CreateFrame("Button", nil, menu)
    row:SetHeight(ROW_H)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(16, 16)
    row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.text:SetPoint("LEFT", row, "LEFT", 26, 0)
    row.text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.text:SetJustifyH("LEFT")

    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.12)

    row:SetScript("OnClick", function(self)
        menu:Hide()
        OpenEntry(self.rec)
    end)
    menu.rows[i] = row
    return row
end

BuildMenu = function()
    local list = Entries()
    local y = -(MENU_PAD + MENU_TITLE_H)
    for i, rec in ipairs(list) do
        local row = GetRow(i)
        row.rec = rec
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", menu, "TOPLEFT", MENU_PAD, y)
        row:SetPoint("RIGHT", menu, "RIGHT", -MENU_PAD, 0)
        if rec.icon then
            row.icon:SetTexture(rec.icon)
            row.icon:Show()
        else
            row.icon:Hide()
        end
        row.text:SetText(rec.title)
        row:Show()
        y = y - ROW_H
    end
    if #list == 0 then
        local row = GetRow(1)
        row.rec = nil
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", menu, "TOPLEFT", MENU_PAD, y)
        row:SetPoint("RIGHT", menu, "RIGHT", -MENU_PAD, 0)
        row.icon:Hide()
        row.text:SetText("|cff808080No other Ul addons installed|r")
        row:Show()
        y = y - ROW_H
    end
    for i = math.max(#list, 1) + 1, #menu.rows do menu.rows[i]:Hide() end
    menu:SetSize(MENU_W, -y + MENU_PAD)
end

local function ToggleMenu()
    if not menu then menu = CreateMenu() end
    if menu:IsShown() then
        menu:Hide()
        return
    end
    BuildMenu()
    menu:ClearAllPoints()
    -- Open towards the screen's center so it does not hang off the edge.
    local bx = button:GetCenter()
    local onRight = bx and (bx * button:GetEffectiveScale() > UIParent:GetWidth() * UIParent:GetEffectiveScale() / 2)
    if onRight then
        menu:SetPoint("TOPRIGHT", button, "BOTTOMLEFT", 4, 0)
    else
        menu:SetPoint("TOPLEFT", button, "BOTTOMRIGHT", -4, 0)
    end
    menu:Show()
end

------------------------------------------------------------------------
-- Button
------------------------------------------------------------------------

local function ShowTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine(UlRemedy.name .. " " .. UlRemedy.Version())
    GameTooltip:AddLine("Left-click: Ul addons menu", 1, 1, 1)
    GameTooltip:AddLine("Right-click: options", 1, 1, 1)
    GameTooltip:AddLine("Drag: move around the minimap", 1, 1, 1)
    local list = Entries()
    if #list > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("In the menu:", 1, 0.82, 0)
        for _, rec in ipairs(list) do
            GameTooltip:AddLine("  " .. rec.title, 0.8, 0.8, 0.8)
        end
    end
    GameTooltip:Show()
end

local function CreateButton()
    local b = CreateFrame("Button", "UlRemedyMinimapButton", Minimap)
    b:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:SetClampedToScreen(true)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")

    -- Blizzard's minimap button layout: a round background, the icon on
    -- top, and the ring border drawn over both.
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20)
    bg:SetPoint("TOPLEFT", b, "TOPLEFT", 7, -5)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetPoint("TOPLEFT", b, "TOPLEFT", 7, -6)
    icon:SetTexture(ICON)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.icon = icon

    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    b:SetScript("OnEnter", ShowTooltip)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnDragStart", function(self)
        dragging = true
        GameTooltip:Hide()
        if menu then menu:Hide() end
        self:SetScript("OnUpdate", FollowCursor)
    end)
    b:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        dragging = false
    end)
    b:SetScript("OnClick", function(self, mouseButton)
        if dragging then return end
        if mouseButton == "RightButton" then
            if menu then menu:Hide() end
            if UlRemedy.ToggleOptions then UlRemedy.ToggleOptions() end
        else
            ToggleMenu()
        end
    end)
    return b
end

local function RefreshUnsafe()
    if not button then
        if not Minimap then return end
        button = CreateButton()
        -- Follows the minimap when something resizes it.
        Minimap:HookScript("OnSizeChanged", ApplyPosition)
    end
    if Enabled() then
        ApplyPosition()
        button:Show()
    else
        button:Hide()
        if menu then menu:Hide() end
    end
end

function UlRemedy.RefreshMinimapButton()
    local ok, err = pcall(RefreshUnsafe)
    if not ok and err ~= lastError then
        lastError = err
        print(UlRemedy.name .. ": minimap button could not be placed: " .. tostring(err))
    end
end

function UlRemedy.HubDebug()
    print(UlRemedy.name .. ": minimap button " .. (Enabled() and "on" or "off")
        .. ", angle " .. math.floor(Angle() + 0.5) .. ", minimap shape " .. Shape()
        .. ", addons in the menu " .. #Entries() .. ":")
    for _, rec in ipairs(Entries()) do
        print("  " .. rec.id .. " (" .. rec.title .. ")" .. (rec.icon and "" or ", no icon"))
    end
    if button then
        print("  button shown " .. tostring(button:IsShown()) .. ", size " .. math.floor(Minimap:GetWidth()) .. "x" .. math.floor(Minimap:GetHeight()))
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self)
    UlRemedy.RefreshMinimapButton()
    self:UnregisterEvent("PLAYER_LOGIN")
end)
