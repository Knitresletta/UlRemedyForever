-- Headless check of Trainer Preview, run on the Mac with Homebrew Lua:
--
--     lua tools/trainer_preview_check.lua .
--
-- Stubs the handful of WoW API calls TrainerPreview.lua touches, loads
-- TrainerData.lua and TrainerPreview.lua, migrates a version-5 DB with a
-- level-0 potion record, reads a trainer list shaped like Loganaar's on
-- 08.11.2026 (Discolored Healing Potions at level 0, learned Wrath lines
-- without a level, Insect Swarm whose rank 1 comes from a talent, a line
-- the catalog does not know), and asserts what the tab would show. Not
-- shipped (tools/ is excluded from the zip).
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
UnitLevel = function() return 34 end
UnitName = function(u) if u == "npc" then return "Loganaar" end end
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
-- old DB with level-0 junk from version 5
UlRemedyForeverTrainerDB = { version = 5, classes = { DRUID = { spells = {
    ["Discolored Healing Potion|0"] = { name = "Discolored Healing Potion", level = 0, cost = 5 },
    ["Starfire|20"] = { name = "Starfire", level = 20, cost = 2400 },
} } } }
scripts.OnEvent(nil, "ADDON_LOADED", "UlRemedyForever")
local db = UlRemedyForeverTrainerDB
assert(db.version == 6, "version")
assert(db.classes.DRUID.spells["Discolored Healing Potion|0"] == nil, "migration dropped level 0")
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
-- no list at all: upcoming from catalog only
db.classes.DRUID = nil
local a2, u2, l2 = Compute(34)
assert(l2 == nil and #a2 == 0 and #u2 > 0, "catalog-only coming up")
print("catalog-only upcoming:", #u2)
UlRemedy.TrainerPreviewDebug()
print("ALL OK")
