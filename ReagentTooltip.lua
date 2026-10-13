-- Reagent Tooltip: adds a "Used by: Alchemy, Engineering" line to the
-- tooltip of every item that is a reagent in a profession recipe.
--
-- Two sources, merged:
--   * ReagentData.lua, a static table generated from game data by
--     tools/build_reagents.py (see its header for which data).
--   * What the addon learns in play: every time a profession window has its
--     recipe list ready, each recipe's required reagents are read with
--     C_TradeSkillUI.GetRecipeSchematic and stored account-wide in
--     UlRemedyForeverReagentDB. This is what makes the line right for the
--     Forever client, whose recipes differ from the static table. Recipes
--     the window does not list (unlearned drop recipes) are not seen, so the
--     learned data only ever adds professions, it never removes one.
--
-- The line colours professions this character knows green and the rest
-- grey. Known professions come from GetProfessions on clients that have it
-- and from the skill list otherwise, re-read whenever the skill lines
-- change.
--
-- Hooks: the item tooltip post-call on clients with TooltipDataProcessor,
-- OnTooltipSetItem on older ones (same approach as the inventory tracker).
-- Only GameTooltip and ItemRefTooltip are touched.

local KNOWN_COLOR = "|cff1eff00"
local UNKNOWN_COLOR = "|cff9d9d9d"
local POISONS_SPELL = 2842   -- the rogue "Poisons" skill spell
local RESCAN_SECONDS = 30    -- the list updates often while a window is open

local DB
local known = {}             -- skill line id -> true
local knownDirty = true
local lastScan = {}          -- skill id -> GetTime() of the last scan
local lastError

local function Enabled()
    return UlRemedy.enabled and UlRemedy.enabled.reagents
end

local function Report(err)
    err = tostring(err)
    if err == lastError then return end
    lastError = err
    print(UlRemedy.name .. ": reagent tooltip error: " .. err)
end

local function InitDB()
    if not UlRemedyForeverReagentDB then UlRemedyForeverReagentDB = {} end
    DB = UlRemedyForeverReagentDB
    DB.items = DB.items or {}       -- itemID -> { [skillID] = true }
    DB.scanned = DB.scanned or {}   -- skillID -> { at = time(), recipes = n }
    DB.names = DB.names or {}       -- skillID -> name, for lines not in the static list
end

------------------------------------------------------------------------
-- Professions
------------------------------------------------------------------------

local function ProfessionBySkill(skillLine)
    for i, prof in ipairs(UlRemedy.ReagentProfessionList or {}) do
        if prof.id == skillLine then return i, prof end
    end
end

local function ProfessionByName(name)
    for i, prof in ipairs(UlRemedy.ReagentProfessionList or {}) do
        if prof.name == name then return i, prof end
    end
end

local function ProfessionName(skillID)
    local _, prof = ProfessionBySkill(skillID)
    if prof then return prof.name end
    return (DB and DB.names[skillID]) or ("skill " .. tostring(skillID))
end

local function RefreshKnown()
    wipe(known)
    if GetProfessions and GetProfessionInfo then
        for i = 1, 6 do
            local index = select(i, GetProfessions())
            if index then
                local name, _, _, _, _, _, skillLine = GetProfessionInfo(index)
                if skillLine and skillLine > 0 then
                    known[skillLine] = true
                end
                if name then
                    local _, prof = ProfessionByName(name)
                    if prof then known[prof.id] = true end
                end
            end
        end
    elseif GetNumSkillLines and GetSkillLineInfo then
        for i = 1, GetNumSkillLines() do
            local name, isHeader = GetSkillLineInfo(i)
            if name and not isHeader then
                local _, prof = ProfessionByName(name)
                if prof then known[prof.id] = true end
            end
        end
    end
    if IsPlayerSpell and IsPlayerSpell(POISONS_SPELL) then
        known[40] = true
    end
    knownDirty = false
end

------------------------------------------------------------------------
-- Learning from the open profession window
------------------------------------------------------------------------

