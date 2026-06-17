----------------------------------------------------------------
-- CustomUI.UnitFrames.Scenario
--
-- Scenario-specific data helpers used by UnitFramesController.
-- Keeps roster career resolution, HP/AP rounding, hit merging, and
-- local-player scenario row overrides out of the main controller.
----------------------------------------------------------------

if not CustomUI then
    CustomUI = {}
end

CustomUI.UnitFrames = CustomUI.UnitFrames or {}
CustomUI.UnitFrames.Scenario = CustomUI.UnitFrames.Scenario or {}

local UnitFramesScenario = CustomUI.UnitFrames.Scenario

local c_MAX_GROUP_WINDOWS = 6
local c_GROUP_MEMBERS = 6
local c_MAX_MAP_POINTS = 511
local c_DISTANCE_FIX_COEFFICIENT = 1 / 1.06

-- Scenario roster uses compact careerId values (Enemy.ScenarioCareerIdToLine),
-- not the same numbering as Icons.careers / PartyUtils warband members.
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

local function NamesMatchSafe(a, b, namesMatchFn)
    if type(namesMatchFn) == "function" then
        return namesMatchFn(a, b)
    end
    return a == b
end

-- Match EnemyPlayer:LoadFromScenarioData -> Enemy.ScenarioCareerIdToLine first,
-- then RoR Icons reverse-map when careerId is in Careers-names space; raw roster
-- careerLine only if still unknown.
function UnitFramesScenario.GetCareerLineFromPlayer(player)
    if player == nil then
        return nil
    end

    local careerId = tonumber(player.careerId)
    if careerId ~= nil and c_SCENARIO_CAREER_ID_TO_LINE[careerId] ~= nil then
        return c_SCENARIO_CAREER_ID_TO_LINE[careerId]
    end

    if careerId ~= nil
        and type(Icons) == "table"
        and type(Icons.GetCareerIconIDFromCareerNamesID) == "function"
        and type(Icons.careerLines) == "table"
    then
        local iconId = Icons.GetCareerIconIDFromCareerNamesID(careerId)
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

function UnitFramesScenario.GetMergedHealthPercent(hitHpByGroup, groupIndex, memberIndex, player)
    local base = tonumber(player and player.health) or 0
    local hitsForGroup = hitHpByGroup and hitHpByGroup[groupIndex]
    if hitsForGroup == nil then
        return base
    end

    local hit = hitsForGroup[memberIndex]
    if hit == nil then
        return base
    end

    -- hits == 0 means dead; do not use `or base`.
    local merged = tonumber(hit)
    if merged == nil then
        return base
    end

    return merged
end

function UnitFramesScenario.ClampPercent(value)
    local n = tonumber(value) or 0
    if n < 0 then n = 0 end
    if n > 100 then n = 100 end
    return n
end

-- Scenario roster / hits often carry float noise; sub-1% reads as dead UX-wise.
function UnitFramesScenario.SnapHpPercentNearZero(hpPct)
    local x = UnitFramesScenario.ClampPercent(hpPct)
    if x > 0 and x < 1 then
        return 0
    end
    return x
end

function UnitFramesScenario.RoundHpPercentForDisplay(hpPct, snapNearZero)
    local x = UnitFramesScenario.ClampPercent(tonumber(hpPct) or 0)
    if snapNearZero then
        x = UnitFramesScenario.SnapHpPercentNearZero(x)
    end
    return math.floor(x + 0.5)
end

function UnitFramesScenario.RoundApPercentForDisplay(apPct)
    return math.floor(UnitFramesScenario.ClampPercent(tonumber(apPct) or 0) + 0.5)
end

function UnitFramesScenario.RoundScenarioHpForDisplay(hpPct, snapNearZero)
    return UnitFramesScenario.RoundHpPercentForDisplay(hpPct, snapNearZero)
end

-- Minimal warband-shaped row for targeting / borders.
function UnitFramesScenario.BuildTargetMember(player, groupIndex, memberIndex, hitHpByGroup, namesMatchFn)
    if player == nil then
        return nil
    end

    local hpRaw = UnitFramesScenario.GetMergedHealthPercent(hitHpByGroup, groupIndex, memberIndex, player)
    local selfRow = GameData and GameData.Player and GameData.Player.name and player.name
        and NamesMatchSafe(player.name, GameData.Player.name, namesMatchFn)
    local hp = UnitFramesScenario.RoundScenarioHpForDisplay(hpRaw, not selfRow)
    local wid = tonumber(player.worldObjNum or player.worldobjnum or player.entityId or player.entityid) or 0

    return {
        name = player.name,
        worldObjNum = wid,
        healthPercent = hp,
        online = true,
    }
