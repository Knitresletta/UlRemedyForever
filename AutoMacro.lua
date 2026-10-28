-- Auto Macro: five account macros that always use the best healing
-- potion, mana potion, food, drink and bandage in your bags.
--
-- UR Heal, UR Mana, UR Food, UR Drink and UR Bandage are created once in
-- the General tab (shared by every character, rewritten by whoever is
-- logged in) and then edited in place whenever the bags, spells or level
-- change (out of combat), so they stay on your action bars. All but UR
-- Heal are "#showtooltip" plus "/use item:<id>", so the bar icon shows
-- the item and its count.
--
-- UR Heal is a chain: a castsequence that goes through the class's own
-- self-heals you know (shortest cooldown first), then a Healthstone when
-- you carry one, then the best healing potion, and starts over when
-- combat ends. One key, pressed again and again, works down the list. A
-- castsequence does not skip a step that is on cooldown, it waits on it,
-- so the chain can stall when its first step was used in the previous
-- fight; the reset on leaving combat and the short-cooldown-first order
-- keep that rare. Self-heals that only work out of combat get their own
-- [nocombat] line above the chain. Lay on Hands and other long cooldowns
-- are left out on purpose: a panic key should not burn them. A Warlock
-- who knows Soulburn gets "/cast [combat] Soulburn" above the chain when
-- a Healthstone is in it, so the stone is empowered by the same press.
--
-- Ported from the retail UlRemedy (AutoMacro.lua), without the flask
-- macro and the stop-casting toggle. Forever has the old world's
-- consumables, so "best" works differently here: there are no crafting
-- ranks, and a higher item level is simply a stronger potion or meal.
-- An item is recognised from a short list of known names or from its
-- subclass and tooltip ("restores ... health", "mana", "well fed"), and
-- the highest item level you are allowed to use wins, then the bigger
-- stack. Items above your level are skipped, since the old world's
-- potions and food carry a level requirement. Food with Well Fed goes
-- before conjured food, which goes before plain food; conjured water
-- goes before bought drinks. Healthstones are found by name, so every
-- rank counts. The names and tooltip words are English; on another
-- client language only the subclass part of the guess works.
--
-- Reads the bags, item tooltips and the spellbook; writes account
-- macros through CreateMacro and EditMacro, which the client refuses in
-- combat, so a change during a fight waits for it to end. Nothing of
-- Blizzard's is hooked. /ur macrolist prints what each macro resolved to
-- and why.

local DEBOUNCE = 1.5          -- seconds after the last bag change
local LOGIN_DELAY = 4         -- let the item cache fill after login

local MACROS = {
    { key = "heal",    name = "UR Heal",    label = "healing potion" },
    { key = "mana",    name = "UR Mana",    label = "mana potion" },
    { key = "food",    name = "UR Food",    label = "food" },
    { key = "drink",   name = "UR Drink",   label = "drink" },
    { key = "bandage", name = "UR Bandage", label = "bandage" },
}

local SOULBURN = 385899            -- Warlock talent, empowers the next Healthstone

-- Known names per category. They only make sure an item is recognised
-- when its tooltip is not; which one is best is decided by item level.
local KNOWN = {
    heal = {
        "Major Healing Potion", "Superior Healing Potion", "Combat Healing Potion",
        "Greater Healing Potion", "Healing Potion", "Lesser Healing Potion",
        "Discolored Healing Potion", "Minor Healing Potion",
    },
    mana = {
        "Major Mana Potion", "Superior Mana Potion", "Combat Mana Potion",
        "Greater Mana Potion", "Mana Potion", "Lesser Mana Potion", "Minor Mana Potion",
    },
    food = {},
    drink = {},
    bandage = {},
}

local IS_KNOWN = {}
for key, names in pairs(KNOWN) do
    IS_KNOWN[key] = {}
    for _, name in ipairs(names) do IS_KNOWN[key][name] = true end
end

-- Tiers, lower is better. Within a tier: item level, then stack size.
local TIER_WELLFED, TIER_CONJURED, TIER_PLAIN = 1, 2, 3

