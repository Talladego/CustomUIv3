----------------------------------------------------------------
-- CustomUI.SCT — Event text runtime
if not CustomUI.SCT then CustomUI.SCT = {} end
-- Ported from ScrollingCombatTextSettings/easystem_eventtext.
-- Requires SCTSettings.lua to be loaded first.
----------------------------------------------------------------

----------------------------------------------------------------
-- Constants
----------------------------------------------------------------

CustomUI.SCT.COMBAT_EVENT  = 1
CustomUI.SCT.POINT_GAIN    = 2

CustomUI.SCT.XP_GAIN       = 1
CustomUI.SCT.RENOWN_GAIN   = 2
CustomUI.SCT.INFLUENCE_GAIN = 3

local COMBAT_EVENT   = CustomUI.SCT.COMBAT_EVENT
local POINT_GAIN     = CustomUI.SCT.POINT_GAIN
local XP_GAIN        = CustomUI.SCT.XP_GAIN
local RENOWN_GAIN    = CustomUI.SCT.RENOWN_GAIN
local INFLUENCE_GAIN = CustomUI.SCT.INFLUENCE_GAIN

local CombatEventText = {
    [ GameData.CombatEvent.HIT ]              = L"",
    [ GameData.CombatEvent.ABILITY_HIT ]      = L"",
    [ GameData.CombatEvent.CRITICAL ]         = L"",
    [ GameData.CombatEvent.ABILITY_CRITICAL ] = L"",
    [ GameData.CombatEvent.BLOCK ]    = GetStringFromTable( "CombatEvents", StringTables.CombatEvents.LABEL_BLOCK   ),
    [ GameData.CombatEvent.PARRY ]    = GetStringFromTable( "CombatEvents", StringTables.CombatEvents.LABEL_PARRY   ),
    [ GameData.CombatEvent.EVADE ]    = GetStringFromTable( "CombatEvents", StringTables.CombatEvents.LABEL_EVADE   ),
    [ GameData.CombatEvent.DISRUPT ]  = GetStringFromTable( "CombatEvents", StringTables.CombatEvents.LABEL_DISRUPT ),
    [ GameData.CombatEvent.ABSORB ]   = GetStringFromTable( "CombatEvents", StringTables.CombatEvents.LABEL_ABSORB  ),
    [ GameData.CombatEvent.IMMUNE ]   = GetStringFromTable( "CombatEvents", StringTables.CombatEvents.LABEL_IMMUNE  ),
}

local DEFAULT_FRIENDLY_EVENT_ANIMATION_PARAMETERS = {
    start              = { x = -280, y =  100 },
    target             = { x = -280, y =   20 },
    current            = { x = -280, y =  100 },
    maximumDisplayTime = 4,
    fadeDelay          = 2,
    fadeDuration       = 0.75,
}

local DEFAULT_HOSTILE_EVENT_ANIMATION_PARAMETERS = {
    start              = { x = -120, y =   0 },
    target             = { x = -120, y = -80 },
    current            = { x = -120, y =   0 },
    maximumDisplayTime = 4,
    fadeDelay          = 2,
    fadeDuration       = 0.75,
}

local DEFAULT_POINT_GAIN_EVENT_ANIMATION_PARAMETERS = {
    start              = { x = -200, y =  -90 },
    target             = { x = -200, y = -170 },
    current            = { x = -200, y =  -90 },
    maximumDisplayTime = 4,
    fadeDelay          = 2,
    fadeDuration       = 0.75,
}

local MINIMUM_EVENT_SPACING   = 36

local OWN_EVENT_SCALE_FACTOR   = 0.6
local OTHER_EVENT_SCALE_FACTOR = 0.48

-- Crit animation tuning
local CRIT_GROW_DURATION        = 0.20
local CRIT_SHAKE_DURATION       = 0.75
local CRIT_SHAKE_AMPLITUDE      = 8
local CRIT_SHAKE_FREQUENCY      = 30
local CRIT_SHAKE_VERTICAL_SCALE = 0.5
local CRIT_FONT_VISUAL_RATIO    = 1.33
local CRIT_COLOR_LERP_DURATION  = 1.00 -- used only for color ramp effects (not for Shake/Pulse by default)
-- Size oscillation (Pulse crit mode; setting value "flash"), after grow
local CRIT_OSC_DURATION         = 0.75
local CRIT_OSC_FREQUENCY        = 12
local CRIT_OSC_SCALE_DELTA      = 0.14 -- peak ±14% at start of osc, fades to 0

-- Color-only flash (new Flash crit mode), after grow
local CRIT_COLORFLASH_DURATION  = 0.75
local CRIT_COLORFLASH_FREQUENCY = 12

local CRIT_LANE_TRAVEL_DURATION = 0.15
local CRIT_FLOAT_DURATION       = 0.75

----------------------------------------------------------------
-- Debug helpers (must be defined early; used by tracker Update)
----------------------------------------------------------------

local function SCTLog(msg)
    if type(d) == "function" then d("[SCT] " .. tostring(msg)) end
end

local function SCTLogWindow(name, tag)
    if type(d) ~= "function" or name == nil then return end
    local n = tostring(name)
    if DoesWindowExist and not DoesWindowExist(n) then
        d(string.format("[SCT] %s %s <no such window>", tostring(tag or ""), n))
        return
    end
    local okSP, sx, sy = pcall(WindowGetScreenPosition, n)
    local okOff, ox, oy = pcall(WindowGetOffsetFromParent, n)
    local okDim, w, h = pcall(WindowGetDimensions, n)
    local okSc, sc = pcall(WindowGetScale, n)
    d(string.format("[SCT] %s %s sp=(%s,%s) off=(%s,%s) dim=(%s,%s) scale=%s",
        tostring(tag or ""),
        n,
        okSP and tostring(sx) or "?",
        okSP and tostring(sy) or "?",
        okOff and tostring(ox) or "?",
        okOff and tostring(oy) or "?",
        okDim and tostring(w) or "?",
        okDim and tostring(h) or "?",
        okSc and tostring(sc) or "?"
    ))
end

-- Offset so relative scaling reads as growing from the label center (engine default is top-left pivot).
-- baseW/baseH = pixel dimensions at endScale; startX/startY = rest offset from parent.
local function CritFlashOffsetForCenterPivot(startX, startY, baseW, baseH, endScale, s)
    if baseW == nil or baseH == nil or baseW <= 0 or baseH <= 0 or endScale == nil or endScale == 0 then
        return startX, startY
    end
    local r = s / endScale
    return startX + baseW * (1 - r) / 2, startY + baseH * (1 - r) / 2
end

local function SctLabelFontName()
    if CustomUI.SCT and CustomUI.SCT.GetTextFontName then
        return CustomUI.SCT.GetTextFontName()
    end
    return "font_default_text_large"
end

----------------------------------------------------------------
-- EA_System_EventEntry — one floating combat text label
----------------------------------------------------------------

EA_System_EventEntry = Frame:Subclass("EA_Window_EventTextLabel")

function EA_System_EventEntry:Create(windowName, parentWindow, animationData)
    local eventFrame = self:CreateFromTemplate(windowName, parentWindow)
    if eventFrame ~= nil then
        eventFrame.m_LifeSpan      = 0
        eventFrame.m_AnimationData = {
            start              = { x = animationData.start.x,  y = animationData.start.y  },
            target             = { x = animationData.target.x, y = animationData.target.y },
            current            = { x = animationData.start.x,  y = animationData.start.y  },
            maximumDisplayTime = animationData.maximumDisplayTime,
        }
        if animationData.flashHolderMode then
            eventFrame.m_AnimationData.flashHolderMode = true
        end
    end
    WindowSetOffsetFromParent(windowName, animationData.start.x, animationData.start.y)
    return eventFrame
