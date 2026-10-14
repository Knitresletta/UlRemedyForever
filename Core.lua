UlRemedy = { name = "UlRemedyForever", enabled = {} }

local DEFAULTS = {
    repair      = true,
    junk        = true,
    junkdelete  = false,
    vendor      = true,
    vendorbags  = true,
    groupinvite = true,
    trainer     = true,
    cursor      = true,
    windows     = true,
    inventory   = true,
    reagents    = true,
    auction     = true,
    auctionshare = true,
    flightpaths = true,
    transports  = true,
    rolls       = true,
}

local function InitDB()
    if not UlRemedyForeverDB then UlRemedyForeverDB = {} end
    for k, v in pairs(DEFAULTS) do
        if UlRemedyForeverDB[k] == nil then UlRemedyForeverDB[k] = v end
    end
    for k in pairs(UlRemedyForeverDB) do
        if DEFAULTS[k] == nil and k ~= "errors" then UlRemedyForeverDB[k] = nil end
    end
    UlRemedy.enabled = UlRemedyForeverDB
end

function UlRemedy.Version()
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local v = get and get(UlRemedy.name, "Version")
    return v and ("v" .. v) or "(unknown version)"
end

function UlRemedy.MoneyText(amount)
    local coinText = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString
    if coinText then
        return coinText(amount)
    end
    return tostring(amount) .. " copper"
end

-- Forever exposes the item APIs under C_Item rather than as globals. Resolve at
-- call time and keep the global path for clients that still have it. Returns
-- nil when the item is not in the local cache yet, which callers must handle.
function UlRemedy.ItemVendorPrice(itemLink)
    local getItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not getItemInfo then return nil end
    return (select(11, getItemInfo(itemLink)))
end

------------------------------------------------------------------------
-- Lua error log
------------------------------------------------------------------------
-- The client keeps every Lua error and warning of the session in
-- ScriptErrorsFrame.errorData (message, count, time, stack, locals; see
-- Blizzard_ScriptErrorsFrame.lua) and forgets them on reload. Warnings
-- such as "exceeded execution limit" never pass through seterrorhandler,
-- so reading that table is the only way to see everything. It is copied
-- into the saved variables at logout and reload, and on /ur errors, so the
-- log can be read from the saved variables file afterwards. Strings that
-- are secret values are replaced with a marker rather than touched.
local MAX_LOGGED_ERRORS = 40

local function PlainString(v)
    if v == nil then return nil end
    if issecretvalue and issecretvalue(v) then return "<secret>" end
    if type(v) ~= "string" then return tostring(v) end
    return v
end

local function Clip(text, n)
    text = PlainString(text)
    if not text then return nil end
    text = text:gsub("Interface[/\\]AddOns[/\\]", "")
    if #text > n then text = text:sub(1, n) .. "..." end
    return text
end

