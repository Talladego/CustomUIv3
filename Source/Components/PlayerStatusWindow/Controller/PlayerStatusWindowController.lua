----------------------------------------------------------------
-- CustomUI.PlayerStatusWindow - Controller
-- Main entry point for the PlayerStatusWindow component.
-- Handles component lifecycle, game event processing, and state management.
----------------------------------------------------------------

if not CustomUI.PlayerStatusWindow then
    CustomUI.PlayerStatusWindow = {}
end

----------------------------------------------------------------
-- Constants
----------------------------------------------------------------

CustomUI.PlayerStatusWindow.FADE_OUT_ANIM_DELAY = 2
CustomUI.PlayerStatusWindow.TOOLTIP_ANCHOR      = {
    Point         = "bottom",
    RelativeTo    = "CustomUIPlayerStatusWindow",
    RelativePoint = "top",
    XOffset       = 0,
    YOffset       = 0,
}

----------------------------------------------------------------
-- State
----------------------------------------------------------------

CustomUI.PlayerStatusWindow.RelicOwnershipCount      = 0
CustomUI.PlayerStatusWindow.KillingSpreeRemainingTime = 0
CustomUI.PlayerStatusWindow.KillingSpreeIsShowing     = false

CustomUI.PlayerStatusWindow.Settings = {
    alwaysShowHitPoints = false,
    alwaysShowAPPoints  = false,
}

CustomUI.PlayerStatusWindow.RelicBonusText = {}
CustomUI.PlayerStatusWindow.RelicBonusText[GameData.Pairing.GREENSKIN_DWARVES] = { value = L"" }
CustomUI.PlayerStatusWindow.RelicBonusText[GameData.Pairing.EMPIRE_CHAOS]      = { value = L"" }
CustomUI.PlayerStatusWindow.RelicBonusText[GameData.Pairing.ELVES_DARKELVES]   = { value = L"" }

CustomUI.PlayerStatusWindow.RelicBonusDetails = {}
CustomUI.PlayerStatusWindow.RelicBonusDetails[GameData.Factions.DWARF]      = { owned = false }
CustomUI.PlayerStatusWindow.RelicBonusDetails[GameData.Factions.GREENSKIN]  = { owned = false }
CustomUI.PlayerStatusWindow.RelicBonusDetails[GameData.Factions.HIGH_ELF]   = { owned = false }
CustomUI.PlayerStatusWindow.RelicBonusDetails[GameData.Factions.DARK_ELF]   = { owned = false }
CustomUI.PlayerStatusWindow.RelicBonusDetails[GameData.Factions.EMPIRE]     = { owned = false }
CustomUI.PlayerStatusWindow.RelicBonusDetails[GameData.Factions.CHAOS]      = { owned = false }

----------------------------------------------------------------
-- Local State
----------------------------------------------------------------

local bUnflagCountdownStarted = false
local rvrFlagStartTimer       = 0

local isMouseOverPortrait     = false
local isFadeIn                = false
local fadeOutAnimationDelay   = 0

local playerIsMainAssist      = false

local prevMoraleLevel         = 0
local prevHitpointLevel       = 1

local MoraleLevelSliceMap = {
    [1] = { slice = "Morale-Mini-1" },
    [2] = { slice = "Morale-Mini-2" },
    [3] = { slice = "Morale-Mini-3" },
    [4] = { slice = "Morale-Mini-4" },
}

local c_MAX_BUFF_SLOTS = 20
local c_BUFF_STRIDE    = 5
local c_CAREER_ICON_WINDOW = "CustomUIPlayerStatusWindowCareerIcon"

----------------------------------------------------------------
-- Local / Utility Functions
----------------------------------------------------------------

local function UpdateStatusContainerVisibility()
    local show = ( SystemData.Settings.GamePlay.preventHealthBarFade
                or GameData.Player.inAgro
                or isMouseOverPortrait
                or ( GameData.Player.hitPoints.current < GameData.Player.hitPoints.maximum )
                or ( GameData.Player.actionPoints.current < GameData.Player.actionPoints.maximum ) )
    local currentAlpha = WindowGetAlpha( "CustomUIPlayerStatusWindowStatusContainer" )

    if ( show ) then
        fadeOutAnimationDelay = 0
        if ( ( currentAlpha == 0.0 ) or ( ( currentAlpha < 1.0 ) and not isFadeIn ) ) then
            isFadeIn = true
            WindowSetShowing( "CustomUIPlayerStatusWindowStatusContainer", true )
            WindowStartAlphaAnimation( "CustomUIPlayerStatusWindowStatusContainer", Window.AnimationType.SINGLE_NO_RESET, currentAlpha, 1.0, 0.5, false, 0, 0 )
        end
    else
        if ( ( fadeOutAnimationDelay == 0 ) and ( ( currentAlpha == 1 ) or ( ( currentAlpha > 0.0 ) and isFadeIn ) ) ) then
            fadeOutAnimationDelay = CustomUI.PlayerStatusWindow.FADE_OUT_ANIM_DELAY
        end
    end
