----------------------------------------------------------------
-- CustomUI.BuffTrackerLayout
--
-- Layout helpers for BuffTracker container visibility, scale, hit area,
-- and center alignment. Tracker lifecycle and buff state stay in
-- BuffTracker.lua; this module only mutates window layout.
----------------------------------------------------------------

if not CustomUI then
    CustomUI = {}
end

CustomUI.BuffTrackerLayout = CustomUI.BuffTrackerLayout or {}

local BuffTrackerLayout = CustomUI.BuffTrackerLayout

function BuffTrackerLayout.ApplyContainerVisibility(tracker, ownerShowing)
    if tracker == nil then
        return
    end
    if tracker.m_containerName and DoesWindowExist(tracker.m_containerName) then
        WindowSetShowing(
            tracker.m_containerName,
            tracker.m_requestedShow == true and ownerShowing == true
        )
    end
end

function BuffTrackerLayout.ApplyContainerScale(tracker)
    if tracker == nil then
        return
    end
    if not (tracker.m_containerName and DoesWindowExist(tracker.m_containerName)) then
        return
    end

    local ownerScale = 1.0
    if tracker.m_ownerName and DoesWindowExist(tracker.m_ownerName) then
        ownerScale = tonumber(WindowGetScale(tracker.m_ownerName)) or 1.0
    end

    WindowSetScale(tracker.m_containerName, ownerScale * (tracker.m_relativeScale or 1.0))
end

function BuffTrackerLayout.ApplyContainerHitArea(tracker)
    if tracker == nil then
        return
    end
    if tracker.m_containerName
       and tracker.m_containerW
       and tracker.m_containerH
       and DoesWindowExist(tracker.m_containerName)
    then
        WindowSetDimensions(tracker.m_containerName, tracker.m_containerW, tracker.m_containerH)
    end
end

-- Resizes the container to exactly fit the visible slots and re-anchors them
-- left-to-right from topleft. Because the container anchor uses a center point
-- (for example "top" -> "bottom"), shrinking the container to the visible row
-- width automatically centers it over that anchor target.
function BuffTrackerLayout.ApplyCenterAlignment(tracker, visibleSlots, iconSize, iconGap, slotWidth)
    if tracker == nil or tracker.m_containerName == nil then
        return
    end

    local container = tracker.m_containerName
    local count = #visibleSlots
    local rowW = count > 0 and (count * iconSize + (count - 1) * iconGap) or 1
    local rowH = count > 0 and iconSize or 1

    WindowSetDimensions(container, rowW, rowH)

    for _, frame in ipairs(tracker.m_buffFrames or {}) do
        local name = frame:GetName()
        WindowClearAnchors(name)
        WindowAddAnchor(name, "topleft", container, "topleft", 0, 0)
    end

    for i, frame in ipairs(visibleSlots) do
        local name = frame:GetName()
        local xOff = (i - 1) * slotWidth
        WindowClearAnchors(name)
        WindowAddAnchor(name, "topleft", container, "topleft", xOff, 0)
    end
end
