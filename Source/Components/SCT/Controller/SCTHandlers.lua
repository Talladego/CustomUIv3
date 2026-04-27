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

local function getOrCreateTracker(targetObjectNumber)
    if not CustomUI.SCT.EventTrackers[targetObjectNumber] then
        local anchorName = CustomUI.SCT.SctAnchorName(targetObjectNumber)
        if CustomUI.SCT.SctCreateAnchor(anchorName) then
            CustomUI.SCT.EventTrackers[targetObjectNumber] =
                CustomUI.SCT.EventTracker:Create(anchorName, targetObjectNumber)
        end
    end
    return CustomUI.SCT.EventTrackers[targetObjectNumber]
end

----------------------------------------------------------------
-- Six engine handlers
----------------------------------------------------------------

function CustomUI.SCT.OnCombatEvent(hitTargetObjectNumber, hitAmount, textType, abilityId)
    local isIncoming = (hitTargetObjectNumber == GameData.Player.worldObjNum)
    if isIncoming then
        if not CustomUI.SCT.CombatTypeIncomingEnabled(textType) then return end
    else
        if not CustomUI.SCT.CombatTypeOutgoingEnabled(textType) then return end
    end
    local isHitOrCrit = (textType == GameData.CombatEvent.HIT)
                     or (textType == GameData.CombatEvent.ABILITY_HIT)
                     or (textType == GameData.CombatEvent.CRITICAL)
                     or (textType == GameData.CombatEvent.ABILITY_CRITICAL)
    if isHitOrCrit and hitAmount > 0 then
        local f = (CustomUI.SCT.GetSettings().outgoing or {}).filters or {}
        if f.showHeal == false then return end
    end
    local tracker = getOrCreateTracker(hitTargetObjectNumber)
    if tracker then
        tracker:AddEvent({ event = COMBAT_EVENT, amount = hitAmount, type = textType, abilityId = abilityId })
    end
end

function CustomUI.SCT.OnXpText(hitTargetObjectNumber, pointsGained)
    local f = (CustomUI.SCT.GetSettings().outgoing or {}).filters or {}
    if f.showXP == false then return end
    local tracker = getOrCreateTracker(hitTargetObjectNumber)
    if tracker then tracker:AddEvent({ event = POINT_GAIN, amount = pointsGained, type = XP_GAIN }) end
end

function CustomUI.SCT.OnRenownText(hitTargetObjectNumber, pointsGained)
    local f = (CustomUI.SCT.GetSettings().outgoing or {}).filters or {}
    if f.showRenown == false then return end
    local tracker = getOrCreateTracker(hitTargetObjectNumber)
    if tracker then tracker:AddEvent({ event = POINT_GAIN, amount = pointsGained, type = RENOWN_GAIN }) end
end

function CustomUI.SCT.OnInfluenceText(hitTargetObjectNumber, pointsGained)
    local f = (CustomUI.SCT.GetSettings().outgoing or {}).filters or {}
    if f.showInfluence == false then return end
    local tracker = getOrCreateTracker(hitTargetObjectNumber)
    if tracker then tracker:AddEvent({ event = POINT_GAIN, amount = pointsGained, type = INFLUENCE_GAIN }) end
end

function CustomUI.SCT.OnLoadingBegin()  CustomUI.SCT.loading = true  end
function CustomUI.SCT.OnLoadingEnd()    CustomUI.SCT.loading = false end

----------------------------------------------------------------
-- OnUpdate driver — called by CustomUISCTWindow XML in Mode D
----------------------------------------------------------------

function CustomUI.SCT.OnUpdate(timePassed)
    if CustomUI.SCT.loading
       or (DoesWindowExist("LoadingWindow") and WindowGetShowing("LoadingWindow"))
    then return end

    local inCombat = GameData and GameData.Player and GameData.Player.inCombat
    for id, tracker in pairs(CustomUI.SCT.EventTrackers or {}) do
        tracker:Update(timePassed)
        if tracker.m_DisplayedEvents:Front() == nil
           and tracker.m_PendingEvents:Front() == nil
           and not inCombat
        then
            tracker:Destroy()
            CustomUI.SCT.EventTrackers[id] = nil
        end
    end
end

function CustomUI.SCT.OnShutdown()
    CustomUI.SCT.RestoreHandlers()
    CustomUI.SCT.DestroyAllTrackers()
end