end

function EA_System_EventEntry:Update(elapsedTime, simulationSpeed)
    local simulationTime = elapsedTime * simulationSpeed
    local animationStep  = simulationTime / self.m_AnimationData.maximumDisplayTime

    -- Critical two-phase impact: grow → shake → float
    if self.m_IsCritical and self.m_CritPhase ~= nil then
        local critTimeMult = 1.0
        if CustomUI.SCT and CustomUI.SCT.m_active and CustomUI.SCT.GetSettings then
            local sct = CustomUI.SCT.GetSettings()
            critTimeMult = (sct and sct.critAnimationSpeed) or 1.0
            if type(critTimeMult) ~= "number" or critTimeMult < 0.5 or critTimeMult > 1.5 then
                critTimeMult = 1.0
            end
        end
        self.m_CritPhaseElapsed = (self.m_CritPhaseElapsed or 0) + simulationTime * critTimeMult
        local wName = self:GetName()

        if self.m_CritPhase == "lanemove" then
            local dur = self.m_CritLaneMoveDuration or CRIT_LANE_TRAVEL_DURATION
            local t = dur > 0 and math.min(1, self.m_CritPhaseElapsed / dur) or 1
            local ease = 1 - (1 - t) * (1 - t)
            if self.m_FlashHolderName then
                local sx = self.m_CritLaneStartX or (self.m_FlashHolderBaseX or 0)
                local tx = self.m_CritLaneTargetX or (self.m_FlashHolderBaseX or 0)
                local y  = self.m_CritLaneY or (self.m_FlashHolderBaseY or 0)
                WindowSetOffsetFromParent(self.m_FlashHolderName, sx + (tx - sx) * ease, y)
            end
            self.m_LifeSpan = self.m_LifeSpan + simulationTime
            if self.m_CritPhaseElapsed >= dur then
                self.m_CritPhaseElapsed = 0
                self.m_CritPhase = "grow"
            end
            return self.m_LifeSpan
        end

        if self.m_CritPhase == "grow" then
            local duration = self.m_CritGrowDuration or CRIT_GROW_DURATION
            local t = duration > 0 and math.min(1, self.m_CritPhaseElapsed / duration) or 0
            local ease = 1 - (1 - t) * (1 - t)
            local s = (self.m_CritStartScale or 1.0) + ((self.m_CritEndScale or 1.0) - (self.m_CritStartScale or 1.0)) * ease
            if WindowSetScale then WindowSetScale(wName, s) end
            WindowSetRelativeScale(wName, s)
            -- Pulse (flash) holder mode: do not use offsets; keep strict center→center anchoring.
            if self.m_AnimationData and self.m_AnimationData.flashHolderMode then
                if WindowUtils and WindowUtils.ForceProcessAnchors then WindowUtils.ForceProcessAnchors(wName) end
            else
                -- Keep the label centered while scaling (engine pivot is top-left).
                local startX = self.m_AnimationData.start.x
                local startY = self.m_AnimationData.start.y
                local baseW  = self.m_CritFlashBaseW
                local baseH  = self.m_CritFlashBaseH
                local endScale = self.m_CritEndScale or 1.0
                local ox, oy = CritFlashOffsetForCenterPivot(startX, startY, baseW, baseH, endScale, s)
                WindowSetOffsetFromParent(self:GetName(), ox, oy)
            end
            if self.m_CritPhaseElapsed >= duration then
                self.m_CritPhaseElapsed = 0
                local endScale = self.m_CritEndScale or 1.0
                if WindowSetScale then WindowSetScale(wName, endScale) end
                WindowSetRelativeScale(wName, endScale)
                if self.m_AnimationData and self.m_AnimationData.flashHolderMode then
                    if WindowUtils and WindowUtils.ForceProcessAnchors then WindowUtils.ForceProcessAnchors(wName) end
                else
                    WindowSetOffsetFromParent(self:GetName(), self.m_AnimationData.start.x, self.m_AnimationData.start.y)
                end
                local animMode = self.m_CritAnimMode or "shake"
                if animMode == "pulse" then
                    self.m_CritPhase = "flashosc"
                elseif animMode == "flash" then
                    self.m_CritPhase = "colorflash"
                elseif animMode == "shake" then
                    self.m_CritPhase = "shake"
                else
                    self.m_CritPhase = "float"
                end
            end
            self.m_LifeSpan = self.m_LifeSpan + simulationTime
            return self.m_LifeSpan

        elseif self.m_CritPhase == "shake" then
            local duration = self.m_CritShakeDuration or CRIT_SHAKE_DURATION
            local t = duration > 0 and math.min(1, self.m_CritPhaseElapsed / duration) or 0
            local endScale = self.m_CritEndScale or 1.0
            if WindowSetScale then WindowSetScale(wName, endScale) end
            WindowSetRelativeScale(wName, endScale)
            local amp  = (self.m_CritShakeAmplitude or CRIT_SHAKE_AMPLITUDE) * (1 - t)
            local freq = self.m_CritShakeFrequency or CRIT_SHAKE_FREQUENCY
            local dx = amp * math.sin(2 * math.pi * freq * self.m_CritPhaseElapsed)
            local dy = (amp * (self.m_CritShakeVerticalScale or CRIT_SHAKE_VERTICAL_SCALE)) * math.cos(2 * math.pi * freq * self.m_CritPhaseElapsed)
            if self.m_AnimationData and self.m_AnimationData.flashHolderMode and self.m_FlashHolderName then
                -- Holder-based shake: keep label centered on holder; shake the holder around its lane position.
                local bx = self.m_FlashHolderBaseX or 0
                local by = self.m_FlashHolderBaseY or 0
                WindowSetOffsetFromParent(self.m_FlashHolderName, bx + dx, by + dy)
                if WindowUtils and WindowUtils.ForceProcessAnchors then WindowUtils.ForceProcessAnchors(wName) end
            else
                WindowSetOffsetFromParent(self:GetName(), self.m_AnimationData.start.x + dx, self.m_AnimationData.start.y + dy)
            end
            local tr, tg, tb = self.m_TextTargetColorR or 255, self.m_TextTargetColorG or 255, self.m_TextTargetColorB or 255
            if self.m_CritPhaseElapsed >= duration then
                self.m_CritPhase = "float"
                self.m_CritPhaseElapsed = 0
                LabelSetTextColor(self:GetName(), tr, tg, tb)
                if self.m_AnimationData and self.m_AnimationData.flashHolderMode and self.m_FlashHolderName then
                    local bx = self.m_FlashHolderBaseX or 0
                    local by = self.m_FlashHolderBaseY or 0
                    WindowSetOffsetFromParent(self.m_FlashHolderName, bx, by)
                    if WindowUtils and WindowUtils.ForceProcessAnchors then WindowUtils.ForceProcessAnchors(wName) end
                else
                    WindowSetOffsetFromParent(self:GetName(), self.m_AnimationData.start.x, self.m_AnimationData.start.y)
                end
                self.m_AnimationData.current.x = self.m_AnimationData.start.x
                self.m_AnimationData.current.y = self.m_AnimationData.start.y
            end
            self.m_LifeSpan = self.m_LifeSpan + simulationTime
            return self.m_LifeSpan

        elseif self.m_CritPhase == "flashosc" then
            local duration = self.m_CritOscDuration or CRIT_OSC_DURATION
            local t = duration > 0 and math.min(1, self.m_CritPhaseElapsed / duration) or 0
            local endScale = self.m_CritEndScale or 1.0
            local startX = self.m_AnimationData.start.x
            local startY = self.m_AnimationData.start.y

            if self.m_CritFlashBaseW == nil then
                if WindowSetScale then WindowSetScale(wName, endScale) end
                WindowSetRelativeScale(wName, endScale)
                WindowSetOffsetFromParent(self:GetName(), startX, startY)
                -- Prefer actual rendered text extents (label size is fixed 400x100, which biases pivot up/left).
                local ok, dw, dh = pcall(LabelGetTextDimensions, wName)
                if not (ok and dw and dh and dw > 0 and dh > 0) then
                    ok, dw, dh = pcall(WindowGetDimensions, wName)
                end
                self.m_CritFlashBaseW = (ok and dw and dw > 0) and dw or 80
                self.m_CritFlashBaseH = (ok and dh and dh > 0) and dh or 24

                -- Capture the desired on-screen center point at rest (endScale). This lets us
                -- compensate for engine clamping/reprojection of world-attached windows so the
                -- pulse expands toward the viewer from a stable screen-space center.
                if not (self.m_AnimationData and self.m_AnimationData.stationaryCritFlash) then
                    local okSP, sx, sy = pcall(WindowGetScreenPosition, wName)
                    if okSP and sx and sy then
                        local uiScale = (InterfaceCore and InterfaceCore.GetScale and InterfaceCore.GetScale()) or 1
                        self.m_CritFlashCenterScreenX = sx + (self.m_CritFlashBaseW * endScale * uiScale) / 2
                        self.m_CritFlashCenterScreenY = sy + (self.m_CritFlashBaseH * endScale * uiScale) / 2
                    else
                        self.m_CritFlashCenterScreenX = nil
                        self.m_CritFlashCenterScreenY = nil
                    end
                end
            end

            local env = 1 - t
            local osc = math.sin(2 * math.pi * CRIT_OSC_FREQUENCY * self.m_CritPhaseElapsed)
            local delta = CRIT_OSC_SCALE_DELTA * env
            local s = endScale * (1 + delta * osc)
            if WindowSetScale then WindowSetScale(wName, s) end
            WindowSetRelativeScale(wName, s)
            if self.m_AnimationData and self.m_AnimationData.flashHolderMode then
                if WindowUtils and WindowUtils.ForceProcessAnchors then WindowUtils.ForceProcessAnchors(wName) end
            else
                -- Use the configured rest offset (startX/startY) as the stable "center" reference.
                local ox, oy = CritFlashOffsetForCenterPivot(startX, startY, self.m_CritFlashBaseW, self.m_CritFlashBaseH, endScale, s)
                WindowSetOffsetFromParent(self:GetName(), ox, oy)
            end

            -- Screen-space center lock (optional): after applying the ideal center-pivot offset,
            -- nudge by any residual drift in screen coordinates. This mitigates lane/edge-dependent
            -- anchoring/clamping effects.
            if (not (self.m_AnimationData and self.m_AnimationData.stationaryCritFlash))
               and self.m_CritFlashCenterScreenX ~= nil and self.m_CritFlashCenterScreenY ~= nil
            then
                local okSP, sx, sy = pcall(WindowGetScreenPosition, wName)
                if okSP and sx and sy then
                    local uiScale = (InterfaceCore and InterfaceCore.GetScale and InterfaceCore.GetScale()) or 1
                    local curCX = sx + (self.m_CritFlashBaseW * s * uiScale) / 2
                    local curCY = sy + (self.m_CritFlashBaseH * s * uiScale) / 2
                    local dx = (self.m_CritFlashCenterScreenX - curCX)
                    local dy = (self.m_CritFlashCenterScreenY - curCY)
                    if math.abs(dx) > 0.1 or math.abs(dy) > 0.1 then
                        local okOff, px, py = pcall(WindowGetOffsetFromParent, wName)
                        if okOff and px and py and uiScale ~= 0 then
                            WindowSetOffsetFromParent(self:GetName(), px + dx / uiScale, py + dy / uiScale)
                        end
                    end
                end
            end

            local tr, tg, tb = self.m_TextTargetColorR or 255, self.m_TextTargetColorG or 255, self.m_TextTargetColorB or 255
            if self.m_CritPhaseElapsed >= duration then
                self.m_CritPhase = "float"
                self.m_CritPhaseElapsed = 0
                self.m_CritFlashBaseW = nil
                self.m_CritFlashBaseH = nil
                self.m_CritFlashCenterScreenX = nil
                self.m_CritFlashCenterScreenY = nil
                LabelSetTextColor(self:GetName(), tr, tg, tb)
                if WindowSetScale then WindowSetScale(wName, endScale) end
                WindowSetRelativeScale(wName, endScale)
                if self.m_AnimationData and self.m_AnimationData.flashHolderMode then
                    if WindowUtils and WindowUtils.ForceProcessAnchors then WindowUtils.ForceProcessAnchors(wName) end
                    self.m_AnimationData.start.x   = 0
                    self.m_AnimationData.start.y   = 0
                    self.m_AnimationData.target.x  = 0
                    self.m_AnimationData.target.y  = 0
                    self.m_AnimationData.current.x = 0
                    self.m_AnimationData.current.y = 0
                else
                    WindowSetOffsetFromParent(self:GetName(), startX, startY)
                end
                self.m_AnimationData.current.x = startX
                self.m_AnimationData.current.y = startY
            end
            self.m_LifeSpan = self.m_LifeSpan + simulationTime
            return self.m_LifeSpan

        elseif self.m_CritPhase == "colorflash" then
            local duration = self.m_CritColorFlashDuration or CRIT_COLORFLASH_DURATION
            local t = duration > 0 and math.min(1, self.m_CritPhaseElapsed / duration) or 0

            local endScale = self.m_CritEndScale or 1.0
            if WindowSetScale then WindowSetScale(wName, endScale) end
            WindowSetRelativeScale(wName, endScale)

            if self.m_AnimationData and self.m_AnimationData.flashHolderMode then
                if WindowUtils and WindowUtils.ForceProcessAnchors then WindowUtils.ForceProcessAnchors(wName) end
            else
                WindowSetOffsetFromParent(self:GetName(), self.m_AnimationData.start.x, self.m_AnimationData.start.y)
            end

            local tr, tg, tb = self.m_TextTargetColorR or 255, self.m_TextTargetColorG or 255, self.m_TextTargetColorB or 255
            local f = self.m_CritColorFlashFrequency or CRIT_COLORFLASH_FREQUENCY
            local osc = 0.5 + 0.5 * math.sin(2 * math.pi * f * self.m_CritPhaseElapsed) -- 0..1
            local env = 1 - t
            local a = osc * env -- fade to stable at end
            LabelSetTextColor(self:GetName(),
                math.floor(tr + (255 - tr) * a + 0.5),
                math.floor(tg + (255 - tg) * a + 0.5),
                math.floor(tb + (255 - tb) * a + 0.5))

            if self.m_CritPhaseElapsed >= duration then
                self.m_CritPhase = "float"
                self.m_CritPhaseElapsed = 0
                LabelSetTextColor(self:GetName(), tr, tg, tb)
                if self.m_AnimationData and self.m_AnimationData.flashHolderMode then
                    if WindowUtils and WindowUtils.ForceProcessAnchors then WindowUtils.ForceProcessAnchors(wName) end
                else
                    WindowSetOffsetFromParent(self:GetName(), self.m_AnimationData.start.x, self.m_AnimationData.start.y)
                end
                self.m_AnimationData.current.x = self.m_AnimationData.start.x
                self.m_AnimationData.current.y = self.m_AnimationData.start.y
            end
            self.m_LifeSpan = self.m_LifeSpan + simulationTime
            return self.m_LifeSpan

        elseif self.m_CritPhase == "float" then
            local dur = self.m_CritFloatDuration or CRIT_FLOAT_DURATION
            local t = dur > 0 and math.min(1, self.m_CritPhaseElapsed / dur) or 1
            local ease = 1 - (1 - t) * (1 - t)
            if self.m_FlashHolderName then
                local bx = self.m_CritLaneTargetX or (self.m_FlashHolderBaseX or 0)
                local by = self.m_CritLaneY or (self.m_FlashHolderBaseY or 0)
                local dy = self.m_CritFloatDeltaY or 0
                WindowSetOffsetFromParent(self.m_FlashHolderName, bx, by + dy * ease)
                if WindowUtils and WindowUtils.ForceProcessAnchors then WindowUtils.ForceProcessAnchors(wName) end
            end
            if self.m_CritPhaseElapsed >= dur then
                self.m_CritPhase = nil
                self.m_CritPhaseElapsed = 0
            end
            self.m_LifeSpan = self.m_LifeSpan + simulationTime
            return self.m_LifeSpan
        end
    end

    -- Holder crits: label is anchored to holder; do not run generic drift on the label.
    if self.m_AnimationData and self.m_AnimationData.flashHolderMode and self.m_FlashHolderName then
        self.m_LifeSpan = self.m_LifeSpan + simulationTime
        return self.m_LifeSpan
    end

    local stepX = (self.m_AnimationData.target.x - self.m_AnimationData.start.x) * animationStep
    local stepY = (self.m_AnimationData.target.y - self.m_AnimationData.start.y) * animationStep
    self.m_AnimationData.current.x = self.m_AnimationData.current.x + stepX
    self.m_AnimationData.current.y = self.m_AnimationData.current.y + stepY
    WindowSetOffsetFromParent(self:GetName(), self.m_AnimationData.current.x, self.m_AnimationData.current.y)
    self.m_LifeSpan = self.m_LifeSpan + simulationTime
    return self.m_LifeSpan
