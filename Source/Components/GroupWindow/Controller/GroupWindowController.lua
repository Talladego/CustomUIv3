----------------------------------------------------------------
-- CustomUI.GroupWindow — Controller
-- Responsibilities: RegisterComponent, roster/status polling, event handlers, and row
--   rendering in one place. There is no View/<Name>.lua; member rows are drawn here to keep
--   a single file next to the stock GroupMemberUnitFrame template. If this grows, extract
--   pure Label/Window/StatusBar calls into View/GroupWindow.lua and call from the controller.
-- CustomUI.mod loads this file before View/GroupWindow.xml; do not <Script> this controller
--   a second time in the XML.
----------------------------------------------------------------

if not CustomUI.GroupWindow then
    CustomUI.GroupWindow = {}
end

----------------------------------------------------------------
-- Constants
----------------------------------------------------------------

local c_WINDOW_NAME       = "CustomUIGroupWindow"
local c_STOCK_WINDOW_NAME = "GroupWindow"
local c_MAX_GROUP_MEMBERS = 5
local c_MEMBER_ROW_PREFIX = "CustomUIGroupWindowMember"
local c_MEMBER_ROW_SCALE = 1.0
local c_BUFF_SLOTS_PER_MEMBER = 20
local c_BUFF_ROW_STRIDE = 20
local c_MEMBER_BUFF_ICON_SCALE = 0.85
local c_MEMBER_HEALTH_TEXT_WIDTH = 132
local c_MEMBER_HEALTH_TEXT_HEIGHT = 21
local c_MEMBER_HEALTH_TEXT_SCALE = 0.9
local c_MEMBER_RVR_OFFSET_X = 0
local c_MEMBER_RVR_OFFSET_Y = 25
local c_MEMBER_RVR_RELATIVE_SCALE = 0.55
local c_FADE_OUT_ANIM_DELAY = 2
local c_STATUS_POLL_INTERVAL = 0.25

local c_MORALE_SLICE_BY_LEVEL = {
    [1] = "Morale-Mini-1",
    [2] = "Morale-Mini-2",
    [3] = "Morale-Mini-3",
    [4] = "Morale-Mini-4",
}

local c_DISTANT_LABEL_TEXT = GetString(StringTables.Default.LABEL_PARTY_MEMBER_IS_DISTANT)
local c_OFFLINE_LABEL_TEXT = GetString(StringTables.Default.LABEL_PARTY_MEMBER_OFFLINE)

----------------------------------------------------------------
-- Module state
----------------------------------------------------------------

local m_enabled                  = false
local m_stockGroupRegistered     = false
local m_groupData                = nil
local m_hasWorldGroup            = false
local m_memberBuffTrackers       = {}
local m_memberRvrIndicators      = {}
local m_memberStatusSnapshot     = {}
local m_memberStatusSource       = {}
local m_lastRosterNames          = {}
local m_lastRosterSignature      = nil
local m_hitPointAlerts           = {}
local m_fadeOutAnimationDelay    = {}
local m_isFadeIn                 = {}
local m_isMouseOverMember        = {}
local m_memberHealthTextLayoutApplied = {}
local m_statusPollElapsed        = 0

----------------------------------------------------------------
-- Helpers
----------------------------------------------------------------

local function IsMemberValid(index)
    return (m_groupData ~= nil
        and m_groupData[index] ~= nil
        and m_groupData[index].name ~= nil
        and m_groupData[index].name ~= L"")
end

local function MemberRowName(index)
    return c_MEMBER_ROW_PREFIX .. index
end

local function MemberNameLabelName(index)
    return MemberRowName(index) .. "Name"
end

local function MemberLevelLabelName(index)
    return MemberRowName(index) .. "LevelText"
end

local function MemberHealthBarName(index)
    return MemberRowName(index) .. "HealthPercentBar"
end

local function MemberActionBarName(index)
    return MemberRowName(index) .. "APPercentBar"
end

local function MemberHealthBarFrameName(index)
    return MemberRowName(index) .. "HealthBarFrame"
end

local function MemberHealthBarBackgroundName(index)
    return MemberRowName(index) .. "HealthBarBG"
end

local function MemberActionBarFrameName(index)
    return MemberRowName(index) .. "APBarFrame"
end

local function MemberActionBarBackgroundName(index)
    return MemberRowName(index) .. "APBarBG"
end

local function MemberHealthTextName(index)
    return MemberRowName(index) .. "HealthText"
end

local function MemberActionTextName(index)
    return MemberRowName(index) .. "APText"
end

local function MemberOfflineTextName(index)
    return MemberRowName(index) .. "OfflineText"
end

local function MemberDistantTextName(index)
    return MemberRowName(index) .. "DistantText"
end

local function MemberDeathPortraitName(index)
    return MemberRowName(index) .. "DeathPortrait"
end

local function MemberPortraitName(index)
    return MemberRowName(index) .. "Portrait"
end

local function MemberGroupLeaderCrownName(index)
    return MemberRowName(index) .. "GroupLeaderCrown"
end

local function MemberMainAssistCrownName(index)
    return MemberRowName(index) .. "MainAssistCrown"
end

local function MemberWarbandLeaderCrownName(index)
    return MemberRowName(index) .. "WarbandLeaderCrown"
end

local function MemberMoraleMiniName(index)
    return MemberRowName(index) .. "MoraleMini"
end

local function MemberCareerIconName(index)
    return MemberRowName(index) .. "CareerIcon"
end

local function MemberPortraitFrameName(index)
    return MemberRowName(index) .. "PortraitFrame"
