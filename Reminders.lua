-- Reminders: a message to yourself at the top of the screen, there until
-- you tick it off.
--
-- Two frames. The panel: top centre of the screen, one row per reminder
-- with a checkbox in front, oldest at the top; ticking the box removes
-- the row, nothing else does (no timeout, no hiding in combat). Dragged
-- anywhere, it remembers where it sits. The window: opened from the
-- minimap menu (Reminders), the + on the panel, or /ur remind; a line to
-- type a new reminder into, a tick for making it one every character
-- sees, the same rows with the same checkboxes, and a button that puts
-- the panel back at the top centre. No other commands: the feature
-- toggle (/ur reminders) is Core's, like every other feature's.
--
-- A reminder belongs to the character it was made on, since most of them
-- are chores for that character (sell this, visit that trainer). One
-- made with "Every character" ticked is seen on all of them until it is
-- ticked off on any. Kept in UlRemedyForeverRemindersDB, which Core's
-- settings pruning never touches.
--
-- The text is shown as typed: pipes are doubled so a stray colour code
-- cannot run into the row. No secret values are involved, the text is
-- the player's own.

local DIALOG_NAME = "UlRemedyRemindersWindow"
local MAX_LETTERS = 160
local PANEL_W = 380
local WINDOW_W = 420
local ROW_MIN_H = 24
local TOP_OFFSET = -40          -- below the top edge, above the zone text
local DONE_DELAY = 0.7          -- a ticked row stays this long, dimmed, before it goes
local SHARED_TAG = "|cff8ab4ff(all)|r "

local db
local panel, window
local lastError

local function Say(text)
    print(UlRemedy.name .. ": " .. text)
end

local function Report(err)
    if err == lastError then return end
    lastError = err
    Say("reminders: " .. tostring(err))
end

local function Enabled()
    return UlRemedy.enabled and UlRemedy.enabled.reminders
end

------------------------------------------------------------------------
-- Data
------------------------------------------------------------------------

local function CharKey()
    local name = UnitName("player") or "?"
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    if not realm or realm == "" then
        realm = (GetRealmName() or ""):gsub("%s+", "")
    end
    return name .. "-" .. realm, name
end

local function InitDB()
    if not UlRemedyForeverRemindersDB then UlRemedyForeverRemindersDB = {} end
    db = UlRemedyForeverRemindersDB
    db.version = 1
    db.chars = db.chars or {}
    db.all = db.all or {}
end

local function MyList(create)
    if not db then return nil end
    local key = CharKey()
    if not db.chars[key] and create then db.chars[key] = {} end
    return db.chars[key]
end

