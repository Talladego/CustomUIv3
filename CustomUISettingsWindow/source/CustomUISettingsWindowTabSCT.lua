CustomUISettingsWindowTabSCT = {}

-- Set true in the client console after /reloadui to trace SCT tab input (uses d() when available).
CustomUISettingsWindowTabSCT.DebugInput = false

-- Poll SystemData.MouseOverWindow / ActiveWindow while this tab is visible (same log sinks as DebugInput).
CustomUISettingsWindowTabSCT.DebugPointer = false

local c_SCROLL_CHILD = "SWTabSCTContentsScrollChild"
local c_SCT_PREFIX   = c_SCROLL_CHILD .. "SCT"
-- Tab is instanced as <Window name="SWTabSCT" inherits="CustomUISettingsWindowTabSCT"/> in CustomUISettingsWindowTabbed.xml, so the template root is SWTabSCT, not the template file name.
-- SctColorPickerHost lives on CustomUISettingsWindowTabbed (last in XML) so it stacks above the footer buttons and receives hits when overlapping them / near window edges.
local c_SCT_TAB_ROOT = "SWTabSCT"
local c_SCT_SETTINGS_ROOT = "CustomUISettingsWindowTabbed"
local c_SCT_COLOR_PICKER_HOST = c_SCT_SETTINGS_ROOT .. "SctColorPickerHost"
local c_SCT_COLOR_PICKER = c_SCT_COLOR_PICKER_HOST .. "SctColorPicker"
-- Must match SctColorPickerHost <Size> in CustomUISettingsWindowTabbed.xml. After WindowSetParent the client can drop
-- dimensions, so we re-apply on show (see OnSctColorSwatchClick).
local c_SCT_COLOR_PICKER_HOST_W, c_SCT_COLOR_PICKER_HOST_H = 192, 360
-- Pixel width of the 5×(24+10)−10 swatch grid; must match XML ColorSpacing / ColorSize. The client
-- may size the ColorPicker as 5×(24+10) = 170 (adds a trailing gap); we trim back to this so column 5 meets the right edge.
local c_SCT_COLOR_PICKER_GRID_W = 5 * 24 + 4 * 10
local c_SCT_COLOR_PICKER_GRID_H = 8 * 24 + 7 * 10
-- Swatch control size (must match OutColorSwatch / InColorSwatch in xml) + gap before the floating grid.
local c_SCT_SWATCH_PICKER_OFF_X = 20 + 6

CustomUISettingsWindowTabSCT.contentsName = c_SCROLL_CHILD

local m_refreshing = false
local m_sctColorPickerReady = false
local m_sctColorPickerGridRev = -1
-- When non-nil, user is editing: { key, dir="Out"|"In", anchorSwatch=full window name of OutColorSwatch/InColorSwatch }.
local m_sctColorPickerContext = nil

local m_pointerLastMouseOver = nil
local m_pointerLastActive = nil

-- Forward declaration so OnUpdateDebugPointer (defined earlier in file) can see this local.
local LogSctLayoutRuntime

local function EmitDebugLine(prefix, msg)
    local line = prefix .. tostring(msg)
    if type(d) == "function" then
        d(line)
    end
    pcall(function()
        if LogLuaMessage and SystemData and SystemData.UiLogFilters then
            LogLuaMessage("Lua", SystemData.UiLogFilters.DEBUG, towstring(line))
        end
    end)
end

local function SctTabDbg(msg)
    if not CustomUISettingsWindowTabSCT.DebugInput then
        return
    end
    EmitDebugLine("[CustomUI SCT Tab] ", msg)
end

local function SctPointerDbg(msg)
    if not CustomUISettingsWindowTabSCT.DebugPointer then
        return
    end
    EmitDebugLine("[CustomUI SCT Tab ptr] ", msg)
end

local function PointerScopeName(name)
    if name == nil or name == "" then
        return false
    end
    return string.find(name, "SWTabSCT", 1, true) ~= nil
        or string.find(name, "CustomUISettingsWindowTabSCT", 1, true) ~= nil
end

