-- Auction Prices: adds the auction house price of an item to its tooltip,
-- per unit and for the whole stack, the same way the vendor sell price is
-- shown.
--
-- The game has no price database to ask; auction prices exist only inside
-- the auction house window while it is open. So the module reads whatever
-- the auction house shows while you are there and remembers it:
--   * everything you browse or search for, passively, and
--   * a full list when you press the Scan button the module adds to the
--     auction house window (the client allows that about every 15 minutes).
-- Stored per realm and faction, since prices differ between them:
-- itemID -> lowest buyout per unit seen in the latest results, and when.
-- The tooltip shows that price with its age, so an old price is visibly
-- old. No average, no history: the last thing the auction house showed.
--
-- Data sources, each used when the client has it:
--   C_AuctionHouse browse results, commodity results, item results and the
--   replicate list (retail-style auction house), and the classic
--   GetAuctionItemInfo list as a fallback. /ur ah prints which of these the
--   client actually delivered, so the first visit to the auction house
--   tells us what the Forever client has.
--
-- Hooks: the item tooltip post-call on clients with TooltipDataProcessor,
-- OnTooltipSetItem otherwise. GameTooltip and ItemRefTooltip only. The
-- stack count comes from the tooltip's own source (bag slot or inventory
-- slot) on clients that expose it, else from SetBagItem and
-- SetInventoryItem hooks.

local SCAN_COOLDOWN = 15 * 60   -- what the client enforces for a full list

local DB
local market                    -- DB.realms[realmKey]: itemID -> { p, at, q }
local lastError
local stats = { browse = 0, commodity = 0, item = 0, replicate = 0, classic = 0, stored = 0 }
local lastScanAt                -- GetTime() of the last full scan request
local scanPending = false       -- a full scan was asked for and not yet read
local scanButton

local frame = CreateFrame("Frame", "UlRemedyAuctionPricesFrame")

local function Enabled()
    return UlRemedy.enabled and UlRemedy.enabled.auction
end

local function Report(err)
    err = tostring(err)
    if err == lastError then return end
    lastError = err
    print(UlRemedy.name .. ": auction prices error: " .. err)
end

-- A number that is safe to compute with: not nil, not a secret value.
local function PlainNumber(v)
    if type(v) ~= "number" then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

local function RealmKey()
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    if not realm or realm == "" then
        realm = (GetRealmName() or ""):gsub("%s+", "")
    end
    local faction = UnitFactionGroup("player") or "Neutral"
    return realm .. "-" .. faction
end

local function InitDB()
    if not UlRemedyForeverAuctionDB then UlRemedyForeverAuctionDB = {} end
    DB = UlRemedyForeverAuctionDB
    DB.realms = DB.realms or {}
end

local function InitRealm()
    if not DB then return end
    local key = RealmKey()
    DB.realms[key] = DB.realms[key] or { items = {}, scanned = nil }
    market = DB.realms[key]
end

------------------------------------------------------------------------
-- Recording prices
------------------------------------------------------------------------

-- One batch per results update: the lowest unit price per item in that
-- update, then written over whatever was stored, since the auction house
-- just showed us the current state for those items.
local function NewBatch() return {} end

local function Note(batch, itemID, unitPrice, quantity)
    itemID = PlainNumber(itemID)
    unitPrice = PlainNumber(unitPrice)
    if not itemID or itemID <= 0 or not unitPrice or unitPrice <= 0 then return end
    local cur = batch[itemID]
    if not cur then
        batch[itemID] = { p = unitPrice, q = PlainNumber(quantity) or 1 }
    elseif unitPrice < cur.p then
        cur.p = unitPrice
        cur.q = PlainNumber(quantity) or 1
    end
end

local function Commit(batch, source)
    if not market then InitRealm() end
    if not market then return 0 end
    local now = time()
    local n = 0
    for itemID, rec in pairs(batch) do
        market.items[itemID] = { p = rec.p, at = now, q = rec.q }
        n = n + 1
    end
    if n > 0 then
        stats[source] = (stats[source] or 0) + n
        stats.stored = stats.stored + n
    end
    return n
