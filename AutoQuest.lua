-- Auto Quest: hold Shift while talking to an NPC and the quest business
-- is done for you.
--
-- With Shift held when a gossip or quest window opens, the module picks
-- what you would have clicked: available quests are taken one by one,
-- quests you have finished are handed in, a lone gossip line is chosen
-- when the NPC has nothing else to offer. The NPC's own windows still
-- open and close as usual; the module only presses their buttons through
-- the same functions Blizzard's buttons call (C_GossipInfo.Select*,
-- AcceptQuest, CompleteQuest, GetQuestReward). Without Shift nothing
-- happens, so a normal visit to an NPC is unchanged.
--
-- Left to you on purpose: a choice between several rewards (the reward
-- window stays open), PvP-flagged quests and quests that cost gold to
-- hand in (both get Blizzard's confirmation popup), a quest whose
-- objectives are not done (the progress window stays open), and an NPC
-- with several gossip lines. Trivial (grey) quests are accepted like any
-- other, since holding Shift is a clear enough wish.
--
-- Each selection is remembered for a few seconds per NPC, so a quest the
-- client refuses (quest log full, for instance) is not picked again when
-- the NPC's list comes back, which would otherwise loop. Blizzard already
-- skips a single gossip line itself unless the server insists on showing
-- it (ForceGossip), so the module steps in only where Blizzard leaves the
-- window up.

local RETRY_AFTER = 8          -- seconds before the same pick is tried again

local tried = {}               -- key -> GetTime() of the last pick
local triedNpc                 -- GUID of the NPC the picks belong to

local function Enabled()
    return UlRemedy.enabled and UlRemedy.enabled.autoquest and IsShiftKeyDown()
end

-- True when this key was picked for the current NPC moments ago.
local function Recently(key)
    local npc = UnitGUID("npc") or "?"
    if npc ~= triedNpc then
        tried = {}
        triedNpc = npc
    end
    local at = tried[key]
    if at and GetTime() - at < RETRY_AFTER then return true end
    tried[key] = GetTime()
    return false
end

------------------------------------------------------------------------
-- Gossip window (retail-style NPC list)
------------------------------------------------------------------------

local function OnGossipShow()
    for _, q in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
        if q.questID and not Recently("avail" .. q.questID) then
            C_GossipInfo.SelectAvailableQuest(q.questID)
            return
        end
    end
    for _, q in ipairs(C_GossipInfo.GetActiveQuests() or {}) do
        if q.questID and q.isComplete and not Recently("active" .. q.questID) then
            C_GossipInfo.SelectActiveQuest(q.questID)
            return
        end
    end
    if C_GossipInfo.GetNumAvailableQuests() > 0 or C_GossipInfo.GetNumActiveQuests() > 0 then return end
    local options = C_GossipInfo.GetOptions() or {}
    if #options ~= 1 then return end
    local opt = options[1]
    -- Blizzard's GossipFrame picks this one itself; selecting it twice helps nobody.
    if opt.selectOptionWhenOnlyOption and not C_GossipInfo.ForceGossip() then return end
    if opt.status and Enum.GossipOptionStatus and opt.status ~= Enum.GossipOptionStatus.Available then return end
    if opt.orderIndex == nil or Recently("gossip" .. tostring(opt.gossipOptionID or opt.orderIndex)) then return end
    C_GossipInfo.SelectOptionByIndex(opt.orderIndex)
end

------------------------------------------------------------------------
-- Quest windows (greeting list, detail, progress, reward)
------------------------------------------------------------------------

-- The older greeting list: no gossip, just the NPC's quests by index.
local function OnQuestGreeting()
    for i = 1, GetNumActiveQuests() do
        local title, isComplete = GetActiveTitle(i)
        if isComplete and not Recently("greetactive" .. tostring(title)) then
            SelectActiveQuest(i)
            return
        end
    end
    for i = 1, GetNumAvailableQuests() do
        local questID = select(5, GetAvailableQuestInfo(i))
        if not Recently("greetavail" .. tostring(questID or GetAvailableTitle(i))) then
            SelectAvailableQuest(i)
            return
        end
    end
end

local function OnQuestDetail(questStartItemID)
    -- Quests from items and area triggers are closed by Blizzard's own
    -- handler before anyone could accept them here.
    if questStartItemID and questStartItemID ~= 0 then return end
    if QuestGetAutoAccept() then
        if QuestIsFromAreaTrigger() then return end
        AcknowledgeAutoAcceptQuest()
        return
    end
    if QuestFlagsPVP() then return end
    AcceptQuest()
end

local function OnQuestProgress()
    if IsQuestCompletable() then CompleteQuest() end
end

local function OnQuestComplete()
    local money = GetQuestMoneyToGet()
    if money and money > 0 then return end
    local choices = GetNumQuestChoices()
    if choices == 0 then
        GetQuestReward(0)
    elseif choices == 1 then
        GetQuestReward(1)
    end
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------

local frame = CreateFrame("Frame", "UlRemedyAutoQuestFrame")
frame:RegisterEvent("GOSSIP_SHOW")
frame:RegisterEvent("QUEST_GREETING")
frame:RegisterEvent("QUEST_DETAIL")
frame:RegisterEvent("QUEST_PROGRESS")
frame:RegisterEvent("QUEST_COMPLETE")

frame:SetScript("OnEvent", function(self, event, arg1)
    if not Enabled() then return end
    if event == "GOSSIP_SHOW" then
        OnGossipShow()
    elseif event == "QUEST_GREETING" then
        OnQuestGreeting()
    elseif event == "QUEST_DETAIL" then
        OnQuestDetail(arg1)
    elseif event == "QUEST_PROGRESS" then
        OnQuestProgress()
    elseif event == "QUEST_COMPLETE" then
        OnQuestComplete()
    end
end)