end

local function MemberBuffWindowNamePrefix(index)
    return "CustomUIGroup" .. index .. "Buffs"
end

local function MemberBuffTargetType(index)
    return GameData.BuffTargetType.GROUP_MEMBER_START + (index - 1)
end

local function ResolveFadeOutDelay()
    if PlayerWindow and PlayerWindow.FADE_OUT_ANIM_DELAY then
        return PlayerWindow.FADE_OUT_ANIM_DELAY
    end

    return c_FADE_OUT_ANIM_DELAY
end

local function GetMemberIndexFromWindowName(windowName)
    if type(windowName) ~= "string" then
        return nil
    end

    local index = tonumber(string.match(windowName, "^" .. c_MEMBER_ROW_PREFIX .. "(%d+)"))
    if index ~= nil and index >= 1 and index <= c_MAX_GROUP_MEMBERS then
        return index
    end

    return nil
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

local function EnsureMemberRvrIndicator(index)
    local indicator = m_memberRvrIndicators[index]
    if indicator ~= nil then
        return indicator
    end

    if type(RvRIndicator) ~= "table" or type(RvRIndicator.Create) ~= "function" then
        return nil
    end

    indicator = RvRIndicator:Create(MemberRowName(index) .. "RvRFlagIndicator", MemberRowName(index))
    if indicator == nil then
        return nil
    end

    indicator:SetAnchor({
        Point = "top",
        RelativePoint = "center",
        RelativeTo = MemberPortraitName(index),
        XOffset = c_MEMBER_RVR_OFFSET_X,
        YOffset = c_MEMBER_RVR_OFFSET_Y,
    })
    indicator:SetRelativeScale(c_MEMBER_RVR_RELATIVE_SCALE)
    indicator:SetTargetType(SystemData.TargetObjectType.ALLY_PLAYER)

    m_memberRvrIndicators[index] = indicator
    return indicator
end

local function SetMemberRvrIndicatorShowing(index, isShowing)
    local indicator = EnsureMemberRvrIndicator(index)
    if indicator ~= nil then
        indicator:SetAnchor({
            Point = "top",
            RelativePoint = "center",
            RelativeTo = MemberPortraitName(index),
            XOffset = c_MEMBER_RVR_OFFSET_X,
            YOffset = c_MEMBER_RVR_OFFSET_Y,
        })
        indicator:SetTargetType(SystemData.TargetObjectType.ALLY_PLAYER)
        indicator:Show(isShowing == true)
    end
end

local function ShutdownMemberRvrIndicators()
    for index = 1, c_MAX_GROUP_MEMBERS do
        local indicator = m_memberRvrIndicators[index]
        if indicator ~= nil and type(indicator.Destroy) == "function" then
            indicator:Destroy()
        end
        m_memberRvrIndicators[index] = nil
    end
end

local function UpdateMemberAnchors()
    for index = 1, c_MAX_GROUP_MEMBERS do
        local rowWindow = MemberRowName(index)
        WindowClearAnchors(rowWindow)

        if index == 1 then
            WindowAddAnchor(rowWindow, "topleft", c_WINDOW_NAME, "topleft", 0, 3)
        else
            local previousIndex = index - 1
            local yOffset = 3
            WindowAddAnchor(rowWindow, "bottomleft", MemberPortraitFrameName(previousIndex), "topleft", 0, yOffset)
        end
    end
end

local RefreshGroupState

local function ReadCurrentRosterNames()
    local names = {}
    for index = 1, c_MAX_GROUP_MEMBERS do
        local name = ""
        if IsMemberValid(index) then
            name = tostring(m_groupData[index].name or "")
        end
        names[index] = name
    end
    return names
end

local function BuildRosterSignature(names)
    return table.concat(names, ";")
end

local function BuildMemberStatusSnapshot(member)
    if member == nil or member.name == nil or member.name == L"" then
        return nil
    end

    return table.concat({
        tostring(member.name),
        tostring(member.healthPercent),
        tostring(member.actionPointPercent),
        tostring(member.moraleLevel),
        tostring(member.level),
        tostring(member.battleLevel),
        tostring(member.online),
        tostring(member.isDistant),
        tostring(member.isInSameRegion),
    }, "|")
end

local function ApplyRawMemberStatus(member, status)
    if member == nil or status == nil then
        return
    end

    member.healthPercent = status.healthPercent
    member.actionPointPercent = status.actionPointPercent
    member.moraleLevel = status.moraleLevel
    member.level = status.level
    member.battleLevel = status.battleLevel
    member.isRVRFlagged = status.isRVRFlagged
    member.zoneNum = status.zoneNum
    member.online = status.online
    member.isDistant = status.isDistant
    member.worldObjNum = status.worldObjNum
end

local function TryGetRawMemberStatus(index)
    if type(GetGroupMemberStatusData) ~= "function" then
        return nil
    end

    return GetGroupMemberStatusData(index)
end

local function IsHarnessActive()
    local harness = CustomUI.GroupWindowTestHarness
    return harness ~= nil
        and type(harness.IsEnabled) == "function"
        and harness.IsEnabled()
end

local function CopyBuffTable(sourceBuffs)
    local copied = {}
    if sourceBuffs == nil then
        return copied
    end

    for buffId, buffData in pairs(sourceBuffs) do
        if buffData ~= nil then
            local cloned = {}
            for key, value in pairs(buffData) do
                cloned[key] = value
            end
            copied[buffId] = cloned
        end
    end

    return copied
end