end

function EA_System_EventEntry:SetupText(hitTargetObjectNumber, hitAmount, textType)
    local text
    local isHitOrCrit = (textType == GameData.CombatEvent.HIT)
                     or (textType == GameData.CombatEvent.ABILITY_HIT)
                     or (textType == GameData.CombatEvent.CRITICAL)
                     or (textType == GameData.CombatEvent.ABILITY_CRITICAL)
    if isHitOrCrit then
        text = hitAmount > 0 and (L"+" .. hitAmount) or (L"" .. hitAmount)
    else
        text = L"" .. CombatEventText[textType]
    end

    local color = DefaultColor.GetCombatEventColor(hitTargetObjectNumber, hitAmount, textType)
    local isCrit = (textType == GameData.CombatEvent.CRITICAL) or (textType == GameData.CombatEvent.ABILITY_CRITICAL)
    self.m_IsCritical = isCrit

    LabelSetText(self:GetName(), text)

    local wName = self:GetName()

    if not CustomUI.SCT.m_active then
        -- SCT disabled: plain float, no crit animation, no custom scale or color
        self.m_IsCritical = false
        LabelSetFont(wName, SctLabelFontName(), WindowUtils.FONT_DEFAULT_TEXT_LINESPACING)
        if WindowSetScale then WindowSetScale(wName, 1.0) end
        WindowSetRelativeScale(wName, 1.0)
        self.m_TextTargetColorR, self.m_TextTargetColorG, self.m_TextTargetColorB = color.r, color.g, color.b
        LabelSetTextColor(wName, color.r, color.g, color.b)
        WindowSetFontAlpha(wName, 1.0)
        return
    end

    local sct = CustomUI.SCT.GetSettings()
    local key = CustomUI.SCT.KeyForCombatType(textType)
    if isHitOrCrit and hitAmount > 0 then key = "Heal" end
    self.m_TextTypeKey = key

    local isIncoming = (hitTargetObjectNumber == GameData.Player.worldObjNum)
    local sizeTable  = isIncoming and sct.incoming or sct.outgoing
    local scale      = (sizeTable and sizeTable.size and sizeTable.size[key]) or 1.0

    if isCrit then
        local critAnim = sct.critAnimation or "shake"
        if critAnim ~= "none" and critAnim ~= "shake" and critAnim ~= "pulse" and critAnim ~= "flash" then
            critAnim = "shake"
        end
        self.m_CritAnimMode = critAnim

        LabelSetFont(wName, SctLabelFontName(), WindowUtils.FONT_DEFAULT_TEXT_LINESPACING)
        if critAnim == "none" then
            -- No crit animation: just scale + default drift.
            self.m_CritPhase = nil
            if WindowSetScale then WindowSetScale(wName, scale) end
            WindowSetRelativeScale(wName, scale)
            WindowSetOffsetFromParent(self:GetName(), self.m_AnimationData.start.x, self.m_AnimationData.start.y)
        else
            -- Shake / Pulse / Flash: grow phase then shake/osc/colorflash.
            self.m_CritPhase              = "grow"
            self.m_CritPhaseElapsed       = 0
            self.m_CritGrowDuration       = CRIT_GROW_DURATION
            self.m_CritShakeDuration      = CRIT_SHAKE_DURATION
            self.m_CritShakeAmplitude     = CRIT_SHAKE_AMPLITUDE
            self.m_CritShakeFrequency     = CRIT_SHAKE_FREQUENCY
            self.m_CritShakeVerticalScale = CRIT_SHAKE_VERTICAL_SCALE
            self.m_CritOscDuration        = CRIT_OSC_DURATION
            self.m_CritColorFlashDuration = CRIT_COLORFLASH_DURATION
            self.m_CritColorFlashFrequency = CRIT_COLORFLASH_FREQUENCY
            -- Start scale: Pulse/Shake grow in; Flash should not "pulse" size at all.
            self.m_CritStartScale         = (critAnim == "flash") and scale or (scale / CRIT_FONT_VISUAL_RATIO)
            self.m_CritEndScale           = scale
            -- For holder-based crit modes (Pulse/Shake), capture rendered extents so center anchoring matches glyphs.
            self.m_CritFlashBaseW         = nil
            self.m_CritFlashBaseH         = nil
            if self.m_AnimationData and self.m_AnimationData.flashHolderMode and (critAnim == "pulse" or critAnim == "shake" or critAnim == "flash") then
                local ok, tw, th = pcall(LabelGetTextDimensions, wName)
                if ok and tw and th and tw > 0 and th > 0 then
                    self.m_CritFlashBaseW = tw
                    self.m_CritFlashBaseH = th
                end
                -- Holder mode (Pulse/Shake): strict center anchoring, no per-label offsets.
                local w = self.m_CritFlashBaseW or 80
                local h = self.m_CritFlashBaseH or 24
                WindowSetDimensions(wName, w, h)
                WindowClearAnchors(wName)
                WindowAddAnchor(wName, "center", WindowGetParent(wName), "center", 0, 0)
                if LabelSetTextAlign then LabelSetTextAlign(wName, "center") end

                -- Keep animation offsets at 0; holder offset drives position.
                self.m_AnimationData.start.x   = 0
                self.m_AnimationData.start.y   = 0
                self.m_AnimationData.current.x = 0
                self.m_AnimationData.current.y = 0
                self.m_AnimationData.target.x  = 0
                self.m_AnimationData.target.y  = 0

                -- Holder visuals: pink bounds + blue center marker.
                if self.m_FlashHolderName then
                    local holderBg = self.m_FlashHolderName .. "DebugHolderBounds"
                    if not DoesWindowExist(holderBg) then
                        CreateWindowFromTemplate(holderBg, "EA_FullResizeImage_WhiteTransparent", self.m_FlashHolderName)
                        WindowSetAlpha(holderBg, 0.20)
                        WindowSetTintColor(holderBg, 255, 0, 200)
                        WindowClearAnchors(holderBg)
                    end
                    WindowSetDimensions(holderBg, w, h)
                    WindowSetOffsetFromParent(holderBg, -w / 2, -h / 2)

                    local holderCenter = self.m_FlashHolderName .. "DebugHolderCenter"
                    if not DoesWindowExist(holderCenter) then
                        CreateWindowFromTemplate(holderCenter, "EA_FullResizeImage_WhiteTransparent", self.m_FlashHolderName)
                        WindowSetDimensions(holderCenter, 6, 6)
                        WindowSetAlpha(holderCenter, 0.9)
                        WindowSetTintColor(holderCenter, 0, 120, 255)
                        WindowSetOffsetFromParent(holderCenter, -3, -3)
                    end
                end
            end

            if WindowSetScale then WindowSetScale(wName, self.m_CritStartScale) end
            WindowSetRelativeScale(wName, self.m_CritStartScale)
            if not (self.m_AnimationData and self.m_AnimationData.flashHolderMode) then
                WindowSetOffsetFromParent(self:GetName(), self.m_AnimationData.start.x, self.m_AnimationData.start.y)
            else
                if WindowUtils and WindowUtils.ForceProcessAnchors then WindowUtils.ForceProcessAnchors(wName) end
            end
            -- 3) Cyan label bounds (always for flash holder mode).
            if self.m_AnimationData and self.m_AnimationData.flashHolderMode and self.m_FlashHolderName then
                local labelBg = self.m_FlashHolderName .. "DebugLabelBounds"
                if not DoesWindowExist(labelBg) then
                    CreateWindowFromTemplate(labelBg, "EA_FullResizeImage_WhiteTransparent", self.m_FlashHolderName)
                    WindowSetAlpha(labelBg, 0.25)
                    WindowSetTintColor(labelBg, 0, 200, 255)
                    WindowClearAnchors(labelBg)
                    WindowAddAnchor(labelBg, "topleft", wName, "topleft", 0, 0)
                    WindowAddAnchor(labelBg, "bottomright", wName, "bottomright", 0, 0)
                end
            end
        end
    else
        LabelSetFont(wName, SctLabelFontName(), WindowUtils.FONT_DEFAULT_TEXT_LINESPACING)
        if WindowSetScale then WindowSetScale(wName, scale) end
        WindowSetRelativeScale(wName, scale)
    end

    local t = LabelGetText(wName)
    if t then LabelSetText(wName, t) end
    if WindowUtils and WindowUtils.ForceProcessAnchors then WindowUtils.ForceProcessAnchors(wName) end

    -- Resolve color: custom RGB picker > preset index > engine default
    local customRGB, colorIdx
    if isIncoming then
        colorIdx  = sct.incoming  and sct.incoming.color  and sct.incoming.color[key]           or 1
        customRGB = sct.customColor and sct.customColor.incoming and sct.customColor.incoming[key]
    else
        colorIdx  = sct.outgoing  and sct.outgoing.color  and sct.outgoing.color[key]           or 1
        customRGB = sct.customColor and sct.customColor.outgoing and sct.customColor.outgoing[key]
    end
    local tr, tg, tb = color.r, color.g, color.b
    if customRGB and customRGB[1] then
        tr, tg, tb = customRGB[1], customRGB[2], customRGB[3]
    elseif colorIdx and colorIdx > 1 then
        local opt = CustomUI.SCT.COLOR_OPTIONS[colorIdx]
        if opt and opt.rgb then tr, tg, tb = opt.rgb[1], opt.rgb[2], opt.rgb[3] end
    end
    self.m_TextTargetColorR, self.m_TextTargetColorG, self.m_TextTargetColorB = tr, tg, tb
    LabelSetTextColor(self:GetName(), tr, tg, tb)
    WindowSetFontAlpha(self:GetName(), 1.0)