end

local function PlayerRealmOwnsRelic( relicFaction, status )
    if ( relicFaction == GameData.Factions.DWARF ) or ( relicFaction == GameData.Factions.EMPIRE ) or ( relicFaction == GameData.Factions.HIGH_ELF ) then
        if ( GameData.Player.realm == GameData.Realm.ORDER ) and ( status == GameData.RelicStatuses.SECURE ) then
            return true
        elseif ( GameData.Player.realm == GameData.Realm.DESTRUCTION ) and ( status == GameData.RelicStatuses.CAPTURED ) then
            return true
        end
    elseif ( relicFaction == GameData.Factions.GREENSKIN ) or ( relicFaction == GameData.Factions.CHAOS ) or ( relicFaction == GameData.Factions.DARK_ELF ) then
        if ( GameData.Player.realm == GameData.Realm.DESTRUCTION ) and ( status == GameData.RelicStatuses.SECURE ) then
            return true
        elseif ( GameData.Player.realm == GameData.Realm.ORDER ) and ( status == GameData.RelicStatuses.CAPTURED ) then
            return true
        end
    end
    return false
end

----------------------------------------------------------------
-- Window Event Handlers
----------------------------------------------------------------

function CustomUI.PlayerStatusWindow.Initialize()
    LayoutEditor.RegisterWindow( "CustomUIPlayerStatusWindow",
                                 L"CustomUI: Player Status",
                                 L"CustomUI replacement for the default player status window.",
                                 false, false, true, nil )
    LayoutEditor.UserHide( "CustomUIPlayerStatusWindow" )  -- hidden until component Enable()

    WindowRegisterEventHandler( "CustomUIPlayerStatusWindow", SystemData.Events.PLAYER_CUR_ACTION_POINTS_UPDATED,   "CustomUI.PlayerStatusWindow.UpdateCurrentActionPoints" )
    WindowRegisterEventHandler( "CustomUIPlayerStatusWindow", SystemData.Events.PLAYER_MAX_ACTION_POINTS_UPDATED,   "CustomUI.PlayerStatusWindow.UpdateMaximumActionPoints" )
    WindowRegisterEventHandler( "CustomUIPlayerStatusWindow", SystemData.Events.PLAYER_CUR_HIT_POINTS_UPDATED,      "CustomUI.PlayerStatusWindow.UpdateCurrentHitPoints" )
    WindowRegisterEventHandler( "CustomUIPlayerStatusWindow", SystemData.Events.PLAYER_MAX_HIT_POINTS_UPDATED,      "CustomUI.PlayerStatusWindow.UpdateMaximumHitPoints" )
    WindowRegisterEventHandler( "CustomUIPlayerStatusWindow", SystemData.Events.PLAYER_START_RVR_FLAG_TIMER,         "CustomUI.PlayerStatusWindow.OnStartRvRFlagTimer" )
    WindowRegisterEventHandler( "CustomUIPlayerStatusWindow", SystemData.Events.PLAYER_RVR_FLAG_UPDATED,             "CustomUI.PlayerStatusWindow.OnRvRFlagUpdated" )
    WindowRegisterEventHandler( "CustomUIPlayerStatusWindow", SystemData.Events.PLAYER_CAREER_RANK_UPDATED,          "CustomUI.PlayerStatusWindow.UpdateCareerRank" )
    WindowRegisterEventHandler( "CustomUIPlayerStatusWindow", SystemData.Events.PLAYER_CAREER_CATEGORY_UPDATED,      "CustomUI.PlayerStatusWindow.UpdateAdvancementNag" )
    WindowRegisterEventHandler( "CustomUIPlayerStatusWindow", SystemData.Events.PLAYER_MORALE_UPDATED,               "CustomUI.PlayerStatusWindow.OnMoraleUpdated" )
    WindowRegisterEventHandler( "CustomUIPlayerStatusWindow", SystemData.Events.PLAYER_EFFECTS_UPDATED,              "CustomUI.PlayerStatusWindow.OnEffectsUpdated" )
    WindowRegisterEventHandler( "CustomUIPlayerStatusWindow", SystemData.Events.PLAYER_AGRO_MODE_UPDATED,            "CustomUI.PlayerStatusWindow.OnAgroModeUpdated" )
    WindowRegisterEventHandler( "CustomUIPlayerStatusWindow", SystemData.Events.PLAYER_KILLING_SPREE_UPDATED,        "CustomUI.PlayerStatusWindow.KillingSpreeUpdated" )
    WindowRegisterEventHandler( "CustomUIPlayerStatusWindow", SystemData.Events.PLAYER_HEALTH_FADE_UPDATED,          "CustomUI.PlayerStatusWindow.UpdateBasedOnUserSettings" )
    WindowRegisterEventHandler( "CustomUIPlayerStatusWindow", SystemData.Events.PLAYER_GROUP_LEADER_STATUS_UPDATED,  "CustomUI.PlayerStatusWindow.UpdateCrown" )
    WindowRegisterEventHandler( "CustomUIPlayerStatusWindow", SystemData.Events.GROUP_UPDATED,                       "CustomUI.PlayerStatusWindow.UpdateCrown" )
    WindowRegisterEventHandler( "CustomUIPlayerStatusWindow", SystemData.Events.PLAYER_MAIN_ASSIST_UPDATED,          "CustomUI.PlayerStatusWindow.UpdateMainAssist" )
    WindowRegisterEventHandler( "CustomUIPlayerStatusWindow", SystemData.Events.PLAYER_BATTLE_LEVEL_UPDATED,         "CustomUI.PlayerStatusWindow.UpdatePlayerLevel" )
    WindowRegisterEventHandler( "CustomUIPlayerStatusWindow", SystemData.Events.ADVANCED_WAR_RELIC_UPDATE,           "CustomUI.PlayerStatusWindow.UpdateRelicBonuses" )

    WindowSetShowing( "CustomUIPlayerStatusWindowMoraleMini",            false )
    WindowSetShowing( "CustomUIPlayerStatusWindowAdvancementIndicator",  false )
    WindowSetShowing( "CustomUIPlayerStatusWindowRenownIndicator",       false )
    WindowSetShowing( "CustomUIPlayerStatusWindowGroupLeaderCrown",      false )
    WindowSetShowing( "CustomUIPlayerStatusWindowWarbandLeaderCrown",    false )
    WindowSetShowing( "CustomUIPlayerStatusWindowMainAssistCrown",       false )
    WindowSetShowing( "CustomUIPlayerStatusWindowDeathPortrait",         false )
    WindowSetShowing( c_CAREER_ICON_WINDOW,                               false )
    WindowSetShowing( "CustomUIPlayerStatusWindowKillingSpree",          false )
    WindowSetShowing( "CustomUIPlayerStatusWindowRelicBonus",            false )
    WindowSetShowing( "CustomUIPlayerStatusWindowStatusContainerAPText", false )

    WindowSetTintColor( "CustomUIPlayerStatusWindowKillingSpreeBoxInner", 0, 0, 0 )
    WindowSetAlpha( "CustomUIPlayerStatusWindowKillingSpreeBoxInner", 0.6 )

    CustomUI.PlayerStatusWindow.KillingSpreeIsShowing = false

    CustomUI.PlayerStatusWindow.playerBuffs = CustomUI.BuffTracker:Create( "CustomUIPlayerBuffs", "Root", GameData.BuffTargetType.SELF, c_MAX_BUFF_SLOTS, c_BUFF_STRIDE, SHOW_BUFF_FRAME_TIMER_LABELS )

    WindowClearAnchors( "CustomUIPlayerBuffs" )
    WindowAddAnchor( "CustomUIPlayerBuffs", "bottomleft", "CustomUIPlayerStatusWindow", "topleft", 100, -38 )
    CustomUI.BuffTracker.ApplyPlayerStatusRules( CustomUI.PlayerStatusWindow.playerBuffs )
    CustomUI.PlayerStatusWindow.ApplyBuffSettings()
    CustomUI.PlayerStatusWindow.playerBuffs:Show( false )  -- hidden until component Enable fires OnShown

    CustomUI.PlayerStatusWindow.UpdatePlayer()
    CustomUI.PlayerStatusWindow.OnRvRFlagUpdated()
    CustomUI.PlayerStatusWindow.UpdateCurrentHitPoints()
    CustomUI.PlayerStatusWindow.UpdateMaximumHitPoints()
    CustomUI.PlayerStatusWindow.UpdateCurrentActionPoints()
    CustomUI.PlayerStatusWindow.UpdateMaximumActionPoints()
    CustomUI.PlayerStatusWindow.OnMoraleUpdated( 0, 0 )
    CustomUI.PlayerStatusWindow.UpdateAdvancementNag()
    CustomUI.PlayerStatusWindow.UpdateMainAssist( nil )
    CustomUI.PlayerStatusWindow.UpdateRelicBonuses()
