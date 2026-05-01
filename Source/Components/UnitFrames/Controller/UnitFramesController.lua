----------------------------------------------------------------
-- CustomUI.UnitFrames — Controller
--
-- View: UnitFrames.xml (CustomUIBGMember row template, HP/AP art, borders). No View/*.lua.
-- Load order: CustomUI.mod loads UnitFramesModel → Events → Renderer → Adapters (stubs) → this file → XML.
--
-- Runtime behavior:
--   • Layout: showActionPointsBar (default false); colorMemberNamesByArchetype; sortPartyMembersByRole (default false — reorder party/warband rows only; scenario unchanged).
--   • Display modes (CustomUI.Settings.UnitFrames groupsParty / groupsWarband / groupsScenario): scenario roster,
--     open-world warband (4×6), warband-own-party-only (player's battlegroup party via IsPlayerInWarband, no GetPartyData), plain party (Enemy slot order),
--     or idle — hides custom frames and restores stock
--     BattlegroupHUD / FloatingScenarioGroup windows when mode is "none".
--   • Window lists: CustomUI.UnitFramesEvents (stock vs CustomUI group names for LayoutEditor UserShow/UserHide).
--   • CustomUIUnitFramesRoot: hosts OnUpdate (visibility poll, scenario map distance scan, target/mouseover borders)
--     and engine events; WindowSetShowing(true) while component enabled so ticks run (see EnsureRootWindowInstances).
--   • Hooks BattlegroupHUD background opacity menu/slide to keep CustomUI member tint in sync with stock control.
--   • Target ring (friendly selffriendlytarget), mouseover ring via SystemData.MouseOverWindow + parent walk + WStringToString.
--   • Scenario roster/HITS/distance parity target Enemy.Core.Groups (Enemy/Code/Core/Groups/Groups.lua + EnemyPlayer:LoadFromScenarioData),
--     not Enemy/Code/UnitFrames/*.lua (those frames mostly pull ScenarioSummaryWindow for unrelated UI paths).
--     RoR-only extras: IsScenarioModeActive also respects isInScenarioGroup + live GetScenarioPlayerGroups rows when flags lag;
--     ScenarioCareerLineFromScenarioPlayer adds Icons careerNames fallback after Enemy.ScenarioCareerIdToLine-equivalent map.
--   • Model / Renderer / Adapters: loaded stubs — factories no-op today; logic stays in this controller until wired.
----------------------------------------------------------------

if not CustomUI then
    CustomUI = {}
end

if not CustomUI.UnitFrames then
    CustomUI.UnitFrames = {}
end

local UnitFrames = CustomUI.UnitFrames
UnitFrames.WindowSettings = UnitFrames.WindowSettings or {}

local c_ROOT_WINDOW_NAME = "CustomUIUnitFramesRoot"
local c_MAX_GROUP_WINDOWS = 6
local c_WARBAND_GROUPS = 4
local c_GROUP_MEMBERS = 6
local c_VISIBILITY_POLL_INTERVAL = 0.25
local c_SCENARIO_DISTANCE_POLL_INTERVAL = 1.0
local c_DISTANT_DISTANCE = 250
local c_OPACITY_MIN = 0
local c_OPACITY_MAX = 1
local c_OPACITY_FULL_SNAP_THRESHOLD = 0.995
local c_DEFAULT_BACKGROUND_ALPHA = 0.25
local c_HEALTH_PCT_LABEL_RGB = { r = 255, g = 255, b = 255 }
local c_MEMBER_NAME_DEFAULT_RGB = { r = 255, g = 255, b = 255 }

local IsScenarioModeActive

local function EnsureUnitFramesGroupsSettings()
    CustomUI.Settings = CustomUI.Settings or { Components = {} }
    if CustomUI.Settings.Components == nil then
        CustomUI.Settings.Components = {}
    end
    if type(CustomUI.Settings.UnitFrames) ~= "table" then
        CustomUI.Settings.UnitFrames = {}
    end
    local s = CustomUI.Settings.UnitFrames
    if s.groupsParty == nil then
        s.groupsParty = false
    end
    if s.groupsWarband == nil then
        s.groupsWarband = true
    end
    if s.groupsScenario == nil then
        s.groupsScenario = true
    end
    if s.showActionPointsBar == nil then
        s.showActionPointsBar = false
    end
    if s.colorMemberNamesByArchetype == nil then
        s.colorMemberNamesByArchetype = false
    end
    if s.sortPartyMembersByRole == nil then
        s.sortPartyMembersByRole = false
    end
    return s
end

local function ShouldSortPartyMembersByRole()
    return EnsureUnitFramesGroupsSettings().sortPartyMembersByRole == true
end

local function ShouldColorUnitFramesMemberNamesByArchetype()
    return EnsureUnitFramesGroupsSettings().colorMemberNamesByArchetype == true
end

local function ShouldShowUnitFramesActionPointsBar()
    return EnsureUnitFramesGroupsSettings().showActionPointsBar == true
end

local function ApplyUnitFramesApBarWindowShowing(memberWindow)
    local apWin = tostring(memberWindow or "") .. "APBar"
    if DoesWindowExist(apWin) then
        WindowSetShowing(apWin, ShouldShowUnitFramesActionPointsBar())
    end
end

--- True when GetScenarioPlayerGroups has rows in an assigned scenario party (sgroupindex > 0).
local function ScenarioRosterHasAssignedGroups()
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

--- Full scenario roster (CustomUI 6×6) when the user opted in, even if IsWarBandActive() wins first:
--- open ShowWarband uses EA_Window_OpenPartyManageWarband*Show toggles and often leaves only party 1 visible.
local function ShouldUseScenarioGroupLayout(s)
    if s.groupsScenario ~= true then
        return false
    end
    if IsScenarioModeActive() then
        return true
    end
    if not ScenarioRosterHasAssignedGroups() then
        return false
    end
    if type(IsWarBandActive) == "function" and IsWarBandActive() then
        return true
    end
    local p = GameData and GameData.Player
    if p and (p.isInScenario == true or p.isInSiege == true or p.isInScenarioGroup == true) then
        return true
    end
    return false
end

--- Resolved visibility mode for ApplyModeVisibility / borders / scenario polls (not identical to IsScenarioModeActive alone).
local function GetActiveUnitFramesDisplayMode()
    local s = EnsureUnitFramesGroupsSettings()
    if ShouldUseScenarioGroupLayout(s) then
        return "scenario"
    end
    if IsScenarioModeActive() then
        if s.groupsParty == true then
            return "party"
        end
        return "none"
    end
    -- In a battlegroup, PartyUtils.GetPartyData is for "other members" (group window); use warband APIs instead.
    -- Enemy: warband uses GetWarbandData; plain group uses GetPartyData with self at slot 1 (see Enemy._GroupsUpdate).
    if type(IsWarBandActive) == "function" and IsWarBandActive() then
        if s.groupsWarband == true then
            return "warband"
        end
        if s.groupsParty == true then
            return "warband_party1"
        end
        return "none"
    end
    if s.groupsParty == true and type(PartyUtils) == "table" and type(PartyUtils.IsPartyActive) == "function" and PartyUtils.IsPartyActive() then
        return "party"
    end
    return "none"
end

local m_enabled = false
local m_windowsInitialized = false
local m_visibilityPollElapsed = 0
local SafeLayoutUserShow
local SafeLayoutUserHide
local m_stockOnMenuClickSetBackgroundOpacity = nil
local m_stockOnOpacitySlide = nil
local m_eventsRegistered = false
local m_debugLastMode = nil
local m_debugLastInitSig = nil
local m_debugLastScenarioSig = nil
local m_scenarioDistancePollElapsed = 0
--- When mode is warband_party1, UI uses CustomUIUnitFramesGroup1* but data comes from this battlegroup party index (PartyUtils.IsPlayerInWarband).
local m_warbandPartyOnlyDataPartyIndex = nil

--- sortPartyMembersByRole: display slot -> member for hit-test/target parity (display slot != PartyUtils slot when sorted).
local m_partySortedDisplayMembers = nil
local m_warbandSortedDisplayMembers = {}

-- Scenario distance snapshot from map points (Enemy-style).
-- { [nameKey] = { distance = number, isDistant = boolean } }
local m_scenarioDistanceByKey = {}

local function DebugLog(msg)
    if type(d) == "function" then
        -- Must not depend on local ToWString (defined later in file).
        d(towstring("[CustomUI.UnitFrames] " .. tostring(msg)))
    end
end

-- Scenario HP overrides from SCENARIO_PLAYER_HITS_UPDATED (Enemy Groups_OnScenarioPlayerHitsUpdated).
-- Invalidate cache whenever roster slots change: overrides are keyed by (group, slot); stale entries cause wrong HP (e.g. stuck at 1%).
local m_scenarioHitHp = {}

-- Scenario roster uses compact careerId values (Enemy.ScenarioCareerIdToLine), not the same numbering as Icons.careers / PartyUtils warband members.
-- Source reference: Enemy/Code/Core/Constants.lua
local c_SCENARIO_CAREER_ID_TO_LINE = {
    [20] = GameData.CareerLine.IRON_BREAKER,
    [100] = GameData.CareerLine.SWORDMASTER,
    [64] = GameData.CareerLine.CHOSEN,
    [24] = GameData.CareerLine.BLACK_ORC,
    [60] = GameData.CareerLine.WITCH_HUNTER,
    [102] = GameData.CareerLine.WHITE_LION,
    [65] = GameData.CareerLine.MARAUDER,
    [105] = GameData.CareerLine.WITCH_ELF,
    [62] = GameData.CareerLine.BRIGHT_WIZARD,
    [67] = GameData.CareerLine.MAGUS,
    [107] = GameData.CareerLine.SORCERER,
    [23] = GameData.CareerLine.ENGINEER,
    [101] = GameData.CareerLine.SHADOW_WARRIOR,
    [27] = GameData.CareerLine.SQUIG_HERDER,
    [63] = GameData.CareerLine.WARRIOR_PRIEST,
    [106] = GameData.CareerLine.DISCIPLE,
    [103] = GameData.CareerLine.ARCHMAGE,
    [26] = GameData.CareerLine.SHAMAN,
    [22] = GameData.CareerLine.RUNE_PRIEST,
    [66] = GameData.CareerLine.ZEALOT,
    [104] = GameData.CareerLine.BLACKGUARD,
    [61] = GameData.CareerLine.KNIGHT,
    [25] = GameData.CareerLine.CHOPPA,
    [21] = GameData.CareerLine.SLAYER or GameData.CareerLine.HAMMERER,
}

-- Party/warband display sort (sortPartyMembersByRole): bucket order tank → melee DPS → ranged DPS → heal → unknown.
local c_UF_SORT_BUCKET_UNKNOWN = 9
local c_UF_SORT_TANK = {
    [GameData.CareerLine.IRON_BREAKER] = true,
    [GameData.CareerLine.SWORDMASTER] = true,
    [GameData.CareerLine.CHOSEN] = true,
    [GameData.CareerLine.BLACK_ORC] = true,
    [GameData.CareerLine.KNIGHT] = true,
    [GameData.CareerLine.BLACKGUARD] = true,
}
local c_UF_SORT_MELEE_DPS = {
    [GameData.CareerLine.WITCH_HUNTER] = true,
    [GameData.CareerLine.WHITE_LION] = true,
    [GameData.CareerLine.MARAUDER] = true,
    [GameData.CareerLine.WITCH_ELF] = true,
    [GameData.CareerLine.CHOPPA] = true,
}
local c_UF_SORT_RANGED_DPS = {
    [GameData.CareerLine.BRIGHT_WIZARD] = true,
    [GameData.CareerLine.MAGUS] = true,
    [GameData.CareerLine.SORCERER] = true,
    [GameData.CareerLine.ENGINEER] = true,
    [GameData.CareerLine.SHADOW_WARRIOR] = true,
    [GameData.CareerLine.SQUIG_HERDER] = true,
}
local c_UF_SORT_HEAL = {
    [GameData.CareerLine.WARRIOR_PRIEST] = true,
    [GameData.CareerLine.DISCIPLE] = true,
    [GameData.CareerLine.ARCHMAGE] = true,
    [GameData.CareerLine.SHAMAN] = true,
    [GameData.CareerLine.RUNE_PRIEST] = true,
    [GameData.CareerLine.ZEALOT] = true,
}
if GameData.CareerLine.SLAYER then
    c_UF_SORT_MELEE_DPS[GameData.CareerLine.SLAYER] = true
end
if GameData.CareerLine.HAMMERER then
    c_UF_SORT_MELEE_DPS[GameData.CareerLine.HAMMERER] = true
end

-- Forward decls (used by target-highlight helpers below).
local IsWarbandModeActive
local MemberWindowName
local TryGetWarbandMember
local TryGetPartyFrameMember
local GetGroupMemberIndicesFromWindowName
local BuildScenarioGroupMap
local ShowScenarioDualModeWindows

-- Target highlight state (friendly target only; same classification string as EA_BattlegroupHUD).
local c_FRIENDLY_TARGET = "selffriendlytarget"
local m_currentTargetId = 0
local m_currentTargetName = nil
local m_mouseOverMemberWindow = nil

local function ToWString(v)
    if v == nil then
        return nil
    end
    if type(v) == "string" then
        return towstring(v)
    end
    return v
end

local function ToLuaString(v)
    if v == nil then
        return nil
    end

    return tostring(v)
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

local function NormalizeNameKey(name)
    local s = ToNameString(name)
    if s == nil or s == "" then
        return nil
    end
    return string.lower(s)
end

--- Match Enemy.FixString + lowercase for overhead-map pip names (strip grammar segment from first '^').
local function FixScenarioMapNameKey(name)
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

local function NamesMatch(memberName, targetName)
    local memberText = ToLuaString(memberName)
    local targetText = ToLuaString(targetName)
    if memberText == nil or targetText == nil or memberText == "" or targetText == "" then
        return false
    end

    if memberText == targetText then
        return true
    end

    -- Stock WStringsCompareIgnoreGrammer strips a leading grammar marker but uses
    -- '<' internally, which can crash on mixed string/wstring values on this client.
    return string.sub(memberText, 2) == string.sub(targetText, 2)
end

local function MemberHasDisplayName(member)
    local memberName = ToWString(member and member.name)
    return member ~= nil and memberName ~= nil and memberName ~= L""
end

local function UnitFramesSortBucketForCareerLine(line)
    line = tonumber(line)
    if line == nil then
        return c_UF_SORT_BUCKET_UNKNOWN
    end
    if c_UF_SORT_TANK[line] then
        return 1
    end
    if c_UF_SORT_MELEE_DPS[line] then
        return 2
    end
    if c_UF_SORT_RANGED_DPS[line] then
        return 3
    end
    if c_UF_SORT_HEAL[line] then
        return 4
    end
    return c_UF_SORT_BUCKET_UNKNOWN
end

local function CareerAlphabeticalSortKey(line)
    line = tonumber(line)
    if line == nil or type(GetCareerLine) ~= "function" then
        return "~"
    end
    local w = GetCareerLine(line, nil)
    local s = ToNameString(w)
    if s == nil or s == "" then
        return "~"
    end
    return string.lower(s)
end

local function BattleRankDescendingSortKey(member)
    return tonumber(member and member.battleLevel) or tonumber(member and member.battleRank) or 0
end

--- Stable ordering: role bucket → career name A→Z → renown rank (battleLevel) descending → original collection order.
local function SortMembersForUnitFramesDisplay(members)
    if type(members) ~= "table" or table.getn(members) < 2 then
        return members
    end
    local enriched = {}
    for i = 1, table.getn(members) do
        local m = members[i]
        local line = m and m.careerLine
        table.insert(enriched, {
            m = m,
            bucket = UnitFramesSortBucketForCareerLine(line),
            careerKey = CareerAlphabeticalSortKey(line),
            br = BattleRankDescendingSortKey(m),
            ord = i,
        })
    end
    table.sort(enriched, function(a, b)
        if a.bucket ~= b.bucket then
            return a.bucket < b.bucket
        end
        if a.careerKey ~= b.careerKey then
            return a.careerKey < b.careerKey
        end
        if a.br ~= b.br then
            return a.br > b.br
        end
        return a.ord < b.ord
    end)
    local out = {}
    for i = 1, table.getn(enriched) do
        out[i] = enriched[i].m
    end
    return out
end

local function IsMemberCurrentFriendlyTarget(member)
    if member == nil then
        return false
    end
    local currentTargetId = tonumber(m_currentTargetId)
    local memberWorldObjNum = tonumber(member.worldObjNum)
    if currentTargetId ~= nil and currentTargetId ~= 0 and memberWorldObjNum ~= nil and memberWorldObjNum ~= 0 and memberWorldObjNum == currentTargetId then
        return true
    end
    local memberName = ToWString(member and member.name)
    if m_currentTargetName ~= nil and memberName ~= nil and memberName ~= L"" then
        local targetName = ToWString(m_currentTargetName)
        if memberName == nil or targetName == nil then
            return false
        end
        return NamesMatch(memberName, targetName)
    end
    return false
end

--- Career line for icons/AP tint: match EnemyPlayer:LoadFromScenarioData → Enemy.ScenarioCareerIdToLine[careerId] first,
--- then RoR Icons reverse-map when careerId is in Careers-names space; raw roster careerLine only if still unknown.
local function ScenarioCareerLineFromScenarioPlayer(player)
    if player == nil then
        return nil
    end
    local cid = tonumber(player.careerId)
    if cid ~= nil and c_SCENARIO_CAREER_ID_TO_LINE[cid] ~= nil then
        return c_SCENARIO_CAREER_ID_TO_LINE[cid]
    end
    if cid ~= nil and type(Icons) == "table" and type(Icons.GetCareerIconIDFromCareerNamesID) == "function" and type(Icons.careerLines) == "table" then
        local iconId = Icons.GetCareerIconIDFromCareerNamesID(cid)
        if iconId ~= nil and iconId ~= 0 then
            for lineIdx, lineIcon in pairs(Icons.careerLines) do
                if type(lineIdx) == "number" and lineIcon == iconId then
                    return lineIdx
                end
            end
        end
    end
    local fromMember = tonumber(player.careerLine)
    if fromMember ~= nil and fromMember ~= 0 then
        return fromMember
    end
    return nil
end

local function GetMergedScenarioHealthPercent(groupIndex, memberIndex, player)
    local base = tonumber(player and player.health) or 0
    local t = m_scenarioHitHp[groupIndex]
    if t == nil then
        return base
    end
    local hit = t[memberIndex]
    if hit == nil then
        return base
    end
    -- hits == 0 means dead; do not use `or base` — in Lua 0 is falsy and would wrongly restore roster HP.
    local merged = tonumber(hit)
    if merged == nil then
        return base
    end
    return merged
end

local function ClampPercent(v)
    local n = tonumber(v) or 0
    if n < 0 then n = 0 end
    if n > 100 then n = 100 end
    return n
end

--- Scenario roster / hits often carry float noise; sub-1% reads as dead UX-wise (stock ScenarioGroupWindow uses integer % bands).
local function SnapScenarioHpPercentNearZero(hpPct)
    local x = ClampPercent(hpPct)
    if x > 0 and x < 1 then
        return 0
    end
    return x
end

--- snapNearZero: roster/hits-only (stock uses integer hit%); omit for local player cur/max float.
local function RoundScenarioHpForDisplay(hpPct, snapNearZero)
    local x = ClampPercent(tonumber(hpPct) or 0)
    if snapNearZero then
        x = SnapScenarioHpPercentNearZero(x)
    end
    return math.floor(x + 0.5)
end

--- Minimal warband-shaped row for targeting / borders (scenario roster lacks PartyUtils fields).
local function ScenarioPlayerAsTargetMember(player, groupIndex, memberIndex)
    if player == nil then
        return nil
    end
    local hpRaw = GetMergedScenarioHealthPercent(groupIndex, memberIndex, player)
    local selfRow = GameData and GameData.Player and GameData.Player.name and player.name
        and NamesMatch(player.name, GameData.Player.name)
    local hp = RoundScenarioHpForDisplay(hpRaw, not selfRow)
    local wid = tonumber(player.worldObjNum or player.worldobjnum or player.entityId or player.entityid) or 0
    return {
        name = player.name,
        worldObjNum = wid,
        healthPercent = hp,
        online = true,
    }
end

local function RefreshTargetBorders()
    if not m_enabled then
        return
    end
    local mode = GetActiveUnitFramesDisplayMode()
    if mode == "scenario" then
        local groups = BuildScenarioGroupMap()
        for groupIndex = 1, c_MAX_GROUP_WINDOWS do
            for memberIndex = 1, c_GROUP_MEMBERS do
                local memberWindow = MemberWindowName(groupIndex, memberIndex)
                local border = memberWindow .. "TargetBorder"
                if DoesWindowExist(border) then
                    local player = groups[groupIndex] and groups[groupIndex][memberIndex]
                    local pseudo = ScenarioPlayerAsTargetMember(player, groupIndex, memberIndex)
                    WindowSetShowing(border, IsMemberCurrentFriendlyTarget(pseudo))
                end
            end
        end
        return
    end
    if mode == "warband" or mode == "warband_party1" then
        local maxG = (mode == "warband_party1") and 1 or c_WARBAND_GROUPS
        for groupIndex = 1, maxG do
            for memberIndex = 1, c_GROUP_MEMBERS do
                local memberWindow = MemberWindowName(groupIndex, memberIndex)
                local border = memberWindow .. "TargetBorder"
                if DoesWindowExist(border) then
                    local member = TryGetWarbandMember(groupIndex, memberIndex)
                    WindowSetShowing(border, IsMemberCurrentFriendlyTarget(member))
                end
            end
        end
        return
    end
    if mode == "party" then
        for memberIndex = 1, c_GROUP_MEMBERS do
            local memberWindow = MemberWindowName(1, memberIndex)
            local border = memberWindow .. "TargetBorder"
            if DoesWindowExist(border) then
                local member = TryGetPartyFrameMember(1, memberIndex)
                WindowSetShowing(border, IsMemberCurrentFriendlyTarget(member))
            end
        end
    end
end

local function SetMouseOverBorderShowing(memberWindow, show)
    local border = tostring(memberWindow or "") .. "MouseOverBorder"
    if DoesWindowExist(border) then
        WindowSetShowing(border, show == true)
    end
end

local function RefreshMouseOverBorders()
    if not m_enabled then
        m_mouseOverMemberWindow = nil
    end

    for groupIndex = 1, c_MAX_GROUP_WINDOWS do
        for memberIndex = 1, c_GROUP_MEMBERS do
            local memberWindow = MemberWindowName(groupIndex, memberIndex)
            SetMouseOverBorderShowing(memberWindow, m_mouseOverMemberWindow == memberWindow)
        end
    end
end

function UnitFrames.OnMemberMouseOver()
    local groupIndex, memberIndex = GetGroupMemberIndicesFromWindowName(SystemData.ActiveWindow.name)
    if groupIndex == nil or memberIndex == nil then
        return
    end

    local memberWindow = MemberWindowName(groupIndex, memberIndex)
    if m_mouseOverMemberWindow ~= memberWindow then
        if m_mouseOverMemberWindow ~= nil then
            SetMouseOverBorderShowing(m_mouseOverMemberWindow, false)
        end
        m_mouseOverMemberWindow = memberWindow
    end

    SetMouseOverBorderShowing(memberWindow, true)
end

function UnitFrames.OnMemberMouseOverEnd()
    local groupIndex, memberIndex = GetGroupMemberIndicesFromWindowName(SystemData.ActiveWindow.name)
    if groupIndex ~= nil and memberIndex ~= nil then
        local memberWindow = MemberWindowName(groupIndex, memberIndex)
        SetMouseOverBorderShowing(memberWindow, false)
        if m_mouseOverMemberWindow == memberWindow then
            m_mouseOverMemberWindow = nil
        end
        return
    end

    if m_mouseOverMemberWindow ~= nil then
        SetMouseOverBorderShowing(m_mouseOverMemberWindow, false)
        m_mouseOverMemberWindow = nil
    end
end

function UnitFrames.OnTargetUpdated(targetClassification, targetId, targetType)
    if targetClassification ~= c_FRIENDLY_TARGET then
        return
    end
    m_currentTargetId = tonumber(targetId) or 0
    m_currentTargetName = nil
    if type(TargetInfo) == "table" and type(TargetInfo.UnitName) == "function" then
        local nm = TargetInfo:UnitName(c_FRIENDLY_TARGET)
        if type(nm) == "string" then
            nm = towstring(nm)
        end
        m_currentTargetName = nm
    end
    RefreshTargetBorders()
end

IsScenarioModeActive = function()
    if GameData == nil or GameData.Player == nil then
        return false
    end
    local p = GameData.Player
    if p.isInScenario == true or p.isInSiege == true then
        return true
    end
    if p.isInScenarioGroup == true then
        return true
    end
    -- RoR: scenario roster can arrive before isInScenario flips; mirror GroupIcons / ScenarioGroupWindow data source.
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

IsWarbandModeActive = function()
    if IsScenarioModeActive() then
        return false
    end

    if type(IsWarBandActive) == "function" then
        return IsWarBandActive()
    end

    return false
end

local function GroupWindowName(groupIndex)
    return "CustomUIUnitFramesGroup" .. groupIndex .. "Window"
end

MemberWindowName = function(groupIndex, memberIndex)
    return GroupWindowName(groupIndex) .. "Member" .. memberIndex
end

local function IsLayoutEditorReady()
    return type(LayoutEditor) == "table"
        and type(LayoutEditor.RegisterWindow) == "function"
        and type(LayoutEditor.UserShow) == "function"
        and type(LayoutEditor.UserHide) == "function"
        and type(LayoutEditor.windowsList) == "table"
end

local function ForEachWindow(windowList, callback)
    if type(callback) ~= "function" then
        return
    end

    for _, windowName in ipairs(windowList or {}) do
        callback(windowName)
    end
end

local function SafeLayoutRegister(windowName, displayName, description)
    if not IsLayoutEditorReady() then
        return false
    end

    if not DoesWindowExist(windowName) then
        return false
    end

    if LayoutEditor.windowsList[windowName] ~= nil then
        return true
    end

    LayoutEditor.RegisterWindow(windowName, displayName, description, false, false, true, nil)
    return LayoutEditor.windowsList[windowName] ~= nil
end

SafeLayoutUserShow = function(windowName)
    if not DoesWindowExist(windowName) then
        return
    end
    if IsLayoutEditorReady() and LayoutEditor.windowsList[windowName] ~= nil then
        LayoutEditor.UserShow(windowName)
        return
    end
    -- Fallback: if the layout editor isn't ready/registered yet, still show the window.
    if type(WindowSetShowing) == "function" then
        WindowSetShowing(windowName, true)
    end
end

SafeLayoutUserHide = function(windowName)
    if not DoesWindowExist(windowName) then
        return
    end
    if IsLayoutEditorReady() and LayoutEditor.windowsList[windowName] ~= nil then
        LayoutEditor.UserHide(windowName)
        return
    end
    -- Fallback: if the layout editor isn't ready/registered yet, still hide the window.
    if type(WindowSetShowing) == "function" then
        WindowSetShowing(windowName, false)
    end
end

local function GetWindowSets()
    local events = CustomUI.UnitFramesEvents or {}
    return {
        customDualMode = events.CustomDualModeWindows or {},
        stockWarband = events.StockWarbandWindows or {},
        stockScenario = events.StockScenarioFloatingWindows or {},
    }
end

local function RegisterCustomWindowsForLayout()
    -- LayoutEditor is used for persistence + user show/hide, but UnitFrames must function even if
    -- the layout editor isn't ready yet (eg early load / scenario transition).
    if not IsLayoutEditorReady() then
        return true
    end

    local windowSets = GetWindowSets()
    local anyRegistered = false

    for _, windowName in ipairs(windowSets.customDualMode) do
        local registered = SafeLayoutRegister(windowName, towstring("CustomUI: " .. windowName), L"CustomUI UnitFrames dual-mode group window")
        anyRegistered = anyRegistered or (registered == true)
        SafeLayoutUserHide(windowName)
    end

    -- Do not gate feature behavior on layout-editor registration success; we can still show/hide via WindowSetShowing.
    return anyRegistered or true
end

local function HideAllStockWindows()
    local windowSets = GetWindowSets()
    ForEachWindow(windowSets.stockWarband, SafeLayoutUserHide)
    ForEachWindow(windowSets.stockScenario, SafeLayoutUserHide)
end

local function HideAllCustomWindows()
    local windowSets = GetWindowSets()
    ForEachWindow(windowSets.customDualMode, SafeLayoutUserHide)
end

local function SetMemberWindowShowing(groupIndex, memberIndex, isShowing)
    local memberWindow = MemberWindowName(groupIndex, memberIndex)
    if DoesWindowExist(memberWindow) then
        WindowSetShowing(memberWindow, isShowing)
    end
end

--- Engine window names are often wstrings; string.match fails unless normalized.
local function NarrowWindowName(raw)
    if raw == nil then
        return ""
    end
    if type(raw) == "string" then
        return raw
    end
    if type(WStringToString) == "function" then
        local ok, s = pcall(WStringToString, raw)
        if ok and type(s) == "string" and s ~= "" then
            return s
        end
    end
    return tostring(raw) or ""
end

local function SetUnitFramesTickWindowShowing(show)
    if not DoesWindowExist(c_ROOT_WINDOW_NAME) or type(WindowSetShowing) ~= "function" then
        return
    end
    WindowSetShowing(c_ROOT_WINDOW_NAME, show == true)
end

local function IsUnitFramesMemberWindowName(windowName)
    local narrow = NarrowWindowName(windowName)
    if narrow == "" then
        return false
    end

    return string.match(narrow, "^CustomUIUnitFramesGroup%d+WindowMember%d+$") ~= nil
end

local function SetUnitFramesBackgroundAlpha(alpha)
    for groupIndex = 1, c_MAX_GROUP_WINDOWS do
        for memberIndex = 1, c_GROUP_MEMBERS do
            local memberWindow = MemberWindowName(groupIndex, memberIndex)
            local backgroundWindow = memberWindow .. "Background"
            if DoesWindowExist(backgroundWindow) then
                WindowSetAlpha(backgroundWindow, alpha)
            end
        end
    end
end

local function ClampAlpha(value)
    local alpha = tonumber(value)
    if alpha == nil then
        return c_OPACITY_MIN
    end

    if alpha < c_OPACITY_MIN then
        return c_OPACITY_MIN
    end

    if alpha > c_OPACITY_MAX then
        return c_OPACITY_MAX
    end

    if alpha >= c_OPACITY_FULL_SNAP_THRESHOLD then
        return c_OPACITY_MAX
    end

    return alpha
end

local function GetStockWarbandBackgroundAlpha()
    local stockBackgroundWindow = "BattlegroupHUDGroup1LayoutWindowMember1Background"
    if DoesWindowExist(stockBackgroundWindow) then
        local liveAlpha = tonumber(WindowGetAlpha(stockBackgroundWindow))
        if liveAlpha ~= nil then
            if liveAlpha < 0 then
                return 0
            end
            if liveAlpha > 1 then
                return 1
            end
            return liveAlpha
        end
    end

    if type(BattlegroupHUD) ~= "table"
    or type(BattlegroupHUD.WindowSettings) ~= "table" then
        return nil
    end

    local alpha = tonumber(BattlegroupHUD.WindowSettings.backgroundAlpha)
    if alpha == nil then
        return nil
    end

    if alpha < 0 then
        return 0
    end

    if alpha > 1 then
        return 1
    end

    return alpha
end

local function SetStockWarbandBackgroundAlpha(alpha)
    if type(BattlegroupHUD) ~= "table" then
        return
    end

    local resolvedAlpha = ClampAlpha(alpha)

    if type(BattlegroupHUD.WindowSettings) ~= "table" then
        BattlegroupHUD.WindowSettings = {}
    end

    BattlegroupHUD.WindowSettings.backgroundAlpha = resolvedAlpha

    if type(BattlegroupHUD.SetBackgroundAlpha) == "function" then
        BattlegroupHUD.SetBackgroundAlpha(resolvedAlpha)
    end
end

local function IsWarbandGroupVisibleByStockToggle(groupIndex)
    if EA_Window_OpenPartyManage == nil then
        return true
    end

    local buttonName = "EA_Window_OpenPartyManageWarband" .. groupIndex .. "Show"
    if not DoesWindowExist(buttonName) then
        return true
    end

    return ButtonGetPressedFlag(buttonName)
end

local function IsScenarioGroupVisibleByStockToggle(groupIndex)
    local buttonName = "ScenarioGroupWindowGroup" .. groupIndex .. "VisibleButton"
    if DoesWindowExist(buttonName) then
        return ButtonGetPressedFlag(buttonName)
    end

    if ScenarioGroupWindow ~= nil
    and ScenarioGroupWindow.GroupWindowSettings ~= nil
    and ScenarioGroupWindow.GroupWindowSettings.floatingVisibility ~= nil then
        local saved = ScenarioGroupWindow.GroupWindowSettings.floatingVisibility[groupIndex]
        if saved ~= nil then
            return saved
        end
    end

    -- Fallback to visible when scenario controls are not available.
    return true
end

local function SetCareerIcon(memberWindow, member)
    if member == nil or member.careerLine == nil then
        return
    end

    local iconId = Icons.GetCareerIconIDFromCareerLine(member.careerLine)
    if iconId == nil then
        return
    end

    local iconTexture, iconX, iconY = GetIconData(iconId)
    if iconTexture ~= nil then
        DynamicImageSetTexture(memberWindow .. "CareerIcon", iconTexture, iconX, iconY)
    end
end

local function SetScenarioCareerIcon(memberWindow, player)
    if player == nil then
        return
    end

    local careerLine = ScenarioCareerLineFromScenarioPlayer(player)
    local iconId = nil
    if careerLine ~= nil then
        iconId = Icons.GetCareerIconIDFromCareerLine(careerLine)
    end
    if iconId == nil and player.careerId ~= nil then
        iconId = Icons.GetCareerIconIDFromCareerNamesID(player.careerId)
    end
    if iconId == nil then
        return
    end

    local iconTexture, iconX, iconY = GetIconData(iconId)
    if iconTexture ~= nil then
        DynamicImageSetTexture(memberWindow .. "CareerIcon", iconTexture, iconX, iconY)
    end
end

local function SetMemberBars(memberWindow, member)
    local hp = tonumber(member.healthPercent) or 0
    local ap = tonumber(member.actionPointPercent) or 0

    if hp < 0 then hp = 0 end
    if hp > 100 then hp = 100 end
    if ap < 0 then ap = 0 end
    if ap > 100 then ap = 100 end

    StatusBarSetMaximumValue(memberWindow .. "HPBar", 100)
    StatusBarSetMaximumValue(memberWindow .. "APBar", 100)
    StatusBarSetCurrentValue(memberWindow .. "HPBar", hp)
    StatusBarSetCurrentValue(memberWindow .. "APBar", ap)
    ApplyUnitFramesApBarWindowShowing(memberWindow)
end

local function SetScenarioMemberBars(memberWindow, player, groupIndex, memberIndex)
    -- Local player: match PlayerStatusWindow — absolute current/max on bars (not 0–100 scale).
    if player ~= nil and GameData and GameData.Player and GameData.Player.name
        and NamesMatch(player.name, GameData.Player.name) then
        local p = GameData.Player
        local hpCur = tonumber(p.hitPoints and p.hitPoints.current) or 0
        local hpMax = tonumber(p.hitPoints and p.hitPoints.maximum) or 1
        local apCur = tonumber(p.actionPoints and p.actionPoints.current) or 0
        local apMax = tonumber(p.actionPoints and p.actionPoints.maximum) or 1
        if hpMax < 1 then hpMax = 1 end
        if apMax < 1 then apMax = 1 end
        StatusBarSetMaximumValue(memberWindow .. "HPBar", hpMax)
        StatusBarSetCurrentValue(memberWindow .. "HPBar", hpCur)
        StatusBarSetMaximumValue(memberWindow .. "APBar", apMax)
        StatusBarSetCurrentValue(memberWindow .. "APBar", apCur)
        ApplyUnitFramesApBarWindowShowing(memberWindow)
        return
    end

    local hp = tonumber(player.health) or 0
    if groupIndex ~= nil and memberIndex ~= nil then
        hp = GetMergedScenarioHealthPercent(groupIndex, memberIndex, player)
    end
    hp = SnapScenarioHpPercentNearZero(hp)
    local ap = tonumber(player.ap) or 0

    if hp < 0 then hp = 0 end
    if hp > 100 then hp = 100 end
    if ap < 0 then ap = 0 end
    if ap > 100 then ap = 100 end

    StatusBarSetMaximumValue(memberWindow .. "HPBar", 100)
    StatusBarSetMaximumValue(memberWindow .. "APBar", 100)
    StatusBarSetCurrentValue(memberWindow .. "HPBar", hp)
    -- Match ScenarioGroupWindow.UpdateSingleMemberHitPoints: AP reads 0 while dead.
    if hp <= 0 then
        StatusBarSetCurrentValue(memberWindow .. "APBar", 0)
    else
        StatusBarSetCurrentValue(memberWindow .. "APBar", ap)
    end
    ApplyUnitFramesApBarWindowShowing(memberWindow)
end

local function RoundApPercentForDisplay(apPct)
    return math.floor(ClampPercent(tonumber(apPct) or 0) + 0.5)
end

--- Match ScenarioGroupWindow.UpdateSingleMemberHitPoints: alive iff hp==100 or (0 < hp < 100). Uses integer percent only.
local function ScenarioStockAliveIntegerBand(hpRounded)
    local h = tonumber(hpRounded) or 0
    if h == 100 then
        return true
    end
    if h > 0 and h < 100 then
        return true
    end
    return false
end

local function ScenarioHitsExplicitZero(groupIndex, memberIndex)
    local t = m_scenarioHitHp[groupIndex]
    if t == nil then
        return false
    end
    local hit = t[memberIndex]
    return hit ~= nil and tonumber(hit) == 0
end

local function TryBuildSelfScenarioRow()
    if GameData == nil or GameData.Player == nil then
        return nil
    end
    local p = GameData.Player
    if p.name == nil or p.name == L"" then
        return nil
    end

    local hp = 0
    if p.hitPoints and p.hitPoints.current and p.hitPoints.maximum and tonumber(p.hitPoints.maximum) and tonumber(p.hitPoints.maximum) > 0 then
        hp = 100 * (tonumber(p.hitPoints.current) / tonumber(p.hitPoints.maximum))
    end
    local ap = 0
    if p.actionPoints and p.actionPoints.current and p.actionPoints.maximum and tonumber(p.actionPoints.maximum) and tonumber(p.actionPoints.maximum) > 0 then
        ap = 100 * (tonumber(p.actionPoints.current) / tonumber(p.actionPoints.maximum))
    end

    return {
        name = p.name,
        worldObjNum = p.worldObjNum,
        -- Scenario code paths use these fields:
        health = RoundScenarioHpForDisplay(hp, false),
        ap = RoundApPercentForDisplay(ap),
        careerLine = p.career and p.career.line,
        careerId = nil,
        isMainAssist = false,
    }
end

local function IsSelfScenarioName(name)
    if name == nil or GameData == nil or GameData.Player == nil or GameData.Player.name == nil then
        return false
    end
    return NamesMatch(name, GameData.Player.name)
end

local function ResolveScenarioPlayer(player)
    -- Scenario roster rows can be stale for the local player; prefer live GameData.Player values.
    local nm = player and player.name
    if nm ~= nil and IsSelfScenarioName(nm) then
        local selfRow = TryBuildSelfScenarioRow()
        if selfRow ~= nil then
            return selfRow
        end
    end
    return player
end

local function ScanScenarioDistancesFromMapPoints()
    if type(GetMapPointData) ~= "function" then
        return
    end

    -- Build quick set of scenario roster names (grouped only).
    local rosterKeySet = {}
    local groups = BuildScenarioGroupMap()
    for gi = 1, c_MAX_GROUP_WINDOWS do
        for mi = 1, c_GROUP_MEMBERS do
            local pl = groups[gi] and groups[gi][mi]
            local key = FixScenarioMapNameKey(pl and pl.name)
            if key ~= nil then
                rosterKeySet[key] = true
            end
        end
    end

    if next(rosterKeySet) == nil then
        return
    end

    -- Same pip whitelist as Enemy.GroupsInitialize MapPointTypeFilter (PLAYER intentionally omitted there).
    local MapPointTypeFilter = {
        [SystemData.MapPips.GROUP_MEMBER] = true,
        [SystemData.MapPips.WARBAND_MEMBER] = true,
        [SystemData.MapPips.DESTRUCTION_ARMY] = true,
        [SystemData.MapPips.ORDER_ARMY] = true,
    }

    local DISTANCE_FIX_COEFFICIENT = 1 / 1.06
    local updated = 0

    -- NOTE: Enemy.GroupsInitialize scans MAX_MAP_POINTS = 511; distance uses math.floor(dist * coeff) (no half-round).
    for k = 1, 511 do
        local mpd = GetMapPointData("EA_Window_OverheadMapMapDisplay", k)
        if mpd and mpd.pointType and MapPointTypeFilter[mpd.pointType] and mpd.name then
            local key = FixScenarioMapNameKey(mpd.name)
            if key ~= nil and rosterKeySet[key] then
                local dist = math.floor((tonumber(mpd.distance) or 0) * DISTANCE_FIX_COEFFICIENT)
                m_scenarioDistanceByKey[key] = { distance = dist, isDistant = dist >= c_DISTANT_DISTANCE }
                updated = updated + 1
            end
        end
    end

    if updated > 0 then
        DebugLog("Scenario distance scan: updated=" .. tostring(updated))
        if m_enabled and m_windowsInitialized and GetActiveUnitFramesDisplayMode() == "scenario" then
            ShowScenarioDualModeWindows()
        end
    end
end

--- showBars is legacy (reserved). hideHpBarForDistant: hide only the HP StatusBar (green fill + red missing-HP track).
--- Row backdrop stays the same EA_FullResizeImage tint as stock BGMember; do not hide it (stock keeps it when distant).
--- healthLabelRgb: when non-nil, LabelHealth uses this (numeric "%" display stays white); offline/dead/distant keep nil.
local function ApplyStatusSettings(memberWindow, color, alpha, showBars, hideHpBarForDistant, healthLabelRgb)
    local hr, hg, hb = color.r, color.g, color.b
    if healthLabelRgb ~= nil then
        hr = healthLabelRgb.r
        hg = healthLabelRgb.g
        hb = healthLabelRgb.b
    end
    LabelSetTextColor(memberWindow .. "LabelHealth", hr, hg, hb)
    WindowSetFontAlpha(memberWindow .. "LabelHealth", alpha)
    WindowSetShowing(memberWindow .. "HPBar", hideHpBarForDistant ~= true)
    WindowSetShowing(memberWindow .. "Background", true)
    local bgWin = memberWindow .. "Background"
    if DoesWindowExist(bgWin) then
        local a = UnitFrames.WindowSettings and UnitFrames.WindowSettings.backgroundAlpha
        if a == nil then
            a = c_DEFAULT_BACKGROUND_ALPHA
        end
        WindowSetAlpha(bgWin, ClampAlpha(a))
    end
    ApplyUnitFramesApBarWindowShowing(memberWindow)
end

--- Default white names; optional archetype tint via CustomUI.Settings.UnitFrames.colorMemberNamesByArchetype + GroupIcons RGB helper. RvR stays yellow.
local function ApplyMemberLabelNameColor(memberWindow, careerLine, isRvrFlagged)
    if isRvrFlagged then
        LabelSetTextColor(memberWindow .. "LabelName", DefaultColor.YELLOW.r, DefaultColor.YELLOW.g, DefaultColor.YELLOW.b)
        return
    end
    if not ShouldColorUnitFramesMemberNamesByArchetype() then
        LabelSetTextColor(memberWindow .. "LabelName", c_MEMBER_NAME_DEFAULT_RGB.r, c_MEMBER_NAME_DEFAULT_RGB.g, c_MEMBER_NAME_DEFAULT_RGB.b)
        return
    end
    local r, g, b = DefaultColor.NAME_COLOR_PLAYER.r, DefaultColor.NAME_COLOR_PLAYER.g, DefaultColor.NAME_COLOR_PLAYER.b
    if type(CustomUI.GroupIcons) == "table" and type(CustomUI.GroupIcons.GetArchetypeTintRgbForCareerLine) == "function" then
        r, g, b = CustomUI.GroupIcons.GetArchetypeTintRgbForCareerLine(careerLine)
    end
    LabelSetTextColor(memberWindow .. "LabelName", r, g, b)
end

local function ApplyDistantHealthIndicator(memberWindow, showClock)
    local icon = memberWindow .. "DistantIcon"
    if DoesWindowExist(icon) then
        WindowSetShowing(icon, showClock == true)
    end
end

TryGetWarbandMember = function(groupIndex, memberIndex)
    if type(PartyUtils) ~= "table" or type(PartyUtils.GetWarbandMember) ~= "function" then
        return nil
    end

    local dataParty = groupIndex
    if m_warbandPartyOnlyDataPartyIndex ~= nil and groupIndex == 1 then
        dataParty = m_warbandPartyOnlyDataPartyIndex
    end
    if ShouldSortPartyMembersByRole() then
        local row = m_warbandSortedDisplayMembers[dataParty]
        if row ~= nil then
            return row[memberIndex]
        end
    end
    return PartyUtils.GetWarbandMember(dataParty, memberIndex)
end

--- Plain-party source rows: slot 1 = local snapshot; mates = PartyUtils.GetPartyMember / GetPartyData. With sortPartyMembersByRole, display order is reshuffled (no slot-1 self guarantee).
local function BuildLocalPlayerPartyMemberSnapshot()
    if GameData == nil or GameData.Player == nil then
        return nil
    end
    local p = GameData.Player
    if p.name == nil or p.name == L"" then
        return nil
    end
    local hp = 0
    if p.hitPoints and tonumber(p.hitPoints.maximum) and tonumber(p.hitPoints.maximum) > 0 then
        hp = 100 * (tonumber(p.hitPoints.current) or 0) / tonumber(p.hitPoints.maximum)
    end
    local ap = 0
    if p.actionPoints and tonumber(p.actionPoints.maximum) and tonumber(p.actionPoints.maximum) > 0 then
        ap = 100 * (tonumber(p.actionPoints.current) or 0) / tonumber(p.actionPoints.maximum)
    end
    if hp < 0 then hp = 0 elseif hp > 100 then hp = 100 end
    if ap < 0 then ap = 0 elseif ap > 100 then ap = 100 end
    local careerLine = nil
    if p.career ~= nil and p.career.line ~= nil then
        careerLine = p.career.line
    end
    return {
        name = p.name,
        healthPercent = hp,
        actionPointPercent = ap,
        moraleLevel = 0,
        level = tonumber(p.rank) or tonumber(p.level) or 0,
        battleLevel = tonumber(p.battleRank) or tonumber(p.battleLevel) or 0,
        isRVRFlagged = p.isRVRFlagged == true,
        zoneNum = tonumber(p.zoneNum) or tonumber(p.zoneNumber) or 0,
        online = true,
        isDistant = false,
        worldObjNum = tonumber(p.worldObjNum) or 0,
        isGroupLeader = p.isGroupLeader == true,
        careerLine = careerLine,
    }
end

local function GetPartySlotMemberForUnitFrames(memberIndex, fallbackData)
    if memberIndex == nil or memberIndex < 1 or memberIndex > c_GROUP_MEMBERS then
        return nil
    end
    if memberIndex == 1 then
        return BuildLocalPlayerPartyMemberSnapshot()
    end
    local mateIndex = memberIndex - 1
    if type(PartyUtils) == "table" and type(PartyUtils.GetPartyMember) == "function" then
        local maxWithoutSelf = tonumber(PartyUtils.PLAYERS_PER_PARTY_WITHOUT_LOCAL) or 5
        if mateIndex >= 1 and mateIndex <= maxWithoutSelf then
            local mem = PartyUtils.GetPartyMember(mateIndex)
            if mem ~= nil then
                return mem
            end
        end
    end
    if type(fallbackData) == "table" then
        return fallbackData[mateIndex]
    end
    return nil
end

TryGetPartyFrameMember = function(groupIndex, memberIndex)
    if groupIndex ~= 1 then
        return nil
    end
    if ShouldSortPartyMembersByRole() and m_partySortedDisplayMembers ~= nil then
        return m_partySortedDisplayMembers[memberIndex]
    end
    local data = nil
    if type(PartyUtils) == "table" and type(PartyUtils.GetPartyData) == "function" then
        data = PartyUtils.GetPartyData()
    end
    return GetPartySlotMemberForUnitFrames(memberIndex, data)
end

GetGroupMemberIndicesFromWindowName = function(windowName)
    local narrow = NarrowWindowName(windowName)
    local groupIndex, memberIndex = string.match(narrow or "", "^CustomUIUnitFramesGroup(%d+)WindowMember(%d+)")
    groupIndex = tonumber(groupIndex)
    memberIndex = tonumber(memberIndex)

    if groupIndex == nil or memberIndex == nil then
        return nil, nil
    end

    return groupIndex, memberIndex
end

--- HP/AP bars and labels sit above the member root; hit-tested widget is often a child, not BGMember.
--- Walk parents from SystemData.MouseOverWindow (stock pattern) until we hit CustomUIUnitFramesGroup*WindowMember*.
local function ResolveMemberWindowFromHoverWindowChain(startWindowName)
    local cur = NarrowWindowName(startWindowName)
    if cur == "" then
        return nil
    end
    local depth = 0
    while depth < 32 do
        local gi, mi = GetGroupMemberIndicesFromWindowName(cur)
        if gi ~= nil and mi ~= nil then
            return MemberWindowName(gi, mi)
        end
        if type(WindowGetParent) ~= "function" then
            break
        end
        local parent = WindowGetParent(cur)
        if parent == nil or parent == "" then
            break
        end
        local nextNarrow = NarrowWindowName(parent)
        if nextNarrow == "" or nextNarrow == cur then
            break
        end
        cur = nextNarrow
        depth = depth + 1
    end
    return nil
end

local function SyncMouseOverBorderFromGlobalHover()
    if not m_enabled or not m_windowsInitialized then
        return
    end
    local startName = nil
    local mo = SystemData and SystemData.MouseOverWindow
    if type(mo) == "table" and mo.name ~= nil then
        startName = mo.name
    elseif type(mo) == "string" or type(mo) == "userdata" then
        startName = mo
    end
    local hoverMember = ResolveMemberWindowFromHoverWindowChain(startName)
    if hoverMember ~= m_mouseOverMemberWindow then
        m_mouseOverMemberWindow = hoverMember
        RefreshMouseOverBorders()
    end
end

local function SetMemberSkullIconShowing(memberWindow, show)
    local skull = tostring(memberWindow or "") .. "SkullIcon"
    if DoesWindowExist(skull) then
        WindowSetShowing(skull, show == true)
    end
end

local function SetMemberTextAndState(memberWindow, member)
    local memberName = ToWString(member and member.name) or L""
    LabelSetText(memberWindow .. "LabelName", memberName)

    local healthText = towstring(tonumber(member.healthPercent) or 0) .. L"%"
    local hp = tonumber(member.healthPercent) or 0

    -- Dead before distant so skull + corpse styling win when both apply.
    local isDead = hp <= 0 and member.online == true

    if member.online ~= true then
        healthText = GetString(StringTables.Default.LABEL_PARTY_MEMBER_OFFLINE)
        ApplyStatusSettings(memberWindow, DefaultColor.HEALTH_TEXT_DEAD, 0.5, true)
        SetMemberSkullIconShowing(memberWindow, false)
    elseif isDead then
        healthText = L""
        ApplyStatusSettings(memberWindow, DefaultColor.HEALTH_TEXT_DEAD, 1.0, true)
        SetMemberSkullIconShowing(memberWindow, true)
    elseif member.isDistant then
        healthText = L""
        ApplyStatusSettings(memberWindow, DefaultColor.HEALTH_TEXT_DEAD, 0.5, true, true)
        SetMemberSkullIconShowing(memberWindow, false)
    elseif hp >= 100 and (tonumber(member.actionPointPercent) or 0) >= 100 then
        ApplyStatusSettings(memberWindow, DefaultColor.HEALTH_TEXT_FULL, 1.0, true, nil, c_HEALTH_PCT_LABEL_RGB)
        SetMemberSkullIconShowing(memberWindow, false)
    elseif hp > 0 then
        ApplyStatusSettings(memberWindow, DefaultColor.HEALTH_TEXT_NOT_FULL, 1.0, true, nil, c_HEALTH_PCT_LABEL_RGB)
        SetMemberSkullIconShowing(memberWindow, false)
    end

    LabelSetText(memberWindow .. "LabelHealth", healthText)
    ApplyDistantHealthIndicator(memberWindow, member.isDistant == true and member.online == true and not isDead)
    WindowSetGameActionData(memberWindow, GameData.PlayerActions.SET_TARGET, 0, memberName)

    if DoesWindowExist(memberWindow .. "TargetBorder") then
        WindowSetShowing(memberWindow .. "TargetBorder", IsMemberCurrentFriendlyTarget(member))
    end
end

local function SetScenarioMemberTextAndState(memberWindow, player, groupIndex, memberIndex)
    local playerName = ToWString(player and player.name) or L""
    LabelSetText(memberWindow .. "LabelName", playerName)
    local hpPct = tonumber(player.health) or 0
    if groupIndex ~= nil and memberIndex ~= nil then
        hpPct = GetMergedScenarioHealthPercent(groupIndex, memberIndex, player)
    end
    local selfScenario = player ~= nil and GameData and GameData.Player and GameData.Player.name
        and NamesMatch(player.name, GameData.Player.name)
    local selfHpCurZero = false
    if selfScenario and GameData.Player.hitPoints then
        local cur = tonumber(GameData.Player.hitPoints.current) or 0
        local max = tonumber(GameData.Player.hitPoints.maximum) or 1
        selfHpCurZero = (cur <= 0)
        if max > 0 then
            hpPct = ClampPercent(100 * cur / max)
        end
    end
    local apPct = tonumber(player and player.ap) or 0
    if selfScenario and GameData.Player.actionPoints then
        local ac = tonumber(GameData.Player.actionPoints.current) or 0
        local am = tonumber(GameData.Player.actionPoints.maximum) or 1
        if am > 0 then
            apPct = ClampPercent(100 * ac / am)
        end
    end

    local hpDisplay = RoundScenarioHpForDisplay(hpPct, not selfScenario)
    local apDisplay = RoundApPercentForDisplay(apPct)

    WindowSetGameActionData(memberWindow, GameData.PlayerActions.SET_TARGET, 0, playerName)

    local explicitHitsDead = (groupIndex ~= nil and memberIndex ~= nil) and ScenarioHitsExplicitZero(groupIndex, memberIndex)
    local isDead = explicitHitsDead
        or selfHpCurZero
        or not ScenarioStockAliveIntegerBand(hpDisplay)

    if DoesWindowExist(memberWindow .. "TargetBorder") then
        local pseudo = ScenarioPlayerAsTargetMember(player, groupIndex, memberIndex)
        WindowSetShowing(memberWindow .. "TargetBorder", IsMemberCurrentFriendlyTarget(pseudo))
    end

    -- Apply "distant" in scenario mode using map-point scan (Enemy-style).
    local isDistant = false
    local key = FixScenarioMapNameKey(player and player.name)
    local distInfo = key and m_scenarioDistanceByKey[key]
    if distInfo and distInfo.isDistant == true then
        isDistant = true
    end

    if isDead then
        LabelSetText(memberWindow .. "LabelHealth", L"")
        ApplyStatusSettings(memberWindow, DefaultColor.HEALTH_TEXT_DEAD, 1.0, false)
        SetMemberSkullIconShowing(memberWindow, true)
    elseif isDistant then
        LabelSetText(memberWindow .. "LabelHealth", L"")
        ApplyStatusSettings(memberWindow, DefaultColor.HEALTH_TEXT_DEAD, 0.5, true, true)
        SetMemberSkullIconShowing(memberWindow, false)
    else
        LabelSetText(memberWindow .. "LabelHealth", towstring(hpDisplay) .. L"%")
        SetMemberSkullIconShowing(memberWindow, false)
        if hpDisplay >= 100 and apDisplay >= 100 then
            ApplyStatusSettings(memberWindow, DefaultColor.HEALTH_TEXT_FULL, 0.5, false, nil, c_HEALTH_PCT_LABEL_RGB)
        else
            ApplyStatusSettings(memberWindow, DefaultColor.HEALTH_TEXT_NOT_FULL, 1.0, true, nil, c_HEALTH_PCT_LABEL_RGB)
        end
    end

    local careerLine = ScenarioCareerLineFromScenarioPlayer(player)
    if careerLine == nil and player ~= nil then
        careerLine = tonumber(player.careerLine)
    end
    ApplyMemberLabelNameColor(memberWindow, careerLine, false)

    ApplyDistantHealthIndicator(memberWindow, isDistant == true and not isDead)
end

local function UpdateWarbandMember(groupIndex, memberIndex, member)
    local memberWindow = MemberWindowName(groupIndex, memberIndex)
    if not DoesWindowExist(memberWindow) then
        return
    end

    SetMemberTextAndState(memberWindow, member)
    SetCareerIcon(memberWindow, member)
    SetMemberBars(memberWindow, member)

    local groupLeaderIcon = GroupWindowName(groupIndex) .. "GroupLeaderIcon"

    if member.isGroupLeader then
        WindowClearAnchors(groupLeaderIcon)
        WindowAddAnchor(groupLeaderIcon, "top", memberWindow .. "LabelName", "bottom", 0, 2)
    end

    ApplyMemberLabelNameColor(memberWindow, member and member.careerLine, member and member.isRVRFlagged == true)
end

--- @param respectStockWarbandToggle boolean|nil Default true — false forces visible when non-empty (CustomUI battlegroup "party only" mode).
--- @param warbandDataPartyIndex number|nil PartyUtils battlegroup party index for roster/stats; defaults to groupIndex (same slot on screen and in warband).
local function UpdateWarbandGroup(groupIndex, respectStockWarbandToggle, warbandDataPartyIndex)
    local groupWindow = GroupWindowName(groupIndex)
    if not DoesWindowExist(groupWindow) then
        return
    end

    if groupIndex > c_WARBAND_GROUPS then
        SafeLayoutUserHide(groupWindow)
        return
    end

    if respectStockWarbandToggle == nil then
        respectStockWarbandToggle = true
    end

    local dataParty = warbandDataPartyIndex or groupIndex

    local warbandParty = PartyUtils.GetWarbandParty(dataParty)
    local players = (warbandParty and warbandParty.players) or {}
    local numMembers = table.getn(players)

    local showGroup
    if respectStockWarbandToggle then
        showGroup = IsWarbandGroupVisibleByStockToggle(dataParty)
    else
        showGroup = numMembers >= 1
    end

    if not showGroup or numMembers < 1 then
        m_warbandSortedDisplayMembers[dataParty] = nil
        SafeLayoutUserHide(groupWindow)
        return
    end

    SafeLayoutUserShow(groupWindow)

    local sortedSlots = nil
    if ShouldSortPartyMembersByRole() then
        local collected = {}
        for mi = 1, c_GROUP_MEMBERS do
            local mm = PartyUtils.GetWarbandMember(dataParty, mi)
            if MemberHasDisplayName(mm) then
                table.insert(collected, mm)
            end
        end
        sortedSlots = SortMembersForUnitFramesDisplay(collected)
        m_warbandSortedDisplayMembers[dataParty] = {}
        for i = 1, table.getn(sortedSlots) do
            m_warbandSortedDisplayMembers[dataParty][i] = sortedSlots[i]
        end
    else
        m_warbandSortedDisplayMembers[dataParty] = nil
    end

    local foundLeader = false

    for memberIndex = 1, c_GROUP_MEMBERS do
        local member = sortedSlots and sortedSlots[memberIndex] or PartyUtils.GetWarbandMember(dataParty, memberIndex)
        local memberName = ToWString(member and member.name)
        if member ~= nil and memberName ~= nil and memberName ~= L"" then
            SetMemberWindowShowing(groupIndex, memberIndex, true)
            UpdateWarbandMember(groupIndex, memberIndex, member)

            if member.isGroupLeader then
                foundLeader = true
            end
        else
            SetMemberWindowShowing(groupIndex, memberIndex, false)
        end
    end

    WindowSetShowing(groupWindow .. "GroupLeaderIcon", foundLeader)
end

local function UpdatePartyOnlyGroup()
    local groupIndex = 1
    local groupWindow = GroupWindowName(groupIndex)
    if not DoesWindowExist(groupWindow) then
        return
    end

    if GameData and GameData.Party then
        GameData.Party.partyDirty = true
    end

    local data = nil
    if type(PartyUtils) == "table" and type(PartyUtils.GetPartyData) == "function" then
        data = PartyUtils.GetPartyData()
    end
    if data == nil and type(GetGroupData) == "function" then
        data = GetGroupData()
    end

    local sortedSlots = nil
    m_partySortedDisplayMembers = nil
    if ShouldSortPartyMembersByRole() then
        local collected = {}
        for mi = 1, c_GROUP_MEMBERS do
            local mm = GetPartySlotMemberForUnitFrames(mi, data)
            if MemberHasDisplayName(mm) then
                table.insert(collected, mm)
            end
        end
        sortedSlots = SortMembersForUnitFramesDisplay(collected)
        m_partySortedDisplayMembers = {}
        for i = 1, table.getn(sortedSlots) do
            m_partySortedDisplayMembers[i] = sortedSlots[i]
        end
    end

    local hasAny = false
    local foundLeader = false

    for memberIndex = 1, c_GROUP_MEMBERS do
        local member = sortedSlots and sortedSlots[memberIndex] or GetPartySlotMemberForUnitFrames(memberIndex, data)
        local memberName = ToWString(member and member.name)
        if member ~= nil and memberName ~= nil and memberName ~= L"" then
            hasAny = true
            SetMemberWindowShowing(groupIndex, memberIndex, true)
            UpdateWarbandMember(groupIndex, memberIndex, member)
            if member.isGroupLeader then
                foundLeader = true
            end
        else
            SetMemberWindowShowing(groupIndex, memberIndex, false)
        end
    end

    if hasAny then
        SafeLayoutUserShow(groupWindow)
    else
        SafeLayoutUserHide(groupWindow)
    end

    WindowSetShowing(groupWindow .. "GroupLeaderIcon", foundLeader)

    for g = 2, c_MAX_GROUP_WINDOWS do
        local gw = GroupWindowName(g)
        SafeLayoutUserHide(gw)
        if DoesWindowExist(gw) then
            WindowSetShowing(gw .. "GroupLeaderIcon", false)
        end
        for m = 1, c_GROUP_MEMBERS do
            SetMemberWindowShowing(g, m, false)
        end
    end
end

local function ShowPartyDualModeWindows()
    UpdatePartyOnlyGroup()
end

local function HideExtraGroupWindows(fromIndex)
    for g = fromIndex, c_MAX_GROUP_WINDOWS do
        local gw = GroupWindowName(g)
        SafeLayoutUserHide(gw)
        if DoesWindowExist(gw) then
            WindowSetShowing(gw .. "GroupLeaderIcon", false)
        end
        for m = 1, c_GROUP_MEMBERS do
            SetMemberWindowShowing(g, m, false)
        end
    end
end

--- Battlegroup with UnitFrames Party on + Warband off: show the party the local player belongs to (not always warband party slot 1).
local function ResolveLocalPlayerWarbandPartyIndex()
    if GameData == nil or GameData.Player == nil then
        return nil
    end
    local pname = GameData.Player.name
    if pname == nil or pname == L"" then
        return nil
    end
    if type(PartyUtils) ~= "table" or type(PartyUtils.IsPlayerInWarband) ~= "function" then
        return nil
    end
    local partyIndex = PartyUtils.IsPlayerInWarband(pname)
    partyIndex = tonumber(partyIndex)
    if partyIndex == nil or partyIndex < 1 or partyIndex > c_WARBAND_GROUPS then
        return nil
    end
    return partyIndex
end

local function ShowWarbandParty1DualModeWindows()
    m_warbandPartyOnlyDataPartyIndex = nil
    if GameData and GameData.Party then
        GameData.Party.partyDirty = true
        GameData.Party.warbandDirty = true
    end
    local dataParty = ResolveLocalPlayerWarbandPartyIndex()
    if dataParty == nil then
        HideExtraGroupWindows(1)
        return
    end
    m_warbandPartyOnlyDataPartyIndex = dataParty
    HideExtraGroupWindows(2)
    UpdateWarbandGroup(1, false, dataParty)
end

local function ShowWarbandDualModeWindows()
    for groupIndex = 1, c_MAX_GROUP_WINDOWS do
        UpdateWarbandGroup(groupIndex, true)
    end
end

-- Only scenario parties with sgroupindex > 0 (assigned groups). Ungrouped roster entries are intentionally ignored (GroupIcons covers broader marking separately).
BuildScenarioGroupMap = function()
    local groups = {}
    for groupIndex = 1, c_MAX_GROUP_WINDOWS do
        groups[groupIndex] = {}
    end

    if type(GameData.GetScenarioPlayerGroups) ~= "function" then
        return groups
    end

    local playerGroups = GameData.GetScenarioPlayerGroups() or {}
    local invalidEntries = 0

    for _, player in ipairs(playerGroups) do
        local groupIndex = tonumber(player.sgroupindex)
        local slotIndex = tonumber(player.sgroupslotnum)

        if groupIndex ~= nil and slotIndex ~= nil and groupIndex > 0
        and groupIndex >= 1 and groupIndex <= c_MAX_GROUP_WINDOWS
        and slotIndex >= 1 and slotIndex <= c_GROUP_MEMBERS then
            groups[groupIndex][slotIndex] = player
        else
            invalidEntries = invalidEntries + 1
        end
    end

    return groups
end

local function UpdateScenarioGroup(groupIndex, groups)
    local groupWindow = GroupWindowName(groupIndex)
    if not DoesWindowExist(groupWindow) then
        return
    end

    local groupSlots = groups[groupIndex] or {}
    local hasMembers = false

    for memberIndex = 1, c_GROUP_MEMBERS do
        local player = ResolveScenarioPlayer(groupSlots[memberIndex])
        local memberWindow = MemberWindowName(groupIndex, memberIndex)

        local playerName = ToWString(player and player.name)
        if player ~= nil and playerName ~= nil and playerName ~= L"" then
            hasMembers = true
            SetMemberWindowShowing(groupIndex, memberIndex, true)
            SetScenarioMemberTextAndState(memberWindow, player, groupIndex, memberIndex)
            SetScenarioCareerIcon(memberWindow, player)
            SetScenarioMemberBars(memberWindow, player, groupIndex, memberIndex)
        else
            SetMemberWindowShowing(groupIndex, memberIndex, false)
        end
    end

    -- CustomUI UnitFrames replaces stock scenario floating groups; do not honor the stock
    -- ScenarioGroupWindow floating visibility toggle (it can be false by default, hiding everything).
    local showGroup = hasMembers
    if showGroup then
        SafeLayoutUserShow(groupWindow)
    else
        SafeLayoutUserHide(groupWindow)
    end

    -- Scenario floating groups do not use group-leader crown.
    WindowSetShowing(groupWindow .. "GroupLeaderIcon", false)
end

ShowScenarioDualModeWindows = function()
    local groups = BuildScenarioGroupMap()

    local members = 0
    for gi = 1, c_MAX_GROUP_WINDOWS do
        for mi = 1, c_GROUP_MEMBERS do
            if groups[gi] and groups[gi][mi] and groups[gi][mi].name ~= nil then
                members = members + 1
            end
        end
    end
    local sig = tostring(members)
    if sig ~= m_debugLastScenarioSig then
        m_debugLastScenarioSig = sig
        DebugLog("ShowScenarioDualModeWindows: rosterMembers=" .. tostring(members))
    end

    for groupIndex = 1, c_MAX_GROUP_WINDOWS do
        UpdateScenarioGroup(groupIndex, groups)
    end
end

local function ApplyModeVisibility()
    if not m_enabled or not m_windowsInitialized then
        if m_enabled and not m_windowsInitialized then
            DebugLog("ApplyModeVisibility: enabled but not initialized; skipping")
        end
        return
    end

    m_warbandPartyOnlyDataPartyIndex = nil

    EnsureUnitFramesGroupsSettings()
    local currentMode = GetActiveUnitFramesDisplayMode()

    if currentMode ~= m_debugLastMode then
        m_debugLastMode = currentMode
        DebugLog("Mode=" .. tostring(currentMode)
            .. " isScenario=" .. tostring(IsScenarioModeActive())
            .. " isWarband=" .. tostring(IsWarbandModeActive())
        )
    end

    -- IMPORTANT: only hide stock frames when we're actively replacing them.
    -- If we hide stock while mode is "none" (eg scenario roster/flags not ready yet),
    -- the player can end up with *no* group frames at all.
    if currentMode == "none" then
        HideAllCustomWindows()
        return
    end

    HideAllStockWindows()
    HideAllCustomWindows()

    if currentMode == "scenario" then
        ShowScenarioDualModeWindows()
        return
    end

    if currentMode == "warband" then
        ShowWarbandDualModeWindows()
        return
    end

    if currentMode == "warband_party1" then
        ShowWarbandParty1DualModeWindows()
        return
    end

    if currentMode == "party" then
        ShowPartyDualModeWindows()
    end
end

local function HideCustomShowStock()
    local windowSets = GetWindowSets()

    HideAllCustomWindows()
    ForEachWindow(windowSets.stockWarband, SafeLayoutUserShow)
    ForEachWindow(windowSets.stockScenario, SafeLayoutUserShow)
end

local function ClearScenarioHitHpOverrides()
    m_scenarioHitHp = {}
end

--- RoR fires this with (groupIndex, groupSlotNum, hits); Enemy maps it to roster HP updates.
function UnitFrames.OnScenarioPlayerHitsUpdated(groupIndex, groupSlotNum, hits)
    local gi = tonumber(groupIndex)
    local mi = tonumber(groupSlotNum)
    if gi == nil or mi == nil then
        return
    end
    m_scenarioHitHp[gi] = m_scenarioHitHp[gi] or {}
    m_scenarioHitHp[gi][mi] = tonumber(hits)
    if m_enabled and m_windowsInitialized and GetActiveUnitFramesDisplayMode() == "scenario" then
        ApplyModeVisibility()
    end
    RefreshTargetBorders()
end

function UnitFrames.OnScenarioLifecycleRefresh()
    ClearScenarioHitHpOverrides()
    ApplyModeVisibility()
end

function UnitFrames.OnVisibilityStateChanged()
    ApplyModeVisibility()
end

--- Scenario roster or assigned-slot changes: drop cached hits so GetScenarioPlayerGroups().health wins until fresh hits arrive.
function UnitFrames.OnScenarioRosterOrSlotsUpdated()
    ClearScenarioHitHpOverrides()
    ApplyModeVisibility()
    RefreshTargetBorders()
end

function UnitFrames.OnWarbandMemberUpdated()
    if not m_enabled or not m_windowsInitialized then
        return
    end

    local mode = GetActiveUnitFramesDisplayMode()
    if mode == "warband" then
        ShowWarbandDualModeWindows()
        return
    end
    if mode == "warband_party1" then
        ShowWarbandParty1DualModeWindows()
    end
end

function UnitFrames.OnGroupsSettingsChanged()
    if not m_enabled or not m_windowsInitialized then
        return
    end
    ApplyModeVisibility()
    RefreshTargetBorders()
end

--- Settings snapshot for CustomUISettingsWindow / tooling (same table as CustomUI.Settings.UnitFrames once ensured).
function UnitFrames.GetSettings()
    return EnsureUnitFramesGroupsSettings()
end

--- Scenario self row: keep HP/AP in sync with PlayerStatusWindow (event-driven, not only visibility poll).
function UnitFrames.OnPlayerSelfResourcesUpdated()
    if not m_enabled or not m_windowsInitialized or GetActiveUnitFramesDisplayMode() ~= "scenario" then
        return
    end
    local groups = BuildScenarioGroupMap()
    for gi = 1, c_MAX_GROUP_WINDOWS do
        for mi = 1, c_GROUP_MEMBERS do
            local raw = groups[gi] and groups[gi][mi]
            local player = ResolveScenarioPlayer(raw)
            if player ~= nil and GameData.Player and GameData.Player.name and NamesMatch(player.name, GameData.Player.name) then
                local memberWindow = MemberWindowName(gi, mi)
                if DoesWindowExist(memberWindow) then
                    SetScenarioMemberBars(memberWindow, player, gi, mi)
                    SetScenarioMemberTextAndState(memberWindow, player, gi, mi)
                end
            end
        end
    end
end

function UnitFrames.OnMouseOverCareerIcon()
    local windowName = NarrowWindowName(SystemData.ActiveWindow and SystemData.ActiveWindow.name)
    local groupIndex, memberIndex = string.match(windowName or "", "^CustomUIUnitFramesGroup(%d+)WindowMember(%d+)CareerIcon$")
    groupIndex = tonumber(groupIndex)
    memberIndex = tonumber(memberIndex)
    if groupIndex == nil or memberIndex == nil then
        return
    end

    local mode = GetActiveUnitFramesDisplayMode()
    local member = TryGetWarbandMember(groupIndex, memberIndex)
    if member == nil and mode == "party" then
        member = TryGetPartyFrameMember(groupIndex, memberIndex)
    end
    if member == nil and mode == "scenario" then
        local groups = BuildScenarioGroupMap()
        local player = groups[groupIndex] and groups[groupIndex][memberIndex]
        if player ~= nil then
            local line = ScenarioCareerLineFromScenarioPlayer(player)
            member = {
                name = player.name,
                level = tonumber(player.rank) or tonumber(player.level) or 0,
                battleLevel = tonumber(player.battleRank) or tonumber(player.battleLevel) or 0,
                zoneNum = nil,
                isRVRFlagged = false,
                careerName = (line ~= nil and GetCareerLine(line, nil)) or L"",
            }
        end
    end

    if member == nil then
        return
    end

    if (member.careerName == nil or member.careerName == L"") and member.careerLine ~= nil then
        member.careerName = GetCareerLine(member.careerLine, nil) or L""
    end

    local levelString = L""
    if type(PartyUtils) == "table" and type(PartyUtils.GetLevelText) == "function" then
        local ok, txt = pcall(PartyUtils.GetLevelText, tonumber(member.level) or 0, tonumber(member.battleLevel) or 0)
        if ok and txt ~= nil then
            levelString = txt
        end
    end

    Tooltips.CreateTextOnlyTooltip(windowName)
    Tooltips.SetTooltipText(1, 1, ToWString(member.name) or L"")
    Tooltips.SetTooltipColorDef(1, 1, Tooltips.COLOR_HEADING)
    Tooltips.SetTooltipText(2, 1, GetStringFormat(StringTables.Default.LABEL_RANK_X, { levelString }))
    Tooltips.SetTooltipText(3, 1, GetStringFormatFromTable("HUDStrings", StringTables.HUD.LABEL_HUD_PLAYER_WINDOW_TOOLTIP_CAREER_NAME, { member.careerName }))

    local tooltipLine = 4
    if tonumber(member.zoneNum) ~= nil and tonumber(member.zoneNum) > 0 then
        Tooltips.SetTooltipText(tooltipLine, 1, GetZoneName(member.zoneNum))
        tooltipLine = tooltipLine + 1
    end

    if member.isRVRFlagged then
        Tooltips.SetTooltipText(tooltipLine, 1, GetStringFromTable("HUDStrings", StringTables.HUD.LABEL_PLAYER_IS_RVR_FLAGGED))
    end

    Tooltips.Finalize()
    Tooltips.AnchorTooltip(Tooltips.ANCHOR_WINDOW_VARIABLE)
end

function UnitFrames.OnMemberRightClick()
    local groupIndex, memberIndex = GetGroupMemberIndicesFromWindowName(SystemData.ActiveWindow.name)
    if groupIndex == nil or memberIndex == nil then
        return
    end

    local member = TryGetWarbandMember(groupIndex, memberIndex)
    if member == nil and GetActiveUnitFramesDisplayMode() == "party" then
        member = TryGetPartyFrameMember(groupIndex, memberIndex)
    end
    local memberName = ToWString(member and member.name)
    if member == nil or memberName == nil or memberName == L"" then
        return
    end

    if type(BattlegroupHUD) == "table" and type(BattlegroupHUD.ShowMenu) == "function" then
        BattlegroupHUD.contextMenuOpenedFrom = MemberWindowName(groupIndex, memberIndex)
        BattlegroupHUD.ShowMenu(memberName, member.online ~= true)
    end
end

function UnitFrames.OnMemberLeftClick()
    -- Targeting is handled by WindowSetGameActionData(...SET_TARGET...) on each member row.
    if GetDesiredInteractAction() == SystemData.InteractActions.TELEPORT then
        UseItemTargeting.SendTeleport()
    end
end

function UnitFrames.InitializeWindow()
    if m_windowsInitialized then
        return
    end

    -- Do not depend on LayoutEditor registration to consider windows "initialized":
    -- the XML instances are created by CustomUI.EnsureRootWindowInstances(), so if they exist we can show/hide them.
    m_windowsInitialized = DoesWindowExist(c_ROOT_WINDOW_NAME) and DoesWindowExist(GroupWindowName(1))
    if not m_windowsInitialized then
        m_windowsInitialized = RegisterCustomWindowsForLayout() == true
    else
        RegisterCustomWindowsForLayout()
    end

    local sig = tostring(m_windowsInitialized)
        .. "|root=" .. tostring(DoesWindowExist(c_ROOT_WINDOW_NAME))
        .. "|g1=" .. tostring(DoesWindowExist(GroupWindowName(1)))
        .. "|layoutReady=" .. tostring(type(LayoutEditor) == "table")
    if sig ~= m_debugLastInitSig then
        m_debugLastInitSig = sig
        DebugLog("InitializeWindow: " .. sig)
    end

end

function UnitFrames.ShutdownWindow()
end

function UnitFrames.Update(elapsedTime)
    if not m_enabled then
        return
    end

    if not m_windowsInitialized then
        UnitFrames.InitializeWindow()
    end

    if GetActiveUnitFramesDisplayMode() == "scenario" then
        m_scenarioDistancePollElapsed = m_scenarioDistancePollElapsed + (elapsedTime or 0)
        if m_scenarioDistancePollElapsed >= c_SCENARIO_DISTANCE_POLL_INTERVAL then
            m_scenarioDistancePollElapsed = 0
            ScanScenarioDistancesFromMapPoints()
        end
    else
        m_scenarioDistancePollElapsed = 0
        m_scenarioDistanceByKey = {}
    end

    m_visibilityPollElapsed = m_visibilityPollElapsed + (elapsedTime or 0)
    if m_visibilityPollElapsed >= c_VISIBILITY_POLL_INTERVAL then
        m_visibilityPollElapsed = 0
        ApplyModeVisibility()
        RefreshTargetBorders()
        RefreshMouseOverBorders()
    end

    -- Hover hits children (bars/icons); member-root OnMouseOver rarely fires. Use global hover + parent walk.
    SyncMouseOverBorderFromGlobalHover()
end

function UnitFrames.Initialize()
    UnitFrames.InitializeWindow()

    if type(BattlegroupHUD) == "table"
    and type(BattlegroupHUD.OnMenuClickSetBackgroundOpacity) == "function"
    and m_stockOnMenuClickSetBackgroundOpacity == nil then
        m_stockOnMenuClickSetBackgroundOpacity = BattlegroupHUD.OnMenuClickSetBackgroundOpacity
        BattlegroupHUD.OnMenuClickSetBackgroundOpacity = function()
            local contextWindow = BattlegroupHUD.contextMenuOpenedFrom
            if IsUnitFramesMemberWindowName(contextWindow) then
                -- Delegate to stock to preserve slider min/max and behavior parity.
                m_stockOnMenuClickSetBackgroundOpacity()
                return
            end

            m_stockOnMenuClickSetBackgroundOpacity()
        end
    end

    if type(BattlegroupHUD) == "table"
    and type(BattlegroupHUD.OnOpacitySlide) == "function"
    and m_stockOnOpacitySlide == nil then
        m_stockOnOpacitySlide = BattlegroupHUD.OnOpacitySlide
        BattlegroupHUD.OnOpacitySlide = function(slidePos)
            local contextWindow = BattlegroupHUD.contextMenuOpenedFrom
            if IsUnitFramesMemberWindowName(contextWindow) then
                local resolvedAlpha = ClampAlpha(slidePos)
                UnitFrames.WindowSettings.backgroundAlpha = resolvedAlpha
                SetUnitFramesBackgroundAlpha(resolvedAlpha)
                return
            end

            m_stockOnOpacitySlide(slidePos)
        end
    end

    if not m_eventsRegistered and DoesWindowExist(c_ROOT_WINDOW_NAME) then
        WindowRegisterEventHandler(c_ROOT_WINDOW_NAME, SystemData.Events.GROUP_UPDATED, "CustomUI.UnitFrames.OnVisibilityStateChanged")
        WindowRegisterEventHandler(c_ROOT_WINDOW_NAME, SystemData.Events.GROUP_STATUS_UPDATED, "CustomUI.UnitFrames.OnVisibilityStateChanged")
        WindowRegisterEventHandler(c_ROOT_WINDOW_NAME, SystemData.Events.GROUP_PLAYER_ADDED, "CustomUI.UnitFrames.OnVisibilityStateChanged")
        WindowRegisterEventHandler(c_ROOT_WINDOW_NAME, SystemData.Events.BATTLEGROUP_UPDATED, "CustomUI.UnitFrames.OnVisibilityStateChanged")
        WindowRegisterEventHandler(c_ROOT_WINDOW_NAME, SystemData.Events.BATTLEGROUP_MEMBER_UPDATED, "CustomUI.UnitFrames.OnWarbandMemberUpdated")
        WindowRegisterEventHandler(c_ROOT_WINDOW_NAME, SystemData.Events.SCENARIO_PLAYERS_LIST_GROUPS_UPDATED, "CustomUI.UnitFrames.OnScenarioRosterOrSlotsUpdated")
        WindowRegisterEventHandler(c_ROOT_WINDOW_NAME, SystemData.Events.SCENARIO_PLAYERS_LIST_RESERVATIONS_UPDATED, "CustomUI.UnitFrames.OnScenarioRosterOrSlotsUpdated")
        WindowRegisterEventHandler(c_ROOT_WINDOW_NAME, SystemData.Events.SCENARIO_PLAYER_HITS_UPDATED, "CustomUI.UnitFrames.OnScenarioPlayerHitsUpdated")
        WindowRegisterEventHandler(c_ROOT_WINDOW_NAME, SystemData.Events.SCENARIO_GROUP_JOIN, "CustomUI.UnitFrames.OnScenarioRosterOrSlotsUpdated")
        WindowRegisterEventHandler(c_ROOT_WINDOW_NAME, SystemData.Events.SCENARIO_GROUP_LEAVE, "CustomUI.UnitFrames.OnScenarioRosterOrSlotsUpdated")
        WindowRegisterEventHandler(c_ROOT_WINDOW_NAME, SystemData.Events.SCENARIO_BEGIN, "CustomUI.UnitFrames.OnScenarioLifecycleRefresh")
        WindowRegisterEventHandler(c_ROOT_WINDOW_NAME, SystemData.Events.CITY_SCENARIO_BEGIN, "CustomUI.UnitFrames.OnScenarioLifecycleRefresh")
        WindowRegisterEventHandler(c_ROOT_WINDOW_NAME, SystemData.Events.SCENARIO_END, "CustomUI.UnitFrames.OnScenarioLifecycleRefresh")
        WindowRegisterEventHandler(c_ROOT_WINDOW_NAME, SystemData.Events.CITY_SCENARIO_END, "CustomUI.UnitFrames.OnScenarioLifecycleRefresh")
        WindowRegisterEventHandler(c_ROOT_WINDOW_NAME, SystemData.Events.PLAYER_TARGET_UPDATED, "CustomUI.UnitFrames.OnTargetUpdated")
        WindowRegisterEventHandler(c_ROOT_WINDOW_NAME, SystemData.Events.PLAYER_CUR_HIT_POINTS_UPDATED, "CustomUI.UnitFrames.OnPlayerSelfResourcesUpdated")
        WindowRegisterEventHandler(c_ROOT_WINDOW_NAME, SystemData.Events.PLAYER_MAX_HIT_POINTS_UPDATED, "CustomUI.UnitFrames.OnPlayerSelfResourcesUpdated")
        WindowRegisterEventHandler(c_ROOT_WINDOW_NAME, SystemData.Events.PLAYER_CUR_ACTION_POINTS_UPDATED, "CustomUI.UnitFrames.OnPlayerSelfResourcesUpdated")
        WindowRegisterEventHandler(c_ROOT_WINDOW_NAME, SystemData.Events.PLAYER_MAX_ACTION_POINTS_UPDATED, "CustomUI.UnitFrames.OnPlayerSelfResourcesUpdated")
        m_eventsRegistered = true
    end
end

function UnitFrames.Enable()
    m_enabled = true
    m_visibilityPollElapsed = 0
    -- Root hosts OnUpdate; CreateWindow(..., false) leaves it hidden — hidden windows may not tick.
    SetUnitFramesTickWindowShowing(true)
    UnitFrames.InitializeWindow()

    if not m_windowsInitialized then
        return true
    end

    ApplyModeVisibility()
    RefreshMouseOverBorders()

    local alpha = UnitFrames.WindowSettings.backgroundAlpha
    if alpha == nil then
        alpha = c_DEFAULT_BACKGROUND_ALPHA
    else
        alpha = ClampAlpha(alpha)
    end

    if alpha ~= nil then
        SetUnitFramesBackgroundAlpha(alpha)
    end

    return true
end

function UnitFrames.Disable()
    ClearScenarioHitHpOverrides()
    m_enabled = false
    m_mouseOverMemberWindow = nil
    RefreshMouseOverBorders()
    m_visibilityPollElapsed = 0
    SetUnitFramesTickWindowShowing(false)
    HideCustomShowStock()

    return true
end

function UnitFrames.Shutdown()
    if m_eventsRegistered and DoesWindowExist(c_ROOT_WINDOW_NAME) then
        WindowUnregisterEventHandler(c_ROOT_WINDOW_NAME, SystemData.Events.GROUP_UPDATED)
        WindowUnregisterEventHandler(c_ROOT_WINDOW_NAME, SystemData.Events.GROUP_STATUS_UPDATED)
        WindowUnregisterEventHandler(c_ROOT_WINDOW_NAME, SystemData.Events.GROUP_PLAYER_ADDED)
        WindowUnregisterEventHandler(c_ROOT_WINDOW_NAME, SystemData.Events.BATTLEGROUP_UPDATED)
        WindowUnregisterEventHandler(c_ROOT_WINDOW_NAME, SystemData.Events.BATTLEGROUP_MEMBER_UPDATED)
        WindowUnregisterEventHandler(c_ROOT_WINDOW_NAME, SystemData.Events.SCENARIO_PLAYERS_LIST_GROUPS_UPDATED)
        WindowUnregisterEventHandler(c_ROOT_WINDOW_NAME, SystemData.Events.SCENARIO_PLAYERS_LIST_RESERVATIONS_UPDATED)
        WindowUnregisterEventHandler(c_ROOT_WINDOW_NAME, SystemData.Events.SCENARIO_PLAYER_HITS_UPDATED)
        WindowUnregisterEventHandler(c_ROOT_WINDOW_NAME, SystemData.Events.SCENARIO_GROUP_JOIN)
        WindowUnregisterEventHandler(c_ROOT_WINDOW_NAME, SystemData.Events.SCENARIO_GROUP_LEAVE)
        WindowUnregisterEventHandler(c_ROOT_WINDOW_NAME, SystemData.Events.SCENARIO_BEGIN)
        WindowUnregisterEventHandler(c_ROOT_WINDOW_NAME, SystemData.Events.CITY_SCENARIO_BEGIN)
        WindowUnregisterEventHandler(c_ROOT_WINDOW_NAME, SystemData.Events.SCENARIO_END)
        WindowUnregisterEventHandler(c_ROOT_WINDOW_NAME, SystemData.Events.CITY_SCENARIO_END)
        WindowUnregisterEventHandler(c_ROOT_WINDOW_NAME, SystemData.Events.PLAYER_TARGET_UPDATED)
        WindowUnregisterEventHandler(c_ROOT_WINDOW_NAME, SystemData.Events.PLAYER_CUR_HIT_POINTS_UPDATED)
        WindowUnregisterEventHandler(c_ROOT_WINDOW_NAME, SystemData.Events.PLAYER_MAX_HIT_POINTS_UPDATED)
        WindowUnregisterEventHandler(c_ROOT_WINDOW_NAME, SystemData.Events.PLAYER_CUR_ACTION_POINTS_UPDATED)
        WindowUnregisterEventHandler(c_ROOT_WINDOW_NAME, SystemData.Events.PLAYER_MAX_ACTION_POINTS_UPDATED)
    end
    m_eventsRegistered = false

    if m_stockOnMenuClickSetBackgroundOpacity ~= nil then
        if type(BattlegroupHUD) == "table" then
            BattlegroupHUD.OnMenuClickSetBackgroundOpacity = m_stockOnMenuClickSetBackgroundOpacity
        end
        m_stockOnMenuClickSetBackgroundOpacity = nil
    end

    if m_stockOnOpacitySlide ~= nil then
        if type(BattlegroupHUD) == "table" then
            BattlegroupHUD.OnOpacitySlide = m_stockOnOpacitySlide
        end
        m_stockOnOpacitySlide = nil
    end
end

local function ResetUnitFramesWindowDefaults()
    if type(CustomUI.ResetWindowToDefault) == "function" then
        CustomUI.ResetWindowToDefault(c_ROOT_WINDOW_NAME)
        for groupIndex = 1, c_MAX_GROUP_WINDOWS do
            CustomUI.ResetWindowToDefault(GroupWindowName(groupIndex))
        end
        return
    end

    if DoesWindowExist(c_ROOT_WINDOW_NAME) then
        WindowRestoreDefaultSettings(c_ROOT_WINDOW_NAME)
    end

    for groupIndex = 1, c_MAX_GROUP_WINDOWS do
        local groupWindow = GroupWindowName(groupIndex)
        if DoesWindowExist(groupWindow) then
            WindowRestoreDefaultSettings(groupWindow)
        end
    end
end

local UnitFramesComponent = {
    Name = "UnitFrames",
    WindowName = c_ROOT_WINDOW_NAME,
    DefaultEnabled = false,
}

function UnitFramesComponent:Initialize()
    UnitFrames.Initialize()
end

function UnitFramesComponent:Enable()
    return UnitFrames.Enable()
end

function UnitFramesComponent:Disable()
    return UnitFrames.Disable()
end

function UnitFramesComponent:ResetToDefaults()
    UnitFrames.WindowSettings.backgroundAlpha = nil

    ResetUnitFramesWindowDefaults()
    SetStockWarbandBackgroundAlpha(c_DEFAULT_BACKGROUND_ALPHA)

    if m_enabled and m_windowsInitialized then
        ApplyModeVisibility()
        SetUnitFramesBackgroundAlpha(c_DEFAULT_BACKGROUND_ALPHA)
    end

    return true
end

function UnitFramesComponent:Shutdown()
    UnitFrames.Shutdown()
end
CustomUI.RegisterComponent("UnitFrames", UnitFramesComponent)