end

function EA_System_EventEntry:IsOutOfStartingBox()
    return (self.m_AnimationData.start.y - self.m_AnimationData.current.y) > MINIMUM_EVENT_SPACING
end

----------------------------------------------------------------
-- EA_System_PointGainEntry — one floating point-gain label
----------------------------------------------------------------

EA_System_PointGainEntry = Frame:Subclass("EA_Window_EventTextLabel")

function EA_System_PointGainEntry:Create(windowName, parentWindow, animationData)
    local eventFrame = self:CreateFromTemplate(windowName, parentWindow)
    if eventFrame ~= nil then
        eventFrame.m_LifeSpan      = 0
        eventFrame.m_AnimationData = {
            start              = { x = animationData.start.x,  y = animationData.start.y  },
            target             = { x = animationData.target.x, y = animationData.target.y },
            current            = { x = animationData.start.x,  y = animationData.start.y  },
            maximumDisplayTime = animationData.maximumDisplayTime,
        }
    end
    WindowSetOffsetFromParent(windowName, animationData.start.x, animationData.start.y)
    return eventFrame
end

function EA_System_PointGainEntry:Update(elapsedTime, simulationSpeed)
    local simulationTime = elapsedTime * simulationSpeed
    local animationStep  = simulationTime / self.m_AnimationData.maximumDisplayTime
    self.m_AnimationData.current.x = self.m_AnimationData.current.x + (self.m_AnimationData.target.x - self.m_AnimationData.start.x) * animationStep
    self.m_AnimationData.current.y = self.m_AnimationData.current.y + (self.m_AnimationData.target.y - self.m_AnimationData.start.y) * animationStep
    WindowSetOffsetFromParent(self:GetName(), self.m_AnimationData.current.x, self.m_AnimationData.current.y)
    self.m_LifeSpan = self.m_LifeSpan + simulationTime
    return self.m_LifeSpan
