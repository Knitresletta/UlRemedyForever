-- Fishing: one key equips the pole, casts the line and hooks the catch,
-- and the splash can be made easier to hear.
--
-- The hook half rides on the client's own soft targeting: the bobber is a
-- game object, the camera picks it as the "soft interact" target, and the
-- Interact binding takes the catch. The key set under Keybindings is a
-- plain click on a secure button that casts Fishing; while your bobber is
-- the soft interact target the same key is rebound (override binding) to
-- Interact, and the override is dropped again when the bobber is gone.
-- On Forever the soft interact unit's GUID can be a secret value; then
-- whatever the client has picked while the line is out counts as the
-- bobber, which is what the Interact key would act on anyway.
-- Without a fishing pole in hand the button's macro is "/equip <best pole
-- in your bags>" instead of the cast, so the first press equips and the
-- next one casts; the macro is rewritten out of combat whenever your
-- equipment or bags change. All three are the client's own actions, the
-- module only chooses which one the key means at the moment.
--
-- Soft targeting is off for keyboard and mouse by default and reaches ten
-- yards, too short for most casts. While Fishing is being channeled the
-- module turns it on (keyboard and gamepad) with thirty yards of reach,
-- and puts the previous values back when the channel ends. The previous
-- values are kept in the saved variables, so a reload in the middle of a
-- cast still restores them at the next login.
--
-- Fishing Sound: while the channel runs, music and ambience are muted and
-- sound effects turned up, so the splash stands out. Restored afterwards
-- the same way as the soft target settings.
--
-- Left alone on purpose: the catch is never hooked for you; you still
-- press the key when the bobber splashes. The weapons the pole replaced
-- are not put back; that is one more press of your own.

local BOBBER_ID = 35591                 -- game object id of the fishing bobber
local FISHING_SPELL = 7620              -- Apprentice Fishing: only used for the localized spell name
local BINDING = "CLICK UlRemedyFishingButton:LeftButton"
local WEAPON_CLASS, POLE_SUBCLASS = 2, 20   -- item class Weapon, subclass Fishing Poles
local MAIN_HAND = 16
local POLL = 0.1                        -- seconds between soft target checks while fishing

BINDING_HEADER_ULREMEDYFOREVER = "UlRemedyForever"
BINDING_NAME_CLICK_UlRemedyFishingButton_LeftButton = "Fish: cast, then hook"

local SOFT_CVARS = { SoftTargetInteract = "3", SoftTargetInteractRange = "30" }
local SOUND_CVARS = {
    Sound_EnableAllSound = "1", Sound_EnableSFX = "1", Sound_SFXVolume = "1",
    Sound_MusicVolume = "0", Sound_AmbienceVolume = "0", Sound_EnableSoundWhenGameIsInBG = "1",
}

local frame = CreateFrame("Frame")
local fishingName                       -- localized "Fishing"
local channeling = false
local overrideOn = false
local pollTicker
local lastEvent = "none"
local keyMeans = "cast"                 -- what the button's macro does right now
local guidState = "none"                -- what the last soft interact GUID looked like, for /ur fish

local function Enabled(key)
    return UlRemedy.enabled and UlRemedy.enabled[key]
end

-- A secret value cannot be turned into a string, not even by tostring.
local function Plain(v)
    if issecretvalue and issecretvalue(v) then return "<secret>" end
    return tostring(v)
end

local function SpellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    if GetSpellInfo then return (GetSpellInfo(id)) end
    return nil
end

------------------------------------------------------------------------
-- The cast button
------------------------------------------------------------------------

local cast = CreateFrame("Button", "UlRemedyFishingButton", UIParent, "SecureActionButtonTemplate")
cast:SetAttribute("type", "macro")
cast:SetAttribute("macrotext", "/cast Fishing")

local function IsPole(itemID)
    if not itemID then return false end
    local _, _, _, _, _, classID, subID = C_Item.GetItemInfoInstant(itemID)
    return classID == WEAPON_CLASS and subID == POLE_SUBCLASS
