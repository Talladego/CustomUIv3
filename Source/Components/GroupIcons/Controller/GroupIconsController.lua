----------------------------------------------------------------
-- CustomUI.GroupIcons — Controller
--
-- View: GroupIcons.xml (templates + OnUpdate driver/probe only); controller owns all logic.
-- Load order: CustomUI.mod lists this script before the XML so handlers exist at parse time.
--
-- Behavior overview:
--   • Roster (party row 1, open-world warband 4×6): career icon + ring on member worldObjNum.
--     Scenario with Scenario checkbox ON: roster grid only for *your* scenario party (sgroupindex match); other scenario parties use outsider tracking with Friendly/Hostile gates — rings match roster style when Scenario enabled else realm blue/red.
--     Self is skipped. Crown on group leader (party row or warband grid; scenario roster omits crown); leader slot drawn at 1.5× scale.
--     Outsider friendly warband leaders (open-party LFG + own warband when applicable): 1.5× scale + Group-Leader-Crown.
--     Hostile outsiders never use leader visuals (names unavailable). Requires showFriendly.
--     Rings: cyan for roster (Party/Warband); realm green/red for Friendly/Hostile outsiders.
--     Guild/Friends (highlightSocial): gold overrides cyan/realm whenever an icon is shown for that name;
--     also attaches roster icons for social members when Party/Warband are off, and tracks Friendly-off
--     mouseover/target allies who are guild/friends (gold instead of green).
--   • Roster attach uses PartyUtils cache + GetGroupMemberStatusData/GetWarbandMemberStatus worldObjNum
--     (do not set partyDirty/warbandDirty on this path — that wipes GroupWindow-hydrated ids after /reloadui).
--     Live non-zero worldObjNum only: distant / 0 id disables the icon (Enemy). Back in range reattaches.
--     Real zone changes clear sticky/known maps (used for name/id validation, not OOR attach).
--     Outsiders: FIFO when full; same AutoMark-style spatial wid probe as roster (below) + window/name checks.
--     Roster: spatial probe; if wid projects as “gone” for several consecutive ticks, squash+hide (Enemy ObjectWindows) until valid again — mitigates top-left stuck attach without probe-boundary flicker.
--   • Outsiders (non-own-roster players incl. other scenario parties): hostile / friendly / mouseover PLAYER_TARGET_UPDATED → deferred TargetInfo read;
--     FIFO pool (c_MAX_TRACKED_OUTSIDERS); realm-tint rings (+ Friendly/Hostile toggles; Guild/Friends can bypass Friendly-off for social names).
--   • Names: NormalizeNameKey (strip caret grammar, lowercase) for PartyUtils / scenario / roster dedupe.
--   • Overlays (lower right, one at a time): death skull first, then one scoreboard
--     stat per player (per realm, exclusive, priority: death blows, kill damage,
--     damage, healing, protection). Dead players show only the skull.
--     Roster death skulls follow live party/warband status HP (and scenario group HP);
--     they clear as soon as HP > 0, on release/offline, or when distant at 0 HP.
--   • Driver + CustomUIGroupIconsWorldProbe: shared AutoMark-style spatial check for outsiders and roster.
----------------------------------------------------------------

if not CustomUI.GroupIcons then
    CustomUI.GroupIcons = {}
end

local OutsiderTracker = CustomUI.GroupIcons.OutsiderTracker or {}
local Roster = CustomUI.GroupIcons.Roster or {}
local SpatialProbe = CustomUI.GroupIcons.SpatialProbe or {}
local WarbandLeaders = CustomUI.GroupIcons.WarbandLeaders or {}
local ScenarioStats = CustomUI.GroupIcons.ScenarioStats or {}

----------------------------------------------------------------
-- Constants
----------------------------------------------------------------

local c_MAX_PARTIES  = 6
local c_MAX_MEMBERS  = 6
-- Round-Swatch-Selection-Ring art is inset in its slice; large centered ring + smaller centered icon.
local c_FRAME_SIZE   = 48   -- Content square and outer window width; vertical band toward attach point
local c_ICON_DRAW    = 34   -- career icon display size (inside ring)
local c_RING_SIZE    = 48   -- ring overlay size (scale up so band clears icon corners)

-- Same career → archetype mapping as Enemy.careerArchetypes (Code/Core/Groups/Groups.lua).

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
-- Poll open-party warband leaders while friendly outsiders are enabled (new LFG / leader transfers).
local c_FRIENDLY_LEADER_POLL_INTERVAL = 30
-- Roster: if fallback entity id was recycled to another player, GetNameForObject shows wrong non-empty name — recheck slowly.
local c_ROSTER_WID_VALIDATE_INTERVAL = 1.5
-- After /reloadui, PartyUtils/GetBattlegroupMemberData can lag several seconds before roster rows carry attachable worldObj ids.
-- Keep nudging refreshes for a while so GroupIcons recovers without requiring a manual disable/enable toggle.
local c_WARM_REFRESH_INTERVAL = 0.35
local c_WARM_REFRESH_ATTEMPTS = 30
local c_GROUPICONS_DRIVER = "CustomUIGroupIconsDriver"
-- Roster spatial hide only after this many consecutive probe intervals (~0.2s each) reporting “gone” — avoids flicker when projection flickers at boundaries.
local c_ROSTER_SPATIAL_GONE_STREAK = 4
-- Overhead map scan used to tell a walking rez from a corpse (camera-independent range).
-- Spatial attach probe stays at 0.2s; map range only needs ~1Hz (skull clear is not latency-critical).
local c_MAX_MAP_POINTS = 511
local c_MAP_DISTANCE_FIX = 1 / 1.06
local c_DEAD_MOTION_LANDMARK_YARDS = 8
local c_DEAD_MOTION_PLAYER_YARDS = 25
local c_DEAD_MOTION_MAP_INTERVAL = 1.0
local c_DEAD_MOTION_MIN_LANDMARKS = 3
local c_OVERHEAD_MAP_DISPLAY = "EA_Window_OverheadMapMapDisplay"

-- Ring colors
local c_RING_FRIENDLY     = { 0, 255, 0 }   -- Green
local c_RING_HOSTILE      = { 255, 0, 0 }   -- Red
local c_RING_CYAN         = { 0, 255, 255 } -- Cyan (roster when archetypeColors off)
local c_RING_SOCIAL       = { 255, 215, 0 } -- Gold (Social friends list / guild mates)


