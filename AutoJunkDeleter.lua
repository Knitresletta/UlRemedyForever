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
--
-- Triggers: any bag change (BAG_UPDATE, debounced, and BAG_UPDATE_DELAYED),
-- a loot window opening, the "Inventory is full" error, and toggling the
-- feature on. After a deletion the next attempt waits a moment so one full
-- bag never causes two deletions.
--
-- The Forever client only honours DeleteCursorItem when the call comes from
-- a click, key press or slash command. From an event the deletion is
-- silently refused. The order of attempts is therefore: cursor deletion
-- (works from /ur junkdelete), then C_Item.DeleteItem by GUID, and if the
-- client refuses both, a popup with a single Delete button, whose click is
-- a hardware event the client accepts.

local lastError
local blockedUntil = 0      -- no new deletion before this time
local hintShown = false     -- "bags full but nothing to delete", once per episode
local declined = false      -- the popup was cancelled for this full-bag episode
local guidDeleteWorks       -- nil = untested, true/false after the first try
local lastEvent, lastEventAt, lastResult

local function Report(err)
    if err == lastError then return end
    lastError = err
    print(UlRemedy.name .. ": junk deleter error: " .. tostring(err))
end

local function LastBag()
    return NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
end

-- Only general-purpose bags count: a free slot in a quiver or soul bag does
-- not help when looting an ordinary item. Returns the free slot count.
local function FreeGeneralSlots()
    local free = 0
    for bag = 0, LastBag() do
        local n, family = C_Container.GetContainerNumFreeSlots(bag)
        if (n or 0) > 0 and (family or 0) == 0 then
            free = free + n
        end
    end
    return free
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

local function Describe(entry)
    return entry.link .. (entry.count > 1 and (" x" .. entry.count) or "")
end

local function Announce(entry)
    lastResult = "deleted " .. entry.link
    print(UlRemedy.name .. ": bags full, deleted " .. Describe(entry) .. " (worth " .. UlRemedy.MoneyText(entry.value) .. ").")
end

local function SlotStillHolds(entry)
    return C_Container.GetContainerItemID(entry.bag, entry.slot) == entry.itemID
end

-- Deletion through the cursor. Returns true, or false and a reason; the
-- reason "refused" means the client ignored DeleteCursorItem, which is what
-- happens when the call is not user-initiated.
local function DeleteViaCursor(entry)
    if GetCursorInfo() then
        return false, "the cursor is holding something"
    end
    if not SlotStillHolds(entry) then
        return false, "the item is no longer in that slot"
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
        return false, "refused"
    end
    return true
end

local function ItemGUIDAt(bag, slot)
    if not (C_Item and C_Item.GetItemGUID and ItemLocation and ItemLocation.CreateFromBagAndSlot) then
        return nil
    end
    local ok, guid = pcall(C_Item.GetItemGUID, ItemLocation:CreateFromBagAndSlot(bag, slot))
    if ok then return guid end
    return nil
end

StaticPopupDialogs["ULREMEDY_DELETE_JUNK"] = {
    text = "Bags are full. Delete %s to free a slot?",
    button1 = DELETE or "Delete",
    button2 = CANCEL or "Cancel",
    OnAccept = function(dialog, entry)
        if not entry then return end
        local ok, err = DeleteViaCursor(entry)
        if ok then
            Announce(entry)
        else
            lastResult = "popup failed: " .. tostring(err)
            Report(err == "refused" and "the client refused the deletion even from a click" or err)
        end
    end,
    OnCancel = function()
        declined = true
        lastResult = "popup cancelled"
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    showAlert = 1,
    preferredIndex = 3,
}

local function Prompt(entry)
    if not StaticPopup_Show then
        Report("no popup available to confirm the deletion")
        return
    end
    lastResult = "asking via popup"
    StaticPopup_Show("ULREMEDY_DELETE_JUNK", Describe(entry), nil, entry)
end