-- Every reminder this character should see: its own, then the shared
-- ones, each in the order made. Each entry carries the list it lives in
-- so ticking it off finds it again.
local function Visible()
    local out = {}
    local mine = MyList(false)
    if mine then
        for _, r in ipairs(mine) do out[#out + 1] = { rec = r, list = mine } end
    end
    if db then
        for _, r in ipairs(db.all) do out[#out + 1] = { rec = r, list = db.all, shared = true } end
    end
    return out
end

local function Clean(text)
    text = strtrim(text or "")
    text = text:gsub("|", "||")
    if #text > MAX_LETTERS then text = text:sub(1, MAX_LETTERS) end
    return text
end

local Refresh

local function Add(text, shared)
    text = Clean(text)
    if text == "" then return false end
    if not db then InitDB() end
    local _, name = CharKey()
    local list = shared and db.all or MyList(true)
    list[#list + 1] = { text = text, at = time(), by = name }
    Refresh()
    return true
end

local function Remove(list, rec)
    for i, r in ipairs(list) do
        if r == rec then
            table.remove(list, i)
            return true
        end
    end
    return false
end

------------------------------------------------------------------------
-- Rows, shared by the panel and the window
------------------------------------------------------------------------

local function MakeRow(parent, rightInset)
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("LEFT", 6, 0)
    row:SetPoint("RIGHT", -rightInset, 0)
    row.box = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.box:SetSize(24, 24)
    row.box:SetPoint("TOPLEFT", 0, 0)
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.text:SetPoint("TOPLEFT", row.box, "TOPRIGHT", 4, -4)
    row.text:SetPoint("RIGHT", 0, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetJustifyV("TOP")
    row.text:SetWordWrap(true)
    row.box:SetScript("OnClick", function(self)
        local entry = row.entry
        if not entry or row.done then
            self:SetChecked(false)
            return
        end
        row.done = true
        self:SetChecked(true)
        row.text:SetTextColor(0.5, 0.5, 0.5)
        if PlaySound and SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON then
            pcall(PlaySound, SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        end
        C_Timer.After(DONE_DELAY, function()
            Remove(entry.list, entry.rec)
            Refresh()
        end)
    end)
    row.box:SetScript("OnEnter", function(self)
        local entry = row.entry
        if not entry then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Tick off when done")
        local when = entry.rec.at and date("%Y-%m-%d %H:%M", entry.rec.at) or "?"
        GameTooltip:AddLine((entry.shared and ("For every character, made on " .. (entry.rec.by or "?") .. ", ") or "Made ") .. when .. ".", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    row.box:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

-- Lays the entries out as rows from startY down. Returns the height used.
local function FillRows(parent, rows, entries, rightInset, startY)
    local y = startY
    for i, entry in ipairs(entries) do
        local row = rows[i]
        if not row then
            row = MakeRow(parent, rightInset)
            rows[i] = row
        end
        row.entry = entry
        row.done = false
        row.box:SetChecked(false)
        row.text:SetTextColor(1, 1, 1)
        row.text:SetText((entry.shared and SHARED_TAG or "") .. entry.rec.text)
        local h = math.max(ROW_MIN_H, (row.text:GetStringHeight() or 0) + 8)
        row:SetHeight(h)
        row:SetPoint("TOP", 0, y)
        row:Show()
        y = y - h - 2
    end
    for i = #entries + 1, #rows do
        rows[i].entry = nil
        rows[i]:Hide()
    end
    return startY - y
end

------------------------------------------------------------------------
-- Panel at the top of the screen
------------------------------------------------------------------------

local function SavePosition()
    if not panel or not db then return end
    local cx = panel:GetCenter()
    local ux = UIParent:GetCenter()
    local top, utop = panel:GetTop(), UIParent:GetTop()
    if not (cx and ux and top and utop) then return end
    db.pos = { x = cx - ux, y = top - utop }
    panel:ClearAllPoints()
    panel:SetPoint("TOP", UIParent, "TOP", db.pos.x, db.pos.y)
end

local function PlacePanel()
    if not panel then return end
    panel:ClearAllPoints()
    local pos = db and db.pos
    if pos and pos.x and pos.y then
        panel:SetPoint("TOP", UIParent, "TOP", pos.x, pos.y)
    else
        panel:SetPoint("TOP", UIParent, "TOP", 0, TOP_OFFSET)
    end
end

local ToggleWindow

local function CreatePanel()
    local f = CreateFrame("Frame", "UlRemedyRemindersFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(PANEL_W, ROW_MIN_H + 16)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition()
    end)
    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        f:SetBackdropColor(0, 0, 0, 0.72)
        f:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.9)
    end

    -- A small + at the corner opens the window for the next one.
    local add = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    add:SetSize(20, 20)
    add:SetPoint("TOPRIGHT", -4, -4)
    add:SetText("+")
    add:SetScript("OnClick", function() ToggleWindow(true) end)
    add:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Reminders")
        GameTooltip:AddLine("Opens the window to add one. Drag the panel to move it.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    add:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.rows = {}
    return f
end

local function RefreshPanel(entries)
    if not Enabled() or #entries == 0 then
        if panel then panel:Hide() end
        return
    end
    if not panel then
        panel = CreatePanel()
        PlacePanel()
    end
    local used = FillRows(panel, panel.rows, entries, 30, -8)
    panel:SetHeight(used + 14)
    panel:Show()
end

------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------

local WIN_TOP = 32       -- title bar
local WIN_INPUT_H = 54   -- the input line and the tick under it
local WIN_BOTTOM = 44    -- footer button and note

local function CreateWindow()
    local f = CreateFrame("Frame", DIALOG_NAME, UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(WINDOW_W, WIN_TOP + WIN_INPUT_H + ROW_MIN_H + WIN_BOTTOM)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    tinsert(UISpecialFrames, DIALOG_NAME)
    if f.CloseButton then f.CloseButton:SetScript("OnClick", function() f:Hide() end) end

    local title = f.TitleText or (f.TitleContainer and f.TitleContainer.TitleText)
    if title then title:SetText(UlRemedy.name .. ": Reminders") end

    -- Input line: type, Enter or Add.
    local input = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    input:SetSize(WINDOW_W - 14 - 14 - 70, 22)
    input:SetPoint("TOPLEFT", 20, -(WIN_TOP + 6))
    input:SetAutoFocus(false)
    input:SetMaxLetters(MAX_LETTERS)
    f.input = input

    local addButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    addButton:SetSize(60, 22)
    addButton:SetPoint("LEFT", input, "RIGHT", 6, 0)
    addButton:SetText(ADD or "Add")

    local shared = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    shared:SetSize(24, 24)
    shared:SetPoint("TOPLEFT", input, "BOTTOMLEFT", -6, -2)
    shared.label = shared:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    shared.label:SetPoint("LEFT", shared, "RIGHT", 2, 0)
    shared.label:SetText("Every character sees it")
    f.shared = shared

    local function Submit()
        if Add(input:GetText(), shared:GetChecked()) then
            input:SetText("")
            shared:SetChecked(false)
        end
        input:SetFocus()
    end
    input:SetScript("OnEnterPressed", Submit)
    input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    addButton:SetScript("OnClick", Submit)

    f.header = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.header:SetPoint("TOPLEFT", 14, -(WIN_TOP + WIN_INPUT_H + 2))
    f.header:SetText("Waiting")

    f.empty = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.empty:SetPoint("TOPLEFT", 36, -(WIN_TOP + WIN_INPUT_H + 24))
    f.empty:SetTextColor(0.6, 0.6, 0.6)
    f.empty:SetText("Nothing waiting.")

    local reset = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    reset:SetSize(150, 22)
    reset:SetPoint("BOTTOMRIGHT", -14, 10)
    reset:SetText("Panel to top centre")
    reset:SetScript("OnClick", function()
        if db then db.pos = nil end
        PlacePanel()
    end)

    f.footer = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.footer:SetPoint("BOTTOMLEFT", 14, 14)
    f.footer:SetPoint("RIGHT", reset, "LEFT", -8, 0)
    f.footer:SetJustifyH("LEFT")
    f.footer:SetTextColor(0.6, 0.6, 0.6)
    f.footer:SetText("The panel at the top of the screen can be dragged.")

    f.rows = {}
    f:SetScript("OnShow", function() Refresh() end)
    f:Hide()
    return f
end

local function RefreshWindow(entries)
    if not window or not window:IsShown() then return end
    local rowTop = -(WIN_TOP + WIN_INPUT_H + 22)
    local used = FillRows(window, window.rows, entries, 14, rowTop)
    if #entries == 0 then window.empty:Show() else window.empty:Hide() end
    window:SetHeight(WIN_TOP + WIN_INPUT_H + 22 + math.max(used, ROW_MIN_H) + WIN_BOTTOM)
end

ToggleWindow = function(show)
    if not Enabled() then
        Say("reminders are off. /ur reminders turns them on.")
        return
    end
    if not window then window = CreateWindow() end
    if show == nil then show = not window:IsShown() end
    if show then
        window:Show()
        window.input:SetFocus()
    else
        window:Hide()
    end
end

Refresh = function()
    if not db then return end
    local entries = Visible()
    RefreshPanel(entries)
    RefreshWindow(entries)
end

------------------------------------------------------------------------
-- Hooks
------------------------------------------------------------------------

-- /ur remind, and the minimap menu row
function UlRemedy.ToggleRemindersWindow()
    ToggleWindow()
end

function UlRemedy.RefreshReminders()
    if not Enabled() and window then window:Hide() end
    Refresh()
end

if UlRemedy.Register then
    UlRemedy.Register({
        id = UlRemedy.name .. ".reminders",
        title = "Reminders",
        icon = "Interface\\Icons\\INV_Misc_Note_01",
        open = function() ToggleWindow() end,
    })
end

local frame = CreateFrame("Frame", "UlRemedyRemindersEventFrame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == UlRemedy.name then
        InitDB()
    elseif event == "PLAYER_LOGIN" then
        if not db then InitDB() end
        local ok, err = pcall(Refresh)
        if not ok then Report(err) end
    end
end)
