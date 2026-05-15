----------------------------------------------------------------
-- CustomUI.SCT — engine handler swap + six event handlers (v2)
-- Handlers are thin: filter, create tracker if needed, AddEvent.
-- All rendering/animation delegates to SCTOverrides (EventTracker/EventEntry).
--
-- Load order: SCTSettings → SCTAnim → SCTOverrides → SCTHandlers → SCTController → SCT.xml
----------------------------------------------------------------
if not CustomUI.SCT then CustomUI.SCT = {} end

local COMBAT_EVENT   = CustomUI.SCT.COMBAT_EVENT
local POINT_GAIN     = CustomUI.SCT.POINT_GAIN
local XP_GAIN        = CustomUI.SCT.XP_GAIN
local RENOWN_GAIN    = CustomUI.SCT.RENOWN_GAIN
local INFLUENCE_GAIN = CustomUI.SCT.INFLUENCE_GAIN

CustomUI.SCT._handlersInstalled  = CustomUI.SCT._handlersInstalled  or false
CustomUI.SCT._stockWasRegistered = CustomUI.SCT._stockWasRegistered or {}
CustomUI.SCT.loading             = CustomUI.SCT.loading             or false
-- Round-robin index for incoming combat fan lanes (left / center / right trackers).
CustomUI.SCT._incomingFanLaneIndex = CustomUI.SCT._incomingFanLaneIndex or 0

function CustomUI.SCT.ClearThrottleQueue()
    for _, tracker in pairs(CustomUI.SCT.EventTrackers or {}) do
        tracker._sctThrottleQueue = {}
        tracker._sctThrottleCredit = 1
    end
end

