-- Player Notes: a note of your own on another player, shown in their
-- tooltip.
--
-- Right-click a player (target, focus, party or raid member, a name in
-- chat, a friend or guild member in those lists) and the menu has
-- "Add note", or "Edit note" and "Remove note" when one exists. The note
-- is typed in a small dialog. Notes are kept per account, keyed by
-- Name-Realm (the realm as GetNormalizedRealmName gives it, so a note made
-- on one character shows on all of them), in UlRemedyForeverNotesDB,
-- which Core's settings pruning never touches. Players only: NPCs share
-- names, and the menu entry is not offered for them.
--
-- The menu entries go through the retail menu system (Menu.ModifyMenu,
-- 11.0 and later), which Forever's 12.x client is expected to carry; not
-- verified on Forever before 1.26.0, /ur notes says whether it was found.
-- The player menus are tagged MENU_UNIT_<kind>; the kinds below are the
-- ones that can mean another player. The callback is only handed the
-- menu's own description object and its context (unit, name, server), it
-- never touches Blizzard's entries. Without the menu system the commands
-- still work: /ur note <name> <text> sets, /ur note <name> shows, /ur
-- unnote <name> removes, /ur notes lists them all.
--
-- The tooltip line comes from the unit tooltip post-call
-- (TooltipDataProcessor) where the client has it, else the
-- OnTooltipSetUnit script hook, the same split as the item tooltips in
-- ReagentTooltip. The unit's name and realm are read with UnitName; a
-- secret value there (Forever's soft-target GUIDs are, names have not
-- been seen as such) means no line rather than an error.

local DIALOG = "ULREMEDY_PLAYER_NOTE"
local MAX_LETTERS = 200
local LINE_COLOR = { 0.6, 0.85, 1 } -- light blue, apart from Blizzard's gold and white

-- Menu kinds whose unit or name can be another player.
local MENU_KINDS = {
    "PLAYER", "TARGET", "FOCUS", "PARTY", "RAID_PLAYER", "RAID", "ENEMY_PLAYER",
    "FRIEND", "FRIEND_OFFLINE", "BN_FRIEND", "GUILD", "GUILD_OFFLINE", "CHAT_ROSTER",
    "COMMUNITIES_WOW_MEMBER", "COMMUNITIES_GUILD_MEMBER", "ARENAENEMY",
}

local db
local menuHooked = false
local lastError
local probe = false          -- /ur noteprobe: print what menus and tooltips see

local function Say(text)
    print(UlRemedy.name .. ": " .. text)
end

local function Report(err)
    if err == lastError then return end
    lastError = err
    Say("player notes: " .. tostring(err))
end

local function Enabled()
    return UlRemedy.enabled and UlRemedy.enabled.notes
end

local function IsSecret(v)
    return issecretvalue and issecretvalue(v)
end

------------------------------------------------------------------------
-- Data
------------------------------------------------------------------------

local function InitDB()
    if not UlRemedyForeverNotesDB then UlRemedyForeverNotesDB = {} end
    db = UlRemedyForeverNotesDB
    db.notes = db.notes or {}
end

local function MyRealm()
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    if not realm or realm == "" then
        realm = (GetRealmName() or ""):gsub("%s+", "")
    end
    return realm
end

-- "Name-Realm" from a name that may or may not carry its realm, with the
-- realm part normalized (no spaces). Nil for anything that is not a
-- plain name.
local function KeyFor(name, realm)
    if type(name) ~= "string" or IsSecret(name) or name == "" then return nil end
    if IsSecret(realm) then realm = nil end
    local n, r = name:match("^([^%-]+)%-(.+)$")
    if n then name, realm = n, r end
    if not realm or realm == "" then realm = MyRealm() end
    realm = realm:gsub("%s+", "")
    -- Capitalize like the game does, so "bob" and "Bob" are one key.
    name = name:sub(1, 1):upper() .. name:sub(2)
    return name .. "-" .. realm
end

-- The key as shown: without the realm when it is this one.
local function ShortName(key)
    local name, realm = key:match("^(.-)%-(.+)$")
    if realm == MyRealm() then return name end
    return key