-- Self-heals worth a place in the UR Heal chain, checked against the
-- spellbook at build time so only the ones this character knows are
-- used; an ID the client does not have simply never matches. Spell IDs
-- are facts about the game, not borrowed code. nocombat marks spells the
-- game only allows out of combat.
local SELF_HEALS = {
    { id = 109304,  note = "Exhilaration (Hunter)" },
    { id = 185311,  note = "Crimson Vial (Rogue)" },
    { id = 19236,   note = "Desperate Prayer (Priest)" },
    { id = 322101,  note = "Expel Harm (Monk)" },
    { id = 122281,  note = "Healing Elixir (Monk)" },
    { id = 108416,  note = "Dark Pact (Warlock)" },
    { id = 48743,   note = "Death Pact (Death Knight)" },
    { id = 55233,   note = "Vampiric Blood (Death Knight)" },
    { id = 12975,   note = "Last Stand (Warrior)" },
    -- Gift of the Naaru has one spell ID per class.
    { id = 28880,   note = "Gift of the Naaru" },
    { id = 59542,   note = "Gift of the Naaru" },
    { id = 59543,   note = "Gift of the Naaru" },
    { id = 59544,   note = "Gift of the Naaru" },
    { id = 59545,   note = "Gift of the Naaru" },
    { id = 59547,   note = "Gift of the Naaru" },
    { id = 59548,   note = "Gift of the Naaru" },
    { id = 121093,  note = "Gift of the Naaru" },
    { id = 370626,  note = "Gift of the Naaru" },
    { id = 416250,  note = "Gift of the Naaru" },
    { id = 461063,  note = "Quiet Contemplation (Earthen)", nocombat = true },
}

local MACRO_LIMIT = 255        -- characters in a standard macro body

-- Consumable subclasses, for the guess.
local CLASS_CONSUMABLE = 0
local SUB_POTION, SUB_FOOD, SUB_BANDAGE = 1, 5, 7

local pending = false         -- a scan is wanted (debounce or combat)
local timer
local lastReport = {}         -- key -> { pick, result, steps, outside }
local fullWarned = false

local function Enabled()
    return UlRemedy.enabled and UlRemedy.enabled.macros
end

------------------------------------------------------------------------
-- Looking at the bags
------------------------------------------------------------------------