function UlRemedy.DumpErrors(announce)
    local frameData = ScriptErrorsFrame and ScriptErrorsFrame.errorData
    local list = {}
    if type(frameData) == "table" then
        local n = #frameData
        for i = math.max(1, n - MAX_LOGGED_ERRORS + 1), n do
            local e = frameData[i]
            local ok, rec = pcall(function()
                return {
                    kind = e.messageType == 1 and "warning" or "error",
                    count = tonumber(PlainString(e.count)) or 0,
                    time = PlainString(e.time),
                    message = Clip(e.message, 400),
                    stack = Clip(e.stack, 1200),
                }
            end)
            list[#list + 1] = ok and rec or { kind = "unreadable", message = tostring(rec) }
        end
    end
    UlRemedyForeverDB.errors = {
        at = date("%Y-%m-%d %H:%M:%S"),
        version = UlRemedy.Version(),
        total = type(frameData) == "table" and #frameData or 0,
        -- Tells a missing frame apart from a clean session.
        source = ScriptErrorsFrame and (type(frameData) == "table" and "ScriptErrorsFrame.errorData" or "frame without errorData") or "no ScriptErrorsFrame",
        list = list,
    }
    if announce then
        print(UlRemedy.name .. ": saved " .. #list .. " of " .. UlRemedyForeverDB.errors.total
            .. " Lua errors and warnings from this session (" .. UlRemedyForeverDB.errors.source
            .. ") to the saved variables, written on reload or logout.")
        for i = math.max(1, #list - 4), #list do
            local e = list[i]
            print("  " .. (e.count or 0) .. "x " .. (e.kind or "?") .. ": " .. (e.message or "?"))
        end
    end
end

-- Every toggleable feature. Options.lua draws one checkbox per entry;
-- /ur <key> toggles it from chat. desc is the one-line explanation shown
-- next to the checkbox and in /ur help.
local FEATURES = {
    { key = "repair",      group = "Vendor",    label = "Auto Repair",       desc = "Repairs your gear at vendors, guild funds first when they cover it." },
    { key = "junk",        group = "Vendor",    label = "Junk Seller",       desc = "Sells all grey items when a vendor opens." },
    { key = "junkdelete",  group = "Vendor",    label = "Junk Deleter",      desc = "Deletes the cheapest grey item when your bags are full. Off by default." },
    { key = "vendor",      group = "Vendor",    label = "Vendor Window",     desc = "Bigger merchant window: scrollable grid, search, filters, sorting." },
    { key = "vendorbags",  group = "Vendor",    label = "Vendor Bags",       desc = "Bag panel docked to the vendor; one click sells an item." },
    { key = "groupinvite", group = "Group",     label = "Group Invite",      desc = "Auto-accepts group invites from friends and guildmates." },
    { key = "rolls",       group = "Group",     label = "Loot Rolls",        desc = "Shows who chose Need, Greed or Pass on each loot roll, by the party frames." },
    { key = "trainer",     group = "Interface", label = "Enhanced Trainer",  desc = "Adds a Train All button to trainers." },
    { key = "cursor",      group = "Interface", label = "Cursor Ring",       desc = "A purple ring that follows your mouse cursor." },
    { key = "windows",     group = "Interface", label = "Movable Windows",   desc = "Drag Blizzard windows and bags anywhere, positions remembered. Off needs /reload." },
    { key = "inventory",   group = "Items",     label = "Inventory Tracker", desc = "Remembers gold, bags and bank for all your characters, with a browser." },
    { key = "reagents",    group = "Items",     label = "Reagent Tooltip",   desc = "Shows which professions use an item, learned from your profession windows." },
    { key = "auction",     group = "Items",     label = "Auction Prices",    desc = "Remembers prices seen at the auction house and shows them in tooltips." },
    { key = "auctionshare", group = "Items",    label = "Price Sharing",     desc = "Swaps auction prices with other UlRemedyForever users on your realm over a hidden chat channel." },
    { key = "flightpaths", group = "Map",       label = "Flight Paths",      desc = "Every flight master on the world map, undiscovered ones in red." },
    { key = "transports",  group = "Map",       label = "Transports",        desc = "Boats, zeppelins, the tram and portals on the world map." },
}
UlRemedy.FEATURE_GROUPS = { "Vendor", "Group", "Interface", "Items", "Map" }
UlRemedy.FEATURES = FEATURES

local function PrintHelp()
    print("|cffffcc00" .. UlRemedy.name .. "|r: /ur opens the options window. Chat commands:")
    for _, f in ipairs(FEATURES) do
        local state = UlRemedy.enabled[f.key] and "|cff00ff00on|r" or "|cffff4444off|r"
        print("  /ur " .. f.key .. ": " .. f.label .. " (" .. state .. "): " .. f.desc)
    end
    print("  /ur inv: open the inventory browser (all characters, gold and items)")
    print("  /ur fp: print flight path map diagnostics for the current map")
    print("  /ur fpreset: forget this character's known flight paths and sync again")
    print("  /ur jd: print junk deleter diagnostics")
    print("  /ur vendorreset: reset the vendor window to its default size")
    print("  /ur rs: print what the reagent tooltip has learned from profession windows")
    print("  /ur rsreset: forget what the reagent tooltip learned in play")
    print("  /ur ah: print auction price diagnostics (items known, last scan, what the client offers)")
    print("  /ur ahreset: forget every auction price for this realm and faction")
    print("  /ur ahshare: print price sharing diagnostics (channel, sent, received, peers)")
    print("  /ur rollside: cycle where the loot roll window sits (party frames, chat, free)")
    print("  /ur rolltest: show a test loot roll so the window can be placed")
    print("  /ur winreset: forget saved window positions")
    print("  /ur errors: save this session's Lua errors and warnings to the saved variables, print the last five")
    print("  /ur win: print movable windows diagnostics (hover a window first to see its name)")
end

-- Modules that need a nudge when a feature changes state.
local function NotifyModules()
    if UlRemedy.UpdateCursorRing then UlRemedy.UpdateCursorRing() end
    if UlRemedy.RefreshMovableWindows then UlRemedy.RefreshMovableWindows() end
    if UlRemedy.RescanInventory then UlRemedy.RescanInventory() end
    if UlRemedy.RefreshFlightPaths then UlRemedy.RefreshFlightPaths() end
    if UlRemedy.RefreshTransports then UlRemedy.RefreshTransports() end
    if UlRemedy.CheckJunkDeleter then UlRemedy.CheckJunkDeleter() end
    if UlRemedy.RefreshVendor then UlRemedy.RefreshVendor() end
    if UlRemedy.RefreshLootRolls then UlRemedy.RefreshLootRolls() end
    if UlRemedy.RefreshAuctionPrices then UlRemedy.RefreshAuctionPrices() end
    if UlRemedy.RefreshAuctionShare then UlRemedy.RefreshAuctionShare() end
    if UlRemedy.RefreshOptions then UlRemedy.RefreshOptions() end
end

-- Shared by the chat command and the options window.
function UlRemedy.SetFeature(key, enabled)
    local feature
    for _, f in ipairs(FEATURES) do
        if f.key == key then feature = f end
    end
    if not feature then return end
    UlRemedy.enabled[key] = enabled and true or false
    local state = UlRemedy.enabled[key] and "|cff00ff00enabled|r" or "|cffff4444disabled|r"
    print(UlRemedy.name .. ": " .. feature.label .. " " .. state .. ".")
    NotifyModules()
end

local function Toggle(key)
    UlRemedy.SetFeature(key, not UlRemedy.enabled[key])
end

SLASH_ULREMEDY1 = "/ur"
SLASH_ULREMEDY2 = "/ulremedy"
SlashCmdList["ULREMEDY"] = function(msg)
    local cmd = strtrim(msg):lower()
    if cmd == "" then
        if UlRemedy.ToggleOptions then UlRemedy.ToggleOptions() else PrintHelp() end
        return
    end
    if cmd == "help" then
        PrintHelp()
        return
    end
    if cmd == "inv" or cmd == "bags" then
        if UlRemedy.ToggleInventoryWindow then UlRemedy.ToggleInventoryWindow() end
        return
    end
    if cmd == "fp" then
        if UlRemedy.FlightPathDebug then UlRemedy.FlightPathDebug() end
        return
    end
    if cmd == "fpreset" then
        if UlRemedy.ResetFlightPaths then UlRemedy.ResetFlightPaths() end
        return
    end
    if cmd == "jd" then
        if UlRemedy.JunkDeleterDebug then UlRemedy.JunkDeleterDebug() end
        return
    end
    if cmd == "vendorreset" then
        if UlRemedy.ResetVendorWindow then UlRemedy.ResetVendorWindow() end
        return
    end
    if cmd == "rs" then
        if UlRemedy.ReagentDebug then UlRemedy.ReagentDebug() end
        return
    end
    if cmd == "rsreset" then
        if UlRemedy.ResetReagentData then UlRemedy.ResetReagentData() end
        return
    end
    if cmd == "ah" then
        if UlRemedy.AuctionDebug then UlRemedy.AuctionDebug() end
        return
    end
    if cmd == "ahshare" then
        if UlRemedy.AuctionShareDebug then UlRemedy.AuctionShareDebug() end
        return
    end
    if cmd == "ahreset" then
        if UlRemedy.ResetAuctionPrices then UlRemedy.ResetAuctionPrices() end
        return
    end
    if cmd == "rollside" then
        if UlRemedy.CycleLootRollSide then UlRemedy.CycleLootRollSide() end
        return
    end
    if cmd == "rolltest" then
        if UlRemedy.LootRollTest then UlRemedy.LootRollTest() end
        return
    end
    if cmd == "errors" then
        local ok, err = pcall(UlRemedy.DumpErrors, true)
        if not ok then print(UlRemedy.name .. ": could not read the error list: " .. tostring(err)) end
        return
    end
    if cmd == "win" then
        if UlRemedy.MovableWindowsDebug then UlRemedy.MovableWindowsDebug() end
        return
    end
    if cmd == "winreset" then
        if UlRemedy.ResetWindowPositions then UlRemedy.ResetWindowPositions() end
        return
    end
    local matched = false
    for _, f in ipairs(FEATURES) do
        if cmd == f.key then
            Toggle(f.key)
            matched = true
            break
        end
    end
    if not matched then PrintHelp() end
end

local frame = CreateFrame("Frame", "UlRemedyCoreFrame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == UlRemedy.name then
        InitDB()
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGOUT" then
        -- Also fires on /reload: the error list is about to be lost.
        pcall(UlRemedy.DumpErrors, false)
    elseif event == "PLAYER_LOGIN" then
        print(UlRemedy.name .. " " .. UlRemedy.Version() .. " loaded. Type |cffffcc00/ur|r for options.")
        self:UnregisterEvent("PLAYER_LOGIN")
    end
end)