end

function CustomUI.PlayerStatusWindow.Shutdown()
    CustomUI.PlayerStatusWindow.playerBuffs:Shutdown()
end

function CustomUI.PlayerStatusWindow.OnShown()
    CustomUI.PlayerStatusWindow.playerBuffs:Show( true )
end

function CustomUI.PlayerStatusWindow.OnHidden()
    CustomUI.PlayerStatusWindow.playerBuffs:Show( false )
end

function CustomUI.PlayerStatusWindow.Update( timePassed )
    if ( bUnflagCountdownStarted == true and GameData.Player.rvrPermaFlagged == false ) then
        bUnflagCountdownStarted = false
    end

    if ( rvrFlagStartTimer > 0 ) then
        rvrFlagStartTimer = rvrFlagStartTimer - timePassed
        if ( rvrFlagStartTimer < 0 ) then
            rvrFlagStartTimer = 0
        end
        LabelSetText( "CustomUIPlayerStatusWindowRvRFlagCountDown", wstring.format( L"%.0f", rvrFlagStartTimer + 0.5 ) )
    end

    if ( fadeOutAnimationDelay > 0 ) then
        if ( WindowGetAlpha( "CustomUIPlayerStatusWindowStatusContainer" ) == 1.0 ) then
            fadeOutAnimationDelay = fadeOutAnimationDelay - timePassed
            if ( fadeOutAnimationDelay <= 0 ) then
                fadeOutAnimationDelay = 0
                isFadeIn = false
                WindowStartAlphaAnimation( "CustomUIPlayerStatusWindowStatusContainer", Window.AnimationType.SINGLE_NO_RESET_HIDE, 1.0, 0.0, 2.0, false, 0, 0 )
            end
        end
    end

    if ( CustomUI.PlayerStatusWindow.KillingSpreeRemainingTime > 0 ) then
        CustomUI.PlayerStatusWindow.KillingSpreeRemainingTime = CustomUI.PlayerStatusWindow.KillingSpreeRemainingTime - timePassed
        if ( CustomUI.PlayerStatusWindow.KillingSpreeRemainingTime <= 0 ) then
            CustomUI.PlayerStatusWindow.KillingSpreeRemainingTime = 0
        end
        local startFill = 360 * ( 1 - ( CustomUI.PlayerStatusWindow.KillingSpreeRemainingTime / CustomUI.PlayerStatusWindow.KillingSpreeTotalTime ) )
        CircleImageSetFillParams( "CustomUIPlayerStatusWindowKillingSpreeArc", -96 + startFill, 360 - startFill )
    end

    CustomUI.PlayerStatusWindow.playerBuffs:Update( timePassed )
