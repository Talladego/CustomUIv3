----------------------------------------------------------------
-- CustomUI.SCT: engine handlers, handler swap, layout-debug, OnUpdate targets.
-- Requires SCTEventText.lua (CustomUI.SCT._RuntimeForHandlers, EventTracker).
-- CustomUI.mod: SCTSettings, SCTEventText, this file, SCTController, View/SCT.xml.
----------------------------------------------------------------
if not CustomUI.SCT then CustomUI.SCT = {} end

-- Do not use `local R = assert(expr, msg)` here: some client Lua builds use a non-standard
-- assert that does not return its argument, leaving R nil while the check still passes.
local R = CustomUI.SCT._RuntimeForHandlers
if not R then
    error("CustomUI SCT: load SCTEventText.lua before SCTHandlers.lua (_RuntimeForHandlers missing)")
end

local function SCTLog(msg)
    R.SCTLog(msg)
end

local function SctLayoutDebugIsOn()
    return R.SctLayoutDebugIsOn()
end

local function SctAnchorName(targetObjectNumber, isCrit)
    return R.SctAnchorName(targetObjectNumber, isCrit)
end

local function SctEnsureEventTextRootAnchor(anchorName)
    return R.SctEnsureEventTextRootAnchor(anchorName)
end

local COMBAT_EVENT   = CustomUI.SCT.COMBAT_EVENT
local POINT_GAIN     = CustomUI.SCT.POINT_GAIN
local XP_GAIN        = CustomUI.SCT.XP_GAIN
local RENOWN_GAIN    = CustomUI.SCT.RENOWN_GAIN
local INFLUENCE_GAIN = CustomUI.SCT.INFLUENCE_GAIN

----------------------------------------------------------------
-- EA_System_EventText: CustomUI engine registrations
----------------------------------------------------------------

-- IMPORTANT:
-- - Do not replace stock EA_System_EventText globals/functions/classes.
-- - Enabling CustomUI.SCT swaps engine event-handler registrations to CustomUI handlers
--   so stock and CustomUI SCT cannot both process the same engine events.

CustomUI.SCT.Trackers     = CustomUI.SCT.Trackers     or {}
CustomUI.SCT.TrackersCrit = CustomUI.SCT.TrackersCrit or {}
CustomUI.SCT.loading      = CustomUI.SCT.loading      or false
CustomUI.SCT._handlersInstalled = CustomUI.SCT._handlersInstalled or false
CustomUI.SCT._stockWasRegistered = CustomUI.SCT._stockWasRegistered or {}

-- Plan section 6.3: engine event id, stock handler string, CustomUI handler string.
-- Must not touch SystemData.Events at file load: that table may not exist until after UI init.
local function sctEngineHandlers()
    local E = SystemData and SystemData.Events
    if not E then
        return nil
    end
    return {
        { id = E.WORLD_OBJ_COMBAT_EVENT,     stock = "EA_System_EventText.AddCombatEventText",     custom = "CustomUI.SCT.OnCombatEvent" },
        { id = E.WORLD_OBJ_XP_GAINED,        stock = "EA_System_EventText.AddXpText",              custom = "CustomUI.SCT.OnXpText" },
        { id = E.WORLD_OBJ_RENOWN_GAINED,    stock = "EA_System_EventText.AddRenownText",          custom = "CustomUI.SCT.OnRenownText" },
        { id = E.WORLD_OBJ_INFLUENCE_GAINED, stock = "EA_System_EventText.AddInfluenceText",       custom = "CustomUI.SCT.OnInfluenceText" },
        { id = E.LOADING_BEGIN,              stock = "EA_System_EventText.BeginLoading",           custom = "CustomUI.SCT.OnLoadingBegin" },
        { id = E.LOADING_END,                stock = "EA_System_EventText.EndLoading",             custom = "CustomUI.SCT.OnLoadingEnd" },
    }
end

