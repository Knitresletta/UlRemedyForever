-- Vendor Window: a bigger merchant window with every item in one scrollable
-- grid, a search box, a quality filter, a usable-only filter, sorting, a
-- resize grip, and a bag panel docked to the right where one click sells.
--
-- How it fits on top of Blizzard's MerchantFrame: the frame itself is kept,
-- because hiding it closes the vendor (its OnHide calls CloseMerchant) and
-- because its buy, buyback, repair, currency and stack-split code is worth
-- keeping. Blizzard lays out ten fixed item slots per page; those slots are
-- hidden and our own slots, built from the same MerchantItemTemplate, are
-- laid out in a scroll box instead. Because the slots share the template,
-- every click, drag, tooltip, modified click and stack split runs Blizzard's
-- own handlers, keyed by the merchant index stored on the button with
-- SetID. The only thing this module does itself is decide which indices to
-- show, in which order, and where.
--
-- Blizzard refreshes the window through MerchantFrame_Update on every
-- merchant, bag or money event. That function is post-hooked, so our grid
-- follows the same rhythm and the same tab (merchant or buyback).
--
-- The bag panel is a separate frame parented to MerchantFrame, so it opens
-- and closes with it. Its buttons sell with C_Container.UseContainerItem,
-- the same call the junk seller uses. Items above common quality ask first.
--
-- Every entry point from a hook or event runs under pcall. If our code
-- fails, Blizzard's layout is restored so the vendor stays usable, and the
-- error is printed once. Settings live in UlRemedyForeverVendorDB
-- (account-wide): window size, sort order, quality filter and the
-- usable-only flag.

local ITEM_W, ITEM_H = 153, 44        -- MerchantItemTemplate size
local GAP_X, GAP_Y = 12, 8            -- Blizzard's own spacing
local LEFT_PAD = 11                   -- matches MerchantItem1's x offset
local TOP_PAD = 96                    -- below the title, portrait and our controls row
local BOTTOM_PAD = 92                 -- above the repair and buyback strip
local BAR_W = 22                      -- scroll bar plus its margins
local DEFAULT_W, DEFAULT_H = 526, 492 -- three columns, six rows
local MIN_W, MIN_H = 526, 380
local MAX_W, MAX_H = 856, 800
local ORIGINAL_W, ORIGINAL_H = 336, 444
local NUM_BLIZZARD_SLOTS = 12
local MAX_COST_ITEMS = MAX_ITEM_COST or 3
local MONEY_WIDTH = 120

local BAG_BTN, BAG_GAP, BAG_COLS = 37, 4, 6
local BAGS_W = 10 + BAG_COLS * (BAG_BTN + BAG_GAP) - BAG_GAP + 10 + BAR_W

local QUALITY_STEPS = {
    { min = 0, label = "Quality: all" },
    { min = 2, label = "Quality: uncommon+" },
    { min = 3, label = "Quality: rare+" },
    { min = 4, label = "Quality: epic+" },
}
local SORT_STEPS = { "vendor", "name", "price", "quality" }
local SORT_LABEL = {
    vendor = "Sort: vendor order",
    name = "Sort: name",
    price = "Sort: price",
    quality = "Sort: quality",
}

local db
local ui = {}             -- our frames on MerchantFrame
local slots = {}          -- pooled item frames (MerchantItemTemplate)
local bags = {}           -- pooled bag buttons
local active = false      -- Blizzard's layout is currently replaced
local hooked = false
local lastTab
local needQuality = false -- some item had no cached quality during the last refresh
local lastError

local function Enabled()
    return UlRemedy.enabled and UlRemedy.enabled.vendor
end

local function BagsEnabled()
    return UlRemedy.enabled and UlRemedy.enabled.vendorbags
end

local function Report(err)
    err = tostring(err)
    if err == lastError then return end
    lastError = err
    print(UlRemedy.name .. ": vendor window error: " .. err)
end

local function InitDB()
    if not UlRemedyForeverVendorDB then UlRemedyForeverVendorDB = {} end
    db = UlRemedyForeverVendorDB
    db.width = db.width or DEFAULT_W
    db.height = db.height or DEFAULT_H
    db.sort = db.sort or "vendor"
    db.quality = db.quality or 1
    if db.usable == nil then db.usable = false end
end

------------------------------------------------------------------------
-- Item data
------------------------------------------------------------------------

-- Normalised merchant item record. Forever is expected to have the retail
-- C_MerchantFrame.GetItemInfo table; the positional GetMerchantItemInfo is
-- the fallback for clients that only have the old form.
local function MerchantItem(index)
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local info = C_MerchantFrame.GetItemInfo(index)
        if not info then return nil end
        if info.currencyID and CurrencyContainerUtil and CurrencyContainerUtil.GetCurrencyContainerInfo then
            info.name, info.texture, info.numAvailable = CurrencyContainerUtil.GetCurrencyContainerInfo(
                info.currencyID, info.numAvailable, info.name, info.texture, nil)
        end
        return info
    end
    local name, texture, price, stackCount, numAvailable, isPurchasable, isUsable, hasExtendedCost, currencyID, spellID = GetMerchantItemInfo(index)
    if not name then return nil end
    return {
        name = name, texture = texture, price = price or 0, stackCount = stackCount or 1,
        numAvailable = numAvailable, isPurchasable = isPurchasable, isUsable = isUsable,
        hasExtendedCost = hasExtendedCost, currencyID = currencyID, spellID = spellID,
    }