local function BuildHarnessBuffUpdateTable()
    if not IsHarnessActive() then
        return nil
    end

    if type(GetBuffs) ~= "function"
    or GameData == nil
    or GameData.BuffTargetType == nil
    or GameData.BuffTargetType.SELF == nil then
        return {}
    end

    local selfBuffs = GetBuffs(GameData.BuffTargetType.SELF)
    return CopyBuffTable(selfBuffs)
end

local function RefreshMemberStatus(index)
    local member = nil
    if m_groupData ~= nil then
        member = m_groupData[index]
    end

    if IsHarnessActive() then
        m_memberStatusSource[index] = "harness"

        local snapshot = BuildMemberStatusSnapshot(member)
        local didChange = (m_memberStatusSnapshot[index] ~= snapshot)
        m_memberStatusSnapshot[index] = snapshot
        return didChange
    end

    if member == nil then
        member = PartyUtils.GetPartyMember(index)
    end

    local rawStatus = TryGetRawMemberStatus(index)
    if rawStatus ~= nil then
        ApplyRawMemberStatus(member, rawStatus)
        m_memberStatusSource[index] = "raw"
    elseif member == nil then
        member = PartyUtils.GetPartyMember(index)
        m_memberStatusSource[index] = "partyutils"
    else
        m_memberStatusSource[index] = "partyutils"
    end

    if m_groupData ~= nil then
        m_groupData[index] = member
    end

    local snapshot = BuildMemberStatusSnapshot(member)
    local didChange = (m_memberStatusSnapshot[index] ~= snapshot)
    m_memberStatusSnapshot[index] = snapshot
    return didChange
end

local function RefreshAllMemberStatuses()
    RefreshGroupState()

    local didAnyChange = false
    for index = 1, c_MAX_GROUP_MEMBERS do
        if RefreshMemberStatus(index) then
            didAnyChange = true
        end
    end

    return didAnyChange
end

local function ShowMemberBars(index, isShowing)
    WindowSetShowing(MemberHealthBarName(index), isShowing)
    WindowSetShowing(MemberHealthBarFrameName(index), isShowing)
    WindowSetShowing(MemberHealthBarBackgroundName(index), isShowing)
    WindowSetShowing(MemberActionBarName(index), isShowing)
    WindowSetShowing(MemberActionBarFrameName(index), isShowing)
    WindowSetShowing(MemberActionBarBackgroundName(index), isShowing)
end

local function ShouldPreventHealthBarFade()
    return SystemData
        and SystemData.Settings
        and SystemData.Settings.GamePlay
        and SystemData.Settings.GamePlay.preventHealthBarFade == true
end

local function ForceMemberBarsVisible(index)
    m_fadeOutAnimationDelay[index] = 0
    m_isFadeIn[index] = true

    WindowStopAlphaAnimation(MemberHealthBarName(index))
    WindowStopAlphaAnimation(MemberHealthBarFrameName(index))
    WindowStopAlphaAnimation(MemberHealthBarBackgroundName(index))
    WindowStopAlphaAnimation(MemberActionBarName(index))
    WindowStopAlphaAnimation(MemberActionBarFrameName(index))
    WindowStopAlphaAnimation(MemberActionBarBackgroundName(index))

    ShowMemberBars(index, true)
    WindowSetAlpha(MemberHealthBarName(index), 1.0)
    WindowSetAlpha(MemberHealthBarFrameName(index), 1.0)
    WindowSetAlpha(MemberHealthBarBackgroundName(index), 1.0)
    WindowSetAlpha(MemberActionBarName(index), 1.0)
    WindowSetAlpha(MemberActionBarFrameName(index), 1.0)
    WindowSetAlpha(MemberActionBarBackgroundName(index), 1.0)
end

local function PerformMemberFadeIn(index, currentAlpha)
    m_fadeOutAnimationDelay[index] = 0
    m_isFadeIn[index] = true

    WindowStartAlphaAnimation(MemberHealthBarName(index), Window.AnimationType.SINGLE_NO_RESET, currentAlpha, 1.0, 0.5, false, 0, 0)
    WindowStartAlphaAnimation(MemberHealthBarFrameName(index), Window.AnimationType.SINGLE_NO_RESET, currentAlpha, 1.0, 0.5, false, 0, 0)
    WindowStartAlphaAnimation(MemberHealthBarBackgroundName(index), Window.AnimationType.SINGLE_NO_RESET, currentAlpha, 1.0, 0.5, false, 0, 0)
    WindowStartAlphaAnimation(MemberActionBarName(index), Window.AnimationType.SINGLE_NO_RESET, currentAlpha, 1.0, 0.5, false, 0, 0)
    WindowStartAlphaAnimation(MemberActionBarFrameName(index), Window.AnimationType.SINGLE_NO_RESET, currentAlpha, 1.0, 0.5, false, 0, 0)
    WindowStartAlphaAnimation(MemberActionBarBackgroundName(index), Window.AnimationType.SINGLE_NO_RESET, currentAlpha, 1.0, 0.5, false, 0, 0)
end

