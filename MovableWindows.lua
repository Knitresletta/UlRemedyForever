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
-- UISpecialFrames, the list Escape does close.
--
-- Bags are a separate case. The ContainerFrameN frames come from a pool, so
-- "ContainerFrame3" is not always the same bag; positions are stored per bag
-- ID instead. Blizzard re-stacks every open bag bottom-right each time one
-- opens (UpdateContainerFrameAnchors), so that function is post-hooked to put
-- the saved positions back.
--
-- Positions are stored as an offset from the centre of UIParent, in the
-- window's own scale, so SetPoint("CENTER", UIParent, "CENTER", x, y)
-- recreates them regardless of UI scale changes. Stored account-wide in
-- UlRemedyForeverWindowDB (Core.lua wipes unknown keys in the main DB).
--
-- Turning the feature off only stops us touching windows from then on; the
-- windows already detached stay detached until /reload.

local PANELS = {
    "CharacterFrame",
    "SpellBookFrame",
    "TalentFrame",        -- Blizzard_TalentUI (load on demand)
    "QuestLogFrame",
    "FriendsFrame",
    "ClassTrainerFrame",  -- Blizzard_TrainerUI (load on demand)
    "MerchantFrame",
    "MailFrame",
    "BankFrame",
    "TradeSkillFrame",    -- Blizzard_TradeSkillUI (load on demand): most professions
    "CraftFrame",         -- Blizzard_CraftUI (load on demand): enchanting, beast training
}

local db
local handled = {}       -- frame name -> true once detached and hooked
local bagsHooked = false

local function Enabled()
    return UlRemedy.enabled and UlRemedy.enabled.windows
end

local function InitDB()
    if not UlRemedyForeverWindowDB then UlRemedyForeverWindowDB = {} end
    db = UlRemedyForeverWindowDB
    db.frames = db.frames or {}
    db.bags = db.bags or {}
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

-- Drag handling shared by panels and bags. onStop receives the frame after
-- the move and is responsible for saving.
local function MakeDraggable(frame, onStop)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:HookScript("OnDragStart", function(self)
        if not Enabled() then return end
        self:StartMoving()
    end)
    frame:HookScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if not Enabled() then return end
        onStop(self)
    end)
end

-- Panels (UIPanelWindows) --------------------------------------------------

-- Take the frame out of UIParent's panel manager. SetUIPanelAttribute is the
-- official way; fall back to editing the table and attributes directly on a
-- client that lacks it.
local function DetachFromPanelManager(frame, name)
    if UIPanelWindows and UIPanelWindows[name] and type(SetUIPanelAttribute) == "function" then
        SetUIPanelAttribute(frame, "area", nil)
        return
    end
    if UIPanelWindows then UIPanelWindows[name] = nil end
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

local function SetupPanel(name)
    if handled[name] then return end
    local frame = _G[name]
    if not frame or type(frame.GetName) ~= "function" then return end
    handled[name] = true

    DetachFromPanelManager(frame, name)
    AddToEscapeList(name)
    frame:SetToplevel(true) -- clicking a window brings it in front of the others

    MakeDraggable(frame, function(self)
        db.frames[name] = ReadPosition(self)
    end)

    frame:HookScript("OnShow", function(self)
        if not Enabled() then return end
        ApplyPosition(self, db.frames[name])
    end)
    if frame:IsShown() then ApplyPosition(frame, db.frames[name]) end
end

-- Bags ---------------------------------------------------------------------

local function ApplyBagPositions()
    if not Enabled() then return end
    local count = NUM_CONTAINER_FRAMES or 13
    for i = 1, count do
        local bag = _G["ContainerFrame" .. i]
        if bag and bag:IsShown() then
            ApplyPosition(bag, db.bags[bag:GetID()])
        end
    end
end

local function SetupBags()
    if bagsHooked then return end
    local count = NUM_CONTAINER_FRAMES or 13
    local found = false
    for i = 1, count do
        local bag = _G["ContainerFrame" .. i]
        if bag then
            found = true
            MakeDraggable(bag, function(self)
                db.bags[self:GetID()] = ReadPosition(self)
            end)
            bag:HookScript("OnShow", function(self)
                if not Enabled() then return end
                ApplyPosition(self, db.bags[self:GetID()])
            end)
        end
    end
    if not found then return end
    bagsHooked = true

    -- Blizzard re-anchors all open bags whenever one opens or closes. Run
    -- after it so the saved positions win. Both hooks are guarded because the
    -- bag code differs between client generations.
    if type(UpdateContainerFrameAnchors) == "function" then
        hooksecurefunc("UpdateContainerFrameAnchors", ApplyBagPositions)
    end
    if type(ContainerFrame_GenerateFrame) == "function" then
        hooksecurefunc("ContainerFrame_GenerateFrame", ApplyBagPositions)
    end
end

-- Public API used by Core.lua ---------------------------------------------

-- Idempotent: detaches and hooks every window that exists right now. Called
-- at login, after each load-on-demand Blizzard addon, and on toggle.
function UlRemedy.RefreshMovableWindows()
    if not db or not Enabled() then return end
    for _, name in ipairs(PANELS) do
        SetupPanel(name)
    end
    SetupBags()
end

function UlRemedy.ResetWindowPositions()
    if not db then return end
    wipe(db.frames)
    wipe(db.bags)
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
            -- talents, trainer) may have just created one of our frames.
            UlRemedy.RefreshMovableWindows()
        end
    elseif event == "PLAYER_LOGIN" then
        UlRemedy.RefreshMovableWindows()
        self:UnregisterEvent("PLAYER_LOGIN")
    end
end)
