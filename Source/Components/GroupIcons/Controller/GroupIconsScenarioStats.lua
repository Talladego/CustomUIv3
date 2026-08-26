----------------------------------------------------------------
-- CustomUI.GroupIcons.ScenarioStats
--
-- Live scenario / city-siege player stats for GroupIcons scoreboard badges.
-- Scoreboard rows have no worldObjNum; the controller joins by normalized name.
-- Winners are per realm. One icon per player, assigned in priority order:
--   death blows > kill damage > damage > healing > protection.
-- Ties use the next priority column, then the rest of the list.
--
-- Stock ScenarioSummaryWindow.OnHidden broadcasts STOP. If we still want badges,
-- MarkStopped + Start so the stream runs while the scoreboard is closed.
--
-- PINNED: previous kill/heal threat formulas live in PickTopWinnersThreatFormula.
-- Restore by pointing PickTopWinners at that function if we want the old scoring.
----------------------------------------------------------------

if not CustomUI then
    CustomUI = {}
end

CustomUI.GroupIcons = CustomUI.GroupIcons or {}
CustomUI.GroupIcons.ScenarioStats = CustomUI.GroupIcons.ScenarioStats or {}

local ScenarioStats = CustomUI.GroupIcons.ScenarioStats

local m_streaming = false
local m_summaryHooked = false

local function StartEvent()
    return SystemData and SystemData.Events and SystemData.Events.SCENARIO_START_UPDATING_PLAYERS_STATS
end

local function StopEvent()
    return SystemData and SystemData.Events and SystemData.Events.SCENARIO_STOP_UPDATING_PLAYERS_STATS
end

local function SummaryWindowIsShowing()
    if type(DoesWindowExist) ~= "function" or type(WindowGetShowing) ~= "function" then
        return false
    end
    if not DoesWindowExist("ScenarioSummaryWindow") then
        return false
    end
    return WindowGetShowing("ScenarioSummaryWindow") == true
end

function ScenarioStats.IsStreaming()
    return m_streaming == true
end

--- Stock OnHidden always STOPs; drop our flag so Start() will re-broadcast.
function ScenarioStats.MarkStopped()
    m_streaming = false
end

function ScenarioStats.Start()
    if m_streaming then
        return
    end
    local ev = StartEvent()
    if ev == nil or type(BroadcastEvent) ~= "function" then
        return
    end
    CustomUI.TryCall("GroupIcons.StartScenarioPlayerStats", BroadcastEvent, ev)
    m_streaming = true
end

--- Stop our stream. If the stock scoreboard is open it owns the START; do not STOP it.
function ScenarioStats.Stop()
    if not m_streaming then
        return
    end
    m_streaming = false
    if SummaryWindowIsShowing() then
        return
    end
    local ev = StopEvent()
    if ev == nil or type(BroadcastEvent) ~= "function" then
        return
    end
    CustomUI.TryCall("GroupIcons.StopScenarioPlayerStats", BroadcastEvent, ev)
end

local function RowKillDamage(row)
    -- Stock ScenarioSummaryWindow maps kill damage from GetScenarioPlayers().renownbonus.
    local killDamage = tonumber(row.killdamagedealt)
    if killDamage == nil then
        killDamage = tonumber(row.renownbonus)
    end
    return killDamage or 0
end

local function RowProtection(row)
    -- Stock ScenarioSummaryWindow maps protection from GetScenarioPlayers().solokills.
    local protection = tonumber(row.protection)
    if protection == nil then
        protection = tonumber(row.solokills)
    end
    return protection or 0
end

-- PINNED (unused): previous kill/heal threat formulas. Keep for revert.
local function RowResurrections(row)
    -- Stock scenario rows may omit this; GRP_STATS uses resurrectionsDone.
    local rez = tonumber(row.resurrectionsDone)
    if rez == nil then
        rez = tonumber(row.resurrections)
    end
    if rez == nil then
        rez = tonumber(row.rezzes)
    end
    return rez or 0
end

local function SafeLog(value)
    if type(math) ~= "table" or type(math.log) ~= "function" then
        return 0
    end
    return math.log(value)
end

local function SafeSqrt(value)
    if type(math) ~= "table" or type(math.sqrt) ~= "function" then
        return value
    end
    return math.sqrt(value)
end

--- Kill-damage backbone, smoothed Kill/Total efficiency, damped Death Blows.
--- threat = KillDamage * (0.7 + 0.3 * eff) * sqrt(1 + DeathBlows)
--- eff = (KillDamage + c) / (TotalDamage + c), c = 15% of field average TotalDamage.
local function DamageThreatScore(totalDamage, killDamage, deathBlows, shrinkC)
    if killDamage <= 0 and deathBlows <= 0 then
        return 0
    end
    local c = shrinkC
    if c == nil or c < 1 then
        c = 1
    end
    local denom = totalDamage + c
    if denom <= 0 then
        return 0
    end
    local efficiency = (killDamage + c) / denom
    return killDamage * (0.7 + 0.3 * efficiency) * SafeSqrt(1 + deathBlows)