local c_DEFAULT_SETTINGS = {
    showParty = true,
    showWarband = true,
    archetypeColors = false,
    highlightSocial = true,
    showFriendly = true,
    showHostile = true,
    showDeathSkull = true,
    showScenarioThreat = true,
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
    -- Archetype colors UI removed: always cyan roster rings.
    s.archetypeColors = false
    return s
end

local function RealmRingRgbForCareerLine(careerLine)
    local playerRealm = GameData and GameData.Player and GameData.Player.realm
    local careerRealm = careerLine and c_CAREER_REALM[careerLine]
    if not careerRealm then
        return 160, 160, 160
    end
    if playerRealm == GameData.Realm.ORDER or playerRealm == GameData.Realm.DESTRUCTION then
        if careerRealm == playerRealm then
            return c_RING_FRIENDLY[1], c_RING_FRIENDLY[2], c_RING_FRIENDLY[3]
        else
            return c_RING_HOSTILE[1], c_RING_HOSTILE[2], c_RING_HOSTILE[3]
        end
    else
        -- Fallback if player realm is unknown: legacy Order blue / Destruction red
        if careerRealm == GameData.Realm.ORDER then
            return 0, 0, 255
        elseif careerRealm == GameData.Realm.DESTRUCTION then
            return 255, 0, 0
        end
    end
    return 160, 160, 160
end

local function GroupRingRgbForCareerLine(careerLine)
    return c_RING_CYAN[1], c_RING_CYAN[2], c_RING_CYAN[3], "cyan"
end

-- Defined after NormalizeNameKey / social name sets (forward decls for GroupIcon:Attach/Update).
local RingRgbForPlayer
local RefreshSocialNameSets
local ApplyIconOverlays
local ApplyAllLiveIconOverlays
local SyncScenarioStatsStream
-- GetIconData atlas cell size in texture pixels for career icons.
-- Stock uses TexDims 32 (see EA_Image_CareerIcon template); using the wrong value can tile/repeat.
local c_ATLAS_ICON   = 32
-- Round-Swatch-Selection-Ring — defaultskintextures.xml on EA_HUD_01 (must match slice or atlas bleeds).
local c_RING_TEXTURE = "EA_HUD_01"
local c_RING_TEX_X   = 295
local c_RING_TEX_Y   = 475
local c_RING_TEX_DIM = 38
-- Leader crowns on EA_HUD_01 (defaultskintextures.xml / templates_unitframes.xml).
local c_CROWN_TEXTURE = "EA_HUD_01"
local c_CROWN_TEX_X   = 162
local c_CROWN_TEX_W   = 25
local c_CROWN_TEX_H   = 16
local c_WARBAND_LEADER_CROWN_TEX_Y = 138 -- slice Warband-Leader-Crown — roster party/warband leaders
local c_GROUP_LEADER_CROWN_TEX_Y   = 122 -- slice Group-Leader-Crown — friendly outsider warband leaders
-- Roster ring uses geometric center (top↔bottom); no atlas X nudge — −2px (PlayerStatus/UnitFrames) reads left here at 48× ring scale.
local c_CROWN_ANCHOR_OPTICAL_OFFSET_X = 0
-- Base vertical tuck (matches UnitFrames crown vs atlas height budget); GroupIcons applies ring scale below.
local c_CROWN_ANCHOR_TOUCH_OFFSET_Y = 5
-- UnitFrames CustomUIBGMember CareerIconRing outer px — ratio vs c_RING_SIZE scales tuck for larger roster geometry (sync UnitFramesController.c_UF_CAREER_RING_OUTER).
local c_UF_RING_OUTER_REF = 42
local c_OFFSET_Y     = 50   -- gap below the frame toward world attach; outer height = c_OFFSET_Y + framePx (GroupIconLayoutPixels)
-- Party/warband leader: +50% linear size on icon, ring, crown (scale 1.5).
local c_LEADER_VISUAL_SCALE = 1.5
-- Overlay badges: ~24px on a 48px Content square; scale with leader layout.
local c_OVERLAY_DRAW = 24
-- Death: EA_HUD_01 PartyMarker-Skull.
local c_DEATH_TEXTURE  = "EA_HUD_01"
local c_DEATH_TEX_X    = 422
local c_DEATH_TEX_Y    = 349
local c_DEATH_TEX_W    = 30
local c_DEATH_TEX_H    = 33
-- Scoreboard stats: EA_ScenarioSummary01_d8 highlighted column icons.
local c_STAT_TEXTURE = "EA_ScenarioSummary01_d8"
-- Slice UV from ea_scenariosummary01_d8.xml (*-highlighted).
local c_STAT_SLICES = {
    deathblows = { x = 63,  y = 33, w = 18, h = 33 }, -- sword-skull-highlighted
    killdamage = { x = 81,  y = 33, w = 30, h = 33 }, -- crown-highlighted
    damage     = { x = 137, y = 33, w = 32, h = 33 }, -- axe-highlighted
    heal       = { x = 169, y = 33, w = 28, h = 33 }, -- health-highlighted
    protection = { x = 146, y = 68, w = 27, h = 33 }, -- shield-highlighted
}
local c_STAT_KINDS = { "deathblows", "killdamage", "damage", "heal", "protection" }

--- @return framePx, iconPx, ringPx, crownW, crownH, outerH, overlayDraw, deathW, deathH
local function GroupIconLayoutPixels( useLeaderScale )
    local scale = ( useLeaderScale == true ) and c_LEADER_VISUAL_SCALE or 1.0
    local framePx = math.max( 1, math.floor( c_FRAME_SIZE * scale + 0.5 ) )
    local iconPx  = math.max( 1, math.floor( c_ICON_DRAW * scale + 0.5 ) )
    local ringPx  = math.max( 1, math.floor( c_RING_SIZE * scale + 0.5 ) )
    local crownW  = math.max( 1, math.floor( c_CROWN_TEX_W * scale + 0.5 ) )
    local crownH  = math.max( 1, math.floor( c_CROWN_TEX_H * scale + 0.5 ) )
    local outerH  = c_OFFSET_Y + framePx
    local overlayDraw = math.max( 1, math.floor( c_OVERLAY_DRAW * scale + 0.5 ) )
    local deathW = overlayDraw
    local deathH = math.max( 1, math.floor( overlayDraw * c_DEATH_TEX_H / c_DEATH_TEX_W + 0.5 ) )
    return framePx, iconPx, ringPx, crownW, crownH, outerH, overlayDraw, deathW, deathH
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
    self.lastGroupLeaderCrown = nil
    self.lastLeaderScale = nil
    self.lastRingTintKey = nil -- "archetype" | "realm:r,g,b"
    self.lastDeathShowing = nil
    self.lastStatKind = nil -- deathblows | killdamage | damage | heal | protection | nil
    self.lastRosterDead = nil
    -- Roster slots only (partyIndex 1..6): hide stuck world-attached UI without Destroy (Enemy ObjectWindows pattern).
    self.rosterSpatialHidden = false
    self.rosterSavedWorldAttachScale = nil
    self.rosterSpatialGoneStreak = 0
    return self
end

function GroupIcon:_windowName()
    return "CustomUIGroupIcon_" .. self.partyIndex .. "_" .. self.memberIndex
end

function GroupIcon:Attach(name, worldObjNum, careerLine, showWarbandCrown, useRealmRingTint, careerNamesId, useLeaderScale, showGroupLeaderCrown)
    self:_detach()

    showWarbandCrown = showWarbandCrown == true
    showGroupLeaderCrown = showGroupLeaderCrown == true
    if useLeaderScale == nil then
        useLeaderScale = showWarbandCrown or showGroupLeaderCrown
    end
    useLeaderScale = useLeaderScale == true
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
    local framePx, iconPx, ringPx, crownW, crownH, outerH = GroupIconLayoutPixels( useLeaderScale )
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
    rr, gg, bb, self.lastRingTintKey = RingRgbForPlayer(name, careerLine, useRealmRingTint)
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
    local crownTexY = c_WARBAND_LEADER_CROWN_TEX_Y
    if showGroupLeaderCrown then
        crownTexY = c_GROUP_LEADER_CROWN_TEX_Y
    end
    DynamicImageSetTexture(crownWin, c_CROWN_TEXTURE, c_CROWN_TEX_X, crownTexY)
    DynamicImageSetTextureDimensions(crownWin, c_CROWN_TEX_W, c_CROWN_TEX_H)
    -- README §Notes: Point on target (ring), RelativePoint on anchored crown → ring.top meets crown.bottom.
    local crownTouchY = math.max(1, math.floor(c_CROWN_ANCHOR_TOUCH_OFFSET_Y * ringPx / c_UF_RING_OUTER_REF + 0.5))
    WindowAddAnchor(crownWin, "top", ringWin, "bottom", c_CROWN_ANCHOR_OPTICAL_OFFSET_X, crownTouchY)
    WindowSetShowing(crownWin, showWarbandCrown or showGroupLeaderCrown)
    self.lastWarbandCrown = showWarbandCrown
    self.lastGroupLeaderCrown = showGroupLeaderCrown
    self.lastLeaderScale = useLeaderScale

    self:_applyOverlayLayout()

    WindowSetShowing(base, true)
    self.rosterSpatialHidden = false
    self.rosterSavedWorldAttachScale = nil
    self.rosterSpatialGoneStreak = 0
    AttachWindowToWorldObject(self.windowName, worldObjNum)
    if type(ForceUpdateWorldObjectWindow) == "function" then
        CustomUI.TryCallQuiet(
            "GroupIcons.ForceUpdateWorldObjectWindow",
            ForceUpdateWorldObjectWindow,
            worldObjNum,
            self.windowName
        )
    end
end

--- Re-issue engine attach without destroying the window (same Lua wid after /reloadui can be unbound).
function GroupIcon:RebindWorldObject()
    local win = self.windowName
    local wid = tonumber(self.worldObjNum) or 0
    if not win or not DoesWindowExist(win) or wid == 0 then
        return
    end
    if type(DetachWindowFromWorldObject) == "function" then
        CustomUI.TryCallQuiet("GroupIcons.RebindDetach", DetachWindowFromWorldObject, win, wid)
    end
    if type(AttachWindowToWorldObject) == "function" then
        CustomUI.TryCallQuiet("GroupIcons.RebindAttach", AttachWindowToWorldObject, win, wid)
    end
    if type(ForceUpdateWorldObjectWindow) == "function" then
        CustomUI.TryCallQuiet("GroupIcons.RebindForceUpdate", ForceUpdateWorldObjectWindow, wid, win)
    end
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
    self:RebindWorldObject()
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
    self.lastGroupLeaderCrown = nil
    self.lastLeaderScale = nil
    self.lastRingTintKey = nil
    self.lastDeathShowing = nil
    self.lastStatKind = nil
    self.lastRosterDead = nil
    self.rosterSpatialHidden = false
    self.rosterSavedWorldAttachScale = nil
    self.rosterSpatialGoneStreak = 0
end

function GroupIcon:Update(name, worldObjNum, careerLine, showWarbandCrown, useRealmRingTint, careerNamesId, useLeaderScale, showGroupLeaderCrown)
    if not self.isEnabled then return end
    showWarbandCrown = showWarbandCrown == true
    showGroupLeaderCrown = showGroupLeaderCrown == true
    if useLeaderScale == nil then
        useLeaderScale = showWarbandCrown or showGroupLeaderCrown
    end
    useLeaderScale = useLeaderScale == true
    useRealmRingTint = useRealmRingTint == true
    careerNamesId = tonumber(careerNamesId)
    local _, _, _, wantRingKey = RingRgbForPlayer(name, careerLine, useRealmRingTint)
    if worldObjNum == 0 then
        self:_detach()
        return
    end
    -- Re-attach if the player, world object, career (ring / icon), leader scale, crown kind, or ring tint mode changed.
    if not self.windowName
        or self.playerName   ~= name
        or self.worldObjNum  ~= worldObjNum
        or self.lastCareerLine ~= careerLine
        or self.lastCareerNamesId ~= careerNamesId
        or self.lastLeaderScale ~= useLeaderScale
        or self.lastWarbandCrown ~= showWarbandCrown
        or self.lastGroupLeaderCrown ~= showGroupLeaderCrown
        or self.lastRingTintKey ~= wantRingKey
    then
        self:Attach(name, worldObjNum, careerLine, showWarbandCrown, useRealmRingTint, careerNamesId, useLeaderScale, showGroupLeaderCrown)
    end
end

function GroupIcon:_overlayWindow(suffix)
    if not self.windowName then
        return nil
    end
    local win = self.windowName .. "Content" .. suffix
    if DoesWindowExist(win) then
        return win
    end
    return nil
end

--- Size/anchor/show death + scoreboard stat overlay without recreating the world attach.
function GroupIcon:_applyOverlayLayout()
    local content = self.windowName and (self.windowName .. "Content")
    if not content or not DoesWindowExist(content) then
        return
    end
    local _, _, _, _, _, _, overlayDraw, deathW, deathH = GroupIconLayoutPixels(self.lastLeaderScale)
    local deathWin = self:_overlayWindow("DeathMark")
    local statWin = self:_overlayWindow("StatMark")
    local showDeath = self.lastDeathShowing == true
    local slice = self.lastStatKind and c_STAT_SLICES[self.lastStatKind]
    local showStat = (not showDeath) and slice ~= nil

    if deathWin then
        if WindowSetHandleInput then
            WindowSetHandleInput(deathWin, false)
        end
        DynamicImageSetTexture(deathWin, c_DEATH_TEXTURE, c_DEATH_TEX_X, c_DEATH_TEX_Y)
        DynamicImageSetTextureDimensions(deathWin, c_DEATH_TEX_W, c_DEATH_TEX_H)
        WindowSetDimensions(deathWin, deathW, deathH)
        WindowClearAnchors(deathWin)
        WindowAddAnchor(deathWin, "bottomright", content, "bottomright", -1, -1)
        WindowSetShowing(deathWin, showDeath)
    end

    if statWin then
        if WindowSetHandleInput then
            WindowSetHandleInput(statWin, false)
        end
        if slice then
            DynamicImageSetTexture(statWin, c_STAT_TEXTURE, slice.x, slice.y)
            DynamicImageSetTextureDimensions(statWin, slice.w, slice.h)
            local statH = overlayDraw
            local statW = math.max(1, math.floor(overlayDraw * slice.w / slice.h + 0.5))
            WindowSetDimensions(statWin, statW, statH)
        end
        WindowClearAnchors(statWin)
        WindowAddAnchor(statWin, "bottomright", content, "bottomright", -1, -1)
        WindowSetShowing(statWin, showStat)
    end
end

function GroupIcon:SetDeathShowing(show)
    show = show == true
    if self.lastDeathShowing == show and self.windowName and DoesWindowExist(self.windowName) then
        return
    end
    self.lastDeathShowing = show
    if self.windowName and DoesWindowExist(self.windowName) then
        self:_applyOverlayLayout()
    end
end

--- kind: deathblows | killdamage | damage | heal | protection | nil
function GroupIcon:SetStatKind(kind)
    if kind == nil or c_STAT_SLICES[kind] == nil then
        kind = nil
    end
    if self.lastStatKind == kind and self.windowName and DoesWindowExist(self.windowName) then
        return
    end
    self.lastStatKind = kind
    if self.windowName and DoesWindowExist(self.windowName) then
        self:_applyOverlayLayout()
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
local m_trackMeta = {}          -- [worldObjNum] = { name = WString, isFriendly = bool } (outsiders)
local m_trackFIFOOrder = {}     -- array of worldObjNum; index 1 = oldest (evicted first when full)
local m_pendingOutsiderClassifications = {} -- TargetInfo classifications to apply next OnUpdate (avoid UpdateFromClient + handler order)
local m_outsiderProbeElapsed = 0
local m_rosterValidateElapsed = 0
local m_friendlyLeaderPollElapsed = 0
local m_groupWorldObjs = {}    -- [worldObjNum] = true for roster (party/warband)
local m_groupNames = {}        -- [playerName] = true (fast path when exact match works)
local m_groupNameList = {}     -- { WString, ... } robust compare via WStringsCompareIgnoreGrammer

-- Debounce group roster rebuilds: GROUP_STATUS_UPDATED can spam and recreating all windows flickers.
-- Status ticks only set this when the attach worldObj id actually changed (0→N, N→M, or should disable).
local m_needsRefreshAll = false
local m_pendingRosterAttachCheck = false
local m_handlersRegistered = false
-- Last zone used for sticky/known wid wipe. /reloadui can fire PLAYER_ZONE_CHANGED with 0 or the same zone.
local m_lastAttachZoneId = nil

-- After /reloadui, warband worldObj ids often arrive shortly after Initialize; Enable defers RefreshAll to OnUpdate
-- (Enemy.Groups schedules the first pass one task tick later). Warm polling rebinds until live ids project.
local m_postEnableWarmRefreshPoll = 0
local m_postEnableWarmRefreshRemaining = 0

-- Known player worldObj ids by normalized name key (learned from PartyUtils + TargetInfo).
-- { [key] = { wid = number, careerLine = number|nil, t = number|nil } }
local m_knownByNameKey = {}

-- Last in-range worldObjNum per name (validation / recycle checks). Not used to keep OOR icons attached.
-- Cleared on real zone change.
local m_stickyRosterWidByKey = {}

-- Social Window friends / guild roster name keys (NormalizeNameKey) for gold ring highlight.
local m_friendNameKeys = {}
local m_guildNameKeys = {}

-- Outsider death: sticky on HP 0 from mouseover/hard target; clear on HP>0, scenario
-- roster health > 0 (rez), or untrack. Looking away from a corpse keeps the skull.
local m_outsiderDeadWids = {}
local m_pendingOutsiderHealthRefresh = false
local m_pendingRosterDeathRefresh = false
-- Scenario group HP from SCENARIO_PLAYER_HITS_UPDATED, keyed [groupIndex][slot].
local m_scenarioHitHp = {}
-- Map-range samples to drop skulls on walking rezes while the local player is still.
local m_deadMotionByWid = {}
local m_deadMotionLandmarks = {}
local m_deadMotionMapElapsed = 0
-- Scenario/siege scoreboard stat winners: [nameKey] = kind.
local m_statKindByKey = {}

local m_debugLastSig = nil

local function GetOutsiderTrackerState()
    return {
        outsiderPool = m_outsiderPool,
        slotOccupantWid = m_slotOccupantWid,
        trackWidToSlot = m_trackWidToSlot,
        trackMeta = m_trackMeta,
        trackFIFOOrder = m_trackFIFOOrder,
        outsiderDeadWids = m_outsiderDeadWids,
        deadMotionByWid = m_deadMotionByWid,
    }
end

local function GetRosterState()
    return {
        icons = m_icons,
        groupWorldObjs = m_groupWorldObjs,
        groupNames = m_groupNames,
        groupNameList = m_groupNameList,
        stickyRosterWidByKey = m_stickyRosterWidByKey,
        knownByNameKey = m_knownByNameKey,
    }
end


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
local HydrateRosterMemberForAttach
local SlotAttachNeedsRefresh

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

local function IngestSocialNameList(dest, list)
    if type(list) ~= "table" then
        return
    end
    for _, entry in pairs(list) do
        if type(entry) == "table" and entry.name ~= nil then
            local key = NormalizeNameKey(entry.name)
            if key ~= nil then
                dest[key] = true
            end
        end
    end
end

RefreshSocialNameSets = function()
    m_friendNameKeys = {}
    m_guildNameKeys = {}
    if type(GetFriendsList) == "function" then
        local ok, list = CustomUI.TryCallQuiet("GroupIcons.GetFriendsList", GetFriendsList)
        if ok then
            IngestSocialNameList(m_friendNameKeys, list)
        end
    end
    if type(GetGuildMemberData) == "function" then
        local ok, list = CustomUI.TryCallQuiet("GroupIcons.GetGuildMemberData", GetGuildMemberData)
        if ok then
            IngestSocialNameList(m_guildNameKeys, list)
        end
    end
end

local function IsSocialHighlightedName(name)
    local s = EnsureSettings()
    if s.highlightSocial ~= true then
        return false
    end
    local key = NormalizeNameKey(name)
    if key == nil then
        return false
    end
    return m_friendNameKeys[key] == true or m_guildNameKeys[key] == true
end

--- Gold for Social friends / guild mates when highlightSocial is on; else realm or group (cyan/archetype).
RingRgbForPlayer = function(name, careerLine, useRealmRingTint)
    if IsSocialHighlightedName(name) then
        return c_RING_SOCIAL[1], c_RING_SOCIAL[2], c_RING_SOCIAL[3], "social"
    end
    if useRealmRingTint == true then
        local r, g, b = RealmRingRgbForCareerLine(careerLine)
        return r, g, b, string.format("realm:%d,%d,%d", r, g, b)
    end
    return GroupRingRgbForCareerLine(careerLine)
end

local function IsRosterMemberDead(member)
    if not member then
        return false
    end
    local hp = tonumber(member.healthPercent)
    if hp == nil then
        return false
    end
    -- Live HP wins: a rez must clear the skull even if distant/online flags lag.
    if hp > 0 then
        return false
    end
    if member.online == false then
        return false
    end
    -- 0 HP while distant is usually out of range, not a corpse.
    if member.isDistant == true then
        return false
    end
    return true
end

local function StatKindForIcon(icon)
    if not icon or EnsureSettings().showScenarioThreat ~= true then
        return nil
    end
    local key = icon.playerName and NormalizeNameKey(icon.playerName)
    if key == nil then
        return nil
    end
    return m_statKindByKey[key]
end

ApplyIconOverlays = function(icon)
    if not icon or not icon.windowName or not DoesWindowExist(icon.windowName) then
        return
    end
    local s = EnsureSettings()
    local showDeath = false
    if s.showDeathSkull == true then
        if icon.partyIndex <= c_MAX_PARTIES then
            showDeath = icon.lastRosterDead == true
        else
            local wid = tonumber(icon.worldObjNum) or 0
            showDeath = wid ~= 0 and m_outsiderDeadWids[wid] == true
        end
    end
    icon:SetDeathShowing(showDeath)
    icon:SetStatKind(StatKindForIcon(icon))
end

ApplyAllLiveIconOverlays = function()
    for p = 1, c_MAX_PARTIES do
        local row = m_icons[p]
        if row then
            for m = 1, c_MAX_MEMBERS do
                ApplyIconOverlays(row[m])
            end
        end
    end
    for i = 1, c_MAX_TRACKED_OUTSIDERS do
        ApplyIconOverlays(m_outsiderPool[i])
    end
end

local function ClearThreatWinners()
    m_statKindByKey = {}
end

local function RefreshThreatWinnersFromScenarioPlayers()
    if type(ScenarioStats.PickTopWinners) ~= "function" then
        ClearThreatWinners()
        return
    end
    local winners = ScenarioStats.PickTopWinners(NormalizeNameKey)
    m_statKindByKey = {}
    if type(winners) ~= "table" then
        return
    end

    for i = 1, #c_STAT_KINDS do
        local kind = c_STAT_KINDS[i]
        local byRealm = winners[kind]
        if type(byRealm) == "table" then
            for _, entry in pairs(byRealm) do
                if type(entry) == "table" and entry.key ~= nil then
                    m_statKindByKey[entry.key] = kind
                end
            end
        end
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
    local ok, res = CustomUI.TryCallQuiet(
        "GroupIcons.SafeWStringEquals",
        WStringsCompareIgnoreGrammer,
        ToWString(a),
        ToWString(b)
    )
    if not ok then
        return false
    end
    return res == 0
end

local function ClearGroupMembershipCache()
    if type(Roster.ClearGroupMembershipCache) == "function" then
        Roster.ClearGroupMembershipCache(GetRosterState())
        return
    end
    m_groupWorldObjs = {}
    m_groupNames = {}
    m_groupNameList = {}
end

local function RegisterGroupMember(member)
    if type(Roster.RegisterGroupMember) == "function" then
        Roster.RegisterGroupMember(GetRosterState(), member, {
            toWString = ToWString,
        })
        return
    end
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

local function LiveAttachWorldId(member)
    if type(Roster.LiveAttachWorldId) == "function" then
        return Roster.LiveAttachWorldId(member)
    end
    if not member then
        return 0
    end
    if member.isDistant == true or member.online == false then
        return 0
    end
    return tonumber(member.worldObjNum) or 0
end

--- Live non-zero worldObjNum only. Sticky/known are not used to keep an OOR icon on a dead entity id.
local function ResolveRosterIconAttachWorldId(nameW, liveWidFromData)
    if type(Roster.ResolveAttachWorldId) == "function" then
        return Roster.ResolveAttachWorldId(GetRosterState(), nameW, liveWidFromData, {
            normalizeNameKey = NormalizeNameKey,
        })
    end
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

--- Empty / failed GetNameForObject ⇒ keep attach (distant / streaming). Non-empty mismatch ⇒ entity id recycled / wrong attach.
local function RosterWorldObjectNameMatchesPlayer(wid, expectedNameW)
    if wid == nil or wid == 0 or type(GetNameForObject) ~= "function" then
        return true
    end
    local ok, nm = CustomUI.TryCallQuiet("GroupIcons.RosterWorldObjectNameMatchesPlayer", GetNameForObject, wid)
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
    if type(Roster.ValidateIconWorldObjects) == "function" then
        Roster.ValidateIconWorldObjects(GetRosterState(), {
            normalizeNameKey = NormalizeNameKey,
            toWString = ToWString,
            safeWStringEquals = SafeWStringEquals,
        })
        return
    end
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
    if type(Roster.LearnKnownWorldObject) == "function" then
        return Roster.LearnKnownWorldObject(GetRosterState(), name, wid, careerLine, {
            normalizeNameKey = NormalizeNameKey,
            debugLog = DebugLog,
        })
    end
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
    if wid ~= nil then
        m_outsiderDeadWids[wid] = nil
        m_deadMotionByWid[wid] = nil
    end
    if type(OutsiderTracker.UntrackWid) == "function" then
        OutsiderTracker.UntrackWid(GetOutsiderTrackerState(), wid)
        return
    end
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
    m_outsiderDeadWids = {}
    m_deadMotionByWid = {}
    m_deadMotionLandmarks = {}
    m_deadMotionMapElapsed = 0
    if type(OutsiderTracker.UntrackAll) == "function" then
        OutsiderTracker.UntrackAll(GetOutsiderTrackerState())
        m_outsiderProbeElapsed = 0
        m_rosterValidateElapsed = 0
        return
    end
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

local function WantFriendlyOutsiderWarbandLeaders()
    return EnsureSettings().showFriendly == true
end

local function RefreshWarbandLeaderCache()
    if type(WarbandLeaders.Refresh) ~= "function" then
        return false
    end
    return WarbandLeaders.Refresh({
        normalizeNameKey = NormalizeNameKey,
    }) == true
end

local function RequestWarbandLeaderData()
    if not WantFriendlyOutsiderWarbandLeaders() then
        return
    end
    if type(WarbandLeaders.RequestNearbyData) == "function" then
        WarbandLeaders.RequestNearbyData({ enabled = true })
    end
end

--- @return useLeaderScale boolean, showGroupLeaderCrown boolean
local function ResolveOutsiderLeaderVisuals(playerName, isFriendly)
    if isFriendly ~= true or not WantFriendlyOutsiderWarbandLeaders() then
        return false, false
    end
    if type(WarbandLeaders.IsKnown) ~= "function" then
        return false, false
    end
    if WarbandLeaders.IsKnown(playerName, NormalizeNameKey) ~= true then
        return false, false
    end
    return true, true
end

local function RefreshTrackedOutsiderLeaderVisuals()
    if not next(m_trackWidToSlot) then
        return
    end
    for wid, idx in pairs(m_trackWidToSlot) do
        local meta = m_trackMeta[wid]
        local nm = meta and meta.name
        local icon = m_outsiderPool[idx]
        if nm and icon and icon.isEnabled and icon.worldObjNum ~= 0 then
            local useLeaderScale, showGroupLeaderCrown = ResolveOutsiderLeaderVisuals(nm, meta.isFriendly == true)
            icon:Update(nm, wid, icon.lastCareerLine, false, true, icon.lastCareerNamesId, useLeaderScale, showGroupLeaderCrown)
            ApplyIconOverlays(icon)
        end
    end
end

local function OnWarbandLeaderListMaybeChanged()
    local changed = RefreshWarbandLeaderCache()
    if changed or next(m_trackWidToSlot) then
        RefreshTrackedOutsiderLeaderVisuals()
    end
    return changed
end

local function TryTrackOutsider(wid, pname, career, isFriendly)
    isFriendly = isFriendly == true
    if type(OutsiderTracker.TryTrack) == "function" then
        if OutsiderTracker.TryTrack(GetOutsiderTrackerState(), wid, pname, career, {
            isFriendly = isFriendly,
            maxTrackedOutsiders = c_MAX_TRACKED_OUTSIDERS,
            isGroupWorldObject = function(trackWid) return m_groupWorldObjs[trackWid] == true end,
            isGroupMemberName = IsGroupMemberName,
            resolveOutsiderLeaderVisuals = ResolveOutsiderLeaderVisuals,
            applyOverlays = ApplyIconOverlays,
        }) then
            m_outsiderProbeElapsed = c_OUTSIDER_PROBE_INTERVAL
        end
        return
    end
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
        local useLeaderScale, showGroupLeaderCrown = ResolveOutsiderLeaderVisuals(pname, isFriendly)
        icon:Update(pname, wid, career, false, realmRing, nil, useLeaderScale, showGroupLeaderCrown)
        icon:RebindWorldObject()
        m_trackMeta[wid] = { name = pname, isFriendly = isFriendly }
        m_outsiderProbeElapsed = c_OUTSIDER_PROBE_INTERVAL
        ApplyIconOverlays(icon)
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
    m_trackMeta[wid] = { name = pname, isFriendly = isFriendly }
    table.insert(m_trackFIFOOrder, wid)
    local icon = m_outsiderPool[freeIdx]
    icon:Enable()
    local useLeaderScale, showGroupLeaderCrown = ResolveOutsiderLeaderVisuals(pname, isFriendly)
    icon:Update(pname, wid, career, false, realmRing, nil, useLeaderScale, showGroupLeaderCrown)
    ApplyIconOverlays(icon)
    m_outsiderProbeElapsed = c_OUTSIDER_PROBE_INTERVAL
end

--- Fill party/warband name + worldObj registry so outsider prune/TryTrack gates work even when roster *icons*
--- are not refreshed (scenario + showParty off, etc.).
local function RegisterAllPartyWarbandMembersForPruning()
    if type(Roster.RegisterAllForPruning) == "function" then
        Roster.RegisterAllForPruning(GetRosterState(), {
            normalizeNameKey = NormalizeNameKey,
            toWString = ToWString,
            isWarBandActive = IsWarBandActive,
            debugLog = DebugLog,
            hydrateMember = HydrateRosterMemberForAttach,
        })
        return
    end
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
                local liveWid = LiveAttachWorldId(member)
                local wid = ResolveRosterIconAttachWorldId(member.name, liveWid)
                RegisterGroupMember({ name = member.name, worldObjNum = (wid ~= 0 and wid) or nil })
            end
        end
    end
    if IsWarBandActive() then
        local parties = (type(Roster.GetWarbandParties) == "function" and Roster.GetWarbandParties(nil)) or GetBattlegroupMemberData()
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
                        local liveWid = LiveAttachWorldId(member)
                        local wid = ResolveRosterIconAttachWorldId(member.name, liveWid)
                        RegisterGroupMember({ name = member.name, worldObjNum = (wid ~= 0 and wid) or nil })
                    end
                end
            end
        end
    end
end

--- Snapshot mouseover/hard-target HP onto outsider sticky death; roster death uses party/warband HP.
local function ApplyOverlaysForOutsiderWid(wid)
    wid = tonumber(wid) or 0
    if wid == 0 then
        return
    end
    local idx = m_trackWidToSlot[wid]
    if not idx then
        return
    end
    ApplyIconOverlays(m_outsiderPool[idx])
end

--- Merge live TargetInfo HP into sticky outsider death. HP 0 sets; HP > 0 clears that wid.
--- Looking away does not clear. Untrack / spatial gone still clears.
local function ApplyLiveTargetDeathObservations()
    local changed = {}

    local function consider(classification)
        if not TargetInfo then
            return
        end
        local unitType = TargetInfo:UnitType(classification)
        if unitType ~= SystemData.TargetObjectType.ENEMY_PLAYER
            and unitType ~= SystemData.TargetObjectType.ALLY_PLAYER
        then
            return
        end
        local wid = TargetInfo:UnitEntityId(classification)
        if not wid or wid == 0 then
            return
        end
        local hp = tonumber(TargetInfo:UnitHealth(classification))
        if hp == nil then
            return
        end
        if hp <= 0 then
            if m_trackWidToSlot[wid] and m_outsiderDeadWids[wid] ~= true then
                m_outsiderDeadWids[wid] = true
                changed[wid] = true
            end
        elseif m_outsiderDeadWids[wid] == true then
            m_outsiderDeadWids[wid] = nil
            changed[wid] = true
        end
    end

    consider(c_HOSTILE_TARGET)
    consider(c_FRIENDLY_TARGET)
    consider(c_MOUSEOVER_TARGET)

    for wid in pairs(changed) do
        ApplyOverlaysForOutsiderWid(wid)
    end
end

local function ScenarioHealthLooksAlive(hp)
    hp = tonumber(hp)
    if hp == nil then
        return false
    end
    -- Same near-zero snap as UnitFrames: sub-1% is still a corpse, not a rez.
    if hp > 0 and hp < 1 then
        hp = 0
    end
    return hp > 0
end

local function BuildScenarioHpByNameKey()
    local byKey = {}
    if type(IsScenarioContext) == "function" and IsScenarioContext() ~= true then
        return byKey
    end
    if type(GameData) ~= "table" or type(GameData.GetScenarioPlayerGroups) ~= "function" then
        return byKey
    end
    local ok, groups = CustomUI.TryCallQuiet("GroupIcons.GetScenarioPlayerGroups", GameData.GetScenarioPlayerGroups)
    if not ok or type(groups) ~= "table" then
        return byKey
    end
    for _, player in ipairs(groups) do
        if type(player) == "table" then
            local key = NormalizeNameKey(player.name)
            if key ~= nil then
                local groupIndex = tonumber(player.sgroupindex)
                local slotIndex = tonumber(player.sgroupslotnum)
                local hp = tonumber(player.health)
                if groupIndex ~= nil and slotIndex ~= nil then
                    local hitsForGroup = m_scenarioHitHp[groupIndex]
                    local hit = hitsForGroup and hitsForGroup[slotIndex]
                    if hit ~= nil then
                        hp = tonumber(hit)
                    end
                end
                if hp ~= nil then
                    byKey[key] = hp
                end
            end
        end
    end
    return byKey
end

--- Party/warband skulls must use live status HP (GetGroupMemberStatusData / GetWarbandMemberStatus),
--- not GetGroupData() after a cache invalidate — that snapshot stays at 0 after rez/release.
local function MergeLiveRosterDeathMember(partyIndex, memberIndex, member, playerName, scenarioHpByKey)
    member = member or {}
    local inScenario = type(IsScenarioContext) == "function" and IsScenarioContext() == true
    local status = nil
    if inScenario ~= true and type(IsWarBandActive) == "function" and IsWarBandActive() then
        if type(GetWarbandMemberStatus) == "function" then
            local ok, st = CustomUI.TryCallQuiet(
                "GroupIcons.GetWarbandMemberStatus",
                GetWarbandMemberStatus,
                partyIndex,
                memberIndex
            )
            if ok and type(st) == "table" then
                status = st
            end
        end
    elseif partyIndex == 1 and type(GetGroupMemberStatusData) == "function" then
        local ok, st = CustomUI.TryCallQuiet(
            "GroupIcons.GetGroupMemberStatusData",
            GetGroupMemberStatusData,
            memberIndex
        )
        if ok and type(st) == "table" then
            status = st
        end
    end
    if status ~= nil then
        if status.healthPercent ~= nil then
            member.healthPercent = status.healthPercent
        end
        if status.online ~= nil then
            member.online = status.online
        end
        if status.isDistant ~= nil then
            member.isDistant = status.isDistant
        end
        local statusWid = tonumber(status.worldObjNum) or 0
        if statusWid ~= 0 then
            member.worldObjNum = statusWid
        end
    end
    local key = NormalizeNameKey(playerName or member.name)
    local scenarioHp = key and scenarioHpByKey and scenarioHpByKey[key]
    if scenarioHp ~= nil then
        member.healthPercent = scenarioHp
        member.online = true
        member.isDistant = false
    end
    return member, status
end

HydrateRosterMemberForAttach = function(partyIndex, memberIndex, member)
    if member == nil then
        return nil
    end
    MergeLiveRosterDeathMember(partyIndex, memberIndex, member, member.name, nil)
    return member
end

local function CurrentPlayerZoneId()
    if GameData and GameData.Player then
        return tonumber(GameData.Player.zone)
    end
    return nil
end

local function RememberAttachZoneId()
    local zone = CurrentPlayerZoneId()
    if zone ~= nil and zone ~= 0 then
        m_lastAttachZoneId = zone
    end
end

--- True when this slot's attach wid (status/cache/sticky) disagrees with the live icon.
SlotAttachNeedsRefresh = function(partyIndex, memberIndex)
    partyIndex = tonumber(partyIndex)
    memberIndex = tonumber(memberIndex)
    if partyIndex == nil or memberIndex == nil then
        return false
    end
    if partyIndex < 1 or partyIndex > c_MAX_PARTIES or memberIndex < 1 or memberIndex > c_MAX_MEMBERS then
        return false
    end

    local s = EnsureSettings()
    local inScenario = IsScenarioContext()
    local member = nil
    local shouldShow = false

    if inScenario then
        if partyIndex ~= 1 then
            return false
        end
        shouldShow = s.showParty == true
        local data = (type(PartyUtils) == "table" and type(PartyUtils.GetPartyData) == "function") and PartyUtils.GetPartyData() or GetGroupData()
        member = GetPartySlotMember(memberIndex, data)
    elseif IsWarBandActive() then
        shouldShow = s.showWarband == true or (s.showParty == true and partyIndex == 1)
        if type(PartyUtils) == "table" and type(PartyUtils.GetWarbandMember) == "function" then
            member = PartyUtils.GetWarbandMember(partyIndex, memberIndex)
        end
        if member == nil then
            local parties = (type(Roster.GetWarbandParties) == "function" and Roster.GetWarbandParties(nil)) or GetBattlegroupMemberData()
            local party = parties and parties[partyIndex]
            member = party and party.players and party.players[memberIndex]
        end
    else
        if partyIndex ~= 1 then
            return false
        end
        shouldShow = s.showParty == true
        local data = (type(PartyUtils) == "table" and type(PartyUtils.GetPartyData) == "function") and PartyUtils.GetPartyData() or GetGroupData()
        member = GetPartySlotMember(memberIndex, data)
    end

    member = HydrateRosterMemberForAttach(partyIndex, memberIndex, member)
    if not member or not member.name then
        local icon = m_icons[partyIndex] and m_icons[partyIndex][memberIndex]
        return icon ~= nil and icon.isEnabled == true
    end

    local socialOnly = IsSocialHighlightedName(member.name)
    if not shouldShow and not socialOnly then
        return false
    end

    local memberName = ToWString(member.name)
    if memberName == nil or memberName == L"" or IsSelfMember(memberName) then
        return false
    end

    local liveWid = LiveAttachWorldId(member)
    local resolvedWid = ResolveRosterIconAttachWorldId(member.name, liveWid)
    local icon = m_icons[partyIndex][memberIndex]
    if not icon then
        return false
    end
    if resolvedWid == 0 then
        return icon.isEnabled == true
    end
    if not icon.isEnabled or icon.worldObjNum ~= resolvedWid then
        return true
    end
    return false
end

local function RefreshRosterDeathOverlays()
    if EnsureSettings().showDeathSkull ~= true then
        return
    end
    local scenarioHpByKey = BuildScenarioHpByNameKey()
    for p = 1, c_MAX_PARTIES do
        local row = m_icons[p]
        if row then
            for m = 1, c_MAX_MEMBERS do
                local icon = row[m]
                if icon and icon.isEnabled == true and icon.windowName and DoesWindowExist(icon.windowName) then
                    local member, status = MergeLiveRosterDeathMember(
                        p,
                        m,
                        { name = icon.playerName },
                        icon.playerName,
                        scenarioHpByKey
                    )
                    icon.lastRosterDead = IsRosterMemberDead(member)
                    ApplyIconOverlays(icon)
                    local liveWid = status and tonumber(status.worldObjNum) or 0
                    -- Include 0→N: overlay-only ticks used to ignore disabled / wid-0 icons.
                    if liveWid ~= 0 and liveWid ~= (tonumber(icon.worldObjNum) or 0) then
                        if not IsSelfMember(icon.playerName or member.name) then
                            m_needsRefreshAll = true
                        end
                    end
                end
            end
        end
    end
end

--- Scenario groups report HP for assigned parties. Sticky-dead outsiders with HP > 0 rezzed.
local function ClearOutsiderDeadFromScenarioHealth()
    if not next(m_outsiderDeadWids) then
        return
    end
    if type(IsScenarioContext) == "function" and IsScenarioContext() ~= true then
        return
    end
    if type(GameData) ~= "table" or type(GameData.GetScenarioPlayerGroups) ~= "function" then
        return
    end
    local ok, groups = CustomUI.TryCallQuiet("GroupIcons.GetScenarioPlayerGroups", GameData.GetScenarioPlayerGroups)
    if not ok or type(groups) ~= "table" then
        return
    end

    local aliveKeys = {}
    local aliveWids = {}
    for _, player in ipairs(groups) do
        if type(player) == "table" then
            local groupIndex = tonumber(player.sgroupindex)
            local slotIndex = tonumber(player.sgroupslotnum)
            local hp = tonumber(player.health)
            if groupIndex ~= nil and slotIndex ~= nil then
                local hitsForGroup = m_scenarioHitHp[groupIndex]
                local hit = hitsForGroup and hitsForGroup[slotIndex]
                if hit ~= nil then
                    hp = tonumber(hit)
                end
            end
            if ScenarioHealthLooksAlive(hp) then
                local key = NormalizeNameKey(player.name)
                if key ~= nil then
                    aliveKeys[key] = true
                end
                local wid = tonumber(player.worldObjNum or player.worldobjnum or player.entityId or player.entityid)
                if wid ~= nil and wid ~= 0 then
                    aliveWids[wid] = true
                end
            end
        end
    end

    if not next(aliveKeys) and not next(aliveWids) then
        return
    end

    local changed = {}
    for wid in pairs(m_outsiderDeadWids) do
        local clear = aliveWids[wid] == true
        if not clear then
            local meta = m_trackMeta[wid]
            local key = meta and meta.name and NormalizeNameKey(meta.name)
            if key ~= nil and aliveKeys[key] == true then
                clear = true
            end
        end
        if clear then
            m_outsiderDeadWids[wid] = nil
            changed[wid] = true
        end
    end
    for wid in pairs(changed) do
        ApplyOverlaysForOutsiderWid(wid)
    end
end

local function AbsNumber(a)
    if a < 0 then
        return -a
    end
    return a
end

--- Only collect distances for sticky-dead outsider names (+ a few landmarks for "did we move").
--- Early-outs once pending player keys are filled and enough landmarks exist (avoids full 511 walks).
local function CollectDeadMotionMapScan(pendingPlayerKeys, pendingPlayerCount)
    local distByKey = {}
    local landmarkByIndex = {}
    if type(GetMapPointData) ~= "function" then
        return distByKey, landmarkByIndex
    end
    if type(DoesWindowExist) == "function" and not DoesWindowExist(c_OVERHEAD_MAP_DISPLAY) then
        return distByKey, landmarkByIndex
    end
    local pips = SystemData and SystemData.MapPips
    if type(pips) ~= "table" then
        return distByKey, landmarkByIndex
    end
    local playerTypes = {
        [pips.GROUP_MEMBER] = true,
        [pips.WARBAND_MEMBER] = true,
        [pips.DESTRUCTION_ARMY] = true,
        [pips.ORDER_ARMY] = true,
    }
    local landmarkTypes = {
        [pips.KEEP] = true,
        [pips.OBJECTIVE] = true,
        [pips.FLAG] = true,
        [pips.LANDMARK] = true,
        [pips.CHAPTER] = true,
        [pips.WAR_CAMP] = true,
        [pips.PUBLIC_QUEST] = true,
    }
    local remaining = tonumber(pendingPlayerCount) or 0
    local landmarkCount = 0
    local needLandmarks = remaining > 0
    for i = 1, c_MAX_MAP_POINTS do
        local mpd = GetMapPointData(c_OVERHEAD_MAP_DISPLAY, i)
        if type(mpd) == "table" and mpd.pointType ~= nil then
            local dist = tonumber(mpd.distance)
            if dist ~= nil then
                dist = dist * c_MAP_DISTANCE_FIX
                if playerTypes[mpd.pointType] then
                    local key = NormalizeNameKey(mpd.name)
                    if key ~= nil and pendingPlayerKeys[key] == true and distByKey[key] == nil then
                        distByKey[key] = dist
                        remaining = remaining - 1
                    end
                elseif needLandmarks and landmarkTypes[mpd.pointType] then
                    landmarkByIndex[i] = dist
                    landmarkCount = landmarkCount + 1
                end
            end
        end
        if remaining <= 0 and (not needLandmarks or landmarkCount >= c_DEAD_MOTION_MIN_LANDMARKS) then
            break
        end
    end
    return distByKey, landmarkByIndex
end

local function LandmarkMaxDelta(prevByIndex, curByIndex)
    local maxDelta = nil
    local compared = 0
    if type(prevByIndex) ~= "table" or type(curByIndex) ~= "table" then
        return nil, 0
    end
    for index, dist in pairs(curByIndex) do
        local prev = prevByIndex[index]
        if prev ~= nil then
            local delta = AbsNumber(dist - prev)
            if maxDelta == nil or delta > maxDelta then
                maxDelta = delta
            end
            compared = compared + 1
        end
    end
    return maxDelta, compared
end

--- World-range motion: if landmarks are stable (we did not translate) and a sticky-dead
--- player's map pip range changes, they walked — drop the skull. Screen position of the
--- attached GroupIcon also moves when the camera yaws, so it is not used here.
local function ClearOutsiderDeadFromIndependentMotion()
    if not next(m_outsiderDeadWids) then
        m_deadMotionByWid = {}
        m_deadMotionLandmarks = {}
        m_deadMotionMapElapsed = 0
        return
    end

    local pendingPlayerKeys = {}
    local pendingPlayerCount = 0
    for wid in pairs(m_outsiderDeadWids) do
        local meta = m_trackMeta[wid]
        local key = meta and meta.name and NormalizeNameKey(meta.name)
        if key ~= nil and pendingPlayerKeys[key] ~= true then
            pendingPlayerKeys[key] = true
            pendingPlayerCount = pendingPlayerCount + 1
        end
    end
    if pendingPlayerCount <= 0 then
        return
    end

    local distByKey, landmarkByIndex = CollectDeadMotionMapScan(pendingPlayerKeys, pendingPlayerCount)
    local maxLandmarkDelta, compared = LandmarkMaxDelta(m_deadMotionLandmarks, landmarkByIndex)
    m_deadMotionLandmarks = landmarkByIndex
    local weMoved = compared < 1 or maxLandmarkDelta == nil or maxLandmarkDelta > c_DEAD_MOTION_LANDMARK_YARDS

    local changed = {}
    for wid in pairs(m_outsiderDeadWids) do
        local meta = m_trackMeta[wid]
        local key = meta and meta.name and NormalizeNameKey(meta.name)
        local dist = key and distByKey[key]
        local prev = m_deadMotionByWid[wid]
        if weMoved or dist == nil then
            m_deadMotionByWid[wid] = { dist = dist }
        elseif prev and prev.dist ~= nil and AbsNumber(dist - prev.dist) > c_DEAD_MOTION_PLAYER_YARDS then
            m_outsiderDeadWids[wid] = nil
            m_deadMotionByWid[wid] = nil
            changed[wid] = true
        else
            m_deadMotionByWid[wid] = { dist = dist }
        end
    end
    for wid in pairs(m_deadMotionByWid) do
        if m_outsiderDeadWids[wid] ~= true then
            m_deadMotionByWid[wid] = nil
        end
    end
    for wid in pairs(changed) do
        ApplyOverlaysForOutsiderWid(wid)
    end
end

local function RefreshOutsiderDeathFlags()
    ApplyLiveTargetDeathObservations()
    ClearOutsiderDeadFromScenarioHealth()
end

--- Reads TargetInfo after stock TargetWindow / MouseOverTargetWindow ran UpdateFromClient on PLAYER_TARGET_UPDATED.
local function ConsiderClassificationForTracking(classification)
    if type(OutsiderTracker.ConsiderClassification) == "function" then
        if OutsiderTracker.ConsiderClassification(GetOutsiderTrackerState(), classification, {
            ensureSettings = EnsureSettings,
            toWString = ToWString,
            isSelfMember = IsSelfMember,
            isSocialHighlightedName = IsSocialHighlightedName,
            learnKnownWorldObject = LearnKnownWorldObject,
            maxTrackedOutsiders = c_MAX_TRACKED_OUTSIDERS,
            isGroupWorldObject = function(trackWid) return m_groupWorldObjs[trackWid] == true end,
            isGroupMemberName = IsGroupMemberName,
            resolveOutsiderLeaderVisuals = ResolveOutsiderLeaderVisuals,
            applyOverlays = ApplyIconOverlays,
        }) then
            m_outsiderProbeElapsed = c_OUTSIDER_PROBE_INTERVAL
        end
        return
    end
    local ut = TargetInfo:UnitType(classification)
    if ut ~= SystemData.TargetObjectType.ENEMY_PLAYER and ut ~= SystemData.TargetObjectType.ALLY_PLAYER then
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
    local s = EnsureSettings()
    local socialHighlight = IsSocialHighlightedName(pname)
    if ut == SystemData.TargetObjectType.ALLY_PLAYER and not s.showFriendly and not socialHighlight then
        return
    end
    if ut == SystemData.TargetObjectType.ENEMY_PLAYER and not s.showHostile then
        return
    end
    local career = TargetInfo:UnitCareer(classification)
    LearnKnownWorldObject(pname, wid, career)
    TryTrackOutsider(wid, pname, career, ut == SystemData.TargetObjectType.ALLY_PLAYER)
end

local function PruneTrackedOutsidersAgainstRoster()
    if type(OutsiderTracker.PruneAgainstRoster) == "function" then
        OutsiderTracker.PruneAgainstRoster(GetOutsiderTrackerState(), {
            isGroupWorldObject = function(trackWid) return m_groupWorldObjs[trackWid] == true end,
            isGroupMemberName = IsGroupMemberName,
        })
        return
    end
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
    local ok, nm = CustomUI.TryCallQuiet("GroupIcons.OutsiderWorldObjectNameMismatchTracked", GetNameForObject, wid)
    if not ok or nm == nil then
        return false
    end
    local w = ToWString(nm)
    if w == nil or w == L"" then
        return false
    end
    return not SafeWStringEquals(w, ToWString(trackedNameW))
end

local function GetWorldProbeCalibration()
    if type(SpatialProbe.GetCalibration) ~= "function" then
        return nil
    end
    return SpatialProbe.GetCalibration()
end

local function WorldObjectSpatialProbeIsGone(wid, cal)
    if type(SpatialProbe.IsGone) ~= "function" then
        return false
    end
    return SpatialProbe.IsGone(wid, cal)
end

local function ResetWorldProbeCalibration()
    if type(SpatialProbe.ResetCalibration) == "function" then
        SpatialProbe.ResetCalibration()
    end
end

local function ValidateTrackedOutsiders(cal)
    if type(OutsiderTracker.ValidateTracked) == "function" then
        OutsiderTracker.ValidateTracked(GetOutsiderTrackerState(), cal, {
            nameMismatch = OutsiderWorldObjectNameMismatchTracked,
            isGone = WorldObjectSpatialProbeIsGone,
        })
        return
    end
    if not next(m_trackWidToSlot) then
        return
    end
    if cal == nil then
        cal = GetWorldProbeCalibration()
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

--- True when every non-self roster member with a *live* worldObjNum is attached to that id.
--- liveWid==0 (distant / not streamed) is ignored — those members should have no icon.
--- Returns false while no live wids exist yet so warm polling keeps running after /reloadui
--- (stopping on "any attached icon" was too eager when only some members had ids).
local function RosterLiveWorldIdsFullyAttached()
    local s = EnsureSettings()
    local inScenario = IsScenarioContext()
    local sawLive = false

    local function memberLiveAttached(partyIndex, memberIndex, member)
        if not member or not member.name then
            return true
        end
        local memberName = ToWString(member.name)
        if memberName == nil or memberName == L"" or IsSelfMember(memberName) then
            return true
        end
        local liveWid = LiveAttachWorldId(member)
        if liveWid == 0 then
            local icon = m_icons[partyIndex][memberIndex]
            if icon and icon.isEnabled then
                return false
            end
            return true
        end
        sawLive = true
        local icon = m_icons[partyIndex][memberIndex]
        if not icon
            or not icon.isEnabled
            or icon.worldObjNum ~= liveWid
            or icon.rosterSpatialHidden == true
            or not icon.windowName
            or not DoesWindowExist(icon.windowName)
        then
            return false
        end
        return true
    end

    local function wantRosterMember(member, partyGate)
        if partyGate then
            return true
        end
        return member ~= nil and IsSocialHighlightedName(member.name)
    end

    if inScenario then
        if s.showParty or s.highlightSocial then
            local data = (type(PartyUtils) == "table" and type(PartyUtils.GetPartyData) == "function") and PartyUtils.GetPartyData() or GetGroupData()
            if type(data) == "table" then
                for m = 1, c_MAX_MEMBERS do
                    local member = HydrateRosterMemberForAttach(1, m, GetPartySlotMember(m, data))
                    if wantRosterMember(member, s.showParty == true) and not memberLiveAttached(1, m, member) then
                        return false
                    end
                end
            end
        end
    elseif IsWarBandActive() then
        local showAll = s.showWarband == true
        local showParty1 = s.showParty == true
        local parties = (type(Roster.GetWarbandParties) == "function" and Roster.GetWarbandParties(nil)) or GetBattlegroupMemberData()
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
                    member = HydrateRosterMemberForAttach(p, m, member)
                    local shouldShow = showAll or (showParty1 and p == 1)
                    if wantRosterMember(member, shouldShow) and not memberLiveAttached(p, m, member) then
                        return false
                    end
                end
            end
        end
    elseif s.showParty or s.highlightSocial then
        local data = (type(PartyUtils) == "table" and type(PartyUtils.GetPartyData) == "function") and PartyUtils.GetPartyData() or GetGroupData()
        if type(data) == "table" then
            for m = 1, c_MAX_MEMBERS do
                local member = HydrateRosterMemberForAttach(1, m, GetPartySlotMember(m, data))
                if wantRosterMember(member, s.showParty == true) and not memberLiveAttached(1, m, member) then
                    return false
                end
            end
        end
    end
    return sawLive
end

--- True when settings allow party/warband roster world markers (or Guild/Friends social roster attach).
local function WantRosterWorldMarkers()
    local s = EnsureSettings()
    return s.showParty == true or s.showWarband == true or s.highlightSocial == true
end

local function RosterRefreshOpts()
    local s = EnsureSettings()
    local scenarioHpByKey = BuildScenarioHpByNameKey()
    return {
        normalizeNameKey = NormalizeNameKey,
        toWString = ToWString,
        isSelfMember = IsSelfMember,
        isSocialHighlightedName = IsSocialHighlightedName,
        showPartyIcons = s.showParty == true,
        debugLog = DebugLog,
        hydrateMember = HydrateRosterMemberForAttach,
        applyRosterOverlays = function(icon, member)
            if not icon then
                return
            end
            member = MergeLiveRosterDeathMember(
                icon.partyIndex,
                icon.memberIndex,
                member,
                icon.playerName or (member and member.name),
                scenarioHpByKey
            )
            icon.lastRosterDead = IsRosterMemberDead(member)
            ApplyIconOverlays(icon)
        end,
    }
end

local function EnsureGroupIconsDriverShowing()
    if DoesWindowExist(c_GROUPICONS_DRIVER) then
        WindowSetShowing(c_GROUPICONS_DRIVER, true)
    end
end

local function ScheduleWarmRefreshRosterPolling(minAttempts)
    m_postEnableWarmRefreshPoll = 0
    if not WantRosterWorldMarkers() then
        m_postEnableWarmRefreshRemaining = 0
        return
    end
    local attempts = tonumber(minAttempts) or c_WARM_REFRESH_ATTEMPTS
    attempts = math.max(1, math.floor(attempts + 0.5))
    if (tonumber(m_postEnableWarmRefreshRemaining) or 0) < attempts then
        m_postEnableWarmRefreshRemaining = attempts
    end
end

local function CheckRosterWorldObjChanges()
    local s = EnsureSettings()
    local inScenario = IsScenarioContext()
    
    local function checkMember(partyIndex, memberIndex, member)
        if not member or not member.name then
            return false
        end
        member = HydrateRosterMemberForAttach(partyIndex, memberIndex, member)
        local icon = m_icons[partyIndex][memberIndex]
        local liveWid = LiveAttachWorldId(member)
        local resolvedWid = ResolveRosterIconAttachWorldId(member.name, liveWid)
        if resolvedWid ~= icon.worldObjNum then
            return true
        end
        return false
    end

    local function wantCheck(member, partyGate)
        if partyGate then
            return true
        end
        return member ~= nil and IsSocialHighlightedName(member.name)
    end

    if inScenario then
        if s.showParty or s.highlightSocial then
            local data = (type(PartyUtils) == "table" and type(PartyUtils.GetPartyData) == "function") and PartyUtils.GetPartyData() or GetGroupData()
            if type(data) == "table" then
                for m = 1, c_MAX_MEMBERS do
                    local member = GetPartySlotMember(m, data)
                    if wantCheck(member, s.showParty == true) and checkMember(1, m, member) then
                        return true
                    end
                end
            end
        end
    elseif IsWarBandActive() then
        local showAll = s.showWarband == true
        local showParty1 = s.showParty == true
        local parties = (type(Roster.GetWarbandParties) == "function" and Roster.GetWarbandParties(nil)) or GetBattlegroupMemberData()
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
                    local shouldShow = showAll or (showParty1 and p == 1)
                    if wantCheck(member, shouldShow) and checkMember(p, m, member) then
                        return true
                    end
                end
            end
        end
    elseif s.showParty or s.highlightSocial then
        local data = (type(PartyUtils) == "table" and type(PartyUtils.GetPartyData) == "function") and PartyUtils.GetPartyData() or GetGroupData()
        if type(data) == "table" then
            for m = 1, c_MAX_MEMBERS do
                local member = GetPartySlotMember(m, data)
                if wantCheck(member, s.showParty == true) and checkMember(1, m, member) then
                    return true
                end
            end
        end
    end
    return false
end

local function RebindAllRosterWorldObjects()
    for p = 1, c_MAX_PARTIES do
        for m = 1, c_MAX_MEMBERS do
            local icon = m_icons[p][m]
            if icon and icon.isEnabled and icon.worldObjNum ~= 0 then
                icon:RebindWorldObject()
            end
        end
    end
end

local function RebindAllOutsiderWorldObjects()
    for wid, slotIdx in pairs(m_trackWidToSlot) do
        if wid ~= nil and slotIdx ~= nil then
            local icon = m_outsiderPool[slotIdx]
            if icon and icon.isEnabled and icon.worldObjNum ~= 0 then
                icon:RebindWorldObject()
            end
        end
    end
end

--- Re-issue engine attach for every live roster + outsider marker (after another addon mutates world binds).
function CustomUI.GroupIcons.RebindAllTrackedWorldObjects()
    if type(CustomUI.IsComponentEnabled) == "function" and not CustomUI.IsComponentEnabled("GroupIcons") then
        return
    end
    RebindAllRosterWorldObjects()
    RebindAllOutsiderWorldObjects()
end

local function WarmRefreshRosterIfNeeded(dt)
    if m_postEnableWarmRefreshRemaining <= 0 then
        return
    end
    if not WantRosterWorldMarkers() then
        m_postEnableWarmRefreshRemaining = 0
        m_postEnableWarmRefreshPoll = 0
        return
    end
    -- Stop early only when every *live* roster wid is attached. Lua wid match after /reloadui can still
    -- be unbound in the engine — rebind once before stopping (Enemy Detach+Attach on ObjectWindow:Attach).
    if RosterLiveWorldIdsFullyAttached() then
        RebindAllRosterWorldObjects()
        m_postEnableWarmRefreshRemaining = 0
        m_postEnableWarmRefreshPoll = 0
        return
    end
    m_postEnableWarmRefreshPoll = (m_postEnableWarmRefreshPoll or 0) + dt
    if m_postEnableWarmRefreshPoll >= c_WARM_REFRESH_INTERVAL then
        m_postEnableWarmRefreshPoll = 0
        m_postEnableWarmRefreshRemaining = m_postEnableWarmRefreshRemaining - 1
        m_needsRefreshAll = true
        RebindAllRosterWorldObjects()
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

local function WantScenarioThreatStream()
    if type(CustomUI.IsComponentEnabled) == "function" and not CustomUI.IsComponentEnabled("GroupIcons") then
        return false
    end
    return EnsureSettings().showScenarioThreat == true and IsScenarioContext() == true
end

SyncScenarioStatsStream = function()
    if type(ScenarioStats.EnsureStockSummaryHook) == "function" then
        ScenarioStats.EnsureStockSummaryHook(function()
            if type(ScenarioStats.MarkStopped) == "function" then
                ScenarioStats.MarkStopped()
            end
            if WantScenarioThreatStream() then
                ScenarioStats.Start()
            end
        end)
    end
    if WantScenarioThreatStream() then
        if type(ScenarioStats.Start) == "function" then
            ScenarioStats.Start()
        end
        RefreshThreatWinnersFromScenarioPlayers()
        ApplyAllLiveIconOverlays()
    else
        if type(ScenarioStats.Stop) == "function" then
            ScenarioStats.Stop()
        end
        ClearThreatWinners()
        ApplyAllLiveIconOverlays()
    end
end

-- Refresh from party data (group / solo).
local function RefreshParty()
    if type(Roster.RefreshParty) == "function" then
        Roster.RefreshParty(GetRosterState(), RosterRefreshOpts())
        return
    end
    local data = nil
    if type(PartyUtils) == "table" and type(PartyUtils.GetPartyData) == "function" then
        data = PartyUtils.GetPartyData()
    end
    if data == nil then
        data = GetGroupData()
    end
    if not data then return end
    local showPartyIcons = EnsureSettings().showParty == true
    local attachable = 0
    local validStickyKeys = {}
    for m = 1, c_MAX_MEMBERS do
        local member = GetPartySlotMember(m, data)
        local icon   = m_icons[1][m]
        local memberName = member and ToWString(member.name)
        local socialOnly = member ~= nil and IsSocialHighlightedName(member.name)
        local wantIcon = showPartyIcons or socialOnly
        if wantIcon and member and memberName ~= nil and memberName ~= L"" then
            local nk = NormalizeNameKey(member.name)
            if nk ~= nil then
                validStickyKeys[nk] = true
            end
            local liveWid = LiveAttachWorldId(member)
            local wid = ResolveRosterIconAttachWorldId(member.name, liveWid)
            RegisterGroupMember({ name = member.name, worldObjNum = (wid ~= 0 and wid) or nil })
            if wid ~= 0 and not IsSelfMember(memberName) then
                attachable = attachable + 1
            end
            if wid ~= 0 and not IsSelfMember(memberName) then
                icon:Enable()
                icon:Update(memberName, wid, member.careerLine, member.isGroupLeader == true, false)
                icon.lastRosterDead = IsRosterMemberDead(member)
                ApplyIconOverlays(icon)
            else
                icon:Disable()
            end
        else
            icon:Disable()
        end
    end
    PruneStickyRosterWids(validStickyKeys)
    DebugLog("RefreshParty: attachableMembers=" .. tostring(attachable)
        .. " showPartyIcons=" .. tostring(showPartyIcons))
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
-- (Other warband parties must not be RegisterGroupMember when hidden, or outsider realm icons never apply —
--  except Guild/Friends social members, who still get gold roster icons.)
-- partiesOverride: when non-nil, use instead of GetBattlegroupMemberData().
local function RefreshWarband(showAll, showParty1, partiesOverride)
    if type(Roster.RefreshWarband) == "function" then
        Roster.RefreshWarband(GetRosterState(), showAll, showParty1, partiesOverride, RosterRefreshOpts())
        return
    end
    local parties = (partiesOverride ~= nil and partiesOverride)
        or (type(Roster.GetWarbandParties) == "function" and Roster.GetWarbandParties(nil))
        or GetBattlegroupMemberData()
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
            local socialOnly = member ~= nil and IsSocialHighlightedName(member.name)
            if (shouldShow or socialOnly) and member and memberName ~= nil and memberName ~= L"" then
                local nk = NormalizeNameKey(member.name)
                if nk ~= nil then
                    validStickyKeys[nk] = true
                end
                local liveWid = LiveAttachWorldId(member)
                local wid = ResolveRosterIconAttachWorldId(member.name, liveWid)
                RegisterGroupMember({ name = member.name, worldObjNum = (wid ~= 0 and wid) or nil })
                if wid ~= 0 and not IsSelfMember(memberName) then
                    icon:Enable()
                    icon:Update(memberName, wid, member.careerLine, member.isGroupLeader == true, false)
                    icon.lastRosterDead = IsRosterMemberDead(member)
                    ApplyIconOverlays(icon)
                else
                    icon:Disable()
                end
            else
                -- Party-only warband: non-social members of other parties stay off the roster grid.
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
        .. " highlightSocial=" .. tostring(s.highlightSocial)
    )
    RegisterAllPartyWarbandMembersForPruning()
    -- Scenarios use party-only roster icons (row 1); other scenario players rely on outsider tracking.
    -- Guild/Friends can still attach gold on social party members when Party is off.
    if inScenario then
        if s.showParty or s.highlightSocial then
            RefreshParty()
        else
            DisableAll()
        end
    elseif IsWarBandActive() then
        RefreshWarband(s.showWarband == true, s.showParty == true, nil)
    elseif s.showParty or s.highlightSocial then
        RefreshParty()
    else
        -- No roster view in this context; ensure all roster slots are disabled.
        DisableAll()
    end

    PruneTrackedOutsidersAgainstRoster()
    if WantFriendlyOutsiderWarbandLeaders() then
        RequestWarbandLeaderData()
        OnWarbandLeaderListMaybeChanged()
    end
    RefreshRosterDeathOverlays()
    ApplyAllLiveIconOverlays()