end

function CustomUI.PlayerStatusWindow.OnAgroModeUpdated()
    UpdateStatusContainerVisibility()
end

function CustomUI.PlayerStatusWindow.KillingSpreeUpdated( stage, time, bonus )
    CustomUI.PlayerStatusWindow.KillingSpreeTotalTime     = time
    CustomUI.PlayerStatusWindow.KillingSpreeRemainingTime = time

    if ( time > 0 ) then
        if ( CustomUI.PlayerStatusWindow.KillingSpreeIsShowing == false ) then
            CustomUI.PlayerStatusWindow.KillingSpreeIsShowing = true
            WindowSetShowing( "CustomUIPlayerStatusWindowKillingSpree", true )
            WindowStartAlphaAnimation( "CustomUIPlayerStatusWindowKillingSpree", Window.AnimationType.SINGLE_NO_RESET, 0.0, 1.0, 0.5, false, 0, 0 )
        end
        LabelSetText( "CustomUIPlayerStatusWindowKillingSpreeText", GetStringFormat( StringTables.Default.LABEL_KILLING_SPREE_XP_BONUS, { bonus } ) )
    end

    if ( time <= 0 and CustomUI.PlayerStatusWindow.KillingSpreeIsShowing ) then
        WindowStartAlphaAnimation( "CustomUIPlayerStatusWindowKillingSpree", Window.AnimationType.SINGLE_NO_RESET_HIDE, 1.0, 0.0, 2.0, false, 0, 0 )
        CustomUI.PlayerStatusWindow.KillingSpreeIsShowing = false
    end
end

function CustomUI.PlayerStatusWindow.UpdateAdvancementNag()
    local showNag    = false
    local pointsData = GameData.Player.GetAdvancePointsAvailable()

    for index, pointsLeft in pairs( pointsData ) do
        if pointsLeft > 0 then
            showNag = true
            break
        end
    end

    WindowSetShowing( "CustomUIPlayerStatusWindowAdvancementIndicator", showNag )
end

function CustomUI.PlayerStatusWindow.OnMoraleUpdated( moralePercent, moraleLevel )
    if ( prevMoraleLevel ~= moraleLevel and moraleLevel ~= 0 ) then
        DynamicImageSetTextureSlice( "CustomUIPlayerStatusWindowMoraleMini", MoraleLevelSliceMap[moraleLevel].slice )
        WindowSetShowing( "CustomUIPlayerStatusWindowMoraleMini", true )
    elseif ( moraleLevel == 0 ) then
        if ( WindowGetShowing( "CustomUIPlayerStatusWindowMoraleMini" ) == true ) then
            WindowSetShowing( "CustomUIPlayerStatusWindowMoraleMini", false )
        end
    end
    prevMoraleLevel = moraleLevel
end

function CustomUI.PlayerStatusWindow.OnEffectsUpdated( updatedEffects, isFullList )
    CustomUI.PlayerStatusWindow.playerBuffs:UpdateBuffs( updatedEffects, isFullList )