end

-- The pole in your bags with the highest item level, by name (what /equip
-- takes), or nil when there is none.
local function BestPole()
    local best, bestLevel
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
            local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
            if ok and info and IsPole(info.itemID) then
                local name, _, _, level = C_Item.GetItemInfo(info.itemID)
                level = level or 0
                if name and (not best or level > bestLevel) then best, bestLevel = name, level end
            end
        end
    end
    return best
end

-- Equip the pole when none is in hand, cast otherwise. Attributes on a
-- secure button cannot change in combat; the next out-of-combat event
-- catches up.
local function UpdateMacro()
    if InCombatLockdown() then return end
    local text, means = "/cast " .. (fishingName or "Fishing"), "cast"
    if Enabled("fishing") and not IsPole(GetInventoryItemID("player", MAIN_HAND)) then
        local pole = BestPole()
        if pole then text, means = "/equip " .. pole, "equip " .. pole end
    end
    if cast:GetAttribute("macrotext") ~= text then cast:SetAttribute("macrotext", text) end
    keyMeans = means
end

-- A bound key clicks on key down or key up depending on the client
-- setting; register for the same edge, otherwise the click is either lost
-- or fires twice (and the second cast would restart the channel).
local function RegisterClicks()
    if InCombatLockdown() then return end
    if GetCVarBool("ActionButtonUseKeyDown") then
        cast:RegisterForClicks("AnyDown")
    else
        cast:RegisterForClicks("AnyUp")
    end
end

------------------------------------------------------------------------
-- Soft target and the key override
------------------------------------------------------------------------

-- Whether the soft interact target is your bobber. The GUID came back as
-- a secret value on every poll of a session on 06.11.2026 (strsplit on it
-- throws, 228 errors in two minutes), so a secret GUID is read as "the
-- client has picked something": while Fishing is channeled that is taken
-- to be the bobber, and the key then does what Interact would do.
local function BobberTargeted()
    local guid = UnitGUID("softinteract")
    if issecretvalue and issecretvalue(guid) then
        guidState = "secret, taken as the bobber while channeling"
        return channeling
    end
    if not guid then
        guidState = "none"
        return false
    end
    guidState = "plain"
    local kind, _, _, _, _, id = strsplit("-", guid)
    return kind == "GameObject" and tonumber(id) == BOBBER_ID
end

local function UpdateOverride()
    if InCombatLockdown() then return end
    local want = Enabled("fishing") and BobberTargeted() or false
    if want == overrideOn then return end
    ClearOverrideBindings(frame)
    if want then
        for i = 1, select("#", GetBindingKey(BINDING)) do
            local key = select(i, GetBindingKey(BINDING))
            if key then SetOverrideBinding(frame, true, key, "INTERACTTARGET") end
        end
    end
    overrideOn = want
end

------------------------------------------------------------------------
-- Settings changed while the line is out, restored afterwards
------------------------------------------------------------------------

local function Saved()
    UlRemedyForeverDB.fishingSaved = UlRemedyForeverDB.fishingSaved or {}
    return UlRemedyForeverDB.fishingSaved
end

local function Apply(cvars)
    local saved = Saved()
    for name, value in pairs(cvars) do
        if saved[name] == nil then saved[name] = GetCVar(name) or "" end
        SetCVar(name, value)
    end
end

local function Restore()
    local saved = UlRemedyForeverDB and UlRemedyForeverDB.fishingSaved
    if not saved then return end
    for name, value in pairs(saved) do
        SetCVar(name, value)
    end
    UlRemedyForeverDB.fishingSaved = nil
end

local function IsFishing(spellID)
    if not spellID then return false end
    local name = SpellName(spellID)
    return name ~= nil and name == fishingName
end

local function OnChannelStart()
    channeling = true
    if Enabled("fishing") then Apply(SOFT_CVARS) end
    if Enabled("fishsound") then Apply(SOUND_CVARS) end
    if not pollTicker then
        pollTicker = C_Timer.NewTicker(POLL, UpdateOverride)
    end
    UpdateOverride()