local function PointerParentSnippet(winName, maxDepth)
    if not winName or winName == "" then
        return "<empty>"
    end
    local parts = {}
    local w = winName
    for i = 1, maxDepth or 8 do
        if not w or w == "" then
            break
        end
        parts[#parts + 1] = tostring(w)
        w = WindowGetParent(w)
    end
    return table.concat(parts, " <- ")
end

local function PointerLogRelevant(mo, act, lastMo, lastAct)
    if PointerScopeName(mo) or PointerScopeName(act) then
        return true
    end
    if PointerScopeName(lastMo) or PointerScopeName(lastAct) then
        return true
    end
    return false
end

local ROW_BY_SUFFIX = {}
for _, d in ipairs(CustomUI.SCT.GetSettingsRowDescriptors()) do
    ROW_BY_SUFFIX[d.suffix] = d
end

-- Color: one shared ColorPicker; row buttons (OutColorButton / InColorButton) show label + text tint (see SctUpdateColorButton).

-- Resolve ...Row<Suffix>OutColorSwatch / InColorSwatch window names to (row key, isIncoming) for default preview tinting.
local function SctParseSwatchNameForKeyDir(swatchName)
    if not swatchName or swatchName == "" then
        return nil, nil
    end
    local s = tostring(swatchName)
    for _, d in ipairs(CustomUI.SCT.GetSettingsRowDescriptors()) do
        local suff = d.suffix
        if string.find(s, "Row" .. suff .. "OutColorSwatch", 1, true) then
            return d.key, false
        end
        if string.find(s, "Row" .. suff .. "InColorSwatch", 1, true) then
            return d.key, true
        end
    end
    return nil, nil
end

-- `GameData.CombatEvent` value for SCT row keys (non-hit) used only for Default-color preview.
local function SctGameDataCombatEventForStockKey(key)
    local C = GameData and GameData.CombatEvent
    if not C then
        return nil
    end
    if key == "Block" then
        return C.BLOCK
    end
    if key == "Parry" then
        return C.PARRY
    end
    if key == "Evade" then
        return C.EVADE
    end
    if key == "Disrupt" then
        return C.DISRUPT
    end
    if key == "Absorb" then
        return C.ABSORB
    end
    if key == "Immune" then
        return C.IMMUNE
    end
    return nil
end

-- For Block / Parry / etc., the engine still calls `DefaultColor.GetCombatEventColor` with the real
-- `hitAmount` from the client. A positive amount selects the *healing* branch (green tints) before
-- `textType` is considered—so the floating text is often green, not the miss greys. Match that in the
-- Default (index 1) swatch by using the same function with amount 1, same as `SCTEventText.SetupText`.
local function SctStockPreviewDefensiveDefaultRgb(key, isIncoming)
    local textType = SctGameDataCombatEventForStockKey(key)
    if textType == nil or not DefaultColor or not DefaultColor.GetCombatEventColor then
        return nil
    end
    local player = GameData.Player and GameData.Player.worldObjNum
    if player == nil then
        return nil
    end
    local other = (player == 0) and 1 or 0
    if other == player then
        other = player + 1
    end
    local hitTargetObjectNumber = isIncoming and player or other
    local ok, c = pcall(function()
        return DefaultColor.GetCombatEventColor(hitTargetObjectNumber, 1, textType)
    end)
    if not ok or type(c) ~= "table" or c.r == nil then
        return nil
    end
    return c.r, c.g, c.b
end

-- RGB preview for index 1 (Default) per row: matches `DefaultColor.GetCombatEventColor` in defaultcolor.lua.
local function SctStockPreviewRgbForKey(key, isIncoming)
    if key == "XP" then
        return 255, 170, 0
    end
    if key == "Renown" then
        return 194, 56, 153
    end
    if key == "Influence" then
        return 0, 170, 163
    end
    if key == "Hit" then
        if isIncoming then
            return 255, 0, 0
        end
        return 235, 235, 235
    end
    if key == "Ability" then
        if isIncoming then
            return 255, 66, 0
        end
        return 235, 215, 135
    end
    if key == "Heal" then
        if isIncoming then
            return 0, 200, 0
        end
        return 0, 138, 0
    end
    local defR, defG, defB = SctStockPreviewDefensiveDefaultRgb(key, isIncoming)
    if defR ~= nil then
        return defR, defG, defB
    end
    if isIncoming then
        return 0, 200, 0
    end
    return 0, 138, 0
end

local function SctRgbForColorOptionIndex(colorIdx, key, isIncoming)
    if (colorIdx or 1) == 1 and key then
        return SctStockPreviewRgbForKey(key, isIncoming)
    end
    local opt = CustomUI.SCT.COLOR_OPTIONS[colorIdx or 1]
    if opt and opt.rgb then
        return opt.rgb[1], opt.rgb[2], opt.rgb[3]
    end
    return 100, 105, 110
end

-- 1D array of { r, g, b, id } for ColorPickerCreateWithColorTable. Skip index 1 (Default) so the grid is exactly 5x8 with one hue per row.
-- `id` is the COLOR_OPTIONS index (2..41) returned by ColorPickerGetColorAtPoint.
local function SctBuildColorTable1D()
    local opts = CustomUI.SCT.COLOR_OPTIONS
    local columns = (CustomUI.SCT and CustomUI.SCT.COLOR_PICKER_COLUMNS) or 5
    local startIdx = 2
    local nPalette = #opts - 1
    if nPalette < 1 then
        return {}, 0, columns
    end
    local rowsN = math.max(1, math.ceil(nPalette / columns))
    local t = {}
    for i = 1, nPalette do
        local optIdx = startIdx + i - 1
        local o = opts[optIdx]
        if o and o.rgb then
            t[i] = { r = o.rgb[1], g = o.rgb[2], b = o.rgb[3], id = optIdx }
        else
            t[i] = { r = 190, g = 190, b = 200, id = optIdx }
        end
    end
    return t, rowsN, columns
end

local function SctHideColorPicker()
    m_sctColorPickerContext = nil
    if DoesWindowExist(c_SCT_COLOR_PICKER_HOST) then
        pcall(function() WindowSetShowing(c_SCT_COLOR_PICKER_HOST, false) end)
    end
end

local function SctTightenColorPickerWidth()
    if not DoesWindowExist(c_SCT_COLOR_PICKER) then
        return
    end
    pcall(function()
        local _, h = WindowGetDimensions(c_SCT_COLOR_PICKER)
        if not h or h <= 0 then
            h = c_SCT_COLOR_PICKER_GRID_H
        end
        WindowSetDimensions(c_SCT_COLOR_PICKER, c_SCT_COLOR_PICKER_GRID_W, h)
    end)
end

local function SctEnsureColorPickerGrid()
    if not DoesWindowExist(c_SCT_COLOR_PICKER) then
        return
    end
    local rev = (CustomUI.SCT and CustomUI.SCT.COLOR_PALETTE_REVISION) or 1
    if m_sctColorPickerReady and m_sctColorPickerGridRev == rev then
        SctTightenColorPickerWidth()
        return
    end
    local t, rowsN, columns = SctBuildColorTable1D()
    local ok, err = pcall(function()
        ColorPickerCreateWithColorTable(c_SCT_COLOR_PICKER, t, columns, rowsN, 10)
    end)
    if not ok then
        SctTabDbg("SctEnsureColorPickerGrid: ColorPickerCreateWithColorTable failed: " .. tostring(err))
        return
    end
    m_sctColorPickerReady = true
    m_sctColorPickerGridRev = rev
    SctTightenColorPickerWidth()
    pcall(function() WindowSetShowing(c_SCT_COLOR_PICKER_HOST, false) end)
end

local function SctClickWindowNameForColorButton()
    local act = (SystemData.ActiveWindow and SystemData.ActiveWindow.name) or ""
    if act ~= "" then
        return act
    end
    return (SystemData.MouseOverWindow and SystemData.MouseOverWindow.name) or ""
end

local function SctUpdateColorSwatch(swatchName, colorIdx, key, isIncoming)
    if not swatchName or not DoesWindowExist(swatchName) then
        return
    end
    if not key then
        key, isIncoming = SctParseSwatchNameForKeyDir(swatchName)
    end
    local r, g, b = SctRgbForColorOptionIndex(colorIdx, key, isIncoming)
    pcall(WindowSetTintColor, swatchName, r, g, b)
end

local function SetupRow(contentPrefix, rowSuffix, sct)
    local info = ROW_BY_SUFFIX[rowSuffix]
    if not info then return end
    local key = info.key
    local rowPfx = contentPrefix .. "Row" .. rowSuffix

    local out = sct.outgoing
    if DoesWindowExist(rowPfx .. "OutShowButton") then
        ButtonSetPressedFlag(rowPfx .. "OutShowButton", out.filters["show" .. key] ~= false)
    end
    if DoesWindowExist(rowPfx .. "OutSize") then
        SliderBarSetCurrentPosition(rowPfx .. "OutSize", CustomUI.SCT.ScaleToSliderPos(out.size[key] or 1.0))
    end
    SctUpdateColorSwatch(rowPfx .. "OutColorSwatch", out.color[key] or 1)

    if info.hasIncoming then
        local inc = sct.incoming
        if DoesWindowExist(rowPfx .. "InShowButton") then
            ButtonSetPressedFlag(rowPfx .. "InShowButton", inc.filters["show" .. key] ~= false)
        end
        if DoesWindowExist(rowPfx .. "InSize") then
            SliderBarSetCurrentPosition(rowPfx .. "InSize", CustomUI.SCT.ScaleToSliderPos(inc.size[key] or 1.0))
        end
        SctUpdateColorSwatch(rowPfx .. "InColorSwatch", inc.color[key] or 1)
    end
end

local function CritAnimButtonPrefix()
    return c_SCROLL_CHILD .. "General"
end

local function SyncCritAnimationButtons(mode)
    local p = CritAnimButtonPrefix()
    local isNone = (mode == "none")
    local isShake = (mode == "shake")
    local isFlash = (mode == "flash")
    if DoesWindowExist(p .. "CritAnimNoneButton") then
        ButtonSetPressedFlag(p .. "CritAnimNoneButton", isNone)
    end
    if DoesWindowExist(p .. "CritAnimShakeButton") then
        ButtonSetPressedFlag(p .. "CritAnimShakeButton", isShake)
    end
    if DoesWindowExist(p .. "CritAnimFlashButton") then
        ButtonSetPressedFlag(p .. "CritAnimFlashButton", isFlash)
    end
end

local function SctTextFontComboName()
    return c_SCT_PREFIX .. "RowTextFontCombo"
end

local function SyncSctTextFontCombo()
    local w = SctTextFontComboName()
    if not DoesWindowExist(w) then
        return
    end
    m_refreshing = true
    pcall(function()
        ComboBoxClearMenuItems(w)
        for _, ent in ipairs(CustomUI.SCT.TEXT_FONTS) do
            ComboBoxAddMenuItem(w, ent.label)
        end
        local idx = CustomUI.SCT.GetSettings().textFont or 1
        ComboBoxSetSelectedMenuItem(w, idx)
    end)
    m_refreshing = false
end

local function SyncCritAnimationSpeedSlider()
    local w = c_SCROLL_CHILD .. "GeneralCritAnimSpeed"
    if not DoesWindowExist(w) then
        return
    end
    m_refreshing = true
    pcall(function()
        local spd = (CustomUI.SCT.GetSettings().critAnimationSpeed) or 1.0
        SliderBarSetCurrentPosition(w, CustomUI.SCT.AnimSpeedToSliderPos(spd))
    end)
    m_refreshing = false
end

local function RefreshSctControls(contentPrefix)
    if not contentPrefix or not DoesWindowExist(contentPrefix) then
        return
    end
    SctHideColorPicker()
    local sct = CustomUI.SCT.GetSettings()
    m_refreshing = true
    for _, d in ipairs(CustomUI.SCT.GetSettingsRowDescriptors()) do
        SetupRow(contentPrefix, d.suffix, sct)
    end
    m_refreshing = false
end

local function ParseControlName(winName)
    for _, d in ipairs(CustomUI.SCT.GetSettingsRowDescriptors()) do
        local rowSuffix = d.suffix
        for _, dir in ipairs({ "Out", "In" }) do
            local prefix = "Row" .. rowSuffix .. dir
            if string.find(winName, prefix, 1, true) then
                return rowSuffix, dir
            end
        end
    end
    return nil, nil
end

-- Events often fire with ActiveWindow on a *child* (slider thumb, combo piece, label text).
-- Walk parents until we find the real control window the API expects.
local MAX_PARENT_WALK = 18

local function ResolveSliderBarWindow(startName)
    local w = startName
    for depth = 0, MAX_PARENT_WALK do
        if not w or w == "" then
            break
        end
        local ok = pcall(function()
            SliderBarGetCurrentPosition(w)
        end)
        if ok then
            local rowSuffix, dir = ParseControlName(w)
            if rowSuffix then
                return w, rowSuffix, dir, depth
            end
        end
        w = WindowGetParent(w)
    end
    return nil, nil, nil, nil
end

local function SctResolveColorSwatchFromWindow(startName)
    local w = startName
    for depth = 0, MAX_PARENT_WALK do
        if not w or w == "" then
            break
        end
        local isOut = string.len(w) >= 14
            and string.sub(w, -14) == "OutColorSwatch"
        local isIn = (not isOut) and string.len(w) >= 13
            and string.sub(w, -13) == "InColorSwatch"
        if isOut or isIn then
            local rowSuffix, dir = ParseControlName(w)
            if rowSuffix then
                return w, rowSuffix, dir, depth
            end
        end
        w = WindowGetParent(w)
    end
    return nil, nil, nil, nil
end

local function ResolveFilterCheckWindow(startName)
    local w = startName
    for depth = 0, MAX_PARENT_WALK do
        if not w or w == "" then
            break
        end
        local btn = w .. "Button"
        if DoesWindowExist(btn) then
            local rowSuffix, dir = ParseControlName(w)
            if rowSuffix then
                return w, rowSuffix, dir, depth
            end
        end
        w = WindowGetParent(w)
    end
    return nil, nil, nil, nil
end

local function LogParentChain(startName, tag)
    if not CustomUISettingsWindowTabSCT.DebugInput then
        return
    end
    local w = startName
    for i = 0, MAX_PARENT_WALK do
        if not w or w == "" then
            SctTabDbg(tag .. " chain[" .. i .. "]=<nil>")
            break
        end
        SctTabDbg(tag .. " chain[" .. i .. "]=" .. tostring(w))
        w = WindowGetParent(w)
    end
end

function CustomUISettingsWindowTabSCT.OnUpdateDebugPointer(timePassed)
    -- Runs only the first time the SCT section is visible with a real screen position.
    LogSctLayoutRuntime()
    if not CustomUISettingsWindowTabSCT.DebugPointer then
        return
    end
    if not DoesWindowExist(c_SCT_TAB_ROOT) or not WindowGetShowing(c_SCT_TAB_ROOT) then
        return
    end
    local mo = (SystemData.MouseOverWindow and SystemData.MouseOverWindow.name) or ""
    local act = (SystemData.ActiveWindow and SystemData.ActiveWindow.name) or ""
    if mo == m_pointerLastMouseOver and act == m_pointerLastActive then
        return
    end
    if not PointerLogRelevant(mo, act, m_pointerLastMouseOver, m_pointerLastActive) then
        m_pointerLastMouseOver = mo
        m_pointerLastActive = act
        return
    end
    m_pointerLastMouseOver = mo
    m_pointerLastActive = act

    local rowHit = c_SCT_PREFIX .. "RowHitOutShow"
    local rowHitExists = DoesWindowExist(rowHit)
    SctPointerDbg("MouseOverWindow=" .. tostring(mo) .. " | ActiveWindow=" .. tostring(act))
    if mo ~= "" then
        SctPointerDbg("  MouseOver parent chain: " .. PointerParentSnippet(mo, 8))
    end
    if act ~= "" and act ~= mo then
        SctPointerDbg("  Active parent chain: " .. PointerParentSnippet(act, 8))
    end
    SctPointerDbg("  Expected RowHit OutShow window exists: " .. tostring(rowHit) .. " => " .. tostring(rowHitExists))
end

local m_runtimeDiagLogged = false

-- Diagnostic layout dumper (see README.md). Active only when DebugInput=true so it doesn't spam uilog in normal play.
local function DumpDim(tag, win)
    if not CustomUISettingsWindowTabSCT.DebugInput then return end
    if not DoesWindowExist(win) then
        EmitDebugLine("[CustomUI SCT diag ", tag .. "] " .. win .. " DOES NOT EXIST")
        return
    end
    local okDim, w, h = pcall(WindowGetDimensions, win)
    local okPos, x, y = pcall(WindowGetScreenPosition, win)
    local okShow, showing = pcall(WindowGetShowing, win)
    EmitDebugLine("[CustomUI SCT diag ", string.format("%s] %s exists=true showing=%s dim=%sx%s pos=%s,%s",
        tag, win,
        tostring(okShow and showing),
        tostring(okDim and w), tostring(okDim and h),
        tostring(okPos and x), tostring(okPos and y)))
end

LogSctLayoutRuntime = function()
    if m_runtimeDiagLogged then return end
    if not CustomUISettingsWindowTabSCT.DebugInput then return end
    if not DoesWindowExist(c_SCT_PREFIX) then return end
    local okShow, showing = pcall(WindowGetShowing, c_SCT_PREFIX)
    if not okShow or not showing then return end
    local okPos, _, y = pcall(WindowGetScreenPosition, c_SCT_PREFIX)
    if not okPos or (y or 0) <= 0 then return end
    m_runtimeDiagLogged = true
    DumpDim("runtime", c_SCROLL_CHILD)
    DumpDim("runtime", c_SCROLL_CHILD .. "General")
    DumpDim("runtime", c_SCROLL_CHILD .. "GeneralSCTEnabled")
    DumpDim("runtime", c_SCT_PREFIX)
    DumpDim("runtime", c_SCT_PREFIX .. "Background")
    DumpDim("runtime", c_SCT_PREFIX .. "Title")
    DumpDim("runtime", c_SCT_PREFIX .. "RowHit")
    DumpDim("runtime", c_SCT_PREFIX .. "RowHitOutShow")
end

-- XML sibling anchors (relativeTo="$parentRow*") collapse all rows to the same Y.
-- Re-anchor each row to the SCT window's top with explicit Y offsets that we know work.
local c_SCT_ROW_ORDER = {
    "TextFont",
    "SctColumnHeaders",
    "Hit",
    "Ability",
    "Heal",
    "Block",
    "Parry",
    "Evade",
    "Disrupt",
    "Absorb",
    "Immune",
    "HorizontalBar",
    "SctPointColumnHeaders",
    "XP",
    "Renown",
    "Influence",
}
local c_SCT_ROW_HEIGHT = 37
local c_SCT_FIRST_ROW_Y = 45

local function ReanchorSctRows()
    for i, name in ipairs(c_SCT_ROW_ORDER) do
        local rowWin = c_SCT_PREFIX .. "Row" .. name
        if DoesWindowExist(rowWin) then
            local y = c_SCT_FIRST_ROW_Y + (i - 1) * c_SCT_ROW_HEIGHT
            WindowClearAnchors(rowWin)
            pcall(WindowAddAnchor, rowWin, "topleft", c_SCT_PREFIX, "topleft", 0, y)
            pcall(WindowAddAnchor, rowWin, "topright", c_SCT_PREFIX, "topright", 0, y)
            pcall(WindowForceProcessAnchors, rowWin)
        end
    end
end

function CustomUISettingsWindowTabSCT.Initialize()
    m_pointerLastMouseOver = nil
    m_pointerLastActive = nil
    m_runtimeDiagLogged = false
    pcall(ReanchorSctRows)
    SctEnsureColorPickerGrid()
    SctHideColorPicker()

    DumpDim("init", c_SCROLL_CHILD)
    DumpDim("init", c_SCROLL_CHILD .. "General")
    DumpDim("init", c_SCT_PREFIX)
    DumpDim("init", c_SCT_PREFIX .. "Title")
    DumpDim("init", c_SCT_PREFIX .. "RowHit")
    DumpDim("init", c_SCT_PREFIX .. "RowHitOutShow")

    LabelSetText( c_SCROLL_CHILD .. "GeneralTitle",          L"General" )
    LabelSetText( c_SCROLL_CHILD .. "GeneralSCTEnabledLabel", L"Enabled" )
    ButtonSetCheckButtonFlag( c_SCROLL_CHILD .. "GeneralSCTEnabledButton", true )

    LabelSetText( c_SCROLL_CHILD .. "GeneralCritAnimationLabel", L"Crit Animation" )
    LabelSetText( c_SCROLL_CHILD .. "GeneralAnimationSpeedLabel", L"Animation Speed" )
    LabelSetText( c_SCROLL_CHILD .. "GeneralCritAnimNoneLabel", L"None" )
    LabelSetText( c_SCROLL_CHILD .. "GeneralCritAnimShakeLabel", L"Shake" )
    LabelSetText( c_SCROLL_CHILD .. "GeneralCritAnimFlashLabel", L"Flash" )
    ButtonSetCheckButtonFlag( c_SCROLL_CHILD .. "GeneralCritAnimNoneButton", true )
    ButtonSetCheckButtonFlag( c_SCROLL_CHILD .. "GeneralCritAnimShakeButton", true )
    ButtonSetCheckButtonFlag( c_SCROLL_CHILD .. "GeneralCritAnimFlashButton", true )

    LabelSetText( c_SCT_PREFIX .. "Title", L"Appearance" )
    LabelSetText( c_SCT_PREFIX .. "RowTextFontTextFontLabel", L"Font" )

    local hdr = c_SCT_PREFIX .. "RowSctColumnHeaders"
    LabelSetText( hdr .. "OutShowHdr", L"Show" )
    LabelSetText( hdr .. "OutSizeHdr", L"Size" )
    LabelSetText( hdr .. "OutColorHdr", L"Color" )
    LabelSetText( hdr .. "InShowHdr", L"Show" )
    LabelSetText( hdr .. "InSizeHdr", L"Size" )
    LabelSetText( hdr .. "InColorHdr", L"Color" )

    local pHdr = c_SCT_PREFIX .. "RowSctPointColumnHeaders"
    LabelSetText( pHdr .. "OutShowHdr", L"Show" )
    LabelSetText( pHdr .. "OutSizeHdr", L"Size" )
    LabelSetText( pHdr .. "OutColorHdr", L"Color" )

    LabelSetText( c_SCT_PREFIX .. "RowHitOutShowLabel",       L"Hit" )
    LabelSetText( c_SCT_PREFIX .. "RowAbilityOutShowLabel",   L"Ability" )
    LabelSetText( c_SCT_PREFIX .. "RowHealOutShowLabel",      L"Heal" )
    LabelSetText( c_SCT_PREFIX .. "RowBlockOutShowLabel",     L"Block" )
    LabelSetText( c_SCT_PREFIX .. "RowParryOutShowLabel",     L"Parry" )
    LabelSetText( c_SCT_PREFIX .. "RowEvadeOutShowLabel",     L"Evade" )
    LabelSetText( c_SCT_PREFIX .. "RowDisruptOutShowLabel",   L"Disrupt" )
    LabelSetText( c_SCT_PREFIX .. "RowAbsorbOutShowLabel",    L"Absorb" )
    LabelSetText( c_SCT_PREFIX .. "RowImmuneOutShowLabel",    L"Immune" )
    LabelSetText( c_SCT_PREFIX .. "RowHitInShowLabel",        L"Hit" )
    LabelSetText( c_SCT_PREFIX .. "RowAbilityInShowLabel",    L"Ability" )
    LabelSetText( c_SCT_PREFIX .. "RowHealInShowLabel",       L"Heal" )
    LabelSetText( c_SCT_PREFIX .. "RowBlockInShowLabel",     L"Block" )
    LabelSetText( c_SCT_PREFIX .. "RowParryInShowLabel",      L"Parry" )
    LabelSetText( c_SCT_PREFIX .. "RowEvadeInShowLabel",      L"Evade" )
    LabelSetText( c_SCT_PREFIX .. "RowDisruptInShowLabel",    L"Disrupt" )
    LabelSetText( c_SCT_PREFIX .. "RowAbsorbInShowLabel",     L"Absorb" )
    LabelSetText( c_SCT_PREFIX .. "RowImmuneInShowLabel",     L"Immune" )
    LabelSetText( c_SCT_PREFIX .. "RowXPOutShowLabel",        L"XP" )
    LabelSetText( c_SCT_PREFIX .. "RowRenownOutShowLabel",    L"Renown" )
    LabelSetText( c_SCT_PREFIX .. "RowInfluenceOutShowLabel", L"Influence" )

    SyncSctTextFontCombo()
    SyncCritAnimationSpeedSlider()
end

function CustomUISettingsWindowTabSCT.UpdateSettings()
    SctTabDbg("UpdateSettings: refreshing controls, m_refreshing=" .. tostring(m_refreshing))
    ButtonSetPressedFlag( c_SCROLL_CHILD .. "GeneralSCTEnabledButton", CustomUI.IsComponentEnabled("SCT") )
    local anim = CustomUI.SCT.GetSettings().critAnimation or "shake"
    SyncCritAnimationButtons(anim)
    SyncSctTextFontCombo()
    SyncCritAnimationSpeedSlider()
    RefreshSctControls(c_SCT_PREFIX)
    SctTabDbg("UpdateSettings: done")
end

function CustomUISettingsWindowTabSCT.ApplyCurrent()
end

function CustomUISettingsWindowTabSCT.ResetSettings()
    CustomUI.SCT.ApplySctSettingsTabFullReset()
    BroadcastEvent(SystemData.Events.USER_SETTINGS_CHANGED)
end

function CustomUISettingsWindowTabSCT.OnToggleSCT()
    EA_LabelCheckButton.Toggle()
    local enabled = ButtonGetPressedFlag( c_SCROLL_CHILD .. "GeneralSCTEnabledButton" )
    CustomUI.SetComponentEnabled( "SCT", enabled )
end

function CustomUISettingsWindowTabSCT.OnCritAnimationModeChanged()
    if m_refreshing then
        return
    end
    local w = SystemData.ActiveWindow and SystemData.ActiveWindow.name or ""
    local mode = "shake"
    for _ = 0, 10 do
        if w == nil or w == "" then
            break
        end
        if string.find(w, "CritAnimFlash", 1, true) then
            mode = "flash"
            break
        end
        if string.find(w, "CritAnimShake", 1, true) then
            mode = "shake"
            break
        end
        if string.find(w, "CritAnimNone", 1, true) then
            mode = "none"
            break
        end
        w = WindowGetParent(w)
    end
    CustomUI.SCT.GetSettings().critAnimation = mode
    SyncCritAnimationButtons(mode)
end

function CustomUISettingsWindowTabSCT.OnSctTextFontChanged()
    if m_refreshing then
        return
    end
    local w = SctTextFontComboName()
    if not DoesWindowExist(w) then
        return
    end
    local ok, idx = pcall(ComboBoxGetSelectedMenuItem, w)
    if not ok or type(idx) ~= "number" or idx < 1 or idx > #CustomUI.SCT.TEXT_FONTS then
        return
    end
    CustomUI.SCT.GetSettings().textFont = idx
end

function CustomUISettingsWindowTabSCT.OnCritAnimationSpeedChanged()
    if m_refreshing then
        return
    end
    local w = c_SCROLL_CHILD .. "GeneralCritAnimSpeed"
    if not DoesWindowExist(w) then
        return
    end
    local pos = SliderBarGetCurrentPosition(w)
    local speed = CustomUI.SCT.SliderPosToAnimSpeed(pos)
    CustomUI.SCT.GetSettings().critAnimationSpeed = speed
end

-- Stock TooltipCheckButton uses SettingsWindowTabbed.OnMouseOverTooltipElement; this is the CustomUI equivalent (extend for real tooltips).
function CustomUISettingsWindowTabSCT.OnMouseOverFilterCheckButton()
    if CustomUISettingsWindowTabSCT.DebugPointer then
        local w = SystemData.MouseOverWindow and SystemData.MouseOverWindow.name
        SctPointerDbg("OnMouseOverFilterCheckButton MouseOverWindow=" .. tostring(w))
    end
end

function CustomUISettingsWindowTabSCT.OnDebugScrollChildClick()
    SctTabDbg("OnDebugScrollChildClick: bubbled click on scroll child (active=" .. tostring(SystemData.ActiveWindow.name) .. ")")
end

function CustomUISettingsWindowTabSCT.OnFilterChanged()
    if m_refreshing then
        SctTabDbg("OnFilterChanged: skipped (m_refreshing)")
        return
    end
    local active = SystemData.ActiveWindow.name
    local winName, rowSuffix, dir, depth = ResolveFilterCheckWindow(active)
    SctTabDbg("OnFilterChanged: active=" .. tostring(active) .. " resolved=" .. tostring(winName) .. " row=" .. tostring(rowSuffix) .. " dir=" .. tostring(dir) .. " depth=" .. tostring(depth))
    if not rowSuffix or not winName then
        LogParentChain(active, "OnFilterChanged: UNRESOLVED")
        return
    end
    local info = ROW_BY_SUFFIX[rowSuffix]
    if not info then return end
    if dir == "In" and not info.hasIncoming then return end

    local sct = CustomUI.SCT.GetSettings()
    local filterKey = "show" .. info.key
    if dir == "Out" then
        local prev = sct.outgoing.filters[filterKey]
        local new = (prev == false)
        sct.outgoing.filters[filterKey] = new
        ButtonSetPressedFlag(winName .. "Button", new)
    else
        local prev = sct.incoming.filters[filterKey]
        local new = (prev == false)
        sct.incoming.filters[filterKey] = new
        ButtonSetPressedFlag(winName .. "Button", new)
    end
end

function CustomUISettingsWindowTabSCT.OnSizeChanged()
    if m_refreshing then
        SctTabDbg("OnSizeChanged: skipped (m_refreshing)")
        return
    end
    local active = SystemData.ActiveWindow.name
    local winName, rowSuffix, dir, depth = ResolveSliderBarWindow(active)
    if not rowSuffix or not winName then
        SctTabDbg("OnSizeChanged: active=" .. tostring(active) .. " UNRESOLVED")
        LogParentChain(active, "OnSizeChanged")
        return
    end
    local info = ROW_BY_SUFFIX[rowSuffix]
    if not info then return end
    if dir == "In" and not info.hasIncoming then
        SctTabDbg("OnSizeChanged: skip (no incoming row)")
        return
    end

    local sct = CustomUI.SCT.GetSettings()
    local pos = SliderBarGetCurrentPosition(winName)
    SctTabDbg("OnSizeChanged: active=" .. tostring(active) .. " resolved=" .. tostring(winName) .. " row=" .. tostring(rowSuffix) .. " dir=" .. tostring(dir) .. " depth=" .. tostring(depth) .. " pos=" .. tostring(pos))
    local scale = CustomUI.SCT.SliderPosToScale(pos)
    SctTabDbg("OnSizeChanged: applied scale=" .. tostring(scale) .. " key=" .. tostring(info.key))
    if dir == "Out" then
        sct.outgoing.size[info.key] = scale
    else
        sct.incoming.size[info.key] = scale
    end
end

function CustomUISettingsWindowTabSCT.OnSctColorSwatchClick()
    if m_refreshing then
        return
    end
    local active = SctClickWindowNameForColorButton()
    local anchorSwatch, rowSuffix, dir = SctResolveColorSwatchFromWindow(active)
    if not anchorSwatch or not rowSuffix or not dir then
        SctTabDbg("OnSctColorSwatchClick: UNRESOLVED active=" .. tostring(active))
        return
    end
    local info = ROW_BY_SUFFIX[rowSuffix]
    if not info then
        return
    end
    if dir == "In" and not info.hasIncoming then
        return
    end
    SctTabDbg("OnSctColorSwatchClick: anchor=" .. tostring(anchorSwatch) .. " key=" .. tostring(info.key) .. " dir=" .. tostring(dir))

    local wasOpen = m_sctColorPickerContext
        and m_sctColorPickerContext.anchorSwatch == anchorSwatch
        and DoesWindowExist(c_SCT_COLOR_PICKER_HOST)
    local showing = false
    if wasOpen and DoesWindowExist(c_SCT_COLOR_PICKER_HOST) then
        pcall(function()
            showing = WindowGetShowing(c_SCT_COLOR_PICKER_HOST) == true
        end)
    end
    if wasOpen and showing then
        SctHideColorPicker()
        return
    end

    m_sctColorPickerContext = { key = info.key, dir = dir, anchorSwatch = anchorSwatch }
    SctEnsureColorPickerGrid()
    if not DoesWindowExist(c_SCT_COLOR_PICKER) or not DoesWindowExist(c_SCT_COLOR_PICKER_HOST) then
        return
    end
    -- Parent one level above the settings root so the palette is not clipped to the 900x800 client when it overlaps the screen edge.
    pcall(function()
        local p = WindowGetParent(c_SCT_SETTINGS_ROOT)
        if p and p ~= L"" then
            WindowSetParent(c_SCT_COLOR_PICKER_HOST, p)
        end
    end)
    -- README / engine: tleft↔tright can place the host on the wrong side; tleft↔tleft + fixed dx is unambiguous
    -- (swatch 20px + 6px gap, see c_SCT_SWATCH_PICKER_OFF_X).
    WindowClearAnchors(c_SCT_COLOR_PICKER_HOST)
    pcall(function()
        WindowAddAnchor(c_SCT_COLOR_PICKER_HOST, "topleft", anchorSwatch, "topleft", c_SCT_SWATCH_PICKER_OFF_X, 0)
    end)
    pcall(function()
        WindowSetDimensions(c_SCT_COLOR_PICKER_HOST, c_SCT_COLOR_PICKER_HOST_W, c_SCT_COLOR_PICKER_HOST_H)
    end)
    pcall(function()
        WindowForceProcessAnchors(c_SCT_COLOR_PICKER_HOST)
    end)
    pcall(function()
        WindowSetShowing(c_SCT_COLOR_PICKER_HOST, true)
    end)
end

function CustomUISettingsWindowTabSCT.OnSctColorPickerLButtonUp(flags, x, y)
    if m_refreshing or not m_sctColorPickerContext then
        return
    end
    if not DoesWindowExist(c_SCT_COLOR_PICKER) then
        SctHideColorPicker()
        return
    end
    local color = ColorPickerGetColorAtPoint(c_SCT_COLOR_PICKER, x, y)
    if not color then
        return
    end
    local idx = color.id
    if type(idx) ~= "number" or idx < 2 or idx > #CustomUI.SCT.COLOR_OPTIONS then
        return
    end
    local ctx = m_sctColorPickerContext
    local sct = CustomUI.SCT.GetSettings()
    SctTabDbg("OnSctColorPickerLButtonUp: idx=" .. tostring(idx) .. " key=" .. tostring(ctx.key))
    if ctx.dir == "Out" then
        sct.outgoing.color[ctx.key] = idx
    else
        sct.incoming.color[ctx.key] = idx
    end
    SctUpdateColorSwatch(ctx.anchorSwatch, idx, ctx.key, ctx.dir == "In")
    SctHideColorPicker()
end

function CustomUISettingsWindowTabSCT.OnSctColorPickerRButtonUp()
    if m_refreshing or not m_sctColorPickerContext then
        SctHideColorPicker()
        return
    end
    local ctx = m_sctColorPickerContext
    local sct = CustomUI.SCT.GetSettings()
    if ctx.dir == "Out" then
        sct.outgoing.color[ctx.key] = 1
    else
        sct.incoming.color[ctx.key] = 1
    end
    SctUpdateColorSwatch(ctx.anchorSwatch, 1, ctx.key, ctx.dir == "In")
    SctHideColorPicker()
end

function CustomUISettingsWindowTabSCT.OnSctColorPickerDefaultButtonLButtonUp()
    if m_refreshing or not m_sctColorPickerContext then
        return
    end
    CustomUISettingsWindowTabSCT.OnSctColorPickerRButtonUp()
end