end

local function ReadBrowseResults()
    if not (C_AuctionHouse and C_AuctionHouse.GetBrowseResults) then return end
    local results = C_AuctionHouse.GetBrowseResults()
    if not results then return end
    local batch = NewBatch()
    for _, r in ipairs(results) do
        local key = r.itemKey
        Note(batch, key and key.itemID, r.minPrice, 1)
    end
    Commit(batch, "browse")
end

local function ReadCommodityResults(itemID)
    if not (C_AuctionHouse and C_AuctionHouse.GetNumCommoditySearchResults) then return end
    itemID = PlainNumber(itemID)
    if not itemID then return end
    local n = C_AuctionHouse.GetNumCommoditySearchResults(itemID) or 0
    local batch = NewBatch()
    for i = 1, n do
        local r = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i)
        if r then Note(batch, r.itemID or itemID, r.unitPrice, r.quantity) end
    end
    Commit(batch, "commodity")
end

local function ReadItemResults(itemKey)
    if not (C_AuctionHouse and C_AuctionHouse.GetNumItemSearchResults) or not itemKey then return end
    local n = C_AuctionHouse.GetNumItemSearchResults(itemKey) or 0
    local batch = NewBatch()
    for i = 1, n do
        local r = C_AuctionHouse.GetItemSearchResultInfo(itemKey, i)
        if r then
            local buyout = PlainNumber(r.buyoutAmount)
            local qty = PlainNumber(r.quantity) or 1
            if buyout and buyout > 0 and qty > 0 then
                Note(batch, (r.itemKey and r.itemKey.itemID) or itemKey.itemID, buyout / qty, qty)
            end
        end
    end
    Commit(batch, "item")
end