end

----------------------------------------------------------------
-- Event handlers
----------------------------------------------------------------

function CustomUI.GroupIcons.OnUpdate(timePassed)
    if type(CustomUI.IsComponentEnabled) == "function" and not CustomUI.IsComponentEnabled("GroupIcons") then
        return
    end
    local dt = tonumber(timePassed) or 0

    if type(WarbandLeaders.TickRequestCooldown) == "function" then
        WarbandLeaders.TickRequestCooldown(dt)
    end

    if WantFriendlyOutsiderWarbandLeaders() then
        m_friendlyLeaderPollElapsed = m_friendlyLeaderPollElapsed + dt
        if m_friendlyLeaderPollElapsed >= c_FRIENDLY_LEADER_POLL_INTERVAL then
            m_friendlyLeaderPollElapsed = 0
            RequestWarbandLeaderData()
            OnWarbandLeaderListMaybeChanged()
        end
    else
        m_friendlyLeaderPollElapsed = 0
    end

    if m_pendingRosterAttachCheck then
        m_pendingRosterAttachCheck = false
        if CheckRosterWorldObjChanges() then
            m_needsRefreshAll = true
        end
    end

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
        RefreshOutsiderDeathFlags()
    elseif m_pendingOutsiderHealthRefresh then
        RefreshOutsiderDeathFlags()
    end
    m_pendingOutsiderHealthRefresh = false
    if m_pendingRosterDeathRefresh then
        m_pendingRosterDeathRefresh = false
        RefreshRosterDeathOverlays()
    end
    WarmRefreshRosterIfNeeded(dt)

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

    -- Map GetMapPointData for walking-rez skull clear: ~1Hz, not every spatial probe tick.
    if next(m_outsiderDeadWids) then
        m_deadMotionMapElapsed = m_deadMotionMapElapsed + dt
        if m_deadMotionMapElapsed >= c_DEAD_MOTION_MAP_INTERVAL then
            m_deadMotionMapElapsed = 0
            ClearOutsiderDeadFromIndependentMotion()
        end
    else
        m_deadMotionMapElapsed = 0
    end
    m_rosterValidateElapsed = m_rosterValidateElapsed + dt
    if m_rosterValidateElapsed >= c_ROSTER_WID_VALIDATE_INTERVAL then
        m_rosterValidateElapsed = 0
        ValidateRosterIconWorldObjects()
        if CheckRosterWorldObjChanges() then
            m_needsRefreshAll = true
        end
        if next(m_outsiderDeadWids) then
            ClearOutsiderDeadFromScenarioHealth()
        end
        RefreshRosterDeathOverlays()
    end