local function PerformMemberFadeOut(index)
    m_fadeOutAnimationDelay[index] = 0
    m_isFadeIn[index] = false

    WindowStartAlphaAnimation(MemberHealthBarName(index), Window.AnimationType.SINGLE_NO_RESET_HIDE, 1.0, 0.0, 2.0, false, 0, 0)
    WindowStartAlphaAnimation(MemberHealthBarFrameName(index), Window.AnimationType.SINGLE_NO_RESET_HIDE, 1.0, 0.0, 2.0, false, 0, 0)
    WindowStartAlphaAnimation(MemberHealthBarBackgroundName(index), Window.AnimationType.SINGLE_NO_RESET_HIDE, 1.0, 0.0, 2.0, false, 0, 0)
    WindowStartAlphaAnimation(MemberActionBarName(index), Window.AnimationType.SINGLE_NO_RESET_HIDE, 1.0, 0.0, 2.0, false, 0, 0)
    WindowStartAlphaAnimation(MemberActionBarFrameName(index), Window.AnimationType.SINGLE_NO_RESET_HIDE, 1.0, 0.0, 2.0, false, 0, 0)
    WindowStartAlphaAnimation(MemberActionBarBackgroundName(index), Window.AnimationType.SINGLE_NO_RESET_HIDE, 1.0, 0.0, 2.0, false, 0, 0)
end

local function UpdateMemberBarVisibility(index, hp, ap)
    if ShouldPreventHealthBarFade() then
        ForceMemberBarsVisible(index)
        return
    end

    if m_isMouseOverMember[index] == true then
        local currentAlpha = WindowGetAlpha(MemberHealthBarFrameName(index))
        m_fadeOutAnimationDelay[index] = 0
        if (currentAlpha == 0.0) or ((currentAlpha < 1.0) and not m_isFadeIn[index]) then
            ShowMemberBars(index, true)
            PerformMemberFadeIn(index, currentAlpha)
        end
        return
    end

    local isStatusBarFull = (hp == 100 and ap == 100)
    local currentAlpha = WindowGetAlpha(MemberHealthBarFrameName(index))

    if not isStatusBarFull then
        m_fadeOutAnimationDelay[index] = 0
        if (currentAlpha == 0.0) or ((currentAlpha < 1.0) and not m_isFadeIn[index]) then
            ShowMemberBars(index, true)
            PerformMemberFadeIn(index, currentAlpha)
        end
    else
        if (m_fadeOutAnimationDelay[index] == 0)
        and ((currentAlpha == 1) or ((currentAlpha > 0.0) and m_isFadeIn[index])) then
            m_fadeOutAnimationDelay[index] = ResolveFadeOutDelay()
        end
    end
end

local function DestroyStaleMemberBuffWindows(index)
    -- Container window owns all slot windows; destroying it removes everything.
    local containerName = MemberBuffWindowNamePrefix(index)
    if DoesWindowExist(containerName) then
        DestroyWindow(containerName)
    end
end

local function EnsureMemberBuffTracker(index)
    if m_memberBuffTrackers[index] ~= nil then
        return m_memberBuffTrackers[index]
    end

    -- Buff slot windows persist across /reloadui; destroy stale instances first.
    DestroyStaleMemberBuffWindows(index)

    local tracker = CustomUI.BuffTracker:Create(
        MemberBuffWindowNamePrefix(index),
        "Root",
        MemberBuffTargetType(index),
        c_BUFF_SLOTS_PER_MEMBER,
        c_BUFF_ROW_STRIDE,
        SHOW_BUFF_FRAME_TIMER_LABELS
    )

    CustomUI.BuffTracker.ApplyPlayerStatusRules(tracker)
    tracker:SetFilter(CustomUI.GroupWindow.GetSettings().buffs)

    -- Anchor container below the action bar for this member row.
    local containerName = MemberBuffWindowNamePrefix(index)
    WindowClearAnchors(containerName)
    WindowAddAnchor(containerName, "bottomleft", MemberActionBarName(index), "topleft", 8, 4)

    -- Group portraits are smaller than player status portrait, so scale buff icons down.
    tracker:SetScale(c_MEMBER_BUFF_ICON_SCALE)
    tracker:Show(true)

    m_memberBuffTrackers[index] = tracker
    return tracker
end

local function ClearMemberBuffs(index)
    local tracker = m_memberBuffTrackers[index]
    if tracker ~= nil then
        tracker:Clear()
    end
end

local function HideMemberBuffs(index)
    local tracker = m_memberBuffTrackers[index]
    if tracker ~= nil then
        tracker:Show(false)
    end
end

local function ResetMemberBuffs(index)
    ClearMemberBuffs(index)
    HideMemberBuffs(index)
end

local function ClearAllMemberBuffs()
    for index = 1, c_MAX_GROUP_MEMBERS do
        ClearMemberBuffs(index)
    end
end

local function ShutdownMemberBuffTrackers()
    for index = 1, c_MAX_GROUP_MEMBERS do
        local tracker = m_memberBuffTrackers[index]
        if tracker ~= nil then
            tracker:Shutdown()
            m_memberBuffTrackers[index] = nil
        end

        DestroyStaleMemberBuffWindows(index)
    end
end

local function HideAllMemberRows()
    for index = 1, c_MAX_GROUP_MEMBERS do
        WindowSetShowing(MemberRowName(index), false)
        m_isMouseOverMember[index] = false
        SetMemberRvrIndicatorShowing(index, false)
        ResetMemberBuffs(index)
    end
end

local function ApplyMemberHealthTextLayoutOverride(index)
    local healthText = MemberHealthTextName(index)

    LabelSetTextAlign(healthText, "center")
    WindowSetScale(healthText, c_MEMBER_HEALTH_TEXT_SCALE)
    WindowSetDimensions(healthText, c_MEMBER_HEALTH_TEXT_WIDTH, c_MEMBER_HEALTH_TEXT_HEIGHT)
    WindowClearAnchors(healthText)
    WindowAddAnchor(healthText, "center", MemberHealthBarFrameName(index), "center", 0, 0)
