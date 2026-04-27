-- LEGACY (v2 SCT, 2026-04-25): replaced by SCTOverrides.lua. Safe to delete once
-- Step 5b verifies no remaining references. Do not extend or fix bugs in this file.
----------------------------------------------------------------
-- CustomUI.SCT — per-target EventTracker
-- Requires SCTAnim, SCTAnchors, and SCTEntry (EventEntry/PointGainEntry).
----------------------------------------------------------------
if not CustomUI.SCT then CustomUI.SCT = {} end
-- Do not use `local X = assert(expr, msg)` here: some client Lua builds use a non-standard
-- assert that does not return its argument, leaving X nil while the check still passes.
local A = CustomUI.SCT._SctAnim
if not A then
    error("CustomUI SCT: load SCTAnim.lua before SCTTracker.lua (_SctAnim missing)")
end
local H = CustomUI.SCT._SctAnchors
if not H then
    error("CustomUI SCT: load SCTAnchors.lua before SCTTracker.lua (_SctAnchors missing)")
end
local DEFAULT_FRIENDLY_EVENT_ANIMATION_PARAMETERS = A.DEFAULT_FRIENDLY_EVENT_ANIMATION_PARAMETERS
local DEFAULT_HOSTILE_EVENT_ANIMATION_PARAMETERS = A.DEFAULT_HOSTILE_EVENT_ANIMATION_PARAMETERS
local DEFAULT_POINT_GAIN_EVENT_ANIMATION_PARAMETERS = A.DEFAULT_POINT_GAIN_EVENT_ANIMATION_PARAMETERS
local MINIMUM_EVENT_SPACING = A.MINIMUM_EVENT_SPACING
local SctCritMainAnimDuration = A.SctCritMainAnimDuration
local CRIT_LANE_TRAVEL_DURATION = A.CRIT_LANE_TRAVEL_DURATION
local CRIT_LANE_OFFSET_X = A.CRIT_LANE_OFFSET_X
local CRIT_GROW_DURATION = A.CRIT_GROW_DURATION
local CRIT_FLOAT_DURATION = A.CRIT_FLOAT_DURATION
local LANE_DUR = A.LANE_DUR
local GROW_DUR = A.GROW_DUR
local SHAKE_DUR = A.SHAKE_DUR
local PULSE_DUR = A.PULSE_DUR
local FLASH_DUR = A.FLASH_DUR
local FLOAT_TAIL = A.FLOAT_TAIL
local MIN_DISPLAY_TIME = A.MIN_DISPLAY_TIME
local ENTRY_FADE_DURATION = A.ENTRY_FADE_DURATION
local Effects = A.Effects
local CRIT_SHAKE_AMPLITUDE = A.CRIT_SHAKE_AMPLITUDE
local CRIT_SHAKE_FREQUENCY = A.CRIT_SHAKE_FREQUENCY
local CRIT_SHAKE_VERTICAL_SCALE = A.CRIT_SHAKE_VERTICAL_SCALE
local CRIT_OSC_FREQUENCY = A.CRIT_OSC_FREQUENCY
local CRIT_OSC_SCALE_DELTA = A.CRIT_OSC_SCALE_DELTA
local COMBAT_EVENT = CustomUI.SCT.COMBAT_EVENT
local POINT_GAIN = CustomUI.SCT.POINT_GAIN
local SctStopWindowAnimations = H.SctStopWindowAnimations
local SctPcallFailed = H.SctPcallFailed
local SctDestroyEventWindowByName = H.SctDestroyEventWindowByName
local StockEventTracker = _G["EA_" .. "System_EventTracker"]

CustomUI.SCT.EventTracker = {}
CustomUI.SCT.EventTracker.__index = CustomUI.SCT.EventTracker
setmetatable(CustomUI.SCT.EventTracker, { __index = StockEventTracker })

