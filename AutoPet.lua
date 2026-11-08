-- Auto Pet: summons one of your favorite companion pets when none is out.
--
-- Forever runs the retail pet journal (C_PetJournal, BattlePetSpecies has
-- 121 species in build 70790, 45 of them Forever-new), so favorites are the
-- ones starred in the Pet Journal (Shift+P). The addon only acts at moments
-- where the game itself has taken the pet away: login and reload, coming
-- back to life, landing from a flight, arriving in a new zone, and the end
-- of combat if one of those happened mid-fight. Dismissing the pet by hand
-- is respected until the next such moment.
--
-- Skipped while dead, in combat, on a taxi, stealthed or in a vehicle. If
-- the client has no pet journal the module stays silent; /ur pet says why.

local Print = function(msg) print(UlRemedy.name .. ": " .. msg) end

local pending = false        -- a trigger fired while we could not act
local hinted = false         -- "no favorites" said once per session
local last = {}              -- what the last attempt saw, for /ur pet

local function Journal()
    local j = C_PetJournal
    if not j or not j.GetSummonedPetGUID or not j.SummonRandomPet then return nil end
    return j
end

-- Whether a favorite is starred, as far as the journal list shows. The
-- list honours the Pet Journal's own filters and search box, and is empty
-- until the journal has loaded after login, so "false" is only trusted
-- when the list had pets in it; otherwise nil, cannot tell.
-- GetPetInfoByIndex returns petID, speciesID, owned, customName, level,
-- favorite, isRevoked, ... (favorite is the sixth).
local function HasFavorites(j)
    if not j.GetNumPets or not j.GetPetInfoByIndex then return nil end
    local total = j.GetNumPets()
    if type(total) ~= "number" or total == 0 then return nil end
    for i = 1, total do
        local ok, _, _, _, _, _, isFavorite = pcall(j.GetPetInfoByIndex, i)
        if ok and isFavorite then return true end
    end
    return false
end

-- Why we cannot summon right now, or nil when we can.
local function Blocker()
    if UnitIsDeadOrGhost("player") then return "dead" end
    if InCombatLockdown() or UnitAffectingCombat("player") then return "combat" end
    if UnitOnTaxi("player") then return "taxi" end
    if IsStealthed and IsStealthed() then return "stealthed" end
    if UnitInVehicle and UnitInVehicle("player") then return "vehicle" end
    return nil
end

local function TrySummon(reason)
    last = { reason = reason, at = date("%H:%M:%S") }
    if not UlRemedy.enabled.autopet then last.result = "feature off" return end
    local j = Journal()
    if not j then last.result = "no pet journal API on this client" return end

    local why = Blocker()
    if why then
        last.result = "waiting: " .. why
        pending = true
        return
    end
    pending = false

    local okGuid, guid = pcall(j.GetSummonedPetGUID)
    if not okGuid then last.result = "GetSummonedPetGUID failed: " .. tostring(guid) return end
    if guid and not (issecretvalue and issecretvalue(guid)) then
        last.result = "a pet is already out"
        return
    end

    -- Summon first, ask questions after: the favorites check depends on
    -- the journal's filters, the summon call does not. A moment later,
    -- if still no pet is out and the list shows no favorite, say so once.
    local ok, err = pcall(j.SummonRandomPet, true)
    if not ok then
        last.result = "SummonRandomPet failed: " .. tostring(err)
        return
    end
    last.result = "asked for a favorite"
    C_Timer.After(1.5, function()
        local okAfter, after = pcall(j.GetSummonedPetGUID)
        if okAfter and after and not (issecretvalue and issecretvalue(after)) then
            last.result = "summoned a favorite"
            return
        end
        local favorites = HasFavorites(j)
        last.result = favorites == false and "nothing came out: no favorites in the journal list"
            or "nothing came out (favorites in list: " .. tostring(favorites) .. ")"
        if favorites == false and not hinted then
            hinted = true
            Print("no favorite pets yet. Star a few in the Pet Journal (Shift+P) and one of them will be summoned when none is out.")
        end
    end)
end

-- Give the world a moment to settle before the pet appears.
local function Later(reason, delay)
    C_Timer.After(delay or 2, function() TrySummon(reason) end)
end

function UlRemedy.RefreshAutoPet()
    if UlRemedy.enabled.autopet then Later("toggle", 0.5) end
end

function UlRemedy.AutoPetDebug()
    local j = Journal()
    Print("auto pet: " .. (UlRemedy.enabled.autopet and "on" or "off")
        .. ", journal API: " .. tostring(j ~= nil)
        .. ", pending: " .. tostring(pending))
    if j then
        local okGuid, guid = pcall(j.GetSummonedPetGUID)
        local total = j.GetNumPets and j.GetNumPets()
        print(string.format("  pets in journal: %s, favorites: %s, summoned now: %s",
            tostring(total), tostring(HasFavorites(j)),
            okGuid and tostring(guid) or ("error " .. tostring(guid))))
    end
    print("  blocker now: " .. tostring(Blocker()))
    if last.reason then
        print(string.format("  last attempt: %s at %s, %s", last.reason, last.at, tostring(last.result)))
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_UNGHOST")
frame:RegisterEvent("PLAYER_ALIVE")
frame:RegisterEvent("PLAYER_CONTROL_GAINED")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_ENTERING_WORLD" then
        Later("login", 4)
    elseif event == "PLAYER_UNGHOST" or event == "PLAYER_ALIVE" then
        if not UnitIsDeadOrGhost("player") then Later("alive", 2) end
    elseif event == "PLAYER_CONTROL_GAINED" then
        Later("landed", 1)
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        Later("zone", 3)
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pending then Later("combat over", 1.5) end
    end
end)
