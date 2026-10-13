-- Options: a window with one checkbox per feature, opened with /ur.
--
-- Built from BasicFrameTemplateWithInset and UICheckButtonTemplate so it
-- looks like the rest of the game's windows. The list of features comes
-- from Core (UlRemedy.FEATURES), so a new module only needs a line there.
-- Clicking a box goes through UlRemedy.SetFeature, the same path as the
-- chat command, so modules get notified the same way either route is used.
-- The window is closed by Escape (UISpecialFrames) and can be dragged.

local ROW_H = 34
local LEFT = 16
local WIDTH = 520

local window
local rows = {}

local function CreateRow(parent, index, feature)
    local y = -36 - (index - 1) * ROW_H
    local box = CreateFrame("CheckButton", "UlRemedyOption" .. feature.key, parent, "UICheckButtonTemplate")
    box:SetSize(26, 26)
    box:SetPoint("TOPLEFT", parent, "TOPLEFT", LEFT, y - 2)
    if box.Text then box.Text:SetText("") end
    box.key = feature.key
    box:SetScript("OnClick", function(self)
        UlRemedy.SetFeature(self.key, self:GetChecked() and true or false)
    end)

    local name = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    name:SetPoint("TOPLEFT", box, "TOPRIGHT", 4, -3)
    name:SetText(feature.label)
    name:SetJustifyH("LEFT")

    local desc = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -1)
    desc:SetPoint("RIGHT", parent, "RIGHT", -LEFT, 0)
    desc:SetJustifyH("LEFT")
    desc:SetTextColor(0.7, 0.7, 0.7)
    desc:SetText(feature.desc)

    -- Clicking the name toggles too, like a settings panel.
    local hit = CreateFrame("Button", nil, parent)
    hit:SetPoint("LEFT", box, "RIGHT", 0, 0)
    hit:SetPoint("RIGHT", parent, "RIGHT", -LEFT, 0)
    hit:SetHeight(ROW_H - 4)
    hit:SetScript("OnClick", function() box:Click() end)

    return box
end

local function CreateWindow()
    local features = UlRemedy.FEATURES or {}
    local height = 36 + #features * ROW_H + 58

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

    local title = f.TitleText or (f.TitleContainer and f.TitleContainer.TitleText)
    if title then title:SetText(UlRemedy.name .. " " .. UlRemedy.Version()) end

    for i, feature in ipairs(features) do
        rows[feature.key] = CreateRow(f, i, feature)
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
            b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", LEFT, 30)
        end
        b:SetText(action.text)
        b:SetScript("OnClick", action.fn)
        previous = b
    end

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
end

function UlRemedy.ToggleOptions()
    if not window then window = CreateWindow() end
    if window:IsShown() then
        window:Hide()
    else
        window:Show()
    end
end
