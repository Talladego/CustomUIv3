----------------------------------------------------------------
-- CustomUI.SCT.EventTracker
--
-- Tracker class and bulk tracker teardown. Hook installation and tracker
-- selection stay in SCTHandlers.lua / SCTOverrides.lua.
----------------------------------------------------------------
if not CustomUI.SCT then CustomUI.SCT = {} end

local StockEventTracker = _G["EA_System_EventTracker"]
if not StockEventTracker then
    error("CustomUI SCT: stock EA_System_EventTracker not found")
end

local COMBAT_EVENT = CustomUI.SCT.COMBAT_EVENT
local c_INCOMING_FAN_ARM = 72
local c_INCOMING_FAN_DIAG = 52

CustomUI.SCT.EventTrackers = CustomUI.SCT.EventTrackers or {}

local function SctStopAnimations(windowName)
    if not windowName or not DoesWindowExist(windowName) then
        return
    end
    WindowStopAlphaAnimation(windowName)
    WindowStopPositionAnimation(windowName)
    WindowStopScaleAnimation(windowName)
end

CustomUI.SCT.EventTracker = setmetatable({}, { __index = StockEventTracker })
CustomUI.SCT.EventTracker.__index = CustomUI.SCT.EventTracker

function CustomUI.SCT.EventTracker:Create(anchorWindowName, targetObjectNumber)
    local tracker = StockEventTracker.Create(self, anchorWindowName, targetObjectNumber)
    if tracker then
        tracker._sctThrottleQueue = {}
        tracker._sctThrottleCredit = 1
    end
    return tracker
end

function CustomUI.SCT.EventTracker:InitializeAnimationData(displayType)
    local animData = StockEventTracker.InitializeAnimationData(self, displayType)
    local category
    if displayType == COMBAT_EVENT then
        category = (self.m_TargetObject == GameData.Player.worldObjNum) and "incoming" or "outgoing"
    else
        category = "points"
    end

    local xOffset = CustomUI.SCT.GetXOffset and CustomUI.SCT.GetXOffset(category) or 0
    local yOffset = CustomUI.SCT.GetYOffset and CustomUI.SCT.GetYOffset(category) or 0

    local function applyIncomingFanCombatOffsets()
        if category ~= "incoming" or displayType ~= COMBAT_EVENT then
            return
        end
        local anchorName = self.m_Anchor
        if type(anchorName) ~= "string" then
            return
        end
        local suffix = string.match(anchorName, "_([^_]+)$")
        local arm, diag = c_INCOMING_FAN_ARM, c_INCOMING_FAN_DIAG
        local sx = animData.start.x or 0
        if suffix == "Heal" then
            animData.start.x = sx - arm
            animData.target.x = sx - arm - diag
            animData.current.x = animData.start.x
        elseif suffix == "Mit" then
            animData.start.x = sx + arm
            animData.target.x = sx + arm + diag
            animData.current.x = animData.start.x
        elseif suffix == "Dmg" then
            -- Center lane keeps vertical float only.
        end
    end

    if category == "points" then
        local sx = animData.start.x or 0
        local sy = animData.start.y or 0
        local tx = animData.target.x or 0
        local ty = animData.target.y or 0
        animData.start.x = xOffset
        animData.start.y = yOffset
        animData.target.x = xOffset + (tx - sx)
        animData.target.y = yOffset + (ty - sy)
        animData.current.x = animData.start.x
        animData.current.y = animData.start.y
    else
        animData.start.x = xOffset
        animData.target.x = xOffset
        animData.current.x = xOffset
        animData.start.y = (animData.start.y or 0) + yOffset
        animData.target.y = (animData.target.y or 0) + yOffset
        animData.current.y = (animData.current.y or 0) + yOffset
        applyIncomingFanCombatOffsets()
    end
    return animData
end

