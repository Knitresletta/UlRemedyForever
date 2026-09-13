local function ShortName(name)
    return (name or ""):match("^([^%-]+)") or name
end

local function IsFriend(name)
    local short = ShortName(name)
    for i = 1, C_FriendList.GetNumFriends() do
        local info = C_FriendList.GetFriendInfoByIndex(i)
        if info and ShortName(info.name) == short then
            return true
        end
    end
    return false
end

local function IsBattleNetFriend(name)
    if not (C_BattleNet and BNGetNumFriends) then return false end
    local short = ShortName(name)
    local numFriends = BNGetNumFriends()
    for i = 1, numFriends do
        local numAccounts = C_BattleNet.GetFriendNumGameAccounts(i) or 0
        for j = 1, numAccounts do
            local ga = C_BattleNet.GetFriendGameAccountInfo(i, j)
            if ga and ga.clientProgram == BNET_CLIENT_WOW
                and ga.characterName and ShortName(ga.characterName) == short then
                return true
            end
        end
    end
    return false
end

local function IsGuildmate(name)
    local short = ShortName(name)
    local count = GetNumGuildMembers()
    for i = 1, count do
        local memberName = GetGuildRosterInfo(i)
        if memberName and ShortName(memberName) == short then
            return true
        end
    end
    return false
end

local lastAccept = 0

local frame = CreateFrame("Frame", "UlRemedyGroupInviteFrame")
frame:RegisterEvent("PARTY_INVITE_REQUEST")
frame:RegisterEvent("PLAYER_LOGIN")

frame:SetScript("OnEvent", function(self, event, inviterName)
    if event == "PLAYER_LOGIN" then
        C_GuildInfo.GuildRoster()
        return
    end
    if not UlRemedy.enabled.groupinvite then return end
    -- Keep the guild roster fresh; throttled by the client, harmless if repeated.
    if IsInGuild() then C_GuildInfo.GuildRoster() end
    local now = GetTime()
    if now - lastAccept < 3 then return end
    if IsFriend(inviterName) or IsBattleNetFriend(inviterName) or IsGuildmate(inviterName) then
        lastAccept = now
        AcceptGroup()
        StaticPopup_Hide("PARTY_INVITE")
        print(UlRemedy.name .. ": Auto-accepted invite from " .. ShortName(inviterName) .. ".")
    end
end)