end

function CustomUI.PlayerStatusWindow.UpdateCurrentActionPoints()
    StatusBarSetCurrentValue( "CustomUIPlayerStatusWindowStatusContainerAPPercentBar", GameData.Player.actionPoints.current )
    CustomUI.PlayerStatusWindow.UpdateAPTextLabel()
    UpdateStatusContainerVisibility()
end

function CustomUI.PlayerStatusWindow.UpdateMaximumActionPoints()
    StatusBarSetMaximumValue( "CustomUIPlayerStatusWindowStatusContainerAPPercentBar", GameData.Player.actionPoints.maximum )
    CustomUI.PlayerStatusWindow.UpdateAPTextLabel()
end

function CustomUI.PlayerStatusWindow.UpdateCurrentHitPoints()
    StatusBarSetCurrentValue( "CustomUIPlayerStatusWindowStatusContainerHealthPercentBar", GameData.Player.hitPoints.current )

    if ( GameData.Player.hitPoints.current == 0 ) then
        WindowSetShowing( "CustomUIPlayerStatusWindowDeathPortrait", true )
    else
        if ( prevHitpointLevel == 0 ) then
            WindowSetShowing( "CustomUIPlayerStatusWindowDeathPortrait", false )
        end
        UpdateStatusContainerVisibility()
    end

    prevHitpointLevel = GameData.Player.hitPoints.current
    CustomUI.PlayerStatusWindow.UpdateHealthTextLabel()
end

function CustomUI.PlayerStatusWindow.UpdateMaximumHitPoints()
    StatusBarSetMaximumValue( "CustomUIPlayerStatusWindowStatusContainerHealthPercentBar", GameData.Player.hitPoints.maximum )
    CustomUI.PlayerStatusWindow.UpdateHealthTextLabel()
end

function CustomUI.PlayerStatusWindow.UpdatePlayer()
    LabelSetText( "CustomUIPlayerStatusWindowPlayerName", GameData.Player.name )
    LabelSetTextColor( "CustomUIPlayerStatusWindowPlayerName", DefaultColor.NAME_COLOR_PLAYER.r, DefaultColor.NAME_COLOR_PLAYER.g, DefaultColor.NAME_COLOR_PLAYER.b )
    CustomUI.PlayerStatusWindow.UpdatePlayerLevel()
    CustomUI.PlayerStatusWindow.UpdateCareerIcon()
    CustomUI.PlayerStatusWindow.UpdateAdvancementNag()
    CustomUI.PlayerStatusWindow.UpdateCrown()
end

function CustomUI.PlayerStatusWindow.UpdateCareerIcon()
    local career = GameData.Player.career or {}
    local careerLine = tonumber( career.line )

    if careerLine == nil then
        WindowSetShowing( c_CAREER_ICON_WINDOW, false )
        return
    end

    local careerIconId = Icons.GetCareerIconIDFromCareerLine( careerLine )
    if careerIconId == nil or careerIconId == 0 then
        WindowSetShowing( c_CAREER_ICON_WINDOW, false )
        return
    end
    local iconTexture, iconX, iconY = GetIconData( careerIconId )
    if iconTexture == nil then
        WindowSetShowing( c_CAREER_ICON_WINDOW, false )
        return
    end

    DynamicImageSetTexture( c_CAREER_ICON_WINDOW, iconTexture, iconX, iconY )
    WindowSetShowing( c_CAREER_ICON_WINDOW, true )
end

function CustomUI.PlayerStatusWindow.UpdatePlayerLevel()
    local color = PartyUtils.GetLevelTextColor( GameData.Player.level, GameData.Player.battleLevel )
    LabelSetText( "CustomUIPlayerStatusWindowLevelText", L"" .. GameData.Player.battleLevel )
    LabelSetTextColor( "CustomUIPlayerStatusWindowLevelText", color.r, color.g, color.b )
    WindowSetShowing( "CustomUIPlayerStatusWindowLevelBackground", true )
    WindowSetShowing( "CustomUIPlayerStatusWindowLevelText", true )
end

function CustomUI.PlayerStatusWindow.UpdateMainAssist( showIcon )
    local isMainAssist = showIcon
    if ( isMainAssist == nil ) then
        isMainAssist = ( IsPlayerMainAssist() == 1 )
    end
    WindowSetShowing( "CustomUIPlayerStatusWindowMainAssistCrown", isMainAssist )
end

function CustomUI.PlayerStatusWindow.UpdateCrown()
    WindowSetShowing( "CustomUIPlayerStatusWindowGroupLeaderCrown", GameData.Player.isGroupLeader == true )
end

