----------------------------------------------------------------
-- CustomUI.GroupIcons — Controller
--
-- View: GroupIcons.xml (templates + OnUpdate driver/probe only); controller owns all logic.
-- Load order: CustomUI.mod lists this script before the XML so handlers exist at parse time.
--
-- Behavior overview:
--   • Roster (party row 1, open-world warband 4×6): career icon + ring on member worldObjNum.
--     Scenario with Scenario checkbox ON: roster grid only for *your* scenario party (sgroupindex match); other scenario parties use outsider tracking with Friendly/Hostile gates — rings match roster style when Scenario enabled else realm blue/red.
--     Self is skipped. Crown overlay matches warband leader on hydrated warband slots only (scenario roster omits crown).
--     Rings use archetype colors when enabled; settings live under CustomUI.Settings.GroupIcons.
--   • Roster attach requires a live worldObjNum this refresh (party slot / scenario roster optional scenarioWorldObjNum).
--     Cached (“sticky”) ids refine LearnKnown tables only — stale ids are never drawn (would anchor at screen origin).
--     Attachment uses AttachWindowToWorldObject; outsiders still use MoveWindowToWorldObject + probe validation.
--   • Outsiders (non-own-roster players incl. other scenario parties): hostile / friendly / mouseover PLAYER_TARGET_UPDATED → deferred TargetInfo read;
--     FIFO pool (c_MAX_TRACKED_OUTSIDERS); realm-tint rings in scenario when Scenario checkbox OFF, archetype roster-style rings when ON (+ Friendly/Hostile toggles unchanged).
--   • Names: NormalizeNameKey (strip caret grammar, lowercase) for PartyUtils / scenario / roster dedupe.
--   • Driver window CustomUIGroupIconsDriver (Root, 1×1) owns OnUpdate; probe CustomUIGroupIconsWorldProbe is hit-test free.
----------------------------------------------------------------

if not CustomUI.GroupIcons then
    CustomUI.GroupIcons = {}
end

----------------------------------------------------------------
-- Constants
----------------------------------------------------------------

local c_MAX_PARTIES  = 6
local c_MAX_MEMBERS  = 6
-- Round-Swatch-Selection-Ring art is inset in its slice; large centered ring + smaller centered icon.
local c_FRAME_SIZE   = 48   -- Content square and outer window width; vertical band toward attach point
local c_ICON_DRAW    = 34   -- career icon display size (inside ring)
local c_RING_SIZE    = 48   -- ring overlay size (scale up so band clears icon corners)

-- Archetype colors: defaults from Enemy UnitFrames HpArchetypeColoredBar (tankColor / dpsColor / healColor).
local c_ARCHETYPE_TANK  = 1
local c_ARCHETYPE_DPS   = 2
local c_ARCHETYPE_HEAL  = 3
local c_ARCHETYPE_RGB = {
    [c_ARCHETYPE_TANK] = { 150, 190, 255 },
    [c_ARCHETYPE_DPS]  = { 255, 190, 100 },
    [c_ARCHETYPE_HEAL] = { 190, 255, 100 },
}
-- Same career → archetype mapping as Enemy.careerArchetypes (Code/Core/Groups/Groups.lua).
local c_CAREER_ARCHETYPE = {
    [GameData.CareerLine.IRON_BREAKER]  = c_ARCHETYPE_TANK,
    [GameData.CareerLine.SWORDMASTER]   = c_ARCHETYPE_TANK,
    [GameData.CareerLine.CHOSEN]        = c_ARCHETYPE_TANK,
    [GameData.CareerLine.BLACK_ORC]     = c_ARCHETYPE_TANK,
    [GameData.CareerLine.KNIGHT]        = c_ARCHETYPE_TANK,
    [GameData.CareerLine.BLACKGUARD]    = c_ARCHETYPE_TANK,
    [GameData.CareerLine.WITCH_HUNTER]  = c_ARCHETYPE_DPS,
    [GameData.CareerLine.WHITE_LION]    = c_ARCHETYPE_DPS,
    [GameData.CareerLine.MARAUDER]      = c_ARCHETYPE_DPS,
    [GameData.CareerLine.WITCH_ELF]     = c_ARCHETYPE_DPS,
    [GameData.CareerLine.BRIGHT_WIZARD] = c_ARCHETYPE_DPS,
    [GameData.CareerLine.MAGUS]         = c_ARCHETYPE_DPS,
    [GameData.CareerLine.SORCERER]      = c_ARCHETYPE_DPS,
    [GameData.CareerLine.ENGINEER]      = c_ARCHETYPE_DPS,
    [GameData.CareerLine.SHADOW_WARRIOR]= c_ARCHETYPE_DPS,
    [GameData.CareerLine.SQUIG_HERDER]  = c_ARCHETYPE_DPS,
    [GameData.CareerLine.CHOPPA]        = c_ARCHETYPE_DPS,
    [GameData.CareerLine.WARRIOR_PRIEST]= c_ARCHETYPE_HEAL,
    [GameData.CareerLine.DISCIPLE]      = c_ARCHETYPE_HEAL,
    [GameData.CareerLine.ARCHMAGE]      = c_ARCHETYPE_HEAL,
    [GameData.CareerLine.SHAMAN]         = c_ARCHETYPE_HEAL,
    [GameData.CareerLine.RUNE_PRIEST]    = c_ARCHETYPE_HEAL,
    [GameData.CareerLine.ZEALOT]         = c_ARCHETYPE_HEAL,
}
if GameData.CareerLine.SLAYER then
    c_CAREER_ARCHETYPE[GameData.CareerLine.SLAYER] = c_ARCHETYPE_DPS
end
if GameData.CareerLine.HAMMERER then
    c_CAREER_ARCHETYPE[GameData.CareerLine.HAMMERER] = c_ARCHETYPE_DPS
end

