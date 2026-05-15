----------------------------------------------------------------
-- CustomUI.GroupIcons — Controller
--
-- View: GroupIcons.xml (templates + OnUpdate driver/probe only); controller owns all logic.
-- Load order: CustomUI.mod lists this script before the XML so handlers exist at parse time.
--
-- Behavior overview:
--   • Roster (party row 1, open-world warband 4×6): career icon + ring on member worldObjNum.
--     Scenario with Scenario checkbox ON: roster grid only for *your* scenario party (sgroupindex match); other scenario parties use outsider tracking with Friendly/Hostile gates — rings match roster style when Scenario enabled else realm blue/red.
--     Self is skipped. Crown + orange-gold ring on group leader (party row or warband grid; scenario roster omits crown); leader slot drawn at 1.5× scale.
--     Rings use full archetype (or all-green) tint for every roster member; leader still uses c_LEADER_RING_RGB.
--   • Roster attach requires a live worldObjNum this refresh (party slot / scenario roster optional scenarioWorldObjNum).
--     Cached ids refine LearnKnown when live wid is 0 (distant / unloaded row); zone change clears caches.
--     Outsiders: FIFO when full; same AutoMark-style spatial wid probe as roster (below) + window/name checks.
--     Roster: spatial probe; if wid projects as “gone” for several consecutive ticks, squash+hide (Enemy ObjectWindows) until valid again — mitigates top-left stuck attach without probe-boundary flicker.
--   • Outsiders (non-own-roster players incl. other scenario parties): hostile / friendly / mouseover PLAYER_TARGET_UPDATED → deferred TargetInfo read;
--     FIFO pool (c_MAX_TRACKED_OUTSIDERS); realm-tint rings in scenario when Scenario checkbox OFF, archetype roster-style rings when ON (+ Friendly/Hostile toggles unchanged).
--   • Names: NormalizeNameKey (strip caret grammar, lowercase) for PartyUtils / scenario / roster dedupe.
--   • Driver + CustomUIGroupIconsWorldProbe: shared AutoMark-style spatial check for outsiders and roster.
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

