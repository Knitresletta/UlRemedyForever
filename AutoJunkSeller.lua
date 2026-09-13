local function SellJunk()
    if not UlRemedy.enabled.junk then return end
    local total = 0
    local sold = 0
    local skipped = 0

    for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or 4) do
        for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.hyperlink and info.quality == Enum.ItemQuality.Poor then
                -- Fix 1: skip locked or quest items to avoid data loss.
                -- GetContainerItemInfo has no isQuestItem field; query it directly.
                local questInfo = C_Container.GetContainerItemQuestInfo(bag, slot)
                local isQuestItem = questInfo and (questInfo.isQuestItem or questInfo.questID)
                if info.isLocked or isQuestItem then
                    skipped = skipped + 1
                else
                    local vendorPrice = select(11, GetItemInfo(info.hyperlink)) or 0
                    if vendorPrice > 0 then
                        local quantity = info.stackCount or 1
                        C_Container.UseContainerItem(bag, slot)
                        total = total + (vendorPrice * quantity)
                        sold = sold + quantity
                    else
                        -- Fix 2: count cache misses so the player knows to retry
                        skipped = skipped + 1
                    end
                end
            end
        end
    end

    if sold > 0 then
        print(UlRemedy.name .. ": Sold " .. sold .. " junk item(s) for " .. UlRemedy.MoneyText(total) .. ".")
    end
    if skipped > 0 then
        print(UlRemedy.name .. ": " .. skipped .. " junk item(s) skipped (locked, quest item, or data not yet loaded).")
    end
end

local frame = CreateFrame("Frame", "UlRemedyJunkFrame")
frame:RegisterEvent("MERCHANT_SHOW")
frame:SetScript("OnEvent", SellJunk)
