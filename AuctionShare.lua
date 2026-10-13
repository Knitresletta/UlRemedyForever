-- Auction Share: swaps auction prices with other UlRemedyForever users on
-- the same realm, so a price one of them saw at the auction house shows up
-- in everyone's tooltips.
--
-- WHAT LEAVES YOUR MACHINE. Addons cannot use the network; the only way
-- two addons can talk is addon messages over the game's chat system. This
-- module joins a chat channel named UlRemedyAH (hidden from your chat
-- windows) and sends, as addon messages nobody sees as text:
--   * item ID, lowest buyout per unit and the age of that price, for the
--     prices this character saw itself at the auction house in the last
--     24 hours;
--   * a short hello when it joins, naming how fresh its newest price is.
-- The chat system attaches your character name to every message, as it
-- does to any chat. Nothing else is sent: no gold, no bags, no bank, no
-- other characters, and no prices heard from others (those are never
-- relayed, so nothing echoes around the channel). Turn it off with
-- /ur auctionshare; the channel is left at once.
--
-- Protocol (one letter kind, one letter faction, then the body):
--   H<newest>              hello, on joining. newest = unix time of the
--                          sender's newest own price, base 36.
--   O<newest>;<count>      offer, whispered back by anyone whose newest
--                          own price is at least ten minutes newer.
--   R                      request, whispered to the best offer.
--   D<id>:<price>:<age>,.. prices, base 36, age in minutes. Broadcast to
--                          the channel after a full scan, whispered on
--                          request.
--   E                      end of a whispered dump.
-- Messages are at most 250 characters and go out four per second, which is
-- well under the client's own throttle; a throttled message is retried.
-- After a full scan the result is broadcast unless someone else's
-- broadcast came in within the last ten minutes, so a busy channel does
-- not fill with the same list from everyone.
--
-- Incoming prices are stored by AuctionPrices.lua (newer wins, a price
-- you saw yourself in the last ten minutes is kept over a shared one) and
-- marked "shared" in the tooltip. Everything received is parsed strictly
-- and bounded; garbage is dropped.

local CHANNEL = "UlRemedyAH"
local PREFIX = "UlRemAH"
local SEND_INTERVAL = 0.25       -- seconds between messages
local MAX_LEN = 250
local FRESH_SECONDS = 24 * 3600  -- older own prices are not sent
local QUIET_AFTER_PEER = 600     -- skip own broadcast this soon after a peer's
local OFFER_WINDOW = 6           -- seconds to collect offers after hello
local OFFER_MARGIN = 600         -- offer only when this much newer
local MAX_PRICE = 1e9            -- copper; anything above is garbage
local MAX_ITEM = 1e6
local MAX_AGE_MIN = 7 * 24 * 60

local frame = CreateFrame("Frame", "UlRemedyAuctionShareFrame")
local queue = {}                 -- { kind, target, text, tries }
local sending = false
local joined = false
local joinTries = 0
local lastError
local stats = { sent = 0, received = 0, merged = 0, dropped = 0, lastPeerBroadcast = nil, skippedBroadcasts = 0 }
local peers = {}                 -- sender -> GetTime() last heard
local hello = { at = nil, bestFrom = nil, bestNewest = 0, requested = nil }

local function Enabled()
    return UlRemedy.enabled and UlRemedy.enabled.auction and UlRemedy.enabled.auctionshare
end

local function Report(err)
    err = tostring(err)
    if err == lastError then return end
    lastError = err
    print(UlRemedy.name .. ": price sharing error: " .. err)
end

local function FactionLetter()
    local f = UnitFactionGroup("player")
    if f == "Alliance" then return "A" elseif f == "Horde" then return "H" end
    return "N"
end

local function MyName()
    return UnitName("player")
end

local function SenderName(sender)
    return (sender or ""):match("^([^%-]+)") or sender
end

------------------------------------------------------------------------
-- Base 36 numbers, to keep messages short
------------------------------------------------------------------------

local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"

