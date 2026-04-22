----------------------------------------------------------------
-- CustomUI.SCT — Settings helpers
if not CustomUI.SCT then CustomUI.SCT = {} end
-- Shared by SCTEventText, SCTController, and external settings UIs (no window paths here).
-- SavedVariable: EA_ScrollingCombatText_Settings
-- (same key as the standalone ScrollingCombatTextSettings addon
--  for profile compatibility)
----------------------------------------------------------------

CustomUI.SCT.COMBAT_TYPE_KEYS = { "Hit", "Ability", "Heal", "Block", "Parry", "Evade", "Disrupt", "Absorb", "Immune" }
CustomUI.SCT.POINT_TYPE_KEYS  = { "XP", "Renown", "Influence" }

-- Discrete size ticks used by the settings UI (slider maps to these values).
CustomUI.SCT.TICK_SCALES = { 0.75, 0.875, 1.0, 1.25, 1.75 }

-- Crit animation time multiplier (1.0 = stock timing). Middle tick = current default.
CustomUI.SCT.ANIMATION_SPEED_TICKS = { 0.5, 0.75, 1.0, 1.25, 1.5 }

-- [1] = stock event-text font (see easystem_eventtext EA_Window_EventTextLabel); 2+ match wsct WSCT.LOCALS.FONTS order.
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

function CustomUI.SCT.AnimSpeedToSliderPos(speed)
    local scales = CustomUI.SCT.ANIMATION_SPEED_TICKS
    local n = #scales
    if n <= 1 then
        return 0
    end
    local best, idx = math.huge, 1
    for i, s in ipairs(scales) do
        local d = math.abs(speed - s)
        if d < best then
            best, idx = d, i
        end
    end
    return (idx - 1) / (n - 1)
end

function CustomUI.SCT.SliderPosToAnimSpeed(pos)
    local scales = CustomUI.SCT.ANIMATION_SPEED_TICKS
    local n = #scales
    local idx = math.floor(pos * (n - 1) + 0.5) + 1
    idx = math.max(1, math.min(n, idx))
    return scales[idx]
end

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
-- GetSettings — returns the validated/migrated settings table.
-- Always returns a live reference to EA_ScrollingCombatText_Settings.
----------------------------------------------------------------

function CustomUI.SCT.GetSettings()
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

    -- Critical hit presentation: "none" | "shake" | "flash" (default shake).
    if v.critAnimation ~= "none" and v.critAnimation ~= "shake" and v.critAnimation ~= "flash" then
        v.critAnimation = "shake"
    end

    -- Multiplier for crit grow/shake/flash phase timing; discrete ticks (1.0 = stock).
    if type(v.critAnimationSpeed) ~= "number" or v.critAnimationSpeed ~= v.critAnimationSpeed then
        v.critAnimationSpeed = 1.0
    end
    v.critAnimationSpeed = CustomUI.SCT.SliderPosToAnimSpeed(CustomUI.SCT.AnimSpeedToSliderPos(v.critAnimationSpeed))

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

function CustomUI.SCT.GetTextFontName()
    local v = CustomUI.SCT.GetSettings()
    local idx = v.textFont
    local t = CustomUI.SCT.TEXT_FONTS
    if type(idx) ~= "number" or idx < 1 or idx > #t then
        idx = 1
    end
    local e = t[idx]
    return (e and e.font) or "font_default_text_large"
end

-- All preset color indices to 1 (engine DefaultColor per event) and clear per-row custom RGB overrides.
function CustomUI.SCT.ResetColorsToStockDefault()
    local v = CustomUI.SCT.GetSettings()
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

function CustomUI.SCT.GetMiddleAnimSpeed()
    local scales = CustomUI.SCT.ANIMATION_SPEED_TICKS
    local n = #scales
    if n < 1 then
        return 1.0
    end
    return scales[math.ceil(n / 2)]
end

-- SCT settings tab "Reset": stock colors, crit = shake, all text size sliders to center tick.
function CustomUI.SCT.ApplySctSettingsTabFullReset()
    CustomUI.SCT.ResetColorsToStockDefault()
    local v = CustomUI.SCT.GetSettings()
    v.critAnimation = "shake"
    v.critAnimationSpeed = CustomUI.SCT.GetMiddleAnimSpeed()
    v.textFont = 1
    v.sctTextFontV2 = true
    local mid = CustomUI.SCT.GetMiddleTextSizeScale()
    for _, k in ipairs(CustomUI.SCT.COMBAT_TYPE_KEYS) do
        v.outgoing.size[k] = mid
        v.incoming.size[k] = mid
    end
    for _, k in ipairs(CustomUI.SCT.POINT_TYPE_KEYS) do
        v.outgoing.size[k] = mid
    end
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
    local f = (CustomUI.SCT.GetSettings().outgoing or {}).filters or {}
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
    local f = (CustomUI.SCT.GetSettings().incoming or {}).filters or {}
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
