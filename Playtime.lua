-- Playtime: remembers /played for every character you log in with, and
-- shows it in a window of its own: one bar per character, longest first,
-- in class colors, with the total across them. /ur played opens it, and
-- so does the Playtime row in the minimap button's menu.
--
-- The client only tells an addon the played time when asked:
-- RequestTimePlayed() answers with TIME_PLAYED_MSG (total seconds, seconds
-- at this level), and the chat frames print the two "Time played" lines
-- on that same event. The addon asks once a few seconds after login and
-- keeps the lines out of chat for that one answer by unregistering the
-- chat frames from the event while the request is out (see below); a
-- /played typed by hand prints as usual and updates the record too.
--
-- Between answers the current character's time is the last answer plus
-- the clock since then, and at logout (also /reload) the record is moved
-- forward to that moment, so the saved value is never older than the
-- last session. Data lives in its own saved variable
-- (UlRemedyForeverPlayedDB) so Core's settings pruning never touches it.
-- Character keys are "Name-Realm", the same format as the inventory
-- tracker.

local LOGIN_DELAY = 5          -- seconds after login before the silent request
local SILENT_TIMEOUT = 15      -- give up suppressing if no answer comes

local DB
local me, myKey
local silent = false
local lastEvent              -- when the last answer came, for diagnostics
local requested = false
local window

local function Enabled()
    return UlRemedy.enabled and UlRemedy.enabled.playtime
end

------------------------------------------------------------------------
-- Saved data
------------------------------------------------------------------------

local function CharKey()
    local name = UnitName("player")
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    if not realm or realm == "" then
        realm = (GetRealmName() or ""):gsub("%s+", "")
    end
    return name .. "-" .. realm, name, realm
end

local function InitDB()
    if not UlRemedyForeverPlayedDB then UlRemedyForeverPlayedDB = {} end
    DB = UlRemedyForeverPlayedDB
    DB.chars = DB.chars or {}
end

local function InitCharacter()
    local key, name, realm = CharKey()
    myKey = key
    local rec = DB.chars[key]
    if not rec then
        rec = { total = 0, levelTime = 0 }
        DB.chars[key] = rec
    end
    rec.name = name
    rec.realm = realm
    rec.class = select(2, UnitClass("player"))
    rec.level = UnitLevel("player")
    me = rec
end

-- The current character's time right now: the last answer plus the clock
-- since. Other characters are not playing, so their stored total is it.
local function PlayedSeconds(rec)
    if not rec then return 0 end
    local total = rec.total or 0
    if rec == me and rec.at then
        total = total + math.max(0, time() - rec.at)
    end
    return total
end

local function LevelSeconds(rec)
    if not rec then return 0 end
    local t = rec.levelTime or 0
    if rec == me and rec.at then
        t = t + math.max(0, time() - rec.at)
    end
    return t
end

-- Moves the current character's record forward to now, so a stored value
-- read later (by another character, or after a crash) is up to date.
local function Settle()
    if me and me.at then
        me.total = PlayedSeconds(me)
        me.levelTime = LevelSeconds(me)
        me.at = time()
    end
end

------------------------------------------------------------------------
-- Asking the client
------------------------------------------------------------------------

-- Keeping one answer out of chat. The chat frames print the two lines
-- from their own TIME_PLAYED_MSG handler (on the 12.x interface that is
-- ChatFrameMixin:SystemEventHandler calling ChatFrameUtil.DisplayTimePlayed;
-- the old global ChatFrame_DisplayTimePlayed is gone, which is why
-- wrapping it did nothing on Forever). Rather than replace a Blizzard
-- function, the chat frames that have the event registered are
-- unregistered from it while our request is out, and registered again
-- once the answer has arrived (or on a timeout). Event registration is a
-- plain widget method, not protected, and nothing of ours runs inside
-- Blizzard's code.
local MAX_CHAT_FRAMES = 20     -- NUM_CHAT_WINDOWS plus temporary windows
local muted = {}               -- chat frames we unregistered