end

--- Healing backbone with keep-alive mix. Aura / lifetap volume (0 rez) is discounted
--- once anyone in the match has rezzed; two similar healers, higher rez wins.
--- When no rezzes yet: raw healing.
--- Else: Healing * (0.55 + 0.45 * log(1+rez)/log(1+maxRez))
local function HealThreatScore(healing, resurrections, maxResurrections)
    if healing <= 0 and resurrections <= 0 then
        return 0
    end
    if maxResurrections <= 0 then
        return healing
    end
    local rezNorm = SafeLog(1 + resurrections) / SafeLog(1 + maxResurrections)
    if rezNorm < 0 then
        rezNorm = 0
    elseif rezNorm > 1 then
        rezNorm = 1
    end
    return healing * (0.55 + 0.45 * rezNorm)
end

local function NameForChat(name)
    if name == nil then
        return nil
    end
    local s = nil
    if type(name) == "wstring" then
        if type(WStringToString) == "function" then
            local ok, text = CustomUI.TryCallQuiet("GroupIcons.ScenarioPlayerChatName", WStringToString, name)
            if ok and type(text) == "string" then
                s = text
            end
        end
    elseif type(name) == "string" then
        s = name
    end
    if s == nil or s == "" then
        return nil
    end
    local caret = string.find(s, "^", 1, true)
    if caret then
        s = string.sub(s, 1, caret - 1)
    end
    if s == "" then
        return nil
    end
    return s
end

local function IsScoredRealm(realm)
    if GameData == nil or GameData.Realm == nil then
        return false
    end
    return realm == GameData.Realm.ORDER or realm == GameData.Realm.DESTRUCTION
end

local function NewRealmBucket()
    return {
        rows = {},
        totalDamageSum = 0,
        totalDamageCount = 0,
        maxKillDamage = 0,
        maxResurrections = 0,
    }
end

--- PINNED: previous per-realm kill/heal threat scoring (not used by PickTopWinners).
local function PickBucketWinnersThreatFormula(bucket, normalizeNameKey)
    local shrinkC = 1
    if bucket.totalDamageCount > 0 then
        shrinkC = 0.15 * (bucket.totalDamageSum / bucket.totalDamageCount)
        if shrinkC < 1 then
            shrinkC = 1
        end
    end
    local useKillDamageBackbone = bucket.maxKillDamage > 0

    local maxDamageThreat, maxHealThreat = 0, 0
    local damageKey, healKey = nil, nil
    local damageName, healName = nil, nil
    for i = 1, #bucket.rows do
        local row = bucket.rows[i]
        local key = normalizeNameKey(row.name)
        if key ~= nil then
            local totalDamage = tonumber(row.damagedealt) or 0
            local killDamage = RowKillDamage(row)
            local deathBlows = tonumber(row.deathblows) or 0
            local damageThreat = 0
            if useKillDamageBackbone then
                damageThreat = DamageThreatScore(totalDamage, killDamage, deathBlows, shrinkC)
            elseif totalDamage > 0 then
                damageThreat = totalDamage * SafeSqrt(1 + deathBlows)
            end
            if damageThreat > maxDamageThreat then
                maxDamageThreat = damageThreat
                damageKey = key
                damageName = NameForChat(row.name)
            end

            local healing = tonumber(row.healingdealt) or 0
            local resurrections = RowResurrections(row)
            local healThreat = HealThreatScore(healing, resurrections, bucket.maxResurrections)
            if healThreat > maxHealThreat then
                maxHealThreat = healThreat
                healKey = key
                healName = NameForChat(row.name)
            end
        end
    end

    local kill = nil
    local heal = nil
    if maxDamageThreat > 0 and damageKey ~= nil then
        kill = { key = damageKey, name = damageName }
    end
    if maxHealThreat > 0 and healKey ~= nil then
        heal = { key = healKey, name = healName }
    end
    return kill, heal
end