end

local function GetNote(key)
    return key and db and db.notes[key] or nil
end

local function SetNote(key, text)
    if not db or not key then return end
    text = strtrim(text or "")
    if text == "" then
        db.notes[key] = nil
        Say("note on " .. ShortName(key) .. " removed.")
    else
        db.notes[key] = text:sub(1, MAX_LETTERS)
        Say("note on " .. ShortName(key) .. ": " .. db.notes[key])
    end
end

------------------------------------------------------------------------
-- Dialog
------------------------------------------------------------------------

StaticPopupDialogs[DIALOG] = {
    text = "Note on %s",
    button1 = SAVE or "Save",
    button2 = CANCEL or "Cancel",
    hasEditBox = true,
    maxLetters = MAX_LETTERS,
    editBoxWidth = 300,
    OnShow = function(self, key)
        local box = self.editBox or self.EditBox
        if not box then return end
        box:SetText(GetNote(key) or "")
        box:HighlightText()
        box:SetFocus()
    end,
    OnAccept = function(self, key)
        local box = self.editBox or self.EditBox
        if box then SetNote(key, box:GetText()) end
    end,
    EditBoxOnEnterPressed = function(self, key)
        local parent = self:GetParent()
        SetNote(key, self:GetText())
        parent:Hide()
    end,
    EditBoxOnEscapePressed = function(self)
        self:GetParent():Hide()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function OpenDialog(key)
    if not key then return end
    StaticPopup_Show(DIALOG, ShortName(key), nil, key)
end

------------------------------------------------------------------------
-- Right-click menu
------------------------------------------------------------------------

-- The player a menu is about, as a key, or nil when it is not a player
-- (an NPC target, a pet) or the context gives no usable name.
local function KeyFromContext(contextData)
    if type(contextData) ~= "table" then return nil end
    local unit = contextData.unit
    if unit and not IsSecret(unit) and UnitExists(unit) then
        if not UnitIsPlayer(unit) then return nil end
        local name, realm = UnitName(unit)
        return KeyFor(name, realm)
    end
    -- Chat names, friends, guild members: a name and maybe a server.
    return KeyFor(contextData.name, contextData.server)
end

local function AddMenuEntries(owner, rootDescription, contextData)
    if not Enabled() then return end
    local key = KeyFromContext(contextData)
    if probe then
        local c = type(contextData) == "table" and contextData or {}
        local unitName, unitRealm
        if c.unit and not IsSecret(c.unit) and UnitExists(c.unit) then unitName, unitRealm = UnitName(c.unit) end
        Say(string.format("menu probe: unit=%s name=%s server=%s UnitName=%s/%s isPlayer=%s key=%s myRealm=%s",
            tostring(c.unit), tostring(c.name), tostring(c.server), tostring(unitName), tostring(unitRealm),
            tostring(c.unit and UnitExists(c.unit) and UnitIsPlayer(c.unit)), tostring(key), MyRealm()))
    end
    if not key then return end
    if not rootDescription or not rootDescription.CreateButton then return end
    local note = GetNote(key)
    if rootDescription.CreateDivider then rootDescription:CreateDivider() end
    if note then
        rootDescription:CreateButton("Edit note", function() OpenDialog(key) end)
        rootDescription:CreateButton("Remove note", function() SetNote(key, "") end)
    else
        rootDescription:CreateButton("Add note", function() OpenDialog(key) end)
    end
end

local function HookMenus()
    if menuHooked then return end
    if not (Menu and Menu.ModifyMenu) then return end
    for _, kind in ipairs(MENU_KINDS) do
        pcall(Menu.ModifyMenu, "MENU_UNIT_" .. kind, function(owner, rootDescription, contextData)
            local ok, err = pcall(AddMenuEntries, owner, rootDescription, contextData)
            if not ok then Report(err) end
        end)
    end
    menuHooked = true
end

------------------------------------------------------------------------
-- Tooltip
------------------------------------------------------------------------

local function AddTooltipLine(tooltip)
    if not Enabled() or not db then return end
    local _, unit = tooltip:GetUnit()
    if not unit or IsSecret(unit) or not UnitExists(unit) or not UnitIsPlayer(unit) then return end
    local name, realm = UnitName(unit)
    local key = KeyFor(name, realm)
    local note = GetNote(key)
    if probe then
        Say(string.format("tooltip probe: unit=%s UnitName=%s/%s key=%s note=%s", tostring(unit), tostring(name), tostring(realm), tostring(key), tostring(note)))
    end
    if not note then return end
    tooltip:AddLine("Note: " .. note, LINE_COLOR[1], LINE_COLOR[2], LINE_COLOR[3], true)
    tooltip:Show()
end

local function HookTooltips()
    local function Safe(tooltip)
        local ok, err = pcall(AddTooltipLine, tooltip)
        if not ok then Report(err) end
    end
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
       and Enum.TooltipDataType and Enum.TooltipDataType.Unit then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
            if tooltip ~= GameTooltip then return end
            Safe(tooltip)
        end)
    elseif GameTooltip.HookScript then
        GameTooltip:HookScript("OnTooltipSetUnit", Safe)
    end