function CustomUI.SCT.EventTracker:Create(anchorWindowName, targetObjectNumber, opts)
    if not DoesWindowExist(anchorWindowName) then
        return nil
    end
    local isPlayerTracker = (targetObjectNumber == GameData.Player.worldObjNum)
    local newTracker = {
        m_DisplayedEvents    = Queue:Create(),
        m_PendingEvents      = Queue:Create(),
        m_TargetObject       = targetObjectNumber,
        m_Anchor             = anchorWindowName,
        m_NextEntryIndex     = 0,
        m_MinimumScrollSpeed = 1,
        m_MaximumScrollSpeed = 20,
        m_CurrentScrollSpeed = 1,
        m_ScrollAcceleration = 0.1,
        m_AttachHeight       = isPlayerTracker and 0.3 or 0.8,
        m_IsCritTracker      = (opts and opts.isCrit) and true or false,
        m_CritLaneOffsetX    = (opts and opts.critLaneOffsetX) or 0,
        m_LaneSlots          = { [1] = false, [2] = false }, -- crit trackers only; false = free
    }
    setmetatable(newTracker, self)
    -- Keep the anchor continuously attached to the world object.
    -- MoveWindowToWorldObject is a one-shot move and will then appear screen-relative.
    local ok, err = pcall(AttachWindowToWorldObject, anchorWindowName, targetObjectNumber)
    if not ok then
        SctPcallFailed("AttachWindowToWorldObject", err)
        return nil
    end
    return newTracker
end

function CustomUI.SCT.EventTracker:AddEvent(eventData)
    eventData = eventData or {}
    self.m_PendingEvents:PushBack(eventData)
end

function CustomUI.SCT.EventTracker:ReserveLane()
    if not self.m_IsCritTracker then return nil end
    self.m_LaneSlots = self.m_LaneSlots or { [1] = false, [2] = false }
    for slot = 1, 2 do
        if not self.m_LaneSlots[slot] then
            self.m_LaneSlots[slot] = true
            return slot
        end
    end
    return nil
end

function CustomUI.SCT.EventTracker:ReleaseLane(slot)
    if not self.m_IsCritTracker then return end
    if not slot then return end
    self.m_LaneSlots = self.m_LaneSlots or { [1] = false, [2] = false }
    self.m_LaneSlots[slot] = false
end