local function MuteChat()
    for i = 1, MAX_CHAT_FRAMES do
        local f = _G["ChatFrame" .. i]
        if f and f.IsEventRegistered and f:IsEventRegistered("TIME_PLAYED_MSG") then
            local ok = pcall(f.UnregisterEvent, f, "TIME_PLAYED_MSG")
            if ok then muted[#muted + 1] = f end
        end
    end
end

local function UnmuteChat()
    for _, f in ipairs(muted) do
        pcall(f.RegisterEvent, f, "TIME_PLAYED_MSG")
    end
    wipe(muted)
    silent = false
end

local function Request()
    if type(RequestTimePlayed) ~= "function" then return end
    requested = true
    silent = true
    MuteChat()
    RequestTimePlayed()
    C_Timer.After(SILENT_TIMEOUT, function()
        if silent then UnmuteChat() end
    end)
end

local RefreshWindow

local function OnTimePlayed(total, levelTime)
    lastEvent = time()
    if silent then
        -- Not during this dispatch: a frame registered now might still be
        -- handed the event we are hiding.
        C_Timer.After(0, UnmuteChat)
    end
    if not me then return end
    total, levelTime = tonumber(total), tonumber(levelTime)
    if not total then return end
    me.total = total
    me.levelTime = levelTime or me.levelTime or 0
    me.level = UnitLevel("player")
    me.at = time()
    RefreshWindow()
end

------------------------------------------------------------------------
-- Formatting
------------------------------------------------------------------------

function UlRemedy.FormatPlayed(seconds)
    seconds = math.floor(tonumber(seconds) or 0)
    local d = math.floor(seconds / 86400)
    seconds = seconds % 86400
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    if d > 0 then return string.format("%dd %dh %dm", d, h, m) end
    if h > 0 then return string.format("%dh %dm", h, m) end
    return string.format("%dm", m)
end

local function ClassColor(classFile)
    local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if c then return c.r, c.g, c.b end
    return 1, 0.82, 0
end

local function ColoredName(rec)
    local r, g, b = ClassColor(rec.class)
    return string.format("|cff%02x%02x%02x%s|r",
        math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5), rec.name or "?")
end