-- The parent skill line (Blacksmithing, not "Classic Blacksmithing") and
-- its name for the profession window that is open, or nil.
local function OpenProfession()
    if C_TradeSkillUI then
        if C_TradeSkillUI.GetBaseProfessionInfo then
            local info = C_TradeSkillUI.GetBaseProfessionInfo()
            if info and info.professionID and info.professionID > 0 then
                return info.professionID, info.professionName
            end
        end
        if C_TradeSkillUI.GetChildProfessionInfo then
            local info = C_TradeSkillUI.GetChildProfessionInfo()
            if info and info.parentProfessionID and info.parentProfessionID > 0 then
                return info.parentProfessionID, info.parentProfessionName or info.professionName
            end
            if info and info.professionID and info.professionID > 0 then
                return info.professionID, info.professionName
            end
        end
        if C_TradeSkillUI.GetTradeSkillLine then
            local id, name, _, _, _, parentID, parentName = C_TradeSkillUI.GetTradeSkillLine()
            if parentID and parentID > 0 then return parentID, parentName or name end
            if id and id > 0 then return id, name end
        end
    end
    if GetTradeSkillLine then
        local name = GetTradeSkillLine()
        local _, prof = name and ProfessionByName(name)
        if prof then return prof.id, name end
    end
end

local function Learn(itemID, skillID)
    if not itemID or itemID <= 0 then return false end
    local entry = DB.items[itemID]
    if not entry then
        entry = {}
        DB.items[itemID] = entry
    end
    if entry[skillID] then return false end
    entry[skillID] = true
    return true
end

-- Returns recipes read and new item/profession pairs stored.
local function ScanRetail(skillID)
    local ids = C_TradeSkillUI.GetAllRecipeIDs()
    if not ids then return 0, 0 end
    local recipes, learned = 0, 0
    local basic = Enum.CraftingReagentType and Enum.CraftingReagentType.Basic
    for _, recipeID in ipairs(ids) do
        local schematic = C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
        if schematic and schematic.reagentSlotSchematics then
            recipes = recipes + 1
            for _, slot in ipairs(schematic.reagentSlotSchematics) do
                local required = (slot.required ~= false)
                    and (basic == nil or slot.reagentType == nil or slot.reagentType == basic)
                if required and slot.reagents then
                    for _, reagent in ipairs(slot.reagents) do
                        if Learn(reagent.itemID, skillID) then learned = learned + 1 end
                    end
                end
            end
        end
    end
    return recipes, learned
end

local function ScanClassic(skillID)
    local recipes, learned = 0, 0
    for i = 1, GetNumTradeSkills() do
        local _, kind = GetTradeSkillInfo(i)
        if kind and kind ~= "header" then
            recipes = recipes + 1
            for j = 1, (GetTradeSkillNumReagents(i) or 0) do
                local link = GetTradeSkillReagentItemLink(i, j)
                local itemID = link and tonumber(link:match("item:(%d+)"))
                if Learn(itemID, skillID) then learned = learned + 1 end
            end
        end
    end
    return recipes, learned
end

local function Scan()
    if not DB or not Enabled() then return end
    if C_TradeSkillUI and C_TradeSkillUI.IsTradeSkillReady and not C_TradeSkillUI.IsTradeSkillReady() then
        return
    end
    local skillID, name = OpenProfession()
    if not skillID then return end
    local now = GetTime()
    if lastScan[skillID] and now - lastScan[skillID] < RESCAN_SECONDS then return end
    lastScan[skillID] = now

    if name and not ProfessionBySkill(skillID) then DB.names[skillID] = name end

    local recipes, learned
    if C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs and C_TradeSkillUI.GetRecipeSchematic then
        recipes, learned = ScanRetail(skillID)
    elseif GetNumTradeSkills and GetTradeSkillReagentItemLink then
        recipes, learned = ScanClassic(skillID)
    else
        return
    end
    if recipes == 0 then return end
    -- Say something only when there is news: new item uses, or a profession
    -- read for the first time ever. Re-reading a known window after a reload
    -- stays quiet; /ur reagents shows the state on demand.
    local firstRead = not DB.scanned[skillID]
    DB.scanned[skillID] = { at = time(), recipes = recipes }
    if learned > 0 or firstRead then
        print(UlRemedy.name .. ": reagent tooltip read " .. recipes .. " " .. ProfessionName(skillID)
            .. " recipes" .. (learned > 0 and (", " .. learned .. " new item uses learned.") or "."))
    end
end

local scanPending = false

local function ScheduleScan()
    if scanPending then return end
    scanPending = true
    C_Timer.After(0.5, function()
        scanPending = false
        local ok, err = pcall(Scan)
        if not ok then Report(err) end
    end)
end

------------------------------------------------------------------------
-- The tooltip line
------------------------------------------------------------------------