end

function CustomUI.GroupIcons.OnOpenPartyUpdated()
    ScheduleWarmRefreshRosterPolling()
    OnWarbandLeaderListMaybeChanged()
end

function CustomUI.GroupIcons.OnPlayerChapterUpdated()
    if WantFriendlyOutsiderWarbandLeaders()
        and GameData and GameData.Player
        and tonumber(GameData.Player.influenceID) ~= 0
    then
        RequestWarbandLeaderData()
    end
end

function CustomUI.GroupIcons.OnGroupUpdated()
    ScheduleWarmRefreshRosterPolling()
    OnWarbandLeaderListMaybeChanged()
    m_needsRefreshAll = true
end

function CustomUI.GroupIcons.OnGroupStatusUpdated(memberIndex)
    m_pendingRosterDeathRefresh = true
    if SlotAttachNeedsRefresh(1, memberIndex) then
        m_needsRefreshAll = true
    elseif memberIndex == nil then
        m_pendingRosterAttachCheck = true
    end
end

function CustomUI.GroupIcons.OnBattlegroupUpdated()
    ScheduleWarmRefreshRosterPolling()
    OnWarbandLeaderListMaybeChanged()
    m_needsRefreshAll = true
end

function CustomUI.GroupIcons.OnBattlegroupMemberUpdated(groupIndex, memberIndex)
    m_pendingRosterDeathRefresh = true
    if SlotAttachNeedsRefresh(groupIndex, memberIndex) then
        m_needsRefreshAll = true
    elseif groupIndex == nil or memberIndex == nil then
        m_pendingRosterAttachCheck = true
    end
