----------------------------------------------------------------
-- GroupWindow test harness (dev) — not part of Controller/View
-- Fakes group roster data and slash gwharness. Do not add production UI or lifecycle
-- here; keep the real Group window split documented in GroupWindowController.lua.
----------------------------------------------------------------

if not CustomUI then
    CustomUI = {}
end

if not CustomUI.GroupWindow then
    CustomUI.GroupWindow = {}
end

CustomUI.GroupWindowTestHarness = CustomUI.GroupWindowTestHarness or {}

local Harness = CustomUI.GroupWindowTestHarness

local c_MAX_GROUP_MEMBERS = 5

Harness.Enabled = Harness.Enabled == true
Harness.MemberCount = Harness.MemberCount or c_MAX_GROUP_MEMBERS

local function ClampMemberCount(value)
    local count = tonumber(value) or c_MAX_GROUP_MEMBERS
    count = math.floor(count)
    if count < 1 then
        count = 1
    elseif count > c_MAX_GROUP_MEMBERS then
        count = c_MAX_GROUP_MEMBERS
    end
    return count
end

local function ToWString(text)
    if type(text) == "wstring" then
        return text
    end
    return towstring(tostring(text or ""))
end

local function BuildMemberName(localName, index)
    if index == 1 then
        return localName
    end
    return localName .. ToWString(" (T") .. towstring(index) .. ToWString(")")
end

local function ClampPercent(value)
    local numberValue = tonumber(value) or 0
    if numberValue < 0 then
        return 0
    end
    if numberValue > 100 then
        return 100
    end
    return math.floor(numberValue + 0.5)
end

local function ReadPercentFromStatus(statusData)
    if type(statusData) ~= "table" then
        return 100
    end

    local current = tonumber(statusData.current)
    local maximum = tonumber(statusData.maximum)
    if current == nil or maximum == nil or maximum <= 0 then
        return 100
    end

    return ClampPercent((current / maximum) * 100)
end

local function ClampMoraleLevel(value)
    local moraleLevel = tonumber(value) or 0
    moraleLevel = math.floor(moraleLevel + 0.5)
    if moraleLevel < 0 then
        return 0
    end
    if moraleLevel > 4 then
        return 4
    end
    return moraleLevel
end

local function ReadPlayerMoraleLevel(player)
    if type(GetPlayerMoraleLevel) == "function" then
        local moraleLevel = GetPlayerMoraleLevel()
        local parsed = tonumber(moraleLevel)
        if parsed ~= nil then
            return ClampMoraleLevel(parsed)
        end
    end

    local parsed = tonumber(player and player.moraleLevel)
    if parsed ~= nil then
        return ClampMoraleLevel(parsed)
    end

    return 0
end

local function ReadPlayerMainAssistStatus()
    if type(IsPlayerMainAssist) ~= "function" then
        return false
    end

    local value = IsPlayerMainAssist()
    if value == true then
        return true
    end

    return tonumber(value) == 1
end

local function ReadPlayerRvrFlaggedStatus(player)
    if player == nil then
        return false
    end

    return (player.rvrFlagged == true)
        or (player.rvrPermaFlagged == true)
        or (player.rvrZoneFlagged == true)
end

local function ReadLocalPlayerPrototype()
    local player = GameData and GameData.Player or {}
    local career = player.career or {}

    local localName = player.name or ToWString("Player")
    local level = tonumber(player.level) or 1
    local battleLevel = tonumber(player.battleLevel) or level
    local careerLine = tonumber(career.line) or tonumber(player.careerLine)
    local careerName = career.name or player.careerName or ToWString("")
    local healthPercent = ReadPercentFromStatus(player.hitPoints)
    local actionPointPercent = ReadPercentFromStatus(player.actionPoints)
    local moraleLevel = ReadPlayerMoraleLevel(player)

    return {
        name = localName,
        healthPercent = healthPercent,
        actionPointPercent = actionPointPercent,
        moraleLevel = moraleLevel,
        level = level,
        battleLevel = battleLevel,
        isRVRFlagged = ReadPlayerRvrFlaggedStatus(player),
        zoneNum = player.zoneNum,
        online = true,
        isDistant = false,
        isInSameRegion = true,
        worldObjNum = player.worldObjNum,
        isGroupLeader = (player.isGroupLeader == true),
        isMainAssist = ReadPlayerMainAssistStatus(),
        isWarbandLeader = (player.isWarbandLeader == true),
        careerLine = careerLine,
        careerName = careerName,
    }
end

function Harness.IsEnabled()
    return Harness.Enabled == true
end

function Harness.SetEnabled(enabled)
    Harness.Enabled = (enabled == true)
end

function Harness.SetMemberCount(count)
    Harness.MemberCount = ClampMemberCount(count)
end

function Harness.GetGroupData()
    local members = {}
    local base = ReadLocalPlayerPrototype()
    local memberCount = ClampMemberCount(Harness.MemberCount)

    for index = 1, memberCount do
        local member = {}
        for key, value in pairs(base) do
            member[key] = value
        end

        member.name = BuildMemberName(base.name, index)
        member.isGroupLeader = (index == 1 and base.isGroupLeader == true)
        member.isMainAssist = (index == 1 and base.isMainAssist == true)
        member.isWarbandLeader = (index == 1 and base.isWarbandLeader == true)
        members[index] = member
    end

    return members
end

local function PrintHelp()
    if type(CustomUI.PrintMessage) ~= "function" then
        return
    end

    CustomUI.PrintMessage(L"GroupWindow harness: /customui gwharness on|off|count <1-5>|status")
end

local function PrintStatus()
    if type(CustomUI.PrintMessage) ~= "function" then
        return
    end

    local state = L"off"
    if Harness.IsEnabled() then
        state = L"on"
    end

    CustomUI.PrintMessage(
        L"GroupWindow harness " .. state .. L", members=" .. towstring(ClampMemberCount(Harness.MemberCount))
    )
end

local function RequestGroupWindowRefresh()
    if not CustomUI.GroupWindow then
        return
    end

    if type(CustomUI.GroupWindow.OnGroupUpdated) == "function" then
        CustomUI.GroupWindow.OnGroupUpdated()
    end
end

function Harness.HandleSlashCommand(trimmedInput)
    if type(trimmedInput) ~= "string" or trimmedInput == "" then
        return false
    end

    local command, argument = trimmedInput:match("^(%S+)%s*(.-)$")
    if string.lower(command or "") ~= "gwharness" then
        return false
    end

    local action, actionArg = (argument or ""):match("^(%S+)%s*(.-)$")
    action = string.lower(action or "status")

    if action == "on" or action == "enable" then
        Harness.SetEnabled(true)
        RequestGroupWindowRefresh()
        PrintStatus()
        return true
    end

    if action == "off" or action == "disable" then
        Harness.SetEnabled(false)
        RequestGroupWindowRefresh()
        PrintStatus()
        return true
    end

    if action == "count" then
        Harness.SetMemberCount(actionArg)
        RequestGroupWindowRefresh()
        PrintStatus()
        return true
    end

    if action == "status" then
        PrintStatus()
        return true
    end

    PrintHelp()
    return true
end
