-- Reagent Tooltip: adds a "Used by: Alchemy, Engineering" line to the
-- tooltip of every item that is a reagent in a profession recipe.
--
-- The client cannot be asked which recipes use an item, so the answer comes
-- from a static table in ReagentData.lua (generated from game data by
-- tools/build_reagents.py; see the header there for the source). The line
-- colours professions this character knows green and the rest grey. Known
-- professions are read from GetProfessions on clients that have it and from
-- the skill list otherwise, and are re-read whenever the skill lines change.
--
-- Hooks: the item tooltip post-call on clients with TooltipDataProcessor,
-- OnTooltipSetItem on older ones (same approach as the inventory tracker).
-- Only GameTooltip and ItemRefTooltip are touched.

local KNOWN_COLOR = "|cff1eff00"
local UNKNOWN_COLOR = "|cff9d9d9d"
local POISONS_SPELL = 2842  -- the rogue "Poisons" skill spell

local known = {}         -- skill line id -> true
local knownDirty = true

local function Enabled()
    return UlRemedy.enabled and UlRemedy.enabled.reagents
end

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

local function RefreshKnown()
    wipe(known)
    if GetProfessions and GetProfessionInfo then
        for i = 1, 6 do
            local index = select(i, GetProfessions())
            if index then
                local name, _, _, _, _, _, skillLine = GetProfessionInfo(index)
                if skillLine and ProfessionBySkill(skillLine) then
                    known[skillLine] = true
                elseif name then
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

local function LineFor(itemID)
    local entry = UlRemedy.ReagentProfessions and UlRemedy.ReagentProfessions[itemID]
    if not entry then return nil end
    if knownDirty then RefreshKnown() end
    local parts = {}
    for _, index in ipairs(entry) do
        local prof = UlRemedy.ReagentProfessionList[index]
        if prof then
            local color = known[prof.id] and KNOWN_COLOR or UNKNOWN_COLOR
            parts[#parts + 1] = color .. prof.name .. "|r"
        end
    end
    if #parts == 0 then return nil end
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

local frame = CreateFrame("Frame", "UlRemedyReagentFrame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("SKILL_LINES_CHANGED")
frame:RegisterEvent("SPELLS_CHANGED")
frame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        HookTooltips()
        self:UnregisterEvent("PLAYER_LOGIN")
    end
    knownDirty = true
end)