-- Ordered list of profession skill IDs for an item: the static list's
-- order first, then anything learned that the static list does not name.
local function ProfessionsFor(itemID)
    local result = {}
    local seen = {}
    local static = UlRemedy.ReagentProfessions and UlRemedy.ReagentProfessions[itemID]
    local learned = DB and DB.items[itemID]
    for index, prof in ipairs(UlRemedy.ReagentProfessionList or {}) do
        local inStatic = false
        if static then
            for _, k in ipairs(static) do
                if k == index then inStatic = true break end
            end
        end
        if inStatic or (learned and learned[prof.id]) then
            result[#result + 1] = prof.id
            seen[prof.id] = true
        end
    end
    if learned then
        local extra = {}
        for skillID in pairs(learned) do
            if not seen[skillID] then extra[#extra + 1] = skillID end
        end
        table.sort(extra, function(a, b) return ProfessionName(a) < ProfessionName(b) end)
        for _, skillID in ipairs(extra) do result[#result + 1] = skillID end
    end
    return result
end

local function LineFor(itemID)
    local list = ProfessionsFor(itemID)
    if #list == 0 then return nil end
    if knownDirty then RefreshKnown() end
    local parts = {}
    for _, skillID in ipairs(list) do
        local color = known[skillID] and KNOWN_COLOR or UNKNOWN_COLOR
        parts[#parts + 1] = color .. ProfessionName(skillID) .. "|r"
    end
    return "Used by: " .. table.concat(parts, ", ")
end

local function AddLine(tooltip, itemID)
    if not Enabled() or not itemID then return end
    -- Some clients run the item hook twice for one tooltip; add once.
    if tooltip.ulRemedyReagentID == itemID then return end
    local text = LineFor(itemID)
    if not text then return end
    tooltip.ulRemedyReagentID = itemID
    tooltip:AddLine(text, 0.8, 0.8, 0.8)
    tooltip:Show()
end

local function ItemIDFromTooltip(tooltip)
    if tooltip.GetItem then
        local _, link = tooltip:GetItem()
        if link then
            local getInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
            return getInstant and getInstant(link)
        end
    end
end

local function HookTooltips()
    local tooltips = { GameTooltip, ItemRefTooltip }
    for _, tt in ipairs(tooltips) do
        if tt and tt.HookScript then
            tt:HookScript("OnTooltipCleared", function(tooltip)
                tooltip.ulRemedyReagentID = nil
            end)
        end
    end
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
       and Enum.TooltipDataType and Enum.TooltipDataType.Item then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
            if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
            AddLine(tooltip, (data and data.id) or ItemIDFromTooltip(tooltip))
        end)
    else
        for _, tt in ipairs(tooltips) do
            if tt and tt.HookScript then
                tt:HookScript("OnTooltipSetItem", function(tooltip)
                    AddLine(tooltip, ItemIDFromTooltip(tooltip))
                end)
            end
        end
    end
end

------------------------------------------------------------------------
-- Commands and events
------------------------------------------------------------------------

function UlRemedy.ReagentDebug()
    if not DB then return end
    local items = 0
    for _ in pairs(DB.items) do items = items + 1 end
    local static = 0
    for _ in pairs(UlRemedy.ReagentProfessions or {}) do static = static + 1 end
    print(UlRemedy.name .. ": reagent tooltip: " .. static .. " items in the shipped table, "
        .. items .. " items learned in play.")
    local any = false
    for skillID, rec in pairs(DB.scanned) do
        any = true
        print("  " .. ProfessionName(skillID) .. ": " .. rec.recipes .. " recipes, last read "
            .. date("%Y-%m-%d %H:%M", rec.at))
    end
    if not any then print("  No profession window read yet. Open one to teach it.") end
    if lastError then print("  last error: " .. lastError) end
end

function UlRemedy.ResetReagentData()
    if not DB then return end
    wipe(DB.items)
    wipe(DB.scanned)
    wipe(DB.names)
    wipe(lastScan)
    print(UlRemedy.name .. ": forgot everything the reagent tooltip learned in play.")
end

local frame = CreateFrame("Frame", "UlRemedyReagentFrame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("SKILL_LINES_CHANGED")
frame:RegisterEvent("SPELLS_CHANGED")
frame:RegisterEvent("TRADE_SKILL_SHOW")
frame:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
frame:RegisterEvent("TRADE_SKILL_DATA_SOURCE_CHANGED")
frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == UlRemedy.name then
            InitDB()
            self:UnregisterEvent("ADDON_LOADED")
        end
    elseif event == "PLAYER_LOGIN" then
        HookTooltips()
        self:UnregisterEvent("PLAYER_LOGIN")
        knownDirty = true
    elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_LIST_UPDATE"
        or event == "TRADE_SKILL_DATA_SOURCE_CHANGED" then
        ScheduleScan()
    else
        knownDirty = true
    end
end)