-- Archetype ring colors (all warband/party rows use the same full palette; leader uses c_LEADER_RING_RGB).
local c_ARCHETYPE_TANK  = 1
local c_ARCHETYPE_DPS   = 2
local c_ARCHETYPE_HEAL  = 3
local c_ARCHETYPE_RGB = {
    [c_ARCHETYPE_TANK] = { 140, 178, 255 },
    [c_ARCHETYPE_DPS]  = { 255, 176, 82 },
    [c_ARCHETYPE_HEAL] = { 175, 255, 90 },
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
-- Eviction skips entity IDs currently shown as hostile or friendly **player** targets (TargetInfo) so the
-- ring for your active target is not dropped when many other outsiders stream through (Low #18).
local c_MAX_TRACKED_OUTSIDERS = 48
-- World-attach probe tick: outsiders (untrack) + roster (Enemy-style hide if spatial “gone”).
local c_OUTSIDER_PROBE_INTERVAL = 0.2
-- Roster: if fallback entity id was recycled to another player, GetNameForObject shows wrong non-empty name — recheck slowly.
local c_ROSTER_WID_VALIDATE_INTERVAL = 1.5
local c_GROUPICONS_DRIVER = "CustomUIGroupIconsDriver"
-- Minimal window: MoveWindowToWorldObject + screen position — detects dead wid without GetNameForObject timers (see AutoMark addon).
local c_GROUPICONS_WORLD_PROBE = "CustomUIGroupIconsWorldProbe"
local c_WORLD_PROBE_ATTACH_Z = 1.0
-- Roster spatial hide only after this many consecutive probe intervals (~0.2s each) reporting “gone” — avoids flicker when projection flickers at boundaries.
local c_ROSTER_SPATIAL_GONE_STREAK = 4

-- Realm ring RGB (outsider targets); archetype colors stay on group members.
local c_REALM_RING_ORDER  = { 0, 0, 255 }
local c_REALM_RING_DEST   = { 255, 0, 0 }
local c_RING_GREEN        = { 0, 255, 0 } -- roster when archetypeColors off
-- Party/warband leader roster ring (overrides archetype / green-off palette).
local c_LEADER_RING_RGB     = { 255, 185, 55 }

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
-- Roster ring uses geometric center (top↔bottom); no atlas X nudge — −2px (PlayerStatus/UnitFrames) reads left here at 48× ring scale.
local c_CROWN_ANCHOR_OPTICAL_OFFSET_X = 0
-- Base vertical tuck (matches UnitFrames crown vs atlas height budget); GroupIcons applies ring scale below.
local c_CROWN_ANCHOR_TOUCH_OFFSET_Y = 5
-- UnitFrames CustomUIBGMember CareerIconRing outer px — ratio vs c_RING_SIZE scales tuck for larger roster geometry (sync UnitFramesController.c_UF_CAREER_RING_OUTER).
local c_UF_RING_OUTER_REF = 42
local c_OFFSET_Y     = 50   -- gap below the frame toward world attach; outer height = c_OFFSET_Y + framePx (GroupIconLayoutPixels)
-- Party/warband leader: +50% linear size on icon, ring, crown (scale 1.5).
local c_LEADER_VISUAL_SCALE = 1.5

--- @return framePx, iconPx, ringPx, crownW, crownH, outerH
local function GroupIconLayoutPixels( showWarbandCrown )
    local scale = ( showWarbandCrown == true ) and c_LEADER_VISUAL_SCALE or 1.0
    local framePx = math.max( 1, math.floor( c_FRAME_SIZE * scale + 0.5 ) )
    local iconPx  = math.max( 1, math.floor( c_ICON_DRAW * scale + 0.5 ) )
    local ringPx  = math.max( 1, math.floor( c_RING_SIZE * scale + 0.5 ) )
    local crownW  = math.max( 1, math.floor( c_CROWN_TEX_W * scale + 0.5 ) )
    local crownH  = math.max( 1, math.floor( c_CROWN_TEX_H * scale + 0.5 ) )
    local outerH  = c_OFFSET_Y + framePx
    return framePx, iconPx, ringPx, crownW, crownH, outerH
end

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
    self.lastRingTintKey = nil -- "archetype" | "leader" | "realm:r,g,b"
    -- Roster slots only (partyIndex 1..6): hide stuck world-attached UI without Destroy (Enemy ObjectWindows pattern).
    self.rosterSpatialHidden = false
    self.rosterSavedWorldAttachScale = nil
    self.rosterSpatialGoneStreak = 0
    return self
end

function GroupIcon:_windowName()
    return "CustomUIGroupIcon_" .. self.partyIndex .. "_" .. self.memberIndex
end

function GroupIcon:Attach(name, worldObjNum, careerLine, showWarbandCrown, useRealmRingTint, careerNamesId)
    self:_detach()

    showWarbandCrown = showWarbandCrown == true
    useRealmRingTint = useRealmRingTint == true
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
    local framePx, iconPx, ringPx, crownW, crownH, outerH = GroupIconLayoutPixels( showWarbandCrown )
    if WindowSetDimensions and DoesWindowExist( base ) then
        WindowSetDimensions( base, framePx, outerH )
        WindowSetDimensions( content, framePx, framePx )
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
    elseif showWarbandCrown then
        rr, gg, bb = c_LEADER_RING_RGB[1], c_LEADER_RING_RGB[2], c_LEADER_RING_RGB[3]
        self.lastRingTintKey = "leader"
    else
        rr, gg, bb, self.lastRingTintKey = GroupRingRgbForCareerLine(careerLine)
    end
    WindowSetTintColor(ringWin, rr, gg, bb)
    self.lastCareerLine = careerLine
    self.lastCareerNamesId = careerNamesId

    WindowClearAnchors(iconWin)
    WindowAddAnchor(iconWin, "center", content, "center", 0, 0)
    WindowSetDimensions(iconWin, iconPx, iconPx)

    WindowClearAnchors(ringWin)
    WindowAddAnchor(ringWin, "center", content, "center", 0, 0)
    WindowSetDimensions(ringWin, ringPx, ringPx)

    WindowClearAnchors(crownWin)
    WindowSetDimensions(crownWin, crownW, crownH)
    DynamicImageSetTexture(crownWin, c_CROWN_TEXTURE, c_CROWN_TEX_X, c_CROWN_TEX_Y)
    DynamicImageSetTextureDimensions(crownWin, c_CROWN_TEX_W, c_CROWN_TEX_H)
    -- README §Notes: Point on target (ring), RelativePoint on anchored crown → ring.top meets crown.bottom.
    local crownTouchY = math.max(1, math.floor(c_CROWN_ANCHOR_TOUCH_OFFSET_Y * ringPx / c_UF_RING_OUTER_REF + 0.5))
    WindowAddAnchor(crownWin, "top", ringWin, "bottom", c_CROWN_ANCHOR_OPTICAL_OFFSET_X, crownTouchY)
    WindowSetShowing(crownWin, showWarbandCrown)
    self.lastWarbandCrown = showWarbandCrown

    WindowSetShowing(base, true)
    self.rosterSpatialHidden = false
    self.rosterSavedWorldAttachScale = nil
    self.rosterSpatialGoneStreak = 0
    AttachWindowToWorldObject(self.windowName, worldObjNum)
end

--- Party/warband roster only: engine often won't hide world-attached windows; squash like Enemy ObjectWindows:Deactivate.
function GroupIcon:RosterSpatialHide()
    if self.partyIndex > c_MAX_PARTIES then
        return
    end
    if self.rosterSpatialHidden then
        return
    end
    local win = self.windowName
    if not win or not DoesWindowExist(win) then
        return
    end
    if type(WindowGetScale) == "function" then
        self.rosterSavedWorldAttachScale = WindowGetScale(win)
    end
    if WindowSetScale then
        WindowSetScale(win, 0.000001)
    end
    WindowSetShowing(win, false)
    self.rosterSpatialHidden = true
end

function GroupIcon:RosterSpatialShow()
    if not self.rosterSpatialHidden then
        return
    end
    local win = self.windowName
    if not win or not DoesWindowExist(win) then
        self.rosterSpatialHidden = false
        self.rosterSavedWorldAttachScale = nil
        return
    end
    local sc = self.rosterSavedWorldAttachScale
    if sc ~= nil and WindowSetScale then
        WindowSetScale(win, sc)
    elseif WindowSetScale then
        WindowSetScale(win, 1.0)
    end
    WindowSetShowing(win, true)
    self.rosterSpatialHidden = false
    self.rosterSavedWorldAttachScale = nil
    self.rosterSpatialGoneStreak = 0
end

function GroupIcon:_detach()
    if not self.windowName then return end
    local wid = self.worldObjNum
    if wid ~= 0 then
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
    self.rosterSpatialHidden = false
    self.rosterSavedWorldAttachScale = nil
    self.rosterSpatialGoneStreak = 0
end

function GroupIcon:Update(name, worldObjNum, careerLine, showWarbandCrown, useRealmRingTint, careerNamesId)
    if not self.isEnabled then return end
    showWarbandCrown = showWarbandCrown == true
    useRealmRingTint = useRealmRingTint == true
    careerNamesId = tonumber(careerNamesId)
    local wantRingKey = "archetype"
    if useRealmRingTint then
        local r, g, b = RealmRingRgbForCareerLine(careerLine)
        wantRingKey = string.format("realm:%d,%d,%d", r, g, b)
    elseif showWarbandCrown then
        wantRingKey = "leader"
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
    then
        WindowSetShowing(crownWin, showWarbandCrown)
        self.lastWarbandCrown = showWarbandCrown
        return
    end
    -- Re-attach if the player, world object, career (ring / icon), warband crown, or ring tint mode changed.
    if not self.windowName
        or self.playerName   ~= name
        or self.worldObjNum  ~= worldObjNum
        or self.lastCareerLine ~= careerLine
        or self.lastCareerNamesId ~= careerNamesId
        or self.lastWarbandCrown ~= showWarbandCrown
        or self.lastRingTintKey ~= wantRingKey
    then
        self:Attach(name, worldObjNum, careerLine, showWarbandCrown, useRealmRingTint, careerNamesId)
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
local m_trackMeta = {}          -- [worldObjNum] = { name = WString } (outsiders)
local m_trackFIFOOrder = {}     -- array of worldObjNum; index 1 = oldest (evicted first when full)
local m_pendingOutsiderClassifications = {} -- TargetInfo classifications to apply next OnUpdate (avoid UpdateFromClient + handler order)
local m_outsiderProbeElapsed = 0
local m_rosterValidateElapsed = 0
local m_groupWorldObjs = {}    -- [worldObjNum] = true for roster (party/warband)
local m_groupNames = {}        -- [playerName] = true (fast path when exact match works)
local m_groupNameList = {}     -- { WString, ... } robust compare via WStringsCompareIgnoreGrammer

-- Debounce group roster rebuilds: GROUP_STATUS_UPDATED can spam and recreating all windows flickers.
local m_needsRefreshAll = false

-- After /reloadui, warband worldObj ids often arrive shortly after Initialize; synchronous RefreshAll in Enable
-- can attach with wid=0 (no marker) until BATTLEGROUP_* fires — stock BattlegroupHUD defers to OnUpdate instead.
local m_postEnableWarmRefreshPoll = 0
local m_postEnableWarmRefreshRemaining = 0

-- Cached probe calibration; can be nil briefly during load or resolution transitions.
local m_worldProbeCalibration = nil
local m_worldProbeResolutionKey = nil

-- Known player worldObj ids by normalized name key (learned from PartyUtils + TargetInfo).
-- { [key] = { wid = number, careerLine = number|nil, t = number|nil } }
local m_knownByNameKey = {}

-- Last known worldObjNum per name (targeting + live party/warband when non-zero). Used when roster row wid is 0.
-- Cleared on zone change with sticky map.
local m_stickyRosterWidByKey = {}

local m_debugLastSig = nil


local function DebugLog(msg)
    if CustomUI.DebugLogging ~= true then
        return
    end
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

--- Prefer live worldObjNum from PartyUtils / battlegroup row. When it is 0 (member out of stream range,
--- status not merged yet, or joined warband while distant), fall back to last known entity id from
--- targeting (`m_knownByNameKey`) or an earlier refresh (`m_stickyRosterWidByKey`). Live non-zero always wins.
local function ResolveRosterIconAttachWorldId(nameW, liveWidFromData)
    local w = tonumber(liveWidFromData) or 0
    if w ~= 0 then
        RememberStickyRosterWid(nameW, w)
        return w
    end
    local key = NormalizeNameKey(nameW)
    if key == nil then
        return 0
    end
    local kn = m_knownByNameKey[key]
    local kw = kn and tonumber(kn.wid) or 0
    if kw ~= 0 then
        RememberStickyRosterWid(nameW, kw)
        return kw
    end
    local sw = tonumber(m_stickyRosterWidByKey[key]) or 0
    if sw ~= 0 then
        return sw
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

--- Empty / failed GetNameForObject ⇒ keep attach (distant / streaming). Non-empty mismatch ⇒ entity id recycled / wrong attach.
local function RosterWorldObjectNameMatchesPlayer(wid, expectedNameW)
    if wid == nil or wid == 0 or type(GetNameForObject) ~= "function" then
        return true
    end
    local ok, nm = pcall(GetNameForObject, wid)
    if not ok or nm == nil then
        return true
    end
    local w = ToWString(nm)
    if w == nil or w == L"" then
        return true
    end
    return SafeWStringEquals(w, ToWString(expectedNameW))
end

local function ClearStickyAndKnownWidForEntity(key, badWid)
    if key == nil then
        return
    end
    local bw = tonumber(badWid) or 0
    if bw == 0 then
        return
    end
    local sw = tonumber(m_stickyRosterWidByKey[key]) or 0
    if sw == bw then
        m_stickyRosterWidByKey[key] = nil
    end
    local kn = m_knownByNameKey[key]
    if kn and tonumber(kn.wid) == bw then
        m_knownByNameKey[key] = nil
    end
end

local function ValidateRosterIconWorldObjects()
    for p = 1, c_MAX_PARTIES do
        for m = 1, c_MAX_MEMBERS do
            local icon = m_icons[p][m]
            if icon.isEnabled and icon.worldObjNum ~= 0 and icon.playerName then
                local wid = icon.worldObjNum
                if not RosterWorldObjectNameMatchesPlayer(wid, icon.playerName) then
                    local key = NormalizeNameKey(icon.playerName)
                    ClearStickyAndKnownWidForEntity(key, wid)
                    icon:Update(icon.playerName, 0, icon.lastCareerLine, false, false, icon.lastCareerNamesId)
                end
            end
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

--- Entity world ids for targets currently populated in TargetInfo (non-empty name). Used to avoid evicting
--- those outsider rings when the FIFO pool is full.
local function BuildActiveTargetEntityIdGuard()
    local guard = {}
    if not TargetInfo then
        return guard
    end
    local function addIfPlayerSlot(unitId)
        if not unitId then
            return
        end
        if TargetInfo:UnitName(unitId) == L"" then
            return
        end
        local ut = TargetInfo:UnitType(unitId)
        if ut ~= SystemData.TargetObjectType.ENEMY_PLAYER and ut ~= SystemData.TargetObjectType.ALLY_PLAYER then
            return
        end
        local e = TargetInfo:UnitEntityId(unitId)
        if e and e ~= 0 then
            guard[e] = true
        end
    end
    addIfPlayerSlot(TargetInfo.HOSTILE_TARGET)
    addIfPlayerSlot(TargetInfo.FRIENDLY_TARGET)
    return guard
end

local function PickOutsiderFifoEvictionVictim(protected)
    for i = 1, #m_trackFIFOOrder do
        local wid = m_trackFIFOOrder[i]
        if not protected[wid] then
            return wid
        end
    end
    return nil
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
    m_outsiderProbeElapsed = 0
    m_rosterValidateElapsed = 0
end

local function TryTrackOutsider(wid, pname, career)
    if not wid or wid == 0 then
        return
    end
    local realmRing = true
    -- Run before the "already tracking this wid" branch: roster membership can flip without recycling ids.
    if m_groupWorldObjs[wid] or IsGroupMemberName(pname) then
        if m_trackWidToSlot[wid] then
            UntrackOutsiderWid(wid)
        end
        return
    end
    if m_trackWidToSlot[wid] then
        local idx = m_trackWidToSlot[wid]
        local icon = m_outsiderPool[idx]
        icon:Enable()
        icon:Update(pname, wid, career, false, realmRing)
        m_trackMeta[wid] = { name = pname }
        m_outsiderProbeElapsed = c_OUTSIDER_PROBE_INTERVAL
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
        local protected = BuildActiveTargetEntityIdGuard()
        local victim = PickOutsiderFifoEvictionVictim(protected)
        if victim == nil then
            -- Only if every FIFO entry matches a protected target id (e.g. stale FIFO); evict oldest.
            victim = m_trackFIFOOrder[1]
        end
        if victim ~= nil then
            UntrackOutsiderWid(victim)
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
    icon:Update(pname, wid, career, false, realmRing)
    m_outsiderProbeElapsed = c_OUTSIDER_PROBE_INTERVAL
end

--- Fill party/warband name + worldObj registry so outsider prune/TryTrack gates work even when roster *icons*
--- are not refreshed (scenario + showParty off, etc.).
local function RegisterAllPartyWarbandMembersForPruning()
    InvalidatePartyAndWarbandCaches()
    ClearGroupMembershipCache()
    local data = nil
    if type(PartyUtils) == "table" and type(PartyUtils.GetPartyData) == "function" then
        data = PartyUtils.GetPartyData()
    end
    if data == nil then
        data = GetGroupData()
    end
    if type(data) == "table" then
        for m = 1, c_MAX_MEMBERS do
            local member = GetPartySlotMember(m, data)
            if member and member.name then
                local liveWid = tonumber(member.worldObjNum) or 0
                local wid = ResolveRosterIconAttachWorldId(member.name, liveWid)
                RegisterGroupMember({ name = member.name, worldObjNum = (wid ~= 0 and wid) or nil })
            end
        end
    end
    if IsWarBandActive() then
        local parties = GetBattlegroupMemberData()
        if type(parties) == "table" then
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
                    if member and member.name then
                        local liveWid = tonumber(member.worldObjNum) or 0
                        local wid = ResolveRosterIconAttachWorldId(member.name, liveWid)
                        RegisterGroupMember({ name = member.name, worldObjNum = (wid ~= 0 and wid) or nil })
                    end
                end
            end
        end
    end
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

--- True when GetNameForObject returns a **non-empty** other player’s name for this wid (entity id recycled).
local function OutsiderWorldObjectNameMismatchTracked(trackedNameW, wid)
    if wid == nil or wid == 0 or type(GetNameForObject) ~= "function" then
        return false
    end
    local ok, nm = pcall(GetNameForObject, wid)
    if not ok or nm == nil then
        return false
    end
    local w = ToWString(nm)
    if w == nil or w == L"" then
        return false
    end
    return not SafeWStringEquals(w, ToWString(trackedNameW))
end

--- Anchor calibration for two probe points (same idea as AutoMark.OnUpdate).
local function CalibrateGroupIconsWorldProbeAnchors()
    local probe = c_GROUPICONS_WORLD_PROBE
    if not DoesWindowExist(probe)
        or type(MoveWindowToWorldObject) ~= "function"
        or type(WindowGetScreenPosition) ~= "function"
        or type(WindowClearAnchors) ~= "function"
        or type(WindowAddAnchor) ~= "function"
    then
        return nil
    end
    local res = SystemData and SystemData.screenResolution
    if not res or res.x == nil or res.y == nil then
        return nil
    end
    WindowSetShowing(probe, true)
    local ax = res.x / 2
    local ay = res.y / 2
    WindowClearAnchors(probe)
    WindowAddAnchor(probe, "topleft", "Root", "topleft", ax, ay)
    local r1x, r1y = WindowGetScreenPosition(probe)
    local ax2 = ax + 10
    local ay2 = ay + 10
    WindowClearAnchors(probe)
    WindowAddAnchor(probe, "topleft", "Root", "topleft", ax2, ay2)
    local r2x, r2y = WindowGetScreenPosition(probe)
    return {
        ax = ax, ay = ay,
        ax2 = ax2, ay2 = ay2,
        r1x = r1x, r1y = r1y,
        r2x = r2x, r2y = r2y,
    }
end

local function GetWorldProbeCalibration()
    local res = SystemData and SystemData.screenResolution
    local key = res and res.x and res.y and (tostring(res.x) .. "x" .. tostring(res.y)) or nil
    if key ~= nil and key == m_worldProbeResolutionKey and m_worldProbeCalibration ~= nil then
        return m_worldProbeCalibration
    end
    local cal = CalibrateGroupIconsWorldProbeAnchors()
    if cal ~= nil then
        m_worldProbeCalibration = cal
        m_worldProbeResolutionKey = key
    end
    return cal
end

--- True if world object id no longer drives UI projection (static/stuck icon symptom). False if probe unavailable.
--- Hidden probe after move ⇒ entity exists off-screen (not gone). Two-anchor non-move ⇒ gone (AutoMark disambiguation).
local function WorldObjectSpatialProbeIsGone(wid, cal)
    if cal == nil or wid == nil or wid == 0 then
        return false
    end
    local probe = c_GROUPICONS_WORLD_PROBE
    if type(WindowGetShowing) ~= "function" then
        return false
    end
    WindowClearAnchors(probe)
    WindowAddAnchor(probe, "topleft", "Root", "topleft", cal.ax, cal.ay)
    MoveWindowToWorldObject(probe, wid, c_WORLD_PROBE_ATTACH_Z)
    if WindowGetShowing(probe) == false then
        WindowSetShowing(probe, true)
        return false
    end
    local ox, oy = WindowGetScreenPosition(probe)
    if cal.r1x ~= ox or cal.r1y ~= oy then
        return false
    end
    WindowClearAnchors(probe)
    WindowAddAnchor(probe, "topleft", "Root", "topleft", cal.ax2, cal.ay2)
    MoveWindowToWorldObject(probe, wid, c_WORLD_PROBE_ATTACH_Z)
    ox, oy = WindowGetScreenPosition(probe)
    if cal.r2x ~= ox or cal.r2y ~= oy then
        return false
    end
    return true
end

local function ValidateTrackedOutsiders(cal)
    if not next(m_trackWidToSlot) then
        return
    end
    if cal == nil then
        cal = CalibrateGroupIconsWorldProbeAnchors()
    end
    local toUntrack = {}
    for wid, idx in pairs(m_trackWidToSlot) do
        local icon = m_outsiderPool[idx]
        local win = icon and icon.windowName
        if not win or not DoesWindowExist(win) then
            toUntrack[#toUntrack + 1] = wid
        else
            local meta = m_trackMeta[wid]
            local nm = meta and meta.name
            if nm == nil or nm == L"" then
                toUntrack[#toUntrack + 1] = wid
            elseif OutsiderWorldObjectNameMismatchTracked(nm, wid) then
                toUntrack[#toUntrack + 1] = wid
            elseif cal and WorldObjectSpatialProbeIsGone(wid, cal) then
                toUntrack[#toUntrack + 1] = wid
            end
        end
    end
    for i = 1, #toUntrack do
        UntrackOutsiderWid(toUntrack[i])
    end
end

local function AnyRosterWorldAttachedIcons()
    for p = 1, c_MAX_PARTIES do
        for m = 1, c_MAX_MEMBERS do
            local icon = m_icons[p][m]
            if icon.isEnabled and icon.worldObjNum ~= 0 and icon.windowName and DoesWindowExist(icon.windowName) then
                return true
            end
        end
    end
    return false
end

--- True when settings allow party/warband roster world markers (not outsiders-only).
local function WantRosterWorldMarkers()
    local s = EnsureSettings()
    return s.showParty == true or s.showWarband == true
end

local function WarmRefreshWarbandIfNeeded(dt)
    if m_postEnableWarmRefreshRemaining <= 0 then
        return
    end
    local function activeWarbandNotScenario()
        if type(IsWarBandActive) ~= "function" then
            return false
        end
        return IsWarBandActive() == true and not IsScenarioContext()
    end
    if not activeWarbandNotScenario() or not WantRosterWorldMarkers() then
        return
    end
    if AnyRosterWorldAttachedIcons() then
        m_postEnableWarmRefreshRemaining = 0
        m_postEnableWarmRefreshPoll = 0
        return
    end
    m_postEnableWarmRefreshPoll = (m_postEnableWarmRefreshPoll or 0) + dt
    if m_postEnableWarmRefreshPoll >= 0.35 then
        m_postEnableWarmRefreshPoll = 0
        m_postEnableWarmRefreshRemaining = m_postEnableWarmRefreshRemaining - 1
        m_needsRefreshAll = true
    end
end

--- Same spatial probe as outsiders: hide stuck roster icons (Enemy squash) until wid projects again.
--- Debounce hide: a single flaky “gone” tick was toggling hide/show every 0.2s (top-left flicker).
local function ValidateRosterIconsSpatial(cal)
    if cal == nil then
        return
    end
    for p = 1, c_MAX_PARTIES do
        for m = 1, c_MAX_MEMBERS do
            local icon = m_icons[p][m]
            if icon.isEnabled and icon.worldObjNum ~= 0 and icon.windowName and DoesWindowExist(icon.windowName) then
                if WorldObjectSpatialProbeIsGone(icon.worldObjNum, cal) then
                    icon.rosterSpatialGoneStreak = (tonumber(icon.rosterSpatialGoneStreak) or 0) + 1
                    if icon.rosterSpatialGoneStreak >= c_ROSTER_SPATIAL_GONE_STREAK then
                        icon:RosterSpatialHide()
                    end
                else
                    icon.rosterSpatialGoneStreak = 0
                    icon:RosterSpatialShow()
                end
            end
        end
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
                icon:Update(memberName, wid, member.careerLine, member.isGroupLeader == true, false)
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
-- (Other warband parties must not be RegisterGroupMember when hidden, or outsider realm icons never apply.)
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
                    icon:Update(memberName, wid, member.careerLine, member.isGroupLeader == true, false)
                else
                    icon:Disable()
                end
            else
                -- Party-only warband: members of other parties are not on the roster grid. Do not mark them
                -- as group roster or outsider tracking will never attach realm-ring icons (blue/red).
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
    RegisterAllPartyWarbandMembersForPruning()
    -- Scenarios use party-only roster icons (row 1); other scenario players rely on outsider tracking.
    if inScenario then
        if s.showParty then
            RefreshParty()
        end
    elseif IsWarBandActive() then
        RefreshWarband(s.showWarband == true, s.showParty == true, nil)
    elseif s.showParty then
        RefreshParty()
    else
        -- No roster view in this context; ensure all roster slots are disabled.
        DisableAll()
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
    local dt = tonumber(timePassed) or 0

    if m_needsRefreshAll then
        m_needsRefreshAll = false
        RefreshAll()
    end

    if next(m_pendingOutsiderClassifications) then
        RegisterAllPartyWarbandMembersForPruning()
        local todo = m_pendingOutsiderClassifications
        m_pendingOutsiderClassifications = {}
        for cls, _ in pairs(todo) do
            ConsiderClassificationForTracking(cls)
        end
        PruneTrackedOutsidersAgainstRoster()
    end
    WarmRefreshWarbandIfNeeded(dt)

    local needsWorldProbe = next(m_trackWidToSlot) ~= nil or AnyRosterWorldAttachedIcons()
    if needsWorldProbe then
        m_outsiderProbeElapsed = m_outsiderProbeElapsed + dt
        if m_outsiderProbeElapsed >= c_OUTSIDER_PROBE_INTERVAL then
            m_outsiderProbeElapsed = 0
            local cal = GetWorldProbeCalibration()
            if next(m_trackWidToSlot) then
                ValidateTrackedOutsiders(cal)
            end
            local hasRosterAttached = AnyRosterWorldAttachedIcons()
            if cal ~= nil and hasRosterAttached then
                ValidateRosterIconsSpatial(cal)
            end
        end
    else
        m_outsiderProbeElapsed = 0
    end
    m_rosterValidateElapsed = m_rosterValidateElapsed + dt
    if m_rosterValidateElapsed >= c_ROSTER_WID_VALIDATE_INTERVAL then
        m_rosterValidateElapsed = 0
        ValidateRosterIconWorldObjects()
    end
end

function CustomUI.GroupIcons.OnGroupUpdated()
    m_needsRefreshAll = true
end

function CustomUI.GroupIcons.OnBattlegroupUpdated()
    m_needsRefreshAll = true
end

function CustomUI.GroupIcons.OnScenarioUpdated()
    m_needsRefreshAll = true
end

function CustomUI.GroupIcons.OnZoneChanged()
    m_stickyRosterWidByKey = {}
    m_knownByNameKey = {}
    UntrackAllOutsiders()
    m_worldProbeCalibration = nil
    m_worldProbeResolutionKey = nil
    m_needsRefreshAll = true
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
    -- Settings tab may change Party/Warband/etc. while the component is disabled; never RefreshAll then or
    -- icons would attach (handlers are unregistered but this path is called directly from settings UI).
    if type(CustomUI.IsComponentEnabled) == "function" and not CustomUI.IsComponentEnabled("GroupIcons") then
        return
    end
    -- Hostile/friendly toggles can invalidate existing tracked outsiders; clear them.
    UntrackAllOutsiders()
    m_worldProbeCalibration = nil
    m_worldProbeResolutionKey = nil
    m_needsRefreshAll = true
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
    WindowRegisterEventHandler("Root", SystemData.Events.LOADING_END,             "CustomUI.GroupIcons.OnBattlegroupUpdated")
    WindowRegisterEventHandler("Root", SystemData.Events.ENTER_WORLD,             "CustomUI.GroupIcons.OnBattlegroupUpdated")
    if DoesWindowExist(c_GROUPICONS_DRIVER) then
        WindowSetShowing(c_GROUPICONS_DRIVER, true)
    end
    -- First tick after Enable re-runs roster attach (fixes warband stale wids right after /reloadui).
    m_needsRefreshAll = true
    m_postEnableWarmRefreshPoll = 0
    m_postEnableWarmRefreshRemaining = 0
    if WantRosterWorldMarkers() then
        -- Until at least one world-attached roster icon appears or attempts exhaust (~3s).
        m_postEnableWarmRefreshRemaining = 9
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
    WindowUnregisterEventHandler("Root", SystemData.Events.LOADING_END)
    WindowUnregisterEventHandler("Root", SystemData.Events.ENTER_WORLD)
    if DoesWindowExist(c_GROUPICONS_DRIVER) then
        WindowSetShowing(c_GROUPICONS_DRIVER, false)
    end
    m_postEnableWarmRefreshRemaining = 0
    m_postEnableWarmRefreshPoll = 0
    m_pendingOutsiderClassifications = {}
    DisableAll()
    UntrackAllOutsiders()
end

function GroupIconsComponent:Shutdown()
    self:Disable()
end

--- Same RGB as roster ring tint (archetype palette vs green vs gray per GroupIcons settings).
function CustomUI.GroupIcons.GetArchetypeTintRgbForCareerLine(careerLine)
    local r, g, b = GroupRingRgbForCareerLine(tonumber(careerLine))
    return r, g, b
end

CustomUI.RegisterComponent("GroupIcons", GroupIconsComponent)
