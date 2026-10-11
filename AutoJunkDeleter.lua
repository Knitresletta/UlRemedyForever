-- Junk Deleter: when the bags are full, deletes the cheapest grey (junk)
-- stack to free a slot. Off by default.
--
-- Safety rules, in order:
--   * only items of Poor (grey) quality are ever considered;
--   * locked items, quest items and stacks whose vendor price is not in the
--     item cache are skipped (an unknown price cannot be ranked);
--   * nothing happens while a vendor window is open, the junk seller sells
--     the greys there instead;
--   * nothing happens while the cursor already holds something;
--   * the item picked up is verified against what was scanned before it is
--     deleted, so a bag change between scan and pickup never deletes the
--     wrong item.
--
-- "Cheapest" is the lowest total vendor value of the stack (price times
-- count), since deleting any stack frees exactly one slot.

local lastError
local armed = true          -- false between a deletion and the next bag update
local hintShown = false     -- "bags full but nothing to delete", once per episode
local lastAttempt = 0

local function Report(err)
    if err == lastError then return end
    lastError = err
    print(UlRemedy.name .. ": junk deleter error: " .. tostring(err))
end

local function LastBag()
    return NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
end

-- Only general-purpose bags count: a free slot in a quiver or soul bag does
-- not help when looting an ordinary item.
local function GeneralBagsFull()
    for bag = 0, LastBag() do
        local free, family = C_Container.GetContainerNumFreeSlots(bag)
        if (free or 0) > 0 and (family or 0) == 0 then
            return false
        end
    end
    return true
end

local function FindCheapestJunk()
    local best, bestValue
    for bag = 0, LastBag() do
        for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.hyperlink and info.quality == Enum.ItemQuality.Poor and not info.isLocked then
                local questInfo = C_Container.GetContainerItemQuestInfo(bag, slot)
                local isQuestItem = questInfo and (questInfo.isQuestItem or questInfo.questID)
                if not isQuestItem then
                    local count = info.stackCount or 1
                    local value
                    if info.hasNoValue then
                        value = 0
                    else
                        local price = UlRemedy.ItemVendorPrice(info.hyperlink)
                        if price then value = price * count end
                    end
                    if value and (not bestValue or value < bestValue or (value == bestValue and count < best.count)) then
                        bestValue = value
                        best = { bag = bag, slot = slot, itemID = info.itemID, link = info.hyperlink, count = count, value = value }
                    end
                end
            end
        end
    end
    return best
end

local function DeleteStack(entry)
    if GetCursorInfo() then
        return false, "the cursor is holding something"
    end
    C_Container.PickupContainerItem(entry.bag, entry.slot)
    local kind, itemID = GetCursorInfo()
    if kind ~= "item" or itemID ~= entry.itemID then
        ClearCursor()
        return false, "could not pick up the item"
    end
    DeleteCursorItem()
    if GetCursorInfo() then
        ClearCursor()
        return false, "the client refused the deletion"
    end
    return true
end

local function Check()
    if not UlRemedy.enabled.junkdelete then return end
    if not armed then return end
    if MerchantFrame and MerchantFrame:IsShown() then return end
    if not GeneralBagsFull() then
        hintShown = false
        return
    end

    local entry = FindCheapestJunk()
    if not entry then
        if not hintShown then
            hintShown = true
            print(UlRemedy.name .. ": bags are full and there is no junk to delete.")
        end
        return
    end

    local now = GetTime()
    if now - lastAttempt < 0.5 then return end
    lastAttempt = now

    armed = false
    local ok, err = DeleteStack(entry)
    if ok then
        local what = entry.link .. (entry.count > 1 and (" x" .. entry.count) or "")
        print(UlRemedy.name .. ": bags full, deleted " .. what .. " (worth " .. UlRemedy.MoneyText(entry.value) .. ").")
    else
        armed = true
        Report(err)
    end
end

function UlRemedy.CheckJunkDeleter()
    local ok, err = pcall(Check)
    if not ok then Report(err) end
end

local frame = CreateFrame("Frame", "UlRemedyJunkDeleterFrame")
frame:RegisterEvent("BAG_UPDATE_DELAYED")
frame:RegisterEvent("UI_ERROR_MESSAGE")
frame:SetScript("OnEvent", function(self, event, _, message)
    if event == "BAG_UPDATE_DELAYED" then
        armed = true
        UlRemedy.CheckJunkDeleter()
    elseif event == "UI_ERROR_MESSAGE" then
        if ERR_INV_FULL and message == ERR_INV_FULL then
            UlRemedy.CheckJunkDeleter()
        end
    end
end)