end

function EA_System_PointGainEntry:SetupText(hitTargetObjectNumber, pointAmount, pointType)
    local text, color
    if pointType == XP_GAIN then
        text  = GetFormatStringFromTable("CombatEvents", StringTables.CombatEvents.LABEL_XP_POINT_GAIN,       { pointAmount })
        color = DefaultColor.COLOR_EXPERIENCE_GAIN
    elseif pointType == RENOWN_GAIN then
        text  = GetFormatStringFromTable("CombatEvents", StringTables.CombatEvents.LABEL_RENOWN_POINT_GAIN,    { pointAmount })
        color = DefaultColor.COLOR_RENOWN_GAIN
    elseif pointType == INFLUENCE_GAIN then
        text  = GetFormatStringFromTable("CombatEvents", StringTables.CombatEvents.LABEL_INFLUENCE_POINT_GAIN, { pointAmount })
        color = DefaultColor.COLOR_INFLUENCE_GAIN
    else
        text  = L"+" .. pointAmount
        color = { r = 255, g = 255, b = 255 }
    end

    local wName = self:GetName()
    LabelSetText(wName, text)
    LabelSetFont(wName, SctLabelFontName(), WindowUtils.FONT_DEFAULT_TEXT_LINESPACING)

    if not CustomUI.SCT.m_active then
        if WindowSetScale then WindowSetScale(wName, 1.0) end
        WindowSetRelativeScale(wName, 1.0)
        LabelSetTextColor(wName, color.r, color.g, color.b)
        WindowSetFontAlpha(wName, 1.0)
        return
    end

    local sct   = CustomUI.SCT.GetSettings()
    local key   = CustomUI.SCT.KeyForPointType(pointType)
    self.m_PointTypeKey = key
    local scale = (sct.outgoing and sct.outgoing.size and sct.outgoing.size[key]) or 1.0

    if WindowSetScale then WindowSetScale(wName, scale) end
    WindowSetRelativeScale(wName, scale)
    local t = LabelGetText(wName)
    if t then LabelSetText(wName, t) end
    if WindowUtils and WindowUtils.ForceProcessAnchors then WindowUtils.ForceProcessAnchors(wName) end

    local customRGB = sct.customColor and sct.customColor.outgoing and sct.customColor.outgoing[key]
    local colorIdx  = sct.outgoing and sct.outgoing.color and sct.outgoing.color[key] or 1
    if customRGB and customRGB[1] then
        LabelSetTextColor(wName, customRGB[1], customRGB[2], customRGB[3])
    elseif colorIdx and colorIdx > 1 then
        local opt = CustomUI.SCT.COLOR_OPTIONS[colorIdx]
        if opt and opt.rgb then
            LabelSetTextColor(wName, opt.rgb[1], opt.rgb[2], opt.rgb[3])
        else
            LabelSetTextColor(wName, color.r, color.g, color.b)
        end
    else
        LabelSetTextColor(wName, color.r, color.g, color.b)
    end
    WindowSetFontAlpha(wName, 1.0)