-- Every character with an answer, longest time first.
local function SortedChars()
    local list = {}
    if not DB then return list end
    for key, rec in pairs(DB.chars) do
        if rec.at then
            rec.key = key
            list[#list + 1] = rec
        end
    end
    table.sort(list, function(a, b)
        local sa, sb = PlayedSeconds(a), PlayedSeconds(b)
        if sa ~= sb then return sa > sb end
        return (a.name or "") < (b.name or "")
    end)
    return list
end

------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------
-- One row per character: name and level on the left, a bar whose length
-- is the character's share of the longest time, and the time at the
-- right. The window's height follows the number of characters. While it
-- is open a ticker redraws it every half minute so the bar of the
-- character you are on keeps growing.

local WIDTH = 460
local ROW_H = 26
local BAR_H = 14
local NAME_W = 130
local TIME_W = 110
local TOP = 58                 -- below the title and the summary line
local BOTTOM = 34              -- room for the footer line
local MIN_ROWS = 3
local MAX_ROWS = 24

local function RowTooltip(self)
    local rec = self.rec
    if not rec then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(ColoredName(rec) .. " |cffaaaaaa(" .. (rec.level or 0) .. ")|r")
    GameTooltip:AddLine(rec.realm or "", 0.7, 0.7, 0.7)
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine("Total", UlRemedy.FormatPlayed(PlayedSeconds(rec)), 1, 1, 1, 1, 1, 1)
    GameTooltip:AddDoubleLine("This level", UlRemedy.FormatPlayed(LevelSeconds(rec)), 1, 1, 1, 1, 1, 1)
    if self.share then
        GameTooltip:AddDoubleLine("Share", string.format("%d%%", self.share), 1, 1, 1, 1, 1, 1)
    end
    if rec.at then
        if rec == me then
            GameTooltip:AddDoubleLine("Counting", "now", 0.7, 0.7, 0.7, 0.7, 0.7, 0.7)
        else
            GameTooltip:AddDoubleLine("Last seen", date("%Y-%m-%d %H:%M", rec.at), 0.7, 0.7, 0.7, 0.7, 0.7, 0.7)
        end
    end
    GameTooltip:Show()
end

local function GetRow(i)
    local row = window.rows[i]
    if row then return row end
    row = CreateFrame("Frame", nil, window)
    row:SetHeight(ROW_H)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.name:SetWidth(NAME_W)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row.track = row:CreateTexture(nil, "BACKGROUND")
    row.track:SetPoint("LEFT", row, "LEFT", NAME_W + 8, 0)
    row.track:SetPoint("RIGHT", row, "RIGHT", -TIME_W - 8, 0)
    row.track:SetHeight(BAR_H)
    row.track:SetColorTexture(1, 1, 1, 0.08)

    row.bar = row:CreateTexture(nil, "ARTWORK")
    row.bar:SetPoint("LEFT", row.track, "LEFT", 0, 0)
    row.bar:SetHeight(BAR_H)

    row.time = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.time:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.time:SetWidth(TIME_W)
    row.time:SetJustifyH("RIGHT")

    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.06)
    row:EnableMouse(true)
    row:SetScript("OnEnter", RowTooltip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    window.rows[i] = row
    return row
end

RefreshWindow = function()
    if not (window and window:IsShown()) then return end
    local list = SortedChars()
    local total, longest = 0, 0
    for _, rec in ipairs(list) do
        local s = PlayedSeconds(rec)
        total = total + s
        if s > longest then longest = s end
    end

    local trackW = WIDTH - 28 - NAME_W - 8 - TIME_W - 8
    local shown = math.min(#list, MAX_ROWS)
    for i = 1, shown do
        local rec = list[i]
        local row = GetRow(i)
        local secs = PlayedSeconds(rec)
        row.rec = rec
        row.share = total > 0 and math.floor(secs / total * 100 + 0.5) or nil
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", window, "TOPLEFT", 14, -(TOP + (i - 1) * ROW_H))
        row:SetPoint("RIGHT", window, "RIGHT", -14, 0)
        row.name:SetText(string.format("%s |cffaaaaaa(%d)|r", ColoredName(rec), rec.level or 0))
        local r, g, b = ClassColor(rec.class)
        row.bar:SetColorTexture(r, g, b, rec == me and 1 or 0.8)
        local frac = longest > 0 and secs / longest or 0
        row.bar:SetWidth(math.max(2, trackW * frac))
        row.time:SetText(UlRemedy.FormatPlayed(secs) .. (rec == me and " |cffaaaaaa+|r" or ""))
        row:Show()
    end
    for i = shown + 1, #window.rows do window.rows[i]:Hide() end

    if #list == 0 then
        window.summary:SetText(requested and "Waiting for the client's answer..." or "Nothing recorded yet. Type /played once.")
    elseif #list == 1 then
        window.summary:SetText(string.format("Total %s on one character", UlRemedy.FormatPlayed(total)))
    else
        window.summary:SetText(string.format("Total |cffffffff%s|r across %d characters", UlRemedy.FormatPlayed(total), #list))
    end
    window:SetHeight(TOP + math.max(MIN_ROWS, shown) * ROW_H + BOTTOM)
end

local function CreateWindow()
    local f = CreateFrame("Frame", "UlRemedyPlaytimeFrame", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(WIDTH, TOP + MIN_ROWS * ROW_H + BOTTOM)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    tinsert(UISpecialFrames, "UlRemedyPlaytimeFrame")
    if f.CloseButton then f.CloseButton:SetScript("OnClick", function() f:Hide() end) end

    local title = f.TitleText or (f.TitleContainer and f.TitleContainer.TitleText)
    if title then title:SetText(UlRemedy.name .. ": Playtime") end

    f.rows = {}

    f.summary = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.summary:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -32)
    f.summary:SetPoint("RIGHT", f, "RIGHT", -14, 0)
    f.summary:SetJustifyH("LEFT")

    f.footer = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.footer:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 12)
    f.footer:SetPoint("RIGHT", f, "RIGHT", -14, 0)
    f.footer:SetJustifyH("LEFT")
    f.footer:SetTextColor(0.6, 0.6, 0.6)
    f.footer:SetText("+ counts up while you play. Hover a row for this level and share.")

    f:SetScript("OnShow", function(self)
        RefreshWindow()
        if not self.ticker then
            self.ticker = C_Timer.NewTicker(30, RefreshWindow)
        end
    end)
    f:SetScript("OnHide", function(self)
        if self.ticker then
            self.ticker:Cancel()
            self.ticker = nil
        end
    end)
    f:Hide()
    return f
end

function UlRemedy.TogglePlaytimeWindow()
    if not window then window = CreateWindow() end
    if window:IsShown() then
        window:Hide()
    else
        if me and not me.at then Request() end
        window:Show()
    end
end

function UlRemedy.PlaytimeDebug()
    local n = #SortedChars()
    print(UlRemedy.name .. ": playtime " .. (Enabled() and "on" or "off")
        .. ", characters with an answer " .. n
        .. ", RequestTimePlayed " .. (type(RequestTimePlayed) == "function" and "present" or "MISSING")
        .. ", last answer " .. (lastEvent and date("%H:%M:%S", lastEvent) or "none")
        .. ", chat frames muted now " .. #muted
        .. (me and me.at and (", this character " .. UlRemedy.FormatPlayed(PlayedSeconds(me))) or ", this character: no answer yet"))
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------

function UlRemedy.RefreshPlaytime()
    if Enabled() and me and not me.at then Request() end
    RefreshWindow()
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("TIME_PLAYED_MSG")
frame:RegisterEvent("PLAYER_LEVEL_UP")
frame:SetScript("OnEvent", function(self, event, arg1, arg2)
    if event == "ADDON_LOADED" and arg1 == UlRemedy.name then
        InitDB()
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        InitCharacter()
        if Enabled() then C_Timer.After(LOGIN_DELAY, Request) end
    elseif event == "PLAYER_LOGOUT" then
        Settle()
    elseif event == "TIME_PLAYED_MSG" then
        pcall(OnTimePlayed, arg1, arg2)
    elseif event == "PLAYER_LEVEL_UP" then
        -- The level clock starts over; the next answer has the exact value.
        if me then
            Settle()
            me.levelTime = 0
            me.level = tonumber(arg1) or UnitLevel("player")
            RefreshWindow()
        end
    end
end)
