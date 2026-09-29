local function SellJunk()
    if not UlRemedy.enabled.junk then return end
    local total = 0
    local sold = 0
    local skipped = 0
    local pricesKnown = true

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
                elseif info.hasNoValue then
                    skipped = skipped + 1
                else
                    -- hasNoValue already established the vendor buys this, so sell
                    -- it even when the price is not cached; only the reported
                    -- total is affected by a cache miss.
                    local vendorPrice = UlRemedy.ItemVendorPrice(info.hyperlink)
                    local quantity = info.stackCount or 1
                    C_Container.UseContainerItem(bag, slot)
                    sold = sold + quantity
                    if vendorPrice then
                        total = total + (vendorPrice * quantity)
                    else
                        pricesKnown = false
                    end
                end
            end
        end
    end

    if sold > 0 then
        if pricesKnown then
            print(UlRemedy.name .. ": Sold " .. sold .. " junk item(s) for " .. UlRemedy.MoneyText(total) .. ".")
        else
            print(UlRemedy.name .. ": Sold " .. sold .. " junk item(s).")
        end
    end
    if skipped > 0 then
        print(UlRemedy.name .. ": " .. skipped .. " junk item(s) skipped (locked, quest item, or no vendor value).")
    end
end

local frame = CreateFrame("Frame", "UlRemedyJunkFrame")
frame:RegisterEvent("MERCHANT_SHOW")
frame:SetScript("OnEvent", SellJunk)
