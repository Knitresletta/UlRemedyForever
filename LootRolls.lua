-- Loot Rolls: a small window that shows, for every group loot roll in
-- progress, what each group member chose (Need, Greed, Pass, Disenchant)
-- and what they rolled, with the item's icon so several rolls at once stay
-- apart.
--
-- Where the data comes from: the game does not send other players' roll
-- choices as an API event, but it prints them to chat ("X has selected
-- Need for: [item]", "Need Roll - 87 for [item] by X", "X won: [item]").
-- Those lines are matched against Blizzard's own format strings
-- (LOOT_ROLL_NEED and friends), turned into Lua patterns at load, so the
-- parsing follows the client's language. START_LOOT_ROLL tells us a roll
-- has begun and which item it is; the item link in each chat line ties
-- the choice to that roll. Several rolls for the same item at the same
-- time are shown as one block, since chat cannot tell them apart.
--
-- Placement: anchored to the right of the party frames by default, with
-- "left of party frames", "above the chat" and "free" (dragged anywhere)
-- as alternatives (/ur rollside cycles, or the button in /ur). The window
-- is only shown while a roll is active, plus a few seconds after it ends
-- so the winner can be seen. /ur rolltest shows a fake roll with the
-- current group so the window can be placed without waiting for loot.
--
-- Settings live in UlRemedyForeverRollDB (account-wide): side and the
-- free position.

local ICON = 16          -- choice icon size
local ITEM_ICON = 20
local ROW_H = 18
local PAD = 8
local WIDTH = 220
local LINGER = 15        -- seconds a finished roll stays visible
local MAX_ROWS = 10      -- members listed per roll; raids get a summary line beyond this

local SIDES = { "partyright", "partyleft", "chat", "free" }
local SIDE_LABEL = {
    partyright = "Right of party frames",
    partyleft = "Left of party frames",
    chat = "Above the chat",
    free = "Free (dragged)",
}

local CHOICE = {
    need = { atlas = "lootroll-toast-icon-need-up", file = "Interface\\Buttons\\UI-GroupLoot-Dice-Up", label = "Need" },
    greed = { atlas = "lootroll-toast-icon-greed-up", file = "Interface\\Buttons\\UI-GroupLoot-Coin-Up", label = "Greed" },
    pass = { atlas = "lootroll-toast-icon-pass-up", file = "Interface\\Buttons\\UI-GroupLoot-Pass-Up", label = "Pass" },
    disenchant = { atlas = "lootroll-toast-icon-transmog-up", file = "Interface\\Buttons\\UI-GroupLoot-DE-Up", label = "Disenchant" },
}

local db
local window
local rolls = {}         -- list of active roll records, oldest first
local blocks = {}        -- pooled block frames
local patterns = {}      -- { pattern, kind, order } built from global strings
local lastError

local function Enabled()
    return UlRemedy.enabled and UlRemedy.enabled.rolls
end

local function Report(err)
    err = tostring(err)
    if err == lastError then return end
    lastError = err
    print(UlRemedy.name .. ": loot rolls error: " .. err)
end

local function InitDB()
    if not UlRemedyForeverRollDB then UlRemedyForeverRollDB = {} end
    db = UlRemedyForeverRollDB
    db.side = db.side or "partyright"
end

------------------------------------------------------------------------
-- Chat message patterns from Blizzard's format strings
------------------------------------------------------------------------

-- Turns "%s has selected Need for: %s" or "%1$s won: %2$s" into a Lua
-- pattern plus the argument number each capture corresponds to.
local function CompileFormat(format)
    local order = {}
    local kinds = {}
    local nextArg = 0
    -- Lift the tokens out first, escape everything else, then put
    -- captures back where the tokens were.
    local working = format:gsub("%%(%d*)%$?([sd])", function(num, kind)
        nextArg = nextArg + 1
        order[#order + 1] = tonumber(num) or nextArg
        kinds[#kinds + 1] = kind
        return "\1"
    end)
    working = working:gsub("[%(%)%.%+%-%*%?%[%]%^%$%%]", "%%%0")
    local i = 0
    working = working:gsub("\1", function()
        i = i + 1
        return kinds[i] == "d" and "(%d+)" or "(.-)"
    end)
    return "^" .. working .. "$", order
end

local function AddPattern(global, kind, fields)
    local format = _G[global]
    if type(format) ~= "string" or format == "" then return end
    local pattern, order = CompileFormat(format)
    -- Literal text left once the captures are removed: the more of it a
    -- pattern has, the more specific it is, and the earlier it is tried.
    local literal = pattern:gsub("%(%.%-%)", ""):gsub("%(%%d%+%)", "")
    patterns[#patterns + 1] = { pattern = pattern, kind = kind, fields = fields, order = order, literal = #literal }
end

-- fields: which argument number holds the player name, the item link and
-- the roll value. "self" means the player is us.
local function BuildPatterns()
    AddPattern("LOOT_ROLL_NEED", "choice", { choice = "need", player = 1, item = 2 })
    AddPattern("LOOT_ROLL_GREED", "choice", { choice = "greed", player = 1, item = 2 })
    AddPattern("LOOT_ROLL_DISENCHANT", "choice", { choice = "disenchant", player = 1, item = 2 })
    AddPattern("LOOT_ROLL_TRANSMOG", "choice", { choice = "disenchant", player = 1, item = 2 })
    AddPattern("LOOT_ROLL_PASSED", "choice", { choice = "pass", player = 1, item = 2 })
    AddPattern("LOOT_ROLL_PASSED_AUTO", "choice", { choice = "pass", player = 1, item = 2 })
    AddPattern("LOOT_ROLL_PASSED_AUTO_FEMALE", "choice", { choice = "pass", player = 1, item = 2 })
    AddPattern("LOOT_ROLL_NEED_SELF", "choice", { choice = "need", self = true, item = 1 })
    AddPattern("LOOT_ROLL_GREED_SELF", "choice", { choice = "greed", self = true, item = 1 })
    AddPattern("LOOT_ROLL_DISENCHANT_SELF", "choice", { choice = "disenchant", self = true, item = 1 })
    AddPattern("LOOT_ROLL_TRANSMOG_SELF", "choice", { choice = "disenchant", self = true, item = 1 })
    AddPattern("LOOT_ROLL_PASSED_SELF", "choice", { choice = "pass", self = true, item = 1 })
    AddPattern("LOOT_ROLL_PASSED_SELF_AUTO", "choice", { choice = "pass", self = true, item = 1 })
    AddPattern("LOOT_ROLL_ROLLED_NEED", "roll", { choice = "need", roll = 1, item = 2, player = 3 })
    AddPattern("LOOT_ROLL_ROLLED_GREED", "roll", { choice = "greed", roll = 1, item = 2, player = 3 })
    AddPattern("LOOT_ROLL_ROLLED_DE", "roll", { choice = "disenchant", roll = 1, item = 2, player = 3 })
    AddPattern("LOOT_ROLL_ROLLED_TRANSMOG", "roll", { choice = "disenchant", roll = 1, item = 2, player = 3 })
    AddPattern("LOOT_ROLL_WON", "won", { player = 1, item = 2 })
    AddPattern("LOOT_ROLL_WON_NO_SPAM_NEED", "won", { player = 1, item = 2 })
    AddPattern("LOOT_ROLL_WON_NO_SPAM_GREED", "won", { player = 1, item = 2 })
    AddPattern("LOOT_ROLL_WON_NO_SPAM_DE", "won", { player = 1, item = 2 })
    AddPattern("LOOT_ROLL_YOU_WON", "won", { self = true, item = 1 })
    AddPattern("LOOT_ROLL_YOU_WON_NO_SPAM_NEED", "won", { self = true, item = 1 })
    AddPattern("LOOT_ROLL_YOU_WON_NO_SPAM_GREED", "won", { self = true, item = 1 })
    AddPattern("LOOT_ROLL_YOU_WON_NO_SPAM_DE", "won", { self = true, item = 1 })
    AddPattern("LOOT_ROLL_ALL_PASSED", "allpassed", { item = 1 })
    -- Most specific first, so "You won" and "automatically passed" are
    -- not swallowed by "%s won" and "%s passed".
    table.sort(patterns, function(a, b) return a.literal > b.literal end)
end

local function Parse(message)
    for _, entry in ipairs(patterns) do
        local captures = { message:match(entry.pattern) }
        if captures[1] then
            local byArg = {}
            for i, argNo in ipairs(entry.order) do byArg[argNo] = captures[i] end
            local f = entry.fields
            return entry.kind, {
                choice = f.choice,
                player = f.self and UnitName("player") or (f.player and byArg[f.player]),
                item = f.item and byArg[f.item],
                roll = f.roll and tonumber(byArg[f.roll]),
            }
        end
    end
end

------------------------------------------------------------------------
-- Group members and roll records
------------------------------------------------------------------------

local function ShortName(name)
    if not name then return nil end
    if Ambiguate then return Ambiguate(name, "short") end
    return (name:gsub("%-.*$", ""))
end

-- Ordered list of { name, class } for the group, the player first.
local function GroupMembers()
    local members = {}
    local function add(unit)
        local name = UnitName(unit)
        if name and name ~= UNKNOWNOBJECT then
            local _, class = UnitClass(unit)
            members[#members + 1] = { name = ShortName(name), class = class }
        end
    end
    add("player")
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            if not UnitIsUnit("raid" .. i, "player") then add("raid" .. i) end
        end
    else
        for i = 1, 4 do
            if UnitExists("party" .. i) then add("party" .. i) end
        end
    end
    return members
end

local function ItemIDFromLink(link)
    return link and tonumber(link:match("item:(%d+)"))
end

local function FindRoll(itemID)
    for _, roll in ipairs(rolls) do
        if roll.itemID == itemID and not roll.finished then return roll end
    end
    for i = #rolls, 1, -1 do
        if rolls[i].itemID == itemID then return rolls[i] end
    end
end

local function NewRoll(link, texture, members)
    local roll = {
        itemID = ItemIDFromLink(link),
        link = link,
        texture = texture,
        started = GetTime(),
        expires = GetTime() + 75,
        members = members or GroupMembers(),
        choices = {},   -- name -> { choice = "need", roll = 87 }
        finished = false,
        winner = nil,
    }
    if not roll.texture then
        local getInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
        if getInstant and link then roll.texture = select(5, getInstant(link)) end
    end
    rolls[#rolls + 1] = roll
    return roll
end

local function Finish(roll, winner)
    roll.finished = true
    roll.winner = winner
    roll.expires = GetTime() + LINGER
end

------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------

local function SetChoiceTexture(texture, choice)
    local info = CHOICE[choice]
    if not info then
        texture:SetTexture(nil)
        return
    end
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(info.atlas) then
        texture:SetAtlas(info.atlas)
    else
        texture:SetTexture(info.file)
    end
end

local function ClassColor(class)
    local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if color then return color.r, color.g, color.b end
    return 1, 1, 1
end

local function PartyAnchor()
    if PartyFrame and PartyFrame.IsShown then return PartyFrame end
    if PartyMemberFrame1 then return PartyMemberFrame1 end
    return PlayerFrame
end

local function Place()
    if not window then return end
    window:ClearAllPoints()
    local side = db.side
    if side == "free" and db.pos then
        window:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", db.pos.x, db.pos.y)
    elseif side == "chat" and ChatFrame1 then
        window:SetPoint("BOTTOMLEFT", ChatFrame1, "TOPLEFT", 0, 28)
    elseif side == "partyleft" then
        local anchor = PartyAnchor()
        if anchor then window:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -6, 0) end
    else
        local anchor = PartyAnchor()
        if anchor then window:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 6, 0) end
    end
    if window:GetNumPoints() == 0 then
        window:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 300, -200)
    end
end

local function SavePosition()
    if not window then return end
    local left, top = window:GetLeft(), window:GetTop()
    if left and top then
        db.pos = { x = left, y = top }
    end
end

local function CreateBlock(index)
    local b = CreateFrame("Frame", nil, window)
    b:SetWidth(WIDTH - 2 * PAD)

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(ITEM_ICON, ITEM_ICON)
    b.icon:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    b.title = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.title:SetPoint("LEFT", b.icon, "RIGHT", 4, 0)
    b.title:SetPoint("RIGHT", b, "RIGHT", 0, 0)
    b.title:SetJustifyH("LEFT")
    b.title:SetWordWrap(false)

    b.iconButton = CreateFrame("Button", nil, b)
    b.iconButton:SetAllPoints(b.icon)
    b.iconButton:SetScript("OnEnter", function(self)
        if b.link then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(b.link)
            GameTooltip:Show()
        end
    end)
    b.iconButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    b.rows = {}
    b.summary = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.summary:SetJustifyH("LEFT")
    b.summary:SetPoint("LEFT", b, "LEFT", 4, 0)
    b.summary:SetPoint("RIGHT", b, "RIGHT", 0, 0)
    return b
end

local function GetRow(block, i)
    local row = block.rows[i]
    if row then return row end
    row = CreateFrame("Frame", nil, block)
    row:SetHeight(ROW_H)
    row:SetPoint("LEFT", block, "LEFT", 4, 0)
    row:SetPoint("RIGHT", block, "RIGHT", 0, 0)
    row.choice = row:CreateTexture(nil, "ARTWORK")
    row.choice:SetSize(ICON, ICON)
    row.choice:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row.choice, "RIGHT", 4, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.value:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    row.value:SetJustifyH("RIGHT")
    row.name:SetPoint("RIGHT", row.value, "LEFT", -4, 0)
    block.rows[i] = row
    return row
end

local function FillBlock(block, roll)
    block.link = roll.link
    block.icon:SetTexture(roll.texture or 134400)
    local title = roll.link or "?"
    if roll.finished then
        if roll.winner then
            title = title .. "  |cffffd100won by " .. roll.winner .. "|r"
        elseif roll.allPassed then
            title = title .. "  |cff9d9d9dall passed|r"
        end
    end
    block.title:SetText(title)

    local members = roll.members
    local shown = math.min(#members, MAX_ROWS)
    local y = -(ITEM_ICON + 2)
    for i = 1, shown do
        local member = members[i]
        local row = GetRow(block, i)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", block, "TOPLEFT", 4, y)
        row:SetPoint("RIGHT", block, "RIGHT", 0, 0)
        row.name:SetText(member.name)
        row.name:SetTextColor(ClassColor(member.class))
        local entry = roll.choices[member.name]
        if entry then
            SetChoiceTexture(row.choice, entry.choice)
            row.choice:SetAlpha(1)
            local label = CHOICE[entry.choice] and CHOICE[entry.choice].label or ""
            if entry.roll then
                row.value:SetText(label .. " " .. entry.roll)
            else
                row.value:SetText(label)
            end
            if roll.winner and member.name == roll.winner then
                row.value:SetTextColor(1, 0.82, 0)
            else
                row.value:SetTextColor(0.9, 0.9, 0.9)
            end
        else
            row.choice:SetTexture(nil)
            row.choice:SetAlpha(0)
            row.value:SetText(roll.finished and "" or "|cff9d9d9d...|r")
            row.value:SetTextColor(0.9, 0.9, 0.9)
        end
        row:Show()
        y = y - ROW_H
    end
    for i = shown + 1, #block.rows do block.rows[i]:Hide() end

    -- Choices by people outside the first rows (big raids) as a summary.
    local extra = 0
    local counts = { need = 0, greed = 0, pass = 0, disenchant = 0 }
    for name, entry in pairs(roll.choices) do
        local listed = false
        for i = 1, shown do
            if members[i].name == name then listed = true break end
        end
        if not listed then
            extra = extra + 1
            counts[entry.choice] = (counts[entry.choice] or 0) + 1
        end
    end
    if extra > 0 then
        block.summary:ClearAllPoints()
        block.summary:SetPoint("TOPLEFT", block, "TOPLEFT", 4, y)
        block.summary:SetText(string.format("+%d others: need %d, greed %d, pass %d",
            extra, counts.need, counts.greed, counts.pass))
        block.summary:Show()
        y = y - ROW_H
    else
        block.summary:Hide()
    end
    block:SetHeight(-y)
    return -y
end

local function Refresh()
    if not window then return end
    if #rolls == 0 then
        window:Hide()
        return
    end
    local y = -PAD
    for i, roll in ipairs(rolls) do
        local block = blocks[i]
        if not block then
            block = CreateBlock(i)
            blocks[i] = block
        end
        block:ClearAllPoints()
        block:SetPoint("TOPLEFT", window, "TOPLEFT", PAD, y)
        local h = FillBlock(block, roll)
        block:Show()
        y = y - h - 6
    end
    for i = #rolls + 1, #blocks do blocks[i]:Hide() end
    window:SetHeight(-y + PAD - 6)
    window:Show()
end

local function CreateWindow()
    local ok, f = pcall(CreateFrame, "Frame", "UlRemedyRollFrame", UIParent, "TooltipBackdropTemplate")
    if not ok or not f then
        f = CreateFrame("Frame", "UlRemedyRollFrame", UIParent)
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.7)
    end
    f:SetWidth(WIDTH)
    f:SetHeight(40)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        db.side = "free"
        SavePosition()
        Place()
        print(UlRemedy.name .. ": loot roll window is now free; /ur rollside puts it back by the party frames.")
    end)
    f:Hide()
    return f
end

------------------------------------------------------------------------
-- Housekeeping
------------------------------------------------------------------------

local ticker

local function Prune()
    local now = GetTime()
    local changed = false
    for i = #rolls, 1, -1 do
        if rolls[i].expires <= now then
            table.remove(rolls, i)
            changed = true
        end
    end
    if changed then Refresh() end
    if #rolls == 0 and ticker then
        ticker:Cancel()
        ticker = nil
    end
end

local function EnsureTicker()
    if not ticker and C_Timer and C_Timer.NewTicker then
        ticker = C_Timer.NewTicker(1, Prune)
    end
end

local function Show()
    if not window then window = CreateWindow() end
    Place()
    Refresh()
    EnsureTicker()
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------

local function OnStartRoll(rollID, rollTime)
    local link = GetLootRollItemLink(rollID)
    if not link then return end
    local texture = GetLootRollItemInfo(rollID)
    local itemID = ItemIDFromLink(link)
    local roll = FindRoll(itemID)
    if roll and not roll.finished then
        roll.expires = math.max(roll.expires, GetTime() + ((rollTime or 60000) / 1000) + LINGER)
    else
        roll = NewRoll(link, texture)
        roll.expires = GetTime() + ((rollTime or 60000) / 1000) + LINGER
    end
    roll.rollID = rollID
    Show()
end

local function OnLootMessage(message)
    local kind, info = Parse(message)
    if not kind then return end
    local itemID = ItemIDFromLink(info.item)
    if not itemID then return end
    local roll = FindRoll(itemID)
    if not roll then
        roll = NewRoll(info.item)
    end
    local player = ShortName(info.player)
    if kind == "choice" then
        local entry = roll.choices[player] or {}
        entry.choice = info.choice
        roll.choices[player] = entry
        -- Someone who joined after the roll started still gets a row.
        local listed = false
        for _, m in ipairs(roll.members) do
            if m.name == player then listed = true break end
        end
        if not listed then roll.members[#roll.members + 1] = { name = player } end
    elseif kind == "roll" then
        local entry = roll.choices[player] or { choice = info.choice }
        entry.roll = info.roll
        roll.choices[player] = entry
    elseif kind == "won" then
        Finish(roll, player)
    elseif kind == "allpassed" then
        roll.allPassed = true
        Finish(roll, nil)
    end
    Show()
end

-- Fake roll with the current group, for placing the window.
function UlRemedy.LootRollTest()
    if not db then return end
    local members = GroupMembers()
    local link = "|cffa335ee|Hitem:19019::::::::60:::::|h[Thunderfury, Blessed Blade of the Windseeker]|h|r"
    local roll = NewRoll(link, 135349, members)
    roll.expires = GetTime() + 20
    local choices = { "need", "greed", "pass" }
    for i, m in ipairs(members) do
        if i > 1 then
            roll.choices[m.name] = { choice = choices[(i % 3) + 1], roll = (i * 37) % 100 }
        end
    end
    Show()
    print(UlRemedy.name .. ": showing a test roll for 20 seconds. Drag the window to place it freely, or /ur rollside to cycle sides.")
end

function UlRemedy.CycleLootRollSide()
    if not db then return end
    local pos = 1
    for i, side in ipairs(SIDES) do
        if side == db.side then pos = i end
    end
    db.side = SIDES[(pos % #SIDES) + 1]
    if db.side == "free" and not db.pos then
        db.side = SIDES[1]
    end
    Place()
    print(UlRemedy.name .. ": loot roll window: " .. SIDE_LABEL[db.side] .. ".")
    if UlRemedy.RefreshOptions then UlRemedy.RefreshOptions() end
end

function UlRemedy.LootRollSideLabel()
    return db and SIDE_LABEL[db.side] or SIDE_LABEL.partyright
end

function UlRemedy.RefreshLootRolls()
    if not Enabled() then
        wipe(rolls)
        if window then window:Hide() end
    end
end

local frame = CreateFrame("Frame", "UlRemedyLootRollFrame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("START_LOOT_ROLL")
frame:RegisterEvent("CHAT_MSG_LOOT")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:SetScript("OnEvent", function(self, event, arg1, arg2)
    if event == "ADDON_LOADED" then
        if arg1 == UlRemedy.name then
            InitDB()
            self:UnregisterEvent("ADDON_LOADED")
        end
        return
    end
    if event == "PLAYER_LOGIN" then
        local ok, err = pcall(BuildPatterns)
        if not ok then Report(err) end
        self:UnregisterEvent("PLAYER_LOGIN")
        return
    end
    if not Enabled() or not db then return end
    local ok, err
    if event == "START_LOOT_ROLL" then
        ok, err = pcall(OnStartRoll, arg1, arg2)
    elseif event == "CHAT_MSG_LOOT" then
        ok, err = pcall(OnLootMessage, arg1)
    elseif event == "GROUP_ROSTER_UPDATE" then
        ok, err = pcall(function() if window and window:IsShown() then Place() end end)
    else
        return
    end
    if not ok then Report(err) end
end)
