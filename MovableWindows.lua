-- Movable Windows: lets the standard Blizzard windows (character, spellbook,
-- professions, bags and so on) be dragged anywhere, remembers where each one
-- was closed, and lets them overlap.
--
-- Why they cannot do that out of the box: UIParent runs a panel manager
-- (UIPanelWindows). Every registered window is assigned an area (left,
-- center, right), the manager re-anchors it on every show, and when a new
-- window wants an occupied area the old one is pushed aside or closed. That
-- is why opening the spellbook moves or closes the character window.
--
-- The fix is to take each window out of that manager by clearing its "area"
-- attribute. ShowUIPanel and HideUIPanel then fall through to plain
-- Show/Hide, so Blizzard's own open/close code keeps working, but nothing
-- positions the window any more. We do that ourselves: apply the saved
-- position on show, and save a new one when a drag ends. Windows outside the
-- manager are no longer closed by Escape, so they are added to
-- UISpecialFrames, the list Escape does close. (Hiding the game menu from a
-- hook instead was tried and dropped: it runs the panel manager from addon
-- code, and that manager also lays out the action bars, which must never be
-- touched from tainted code in combat.) As a safety net ShowUIPanel
-- and HideUIPanel are post-hooked so a detached window is shown or hidden
-- even on a client whose panel code bails out on an area-less frame.
--
-- Which windows: every entry in UIPanelWindows except full-screen panels and
-- a short exclusion list, plus a named list for windows that are not panels
-- on every client. A window left inside the manager misbehaves next to the
-- detached ones: the manager raises it on every layout update and runs
-- CloseWindows when it is shown, which also closes everything in
-- UISpecialFrames. So the rule is all or nothing, not a list of areas. This way Forever-only windows
-- are picked up without knowing their names in advance.
--
-- Bags are a separate case. The ContainerFrameN frames come from a pool, so
-- "ContainerFrame3" is not always the same bag; positions are stored per bag
-- ID instead. Blizzard re-stacks every open bag bottom-right each time one
-- opens (UpdateContainerFrameAnchors), so that function is post-hooked to put
-- the saved positions back.
--
-- Every per-window setup runs under pcall and is reported in chat, so one
-- window the client handles differently never breaks the others.
--
-- Positions are stored as an offset from the centre of UIParent, in the
-- window's own scale, so SetPoint("CENTER", UIParent, "CENTER", x, y)
-- recreates them regardless of UI scale changes. Stored account-wide in
-- UlRemedyForeverWindowDB (Core.lua wipes unknown keys in the main DB).
--
-- Off by default while experimental: the panel manager is entangled with the
-- action bar layout, and tainting it can make the bars vanish in combat.
-- Turning the feature off only stops us touching windows from then on; the
-- windows already detached stay detached until /reload. /ur win prints
-- diagnostics, including the frame under the mouse, for windows that do not
-- get picked up.

-- Windows handled even when they are not registered in UIPanelWindows.
local NAMED = {
    "CharacterFrame",
    "SpellBookFrame",
    "PlayerSpellsFrame",  -- newer spellbook
    "TalentFrame",        -- Blizzard_TalentUI (load on demand)
    "QuestLogFrame",
    "FriendsFrame",
    "GuildFrame",         -- Blizzard_GuildUI (load on demand)
    "ClassTrainerFrame",  -- Blizzard_TrainerUI (load on demand)
    "MerchantFrame",
    "MailFrame",
    "BankFrame",
    "TradeSkillFrame",    -- Blizzard_TradeSkillUI (load on demand): most professions
    "CraftFrame",         -- Blizzard_CraftUI (load on demand): enchanting, beast training
    "ProfessionsFrame",   -- newer professions window
}

-- Panels never detached: system windows that manage themselves, or that
-- other code expects to find in the panel manager. The world map is not in
-- the list on purpose: it is a window like the others on this client.
local EXCLUDE = {
    GameMenuFrame = true,
    SettingsPanel = true,
    VideoOptionsFrame = true,
    InterfaceOptionsFrame = true,
    AudioOptionsFrame = true,
    HelpFrame = true,
    StoreFrame = true,
    EditModeManagerFrame = true,
    MacOptionsFrame = true,
}

