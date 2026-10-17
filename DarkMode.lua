-- Dark Mode: Blizzard's frame borders turned dark grey, everything else
-- left alone.
--
-- The interface is drawn from textures. The ones that are frame, the
-- bronze borders, corners and edges around windows, bars, bags, unit
-- frames and the minimap, are desaturated and darkened with a vertex
-- colour; nothing is replaced. Only textures recognised as frame are
-- touched: the eight edge and corner pieces of a nine-slice (never its
-- Center), textures whose key, name or atlas says border, frame, edge
-- or corner, and the slot border of icon buttons (their NormalTexture).
-- Backgrounds, pages, parchment, fills, icons, portraits, text and
-- whole widget types that render their own content (models, cooldowns)
-- are not. That is a deliberate narrowing from "everything but icons":
-- a dark frame around light content reads well, dark pages do not.
-- This module walks a fixed list of frames (TARGETS) and every UI panel
-- Blizzard opens, and decides texture by texture.
--
-- The original colour and desaturation of every texture touched are
-- remembered (weakly, so a texture that goes away is forgotten) and put
-- back when the feature is turned off. Frames are shaded at login, when a load-on-demand
-- Blizzard addon brings a frame on the list, and on their OnShow, since
-- some of Blizzard's code recolours its art when a window opens
-- (tooltip styles, for one). Nothing protected is called: SetVertexColor
-- on a texture is free, and the OnShow hooks are post-hooks.
--
-- The frame names are those of the retail interface this client runs;
-- the ones missing on it are reported by /ur darkprobe, which also lists
-- what was shaded and what was skipped in any one frame, so the list can
-- be corrected from what the client really has. /ur shade <0.2-1> sets
-- how dark.

local DEFAULT_SHADE = 0.35
local MIN_SHADE, MAX_SHADE = 0.2, 1
local MAX_DEPTH = 10

