----------------------------------------------------------------
-- CustomUI.SCT.EventEntry
--
-- Event/point-gain entry classes plus their holder/icon/suffix window layout.
-- Ability icon DATA resolution lives in SCTAbilityIconResolver.lua.
----------------------------------------------------------------
if not CustomUI.SCT then CustomUI.SCT = {} end

local Resolver = CustomUI.SCT.AbilityIconResolver or {}
local StockEventEntry = _G["EA_System_EventEntry"]
local StockPointGainEntry = _G["EA_System_PointGainEntry"]

if not StockEventEntry or not StockPointGainEntry then
    error("CustomUI SCT: stock EA_System_EventEntry / PointGainEntry not found")
end

local function SctStopAnimations(windowName)
    if not windowName or not DoesWindowExist(windowName) then
        return
    end
    WindowStopAlphaAnimation(windowName)
    WindowStopPositionAnimation(windowName)
    WindowStopScaleAnimation(windowName)
end

local function SctForceProcessAnchors(windowName)
    if not windowName or windowName == "" then
        return
    end
    local fn = WindowUtils and WindowUtils.ForceProcessAnchors
    if type(fn) == "function" then
        fn(windowName)
    end
end

local function SctForgetManagedFrame(windowName)
    if FrameManager and FrameManager.m_Frames and windowName and windowName ~= "" then
        FrameManager.m_Frames[windowName] = nil
    end
end

local function SctDestroyWindow(windowName)
    if not windowName or windowName == "" then
        return
    end
    SctStopAnimations(windowName)
    SctForgetManagedFrame(windowName)
    if DoesWindowExist(windowName) then
        DestroyWindow(windowName)
    end
end

local function SctHolderName(entryWindowName)
    return tostring(entryWindowName) .. "Holder"
end

local function SctAnchorLabelToHolder(labelName, holderName, xOffset, yOffset)
    if not DoesWindowExist(labelName) or not DoesWindowExist(holderName) then
        return
    end
    WindowClearAnchors(labelName)
    WindowAddAnchor(labelName, "center", holderName, "center", xOffset or 0, yOffset or 0)
end

local function SctCreateHolder(holderName, parentWindow, animationData)
    SctDestroyWindow(holderName)
    if not parentWindow or parentWindow == "" or not DoesWindowExist(parentWindow) then
        return false
    end
    CreateWindowFromTemplate(holderName, "EA_Window_EventTextAnchor", parentWindow)
    if not DoesWindowExist(holderName) then
        return false
    end
    WindowSetOffsetFromParent(holderName, animationData.start.x, animationData.start.y)
    WindowSetShowing(holderName, true)
    return true
end

local function SctMoveEntryHolder(entry, x, y)
    local holder = entry and entry.m_HolderWindow
    if holder and DoesWindowExist(holder) then
        WindowSetOffsetFromParent(holder, x, y)
    end
    if entry and entry.UpdateAbilityIconPosition then
        entry:UpdateAbilityIconPosition()
    end
end

local function SctUpdateEntryPosition(entry, elapsedTime, simulationSpeed)
    local simulationTime = elapsedTime * (simulationSpeed or 1)
    local animationData = entry.m_AnimationData
    if not animationData then
        return 0
    end

    local animationStep = simulationTime / animationData.maximumDisplayTime
    local stepX = (animationData.target.x - animationData.start.x) * animationStep
    local stepY = (animationData.target.y - animationData.start.y) * animationStep

    animationData.current.x = animationData.current.x + stepX
    animationData.current.y = animationData.current.y + stepY
    SctMoveEntryHolder(entry, animationData.current.x, animationData.current.y)

    entry.m_LifeSpan = (entry.m_LifeSpan or 0) + simulationTime
    return entry.m_LifeSpan
end

local function SctStripLeadingCombatAmountSign(windowName)
    if not windowName or windowName == "" or not DoesWindowExist(windowName) then
        return
    end
    local text = LabelGetText(windowName)
    if not text or text == L"" then
        return
    end
    local c1 = wstring.sub(text, 1, 1)
    if c1 == L"+" or c1 == L"-" then
        LabelSetText(windowName, wstring.sub(text, 2))
    end
end

