----------------------------------------------------------------
-- CustomUI.GroupIcons.SpatialProbe
--
-- Shared AutoMark-style world-object probe used to:
--   - untrack outsider rings whose entity id no longer projects
--   - temporarily hide roster icons whose attach wid is stuck
----------------------------------------------------------------

if not CustomUI then
    CustomUI = {}
end

CustomUI.GroupIcons = CustomUI.GroupIcons or {}
CustomUI.GroupIcons.SpatialProbe = CustomUI.GroupIcons.SpatialProbe or {}

local SpatialProbe = CustomUI.GroupIcons.SpatialProbe

local c_PROBE_WINDOW_NAME = "CustomUIGroupIconsWorldProbe"
local c_ATTACH_Z = 1.0

local function GetResolutionKey()
    local res = SystemData and SystemData.screenResolution
    if not res or res.x == nil or res.y == nil then
        return nil
    end
    return tostring(res.x) .. "x" .. tostring(res.y)
end

--- Anchor calibration for two probe points (same idea as AutoMark.OnUpdate).
local function CalibrateProbeAnchors()
    local probe = c_PROBE_WINDOW_NAME
    if not DoesWindowExist(probe)
        or type(MoveWindowToWorldObject) ~= "function"
        or type(WindowGetScreenPosition) ~= "function"
        or type(WindowClearAnchors) ~= "function"
        or type(WindowAddAnchor) ~= "function"
    then
        return nil
    end

    local res = SystemData and SystemData.screenResolution
    if not res or res.x == nil or res.y == nil then
        return nil
    end

    WindowSetShowing(probe, true)

    local ax = res.x / 2
    local ay = res.y / 2
    WindowClearAnchors(probe)
    WindowAddAnchor(probe, "topleft", "Root", "topleft", ax, ay)
    local r1x, r1y = WindowGetScreenPosition(probe)

    local ax2 = ax + 10
    local ay2 = ay + 10
    WindowClearAnchors(probe)
    WindowAddAnchor(probe, "topleft", "Root", "topleft", ax2, ay2)
    local r2x, r2y = WindowGetScreenPosition(probe)

    return {
        ax = ax,
        ay = ay,
        ax2 = ax2,
        ay2 = ay2,
        r1x = r1x,
        r1y = r1y,
        r2x = r2x,
        r2y = r2y,
    }
end

function SpatialProbe.ResetCalibration()
    SpatialProbe.m_calibration = nil
    SpatialProbe.m_resolutionKey = nil
end

function SpatialProbe.GetCalibration()
    local key = GetResolutionKey()
    if key ~= nil
        and key == SpatialProbe.m_resolutionKey
        and SpatialProbe.m_calibration ~= nil
    then
        return SpatialProbe.m_calibration
    end

    local cal = CalibrateProbeAnchors()
    if cal ~= nil then
        SpatialProbe.m_calibration = cal
        SpatialProbe.m_resolutionKey = key
    end

    return cal
end

--- True if world object id no longer drives UI projection (static/stuck icon symptom).
--- Hidden probe after move => entity exists off-screen (not gone).
--- Two-anchor non-move => gone (AutoMark disambiguation).
function SpatialProbe.IsGone(wid, cal)
    if cal == nil or wid == nil or wid == 0 then
        return false
    end

    if type(WindowGetShowing) ~= "function" then
        return false
    end

    local probe = c_PROBE_WINDOW_NAME

    WindowClearAnchors(probe)
    WindowAddAnchor(probe, "topleft", "Root", "topleft", cal.ax, cal.ay)
    MoveWindowToWorldObject(probe, wid, c_ATTACH_Z)
    if WindowGetShowing(probe) == false then
        WindowSetShowing(probe, true)
        return false
    end

    local ox, oy = WindowGetScreenPosition(probe)
    if cal.r1x ~= ox or cal.r1y ~= oy then
        return false
    end

    WindowClearAnchors(probe)
    WindowAddAnchor(probe, "topleft", "Root", "topleft", cal.ax2, cal.ay2)
    MoveWindowToWorldObject(probe, wid, c_ATTACH_Z)
    ox, oy = WindowGetScreenPosition(probe)
    if cal.r2x ~= ox or cal.r2y ~= oy then
        return false
    end

    return true
end
