-- Trainer Preview: what your class trainer has for you, seen from anywhere.
--
-- The client knows nothing about a trainer's list until you stand at one,
-- so the list is learned there. Every service the trainer shows (name,
-- rank, level requirement, cost, spell ID, icon) is remembered per class,
-- account-wide, in UlRemedyForeverTrainerDB. A class trainer lists every
-- rank up to the class's maximum with its level, so one visit covers the
-- class. The trainer window's own filters are switched to show everything
-- while the list is read and put back afterwards. Away from the trainer
-- the list is compared with the player's level and spellbook to give
-- "available now" and "coming up". A rank counts as known when the
-- spellbook has it or a higher rank of the same name (learning a higher
-- rank drops the lower one from the spellbook), or when the trainer
-- listed it as already learned.
--
-- Two outputs. A tab in the spellbook: a button in Blizzard's tab style to
-- the right of its own tabs, owned by this addon, whose panel covers the
-- spellbook's content area. Blizzard's tab system is not touched: on this
-- client the spellbook (PlayerSpellsFrame) reads secret values when it
-- updates, and a tab added to its system would run that code tainted
-- (see MovableWindows). Clicking one of Blizzard's tabs hides the panel
-- again (SetTab post-hook). And a chat line on level up naming the
-- abilities that just became available and what they cost in total.
--
-- Blizzard_PlayerSpells is load-on-demand, so the tab is built when that
-- addon loads, or at login if it is already there.

local ROW_H = 22
local TAB_TEXT = "Trainer"
local CATEGORIES = { available = true, unavailable = true, used = true, header = true }
local FILTERS = { "available", "unavailable", "used" }

local db                 -- UlRemedyForeverTrainerDB
local panel, tab
local scanning = false
local scanQueued = false
local lastError

local function Enabled()
    return UlRemedy.enabled and UlRemedy.enabled.trainerpreview
end

local function Say(text)
    print(UlRemedy.name .. ": " .. text)
end

local function Report(what, err)
    if err == lastError then return end
    lastError = err
    Say("trainer preview " .. what .. ": " .. tostring(err))
end

------------------------------------------------------------------------
-- Data
------------------------------------------------------------------------

local function InitDB()
    if not UlRemedyForeverTrainerDB then UlRemedyForeverTrainerDB = {} end
    db = UlRemedyForeverTrainerDB
    db.classes = db.classes or {}
end

local function ClassKey()
    local _, classFile = UnitClass("player")
    return classFile or "UNKNOWN"
end

local function ClassList(create)
    if not db then return nil end
    local key = ClassKey()
    if not db.classes[key] and create then db.classes[key] = { spells = {} } end
    return db.classes[key]
end

local function RankNumber(rank)
    return rank and tonumber(rank:match("(%d+)")) or nil
end

local function Label(rec)
    if rec.rank and rec.rank ~= "" then return rec.name .. " (" .. rec.rank .. ")" end
    return rec.name
end

-- Known right now according to the spellbook, by spell ID only.
local function SpellKnownNow(rec)
    if not rec.spellID then return false end
    if IsSpellKnown and IsSpellKnown(rec.spellID) then return true end
    if IsPlayerSpell and IsPlayerSpell(rec.spellID) then return true end
    return false
end