end

local function EnsureMemberHealthTextLayoutOverride(index)
    if m_memberHealthTextLayoutApplied[index] == true then
        return
    end

    ApplyMemberHealthTextLayoutOverride(index)
    m_memberHealthTextLayoutApplied[index] = true
end

local function UpdateMemberRow(index)
    local rowWindow = MemberRowName(index)
    local nameLabel = MemberNameLabelName(index)
    local levelLabel = MemberLevelLabelName(index)
    local healthBar = MemberHealthBarName(index)
    local actionBar = MemberActionBarName(index)
    local healthText = MemberHealthTextName(index)
    local actionText = MemberActionTextName(index)
    local offlineText = MemberOfflineTextName(index)
    local distantText = MemberDistantTextName(index)
    local deathPortrait = MemberDeathPortraitName(index)
    local portrait = MemberPortraitName(index)
    local groupLeaderCrown = MemberGroupLeaderCrownName(index)
    local mainAssistCrown = MemberMainAssistCrownName(index)
    local warbandLeaderCrown = MemberWarbandLeaderCrownName(index)
    local moraleMini = MemberMoraleMiniName(index)
    local careerIcon = MemberCareerIconName(index)

    if not IsMemberValid(index) then
        WindowSetShowing(rowWindow, false)
        m_isMouseOverMember[index] = false
        SetMemberRvrIndicatorShowing(index, false)
        ResetMemberBuffs(index)
        return
    end

    local member = m_groupData[index]
    local hp = ClampPercent(member.healthPercent)
    local ap = ClampPercent(member.actionPointPercent)
    local level = tonumber(member.level) or 0
    local moraleLevel = tonumber(member.moraleLevel) or 0
    local isDead = (hp <= 0)

    WindowSetShowing(rowWindow, true)
    WindowSetScale(rowWindow, WindowGetScale(c_WINDOW_NAME))
    EnsureMemberHealthTextLayoutOverride(index)
    LabelSetText(nameLabel, member.name)
    LabelSetText(levelLabel, towstring(level))
    WindowSetGameActionData(rowWindow, GameData.PlayerActions.SET_TARGET, 0, member.name)
    LabelSetText(offlineText, c_OFFLINE_LABEL_TEXT)
    LabelSetText(distantText, c_DISTANT_LABEL_TEXT)
    LabelSetTextAlign(offlineText, "leftcenter")
    LabelSetTextAlign(distantText, "leftcenter")
    LabelSetText(healthText, towstring(hp) .. L"%")

    StatusBarSetMaximumValue(healthBar, 100)
    StatusBarSetCurrentValue(healthBar, hp)
    StatusBarSetMaximumValue(actionBar, 100)
    StatusBarSetCurrentValue(actionBar, ap)

    WindowSetShowing(healthText, true)
    WindowSetShowing(actionText, false)

    if hp < 20 then
        if m_hitPointAlerts[index] ~= true then
            WindowSetShowing(healthBar, true)
            WindowStartAlphaAnimation(healthBar, Window.AnimationType.LOOP, 0.5, 1.0, 0.5, false, 0, 0)
            m_hitPointAlerts[index] = true
        end
    else
        if m_hitPointAlerts[index] == true then
            WindowStopAlphaAnimation(healthBar)
            m_hitPointAlerts[index] = false
        end
    end

    UpdateMemberBarVisibility(index, hp, ap)

    local isOffline = (member.online ~= true)
    local isDistant = (member.isDistant and member.online == true)

    WindowSetShowing(offlineText, isOffline)
    if member.online == true then
        WindowSetAlpha(rowWindow, 1.0)
        WindowSetFontAlpha(rowWindow, 1.0)
    else
        WindowSetAlpha(rowWindow, 0.5)
        WindowSetFontAlpha(rowWindow, 0.5)
        WindowSetShowing(distantText, false)
        WindowSetTintColor(rowWindow, 255, 255, 255)
    end

    if isDistant then
        WindowSetShowing(distantText, true)
        LabelSetText(distantText, c_DISTANT_LABEL_TEXT)
        WindowSetShowing(healthText, false)
        WindowSetTintColor(rowWindow, 100, 100, 200)
    elseif not isOffline then
        WindowSetShowing(distantText, false)
        WindowSetShowing(healthText, true)
        WindowSetTintColor(rowWindow, 255, 255, 255)
    else
        WindowSetShowing(distantText, false)
        WindowSetShowing(healthText, false)
        WindowSetTintColor(rowWindow, 255, 255, 255)
    end

    WindowSetShowing(deathPortrait, isDead)
    WindowSetShowing(portrait, not isDead)

    WindowSetShowing(groupLeaderCrown, member.isGroupLeader == true)
    WindowSetShowing(mainAssistCrown, member.isMainAssist == true)
    WindowSetShowing(warbandLeaderCrown, member.isWarbandLeader == true)
    SetMemberRvrIndicatorShowing(index, member.isRVRFlagged == true)

    if member.careerLine ~= nil then
        local iconId = Icons.GetCareerIconIDFromCareerLine(member.careerLine)
        if iconId ~= nil then
            local iconTexture, iconX, iconY = GetIconData(iconId)
            DynamicImageSetTexture(careerIcon, iconTexture, iconX, iconY)
        end
    end
    WindowSetShowing(careerIcon, not IsWarBandActive())

    if moraleLevel >= 1 and moraleLevel <= 4 then
        DynamicImageSetTextureSlice(moraleMini, c_MORALE_SLICE_BY_LEVEL[moraleLevel])
        WindowSetShowing(moraleMini, true)
    else
        WindowSetShowing(moraleMini, false)
    end

    CircleImageSetTexture(portrait, "render_scene_group_portrait" .. index, 40, 54)

    local tracker = EnsureMemberBuffTracker(index)
    if tracker ~= nil then
        tracker:Show(true)

        if IsHarnessActive() then
            tracker:UpdateBuffs(BuildHarnessBuffUpdateTable(), true)
        end
    end