-- The full list (Scan button). Both the retail replicate list and the
-- classic list return the same positional values.
--
-- A full list is big (73 000 auctions on the Forever beta) and the client
-- stops an addon that runs too long in one frame ("insecure scripts
-- exceeded execution limit"), so the list is read in chunks, one chunk
-- per frame, and written to the database when the last chunk is done.
-- The client also fires the list-updated event again after the first
-- time; only the one we asked for is read.
local SCAN_CHUNK = 1500
local scanJob                   -- { getInfo, source, index, n, batch }

local function FinishScan(job)
    scanJob = nil
    frame:SetScript("OnUpdate", nil)
    local stored = Commit(job.batch, job.source)
    if market then market.scanned = { at = time(), auctions = job.n, items = stored } end
    print(UlRemedy.name .. ": auction scan read " .. job.n .. " auctions, " .. stored .. " item prices stored.")
    if scanButton then scanButton:SetText("Scanned " .. stored) end
end

local function StepScan()
    local job = scanJob
    if not job then
        frame:SetScript("OnUpdate", nil)
        return
    end
    local last = math.min(job.index + SCAN_CHUNK - 1, job.n)
    local ok, err = pcall(function()
        for i = job.index, last do
            local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = job.getInfo(i)
            buyout = PlainNumber(buyout)
            count = PlainNumber(count) or 1
            if buyout and buyout > 0 and count > 0 then
                Note(job.batch, itemID, buyout / count, count)
            end
        end
    end)
    if not ok then
        Report(err)
        scanJob = nil
        frame:SetScript("OnUpdate", nil)
        if scanButton then scanButton:SetText("Scan failed") end
        return
    end
    job.index = last + 1
    if job.index > job.n then
        FinishScan(job)
    elseif scanButton then
        scanButton:SetText(("Reading %d%%"):format(math.floor(100 * last / job.n)))
    end
end

local function ReadFullList(getNum, getInfo, source)
    if scanJob then return end
    local n = getNum() or 0
    scanJob = { getInfo = getInfo, source = source, index = 1, n = n, batch = NewBatch() }
    if n == 0 then
        FinishScan(scanJob)
        return
    end
    frame:SetScript("OnUpdate", StepScan)
end

------------------------------------------------------------------------
-- The Scan button on the auction house window
------------------------------------------------------------------------

local function CanScan()
    if lastScanAt and GetTime() - lastScanAt < SCAN_COOLDOWN then return false end
    if C_AuctionHouse and C_AuctionHouse.ReplicateItems then return true end
    if QueryAuctionItems and (not CanSendAuctionQuery or CanSendAuctionQuery()) then return true end
    return false
end

local function RequestScan()
    if not CanScan() then return end
    lastScanAt = GetTime()
    scanPending = true
    if scanButton then
        scanButton:SetText("Scanning...")
        scanButton:Disable()
        C_Timer.After(SCAN_COOLDOWN, function()
            if scanButton then
                scanButton:SetText("Scan prices")
                scanButton:Enable()
            end
        end)
    end
    local ok, err = pcall(function()
        if C_AuctionHouse and C_AuctionHouse.ReplicateItems then
            C_AuctionHouse.ReplicateItems()
        elseif QueryAuctionItems then
            QueryAuctionItems("", nil, nil, 0, 0, 0, 0, 0, 0, true)
        end
    end)
    if not ok then Report(err) end
end

local buttonTries = 0
local buttonNote = "not tried yet"

-- The auction house window lives in Blizzard_AuctionHouseUI, which is
-- loaded on demand, so at AUCTION_HOUSE_SHOW the frame may not exist yet.
-- Retry a few times over the next seconds, and again when that addon loads.
local function EnsureScanButton()
    if scanButton then
        scanButton:SetShown(Enabled())
        return
    end
    local parent = AuctionHouseFrame or AuctionFrame
    if not parent then
        buttonTries = buttonTries + 1
        buttonNote = "no auction frame yet (try " .. buttonTries .. ")"
        if buttonTries <= 10 then C_Timer.After(0.5, EnsureScanButton) end
        return
    end
    buttonNote = "created on " .. (parent:GetName() or "?")
    scanButton = CreateFrame("Button", "UlRemedyAuctionScanButton", parent, "UIPanelButtonTemplate")
    scanButton:SetSize(110, 22)
    -- Top right of the window, left of the close button.
    local close = parent.CloseButton or _G[parent:GetName() .. "CloseButton"]
    if close then
        scanButton:SetPoint("RIGHT", close, "LEFT", -4, 0)
    else
        scanButton:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -32, -4)
    end
    scanButton:SetText("Scan prices")
    -- The window's border art is drawn over children at nearby frame
    -- levels (the button took clicks but was invisible on 1.8.1), so lift
    -- it a whole stratum. Tooltips still sit above it.
    scanButton:SetFrameStrata("DIALOG")
    scanButton:SetFrameLevel(parent:GetFrameLevel() + 10)
    scanButton:SetScript("OnClick", RequestScan)
    scanButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:SetText("Scan auction prices")
        GameTooltip:AddLine("Reads the whole auction list and remembers the lowest buyout per item, for the tooltips. The client allows this about every 15 minutes. Browsing and searching are remembered on their own.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    scanButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    scanButton:SetShown(Enabled())
end

------------------------------------------------------------------------
-- The tooltip lines
------------------------------------------------------------------------

local function AgeText(at)
    local s = time() - (at or 0)
    if s < 0 then s = 0 end
    if s < 3600 then return math.floor(s / 60) .. " min ago" end
    if s < 86400 then return math.floor(s / 3600) .. " h ago" end
    return math.floor(s / 86400) .. " d ago"
end

local function MoneyLine(tooltip, prefix, amount, suffix)
    if type(SetTooltipMoney) == "function" then
        local ok = pcall(SetTooltipMoney, tooltip, amount, nil, prefix, suffix)
        if ok then return end
    end
    tooltip:AddLine(prefix .. " " .. UlRemedy.MoneyText(amount) .. (suffix and (" " .. suffix) or ""), 1, 1, 1)
end

-- How many of the item the tooltip is about: the bag or inventory slot it
-- was built from, else what the SetBagItem/SetInventoryItem hooks saw.
local function StackCount(tooltip)
    if tooltip.GetPrimaryTooltipInfo then
        local ok, info = pcall(tooltip.GetPrimaryTooltipInfo, tooltip)
        if ok and info and info.getterName and info.getterArgs then
            local args = info.getterArgs
            if info.getterName == "GetBagItem" and C_Container and C_Container.GetContainerItemInfo then
                local ok2, itemInfo = pcall(C_Container.GetContainerItemInfo, args[1], args[2])
                local n = ok2 and itemInfo and PlainNumber(itemInfo.stackCount)
                if n and n > 0 then return n end
            elseif info.getterName == "GetInventoryItem" and GetInventoryItemCount then
                local ok2, n = pcall(GetInventoryItemCount, args[1], args[2])
                n = ok2 and PlainNumber(n)
                if n and n > 0 then return n end
            end
        end
    end
    local n = PlainNumber(tooltip.ulRemedyStack)
    if n and n > 0 then return n end
    return 1
end

local function AddLines(tooltip, itemID)
    if not Enabled() or not itemID or not market then return end
    if tooltip.ulRemedyAuctionID == itemID then return end
    local rec = market.items[itemID]
    if not rec or not rec.p then return end
    tooltip.ulRemedyAuctionID = itemID
    local count = StackCount(tooltip)
    MoneyLine(tooltip, "Auction:", rec.p, "(" .. AgeText(rec.at) .. ")")
    if count > 1 then
        MoneyLine(tooltip, "Auction x" .. count .. ":", rec.p * count)
    end
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
                tooltip.ulRemedyAuctionID = nil
                tooltip.ulRemedyStack = nil
            end)
        end
    end
    -- Stack count fallback for clients without GetPrimaryTooltipInfo.
    if GameTooltip.SetBagItem then
        hooksecurefunc(GameTooltip, "SetBagItem", function(self, bag, slot)
            if C_Container and C_Container.GetContainerItemInfo then
                local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
                self.ulRemedyStack = ok and info and PlainNumber(info.stackCount) or nil
            elseif GetContainerItemInfo then
                local _, n = GetContainerItemInfo(bag, slot)
                self.ulRemedyStack = PlainNumber(n)
            end
        end)
    end
    if GameTooltip.SetInventoryItem and GetInventoryItemCount then
        hooksecurefunc(GameTooltip, "SetInventoryItem", function(self, unit, slot)
            local ok, n = pcall(GetInventoryItemCount, unit, slot)
            self.ulRemedyStack = ok and PlainNumber(n) or nil
        end)
    end

    local function Safe(tooltip, itemID)
        local ok, err = pcall(AddLines, tooltip, itemID)
        if not ok then Report(err) end
    end
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
       and Enum.TooltipDataType and Enum.TooltipDataType.Item then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
            if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
            Safe(tooltip, (data and data.id) or ItemIDFromTooltip(tooltip))
        end)
    else
        for _, tt in ipairs(tooltips) do
            if tt and tt.HookScript then
                tt:HookScript("OnTooltipSetItem", function(tooltip)
                    Safe(tooltip, ItemIDFromTooltip(tooltip))
                end)
            end
        end
    end