local function TooltipText(bag, slot)
    if not (C_TooltipInfo and C_TooltipInfo.GetBagItem) then return "" end
    local ok, data = pcall(C_TooltipInfo.GetBagItem, bag, slot)
    if not ok or type(data) ~= "table" or type(data.lines) ~= "table" then return "" end
    local parts = {}
    for _, line in ipairs(data.lines) do
        local t = line.leftText
        if type(t) == "string" and not (issecretvalue and issecretvalue(t)) then parts[#parts + 1] = t end
    end
    return table.concat(parts, "\n")
end

-- Which category an item belongs to and its tier there, from the known
-- names, the subclass and the tooltip, or nil when it is none of them.
local function Classify(itemID, name, bag, slot)
    for key in pairs(KNOWN) do
        if IS_KNOWN[key][name] then return key, TIER_PLAIN, "known name" end
    end
    local _, _, _, _, _, classID, subID = C_Item.GetItemInfoInstant(itemID)
    if classID ~= CLASS_CONSUMABLE then return nil end
    if subID == SUB_BANDAGE or name:find("Bandage", 1, true) then
        return "bandage", TIER_PLAIN, "bandage subclass"
    end
    if subID ~= SUB_POTION and subID ~= SUB_FOOD then return nil end
    local text = TooltipText(bag, slot):lower()
    local health = text:find("health", 1, true)
    local mana = text:find("mana", 1, true)
    if subID == SUB_POTION then
        if not text:find("restores", 1, true) then return nil end
        if health then return "heal", TIER_PLAIN, "guess from tooltip" end
        if mana then return "mana", TIER_PLAIN, "guess from tooltip" end
        return nil
    end
    -- Food & Drink. Feasts are placed, not eaten.
    if text:find("feast", 1, true) then return nil end
    local conjured = name:find("^Conjured ") ~= nil
    if text:find("well fed", 1, true) then return "food", TIER_WELLFED, "Well Fed" end
    -- Plain food and drink: which one it is depends on what it restores.
    if health then return "food", conjured and TIER_CONJURED or TIER_PLAIN, conjured and "conjured" or "guess from tooltip" end
    if mana then return "drink", conjured and TIER_CONJURED or TIER_PLAIN, conjured and "conjured" or "guess from tooltip" end
    return nil
end

local function Bags()
    local list = { 0 }
    for i = 1, (NUM_BAG_SLOTS or 4) + (NUM_REAGENTBAG_SLOTS or 0) do list[#list + 1] = i end
    return list
end

local function Better(a, b)
    if not b then return true end
    if a.tier ~= b.tier then return a.tier < b.tier end
    if a.ilvl ~= b.ilvl then return a.ilvl > b.ilvl end
    return a.count > b.count
end

-- One candidate per category: the best thing in the bags, with the
-- reason, or nil. Also the Healthstones carried, best first. Returns
-- candidates, stones and whether any item was still uncached (then a
-- rescan is worth doing once the data arrives).
local function Scan()
    local best, stones = {}, {}
    local seenStone = {}
    local uncached = false
    local level = UnitLevel("player") or 1
    for _, bag in ipairs(Bags()) do
        local n = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, n do
            local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
            if ok and type(info) == "table" and info.itemID then
                local itemID = info.itemID
                local name, _, _, ilvl, minLevel = C_Item.GetItemInfo(itemID)
                if not name then
                    uncached = true
                    if C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
                elseif (minLevel or 0) <= level then
                    if name:find("Healthstone", 1, true) then
                        if not seenStone[itemID] then
                            seenStone[itemID] = true
                            stones[#stones + 1] = { itemID = itemID, ilvl = ilvl or 0 }
                        end
                    else
                        local key, tier, why = Classify(itemID, name, bag, slot)
                        if key then
                            local score = { tier = tier, ilvl = ilvl or 0, count = tonumber(info.stackCount) or 1 }
                            if Better(score, best[key]) then
                                score.itemID = itemID
                                score.name = name
                                score.link = info.hyperlink
                                score.why = why
                                best[key] = score
                            end
                        end
                    end
                end
            end
        end
    end
    table.sort(stones, function(a, b) return a.ilvl > b.ilvl end)
    return best, stones, uncached
end

------------------------------------------------------------------------
-- The heal chain
------------------------------------------------------------------------

local function SpellKnown(id)
    if C_SpellBook and C_SpellBook.IsSpellInSpellBook and Enum and Enum.SpellBookSpellBank then
        local ok, known = pcall(C_SpellBook.IsSpellInSpellBook, id, Enum.SpellBookSpellBank.Player, false)
        return ok and known or false
    end
    if IsSpellKnownOrOverridesKnown then return IsSpellKnownOrOverridesKnown(id) end
    return false
end

local function SpellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    return nil
end

local function SpellCooldown(id)
    if type(GetSpellBaseCooldown) ~= "function" then return 0 end
    local ok, ms = pcall(GetSpellBaseCooldown, id)
    return ok and tonumber(ms) and ms / 1000 or 0
end

-- The spells this character can use in the chain: in-combat ones sorted
-- by cooldown, shortest first, and the out-of-combat ones separately.
local function KnownSelfHeals()
    local combat, outside = {}, {}
    for _, spell in ipairs(SELF_HEALS) do
        if SpellKnown(spell.id) then
            local name = SpellName(spell.id)
            if name then
                local rec = { id = spell.id, name = name, cd = SpellCooldown(spell.id), note = spell.note }
                if spell.nocombat then outside[#outside + 1] = rec else combat[#combat + 1] = rec end
            end
        end
    end
    table.sort(combat, function(a, b)
        if a.cd ~= b.cd then return a.cd < b.cd end
        return a.name < b.name
    end)
    return combat, outside
end

-- Builds the UR Heal body and the chain steps for the report. Spells are
-- dropped from the end of the chain if the body would pass the macro
-- length limit; the Healthstone and the potion always stay.
local function HealBody(potionID, stones)
    local spells, outside = KnownSelfHeals()
    local function Build(nSpells)
        local steps = {}
        for i = 1, nSpells do steps[#steps + 1] = spells[i].name end
        for _, stone in ipairs(stones) do steps[#steps + 1] = "item:" .. stone.itemID end
        if potionID then steps[#steps + 1] = "item:" .. potionID end
        local lines = { "#showtooltip" }
        local condition = "@player"
        if outside[1] then
            lines[#lines + 1] = "/cast [nocombat] " .. outside[1].name
            condition = "@player,combat"
        end
        -- Soulburn is off the global cooldown, so it lands in the same
        -- press as the Healthstone step it empowers. Without a Soul Shard
        -- the line simply fails and the chain goes on.
        if #stones > 0 and SpellKnown(SOULBURN) and SpellName(SOULBURN) then
            lines[#lines + 1] = "/cast [combat] " .. SpellName(SOULBURN)
        end
        if #steps == 0 then
            lines[#lines + 1] = "/run print(\"UlRemedyForever: no self-heal, Healthstone or healing potion available.\")"
        else
            lines[#lines + 1] = "/castsequence [" .. condition .. "] reset=combat " .. table.concat(steps, ", ")
        end
        return table.concat(lines, "\n"), steps
    end
    local body, steps
    for n = #spells, 0, -1 do
        body, steps = Build(n)
        if #body <= MACRO_LIMIT then break end
    end
    return body, steps, outside[1]
end

------------------------------------------------------------------------
-- Writing the macros
------------------------------------------------------------------------

local function Body(m, itemID, stones)
    if m.key == "heal" then return HealBody(itemID, stones) end
    if itemID then
        return "#showtooltip item:" .. itemID .. "\n/use [@player] item:" .. itemID
    end
    return "#showtooltip\n/run print(\"UlRemedyForever: nothing suitable in your bags for this macro.\")"
end

local function AccountMax()
    local consts = Constants and Constants.MacroConsts
    return (consts and consts.MAX_ACCOUNT_MACROS) or MAX_ACCOUNT_MACROS or 120
end

-- Returns "created", "updated", "same", or an error string, plus the
-- chain steps and the out-of-combat spell for the heal macro.
local function WriteMacro(m, itemID, stones)
    local body, steps, outside = Body(m, itemID, stones)
    local index = GetMacroIndexByName(m.name)
    -- Macros are indexed account ones first, then the character's own. A
    -- character macro with our name is left alone; the account one is the
    -- one we keep up to date.
    if index and index > AccountMax() then index = nil end
    if index and index > 0 then
        local _, _, current = GetMacroInfo(index)
        if current == body then return "same", steps, outside end
        local ok, err = pcall(EditMacro, index, m.name, "INV_Misc_QuestionMark", body)
        return ok and "updated" or ("edit failed: " .. tostring(err)), steps, outside
    end
    local account = GetNumMacros()
    if account and account >= AccountMax() then
        return "no room: the account macro list is full", steps, outside
    end
    local ok, err = pcall(CreateMacro, m.name, "INV_Misc_QuestionMark", body, false)
    return ok and "created" or ("create failed: " .. tostring(err)), steps, outside
end

local function Apply()
    pending = false
    if not Enabled() then return end
    if InCombatLockdown() then
        pending = true
        return
    end
    local best, stones, uncached = Scan()
    UlRemedyForeverDB.macroTargets = UlRemedyForeverDB.macroTargets or {}
    local targets = UlRemedyForeverDB.macroTargets
    for _, m in ipairs(MACROS) do
        local pick = best[m.key]
        local itemID = pick and pick.itemID
        local result, steps, outside = WriteMacro(m, itemID, stones)
        lastReport[m.key] = { pick = pick, result = result, steps = steps, outside = outside }
        if result == "created" or result == "updated" then
            local signature = steps and table.concat(steps, ",") or tostring(itemID)
            if signature ~= targets[m.key] then
                if steps then
                    print(UlRemedy.name .. ": " .. m.name .. " chain is now " .. (#steps > 0 and table.concat(steps, " > ") or "empty"))
                else
                    print(UlRemedy.name .. ": " .. m.name .. " now uses " .. (pick and (pick.link or pick.name) or "nothing (no " .. m.label .. " in bags)"))
                end
            end
            targets[m.key] = signature
        elseif result:find("no room", 1, true) then
            if not fullWarned then
                print(UlRemedy.name .. ": cannot create " .. m.name .. ", the account macro list is full (" .. AccountMax() .. ").")
                fullWarned = true
            end
        elseif result ~= "same" then
            print(UlRemedy.name .. ": " .. m.name .. " " .. result)
        end
    end
    if uncached then
        -- Item data is on its way; look again shortly.
        C_Timer.After(3, function() if not pending then Apply() end end)
    end
end

local function Schedule()
    if not Enabled() then return end
    pending = true
    if timer then timer:Cancel() end
    timer = C_Timer.NewTimer(DEBOUNCE, function()
        timer = nil
        if pending then Apply() end
    end)
end

------------------------------------------------------------------------
-- Commands
------------------------------------------------------------------------

function UlRemedy.MacroReport()
    if not Enabled() then
        print(UlRemedy.name .. ": Auto Macro is off. /ur macros turns it on.")
        return
    end
    print(UlRemedy.name .. ": auto macros (account macros, edited out of combat when the bags change):")
    for _, m in ipairs(MACROS) do
        local r = lastReport[m.key]
        if not r then
            print("  " .. m.name .. ": not written yet")
        elseif r.steps then
            print(string.format("  %s: %s (%s)", m.name, #r.steps > 0 and table.concat(r.steps, " > ") or "empty", r.result))
            if r.outside then print("    out of combat first: " .. r.outside.name) end
            if r.pick then print(string.format("    potion: %s x%d, ilvl %d, %s", r.pick.link or r.pick.name, r.pick.count, r.pick.ilvl, r.pick.why)) end
        elseif r.pick then
            print(string.format("  %s: %s x%d, ilvl %d, %s (%s)", m.name, r.pick.link or r.pick.name, r.pick.count, r.pick.ilvl, r.pick.why, r.result))
        else
            print("  " .. m.name .. ": no " .. m.label .. " in bags (" .. r.result .. ")")
        end
    end
    if pending then print("  a rescan is waiting" .. (InCombatLockdown() and " for combat to end" or "")) end
end

-- Core calls this when a feature is toggled.
function UlRemedy.RefreshAutoMacro()
    if Enabled() then Schedule() end
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------

local frame = CreateFrame("Frame", "UlRemedyForeverAutoMacroFrame")

-- Registering an event the client does not have is an error, so the
-- optional ones are checked first.
local function RegisterIfValid(event)
    if C_EventUtils and C_EventUtils.IsEventValid and not C_EventUtils.IsEventValid(event) then return end
    frame:RegisterEvent(event)
end

frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("BAG_UPDATE_DELAYED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
-- A new level lifts level requirements and teaches spells.
frame:RegisterEvent("PLAYER_LEVEL_UP")
RegisterIfValid("PLAYER_SPECIALIZATION_CHANGED")
RegisterIfValid("TRAIT_CONFIG_UPDATED")
frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "PLAYER_LOGIN" then
        C_Timer.After(LOGIN_DELAY, Schedule)
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        if arg1 == "player" then Schedule() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pending then Schedule() end
    elseif event == "PLAYER_LEVEL_UP" then
        -- UnitLevel lags the event by a moment.
        C_Timer.After(1, Schedule)
    else
        Schedule()
    end
end)