end

function UnitFramesScenario.IsAliveIntegerBand(hpRounded)
    local h = tonumber(hpRounded) or 0
    if h == 100 then
        return true
    end
    if h > 0 and h < 100 then
        return true
    end
    return false
end

function UnitFramesScenario.HitsExplicitZero(hitHpByGroup, groupIndex, memberIndex)
    local hitsForGroup = hitHpByGroup and hitHpByGroup[groupIndex]
    if hitsForGroup == nil then
        return false
    end

    local hit = hitsForGroup[memberIndex]
    return hit ~= nil and tonumber(hit) == 0
end

function UnitFramesScenario.BuildSelfRow()
    if GameData == nil or GameData.Player == nil then
        return nil
    end

    local player = GameData.Player
    if player.name == nil or player.name == L"" then
        return nil
    end

    local hp = 0
    if player.hitPoints
        and player.hitPoints.current
        and player.hitPoints.maximum
        and tonumber(player.hitPoints.maximum)
        and tonumber(player.hitPoints.maximum) > 0
    then
        hp = 100 * (tonumber(player.hitPoints.current) / tonumber(player.hitPoints.maximum))
    end

    local ap = 0
    if player.actionPoints
        and player.actionPoints.current
        and player.actionPoints.maximum
        and tonumber(player.actionPoints.maximum)
        and tonumber(player.actionPoints.maximum) > 0
    then
        ap = 100 * (tonumber(player.actionPoints.current) / tonumber(player.actionPoints.maximum))
    end

    return {
        name = player.name,
        worldObjNum = player.worldObjNum,
        health = UnitFramesScenario.RoundScenarioHpForDisplay(hp, false),
        ap = UnitFramesScenario.RoundApPercentForDisplay(ap),
        careerLine = player.career and player.career.line,
        careerId = nil,
        isMainAssist = false,
        level = tonumber(player.level) or tonumber(player.rank) or 0,
    }
end

function UnitFramesScenario.IsSelfName(name, namesMatchFn)
    if name == nil or GameData == nil or GameData.Player == nil or GameData.Player.name == nil then
        return false
    end
    return NamesMatchSafe(name, GameData.Player.name, namesMatchFn)
end

function UnitFramesScenario.ResolvePlayer(player, namesMatchFn)
    local name = player and player.name
    if name ~= nil and UnitFramesScenario.IsSelfName(name, namesMatchFn) then
        local selfRow = UnitFramesScenario.BuildSelfRow()
        if selfRow ~= nil then
            return selfRow
        end
    end
    return player
end

-- Only scenario parties with sgroupindex > 0 (assigned groups). Ungrouped
-- roster entries are intentionally ignored (GroupIcons covers broader marking).
function UnitFramesScenario.BuildGroupMap()
    local groups = {}
    for groupIndex = 1, c_MAX_GROUP_WINDOWS do
        groups[groupIndex] = {}
    end

    if type(GameData.GetScenarioPlayerGroups) ~= "function" then
        return groups
    end

    local playerGroups = GameData.GetScenarioPlayerGroups() or {}
    for _, player in ipairs(playerGroups) do
        local groupIndex = tonumber(player.sgroupindex)
        local slotIndex = tonumber(player.sgroupslotnum)

        if groupIndex ~= nil and slotIndex ~= nil and groupIndex > 0
            and groupIndex >= 1 and groupIndex <= c_MAX_GROUP_WINDOWS
            and slotIndex >= 1 and slotIndex <= c_GROUP_MEMBERS
        then
            groups[groupIndex][slotIndex] = player
        end
    end

    return groups
end