end

local function UpdateMemberRows()
    UpdateMemberAnchors()

    for index = 1, c_MAX_GROUP_MEMBERS do
        UpdateMemberRow(index)
    end
end

local function EnsureStockGroupWindowRegistered()
    if m_stockGroupRegistered then
        return true
    end

    if not DoesWindowExist(c_STOCK_WINDOW_NAME) then
        return false
    end

    if LayoutEditor.windowsList[c_STOCK_WINDOW_NAME] == nil then
        LayoutEditor.RegisterWindow(
            c_STOCK_WINDOW_NAME,
            L"Group Window (stock)",
            L"Stock group window hidden while CustomUI GroupWindow is enabled.",
            false,
            false,
            true,
            nil
        )
    end

    m_stockGroupRegistered = (LayoutEditor.windowsList[c_STOCK_WINDOW_NAME] ~= nil)
    return m_stockGroupRegistered
end

RefreshGroupState = function()
    local harness = CustomUI.GroupWindowTestHarness
    if harness
    and type(harness.IsEnabled) == "function"
    and harness.IsEnabled()
    and type(harness.GetGroupData) == "function" then
        m_groupData = harness.GetGroupData() or {}
        m_hasWorldGroup = IsMemberValid(1)
        return
    end

    m_groupData = PartyUtils.GetPartyData()
    m_hasWorldGroup = IsMemberValid(1)
end

local function ShouldShowContainer()
    if not m_enabled then
        return false
    end

    if not m_hasWorldGroup then
        return false
    end

    local hideForWarband = IsWarBandActive()
        and not GameData.Player.isInScenario
        and not GameData.Player.isInSiege

    return not hideForWarband
end

local function UpdateContainerVisibility()
    local shouldShow = ShouldShowContainer()
    WindowSetShowing(c_WINDOW_NAME, shouldShow)

    if shouldShow then
        UpdateMemberRows()
        for index = 1, c_MAX_GROUP_MEMBERS do
            local tracker = m_memberBuffTrackers[index]
            if tracker ~= nil and IsMemberValid(index) then
                tracker:Refresh()
            end
        end
    else
        HideAllMemberRows()
    end
end

----------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------

function CustomUI.GroupWindow.Initialize()
    LayoutEditor.RegisterWindow(
        c_WINDOW_NAME,
        L"CustomUI: Group Window",
        L"CustomUI group window scaffold.",
        false,
        false,
        true,
        nil
    )

    -- Hidden until component Enable().
    LayoutEditor.UserHide(c_WINDOW_NAME)

    -- Set default anchor near player frame. This is applied once; user layout can override.
    WindowClearAnchors(c_WINDOW_NAME)
    WindowAddAnchor(c_WINDOW_NAME, "bottomleft", "PlayerWindowPortraitFrame", "topleft", 0, 48)

    WindowRegisterEventHandler(c_WINDOW_NAME, SystemData.Events.GROUP_UPDATED, "CustomUI.GroupWindow.OnGroupUpdated")
    WindowRegisterEventHandler(c_WINDOW_NAME, SystemData.Events.BATTLEGROUP_UPDATED, "CustomUI.GroupWindow.OnGroupUpdated")
    WindowRegisterEventHandler(c_WINDOW_NAME, SystemData.Events.GROUP_PLAYER_ADDED, "CustomUI.GroupWindow.OnGroupPlayerAdded")
    WindowRegisterEventHandler(c_WINDOW_NAME, SystemData.Events.GROUP_STATUS_UPDATED, "CustomUI.GroupWindow.OnStatusUpdated")
    WindowRegisterEventHandler(c_WINDOW_NAME, SystemData.Events.GROUP_EFFECTS_UPDATED, "CustomUI.GroupWindow.OnEffectsUpdated")
    WindowRegisterEventHandler(c_WINDOW_NAME, SystemData.Events.PLAYER_HEALTH_FADE_UPDATED, "CustomUI.GroupWindow.OnHealthFadeUpdated")
    WindowRegisterEventHandler(c_WINDOW_NAME, SystemData.Events.SCENARIO_BEGIN, "CustomUI.GroupWindow.OnScenarioBegin")
    WindowRegisterEventHandler(c_WINDOW_NAME, SystemData.Events.CITY_SCENARIO_BEGIN, "CustomUI.GroupWindow.OnScenarioBegin")
    WindowRegisterEventHandler(c_WINDOW_NAME, SystemData.Events.SCENARIO_END, "CustomUI.GroupWindow.OnScenarioEnd")
    WindowRegisterEventHandler(c_WINDOW_NAME, SystemData.Events.CITY_SCENARIO_END, "CustomUI.GroupWindow.OnScenarioEnd")
    for index = 1, c_MAX_GROUP_MEMBERS do
        m_hitPointAlerts[index] = false
        m_fadeOutAnimationDelay[index] = 0
        m_isFadeIn[index] = false
        m_isMouseOverMember[index] = false
        m_memberHealthTextLayoutApplied[index] = false
        m_memberStatusSnapshot[index] = nil
        DestroyStaleMemberBuffWindows(index)
    end

    m_statusPollElapsed = 0

    HideAllMemberRows()
    RefreshAllMemberStatuses()
    UpdateContainerVisibility()
