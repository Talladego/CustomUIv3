----------------------------------------------------------------
-- CustomUI.UnitFrames — Controller
-- Responsibilities: RegisterComponent, visibility/scenario/battlegroup events, and wiring
--   to internal helpers (Model, Events, Renderer). Not the same as a View/ .lua: rendering
--   is split into UnitFramesRenderer.lua by subsystem, not a separate View/ folder.
-- CustomUI.mod loads this file after the other UnitFrames/*.lua and before View/UnitFrames.xml;
--   the XML does not re-<Script> the controller. Internal modules stay in Controller/ by layout.
----------------------------------------------------------------

if not CustomUI then
    CustomUI = {}
end

if not CustomUI.UnitFrames then
    CustomUI.UnitFrames = {}
end

local UnitFrames = CustomUI.UnitFrames
UnitFrames.WindowSettings = UnitFrames.WindowSettings or {}

local c_ROOT_WINDOW_NAME = "CustomUIUnitFramesRoot"
local c_MAX_GROUP_WINDOWS = 6
local c_WARBAND_GROUPS = 4
local c_GROUP_MEMBERS = 6
local c_VISIBILITY_POLL_INTERVAL = 0.25
local c_OPACITY_MIN = 0
local c_OPACITY_MAX = 1
local c_OPACITY_FULL_SNAP_THRESHOLD = 0.995
local c_DEFAULT_BACKGROUND_ALPHA = 0.25

local m_enabled = false
local m_windowsInitialized = false
local m_visibilityPollElapsed = 0
local SafeLayoutUserShow
local SafeLayoutUserHide
local m_stockOnMenuClickSetBackgroundOpacity = nil
local m_stockOnOpacitySlide = nil
local m_eventsRegistered = false
local m_lastVisibilityMode = nil

-- Forward decls (used by target-highlight helpers below).
local IsWarbandModeActive
local MemberWindowName
local TryGetWarbandMember
local GetGroupMemberIndicesFromWindowName

-- Target highlight state (friendly target only; same classification string as EA_BattlegroupHUD).
local c_FRIENDLY_TARGET = "selffriendlytarget"
local m_currentTargetId = 0
local m_currentTargetName = nil
local m_mouseOverMemberWindow = nil

local function ToWString(v)
    if v == nil then
        return nil
    end
    if type(v) == "string" then
        return towstring(v)
    end
    return v
end

local function ToLuaString(v)
    if v == nil then
        return nil
    end

    return tostring(v)
end

local function NamesMatch(memberName, targetName)
    local memberText = ToLuaString(memberName)
    local targetText = ToLuaString(targetName)
    if memberText == nil or targetText == nil or memberText == "" or targetText == "" then
        return false
    end

    if memberText == targetText then
        return true
    end

    -- Stock WStringsCompareIgnoreGrammer strips a leading grammar marker but uses
    -- '<' internally, which can crash on mixed string/wstring values on this client.
    return string.sub(memberText, 2) == string.sub(targetText, 2)
end

local function IsMemberCurrentFriendlyTarget(member)
    if member == nil then
        return false
    end
    local currentTargetId = tonumber(m_currentTargetId)
    local memberWorldObjNum = tonumber(member.worldObjNum)
    if currentTargetId ~= nil and currentTargetId ~= 0 and memberWorldObjNum ~= nil and memberWorldObjNum ~= 0 and memberWorldObjNum == currentTargetId then
        return true
    end
    local memberName = ToWString(member and member.name)
    if m_currentTargetName ~= nil and memberName ~= nil and memberName ~= L"" then
        local targetName = ToWString(m_currentTargetName)
        if memberName == nil or targetName == nil then
            return false
        end
        return NamesMatch(memberName, targetName)
    end
    return false
end

local function RefreshTargetBorders()
    if not m_enabled then
        return
    end
    if not IsWarbandModeActive() then
        return
    end
    for groupIndex = 1, c_WARBAND_GROUPS do
        for memberIndex = 1, c_GROUP_MEMBERS do
            local memberWindow = MemberWindowName(groupIndex, memberIndex)
            local border = memberWindow .. "TargetBorder"
            if DoesWindowExist(border) then
                local member = TryGetWarbandMember(groupIndex, memberIndex)
                WindowSetShowing(border, IsMemberCurrentFriendlyTarget(member))
            end
        end
    end
end

local function SetMouseOverBorderShowing(memberWindow, show)
    local border = tostring(memberWindow or "") .. "MouseOverBorder"
    if DoesWindowExist(border) then
        WindowSetShowing(border, show == true)
    end
end

local function RefreshMouseOverBorders()
    if not m_enabled then
        m_mouseOverMemberWindow = nil
    end

    for groupIndex = 1, c_MAX_GROUP_WINDOWS do
        for memberIndex = 1, c_GROUP_MEMBERS do
            local memberWindow = MemberWindowName(groupIndex, memberIndex)
            SetMouseOverBorderShowing(memberWindow, m_mouseOverMemberWindow == memberWindow)
        end
    end
end

function UnitFrames.OnMemberMouseOver()
    local groupIndex, memberIndex = GetGroupMemberIndicesFromWindowName(SystemData.ActiveWindow.name)
    if groupIndex == nil or memberIndex == nil then
        return
    end

    local memberWindow = MemberWindowName(groupIndex, memberIndex)
    if m_mouseOverMemberWindow ~= memberWindow then
        if m_mouseOverMemberWindow ~= nil then
            SetMouseOverBorderShowing(m_mouseOverMemberWindow, false)
        end
        m_mouseOverMemberWindow = memberWindow
    end

    SetMouseOverBorderShowing(memberWindow, true)
end

function UnitFrames.OnMemberMouseOverEnd()
    local groupIndex, memberIndex = GetGroupMemberIndicesFromWindowName(SystemData.ActiveWindow.name)
    if groupIndex ~= nil and memberIndex ~= nil then
        local memberWindow = MemberWindowName(groupIndex, memberIndex)
        SetMouseOverBorderShowing(memberWindow, false)
        if m_mouseOverMemberWindow == memberWindow then
            m_mouseOverMemberWindow = nil
        end
        return
    end

    if m_mouseOverMemberWindow ~= nil then
        SetMouseOverBorderShowing(m_mouseOverMemberWindow, false)
        m_mouseOverMemberWindow = nil
    end
end

function UnitFrames.OnTargetUpdated(targetClassification, targetId, targetType)
    if targetClassification ~= c_FRIENDLY_TARGET then
        return
    end
    m_currentTargetId = tonumber(targetId) or 0
    m_currentTargetName = nil
    if type(TargetInfo) == "table" and type(TargetInfo.UnitName) == "function" then
        local nm = TargetInfo:UnitName(c_FRIENDLY_TARGET)
        if type(nm) == "string" then
            nm = towstring(nm)
        end
        m_currentTargetName = nm
    end
    RefreshTargetBorders()
end

local function IsScenarioModeActive()
    return GameData ~= nil
        and GameData.Player ~= nil
        and (GameData.Player.isInScenario == true or GameData.Player.isInSiege == true)
end

IsWarbandModeActive = function()
    if IsScenarioModeActive() then
        return false
    end

    if type(IsWarBandActive) == "function" then
        return IsWarBandActive()
    end

    return false
end

local function GroupWindowName(groupIndex)
    return "CustomUIUnitFramesGroup" .. groupIndex .. "Window"
end

MemberWindowName = function(groupIndex, memberIndex)
    return GroupWindowName(groupIndex) .. "Member" .. memberIndex
end

local function IsLayoutEditorReady()
    return type(LayoutEditor) == "table"
        and type(LayoutEditor.RegisterWindow) == "function"
        and type(LayoutEditor.UserShow) == "function"
        and type(LayoutEditor.UserHide) == "function"
        and type(LayoutEditor.windowsList) == "table"
end

local function ForEachWindow(windowList, callback)
    if type(callback) ~= "function" then
        return
    end

    for _, windowName in ipairs(windowList or {}) do
        callback(windowName)
    end
end

local function SafeLayoutRegister(windowName, displayName, description)
    if not IsLayoutEditorReady() then
        return false
    end

    if not DoesWindowExist(windowName) then
        return false
    end

    if LayoutEditor.windowsList[windowName] ~= nil then
        return true
    end

    LayoutEditor.RegisterWindow(windowName, displayName, description, false, false, true, nil)
    return LayoutEditor.windowsList[windowName] ~= nil
end

SafeLayoutUserShow = function(windowName)
    if IsLayoutEditorReady()
    and DoesWindowExist(windowName)
    and LayoutEditor.windowsList[windowName] ~= nil then
        LayoutEditor.UserShow(windowName)
    end
end

SafeLayoutUserHide = function(windowName)
    if IsLayoutEditorReady()
    and DoesWindowExist(windowName)
    and LayoutEditor.windowsList[windowName] ~= nil then
        LayoutEditor.UserHide(windowName)
    end
end

local function GetWindowSets()
    local events = CustomUI.UnitFramesEvents or {}
    return {
        customDualMode = events.CustomDualModeWindows or {},
        stockWarband = events.StockWarbandWindows or {},
        stockScenario = events.StockScenarioFloatingWindows or {},
    }
end

local function RegisterCustomWindowsForLayout()
    if not IsLayoutEditorReady() then
        return false
    end

    local windowSets = GetWindowSets()
    local allRegistered = true

    for _, windowName in ipairs(windowSets.customDualMode) do
        local registered = SafeLayoutRegister(windowName, towstring("CustomUI: " .. windowName), L"CustomUI UnitFrames dual-mode group window")
        if not registered then
            allRegistered = false
        end
        SafeLayoutUserHide(windowName)
    end

    return allRegistered
end

local function HideAllStockWindows()
    local windowSets = GetWindowSets()
    ForEachWindow(windowSets.stockWarband, SafeLayoutUserHide)
    ForEachWindow(windowSets.stockScenario, SafeLayoutUserHide)
end

local function HideAllCustomWindows()
    local windowSets = GetWindowSets()
    ForEachWindow(windowSets.customDualMode, SafeLayoutUserHide)
end

local function SetMemberWindowShowing(groupIndex, memberIndex, isShowing)
    local memberWindow = MemberWindowName(groupIndex, memberIndex)
    if DoesWindowExist(memberWindow) then
        WindowSetShowing(memberWindow, isShowing)
    end
end

local function IsUnitFramesMemberWindowName(windowName)
    if type(windowName) ~= "string" then
        return false
    end

    return string.match(windowName, "^CustomUIUnitFramesGroup%d+WindowMember%d+$") ~= nil
end

local function SetUnitFramesBackgroundAlpha(alpha)
    for groupIndex = 1, c_MAX_GROUP_WINDOWS do
        for memberIndex = 1, c_GROUP_MEMBERS do
            local memberWindow = MemberWindowName(groupIndex, memberIndex)
            local backgroundWindow = memberWindow .. "Background"
            if DoesWindowExist(backgroundWindow) then
                WindowSetAlpha(backgroundWindow, alpha)
            end
        end
    end
end

local function ClampAlpha(value)
    local alpha = tonumber(value)
    if alpha == nil then
        return c_OPACITY_MIN
    end

    if alpha < c_OPACITY_MIN then
        return c_OPACITY_MIN
    end

    if alpha > c_OPACITY_MAX then
        return c_OPACITY_MAX
    end

    if alpha >= c_OPACITY_FULL_SNAP_THRESHOLD then
        return c_OPACITY_MAX
    end

    return alpha
end

local function GetStockWarbandBackgroundAlpha()
    local stockBackgroundWindow = "BattlegroupHUDGroup1LayoutWindowMember1Background"
    if DoesWindowExist(stockBackgroundWindow) then
        local liveAlpha = tonumber(WindowGetAlpha(stockBackgroundWindow))
        if liveAlpha ~= nil then
            if liveAlpha < 0 then
                return 0
            end
            if liveAlpha > 1 then
                return 1
            end
            return liveAlpha
        end
    end

    if type(BattlegroupHUD) ~= "table"
    or type(BattlegroupHUD.WindowSettings) ~= "table" then
        return nil
    end

    local alpha = tonumber(BattlegroupHUD.WindowSettings.backgroundAlpha)
    if alpha == nil then
        return nil
    end

    if alpha < 0 then
        return 0
    end

    if alpha > 1 then
        return 1
    end

    return alpha
end

local function SetStockWarbandBackgroundAlpha(alpha)
    if type(BattlegroupHUD) ~= "table" then
        return
    end

    local resolvedAlpha = ClampAlpha(alpha)

    if type(BattlegroupHUD.WindowSettings) ~= "table" then
        BattlegroupHUD.WindowSettings = {}
    end

    BattlegroupHUD.WindowSettings.backgroundAlpha = resolvedAlpha

    if type(BattlegroupHUD.SetBackgroundAlpha) == "function" then
        BattlegroupHUD.SetBackgroundAlpha(resolvedAlpha)
    end
end

local function IsWarbandGroupVisibleByStockToggle(groupIndex)
    if EA_Window_OpenPartyManage == nil then
        return true
    end

    local buttonName = "EA_Window_OpenPartyManageWarband" .. groupIndex .. "Show"
    if not DoesWindowExist(buttonName) then
        return true
    end

    return ButtonGetPressedFlag(buttonName)
end

local function IsScenarioGroupVisibleByStockToggle(groupIndex)
    local buttonName = "ScenarioGroupWindowGroup" .. groupIndex .. "VisibleButton"
    if DoesWindowExist(buttonName) then
        return ButtonGetPressedFlag(buttonName)
    end

    if ScenarioGroupWindow ~= nil
    and ScenarioGroupWindow.GroupWindowSettings ~= nil
    and ScenarioGroupWindow.GroupWindowSettings.floatingVisibility ~= nil then
        local saved = ScenarioGroupWindow.GroupWindowSettings.floatingVisibility[groupIndex]
        if saved ~= nil then
            return saved
        end
    end

    -- Fallback to visible when scenario controls are not available.
    return true
end

local function SetCareerIcon(memberWindow, member)
    if member == nil or member.careerLine == nil then
        return
    end

    local iconId = Icons.GetCareerIconIDFromCareerLine(member.careerLine)
    if iconId == nil then
        return
    end

    local iconTexture, iconX, iconY = GetIconData(iconId)
    if iconTexture ~= nil then
        DynamicImageSetTexture(memberWindow .. "CareerIcon", iconTexture, iconX, iconY)
    end
end

local function SetScenarioCareerIcon(memberWindow, player)
    if player == nil or player.careerId == nil then
        return
    end

    local iconId = Icons.GetCareerIconIDFromCareerNamesID(player.careerId)
    if iconId == nil then
        return
    end

    local iconTexture, iconX, iconY = GetIconData(iconId)
    if iconTexture ~= nil then
        DynamicImageSetTexture(memberWindow .. "CareerIcon", iconTexture, iconX, iconY)
    end
end

local function SetMemberBars(memberWindow, member)
    local hp = tonumber(member.healthPercent) or 0
    local ap = tonumber(member.actionPointPercent) or 0

    if hp < 0 then hp = 0 end
    if hp > 100 then hp = 100 end
    if ap < 0 then ap = 0 end
    if ap > 100 then ap = 100 end

    StatusBarSetMaximumValue(memberWindow .. "HPBar", 100)
    StatusBarSetMaximumValue(memberWindow .. "APBar", 100)
    StatusBarSetCurrentValue(memberWindow .. "HPBar", hp)
    StatusBarSetCurrentValue(memberWindow .. "APBar", ap)
end

local function SetScenarioMemberBars(memberWindow, player)
    local hp = tonumber(player.health) or 0
    local ap = tonumber(player.ap) or 0

    if hp < 0 then hp = 0 end
    if hp > 100 then hp = 100 end
    if ap < 0 then ap = 0 end
    if ap > 100 then ap = 100 end

    StatusBarSetMaximumValue(memberWindow .. "HPBar", 100)
    StatusBarSetMaximumValue(memberWindow .. "APBar", 100)
    StatusBarSetCurrentValue(memberWindow .. "HPBar", hp)
    StatusBarSetCurrentValue(memberWindow .. "APBar", ap)
end

local function ApplyStatusSettings(memberWindow, color, alpha, showBars)
    LabelSetTextColor(memberWindow .. "LabelHealth", color.r, color.g, color.b)
    WindowSetFontAlpha(memberWindow .. "LabelHealth", alpha)
    -- UnitFrames: always show HP/AP bars (no fade/hide on full bars).
    WindowSetShowing(memberWindow .. "HPBar", true)
    WindowSetShowing(memberWindow .. "APBar", true)
end

TryGetWarbandMember = function(groupIndex, memberIndex)
    if type(PartyUtils) ~= "table" or type(PartyUtils.GetWarbandMember) ~= "function" then
        return nil
    end

    return PartyUtils.GetWarbandMember(groupIndex, memberIndex)
end

local function GetMemberFromCareerIconWindow(windowName)
    local groupIndex, memberIndex = string.match(windowName or "", "^CustomUIUnitFramesGroup(%d+)WindowMember(%d+)CareerIcon$")
    groupIndex = tonumber(groupIndex)
    memberIndex = tonumber(memberIndex)

    if groupIndex == nil or memberIndex == nil then
        return nil
    end

    return TryGetWarbandMember(groupIndex, memberIndex)
end

GetGroupMemberIndicesFromWindowName = function(windowName)
    local groupIndex, memberIndex = string.match(windowName or "", "^CustomUIUnitFramesGroup(%d+)WindowMember(%d+)")
    groupIndex = tonumber(groupIndex)
    memberIndex = tonumber(memberIndex)

    if groupIndex == nil or memberIndex == nil then
        return nil, nil
    end

    return groupIndex, memberIndex
end

local function SetMemberTextAndState(memberWindow, member)
    local memberName = ToWString(member and member.name) or L""
    LabelSetText(memberWindow .. "LabelName", memberName)

    local healthText = towstring(tonumber(member.healthPercent) or 0) .. L"%"
    local hp = tonumber(member.healthPercent) or 0

    if member.online ~= true then
        healthText = GetString(StringTables.Default.LABEL_PARTY_MEMBER_OFFLINE)
        ApplyStatusSettings(memberWindow, DefaultColor.HEALTH_TEXT_DEAD, 0.5, true)
    elseif member.isDistant then
        healthText = GetString(StringTables.Default.LABEL_PARTY_MEMBER_IS_DISTANT)
        ApplyStatusSettings(memberWindow, DefaultColor.HEALTH_TEXT_DEAD, 0.5, true)
    elseif hp >= 100 and (tonumber(member.actionPointPercent) or 0) >= 100 then
        ApplyStatusSettings(memberWindow, DefaultColor.HEALTH_TEXT_FULL, 1.0, true)
    elseif hp > 0 then
        ApplyStatusSettings(memberWindow, DefaultColor.HEALTH_TEXT_NOT_FULL, 1.0, true)
    else
        healthText = GetString(StringTables.Default.LABEL_PLAYER_DEAD_ALLCAPS)
        ApplyStatusSettings(memberWindow, DefaultColor.HEALTH_TEXT_DEAD, 1.0, true)
    end

    LabelSetText(memberWindow .. "LabelHealth", healthText)
    WindowSetGameActionData(memberWindow, GameData.PlayerActions.SET_TARGET, 0, memberName)

    if DoesWindowExist(memberWindow .. "TargetBorder") then
        WindowSetShowing(memberWindow .. "TargetBorder", IsMemberCurrentFriendlyTarget(member))
    end

    local isDead = hp <= 0 and member.online == true
    WindowSetShowing(memberWindow .. "DeathIcon", isDead)
end

local function SetScenarioMemberTextAndState(memberWindow, player)
    local playerName = ToWString(player and player.name) or L""
    LabelSetText(memberWindow .. "LabelName", playerName)
    LabelSetText(memberWindow .. "LabelHealth", towstring(tonumber(player.health) or 0) .. L"%")

    WindowSetGameActionData(memberWindow, GameData.PlayerActions.SET_TARGET, 0, playerName)

    local isDead = (tonumber(player.health) or 0) <= 0
    WindowSetShowing(memberWindow .. "DeathIcon", isDead)

    if isDead then
        ApplyStatusSettings(memberWindow, DefaultColor.HEALTH_TEXT_DEAD, 1.0, false)
    elseif (tonumber(player.health) or 0) >= 100 and (tonumber(player.ap) or 0) >= 100 then
        ApplyStatusSettings(memberWindow, DefaultColor.HEALTH_TEXT_FULL, 0.5, false)
    else
        ApplyStatusSettings(memberWindow, DefaultColor.HEALTH_TEXT_NOT_FULL, 1.0, true)
    end

    LabelSetTextColor(memberWindow .. "LabelName", DefaultColor.NAME_COLOR_PLAYER.r, DefaultColor.NAME_COLOR_PLAYER.g, DefaultColor.NAME_COLOR_PLAYER.b)
end

local function UpdateWarbandMember(groupIndex, memberIndex, member)
    local memberWindow = MemberWindowName(groupIndex, memberIndex)
    if not DoesWindowExist(memberWindow) then
        return
    end

    SetMemberTextAndState(memberWindow, member)
    SetCareerIcon(memberWindow, member)
    SetMemberBars(memberWindow, member)

    local groupLeaderIcon = GroupWindowName(groupIndex) .. "GroupLeaderIcon"
    local mainAssistIcon = GroupWindowName(groupIndex) .. "MainAssistIcon"

    if member.isGroupLeader then
        WindowClearAnchors(groupLeaderIcon)
        WindowAddAnchor(groupLeaderIcon, "top", memberWindow .. "LabelName", "bottom", 0, 2)
    end

    if member.isMainAssist then
        WindowClearAnchors(mainAssistIcon)
        WindowAddAnchor(mainAssistIcon, "right", memberWindow, "center", 0, 0)
    end

    if member.isRVRFlagged then
        LabelSetTextColor(memberWindow .. "LabelName", DefaultColor.YELLOW.r, DefaultColor.YELLOW.g, DefaultColor.YELLOW.b)
    else
        LabelSetTextColor(memberWindow .. "LabelName", DefaultColor.NAME_COLOR_PLAYER.r, DefaultColor.NAME_COLOR_PLAYER.g, DefaultColor.NAME_COLOR_PLAYER.b)
    end
end

local function UpdateWarbandGroup(groupIndex)
    local groupWindow = GroupWindowName(groupIndex)
    if not DoesWindowExist(groupWindow) then
        return
    end

    if groupIndex > c_WARBAND_GROUPS then
        SafeLayoutUserHide(groupWindow)
        return
    end

    local showGroup = IsWarbandGroupVisibleByStockToggle(groupIndex)
    local warbandParty = PartyUtils.GetWarbandParty(groupIndex)
    local players = (warbandParty and warbandParty.players) or {}
    local numMembers = table.getn(players)

    if not showGroup or numMembers < 1 then
        SafeLayoutUserHide(groupWindow)
        return
    end

    SafeLayoutUserShow(groupWindow)

    local foundLeader = false
    local foundMainAssist = false

    for memberIndex = 1, c_GROUP_MEMBERS do
        local member = PartyUtils.GetWarbandMember(groupIndex, memberIndex)
        local memberName = ToWString(member and member.name)
        if member ~= nil and memberName ~= nil and memberName ~= L"" then
            SetMemberWindowShowing(groupIndex, memberIndex, true)
            UpdateWarbandMember(groupIndex, memberIndex, member)

            if member.isGroupLeader then
                foundLeader = true
            end

            if member.isMainAssist then
                foundMainAssist = true
            end
        else
            SetMemberWindowShowing(groupIndex, memberIndex, false)
        end
    end

    WindowSetShowing(groupWindow .. "GroupLeaderIcon", foundLeader)
    WindowSetShowing(groupWindow .. "MainAssistIcon", foundMainAssist)
end

local function ShowWarbandDualModeWindows()
    for groupIndex = 1, c_MAX_GROUP_WINDOWS do
        UpdateWarbandGroup(groupIndex)
    end
end

local function BuildScenarioGroupMap()
    local groups = {}
    for groupIndex = 1, c_MAX_GROUP_WINDOWS do
        groups[groupIndex] = {}
    end

    if type(GameData.GetScenarioPlayerGroups) ~= "function" then
        return groups
    end

    local playerGroups = GameData.GetScenarioPlayerGroups() or {}
    local invalidEntries = 0

    for _, player in ipairs(playerGroups) do
        local groupIndex = tonumber(player.sgroupindex)
        local slotIndex = tonumber(player.sgroupslotnum)

        if groupIndex ~= nil and slotIndex ~= nil
        and groupIndex >= 1 and groupIndex <= c_MAX_GROUP_WINDOWS
        and slotIndex >= 1 and slotIndex <= c_GROUP_MEMBERS then
            groups[groupIndex][slotIndex] = player
        else
            invalidEntries = invalidEntries + 1
        end
    end

    return groups
end

local function UpdateScenarioGroup(groupIndex, groups)
    local groupWindow = GroupWindowName(groupIndex)
    if not DoesWindowExist(groupWindow) then
        return
    end

    local groupSlots = groups[groupIndex] or {}
    local hasMembers = false
    local mainAssistSlot = nil

    for memberIndex = 1, c_GROUP_MEMBERS do
        local player = groupSlots[memberIndex]
        local memberWindow = MemberWindowName(groupIndex, memberIndex)

        local playerName = ToWString(player and player.name)
        if player ~= nil and playerName ~= nil and playerName ~= L"" then
            hasMembers = true
            SetMemberWindowShowing(groupIndex, memberIndex, true)
            SetScenarioMemberTextAndState(memberWindow, player)
            SetScenarioCareerIcon(memberWindow, player)
            SetScenarioMemberBars(memberWindow, player)

            if player.isMainAssist then
                mainAssistSlot = memberIndex
            end
        else
            SetMemberWindowShowing(groupIndex, memberIndex, false)
        end
    end

    local toggleVisible = IsScenarioGroupVisibleByStockToggle(groupIndex)
    local showGroup = toggleVisible and hasMembers
    if showGroup then
        SafeLayoutUserShow(groupWindow)
    else
        SafeLayoutUserHide(groupWindow)
    end

    -- Scenario floating groups do not use group-leader crown.
    WindowSetShowing(groupWindow .. "GroupLeaderIcon", false)

    if mainAssistSlot ~= nil then
        local mainAssistIcon = groupWindow .. "MainAssistIcon"
        local memberWindow = MemberWindowName(groupIndex, mainAssistSlot)
        WindowClearAnchors(mainAssistIcon)
        WindowAddAnchor(mainAssistIcon, "right", memberWindow, "center", 0, 0)
        WindowSetShowing(mainAssistIcon, true)
    else
        WindowSetShowing(groupWindow .. "MainAssistIcon", false)
    end
end

local function ShowScenarioDualModeWindows()
    local groups = BuildScenarioGroupMap()

    for groupIndex = 1, c_MAX_GROUP_WINDOWS do
        UpdateScenarioGroup(groupIndex, groups)
    end
end

local function ApplyModeVisibility()
    if not m_enabled or not m_windowsInitialized then
        return
    end

    local currentMode = "none"
    if IsScenarioModeActive() then
        currentMode = "scenario"
    elseif IsWarbandModeActive() then
        currentMode = "warband"
    end

    if currentMode ~= m_lastVisibilityMode then
        m_lastVisibilityMode = currentMode
    end

    HideAllStockWindows()
    HideAllCustomWindows()

    if currentMode == "scenario" then
        ShowScenarioDualModeWindows()
        return
    end

    if currentMode == "warband" then
        ShowWarbandDualModeWindows()
    end
end

local function HideCustomShowStock()
    local windowSets = GetWindowSets()

    HideAllCustomWindows()
    ForEachWindow(windowSets.stockWarband, SafeLayoutUserShow)
    ForEachWindow(windowSets.stockScenario, SafeLayoutUserShow)
end

function UnitFrames.OnVisibilityStateChanged()
    ApplyModeVisibility()
end

function UnitFrames.OnWarbandMemberUpdated()
    if not m_enabled or not m_windowsInitialized then
        return
    end

    if not IsWarbandModeActive() then
        return
    end

    ShowWarbandDualModeWindows()
end

function UnitFrames.OnMouseOverCareerIcon()
    local member = GetMemberFromCareerIconWindow(SystemData.ActiveWindow.name)
    if member == nil then
        return
    end

    local levelString = PartyUtils.GetLevelText(member.level, member.battleLevel)

    Tooltips.CreateTextOnlyTooltip(SystemData.ActiveWindow.name)
    Tooltips.SetTooltipText(1, 1, ToWString(member.name) or L"")
    Tooltips.SetTooltipColorDef(1, 1, Tooltips.COLOR_HEADING)
    Tooltips.SetTooltipText(2, 1, GetStringFormat(StringTables.Default.LABEL_RANK_X, { levelString }))
    Tooltips.SetTooltipText(3, 1, GetStringFormatFromTable("HUDStrings", StringTables.HUD.LABEL_HUD_PLAYER_WINDOW_TOOLTIP_CAREER_NAME, { member.careerName }))

    local tooltipLine = 4
    if tonumber(member.zoneNum) ~= nil and tonumber(member.zoneNum) > 0 then
        Tooltips.SetTooltipText(tooltipLine, 1, GetZoneName(member.zoneNum))
        tooltipLine = tooltipLine + 1
    end

    if member.isRVRFlagged then
        Tooltips.SetTooltipText(tooltipLine, 1, GetStringFromTable("HUDStrings", StringTables.HUD.LABEL_PLAYER_IS_RVR_FLAGGED))
    end

    Tooltips.Finalize()
    Tooltips.AnchorTooltip(Tooltips.ANCHOR_WINDOW_VARIABLE)
end

function UnitFrames.OnMemberRightClick()
    local groupIndex, memberIndex = GetGroupMemberIndicesFromWindowName(SystemData.ActiveWindow.name)
    if groupIndex == nil or memberIndex == nil then
        return
    end

    local member = TryGetWarbandMember(groupIndex, memberIndex)
    local memberName = ToWString(member and member.name)
    if member == nil or memberName == nil or memberName == L"" then
        return
    end

    if type(BattlegroupHUD) == "table" and type(BattlegroupHUD.ShowMenu) == "function" then
        BattlegroupHUD.contextMenuOpenedFrom = MemberWindowName(groupIndex, memberIndex)
        BattlegroupHUD.ShowMenu(memberName, member.online ~= true)
    end
end

function UnitFrames.OnMemberLeftClick()
    -- Targeting is handled by WindowSetGameActionData(...SET_TARGET...) on each member row.
    if GetDesiredInteractAction() == SystemData.InteractActions.TELEPORT then
        UseItemTargeting.SendTeleport()
    end
end

function UnitFrames.InitializeWindow()
    if m_windowsInitialized then
        return
    end

    m_windowsInitialized = RegisterCustomWindowsForLayout()

end

function UnitFrames.ShutdownWindow()
end

function UnitFrames.Update(elapsedTime)
    if not m_enabled then
        return
    end

    m_visibilityPollElapsed = m_visibilityPollElapsed + (elapsedTime or 0)
    if m_visibilityPollElapsed >= c_VISIBILITY_POLL_INTERVAL then
        m_visibilityPollElapsed = 0
        ApplyModeVisibility()
        RefreshTargetBorders()
        RefreshMouseOverBorders()
    end
end

function UnitFrames.Initialize()
    UnitFrames.InitializeWindow()

    if type(BattlegroupHUD) == "table"
    and type(BattlegroupHUD.OnMenuClickSetBackgroundOpacity) == "function"
    and m_stockOnMenuClickSetBackgroundOpacity == nil then
        m_stockOnMenuClickSetBackgroundOpacity = BattlegroupHUD.OnMenuClickSetBackgroundOpacity
        BattlegroupHUD.OnMenuClickSetBackgroundOpacity = function()
            local contextWindow = BattlegroupHUD.contextMenuOpenedFrom
            if IsUnitFramesMemberWindowName(contextWindow) then
                -- Delegate to stock to preserve slider min/max and behavior parity.
                m_stockOnMenuClickSetBackgroundOpacity()
                return
            end

            m_stockOnMenuClickSetBackgroundOpacity()
        end
    end

    if type(BattlegroupHUD) == "table"
    and type(BattlegroupHUD.OnOpacitySlide) == "function"
    and m_stockOnOpacitySlide == nil then
        m_stockOnOpacitySlide = BattlegroupHUD.OnOpacitySlide
        BattlegroupHUD.OnOpacitySlide = function(slidePos)
            local contextWindow = BattlegroupHUD.contextMenuOpenedFrom
            if IsUnitFramesMemberWindowName(contextWindow) then
                local resolvedAlpha = ClampAlpha(slidePos)
                UnitFrames.WindowSettings.backgroundAlpha = resolvedAlpha
                SetUnitFramesBackgroundAlpha(resolvedAlpha)
                return
            end

            m_stockOnOpacitySlide(slidePos)
        end
    end

    if not m_eventsRegistered and DoesWindowExist(c_ROOT_WINDOW_NAME) then
        WindowRegisterEventHandler(c_ROOT_WINDOW_NAME, SystemData.Events.BATTLEGROUP_UPDATED, "CustomUI.UnitFrames.OnVisibilityStateChanged")
        WindowRegisterEventHandler(c_ROOT_WINDOW_NAME, SystemData.Events.BATTLEGROUP_MEMBER_UPDATED, "CustomUI.UnitFrames.OnWarbandMemberUpdated")
        WindowRegisterEventHandler(c_ROOT_WINDOW_NAME, SystemData.Events.SCENARIO_PLAYERS_LIST_GROUPS_UPDATED, "CustomUI.UnitFrames.OnVisibilityStateChanged")
        WindowRegisterEventHandler(c_ROOT_WINDOW_NAME, SystemData.Events.SCENARIO_PLAYER_HITS_UPDATED, "CustomUI.UnitFrames.OnVisibilityStateChanged")
        WindowRegisterEventHandler(c_ROOT_WINDOW_NAME, SystemData.Events.SCENARIO_BEGIN, "CustomUI.UnitFrames.OnVisibilityStateChanged")
        WindowRegisterEventHandler(c_ROOT_WINDOW_NAME, SystemData.Events.CITY_SCENARIO_BEGIN, "CustomUI.UnitFrames.OnVisibilityStateChanged")
        WindowRegisterEventHandler(c_ROOT_WINDOW_NAME, SystemData.Events.SCENARIO_END, "CustomUI.UnitFrames.OnVisibilityStateChanged")
        WindowRegisterEventHandler(c_ROOT_WINDOW_NAME, SystemData.Events.CITY_SCENARIO_END, "CustomUI.UnitFrames.OnVisibilityStateChanged")
        WindowRegisterEventHandler(c_ROOT_WINDOW_NAME, SystemData.Events.PLAYER_TARGET_UPDATED, "CustomUI.UnitFrames.OnTargetUpdated")
        m_eventsRegistered = true
    end
end

function UnitFrames.Enable()
    m_enabled = true
    m_visibilityPollElapsed = 0
    UnitFrames.InitializeWindow()

    if not m_windowsInitialized then
        return true
    end

    ApplyModeVisibility()
    RefreshMouseOverBorders()

    local alpha = UnitFrames.WindowSettings.backgroundAlpha
    if alpha == nil then
        alpha = c_DEFAULT_BACKGROUND_ALPHA
    else
        alpha = ClampAlpha(alpha)
    end

    if alpha ~= nil then
        SetUnitFramesBackgroundAlpha(alpha)
    end

    return true
end

function UnitFrames.Disable()
    m_enabled = false
    m_mouseOverMemberWindow = nil
    RefreshMouseOverBorders()
    m_visibilityPollElapsed = 0
    HideCustomShowStock()

    return true
end

function UnitFrames.Shutdown()
    if m_eventsRegistered and DoesWindowExist(c_ROOT_WINDOW_NAME) then
        WindowUnregisterEventHandler(c_ROOT_WINDOW_NAME, SystemData.Events.BATTLEGROUP_UPDATED)
        WindowUnregisterEventHandler(c_ROOT_WINDOW_NAME, SystemData.Events.BATTLEGROUP_MEMBER_UPDATED)
        WindowUnregisterEventHandler(c_ROOT_WINDOW_NAME, SystemData.Events.SCENARIO_PLAYERS_LIST_GROUPS_UPDATED)
        WindowUnregisterEventHandler(c_ROOT_WINDOW_NAME, SystemData.Events.SCENARIO_PLAYER_HITS_UPDATED)
        WindowUnregisterEventHandler(c_ROOT_WINDOW_NAME, SystemData.Events.SCENARIO_BEGIN)
        WindowUnregisterEventHandler(c_ROOT_WINDOW_NAME, SystemData.Events.CITY_SCENARIO_BEGIN)
        WindowUnregisterEventHandler(c_ROOT_WINDOW_NAME, SystemData.Events.SCENARIO_END)
        WindowUnregisterEventHandler(c_ROOT_WINDOW_NAME, SystemData.Events.CITY_SCENARIO_END)
    end
    m_eventsRegistered = false

    if m_stockOnMenuClickSetBackgroundOpacity ~= nil then
        if type(BattlegroupHUD) == "table" then
            BattlegroupHUD.OnMenuClickSetBackgroundOpacity = m_stockOnMenuClickSetBackgroundOpacity
        end
        m_stockOnMenuClickSetBackgroundOpacity = nil
    end

    if m_stockOnOpacitySlide ~= nil then
        if type(BattlegroupHUD) == "table" then
            BattlegroupHUD.OnOpacitySlide = m_stockOnOpacitySlide
        end
        m_stockOnOpacitySlide = nil
    end
end

local function ResetUnitFramesWindowDefaults()
    if type(CustomUI.ResetWindowToDefault) == "function" then
        CustomUI.ResetWindowToDefault(c_ROOT_WINDOW_NAME)
        for groupIndex = 1, c_MAX_GROUP_WINDOWS do
            CustomUI.ResetWindowToDefault(GroupWindowName(groupIndex))
        end
        return
    end

    if DoesWindowExist(c_ROOT_WINDOW_NAME) then
        WindowRestoreDefaultSettings(c_ROOT_WINDOW_NAME)
    end

    for groupIndex = 1, c_MAX_GROUP_WINDOWS do
        local groupWindow = GroupWindowName(groupIndex)
        if DoesWindowExist(groupWindow) then
            WindowRestoreDefaultSettings(groupWindow)
        end
    end
end

local UnitFramesComponent = {
    Name = "UnitFrames",
    WindowName = c_ROOT_WINDOW_NAME,
    DefaultEnabled = false,
}

function UnitFramesComponent:Initialize()
    UnitFrames.Initialize()
end

function UnitFramesComponent:Enable()
    return UnitFrames.Enable()
end

function UnitFramesComponent:Disable()
    return UnitFrames.Disable()
end

function UnitFramesComponent:ResetToDefaults()
    UnitFrames.WindowSettings.backgroundAlpha = nil

    ResetUnitFramesWindowDefaults()
    SetStockWarbandBackgroundAlpha(c_DEFAULT_BACKGROUND_ALPHA)

    if m_enabled and m_windowsInitialized then
        ApplyModeVisibility()
        SetUnitFramesBackgroundAlpha(c_DEFAULT_BACKGROUND_ALPHA)
    end

    return true
end

function UnitFramesComponent:Shutdown()
    UnitFrames.Shutdown()
end
CustomUI.RegisterComponent("UnitFrames", UnitFramesComponent)