-- Areas never detached: full-screen panels manage the whole screen themselves.
local SKIP_AREAS = { full = true, fullscreen = true }

-- Child regions that commonly sit on top of a window's title bar with the
-- mouse enabled, which would otherwise eat the drag before the window sees it.
-- Only children that already take the mouse are touched: enabling the mouse
-- on a child that covers the window (NineSlice, for one) blocks every click
-- to the buttons underneath it.
local TITLE_CHILDREN = { "TitleContainer", "TitleBar" }

local db
local handled = {}       -- frame name -> true once detached and hooked
local errors = {}        -- frame name -> last error text, for /ur win
local bagsHooked = false
local panelHooksDone = false

local function Enabled()
    return UlRemedy.enabled and UlRemedy.enabled.windows
end

local function Report(name, err)
    errors[name] = err
    print(UlRemedy.name .. ": movable windows could not set up " .. name .. ": " .. tostring(err))
end

local function InitDB()
    if not UlRemedyForeverWindowDB then UlRemedyForeverWindowDB = {} end
    db = UlRemedyForeverWindowDB
    db.frames = db.frames or {}
    db.bags = db.bags or {}
    -- 1.1.7: the feature made action bars vanish in combat for some users.
    -- Switch it off once for everyone who had it on; /ur windows turns it
    -- back on deliberately.
    if not db.forcedOff117 then
        db.forcedOff117 = true
        if UlRemedy.enabled then UlRemedy.enabled.windows = false end
    end
end

-- Position helpers ---------------------------------------------------------

-- Offset of the frame's centre from UIParent's centre, expressed in the
-- frame's own scale so it can be fed straight back into SetPoint.
local function ReadPosition(frame)
    local cx, cy = frame:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if not cx or not ux then return nil end
    local fs = frame:GetEffectiveScale()
    local us = UIParent:GetEffectiveScale()
    return {
        x = (cx * fs - ux * us) / fs,
        y = (cy * fs - uy * us) / fs,
    }
end

local function ApplyPosition(frame, pos)
    if not pos then return end
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", pos.x, pos.y)
end

-- Many panel windows have no anchor of their own: the panel manager gives
-- them one the first time they are shown. A window detached before that is
-- shown without any point and simply does not render, which looks like "it
-- will not open". Give such a window the manager's usual left-area spot.
local function PlaceWindow(frame, pos)
    if pos then
        ApplyPosition(frame, pos)
    elseif frame:GetNumPoints() == 0 then
        frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116)
    end
end

-- Set a script when the frame has none, hook it when it has one. HookScript
-- on a frame without a handler is not reliable on every client.
local function AddScript(frame, script, fn)
    if frame:GetScript(script) then
        frame:HookScript(script, fn)
    else
        frame:SetScript(script, fn)
    end
end

-- Make `region` start a drag of `frame` (they are the same object for the
-- window itself, different for a title bar child). onStop saves.
local function DragFrom(region, frame, onStop)
    if type(region.RegisterForDrag) ~= "function" then return end
    if region == frame then
        region:EnableMouse(true)
    elseif not region:IsMouseEnabled() then
        return
    end
    region:RegisterForDrag("LeftButton")
    AddScript(region, "OnDragStart", function()
        if not Enabled() then return end
        frame:StartMoving()
    end)
    AddScript(region, "OnDragStop", function()
        frame:StopMovingOrSizing()
        if not Enabled() then return end
        onStop(frame)
    end)
end

local function MakeDraggable(frame, onStop)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    DragFrom(frame, frame, onStop)
    for _, key in ipairs(TITLE_CHILDREN) do
        local child = frame[key]
        if type(child) == "table" and child ~= frame and type(child.GetObjectType) == "function" then
            DragFrom(child, frame, onStop)
        end
    end
end

-- Panels (UIPanelWindows) --------------------------------------------------