local function SctDestroyAbilityNameSuffix(entry)
    if not entry then
        return
    end
    local suffixWindow = entry.m_AbilityNameSuffixWindow
    if suffixWindow and entry.m_AbilityIconAnchorRightWindow == suffixWindow then
        entry.m_AbilityIconAnchorRightWindow = nil
    end
    if not suffixWindow then
        return
    end
    SctStopAnimations(suffixWindow)
    if DoesWindowExist(suffixWindow) then
        DestroyWindow(suffixWindow)
    end
    entry.m_AbilityNameSuffixWindow = nil
end

local function SctApplyAbilityNameSuffix(entry, windowName, holderName, cleanName, fontName, scale)
    if not cleanName or cleanName == "" or not windowName or windowName == "" or not DoesWindowExist(windowName) then
        return false
    end
    if not holderName or holderName == "" or not DoesWindowExist(holderName) then
        return false
    end

    local suffixWindow = windowName .. "AbilityNameSuffix"
    if DoesWindowExist(suffixWindow) then
        DestroyWindow(suffixWindow)
    end
    CreateWindowFromTemplate(suffixWindow, "CustomUI_SCTAbilityNameSuffix", holderName)
    if not DoesWindowExist(suffixWindow) then
        return false
    end

    LabelSetText(suffixWindow, L" (" .. towstring(cleanName) .. L")")
    if fontName and fontName ~= "" and fontName ~= "font_default_text_large" then
        LabelSetFont(suffixWindow, fontName, WindowUtils.FONT_DEFAULT_TEXT_LINESPACING)
    end
    if type(LabelGetTextColor) == "function" then
        local r, g, b = LabelGetTextColor(windowName)
        if r ~= nil and g ~= nil and b ~= nil then
            LabelSetTextColor(suffixWindow, r, g, b)
        end
    end
    LabelSetTextAlign(suffixWindow, "left")

    local entryScale = scale or 1.0
    WindowSetScale(suffixWindow, entryScale)
    WindowSetRelativeScale(suffixWindow, entryScale)

    local suffixW, suffixH = LabelGetTextDimensions(suffixWindow)
    suffixW = (suffixW and suffixW > 0) and suffixW or 40
    suffixH = (suffixH and suffixH > 0) and suffixH or 24
    WindowSetDimensions(suffixWindow, suffixW, suffixH)

    local _, mainH = LabelGetTextDimensions(windowName)
    mainH = (mainH and mainH > 0) and mainH or suffixH
    local yOffset = math.floor(((mainH - suffixH) / 2) + 0.5)
    local gap = math.floor((2 * entryScale) + 0.5)
    WindowClearAnchors(suffixWindow)
    WindowAddAnchor(suffixWindow, "topright", windowName, "topleft", gap, yOffset)
    SctForceProcessAnchors(suffixWindow)
    WindowSetShowing(suffixWindow, true)

    entry.m_AbilityNameSuffixWindow = suffixWindow
    entry.m_AbilityIconAnchorRightWindow = suffixWindow
    return true
end

local function SctCreateAbilityIcon(iconWindowName, parentWindowName, iconInfo, textH, abilityData)
    if not iconInfo or not DoesWindowExist(parentWindowName) then
        return false
    end
    if DoesWindowExist(iconWindowName) then
        DestroyWindow(iconWindowName)
    end
    CreateWindowFromTemplate(iconWindowName, "CustomUI_SCTAbilityIcon", parentWindowName)
    if not DoesWindowExist(iconWindowName) then
        return false
    end

    local size = math.floor(math.max(12, (textH or 24) * 0.9))
    WindowSetDimensions(iconWindowName, size, size)
    DynamicImageSetTexture(iconWindowName .. "Icon", iconInfo.texture, iconInfo.x, iconInfo.y)
    DynamicImageSetTextureDimensions(iconWindowName .. "Icon", 64, 64)

    if DoesWindowExist(iconWindowName .. "Frame") then
        DynamicImageSetTexture(iconWindowName .. "Frame", "EA_SquareFrame", 0, 0)
        DynamicImageSetTextureDimensions(iconWindowName .. "Frame", 64, 64)
        WindowSetDimensions(iconWindowName .. "Frame", size, size)

        local r, g, b
        if abilityData and DataUtils and DataUtils.GetAbilityTypeTextureAndColor then
            local _, _, _, rr, gg, bb = DataUtils.GetAbilityTypeTextureAndColor(abilityData)
            r, g, b = rr, gg, bb
        end
        if r and g and b then
            WindowSetTintColor(iconWindowName .. "Frame", r, g, b)
        else
            WindowSetTintColor(iconWindowName .. "Frame", 255, 255, 255)
        end
    end

    WindowSetShowing(iconWindowName, true)
    return true
