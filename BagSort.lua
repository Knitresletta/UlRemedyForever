-- Bag Sort Button: brings Blizzard's own sort button back into view on
-- the combined bag.
--
-- The retail bag code (which Forever runs) keeps one sort button,
-- BagItemAutoSortButton, and hangs it on whichever frame is the backpack
-- or the combined bag, top-right at (-9, -34). Its click plays a sound
-- and calls C_Container.SortBags(). Forever kept all of that, but its
-- combined bag has a new element in that corner, CountContainer (the bag
-- icon with the slot count, 100 wide), drawn on top of the button. So the
-- button is there, enabled and invisible. Probed 14.10.2026: shown, parent
-- ContainerFrameCombinedBags, point TOPRIGHT -9 -34; search box at
-- TOPLEFT 62 -37, 330 wide. Separate bags are fine, their backpack has no
-- count element.
--
-- Fix: once Blizzard has placed the button, move it to the right end of
-- the search box and shorten the search box by the button's width so the
-- two do not overlap, and lift the button's frame level above the count
-- element so it takes the click. Blizzard places both again every time
-- the frame's UpdateSearchBox runs (each show and bag change), so that
-- method is post-hooked and the move redone. When the combined bag hides,
-- Blizzard's own anchor is put back: the backpack's placement code sets
-- the TOPRIGHT point without clearing the others, so an anchor of ours
-- left behind would stretch the button between two frames the next time
-- the bags are opened separately. The click handler, the sound and the
-- sorting itself stay Blizzard's.

local GAP = 4            -- between the search box and the button
local BUTTON_W = 28      -- the button's width in Blizzard's XML
local BLIZZ_POINT = { "TOPRIGHT", -9, -34 }   -- where Blizzard puts it

local hooked = false
local blizzWidth         -- the search box width Blizzard last set
local lastError

local function Enabled()
    return UlRemedy.enabled and UlRemedy.enabled.bagsort
end

local function Frames()
    local combined = ContainerFrameCombinedBags
    local button = BagItemAutoSortButton
    local search = BagItemSearchBox
    if not (combined and button and search) then return nil end
    return combined, button, search
end

-- Blizzard's placement, for when the feature is off or the frame hides.
local function Restore()
    local combined, button, search = Frames()
    if not combined then return end
    if button:GetParent() == combined then
        button:ClearAllPoints()
        button:SetPoint(BLIZZ_POINT[1], combined, BLIZZ_POINT[1], BLIZZ_POINT[2], BLIZZ_POINT[3])
    end
    if blizzWidth and search:GetParent() == combined then
        search:SetWidth(blizzWidth)
    end
end

local function PlaceUnsafe()
    local combined, button, search = Frames()
    if not combined or not combined:IsShown() then return end
    -- Only when Blizzard has given the button to the combined bag; the
    -- backpack's own placement is left alone.
    if button:GetParent() ~= combined or search:GetParent() ~= combined then return end

    if not blizzWidth then blizzWidth = search:GetWidth() end
    search:SetWidth(blizzWidth - BUTTON_W - GAP)
    button:ClearAllPoints()
    button:SetPoint("LEFT", search, "RIGHT", GAP, 0)

    local count = combined.CountContainer
    if type(count) == "table" and type(count.GetFrameLevel) == "function" then
        local above = count:GetFrameLevel() + 1
        if button:GetFrameLevel() < above then button:SetFrameLevel(above) end
    end
    button:Show()
end

local function Place()
    if not Enabled() then return end
    local ok, err = pcall(PlaceUnsafe)
    if not ok and err ~= lastError then
        lastError = err
        print(UlRemedy.name .. ": bag sort button could not be placed: " .. tostring(err))
    end
end

-- Runs right after Blizzard's own placement, so the width it just set is
-- the one to shorten.
local function AfterBlizzardPlacement()
    local _, _, search = Frames()
    if search and search:GetParent() == ContainerFrameCombinedBags then
        blizzWidth = search:GetWidth()
    end
    Place()
end

local function Hook()
    if hooked then return end
    local combined = Frames()
    if not combined then return end
    hooked = true
    if type(combined.UpdateSearchBox) == "function" then
        hooksecurefunc(combined, "UpdateSearchBox", AfterBlizzardPlacement)
    end
    combined:HookScript("OnShow", Place)
    combined:HookScript("OnHide", Restore)
end

function UlRemedy.RefreshBagSort()
    Hook()
    if Enabled() then Place() else Restore() end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self)
    UlRemedy.RefreshBagSort()
    self:UnregisterEvent("PLAYER_LOGIN")
end)