end

local function OnChannelStop()
    channeling = false
    if pollTicker then
        pollTicker:Cancel()
        pollTicker = nil
    end
    Restore()
    UpdateOverride()
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------

function UlRemedy.RefreshFishing()
    RegisterClicks()
    overrideOn = nil                    -- force a fresh look at the binding
    UpdateOverride()
    UpdateMacro()
end

frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
frame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
frame:RegisterEvent("UPDATE_BINDINGS")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("CVAR_UPDATE")
frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
frame:RegisterEvent("BAG_UPDATE_DELAYED")
pcall(frame.RegisterEvent, frame, "PLAYER_SOFT_INTERACT_CHANGED")

frame:SetScript("OnEvent", function(self, event, unit, _, spellID)
    if event == "PLAYER_LOGIN" then
        fishingName = SpellName(FISHING_SPELL) or "Fishing"
        Restore()                       -- a reload mid-cast left the previous values here
        UlRemedy.RefreshFishing()
    elseif event == "PLAYER_LOGOUT" then
        Restore()
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
        if unit == "player" and IsFishing(spellID) then
            lastEvent = "channel start"
            OnChannelStart()
        end
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        if unit == "player" and channeling and IsFishing(spellID) then
            lastEvent = "channel stop"
            OnChannelStop()
        end
    elseif event == "PLAYER_SOFT_INTERACT_CHANGED" then
        lastEvent = "soft interact changed"
        UpdateOverride()
    elseif event == "UPDATE_BINDINGS" or event == "PLAYER_REGEN_ENABLED" then
        overrideOn = nil
        UpdateOverride()
        UpdateMacro()
    elseif event == "PLAYER_EQUIPMENT_CHANGED" or event == "BAG_UPDATE_DELAYED" then
        UpdateMacro()
    elseif event == "CVAR_UPDATE" and unit == "ActionButtonUseKeyDown" then
        RegisterClicks()
    end
end)

------------------------------------------------------------------------
-- Diagnostics: /ur fish
------------------------------------------------------------------------

function UlRemedy.FishingDebug()
    local keys = { GetBindingKey(BINDING) }
    print("|cffffcc00" .. UlRemedy.name .. "|r fishing:")
    print("  fishing " .. (Enabled("fishing") and "on" or "off")
        .. ", sound " .. (Enabled("fishsound") and "on" or "off"))
    print("  key: " .. (#keys > 0 and table.concat(keys, ", ") or "none (set one under Keybindings > AddOns > UlRemedyForever)"))
    print("  spell: " .. tostring(fishingName) .. ", channeling: " .. tostring(channeling) .. ", last event: " .. lastEvent)
    local bobber = BobberTargeted()
    print("  soft interact: " .. Plain(UnitName("softinteract")) .. " " .. Plain(UnitGUID("softinteract"))
        .. " (guid " .. guidState .. (bobber and ", bobber)" or ")"))
    print("  key means: " .. (overrideOn and "Interact (hook)" or keyMeans))
    print("  pole in hand: " .. tostring(IsPole(GetInventoryItemID("player", MAIN_HAND))) .. ", best pole in bags: " .. tostring(BestPole()))
    print("  SoftTargetInteract=" .. tostring(GetCVar("SoftTargetInteract"))
        .. " SoftTargetInteractRange=" .. tostring(GetCVar("SoftTargetInteractRange"))
        .. " ActionButtonUseKeyDown=" .. tostring(GetCVar("ActionButtonUseKeyDown")))
    local saved = UlRemedyForeverDB and UlRemedyForeverDB.fishingSaved
    if saved then
        local parts = {}
        for k, v in pairs(saved) do parts[#parts + 1] = k .. "=" .. tostring(v) end
        print("  to restore after the cast: " .. table.concat(parts, " "))
    else
        print("  nothing to restore.")
    end
end
