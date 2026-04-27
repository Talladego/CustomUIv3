----------------------------------------------------------------
-- CustomUI.SCT — Settings helpers (SCT; not a View/ .lua)
-- Responsibilities: default schema, GetSettings, migrations, and pure helpers (colors, fonts
--   descriptors) used by SCT runtime modules and CustomUISettingsWindow tabs. No RegisterComponent
--   here, no engine hooks — data and defaults only. Call sites must not add saved-variable
--   paths to a specific settings window; tabs live in the CustomUISettingsWindow addon.
if not CustomUI.SCT then CustomUI.SCT = {} end
-- Mirror SCT hard failures to LogLuaMessage + uilog text log (see SCTAnchors). Default on.
-- Legacy: old saves used `m_uilog`; when nil we migrate.
if CustomUI.SCT.m_sctFileLog == nil then
    if type(CustomUI.SCT.m_uilog) == "boolean" then
        CustomUI.SCT.m_sctFileLog = CustomUI.SCT.m_uilog
    else
        CustomUI.SCT.m_sctFileLog = true
    end
end

function CustomUI.SCT.SetSctFileLog(enabled)
    CustomUI.SCT.m_sctFileLog = enabled == true
    return CustomUI.SCT.m_sctFileLog
end

-- Back compat for saved vars / old scripts; prefer `SetSctFileLog`.
CustomUI.SCT.SetUilogLogging = CustomUI.SCT.SetSctFileLog

-- Shared by SCT runtime modules, SCTController, and external settings UIs.
----------------------------------------------------------------

CustomUI.SCT.COMBAT_TYPE_KEYS = { "Hit", "Ability", "Heal", "Block", "Parry", "Evade", "Disrupt", "Absorb", "Immune" }
CustomUI.SCT.POINT_TYPE_KEYS  = { "XP", "Renown", "Influence" }

-- Setters are declared before the implementation block for IsAtDefault / notifyChange.
-- Forward declare so setter bodies bind this local instead of looking for a global.
local notifyChange

-- Discrete size ticks used by the settings UI (slider maps to these values).
CustomUI.SCT.TICK_SCALES = { 0.75, 0.875, 1.0, 1.25, 1.75 }

-- Crit-only size multiplier. Applied on top of the per-event Size slider (multiplicative).
CustomUI.SCT.CRIT_SIZE_TICK_SCALES = { 1.0, 1.15, 1.3, 1.5, 1.75 }

-- [1] = event-text font (see CustomUI_EventTextLabel.xml / stock EA_Window_EventTextLabel); 2+ match wsct WSCT.LOCALS.FONTS order.
CustomUI.SCT.TEXT_FONTS = {
    { font = "font_default_text_large",     label = L"Default" },
    { font = "font_journal_text_huge",     label = L"Cronos Pro" },
    { font = "font_clear_large",            label = L"Myriad Pro" },
    { font = "font_clear_large_bold",       label = L"Myriad Pro Bold" },
    { font = "font_journal_sub_heading",   label = L"Age Of Reckoning" },
    { font = "font_default_war_heading",    label = L"Age Of Reckoning Outline" },
    { font = "font_heading_small_no_shadow", label = L"Caslon" },
    { font = "font_default_medium_heading",  label = L"Caslon Outline" },
    { font = "font_heading_default",        label = L"Caslon Shadow" },
}

----------------------------------------------------------------
-- Row model for external settings UIs (suffix matches window Row<Suffix> names).
----------------------------------------------------------------