function CustomUI.PlayerStatusWindow.ShowMenu()
    local disableUnflag = true
    if ( GameData.Player.rvrZoneFlagged == false and GameData.Player.rvrPermaFlagged == true ) then
        if ( bUnflagCountdownStarted == false ) then
            disableUnflag = false
        end
    end

    EA_Window_ContextMenu.CreateContextMenu( "CustomUIPlayerStatusWindow" )
    EA_Window_ContextMenu.AddMenuItem( GetStringFromTable( "HUDStrings", StringTables.HUD.LABEL_FLAG_PLAYER_RVR ),   CustomUI.PlayerStatusWindow.OnMenuClickFlagRvR,   GameData.Player.rvrZoneFlagged or GameData.Player.rvrPermaFlagged, true )
    EA_Window_ContextMenu.AddMenuItem( GetStringFromTable( "HUDStrings", StringTables.HUD.LABEL_UNFLAG_PLAYER_RVR ), CustomUI.PlayerStatusWindow.OnMenuClickUnFlagRvR, disableUnflag, true )
    local fadeMenuLabel = L"Disable Health Bar Fade"
    if ( SystemData.Settings.GamePlay.preventHealthBarFade == true ) then
        fadeMenuLabel = L"Enable Health Bar Fade"
    end
    EA_Window_ContextMenu.AddMenuItem( fadeMenuLabel, CustomUI.PlayerStatusWindow.OnMenuClickToggleHealthBarFade, false, true )

    if ( ( GroupWindow.inWorldGroup or IsWarBandActive() ) and not GameData.Player.isInScenario and not GameData.Player.isInSiege ) then
        EA_Window_ContextMenu.AddMenuItem( GetString( StringTables.Default.LABEL_GROUP_OPTIONS ),                  EA_Window_OpenParty.OpenToManageTab,                       false, true, EA_Window_ContextMenu.CONTEXT_MENU_1 )
        EA_Window_ContextMenu.AddMenuItem( GetStringFromTable( "HUDStrings", StringTables.HUD.LABEL_LEAVE_GROUP ), CustomUI.PlayerStatusWindow.OnMenuClickLeaveGroup,         false, true )
        if ( GameData.Player.isGroupLeader ) then
            SystemData.UserInput.selectedGroupMember = GameData.Player.name
            EA_Window_ContextMenu.AddMenuItem( GetString( StringTables.Default.LABEL_MAKE_MAIN_ASSIST ), GroupWindow.OnMakeMainAssist, playerIsMainAssist, true, EA_Window_ContextMenu.CONTEXT_MENU_1 )
        end
    end

    if ( GroupWindow.inScenarioGroup ) then
        EA_Window_ContextMenu.AddMenuItem( GetStringFromTable( "HUDStrings", StringTables.HUD.LABEL_LEAVE_SCENARIO_GROUP ), CustomUI.PlayerStatusWindow.OnMenuClickLeaveScenarioGroup, false, true )
    end

    EA_Window_ContextMenu.Finalize()
end

function CustomUI.PlayerStatusWindow.OnMenuClickFlagRvR()         SendChatText( L"/rvr", L"" ) end
function CustomUI.PlayerStatusWindow.OnMenuClickUnFlagRvR()
    bUnflagCountdownStarted = true
    WindowStartAlphaAnimation( "CustomUIPlayerStatusWindowRvRFlagIndicator", Window.AnimationType.LOOP, 0.1, 1.0, 0.8, false, 0, 0 )
    SendChatText( L"/rvr", L"" )
end
function CustomUI.PlayerStatusWindow.OnMenuClickLeaveGroup()         BroadcastEvent( SystemData.Events.GROUP_LEAVE ) end
function CustomUI.PlayerStatusWindow.OnMenuClickLeaveScenarioGroup() ScenarioGroupWindow.LeaveGroup() end
function CustomUI.PlayerStatusWindow.OnMenuClickToggleHealthBarFade()
    SystemData.Settings.GamePlay.preventHealthBarFade = not SystemData.Settings.GamePlay.preventHealthBarFade
    BroadcastEvent( SystemData.Events.PLAYER_HEALTH_FADE_UPDATED )
end

function CustomUI.PlayerStatusWindow.OnStartRvRFlagTimer()
    rvrFlagStartTimer = 10
    WindowSetShowing( "CustomUIPlayerStatusWindowRvRFlagCountDown", true )
    WindowSetShowing( "CustomUIPlayerStatusWindowRvRFlagIndicator", true )
    WindowStartAlphaAnimation( "CustomUIPlayerStatusWindowRvRFlagIndicator", Window.AnimationType.LOOP, 0.1, 1.0, 0.5, false, 0, 0 )
end

function CustomUI.PlayerStatusWindow.OnRvRFlagUpdated()
    WindowSetShowing( "CustomUIPlayerStatusWindowRvRFlagIndicator", GameData.Player.rvrPermaFlagged or GameData.Player.rvrZoneFlagged )

    if ( bUnflagCountdownStarted == true ) then
        if ( GameData.Player.rvrPermaFlagged == false ) then
            WindowStopAlphaAnimation( "CustomUIPlayerStatusWindowRvRFlagIndicator" )
            bUnflagCountdownStarted = false
        end
    else
        WindowStopAlphaAnimation( "CustomUIPlayerStatusWindowRvRFlagIndicator" )
    end

    WindowSetShowing( "CustomUIPlayerStatusWindowRvRFlagCountDown", false )
