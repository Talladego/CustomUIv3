----------------------------------------------------------------
-- CustomUI.SCT — crit animation effects (v2)
-- Only Shake, Pulse, and ColorFlash survive from v1.  The unified-pipeline
-- machinery (m_BaseAnim, m_Effects array, LaneMove, Grow) is gone; stock's
-- :Update handles base float.  These effects are applied on top of stock's
-- positional update in EventEntry:Update (SCTOverrides.lua).
--
-- Load order: SCTSettings → SCTAnim → SCTOverrides → SCTHandlers → SCTController → SCT.xml
----------------------------------------------------------------
if not CustomUI.SCT then CustomUI.SCT = {} end

local SHAKE_DUR   = 0.75
local PULSE_DUR   = 0.75
local FLASH_DUR   = 0.75

local SHAKE_AMP   = 8
local SHAKE_FREQ  = 30
local SHAKE_VERT  = 0.5

local PULSE_FREQ  = 12
local PULSE_DELTA = 0.14

-- p in [0,1]; 10-segment Base→White→Base→Black→Base colour sequence.
local function ColorFlashRGB(tr, tg, tb, p)
    if p <= 0 or p >= 1 then return tr, tg, tb end
    local function lerp(a, b, u) return a + (b - a) * u end
    local t = p * 10
    local i = math.min(9, math.floor(t))
    local u = t - i
    local m = i % 4
    local r, g, b
    if     m == 0 then r,g,b = lerp(tr,255,u), lerp(tg,255,u), lerp(tb,255,u)
    elseif m == 1 then r,g,b = lerp(255,tr,u), lerp(255,tg,u), lerp(255,tb,u)
    elseif m == 2 then r,g,b = lerp(tr,0,u),   lerp(tg,0,u),   lerp(tb,0,u)
    else              r,g,b = lerp(0,tr,u),    lerp(0,tg,u),   lerp(0,tb,u)
    end
    return math.floor(r+0.5), math.floor(g+0.5), math.floor(b+0.5)
end

local Effects = {}

Effects.Shake = {
    Apply = function(entry, t)
        if t >= SHAKE_DUR then
            if entry.SetVisualOffset then
                entry:SetVisualOffset(0, 0)
            end
            return
        end
        local ad = entry.m_AnimationData
        if not ad then return end
        local env = 1 - (t / SHAKE_DUR)
        local amp = SHAKE_AMP * env
        local dx  = amp * math.sin(2 * math.pi * SHAKE_FREQ * t)
        local dy  = (amp * SHAKE_VERT) * math.cos(2 * math.pi * SHAKE_FREQ * t)
        if entry.SetVisualOffset then
            entry:SetVisualOffset(dx, dy)
            return
        end
        local w   = entry:GetName()
        if DoesWindowExist(w) then
            WindowSetOffsetFromParent(w, ad.current.x + dx, ad.current.y + dy)
        end
    end,
}

Effects.Pulse = {
    Apply = function(entry, t)
        local restScale = entry.m_EffectiveScale or 1.0
        local w = entry:GetName()
        if t >= PULSE_DUR then
            if entry.SetVisualScale then
                entry:SetVisualScale(restScale)
            else
                WindowSetScale(w, restScale)
                WindowSetRelativeScale(w, restScale)
            end
            return
        end
        local env = 1 - (t / PULSE_DUR)
        local osc = math.sin(2 * math.pi * PULSE_FREQ * t)
        local s   = restScale * (1 + PULSE_DELTA * env * osc)
        if entry.SetVisualScale then
            entry:SetVisualScale(s)
        else
            WindowSetScale(w, s)
            WindowSetRelativeScale(w, s)
        end
    end,
}

Effects.ColorFlash = {
    Apply = function(entry, t, tr, tg, tb)
        tr = tr or 255; tg = tg or 255; tb = tb or 255
        local p = math.min(1, (FLASH_DUR > 0) and (t / FLASH_DUR) or 1)
        local r, g, b = ColorFlashRGB(tr, tg, tb, p)
        local w = entry:GetName()
        if DoesWindowExist(w) then LabelSetTextColor(w, r, g, b) end
    end,
}

CustomUI.SCT._SctAnim = {
    Effects   = Effects,
    SHAKE_DUR = SHAKE_DUR,
    PULSE_DUR = PULSE_DUR,
    FLASH_DUR = FLASH_DUR,
}

-- LEGACY (v2 SCT, 2026-04-25): v1 constants exposed so SCTEntry.lua / SCTTracker.lua
-- (still loaded as legacy files) don't nil-error on their local reads.
-- Remove these entries in Step 5b when legacy files are deleted.
local _Z = 0
CustomUI.SCT._SctAnim.LANE_DUR              = _Z
CustomUI.SCT._SctAnim.GROW_DUR              = _Z
CustomUI.SCT._SctAnim.FLOAT_TAIL            = _Z
CustomUI.SCT._SctAnim.MIN_DISPLAY_TIME      = _Z
CustomUI.SCT._SctAnim.ENTRY_FADE_DURATION   = _Z
CustomUI.SCT._SctAnim.MINIMUM_EVENT_SPACING = _Z
-- v1 constants still referenced by SCTTracker.lua legacy file.
CustomUI.SCT._SctAnim.CRIT_LANE_TRAVEL_DURATION = _Z
CustomUI.SCT._SctAnim.CRIT_GROW_DURATION        = _Z
CustomUI.SCT._SctAnim.CRIT_FLOAT_DURATION       = _Z
CustomUI.SCT._SctAnim.CRIT_SHAKE_AMPLITUDE      = SHAKE_AMP
CustomUI.SCT._SctAnim.CRIT_SHAKE_FREQUENCY      = SHAKE_FREQ
CustomUI.SCT._SctAnim.CRIT_SHAKE_VERTICAL_SCALE = SHAKE_VERT
CustomUI.SCT._SctAnim.CRIT_OSC_FREQUENCY        = PULSE_FREQ
CustomUI.SCT._SctAnim.CRIT_OSC_SCALE_DELTA      = PULSE_DELTA
CustomUI.SCT._SctAnim.SctCritMainAnimDuration    = function() return 0 end
CustomUI.SCT._SctAnim.SctCritColorFlashSequenceRGB = ColorFlashRGB
CustomUI.SCT._SctAnim.CritFlashOffsetForCenterPivot = function(sx,sy) return sx,sy end
-- LEGACY (v2 SCT): LaneMove and Grow stubs — fail loudly if actually called.
local function _legacyErr(n)
    return function() error("LEGACY (v2 SCT): " .. n .. " removed") end
end
CustomUI.SCT._SctAnim.Effects.LaneMove = {
    Apply = _legacyErr("LaneMove.Apply"), Finish = _legacyErr("LaneMove.Finish")
}
CustomUI.SCT._SctAnim.Effects.Grow = {
    Apply = _legacyErr("Grow.Apply"), Finish = _legacyErr("Grow.Finish")
}