local function Enc(n)
    n = math.floor(n)
    if n <= 0 then return "0" end
    local t = {}
    while n > 0 do
        local d = n % 36
        t[#t + 1] = DIGITS:sub(d + 1, d + 1)
        n = math.floor(n / 36)
    end
    return string.reverse(table.concat(t))
end

local function Dec(s)
    if not s or s == "" or #s > 12 or s:find("[^0-9a-z]") then return nil end
    return tonumber(s, 36)
end

------------------------------------------------------------------------
-- The channel
------------------------------------------------------------------------

local function ChannelID()
    local id = GetChannelName(CHANNEL)
    if id and id > 0 then return id end
end

-- Keep the channel out of every chat window.
local function HideChannel()
    if not ChatFrame_RemoveChannel then return end
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local cf = _G["ChatFrame" .. i]
        if cf then pcall(ChatFrame_RemoveChannel, cf, CHANNEL) end
    end
end

local SendHello

local function Join()
    if not Enabled() then return end
    if ChannelID() then
        if not joined then
            joined = true
            HideChannel()
            C_Timer.After(3, SendHello)
        end
        return
    end
    joinTries = joinTries + 1
    if joinTries > 12 then return end
    pcall(JoinChannelByName, CHANNEL)
    C_Timer.After(5, Join)
end

local function Leave()
    joined = false
    queue = {}
    if ChannelID() then pcall(LeaveChannelByName, CHANNEL) end
end

-- Swallow the "Joined Channel" and "Left Channel" notices for our channel.
if ChatFrame_AddMessageEventFilter then
    ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL_NOTICE", function(_, _, _, _, _, channelString, _, _, _, _, baseName)
        if baseName == CHANNEL then return true end
        if type(channelString) == "string" and channelString:find(CHANNEL, 1, true) then return true end
        return false
    end)
end

------------------------------------------------------------------------
-- Sending, paced
------------------------------------------------------------------------

local SendNext

local function Enqueue(kind, target, text)
    queue[#queue + 1] = { kind = kind, target = target, text = text, tries = 0 }
    if not sending then
        sending = true
        C_Timer.After(SEND_INTERVAL, SendNext)
    end
end

local function ResultOK(result)
    if result == nil or result == true then return true end
    local E = Enum and Enum.SendAddonMessageResult
    return E and result == E.Success
end

SendNext = function()
    if not Enabled() then
        queue = {}
        sending = false
        return
    end
    local msg = table.remove(queue, 1)
    if not msg then
        sending = false
        return
    end
    local target = msg.target
    if msg.kind == "CHANNEL" then
        target = ChannelID()
        if not target then
            -- Channel gone; drop channel traffic and try to rejoin.
            joined = false
            joinTries = 0
            Join()
            C_Timer.After(SEND_INTERVAL, SendNext)
            return
        end
    end
    local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg.text, msg.kind, target)
    if ok and ResultOK(result) then
        stats.sent = stats.sent + 1
        C_Timer.After(SEND_INTERVAL, SendNext)
    else
        if not ok then Report(result) end
        msg.tries = msg.tries + 1
        if msg.tries < 4 then table.insert(queue, 1, msg) else stats.dropped = stats.dropped + 1 end
        C_Timer.After(2, SendNext)
    end
end