-- Frames whose own regions are shaded but whose children are not walked.
-- (The Minimap widget is walked like any frame: the map it renders is
-- neither a region nor a child, and its border sits in a child frame.)
local REGIONS_ONLY = { ScrollingMessageFrame = true }
-- Frames left alone by name wherever they turn up: content drawn as art.
local SKIP_FRAMES = {}
-- Children skipped under a given target, by parent key: the map itself
-- is textures too.
local SKIP_CHILDREN = {
    WorldMapFrame = { ScrollContainer = true },
}
-- Words in a texture's key or name, or its parent's, that mark content,
-- not frame.
local CONTENT_WORDS = { "icon", "portrait", "gold", "silver", "copper", "coin", "money" }
-- The nine-slice pieces that are frame (Center is background).
local NINE_PIECES = {
    TopLeftCorner = true, TopRightCorner = true, BottomLeftCorner = true, BottomRightCorner = true,
    TopEdge = true, BottomEdge = true, LeftEdge = true, RightEdge = true,
}
-- Words in a key, name, atlas or texture path that say frame.
local FRAME_WORDS = { "border", "frame", "edge", "corner", "nineslice", "divider" }
-- Words that say background, even when a frame word is there too.
local NOT_FRAME_WORDS = { "center", "background", "backdrop", "parchment", "paper", "fill", "bg" }
-- Atlases that are frame no matter what their key says: the title
-- plates in the character stats pane are keyed Background, and the
-- minimap's buttons and header strip are bronze art keyed as states.
local FRAME_ATLAS_WORDS = { "ui-character-info-title", "ui-hud-minimap-", "actionbar-frame-divider", "actionbar-gryphon",
    "micromenu-buttonbg", -- the ring around each micro menu button is its own texture, keyed Background
    "cooldownmanager-bar-bg", -- the personal resource bars' background has their light edge baked in
    "redbutton-", "128-redbutton" , -- red buttons (close X, Abandon, Share...): symbol and gold frame are one picture
    "common-sidetab", "ui-character-info-stattab", -- the character window's side tabs and stat tabs
    "common-coinbox", -- the box around the money line in bags
    "minimal-scrollbar", "scrollbar-", -- scroll bars: track, thumb and arrows
    "ui-character-info-line", "ui-character-info-scrollline", -- the lines the stats sit on
    "ui-character-info-gearslot", -- the frame around each equipment slot
    "ui-damagemeters-header-bar", "damagemeters-scalehandle", "ui-damagemeters-bar-shadowedge", -- the damage meter's chrome
    "ui-questtrackerbutton-", -- the tracker's buttons (collapse, filter): symbol and frame in one
    "ui-questtracker-primary-objective-header", "ui-questtracker-secondary-objective-header", -- the gold header lines
    "uiframe-tab", "uiframe-activetab", -- window tabs, all three pieces (the middle is keyed center but is frame)
    "spellbook-tab-frame", -- the frame around each spellbook category icon
    "talents-main-ring", -- the ring around each talent spec icon, and the points box under it
    "ui-lfg-roleicon-tank-background", "ui-lfg-roleicon-healer-background", -- the rings behind the role icons
    "ui-lfg-roleicon-dps-background", "ui-lfg-roleicon-leader-background",
    "groupfinder-button-cover", -- the frame over each group finder category button
    "common-button-list-collapseexpand", -- the header bar of a collapsible list (group finder's Players)
    "common-search-border", "common-dropdown", "common-input", -- the same chrome family elsewhere
    "ui-frame-", "ui-hud-actionbar-iconframe" } -- generic frame pieces and action slot frames
-- Textures known only by file ID that are frame: the action bar's
-- gryphon end caps on this client.
local FRAME_FILE_IDS = { [237700] = true, [237699] = true,
    [337499] = true, -- the brown cover over the group finder's role rings
    [796423] = true, [896467] = true } -- the group finder refresh button's frame pieces
-- Symbols on buttons that are keyed Icon but belong with the frames: a
-- settings cog next to a grey close button looks wrong in gold.
local SYMBOL_ATLAS_WORDS = { "button-settings", "common-dropdown-a-button", "profession-button-red-crossmark",
    "optionsicon-brown", "common-button-list-plus", "common-button-list-minus" } -- list collapse symbols
-- The same, for symbols known only by file ID.
local SYMBOL_FILE_IDS = { [851904] = true } -- the group finder refresh arrows, frame and all
-- Plain panel buttons, frame only when Blizzard has tinted them (the red
-- Delist button is the grey List Self button with a red vertex colour).
-- Judged every time, since the tint comes and goes.
local TINTED_FILE_IDS = { [130824] = true, [130828] = true }

local function IsTinted(region)
    local r, g, b = region:GetVertexColor()
    if not r then return false end
    local hi, lo = math.max(r, g, b), math.min(r, g, b)
    return hi - lo > 0.25
end
-- Atlases those words would catch that are content after all.
local CONTENT_ATLAS_WORDS = { "daycycle", "mail-icon", "tracking-icon",
    "sidetab-selected", "sidetab-hover", "sidetab-mask", -- a tab's selected and hover looks stay
    "scalehandle-hover", "tab-frame-glow" } -- the active spellbook tab's glow stays
-- Widget types left alone entirely.
local SKIP_TYPES = {
    Model = true, PlayerModel = true, DressUpModel = true,
    CinematicModel = true, ModelScene = true, ModelSceneActor = true,
    Cooldown = true, MessageFrame = true, SimpleHTML = true, Browser = true,
}

local TARGETS = {
    -- Action bars and the bottom of the screen
    "MainActionBar", "MainMenuBar", "MainMenuBarArtFrame", "MultiBarBottomLeft", "MultiBarBottomRight",
    "MultiBarRight", "MultiBarLeft", "MultiBar5", "MultiBar6", "MultiBar7",
    "StanceBar", "PetActionBar", "PossessActionBar", "OverrideActionBar",
    "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer", "StatusTrackingBarManager",
    "BagsBar", "MainMenuBarBackpackButton", "MicroMenuContainer", "MicroMenu",
    -- Minimap
    "MinimapCluster",
    -- Unit frames
    "PlayerFrame", "TargetFrame", "FocusFrame", "PetFrame", "PartyFrame", "PersonalResourceDisplayFrame",
    "TargetFrameToT", "FocusFrameToT", "BossTargetFrameContainer",
    -- Chat
    "GeneralDockManager", "ChatFrameMenuButton", "ChatFrameChannelButton", "QuickJoinToastButton",
    "ChatFrame1", "ChatFrame2", "ChatFrame3", "ChatFrame4", "ChatFrame5",
    "ChatFrame1Tab", "ChatFrame2Tab", "ChatFrame3Tab", "ChatFrame4Tab", "ChatFrame5Tab",
    "ChatFrame1EditBox",
    -- Buffs, the quest tracker and this client's own damage meter
    "BuffFrame", "DebuffFrame", "ObjectiveTrackerFrame", "DamageMeter",
    -- Map
    "WorldMapFrame",
    -- Bags and bank
    "ContainerFrameCombinedBags", "ContainerFrame1", "ContainerFrame2", "ContainerFrame3",
    "ContainerFrame4", "ContainerFrame5", "ContainerFrame6", "ContainerFrame7",
    "ContainerFrame8", "ContainerFrame9", "ContainerFrame10", "ContainerFrame11",
    "ContainerFrame12", "ContainerFrame13", "BankFrame",
    -- Panels (many load on demand)
    "CharacterFrame", "PlayerSpellsFrame", "SpellBookFrame", "QuestMapFrame", "QuestLogFrame",
    "MerchantFrame", "ClassTrainerFrame", "GameMenuFrame", "SettingsPanel", "FriendsFrame",
    "MailFrame", "OpenMailFrame", "TradeFrame", "LootFrame", "GossipFrame", "QuestFrame",
    "TaxiFrame", "DressUpFrame", "PVEFrame", "AddonList", "HelpFrame", "MacroFrame",
    "ItemTextFrame", "PetStableFrame", "InspectFrame", "TabardFrame", "GuildRegistrarFrame", "LFGParentFrame",
    "CollectionsJournal", "EncounterJournal", "ClassTalentFrame", "PlayerTalentFrame",
    "PetitionFrame", "ProfessionsFrame", "TradeSkillFrame", "CraftFrame", "GuildFrame",
    "CommunitiesFrame", "CalendarFrame", "TimeManagerFrame", "RaidFrame", "StackSplitFrame",
    "ColorPickerFrame", "ItemSocketingFrame", "GuildBankFrame", "LootHistoryFrame",
    "StaticPopup1", "StaticPopup2", "StaticPopup3", "StaticPopup4", "ReadyCheckFrame",
    "InterfaceOptionsFrame", "VideoOptionsFrame", "KeyBindingFrame", "ChatConfigFrame",
    -- Tooltips
    "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2",
    "ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2", "EmbeddedItemTooltip",
    "FriendsTooltip", "NamePlateTooltip",
    -- This addon's own windows (same templates as Blizzard's)
    "UlRemedyOptionsFrame", "UlRemedyPlaytimeFrame", "UlRemedyChatCopyFrame",
    "UlRemedyInventoryFrame", "UlRemedyMinimapMenu", "UlRemedyLootRollFrame",
}