-- Take the frame out of UIParent's panel manager. A window can be registered
-- in two ways: an entry in the UIPanelWindows table, or UIPanelLayout-*
-- attributes set straight on the frame (newer Blizzard XML does this, and
-- the manager caches table entries into the same attributes on first use).
-- Clear both. The manager reads the area attribute once "defined" is set,
-- so an attribute-defined frame with a nil area is a free frame.
local function DetachFromPanelManager(frame, name)
    if UIPanelWindows and UIPanelWindows[name] and type(SetUIPanelAttribute) == "function" then
        SetUIPanelAttribute(frame, "area", nil)
    end
    if frame:GetAttribute("UIPanelLayout-defined") then
        frame:SetAttribute("UIPanelLayout-area", nil)
    end
end

local function AddToEscapeList(name)
    if not UISpecialFrames then return end
    for _, existing in ipairs(UISpecialFrames) do
        if existing == name then return end
    end
    table.insert(UISpecialFrames, name)
end

local function SetupPanelUnsafe(name, frame)
    DetachFromPanelManager(frame, name)
    AddToEscapeList(name)
    frame:SetToplevel(true) -- clicking a window brings it in front of the others

    MakeDraggable(frame, function(self)
        db.frames[name] = ReadPosition(self)
    end)

    AddScript(frame, "OnShow", function(self)
        if not Enabled() then return end
        PlaceWindow(self, db.frames[name])
    end)
    PlaceWindow(frame, db.frames[name])
end

local function SetupPanel(name)
    if handled[name] or EXCLUDE[name] then return end
    local frame = _G[name]
    if type(frame) ~= "table" or type(frame.GetObjectType) ~= "function" then return end
    if frame:GetObjectType() ~= "Frame" then return end
    handled[name] = true
    local ok, err = pcall(SetupPanelUnsafe, name, frame)
    if not ok then Report(name, err) end
end

-- Safety net: a detached frame must still open and close through Blizzard's
-- panel functions, whatever this client's versions of them do with a frame
-- that has no area.
local function HookPanelFunctions()
    if panelHooksDone then return end
    panelHooksDone = true
    if type(ShowUIPanel) == "function" then
        hooksecurefunc("ShowUIPanel", function(frame)
            if not Enabled() or type(frame) ~= "table" then return end
            local name = frame.GetName and frame:GetName()
            if not name then
                if db then db.seen = db.seen or {}; db.seen["<unnamed>"] = "?" end
                return
            end
            -- Diagnostics: remember every panel that comes through here,
            -- with the area the manager sees for it right now.
            if db then
                db.seen = db.seen or {}
                local area = frame.GetAttribute and frame:GetAttribute("UIPanelLayout-area")
                local tableArea = UIPanelWindows and UIPanelWindows[name] and UIPanelWindows[name].area
                db.seen[name] = tostring(area) .. "/" .. tostring(tableArea) .. (handled[name] and " handled" or " free")
            end
            if handled[name] then
                -- Blizzard code can put the area back (some frames set their
                -- layout attributes on show). Clear it again and note it.
                if frame.GetAttribute and frame:GetAttribute("UIPanelLayout-area") then
                    frame:SetAttribute("UIPanelLayout-area", nil)
                    errors[name] = "area was re-set by the client on show, cleared again"
                end
            end
            if not handled[name] and not EXCLUDE[name] then
                -- A panel we did not know about (registered by attributes
                -- rather than the table). Detach it now; from the next show
                -- on it is free.
                local area = frame.GetAttribute and frame:GetAttribute("UIPanelLayout-area")
                if area and not SKIP_AREAS[area] then SetupPanel(name) end
            end
            if handled[name] and not frame:IsShown() then frame:Show() end
        end)
    end
    if type(HideUIPanel) == "function" then
        hooksecurefunc("HideUIPanel", function(frame)
            if not Enabled() or type(frame) ~= "table" then return end
            local name = frame.GetName and frame:GetName()
            if name and handled[name] and frame:IsShown() then frame:Hide() end
        end)
    end
end

local function PanelArea(name)
    local info = UIPanelWindows and UIPanelWindows[name]
    local frame = _G[name]
    if type(frame) == "table" and type(frame.GetAttribute) == "function"
        and frame:GetAttribute("UIPanelLayout-defined") then
        return frame:GetAttribute("UIPanelLayout-area")
    end
    return info and info.area
end