-- Career → realm for outsider ring tint (Order blue / Destruction red).
local c_CAREER_REALM = {
    [GameData.CareerLine.IRON_BREAKER]   = GameData.Realm.ORDER,
    [GameData.CareerLine.SWORDMASTER]    = GameData.Realm.ORDER,
    [GameData.CareerLine.WITCH_HUNTER]   = GameData.Realm.ORDER,
    [GameData.CareerLine.WHITE_LION]     = GameData.Realm.ORDER,
    [GameData.CareerLine.BRIGHT_WIZARD]  = GameData.Realm.ORDER,
    [GameData.CareerLine.ENGINEER]      = GameData.Realm.ORDER,
    [GameData.CareerLine.SHADOW_WARRIOR] = GameData.Realm.ORDER,
    [GameData.CareerLine.WARRIOR_PRIEST] = GameData.Realm.ORDER,
    [GameData.CareerLine.RUNE_PRIEST]    = GameData.Realm.ORDER,
    [GameData.CareerLine.ARCHMAGE]       = GameData.Realm.ORDER,
    [GameData.CareerLine.KNIGHT]         = GameData.Realm.ORDER,
    [GameData.CareerLine.CHOSEN]         = GameData.Realm.DESTRUCTION,
    [GameData.CareerLine.BLACK_ORC]      = GameData.Realm.DESTRUCTION,
    [GameData.CareerLine.MARAUDER]       = GameData.Realm.DESTRUCTION,
    [GameData.CareerLine.WITCH_ELF]      = GameData.Realm.DESTRUCTION,
    [GameData.CareerLine.MAGUS]          = GameData.Realm.DESTRUCTION,
    [GameData.CareerLine.SORCERER]       = GameData.Realm.DESTRUCTION,
    [GameData.CareerLine.SQUIG_HERDER]   = GameData.Realm.DESTRUCTION,
    [GameData.CareerLine.CHOPPA]         = GameData.Realm.DESTRUCTION,
    [GameData.CareerLine.DISCIPLE]       = GameData.Realm.DESTRUCTION,
    [GameData.CareerLine.SHAMAN]         = GameData.Realm.DESTRUCTION,
    [GameData.CareerLine.ZEALOT]         = GameData.Realm.DESTRUCTION,
    [GameData.CareerLine.BLACKGUARD]     = GameData.Realm.DESTRUCTION,
}
if GameData.CareerLine.SLAYER then
    c_CAREER_REALM[GameData.CareerLine.SLAYER] = GameData.Realm.ORDER
end
if GameData.CareerLine.HAMMERER then
    c_CAREER_REALM[GameData.CareerLine.HAMMERER] = GameData.Realm.ORDER
end

-- Stock TargetInfo unit ids (ea_targetwindow / ea_mouseovertargetwindow).
local c_HOSTILE_TARGET    = "selfhostiletarget"
local c_FRIENDLY_TARGET   = "selffriendlytarget"
local c_MOUSEOVER_TARGET  = "mouseovertarget"

-- Outsiders beyond this cap evict the longest-held track first (FIFO, not LRU refresh on retarget).
local c_MAX_TRACKED_OUTSIDERS = 48
local c_WORLD_PROBE_WINDOW = "CustomUIGroupIconsWorldProbe"
local c_GROUPICONS_DRIVER = "CustomUIGroupIconsDriver"

-- Realm ring RGB (outsider targets); archetype colors stay on group members.
local c_REALM_RING_ORDER  = { 0, 0, 255 }
local c_REALM_RING_DEST   = { 255, 0, 0 }
local c_RING_GREEN        = { 0, 255, 0 }

local c_DEFAULT_SETTINGS = {
    showParty = true,
    showWarband = true,
    archetypeColors = true,
    showFriendly = true,
    showHostile = true,
}

local function EnsureSettings()
    CustomUI.Settings = CustomUI.Settings or { Components = {} }
    if CustomUI.Settings.Components == nil then
        CustomUI.Settings.Components = {}
    end
    if type(CustomUI.Settings.GroupIcons) ~= "table" then
        CustomUI.Settings.GroupIcons = {}
    end
    local s = CustomUI.Settings.GroupIcons
    for k, v in pairs(c_DEFAULT_SETTINGS) do
        if s[k] == nil then
            s[k] = v
        end
    end
    return s
end

local function RealmRingRgbForCareerLine(careerLine)
    local realm = careerLine and c_CAREER_REALM[careerLine]
    if realm == GameData.Realm.ORDER then
        return c_REALM_RING_ORDER[1], c_REALM_RING_ORDER[2], c_REALM_RING_ORDER[3]
    elseif realm == GameData.Realm.DESTRUCTION then
        return c_REALM_RING_DEST[1], c_REALM_RING_DEST[2], c_REALM_RING_DEST[3]
    end
    return 160, 160, 160
end

local function GroupRingRgbForCareerLine(careerLine)
    local s = EnsureSettings()
    if not s.archetypeColors then
        return c_RING_GREEN[1], c_RING_GREEN[2], c_RING_GREEN[3], "green"
    end
    local arch = careerLine and c_CAREER_ARCHETYPE[careerLine]
    local rgb = arch and c_ARCHETYPE_RGB[arch]
    if rgb then
        return rgb[1], rgb[2], rgb[3], "archetype"
    end
    return 160, 160, 160, "archetype"
end
-- GetIconData atlas cell size in texture pixels for career icons.
-- Stock uses TexDims 32 (see EA_Image_CareerIcon template); using the wrong value can tile/repeat.
local c_ATLAS_ICON   = 32
-- Round-Swatch-Selection-Ring — defaultskintextures.xml on EA_HUD_01 (must match slice or atlas bleeds).
local c_RING_TEXTURE = "EA_HUD_01"
local c_RING_TEX_X   = 295
local c_RING_TEX_Y   = 475
local c_RING_TEX_DIM = 38
-- WarbandLeaderCrown — templates_unitframes.xml / defaultskintextures Warband-Leader-Crown
local c_CROWN_TEXTURE = "EA_HUD_01"
local c_CROWN_TEX_X   = 162
local c_CROWN_TEX_Y   = 138
local c_CROWN_TEX_W   = 25
local c_CROWN_TEX_H   = 16
local c_OFFSET_Y     = 50   -- empty vertical gap (pixels) *below* the icon inside the outer window, toward the world-attach end
local c_OUTER_H      = c_OFFSET_Y + c_FRAME_SIZE   -- outer must contain frame + gap (View/GroupIcons.xml)