function CustomUI.SCT.EventTracker:Update(elapsedTime)
    if self.m_Anchor and not DoesWindowExist(self.m_Anchor) then
        self.m_DisplayedEvents = Queue:Create()
        self.m_PendingEvents = Queue:Create()
        self.m_NextEntryIndex = 0
        return
    end
    if self.m_NextEntryIndex == nil then
        self.m_NextEntryIndex = 0
    end

    local clearForPendingDispatch = true

    for index = self.m_DisplayedEvents:Begin(), self.m_DisplayedEvents:End() do
        local frame = self.m_DisplayedEvents[index]
        if frame == nil then
            break
        end
        local lifeElapsed = frame:Update(elapsedTime, self.m_CurrentScrollSpeed)
        local maxLife = (frame and frame.m_BaseAnim and frame.m_BaseAnim.maxTime)
                     or (frame and frame.m_AnimationData and frame.m_AnimationData.maximumDisplayTime)
                     or DEFAULT_FRIENDLY_EVENT_ANIMATION_PARAMETERS.maximumDisplayTime
        if lifeElapsed > maxLife
           and index == self.m_DisplayedEvents:Begin()
        then
            self.m_DisplayedEvents:PopFront():Destroy()
            clearForPendingDispatch = false
        elseif not frame:IsOutOfStartingBox() then
            clearForPendingDispatch = false
        end
    end

    if not self.m_PendingEvents:IsEmpty() and clearForPendingDispatch then
        local eventType = self.m_PendingEvents:Front().event

        if eventType == COMBAT_EVENT then
            local eventDataFront = self.m_PendingEvents:Front()
            local entryIndex    = self.m_NextEntryIndex
            self.m_NextEntryIndex = self.m_NextEntryIndex + 1
            local newName       = self.m_Anchor .. "Event" .. entryIndex
            if DoesWindowExist(newName) then
                SctDestroyEventWindowByName(newName)
            end
            local eventData = eventDataFront
            local animData      = self:InitializeAnimationData(eventType)
            animData.target.y   = animData.target.y - ((self.m_PendingEvents:End() - self.m_PendingEvents:Begin() + 1) * MINIMUM_EVENT_SPACING)
            local parentForLabel = self.m_Anchor
            local animForLabel   = animData

                -- Crits: use a holder window under the world anchor.
                -- Holder handles move-to-lane + float; label stays center-anchored and does visual animation.
                local holderName
                local critSh, critPu, critCf = false, false, false
                if self.m_IsCritTracker and CustomUI.SCT and CustomUI.SCT.GetCritAnimFlags then
                    critSh, critPu, critCf = CustomUI.SCT.GetCritAnimFlags()
                end
                if self.m_IsCritTracker and (critSh or critPu or critCf) then
                    local laneSlot = self:ReserveLane()
                    if not laneSlot then
                        -- No lane available; try again next frame.
                        clearForPendingDispatch = false
                        return
                    end
                    eventData.laneSlot = laneSlot
                    local laneX = (laneSlot == 1) and CRIT_LANE_OFFSET_X or -CRIT_LANE_OFFSET_X
                    self.m_CritLaneOffsetX = laneX

                    holderName = self.m_Anchor .. "Holder" .. entryIndex
                    if DoesWindowExist(holderName) then
                        SctStopWindowAnimations(holderName)
                        DestroyWindow(holderName)
                    end
                    local createOk, createErr = pcall(CreateWindowFromTemplate, holderName, "EA_Window_EventTextAnchor", self.m_Anchor)
                    if not createOk then
                        SctPcallFailed("CreateWindowFromTemplate(crit holder)", createErr)
                    end
                    if not createOk or not DoesWindowExist(holderName) then
                        if eventData and eventData.laneSlot then
                            self:ReleaseLane(eventData.laneSlot)
                            eventData.laneSlot = nil
                        end
                        clearForPendingDispatch = false
                        return
                    end

                    -- 1) Start holder at base position (no lane offset), then the entry anim moves it into the crit lane.
                    if holderName then
                        WindowSetOffsetFromParent(holderName, animData.start.x, animData.start.y)
                        parentForLabel = holderName
                    end

                    -- 2) Label: holder-local (no float). We'll finalize centered offsets in SetupText after measuring glyph extents.
                    -- Fade after: lane move + grow + anim + float.
                    local animDur = SctCritMainAnimDuration(critSh, critPu, critCf)
                    local fadeDelay = CRIT_LANE_TRAVEL_DURATION + CRIT_GROW_DURATION + animDur + CRIT_FLOAT_DURATION
                    animData.fadeDelay = fadeDelay
                    animData.maximumDisplayTime = fadeDelay + animData.fadeDuration + 0.10

                    if holderName then
                        animForLabel = {
                            start              = { x = 0, y = 0 },
                            target             = { x = 0, y = 0 },
                            current            = { x = 0, y = 0 },
                            maximumDisplayTime = animData.maximumDisplayTime,
                            flashHolderMode    = true,
                        }
                    end
                end

                local frame         = CustomUI.SCT.EventEntry:Create(newName, parentForLabel, animForLabel)
                if frame and frame.GetName then
                    if holderName then
                        frame.m_FlashHolderName = holderName
                        frame.m_Tracker = self
                        frame.m_LaneSlot = eventData and eventData.laneSlot
                        if self.m_IsCritTracker then
                            local laneX = self.m_CritLaneOffsetX or 0
                            frame.m_CritLaneStartX = animData.start.x - laneX
                            frame.m_CritLaneTargetX = animData.start.x
                            frame.m_CritLaneY = animData.start.y
                            frame.m_CritLaneMoveDuration = CRIT_LANE_TRAVEL_DURATION
                            frame.m_FlashHolderBaseX = animData.start.x
                            frame.m_FlashHolderBaseY = animData.start.y
                            frame.m_CritFloatDeltaY = animData.target.y - animData.start.y
                            frame.m_CritFloatDuration = CRIT_FLOAT_DURATION
                        end
                    end
                    frame:SetupText(self.m_TargetObject, eventData.amount, eventData.type, eventData.abilityId)
                    WindowSetShowing(frame:GetName(), true)

                    -- Step 6 unified animation pipeline: build base anim + effect list.
                    frame.m_Window = frame:GetName()
                    frame.m_Holder = holderName
                    frame.m_Effects = {}
                    frame.m_BaseAnim = nil

                    local baseStartX, baseStartY = animData.start.x, animData.start.y
                    local baseTargetX, baseTargetY = animData.start.x, animData.target.y
                    local targetWindow = frame.m_Window

                    if holderName and (critSh or critPu or critCf) then
                        local laneX = self.m_CritLaneOffsetX or 0
                        baseStartX = animData.start.x - laneX
                        baseTargetX = baseStartX
                        targetWindow = holderName
                        -- LaneMove: holder slides from lane (animData.start.x) into center (baseStartX).
                        table.insert(frame.m_Effects, {
                            effect = Effects.LaneMove,
                            startAt = 0,
                            duration = LANE_DUR,
                            params = { window = holderName, fromX = animData.start.x, toX = baseStartX, y = animData.start.y },
                        })
                    end

                    local t = (holderName and (critSh or critPu or critCf)) and LANE_DUR or 0
                    if critSh or critPu or critCf then
                        -- Grow: only meaningful for shake/pulse; still runs for flash to keep timing consistent.
                        table.insert(frame.m_Effects, {
                            effect = Effects.Grow,
                            startAt = t,
                            duration = GROW_DUR,
                            params = { fromScale = frame.m_CritStartScale or 1.0, toScale = frame.m_CritEndScale or 1.0, centerPivot = false },
                        })
                        t = t + GROW_DUR

                        local mainEnd = t
                        if critSh then
                            table.insert(frame.m_Effects, {
                                effect = Effects.Shake,
                                startAt = t,
                                duration = SHAKE_DUR,
                                params = { window = holderName or frame.m_Window, baseX = animData.start.x, baseY = animData.start.y, amplitude = CRIT_SHAKE_AMPLITUDE, frequency = CRIT_SHAKE_FREQUENCY, verticalScale = CRIT_SHAKE_VERTICAL_SCALE },
                            })
                            mainEnd = math.max(mainEnd, t + SHAKE_DUR)
                        end
                        if critPu then
                            table.insert(frame.m_Effects, {
                                effect = Effects.Pulse,
                                startAt = t,
                                duration = PULSE_DUR,
                                params = { restScale = frame.m_CritEndScale or 1.0, frequency = CRIT_OSC_FREQUENCY, scaleDelta = CRIT_OSC_SCALE_DELTA, centerPivot = false },
                            })
                            mainEnd = math.max(mainEnd, t + PULSE_DUR)
                        end
                        if critCf then
                            table.insert(frame.m_Effects, {
                                effect = Effects.ColorFlash,
                                startAt = t,
                                duration = FLASH_DUR,
                                params = { tr = frame.m_TextTargetColorR or 255, tg = frame.m_TextTargetColorG or 255, tb = frame.m_TextTargetColorB or 255 },
                            })
                            mainEnd = math.max(mainEnd, t + FLASH_DUR)
                        end
                        t = mainEnd
                    end

                    local maxTime = math.max(MIN_DISPLAY_TIME, t + FLOAT_TAIL)
                    frame.m_BaseAnim = {
                        start = { x = baseStartX, y = baseStartY },
                        target = { x = baseTargetX, y = baseTargetY },
                        current = { x = baseStartX, y = baseStartY },
                        maxTime = maxTime,
                        targetWindow = targetWindow,
                    }
                    if frame.m_AnimationData then
                        frame.m_AnimationData.maximumDisplayTime = maxTime
                    end

                    local fadeDelay = math.max(0, maxTime - ENTRY_FADE_DURATION)
                    WindowStartAlphaAnimation(frame.m_Window, Window.AnimationType.EASE_OUT,
                        1, 0, ENTRY_FADE_DURATION, false, fadeDelay, 0)
                    if frame.m_AbilityIconWindow then
                        WindowStartAlphaAnimation(frame.m_AbilityIconWindow, Window.AnimationType.EASE_OUT,
                            1, 0, ENTRY_FADE_DURATION, false, fadeDelay, 0)
                    end

                    self.m_DisplayedEvents:PushBack(frame)
                end
                -- Only pop pending once we've successfully dispatched (and reserved any lane).
                if frame and frame.GetName then
                    self.m_PendingEvents:PopFront()
                else
                    if eventData and eventData.laneSlot then
                        self:ReleaseLane(eventData.laneSlot)
                        eventData.laneSlot = nil
                    end
                end
        else
            local eventData         = self.m_PendingEvents:PopFront()
            local entryIndex        = self.m_NextEntryIndex
            self.m_NextEntryIndex   = self.m_NextEntryIndex + 1
            local newName           = self.m_Anchor .. "PointGain" .. entryIndex
            if DoesWindowExist(newName) then
                SctDestroyEventWindowByName(newName)
            end
            local animData          = self:InitializeAnimationData(eventType)
            local pendingSize       = self.m_PendingEvents:End() - self.m_PendingEvents:Begin() + 1
            local sign              = ((pendingSize % 2) == 0) and 1 or -1
            animData.target.x       = animData.target.x + sign * (pendingSize * (MINIMUM_EVENT_SPACING / 2))
            animData.target.y       = animData.target.y - (pendingSize * MINIMUM_EVENT_SPACING)
            local frame             = CustomUI.SCT.PointGainEntry:Create(newName, self.m_Anchor, animData)
            if frame and frame.GetName then
                frame:SetupText(self.m_TargetObject, eventData.amount, eventData.type)
                WindowSetShowing(frame:GetName(), true)
                frame.m_Window = frame:GetName()
                frame.m_Holder = nil
                frame.m_Effects = {}
                local maxTime = math.max(MIN_DISPLAY_TIME, FLOAT_TAIL)
                frame.m_BaseAnim = {
                    start = { x = animData.start.x, y = animData.start.y },
                    target = { x = animData.target.x, y = animData.target.y },
                    current = { x = animData.start.x, y = animData.start.y },
                    maxTime = maxTime,
                    targetWindow = frame.m_Window,
                }
                if frame.m_AnimationData then
                    frame.m_AnimationData.maximumDisplayTime = maxTime
                end
                local fadeDelay = math.max(0, maxTime - ENTRY_FADE_DURATION)
                WindowStartAlphaAnimation(frame.m_Window, Window.AnimationType.EASE_OUT,
                    1, 0, ENTRY_FADE_DURATION, false, fadeDelay, 0)
                self.m_DisplayedEvents:PushBack(frame)
            end
        end
    end

    if self.m_PendingEvents:IsEmpty() then
        self.m_CurrentScrollSpeed = math.max(self.m_MinimumScrollSpeed, self.m_CurrentScrollSpeed - self.m_ScrollAcceleration)
    else
        self.m_CurrentScrollSpeed = math.min(self.m_MaximumScrollSpeed, self.m_CurrentScrollSpeed + self.m_ScrollAcceleration)
    end
