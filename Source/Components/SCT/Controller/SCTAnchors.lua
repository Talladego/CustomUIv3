-- LEGACY (v2 SCT, 2026-04-25): replaced by SCTOverrides.lua. Safe to delete once
-- Step 5b verifies no remaining references. Do not extend or fix bugs in this file.
----------------------------------------------------------------
-- CustomUI.SCT — anchors, engine log mirror, ability-icon window helpers
-- Load after SCTAnim. Exposes CustomUI.SCT._SctAnchors and _RuntimeForHandlers.
----------------------------------------------------------------

local function sctFileTextLogName()
    return "uilog"
end

local function sctWriteEngineLog(level, message)
    if not (CustomUI.SCT and CustomUI.SCT.m_sctFileLog ~= false) then
        return
    end
    if type(message) ~= "string" then
        message = tostring(message)
    end
    local filter = (SystemData and SystemData.UiLogFilters) and SystemData.UiLogFilters.ERROR or 0
    if level == "warning" and SystemData and SystemData.UiLogFilters then
        filter = SystemData.UiLogFilters.WARNING
    elseif level == "debug" and SystemData and SystemData.UiLogFilters then
        filter = SystemData.UiLogFilters.DEBUG
    end
    if LogLuaMessage and type(towstring) == "function" then
        LogLuaMessage("Lua", filter, towstring(message))
    end
    if TextLogAddEntry and type(towstring) == "function" then
        TextLogAddEntry(sctFileTextLogName(), filter, towstring(message))
    end
end

--- Engine-boundary helper: on failure, always log to uilog; mirror to TextLog when file logging is on.
local function SctPcallFailed(operation, err)
    local msg = "[CustomUI.SCT] " .. tostring(operation) .. " failed: " .. tostring(err)
    if LogLuaMessage and type(towstring) == "function" and SystemData and SystemData.UiLogFilters then
        LogLuaMessage("Lua", SystemData.UiLogFilters.WARNING, towstring(msg))
    end
    sctWriteEngineLog("warning", msg)
end

local function SctFileLogError(message)
    sctWriteEngineLog("error", "[CustomUI.SCT] " .. tostring(message))
end

local function SctStopWindowAnimations(windowName)
    if not windowName or windowName == "" then return end
    if not DoesWindowExist(windowName) then return end

    -- Hard rule: stop animations before destroying any SCT-owned window.
    WindowStopAlphaAnimation(windowName)
    WindowStopPositionAnimation(windowName)
    WindowStopScaleAnimation(windowName)
end

-- Frame:CreateFromTemplate registers transient SCT labels with FrameManager. Do not use
-- FrameManager:Remove here: it walks all managed frames via WindowGetParent and stale SCT
-- names are exactly what can trigger uilog parent errors. Forget our exact name directly.
local function SctForgetManagedFrame(windowName)
    if not windowName or windowName == "" then
        return
    end
    if FrameManager and FrameManager.m_Frames then
        FrameManager.m_Frames[windowName] = nil
    end
end

local function SctDestroyEventWindowByName(windowName)
    if not windowName or windowName == "" then
        return
    end
    local iconName = windowName .. "AbilityIcon"
    SctStopWindowAnimations(iconName)
    if DoesWindowExist(iconName) then
        DestroyWindow(iconName)
    end
    SctStopWindowAnimations(windowName)
    SctForgetManagedFrame(windowName)
    if DoesWindowExist(windowName) then
        DestroyWindow(windowName)
    end
end

-- Not all client builds define WindowUtils.ForceProcessAnchors; optional layout refresh.
local function SctForceProcessAnchors(windowName)
    if not windowName or windowName == "" then
        return
    end
    local fn = WindowUtils and WindowUtils.ForceProcessAnchors
    if type(fn) == "function" then
        fn(windowName)
    end
end

local function SctLabelFontName()
    if CustomUI.SCT and CustomUI.SCT.GetTextFontName then
        return CustomUI.SCT.GetTextFontName()
    end
    return "font_default_text_large"
end

-- Per-world-object root under CustomUI-owned CustomUISCTWindow. Must always be reload-safe:
-- destroy any stale anchor instance before re-creating it.
local function SctEnsureEventTextRootAnchor(anchorName)
    if not anchorName or anchorName == "" then
        return false
    end
    if not DoesWindowExist("CustomUISCTWindow") then
        return false
    end
    if DoesWindowExist(anchorName) then
        -- Stale anchor windows can survive reloads/toggles; always destroy first so we can't
        -- inherit orphaned children/animations that break future dispatch.
        SctStopWindowAnimations(anchorName)
        DestroyWindow(anchorName)
    end
    local ok, err = pcall(CreateWindowFromTemplate, anchorName, "EA_Window_EventTextAnchor", "CustomUISCTWindow")
    if not ok then
        SctPcallFailed("CreateWindowFromTemplate(EventTextAnchor)", err)
        return false
    end
    return DoesWindowExist(anchorName)
end

-- Step 5 cleanup: single "create anchor" verb; keep old name for compatibility.
local function SctCreateAnchor(anchorName)
    return SctEnsureEventTextRootAnchor(anchorName)
end