end

local function LinkQuality(link)
    if not link then return nil end
    local getItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not getItemInfo then return nil end
    return (select(3, getItemInfo(link)))
end

local function QualityColor(quality)
    if quality and C_Item and C_Item.GetItemQualityColor then
        local r, g, b = C_Item.GetItemQualityColor(quality)
        return r, g, b
    end
    return NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b
end

local function IsRefundable(index)
    if C_MerchantFrame and C_MerchantFrame.IsMerchantItemRefundable then
        return C_MerchantFrame.IsMerchantItemRefundable(index)
    end
    return true
end

------------------------------------------------------------------------
-- Which items, in which order
------------------------------------------------------------------------

local function SearchText()
    local box = ui.search
    if not box then return "" end
    local text = box:GetText() or ""
    return strtrim(text):lower()
end

local function MinQuality()
    local step = QUALITY_STEPS[db.quality] or QUALITY_STEPS[1]
    return step.min
end

local function BuildMerchantList()
    local list = {}
    local text = SearchText()
    local minQuality = MinQuality()
    local usableOnly = db.usable
    for index = 1, GetMerchantNumItems() do
        local info = MerchantItem(index)
        if info then
            local keep = true
            if text ~= "" and not (info.name or ""):lower():find(text, 1, true) then
                keep = false
            end
            local link = GetMerchantItemLink(index)
            local quality = LinkQuality(link)
            if quality == nil and link then needQuality = true end
            if keep and minQuality > 0 and quality and quality < minQuality then
                keep = false
            end
            if keep and usableOnly and not info.isUsable then
                keep = false
            end
            if keep then
                list[#list + 1] = {
                    index = index,
                    name = (info.name or ""):lower(),
                    price = info.price or 0,
                    quality = quality or 1,
                }
            end
        end
    end
    local sort = db.sort
    if sort == "name" then
        table.sort(list, function(a, b)
            if a.name ~= b.name then return a.name < b.name end
            return a.index < b.index
        end)
    elseif sort == "price" then
        table.sort(list, function(a, b)
            if a.price ~= b.price then return a.price < b.price end
            return a.index < b.index
        end)
    elseif sort == "quality" then
        table.sort(list, function(a, b)
            if a.quality ~= b.quality then return a.quality > b.quality end
            if a.name ~= b.name then return a.name < b.name end
            return a.index < b.index
        end)
    end
    return list
end