end

function CustomUI.GroupIcons.OnScenarioUpdated()
    m_scenarioHitHp = {}
    ScheduleWarmRefreshRosterPolling()
    m_needsRefreshAll = true
    SyncScenarioStatsStream()
end

function CustomUI.GroupIcons.OnScenarioPlayersStatsUpdated()
    if type(CustomUI.IsComponentEnabled) == "function" and not CustomUI.IsComponentEnabled("GroupIcons") then
        return
    end
    if EnsureSettings().showScenarioThreat ~= true or not IsScenarioContext() then
        return
    end
    RefreshThreatWinnersFromScenarioPlayers()
    ApplyAllLiveIconOverlays()
end

function CustomUI.GroupIcons.OnInterfaceReady()
    -- Stock UI commonly rebuilds windows from INTERFACE_RELOADED in addition to LOADING_END.
    -- Driver is CreateWindow(..., false); keep it shown so OnUpdate/warm refresh keep ticking after reload.
    EnsureGroupIconsDriverShowing()
    RememberAttachZoneId()
    RefreshSocialNameSets()
    ScheduleWarmRefreshRosterPolling()
    RequestWarbandLeaderData()
    OnWarbandLeaderListMaybeChanged()
    m_needsRefreshAll = true
    SyncScenarioStatsStream()