local function SctAnchorName(targetObjectNumber, isCrit)
    local suffix = tostring(targetObjectNumber or "unknown")
    if isCrit then
        return "CustomUI_SCT_EventTextAnchorCrit" .. suffix
    end
    return "CustomUI_SCT_EventTextAnchor" .. suffix
end

local function SctAbilityIconForAbilityId(abilityId)
    if not abilityId or abilityId == 0 then
        return nil
    end
    local data = GetAbilityData(abilityId)
    if type(data) ~= "table" or not data.iconNum or data.iconNum <= 0 then
        return nil
    end
    local texture, x, y = GetIconData(data.iconNum)
    if texture == nil or texture == "" or texture == "icon000000" then
        return nil
    end
    return { texture = texture, x = x or 0, y = y or 0 }
end

local function SctEnsureAbilityIconWindow(iconWindowName, parentWindowName)
    if not iconWindowName or not parentWindowName then
        return false
    end
    if DoesWindowExist(iconWindowName) then
        return true
    end
    local ok, err = pcall(CreateWindowFromTemplate, iconWindowName, "CustomUI_SCTAbilityIcon", parentWindowName)
    if not ok then
        SctPcallFailed("CreateWindowFromTemplate(AbilityIcon)", err)
        return false
    end
    return DoesWindowExist(iconWindowName)
end

local function SctDestroyAbilityIcon(frame)
    if not frame or not frame.m_AbilityIconWindow then
        return
    end
    SctStopWindowAnimations(frame.m_AbilityIconWindow)
    if DoesWindowExist(frame.m_AbilityIconWindow) then
        DestroyWindow(frame.m_AbilityIconWindow)
    end
    frame.m_AbilityIconWindow = nil
end

local function SctApplyAbilityIconLayout(frame, wName, iconInfo)
    if not frame or not wName or not iconInfo then
        SctDestroyAbilityIcon(frame)
        return
    end
    -- Labels cannot host child windows in this client. Parent the icon beside the label
    -- under the same parent, then move it from EventEntry:Update with the label's offset.
    -- Do not WindowAddAnchor to transient labels: the engine resolves that through
    -- WindowGetParent internally and can log errors after the label is destroyed.
    local iconWin = wName .. "AbilityIcon"
    local parentWin = (frame.GetKnownParent and frame:GetKnownParent()) or frame.m_ParentWindow
    if not DoesWindowExist(wName) then
        SctDestroyAbilityIcon(frame)
        return
    end
    if not parentWin or parentWin == "" or not DoesWindowExist(parentWin) then
        frame.m_AbilityIconWindow = nil
        return
    end
    if not SctEnsureAbilityIconWindow(iconWin, parentWin) then
        frame.m_AbilityIconWindow = nil
        return
    end
    if not DoesWindowExist(iconWin .. "Icon") then
        frame.m_AbilityIconWindow = nil
        return
    end
    frame.m_AbilityIconWindow = iconWin

    local textH = frame.m_TextBaseH or 24
    -- Ability icon tuning: slightly smaller than text height, with a tighter gap, and centered vertically.
    local size = math.floor(math.max(12, textH * 0.9))
    local gap = math.floor(math.max(2, textH * 0.18))
    local yOff = math.floor(((textH - size) / 2) + 0.5)

    WindowSetDimensions(iconWin, size, size)
    WindowClearAnchors(iconWin)
    frame.m_AbilityIconOffsetX = (frame.m_WindowW or frame.m_TextBaseW or 80) + gap
    frame.m_AbilityIconOffsetY = yOff
    WindowSetOffsetFromParent(iconWin, frame.m_AbilityIconOffsetX, yOff)
    SctForceProcessAnchors(iconWin)
    DynamicImageSetTexture(iconWin .. "Icon", iconInfo.texture, iconInfo.x, iconInfo.y)
    DynamicImageSetTextureDimensions(iconWin .. "Icon", 64, 64)
    WindowSetShowing(iconWin, true)
end

CustomUI.SCT._SctAnchors = {
    SctPcallFailed = SctPcallFailed,
    SctFileLogError = SctFileLogError,
    SctUilogError = SctFileLogError,
    SctStopWindowAnimations = SctStopWindowAnimations,
    SctForgetManagedFrame = SctForgetManagedFrame,
    SctDestroyEventWindowByName = SctDestroyEventWindowByName,
    SctForceProcessAnchors = SctForceProcessAnchors,
    SctLabelFontName = SctLabelFontName,
    SctCreateAnchor = SctCreateAnchor,
    SctEnsureEventTextRootAnchor = SctEnsureEventTextRootAnchor,
    SctAnchorName = SctAnchorName,
    SctAbilityIconForAbilityId = SctAbilityIconForAbilityId,
    SctEnsureAbilityIconWindow = SctEnsureAbilityIconWindow,
    SctDestroyAbilityIcon = SctDestroyAbilityIcon,
    SctApplyAbilityIconLayout = SctApplyAbilityIconLayout,
}

CustomUI.SCT._RuntimeForHandlers = {
    SctAnchorName = SctAnchorName,
    SctCreateAnchor = SctCreateAnchor,
    SctEnsureEventTextRootAnchor = SctEnsureEventTextRootAnchor,
    SctPcallFailed = SctPcallFailed,
    SctFileLogError = SctFileLogError,
}