local function BuildBuybackList()
    local list = {}
    local text = SearchText()
    for index = 1, GetNumBuybackItems() do
        local name = GetBuybackItemInfo(index)
        if name and (text == "" or name:lower():find(text, 1, true)) then
            list[#list + 1] = { index = index }
        end
    end
    return list
end

------------------------------------------------------------------------
-- Filling a slot (mirrors what Blizzard does for its ten fixed slots)
------------------------------------------------------------------------

local function TintSlot(frame, button, nameRGB, slotRGB, textureRGB)
    SetItemButtonNameFrameVertexColor(frame, nameRGB[1], nameRGB[2], nameRGB[3])
    SetItemButtonSlotVertexColor(frame, slotRGB[1], slotRGB[2], slotRGB[3])
    SetItemButtonTextureVertexColor(button, textureRGB[1], textureRGB[2], textureRGB[3])
    SetItemButtonNormalTextureVertexColor(button, textureRGB[1], textureRGB[2], textureRGB[3])
end

local GREY, WHITE, DARK_RED, RED, DIM_RED = { 0.5, 0.5, 0.5 }, { 1, 1, 1 }, { 0.5, 0, 0 }, { 1, 0, 0 }, { 0.9, 0, 0 }

local function UpdateQuality(frame, link, isBound)
    if MerchantFrameItem_UpdateQuality then
        MerchantFrameItem_UpdateQuality(frame, link, isBound)
        return
    end
    local quality = LinkQuality(link)
    frame.Name:SetTextColor(QualityColor(quality))
    if SetItemButtonQuality then
        SetItemButtonQuality(frame.ItemButton, quality, link, false, isBound)
    end
end

local function UpdateAltCurrency(frame, index, canAfford)
    local base = frame:GetName() .. "AltCurrencyFrameItem"
    local costs = GetMerchantItemCostInfo(index) or 0
    local used, width = 0, 0
    if costs > 0 then
        for i = 1, MAX_COST_ITEMS do
            local texture, value, itemLink = GetMerchantItemCostItem(index, i)
            if texture then
                used = used + 1
                local button = _G[base .. used]
                button.index = index
                button.item = i
                button.itemLink = itemLink
                AltCurrencyFrame_Update(base .. used, texture, value, canAfford)
                width = width + button:GetWidth()
                if used > 1 then width = width + 4 end
                button:Show()
            end
        end
    end
    for i = used + 1, MAX_COST_ITEMS do
        local button = _G[base .. i]
        if button then button:Hide() end
    end
    return width
end

local function FillMerchantSlot(frame, index)
    local name = frame:GetName()
    local button = frame.ItemButton
    local money = _G[name .. "MoneyFrame"]
    local alt = _G[name .. "AltCurrencyFrame"]
    local nameFrame = name .. "NameFrame"
    local info = MerchantItem(index)
    if not info then
        frame:Hide()
        return
    end
    local canAfford = CanAffordMerchantItem and CanAffordMerchantItem(index)
    local link = GetMerchantItemLink(index)

    frame.Name:SetText(info.name or "")
    SetItemButtonCount(button, info.stackCount)
    SetItemButtonStock(button, info.numAvailable)
    SetItemButtonTexture(button, info.texture)
    button.name = info.name
    button.link = link
    button.texture = info.texture

    local price = info.price or 0
    if info.hasExtendedCost and price <= 0 then
        button.price = nil
        button.extendedCost = true
        UpdateAltCurrency(frame, index, canAfford)
        alt:ClearAllPoints()
        alt:SetPoint("BOTTOMLEFT", nameFrame, "BOTTOMLEFT", 0, 31)
        money:Hide()
        alt:Show()
    elseif info.hasExtendedCost then
        button.price = price
        button.extendedCost = true
        local altWidth = UpdateAltCurrency(frame, index, canAfford)
        MoneyFrame_SetMaxDisplayWidth(money, MONEY_WIDTH - altWidth)
        MoneyFrame_Update(money:GetName(), price)
        SetMoneyFrameColor(money:GetName(), (canAfford == false) and "gray" or nil)
        alt:ClearAllPoints()
        alt:SetPoint("LEFT", money:GetName(), "RIGHT", -14, 0)
        alt:Show()
        money:Show()
    else
        button.price = price
        button.extendedCost = nil
        MoneyFrame_SetMaxDisplayWidth(money, MONEY_WIDTH)
        MoneyFrame_Update(money:GetName(), price)
        SetMoneyFrameColor(money:GetName(), (canAfford == false) and "gray" or nil)
        alt:Hide()
        money:Show()
    end

    if button.IconQuestTexture then
        if info.isQuestStartItem then
            button.IconQuestTexture:SetTexture(TEXTURE_ITEM_QUEST_BANG)
            button.IconQuestTexture:Show()
        else
            button.IconQuestTexture:Hide()
        end
    end

    UpdateQuality(frame, link)

    local itemID = GetMerchantItemID and GetMerchantItemID(index)
    local isHeirloom = itemID and C_Heirloom and C_Heirloom.IsItemHeirloom and C_Heirloom.IsItemHeirloom(itemID)
    local isKnownHeirloom = isHeirloom and C_Heirloom.PlayerHasHeirloom(itemID)

    button.showNonrefundablePrompt = not IsRefundable(index)
    button.hasItem = true
    button:SetID(index)
    button:Show()

    local tintRed = not info.isPurchasable or (not info.isUsable and not isHeirloom)
    SetItemButtonDesaturated(button, isKnownHeirloom)
    if info.numAvailable == 0 or isKnownHeirloom then
        if tintRed then
            TintSlot(frame, button, DARK_RED, DARK_RED, DARK_RED)
        else
            TintSlot(frame, button, GREY, GREY, GREY)
        end
    elseif tintRed then
        TintSlot(frame, button, RED, RED, DIM_RED)
    else
        TintSlot(frame, button, GREY, WHITE, WHITE)
    end
    frame:Show()
end

local function FillBuybackSlot(frame, index)
    local name = frame:GetName()
    local button = frame.ItemButton
    local money = _G[name .. "MoneyFrame"]
    local alt = _G[name .. "AltCurrencyFrame"]
    local itemName, texture, price, quantity, numAvailable, isUsable, isBound = GetBuybackItemInfo(index)
    if not itemName then
        frame:Hide()
        return
    end
    frame.Name:SetText(itemName)
    SetItemButtonCount(button, quantity)
    SetItemButtonStock(button, numAvailable)
    SetItemButtonTexture(button, texture)
    if button.IconQuestTexture then button.IconQuestTexture:Hide() end
    alt:Hide()
    MoneyFrame_SetMaxDisplayWidth(money, MONEY_WIDTH)
    MoneyFrame_Update(money:GetName(), price)
    SetMoneyFrameColor(money:GetName(), nil)
    money:Show()
    UpdateQuality(frame, GetBuybackItemLink(index), isBound)
    button.price = nil
    button.extendedCost = nil
    button.showNonrefundablePrompt = nil
    button.hasItem = true
    button:SetID(index)
    button:Show()
    SetItemButtonDesaturated(button, false)
    if not isUsable then
        TintSlot(frame, button, RED, RED, DIM_RED)
    else
        TintSlot(frame, button, GREY, WHITE, WHITE)
    end
    frame:Show()
end

local function AcquireSlot(i)
    local frame = slots[i]
    if not frame then
        frame = CreateFrame("Frame", "UlRemedyVendorItem" .. i, ui.content, "MerchantItemTemplate")
        slots[i] = frame
    end
    return frame
end

------------------------------------------------------------------------
-- Layout and refresh
------------------------------------------------------------------------

local function GridWidth()
    return MerchantFrame:GetWidth() - LEFT_PAD - BAR_W - 6
end

local function Columns()
    return math.max(1, math.floor((GridWidth() + GAP_X) / (ITEM_W + GAP_X)))
end

local function ScrollUpdate()
    local box = ui.scrollBox
    if not box then return end
    if box.FullUpdate then
        box:FullUpdate(ScrollBoxConstants and ScrollBoxConstants.UpdateImmediately)
    elseif box.Update then
        box:Update(true)
    end
end

local shownCount = 0

local function Layout()
    local columns = Columns()
    for k = 1, shownCount do
        local frame = slots[k]
        local col = (k - 1) % columns
        local row = math.floor((k - 1) / columns)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", ui.content, "TOPLEFT", col * (ITEM_W + GAP_X), -row * (ITEM_H + GAP_Y))
    end
    local rows = math.ceil(shownCount / columns)
    local height = rows > 0 and (rows * (ITEM_H + GAP_Y) - GAP_Y) or 1
    ui.content:SetSize(GridWidth(), height)
    ScrollUpdate()
end

local function CloseOurStackSplit()
    if not StackSplitFrame or not StackSplitFrame:IsShown() then return end
    for _, frame in ipairs(slots) do
        if StackSplitFrame.owner == frame.ItemButton then
            if StackSplitCancelButton_OnClick then StackSplitCancelButton_OnClick() else StackSplitFrame:Hide() end
            return
        end
    end
end

local function Refresh()
    if not active then return end
    local tab = MerchantFrame.selectedTab or 1
    if tab ~= lastTab then
        CloseOurStackSplit()
        lastTab = tab
    end
    needQuality = false
    local list = (tab == 1) and BuildMerchantList() or BuildBuybackList()
    for k, entry in ipairs(list) do
        local frame = AcquireSlot(k)
        if tab == 1 then
            FillMerchantSlot(frame, entry.index)
        else
            FillBuybackSlot(frame, entry.index)
        end
    end
    for k = #list + 1, #slots do
        slots[k]:Hide()
        slots[k].ItemButton.hasItem = nil
    end
    shownCount = #list
    Layout()

    local total = (tab == 1) and GetMerchantNumItems() or GetNumBuybackItems()
    if ui.count then
        if #list == total then
            ui.count:SetText(total .. " items")
        else
            ui.count:SetText(#list .. " of " .. total .. " items")
        end
    end
    if ui.quality then ui.quality:SetText(QUALITY_STEPS[db.quality].label) end
    if ui.sort then ui.sort:SetText(SORT_LABEL[db.sort]) end
    if ui.usable then
        ui.usable:SetChecked(db.usable)
        ui.usable:SetShown(tab == 1)
        ui.usableLabel:SetShown(tab == 1)
    end
    if ui.quality then ui.quality:SetShown(tab == 1) end
    if ui.sort then ui.sort:SetShown(tab == 1) end

    if needQuality then
        ui.events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    else
        ui.events:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
    end
end

local function SafeRefresh()
    local ok, err = pcall(Refresh)
    if not ok then
        Report(err)
        if UlRemedy.DeactivateVendorWindow then UlRemedy.DeactivateVendorWindow() end
    end
end

-- Hide the parts of Blizzard's layout our grid replaces. Called after every
-- MerchantFrame_Update, because Blizzard shows some of them again on the
-- buyback tab.
local function HideBlizzardSlots()
    for i = 1, NUM_BLIZZARD_SLOTS do
        local frame = _G["MerchantItem" .. i]
        if frame then frame:Hide() end
    end
    if MerchantPageText then MerchantPageText:Hide() end
    if MerchantPrevPageButton then MerchantPrevPageButton:Hide() end
    if MerchantNextPageButton then MerchantNextPageButton:Hide() end
    if BuybackBG then BuybackBG:Hide() end
end

------------------------------------------------------------------------
-- Activate / deactivate on MerchantFrame
------------------------------------------------------------------------

local function SetResizeBounds()
    if MerchantFrame.SetResizeBounds then
        MerchantFrame:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H)
    else
        if MerchantFrame.SetMinResize then MerchantFrame:SetMinResize(MIN_W, MIN_H) end
        if MerchantFrame.SetMaxResize then MerchantFrame:SetMaxResize(MAX_W, MAX_H) end
    end
end

local function ClampSize()
    local w = math.max(MIN_W, math.min(MAX_W, math.floor(MerchantFrame:GetWidth() + 0.5)))
    local h = math.max(MIN_H, math.min(MAX_H, math.floor(MerchantFrame:GetHeight() + 0.5)))
    MerchantFrame:SetSize(w, h)
    db.width, db.height = w, h
end

local function Activate()
    if active then return end
    active = true
    MerchantFrame:SetResizable(true)
    SetResizeBounds()
    MerchantFrame:SetSize(db.width, db.height)

    HideBlizzardSlots()

    if MerchantFrameBottomLeftBorder then
        MerchantFrameBottomLeftBorder:ClearAllPoints()
        MerchantFrameBottomLeftBorder:SetPoint("BOTTOMLEFT", MerchantFrame, "BOTTOMLEFT", 1, 26)
        MerchantFrameBottomLeftBorder:SetPoint("BOTTOMRIGHT", MerchantFrame, "BOTTOMRIGHT", -1, 26)
    end
    if MerchantBuyBackItem then
        MerchantBuyBackItem:ClearAllPoints()
        MerchantBuyBackItem:SetPoint("BOTTOMLEFT", MerchantFrame, "BOTTOMLEFT", 206, 33)
    end

    for _, key in ipairs({ "controls", "scrollBox", "scrollBar", "grip" }) do
        if ui[key] then ui[key]:Show() end
    end
    lastTab = nil
end

local function Deactivate()
    if not active then return end
    active = false
    for _, key in ipairs({ "controls", "scrollBox", "scrollBar", "grip" }) do
        if ui[key] then ui[key]:Hide() end
    end
    for _, frame in ipairs(slots) do frame:Hide() end
    shownCount = 0

    MerchantFrame:SetSize(ORIGINAL_W, ORIGINAL_H)
    for i = 1, 10 do
        local frame = _G["MerchantItem" .. i]
        if frame then frame:Show() end
    end
    if MerchantFrameBottomLeftBorder then
        MerchantFrameBottomLeftBorder:ClearAllPoints()
        MerchantFrameBottomLeftBorder:SetPoint("BOTTOMLEFT", MerchantFrame, "BOTTOMLEFT", 1, 26)
        MerchantFrameBottomLeftBorder:SetSize(334, 61)
    end
    if MerchantBuyBackItem and MerchantItem10 then
        MerchantBuyBackItem:ClearAllPoints()
        MerchantBuyBackItem:SetPoint("TOPLEFT", MerchantItem10, "BOTTOMLEFT", 30, -53)
    end
    if MerchantFrame:IsShown() and MerchantFrame_Update then
        MerchantFrame_Update()
    end
end

function UlRemedy.DeactivateVendorWindow()
    pcall(Deactivate)
end

------------------------------------------------------------------------
-- Building our frames on MerchantFrame (once)
------------------------------------------------------------------------

local pendingLayout = false

local function ScheduleLayout()
    if pendingLayout or not active then return end
    pendingLayout = true
    C_Timer.After(0, function()
        pendingLayout = false
        if active then pcall(Layout) end
    end)
end

local function CreateControls()
    -- One row under the portrait (which reaches y = -66) and the filter
    -- dropdown Blizzard keeps at the top right.
    local controls = CreateFrame("Frame", "UlRemedyVendorControls", MerchantFrame)
    controls:SetPoint("TOPLEFT", MerchantFrame, "TOPLEFT", LEFT_PAD, -68)
    controls:SetPoint("TOPRIGHT", MerchantFrame, "TOPRIGHT", -LEFT_PAD, -68)
    controls:SetHeight(22)
    ui.controls = controls

    local search = CreateFrame("EditBox", "UlRemedyVendorSearch", controls, "SearchBoxTemplate")
    search:SetSize(140, 20)
    search:SetPoint("LEFT", controls, "LEFT", 6, 0)
    search:SetAutoFocus(false)
    search:HookScript("OnTextChanged", function() SafeRefresh() end)
    ui.search = search

    local quality = CreateFrame("Button", "UlRemedyVendorQuality", controls, "UIPanelButtonTemplate")
    quality:SetSize(132, 22)
    quality:SetPoint("LEFT", search, "RIGHT", 8, 0)
    quality:SetScript("OnClick", function()
        db.quality = (db.quality % #QUALITY_STEPS) + 1
        SafeRefresh()
    end)
    ui.quality = quality

    local sort = CreateFrame("Button", "UlRemedyVendorSort", controls, "UIPanelButtonTemplate")
    sort:SetSize(132, 22)
    sort:SetPoint("LEFT", quality, "RIGHT", 4, 0)
    sort:SetScript("OnClick", function()
        local pos = 1
        for i, key in ipairs(SORT_STEPS) do
            if key == db.sort then pos = i end
        end
        db.sort = SORT_STEPS[(pos % #SORT_STEPS) + 1]
        SafeRefresh()
    end)
    ui.sort = sort

    local usable = CreateFrame("CheckButton", "UlRemedyVendorUsable", controls, "UICheckButtonTemplate")
    usable:SetSize(24, 24)
    usable:SetPoint("LEFT", sort, "RIGHT", 2, 0)
    usable:SetScript("OnClick", function(self)
        db.usable = self:GetChecked() and true or false
        SafeRefresh()
    end)
    ui.usable = usable
    local label = controls:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", usable, "RIGHT", 0, 0)
    label:SetText("Usable")
    ui.usableLabel = label

    local count = MerchantFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    count:SetPoint("BOTTOM", MerchantFrame, "BOTTOM", 0, 86)
    ui.count = count
end

local function CreateGrid()
    local box = CreateFrame("Frame", "UlRemedyVendorScrollBox", MerchantFrame, "WowScrollBox")
    box:SetPoint("TOPLEFT", MerchantFrame, "TOPLEFT", LEFT_PAD, -TOP_PAD)
    box:SetPoint("BOTTOMRIGHT", MerchantFrame, "BOTTOMRIGHT", -(BAR_W + 6), BOTTOM_PAD)
    local bar = CreateFrame("EventFrame", "UlRemedyVendorScrollBar", MerchantFrame, "MinimalScrollBar")
    bar:SetPoint("TOPLEFT", box, "TOPRIGHT", 6, 0)
    bar:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 6, 0)

    -- The content frame must exist, and be flagged scrollable, before the
    -- view is attached: the box adopts flagged children into its scroll
    -- target at that moment.
    local content = CreateFrame("Frame", "UlRemedyVendorContent", box)
    content.scrollable = true
    content:SetSize(GridWidth(), 1)

    -- Without an explicit pan extent the wheel would scroll by the height of
    -- the first child, which is the whole grid.
    local view = CreateScrollBoxLinearView()
    if view.SetPanExtent then view:SetPanExtent(ITEM_H + GAP_Y) end
    ScrollUtil.InitScrollBoxWithScrollBar(box, bar, view)

    ui.scrollBox, ui.scrollBar, ui.content = box, bar, content
end

local function CreateGrip()
    local grip = CreateFrame("Button", "UlRemedyVendorResize", MerchantFrame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", MerchantFrame, "BOTTOMRIGHT", -2, 2)
    grip:SetFrameLevel(MerchantFrame:GetFrameLevel() + 10)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetScript("OnMouseDown", function()
        if not active then return end
        MerchantFrame:StartSizing("BOTTOMRIGHT")
    end)
    grip:SetScript("OnMouseUp", function()
        if not active then return end
        MerchantFrame:StopMovingOrSizing()
        pcall(ClampSize)
        SafeRefresh()
    end)
    grip:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Drag to resize the vendor window")
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ui.grip = grip
end

------------------------------------------------------------------------
-- Bag panel
------------------------------------------------------------------------

local function LastBag()
    return NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
end

local function BagSearchText()
    local box = ui.bagSearch
    if not box then return "" end
    return strtrim(box:GetText() or ""):lower()
end

local function SlotText(bag, slot)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if not info or not info.hyperlink then return nil end
    local link = info.hyperlink
    local name = link:match("%[(.-)%]") or ""
    return name, info, link
end

local function SellSlot(bag, slot, expectedItemID)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if not info or not info.hyperlink then return end
    if expectedItemID and info.itemID and info.itemID ~= expectedItemID then
        print(UlRemedy.name .. ": that bag slot changed, nothing sold.")
        return
    end
    if not (MerchantFrame and MerchantFrame:IsShown()) then return end
    local count = info.stackCount or 1
    local price = UlRemedy.ItemVendorPrice(info.hyperlink)
    C_Container.UseContainerItem(bag, slot)
    if price and price > 0 then
        print(UlRemedy.name .. ": sold " .. info.hyperlink .. (count > 1 and (" x" .. count) or "")
            .. " for " .. UlRemedy.MoneyText(price * count) .. ".")
    end
end

StaticPopupDialogs["ULREMEDY_SELL_ITEM"] = {
    text = "Sell %s for %s?",
    button1 = SELL or "Sell",
    button2 = CANCEL or "Cancel",
    OnAccept = function(self, data)
        if data then SellSlot(data.bag, data.slot, data.itemID) end
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    preferredIndex = 3,
}

local function TrySell(button)
    local bag, slot = button.bag, button.slot
    local name, info, link = SlotText(bag, slot)
    if not info then return end
    if info.isLocked then
        print(UlRemedy.name .. ": " .. link .. " is locked right now.")
        return
    end
    local questInfo = C_Container.GetContainerItemQuestInfo and C_Container.GetContainerItemQuestInfo(bag, slot)
    if questInfo and (questInfo.isQuestItem or questInfo.questID) then
        print(UlRemedy.name .. ": " .. link .. " is a quest item, not sold.")
        return
    end
    if info.hasNoValue then
        print(UlRemedy.name .. ": " .. link .. " has no vendor value.")
        return
    end
    local quality = info.quality or LinkQuality(link) or 1
    if quality >= (Enum.ItemQuality.Uncommon or 2) then
        local count = info.stackCount or 1
        local price = UlRemedy.ItemVendorPrice(link)
        local priceText = price and UlRemedy.MoneyText(price * count) or "an unknown price"
        local label = link .. (count > 1 and (" x" .. count) or "")
        StaticPopup_Show("ULREMEDY_SELL_ITEM", label, priceText, { bag = bag, slot = slot, itemID = info.itemID })
        return
    end
    SellSlot(bag, slot, info.itemID)
end

local function CreateBagButton(i, parent)
    local name = "UlRemedyVendorBagItem" .. i
    local ok, button = pcall(CreateFrame, "ItemButton", name, parent)
    if not ok or not button then
        button = CreateFrame("Button", name, parent, "ItemButtonTemplate")
    end
    button:SetSize(BAG_BTN, BAG_BTN)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetScript("OnEnter", function(self)
        if not self.bag then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetBagItem(self.bag, self.slot)
        if self.hasItem and ShowContainerSellCursor then
            ShowContainerSellCursor(self.bag, self.slot)
        end
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
        ResetCursor()
    end)
    button:SetScript("OnClick", function(self, mouseButton)
        if not self.hasItem then return end
        local _, _, link = SlotText(self.bag, self.slot)
        if link and IsModifiedClick("CHATLINK") then
            HandleModifiedItemClick(link)
            return
        end
        if mouseButton == "LeftButton" then
            TrySell(self)
        end
    end)
    return button
end

local function RefreshBags()
    local panel = ui.bags
    if not panel or not panel:IsShown() then return end
    local text = BagSearchText()
    local k = 0
    for bag = 0, LastBag() do
        local numSlots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, numSlots do
            k = k + 1
            local button = bags[k]
            if not button then
                button = CreateBagButton(k, ui.bagContent)
                bags[k] = button
            end
            button.bag, button.slot = bag, slot
            local col = (k - 1) % BAG_COLS
            local row = math.floor((k - 1) / BAG_COLS)
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", ui.bagContent, "TOPLEFT", col * (BAG_BTN + BAG_GAP), -row * (BAG_BTN + BAG_GAP))
            local name, info, link = SlotText(bag, slot)
            if info then
                button.hasItem = true
                button.itemID = info.itemID
                SetItemButtonTexture(button, info.iconFileID)
                SetItemButtonCount(button, info.stackCount or 1)
                SetItemButtonDesaturated(button, info.isLocked)
                if SetItemButtonQuality then
                    SetItemButtonQuality(button, info.quality, link, false, info.isBound)
                end
                local dim = text ~= "" and not name:lower():find(text, 1, true)
                if button.searchOverlay then
                    button.searchOverlay:SetShown(dim)
                else
                    button:SetAlpha(dim and 0.3 or 1)
                end
            else
                button.hasItem = nil
                button.itemID = nil
                SetItemButtonTexture(button, nil)
                SetItemButtonCount(button, 0)
                SetItemButtonDesaturated(button, false)
                if SetItemButtonQuality then SetItemButtonQuality(button, nil, nil) end
                if button.searchOverlay then button.searchOverlay:Hide() else button:SetAlpha(1) end
            end
            button:Show()
        end
    end
    for i = k + 1, #bags do
        bags[i]:Hide()
        bags[i].hasItem = nil
    end
    local rows = math.ceil(k / BAG_COLS)
    ui.bagContent:SetSize(BAG_COLS * (BAG_BTN + BAG_GAP) - BAG_GAP, rows > 0 and (rows * (BAG_BTN + BAG_GAP) - BAG_GAP) or 1)
    local box = ui.bagBox
    if box.FullUpdate then
        box:FullUpdate(ScrollBoxConstants and ScrollBoxConstants.UpdateImmediately)
    elseif box.Update then
        box:Update(true)
    end
end

local function SafeRefreshBags()
    local ok, err = pcall(RefreshBags)
    if not ok then Report(err) end
end

local function CreateBagPanel()
    local panel = CreateFrame("Frame", "UlRemedyVendorBags", MerchantFrame, "BasicFrameTemplateWithInset")
    panel:SetWidth(BAGS_W)
    panel:SetPoint("TOPLEFT", MerchantFrame, "TOPRIGHT", 2, 0)
    panel:SetPoint("BOTTOMLEFT", MerchantFrame, "BOTTOMRIGHT", 2, 0)
    panel:EnableMouse(true)
    if panel.CloseButton then panel.CloseButton:Hide() end
    local title = panel.TitleText or (panel.TitleContainer and panel.TitleContainer.TitleText)
    if title then title:SetText("Bags") end
    ui.bags = panel

    local search = CreateFrame("EditBox", "UlRemedyVendorBagSearch", panel, "SearchBoxTemplate")
    search:SetSize(BAGS_W - 24, 20)
    search:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -30)
    search:SetAutoFocus(false)
    search:HookScript("OnTextChanged", function() SafeRefreshBags() end)
    ui.bagSearch = search

    local box = CreateFrame("Frame", "UlRemedyVendorBagBox", panel, "WowScrollBox")
    box:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -56)
    box:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -(BAR_W + 4), 26)
    local bar = CreateFrame("EventFrame", "UlRemedyVendorBagBar", panel, "MinimalScrollBar")
    bar:SetPoint("TOPLEFT", box, "TOPRIGHT", 6, 0)
    bar:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 6, 0)
    local content = CreateFrame("Frame", "UlRemedyVendorBagContent", box)
    content.scrollable = true
    content:SetSize(BAG_COLS * (BAG_BTN + BAG_GAP) - BAG_GAP, 1)
    local view = CreateScrollBoxLinearView()
    if view.SetPanExtent then view:SetPanExtent(BAG_BTN + BAG_GAP) end
    ScrollUtil.InitScrollBoxWithScrollBar(box, bar, view)
    ui.bagBox, ui.bagContent = box, content

    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOM", panel, "BOTTOM", 0, 9)
    hint:SetText("Click sells. Green and better ask first.")

    panel:SetScript("OnShow", SafeRefreshBags)
