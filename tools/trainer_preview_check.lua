-- Headless check of Trainer Preview, run on the Mac with Homebrew Lua:
--
--     lua tools/trainer_preview_check.lua .
--
-- Stubs the handful of WoW API calls TrainerPreview.lua touches, loads
-- TrainerData.lua and TrainerPreview.lua, migrates a version-5 DB with a
-- level-0 potion record and class-wide learned marks, reads a trainer
-- list shaped like Loganaar's on 08.11.2026 (Discolored Healing Potions
-- at level 0, learned Wrath lines without a level, Insect Swarm whose
-- rank 1 comes from a talent, a line the catalog does not know), and
-- asserts what the tab would show. Then a second druid of level 10 visits
-- a starter trainer: the learned marks of the two must not leak into each
-- other (they did until 1.25.1, per class). Not shipped (tools/ is
-- excluded from the zip).
--
local ROOT = arg[1]
UlRemedy = { name = "UlRemedyForever", enabled = { trainerpreview = true } }
function UlRemedy.MoneyText(c) return string.format("%dc", c or 0) end
local scripts = {}
local function Frame()
    local f = {}
    function f:RegisterEvent() end
    function f:SetScript(k, fn) scripts[k] = fn end
    function f:SetPoint() end function f:SetSize() end function f:Hide() end function f:Show() end
    function f:IsShown() return false end
    return f
end
CreateFrame = function() return Frame() end
C_Timer = { After = function(_, fn) end }
GetTime = function() return 0 end
UnitClass = function() return "Druid", "DRUID" end
local playerName, playerLevel, npcName = "Sofie", 34, "Loganaar"
UnitLevel = function() return playerLevel end
UnitName = function(u) if u == "npc" then return npcName end return playerName end
GetNormalizedRealmName = function() return "Realm" end
GetMoney = function() return 115000 end
date = os.date
C_SpellBook = { GetSpellBookItemName = function(i, bank)
    if bank ~= 0 then return nil end
    -- spellbook: Wrath ranks 1-4 known, Mark of the Wild 1-4, Starfire none
    local book = { {"Wrath","Rank 1"},{"Wrath","Rank 2"},{"Wrath","Rank 3"},{"Wrath","Rank 4"},{"Mark of the Wild","Rank 4"} }
    local e = book[i]; if e then return e[1], e[2] end
    return nil
end }
Enum = { SpellBookSpellBank = { Player = 0, Pet = 1 } }
print = print

-- Trainer API, as at Loganaar in the screenshot plus learned lines and potions
local services = {
    { "Discolored Healing Potion", "available", 0, 5 },
    { "Greater Discolored Healing Potion", "available", 0, 15 },
    { "Major Discolored Healing Potion", "available", 0, 10000 },
    { "Superior Discolored Healing Potion", "available", 0, 50 },
    { "Wrath", "used", 0, 0 }, { "Wrath", "used", 0, 0 }, { "Wrath", "used", 0, 0 },
    { "Wrath", "available", 22, 3300 },
    { "Wrath", "available", 30, 4600 },
    { "Starfire", "available", 20, 2400 },
    { "Starfire", "available", 26, 4400 },
    { "Starfire", "available", 34, 7000 },
    { "Starfire", "unavailable", 42, 9000 },
    { "Insect Swarm", "available", 30, 4600 },
    { "Insect Swarm", "unavailable", 40, 9000 },
    { "Track Humanoids", "available", 32, 6000 },
    { "Mystery Druid Thing", "available", 33, 100 },
    { "Frenzied Regeneration", "unavailable", 36, 8000 },
}
GetNumTrainerServices = function() return #services end
GetTrainerServiceInfo = function(i) local s = services[i]; return s[1], s[2], 134400 end
GetTrainerServiceLevelReq = function(i) return services[i][3] end
GetTrainerServiceCost = function(i) return services[i][4] end
GetTrainerServiceIcon = function(i) return 134400 end
GetTrainerServiceTypeFilter = function() return true end
SetTrainerServiceTypeFilter = function() end
ClassTrainerFrame = { IsShown = function() return true end }

