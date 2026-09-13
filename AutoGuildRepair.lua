-- Auto Repair: repairs at any vendor, guild funds first when they actually
-- cover the bill, personal gold as fallback. Success is only reported after
-- the server confirms the repair (durability update), never guessed from an
-- immediate money read. GetMoney() doesn't reflect the cost until the
-- server round-trip completes.

local frame = CreateFrame("Frame", "UlRemedyRepairFrame")
local pending -- repair sent to the server, awaiting confirmation

-- GetGuildBankWithdrawMoney() is only the player's remaining daily
-- allowance: it stays positive even when the guild bank is empty, so the
-- actual bank balance must cap it. GetGuildBankMoney() can read 0 until the
-- client has seen guild bank data this session; the failure direction is
-- safe (falls back to personal gold instead of a repair that silently fails).
local function GuildFundsAvailable()
    if not CanGuildBankRepair or not CanGuildBankRepair() then
        return 0
    end
    if not GetGuildBankWithdrawMoney or not GetGuildBankMoney then
        return 0
    end
    local allowance = GetGuildBankWithdrawMoney()
    local bankMoney = GetGuildBankMoney() or 0
    if allowance == -1 then
        return bankMoney
    end
    return math.min(allowance, bankMoney)
end

local function StopWaiting()
    pending = nil
    frame:UnregisterEvent("UPDATE_INVENTORY_DURABILITY")
    frame:UnregisterEvent("MERCHANT_CLOSED")
end

local function Repair()
    if not UlRemedy.enabled.repair then return end
    if not CanMerchantRepair() then return end
    local cost, canRepair = GetRepairAllCost()
    if not canRepair or not cost or cost <= 0 then return end

    local useGuild = GuildFundsAvailable() >= cost

    if not useGuild and GetMoney() < cost then
        print(UlRemedy.name .. ": Not enough money to repair. Need " .. UlRemedy.MoneyText(cost) .. ".")
        return
    end

    RepairAllItems(useGuild)

    pending = { cost = cost, useGuild = useGuild }
    frame:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
    frame:RegisterEvent("MERCHANT_CLOSED")
end

local function OnConfirmed()
    local remaining = GetRepairAllCost()
    if remaining and remaining > 0 then return end -- durability changed for another reason

    if pending.useGuild then
        print(UlRemedy.name .. ": Repaired with guild funds for " .. UlRemedy.MoneyText(pending.cost) .. ".")
    else
        print(UlRemedy.name .. ": Repaired with personal gold for " .. UlRemedy.MoneyText(pending.cost) .. ".")
    end
    StopWaiting()
end

local function OnMerchantClosed()
    -- No durability update before the window closed: the repair never
    -- happened (typically a guild repair the bank couldn't cover).
    if pending.useGuild then
        print(UlRemedy.name .. ": Repair did not go through: guild funds could not cover it.")
    else
        print(UlRemedy.name .. ": Repair did not go through.")
    end
    StopWaiting()
end

frame:RegisterEvent("MERCHANT_SHOW")
frame:SetScript("OnEvent", function(_, event)
    if event == "MERCHANT_SHOW" then
        Repair()
    elseif not pending then
        return
    elseif event == "UPDATE_INVENTORY_DURABILITY" then
        OnConfirmed()
    elseif event == "MERCHANT_CLOSED" then
        OnMerchantClosed()
    end
end)