end

local function SctDestroyAbilityIcon(entry)
    if not entry.m_AbilityIconWindow then
        return
    end
    SctStopAnimations(entry.m_AbilityIconWindow)
    if DoesWindowExist(entry.m_AbilityIconWindow) then
        DestroyWindow(entry.m_AbilityIconWindow)
    end
    entry.m_AbilityIconWindow = nil
end

local function SctPositionAbilityIcon(entry, iconWindowName, textW, textH)
    if not DoesWindowExist(iconWindowName) or not DoesWindowExist(entry:GetName()) then
        return
    end

    local windowName = entry:GetName()
    local before = CustomUI.SCT.GetAbilityIconBeforeText and CustomUI.SCT.GetAbilityIconBeforeText()
    local anchorRight = windowName
    if not before and entry.m_AbilityIconAnchorRightWindow and entry.m_AbilityIconAnchorRightWindow ~= ""
        and DoesWindowExist(entry.m_AbilityIconAnchorRightWindow)
    then
        anchorRight = entry.m_AbilityIconAnchorRightWindow
    end

    local _, mainH = LabelGetTextDimensions(windowName)
    local currentW, currentH = LabelGetTextDimensions(anchorRight)
    if currentW and currentW > 0 then
        textW = currentW
    end
    if currentH and currentH > 0 then
        textH = currentH
    end
    if mainH and mainH > 0 then
        textH = mainH
    end
    textW = (textW and textW > 0) and textW or 80
    textH = (textH and textH > 0) and textH or 24

    local scale = entry.m_CurrentVisualScale or entry.m_EffectiveScale or 1.0
    local baseSize = math.floor(math.max(12, textH * 0.9))
    WindowSetDimensions(iconWindowName, baseSize, baseSize)
    WindowSetScale(iconWindowName, scale)
    WindowSetRelativeScale(iconWindowName, scale)

    WindowClearAnchors(iconWindowName)
    local gap = math.floor((10 * scale) + 0.5)
    local yOffset = math.floor(((textH - baseSize) / 2) + 0.5) - math.floor((3 * scale) + 0.5)
    if before then
        WindowAddAnchor(iconWindowName, "topleft", windowName, "topright", -gap, yOffset)
    else
        WindowAddAnchor(iconWindowName, "topright", anchorRight, "topleft", gap, yOffset)
    end
    SctForceProcessAnchors(iconWindowName)
end

local function SctGetEffects()
    return CustomUI.SCT._SctAnim and CustomUI.SCT._SctAnim.Effects
end

CustomUI.SCT.EventEntry = StockEventEntry:Subclass("CustomUI_Window_EventTextLabel")

function CustomUI.SCT.EventEntry:Create(windowName, parentWindow, animationData)
    local holderName = SctHolderName(windowName)
    SctDestroyWindow(windowName)
    if not SctCreateHolder(holderName, parentWindow, animationData) then
        return nil
    end

    local frame = StockEventEntry.Create(self, windowName, holderName, animationData)
    if frame then
        frame.m_Anchor = parentWindow
        frame.m_HolderWindow = holderName
        frame.m_VisualOffsetX = 0
        frame.m_VisualOffsetY = 0
        SctAnchorLabelToHolder(windowName, holderName, 0, 0)
        SctMoveEntryHolder(frame, frame.m_AnimationData.current.x, frame.m_AnimationData.current.y)
    end
    return frame
end

function CustomUI.SCT.EventEntry:SetVisualOffset(x, y)
    self.m_VisualOffsetX = x or 0
    self.m_VisualOffsetY = y or 0
    SctAnchorLabelToHolder(self:GetName(), self.m_HolderWindow, self.m_VisualOffsetX, self.m_VisualOffsetY)
    self:UpdateAbilityIconPosition()
end