----------------------------------------------------------------
-- GroupIcon — one reusable slot
----------------------------------------------------------------

local GroupIcon = {}
GroupIcon.__index = GroupIcon

function GroupIcon.New(partyIndex, memberIndex)
    local self = setmetatable({}, GroupIcon)
    self.partyIndex  = partyIndex
    self.memberIndex = memberIndex
    self.isEnabled   = false
    self.windowName  = nil
    self.playerName  = nil
    self.worldObjNum    = 0
    self.lastCareerLine = nil
    self.lastCareerNamesId = nil -- Icons careers table id (scenario roster); nil = use careerLine → atlas only
    self.lastWarbandCrown = nil
    self.lastRingTintKey = nil -- "archetype" | "realm:r,g,b"
    self.followWorldMovePoll = false
    self.lastFollowWorldMovePoll = nil
    return self
end

function GroupIcon:_windowName()
    return "CustomUIGroupIcon_" .. self.partyIndex .. "_" .. self.memberIndex
end

function GroupIcon:Attach(name, worldObjNum, careerLine, showWarbandCrown, useRealmRingTint, followWorldMovePoll, careerNamesId)
    self:_detach()

    showWarbandCrown = showWarbandCrown == true
    useRealmRingTint = useRealmRingTint == true
    followWorldMovePoll = followWorldMovePoll == true
    careerNamesId = tonumber(careerNamesId)

    self.windowName  = self:_windowName()
    self.playerName  = name
    self.worldObjNum = worldObjNum

    CreateWindowFromTemplate(self.windowName, "CustomUIGroupIcon", "Root")
    local base = self.windowName
    local content = base .. "Content"
    if WindowSetHandleInput then
        WindowSetHandleInput(base, false)
        WindowSetHandleInput(content, false)
    end
    local iconWin = content .. "Icon"
    local ringWin = content .. "Ring"
    local crownWin = content .. "WarbandCrown"
    if WindowSetDimensions and DoesWindowExist(base) then
        WindowSetDimensions(base, c_FRAME_SIZE, c_OUTER_H)
        WindowSetDimensions(content, c_FRAME_SIZE, c_FRAME_SIZE)
    end

    -- Pin Content to outer base before children anchor to Content or each other (ClearAnchors(Content) last was breaking crown↔ring).
    WindowClearAnchors(content)
    WindowAddAnchor(content, "topleft", base, "topleft", 0, 0)

    -- Career icon: match ScenarioGroupWindow — scenario roster careerId is a Careers-names id, not always == careerLine index.
    local texture, tx, ty
    if careerNamesId ~= nil and careerNamesId ~= 0 and type(Icons) == "table" and type(Icons.GetCareerIconIDFromCareerNamesID) == "function" then
        local cell = Icons.GetCareerIconIDFromCareerNamesID(careerNamesId)
        if cell ~= nil and cell ~= 0 then
            texture, tx, ty = GetIconData(cell)
        end
    end
    if texture == nil and careerLine ~= nil and type(Icons) == "table" and type(Icons.GetCareerIconIDFromCareerLine) == "function" then
        texture, tx, ty = GetIconData(Icons.GetCareerIconIDFromCareerLine(careerLine))
    end
    if texture ~= nil then
        DynamicImageSetTexture(iconWin, texture, tx, ty)
        DynamicImageSetTextureDimensions(iconWin, c_ATLAS_ICON, c_ATLAS_ICON)
    end

    DynamicImageSetTexture(ringWin, c_RING_TEXTURE, c_RING_TEX_X, c_RING_TEX_Y)
    DynamicImageSetTextureDimensions(ringWin, c_RING_TEX_DIM, c_RING_TEX_DIM)

    local rr, gg, bb
    if useRealmRingTint then
        rr, gg, bb = RealmRingRgbForCareerLine(careerLine)
        self.lastRingTintKey = string.format("realm:%d,%d,%d", rr, gg, bb)
    else
        rr, gg, bb, self.lastRingTintKey = GroupRingRgbForCareerLine(careerLine)
    end
    WindowSetTintColor(ringWin, rr, gg, bb)
    self.lastCareerLine = careerLine
    self.lastCareerNamesId = careerNamesId

    WindowClearAnchors(iconWin)
    WindowAddAnchor(iconWin, "center", content, "center", 0, 0)
    WindowSetDimensions(iconWin, c_ICON_DRAW, c_ICON_DRAW)

    WindowClearAnchors(ringWin)
    WindowAddAnchor(ringWin, "center", content, "center", 0, 0)
    WindowSetDimensions(ringWin, c_RING_SIZE, c_RING_SIZE)

    DynamicImageSetTexture(crownWin, c_CROWN_TEXTURE, c_CROWN_TEX_X, c_CROWN_TEX_Y)
    DynamicImageSetTextureDimensions(crownWin, c_CROWN_TEX_W, c_CROWN_TEX_H)
    WindowClearAnchors(crownWin)
    WindowSetDimensions(crownWin, c_CROWN_TEX_W, c_CROWN_TEX_H)
    -- Crown.bottom must meet ring.top; crown→ring WindowAddAnchor resolves inverted for these DynamicImages,
    -- so place crown explicitly from Content topleft (ring is centered: ring top inset = (FRAME−RING)/2 on each axis).
    local ringTopInset = math.floor((c_FRAME_SIZE - c_RING_SIZE) / 2)
    local crownOffX = math.floor((c_FRAME_SIZE - c_CROWN_TEX_W) / 2)
    local crownTopY = ringTopInset - c_CROWN_TEX_H
    WindowAddAnchor(crownWin, "topleft", content, "topleft", crownOffX, crownTopY)
    WindowSetShowing(crownWin, showWarbandCrown)
    self.lastWarbandCrown = showWarbandCrown

    self.followWorldMovePoll = followWorldMovePoll
    self.lastFollowWorldMovePoll = followWorldMovePoll
    if followWorldMovePoll then
        WindowSetShowing(base, true)
        MoveWindowToWorldObject(self.windowName, worldObjNum, 1.0)
        WindowSetAlpha(base, 1.0)
    else
        AttachWindowToWorldObject(self.windowName, worldObjNum)
    end