function CustomUI.SCT.GetSettingsRowDescriptors()
    local rows = {}
    for _, k in ipairs(CustomUI.SCT.COMBAT_TYPE_KEYS) do
        rows[#rows + 1] = { suffix = k, key = k, hasIncoming = true }
    end
    for _, k in ipairs(CustomUI.SCT.POINT_TYPE_KEYS) do
        rows[#rows + 1] = { suffix = k, key = k, hasIncoming = false }
    end
    return rows
end

-- Normalized slider position (0–1) ↔ discrete scale from TICK_SCALES.
function CustomUI.SCT.ScaleToSliderPos(scale)
    local scales = CustomUI.SCT.TICK_SCALES
    local n = #scales
    if n <= 1 then
        return 0
    end
    local best, idx = math.huge, 1
    for i, s in ipairs(scales) do
        local d = math.abs(scale - s)
        if d < best then
            best, idx = d, i
        end
    end
    return (idx - 1) / (n - 1)
end

function CustomUI.SCT.SliderPosToScale(pos)
    local scales = CustomUI.SCT.TICK_SCALES
    local n = #scales
    local idx = math.floor(pos * (n - 1) + 0.5) + 1
    idx = math.max(1, math.min(n, idx))
    return scales[idx]
end

function CustomUI.SCT.CritSizeToSliderPos(scale)
    local scales = CustomUI.SCT.CRIT_SIZE_TICK_SCALES
    local n = #scales
    if n <= 1 then
        return 0
    end
    local best, idx = math.huge, 1
    for i, s in ipairs(scales) do
        local d = math.abs(scale - s)
        if d < best then
            best, idx = d, i
        end
    end
    return (idx - 1) / (n - 1)
end

function CustomUI.SCT.SliderPosToCritSize(pos)
    local scales = CustomUI.SCT.CRIT_SIZE_TICK_SCALES
    local n = #scales
    local idx = math.floor(pos * (n - 1) + 0.5) + 1
    idx = math.max(1, math.min(n, idx))
    return scales[idx]
end

----------------------------------------------------------------
-- X offsets (pixels) — absolute category positions relative to the world-object anchor.
-- Defaults are 0 (centered on the anchor). Exposed as sliders in CustomUISettingsWindow.
----------------------------------------------------------------

local X_OFFSET_MIN = -100
local X_OFFSET_MAX = 100

-- Y offsets (pixels) — category vertical offsets relative to stock animation Y.
local Y_OFFSET_MIN = -200
local Y_OFFSET_MAX = 200

function CustomUI.SCT.XOffsetToSliderPos(px)
    if type(px) ~= "number" or px ~= px then px = 0 end
    if px < X_OFFSET_MIN then px = X_OFFSET_MIN end
    if px > X_OFFSET_MAX then px = X_OFFSET_MAX end
    -- SliderBar positions are normalized [0,1] in this UI.
    local denom = (X_OFFSET_MAX - X_OFFSET_MIN)
    if denom <= 0 then
        return 0
    end
    return (px - X_OFFSET_MIN) / denom
end

function CustomUI.SCT.SliderPosToXOffset(pos)
    if type(pos) ~= "number" or pos ~= pos then pos = 0.5 end
    if pos < 0 then pos = 0 end
    if pos > 1 then pos = 1 end
    local px = X_OFFSET_MIN + ((X_OFFSET_MAX - X_OFFSET_MIN) * pos)
    -- Keep it integer pixels for stable window positioning.
    return math.floor(px + 0.5)
end

function CustomUI.SCT.YOffsetToSliderPos(px)
    if type(px) ~= "number" or px ~= px then px = 0 end
    if px < Y_OFFSET_MIN then px = Y_OFFSET_MIN end
    if px > Y_OFFSET_MAX then px = Y_OFFSET_MAX end
    local denom = (Y_OFFSET_MAX - Y_OFFSET_MIN)
    if denom <= 0 then
        return 0
    end
    return (px - Y_OFFSET_MIN) / denom
end

function CustomUI.SCT.SliderPosToYOffset(pos)
    if type(pos) ~= "number" or pos ~= pos then pos = 0.5 end
    if pos < 0 then pos = 0 end
    if pos > 1 then pos = 1 end
    local px = Y_OFFSET_MIN + ((Y_OFFSET_MAX - Y_OFFSET_MIN) * pos)
    return math.floor(px + 0.5)
end

-- Back compat for old settings-window code paths; per-category offsets use the generic names.
CustomUI.SCT.BaseXOffsetToSliderPos = CustomUI.SCT.XOffsetToSliderPos
CustomUI.SCT.SliderPosToBaseXOffset = CustomUI.SCT.SliderPosToXOffset

-- Predefined color palette (index 1 = Default = keep engine color; not shown in the 5x8 ColorPicker—use R-click on the palette for Default).
-- Indices 2+ are 5 columns x 8 rows in row-major order, one base hue per row: [dark, dark, base, light, light].
-- Row 1: greys; rows 2–8: Red … Purple with full-strength center swatches, shades from lerp to black/white.
CustomUI.SCT.COLOR_PICKER_COLUMNS = 5
-- Bump when palette entries change (forces ColorPicker grid rebuild in settings UI).
CustomUI.SCT.COLOR_PALETTE_REVISION = 6
CustomUI.SCT.COLOR_OPTIONS = (function()
    local function lerpToWhite(r, g, b, t)
        t = t or 0
        return math.floor(r + (255 - r) * t + 0.5), math.floor(g + (255 - g) * t + 0.5), math.floor(b + (255 - b) * t + 0.5)
    end
    local function lerpToBlack(r, g, b, t)
        t = t or 0
        return math.floor(r * (1 - t) + 0.5), math.floor(g * (1 - t) + 0.5), math.floor(b * (1 - t) + 0.5)
    end
    local function pack(r, g, b)
        return { math.max(0, math.min(255, r)), math.max(0, math.min(255, g)), math.max(0, math.min(255, b)) }
    end
    -- One row: dark2, dark1, base, light1, light2 (left  right). Darks / lights are lerped from the base.
    local function row5Chromatic(label, r, g, b)
        local r1, g1, b1 = lerpToBlack(r, g, b, 0.62)
        local r2, g2, b2 = lerpToBlack(r, g, b, 0.32)
        local r3, g3, b3 = r, g, b
        local r4, g4, b4 = lerpToWhite(r, g, b, 0.32)
        local r5, g5, b5 = lerpToWhite(r, g, b, 0.62)
        return {
            { name = label .. L" 1", rgb = pack(r1, g1, b1) },
            { name = label .. L" 2", rgb = pack(r2, g2, b2) },
            { name = label .. L" 3", rgb = pack(r3, g3, b3) },
            { name = label .. L" 4", rgb = pack(r4, g4, b4) },
            { name = label .. L" 5", rgb = pack(r5, g5, b5) },
        }
    end
    -- Grey scale: dark grey (not near-black) through pure white, 5 even steps.
    local function row5Grey()
        return {
            { name = L"Gray 1", rgb = pack(24, 24, 24) },
            { name = L"Gray 2", rgb = pack(82, 82, 82) },
            { name = L"Gray 3", rgb = pack(140, 140, 140) },
            { name = L"Gray 4", rgb = pack(197, 197, 197) },
            { name = L"Gray 5", rgb = pack(255, 255, 255) },
        }
    end
    local t = { { name = L"Default", rgb = nil } }
    for _, o in ipairs(row5Grey()) do
        t[#t + 1] = o
    end
    for _, row in ipairs({
        { L"Red",    255,   0,   0 },
        { L"Orange", 255, 128,   0 },
        { L"Yellow", 255, 255,   0 },
        { L"Green",    0, 255,   0 },
        { L"Cyan",     0, 255, 255 },
        { L"Blue",     0,   0, 255 },
        { L"Purple", 230,   0, 255 },
    }) do
        for _, o in ipairs(row5Chromatic(row[1], row[2], row[3], row[4])) do
            t[#t + 1] = o
        end
    end
    return t
end)()

----------------------------------------------------------------
-- Settings() — private: returns validated/migrated `CustomUI.Settings.SCT`.
-- Direct `CustomUI.Settings.SCT` access exists only here (plan §5 / Step 1 gate).
----------------------------------------------------------------

local function isPointTypeKey(key)
    for _, pk in ipairs(CustomUI.SCT.POINT_TYPE_KEYS) do
        if pk == key then
            return true
        end
    end
    return false
end

local function isValidSettingsKey(key)
    for _, k in ipairs(CustomUI.SCT.COMBAT_TYPE_KEYS) do
        if k == key then
            return true
        end
    end
    for _, k in ipairs(CustomUI.SCT.POINT_TYPE_KEYS) do
        if k == key then
            return true
        end
    end
    return false
end

local function Settings()
    CustomUI.Settings.SCT          = CustomUI.Settings.SCT          or {}
    local v = CustomUI.Settings.SCT
    v.outgoing = v.outgoing or { filters = {}, size = {}, color = {} }
    v.incoming = v.incoming or { filters = {}, size = {}, color = {} }

    for _, k in ipairs(CustomUI.SCT.COMBAT_TYPE_KEYS) do
        if v.outgoing.filters["show"..k] == nil then v.outgoing.filters["show"..k] = true end
        if v.incoming.filters["show"..k] == nil then v.incoming.filters["show"..k] = true end
        if v.outgoing.size[k]            == nil then v.outgoing.size[k]            = 1.0  end
        if v.incoming.size[k]            == nil then v.incoming.size[k]            = 1.0  end
        if (v.outgoing.color[k] or 0) < 1 then v.outgoing.color[k] = 1 end
        if (v.incoming.color[k] or 0) < 1 then v.incoming.color[k] = 1 end
    end
    for _, k in ipairs(CustomUI.SCT.POINT_TYPE_KEYS) do
        if v.outgoing.filters["show"..k] == nil then v.outgoing.filters["show"..k] = true end
        if v.outgoing.size[k]            == nil then v.outgoing.size[k]            = 1.0  end
        if (v.outgoing.color[k] or 0) < 1 then v.outgoing.color[k] = 1 end
    end

    v.customColor          = v.customColor          or {}
    v.customColor.outgoing = v.customColor.outgoing or {}
    v.customColor.incoming = v.customColor.incoming or {}

    -- Critical hit presentation (v2): independent toggles — Flash (color) can combine with Shake or Pulse; Shake and Pulse are mutually exclusive.
    if v.critAnimV2 ~= true then
        local o = v.critAnimation
        v.critAnimShake = false
        v.critAnimPulse = false
        v.critAnimFlash = false
        if o == "none" then
            -- leave all off
        elseif o == "pulse" then
            v.critAnimPulse = true
        elseif o == "flash" then
            v.critAnimFlash = true
        else
            -- "shake", nil, or unknown (legacy default was shake)
            v.critAnimShake = true
        end
        v.critAnimV2 = true
    end
    if v.critAnimShake and v.critAnimPulse then
        v.critAnimPulse = false
    end
    v.critAnimShake = v.critAnimShake == true
    v.critAnimPulse = v.critAnimPulse == true and not v.critAnimShake
    v.critAnimFlash = v.critAnimFlash == true

    -- Crit size scale (multiplicative with per-event scale). Discrete ticks.
    if type(v.critSizeScale) ~= "number" or v.critSizeScale ~= v.critSizeScale then
        v.critSizeScale = 1.0
    end
    v.critSizeScale = CustomUI.SCT.SliderPosToCritSize(CustomUI.SCT.CritSizeToSliderPos(v.critSizeScale))

    -- Optional ability icon next to combat event text.
    if v.showAbilityIcon == nil then
        v.showAbilityIcon = false
    end
    v.showAbilityIcon = v.showAbilityIcon == true

    -- Per-category X offsets (pixels): absolute positions relative to the world-object anchor.
    if type(v.offsets) ~= "table" then v.offsets = {} end
    if type(v.offsets.outgoing) ~= "table" then v.offsets.outgoing = {} end
    if type(v.offsets.incoming) ~= "table" then v.offsets.incoming = {} end
    if type(v.offsets.points) ~= "table" then v.offsets.points = {} end
    v.offsets.outgoing.x = CustomUI.SCT.SliderPosToXOffset(CustomUI.SCT.XOffsetToSliderPos(v.offsets.outgoing.x or 0))
    v.offsets.incoming.x = CustomUI.SCT.SliderPosToXOffset(CustomUI.SCT.XOffsetToSliderPos(v.offsets.incoming.x or 0))
    v.offsets.points.x   = CustomUI.SCT.SliderPosToXOffset(CustomUI.SCT.XOffsetToSliderPos(v.offsets.points.x or 0))
    v.offsets.outgoing.y = CustomUI.SCT.SliderPosToYOffset(CustomUI.SCT.YOffsetToSliderPos(v.offsets.outgoing.y or 0))
    v.offsets.incoming.y = CustomUI.SCT.SliderPosToYOffset(CustomUI.SCT.YOffsetToSliderPos(v.offsets.incoming.y or 0))
    v.offsets.points.y   = CustomUI.SCT.SliderPosToYOffset(CustomUI.SCT.YOffsetToSliderPos(v.offsets.points.y or 0))

    -- LEGACY (v2 SCT, 2026-04-25): old global X offset no longer applied.
    if type(v.baseXOffset) ~= "number" or v.baseXOffset ~= v.baseXOffset then
        v.baseXOffset = 0
    end
    v.baseXOffset = CustomUI.SCT.SliderPosToXOffset(CustomUI.SCT.XOffsetToSliderPos(v.baseXOffset))

    -- textFont: 1 = Default (stock), 2–9 = former 8 wsct options. Migrate old 1–8 → 2–9 when Default row was added.
    local nFonts = #CustomUI.SCT.TEXT_FONTS
    if v.sctTextFontV2 ~= true then
        if type(v.textFont) == "number" and v.textFont == math.floor(v.textFont) and v.textFont >= 1 and v.textFont <= 8 then
            v.textFont = v.textFont + 1
        end
        v.sctTextFontV2 = true
    end
    if type(v.textFont) ~= "number" or v.textFont < 1 or v.textFont > nFonts or v.textFont ~= math.floor(v.textFont) then
        v.textFont = 1
    end

    return v
end

-- Live settings table; same object as `Settings()` (for runtime and legacy call sites).
function CustomUI.SCT.GetSettings()
    return Settings()
end

----------------------------------------------------------------
-- Public API (plan §5) — thin wrappers; CustomUISettingsWindow migrates to these in Step 2.
----------------------------------------------------------------

function CustomUI.SCT.GetCombatTypeKeys()
    return CustomUI.SCT.COMBAT_TYPE_KEYS
end

function CustomUI.SCT.GetPointTypeKeys()
    return CustomUI.SCT.POINT_TYPE_KEYS
end

function CustomUI.SCT.GetTextFonts()
    return CustomUI.SCT.TEXT_FONTS
end

function CustomUI.SCT.GetColorOptions()
    return CustomUI.SCT.COLOR_OPTIONS
end

function CustomUI.SCT.GetTickScales()
    return CustomUI.SCT.TICK_SCALES
end

function CustomUI.SCT.GetCritTickScales()
    return CustomUI.SCT.CRIT_SIZE_TICK_SCALES
end

function CustomUI.SCT.GetColorPaletteRevision()
    return CustomUI.SCT.COLOR_PALETTE_REVISION
end

function CustomUI.SCT.GetColorPickerColumns()
    return CustomUI.SCT.COLOR_PICKER_COLUMNS
end

function CustomUI.SCT.GetSize(direction, key)
    local v = Settings()
    if not isValidSettingsKey(key) then
        return 1.0
    end
    if isPointTypeKey(key) then
        return (v.outgoing.size and v.outgoing.size[key]) or 1.0
    end
    if direction ~= "outgoing" and direction ~= "incoming" then
        return 1.0
    end
    return (v[direction].size and v[direction].size[key]) or 1.0
end

function CustomUI.SCT.GetColorIndex(direction, key)
    local v = Settings()
    if not isValidSettingsKey(key) then
        return 1
    end
    if isPointTypeKey(key) and direction == "incoming" then
        return 1
    end
    if direction ~= "outgoing" and direction ~= "incoming" then
        return 1
    end
    local c = v[direction].color and v[direction].color[key]
    if type(c) ~= "number" or c < 1 then
        return 1
    end
    return c
end

function CustomUI.SCT.GetCustomColor(direction, key)
    local v = Settings()
    if not isValidSettingsKey(key) then
        return nil
    end
    if isPointTypeKey(key) and direction == "incoming" then
        return nil
    end
    if direction ~= "outgoing" and direction ~= "incoming" then
        return nil
    end
    local t = v.customColor and v.customColor[direction] and v.customColor[direction][key]
    if type(t) ~= "table" or t[1] == nil then
        return nil
    end
    return { t[1], t[2], t[3] }
end

function CustomUI.SCT.GetFilter(direction, key)
    local v = Settings()
    if not isValidSettingsKey(key) then
        return true
    end
    if isPointTypeKey(key) and direction == "incoming" then
        return true
    end
    if direction ~= "outgoing" and direction ~= "incoming" then
        return true
    end
    local fk = "show" .. key
    local f = v[direction].filters and v[direction].filters[fk]
    return f ~= false
end

function CustomUI.SCT.GetCritFlags()
    local s = Settings()
    local sh = s.critAnimShake == true
    local pu = s.critAnimPulse == true
    local cf = s.critAnimFlash == true
    if sh then
        pu = false
    end
    return sh, pu, cf
end

function CustomUI.SCT.GetCritSizeScale()
    return Settings().critSizeScale or 1.0
end

function CustomUI.SCT.GetTextFontIndex()
    return Settings().textFont or 1
end

function CustomUI.SCT.GetShowAbilityIcon()
    return Settings().showAbilityIcon == true
end

function CustomUI.SCT.GetBaseXOffset()
    return Settings().baseXOffset or 0
end

local function isValidOffsetCategory(category)
    return category == "outgoing" or category == "incoming" or category == "points"
end

function CustomUI.SCT.GetXOffset(category)
    if not isValidOffsetCategory(category) then
        return 0
    end
    local offsets = Settings().offsets or {}
    local t = offsets[category]
    return (type(t) == "table" and type(t.x) == "number") and t.x or 0
end

function CustomUI.SCT.GetYOffset(category)
    if not isValidOffsetCategory(category) then
        return 0
    end
    local offsets = Settings().offsets or {}
    local t = offsets[category]
    return (type(t) == "table" and type(t.y) == "number") and t.y or 0
end

function CustomUI.SCT.SetXOffset(category, px)
    if not isValidOffsetCategory(category) or type(px) ~= "number" or px ~= px then
        return
    end
    local v = Settings()
    v.offsets = v.offsets or {}
    v.offsets[category] = v.offsets[category] or {}
    v.offsets[category].x = CustomUI.SCT.SliderPosToXOffset(CustomUI.SCT.XOffsetToSliderPos(px))
    notifyChange()
end

function CustomUI.SCT.SetYOffset(category, px)
    if not isValidOffsetCategory(category) or type(px) ~= "number" or px ~= px then
        return
    end
    local v = Settings()
    v.offsets = v.offsets or {}
    v.offsets[category] = v.offsets[category] or {}
    v.offsets[category].y = CustomUI.SCT.SliderPosToYOffset(CustomUI.SCT.YOffsetToSliderPos(px))
    notifyChange()
end

function CustomUI.SCT.SetSize(direction, key, scale)
    if not isValidSettingsKey(key) or type(scale) ~= "number" or scale ~= scale then
        return
    end
    local v = Settings()
    if isPointTypeKey(key) then
        scale = CustomUI.SCT.SliderPosToScale(CustomUI.SCT.ScaleToSliderPos(scale))
        v.outgoing.size[key] = scale
        notifyChange()
        return
    end
    assert(direction == "outgoing" or direction == "incoming", "bad direction")
    if not v[direction] or not v[direction].size then
        return
    end
    scale = CustomUI.SCT.SliderPosToScale(CustomUI.SCT.ScaleToSliderPos(scale))
    v[direction].size[key] = scale
    notifyChange()
end

function CustomUI.SCT.SetColorIndex(direction, key, idx)
    if not isValidSettingsKey(key) or type(idx) ~= "number" then
        return
    end
    if isPointTypeKey(key) and direction == "incoming" then
        return
    end
    assert(direction == "outgoing" or direction == "incoming", "bad direction")
    local v = Settings()
    idx = math.floor(idx + 0.5)
    local n = #(CustomUI.SCT.COLOR_OPTIONS or {})
    if idx < 1 then
        idx = 1
    end
    if idx > n then
        idx = n
    end
    v[direction].color[key] = idx
    notifyChange()
end

function CustomUI.SCT.SetCustomColor(direction, key, rgb_or_nil)
    if not isValidSettingsKey(key) then
        return
    end
    if isPointTypeKey(key) and direction == "incoming" then
        return
    end
    assert(direction == "outgoing" or direction == "incoming", "bad direction")
    local v = Settings()
    v.customColor[direction] = v.customColor[direction] or {}
    if rgb_or_nil == nil then
        v.customColor[direction][key] = nil
        notifyChange()
        return
    end
    if type(rgb_or_nil) ~= "table" then
        return
    end
    local r, g, b = rgb_or_nil[1] or rgb_or_nil.r, rgb_or_nil[2] or rgb_or_nil.g, rgb_or_nil[3] or rgb_or_nil.b
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then
        return
    end
    v.customColor[direction][key] = {
        math.max(0, math.min(255, math.floor(r + 0.5))),
        math.max(0, math.min(255, math.floor(g + 0.5))),
        math.max(0, math.min(255, math.floor(b + 0.5))),
    }
    notifyChange()
end

function CustomUI.SCT.SetFilter(direction, key, boolVal)
    if not isValidSettingsKey(key) then
        return
    end
    if isPointTypeKey(key) and direction == "incoming" then
        return
    end
    assert(direction == "outgoing" or direction == "incoming", "bad direction")
    local v = Settings()
    local fk = "show" .. key
    v[direction].filters[fk] = boolVal == true
    notifyChange()
end

function CustomUI.SCT.SetCritFlags(shake, pulse, flash)
    local v = Settings()
    v.critAnimV2 = true
    local sh = shake == true
    local pu = pulse == true and not sh
    local cf = flash == true
    v.critAnimShake = sh
    v.critAnimPulse = pu
    v.critAnimFlash = cf
    notifyChange()
end

function CustomUI.SCT.SetCritSizeScale(scale)
    if type(scale) ~= "number" or scale ~= scale then
        return
    end
    local v = Settings()
    v.critSizeScale = CustomUI.SCT.SliderPosToCritSize(CustomUI.SCT.CritSizeToSliderPos(scale))
    notifyChange()
end

function CustomUI.SCT.SetTextFontIndex(idx)
    if type(idx) ~= "number" or idx ~= math.floor(idx) then
        return
    end
    local nFonts = #CustomUI.SCT.TEXT_FONTS
    if idx < 1 or idx > nFonts then
        return
    end
    Settings().textFont = idx
    notifyChange()
end

function CustomUI.SCT.SetShowAbilityIcon(enabled)
    Settings().showAbilityIcon = enabled == true
    notifyChange()
end

-- LEGACY (v2 SCT, 2026-04-25): baseXOffset no longer applied.
-- Field preserved so old saves load without error. Setter is a no-op.
function CustomUI.SCT.SetBaseXOffset(_px)
    -- no-op
end

-- Returns shake, pulse, color-flash (all booleans). Shake and pulse are mutually exclusive after GetSettings().
function CustomUI.SCT.GetCritAnimFlags()
    return CustomUI.SCT.GetCritFlags()
end

function CustomUI.SCT.GetTextFontName()
    local v = Settings()
    local idx = v.textFont
    local t = CustomUI.SCT.TEXT_FONTS
    if type(idx) ~= "number" or idx < 1 or idx > #t then
        idx = 1
    end
    local e = t[idx]
    return (e and e.font) or "font_default_text_large"
end

-- All preset color indices to 1 (engine DefaultColor per event) and clear per-row custom RGB overrides.
function CustomUI.SCT.ResetColorsToStockDefault(skipNotify)
    local v = Settings()
    for _, k in ipairs(CustomUI.SCT.COMBAT_TYPE_KEYS) do
        v.outgoing.color[k] = 1
        v.incoming.color[k] = 1
        if v.customColor.outgoing then
            v.customColor.outgoing[k] = nil
        end
        if v.customColor.incoming then
            v.customColor.incoming[k] = nil
        end
    end
    for _, k in ipairs(CustomUI.SCT.POINT_TYPE_KEYS) do
        v.outgoing.color[k] = 1
        if v.customColor.outgoing then
            v.customColor.outgoing[k] = nil
        end
    end
    if skipNotify ~= true then
        notifyChange()
    end
end

-- Middle discrete text-size tick (see TICK_SCALES / ScaleToSliderPos).
function CustomUI.SCT.GetMiddleTextSizeScale()
    local scales = CustomUI.SCT.TICK_SCALES
    local n = #scales
    if n < 1 then
        return 1.0
    end
    return scales[math.ceil(n / 2)]
end

function CustomUI.SCT.GetMiddleCritSizeScale()
    local scales = CustomUI.SCT.CRIT_SIZE_TICK_SCALES
    local n = #scales
    if n < 1 then
        return 1.0
    end
    return scales[math.ceil(n / 2)]
end

-- SCT settings tab "Reset": restore stock-equivalent defaults so IsAtDefault() becomes true.
function CustomUI.SCT.ApplySctSettingsTabFullReset()
    CustomUI.SCT.ResetColorsToStockDefault(true)
    local v = Settings()
    v.critAnimV2 = true
    v.critAnimShake = false
    v.critAnimPulse = false
    v.critAnimFlash = false
    v.critSizeScale = 1.0
    v.textFont = 1
    v.sctTextFontV2 = true
    v.offsets = v.offsets or {}
    v.offsets.outgoing = { x = 0, y = 0 }
    v.offsets.incoming = { x = 0, y = 0 }
    v.offsets.points = { x = 0, y = 0 }
    local mid = CustomUI.SCT.GetMiddleTextSizeScale()
    for _, k in ipairs(CustomUI.SCT.COMBAT_TYPE_KEYS) do
        v.outgoing.size[k] = mid
        v.incoming.size[k] = mid
    end
    for _, k in ipairs(CustomUI.SCT.POINT_TYPE_KEYS) do
        v.outgoing.size[k] = mid
    end
    notifyChange()
end

----------------------------------------------------------------
-- Key mappers
----------------------------------------------------------------

function CustomUI.SCT.KeyForCombatType(textType)
    if textType == GameData.CombatEvent.HIT             then return "Hit"     end
    if textType == GameData.CombatEvent.ABILITY_HIT     then return "Ability" end
    if textType == GameData.CombatEvent.CRITICAL        then return "Hit"     end
    if textType == GameData.CombatEvent.ABILITY_CRITICAL then return "Ability" end
    if textType == GameData.CombatEvent.BLOCK           then return "Block"   end
    if textType == GameData.CombatEvent.PARRY           then return "Parry"   end
    if textType == GameData.CombatEvent.EVADE           then return "Evade"   end
    if textType == GameData.CombatEvent.DISRUPT         then return "Disrupt" end
    if textType == GameData.CombatEvent.ABSORB          then return "Absorb"  end
    if textType == GameData.CombatEvent.IMMUNE          then return "Immune"  end
    return "Hit"
end

function CustomUI.SCT.KeyForPointType(pointType)
    if pointType == CustomUI.SCT.XP_GAIN       then return "XP"       end
    if pointType == CustomUI.SCT.RENOWN_GAIN    then return "Renown"   end
    if pointType == CustomUI.SCT.INFLUENCE_GAIN then return "Influence" end
    return "XP"
end

----------------------------------------------------------------
-- Filter helpers
----------------------------------------------------------------

function CustomUI.SCT.CombatTypeOutgoingEnabled(textType)
    local f = (Settings().outgoing or {}).filters or {}
    if textType == GameData.CombatEvent.HIT              then return f.showHit     ~= false end
    if textType == GameData.CombatEvent.ABILITY_HIT      then return f.showAbility ~= false end
    if textType == GameData.CombatEvent.CRITICAL         then return f.showHit     ~= false end
    if textType == GameData.CombatEvent.ABILITY_CRITICAL  then return f.showAbility ~= false end
    if textType == GameData.CombatEvent.BLOCK            then return f.showBlock   ~= false end
    if textType == GameData.CombatEvent.PARRY            then return f.showParry   ~= false end
    if textType == GameData.CombatEvent.EVADE            then return f.showEvade   ~= false end
    if textType == GameData.CombatEvent.DISRUPT          then return f.showDisrupt ~= false end
    if textType == GameData.CombatEvent.ABSORB           then return f.showAbsorb  ~= false end
    if textType == GameData.CombatEvent.IMMUNE           then return f.showImmune  ~= false end
    return true
end

function CustomUI.SCT.CombatTypeIncomingEnabled(textType)
    local f = (Settings().incoming or {}).filters or {}
    if textType == GameData.CombatEvent.HIT              then return f.showHit     ~= false end
    if textType == GameData.CombatEvent.ABILITY_HIT      then return f.showAbility ~= false end
    if textType == GameData.CombatEvent.CRITICAL         then return f.showHit     ~= false end
    if textType == GameData.CombatEvent.ABILITY_CRITICAL  then return f.showAbility ~= false end
    if textType == GameData.CombatEvent.BLOCK            then return f.showBlock   ~= false end
    if textType == GameData.CombatEvent.PARRY            then return f.showParry   ~= false end
    if textType == GameData.CombatEvent.EVADE            then return f.showEvade   ~= false end
    if textType == GameData.CombatEvent.DISRUPT          then return f.showDisrupt ~= false end
    if textType == GameData.CombatEvent.ABSORB           then return f.showAbsorb  ~= false end
    if textType == GameData.CombatEvent.IMMUNE           then return f.showImmune  ~= false end
    return true
end

----------------------------------------------------------------
-- IsAtDefault() — true iff every SCT setting matches its stock-equivalent default.
-- Recomputed on every Set* call for settings UI/reset state; handler ownership follows
-- the component enabled state, not this value.
----------------------------------------------------------------

local function checkDefault(v)
    if not v then return true end

    for _, k in ipairs(CustomUI.SCT.COMBAT_TYPE_KEYS) do
        local fk = "show"..k
        if v.outgoing and v.outgoing.filters and v.outgoing.filters[fk] == false then return false end
        if v.incoming and v.incoming.filters and v.incoming.filters[fk] == false then return false end
    end
    for _, k in ipairs(CustomUI.SCT.POINT_TYPE_KEYS) do
        local fk = "show"..k
        if v.outgoing and v.outgoing.filters and v.outgoing.filters[fk] == false then return false end
    end

    for _, k in ipairs(CustomUI.SCT.COMBAT_TYPE_KEYS) do
        if v.outgoing and v.outgoing.size and (v.outgoing.size[k] or 1.0) ~= 1.0 then return false end
        if v.incoming and v.incoming.size and (v.incoming.size[k] or 1.0) ~= 1.0 then return false end
    end
    for _, k in ipairs(CustomUI.SCT.POINT_TYPE_KEYS) do
        if v.outgoing and v.outgoing.size and (v.outgoing.size[k] or 1.0) ~= 1.0 then return false end
    end

    for _, k in ipairs(CustomUI.SCT.COMBAT_TYPE_KEYS) do
        if v.outgoing and v.outgoing.color and (v.outgoing.color[k] or 1) ~= 1 then return false end
        if v.incoming and v.incoming.color and (v.incoming.color[k] or 1) ~= 1 then return false end
    end
    for _, k in ipairs(CustomUI.SCT.POINT_TYPE_KEYS) do
        if v.outgoing and v.outgoing.color and (v.outgoing.color[k] or 1) ~= 1 then return false end
    end

    if v.customColor then
        for _, k in ipairs(CustomUI.SCT.COMBAT_TYPE_KEYS) do
            if v.customColor.outgoing and v.customColor.outgoing[k] then return false end
            if v.customColor.incoming and v.customColor.incoming[k] then return false end
        end
        for _, k in ipairs(CustomUI.SCT.POINT_TYPE_KEYS) do
            if v.customColor.outgoing and v.customColor.outgoing[k] then return false end
        end
    end

    if v.critAnimShake == true  then return false end
    if v.critAnimPulse == true  then return false end
    if v.critAnimFlash == true  then return false end
    if (v.critSizeScale or 1.0) ~= 1.0 then return false end
    if (v.textFont or 1) ~= 1           then return false end
    if v.showAbilityIcon == true        then return false end
    if v.offsets then
        if type(v.offsets.outgoing) == "table" and (v.offsets.outgoing.x or 0) ~= 0 then return false end
        if type(v.offsets.incoming) == "table" and (v.offsets.incoming.x or 0) ~= 0 then return false end
        if type(v.offsets.points) == "table" and (v.offsets.points.x or 0) ~= 0 then return false end
        if type(v.offsets.outgoing) == "table" and (v.offsets.outgoing.y or 0) ~= 0 then return false end
        if type(v.offsets.incoming) == "table" and (v.offsets.incoming.y or 0) ~= 0 then return false end
        if type(v.offsets.points) == "table" and (v.offsets.points.y or 0) ~= 0 then return false end
    end

    return true
end

function CustomUI.SCT.IsAtDefault()
    local v = CustomUI.Settings and CustomUI.Settings.SCT
    local result = checkDefault(v)
    CustomUI.SCT._isAtDefault = result
    return result
end

-- Fires after every public setter. SCTController.ApplyMode is defined later; lazy call is safe.
function notifyChange()
    CustomUI.SCT._isAtDefault = nil
    if CustomUI.SCT.ApplyMode then
        CustomUI.SCT.ApplyMode()
    end
end