local function SctApplyAllLayoutDebugVisibility(show)
    if not WindowSetShowing then return end
    local vis = (show == true)
    local function onTracker(tracker)
        if not tracker or not tracker.m_Anchor then return end
        local wp = tracker.m_Anchor .. "DebugWorldPoint"
        if DoesWindowExist and DoesWindowExist(wp) then
            pcall(function() WindowSetShowing(wp, vis) end)
        end
        local de = tracker.m_DisplayedEvents
        if not de then return end
        for i = de:Begin(), de:End() do
            local fr = de[i]
            if fr and fr.m_FlashHolderName then
                for _, suf in ipairs({ "DebugHolderBounds", "DebugHolderCenter", "DebugLabelBounds" }) do
                    local wn = fr.m_FlashHolderName .. suf
                    if DoesWindowExist and DoesWindowExist(wn) then
                        pcall(function() WindowSetShowing(wn, vis) end)
                    end
                end
            end
        end
    end
    for _, tr in pairs(CustomUI.SCT.Trackers or {}) do
        onTracker(tr)
    end
    for _, tr in pairs(CustomUI.SCT.TrackersCrit or {}) do
        onTracker(tr)
    end
end

function CustomUI.SCT.SctLayoutDebugEnabled()
    return SctLayoutDebugIsOn()
end

function CustomUI.SCT.SetSctLayoutDebug(show)
    if not CustomUI.SCT then CustomUI.SCT = {} end
    CustomUI.SCT.m_sctLayoutDebug = (show == true)
    SctApplyAllLayoutDebugVisibility(CustomUI.SCT.m_sctLayoutDebug)
    return CustomUI.SCT.m_sctLayoutDebug
end

function CustomUI.SCT.ToggleSctLayoutDebug()
    return CustomUI.SCT.SetSctLayoutDebug(not SctLayoutDebugIsOn())
end

function CustomUI.SCT.DestroyAllTrackers()
    for _, tracker in pairs(CustomUI.SCT.Trackers or {}) do
        pcall(function() tracker:Destroy() end)
    end
    CustomUI.SCT.Trackers = {}
    for id, tracker in pairs(CustomUI.SCT.TrackersCrit or {}) do
        pcall(function() tracker:Destroy() end)
        CustomUI.SCT.TrackersCrit[id] = nil
    end
end

function CustomUI.SCT.Activate()
    local enabled = CustomUI.IsComponentEnabled and CustomUI.IsComponentEnabled("SCT")
    SCTLog("Activate called; m_active was: " .. tostring(CustomUI.SCT.m_active) .. " component enabled: " .. tostring(enabled))
    if not enabled then
        SCTLog("Activate: component is disabled, staying inactive")
        return
    end
    CustomUI.SCT.m_active = true
    pcall(function() CustomUI.SCT.GetSettings() end)
    SCTLog("Activate done")
end

function CustomUI.SCT.Deactivate()
    SCTLog("Deactivate called; m_active was: " .. tostring(CustomUI.SCT.m_active))
    CustomUI.SCT.m_active = false
    CustomUI.SCT.DestroyAllTrackers()
    SCTLog("Deactivate done")
end

function CustomUI.SCT.OnCombatEvent(hitTargetObjectNumber, hitAmount, textType, abilityId)
    local isIncoming = (hitTargetObjectNumber == GameData.Player.worldObjNum)
    SCTLog("AddCombatEventText; active:" .. tostring(CustomUI.SCT.m_active)
        .. " type:" .. tostring(textType)
        .. " amount:" .. tostring(hitAmount)
        .. " dir:" .. (isIncoming and "incoming" or "outgoing")
        .. " target:" .. tostring(hitTargetObjectNumber)
        .. " abilityId:" .. tostring(abilityId))
    if not CustomUI.SCT.m_active then return end
    local sct        = CustomUI.SCT.GetSettings()
    local filters    = (isIncoming and sct.incoming and sct.incoming.filters)
                    or (sct.outgoing and sct.outgoing.filters) or {}
    local isHitOrCrit = (textType == GameData.CombatEvent.HIT)
                     or (textType == GameData.CombatEvent.ABILITY_HIT)
                     or (textType == GameData.CombatEvent.CRITICAL)
                     or (textType == GameData.CombatEvent.ABILITY_CRITICAL)
    if isHitOrCrit and hitAmount > 0 then
        if filters.showHeal == false then
            SCTLog("AddCombatEventText; filtered (showHeal=false)")
            return
        end
    else
        if isIncoming then
            if not CustomUI.SCT.CombatTypeIncomingEnabled(textType) then
                SCTLog("AddCombatEventText; filtered (incoming type " .. tostring(textType) .. " disabled)")
                return
            end
        else
            if not CustomUI.SCT.CombatTypeOutgoingEnabled(textType) then
                SCTLog("AddCombatEventText; filtered (outgoing type " .. tostring(textType) .. " disabled)")
                return
            end
        end
    end
    SCTLog("AddCombatEventText; passing through isCrit:" .. tostring((textType == GameData.CombatEvent.CRITICAL) or (textType == GameData.CombatEvent.ABILITY_CRITICAL)))

    local eventData = { event = COMBAT_EVENT, amount = hitAmount, type = textType, abilityId = abilityId }
    local isCrit    = (textType == GameData.CombatEvent.CRITICAL) or (textType == GameData.CombatEvent.ABILITY_CRITICAL)

    if isCrit then
        if CustomUI.SCT.TrackersCrit[hitTargetObjectNumber] == nil then
            local anchorName = SctAnchorName(hitTargetObjectNumber, true)
            if SctEnsureEventTextRootAnchor(anchorName) then
                CustomUI.SCT.TrackersCrit[hitTargetObjectNumber] = CustomUI.SCT.EventTracker:Create(anchorName, hitTargetObjectNumber, {
                    isCrit = true,
                })
            end
        end
        if CustomUI.SCT.TrackersCrit[hitTargetObjectNumber] then
            CustomUI.SCT.TrackersCrit[hitTargetObjectNumber]:AddEvent(eventData)
        end
        return
    end

    if CustomUI.SCT.Trackers[hitTargetObjectNumber] == nil then
        local anchorName = SctAnchorName(hitTargetObjectNumber, false)
        if SctEnsureEventTextRootAnchor(anchorName) then
            CustomUI.SCT.Trackers[hitTargetObjectNumber] = CustomUI.SCT.EventTracker:Create(anchorName, hitTargetObjectNumber, nil)
        end
    end
    if CustomUI.SCT.Trackers[hitTargetObjectNumber] then
        CustomUI.SCT.Trackers[hitTargetObjectNumber]:AddEvent(eventData)
    end
