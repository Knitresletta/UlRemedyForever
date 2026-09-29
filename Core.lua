UlRemedy = { name = "UlRemedyForever", enabled = {} }

local DEFAULTS = {
    repair      = true,
    junk        = true,
    groupinvite = true,
    trainer     = true,
    cursor      = true,
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
    { key = "groupinvite", label = "Group Invite" },
    { key = "trainer",     label = "Enhanced Trainer" },
    { key = "cursor",      label = "Cursor Ring" },
}

local function PrintHelp()
    print("|cffffcc00" .. UlRemedy.name .. "|r commands:")
    for _, f in ipairs(FEATURES) do
        local state = UlRemedy.enabled[f.key] and "|cff00ff00on|r" or "|cffff4444off|r"
        print("  /ur " .. f.key .. ": " .. f.label .. " (" .. state .. ")")
    end
end

local function Toggle(key, label)
    UlRemedy.enabled[key] = not UlRemedy.enabled[key]
    local state = UlRemedy.enabled[key] and "|cff00ff00enabled|r" or "|cffff4444disabled|r"
    print(UlRemedy.name .. ": " .. label .. " " .. state .. ".")
    if UlRemedy.UpdateCursorRing then UlRemedy.UpdateCursorRing() end
end

SLASH_ULREMEDY1 = "/ur"
SLASH_ULREMEDY2 = "/ulremedy"
SlashCmdList["ULREMEDY"] = function(msg)
    local cmd = strtrim(msg):lower()
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