end

------------------------------------------------------------------------
-- Commands and events
------------------------------------------------------------------------

function UlRemedy.AuctionDebug()
    if not market then InitRealm() end
    local items = 0
    if market then for _ in pairs(market.items) do items = items + 1 end end
    print(UlRemedy.name .. ": auction prices for " .. RealmKey() .. ": " .. items .. " items known.")
    if market and market.scanned then
        print("  last full scan " .. AgeText(market.scanned.at) .. ": " .. market.scanned.auctions
            .. " auctions, " .. market.scanned.items .. " item prices.")
    else
        print("  no full scan yet. Press Scan prices in the auction house.")
    end
    print("  this session: browse " .. stats.browse .. ", commodity " .. stats.commodity
        .. ", item " .. stats.item .. ", replicate " .. stats.replicate .. ", classic " .. stats.classic)
    local api = {}
    api[#api + 1] = "C_AuctionHouse " .. (C_AuctionHouse and "yes" or "no")
    api[#api + 1] = "ReplicateItems " .. ((C_AuctionHouse and C_AuctionHouse.ReplicateItems) and "yes" or "no")
    api[#api + 1] = "GetBrowseResults " .. ((C_AuctionHouse and C_AuctionHouse.GetBrowseResults) and "yes" or "no")
    api[#api + 1] = "GetAuctionItemInfo " .. (GetAuctionItemInfo and "yes" or "no")
    api[#api + 1] = "SetTooltipMoney " .. (type(SetTooltipMoney) == "function" and "yes" or "no")
    api[#api + 1] = "GetPrimaryTooltipInfo " .. (GameTooltip.GetPrimaryTooltipInfo and "yes" or "no")
    print("  client: " .. table.concat(api, ", "))
    if scanJob then
        print("  reading a full list: " .. (scanJob.index - 1) .. " of " .. scanJob.n .. " auctions so far.")
    end
    local shown = scanButton and (scanButton:IsShown() and "shown" or "hidden") or "none"
    print("  scan button: " .. buttonNote .. ", " .. shown
        .. ", auction frame " .. ((AuctionHouseFrame or AuctionFrame) and "exists" or "missing"))
    if lastError then print("  last error: " .. lastError) end
end

function UlRemedy.ResetAuctionPrices()
    if not DB then return end
    DB.realms[RealmKey()] = nil
    market = nil
    InitRealm()
    print(UlRemedy.name .. ": forgot every auction price for " .. RealmKey() .. ".")
end

function UlRemedy.RefreshAuctionPrices()
    if scanButton then scanButton:SetShown(Enabled()) end
end

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
-- The retail and classic auction events do not all exist on one client,
-- and registering an unknown event is an error, so each is tried alone.
for _, event in ipairs({
    "AUCTION_HOUSE_SHOW",
    "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_RESULTS_ADDED",
    "COMMODITY_SEARCH_RESULTS_UPDATED", "COMMODITY_SEARCH_RESULTS_ADDED",
    "ITEM_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_ADDED",
    "REPLICATE_ITEM_LIST_UPDATE", "AUCTION_ITEM_LIST_UPDATE",
}) do
    pcall(frame.RegisterEvent, frame, event)
end

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == UlRemedy.name then
            InitDB()
        elseif arg1 == "Blizzard_AuctionHouseUI" or arg1 == "Blizzard_AuctionUI" then
            if Enabled() then EnsureScanButton() end
        end
        return
    elseif event == "PLAYER_LOGIN" then
        InitRealm()
        HookTooltips()
        self:UnregisterEvent("PLAYER_LOGIN")
        return
    end
    if not Enabled() then return end
    local ok, err = pcall(function()
        if event == "AUCTION_HOUSE_SHOW" then
            EnsureScanButton()
        elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" or event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
            ReadBrowseResults()
        elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" or event == "COMMODITY_SEARCH_RESULTS_ADDED" then
            ReadCommodityResults(arg1)
        elseif event == "ITEM_SEARCH_RESULTS_UPDATED" or event == "ITEM_SEARCH_RESULTS_ADDED" then
            ReadItemResults(arg1)
        elseif event == "REPLICATE_ITEM_LIST_UPDATE" then
            if scanPending and C_AuctionHouse and C_AuctionHouse.GetNumReplicateItems then
                scanPending = false
                ReadFullList(C_AuctionHouse.GetNumReplicateItems, C_AuctionHouse.GetReplicateItemInfo, "replicate")
            end
        elseif event == "AUCTION_ITEM_LIST_UPDATE" then
            if scanPending and GetNumAuctionItems and GetAuctionItemInfo then
                scanPending = false
                ReadFullList(function() return GetNumAuctionItems("list") end,
                    function(i) return GetAuctionItemInfo("list", i) end, "classic")
            end
        end
    end)
    if not ok then Report(err) end
end)