local function SetupAllPanels()
    if UIPanelWindows then
        for name, info in pairs(UIPanelWindows) do
            if type(info) == "table" and info.area and not SKIP_AREAS[info.area] then
                SetupPanel(name)
            end
        end
    end
    for _, name in ipairs(NAMED) do
        SetupPanel(name)
    end
end

-- Bags ---------------------------------------------------------------------

local function BagFrames()
    local list = {}
    local count = NUM_CONTAINER_FRAMES or 13
    for i = 1, count do
        local bag = _G["ContainerFrame" .. i]
        if bag then list[#list + 1] = bag end
    end
    if ContainerFrameCombinedBags then list[#list + 1] = ContainerFrameCombinedBags end
    return list
end

local function BagKey(bag)
    if bag == ContainerFrameCombinedBags then return "combined" end
    return bag:GetID()
end

local function ApplyBagPositions()
    if not Enabled() then return end
    for _, bag in ipairs(BagFrames()) do
        if bag:IsShown() then
            ApplyPosition(bag, db.bags[BagKey(bag)])
        end
    end
end

local function SetupBagsUnsafe()
    local bags = BagFrames()
    if #bags == 0 then return false end
    for _, bag in ipairs(bags) do
        MakeDraggable(bag, function(self)
            db.bags[BagKey(self)] = ReadPosition(self)
        end)
        AddScript(bag, "OnShow", function(self)
            if not Enabled() then return end
            ApplyPosition(self, db.bags[BagKey(self)])
        end)
    end

    -- Blizzard re-anchors all open bags whenever one opens or closes. Run
    -- after it so the saved positions win. Both hooks are guarded because the
    -- bag code differs between client generations.
    if type(UpdateContainerFrameAnchors) == "function" then
        hooksecurefunc("UpdateContainerFrameAnchors", ApplyBagPositions)
    end
    if type(ContainerFrame_GenerateFrame) == "function" then
        hooksecurefunc("ContainerFrame_GenerateFrame", ApplyBagPositions)
    end
    return true
end

local function SetupBags()
    if bagsHooked then return end
    local ok, result = pcall(SetupBagsUnsafe)
    if not ok then
        bagsHooked = true -- do not retry a broken hook on every refresh
        Report("bags", result)
    elseif result then
        bagsHooked = true
    end
end

-- Diagnostics --------------------------------------------------------------

-- The client hides Lua errors unless scriptErrors is on, and this addon is
-- tested on a machine without copy and paste. Keep the last few errors in
-- the DB (chained in front of the previous handler, as BugGrabber does) so
-- /ur win can print them.
local MAX_ERRORS = 5
local errorHandlerInstalled = false

local function InstallErrorHandler()
    if errorHandlerInstalled or type(seterrorhandler) ~= "function" then return end
    errorHandlerInstalled = true
    local previous = type(geterrorhandler) == "function" and geterrorhandler() or nil
    seterrorhandler(function(msg, ...)
        if db then
            db.errors = db.errors or {}
            local text = tostring(msg):gsub("Interface[/\\]AddOns[/\\]", "")
            table.insert(db.errors, 1, date("%H:%M ") .. text:sub(1, 220))
            while #db.errors > MAX_ERRORS do table.remove(db.errors) end
        end
        if previous then return previous(msg, ...) end
    end)
end

local function FrameChain(frame)
    local parts = {}
    local f = frame
    while f and f ~= UIParent and #parts < 8 do
        local name = f.GetName and f:GetName()
        parts[#parts + 1] = name or ("<" .. (f.GetObjectType and f:GetObjectType() or "?") .. ">")
        f = f.GetParent and f:GetParent()
    end
    return table.concat(parts, " > ")
end

local function MouseFrames()
    if type(GetMouseFoci) == "function" then return GetMouseFoci() end
    if type(GetMouseFocus) == "function" then return { GetMouseFocus() } end
    return {}
end

function UlRemedy.MovableWindowsDebug()
    local p = print
    p("|cffffcc00" .. UlRemedy.name .. " " .. UlRemedy.Version() .. "|r movable windows diagnostics")
    p("  enabled: " .. tostring(Enabled()) .. ", db: " .. tostring(db ~= nil)
        .. ", bags hooked: " .. tostring(bagsHooked))
    p("  API: SetUIPanelAttribute=" .. type(SetUIPanelAttribute)
        .. " ShowUIPanel=" .. type(ShowUIPanel)
        .. " UpdateContainerFrameAnchors=" .. type(UpdateContainerFrameAnchors)
        .. " ContainerFrame_GenerateFrame=" .. type(ContainerFrame_GenerateFrame)
        .. " NUM_CONTAINER_FRAMES=" .. tostring(NUM_CONTAINER_FRAMES)
        .. " CombinedBags=" .. tostring(ContainerFrameCombinedBags ~= nil))

    local names, ok, bad = {}, {}, {}
    for name in pairs(handled) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        local f = _G[name]
        if errors[name] then
            bad[#bad + 1] = name
        elseif f then
            local tag = name
            if f:IsShown() then
                tag = tag .. "(shown," .. f:GetNumPoints() .. "pt)"
            end
            ok[#ok + 1] = tag
        end
    end
    p("  ok (" .. #ok .. "): " .. table.concat(ok, ", "))
    for _, name in ipairs(bad) do
        p("  |cffff4444setup error|r " .. name .. ": " .. errors[name])
    end
    if errors.bags then p("  |cffff4444bags error|r: " .. errors.bags) end
    if db and db.errors and #db.errors > 0 then
        p("  recent Lua errors (newest first):")
        for i, text in ipairs(db.errors) do p("    " .. i .. ". " .. text) end
    else
        p("  recent Lua errors: none")
    end

    local panels = {}
    if UIPanelWindows then
        for name, info in pairs(UIPanelWindows) do
            if not handled[name] then
                panels[#panels + 1] = name .. "=" .. tostring(type(info) == "table" and info.area or "?")
            end
        end
    end
    table.sort(panels)
    p("  panels not handled: " .. (#panels > 0 and table.concat(panels, ", ") or "none"))

    local seen = {}
    if db and db.seen then
        for name, info in pairs(db.seen) do seen[#seen + 1] = name .. " " .. info end
    end
    table.sort(seen)
    p("  panels shown via the manager (name attr/table state):")
    for _, line in ipairs(seen) do p("    " .. line) end
    if #seen == 0 then p("    none yet") end

    local bags = {}
    for _, bag in ipairs(BagFrames()) do
        if bag:IsShown() then bags[#bags + 1] = bag:GetName() .. "(id " .. tostring(BagKey(bag)) .. ")" end
    end
    p("  open bags: " .. (#bags > 0 and table.concat(bags, ", ") or "none"))

    for _, f in ipairs(MouseFrames()) do
        if f and f ~= WorldFrame then
            local top = f
            while top:GetParent() and top:GetParent() ~= UIParent do top = top:GetParent() end
            local topName = top.GetName and top:GetName() or "?"
            p("  under mouse: " .. FrameChain(f))
            p("  window: " .. topName .. " area=" .. tostring(PanelArea(topName))
                .. " handled=" .. tostring(handled[topName] or false))
        end
    end
    p("  Hover a window and run /ur win again to see its frame name.")
end

-- Public API used by Core.lua ---------------------------------------------

-- Idempotent: detaches and hooks every window that exists right now. Called
-- at login, after each load-on-demand Blizzard addon, and on toggle.
function UlRemedy.RefreshMovableWindows()
    if not db or not Enabled() then return end
    InstallErrorHandler()
    HookPanelFunctions()
    SetupAllPanels()
    SetupBags()
end

function UlRemedy.ResetWindowPositions()
    if not db then return end
    wipe(db.frames)
    wipe(db.bags)
    db.errors = nil
    db.seen = nil
    print(UlRemedy.name .. ": window positions forgotten. Type /reload to put the windows back where Blizzard puts them.")
end

local frame = CreateFrame("Frame", "UlRemedyMovableWindowsFrame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == UlRemedy.name then
            InitDB()
        elseif db then
            -- A load-on-demand Blizzard addon (trade skills, crafting,
            -- talents, trainer, guild) may have just created one of our
            -- frames or registered new panels.
            UlRemedy.RefreshMovableWindows()
        end
    elseif event == "PLAYER_LOGIN" then
        UlRemedy.RefreshMovableWindows()
        self:UnregisterEvent("PLAYER_LOGIN")
    end
end)