end

function CustomUI.GroupIcons.OnSocialListsUpdated()
    RefreshSocialNameSets()
    m_needsRefreshAll = true
end

function CustomUI.GroupIcons.OnZoneChanged()
    local zone = CurrentPlayerZoneId()
    local loadingZone = (zone == nil or zone == 0)
    local sameZone = (not loadingZone and m_lastAttachZoneId ~= nil and zone == m_lastAttachZoneId)
    -- /reloadui can fire PLAYER_ZONE_CHANGED with 0 or the current zone; keep sticky/known ids then.
    if not sameZone and not loadingZone then
        m_stickyRosterWidByKey = {}
        m_knownByNameKey = {}
        UntrackAllOutsiders()
        ResetWorldProbeCalibration()
        m_lastAttachZoneId = zone
    end
    RememberAttachZoneId()
    RefreshSocialNameSets()
    ScheduleWarmRefreshRosterPolling()
    m_friendlyLeaderPollElapsed = 0
    RequestWarbandLeaderData()
    OnWarbandLeaderListMaybeChanged()
    m_needsRefreshAll = true
    SyncScenarioStatsStream()
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

function CustomUI.GroupIcons.OnPlayerTargetHitPointsUpdated()
    -- TargetInfo HP is updated in place; do not call UpdateFromClient. Merge dead flags next tick.
    m_pendingOutsiderHealthRefresh = true
