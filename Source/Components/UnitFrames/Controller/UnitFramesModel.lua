if not CustomUI then
    CustomUI = {}
end

CustomUI.UnitFramesModel = CustomUI.UnitFramesModel or {}

local Model = CustomUI.UnitFramesModel

function Model.CreateGroup(groupIndex, layoutRole, windowName)
    return {
        groupIndex = groupIndex,
        isVisible = false,
        layoutRole = layoutRole,
        windowName = windowName,
        slots = {},
    }
end

function Model.CreateSlot(slotIndex)
    return {
        slotIndex = slotIndex,
        isActive = false,
        member = nil,
    }
end

function Model.CreateMember()
    return {
        name = L"",
        level = 0,
        battleLevel = 0,
        careerLine = nil,
        careerId = nil,
        hpPercent = 0,
        apPercent = 0,
        moraleLevel = 0,
        online = false,
        isDistant = false,
        zoneNum = 0,
        isGroupLeader = false,
        isMainAssist = false,
        isWarbandLeader = false,
        isRVRFlagged = false,
    }
end