end

function CustomUI.SCT.OnXpText(hitTargetObjectNumber, pointsGained)
    SCTLog("AddXpText; active:" .. tostring(CustomUI.SCT.m_active) .. " amount:" .. tostring(pointsGained))
    if not CustomUI.SCT.m_active then return end
    if (CustomUI.SCT.GetSettings().outgoing or {}).filters and
       CustomUI.SCT.GetSettings().outgoing.filters.showXP == false then
        SCTLog("AddXpText; filtered (showXP=false)")
        return
    end
    CustomUI.SCT.AddPointGain(hitTargetObjectNumber, { event = POINT_GAIN, amount = pointsGained, type = XP_GAIN })
end

function CustomUI.SCT.OnRenownText(hitTargetObjectNumber, pointsGained)
    SCTLog("AddRenownText; active:" .. tostring(CustomUI.SCT.m_active) .. " amount:" .. tostring(pointsGained))
    if not CustomUI.SCT.m_active then return end
    if (CustomUI.SCT.GetSettings().outgoing or {}).filters and
       CustomUI.SCT.GetSettings().outgoing.filters.showRenown == false then
        SCTLog("AddRenownText; filtered (showRenown=false)")
        return
    end
    CustomUI.SCT.AddPointGain(hitTargetObjectNumber, { event = POINT_GAIN, amount = pointsGained, type = RENOWN_GAIN })
end

function CustomUI.SCT.OnInfluenceText(hitTargetObjectNumber, pointsGained)
    SCTLog("AddInfluenceText; active:" .. tostring(CustomUI.SCT.m_active) .. " amount:" .. tostring(pointsGained))
    if not CustomUI.SCT.m_active then return end
    if (CustomUI.SCT.GetSettings().outgoing or {}).filters and
       CustomUI.SCT.GetSettings().outgoing.filters.showInfluence == false then
        SCTLog("AddInfluenceText; filtered (showInfluence=false)")
        return
    end
    CustomUI.SCT.AddPointGain(hitTargetObjectNumber, { event = POINT_GAIN, amount = pointsGained, type = INFLUENCE_GAIN })
end

function CustomUI.SCT.AddPointGain(hitTargetObjectNumber, pointGainData)
    if CustomUI.SCT.Trackers[hitTargetObjectNumber] == nil then
        local anchorName = SctAnchorName(hitTargetObjectNumber, false)
        if SctEnsureEventTextRootAnchor(anchorName) then
            CustomUI.SCT.Trackers[hitTargetObjectNumber] = CustomUI.SCT.EventTracker:Create(anchorName, hitTargetObjectNumber)
        end
    end
    if CustomUI.SCT.Trackers[hitTargetObjectNumber] then
        CustomUI.SCT.Trackers[hitTargetObjectNumber]:AddEvent(pointGainData)
    end
