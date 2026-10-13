-- Options: a window with one checkbox per feature, opened with /ur.
--
-- Built from BasicFrameTemplateWithInset and UICheckButtonTemplate so it
-- looks like the rest of the game's windows. The list of features comes
-- from Core (UlRemedy.FEATURES), so a new module only needs a line there.
-- Clicking a box goes through UlRemedy.SetFeature, the same path as the
-- chat command, so modules get notified the same way either route is used.
-- The window is closed by Escape (UISpecialFrames) and can be dragged.

local ROW_H = 30
local HEADER_H = 24
local LEFT = 16
local WIDTH = 520

local window
local rows = {}

local function CreateRow(parent, y, feature)
    local box = CreateFrame("CheckButton", "UlRemedyOption" .. feature.key, parent, "UICheckButtonTemplate")
    box:SetSize(26, 26)
    box:SetPoint("TOPLEFT", parent, "TOPLEFT", LEFT + 8, y)
    if box.Text then box.Text:SetText("") end
    box.key = feature.key
    box:SetScript("OnClick", function(self)
        UlRemedy.SetFeature(self.key, self:GetChecked() and true or false)
    end)

    local name = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    name:SetPoint("TOPLEFT", box, "TOPRIGHT", 4, -2)
    name:SetText(feature.label)
    name:SetJustifyH("LEFT")

    local desc = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -1)
    desc:SetPoint("RIGHT", parent, "RIGHT", -LEFT, 0)
    desc:SetJustifyH("LEFT")
    desc:SetWordWrap(false)
    desc:SetTextColor(0.7, 0.7, 0.7)
    desc:SetText(feature.desc)

    -- Clicking the name toggles too, like a settings panel.
    local hit = CreateFrame("Button", nil, parent)
    hit:SetPoint("LEFT", box, "RIGHT", 0, 0)
    hit:SetPoint("RIGHT", parent, "RIGHT", -LEFT, 0)
    hit:SetHeight(ROW_H - 2)
    hit:SetScript("OnClick", function() box:Click() end)

    return box
end

local function CreateHeader(parent, y, text)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", LEFT, y)
    label:SetText(text)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 0.82, 0, 0.25)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -2)
    line:SetPoint("RIGHT", parent, "RIGHT", -LEFT, 0)
end

-- Features grouped in the order Core lists the groups; anything with an
-- unknown group lands under "Other" at the end.
local function GroupedFeatures()
    local groups = {}
    local byName = {}
    for _, name in ipairs(UlRemedy.FEATURE_GROUPS or {}) do
        local g = { name = name, features = {} }
        groups[#groups + 1] = g
        byName[name] = g
    end
    for _, feature in ipairs(UlRemedy.FEATURES or {}) do
        local g = byName[feature.group or "Other"]
        if not g then
            g = { name = feature.group or "Other", features = {} }
            groups[#groups + 1] = g
            byName[g.name] = g
        end
        g.features[#g.features + 1] = feature
    end
    local kept = {}
    for _, g in ipairs(groups) do
        if #g.features > 0 then kept[#kept + 1] = g end
    end
    return kept
end

local function CreateWindow()
    local groups = GroupedFeatures()
    local height = 36 + 84
    for _, g in ipairs(groups) do
        height = height + HEADER_H + 6 + #g.features * ROW_H + 6
    end

    local f = CreateFrame("Frame", "UlRemedyOptionsFrame", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(WIDTH, height)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    tinsert(UISpecialFrames, "UlRemedyOptionsFrame")
    -- The template's close button goes through the panel manager, which
    -- ignores windows it does not manage; close directly instead.
    if f.CloseButton then f.CloseButton:SetScript("OnClick", function() f:Hide() end) end

    local title = f.TitleText or (f.TitleContainer and f.TitleContainer.TitleText)
    if title then title:SetText(UlRemedy.name .. " " .. UlRemedy.Version()) end

    local y = -32
    for _, g in ipairs(groups) do
        CreateHeader(f, y, g.name)
        y = y - HEADER_H - 6
        for _, feature in ipairs(g.features) do
            rows[feature.key] = CreateRow(f, y, feature)
            y = y - ROW_H
        end
        y = y - 6
    end

    -- Buttons for the actions that are not on/off switches.
    local actions = {
        { text = "Inventory",         fn = function() if UlRemedy.ToggleInventoryWindow then UlRemedy.ToggleInventoryWindow() end end },
        { text = "Reset windows",     fn = function() if UlRemedy.ResetWindowPositions then UlRemedy.ResetWindowPositions() end end },
        { text = "Reset vendor size", fn = function() if UlRemedy.ResetVendorWindow then UlRemedy.ResetVendorWindow() end end },
        { text = "Forget reagents",   fn = function() if UlRemedy.ResetReagentData then UlRemedy.ResetReagentData() end end },
    }
    local buttonW = math.floor((WIDTH - 2 * LEFT - (#actions - 1) * 8) / #actions)
    local previous
    for _, action in ipairs(actions) do
        local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        b:SetSize(buttonW, 22)
        if previous then
            b:SetPoint("LEFT", previous, "RIGHT", 8, 0)
        else
            b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", LEFT, 56)
        end
        b:SetText(action.text)
        b:SetScript("OnClick", action.fn)
        previous = b
    end

    -- Second row: the loot roll window's placement, cycled by one button,
    -- and a test roll to see where it lands.
    local sideLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sideLabel:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", LEFT, 36)
    sideLabel:SetText("Loot roll window:")
    f.sideButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.sideButton:SetSize(180, 22)
    f.sideButton:SetPoint("LEFT", sideLabel, "RIGHT", 8, 0)
    f.sideButton:SetScript("OnClick", function()
        if UlRemedy.CycleLootRollSide then UlRemedy.CycleLootRollSide() end
    end)
    local test = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    test:SetSize(100, 22)
    test:SetPoint("LEFT", f.sideButton, "RIGHT", 8, 0)
    test:SetText("Test roll")
    test:SetScript("OnClick", function()
        if UlRemedy.LootRollTest then UlRemedy.LootRollTest() end
    end)

    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOM", f, "BOTTOM", 0, 11)
    hint:SetText("Chat works too: /ur <feature> toggles, /ur help lists every command.")

    f:SetScript("OnShow", function() if UlRemedy.RefreshOptions then UlRemedy.RefreshOptions() end end)
    -- A new frame is visible from the start; hide it so the first toggle
    -- shows it instead of hiding it.
    f:Hide()
    return f
end

function UlRemedy.RefreshOptions()
    if not window or not window:IsShown() then return end
    for key, box in pairs(rows) do
        box:SetChecked(UlRemedy.enabled[key] and true or false)
    end
    if window.sideButton and UlRemedy.LootRollSideLabel then
        window.sideButton:SetText(UlRemedy.LootRollSideLabel())
    end
end

function UlRemedy.ToggleOptions()
    if not window then window = CreateWindow() end
    if window:IsShown() then
        window:Hide()
    else
        window:Show()
    end
end
