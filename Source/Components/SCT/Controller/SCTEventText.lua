----------------------------------------------------------------
-- CustomUI.SCT — Event text runtime (SCT; not a View/ .lua)
-- Responsibilities: CustomUI SCT event text handling (floating text, trackers, combat/point
--   pipelining) implemented by inheriting stock classes and swapping engine event-handler
--   registrations on enable/disable (no stock global replacement / no interception of stock APIs).
--   Lived in Controller/ because it is engine integration and a large system,
--   not a thin presentation layer. The controller adapter in SCTController.lua and settings
--   readers in SCTSettings.lua are the public coordination points. External tab UI: CustomUISettingsWindow.
-- Engine handler registration, OnUpdate, Activate/Deactivate: SCTHandlers.lua (after this file).
-- Requires SCTSettings.lua loaded first. Ported from easystem_eventtext.
----------------------------------------------------------------
if not CustomUI.SCT then CustomUI.SCT = {} end
CustomUI.SCT.m_sctLayoutDebug = false -- pink/cyan/blue/red SCT layout overlays (SetSctLayoutDebug / ToggleSctLayoutDebug)

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

-- Color-only flash (Flash crit mode), after grow
local CRIT_COLORFLASH_DURATION  = 0.75
-- Legacy: sin-based flash no longer used (kept for save compatibility if ever read).
local CRIT_COLORFLASH_FREQUENCY = 12

local CRIT_LANE_TRAVEL_DURATION = 0.15
local CRIT_FLOAT_DURATION       = 0.75

-- Crit main phase length (pre-float), used by tracker timing; same units as m_CritPhaseElapsed.
local function SctCritMainAnimDuration(sh, pu, cf)
    local d = 0
    if sh then d = math.max(d, CRIT_SHAKE_DURATION) end
    if pu then d = math.max(d, CRIT_OSC_DURATION) end
    if cf then d = math.max(d, CRIT_COLORFLASH_DURATION) end
    return d
end

-- p in [0,1] over the color-flash duration. Same total time, ten equal lerp segments:
-- (Base->White->Base->Black->Base) x2, then Base->White->Base.
-- m=i%4: 0=Base->White, 1=White->Base, 2=Base->Black, 3=Black->Base; segment i = 0..9.
local function SctCritColorFlashSequenceRGB(tr, tg, tb, p)
    if p < 0 then p = 0 elseif p > 1 then p = 1 end
    if p >= 1 then
        return math.floor(tr + 0.5), math.floor(tg + 0.5), math.floor(tb + 0.5)
    end
    local function lerp(a, b, u)
        return a + (b - a) * u
    end
    local t = p * 10
    local i = math.floor(t)
    if i > 9 then
        i = 9
    end
    local u = t - i
    local m = i % 4
    local r, g, b
    if m == 0 then
        r = lerp(tr, 255, u)
        g = lerp(tg, 255, u)
        b = lerp(tb, 255, u)
    elseif m == 1 then
        r = lerp(255, tr, u)
        g = lerp(255, tg, u)
        b = lerp(255, tb, u)
    elseif m == 2 then
        r = lerp(tr, 0, u)
        g = lerp(tg, 0, u)
        b = lerp(tb, 0, u)
    else
        r = lerp(0, tr, u)
        g = lerp(0, tg, u)
        b = lerp(0, tb, u)
    end
    return math.floor(r + 0.5), math.floor(g + 0.5), math.floor(b + 0.5)
end

----------------------------------------------------------------
-- Debug helpers (must be defined early; used by tracker Update)
----------------------------------------------------------------

local function SctLayoutDebugIsOn()
    return not not (CustomUI.SCT and CustomUI.SCT.m_sctLayoutDebug)
end

local function SCTLog(msg)
    local dbg = CustomUI.GetClientDebugLog()
    if type(dbg) == "function" then dbg("[SCT] " .. tostring(msg)) end
end

local function SctStopWindowAnimations(windowName)
    if not windowName or windowName == "" then
        return
    end
    if DoesWindowExist and not DoesWindowExist(windowName) then
        return
    end
    if WindowStopAlphaAnimation then
        pcall(WindowStopAlphaAnimation, windowName)
    end
    if WindowStopPositionAnimation then
        pcall(WindowStopPositionAnimation, windowName)
    end
    if WindowStopScaleAnimation then
        pcall(WindowStopScaleAnimation, windowName)
    end
end