end

function CustomUI.PlayerStatusWindow.UpdateBasedOnUserSettings()
    UpdateStatusContainerVisibility()
end

function CustomUI.PlayerStatusWindow.MouseOverPortrait()
    Tooltips.CreateTextOnlyTooltip( SystemData.ActiveWindow.name )
    Tooltips.SetTooltipText( 1, 1, GameData.Player.name )
    Tooltips.SetTooltipColorDef( 1, 1, Tooltips.COLOR_HEADING )
    local levelString = PartyUtils.GetLevelText( GameData.Player.level, GameData.Player.battleLevel )
    Tooltips.SetTooltipText( 2, 1, GetStringFormat( StringTables.Default.LABEL_RANK_X, { levelString } ) )
    Tooltips.SetTooltipText( 3, 1, GetStringFormatFromTable( "HUDStrings", StringTables.HUD.LABEL_HUD_PLAYER_WINDOW_TOOLTIP_CAREER_NAME, { GameData.Player.career.name } ) )
    Tooltips.Finalize()
    Tooltips.AnchorTooltip( CustomUI.PlayerStatusWindow.TOOLTIP_ANCHOR )

    isMouseOverPortrait = true
    UpdateStatusContainerVisibility()
end

function CustomUI.PlayerStatusWindow.MouseOverPortraitEnd()
    isMouseOverPortrait = false
    UpdateStatusContainerVisibility()
end

function CustomUI.PlayerStatusWindow.UpdateCareerRank()
    Sound.Play( Sound.ADVANCE_RANK )
    CustomUI.PlayerStatusWindow.UpdatePlayer()
end

function CustomUI.PlayerStatusWindow.UpdateRelicBonuses()
    local relicData = GetRelicStatuses()
    CustomUI.PlayerStatusWindow.RelicOwnershipCount = 0

    if ( relicData ~= nil ) then
        for index, data in ipairs( relicData ) do
            local race   = relicData[index].race
            local status = relicData[index].status
            CustomUI.PlayerStatusWindow.RelicBonusDetails[race].owned = PlayerRealmOwnsRelic( race, status )
        end
    end

    CustomUI.PlayerStatusWindow.RelicBonusText[GameData.Pairing.GREENSKIN_DWARVES].value = L""
    CustomUI.PlayerStatusWindow.RelicBonusText[GameData.Pairing.EMPIRE_CHAOS].value      = L""
    CustomUI.PlayerStatusWindow.RelicBonusText[GameData.Pairing.ELVES_DARKELVES].value   = L""

    if ( CustomUI.PlayerStatusWindow.RelicBonusDetails[GameData.Factions.DWARF].owned == true ) and ( CustomUI.PlayerStatusWindow.RelicBonusDetails[GameData.Factions.GREENSKIN].owned == true ) then
        local relicDesc = GetStringFromTable( "RvRCityStrings", StringTables.RvRCity.TEXT_RELIC_BONUS_GVD )
        CustomUI.PlayerStatusWindow.RelicOwnershipCount = CustomUI.PlayerStatusWindow.RelicOwnershipCount + 1
        CustomUI.PlayerStatusWindow.RelicBonusText[GameData.Pairing.GREENSKIN_DWARVES].value = CustomUI.PlayerStatusWindow.RelicBonusText[GameData.Pairing.GREENSKIN_DWARVES].value .. L"- " .. relicDesc
    end

    if ( CustomUI.PlayerStatusWindow.RelicBonusDetails[GameData.Factions.EMPIRE].owned == true ) and ( CustomUI.PlayerStatusWindow.RelicBonusDetails[GameData.Factions.CHAOS].owned == true ) then
        local relicDesc = GetStringFromTable( "RvRCityStrings", StringTables.RvRCity.TEXT_RELIC_BONUS_EVC )
        CustomUI.PlayerStatusWindow.RelicOwnershipCount = CustomUI.PlayerStatusWindow.RelicOwnershipCount + 1
        CustomUI.PlayerStatusWindow.RelicBonusText[GameData.Pairing.EMPIRE_CHAOS].value = CustomUI.PlayerStatusWindow.RelicBonusText[GameData.Pairing.EMPIRE_CHAOS].value .. L"- " .. relicDesc
    end

    if ( CustomUI.PlayerStatusWindow.RelicBonusDetails[GameData.Factions.HIGH_ELF].owned == true ) and ( CustomUI.PlayerStatusWindow.RelicBonusDetails[GameData.Factions.DARK_ELF].owned == true ) then
        local relicDesc = GetStringFromTable( "RvRCityStrings", StringTables.RvRCity.TEXT_RELIC_BONUS_ELF )
        CustomUI.PlayerStatusWindow.RelicOwnershipCount = CustomUI.PlayerStatusWindow.RelicOwnershipCount + 1
        CustomUI.PlayerStatusWindow.RelicBonusText[GameData.Pairing.ELVES_DARKELVES].value = CustomUI.PlayerStatusWindow.RelicBonusText[GameData.Pairing.ELVES_DARKELVES].value .. L"- " .. relicDesc
    end

    if ( CustomUI.PlayerStatusWindow.RelicOwnershipCount > 0 ) then
        WindowSetShowing( "CustomUIPlayerStatusWindowRelicBonus", true )
    else
        WindowSetShowing( "CustomUIPlayerStatusWindowRelicBonus", false )
    end