end

function EA_System_PointGainEntry:IsOutOfStartingBox()
    return (self.m_AnimationData.start.y - self.m_AnimationData.current.y) > MINIMUM_EVENT_SPACING
end

----------------------------------------------------------------
-- EA_System_EventTracker — per-target event stream
----------------------------------------------------------------

EA_System_EventTracker = {}
EA_System_EventTracker.__index = EA_System_EventTracker

function EA_System_EventTracker:Create(anchorWindowName, targetObjectNumber, opts)
    local isPlayerTracker = (targetObjectNumber == GameData.Player.worldObjNum)
    local newTracker = {
        m_DisplayedEvents    = Queue:Create(),
        m_PendingEvents      = Queue:Create(),
        m_TargetObject       = targetObjectNumber,
        m_Anchor             = anchorWindowName,
        m_MinimumScrollSpeed = 1,
        m_MaximumScrollSpeed = 20,
        m_CurrentScrollSpeed = 1,
        m_ScrollAcceleration = 0.1,
        m_AttachHeight       = isPlayerTracker and 0.3 or 0.8,
        m_IsCritTracker      = (opts and opts.isCrit) and true or false,
        m_CritLaneOffsetX    = (opts and opts.critLaneOffsetX) or 0,
        m_CritAnimMode       = (opts and opts.critAnimMode) or nil,
    }
    setmetatable(newTracker, self)
    -- Keep the anchor continuously attached to the world object.
    -- MoveWindowToWorldObject is a one-shot move and will then appear screen-relative.
    AttachWindowToWorldObject(anchorWindowName, targetObjectNumber)
    return newTracker
end

function EA_System_EventTracker:Update(elapsedTime)
    local clearForPendingDispatch = true

    for index = self.m_DisplayedEvents:Begin(), self.m_DisplayedEvents:End() do
        local lifeElapsed = self.m_DisplayedEvents[index]:Update(elapsedTime, self.m_CurrentScrollSpeed)
        if lifeElapsed > DEFAULT_FRIENDLY_EVENT_ANIMATION_PARAMETERS.maximumDisplayTime
           and index == self.m_DisplayedEvents:Begin()
        then
            self.m_DisplayedEvents:PopFront():Destroy()
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
                local eventData     = self.m_PendingEvents:PopFront()
                local animData      = self:InitializeAnimationData(eventType)
                animData.target.y   = animData.target.y - ((self.m_PendingEvents:End() - self.m_PendingEvents:Begin() + 1) * MINIMUM_EVENT_SPACING)
                local parentForLabel = self.m_Anchor
                local animForLabel   = animData

                -- Crits: use a holder window under the world anchor.
                -- Holder handles move-to-lane + float; label stays center-anchored and does visual animation.
                local holderName
                if self.m_IsCritTracker and (self.m_CritAnimMode == "pulse" or self.m_CritAnimMode == "shake" or self.m_CritAnimMode == "flash") then
                    holderName = self.m_Anchor .. "Holder" .. self.m_DisplayedEvents:End()
                    if not DoesWindowExist(holderName) then
                        CreateWindowFromTemplate(holderName, "EA_Window_EventTextAnchor", self.m_Anchor)
                    end
                    -- 1) World marker: fixed red square at anchor origin.
                    local worldPoint = self.m_Anchor .. "DebugWorldPoint"
                    if not DoesWindowExist(worldPoint) then
                        CreateWindowFromTemplate(worldPoint, "EA_FullResizeImage_RedTransparent", self.m_Anchor)
                        WindowSetDimensions(worldPoint, 6, 6)
                        WindowSetAlpha(worldPoint, 0.9)
                        WindowSetOffsetFromParent(worldPoint, -3, -3)
                    end

                    -- 2) Start holder at base position (no lane offset), then the entry anim moves it into the crit lane.
                    local laneX = self.m_CritLaneOffsetX or 0
                    local startX = animData.start.x - laneX
                    WindowSetOffsetFromParent(holderName, startX, animData.start.y)
                    parentForLabel = holderName

                    -- 3) Label: holder-local (no float). We'll finalize centered offsets in SetupText after measuring glyph extents.
                    -- Fade after: lane move + grow + anim + float.
                    local animDur = 0
                    if self.m_CritAnimMode == "pulse" then
                        animDur = CRIT_OSC_DURATION
                    elseif self.m_CritAnimMode == "shake" then
                        animDur = CRIT_SHAKE_DURATION
                    elseif self.m_CritAnimMode == "flash" then
                        animDur = CRIT_COLORFLASH_DURATION
                    end
                    local fadeDelay = CRIT_LANE_TRAVEL_DURATION + CRIT_GROW_DURATION + animDur + CRIT_FLOAT_DURATION
                    animData.fadeDelay = fadeDelay
                    animData.maximumDisplayTime = fadeDelay + animData.fadeDuration + 0.10

                    animForLabel = {
                        start              = { x = 0, y = 0 },
                        target             = { x = 0, y = 0 },
                        current            = { x = 0, y = 0 },
                        maximumDisplayTime = animData.maximumDisplayTime,
                        flashHolderMode    = true,
                    }
                end

                local frame         = EA_System_EventEntry:Create(newName, parentForLabel, animForLabel)
                if frame and frame.GetName then
                    if holderName then
                        frame.m_FlashHolderName = holderName
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
                    frame:SetupText(self.m_TargetObject, eventData.amount, eventData.type)
                    if frame.m_IsCritical and holderName and frame.m_CritAnimMode ~= "none" then
                        frame.m_CritPhase = "lanemove"
                        frame.m_CritPhaseElapsed = 0
                    end
                    WindowSetShowing(frame:GetName(), true)
                    WindowStartAlphaAnimation(frame:GetName(), Window.AnimationType.EASE_OUT,
                        1, 0, animData.fadeDuration, false, animData.fadeDelay, 0)
                    self.m_DisplayedEvents:PushBack(frame)
                end
            end
        else
            local newName = self.m_Anchor .. "PointGain" .. self.m_DisplayedEvents:End()
            if not DoesWindowExist(newName) then
                local eventData         = self.m_PendingEvents:PopFront()
                local animData          = self:InitializeAnimationData(eventType)
                local pendingSize       = self.m_PendingEvents:End() - self.m_PendingEvents:Begin() + 1
                local sign              = ((pendingSize % 2) == 0) and 1 or -1
                animData.target.x       = animData.target.x + sign * (pendingSize * (MINIMUM_EVENT_SPACING / 2))
                animData.target.y       = animData.target.y - (pendingSize * MINIMUM_EVENT_SPACING)
                local frame             = EA_System_PointGainEntry:Create(newName, self.m_Anchor, animData)
                if frame and frame.GetName then
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
        self.m_CurrentScrollSpeed = math.max(self.m_MinimumScrollSpeed, self.m_CurrentScrollSpeed - self.m_ScrollAcceleration)
    else
        self.m_CurrentScrollSpeed = math.min(self.m_MaximumScrollSpeed, self.m_CurrentScrollSpeed + self.m_ScrollAcceleration)
    end