end

function GroupIcon:_detach()
    if not self.windowName then return end
    local wid = self.worldObjNum
    if wid ~= 0 and not self.followWorldMovePoll then
        DetachWindowFromWorldObject(self.windowName, wid)
    end
    if DoesWindowExist(self.windowName) then
        DestroyWindow(self.windowName)
    end
    self.windowName   = nil
    self.playerName   = nil
    self.worldObjNum  = 0
    self.lastCareerLine = nil
    self.lastCareerNamesId = nil
    self.lastWarbandCrown = nil
    self.lastRingTintKey = nil
    self.followWorldMovePoll = false
    self.lastFollowWorldMovePoll = nil
end

function GroupIcon:Update(name, worldObjNum, careerLine, showWarbandCrown, useRealmRingTint, followWorldMovePoll, careerNamesId)
    if not self.isEnabled then return end
    showWarbandCrown = showWarbandCrown == true
    useRealmRingTint = useRealmRingTint == true
    followWorldMovePoll = followWorldMovePoll == true
    careerNamesId = tonumber(careerNamesId)
    local wantRingKey = "archetype"
    if useRealmRingTint then
        local r, g, b = RealmRingRgbForCareerLine(careerLine)
        wantRingKey = string.format("realm:%d,%d,%d", r, g, b)
    else
        local _, _, _, key = GroupRingRgbForCareerLine(careerLine)
        wantRingKey = key
    end
    if worldObjNum == 0 then
        self:_detach()
        return
    end
    -- Fast path: only leader crown toggled; skip Destroy/Attach for identical attach state.
    local crownWin = self.windowName and (self.windowName .. "ContentWarbandCrown")
    if crownWin and DoesWindowExist(crownWin)
        and self.playerName == name
        and self.worldObjNum == worldObjNum
        and self.lastCareerLine == careerLine
        and self.lastCareerNamesId == careerNamesId
        and self.lastWarbandCrown ~= showWarbandCrown
        and self.lastRingTintKey == wantRingKey
        and self.lastFollowWorldMovePoll == followWorldMovePoll
    then
        WindowSetShowing(crownWin, showWarbandCrown)
        self.lastWarbandCrown = showWarbandCrown
        return
    end
    -- Re-attach if the player, world object, career (ring / icon), warband crown, ring tint mode, or follow mode changed.
    if not self.windowName
        or self.playerName   ~= name
        or self.worldObjNum  ~= worldObjNum
        or self.lastCareerLine ~= careerLine
        or self.lastCareerNamesId ~= careerNamesId
        or self.lastWarbandCrown ~= showWarbandCrown
        or self.lastRingTintKey ~= wantRingKey
        or self.lastFollowWorldMovePoll ~= followWorldMovePoll
    then
        self:Attach(name, worldObjNum, careerLine, showWarbandCrown, useRealmRingTint, followWorldMovePoll, careerNamesId)
    end
end

function GroupIcon:Enable()
    self.isEnabled = true
end

function GroupIcon:Disable()
    self:_detach()
    self.isEnabled = false
end

----------------------------------------------------------------
-- Module state
----------------------------------------------------------------

local m_icons = {}      -- m_icons[partyIndex][memberIndex] = GroupIcon
local m_outsiderPool = {}       -- [1..c_MAX_TRACKED_OUTSIDERS] = GroupIcon
local m_slotOccupantWid = {}    -- [slotIndex] = worldObjNum | nil
local m_trackWidToSlot = {}     -- [worldObjNum] = slotIndex
local m_trackMeta = {}          -- [worldObjNum] = { name = WString }
local m_trackFIFOOrder = {}     -- array of worldObjNum; index 1 = oldest (evicted first when full)
local m_pendingOutsiderClassifications = {} -- TargetInfo classifications to apply next OnUpdate (avoid UpdateFromClient + handler order)
local m_groupWorldObjs = {}    -- [worldObjNum] = true for roster (party/warband)
local m_groupNames = {}        -- [playerName] = true (fast path when exact match works)
local m_groupNameList = {}     -- { WString, ... } robust compare via WStringsCompareIgnoreGrammer

-- Known player worldObj ids by normalized name key (learned from PartyUtils + TargetInfo).
-- { [key] = { wid = number, careerLine = number|nil, t = number|nil } }
local m_knownByNameKey = {}

-- Last known worldObjNum per name (updated when live data gives a wid). Used for cache/learn paths only;
-- roster icons are not drawn from sticky alone (stale wid → MoveWindowToWorldObject often lands top-left).
-- Cleared for keys no longer on the roster; full clear on zone change.
local m_stickyRosterWidByKey = {}

local m_debugLastSig = nil

local function DebugLog(msg)
    if type(d) == "function" then
        -- Must not depend on local ToWString (defined later in file).
        d(towstring("[CustomUI.GroupIcons] " .. tostring(msg)))
    end
end

-- Forward decls (used before definition).
local IsScenarioContext
local RefreshAll

----------------------------------------------------------------
-- Internal helpers
----------------------------------------------------------------

local function ToWString(v)
    if v == nil then
        return L""
    end
    if type(v) == "wstring" then
        return v
    end
    return towstring(v)
end

local function ToNameString(name)
    if name == nil then
        return nil
    end
    if type(name) == "wstring" and type(WStringToString) == "function" then
        name = WStringToString(name)
    end
    if type(name) ~= "string" then
        name = tostring(name)
    end
    return name
end

--- Stable key for matching PartyUtils / scenario roster / TargetInfo names (Enemy.FixString: strip '^' grammar + lowercase).
local function NormalizeNameKey(name)
    local s = ToNameString(name)
    if s == nil or s == "" then
        return nil
    end
    local caret = string.find(s, "^", 1, true)
    if caret then
        s = string.sub(s, 1, caret - 1)
    end
    return string.lower(s)
end

local function InvalidatePartyAndWarbandCaches()
    if GameData and GameData.Party then
        GameData.Party.partyDirty = true
        GameData.Party.warbandDirty = true
    end