end

function CustomUI.GroupWindow.Shutdown()
    HideAllMemberRows()
    ShutdownMemberBuffTrackers()
    ShutdownMemberRvrIndicators()
    m_groupData = nil
    m_hasWorldGroup = false

    m_hitPointAlerts = {}
    m_fadeOutAnimationDelay = {}
    m_isFadeIn = {}
    m_isMouseOverMember = {}
    m_memberHealthTextLayoutApplied = {}
    m_memberStatusSnapshot = {}
    m_memberStatusSource = {}
    m_memberRvrIndicators = {}
    m_lastRosterNames = {}
    m_lastRosterSignature = nil
    m_statusPollElapsed = 0
end

function CustomUI.GroupWindow.OnHidden()
    ClearAllMemberBuffs()
end

----------------------------------------------------------------
-- Event handlers
----------------------------------------------------------------

function CustomUI.GroupWindow.OnGroupUpdated()
    RefreshAllMemberStatuses()
    UpdateContainerVisibility()
end

function CustomUI.GroupWindow.OnGroupPlayerAdded()
    RefreshAllMemberStatuses()
    UpdateContainerVisibility()
end

function CustomUI.GroupWindow.OnEffectsUpdated(updateType, updatedEffects, isFullList)
    if not m_enabled then
        return
    end

    if updateType < GameData.BuffTargetType.GROUP_MEMBER_START
    or updateType > GameData.BuffTargetType.GROUP_MEMBER_END then
        return
    end

    local memberIndex = updateType - GameData.BuffTargetType.GROUP_MEMBER_START + 1
    local tracker = EnsureMemberBuffTracker(memberIndex)
    if tracker == nil then
        return
    end

    if not ShouldShowContainer()
    or not IsMemberValid(memberIndex)
    or not WindowGetShowing(MemberRowName(memberIndex)) then
        updatedEffects = {}
        isFullList = true
    end

    tracker:UpdateBuffs(updatedEffects, isFullList)
end

function CustomUI.GroupWindow.OnStatusUpdated(groupMemberIndex)
    RefreshGroupState()

    if groupMemberIndex ~= nil and ShouldShowContainer() then
        RefreshMemberStatus(groupMemberIndex)
        UpdateMemberRows()
    else
        RefreshAllMemberStatuses()
        UpdateContainerVisibility()
    end
end

function CustomUI.GroupWindow.OnHealthFadeUpdated()
    if ShouldShowContainer() then
        UpdateMemberRows()
    else
        UpdateContainerVisibility()
    end
end

function CustomUI.GroupWindow.OnScenarioBegin()
    UpdateContainerVisibility()
end

function CustomUI.GroupWindow.OnScenarioEnd()
    RefreshAllMemberStatuses()
    UpdateContainerVisibility()
end

function CustomUI.GroupWindow.Update(elapsedTime)
    if not m_enabled then
        return
    end

    m_statusPollElapsed = m_statusPollElapsed + (elapsedTime or 0)
    if m_statusPollElapsed >= c_STATUS_POLL_INTERVAL then
        m_statusPollElapsed = 0
        RefreshAllMemberStatuses()
        if ShouldShowContainer() then
            UpdateMemberRows()
        else
            UpdateContainerVisibility()
        end
    end

    for index = 1, c_MAX_GROUP_MEMBERS do
        if ShouldPreventHealthBarFade() then
            m_fadeOutAnimationDelay[index] = 0
        else
        local fadeDelay = m_fadeOutAnimationDelay[index] or 0
        if IsMemberValid(index) and fadeDelay > 0 then
            if WindowGetAlpha(MemberHealthBarFrameName(index)) == 1.0 then
                m_fadeOutAnimationDelay[index] = fadeDelay - elapsedTime
                if m_fadeOutAnimationDelay[index] <= 0 then
                    PerformMemberFadeOut(index)
                end
            end
        end
        end

        local tracker = m_memberBuffTrackers[index]
        if tracker ~= nil then
            tracker:Update(elapsedTime)
        end
    end
end

function CustomUI.GroupWindow.OnMemberMouseOver()
    local activeName = SystemData.ActiveWindow.name
    local memberIndex = GetMemberIndexFromWindowName(activeName)
    if not memberIndex or not IsMemberValid(memberIndex) then
        return
    end

    m_isMouseOverMember[memberIndex] = true
    UpdateMemberRow(memberIndex)

    local player = m_groupData[memberIndex]
    if not player then
        return
    end

    Tooltips.CreateTextOnlyTooltip(MemberRowName(memberIndex))
    Tooltips.SetTooltipText(1, 1, player.name)
    Tooltips.SetTooltipColorDef(1, 1, Tooltips.COLOR_HEADING)

    local levelString = PartyUtils.GetLevelText(player.level, player.battleLevel)
    Tooltips.SetTooltipText(2, 1, GetStringFormat(StringTables.Default.LABEL_RANK_X, { levelString }))
    Tooltips.SetTooltipText(3, 1, GetStringFormatFromTable("HUDStrings", StringTables.HUD.LABEL_HUD_PLAYER_WINDOW_TOOLTIP_CAREER_NAME, { player.careerName }))

    local tooltipLine = 4
    local zoneId = tonumber(player.zoneNum)
    if zoneId ~= nil and zoneId > 0 then
        Tooltips.SetTooltipText(tooltipLine, 1, GetZoneName(zoneId))
        tooltipLine = tooltipLine + 1
    end

    if player.isRVRFlagged then
        Tooltips.SetTooltipText(tooltipLine, 1, GetStringFromTable("HUDStrings", StringTables.HUD.LABEL_PLAYER_IS_RVR_FLAGGED))
    end

    Tooltips.Finalize()
    Tooltips.AnchorTooltip({ Point = "bottomright", RelativeTo = MemberRowName(memberIndex) .. "Portrait", RelativePoint = "topleft", XOffset = -5, YOffset = -5 })