end

function CustomUI.SCT.OnLoadingBegin()
    CustomUI.SCT.loading = true
end

function CustomUI.SCT.OnLoadingEnd()
    CustomUI.SCT.loading = false
end

local function SafeUnregister(id, handler)
    if UnregisterEventHandler and id and handler then
        pcall(function() UnregisterEventHandler(id, handler) end)
    end
end

local function SafeRegister(id, handler)
    if RegisterEventHandler and id and handler then
        pcall(function() RegisterEventHandler(id, handler) end)
    end
end

local function tryUnregisterStock(eventId, stockHandlerName)
    if not (UnregisterEventHandler and eventId and stockHandlerName) then
        return false
    end
    return select(1, pcall(function() UnregisterEventHandler(eventId, stockHandlerName) end))
end

function CustomUI.SCT.InstallHandlers()
    if CustomUI.SCT._handlersInstalled then return end
    SCTLog("InstallHandlers")

    local rows = sctEngineHandlers()
    if not rows then
        SCTLog("InstallHandlers: SystemData.Events not ready; will retry on next Enable")
        return
    end

    CustomUI.SCT._stockWasRegistered = {}
    for _, row in ipairs(rows) do
        CustomUI.SCT._stockWasRegistered[row.id] = tryUnregisterStock(row.id, row.stock)
    end
    for _, row in ipairs(rows) do
        SafeRegister(row.id, row.custom)
    end

    CustomUI.SCT._engineHandlerRowsCache = rows
    CustomUI.SCT.m_active = true
    CustomUI.SCT._handlersInstalled = true
end

function CustomUI.SCT.RestoreHandlers()
    if not CustomUI.SCT._handlersInstalled then return end
    SCTLog("RestoreHandlers")

    CustomUI.SCT.m_active = false

    local rows = CustomUI.SCT._engineHandlerRowsCache or sctEngineHandlers()
    if rows then
        for _, row in ipairs(rows) do
            SafeUnregister(row.id, row.custom)
        end
        for _, row in ipairs(rows) do
            if CustomUI.SCT._stockWasRegistered[row.id] then
                SafeRegister(row.id, row.stock)
            end
        end
    else
        SCTLog("RestoreHandlers: no row cache and SystemData.Events missing; stock handlers may not be restored")
    end

    CustomUI.SCT._engineHandlerRowsCache = nil
    CustomUI.SCT._handlersInstalled = false
end

function CustomUI.SCT.OnUpdate(timePassed)
    if not CustomUI.SCT.m_active then return end
    if CustomUI.SCT.loading
       or (DoesWindowExist("LoadingWindow") and WindowGetShowing("LoadingWindow"))
    then
        return
    end
    local inCombat = (GameData and GameData.Player and GameData.Player.inCombat) and true or false

    for id, tracker in pairs(CustomUI.SCT.Trackers or {}) do
        local ok, err = pcall(tracker.Update, tracker, timePassed)
        if not ok then
            SCTLog("SCT.Trackers Update failed: " .. tostring(err))
        end
        if not ok then
            pcall(tracker.Destroy, tracker)
            CustomUI.SCT.Trackers[id] = nil
        elseif tracker.m_DisplayedEvents:Front() == nil
            and tracker.m_PendingEvents:Front() == nil
            and not inCombat
        then
            tracker:Destroy()
            CustomUI.SCT.Trackers[id] = nil
        end
    end
    for id, tracker in pairs(CustomUI.SCT.TrackersCrit or {}) do
        local ok, err = pcall(tracker.Update, tracker, timePassed)
        if not ok then
            SCTLog("SCT.TrackersCrit Update failed: " .. tostring(err))
        end
        if not ok then
            pcall(tracker.Destroy, tracker)
            CustomUI.SCT.TrackersCrit[id] = nil
        elseif tracker.m_DisplayedEvents:Front() == nil and tracker.m_PendingEvents:Front() == nil then
            tracker:Destroy()
            CustomUI.SCT.TrackersCrit[id] = nil
        end
    end
end

function CustomUI.SCT.OnShutdown()
    if WindowSetShowing then
        pcall(function() WindowSetShowing("CustomUISCTWindow", false) end)
    end
    CustomUI.SCT.RestoreHandlers()
    CustomUI.SCT.DestroyAllTrackers()
end
