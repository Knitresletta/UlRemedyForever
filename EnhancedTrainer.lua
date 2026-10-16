-- Enhanced Trainer: adds a "Train All" button to the trainer frame that
-- trains every available skill you can afford in one click.
--
-- Classic clients return the category third from GetTrainerServiceInfo
-- (name, rank, category) while retail returns it second, so the category is
-- read from whichever slot holds a known value. Retail's BuyTrainerService(0)
-- shortcut (train everything server-side) is not assumed to exist; services
-- are bought one at a time instead.

local CATEGORIES = {
    available   = true,
    unavailable = true,
    used        = true,
    header      = true,
}

local function ServiceCategory(index)
    local _, second, third = GetTrainerServiceInfo(index)
    if CATEGORIES[second] then return second end
    if CATEGORIES[third] then return third end
    return nil
end

-- Pet training uses the same trainer frame: the hunter's Beast Training
-- window and the pet and demon trainers list the pet's abilities, not the
-- player's, and Beast Training is paid in training points. The client
-- says so per service where IsTrainerServiceLearnSpell exists (its second
-- return). Failing that, a list where no unlearned service costs any gold
-- is paid in training points, which is pet training. Shared with
-- TrainerPreview, which must not file pet abilities under the class.
function UlRemedy.IsPetTraining()
    local n = type(GetNumTrainerServices) == "function" and GetNumTrainerServices() or 0
    if n == 0 then return false end
    local learn = type(IsTrainerServiceLearnSpell) == "function"
    local anyCost, anyUnlearned = false, false
    for i = 1, n do
        local category = ServiceCategory(i)
        if category and category ~= "header" then
            if learn then
                local ok, isLearn, isPet = pcall(IsTrainerServiceLearnSpell, i)
                if ok and isLearn and isPet then return true end
            end
            if category ~= "used" then
                anyUnlearned = true
                local cost = type(GetTrainerServiceCost) == "function" and GetTrainerServiceCost(i) or 0
                if (cost or 0) > 0 then anyCost = true end
            end
        end
    end
    return anyUnlearned and not anyCost
end

-- Returns trained, spent, unaffordable, detail. detail is only set when
-- nothing was available at all.
function UlRemedy.TrainAllAvailable()
    local total = GetNumTrainerServices()
    local available = {}
    local counts = {}
    for i = 1, total do
        local category = ServiceCategory(i) or "?"
        counts[category] = (counts[category] or 0) + 1
        if category == "available" then
            available[#available + 1] = i
        end
    end
    if #available == 0 then
        -- Diagnostic breakdown: shows what the scan actually saw, so a wrong
        -- category assumption or an empty list is visible straight in chat.
        local detail
        if total == 0 then
            detail = "trainer list is empty"
        else
            local parts = {}
            for cat, n in pairs(counts) do
                table.insert(parts, n .. " " .. cat)
            end
            table.sort(parts)
            detail = table.concat(parts, ", ")
        end
        return 0, 0, 0, detail
    end

    -- Walk from the bottom of the list up. A learned service can move or
    -- disappear, which only shifts the entries after it, so the indices we
    -- have not reached yet stay valid. The budget keeps us from firing
    -- purchases the server would reject for lack of gold.
    local budget = GetMoney()
    local trained, spent = 0, 0
    for n = #available, 1, -1 do
        local index = available[n]
        local cost = GetTrainerServiceCost(index) or 0
        if cost <= budget then
            BuyTrainerService(index)
            budget = budget - cost
            spent = spent + cost
            trained = trained + 1
        end
    end
    return trained, spent, #available - trained
end

-- This client moves some former globals under C_* namespaces (GetItemInfo is
-- one). Name the missing function instead of throwing a Lua error, so an API
-- that moved is obvious from chat.
local TRAINER_API = {
    "GetNumTrainerServices",
    "GetTrainerServiceInfo",
    "GetTrainerServiceCost",
    "BuyTrainerService",
}

local function MissingTrainerAPI()
    for _, name in ipairs(TRAINER_API) do
        if type(_G[name]) ~= "function" then return name end
    end
    return nil
end

local function OnTrainAllClick()
    if not UlRemedy.enabled.trainer then return end
    local missing = MissingTrainerAPI()
    if missing then
        print(UlRemedy.name .. ": trainer API " .. missing .. " is not available on this client.")
        return
    end
    if UlRemedy.IsPetTraining() then
        print(UlRemedy.name .. ": Train All is for class trainers. Pet abilities are picked one at a time.")
        return
    end
    local trained, spent, unaffordable, detail = UlRemedy.TrainAllAvailable()
    if detail then
        print(UlRemedy.name .. ": Nothing available to train (" .. detail .. ").")
    elseif trained == 0 then
        print(UlRemedy.name .. ": Not enough gold for any of the " .. unaffordable .. " available skill(s).")
    elseif unaffordable > 0 then
        print(UlRemedy.name .. ": Trained " .. trained .. " skill(s) for " .. UlRemedy.MoneyText(spent) .. ". Not enough gold for the remaining " .. unaffordable .. ".")
    else
        print(UlRemedy.name .. ": Trained " .. trained .. " skill(s) for " .. UlRemedy.MoneyText(spent) .. ".")
    end
end

local trainAllButton

local function EnsureButton()
    if trainAllButton then return trainAllButton end
    if not ClassTrainerFrame then return nil end
    local b = CreateFrame("Button", "UlRemedyTrainAllButton", ClassTrainerFrame, "UIPanelButtonTemplate")
    b:SetSize(90, 22)
    b:SetText("Train All")
    if ClassTrainerTrainButton then
        b:SetPoint("RIGHT", ClassTrainerTrainButton, "LEFT", -4, 0)
    else
        b:SetPoint("BOTTOMLEFT", ClassTrainerFrame, "BOTTOMLEFT", 20, 4)
    end
    b:SetScript("OnClick", OnTrainAllClick)
    trainAllButton = b
    return b
end

-- The list is often still empty at TRAINER_SHOW and fills in on
-- TRAINER_UPDATE, so the button is decided on both: shown at class
-- trainers, hidden at pet training.
local function UpdateButton()
    if not UlRemedy.enabled.trainer or UlRemedy.IsPetTraining() then
        if trainAllButton then trainAllButton:Hide() end
        return
    end
    local b = EnsureButton()
    if b then b:Show() end
end

local frame = CreateFrame("Frame", "UlRemedyTrainerFrame")
frame:RegisterEvent("TRAINER_SHOW")
frame:RegisterEvent("TRAINER_UPDATE")
frame:SetScript("OnEvent", function(_, event)
    if event == "TRAINER_SHOW" then
        -- Blizzard_TrainerUI is load-on-demand; make sure the frame exists.
        if C_AddOns and C_AddOns.LoadAddOn then
            C_AddOns.LoadAddOn("Blizzard_TrainerUI")
        end
    end
    UpdateButton()
end)