--- PINNED: previous kill/heal threat winners. Restore by swapping PickTopWinners to this.
function ScenarioStats.PickTopWinnersThreatFormula(normalizeNameKey)
    if type(normalizeNameKey) ~= "function" then
        return { kill = {}, heal = {} }
    end
    if type(GameData) ~= "table" or type(GameData.GetScenarioPlayers) ~= "function" then
        return { kill = {}, heal = {} }
    end
    local ok, list = CustomUI.TryCallQuiet("GroupIcons.GetScenarioPlayers", GameData.GetScenarioPlayers)
    if not ok or type(list) ~= "table" then
        return { kill = {}, heal = {} }
    end

    local byRealm = {}
    for _, row in ipairs(list) do
        if type(row) == "table" then
            local realm = tonumber(row.realm)
            if IsScoredRealm(realm) then
                local bucket = byRealm[realm]
                if bucket == nil then
                    bucket = NewRealmBucket()
                    byRealm[realm] = bucket
                end
                bucket.rows[#bucket.rows + 1] = row
                local totalDamage = tonumber(row.damagedealt) or 0
                if totalDamage > 0 then
                    bucket.totalDamageSum = bucket.totalDamageSum + totalDamage
                    bucket.totalDamageCount = bucket.totalDamageCount + 1
                end
                local killDamage = RowKillDamage(row)
                if killDamage > bucket.maxKillDamage then
                    bucket.maxKillDamage = killDamage
                end
                local rez = RowResurrections(row)
                if rez > bucket.maxResurrections then
                    bucket.maxResurrections = rez
                end
            end
        end
    end

    local kill = {}
    local heal = {}
    for realm, bucket in pairs(byRealm) do
        local killEntry, healEntry = PickBucketWinnersThreatFormula(bucket, normalizeNameKey)
        if killEntry ~= nil then
            kill[realm] = killEntry
        end
        if healEntry ~= nil then
            heal[realm] = healEntry
        end
    end
    return { kill = kill, heal = heal }
end

local c_STAT_ORDER = {
    "deathblows",
    "killdamage",
    "damage",
    "heal",
    "protection",
}

local function EmptyStatWinners()
    local winners = {}
    for i = 1, #c_STAT_ORDER do
        winners[c_STAT_ORDER[i]] = {}
    end
    return winners
end

local function RowStatValue(kind, row)
    if kind == "deathblows" then
        return tonumber(row.deathblows) or 0
    end
    if kind == "killdamage" then
        return RowKillDamage(row)
    end
    if kind == "damage" then
        return tonumber(row.damagedealt) or 0
    end
    if kind == "heal" then
        return tonumber(row.healingdealt) or 0
    end
    if kind == "protection" then
        return RowProtection(row)
    end
    return 0
end

local function ChallengerWinsTieBreak(startIndex, challenger, incumbent)
    for i = startIndex, #c_STAT_ORDER do
        local kind = c_STAT_ORDER[i]
        local a = RowStatValue(kind, challenger)
        local b = RowStatValue(kind, incumbent)
        if a ~= b then
            return a > b
        end
    end
    return false
end

local function PickExclusiveStatWinners(rows, normalizeNameKey)
    local taken = {}
    local winners = {}
    for i = 1, #c_STAT_ORDER do
        local kind = c_STAT_ORDER[i]
        local bestRow, bestKey, bestName = nil, nil, nil
        for r = 1, #rows do
            local row = rows[r]
            local key = normalizeNameKey(row.name)
            if key ~= nil and taken[key] ~= true then
                if RowStatValue(kind, row) > 0 then
                    if bestRow == nil or ChallengerWinsTieBreak(i, row, bestRow) then
                        bestRow = row
                        bestKey = key
                        bestName = NameForChat(row.name)
                    end
                end
            end
        end
        if bestKey ~= nil then
            winners[kind] = { key = bestKey, name = bestName }
            taken[bestKey] = true
        end
    end
    return winners
end

--- Per-realm exclusive scoreboard tops. Returns { [kind] = { [realm] = { key, name } } }.
function ScenarioStats.PickTopWinners(normalizeNameKey)
    local winners = EmptyStatWinners()
    if type(normalizeNameKey) ~= "function" then
        return winners
    end
    if type(GameData) ~= "table" or type(GameData.GetScenarioPlayers) ~= "function" then
        return winners
    end
    local ok, list = CustomUI.TryCallQuiet("GroupIcons.GetScenarioPlayers", GameData.GetScenarioPlayers)
    if not ok or type(list) ~= "table" then
        return winners
    end

    local byRealm = {}
    for _, row in ipairs(list) do
        if type(row) == "table" then
            local realm = tonumber(row.realm)
            if IsScoredRealm(realm) then
                local bucket = byRealm[realm]
                if bucket == nil then
                    bucket = {}
                    byRealm[realm] = bucket
                end
                bucket[#bucket + 1] = row
            end
        end
    end

    for realm, rows in pairs(byRealm) do
        local picked = PickExclusiveStatWinners(rows, normalizeNameKey)
        for i = 1, #c_STAT_ORDER do
            local kind = c_STAT_ORDER[i]
            local entry = picked[kind]
            if entry ~= nil then
                winners[kind][realm] = entry
            end
        end
    end
    return winners
end

--- Wrap stock ScenarioSummaryWindow.OnHidden so we can START again after it STOPs.
function ScenarioStats.EnsureStockSummaryHook(onStockStopped)
    if m_summaryHooked then
        return
    end
    if type(ScenarioSummaryWindow) ~= "table" then
        return
    end
    local orig = ScenarioSummaryWindow.OnHidden
    if type(orig) ~= "function" then
        return
    end
    m_summaryHooked = true
    ScenarioSummaryWindow.OnHidden = function(...)
        local ok, r1, r2, r3, r4, r5 = CustomUI.TryCall(
            "GroupIcons.ScenarioSummaryWindow.OnHidden",
            orig,
            ...
        )
        if type(onStockStopped) == "function" then
            onStockStopped()
        end
        if ok then
            return r1, r2, r3, r4, r5
        end
    end
end