dofile(ROOT .. "/TrainerData.lua")
dofile(ROOT .. "/TrainerPreview.lua")
-- old DB with level-0 junk from version 5 and class-wide learned marks
UlRemedyForeverTrainerDB = { version = 5, classes = { DRUID = { learned = { Wrath = 3 }, spells = {
    ["Discolored Healing Potion|0"] = { name = "Discolored Healing Potion", level = 0, cost = 5 },
    ["Starfire|20"] = { name = "Starfire", level = 20, cost = 2400, usedSeen = true },
} } } }
scripts.OnEvent(nil, "ADDON_LOADED", "UlRemedyForever")
local db = UlRemedyForeverTrainerDB
assert(db.version == 7, "version")
assert(db.classes.DRUID.spells["Discolored Healing Potion|0"] == nil, "migration dropped level 0")
assert(db.classes.DRUID.spells["Starfire|20"].usedSeen == nil, "migration stripped the learned mark")
assert(db.classes.DRUID.learned == nil and type(db.chars) == "table" and db.rebuilt, "migration moved learned marks out")
print("migration ok")

-- find locals via upvalues of the debug command
local function upvalue(fn, want)
    for i = 1, 60 do
        local n, v = debug.getupvalue(fn, i)
        if not n then break end
        if n == want then return v end
    end
end
local Compute = upvalue(UlRemedy.TrainerPreviewDebug, "Compute")
local ScanTrainer = upvalue(UlRemedy.RefreshTrainerPreview, "ScanTrainer") or upvalue(scripts.OnEvent, "ScanTrainer")
assert(Compute, "Compute")
-- scan via TRAINER_SHOW -> ScheduleScan uses C_Timer; call ScanTrainer directly
local Scan = upvalue(scripts.OnEvent, "ScheduleScan")
C_Timer.After = function(_, fn) fn() end
scripts.OnEvent(nil, "TRAINER_UPDATE")
local spells = db.classes.DRUID.spells
local n = 0; for k in pairs(spells) do n = n + 1 end
print("records after scan:", n)
for k, rec in pairs(spells) do assert(rec.level > 0, "level 0 stored: " .. k) end
assert(spells["Discolored Healing Potion|0"] == nil and spells["Major Discolored Healing Potion|0"] == nil, "potions kept")
print("potions dropped ok")

