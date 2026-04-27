-- LEGACY (v2 SCT, 2026-04-25): replaced by SCTOverrides.lua. Safe to delete once
-- Step 5b verifies no remaining references. Do not extend or fix bugs in this file.
----------------------------------------------------------------
-- CustomUI.SCT — EventEntry / PointGainEntry (floating labels)
-- Requires SCTAnim.lua and SCTAnchors.lua loaded before this file.
----------------------------------------------------------------
if not CustomUI.SCT then CustomUI.SCT = {} end
-- Do not use `local X = assert(expr, msg)` here: some client Lua builds use a non-standard
-- assert that does not return its argument, leaving X nil while the check still passes.
local A = CustomUI.SCT._SctAnim
if not A then
    error("CustomUI SCT: load SCTAnim.lua before SCTEntry.lua (_SctAnim missing)")
end
local H = CustomUI.SCT._SctAnchors
if not H then
    error("CustomUI SCT: load SCTAnchors.lua before SCTEntry.lua (_SctAnchors missing)")
end
local DEFAULT_FRIENDLY_EVENT_ANIMATION_PARAMETERS = A.DEFAULT_FRIENDLY_EVENT_ANIMATION_PARAMETERS
local DEFAULT_HOSTILE_EVENT_ANIMATION_PARAMETERS = A.DEFAULT_HOSTILE_EVENT_ANIMATION_PARAMETERS
local DEFAULT_POINT_GAIN_EVENT_ANIMATION_PARAMETERS = A.DEFAULT_POINT_GAIN_EVENT_ANIMATION_PARAMETERS
local MINIMUM_EVENT_SPACING = A.MINIMUM_EVENT_SPACING
local CRIT_GROW_DURATION = A.CRIT_GROW_DURATION
local CRIT_SHAKE_DURATION = A.CRIT_SHAKE_DURATION
local CRIT_SHAKE_AMPLITUDE = A.CRIT_SHAKE_AMPLITUDE
local CRIT_SHAKE_FREQUENCY = A.CRIT_SHAKE_FREQUENCY
local CRIT_SHAKE_VERTICAL_SCALE = A.CRIT_SHAKE_VERTICAL_SCALE
local CRIT_FONT_VISUAL_RATIO = A.CRIT_FONT_VISUAL_RATIO
local CRIT_OSC_DURATION = A.CRIT_OSC_DURATION
local CRIT_OSC_FREQUENCY = A.CRIT_OSC_FREQUENCY
local CRIT_OSC_SCALE_DELTA = A.CRIT_OSC_SCALE_DELTA
local CRIT_COLORFLASH_DURATION = A.CRIT_COLORFLASH_DURATION
local CRIT_LANE_TRAVEL_DURATION = A.CRIT_LANE_TRAVEL_DURATION
local CRIT_FLOAT_DURATION = A.CRIT_FLOAT_DURATION
local ENTRY_FADE_DURATION = A.ENTRY_FADE_DURATION
local SctCritMainAnimDuration = A.SctCritMainAnimDuration
local SctCritColorFlashSequenceRGB = A.SctCritColorFlashSequenceRGB
local CritFlashOffsetForCenterPivot = A.CritFlashOffsetForCenterPivot
local CombatEventText = A.CombatEventText
local Effects = A.Effects
local COMBAT_EVENT = CustomUI.SCT.COMBAT_EVENT
local POINT_GAIN = CustomUI.SCT.POINT_GAIN
local XP_GAIN = CustomUI.SCT.XP_GAIN
local RENOWN_GAIN = CustomUI.SCT.RENOWN_GAIN
local INFLUENCE_GAIN = CustomUI.SCT.INFLUENCE_GAIN
local SctStopWindowAnimations = H.SctStopWindowAnimations
local SctForgetManagedFrame = H.SctForgetManagedFrame
local SctDestroyEventWindowByName = H.SctDestroyEventWindowByName
local SctForceProcessAnchors = H.SctForceProcessAnchors
local SctLabelFontName = H.SctLabelFontName
local SctAbilityIconForAbilityId = H.SctAbilityIconForAbilityId
local SctEnsureAbilityIconWindow = H.SctEnsureAbilityIconWindow
local SctDestroyAbilityIcon = H.SctDestroyAbilityIcon
local SctApplyAbilityIconLayout = H.SctApplyAbilityIconLayout
-- After WindowSetScale / WindowSetRelativeScale, ink size no longer matches a box measured at
-- 1.0 scale — refit to measured extents (+ padding) to avoid (CustomUI) "Text is cut off in Label" warnings.
local function SctRefitEventLabelAfterScale(self, wName, useAbilityIcon, abilityIconInfo)
    if not wName or wName == "" or not self then
        return
    end
    if not DoesWindowExist(wName) then
        return
    end
    local dw, dh = LabelGetTextDimensions(wName)
    self.m_TextBaseW = (dw and dw > 0) and dw or (self.m_TextBaseW or 80)
    self.m_TextBaseH = (dh and dh > 0) and dh or (self.m_TextBaseH or 24)
    local h = self.m_TextBaseH or 24
    local padW = math.floor(math.max(2, h * 0.15))
    local padH = 2
    if useAbilityIcon then
        padW = math.floor(math.max(6, h * 0.4)) + h + math.floor(math.max(3, h * 0.25))
        padH = math.floor(math.max(3, h * 0.12))
    end
    self.m_WindowW = (self.m_TextBaseW or 80) + padW
    WindowSetDimensions(wName, self.m_WindowW, (self.m_TextBaseH or 24) + padH)
    SctApplyAbilityIconLayout(self, wName, abilityIconInfo)
    SctForceProcessAnchors(wName)