end

local function RegisterGroupMemberName(nameW)
    local name = ToWString(nameW)
    if name == L"" then
        return
    end
    m_groupNames[name] = true
    m_groupNameList[#m_groupNameList + 1] = name
end

local function SafeWStringEquals(a, b)
    -- Defensive: some call sites still surface mixed string/wstring; never crash OnUpdate.
    local ok, res = pcall(WStringsCompareIgnoreGrammer, ToWString(a), ToWString(b))
    if not ok then
        return false
    end
    return res == 0
end

local function ClearGroupMembershipCache()
    m_groupWorldObjs = {}
    m_groupNames = {}
    m_groupNameList = {}
end

local function RegisterGroupMember(member)
    if not member or not member.name then
        return
    end
    local name = ToWString(member.name)
    if member.worldObjNum and member.worldObjNum ~= 0 then
        m_groupWorldObjs[member.worldObjNum] = true
    end
    m_groupNames[name] = true
    m_groupNameList[#m_groupNameList + 1] = name
end

local function RememberStickyRosterWid(nameW, wid)
    local key = NormalizeNameKey(nameW)
    local w = tonumber(wid) or 0
    if key ~= nil and w ~= 0 then
        m_stickyRosterWidByKey[key] = w
    end
end

--- Roster icons only attach when this refresh has live worldObjNum from party/warband rows.
--- RememberStickyRosterWid updates cache when non-zero; zero means hide slot (no sticky-only draw).
local function ResolveRosterIconAttachWorldId(nameW, liveWidFromData)
    local w = tonumber(liveWidFromData) or 0
    if w ~= 0 then
        RememberStickyRosterWid(nameW, w)
        return w
    end
    return 0
end

local function PruneStickyRosterWids(validKeys)
    if validKeys == nil then
        return
    end
    for key, _ in pairs(m_stickyRosterWidByKey) do
        if not validKeys[key] then
            m_stickyRosterWidByKey[key] = nil
        end
    end
end

local function LearnKnownWorldObject(name, wid, careerLine)
    local key = NormalizeNameKey(name)
    local w = tonumber(wid) or 0
    if key == nil or w == 0 then
        return false
    end
    local prev = m_knownByNameKey[key]
    if prev ~= nil and prev.wid == w and (careerLine == nil or prev.careerLine == careerLine) then
        return false
    end
    RememberStickyRosterWid(name, w)
    m_knownByNameKey[key] = {
        wid = w,
        careerLine = tonumber(careerLine),
        t = type(CustomUI) == "table" and CustomUI.Time or nil,
    }
    DebugLog("LearnKnownWorldObject: " .. tostring(key) .. " wid=" .. tostring(w) .. " careerLine=" .. tostring(careerLine))
    return true
end

--- Prefer PartyUtils.GetPartyMember(i): merges GetGroupMemberStatusData (worldObjNum, etc.) when dirty.
--- Raw GetPartyData()[i] can omit or stale worldObjNum until stock party pipeline refreshes members.
local function GetPartySlotMember(memberIndex, fallbackData)
    if memberIndex == nil or memberIndex < 1 then
        return nil
    end
    if type(PartyUtils) == "table" and type(PartyUtils.GetPartyMember) == "function" then
        local maxWithoutSelf = tonumber(PartyUtils.PLAYERS_PER_PARTY_WITHOUT_LOCAL) or 5
        if memberIndex <= maxWithoutSelf then
            local mem = PartyUtils.GetPartyMember(memberIndex)
            if mem ~= nil then
                return mem
            end
        end
    end
    if type(fallbackData) == "table" then
        return fallbackData[memberIndex]
    end
    return nil
end

local function LearnKnownWorldObjectsFromParty()
    InvalidatePartyAndWarbandCaches()
    local data = nil
    if type(PartyUtils) == "table" and type(PartyUtils.GetPartyData) == "function" then
        data = PartyUtils.GetPartyData()
    end
    if data == nil then
        data = GetGroupData()
    end
    if type(data) ~= "table" then
        return
    end
    for m = 1, c_MAX_MEMBERS do
        local member = GetPartySlotMember(m, data)
        if member and member.name and member.worldObjNum and member.worldObjNum ~= 0 then
            LearnKnownWorldObject(member.name, member.worldObjNum, member.careerLine)
        end
    end
end

local function IsSelfMember(memberName)
    memberName = ToWString(memberName)
    if memberName == L"" or not GameData or not GameData.Player or not GameData.Player.name then
        return false
    end
    return SafeWStringEquals(memberName, GameData.Player.name)
end

local function IsGroupMemberName(name)
    name = ToWString(name)
    if name == L"" then
        return false
    end
    if m_groupNames[name] then
        return true
    end
    for i = 1, #m_groupNameList do
        if SafeWStringEquals(name, m_groupNameList[i]) then
            return true
        end
    end
    return false
end

local function TrackFifoRemove(wid)
    for i = 1, #m_trackFIFOOrder do
        if m_trackFIFOOrder[i] == wid then
            table.remove(m_trackFIFOOrder, i)
            return
        end
    end
end

local function UntrackOutsiderWid(wid)
    TrackFifoRemove(wid)
    local idx = m_trackWidToSlot[wid]
    if not idx then
        return
    end
    m_trackWidToSlot[wid] = nil
    m_trackMeta[wid] = nil
    m_slotOccupantWid[idx] = nil
    local icon = m_outsiderPool[idx]
    if icon then
        icon:Disable()
    end
end

local function UntrackAllOutsiders()
    local wids = {}
    for wid, _ in pairs(m_trackWidToSlot) do
        wids[#wids + 1] = wid
    end
    for i = 1, #wids do
        UntrackOutsiderWid(wids[i])
    end
    m_trackFIFOOrder = {}
end

local function TryTrackOutsider(wid, pname, career)
    if not wid or wid == 0 then
        return
    end
    local realmRing = true
    if m_trackWidToSlot[wid] then
        local idx = m_trackWidToSlot[wid]
        local icon = m_outsiderPool[idx]
        icon:Enable()
        icon:Update(pname, wid, career, false, realmRing, true)
        m_trackMeta[wid] = { name = pname }
        return
    end
    if m_groupWorldObjs[wid] or IsGroupMemberName(pname) then
        return
    end

    local function findFreeSlot()
        for i = 1, c_MAX_TRACKED_OUTSIDERS do
            if m_slotOccupantWid[i] == nil then
                return i
            end
        end
        return nil
    end

    local freeIdx = findFreeSlot()
    if freeIdx == nil then
        local oldest = m_trackFIFOOrder[1]
        if oldest ~= nil then
            UntrackOutsiderWid(oldest)
        end
        freeIdx = findFreeSlot()
    end
    if freeIdx == nil then
        return
    end

    m_slotOccupantWid[freeIdx] = wid
    m_trackWidToSlot[wid] = freeIdx
    m_trackMeta[wid] = { name = pname }
    table.insert(m_trackFIFOOrder, wid)
    local icon = m_outsiderPool[freeIdx]
    icon:Enable()
    icon:Update(pname, wid, career, false, realmRing, true)
end

--- Reads TargetInfo after stock TargetWindow / MouseOverTargetWindow ran UpdateFromClient on PLAYER_TARGET_UPDATED.
local function ConsiderClassificationForTracking(classification)
    local ut = TargetInfo:UnitType(classification)
    if ut ~= SystemData.TargetObjectType.ENEMY_PLAYER and ut ~= SystemData.TargetObjectType.ALLY_PLAYER then
        return
    end
    local s = EnsureSettings()
    if ut == SystemData.TargetObjectType.ALLY_PLAYER and not s.showFriendly then
        return
    end
    if ut == SystemData.TargetObjectType.ENEMY_PLAYER and not s.showHostile then
        return
    end
    local wid = TargetInfo:UnitEntityId(classification)
    if wid == 0 then
        return
    end
    local pname = TargetInfo:UnitName(classification)
    pname = ToWString(pname)
    if pname == L"" then
        return
    end
    if IsSelfMember(pname) then
        return
    end
    local career = TargetInfo:UnitCareer(classification)
    LearnKnownWorldObject(pname, wid, career)
    if m_groupWorldObjs[wid] or IsGroupMemberName(pname) then
        return
    end
    TryTrackOutsider(wid, pname, career)
end

local function PruneTrackedOutsidersAgainstRoster()
    local wids = {}
    for wid, _ in pairs(m_trackWidToSlot) do
        wids[#wids + 1] = wid
    end
    for i = 1, #wids do
        local wid = wids[i]
        local meta = m_trackMeta[wid]
        local nm = meta and meta.name
        if m_groupWorldObjs[wid] or (nm and IsGroupMemberName(nm)) then
            UntrackOutsiderWid(wid)
        end
    end
end

--- AutoMark-style: probe window + MoveWindowToWorldObject for tracked outsider icons.
local function UpdateTrackedOutsiderWorldPositions()
    local probe = c_WORLD_PROBE_WINDOW
    if not DoesWindowExist(probe) then
        return
    end
    local sr = SystemData and SystemData.screenResolution
    if not sr or not sr.x or not sr.y then
        return
    end

    WindowSetShowing(probe, true)

    local reset1_anchor_x = sr.x / 2
    local reset1_anchor_y = sr.y / 2
    WindowClearAnchors(probe)
    WindowAddAnchor(probe, "topleft", "Root", "topleft", reset1_anchor_x, reset1_anchor_y)
    local reset1_actual_x, reset1_actual_y = WindowGetScreenPosition(probe)

    local reset2_anchor_x = reset1_anchor_x + 10
    local reset2_anchor_y = reset1_anchor_y + 10
    WindowClearAnchors(probe)
    WindowAddAnchor(probe, "topleft", "Root", "topleft", reset2_anchor_x, reset2_anchor_y)
    local reset2_actual_x, reset2_actual_y = WindowGetScreenPosition(probe)

    local MoveWindowToWorldObject = MoveWindowToWorldObject
    local toUntrack = {}

    for wid, idx in pairs(m_trackWidToSlot) do
        local icon = m_outsiderPool[idx]
        local win = icon and icon.windowName
        if not win or not DoesWindowExist(win) then
            toUntrack[#toUntrack + 1] = wid
        else
            WindowClearAnchors(probe)
            WindowAddAnchor(probe, "topleft", "Root", "topleft", reset1_anchor_x, reset1_anchor_y)
            MoveWindowToWorldObject(probe, wid, 1.0)

            if WindowGetShowing(probe) == false then
                WindowSetShowing(probe, true)
                WindowSetAlpha(win, 0.0)
            else
                local object_x, object_y = WindowGetScreenPosition(probe)
                if (reset1_actual_x ~= object_x) or (reset1_actual_y ~= object_y) then
                    MoveWindowToWorldObject(win, wid, 1.0)
                    WindowSetAlpha(win, 1.0)
                else
                    WindowClearAnchors(probe)
                    WindowAddAnchor(probe, "topleft", "Root", "topleft", reset2_anchor_x, reset2_anchor_y)
                    MoveWindowToWorldObject(probe, wid, 1.0)
                    object_x, object_y = WindowGetScreenPosition(probe)
                    if (reset2_actual_x ~= object_x) or (reset2_actual_y ~= object_y) then
                        MoveWindowToWorldObject(win, wid, 1.0)
                        WindowSetAlpha(win, 1.0)
                    else
                        toUntrack[#toUntrack + 1] = wid
                    end
                end
            end
        end
    end

    for i = 1, #toUntrack do
        UntrackOutsiderWid(toUntrack[i])
    end
end

local function DisableAll()
    for p = 1, c_MAX_PARTIES do
        for m = 1, c_MAX_MEMBERS do
            m_icons[p][m]:Disable()
        end
    end
end

--- Matches UnitFrames scenario detection: flags plus live scenario roster rows (RoR can lag isInScenario).
IsScenarioContext = function()
    if not GameData or not GameData.Player then
        return false
    end
    local p = GameData.Player
    if p.isInScenario == true or p.isInSiege == true then
        return true
    end
    if p.isInScenarioGroup == true then
        return true
    end
    if type(GameData.GetScenarioPlayerGroups) ~= "function" then
        return false
    end
    local pg = GameData.GetScenarioPlayerGroups()
    if type(pg) ~= "table" then
        return false
    end
    for _, pl in ipairs(pg) do
        local gi = tonumber(pl and pl.sgroupindex)
        if gi ~= nil and gi > 0 then
            return true
        end
    end
    return false
end

-- Refresh from party data (group / solo).
local function RefreshParty()
    InvalidatePartyAndWarbandCaches()
    local data = nil
    if type(PartyUtils) == "table" and type(PartyUtils.GetPartyData) == "function" then
        data = PartyUtils.GetPartyData()
    end
    if data == nil then
        data = GetGroupData()
    end
    if not data then return end
    local attachable = 0
    local validStickyKeys = {}
    for m = 1, c_MAX_MEMBERS do
        local member = GetPartySlotMember(m, data)
        local icon   = m_icons[1][m]
        local memberName = member and ToWString(member.name)
        if member and memberName ~= nil and memberName ~= L"" then
            local nk = NormalizeNameKey(member.name)
            if nk ~= nil then
                validStickyKeys[nk] = true
            end
            local liveWid = tonumber(member.worldObjNum) or 0
            local wid = ResolveRosterIconAttachWorldId(member.name, liveWid)
            RegisterGroupMember({ name = member.name, worldObjNum = (wid ~= 0 and wid) or nil })
            if wid ~= 0 and not IsSelfMember(memberName) then
                attachable = attachable + 1
            end
            if wid ~= 0 and not IsSelfMember(memberName) then
                icon:Enable()
                icon:Update(memberName, wid, member.careerLine, false, false, false)
            else
                icon:Disable()
            end
        else
            icon:Disable()
        end
    end
    PruneStickyRosterWids(validStickyKeys)
    DebugLog("RefreshParty: attachableMembers=" .. tostring(attachable))
    -- Disable unused parties.
    for p = 2, c_MAX_PARTIES do
        for m = 1, c_MAX_MEMBERS do
            m_icons[p][m]:Disable()
        end
    end
end

-- Refresh from warband data.
-- showAll = true  => show every party (full warband roster)
-- showParty1 = true => show only your own party (party index 1) even while in a warband
-- partiesOverride: when non-nil, use instead of GetBattlegroupMemberData().
local function RefreshWarband(showAll, showParty1, partiesOverride)
    InvalidatePartyAndWarbandCaches()
    local parties = partiesOverride or GetBattlegroupMemberData()
    if not parties then return end
    DebugLog("RefreshWarband: showAll=" .. tostring(showAll) .. " showParty1=" .. tostring(showParty1))
    showAll = showAll == true
    showParty1 = showParty1 == true
    local validStickyKeys = {}
    for p = 1, c_MAX_PARTIES do
        local party = parties[p]
        for m = 1, c_MAX_MEMBERS do
            local member = party and party.players and party.players[m]
            if type(PartyUtils) == "table" and type(PartyUtils.GetWarbandMember) == "function" then
                local hydrated = PartyUtils.GetWarbandMember(p, m)
                if hydrated ~= nil then
                    member = hydrated
                end
            end
            local icon   = m_icons[p][m]
            local shouldShow = showAll or (showParty1 and p == 1)
            local memberName = member and ToWString(member.name)
            if shouldShow and member and memberName ~= nil and memberName ~= L"" then
                local nk = NormalizeNameKey(member.name)
                if nk ~= nil then
                    validStickyKeys[nk] = true
                end
                local liveWid = tonumber(member.worldObjNum) or 0
                local wid = ResolveRosterIconAttachWorldId(member.name, liveWid)
                RegisterGroupMember({ name = member.name, worldObjNum = (wid ~= 0 and wid) or nil })
                if wid ~= 0 and not IsSelfMember(memberName) then
                    icon:Enable()
                    icon:Update(memberName, wid, member.careerLine, member.isGroupLeader == true, false, false)
                else
                    icon:Disable()
                end
            else
                if member then
                    RegisterGroupMember(member)
                end
                icon:Disable()
            end
        end
    end
    PruneStickyRosterWids(validStickyKeys)
end

RefreshAll = function()
    local s = EnsureSettings()
    local inScenario = IsScenarioContext()
    DebugLog("RefreshAll: inScenario=" .. tostring(inScenario)
        .. " showParty=" .. tostring(s.showParty)
        .. " showWarband=" .. tostring(s.showWarband)
        .. " showFriendly=" .. tostring(s.showFriendly)
        .. " showHostile=" .. tostring(s.showHostile)
    )
    DisableAll()
    ClearGroupMembershipCache()
    -- Scenarios use party-only roster icons (row 1); other scenario players rely on outsider tracking.
    if inScenario then
        if s.showParty then
            RefreshParty()
        end
    elseif IsWarBandActive() then
        RefreshWarband(s.showWarband == true, s.showParty == true, nil)
    elseif s.showParty then
        RefreshParty()
    end

    PruneTrackedOutsidersAgainstRoster()
end

----------------------------------------------------------------
-- Event handlers
----------------------------------------------------------------

function CustomUI.GroupIcons.OnUpdate(timePassed)
    if type(CustomUI.IsComponentEnabled) == "function" and not CustomUI.IsComponentEnabled("GroupIcons") then
        return
    end
    if next(m_pendingOutsiderClassifications) then
        local todo = m_pendingOutsiderClassifications
        m_pendingOutsiderClassifications = {}
        for cls, _ in pairs(todo) do
            ConsiderClassificationForTracking(cls)
        end
    end
    if next(m_trackWidToSlot) then
        UpdateTrackedOutsiderWorldPositions()
    end
end

function CustomUI.GroupIcons.OnGroupUpdated()
    RefreshAll()
end

function CustomUI.GroupIcons.OnBattlegroupUpdated()
    RefreshAll()
end

function CustomUI.GroupIcons.OnScenarioUpdated()
    RefreshAll()
end

function CustomUI.GroupIcons.OnZoneChanged()
    m_stickyRosterWidByKey = {}
    UntrackAllOutsiders()
    RefreshAll()
end

function CustomUI.GroupIcons.OnPlayerTargetUpdated(targetClassification, targetId, targetType)
    if targetClassification ~= c_HOSTILE_TARGET
        and targetClassification ~= c_FRIENDLY_TARGET
        and targetClassification ~= c_MOUSEOVER_TARGET
    then
        return
    end
    -- Defer to OnUpdate: avoid calling TargetInfo:UpdateFromClient() here (second caller gets nil and ClearUnits()).
    -- Stock ea_targetwindow / ea_mouseovertargetwindow refresh TargetInfo during this event first.
    m_pendingOutsiderClassifications[targetClassification] = true
end

function CustomUI.GroupIcons.OnSettingsChanged()
    -- Hostile/friendly toggles can invalidate existing tracked outsiders; clear them.
    UntrackAllOutsiders()
    RefreshAll()
end

----------------------------------------------------------------
-- Component adapter
----------------------------------------------------------------

local GroupIconsComponent = {}

function GroupIconsComponent:Initialize()
    for p = 1, c_MAX_PARTIES do
        m_icons[p] = {}
        for m = 1, c_MAX_MEMBERS do
            m_icons[p][m] = GroupIcon.New(p, m)
        end
    end
    for i = 1, c_MAX_TRACKED_OUTSIDERS do
        m_outsiderPool[i] = GroupIcon.New(96, i)
    end
    EnsureSettings()
    return true
end

function GroupIconsComponent:Enable()
    WindowRegisterEventHandler("Root", SystemData.Events.GROUP_UPDATED,           "CustomUI.GroupIcons.OnGroupUpdated")
    WindowRegisterEventHandler("Root", SystemData.Events.GROUP_STATUS_UPDATED,    "CustomUI.GroupIcons.OnGroupUpdated")
    WindowRegisterEventHandler("Root", SystemData.Events.GROUP_PLAYER_ADDED,      "CustomUI.GroupIcons.OnGroupUpdated")
    WindowRegisterEventHandler("Root", SystemData.Events.BATTLEGROUP_UPDATED,     "CustomUI.GroupIcons.OnBattlegroupUpdated")
    WindowRegisterEventHandler("Root", SystemData.Events.BATTLEGROUP_MEMBER_UPDATED, "CustomUI.GroupIcons.OnBattlegroupUpdated")
    WindowRegisterEventHandler("Root", SystemData.Events.SCENARIO_GROUP_UPDATED,  "CustomUI.GroupIcons.OnScenarioUpdated")
    WindowRegisterEventHandler("Root", SystemData.Events.SCENARIO_PLAYERS_LIST_GROUPS_UPDATED, "CustomUI.GroupIcons.OnScenarioUpdated")
    WindowRegisterEventHandler("Root", SystemData.Events.SCENARIO_BEGIN, "CustomUI.GroupIcons.OnScenarioUpdated")
    WindowRegisterEventHandler("Root", SystemData.Events.SCENARIO_END, "CustomUI.GroupIcons.OnScenarioUpdated")
    WindowRegisterEventHandler("Root", SystemData.Events.CITY_SCENARIO_BEGIN, "CustomUI.GroupIcons.OnScenarioUpdated")
    WindowRegisterEventHandler("Root", SystemData.Events.CITY_SCENARIO_END, "CustomUI.GroupIcons.OnScenarioUpdated")
    WindowRegisterEventHandler("Root", SystemData.Events.PLAYER_ZONE_CHANGED,     "CustomUI.GroupIcons.OnZoneChanged")
    WindowRegisterEventHandler("Root", SystemData.Events.PLAYER_TARGET_UPDATED,    "CustomUI.GroupIcons.OnPlayerTargetUpdated")
    if DoesWindowExist(c_GROUPICONS_DRIVER) then
        WindowSetShowing(c_GROUPICONS_DRIVER, true)
    end
    RefreshAll()
    return true
end

function GroupIconsComponent:Disable()
    WindowUnregisterEventHandler("Root", SystemData.Events.GROUP_UPDATED)
    WindowUnregisterEventHandler("Root", SystemData.Events.GROUP_STATUS_UPDATED)
    WindowUnregisterEventHandler("Root", SystemData.Events.GROUP_PLAYER_ADDED)
    WindowUnregisterEventHandler("Root", SystemData.Events.BATTLEGROUP_UPDATED)
    WindowUnregisterEventHandler("Root", SystemData.Events.BATTLEGROUP_MEMBER_UPDATED)
    WindowUnregisterEventHandler("Root", SystemData.Events.SCENARIO_GROUP_UPDATED)
    WindowUnregisterEventHandler("Root", SystemData.Events.SCENARIO_PLAYERS_LIST_GROUPS_UPDATED)
    WindowUnregisterEventHandler("Root", SystemData.Events.SCENARIO_BEGIN)
    WindowUnregisterEventHandler("Root", SystemData.Events.SCENARIO_END)
    WindowUnregisterEventHandler("Root", SystemData.Events.CITY_SCENARIO_BEGIN)
    WindowUnregisterEventHandler("Root", SystemData.Events.CITY_SCENARIO_END)
    WindowUnregisterEventHandler("Root", SystemData.Events.PLAYER_ZONE_CHANGED)
    WindowUnregisterEventHandler("Root", SystemData.Events.PLAYER_TARGET_UPDATED)
    if DoesWindowExist(c_GROUPICONS_DRIVER) then
        WindowSetShowing(c_GROUPICONS_DRIVER, false)
    end
    m_pendingOutsiderClassifications = {}
    DisableAll()
    UntrackAllOutsiders()
end

function GroupIconsComponent:Shutdown()
    self:Disable()
end

--- Same RGB as roster ring tint (archetype palette vs green vs gray per GroupIcons settings). For UnitFrames name labels.
function CustomUI.GroupIcons.GetArchetypeTintRgbForCareerLine(careerLine)
    local r, g, b = GroupRingRgbForCareerLine(tonumber(careerLine))
    return r, g, b
end

CustomUI.RegisterComponent("GroupIcons", GroupIconsComponent)