end

function CustomUI.GroupIcons.OnScenarioPlayerHitsUpdated(groupIndex, groupSlotNum, hits)
    local gi = tonumber(groupIndex)
    local mi = tonumber(groupSlotNum)
    if gi ~= nil and mi ~= nil then
        m_scenarioHitHp[gi] = m_scenarioHitHp[gi] or {}
        m_scenarioHitHp[gi][mi] = tonumber(hits)
    end
    m_pendingOutsiderHealthRefresh = true
    m_pendingRosterDeathRefresh = true
end

function CustomUI.GroupIcons.OnSettingsChanged()
    -- Settings tab may change Party/Warband/etc. while the component is disabled; never RefreshAll then or
    -- icons would attach (handlers are unregistered but this path is called directly from settings UI).
    if type(CustomUI.IsComponentEnabled) == "function" and not CustomUI.IsComponentEnabled("GroupIcons") then
        return
    end
    -- Hostile/friendly toggles can invalidate existing tracked outsiders; clear them.
    UntrackAllOutsiders()
    ResetWorldProbeCalibration()
    ScheduleWarmRefreshRosterPolling()
    m_needsRefreshAll = true
    SyncScenarioStatsStream()
end

----------------------------------------------------------------
-- Component adapter
----------------------------------------------------------------

