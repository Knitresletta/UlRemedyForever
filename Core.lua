UlRemedy = { name = "UlRemedyForever", enabled = {} }

local DEFAULTS = {
    repair      = true,
    junk        = true,
    junkdelete  = false,
    groupinvite = true,
    trainer     = true,
    cursor      = true,
    inventory   = true,
    flightpaths = true,
    transports  = true,
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

local FEATURES = {
    { key = "repair",      label = "Auto Repair" },
    { key = "junk",        label = "Junk Seller" },
    { key = "junkdelete",  label = "Junk Deleter (deletes the cheapest junk item when bags are full)" },
    { key = "groupinvite", label = "Group Invite" },
    { key = "trainer",     label = "Enhanced Trainer" },
    { key = "cursor",      label = "Cursor Ring" },
    { key = "inventory",   label = "Inventory Tracker" },
    { key = "flightpaths", label = "Flight Paths on Map" },
    { key = "transports",  label = "Boats, Zeppelins, Tram and Portals on Map" },
}

local function PrintHelp()
    print("|cffffcc00" .. UlRemedy.name .. "|r commands:")
    for _, f in ipairs(FEATURES) do
        local state = UlRemedy.enabled[f.key] and "|cff00ff00on|r" or "|cffff4444off|r"
        print("  /ur " .. f.key .. ": " .. f.label .. " (" .. state .. ")")
    end
    print("  /ur inv: open the inventory browser (all characters, gold and items)")
    print("  /ur fp: print flight path map diagnostics for the current map")
    print("  /ur fpreset: forget this character's known flight paths and sync again")
    print("  /ur jd: print junk deleter diagnostics")
end

local function Toggle(key, label)
    UlRemedy.enabled[key] = not UlRemedy.enabled[key]
    local state = UlRemedy.enabled[key] and "|cff00ff00enabled|r" or "|cffff4444disabled|r"
    print(UlRemedy.name .. ": " .. label .. " " .. state .. ".")
    if UlRemedy.UpdateCursorRing then UlRemedy.UpdateCursorRing() end
    if UlRemedy.RescanInventory then UlRemedy.RescanInventory() end
    if UlRemedy.RefreshFlightPaths then UlRemedy.RefreshFlightPaths() end
    if UlRemedy.RefreshTransports then UlRemedy.RefreshTransports() end
    if UlRemedy.CheckJunkDeleter then UlRemedy.CheckJunkDeleter() end
end

SLASH_ULREMEDY1 = "/ur"
SLASH_ULREMEDY2 = "/ulremedy"
SlashCmdList["ULREMEDY"] = function(msg)
    local cmd = strtrim(msg):lower()
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
    local matched = false
    for _, f in ipairs(FEATURES) do
        if cmd == f.key then
            Toggle(f.key, f.label)
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
        print(UlRemedy.name .. " loaded. Type |cffffcc00/ur|r to see commands.")
        self:UnregisterEvent("PLAYER_LOGIN")
    end
end)