end

----------------------------------------------------------------
-- Component Adapter
----------------------------------------------------------------

local PlayerStatusWindowComponent = {
    Name           = "PlayerStatusWindow",
    WindowName     = "CustomUIPlayerStatusWindow",
    DefaultEnabled = false,
}

function PlayerStatusWindowComponent:Enable()
    LayoutEditor.UserShow( self.WindowName )
    if LayoutEditor.windowsList["PlayerWindow"] then
        LayoutEditor.UserHide( "PlayerWindow" )
    end
    CustomUI.PlayerPetWindow.Enable()
    CustomUI.PlayerStatusWindow.ApplyBuffSettings()
    return true
end

function PlayerStatusWindowComponent:Disable()
    CustomUI.PlayerPetWindow.Disable()
    LayoutEditor.UserHide( self.WindowName )
    if LayoutEditor.windowsList["PlayerWindow"] then
        LayoutEditor.UserShow( "PlayerWindow" )
    end
    return true
end

function PlayerStatusWindowComponent:ResetToDefaults()
    if type(CustomUI.ResetWindowToDefault) == "function" then
        CustomUI.ResetWindowToDefault(self.WindowName)
    elseif DoesWindowExist(self.WindowName) then
        WindowRestoreDefaultSettings(self.WindowName)
    end
    return true
end

function PlayerStatusWindowComponent:Shutdown()
end

----------------------------------------------------------------
-- Buff settings helpers
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

function CustomUI.PlayerStatusWindow.GetSettings()
    CustomUI.Settings.PlayerStatusWindow = CustomUI.Settings.PlayerStatusWindow or {}
    local v = CustomUI.Settings.PlayerStatusWindow
    v.buffs = v.buffs or {}
    for _, k in ipairs(BUFF_FILTER_KEYS) do
        if v.buffs[k] == nil then
            v.buffs[k] = BUFF_FILTER_DEFAULTS[k]
        end
    end
    return v
end

function CustomUI.PlayerStatusWindow.ApplyBuffSettings()
    local tracker = CustomUI.PlayerStatusWindow.playerBuffs
    if not tracker then return end
    local cfg = CustomUI.PlayerStatusWindow.GetSettings().buffs
    tracker:SetFilter(cfg)
end

----------------------------------------------------------------
-- LEGACY: in-addon settings tab (View/PlayerStatusWindowTab.xml). Superseded by CustomUISettingsWindow.
----------------------------------------------------------------

CustomUI.PlayerStatusWindow.Tab = {}

function CustomUI.PlayerStatusWindow.Tab.OnShown(contentName)
    ButtonSetPressedFlag(contentName .. "EnableCheckBox", CustomUI.IsComponentEnabled("PlayerStatusWindow"))
    LabelSetText(contentName .. "EnableLabel", L"Enabled")
    CustomUI.BuffFilterSection.SetupLabels(contentName)
    CustomUI.BuffFilterSection.RefreshControls(contentName, CustomUI.PlayerStatusWindow.GetSettings().buffs)
end

function CustomUI.PlayerStatusWindow.Tab.OnToggleEnable()
    local newState = not CustomUI.IsComponentEnabled("PlayerStatusWindow")
    CustomUI.SetComponentEnabled("PlayerStatusWindow", newState)
    ButtonSetPressedFlag(SystemData.ActiveWindow.name, newState)
end

function CustomUI.PlayerStatusWindow.Tab.OnFilterChanged()
    CustomUI.BuffFilterSection.OnFilterChanged(
        function() return CustomUI.PlayerStatusWindow.GetSettings().buffs end,
        function() CustomUI.PlayerStatusWindow.ApplyBuffSettings() end
    )
end

--CustomUI.SettingsWindow.RegisterTab("Player", "CustomUIPlayerStatusWindowTab", PlayerStatusWindowComponent, CustomUI.PlayerStatusWindow.Tab.OnShown)  -- LEGACY (in-addon tab)
CustomUI.RegisterComponent( "PlayerStatusWindow", PlayerStatusWindowComponent )