local Label = upvalue(Compute, "Label")
local sofie = db.chars["Sofie-Realm"]
assert(sofie and sofie.lastVisit and sofie.trainer == "Loganaar", "character visit recorded")
assert(sofie.learned.Wrath == 3 and sofie.learnedBelow.Wrath == 22, "Wrath marks: 3 learned lines, lowest unlearned at 22")
assert(sofie.learned.Starfire == 0 and sofie.learnedBelow.Starfire == 20, "Starfire: nothing learned, lowest unlearned 20")
local available, upcoming, list = Compute(34)
print("AVAILABLE")
for _, r in ipairs(available) do print("  ", Label(r), "L" .. r.level, r.cost, r.offCatalog and "OFF" or "") end
print("UPCOMING (first 12)")
for i = 1, math.min(12, #upcoming) do local r = upcoming[i]; print("  ", Label(r), "L" .. r.level, r.catalog and "catalog" or ("trainer " .. tostring(r.cost))) end
print("upcoming total:", #upcoming)
local function find(t, label) for _, r in ipairs(t) do if Label(r) == label then return r end end end
assert(find(available, "Insect Swarm (Rank 2)"), "Insect Swarm trainer rank 2 via catalog")
assert(find(available, "Starfire (Rank 3)"), "Starfire rank 3")
assert(find(available, "Wrath (Rank 4)") and find(available, "Wrath (Rank 5)"), "Wrath ranks via catalog")
assert(find(available, "Mystery Druid Thing").offCatalog, "off catalog marked")
assert(not find(upcoming, "Insect Swarm (Rank 1)"), "talent rank 1 not listed")
assert(find(upcoming, "Starfire (Rank 5)").catalog, "Starfire rank 5 from catalog")
assert(find(upcoming, "Starfire (Rank 4)").cost == 9000, "Starfire rank 4 from trainer, not duplicated")
local dup = 0; for _, r in ipairs(upcoming) do if Label(r) == "Starfire (Rank 4)" then dup = dup + 1 end end
assert(dup == 1, "duplicate rank 4")
-- A second druid, level 10, at a starter trainer that lists low ranks
-- only: Wrath rank 2 (6) for sale, rank 3 (14) too high, Moonfire 10.
playerName, playerLevel, npcName = "Nyx", 10, "Mardant Strongoak"
services = {
    { "Wrath", "available", 6, 100 },
    { "Wrath", "unavailable", 14, 800 },
    { "Moonfire", "available", 10, 400 },
}
scripts.OnEvent(nil, "TRAINER_UPDATE")
local nyx = db.chars["Nyx-Realm"]
assert(nyx and nyx.lastVisit and nyx.trainer == "Mardant Strongoak", "second character's visit recorded")
assert(nyx.learnedBelow.Wrath == 6 and nyx.learned.Wrath == 0, "Nyx: no Wrath learned")
assert(sofie.learnedBelow.Wrath == 22, "Sofie's marks untouched by Nyx's visit")
local a3, u3 = Compute(10)
print("NYX AVAILABLE")
for _, r in ipairs(a3) do print("  ", Label(r), "L" .. r.level, r.cost) end
assert(find(a3, "Wrath (Rank 2)") and find(a3, "Wrath (Rank 2)").cost == 100, "Nyx: Wrath rank 2 for sale, Sofie's learned Wrath does not hide it")
assert(find(a3, "Moonfire (Rank 2)"), "Nyx: Moonfire 10 is rank 2 by the catalog")
assert(not find(a3, "Wrath (Rank 3)") and find(u3, "Wrath (Rank 3)").cost == 800, "Nyx: Wrath 14 coming up, from the trainer")
assert(find(u3, "Starfire (Rank 1)").cost == 2400, "Nyx: Starfire 20 from Sofie's trainer list, prices are shared")
assert(find(u3, "Moonfire (Rank 3)").catalog, "Nyx: Moonfire 16 from the catalog")
-- Sofie again: the starter trainer's Wrath lines are below her lowest unlearned Wrath, so learned
playerName, playerLevel = "Sofie", 34
local a4 = Compute(34)
assert(not find(a4, "Wrath (Rank 2)") and not find(a4, "Wrath (Rank 3)"), "Sofie: low Wrath ranks learned, not shown")
assert(find(a4, "Starfire (Rank 3)") and find(a4, "Wrath (Rank 4)"), "Sofie: her own list unchanged")
assert(find(a4, "Moonfire (Rank 2)"), "Sofie: Moonfire 10 is unknown to her, shown until her next visit")
-- Nyx learns Wrath rank 2 and Moonfire, visits again: no unlearned Moonfire on this trainer,
-- so Moonfire is learned up to the trainer's reach (14), not up to 60
playerName, playerLevel = "Nyx", 10
services = {
    { "Wrath", "used", 0, 0 },
    { "Wrath", "unavailable", 14, 800 },
    { "Moonfire", "used", 0, 0 },
}
scripts.OnEvent(nil, "TRAINER_UPDATE")
assert(nyx.learnedBelow.Wrath == 14 and nyx.learned.Wrath == 1, "Nyx: Wrath learned below 14")
assert(nyx.learnedBelow.Moonfire == 15 and nyx.learned.Moonfire == 1, "Nyx: Moonfire learned up to the trainer's reach")
local a5, u5 = Compute(10)
assert(#a5 == 0, "Nyx: nothing waiting after learning both")
assert(find(u5, "Moonfire (Rank 3)") and find(u5, "Wrath (Rank 3)"), "Nyx: next ranks still coming up")
-- Nyx before any visit of her own: everything up to her level is listed, with a note
db.chars["Nyx-Realm"] = nil
local a6, _, _, c6 = Compute(10)
assert(c6 == nil and find(a6, "Wrath (Rank 2)") and find(a6, "Moonfire (Rank 2)"), "no visit: nothing counts as learned")
print("per-character marks ok")

-- no list at all: upcoming from catalog only
db.classes.DRUID = nil
local a2, u2, l2 = Compute(34)
assert(l2 == nil and #a2 == 0 and #u2 > 0, "catalog-only coming up")
print("catalog-only upcoming:", #u2)
UlRemedy.TrainerPreviewDebug()
print("ALL OK")