function CustomUI.SCT.EventEntry:SetVisualScale(scale)
    local windowName = self:GetName()
    if not DoesWindowExist(windowName) then
        return
    end
    self.m_CurrentVisualScale = scale or self.m_EffectiveScale or 1.0
    WindowSetScale(windowName, self.m_CurrentVisualScale)
    WindowSetRelativeScale(windowName, self.m_CurrentVisualScale)
    local suffixWindow = self.m_AbilityNameSuffixWindow
    if suffixWindow and suffixWindow ~= "" and DoesWindowExist(suffixWindow) then
        WindowSetScale(suffixWindow, self.m_CurrentVisualScale)
        WindowSetRelativeScale(suffixWindow, self.m_CurrentVisualScale)
    end
    self:UpdateAbilityIconLayout()
end

function CustomUI.SCT.EventEntry:UpdateAbilityIconLayout()
    if not self.m_AbilityIconWindow or not DoesWindowExist(self.m_AbilityIconWindow) then
        return
    end
    SctPositionAbilityIcon(self, self.m_AbilityIconWindow, self.m_AbilityIconTextW, self.m_AbilityIconTextH)
end

function CustomUI.SCT.EventEntry:UpdateAbilityIconPosition()
    if not self.m_AbilityIconWindow or not DoesWindowExist(self.m_AbilityIconWindow) then
        return
    end
    SctForceProcessAnchors(self.m_AbilityIconWindow)
end

