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
        if DEFAULTS[k] == nil then UlRemedyForeverDB[k] = nil end
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
    print("  /ur rollside: cycle where the loot roll window sits (party frames, chat, free)")
    print("  /ur rolltest: show a test loot roll so the window can be placed")
    print("  /ur winreset: forget saved window positions")
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
    if cmd == "rollside" then
        if UlRemedy.CycleLootRollSide then UlRemedy.CycleLootRollSide() end
        return
    end
    if cmd == "rolltest" then
        if UlRemedy.LootRollTest then UlRemedy.LootRollTest() end
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

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == UlRemedy.name then
        InitDB()
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        print(UlRemedy.name .. " " .. UlRemedy.Version() .. " loaded. Type |cffffcc00/ur|r for options.")
        self:UnregisterEvent("PLAYER_LOGIN")
    end
end)
