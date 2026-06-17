----------------------------------------------------------------
-- CustomUI.SCT — shared override scaffolding
--
-- Runtime-specific responsibilities now live in dedicated helpers:
--   • SCTAbilityIconResolver.lua
--   • SCTEventEntry.lua
--   • SCTEventTracker.lua
--
-- This file keeps the shared constants, live tracker table, and anchor/key
-- helpers consumed by SCTHandlers.lua.
----------------------------------------------------------------
if not CustomUI.SCT then CustomUI.SCT = {} end

-- Event-type constants (mirrors stock locals; exposed on namespace for handlers).
CustomUI.SCT.COMBAT_EVENT   = CustomUI.SCT.COMBAT_EVENT or 1
CustomUI.SCT.POINT_GAIN     = CustomUI.SCT.POINT_GAIN or 2
CustomUI.SCT.XP_GAIN        = CustomUI.SCT.XP_GAIN or 1
CustomUI.SCT.RENOWN_GAIN    = CustomUI.SCT.RENOWN_GAIN or 2
CustomUI.SCT.INFLUENCE_GAIN = CustomUI.SCT.INFLUENCE_GAIN or 3

-- Live tracker tables (keyed by targetObjectNumber or incoming lane keys).
CustomUI.SCT.EventTrackers = CustomUI.SCT.EventTrackers or {}

local function SctStopAnimations(windowName)
    if not windowName or not DoesWindowExist(windowName) then
        return
    end
    WindowStopAlphaAnimation(windowName)
    WindowStopPositionAnimation(windowName)
    WindowStopScaleAnimation(windowName)
end

local function SctCreateAnchor(anchorName)
    if not DoesWindowExist("CustomUISCTWindow") then
        return false
    end
    if DoesWindowExist(anchorName) then
        SctStopAnimations(anchorName)
        DestroyWindow(anchorName)
    end
    CreateWindowFromTemplate(anchorName, "EA_Window_EventTextAnchor", "CustomUISCTWindow")
    return DoesWindowExist(anchorName)
end
CustomUI.SCT.SctCreateAnchor = SctCreateAnchor

local function SctAnchorName(targetObjectNumber)
    return "CustomUI_SCT_EventTextAnchor" .. tostring(targetObjectNumber or "unknown")
end
CustomUI.SCT.SctAnchorName = SctAnchorName

function CustomUI.SCT.IncomingHealTrackerKey(worldObjNum)
    return "inHeal_" .. tostring(worldObjNum or "")
end

function CustomUI.SCT.IncomingDamageTrackerKey(worldObjNum)
    return "inDmg_" .. tostring(worldObjNum or "")
end

function CustomUI.SCT.IncomingMitigationTrackerKey(worldObjNum)
    return "inMit_" .. tostring(worldObjNum or "")
end

function CustomUI.SCT.IncomingHealAnchorName(worldObjNum)
    return "CustomUI_SCT_EventTextAnchor_IN" .. tostring(worldObjNum or "unknown") .. "_Heal"
end

function CustomUI.SCT.IncomingDamageAnchorName(worldObjNum)
    return "CustomUI_SCT_EventTextAnchor_IN" .. tostring(worldObjNum or "unknown") .. "_Dmg"
end

function CustomUI.SCT.IncomingMitigationAnchorName(worldObjNum)
    return "CustomUI_SCT_EventTextAnchor_IN" .. tostring(worldObjNum or "unknown") .. "_Mit"
end