local touched = setmetatable({}, { __mode = "k" }) -- texture -> { r, g, b } as first seen
local decided = setmetatable({}, { __mode = "k" }) -- texture -> false (shade) or the skip reason, once judged
local hooked = setmetatable({}, { __mode = "k" })  -- frame -> true once its OnShow is hooked
local missing = {}                                 -- target names not found yet (ApplyNew looks here)

local function Enabled()
    return UlRemedy.enabled and UlRemedy.enabled.darkmode
end

local function Shade()
    local s = tonumber(UlRemedy.enabled and UlRemedy.enabled.shade) or DEFAULT_SHADE
    if s < MIN_SHADE then s = MIN_SHADE elseif s > MAX_SHADE then s = MAX_SHADE end
    return s
end

------------------------------------------------------------------------
-- Deciding what to shade
------------------------------------------------------------------------

local function Lower(s)
    return type(s) == "string" and s:lower() or ""
end

-- Returns nil to shade, or a short reason to skip.
local function HasWord(s, words)
    for _, word in ipairs(words) do
        if s:find(word, 1, true) then return word end
    end
    return nil
end

-- Returns nil to shade, or a short reason to leave the texture alone.
local function SkipReason(region, parent)
    local okKey, key = pcall(region.GetParentKey, region)
    local okName, name = pcall(region.GetName, region)
    local okPKey, pkey = pcall(parent.GetParentKey, parent)
    local okPName, pname = pcall(parent.GetName, parent)
    local okAtlas, atlas = pcall(region.GetAtlas, region)
    local okTex, tex = pcall(region.GetTexture, region)
    local k, n = Lower(okKey and key), Lower(okName and name)
    local own = k .. " " .. n
    local parentWords = Lower(okPKey and pkey) .. " " .. Lower(okPName and pname)
    local art = Lower(okAtlas and atlas) .. " " .. Lower(okTex and type(tex) == "string" and tex)

    -- Button symbols that go grey with the frames, before the content rules.
    if HasWord(art, SYMBOL_ATLAS_WORDS) then return nil end
    if okTex and type(tex) == "number" and SYMBOL_FILE_IDS[tex] then return nil end
    if okTex and type(tex) == "number" and TINTED_FILE_IDS[tex] then
        return IsTinted(region) and nil or "plain button"
    end
    -- Content, whatever else it is called.
    local word = HasWord(own, CONTENT_WORDS)
    if word then return word end
    word = HasWord(parentWords, CONTENT_WORDS)
    if word then return word .. " (parent)" end
    if parent.icon == region or parent.Icon == region or parent.IconTexture == region then return "icon" end
    if parent.GetHighlightTexture and parent:GetHighlightTexture() == region then return "highlight" end
    if parent.GetCheckedTexture and parent:GetCheckedTexture() == region then return "checked" end
    if parent.GetStatusBarTexture and parent:GetStatusBarTexture() == region then return "bar fill" end

    -- Frame: a nine-slice piece, a frame word, or an icon button's slot.
    if okKey and NINE_PIECES[key] then return nil end
    if okTex and type(tex) == "number" and FRAME_FILE_IDS[tex] then return nil end
    if HasWord(art, CONTENT_ATLAS_WORDS) then return "content art" end
    if HasWord(art, FRAME_ATLAS_WORDS) then return nil end
    local notFrame = HasWord(own, NOT_FRAME_WORDS) or HasWord(art, NOT_FRAME_WORDS)
    if notFrame then return "not frame (" .. notFrame .. ")" end
    if HasWord(own, FRAME_WORDS) or HasWord(art, FRAME_WORDS) then return nil end
    if parent.GetNormalTexture and parent:GetNormalTexture() == region
        and (parent.icon or parent.Icon or parent.IconTexture) then return nil end
    return "not frame"