local function SCTLogWindow(name, tag)
    local dbg = CustomUI.GetClientDebugLog()
    if type(dbg) ~= "function" or name == nil then return end
    local n = tostring(name)
    if DoesWindowExist and not DoesWindowExist(n) then
        dbg(string.format("[SCT] %s %s <no such window>", tostring(tag or ""), n))
        return
    end
    local okSP, sx, sy = pcall(WindowGetScreenPosition, n)
    local okOff, ox, oy = pcall(WindowGetOffsetFromParent, n)
    local okDim, w, h = pcall(WindowGetDimensions, n)
    local okSc, sc = pcall(WindowGetScale, n)
    dbg(string.format("[SCT] %s %s sp=(%s,%s) off=(%s,%s) dim=(%s,%s) scale=%s",
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

-- Per-world-object root under EA_Window_EventTextContainer. Must not Create if it already
-- exists: after /rel, failed EventTracker:Create, or a prior run that logged "already exists"
-- would leave a window but no CustomUI.SCT.Trackers[id], then a second AddCombatEvent would
-- error and can orphan Lua vs window manager state.
local function SctEnsureEventTextRootAnchor(anchorName)
    if not anchorName or anchorName == "" or not CreateWindowFromTemplate then
        return false
    end
    if DoesWindowExist and not DoesWindowExist("EA_Window_EventTextContainer") then
        return false
    end
    if DoesWindowExist and DoesWindowExist(anchorName) then
        return true
    end
    CreateWindowFromTemplate(anchorName, "EA_Window_EventTextAnchor", "EA_Window_EventTextContainer")
    return DoesWindowExist and DoesWindowExist(anchorName)
end

local function SctAnchorName(targetObjectNumber, isCrit)
    local suffix = tostring(targetObjectNumber or "unknown")
    if isCrit then
        return "CustomUI_SCT_EventTextAnchorCrit" .. suffix
    end
    return "CustomUI_SCT_EventTextAnchor" .. suffix
end

local function SctAbilityIconForAbilityId(abilityId)
    if not abilityId or abilityId == 0 or not GetAbilityData or not GetIconData then
        return nil
    end
    local ok, data = pcall(GetAbilityData, abilityId)
    if not ok or type(data) ~= "table" or not data.iconNum or data.iconNum <= 0 then
        return nil
    end
    local texture, x, y = GetIconData(data.iconNum)
    if texture == nil or texture == "" or texture == "icon000000" then
        return nil
    end
    return { texture = texture, x = x or 0, y = y or 0 }
end

local function SctEnsureAbilityIconWindow(iconWindowName, parentWindowName)
    if not iconWindowName or not parentWindowName or not CreateWindowFromTemplate then
        return false
    end
    if DoesWindowExist and DoesWindowExist(iconWindowName) then
        return true
    end
    CreateWindowFromTemplate(iconWindowName, "CustomUI_SCTAbilityIcon", parentWindowName)
    return DoesWindowExist and DoesWindowExist(iconWindowName)
end

local function SctDestroyAbilityIcon(frame)
    if not frame or not frame.m_AbilityIconWindow then
        return
    end
    SctStopWindowAnimations(frame.m_AbilityIconWindow)
    if DestroyWindow and DoesWindowExist and DoesWindowExist(frame.m_AbilityIconWindow) then
        DestroyWindow(frame.m_AbilityIconWindow)
    end
    frame.m_AbilityIconWindow = nil
end

local function SctApplyAbilityIconLayout(frame, wName, iconInfo)
    if not frame or not wName or not iconInfo then
        SctDestroyAbilityIcon(frame)
        return
    end
    -- Labels cannot host child windows in this client; parent the icon to the label's parent
    -- (anchor or crit holder) and anchor to the label so it tracks motion/scale with the text.
    local iconWin = wName .. "AbilityIcon"
    local parentWin = nil
    if WindowGetParent and DoesWindowExist and DoesWindowExist(wName) then
        local okP, p = pcall(WindowGetParent, wName)
        if okP then parentWin = p end
    end
    if not parentWin or parentWin == "" or not DoesWindowExist or not DoesWindowExist(parentWin) then
        frame.m_AbilityIconWindow = nil
        return
    end
    if not SctEnsureAbilityIconWindow(iconWin, parentWin) then
        frame.m_AbilityIconWindow = nil
        return
    end
    if DoesWindowExist and not DoesWindowExist(iconWin .. "Icon") then
        frame.m_AbilityIconWindow = nil
        return
    end
    frame.m_AbilityIconWindow = iconWin

    local textH = frame.m_TextBaseH or 24
    local size = math.floor(math.max(12, textH))
    local gap = math.floor(math.max(3, textH * 0.25))

    WindowSetDimensions(iconWin, size, size)
    WindowClearAnchors(iconWin)
    if WindowAddAnchor and DoesWindowExist(wName) then
        WindowAddAnchor(iconWin, "topleft", wName, "topright", gap, 0)
    else
        WindowSetOffsetFromParent(iconWin, (frame.m_TextBaseW or 80) + gap, 0)
    end
    if WindowUtils and WindowUtils.ForceProcessAnchors then
        WindowUtils.ForceProcessAnchors(iconWin)
    end
    DynamicImageSetTexture(iconWin .. "Icon", iconInfo.texture, iconInfo.x, iconInfo.y)
    DynamicImageSetTextureDimensions(iconWin .. "Icon", 64, 64)
    WindowSetShowing(iconWin, true)
end

----------------------------------------------------------------
-- CustomUI.SCT.EventEntry — one floating combat text label
-- Inherits from stock `EA_System_EventEntry` (no stock replacement).
----------------------------------------------------------------

-- Inherit stock classes; do not replace stock globals.
local StockEventEntry = EA_System_EventEntry
local StockPointGainEntry = EA_System_PointGainEntry
local StockEventTracker = EA_System_EventTracker

if not CustomUI.SCT then CustomUI.SCT = {} end

-- IMPORTANT: the Subclass argument is the XML template name used by CreateFromTemplate().
-- Stock `EA_Window_EventTextLabel` sets ignoreFormattingTags=true (no <icon#> etc.). We use
-- `CustomUI_Window_EventTextLabel` (see CustomUI_EventTextLabel.xml) with formatting enabled.
CustomUI.SCT.EventEntry = (StockEventEntry or Frame):Subclass("CustomUI_Window_EventTextLabel")

function CustomUI.SCT.EventEntry:Create(windowName, parentWindow, animationData)
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
    if DoesWindowExist and not DoesWindowExist(windowName) then
        return nil
    end
    -- flashHolderMode: parent holds start→target motion; label is center-anchored at (0,0) on parent.
    if animationData.flashHolderMode then
        WindowSetOffsetFromParent(windowName, 0, 0)
    else
        WindowSetOffsetFromParent(windowName, animationData.start.x, animationData.start.y)
    end
    return eventFrame
end

function CustomUI.SCT.EventEntry:Update(elapsedTime, simulationSpeed)
    local w0 = self.GetName and self:GetName()
    if w0 and DoesWindowExist and not DoesWindowExist(w0) then
        return (DEFAULT_FRIENDLY_EVENT_ANIMATION_PARAMETERS.maximumDisplayTime) + 1
    end
    if self.m_FlashHolderName and DoesWindowExist and not DoesWindowExist(self.m_FlashHolderName) then
        return (DEFAULT_FRIENDLY_EVENT_ANIMATION_PARAMETERS.maximumDisplayTime) + 1
    end
    if not self.m_AnimationData then
        return (DEFAULT_FRIENDLY_EVENT_ANIMATION_PARAMETERS.maximumDisplayTime) + 1
    end
    local maxDisp = self.m_AnimationData.maximumDisplayTime
    if (not maxDisp) or (maxDisp <= 0) then
        maxDisp = DEFAULT_FRIENDLY_EVENT_ANIMATION_PARAMETERS.maximumDisplayTime
        self.m_AnimationData.maximumDisplayTime = maxDisp
    end
    local simulationTime = elapsedTime * simulationSpeed
    local animationStep  = simulationTime / maxDisp

    -- Critical two-phase impact: grow → shake → float
    if self.m_IsCritical and self.m_CritPhase ~= nil then
        -- Crit animation speed is fixed at 1.0; only size/visuals are configurable.
        self.m_CritPhaseElapsed = (self.m_CritPhaseElapsed or 0) + simulationTime
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
                local sh  = self.m_CritWantsShake
                local pu  = self.m_CritWantsPulse
                local cf  = self.m_CritWantsColorFlash
                if sh and cf and not pu then
                    self.m_CritPhase = "shake_color"
                elseif pu and cf and not sh then
                    self.m_CritPhase = "pulse_color"
                    self.m_CritPulseColorOscDone = false
                elseif sh then
                    self.m_CritPhase = "shake"
                elseif pu then
                    self.m_CritPhase = "flashosc"
                elseif cf then
                    self.m_CritPhase = "colorflash"
                else
                    self.m_CritPhase = "float"
                end
            end
            self.m_LifeSpan = self.m_LifeSpan + simulationTime
            return self.m_LifeSpan

        elseif self.m_CritPhase == "shake_color" then
            local shakeDur = self.m_CritShakeDuration or CRIT_SHAKE_DURATION
            local colorDur = self.m_CritColorFlashDuration or CRIT_COLORFLASH_DURATION
            local D = math.max(shakeDur, colorDur)
            local e = self.m_CritPhaseElapsed
            local endScale = self.m_CritEndScale or 1.0
            if WindowSetScale then WindowSetScale(wName, endScale) end
            WindowSetRelativeScale(wName, endScale)
            if e <= shakeDur then
                local ts = shakeDur > 0 and math.min(1, e / shakeDur) or 0
                local amp  = (self.m_CritShakeAmplitude or CRIT_SHAKE_AMPLITUDE) * (1 - ts)
                local freq = self.m_CritShakeFrequency or CRIT_SHAKE_FREQUENCY
                local dx = amp * math.sin(2 * math.pi * freq * e)
                local dy = (amp * (self.m_CritShakeVerticalScale or CRIT_SHAKE_VERTICAL_SCALE)) * math.cos(2 * math.pi * freq * e)
                if self.m_AnimationData and self.m_AnimationData.flashHolderMode and self.m_FlashHolderName then
                    local bx = self.m_FlashHolderBaseX or 0
                    local by = self.m_FlashHolderBaseY or 0
                    WindowSetOffsetFromParent(self.m_FlashHolderName, bx + dx, by + dy)
                    if WindowUtils and WindowUtils.ForceProcessAnchors then WindowUtils.ForceProcessAnchors(wName) end
                else
                    WindowSetOffsetFromParent(self:GetName(), self.m_AnimationData.start.x + dx, self.m_AnimationData.start.y + dy)
                end
            else
                if self.m_AnimationData and self.m_AnimationData.flashHolderMode and self.m_FlashHolderName then
                    local bx = self.m_FlashHolderBaseX or 0
                    local by = self.m_FlashHolderBaseY or 0
                    WindowSetOffsetFromParent(self.m_FlashHolderName, bx, by)
                    if WindowUtils and WindowUtils.ForceProcessAnchors then WindowUtils.ForceProcessAnchors(wName) end
                else
                    WindowSetOffsetFromParent(self:GetName(), self.m_AnimationData.start.x, self.m_AnimationData.start.y)
                end
            end
            local tr, tg, tb = self.m_TextTargetColorR or 255, self.m_TextTargetColorG or 255, self.m_TextTargetColorB or 255
            if e <= colorDur then
                local tcol = colorDur > 0 and math.min(1, e / colorDur) or 0
                local cr, cg, cb = SctCritColorFlashSequenceRGB(tr, tg, tb, tcol)
                LabelSetTextColor(self:GetName(), cr, cg, cb)
            else
                LabelSetTextColor(self:GetName(), tr, tg, tb)
            end
            if e >= D then
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

        elseif self.m_CritPhase == "pulse_color" then
            local oscDur = self.m_CritOscDuration or CRIT_OSC_DURATION
            local colorDur = self.m_CritColorFlashDuration or CRIT_COLORFLASH_DURATION
            local D = math.max(oscDur, colorDur)
            local e = self.m_CritPhaseElapsed
            local endScale = self.m_CritEndScale or 1.0
            local startX = self.m_AnimationData.start.x
            local startY = self.m_AnimationData.start.y
            local tr, tg, tb = self.m_TextTargetColorR or 255, self.m_TextTargetColorG or 255, self.m_TextTargetColorB or 255
            if e < oscDur then
                local t = oscDur > 0 and math.min(1, e / oscDur) or 0
                if self.m_CritFlashBaseW == nil then
                    if WindowSetScale then WindowSetScale(wName, endScale) end
                    WindowSetRelativeScale(wName, endScale)
                    WindowSetOffsetFromParent(self:GetName(), startX, startY)
                    local ok, dw, dh = pcall(LabelGetTextDimensions, wName)
                    if not (ok and dw and dh and dw > 0 and dh > 0) then
                        ok, dw, dh = pcall(WindowGetDimensions, wName)
                    end
                    self.m_CritFlashBaseW = (ok and dw and dw > 0) and dw or 80
                    self.m_CritFlashBaseH = (ok and dh and dh > 0) and dh or 24
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
                local osc = math.sin(2 * math.pi * CRIT_OSC_FREQUENCY * e)
                local delta = CRIT_OSC_SCALE_DELTA * env
                local s = endScale * (1 + delta * osc)
                if WindowSetScale then WindowSetScale(wName, s) end
                WindowSetRelativeScale(wName, s)
                if self.m_AnimationData and self.m_AnimationData.flashHolderMode then
                    if WindowUtils and WindowUtils.ForceProcessAnchors then WindowUtils.ForceProcessAnchors(wName) end
                else
                    local ox, oy = CritFlashOffsetForCenterPivot(startX, startY, self.m_CritFlashBaseW, self.m_CritFlashBaseH, endScale, s)
                    WindowSetOffsetFromParent(self:GetName(), ox, oy)
                end
                if (not (self.m_AnimationData and self.m_AnimationData.stationaryCritFlash))
                   and self.m_CritFlashCenterScreenX ~= nil and self.m_CritFlashCenterScreenY ~= nil
                then
                    local okSP, sx, sy = pcall(WindowGetScreenPosition, wName)
                    if okSP and sx and sy then
                        local uiScale = (InterfaceCore and InterfaceCore.GetScale and InterfaceCore.GetScale()) or 1
                        local curCX = sx + (self.m_CritFlashBaseW * s * uiScale) / 2
                        local curCY = sy + (self.m_CritFlashBaseH * s * uiScale) / 2
                        local dx = (self.m_CritFlashCenterScreenX - curCX)
                        local dyy = (self.m_CritFlashCenterScreenY - curCY)
                        if math.abs(dx) > 0.1 or math.abs(dyy) > 0.1 then
                            local okOff, px, py = pcall(WindowGetOffsetFromParent, wName)
                            if okOff and px and py and uiScale ~= 0 then
                                WindowSetOffsetFromParent(self:GetName(), px + dx / uiScale, py + dyy / uiScale)
                            end
                        end
                    end
                end
            else
                if not self.m_CritPulseColorOscDone then
                    self.m_CritFlashBaseW = nil
                    self.m_CritFlashBaseH = nil
                    self.m_CritFlashCenterScreenX = nil
                    self.m_CritFlashCenterScreenY = nil
                end
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
                self.m_CritPulseColorOscDone = true
            end
            if e <= colorDur then
                local tcol = colorDur > 0 and math.min(1, e / colorDur) or 0
                local cr, cg, cb = SctCritColorFlashSequenceRGB(tr, tg, tb, tcol)
                LabelSetTextColor(self:GetName(), cr, cg, cb)
            else
                LabelSetTextColor(self:GetName(), tr, tg, tb)
            end
            if e >= D then
                self.m_CritPhase = "float"
                self.m_CritPhaseElapsed = 0
                self.m_CritFlashBaseW = nil
                self.m_CritFlashBaseH = nil
                self.m_CritFlashCenterScreenX = nil
                self.m_CritFlashCenterScreenY = nil
                self.m_CritPulseColorOscDone = false
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
            local cr, cg, cb = SctCritColorFlashSequenceRGB(tr, tg, tb, t)
            LabelSetTextColor(self:GetName(), cr, cg, cb)

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
                if self.m_CritFloatRefY == nil then
                    self.m_CritFloatRefY = by
                end
                local hy = by + dy * ease
                self.m_CritFloatCurY = hy
                WindowSetOffsetFromParent(self.m_FlashHolderName, bx, hy)
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

    -- Holder crits: after crit animation phases, label does not use generic drift (motion was on the holder / phases).
    if self.m_AnimationData
       and self.m_AnimationData.flashHolderMode
       and self.m_FlashHolderName
       and self.m_IsCritical
    then
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

function CustomUI.SCT.EventEntry:SetupText(hitTargetObjectNumber, hitAmount, textType, abilityId)
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

    local wName = self:GetName()

    local useAbilityIcon = false
    local abilityIconInfo = nil
    if CustomUI.SCT and CustomUI.SCT.m_active then
        local sct0 = CustomUI.SCT.GetSettings()
        if sct0 and sct0.showAbilityIcon == true then
            abilityIconInfo = SctAbilityIconForAbilityId(abilityId)
            useAbilityIcon = abilityIconInfo ~= nil
        end
    end

    -- Do not use <icon#> markup here: animated labels can leave the engine-generated icon behind.
    -- SCT renders the ability icon as an explicit child window controlled by this frame.
    LabelSetFont(wName, SctLabelFontName(), WindowUtils.FONT_DEFAULT_TEXT_LINESPACING)
    LabelSetText(wName, text)
    if useAbilityIcon and LabelSetTextAlign then
        LabelSetTextAlign(wName, "left")
    end

    local okDim, dw, dh = pcall(LabelGetTextDimensions, wName)
    self.m_TextBaseW = (okDim and dw and dw > 0) and dw or (self.m_TextBaseW or 80)
    self.m_TextBaseH = (okDim and dh and dh > 0) and dh or (self.m_TextBaseH or 24)
    do
        -- Make the label window match measured ink bounds (+ pad). When ability icons are enabled,
        -- include the controlled child icon in the same moving window bounds.
        local h = self.m_TextBaseH or 24
        local padW = math.floor(math.max(2, h * 0.15))
        local padH = 2
        if useAbilityIcon then
            padW = math.floor(math.max(6, h * 0.4)) + h + math.floor(math.max(3, h * 0.25))
            padH = math.floor(math.max(3, h * 0.12))
        end
        WindowSetDimensions(wName, (self.m_TextBaseW or 80) + padW, (self.m_TextBaseH or 24) + padH)
    end
    SctApplyAbilityIconLayout(self, wName, abilityIconInfo)

    if not CustomUI.SCT.m_active then
        -- SCT disabled: plain float, no crit animation, no custom scale or color
        self.m_IsCritical = false
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
    if isCrit and sct and type(sct.critSizeScale) == "number" then
        scale = scale * sct.critSizeScale
    end

    if isCrit then
        local sh, pu, cf = false, false, false
        if CustomUI.SCT and CustomUI.SCT.GetCritAnimFlags then
            sh, pu, cf = CustomUI.SCT.GetCritAnimFlags()
        end
        self.m_CritWantsShake = sh
        self.m_CritWantsPulse = pu
        self.m_CritWantsColorFlash = cf
        local anyAnim = sh or pu or cf
        local anySizeAnim = sh or pu

        LabelSetFont(wName, SctLabelFontName(), WindowUtils.FONT_DEFAULT_TEXT_LINESPACING)
        if not anyAnim then
            -- All crit toggles off: just scale + default drift.
            self.m_CritPhase = nil
            if WindowSetScale then WindowSetScale(wName, scale) end
            WindowSetRelativeScale(wName, scale)
            WindowSetOffsetFromParent(self:GetName(), self.m_AnimationData.start.x, self.m_AnimationData.start.y)
        else
            -- At least one of Shake, Pulse, Flash: grow (size grow only for Shake or Pulse) then main phase(s), then float.
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
            self.m_CritStartScale         = anySizeAnim and (scale / CRIT_FONT_VISUAL_RATIO) or scale
            self.m_CritEndScale           = scale
            self.m_CritFlashBaseW         = nil
            self.m_CritFlashBaseH         = nil
            if self.m_AnimationData and self.m_AnimationData.flashHolderMode and anyAnim then
                local ok, tw, th = pcall(LabelGetTextDimensions, wName)
                if ok and tw and th and tw > 0 and th > 0 then
                    self.m_CritFlashBaseW = tw
                    self.m_CritFlashBaseH = th
                end
                -- Holder mode (Pulse/Shake): strict center anchoring, no per-label offsets.
                local w = self.m_CritFlashBaseW or 80
                local h = self.m_CritFlashBaseH or 24
                if useAbilityIcon then
                    w = w + h + math.floor(math.max(3, h * 0.25))
                    h = h + math.floor(math.max(2, h * 0.15))
                end
                local parent = nil
                if WindowGetParent and DoesWindowExist and DoesWindowExist(wName) then
                    local okP, p = pcall(WindowGetParent, wName)
                    if okP then parent = p end
                end
                WindowSetDimensions(wName, w, h)
                WindowClearAnchors(wName)
                if parent and parent ~= "" and (not DoesWindowExist or DoesWindowExist(parent)) then
                    WindowAddAnchor(wName, "center", parent, "center", 0, 0)
                end
                if LabelSetTextAlign then
                    LabelSetTextAlign(wName, (useAbilityIcon and "left") or "center")
                end

                -- Keep animation offsets at 0; holder offset drives position.
                self.m_AnimationData.start.x   = 0
                self.m_AnimationData.start.y   = 0
                self.m_AnimationData.current.x = 0
                self.m_AnimationData.current.y = 0
                self.m_AnimationData.target.x  = 0
                self.m_AnimationData.target.y  = 0

                -- Holder visuals: pink bounds + blue center marker (opt-in: CustomUI.SCT.SetSctLayoutDebug / ToggleSctLayoutDebug).
                if SctLayoutDebugIsOn() and self.m_FlashHolderName then
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
            -- 3) Cyan label bounds (flash holder mode, opt-in layout debug).
            if SctLayoutDebugIsOn() and self.m_AnimationData and self.m_AnimationData.flashHolderMode and self.m_FlashHolderName then
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

    if useAbilityIcon then
        LabelSetFont(wName, SctLabelFontName(), WindowUtils.FONT_DEFAULT_TEXT_LINESPACING)
    end
    -- Re-setting the string after scale is only needed for plain text; icon rows already have a controlled child window.
    if not useAbilityIcon then
        local t = LabelGetText(wName)
        if t then LabelSetText(wName, t) end
    end
    if useAbilityIcon and LabelSetTextAlign then
        LabelSetTextAlign(wName, "left")
    end
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

function CustomUI.SCT.EventEntry:IsOutOfStartingBox()
    -- Stock behavior: compare configured drift start vs current.
    if self.m_FlashHolderName
       and self.m_CritFloatRefY ~= nil
       and self.m_CritFloatCurY ~= nil
    then
        return math.abs((self.m_CritFloatRefY or 0) - (self.m_CritFloatCurY or 0)) > MINIMUM_EVENT_SPACING
    end
    if not self.m_AnimationData or not self.m_AnimationData.start or not self.m_AnimationData.current then
        return true
    end
    return (self.m_AnimationData.start.y - self.m_AnimationData.current.y) > MINIMUM_EVENT_SPACING
end

----------------------------------------------------------------
-- CustomUI.SCT.PointGainEntry — one floating point-gain label
-- Inherits from stock `EA_System_PointGainEntry` (no stock replacement).
----------------------------------------------------------------

-- Same template requirement as EventEntry.
CustomUI.SCT.PointGainEntry = (StockPointGainEntry or Frame):Subclass("CustomUI_Window_EventTextLabel")

function CustomUI.SCT.PointGainEntry:Create(windowName, parentWindow, animationData)
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
    if DoesWindowExist and not DoesWindowExist(windowName) then
        return nil
    end
    WindowSetOffsetFromParent(windowName, animationData.start.x, animationData.start.y)
    return eventFrame
end

function CustomUI.SCT.PointGainEntry:Update(elapsedTime, simulationSpeed)
    local w0 = self.GetName and self:GetName()
    if w0 and DoesWindowExist and not DoesWindowExist(w0) then
        return (DEFAULT_FRIENDLY_EVENT_ANIMATION_PARAMETERS.maximumDisplayTime) + 1
    end
    if not self.m_AnimationData then
        return (DEFAULT_FRIENDLY_EVENT_ANIMATION_PARAMETERS.maximumDisplayTime) + 1
    end
    local maxDisp = self.m_AnimationData.maximumDisplayTime
    if (not maxDisp) or (maxDisp <= 0) then
        maxDisp = DEFAULT_FRIENDLY_EVENT_ANIMATION_PARAMETERS.maximumDisplayTime
        self.m_AnimationData.maximumDisplayTime = maxDisp
    end
    local simulationTime = elapsedTime * simulationSpeed
    local animationStep  = simulationTime / maxDisp
    self.m_AnimationData.current.x = self.m_AnimationData.current.x + (self.m_AnimationData.target.x - self.m_AnimationData.start.x) * animationStep
    self.m_AnimationData.current.y = self.m_AnimationData.current.y + (self.m_AnimationData.target.y - self.m_AnimationData.start.y) * animationStep
    WindowSetOffsetFromParent(self:GetName(), self.m_AnimationData.current.x, self.m_AnimationData.current.y)
    self.m_LifeSpan = self.m_LifeSpan + simulationTime
    return self.m_LifeSpan
end

function CustomUI.SCT.PointGainEntry:SetupText(hitTargetObjectNumber, pointAmount, pointType)
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

function CustomUI.SCT.EventEntry:Destroy()
    if not DestroyWindow then
        return
    end
    local wName = self.GetName and self:GetName()
    SctDestroyAbilityIcon(self)
    SctStopWindowAnimations(wName)
    if self.m_FlashHolderName and DoesWindowExist and DoesWindowExist(self.m_FlashHolderName) then
        SctStopWindowAnimations(self.m_FlashHolderName)
        DestroyWindow(self.m_FlashHolderName)
        self.m_FlashHolderName = nil
        return
    end
    if wName and (not DoesWindowExist or DoesWindowExist(wName)) then
        DestroyWindow(wName)
    end
end

function CustomUI.SCT.PointGainEntry:IsOutOfStartingBox()
    return (self.m_AnimationData.start.y - self.m_AnimationData.current.y) > MINIMUM_EVENT_SPACING
end

function CustomUI.SCT.PointGainEntry:Destroy()
    if not DestroyWindow then
        return
    end
    local wName = self.GetName and self:GetName()
    SctStopWindowAnimations(wName)
    if wName and (not DoesWindowExist or DoesWindowExist(wName)) then
        DestroyWindow(wName)
    end
end

----------------------------------------------------------------
-- CustomUI.SCT.EventTracker — per-target event stream
-- Derived from stock `EA_System_EventTracker` (no stock replacement).
----------------------------------------------------------------

CustomUI.SCT.EventTracker = {}
CustomUI.SCT.EventTracker.__index = CustomUI.SCT.EventTracker
setmetatable(CustomUI.SCT.EventTracker, { __index = StockEventTracker })

function CustomUI.SCT.EventTracker:Create(anchorWindowName, targetObjectNumber, opts)
    if DoesWindowExist and not DoesWindowExist(anchorWindowName) then
        return nil
    end
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
        m_CritQueueSeq       = 0,
    }
    setmetatable(newTracker, self)
    -- Keep the anchor continuously attached to the world object.
    -- MoveWindowToWorldObject is a one-shot move and will then appear screen-relative.
    if AttachWindowToWorldObject then
        pcall(AttachWindowToWorldObject, anchorWindowName, targetObjectNumber)
    end
    return newTracker
end

function CustomUI.SCT.EventTracker:AddEvent(eventData)
    if self.m_IsCritTracker then
        self.m_CritQueueSeq = (self.m_CritQueueSeq or 0) + 1
        local n = self.m_CritQueueSeq
        eventData = eventData or {}
        eventData.critLaneOffsetX = ((n % 2) == 0) and 80 or -80
    end
    self.m_PendingEvents:PushBack(eventData)
end

function CustomUI.SCT.EventTracker:Update(elapsedTime)
    if self.m_Anchor and DoesWindowExist and not DoesWindowExist(self.m_Anchor) then
        self.m_DisplayedEvents = Queue:Create()
        self.m_PendingEvents = Queue:Create()
        return
    end

    local clearForPendingDispatch = true

    for index = self.m_DisplayedEvents:Begin(), self.m_DisplayedEvents:End() do
        local frame = self.m_DisplayedEvents[index]
        if frame == nil then
            break
        end
        local ok, lifeElapsed = pcall(function()
            return frame:Update(elapsedTime, self.m_CurrentScrollSpeed)
        end)
        if not ok then
            SCTLog("EventTracker frame:Update failed: " .. tostring(lifeElapsed))
            lifeElapsed = DEFAULT_FRIENDLY_EVENT_ANIMATION_PARAMETERS.maximumDisplayTime + 1
        end
        if lifeElapsed > DEFAULT_FRIENDLY_EVENT_ANIMATION_PARAMETERS.maximumDisplayTime
           and index == self.m_DisplayedEvents:Begin()
        then
            pcall(function()
                self.m_DisplayedEvents:PopFront():Destroy()
            end)
            clearForPendingDispatch = false
        elseif not ok then
            clearForPendingDispatch = false
        else
            local okOob, inStartZone = pcall(function()
                return not frame:IsOutOfStartingBox()
            end)
            if okOob and inStartZone then
                clearForPendingDispatch = false
            end
        end
    end

    if not self.m_PendingEvents:IsEmpty() and clearForPendingDispatch then
        local eventType = self.m_PendingEvents:Front().event

        if eventType == COMBAT_EVENT then
            local newName = self.m_Anchor .. "Event" .. self.m_DisplayedEvents:End()
            if not DoesWindowExist(newName) then
                local eventData     = self.m_PendingEvents:PopFront()
                if self.m_IsCritTracker then
                    self.m_CritLaneOffsetX = (eventData and eventData.critLaneOffsetX) or 0
                end
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
                    holderName = self.m_Anchor .. "Holder" .. self.m_DisplayedEvents:End()
                    if not DoesWindowExist(holderName) then
                        CreateWindowFromTemplate(holderName, "EA_Window_EventTextAnchor", self.m_Anchor)
                    end
                    if not DoesWindowExist(holderName) then
                        holderName = nil
                    end
                    -- 1) World marker: fixed red square at anchor origin (opt-in layout debug).
                    if SctLayoutDebugIsOn() then
                        local worldPoint = self.m_Anchor .. "DebugWorldPoint"
                        if not DoesWindowExist(worldPoint) then
                            CreateWindowFromTemplate(worldPoint, "EA_FullResizeImage_RedTransparent", self.m_Anchor)
                            WindowSetDimensions(worldPoint, 6, 6)
                            WindowSetAlpha(worldPoint, 0.9)
                            WindowSetOffsetFromParent(worldPoint, -3, -3)
                        end
                    end

                    -- 2) Start holder at base position (no lane offset), then the entry anim moves it into the crit lane.
                    local laneX = self.m_CritLaneOffsetX or 0
                    local startX = animData.start.x - laneX
                    if holderName then
                        WindowSetOffsetFromParent(holderName, startX, animData.start.y)
                        parentForLabel = holderName
                    end

                    -- 3) Label: holder-local (no float). We'll finalize centered offsets in SetupText after measuring glyph extents.
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
                    if frame.m_IsCritical and holderName
                       and (frame.m_CritWantsShake or frame.m_CritWantsPulse or frame.m_CritWantsColorFlash)
                    then
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
                local frame             = CustomUI.SCT.PointGainEntry:Create(newName, self.m_Anchor, animData)
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

    return {
        start              = { x = base.start.x  + laneX, y = base.start.y  },
        target             = { x = base.target.x + laneX, y = base.target.y },
        current            = { x = base.start.x  + laneX, y = base.start.y  },
        maximumDisplayTime = base.maximumDisplayTime,
        fadeDelay          = base.fadeDelay,
        fadeDuration       = base.fadeDuration,
    }
end

function CustomUI.SCT.EventTracker:Destroy()
    while self.m_DisplayedEvents:Front() ~= nil do
        pcall(function()
            self.m_DisplayedEvents:PopFront():Destroy()
        end)
    end
    if self.m_Anchor and DoesWindowExist and DoesWindowExist(self.m_Anchor) then
        SctStopWindowAnimations(self.m_Anchor)
        pcall(DetachWindowFromWorldObject, self.m_Anchor, self.m_TargetObject)
        pcall(DestroyWindow, self.m_Anchor)
    end
end

-- Exposed for SCTHandlers.lua (CustomUI.mod loads SCTEventText before SCTHandlers).
CustomUI.SCT._RuntimeForHandlers = {
    SCTLog                        = SCTLog,
    SctLayoutDebugIsOn            = SctLayoutDebugIsOn,
    SctAnchorName                 = SctAnchorName,
    SctEnsureEventTextRootAnchor  = SctEnsureEventTextRootAnchor,
}