-- Returns available (level reached, not known), upcoming (level not
-- reached, not known), both sorted by level then name, and the class list.
local function Compute(level)
    local available, upcoming = {}, {}
    local list = ClassList(false)
    if not list then return available, upcoming, nil end

    local maxKnown = {} -- spell name -> highest known rank number
    for _, rec in pairs(list.spells) do
        if SpellKnownNow(rec) then
            local r = RankNumber(rec.rank) or 0
            if (maxKnown[rec.name] or -1) < r then maxKnown[rec.name] = r end
        end
    end
    for _, rec in pairs(list.spells) do
        local r = RankNumber(rec.rank) or 0
        local known = SpellKnownNow(rec) or rec.usedSeen
            or (maxKnown[rec.name] ~= nil and r <= maxKnown[rec.name])
        if not known then
            if (rec.level or 0) <= level then
                available[#available + 1] = rec
            else
                upcoming[#upcoming + 1] = rec
            end
        end
    end
    local function byLevel(a, b)
        if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) < (b.level or 0) end
        return Label(a) < Label(b)
    end
    table.sort(available, byLevel)
    table.sort(upcoming, byLevel)
    return available, upcoming, list
end

------------------------------------------------------------------------
-- Learning at the trainer
------------------------------------------------------------------------

-- name, rank and category from GetTrainerServiceInfo, whichever slots
-- hold them (the category is second on some clients, third on others).
local function ServiceFields(index)
    local name, a, b = GetTrainerServiceInfo(index)
    if CATEGORIES[a] then
        return name, (type(b) == "string" and not CATEGORIES[b]) and b or nil, a
    elseif CATEGORIES[b] then
        return name, type(a) == "string" and a or nil, b
    end
    return name, nil, nil
end

local function SpellIDFromLink(link)
    if type(link) ~= "string" then return nil end
    return tonumber(link:match("[Hh]spell:(%d+)") or link:match("[Hh]enchant:(%d+)"))
end

-- Runs fn with every trainer filter on, then puts the filters back.
local function WithAllShown(fn)
    local saved, changed = {}, false
    local canFilter = type(GetTrainerServiceTypeFilter) == "function"
        and type(SetTrainerServiceTypeFilter) == "function"
    if canFilter then
        for _, f in ipairs(FILTERS) do
            saved[f] = GetTrainerServiceTypeFilter(f)
            if not saved[f] and pcall(SetTrainerServiceTypeFilter, f, true) then changed = true end
        end
    end
    local ok, err = pcall(fn)
    if changed then
        for _, f in ipairs(FILTERS) do
            if not saved[f] then pcall(SetTrainerServiceTypeFilter, f, false) end
        end
    end
    if not ok then error(err, 0) end
end

local function ScanTrainerUnsafe()
    local list = ClassList(true)
    local seen = 0
    WithAllShown(function()
        local n = GetNumTrainerServices() or 0
        for i = 1, n do
            local name, rank, category = ServiceFields(i)
            if name and category and category ~= "header" then
                local level = GetTrainerServiceLevelReq and GetTrainerServiceLevelReq(i) or 0
                local cost = GetTrainerServiceCost and GetTrainerServiceCost(i) or 0
                local spellID = GetTrainerServiceItemLink and SpellIDFromLink(GetTrainerServiceItemLink(i))
                local icon = GetTrainerServiceIcon and GetTrainerServiceIcon(i)
                local key = spellID and ("s" .. spellID) or (name .. "|" .. (rank or ""))
                local rec = list.spells[key] or {}
                rec.name, rec.rank, rec.spellID = name, rank, spellID
                if icon then rec.icon = icon end
                if (level or 0) > 0 or not rec.level then rec.level = level or 0 end
                -- A learned service shows no cost; keep the one seen earlier.
                if category ~= "used" or (cost or 0) > 0 then rec.cost = cost or 0 end
                if category == "used" then rec.usedSeen = true end
                list.spells[key] = rec
                seen = seen + 1
            end
        end
    end)
    list.lastVisit = date("%Y-%m-%d %H:%M")
    list.trainer = UnitName("npc")
    return seen
end

local function ScanTrainer()
    if scanning or not db then return end
    if type(IsTradeskillTrainer) == "function" and IsTradeskillTrainer() then return end
    if type(GetNumTrainerServices) ~= "function" or type(GetTrainerServiceInfo) ~= "function" then return end
    scanning = true
    local ok, err = pcall(ScanTrainerUnsafe)
    scanning = false
    if not ok then Report("could not read the trainer", err) end
end

-- TRAINER_UPDATE fires several times while the list arrives; read it once
-- things have settled.
local function ScheduleScan()
    if scanQueued then return end
    scanQueued = true
    C_Timer.After(0.3, function()
        scanQueued = false
        if ClassTrainerFrame and ClassTrainerFrame:IsShown() then ScanTrainer() end
    end)
end

------------------------------------------------------------------------
-- Level-up chat line
------------------------------------------------------------------------

local function AnnounceLevelUp(level)
    if not Enabled() then return end
    local available = Compute(level)
    local new, total = {}, 0
    for _, rec in ipairs(available) do
        if (rec.level or 0) == level then
            new[#new + 1] = Label(rec)
            total = total + (rec.cost or 0)
        end
    end
    if #new == 0 then return end
    Say(string.format("%d new %s at your class trainer: %s. %s in total, you have %s.",
        #new, #new == 1 and "ability" or "abilities", table.concat(new, ", "),
        UlRemedy.MoneyText(total), UlRemedy.MoneyText(GetMoney() or 0)))
    local older = #available - #new
    if older > 0 then
        print(string.format("  Plus %d from earlier levels still waiting. The Trainer tab in your spellbook has the list.", older))
    end
end

------------------------------------------------------------------------
-- Spellbook tab and panel
------------------------------------------------------------------------

local function InitRow(button, data)
    if not button.icon then
        button.icon = button:CreateTexture(nil, "ARTWORK")
        button.icon:SetSize(18, 18)
        button.icon:SetPoint("LEFT", 6, 0)
        button.name = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        button.name:SetPoint("LEFT", button.icon, "RIGHT", 6, 0)
        button.name:SetPoint("RIGHT", -170, 0)
        button.name:SetJustifyH("LEFT")
        button.level = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        button.level:SetPoint("RIGHT", -110, 0)
        button.level:SetWidth(56)
        button.level:SetJustifyH("RIGHT")
        button.cost = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        button.cost:SetPoint("RIGHT", -8, 0)
        button.cost:SetWidth(100)
        button.cost:SetJustifyH("RIGHT")
        local hl = button:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.08)
        button:SetScript("OnEnter", function(self)
            local rec = self.data and self.data.rec
            if rec and rec.spellID and GameTooltip.SetSpellByID then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetSpellByID(rec.spellID)
                GameTooltip:Show()
            end
        end)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    button.data = data
    if data.header then
        button.icon:Hide()
        button.name:SetText("|cffffd100" .. data.text .. "|r")
        button.level:SetText("")
        button.cost:SetText(data.right or "")
    elseif data.note then
        button.icon:Hide()
        button.name:SetText("|cff999999" .. data.text .. "|r")
        button.level:SetText("")
        button.cost:SetText("")
    else
        local rec = data.rec
        button.icon:Show()
        button.icon:SetTexture(rec.icon or 134400)
        button.name:SetText(Label(rec))
        button.level:SetText(data.dim and ("|cff999999Level " .. (rec.level or 0) .. "|r") or ("|cff00ff00Level " .. (rec.level or 0) .. "|r"))
        button.cost:SetText(UlRemedy.MoneyText(rec.cost or 0))
    end
end

local function BuildRows()
    local level = UnitLevel("player") or 1
    local available, upcoming, list = Compute(level)
    local rows = {}
    if not list then
        rows[#rows + 1] = { note = true, text = "No trainer visit recorded for this class yet." }
        rows[#rows + 1] = { note = true, text = "Open your class trainer once and the list fills in." }
        return rows, nil
    end
    local total = 0
    for _, rec in ipairs(available) do total = total + (rec.cost or 0) end
    rows[#rows + 1] = { header = true, text = "Available now (level " .. level .. ")",
        right = #available > 0 and (UlRemedy.MoneyText(total) .. " in total") or "" }
    if #available == 0 then
        rows[#rows + 1] = { note = true, text = "Nothing waiting. Everything up to your level is learned." }
    end
    for _, rec in ipairs(available) do rows[#rows + 1] = { rec = rec } end
    rows[#rows + 1] = { header = true, text = "Coming up" }
    if #upcoming == 0 then
        rows[#rows + 1] = { note = true, text = "Nothing more on the trainer's list." }
    end
    for _, rec in ipairs(upcoming) do rows[#rows + 1] = { rec = rec, dim = true } end
    return rows, list
end

local function RefreshPanel()
    if not panel or not panel:IsShown() then return end
    local rows, list = BuildRows()
    if list and list.lastVisit then
        panel.sub:SetText("From your trainer visit on " .. list.lastVisit
            .. (list.trainer and (" (" .. list.trainer .. ")") or "") .. ". Visit again to pick up changes.")
    else
        panel.sub:SetText("")
    end
    local provider = CreateDataProvider(rows)
    panel.box:SetDataProvider(provider, true) -- true: keep the scroll position
end

local function SetTabSelected(selected)
    if not tab then return end
    if selected then
        if PanelTemplates_SelectTab then pcall(PanelTemplates_SelectTab, tab) end
    else
        if PanelTemplates_DeselectTab then pcall(PanelTemplates_DeselectTab, tab) end
    end
end

local function HidePanel()
    if panel then panel:Hide() end
    SetTabSelected(false)
end

local function ShowPanel()
    if not panel then return end
    panel:Show()
    SetTabSelected(true)
    RefreshPanel()
end

local function TogglePanel()
    if panel and panel:IsShown() then HidePanel() else ShowPanel() end
end

local function CreatePanel(parent)
    local f = CreateFrame("Frame", "UlRemedyTrainerPreviewPanel", parent)
    f:SetPoint("TOPLEFT", parent, "TOPLEFT", 7, -26)
    f:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -7, 6)
    -- The spellbook's pages sit on child frames with high levels of their
    -- own; the panel has to be well above them to cover them. The
    -- maximize button lives in the title bar, which the panel does not
    -- reach, so nothing of Blizzard's that is clickable ends up beneath.
    f:SetFrameStrata(parent:GetFrameStrata())
    f:SetFrameLevel(parent:GetFrameLevel() + 5000)
    f:EnableMouse(true) -- keeps clicks from reaching the spellbook page underneath
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.07, 0.06, 0.05, 1)

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOP", 0, -12)
    f.title:SetText("At your class trainer")
    f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.sub:SetPoint("TOP", f.title, "BOTTOM", 0, -4)
    f.sub:SetPoint("LEFT", 12, 0)
    f.sub:SetPoint("RIGHT", -12, 0)
    f.sub:SetJustifyH("CENTER")

    local box = CreateFrame("Frame", nil, f, "WowScrollBoxList")
    box:SetPoint("TOPLEFT", 8, -56)
    box:SetPoint("BOTTOMRIGHT", -30, 10)
    local bar = CreateFrame("EventFrame", nil, f, "MinimalScrollBar")
    bar:SetPoint("TOPLEFT", box, "TOPRIGHT", 4, 0)
    bar:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 4, 0)
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(ROW_H)
    view:SetElementInitializer("Button", InitRow)
    ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)
    f.box = box

    f:Hide()
    return f
end

-- Our tab goes right of the last of Blizzard's own tabs, which hang
-- below the frame's bottom-left corner. On Forever the tab system is
-- there but hidden (its buttons still answer IsShown, so IsVisible is the
-- test), and the tab then takes the first spot itself.
local function AnchorTab()
    if not tab then return end
    local parent = PlayerSpellsFrame
    local system = parent and (parent.TabSystem or parent.tabSystem)
    local last, lastRight
    if system then
        for _, child in ipairs({ system:GetChildren() }) do
            local right = child:IsVisible() and child.GetRight and child:GetRight()
            if right and (not lastRight or right > lastRight) then last, lastRight = child, right end
        end
    end
    tab:ClearAllPoints()
    if last then
        tab:SetPoint("LEFT", last, "RIGHT", 3, 0)
    else
        tab:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", 22, 2)
    end
end

local function CreateTab(parent)
    local b = CreateFrame("Button", "UlRemedyTrainerPreviewTab", parent, "PanelTabButtonTemplate")
    if not b.Text then
        -- Template missing on this client: a plain button in its place.
        b = CreateFrame("Button", "UlRemedyTrainerPreviewTab", parent, "UIPanelButtonTemplate")
        b:SetSize(80, 22)
    end
    b:SetText(TAB_TEXT)
    if PanelTemplates_TabResize then pcall(PanelTemplates_TabResize, b, 10) end
    b:SetScript("OnClick", TogglePanel)
    return b
end

local hooked = false

local function SetupSpellbookUnsafe()
    local parent = PlayerSpellsFrame
    if not parent or hooked then return end
    hooked = true
    panel = CreatePanel(parent)
    tab = CreateTab(parent)
    AnchorTab()
    SetTabSelected(false)
    -- A Blizzard tab taking over hides our panel. Post-hook only; the
    -- tab system itself is never called from here.
    if type(parent.SetTab) == "function" then
        hooksecurefunc(parent, "SetTab", HidePanel)
    end
    parent:HookScript("OnShow", function()
        HidePanel()
        -- Tabs can appear or vanish between shows (talents at level 10).
        C_Timer.After(0, AnchorTab)
    end)
end

local function SetupSpellbook()
    local ok, err = pcall(SetupSpellbookUnsafe)
    if not ok then Report("could not set up the spellbook tab", err) end
end

function UlRemedy.RefreshTrainerPreview()
    if not db then return end
    if Enabled() then
        if not hooked and PlayerSpellsFrame then SetupSpellbook() end
        if tab then tab:Show() end
    else
        HidePanel()
        if tab then tab:Hide() end
    end
end

------------------------------------------------------------------------
-- Commands
------------------------------------------------------------------------

-- /ur tp
function UlRemedy.TrainerPreviewDebug()
    local level = UnitLevel("player") or 1
    local available, upcoming, list = Compute(level)
    local count = 0
    if list then for _ in pairs(list.spells) do count = count + 1 end end
    Say(string.format("trainer preview for %s: %d services remembered, %d available now, %d coming up.",
        ClassKey(), count, #available, #upcoming))
    print("  last visit: " .. tostring(list and list.lastVisit) .. ", trainer: " .. tostring(list and list.trainer))
    print("  spellbook tab: " .. (tab and "built" or "not built") .. ", PlayerSpellsFrame: " .. tostring(PlayerSpellsFrame ~= nil))
    for _, name in ipairs({ "GetTrainerServiceLevelReq", "GetTrainerServiceCost", "GetTrainerServiceItemLink", "IsTradeskillTrainer", "IsSpellKnown" }) do
        print("  " .. name .. ": " .. type(_G[name]))
    end
    for i = 1, math.min(5, #available) do
        local rec = available[i]
        print("  available: " .. Label(rec) .. ", level " .. (rec.level or 0) .. ", " .. UlRemedy.MoneyText(rec.cost or 0))
    end
    print("  last error: " .. tostring(lastError))
end

-- /ur tpreset
function UlRemedy.ResetTrainerPreview()
    if not db then return end
    db.classes[ClassKey()] = nil
    RefreshPanel()
    Say("trainer list for " .. ClassKey() .. " forgotten. Visit your class trainer to learn it again.")
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------

local frame = CreateFrame("Frame", "UlRemedyTrainerPreviewFrame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LEVEL_UP")
frame:RegisterEvent("TRAINER_SHOW")
frame:RegisterEvent("TRAINER_UPDATE")
frame:RegisterEvent("SPELLS_CHANGED")
frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == UlRemedy.name then
            InitDB()
        elseif arg1 == "Blizzard_PlayerSpells" and db then
            UlRemedy.RefreshTrainerPreview()
        end
    elseif event == "PLAYER_LOGIN" then
        UlRemedy.RefreshTrainerPreview()
    elseif event == "PLAYER_LEVEL_UP" then
        local level = tonumber(arg1)
        if level then
            -- The spellbook may not have caught up yet; give it a moment.
            C_Timer.After(1, function() AnnounceLevelUp(level) end)
        end
    elseif event == "TRAINER_SHOW" then
        if C_AddOns and C_AddOns.LoadAddOn then C_AddOns.LoadAddOn("Blizzard_TrainerUI") end
        ScheduleScan()
    elseif event == "TRAINER_UPDATE" then
        ScheduleScan()
    elseif event == "SPELLS_CHANGED" then
        RefreshPanel()
    end
end)