end

-- Desaturated first, so bronze comes out grey rather than dark brown.
-- The grey is set from the brightest channel of the original colour, so
-- art Blizzard tinted (a red button) comes out grey too, and art that
-- was neutral comes out exactly as a plain multiply would.
local function ShadeTexture(tex, s)
    local orig = touched[tex]
    if not orig then
        local r, g, b = tex:GetVertexColor()
        local okD, desat = pcall(tex.IsDesaturated, tex)
        orig = { r or 1, g or 1, b or 1, okD and desat or false }
        touched[tex] = orig
    end
    pcall(tex.SetDesaturated, tex, true)
    local g = math.max(orig[1], orig[2], orig[3]) * s
    tex:SetVertexColor(g, g, g)
end

-- Walks frame and its children. report, when given, collects one line
-- per texture for /ur darkprobe <frame>. Returns shaded, skipped.
local function ShadeFrame(frame, s, depth, report, skipChildren)
    if depth > MAX_DEPTH then return 0, 0 end
    if frame.IsForbidden and frame:IsForbidden() then return 0, 0 end
    local ftype = frame:GetObjectType()
    local fname = frame.GetName and frame:GetName()
    if SKIP_TYPES[ftype] or (fname and SKIP_FRAMES[fname]) then
        if report then
            report[#report + 1] = string.format("%s[%s %s: left alone]", string.rep("  ", depth), ftype, tostring(fname))
        end
        return 0, 0
    end
    if report then
        local okKey, key = pcall(frame.GetParentKey, frame)
        report[#report + 1] = string.format("%s[%s %s]", string.rep("  ", depth), ftype, tostring(fname or (okKey and key and ("." .. key)) or "?"))
    end
    local shaded, skipped = 0, 0
    for _, region in ipairs({ frame:GetRegions() }) do
        if region:IsObjectType("Texture") and not (region.IsForbidden and region:IsForbidden()) then
            -- Judged once per texture: the walk runs on every show, and
            -- the judging is the expensive part.
            local reason = decided[region]
            local okT, texId = pcall(region.GetTexture, region)
            if reason == nil or report or (okT and type(texId) == "number" and TINTED_FILE_IDS[texId]) then
                reason = SkipReason(region, frame)
                decided[region] = reason or false
            end
            if reason == false then reason = nil end
            if reason then
                skipped = skipped + 1
            else
                ShadeTexture(region, s)
                shaded = shaded + 1
            end
            if report then
                local okKey, key = pcall(region.GetParentKey, region)
                local okAtlas, atlas = pcall(region.GetAtlas, region)
                local okTex, tex = pcall(region.GetTexture, region)
                report[#report + 1] = string.format("%s%s: %s (%s)", string.rep("  ", depth),
                    tostring(okKey and key or region:GetName() or "?"),
                    reason and ("left, " .. reason) or "shaded",
                    tostring(okAtlas and atlas or okTex and tex or "no texture"))
            end
        end
    end
    if not REGIONS_ONLY[ftype] then
        for _, child in ipairs({ frame:GetChildren() }) do
            local okKey, key = pcall(child.GetParentKey, child)
            if not (skipChildren and okKey and key and skipChildren[key]) then
                local a, b = ShadeFrame(child, s, depth + 1, report)
                shaded, skipped = shaded + a, skipped + b
            end
        end
    end
    return shaded, skipped
end

local function SafeShadeFrame(frame, s, report)
    local fname = frame.GetName and frame:GetName()
    local ok, shaded, skipped = pcall(ShadeFrame, frame, s, 0, report, fname and SKIP_CHILDREN[fname])
    if ok then return shaded, skipped end
    return 0, 0, shaded
end

------------------------------------------------------------------------
-- Pet happiness
------------------------------------------------------------------------

-- The pet frame's happiness face and the gold frame around it are one
-- texture (UI-PetHappiness, three faces side by side). The frame cannot
-- be darkened on its own, so the whole texture is darkened and the
-- middle of it, the face, is drawn over again in colour: the same
-- picture, cropped by HAPPINESS_INSET on each side, with the texture
-- coordinates the region uses right now. The face changes with the
-- pet's mood, so the copy is refreshed on the mood events and when the
-- frame shows, and hidden when the region is.
local HAPPINESS_INSET = 0.14
local happiness -- { region = texture, overlay = texture }

local function FindHappiness()
    local function scan(frame, depth)
        if depth > 4 then return nil end
        for _, r in ipairs({ frame:GetRegions() }) do
            if r:IsObjectType("Texture") then
                local okA, a = pcall(r.GetAtlas, r)
                local okT, t = pcall(r.GetTexture, r)
                local name = Lower(okA and a) .. " " .. Lower(okT and type(t) == "string" and t)
                if name:find("pethappiness", 1, true) then return r end
            end
        end
        for _, c in ipairs({ frame:GetChildren() }) do
            local found = scan(c, depth + 1)
            if found then return found end
        end
        return nil
    end
    local pf = _G.PetFrame
    return pf and scan(pf, 0) or nil
end

local function UpdateHappiness(s)
    local region = happiness and happiness.region or FindHappiness()
    if not region then return end
    happiness = happiness or { region = region }
    local overlay = happiness.overlay
    if not overlay then
        overlay = region:GetParent():CreateTexture(nil, "OVERLAY", nil, 7)
        happiness.overlay = overlay
    end
    local l, r, t, b
    local okA, atlas = pcall(region.GetAtlas, region)
    local info = okA and type(atlas) == "string" and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)
    if info and info.file then
        overlay:SetTexture(info.file)
        l, r, t, b = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
    else
        local okT, tex = pcall(region.GetTexture, region)
        if not okT or not tex then return end
        overlay:SetTexture(tex)
        local ulx, uly, llx, lly, urx = region:GetTexCoord()
        l, r, t, b = ulx, urx, uly, lly
    end
    local du, dv = (r - l) * HAPPINESS_INSET, (b - t) * HAPPINESS_INSET
    overlay:SetTexCoord(l + du, r - du, t + dv, b - dv)
    local w, h = region:GetSize()
    overlay:ClearAllPoints()
    overlay:SetPoint("TOPLEFT", region, "TOPLEFT", w * HAPPINESS_INSET, -h * HAPPINESS_INSET)
    overlay:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT", -w * HAPPINESS_INSET, h * HAPPINESS_INSET)
    ShadeTexture(region, s)
    overlay:SetShown(region:IsShown())
end

local function RefreshHappiness()
    if Enabled() then pcall(UpdateHappiness, Shade()) end
end

------------------------------------------------------------------------
-- Applying to the list
------------------------------------------------------------------------

-- Shaded on show, and once more a moment later: side tabs and other
-- parts of a window are often built after it is shown.
local function HookFrame(frame)
    if hooked[frame] then return end
    hooked[frame] = true
    if frame.HookScript then
        pcall(frame.HookScript, frame, "OnShow", function(self)
            if not Enabled() then return end
            SafeShadeFrame(self, Shade())
            C_Timer.After(0.3, function()
                if Enabled() and self:IsShown() then SafeShadeFrame(self, Shade()) end
            end)
        end)
    end
end

-- Shades every target that exists. Targets that appear later (load on
-- demand) are picked up by ApplyNew, which looks only at those, so a
-- Blizzard addon loading does not cost a walk of every window again.
local function ApplyAll()
    if not Enabled() then return end
    local s = Shade()
    wipe(missing)
    for _, name in ipairs(TARGETS) do
        local frame = _G[name]
        if type(frame) == "table" and frame.GetObjectType then
            SafeShadeFrame(frame, s)
            HookFrame(frame)
        else
            missing[#missing + 1] = name
        end
    end
    pcall(UpdateHappiness, s)
    if _G.PetFrame and not hooked.petHappiness then
        hooked.petHappiness = true
        pcall(_G.PetFrame.HookScript, _G.PetFrame, "OnShow", RefreshHappiness)
    end
end

local function ApplyNew()
    if not Enabled() then return end
    local s = Shade()
    local still = {}
    for _, name in ipairs(missing) do
        local frame = _G[name]
        if type(frame) == "table" and frame.GetObjectType then
            SafeShadeFrame(frame, s)
            HookFrame(frame)
        else
            still[#still + 1] = name
        end
    end
    missing = still
end

local function RestoreAll()
    for tex, orig in pairs(touched) do
        pcall(tex.SetDesaturated, tex, orig[4])
        pcall(tex.SetVertexColor, tex, orig[1], orig[2], orig[3])
    end
    if happiness and happiness.overlay then happiness.overlay:Hide() end
end

function UlRemedy.RefreshDarkMode()
    if Enabled() then ApplyAll() else RestoreAll() end
end

-- Every window Blizzard opens as a UI panel (character, map, group
-- finder, collections, and whatever this client adds) goes through
-- ShowUIPanel, so a post-hook there shades panels the list does not
-- name. Post-hook only: nothing of Blizzard's is changed or called.
if type(hooksecurefunc) == "function" and type(ShowUIPanel) == "function" then
    hooksecurefunc("ShowUIPanel", function(panel)
        if Enabled() and type(panel) == "table" and panel.GetObjectType and not hooked[panel] then
            -- First time only; from then on the OnShow hook does it.
            SafeShadeFrame(panel, Shade())
            HookFrame(panel)
            C_Timer.After(0.3, function()
                if Enabled() and panel:IsShown() then SafeShadeFrame(panel, Shade()) end
            end)
        end
    end)
end

------------------------------------------------------------------------
-- Commands
------------------------------------------------------------------------

-- /ur shade <n>
function UlRemedy.SetShade(arg)
    local n = tonumber(arg)
    if not n then
        print(string.format("%s: shade is %.2f. /ur shade <%.1f to %d> sets it, lower is darker.",
            UlRemedy.name, Shade(), MIN_SHADE, MAX_SHADE))
        return
    end
    if n < MIN_SHADE then n = MIN_SHADE elseif n > MAX_SHADE then n = MAX_SHADE end
    UlRemedy.enabled.shade = n
    if Enabled() then ApplyAll() end
    print(string.format("%s: shade set to %.2f.", UlRemedy.name, n))
end

-- The named frame under the mouse and its named ancestors, for
-- /ur darkprobe mouse: the way to learn what a window is called.
local function MouseChain()
    local focus
    if type(GetMouseFoci) == "function" then
        local ok, list = pcall(GetMouseFoci)
        focus = ok and type(list) == "table" and list[1] or nil
    elseif type(GetMouseFocus) == "function" then
        local ok, f = pcall(GetMouseFocus)
        focus = ok and f or nil
    end
    local chain = {}
    local f = focus
    while f and #chain < 12 do
        local okName, name = pcall(f.GetName, f)
        local okKey, key = pcall(f.GetParentKey, f)
        chain[#chain + 1] = (okName and name) or (okKey and key and ("." .. key)) or f:GetObjectType()
        local okP, p = pcall(f.GetParent, f)
        f = okP and p or nil
    end
    return chain
end

-- /ur darkprobe [frame [word] | mouse]: with a word, only the lines
-- containing it are printed ("left" shows what was not taken).
function UlRemedy.DarkModeProbe(arg)
    if arg == "mouse" then
        print(UlRemedy.name .. ": under the mouse: " .. table.concat(MouseChain(), " < "))
        return
    end
    if arg and arg ~= "" then
        local path, filter = arg:match("^(%S+)%s*(.*)$")
        filter = filter ~= "" and filter:lower() or nil
        -- A dotted path walks keys: MinimapCluster.BorderTop
        local frame = _G
        for part in path:gmatch("[^%.]+") do
            frame = type(frame) == "table" and frame[part] or nil
        end
        if type(frame) ~= "table" or not frame.GetObjectType then
            print(UlRemedy.name .. ": no frame named " .. path)
            return
        end
        local report = {}
        local shaded, skipped, err = SafeShadeFrame(frame, Enabled() and Shade() or 1, report)
        print(string.format("%s: %s, %d shaded, %d left%s%s", UlRemedy.name, path, shaded, skipped,
            err and (", error: " .. tostring(err)) or "", filter and (", lines with '" .. filter .. "'") or ""))
        for _, line in ipairs(report) do
            if not filter or line:lower():find(filter, 1, true) then print("  " .. line) end
        end
        return
    end
    print(string.format("%s: dark mode %s, shade %.2f. Targets:", UlRemedy.name,
        Enabled() and "on" or "off", Shade()))
    local found, lost = {}, {}
    for _, name in ipairs(TARGETS) do
        local frame = _G[name]
        if type(frame) == "table" and frame.GetObjectType then
            local shaded, skipped, err = SafeShadeFrame(frame, Enabled() and Shade() or 1)
            found[#found + 1] = string.format("%s %d/%d%s", name, shaded, skipped, err and "!" or "")
        else
            lost[#lost + 1] = name
        end
    end
    print("  found (shaded/skipped): " .. table.concat(found, ", "))
    print("  missing: " .. table.concat(lost, ", "))
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------

local frame = CreateFrame("Frame", "UlRemedyDarkModeFrame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("ADDON_LOADED")
-- The pet's mood: these may not all exist on every client.
for _, ev in ipairs({ "UNIT_HAPPINESS", "PET_UI_UPDATE", "UNIT_PET" }) do pcall(frame.RegisterEvent, frame, ev) end
frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "UNIT_HAPPINESS" or event == "PET_UI_UPDATE" or event == "UNIT_PET" then
        C_Timer.After(0, RefreshHappiness)
    elseif event == "ADDON_LOADED" then
        -- A Blizzard panel addon just brought its frames; shade them a
        -- moment later, once they are built.
        if type(arg1) == "string" and arg1:find("^Blizzard_") and Enabled() then
            C_Timer.After(0, ApplyNew)
        end
    else
        if Enabled() then ApplyAll() end
    end
end)