function UnitFramesScenario.ScanDistancesFromMapPoints(groups, opts)
    opts = opts or {}

    if type(GetMapPointData) ~= "function" then
        return {}, 0
    end

    local rosterKeySet = {}
    for groupIndex = 1, c_MAX_GROUP_WINDOWS do
        local groupSlots = groups and groups[groupIndex] or nil
        for memberIndex = 1, c_GROUP_MEMBERS do
            local player = groupSlots and groupSlots[memberIndex]
            local key = type(opts.fixMapNameKeyFn) == "function" and opts.fixMapNameKeyFn(player and player.name) or nil
            if key ~= nil then
                rosterKeySet[key] = true
            end
        end
    end

    if next(rosterKeySet) == nil then
        return {}, 0
    end

    local mapPointTypeFilter = {
        [SystemData.MapPips.GROUP_MEMBER] = true,
        [SystemData.MapPips.WARBAND_MEMBER] = true,
        [SystemData.MapPips.DESTRUCTION_ARMY] = true,
        [SystemData.MapPips.ORDER_ARMY] = true,
    }

    local distanceByKey = {}
    local updated = 0
    local mapWindowName = opts.mapWindowName or "EA_Window_OverheadMapMapDisplay"
    local distantDistance = tonumber(opts.distantDistance) or 250

    for pointIndex = 1, c_MAX_MAP_POINTS do
        local mpd = GetMapPointData(mapWindowName, pointIndex)
        if mpd and mpd.pointType and mapPointTypeFilter[mpd.pointType] and mpd.name then
            local key = type(opts.fixMapNameKeyFn) == "function" and opts.fixMapNameKeyFn(mpd.name) or nil
            if key ~= nil and rosterKeySet[key] then
                local dist = math.floor((tonumber(mpd.distance) or 0) * c_DISTANCE_FIX_COEFFICIENT)
                distanceByKey[key] = {
                    distance = dist,
                    isDistant = dist >= distantDistance,
                }
                updated = updated + 1
            end
        end
    end

    return distanceByKey, updated
end

-- Resolve roster player + server slot for a scenario UI row
-- (displaySlot = Member suffix). `opts.groups` may be supplied to avoid
-- rebuilding, and `opts.displayPlan` is used when role sorting is enabled.
function UnitFramesScenario.TryGetDisplayRow(groupIndex, displaySlot, opts)
    if groupIndex == nil or displaySlot == nil then
        return nil, nil
    end

    opts = opts or {}
    if opts.sortByRole == true then
        local planByGroup = opts.displayPlan and opts.displayPlan[groupIndex]
        if planByGroup ~= nil then
            local entry = planByGroup[displaySlot]
            if entry ~= nil then
                return entry.player, entry.rosterSlot
            end
            return nil, nil
        end
    end

    local groups = opts.groups
    if groups == nil then
        groups = UnitFramesScenario.BuildGroupMap()
    end
    if groups == nil then
        return nil, nil
    end

    local raw = groups[groupIndex] and groups[groupIndex][displaySlot]
    local player = UnitFramesScenario.ResolvePlayer(raw, opts.namesMatchFn)
    if type(opts.memberHasDisplayNameFn) == "function" then
        if opts.memberHasDisplayNameFn(player) then
            return player, displaySlot
        end
        return nil, nil
    end

    if player ~= nil and player.name ~= nil and player.name ~= L"" then
        return player, displaySlot
    end
    return nil, nil
end

-- Build the sorted scenario display proxies used by UnitFramesController when
-- role sorting is enabled. Returns `sortedProxies, displayPlan`.
function UnitFramesScenario.BuildSortedDisplayPlan(groupSlots, opts)
    opts = opts or {}
    if opts.sortByRole ~= true then
        return nil, nil
    end

    local collected = {}
    for rosterSlot = 1, c_GROUP_MEMBERS do
        local player = groupSlots and groupSlots[rosterSlot]
        if type(opts.resolvePlayerFn) == "function" then
            player = opts.resolvePlayerFn(player)
        end

        if type(opts.memberHasDisplayNameFn) == "function" and opts.memberHasDisplayNameFn(player) then
            local careerLine = nil
            if type(opts.getCareerLineFn) == "function" then
                careerLine = opts.getCareerLineFn(player)
            end

            collected[#collected + 1] = {
                rosterSlot = rosterSlot,
                player = player,
                careerLine = careerLine,
                battleLevel = player and player.battleLevel,
                battleRank = player and player.battleRank,
            }
        end
    end

    local sortedProxies = collected
    if type(opts.sortMembersFn) == "function" then
        sortedProxies = opts.sortMembersFn(collected)
    end

    local displayPlan = {}
    local n = table.getn(sortedProxies or {})
    for i = 1, n do
        local proxy = sortedProxies[i]
        displayPlan[i] = { player = proxy.player, rosterSlot = proxy.rosterSlot }
    end
    for i = n + 1, c_GROUP_MEMBERS do
        displayPlan[i] = nil
    end

    return sortedProxies, displayPlan
end