-- Per-tracker: append to that tracker's throttle queue or AddEvent immediately.
local function dispatchOrQueueEvent(tracker, eventPayload)
    local mps = CustomUI.SCT.GetThrottleMessagesPerSecond()
    if type(mps) ~= "number" or mps ~= mps or mps <= 0 then
        tracker:AddEvent(eventPayload)
        return
    end

    local q = tracker._sctThrottleQueue
    if not q then
        q = {}
        tracker._sctThrottleQueue = q
    end

    local maxCap = CustomUI.SCT.GetThrottleQueueMax()
    if type(maxCap) ~= "number" or maxCap < 32 then
        maxCap = 1024
    end
    maxCap = math.floor(maxCap + 0.5)

    while #q >= maxCap do
        table.remove(q, 1)
    end
    q[#q + 1] = eventPayload
end

local function flushTrackerThrottleQueue(tracker, elapsedTime)
    local mps = CustomUI.SCT.GetThrottleMessagesPerSecond()
    local q = tracker._sctThrottleQueue
    if not q then
        q = {}
        tracker._sctThrottleQueue = q
    end

    -- Unlimited: drain this tracker's backlog immediately.
    if type(mps) ~= "number" or mps ~= mps or mps <= 0 then
        while #q > 0 do
            tracker:AddEvent(table.remove(q, 1))
        end
        tracker._sctThrottleCredit = 1
        return
    end

    if #q == 0 then
        return
    end

    local dt = tonumber(elapsedTime) or 0
    if dt < 0 then
        dt = 0
    end

    tracker._sctThrottleCredit = (tracker._sctThrottleCredit or 0) + dt * mps
    -- Short burst allowance (~3× steady rate). Do NOT use a fixed floor (old code used max(..., 30)),
    -- which made low MPS settings (1–3/sec) accumulate up to 30 tokens and dump many lines at once.
    local burstCap = math.max(1, mps * 3)
    if tracker._sctThrottleCredit > burstCap then
        tracker._sctThrottleCredit = burstCap
    end

    while tracker._sctThrottleCredit >= 1 and #q > 0 do
        tracker._sctThrottleCredit = tracker._sctThrottleCredit - 1
        tracker:AddEvent(table.remove(q, 1))
    end
end

function CustomUI.SCT.FlushThrottle(elapsedTime)
    for _, tracker in pairs(CustomUI.SCT.EventTrackers or {}) do
        flushTrackerThrottleQueue(tracker, elapsedTime)
    end
end

local function sctEngineHandlers()
    local E = SystemData and SystemData.Events
    if not E then return nil end
    return {
        { id = E.WORLD_OBJ_COMBAT_EVENT,     stock = "EA_System_EventText.AddCombatEventText", custom = "CustomUI.SCT.OnCombatEvent"   },
        { id = E.WORLD_OBJ_XP_GAINED,        stock = "EA_System_EventText.AddXpText",          custom = "CustomUI.SCT.OnXpText"        },
        { id = E.WORLD_OBJ_RENOWN_GAINED,    stock = "EA_System_EventText.AddRenownText",       custom = "CustomUI.SCT.OnRenownText"    },
        { id = E.WORLD_OBJ_INFLUENCE_GAINED, stock = "EA_System_EventText.AddInfluenceText",    custom = "CustomUI.SCT.OnInfluenceText" },
        { id = E.LOADING_BEGIN,              stock = "EA_System_EventText.BeginLoading",        custom = "CustomUI.SCT.OnLoadingBegin"  },
        { id = E.LOADING_END,               stock = "EA_System_EventText.EndLoading",          custom = "CustomUI.SCT.OnLoadingEnd"   },
    }
end

function CustomUI.SCT.InstallHandlers()
    if CustomUI.SCT._handlersInstalled then return end
    local rows = sctEngineHandlers()
    if not rows then return end
    CustomUI.SCT._stockWasRegistered = {}
    for _, row in ipairs(rows) do
        UnregisterEventHandler(row.id, row.stock)
        CustomUI.SCT._stockWasRegistered[row.id] = true
    end
    for _, row in ipairs(rows) do
        RegisterEventHandler(row.id, row.custom)
    end
    CustomUI.SCT._engineHandlerRowsCache = rows
    CustomUI.SCT._handlersInstalled = true
end

function CustomUI.SCT.RestoreHandlers()
    if not CustomUI.SCT._handlersInstalled then return end
    local rows = CustomUI.SCT._engineHandlerRowsCache or sctEngineHandlers()
    if rows then
        for _, row in ipairs(rows) do
            UnregisterEventHandler(row.id, row.custom)
        end
        for _, row in ipairs(rows) do
            if CustomUI.SCT._stockWasRegistered[row.id] then
                RegisterEventHandler(row.id, row.stock)
            end
        end
    end
    CustomUI.SCT._engineHandlerRowsCache = nil
    CustomUI.SCT._handlersInstalled = false
end

----------------------------------------------------------------
-- Tracker helpers
----------------------------------------------------------------

-- Seconds a tracker can remain idle (both queues empty) before being evicted during combat.
-- Out-of-combat eviction is immediate (existing behaviour); this only affects in-combat retention.
local c_TRACKER_IDLE_EVICT_TIME = 10

-- Hard cap on live trackers (Medium #24). Incoming combat alone uses three string keys per player worldObjNum;
-- LRU eviction avoids unbounded growth during long fights with many distinct targets.
local c_EVENT_TRACKERS_MAX = 72

local m_sctTrackerTouchSeq = 0

local function bumpTrackerTouchSeq(tracker)
    if not tracker then return end
    m_sctTrackerTouchSeq = m_sctTrackerTouchSeq + 1
    tracker._sctTouchSeq = m_sctTrackerTouchSeq
end

local function trackerIsQuiescent(tracker)
    if not tracker then return true end
    local throttleDepth = tracker._sctThrottleQueue and #tracker._sctThrottleQueue or 0
    local queuesEmpty = tracker.m_DisplayedEvents:Front() == nil
        and tracker.m_PendingEvents:Front() == nil
        and throttleDepth == 0
    return queuesEmpty
end

local function destroyTrackerAtId(id)
    local tracker = CustomUI.SCT.EventTrackers[id]
    if tracker then
        tracker:Destroy()
        CustomUI.SCT.EventTrackers[id] = nil
    end
end

local function countEventTrackers()
    local n = 0
    for _ in pairs(CustomUI.SCT.EventTrackers or {}) do
        n = n + 1
    end
    return n
end

--- Pick LRU tracker id to evict; pass 1 = quiescent only, pass 2 = any.
local function findEvictionVictim(protectStorageKey, passQuiescentOnly)
    local victimId = nil
    local victimSeq = nil
    for id, tracker in pairs(CustomUI.SCT.EventTrackers or {}) do
        if id ~= protectStorageKey then
            local skipBusy = passQuiescentOnly and not trackerIsQuiescent(tracker)
            if not skipBusy then
                local seq = tonumber(tracker._sctTouchSeq) or 0
                if victimSeq == nil or seq < victimSeq then
                    victimSeq = seq
                    victimId = id
                end
            end
        end
    end
    return victimId
end

--- Drop oldest-touch trackers until count <= cap; never removes protectStorageKey.
local function enforceMaxEventTrackers(protectStorageKey)
    local maxN = c_EVENT_TRACKERS_MAX
    if type(maxN) ~= "number" or maxN < 8 then
        return
    end
    maxN = math.floor(maxN + 0.5)

    while countEventTrackers() > maxN do
        local victimId = findEvictionVictim(protectStorageKey, true)
        if victimId == nil then
            victimId = findEvictionVictim(protectStorageKey, false)
        end
        if victimId == nil then
            return
        end
        destroyTrackerAtId(victimId)
    end
end

-- storageKey: numeric worldObjNum for outgoing/points, or string keys for split incoming heal/damage/mitigation (see SCTOverrides Incoming*TrackerKey).
-- attachWorldObjNum: world object both anchors attach to (incoming sub-trackers use player wid).
local function getOrCreateTracker(storageKey, attachWorldObjNum, anchorName)
    if not CustomUI.SCT.EventTrackers[storageKey] then
        local an = anchorName
        if an == nil or an == "" then
            an = CustomUI.SCT.SctAnchorName(attachWorldObjNum)
        end
        if CustomUI.SCT.SctCreateAnchor(an) then
            local t = CustomUI.SCT.EventTracker:Create(an, attachWorldObjNum)
            if t then
                t.m_idleTime = 0
                t._sctThrottleCredit = 1
                bumpTrackerTouchSeq(t)
            end
            CustomUI.SCT.EventTrackers[storageKey] = t
            if t then
                enforceMaxEventTrackers(storageKey)
            end
        end
    end
    return CustomUI.SCT.EventTrackers[storageKey]
end

local function isHitOrCritType(textType)
    return textType == GameData.CombatEvent.HIT
        or textType == GameData.CombatEvent.ABILITY_HIT
        or textType == GameData.CombatEvent.CRITICAL
        or textType == GameData.CombatEvent.ABILITY_CRITICAL
end

local function playPointsGainSound(pointsGained)
    local n = tonumber(pointsGained)
    if n == nil or n <= 0 then
        return
    end
    if type(Sound) ~= "table" or type(Sound.Play) ~= "function" then
        return
    end
    if n >= 100 then
        if Sound.MONEY_TRANSACTION ~= nil then
            Sound.Play(Sound.MONEY_TRANSACTION)
        end
    else
        if Sound.MONEY_LOOT ~= nil then
            Sound.Play(Sound.MONEY_LOOT)
        end
    end
end

-- Mark a tracker active; called each time an event arrives so idle clock resets.
local function markTrackerActive(tracker)
    if tracker then
        tracker.m_idleTime = 0
        bumpTrackerTouchSeq(tracker)
    end
end

----------------------------------------------------------------
-- Six engine handlers
----------------------------------------------------------------

function CustomUI.SCT.OnCombatEvent(hitTargetObjectNumber, hitAmount, textType, abilityId)
    -- RoR WORLD_OBJ_COMBAT_EVENT payload for hit/crit lines: signed numeric amount —
    -- positive = heal, negative = damage. Missing/non-numeric amounts have nothing to show (ignore).
    -- Block/parry/evade/etc. use separate combat event types, not ambiguous amounts here.
    local isIncoming = (hitTargetObjectNumber == GameData.Player.worldObjNum)
    if isIncoming then
        if not CustomUI.SCT.CombatTypeIncomingEnabled(textType) then return end
    else
        if not CustomUI.SCT.CombatTypeOutgoingEnabled(textType) then return end
    end
    local isHitOrCrit = isHitOrCritType(textType)
    if isHitOrCrit then
        local amt = tonumber(hitAmount)
        if amt == nil or amt ~= amt then
            return
        end
        hitAmount = amt
    end
    if isHitOrCrit and hitAmount > 0 then
        local s = CustomUI.SCT.GetSettings()
        local f = isIncoming and (s.incoming or {}).filters or (s.outgoing or {}).filters
        f = f or {}
        if f.showHeal == false then return end
    end

    local tracker
    if isIncoming then
        local wid = hitTargetObjectNumber
        local lane = CustomUI.SCT._incomingFanLaneIndex % 3
        CustomUI.SCT._incomingFanLaneIndex = CustomUI.SCT._incomingFanLaneIndex + 1
        if lane == 0 then
            tracker = getOrCreateTracker(
                CustomUI.SCT.IncomingHealTrackerKey(wid),
                wid,
                CustomUI.SCT.IncomingHealAnchorName(wid))
        elseif lane == 1 then
            tracker = getOrCreateTracker(
                CustomUI.SCT.IncomingDamageTrackerKey(wid),
                wid,
                CustomUI.SCT.IncomingDamageAnchorName(wid))
        else
            tracker = getOrCreateTracker(
                CustomUI.SCT.IncomingMitigationTrackerKey(wid),
                wid,
                CustomUI.SCT.IncomingMitigationAnchorName(wid))
        end
    else
        tracker = getOrCreateTracker(hitTargetObjectNumber, hitTargetObjectNumber, CustomUI.SCT.SctAnchorName(hitTargetObjectNumber))
    end

    if tracker then
        markTrackerActive(tracker)
        dispatchOrQueueEvent(tracker, { event = COMBAT_EVENT, amount = hitAmount, type = textType, abilityId = abilityId })
    end
end

function CustomUI.SCT.OnXpText(hitTargetObjectNumber, pointsGained)
    local f = (CustomUI.SCT.GetSettings().outgoing or {}).filters or {}
    if f.showXP == false then return end
    playPointsGainSound(pointsGained)
    local wid = hitTargetObjectNumber
    local tracker = getOrCreateTracker(wid, wid, CustomUI.SCT.SctAnchorName(wid))
    if tracker then markTrackerActive(tracker); dispatchOrQueueEvent(tracker, { event = POINT_GAIN, amount = pointsGained, type = XP_GAIN }) end
end

function CustomUI.SCT.OnRenownText(hitTargetObjectNumber, pointsGained)
    local f = (CustomUI.SCT.GetSettings().outgoing or {}).filters or {}
    if f.showRenown == false then return end
    playPointsGainSound(pointsGained)
    local wid = hitTargetObjectNumber
    local tracker = getOrCreateTracker(wid, wid, CustomUI.SCT.SctAnchorName(wid))
    if tracker then markTrackerActive(tracker); dispatchOrQueueEvent(tracker, { event = POINT_GAIN, amount = pointsGained, type = RENOWN_GAIN }) end
end

function CustomUI.SCT.OnInfluenceText(hitTargetObjectNumber, pointsGained)
    local f = (CustomUI.SCT.GetSettings().outgoing or {}).filters or {}
    if f.showInfluence == false then return end
    playPointsGainSound(pointsGained)
    local wid = hitTargetObjectNumber
    local tracker = getOrCreateTracker(wid, wid, CustomUI.SCT.SctAnchorName(wid))
    if tracker then markTrackerActive(tracker); dispatchOrQueueEvent(tracker, { event = POINT_GAIN, amount = pointsGained, type = INFLUENCE_GAIN }) end
end

function CustomUI.SCT.OnLoadingBegin()
    CustomUI.SCT.loading = true
    -- Tear down all crit trackers on zone/UI load so pre-load state doesn't
    -- resume on the wrong targets after the load completes.
    CustomUI.SCT.DestroyAllTrackers()
    CustomUI.SCT._incomingFanLaneIndex = 0
end
function CustomUI.SCT.OnLoadingEnd()    CustomUI.SCT.loading = false end

----------------------------------------------------------------
-- OnUpdate driver — called by CustomUISCTWindow XML in Mode D
----------------------------------------------------------------

function CustomUI.SCT.OnUpdate(timePassed)
    if CustomUI.SCT.loading
       or (DoesWindowExist("LoadingWindow") and WindowGetShowing("LoadingWindow"))
    then return end

    -- One Settings() read for all crit lines this tick (EventEntry:Update runs per visible float).
    CustomUI.SCT._frameCritShake, CustomUI.SCT._frameCritPulse, CustomUI.SCT._frameCritFlash =
        CustomUI.SCT.GetCritFlags()

    CustomUI.SCT.FlushThrottle(timePassed)

    local inCombat = GameData and GameData.Player and GameData.Player.inCombat
    for id, tracker in pairs(CustomUI.SCT.EventTrackers or {}) do
        tracker:Update(timePassed)
        local throttleDepth = tracker._sctThrottleQueue and #tracker._sctThrottleQueue or 0
        local queuesEmpty = tracker.m_DisplayedEvents:Front() == nil
                         and tracker.m_PendingEvents:Front() == nil
                         and throttleDepth == 0
        if queuesEmpty then
            tracker.m_idleTime = (tracker.m_idleTime or 0) + timePassed
            if not inCombat or tracker.m_idleTime >= c_TRACKER_IDLE_EVICT_TIME then
                tracker:Destroy()
                CustomUI.SCT.EventTrackers[id] = nil
            end
        end
    end
end

function CustomUI.SCT.OnShutdown()
    CustomUI.SCT.RestoreHandlers()
    CustomUI.SCT.ClearThrottleQueue()
    CustomUI.SCT.DestroyAllTrackers()
end