end

function CustomUI.GroupWindow.OnMemberMouseOverEnd()
    local activeName = SystemData.ActiveWindow.name
    local memberIndex = GetMemberIndexFromWindowName(activeName)
    if not memberIndex then
        return
    end

    m_isMouseOverMember[memberIndex] = false
    if IsMemberValid(memberIndex) and ShouldShowContainer() then
        UpdateMemberRow(memberIndex)
    end
end

function CustomUI.GroupWindow.OnMemberRightClick()
    local activeName = SystemData.ActiveWindow.name
    local memberIndex = GetMemberIndexFromWindowName(activeName)
    if not memberIndex or not IsMemberValid(memberIndex) then
        return
    end

    local player = m_groupData[memberIndex]
    if not player then
        return
    end

    GroupWindow.ShowMenu(player.name, player.online ~= true)
end

function CustomUI.GroupWindow.OnMemberLeftClick()
    if GetDesiredInteractAction() == SystemData.InteractActions.TELEPORT then
        UseItemTargeting.SendTeleport()
    end
end

----------------------------------------------------------------
-- Component adapter
----------------------------------------------------------------

local GroupWindowComponent = {
    Name           = "GroupWindow",
    WindowName     = c_WINDOW_NAME,
    DefaultEnabled = false,
}

function GroupWindowComponent:Enable()
    m_enabled = true

    if EnsureStockGroupWindowRegistered() then
        LayoutEditor.UserHide(c_STOCK_WINDOW_NAME)
    end

    LayoutEditor.UserShow(self.WindowName)

    m_statusPollElapsed = 0
    RefreshAllMemberStatuses()
    UpdateContainerVisibility()

    return true
end

function GroupWindowComponent:Disable()
    m_enabled = false
    LayoutEditor.UserHide(self.WindowName)
    HideAllMemberRows()
    ShutdownMemberBuffTrackers()
    ShutdownMemberRvrIndicators()
    m_memberStatusSnapshot = {}
    m_memberStatusSource = {}
    m_memberRvrIndicators = {}
    m_lastRosterNames = {}
    m_lastRosterSignature = nil
    m_statusPollElapsed = 0

    for index = 1, c_MAX_GROUP_MEMBERS do
        m_hitPointAlerts[index] = false
        m_fadeOutAnimationDelay[index] = 0
        m_isFadeIn[index] = false
        m_isMouseOverMember[index] = false
        m_memberHealthTextLayoutApplied[index] = false
    end

    if EnsureStockGroupWindowRegistered() then
        LayoutEditor.UserShow(c_STOCK_WINDOW_NAME)
        LayoutEditor.UnregisterWindow(c_STOCK_WINDOW_NAME)
        m_stockGroupRegistered = false
    end

    return true
end

function GroupWindowComponent:ResetToDefaults()
    if type(CustomUI.ResetWindowToDefault) == "function" then
        CustomUI.ResetWindowToDefault(self.WindowName)
        CustomUI.ResetWindowToDefault(c_STOCK_WINDOW_NAME)
    else
        if DoesWindowExist(self.WindowName) then
            WindowRestoreDefaultSettings(self.WindowName)
        end
        if DoesWindowExist(c_STOCK_WINDOW_NAME) then
            WindowRestoreDefaultSettings(c_STOCK_WINDOW_NAME)
        end
    end

    if m_enabled then
        RefreshAllMemberStatuses()
        UpdateContainerVisibility()
    end

    return true
end

function GroupWindowComponent:Shutdown()
end

----------------------------------------------------------------
----------------------------------------------------------------
-- Buff settings
----------------------------------------------------------------

local BUFF_FILTER_KEYS = {
    "showBuffs", "showDebuffs", "showNeutral",
    "showShort", "showLong", "showPermanent",
    "playerCastOnly",
}

local BUFF_FILTER_DEFAULTS = {
    showBuffs      = true,
    showDebuffs    = true,
    showNeutral    = true,
    showShort      = true,
    showLong       = true,
    showPermanent  = true,
    playerCastOnly = false,
}

function CustomUI.GroupWindow.GetSettings()
    CustomUI.Settings.GroupWindow = CustomUI.Settings.GroupWindow or {}
    local v = CustomUI.Settings.GroupWindow
    v.buffs = v.buffs or {}
    for _, k in ipairs(BUFF_FILTER_KEYS) do
        if v.buffs[k] == nil then
            v.buffs[k] = BUFF_FILTER_DEFAULTS[k]
        end
    end
    return v
end

function CustomUI.GroupWindow.ApplyBuffSettings()
    local cfg = CustomUI.GroupWindow.GetSettings().buffs
    for index = 1, c_MAX_GROUP_MEMBERS do
        local tracker = m_memberBuffTrackers[index]
        if tracker ~= nil then
            tracker:SetFilter(cfg)
        end
    end
end
CustomUI.RegisterComponent("GroupWindow", GroupWindowComponent)