end

------------------------------------------------------------------------
-- Commands
------------------------------------------------------------------------

-- The name at the front of a command's arguments, and the rest. Forever
-- names can have spaces ("Xavz Storm"), so a name may be quoted.
local function SplitName(args)
    args = strtrim(args or "")
    local name, rest = args:match('^"([^"]+)"%s*(.*)$')
    if not name then name, rest = args:match("^(%S+)%s*(.*)$") end
    return name, rest or ""
end

-- /ur note <name> [text]: with text sets the note, without shows it.
function UlRemedy.PlayerNoteCommand(args)
    if not db then return end
    local name, text = SplitName(args)
    if not name then
        Say('usage: /ur note <name> [text], quote a name with spaces: /ur note "Xavz Storm" text. Without text the note is shown; /ur unnote <name> removes it.')
        return
    end
    local key = KeyFor(name)
    if text ~= "" then
        SetNote(key, text)
    else
        local note = GetNote(key)
        Say(note and ("note on " .. ShortName(key) .. ": " .. note) or ("no note on " .. ShortName(key) .. "."))
    end
end

-- /ur unnote <name>
function UlRemedy.PlayerUnnoteCommand(args)
    if not db then return end
    local name = SplitName(args)
    if not name then
        Say('usage: /ur unnote <name>, quote a name with spaces.')
        return
    end
    local key = KeyFor(name)
    if GetNote(key) then
        SetNote(key, "")
    else
        Say("no note on " .. ShortName(key) .. ".")
    end
end

-- /ur notes: every note, and whether the menu system was found.
function UlRemedy.PlayerNotesList()
    if not db then return end
    local keys = {}
    for key in pairs(db.notes) do keys[#keys + 1] = key end
    table.sort(keys)
    Say(string.format("player notes: %d (feature %s, my realm %s, menu system %s, menus hooked %s, unit tooltip post-call %s, probe %s)",
        #keys, Enabled() and "on" or "off", MyRealm(),
        (Menu and Menu.ModifyMenu) and "found" or "missing, use /ur note",
        tostring(menuHooked),
        (TooltipDataProcessor and Enum.TooltipDataType and Enum.TooltipDataType.Unit) and "yes" or "no, script hook",
        probe and "on" or "off"))
    for _, key in ipairs(keys) do
        print("  " .. ShortName(key) .. ": " .. db.notes[key])
    end
    if lastError then print("  last error: " .. tostring(lastError)) end
end

-- /ur noteprobe: print what every player menu and unit tooltip sees,
-- for when a note made one way does not show another way.
function UlRemedy.PlayerNotesProbe()
    probe = not probe
    Say("note probe " .. (probe and "on: right-click a player or hover one, the fields print in chat" or "off"))
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------

local frame = CreateFrame("Frame", "UlRemedyPlayerNotesFrame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == UlRemedy.name then
        InitDB()
    elseif event == "PLAYER_LOGIN" then
        if not db then InitDB() end
        HookTooltips()
        HookMenus()
    end
end)