-- Own prices (never relayed ones) newer than FRESH_SECONDS, as D messages.
-- items: itemID -> { p, at } ; when at is nil the price is from now.
local function QueuePrices(kind, target, items)
    local now = time()
    local parts, len, n = {}, 0, 0
    local function flush()
        if #parts == 0 then return end
        Enqueue(kind, target, "D" .. FactionLetter() .. table.concat(parts, ","))
        parts, len = {}, 0
    end
    for itemID, rec in pairs(items) do
        local at = rec.at or now
        if rec.p and not rec.s and now - at <= FRESH_SECONDS then
            local ageMin = math.max(0, math.floor((now - at) / 60))
            local entry = Enc(itemID) .. ":" .. Enc(rec.p) .. ":" .. Enc(ageMin)
            if len + #entry + 1 > MAX_LEN - 2 then flush() end
            parts[#parts + 1] = entry
            len = len + #entry + 1
            n = n + 1
        end
    end
    flush()
    return n
end

local function NewestOwn()
    local market = UlRemedy.AuctionMarket and UlRemedy.AuctionMarket()
    local newest = 0
    if market then
        for _, rec in pairs(market.items) do
            if not rec.s and rec.at and rec.at > newest then newest = rec.at end
        end
    end
    return newest
end

local function CountOwnFresh()
    local market = UlRemedy.AuctionMarket and UlRemedy.AuctionMarket()
    local n, now = 0, time()
    if market then
        for _, rec in pairs(market.items) do
            if not rec.s and rec.at and now - rec.at <= FRESH_SECONDS then n = n + 1 end
        end
    end
    return n
end

------------------------------------------------------------------------
-- Hello, offer, request
------------------------------------------------------------------------

local function ResolveOffers()
    if not hello.at then return end
    local from = hello.bestFrom
    hello.at = nil
    if not from then return end
    hello.requested = from
    Enqueue("WHISPER", from, "R" .. FactionLetter())
end

SendHello = function()
    if not Enabled() or not ChannelID() then return end
    hello.at = GetTime()
    hello.bestFrom, hello.bestNewest = nil, 0
    Enqueue("CHANNEL", nil, "H" .. FactionLetter() .. Enc(NewestOwn()))
    C_Timer.After(OFFER_WINDOW, ResolveOffers)
end

local function OnHello(sender, body)
    local theirs = Dec(body) or 0
    local mine = NewestOwn()
    if mine - theirs >= OFFER_MARGIN then
        Enqueue("WHISPER", sender, "O" .. FactionLetter() .. Enc(mine) .. ";" .. Enc(CountOwnFresh()))
    end
end

local function OnOffer(sender, body)
    if not hello.at then return end
    local newest = Dec(body:match("^([^;]*)")) or 0
    if newest > hello.bestNewest then
        hello.bestNewest = newest
        hello.bestFrom = sender
    end
end

local function OnRequest(sender)
    local market = UlRemedy.AuctionMarket and UlRemedy.AuctionMarket()
    if not market then return end
    QueuePrices("WHISPER", sender, market.items)
    Enqueue("WHISPER", sender, "E" .. FactionLetter())
end

local function OnPrices(sender, body, channelKind)
    if not UlRemedy.AuctionMergeShared then return end
    local now = time()
    local merged = 0
    for entry in body:gmatch("[^,]+") do
        local a, b, c = entry:match("^([0-9a-z]+):([0-9a-z]+):([0-9a-z]+)$")
        local itemID, price, ageMin = Dec(a), Dec(b), Dec(c)
        if itemID and price and ageMin
           and itemID > 0 and itemID < MAX_ITEM
           and price > 0 and price < MAX_PRICE
           and ageMin <= MAX_AGE_MIN then
            if UlRemedy.AuctionMergeShared(itemID, price, now - ageMin * 60) then
                merged = merged + 1
            end
        else
            stats.dropped = stats.dropped + 1
        end
    end
    stats.merged = stats.merged + merged
    if channelKind == "CHANNEL" then stats.lastPeerBroadcast = GetTime() end
end

local function OnAddonMessage(prefix, text, channelKind, sender)
    if prefix ~= PREFIX or not Enabled() then return end
    if SenderName(sender) == MyName() then return end
    if type(text) ~= "string" or #text < 2 then return end
    local kind, faction, body = text:sub(1, 1), text:sub(2, 2), text:sub(3)
    if faction ~= FactionLetter() then return end
    stats.received = stats.received + 1
    peers[sender] = GetTime()
    if kind == "H" then
        OnHello(sender, body)
    elseif kind == "O" and channelKind == "WHISPER" then
        OnOffer(sender, body)
    elseif kind == "R" and channelKind == "WHISPER" then
        OnRequest(sender)
    elseif kind == "D" then
        OnPrices(sender, body, channelKind)
    end
    -- "E" needs no action.
end

------------------------------------------------------------------------
-- After our own full scan
------------------------------------------------------------------------

-- batch: itemID -> { p, q } from AuctionPrices, all seen just now.
function UlRemedy.OnAuctionScanDone(batch)
    if not Enabled() or not joined then return end
    if stats.lastPeerBroadcast and GetTime() - stats.lastPeerBroadcast < QUIET_AFTER_PEER then
        stats.skippedBroadcasts = stats.skippedBroadcasts + 1
        return
    end
    QueuePrices("CHANNEL", nil, batch)
end

------------------------------------------------------------------------
-- Commands and events
------------------------------------------------------------------------

function UlRemedy.AuctionShareDebug()
    local id = ChannelID()
    print(UlRemedy.name .. ": price sharing " .. (Enabled() and "on" or "off")
        .. ", channel " .. CHANNEL .. (id and (" joined as /" .. id) or " not joined")
        .. " (" .. joinTries .. " join attempts).")
    local n, now = 0, GetTime()
    for _, at in pairs(peers) do if now - at < 3600 then n = n + 1 end end
    print("  this session: sent " .. stats.sent .. ", received " .. stats.received
        .. ", prices merged " .. stats.merged .. ", dropped " .. stats.dropped
        .. ", peers heard in the last hour " .. n .. ", queued " .. #queue .. ".")
    if stats.lastPeerBroadcast then
        print("  last broadcast from a peer " .. math.floor((now - stats.lastPeerBroadcast) / 60) .. " min ago; own broadcasts skipped " .. stats.skippedBroadcasts .. ".")
    end
    if hello.requested then print("  requested a dump from " .. hello.requested .. ".") end
    if lastError then print("  last error: " .. lastError) end
end

function UlRemedy.RefreshAuctionShare()
    if Enabled() then
        if not joined then
            joinTries = 0
            Join()
        end
    elseif joined or ChannelID() then
        Leave()
    end
end

frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
            pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
        end
        self:UnregisterEvent("PLAYER_LOGIN")
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Channels are not available right at login; give it a moment.
        if not joined then
            joinTries = 0
            C_Timer.After(8, Join)
        end
    elseif event == "CHAT_MSG_ADDON" then
        local ok, err = pcall(OnAddonMessage, ...)
        if not ok then Report(err) end
    end
end)