local GroupIconsComponent = {}

-- Event handlers attach to CustomUIGroupIconsDriver (not Root). Programmatic
-- WindowRegisterEventHandler bindings are cleared by destroying the driver window;
-- WindowUnregisterEventHandler only works for handlers registered this session on that window.

local function WorldEventHandlers()
    local events = SystemData and SystemData.Events
    if not events then
        return nil
    end
    return {
        { events.GROUP_UPDATED, "CustomUI.GroupIcons.OnGroupUpdated" },
        { events.GROUP_STATUS_UPDATED, "CustomUI.GroupIcons.OnGroupStatusUpdated" },
        { events.GROUP_PLAYER_ADDED, "CustomUI.GroupIcons.OnGroupUpdated" },
        { events.BATTLEGROUP_UPDATED, "CustomUI.GroupIcons.OnBattlegroupUpdated" },
        { events.BATTLEGROUP_MEMBER_UPDATED, "CustomUI.GroupIcons.OnBattlegroupMemberUpdated" },
        { events.SCENARIO_GROUP_UPDATED, "CustomUI.GroupIcons.OnScenarioUpdated" },
        { events.SCENARIO_PLAYERS_LIST_GROUPS_UPDATED, "CustomUI.GroupIcons.OnScenarioUpdated" },
        { events.SCENARIO_BEGIN, "CustomUI.GroupIcons.OnScenarioUpdated" },
        { events.SCENARIO_END, "CustomUI.GroupIcons.OnScenarioUpdated" },
        { events.CITY_SCENARIO_BEGIN, "CustomUI.GroupIcons.OnScenarioUpdated" },
        { events.CITY_SCENARIO_END, "CustomUI.GroupIcons.OnScenarioUpdated" },
        { events.SCENARIO_PLAYERS_LIST_STATS_UPDATED, "CustomUI.GroupIcons.OnScenarioPlayersStatsUpdated" },
        { events.SCENARIO_PLAYER_HITS_UPDATED, "CustomUI.GroupIcons.OnScenarioPlayerHitsUpdated" },
        { events.PLAYER_ZONE_CHANGED, "CustomUI.GroupIcons.OnZoneChanged" },
        { events.PLAYER_TARGET_UPDATED, "CustomUI.GroupIcons.OnPlayerTargetUpdated" },
        { events.PLAYER_TARGET_HIT_POINTS_UPDATED, "CustomUI.GroupIcons.OnPlayerTargetHitPointsUpdated" },
        { events.LOADING_END, "CustomUI.GroupIcons.OnInterfaceReady" },
        { events.ENTER_WORLD, "CustomUI.GroupIcons.OnInterfaceReady" },
        { events.INTERFACE_RELOADED, "CustomUI.GroupIcons.OnInterfaceReady" },
        { events.ALL_MODULES_INITIALIZED, "CustomUI.GroupIcons.OnInterfaceReady" },
        { events.GROUP_SETTINGS_PRIVACY_UPDATED, "CustomUI.GroupIcons.OnOpenPartyUpdated" },
        { events.SOCIAL_OPENPARTYINTEREST_UPDATED, "CustomUI.GroupIcons.OnOpenPartyUpdated" },
        { events.PLAYER_CHAPTER_UPDATED, "CustomUI.GroupIcons.OnPlayerChapterUpdated" },
        { events.SOCIAL_OPENPARTY_UPDATED, "CustomUI.GroupIcons.OnOpenPartyUpdated" },
        { events.SOCIAL_OPENPARTY_WORLD_UPDATED, "CustomUI.GroupIcons.OnOpenPartyUpdated" },
        { events.SOCIAL_OPENPARTY_NOTIFY, "CustomUI.GroupIcons.OnOpenPartyUpdated" },
        { events.SOCIAL_FRIENDS_UPDATED, "CustomUI.GroupIcons.OnSocialListsUpdated" },
        { events.GUILD_MEMBER_UPDATED, "CustomUI.GroupIcons.OnSocialListsUpdated" },
        { events.GUILD_MEMBER_ADDED, "CustomUI.GroupIcons.OnSocialListsUpdated" },
        { events.GUILD_MEMBER_REMOVED, "CustomUI.GroupIcons.OnSocialListsUpdated" },
    }
end

local function ResetGroupIconsDriverWindow()
    if type(DestroyWindow) == "function" and DoesWindowExist(c_GROUPICONS_DRIVER) then
        CustomUI.TryCallQuiet("GroupIcons.DestroyDriver", DestroyWindow, c_GROUPICONS_DRIVER)
    end
    if type(CreateWindow) == "function" and not DoesWindowExist(c_GROUPICONS_DRIVER) then
        CustomUI.TryCallQuiet("GroupIcons.CreateDriver", CreateWindow, c_GROUPICONS_DRIVER, false)
    end
end

local function RegisterWorldEvents()
    if m_handlersRegistered then
        return
    end
    local pairsList = WorldEventHandlers()
    if not pairsList or type(WindowRegisterEventHandler) ~= "function" then
        return
    end
    if not DoesWindowExist(c_GROUPICONS_DRIVER) then
        return
    end
    for i = 1, #pairsList do
        local ev, handler = pairsList[i][1], pairsList[i][2]
        if ev then
            CustomUI.TryCallQuiet(
                "GroupIcons.Register " .. tostring(handler),
                WindowRegisterEventHandler,
                c_GROUPICONS_DRIVER,
                ev,
                handler
            )
        end
    end
    m_handlersRegistered = true
end

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
    ResetGroupIconsDriverWindow()
    EnsureGroupIconsDriverShowing()
    RegisterWorldEvents()
    -- First ticks after Enable re-run roster attach until late roster worldObj ids arrive (common after /reloadui).
    RefreshSocialNameSets()
    RememberAttachZoneId()
    m_needsRefreshAll = true
    ScheduleWarmRefreshRosterPolling()
    RequestWarbandLeaderData()
    OnWarbandLeaderListMaybeChanged()
    SyncScenarioStatsStream()
    return true
end

function GroupIconsComponent:Disable()
    if type(DestroyWindow) == "function" and DoesWindowExist(c_GROUPICONS_DRIVER) then
        CustomUI.TryCallQuiet("GroupIcons.DestroyDriver", DestroyWindow, c_GROUPICONS_DRIVER)
    end
    m_handlersRegistered = false
    m_postEnableWarmRefreshRemaining = 0
    m_postEnableWarmRefreshPoll = 0
    m_pendingOutsiderClassifications = {}
    m_pendingOutsiderHealthRefresh = false
    m_pendingRosterDeathRefresh = false
    m_pendingRosterAttachCheck = false
    if type(ScenarioStats.Stop) == "function" then
        ScenarioStats.Stop()
    end
    ClearThreatWinners()
    m_outsiderDeadWids = {}
    m_deadMotionByWid = {}
    m_deadMotionLandmarks = {}
    m_deadMotionMapElapsed = 0
    m_scenarioHitHp = {}
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