end

function EA_System_EventTracker:InitializeAnimationData(displayType)
    local base
    if displayType == COMBAT_EVENT then
        base = (self.m_TargetObject == GameData.Player.worldObjNum)
               and DEFAULT_FRIENDLY_EVENT_ANIMATION_PARAMETERS
               or  DEFAULT_HOSTILE_EVENT_ANIMATION_PARAMETERS
    else
        base = DEFAULT_POINT_GAIN_EVENT_ANIMATION_PARAMETERS
    end
    local laneX = (self.m_IsCritTracker and self.m_CritLaneOffsetX) or 0

    return {
        start              = { x = base.start.x  + laneX, y = base.start.y  },
        target             = { x = base.target.x + laneX, y = base.target.y },
        current            = { x = base.start.x  + laneX, y = base.start.y  },
        maximumDisplayTime = base.maximumDisplayTime,
        fadeDelay          = base.fadeDelay,
        fadeDuration       = base.fadeDuration,
    }
end

function EA_System_EventTracker:AddEvent(eventData)
    self.m_PendingEvents:PushBack(eventData)
end

function EA_System_EventTracker:Destroy()
    while self.m_DisplayedEvents:Front() ~= nil do
        self.m_DisplayedEvents:PopFront():Destroy()
    end
    DetachWindowFromWorldObject(self.m_Anchor, self.m_TargetObject)
    DestroyWindow(self.m_Anchor)
end

----------------------------------------------------------------
-- EA_System_EventText — dispatcher / factory
----------------------------------------------------------------

-- Save stock functions before overwriting so Deactivate can restore them.
local _stock = {
    AddCombatEventText = EA_System_EventText and EA_System_EventText.AddCombatEventText,
    AddXpText          = EA_System_EventText and EA_System_EventText.AddXpText,
    AddRenownText      = EA_System_EventText and EA_System_EventText.AddRenownText,
    AddInfluenceText   = EA_System_EventText and EA_System_EventText.AddInfluenceText,
}

EA_System_EventText = EA_System_EventText or {}
EA_System_EventText.EventTrackers     = EA_System_EventText.EventTrackers     or {}
EA_System_EventText.EventTrackersCrit = EA_System_EventText.EventTrackersCrit or {}
EA_System_EventText.CritTrackerSeq    = EA_System_EventText.CritTrackerSeq    or 0


function CustomUI.SCT.Activate()
    local enabled = CustomUI.IsComponentEnabled and CustomUI.IsComponentEnabled("SCT")
    SCTLog("Activate called — m_active was: " .. tostring(CustomUI.SCT.m_active) .. " component enabled: " .. tostring(enabled))
    if not enabled then
        SCTLog("Activate — component is disabled, staying inactive")
        return
    end
    CustomUI.SCT.m_active = true
    pcall(function() CustomUI.SCT.GetSettings() end)
    SCTLog("Activate done")
end

function CustomUI.SCT.Deactivate()
    SCTLog("Deactivate called — m_active was: " .. tostring(CustomUI.SCT.m_active))
    CustomUI.SCT.m_active = false
    EA_System_EventText.EventTrackers     = EA_System_EventText.EventTrackers     or {}
    EA_System_EventText.EventTrackersCrit = EA_System_EventText.EventTrackersCrit or {}
    for _, tracker in pairs(EA_System_EventText.EventTrackers) do
        tracker:Destroy()
    end
    EA_System_EventText.EventTrackers = {}
    for id, tracker in pairs(EA_System_EventText.EventTrackersCrit) do
        tracker:Destroy()
        EA_System_EventText.EventTrackersCrit[id] = nil
    end
    SCTLog("Deactivate done")
end

function EA_System_EventText.Initialize()
    SCTLog("EA_System_EventText.Initialize called (CustomUI override)")
    RegisterEventHandler( SystemData.Events.WORLD_OBJ_COMBAT_EVENT,     "EA_System_EventText.AddCombatEventText" )
    RegisterEventHandler( SystemData.Events.WORLD_OBJ_XP_GAINED,        "EA_System_EventText.AddXpText"          )
    RegisterEventHandler( SystemData.Events.WORLD_OBJ_RENOWN_GAINED,    "EA_System_EventText.AddRenownText"      )
    RegisterEventHandler( SystemData.Events.WORLD_OBJ_INFLUENCE_GAINED, "EA_System_EventText.AddInfluenceText"   )
    RegisterEventHandler( SystemData.Events.LOADING_BEGIN,              "EA_System_EventText.BeginLoading"       )
    RegisterEventHandler( SystemData.Events.LOADING_END,                "EA_System_EventText.EndLoading"         )
    CustomUI.SCT.Activate()
end

function EA_System_EventText.Shutdown()
    CustomUI.SCT.Deactivate()
end

function EA_System_EventText.Update(timePassed)
    if EA_System_EventText.loading
       or (DoesWindowExist("LoadingWindow") and WindowGetShowing("LoadingWindow"))
    then
        return
    end
    for index, tracker in pairs(EA_System_EventText.EventTrackers) do
        tracker:Update(timePassed)
        if tracker.m_DisplayedEvents:Front() == nil
           and tracker.m_PendingEvents:Front() == nil
           and not GameData.Player.inCombat
        then
            tracker:Destroy()
            EA_System_EventText.EventTrackers[index] = nil
        end
    end
    for id, tracker in pairs(EA_System_EventText.EventTrackersCrit or {}) do
        tracker:Update(timePassed)
        if tracker.m_DisplayedEvents:Front() == nil and tracker.m_PendingEvents:Front() == nil then
            tracker:Destroy()
            EA_System_EventText.EventTrackersCrit[id] = nil
        end
    end
end