end

function CustomUI.SCT.EventTracker:InitializeAnimationData(displayType)
    local base
    if displayType == COMBAT_EVENT then
        base = (self.m_TargetObject == GameData.Player.worldObjNum)
               and DEFAULT_FRIENDLY_EVENT_ANIMATION_PARAMETERS
               or  DEFAULT_HOSTILE_EVENT_ANIMATION_PARAMETERS
    else
        base = DEFAULT_POINT_GAIN_EVENT_ANIMATION_PARAMETERS
    end
    local laneX = (self.m_IsCritTracker and self.m_CritLaneOffsetX) or 0
    local xOffset = 0
    if CustomUI.SCT and CustomUI.SCT.GetBaseXOffset then
        xOffset = CustomUI.SCT.GetBaseXOffset() or 0
    end

    return {
        start              = { x = base.start.x  + laneX + xOffset, y = base.start.y  },
        target             = { x = base.target.x + laneX + xOffset, y = base.target.y },
        current            = { x = base.start.x  + laneX + xOffset, y = base.start.y  },
        maximumDisplayTime = base.maximumDisplayTime,
        fadeDelay          = base.fadeDelay,
        fadeDuration       = base.fadeDuration,
    }
end

function CustomUI.SCT.EventTracker:Destroy()
    while not self.m_PendingEvents:IsEmpty() do
        self.m_PendingEvents:PopFront()
    end
    while self.m_DisplayedEvents:Front() ~= nil do
        self.m_DisplayedEvents:PopFront():Destroy()
    end
    if self.m_Anchor and DoesWindowExist(self.m_Anchor) then
        SctStopWindowAnimations(self.m_Anchor)
        local detOk, detErr = pcall(DetachWindowFromWorldObject, self.m_Anchor, self.m_TargetObject)
        if not detOk then
            SctPcallFailed("DetachWindowFromWorldObject", detErr)
        end
        DestroyWindow(self.m_Anchor)
    end
end