function CustomUI.SCT.EventEntry:SetupText(hitTargetObjectNumber, hitAmount, textType, abilityId)
    StockEventEntry.SetupText(self, hitTargetObjectNumber, hitAmount, textType)

    local windowName = self:GetName()
    SctDestroyAbilityNameSuffix(self)
    self.m_AbilityIconAnchorRightWindow = nil

    local sct = CustomUI.SCT.GetSettings()

    local isHitOrCrit = (textType == GameData.CombatEvent.HIT)
                     or (textType == GameData.CombatEvent.ABILITY_HIT)
                     or (textType == GameData.CombatEvent.CRITICAL)
                     or (textType == GameData.CombatEvent.ABILITY_CRITICAL)
    local abilityLine = (textType == GameData.CombatEvent.ABILITY_HIT)
                     or (textType == GameData.CombatEvent.ABILITY_CRITICAL)

    local isIncoming = (type(GameData) == "table" and GameData.Player
        and hitTargetObjectNumber == GameData.Player.worldObjNum)

    local preIconInfo, preIconAbilityData, preIconReason = nil, nil, nil
    if abilityId and abilityId ~= 0 and sct.showAbilityIcon then
        preIconInfo, preIconAbilityData, preIconReason = Resolver.GetAbilityIconInfo(abilityId, isIncoming)
    end

    local nameHintAbilityData = preIconAbilityData
    if abilityLine and sct.showAbilityNameInText and abilityId and abilityId ~= 0 then
        nameHintAbilityData = Resolver.MergeAbilityNameHintForSuffix(preIconAbilityData, abilityId, abilityLine, sct)
    end

    local suffixClean = nil
    if abilityLine and sct.showAbilityNameInText and abilityId and abilityId ~= 0 then
        suffixClean = Resolver.TryGetAbilityDisplayNameForSuffix(abilityId, nameHintAbilityData)
    end

    if isHitOrCrit then
        SctStripLeadingCombatAmountSign(windowName)
    end

    local layoutLeft = (preIconInfo ~= nil)
    LabelSetTextAlign(windowName, layoutLeft and "left" or "center")

    local key = CustomUI.SCT.KeyForCombatType(textType)
    if isHitOrCrit and type(hitAmount) == "number" and hitAmount == hitAmount and hitAmount > 0 then
        key = "Heal"
    end

    local isCrit = (textType == GameData.CombatEvent.CRITICAL)
                or (textType == GameData.CombatEvent.ABILITY_CRITICAL)
    self.m_IsCrit = isCrit

    local iconInfo, iconAbilityData, iconReason = preIconInfo, preIconAbilityData, preIconReason
    if sct.showAbilityIcon then
        if (textType == GameData.CombatEvent.ABILITY_HIT or textType == GameData.CombatEvent.ABILITY_CRITICAL)
            and (not abilityId or abilityId == 0)
        then
            Resolver.DebugAbilityEventMissingAbilityId(textType, hitAmount)
        end

        if not iconInfo and key == "Ability" then
            Resolver.DebugAbilityTextNoIcon(textType, hitAmount, abilityId)
        end
        if not iconInfo and abilityId and abilityId ~= 0 then
            local abilityData = iconAbilityData
            if type(abilityData) ~= "table" then
                abilityData = GetAbilityData and GetAbilityData(abilityId)
            end
            if type(abilityData) ~= "table" then
                Resolver.DebugMissingAbilityIcon(abilityId, "GetAbilityData returned nil", nil)
            elseif not abilityData.iconNum then
                Resolver.DebugMissingAbilityIcon(abilityId, "abilityData.iconNum missing", abilityData)
            elseif abilityData.iconNum <= 0 then
                Resolver.DebugMissingAbilityIcon(abilityId, "abilityData.iconNum<=0", abilityData)
            else
                Resolver.DebugMissingAbilityIcon(abilityId, iconReason or "GetIconData returned empty/icon000000", abilityData)
            end
        end
    end

    local fontName = CustomUI.SCT.GetTextFontName()
    if fontName ~= "font_default_text_large" then
        LabelSetFont(windowName, fontName, WindowUtils.FONT_DEFAULT_TEXT_LINESPACING)
    end

    local tr, tg, tb
    local colorIdx, customRGB
    if isIncoming then
        colorIdx = CustomUI.SCT.GetColorIndex("incoming", key)
        customRGB = CustomUI.SCT.GetCustomColor("incoming", key)
    else
        colorIdx = CustomUI.SCT.GetColorIndex("outgoing", key)
        customRGB = CustomUI.SCT.GetCustomColor("outgoing", key)
    end
    if customRGB and customRGB[1] then
        tr, tg, tb = customRGB[1], customRGB[2], customRGB[3]
        LabelSetTextColor(windowName, tr, tg, tb)
    elseif colorIdx and colorIdx > 1 then
        local opt = CustomUI.SCT.COLOR_OPTIONS[colorIdx]
        if opt and opt.rgb then
            tr, tg, tb = opt.rgb[1], opt.rgb[2], opt.rgb[3]
            LabelSetTextColor(windowName, tr, tg, tb)
        end
    end
    self.m_TargetR = tr
    self.m_TargetG = tg
    self.m_TargetB = tb

    local sizeTable = isIncoming and sct.incoming or sct.outgoing
    local scale = (sizeTable and sizeTable.size and sizeTable.size[key]) or 1.0
    if isCrit then
        scale = scale * (sct.critSizeScale or 1.0)
    end
    self.m_EffectiveScale = scale
    self:SetVisualScale(scale)

    local needsTightMain = (suffixClean ~= nil) or (iconInfo ~= nil)
    if needsTightMain then
        local textW, textH = LabelGetTextDimensions(windowName)
        textW = (textW and textW > 0) and textW or 80
        textH = (textH and textH > 0) and textH or 24
        WindowSetDimensions(windowName, textW, textH)
    end

    local holderName = self.m_HolderWindow
    if suffixClean and holderName and holderName ~= "" and DoesWindowExist(holderName) then
        SctApplyAbilityNameSuffix(self, windowName, holderName, suffixClean, fontName, scale)
    end

    if iconInfo then
        local textW, textH = LabelGetTextDimensions(windowName)
        textW = (textW and textW > 0) and textW or 80
        textH = (textH and textH > 0) and textH or 24

        if not needsTightMain then
            WindowSetDimensions(windowName, textW, textH)
        end

        local iconWindow = windowName .. "AbilityIcon"
        local parentWindow = self.m_HolderWindow
        local abilityData = iconAbilityData or (abilityId and GetAbilityData and GetAbilityData(abilityId))
        if parentWindow and parentWindow ~= "" and DoesWindowExist(parentWindow) then
            if SctCreateAbilityIcon(iconWindow, parentWindow, iconInfo, textH, abilityData) then
                self.m_AbilityIconWindow = iconWindow
                self.m_AbilityIconTextW = textW
                self.m_AbilityIconTextH = textH
                SctPositionAbilityIcon(self, iconWindow, textW, textH)
            end
        end
    end

    self.m_CritT = 0
end