function CustomUI.SCT.EventTracker:Update(elapsedTime)
    local clearForPendingDispatch = true

    for index = self.m_DisplayedEvents:Begin(), self.m_DisplayedEvents:End() do
        local lifeElapsed = self.m_DisplayedEvents[index]:Update(elapsedTime, self.m_CurrentScrollSpeed)

        if lifeElapsed > (self.m_DisplayedEvents[index].m_AnimationData and
                          self.m_DisplayedEvents[index].m_AnimationData.maximumDisplayTime or 4)
           and index == self.m_DisplayedEvents:Begin()
        then
            local condemned = self.m_DisplayedEvents:PopFront()
            condemned:Destroy()
            clearForPendingDispatch = false
        elseif not self.m_DisplayedEvents[index]:IsOutOfStartingBox() then
            clearForPendingDispatch = false
        end
    end

    if not self.m_PendingEvents:IsEmpty() and clearForPendingDispatch then
        local eventType = self.m_PendingEvents:Front().event

        if eventType == COMBAT_EVENT then
            local newName = self.m_Anchor .. "Event" .. self.m_DisplayedEvents:End()
            if not DoesWindowExist(newName) then
                local eventData = self.m_PendingEvents:PopFront()
                local animData = self:InitializeAnimationData(eventType)
                local pendingCount = self.m_PendingEvents:End() - self.m_PendingEvents:Begin() + 1
                animData.target.y = animData.target.y - (pendingCount * 36)
                if CustomUI.SCT.GetCombatSplitLanes() then
                    animData.target.x = animData.target.x + (math.pow(-1, pendingCount) * pendingCount * 18)
                end

                local frame = CustomUI.SCT.EventEntry:Create(newName, self.m_Anchor, animData)
                if frame then
                    frame:SetupText(self.m_TargetObject, eventData.amount, eventData.type, eventData.abilityId)
                    WindowSetShowing(frame:GetName(), true)
                    WindowStartAlphaAnimation(frame:GetName(), Window.AnimationType.EASE_OUT,
                        1, 0, animData.fadeDuration, false, animData.fadeDelay, 0)
                    if frame.m_AbilityIconWindow and DoesWindowExist(frame.m_AbilityIconWindow) then
                        WindowStartAlphaAnimation(frame.m_AbilityIconWindow, Window.AnimationType.EASE_OUT,
                            1, 0, animData.fadeDuration, false, animData.fadeDelay, 0)
                    end
                    local suffixWindow = frame.m_AbilityNameSuffixWindow
                    if suffixWindow and suffixWindow ~= "" and DoesWindowExist(suffixWindow) then
                        WindowStartAlphaAnimation(suffixWindow, Window.AnimationType.EASE_OUT,
                            1, 0, animData.fadeDuration, false, animData.fadeDelay, 0)
                    end
                    self.m_DisplayedEvents:PushBack(frame)
                end
            end
        else
            local newName = self.m_Anchor .. "PointGain" .. self.m_DisplayedEvents:End()
            if not DoesWindowExist(newName) then
                local eventData = self.m_PendingEvents:PopFront()
                local animData = self:InitializeAnimationData(eventType)
                local pendingCount = self.m_PendingEvents:End() - self.m_PendingEvents:Begin() + 1
                animData.target.x = animData.target.x + (math.pow(-1, pendingCount) * pendingCount * 18)
                animData.target.y = animData.target.y - (pendingCount * 36)

                local frame = CustomUI.SCT.PointGainEntry:Create(newName, self.m_Anchor, animData)
                if frame then
                    frame:SetupText(self.m_TargetObject, eventData.amount, eventData.type)
                    WindowSetShowing(frame:GetName(), true)
                    WindowStartAlphaAnimation(frame:GetName(), Window.AnimationType.EASE_OUT,
                        1, 0, animData.fadeDuration, false, animData.fadeDelay, 0)
                    self.m_DisplayedEvents:PushBack(frame)
                end
            end
        end
    end

    if self.m_PendingEvents:IsEmpty() then
        self.m_CurrentScrollSpeed = math.max(
            self.m_MinimumScrollSpeed,
            self.m_CurrentScrollSpeed - self.m_ScrollAcceleration)
    else
        self.m_CurrentScrollSpeed = math.min(
            self.m_MaximumScrollSpeed,
            self.m_CurrentScrollSpeed + self.m_ScrollAcceleration)
    end
end

function CustomUI.SCT.EventTracker:Destroy()
    self._sctThrottleQueue = {}
    self._sctThrottleCredit = 1
    while self.m_PendingEvents:Front() ~= nil do
        self.m_PendingEvents:PopFront()
    end
    while self.m_DisplayedEvents:Front() ~= nil do
        self.m_DisplayedEvents:PopFront():Destroy()
    end
    if self.m_Anchor and DoesWindowExist(self.m_Anchor) then
        SctStopAnimations(self.m_Anchor)
        DetachWindowFromWorldObject(self.m_Anchor, self.m_TargetObject)
        DestroyWindow(self.m_Anchor)
    end
end

function CustomUI.SCT.DestroyAllTrackers()
    if type(CustomUI.SCT.ClearThrottleQueue) == "function" then
        CustomUI.SCT.ClearThrottleQueue()
    end
    for id, tracker in pairs(CustomUI.SCT.EventTrackers or {}) do
        tracker:Destroy()
        CustomUI.SCT.EventTrackers[id] = nil
    end
    CustomUI.SCT.EventTrackers = {}
end