end

local function UpdateBagPanel()
    if not ui.bags then return end
    if BagsEnabled() then
        ui.bags:Show()
        SafeRefreshBags()
    else
        ui.bags:Hide()
    end
end

------------------------------------------------------------------------
-- Wiring
------------------------------------------------------------------------

-- Set a script when the frame has none, hook it when it has one. HookScript
-- on a frame without a handler is not reliable on every client.
local function AddScript(frame, script, fn)
    if frame:GetScript(script) then
        frame:HookScript(script, fn)
    else
        frame:SetScript(script, fn)
    end
end

local function Setup()
    if hooked or not MerchantFrame then return end
    hooked = true

    CreateControls()
    CreateGrid()
    CreateGrip()
    CreateBagPanel()
    for _, key in ipairs({ "controls", "scrollBox", "scrollBar", "grip", "bags" }) do
        ui[key]:Hide()
    end

    hooksecurefunc("MerchantFrame_Update", function()
        if not active then return end
        pcall(HideBlizzardSlots)
        SafeRefresh()
    end)
    if MerchantFrame_UpdateItemQualityBorders then
        hooksecurefunc("MerchantFrame_UpdateItemQualityBorders", function()
            if active then SafeRefresh() end
        end)
    end
    AddScript(MerchantFrame, "OnSizeChanged", ScheduleLayout)
    AddScript(MerchantFrame, "OnShow", function()
        -- Blizzard's own OnShow has already run one MerchantFrame_Update
        -- with our grid inactive, so refresh once here as well.
        if Enabled() then
            local ok, err = pcall(Activate)
            if ok then SafeRefresh() else Report(err) pcall(Deactivate) end
        else
            pcall(Deactivate)
        end
        UpdateBagPanel()
        if BagsEnabled() and CloseAllBags then
            -- Blizzard opens every bag with the vendor; the panel takes over.
            pcall(CloseAllBags, MerchantFrame, true)
        end
    end)
    AddScript(MerchantFrame, "OnHide", function()
        if ui.search then ui.search:SetText("") end
        if ui.bagSearch then ui.bagSearch:SetText("") end
        ui.events:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
    end)