end

-- Point-gain labels use the same template; they only need ink + small padding (no ability icon here).
local function SctRefitPointGainLabelAfterScale(self, wName)
    if not self or not wName or wName == "" then
        return
    end
    if not DoesWindowExist(wName) then
        return
    end
    local dw, dh = LabelGetTextDimensions(wName)
    if not dw or not dh or dw <= 0 or dh <= 0 then
        return
    end
    local padW = math.floor(math.max(2, dh * 0.15))
    local padH = 2
    self.m_TextBaseW = dw
    self.m_TextBaseH = dh
    self.m_WindowW = dw + padW
    WindowSetDimensions(wName, self.m_WindowW, dh + padH)
    SctForceProcessAnchors(wName)
end

----------------------------------------------------------------
-- CustomUI.SCT.EventEntry — one floating combat text label
-- Inherits from stock event-entry class (EASystem_EventText module; no stock replacement).
----------------------------------------------------------------

-- Inherit stock classes; do not replace stock globals (split _G keys so a narrow stock-prefix grep hits only handler strings).
local StockEventEntry = _G["EA_" .. "System_EventEntry"]
local StockPointGainEntry = _G["EA_" .. "System_PointGainEntry"]

-- IMPORTANT: the Subclass argument is the XML template name used by CreateFromTemplate().
-- Stock `EA_Window_EventTextLabel` sets ignoreFormattingTags=true (no <icon#> etc.). We use
-- `CustomUI_Window_EventTextLabel` (see CustomUI_EventTextLabel.xml) with formatting enabled.
CustomUI.SCT.EventEntry = (StockEventEntry or Frame):Subclass("CustomUI_Window_EventTextLabel")

function CustomUI.SCT.EventEntry:Create(windowName, parentWindow, animationData)
    local eventFrame = self:CreateFromTemplate(windowName, parentWindow)
    if eventFrame ~= nil then
        eventFrame:SetKnownParent(parentWindow)
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
    if not DoesWindowExist(windowName) then
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

function CustomUI.SCT.EventEntry:SetKnownParent(parentWindow)
    self.m_ParentWindow = parentWindow
end

function CustomUI.SCT.EventEntry:GetKnownParent()
    return self.m_ParentWindow
end

function CustomUI.SCT.EventEntry:Update(elapsedTime, simulationSpeed)
    local wName = self.m_Window or (self.GetName and self:GetName())
    if not wName then
        return (DEFAULT_FRIENDLY_EVENT_ANIMATION_PARAMETERS.maximumDisplayTime) + 1
    end
    if not DoesWindowExist(wName) then
        return (DEFAULT_FRIENDLY_EVENT_ANIMATION_PARAMETERS.maximumDisplayTime) + 1
    end
    local anim = self.m_BaseAnim
    if not (anim and anim.maxTime and anim.targetWindow) then
        return (DEFAULT_FRIENDLY_EVENT_ANIMATION_PARAMETERS.maximumDisplayTime) + 1
    end
    if not DoesWindowExist(anim.targetWindow) then
        return (DEFAULT_FRIENDLY_EVENT_ANIMATION_PARAMETERS.maximumDisplayTime) + 1
    end

    local simTime = (elapsedTime or 0) * (simulationSpeed or 1)
    self.m_LifeSpan = (self.m_LifeSpan or 0) + simTime

    for _, slot in ipairs(self.m_Effects or {}) do
        local localT = self.m_LifeSpan - (slot.startAt or 0)
        local dur = slot.duration or 0
        if localT >= 0 and localT <= dur then
            local p = (dur > 0) and (localT / dur) or 1
            slot.effect.Apply(self, localT, p, slot.params or {})
        elseif localT > dur and not slot._finished then
            slot.effect.Finish(self, slot.params or {})
            slot._finished = true
        end
    end

    local step = (anim.maxTime > 0) and (simTime / anim.maxTime) or 1
    anim.current.x = anim.current.x + (anim.target.x - anim.start.x) * step
    anim.current.y = anim.current.y + (anim.target.y - anim.start.y) * step
    local ox = anim.current.x
    -- For plain (non-holder) entries, treat X as the desired label *center*.
    if anim.targetWindow == wName and self.m_WindowW and self.m_WindowW > 0 then
        ox = ox - (self.m_WindowW / 2)
    end
    WindowSetOffsetFromParent(anim.targetWindow, ox, anim.current.y)
    if self.m_AbilityIconWindow and DoesWindowExist(self.m_AbilityIconWindow) then
        local iconX = (anim.targetWindow == wName) and ox or 0
        local iconY = (anim.targetWindow == wName) and anim.current.y or 0
        WindowSetOffsetFromParent(
            self.m_AbilityIconWindow,
            iconX + (self.m_AbilityIconOffsetX or 0),
            iconY + (self.m_AbilityIconOffsetY or 0)
        )
    end

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
    do
        local sct0 = CustomUI.SCT and CustomUI.SCT.GetSettings and CustomUI.SCT.GetSettings()
        if sct0 and sct0.showAbilityIcon == true then
            abilityIconInfo = SctAbilityIconForAbilityId(abilityId)
            useAbilityIcon = abilityIconInfo ~= nil
        end
    end

    -- Do not use <icon#> markup here: animated labels can leave the engine-generated icon behind.
    -- SCT renders the ability icon as an explicit child window controlled by this frame.
    LabelSetFont(wName, SctLabelFontName(), WindowUtils.FONT_DEFAULT_TEXT_LINESPACING)
    LabelSetText(wName, text)
    if useAbilityIcon then
        LabelSetTextAlign(wName, "left")
    end

    local dw, dh = LabelGetTextDimensions(wName)
    self.m_TextBaseW = (dw and dw > 0) and dw or (self.m_TextBaseW or 80)
    self.m_TextBaseH = (dh and dh > 0) and dh or (self.m_TextBaseH or 24)
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
    do
        local ww, _ = WindowGetDimensions(wName)
        self.m_WindowW = ww
    end
    SctApplyAbilityIconLayout(self, wName, abilityIconInfo)

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
        local anySizeAnim = sh or pu
        self.m_CritStartScale = anySizeAnim and (scale / CRIT_FONT_VISUAL_RATIO) or scale
        self.m_CritEndScale = scale
        LabelSetFont(wName, SctLabelFontName(), WindowUtils.FONT_DEFAULT_TEXT_LINESPACING)
        WindowSetScale(wName, self.m_CritStartScale)
        WindowSetRelativeScale(wName, self.m_CritStartScale)
    else
        LabelSetFont(wName, SctLabelFontName(), WindowUtils.FONT_DEFAULT_TEXT_LINESPACING)
        WindowSetScale(wName, scale)
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
    if useAbilityIcon then
        LabelSetTextAlign(wName, "left")
    end
    SctForceProcessAnchors(wName)

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
    SctRefitEventLabelAfterScale(self, wName, useAbilityIcon, abilityIconInfo)
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
    if not DoesWindowExist(windowName) then
        return nil
    end
    WindowSetOffsetFromParent(windowName, animationData.start.x, animationData.start.y)
    return eventFrame
end

function CustomUI.SCT.PointGainEntry:Update(elapsedTime, simulationSpeed)
    local wName = self.m_Window or (self.GetName and self:GetName())
    if not wName then
        return (DEFAULT_FRIENDLY_EVENT_ANIMATION_PARAMETERS.maximumDisplayTime) + 1
    end
    if not DoesWindowExist(wName) then
        return (DEFAULT_FRIENDLY_EVENT_ANIMATION_PARAMETERS.maximumDisplayTime) + 1
    end
    local anim = self.m_BaseAnim
    if not (anim and anim.maxTime and anim.targetWindow) then
        return (DEFAULT_FRIENDLY_EVENT_ANIMATION_PARAMETERS.maximumDisplayTime) + 1
    end
    if not DoesWindowExist(anim.targetWindow) then
        return (DEFAULT_FRIENDLY_EVENT_ANIMATION_PARAMETERS.maximumDisplayTime) + 1
    end

    local simTime = (elapsedTime or 0) * (simulationSpeed or 1)
    self.m_LifeSpan = (self.m_LifeSpan or 0) + simTime

    local step = (anim.maxTime > 0) and (simTime / anim.maxTime) or 1
    anim.current.x = anim.current.x + (anim.target.x - anim.start.x) * step
    anim.current.y = anim.current.y + (anim.target.y - anim.start.y) * step
    local ox = anim.current.x
    if anim.targetWindow == wName and self.m_WindowW and self.m_WindowW > 0 then
        ox = ox - (self.m_WindowW / 2)
    end
    WindowSetOffsetFromParent(anim.targetWindow, ox, anim.current.y)

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
    SctRefitPointGainLabelAfterScale(self, wName)

    local sct   = CustomUI.SCT.GetSettings()
    local key   = CustomUI.SCT.KeyForPointType(pointType)
    self.m_PointTypeKey = key
    local scale = (sct.outgoing and sct.outgoing.size and sct.outgoing.size[key]) or 1.0

    WindowSetScale(wName, scale)
    WindowSetRelativeScale(wName, scale)
    local t = LabelGetText(wName)
    if t then LabelSetText(wName, t) end
    SctRefitPointGainLabelAfterScale(self, wName)
    if self.m_AnimationData and self.m_AnimationData.current then
        local centeredX = (self.m_AnimationData.current.x or 0) - ((self.m_WindowW or 0) / 2)
        WindowSetOffsetFromParent(wName, centeredX, self.m_AnimationData.current.y or 0)
    end

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
    SctRefitPointGainLabelAfterScale(self, wName)
end

function CustomUI.SCT.EventEntry:Destroy()
    local wName = self.GetName and self:GetName()
    if self.m_FlashHolderName and DoesWindowExist(self.m_FlashHolderName) then
        SctDestroyAbilityIcon(self)
        SctStopWindowAnimations(wName)
        SctForgetManagedFrame(wName)
        SctStopWindowAnimations(self.m_FlashHolderName)
        DestroyWindow(self.m_FlashHolderName)
        self.m_FlashHolderName = nil
        if self.m_Tracker and self.m_LaneSlot then
            self.m_Tracker:ReleaseLane(self.m_LaneSlot)
        end
        self.m_Tracker = nil
        self.m_LaneSlot = nil
        return
    end
    SctDestroyEventWindowByName(wName)
end

function CustomUI.SCT.PointGainEntry:IsOutOfStartingBox()
    return (self.m_AnimationData.start.y - self.m_AnimationData.current.y) > MINIMUM_EVENT_SPACING
end

function CustomUI.SCT.PointGainEntry:Destroy()
    local wName = self.GetName and self:GetName()
    SctDestroyEventWindowByName(wName)
end