function EA_System_EventText.BeginLoading() EA_System_EventText.loading = true  end
function EA_System_EventText.EndLoading()   EA_System_EventText.loading = false end

function CustomUI.SCT._AddCombatEventText(hitTargetObjectNumber, hitAmount, textType)
    local isIncoming = (hitTargetObjectNumber == GameData.Player.worldObjNum)
    SCTLog("AddCombatEventText — active:" .. tostring(CustomUI.SCT.m_active)
        .. " type:" .. tostring(textType)
        .. " amount:" .. tostring(hitAmount)
        .. " dir:" .. (isIncoming and "incoming" or "outgoing")
        .. " target:" .. tostring(hitTargetObjectNumber))
    if not CustomUI.SCT.m_active then
        if _stock.AddCombatEventText then _stock.AddCombatEventText(hitTargetObjectNumber, hitAmount, textType) end
        return
    end
    local sct        = CustomUI.SCT.GetSettings()
    local filters    = (isIncoming and sct.incoming and sct.incoming.filters)
                    or (sct.outgoing and sct.outgoing.filters) or {}
    local isHitOrCrit = (textType == GameData.CombatEvent.HIT)
                     or (textType == GameData.CombatEvent.ABILITY_HIT)
                     or (textType == GameData.CombatEvent.CRITICAL)
                     or (textType == GameData.CombatEvent.ABILITY_CRITICAL)
    if isHitOrCrit and hitAmount > 0 then
        if filters.showHeal == false then
            SCTLog("AddCombatEventText — filtered (showHeal=false)")
            return
        end
    else
        if isIncoming then
            if not CustomUI.SCT.CombatTypeIncomingEnabled(textType) then
                SCTLog("AddCombatEventText — filtered (incoming type " .. tostring(textType) .. " disabled)")
                return
            end
        else
            if not CustomUI.SCT.CombatTypeOutgoingEnabled(textType) then
                SCTLog("AddCombatEventText — filtered (outgoing type " .. tostring(textType) .. " disabled)")
                return
            end
        end
    end
    SCTLog("AddCombatEventText — passing through isCrit:" .. tostring((textType == GameData.CombatEvent.CRITICAL) or (textType == GameData.CombatEvent.ABILITY_CRITICAL)))

    local eventData = { event = COMBAT_EVENT, amount = hitAmount, type = textType }
    local isCrit    = (textType == GameData.CombatEvent.CRITICAL) or (textType == GameData.CombatEvent.ABILITY_CRITICAL)

    if isCrit then
        EA_System_EventText.CritTrackerSeq = EA_System_EventText.CritTrackerSeq + 1
        local id         = EA_System_EventText.CritTrackerSeq
        local anchorName = "EA_System_EventTextAnchorCrit" .. hitTargetObjectNumber .. "_" .. id
        CreateWindowFromTemplate(anchorName, "EA_Window_EventTextAnchor", "EA_Window_EventTextContainer")
        local laneOffset = ((id % 2) == 0) and 80 or -80
        local critAnim = (sct and sct.critAnimation) or "shake"
        local tracker    = EA_System_EventTracker:Create(anchorName, hitTargetObjectNumber, {
            isCrit = true,
            critLaneOffsetX = laneOffset,
            critAnimMode = critAnim,
        })
        EA_System_EventText.EventTrackersCrit[id] = tracker
        tracker:AddEvent(eventData)
        return
    end

    if EA_System_EventText.EventTrackers[hitTargetObjectNumber] == nil then
        local anchorName = "EA_System_EventTextAnchor" .. hitTargetObjectNumber
        CreateWindowFromTemplate(anchorName, "EA_Window_EventTextAnchor", "EA_Window_EventTextContainer")
        EA_System_EventText.EventTrackers[hitTargetObjectNumber] = EA_System_EventTracker:Create(anchorName, hitTargetObjectNumber, nil)
    end
    EA_System_EventText.EventTrackers[hitTargetObjectNumber]:AddEvent(eventData)
end

function CustomUI.SCT._AddXpText(hitTargetObjectNumber, pointsGained)
    SCTLog("AddXpText — active:" .. tostring(CustomUI.SCT.m_active) .. " amount:" .. tostring(pointsGained))
    if not CustomUI.SCT.m_active then
        if _stock.AddXpText then _stock.AddXpText(hitTargetObjectNumber, pointsGained) end
        return
    end
    if (CustomUI.SCT.GetSettings().outgoing or {}).filters and
       CustomUI.SCT.GetSettings().outgoing.filters.showXP == false then
        SCTLog("AddXpText — filtered (showXP=false)")
        return
    end
    EA_System_EventText.AddPointGain(hitTargetObjectNumber, { event = POINT_GAIN, amount = pointsGained, type = XP_GAIN })
end

function CustomUI.SCT._AddRenownText(hitTargetObjectNumber, pointsGained)
    SCTLog("AddRenownText — active:" .. tostring(CustomUI.SCT.m_active) .. " amount:" .. tostring(pointsGained))
    if not CustomUI.SCT.m_active then
        if _stock.AddRenownText then _stock.AddRenownText(hitTargetObjectNumber, pointsGained) end
        return
    end
    if (CustomUI.SCT.GetSettings().outgoing or {}).filters and
       CustomUI.SCT.GetSettings().outgoing.filters.showRenown == false then
        SCTLog("AddRenownText — filtered (showRenown=false)")
        return
    end
    EA_System_EventText.AddPointGain(hitTargetObjectNumber, { event = POINT_GAIN, amount = pointsGained, type = RENOWN_GAIN })
end

function CustomUI.SCT._AddInfluenceText(hitTargetObjectNumber, pointsGained)
    SCTLog("AddInfluenceText — active:" .. tostring(CustomUI.SCT.m_active) .. " amount:" .. tostring(pointsGained))
    if not CustomUI.SCT.m_active then
        if _stock.AddInfluenceText then _stock.AddInfluenceText(hitTargetObjectNumber, pointsGained) end
        return
    end
    if (CustomUI.SCT.GetSettings().outgoing or {}).filters and
       CustomUI.SCT.GetSettings().outgoing.filters.showInfluence == false then
        SCTLog("AddInfluenceText — filtered (showInfluence=false)")
        return
    end
    EA_System_EventText.AddPointGain(hitTargetObjectNumber, { event = POINT_GAIN, amount = pointsGained, type = INFLUENCE_GAIN })
end

function EA_System_EventText.AddPointGain(hitTargetObjectNumber, pointGainData)
    if EA_System_EventText.EventTrackers[hitTargetObjectNumber] == nil then
        local anchorName = "EA_System_EventTextAnchor" .. hitTargetObjectNumber
        CreateWindowFromTemplate(anchorName, "EA_Window_EventTextAnchor", "EA_Window_EventTextContainer")
        EA_System_EventText.EventTrackers[hitTargetObjectNumber] = EA_System_EventTracker:Create(anchorName, hitTargetObjectNumber)
    end
    EA_System_EventText.EventTrackers[hitTargetObjectNumber]:AddEvent(pointGainData)
end

-- Install our wrappers as the permanent dispatchers. When m_active is false they
-- fall through to _stock, restoring unmodified stock SCT behaviour.
EA_System_EventText.AddCombatEventText = CustomUI.SCT._AddCombatEventText
EA_System_EventText.AddXpText          = CustomUI.SCT._AddXpText
EA_System_EventText.AddRenownText      = CustomUI.SCT._AddRenownText
EA_System_EventText.AddInfluenceText   = CustomUI.SCT._AddInfluenceText