end

-- Called by Core when a feature is toggled.
function UlRemedy.RefreshVendor()
    if not db then return end
    if not hooked then
        local ok, err = pcall(Setup)
        if not ok then Report(err) return end
    end
    if MerchantFrame and MerchantFrame:IsShown() then
        if Enabled() then
            local ok, err = pcall(Activate)
            if not ok then Report(err) Deactivate() return end
            if MerchantFrame_Update then MerchantFrame_Update() end
        else
            pcall(Deactivate)
        end
        UpdateBagPanel()
    end
end

function UlRemedy.ResetVendorWindow()
    if not db then return end
    db.width, db.height = DEFAULT_W, DEFAULT_H
    if active then
        MerchantFrame:SetSize(db.width, db.height)
        SafeRefresh()
    end
    print(UlRemedy.name .. ": vendor window size reset.")
end

local events = CreateFrame("Frame", "UlRemedyVendorEvents")
ui.events = events
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:RegisterEvent("ITEM_LOCK_CHANGED")
events:RegisterEvent("PLAYER_MONEY")

local qualityPending = false

events:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == UlRemedy.name then
        InitDB()
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        local ok, err = pcall(Setup)
        if not ok then Report(err) end
        self:UnregisterEvent("PLAYER_LOGIN")
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        if qualityPending or not active then return end
        qualityPending = true
        C_Timer.After(0.2, function()
            qualityPending = false
            if active then SafeRefresh() end
        end)
    elseif event == "BAG_UPDATE_DELAYED" or event == "ITEM_LOCK_CHANGED" then
        if ui.bags and ui.bags:IsShown() then SafeRefreshBags() end
    elseif event == "PLAYER_MONEY" then
        if active then SafeRefresh() end
    end
end)