function CustomUI.SCT.EventEntry:Update(elapsedTime, simulationSpeed)
    local lifeElapsed = SctUpdateEntryPosition(self, elapsedTime, simulationSpeed)

    if self.m_IsCrit then
        local shake = CustomUI.SCT._frameCritShake
        local pulse = CustomUI.SCT._frameCritPulse
        local flash = CustomUI.SCT._frameCritFlash
        if shake == nil and pulse == nil and flash == nil then
            shake, pulse, flash = CustomUI.SCT.GetCritFlags()
        end
        if shake or pulse or flash then
            local effects = SctGetEffects()
            if effects then
                local simulationTime = elapsedTime * (simulationSpeed or 1)
                self.m_CritT = (self.m_CritT or 0) + simulationTime
                local t = self.m_CritT
                if shake and effects.Shake then effects.Shake.Apply(self, t) end
                if pulse and effects.Pulse then effects.Pulse.Apply(self, t) end
                if flash and effects.ColorFlash then
                    effects.ColorFlash.Apply(self, t, self.m_TargetR, self.m_TargetG, self.m_TargetB)
                end
            end
        else
            self:SetVisualOffset(0, 0)
        end
    else
        self:SetVisualOffset(0, 0)
    end

    return lifeElapsed
end

function CustomUI.SCT.EventEntry:Destroy()
    SctDestroyAbilityIcon(self)
    SctDestroyAbilityNameSuffix(self)
    self.m_AbilityIconAnchorRightWindow = nil
    SctStopAnimations(self:GetName())
    SctDestroyWindow(self:GetName())
    SctDestroyWindow(self.m_HolderWindow)
end

CustomUI.SCT.PointGainEntry = StockPointGainEntry:Subclass("CustomUI_Window_EventTextLabel")

function CustomUI.SCT.PointGainEntry:Create(windowName, parentWindow, animationData)
    local holderName = SctHolderName(windowName)
    SctDestroyWindow(windowName)
    if not SctCreateHolder(holderName, parentWindow, animationData) then
        return nil
    end

    local frame = StockPointGainEntry.Create(self, windowName, holderName, animationData)
    if frame then
        frame.m_Anchor = parentWindow
        frame.m_HolderWindow = holderName
        SctAnchorLabelToHolder(windowName, holderName, 0, 0)
        SctMoveEntryHolder(frame, frame.m_AnimationData.current.x, frame.m_AnimationData.current.y)
    end
    return frame
end

function CustomUI.SCT.PointGainEntry:SetupText(hitTargetObjectNumber, pointAmount, pointType)
    StockPointGainEntry.SetupText(self, hitTargetObjectNumber, pointAmount, pointType)

    local windowName = self:GetName()
    local sct = CustomUI.SCT.GetSettings()
    local key = CustomUI.SCT.KeyForPointType(pointType)

    local fontName = CustomUI.SCT.GetTextFontName()
    if fontName ~= "font_default_text_large" then
        LabelSetFont(windowName, fontName, WindowUtils.FONT_DEFAULT_TEXT_LINESPACING)
    end

    local colorIdx = CustomUI.SCT.GetColorIndex("outgoing", key)
    local customRGB = CustomUI.SCT.GetCustomColor("outgoing", key)
    if customRGB and customRGB[1] then
        LabelSetTextColor(windowName, customRGB[1], customRGB[2], customRGB[3])
    elseif colorIdx and colorIdx > 1 then
        local opt = CustomUI.SCT.COLOR_OPTIONS[colorIdx]
        if opt and opt.rgb then
            LabelSetTextColor(windowName, opt.rgb[1], opt.rgb[2], opt.rgb[3])
        end
    end

    local scale = (sct.outgoing and sct.outgoing.size and sct.outgoing.size[key]) or 1.0
    if scale ~= 1.0 then
        WindowSetScale(windowName, scale)
        WindowSetRelativeScale(windowName, scale)
    end
end

function CustomUI.SCT.PointGainEntry:Update(elapsedTime, simulationSpeed)
    return SctUpdateEntryPosition(self, elapsedTime, simulationSpeed)
end

function CustomUI.SCT.PointGainEntry:Destroy()
    SctStopAnimations(self:GetName())
    SctDestroyWindow(self:GetName())
    SctDestroyWindow(self.m_HolderWindow)
end