-- Tries the silent routes first and falls back to the popup.
local function Delete(entry)
    local ok, err = DeleteViaCursor(entry)
    if ok then
        Announce(entry)
        return
    end
    if err ~= "refused" then
        lastResult = "failed: " .. tostring(err)
        blockedUntil = 0
        Report(err)
        return
    end

    if guidDeleteWorks ~= false and C_Item and C_Item.DeleteItem then
        local guid = ItemGUIDAt(entry.bag, entry.slot)
        if guid then
            lastResult = "trying deletion by GUID"
            pcall(C_Item.DeleteItem, guid)
            C_Timer.After(0.6, function()
                if SlotStillHolds(entry) then
                    guidDeleteWorks = false
                    Prompt(entry)
                else
                    guidDeleteWorks = true
                    Announce(entry)
                end
            end)
            return
        end
    end

    Prompt(entry)
end

local function Check()
    if not UlRemedy.enabled.junkdelete then
        lastResult = "feature off"
        return
    end
    if MerchantFrame and MerchantFrame:IsShown() then
        lastResult = "vendor open"
        return
    end
    if FreeGeneralSlots() > 0 then
        hintShown = false
        declined = false
        lastResult = "bags not full"
        if StaticPopup_Hide then StaticPopup_Hide("ULREMEDY_DELETE_JUNK") end
        return
    end
    if declined then
        lastResult = "popup cancelled, waiting until bags are not full"
        return
    end
    if GetTime() < blockedUntil then
        lastResult = "waiting after a deletion"
        return
    end

    local entry = FindCheapestJunk()
    if not entry then
        lastResult = "bags full, no junk"
        if not hintShown then
            hintShown = true
            print(UlRemedy.name .. ": bags are full and there is no junk to delete.")
        end
        return
    end

    blockedUntil = GetTime() + 1.5
    Delete(entry)
end

function UlRemedy.CheckJunkDeleter()
    local ok, err = pcall(Check)
    if not ok then Report(err) end
end

local scheduled = false
local function ScheduleCheck()
    if scheduled then return end
    scheduled = true
    C_Timer.After(0.3, function()
        scheduled = false
        UlRemedy.CheckJunkDeleter()
    end)
end

function UlRemedy.JunkDeleterDebug()
    local entry = FindCheapestJunk()
    print("|cffffcc00" .. UlRemedy.name .. " junk deleter|r")
    print("  enabled: " .. tostring(UlRemedy.enabled.junkdelete) .. ", free general slots: " .. FreeGeneralSlots())
    print("  cheapest junk: " .. (entry and (entry.link .. " x" .. entry.count .. " = " .. UlRemedy.MoneyText(entry.value)) or "none"))
    print("  last event: " .. tostring(lastEvent) .. (lastEventAt and (" (" .. math.floor(GetTime() - lastEventAt) .. "s ago)") or ""))
    print("  last check: " .. tostring(lastResult) .. ", last error: " .. tostring(lastError))
    print("  GUID deletion: " .. tostring(guidDeleteWorks) .. ", popup cancelled: " .. tostring(declined)
        .. ", vendor open: " .. tostring((MerchantFrame and MerchantFrame:IsShown()) or false))
end

local frame = CreateFrame("Frame", "UlRemedyJunkDeleterFrame")
frame:RegisterEvent("BAG_UPDATE")
frame:RegisterEvent("BAG_UPDATE_DELAYED")
frame:RegisterEvent("ITEM_PUSH")
frame:RegisterEvent("LOOT_READY")
frame:RegisterEvent("LOOT_OPENED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("UI_ERROR_MESSAGE")
frame:SetScript("OnEvent", function(self, event, arg1, arg2)
    if event == "UI_ERROR_MESSAGE" then
        local message = tostring(arg2 or arg1 or ""):lower()
        local invFull = (ERR_INV_FULL and arg2 == ERR_INV_FULL) or (ERR_BAG_FULL and arg2 == ERR_BAG_FULL)
            or message:find("inventory is full", 1, true) or message:find("bag is full", 1, true)
        if not invFull then return end
        blockedUntil = 0
    end
    lastEvent, lastEventAt = event, GetTime()
    ScheduleCheck()
end)
