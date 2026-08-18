----------------------------------------------------------------
-- CustomUI.PlayerStatusWindow — Controller
-- Responsibilities: RegisterComponent, lifecycle, WindowRegisterEventHandler, all game
--   event and stock-frame updates, and buff/window state. Calls View/PlayerStatusWindow.lua
--   for labels, tooltips, and static XML handlers (same CustomUI.PlayerStatusWindow namespace).
-- This file is listed in CustomUI.mod before View/PlayerStatusWindow.xml; the XML may load
--   only the View .lua, not a second copy of the controller.
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
local m_handlersRegistered    = false
local m_stockPlayerUnhooked   = false
local m_stockReplaceTracked   = {} -- PlayerWindow: true if we hid, false if already user-hidden

local function RegisterHandlers()
    if m_handlersRegistered then return end
    local w = "CustomUIPlayerStatusWindow"
    local e = SystemData.Events
    WindowRegisterEventHandler(w, e.PLAYER_CUR_ACTION_POINTS_UPDATED,   "CustomUI.PlayerStatusWindow.UpdateCurrentActionPoints")
    WindowRegisterEventHandler(w, e.PLAYER_MAX_ACTION_POINTS_UPDATED,   "CustomUI.PlayerStatusWindow.UpdateMaximumActionPoints")
    WindowRegisterEventHandler(w, e.PLAYER_CUR_HIT_POINTS_UPDATED,      "CustomUI.PlayerStatusWindow.UpdateCurrentHitPoints")
    WindowRegisterEventHandler(w, e.PLAYER_MAX_HIT_POINTS_UPDATED,      "CustomUI.PlayerStatusWindow.UpdateMaximumHitPoints")
    WindowRegisterEventHandler(w, e.PLAYER_START_RVR_FLAG_TIMER,        "CustomUI.PlayerStatusWindow.OnStartRvRFlagTimer")
    WindowRegisterEventHandler(w, e.PLAYER_RVR_FLAG_UPDATED,            "CustomUI.PlayerStatusWindow.OnRvRFlagUpdated")
    WindowRegisterEventHandler(w, e.PLAYER_CAREER_RANK_UPDATED,         "CustomUI.PlayerStatusWindow.UpdateCareerRank")
    WindowRegisterEventHandler(w, e.PLAYER_CAREER_CATEGORY_UPDATED,     "CustomUI.PlayerStatusWindow.UpdateAdvancementNag")
    WindowRegisterEventHandler(w, e.PLAYER_MORALE_UPDATED,              "CustomUI.PlayerStatusWindow.OnMoraleUpdated")
    WindowRegisterEventHandler(w, e.PLAYER_EFFECTS_UPDATED,             "CustomUI.PlayerStatusWindow.OnEffectsUpdated")
    WindowRegisterEventHandler(w, e.PLAYER_AGRO_MODE_UPDATED,           "CustomUI.PlayerStatusWindow.OnAgroModeUpdated")
    WindowRegisterEventHandler(w, e.PLAYER_KILLING_SPREE_UPDATED,       "CustomUI.PlayerStatusWindow.KillingSpreeUpdated")
    WindowRegisterEventHandler(w, e.PLAYER_HEALTH_FADE_UPDATED,         "CustomUI.PlayerStatusWindow.UpdateBasedOnUserSettings")
    WindowRegisterEventHandler(w, e.PLAYER_GROUP_LEADER_STATUS_UPDATED, "CustomUI.PlayerStatusWindow.UpdateCrown")
    WindowRegisterEventHandler(w, e.GROUP_UPDATED,                      "CustomUI.PlayerStatusWindow.UpdateCrown")
    WindowRegisterEventHandler(w, e.PLAYER_MAIN_ASSIST_UPDATED,         "CustomUI.PlayerStatusWindow.UpdateMainAssist")
    WindowRegisterEventHandler(w, e.PLAYER_BATTLE_LEVEL_UPDATED,        "CustomUI.PlayerStatusWindow.UpdatePlayerLevel")
    WindowRegisterEventHandler(w, e.ADVANCED_WAR_RELIC_UPDATE,          "CustomUI.PlayerStatusWindow.UpdateRelicBonuses")
    WindowRegisterEventHandler(w, e.LOADING_END,                        "CustomUI.PlayerStatusWindow.UpdatePlayer")
    WindowRegisterEventHandler(w, e.ENTER_WORLD,                        "CustomUI.PlayerStatusWindow.UpdatePlayer")
    WindowRegisterEventHandler(w, e.PLAYER_ZONE_CHANGED,                "CustomUI.PlayerStatusWindow.UpdatePlayer")
    m_handlersRegistered = true
end

local function UnregisterHandlers()
    if not m_handlersRegistered then return end
    local w = "CustomUIPlayerStatusWindow"
    local e = SystemData.Events
    WindowUnregisterEventHandler(w, e.PLAYER_CUR_ACTION_POINTS_UPDATED)
    WindowUnregisterEventHandler(w, e.PLAYER_MAX_ACTION_POINTS_UPDATED)
    WindowUnregisterEventHandler(w, e.PLAYER_CUR_HIT_POINTS_UPDATED)
    WindowUnregisterEventHandler(w, e.PLAYER_MAX_HIT_POINTS_UPDATED)
    WindowUnregisterEventHandler(w, e.PLAYER_START_RVR_FLAG_TIMER)
    WindowUnregisterEventHandler(w, e.PLAYER_RVR_FLAG_UPDATED)
    WindowUnregisterEventHandler(w, e.PLAYER_CAREER_RANK_UPDATED)
    WindowUnregisterEventHandler(w, e.PLAYER_CAREER_CATEGORY_UPDATED)
    WindowUnregisterEventHandler(w, e.PLAYER_MORALE_UPDATED)
    WindowUnregisterEventHandler(w, e.PLAYER_EFFECTS_UPDATED)
    WindowUnregisterEventHandler(w, e.PLAYER_AGRO_MODE_UPDATED)
    WindowUnregisterEventHandler(w, e.PLAYER_KILLING_SPREE_UPDATED)
    WindowUnregisterEventHandler(w, e.PLAYER_HEALTH_FADE_UPDATED)
    WindowUnregisterEventHandler(w, e.PLAYER_GROUP_LEADER_STATUS_UPDATED)
    WindowUnregisterEventHandler(w, e.GROUP_UPDATED)
    WindowUnregisterEventHandler(w, e.PLAYER_MAIN_ASSIST_UPDATED)
    WindowUnregisterEventHandler(w, e.PLAYER_BATTLE_LEVEL_UPDATED)
    WindowUnregisterEventHandler(w, e.ADVANCED_WAR_RELIC_UPDATE)
    WindowUnregisterEventHandler(w, e.LOADING_END)
    WindowUnregisterEventHandler(w, e.ENTER_WORLD)
    WindowUnregisterEventHandler(w, e.PLAYER_ZONE_CHANGED)
    m_handlersRegistered = false
end

local function UnhookStockPlayerWindowHandlers()
    if m_stockPlayerUnhooked then
        return
    end
    if not DoesWindowExist("PlayerWindow") then
        return
    end
    local w = "PlayerWindow"
    local e = SystemData.Events
    -- Stock ea_playerstatuswindow/source/playerwindow.lua registers these on "PlayerWindow".
    WindowUnregisterEventHandler(w, e.PLAYER_CUR_ACTION_POINTS_UPDATED)
    WindowUnregisterEventHandler(w, e.PLAYER_MAX_ACTION_POINTS_UPDATED)
    WindowUnregisterEventHandler(w, e.PLAYER_CUR_HIT_POINTS_UPDATED)
    WindowUnregisterEventHandler(w, e.PLAYER_MAX_HIT_POINTS_UPDATED)
    WindowUnregisterEventHandler(w, e.PLAYER_START_RVR_FLAG_TIMER)
    WindowUnregisterEventHandler(w, e.PLAYER_RVR_FLAG_UPDATED)
    WindowUnregisterEventHandler(w, e.PLAYER_CAREER_RANK_UPDATED)
    WindowUnregisterEventHandler(w, e.PLAYER_CAREER_CATEGORY_UPDATED)
    WindowUnregisterEventHandler(w, e.PLAYER_MORALE_UPDATED)
    WindowUnregisterEventHandler(w, e.PLAYER_EFFECTS_UPDATED)
    WindowUnregisterEventHandler(w, e.PLAYER_AGRO_MODE_UPDATED)
    WindowUnregisterEventHandler(w, e.PLAYER_KILLING_SPREE_UPDATED)
    WindowUnregisterEventHandler(w, e.PLAYER_HEALTH_FADE_UPDATED)
    WindowUnregisterEventHandler(w, e.PLAYER_GROUP_LEADER_STATUS_UPDATED)
    WindowUnregisterEventHandler(w, e.GROUP_UPDATED)
    WindowUnregisterEventHandler(w, e.PLAYER_MAIN_ASSIST_UPDATED)
    WindowUnregisterEventHandler(w, e.PLAYER_BATTLE_LEVEL_UPDATED)
    WindowUnregisterEventHandler(w, e.ADVANCED_WAR_RELIC_UPDATE)
    m_stockPlayerUnhooked = true
end

local function RehookStockPlayerWindowHandlers()
    if not m_stockPlayerUnhooked then
        return
    end
    if not DoesWindowExist("PlayerWindow") then
        m_stockPlayerUnhooked = false
        return
    end
    local w = "PlayerWindow"
    local e = SystemData.Events
    WindowRegisterEventHandler(w, e.PLAYER_CUR_ACTION_POINTS_UPDATED,   "PlayerWindow.UpdateCurrentActionPoints")
    WindowRegisterEventHandler(w, e.PLAYER_MAX_ACTION_POINTS_UPDATED,   "PlayerWindow.UpdateMaximumActionPoints")
    WindowRegisterEventHandler(w, e.PLAYER_CUR_HIT_POINTS_UPDATED,      "PlayerWindow.UpdateCurrentHitPoints")
    WindowRegisterEventHandler(w, e.PLAYER_MAX_HIT_POINTS_UPDATED,      "PlayerWindow.UpdateMaximumHitPoints")
    WindowRegisterEventHandler(w, e.PLAYER_START_RVR_FLAG_TIMER,        "PlayerWindow.OnStartRvRFlagTimer")
    WindowRegisterEventHandler(w, e.PLAYER_RVR_FLAG_UPDATED,            "PlayerWindow.OnRvRFlagUpdated")
    WindowRegisterEventHandler(w, e.PLAYER_CAREER_RANK_UPDATED,         "PlayerWindow.UpdateCareerRank")
    WindowRegisterEventHandler(w, e.PLAYER_CAREER_CATEGORY_UPDATED,     "PlayerWindow.UpdateAdvancementNag")
    WindowRegisterEventHandler(w, e.PLAYER_MORALE_UPDATED,              "PlayerWindow.OnMoraleUpdated")
    WindowRegisterEventHandler(w, e.PLAYER_EFFECTS_UPDATED,             "PlayerWindow.OnEffectsUpdated")
    WindowRegisterEventHandler(w, e.PLAYER_AGRO_MODE_UPDATED,           "PlayerWindow.OnAgroModeUpdated")
    WindowRegisterEventHandler(w, e.PLAYER_KILLING_SPREE_UPDATED,       "PlayerWindow.KillingSpreeUpdated")
    WindowRegisterEventHandler(w, e.PLAYER_HEALTH_FADE_UPDATED,         "PlayerWindow.UpdateBasedOnUserSettings")
    WindowRegisterEventHandler(w, e.PLAYER_GROUP_LEADER_STATUS_UPDATED, "PlayerWindow.UpdateCrown")
    WindowRegisterEventHandler(w, e.GROUP_UPDATED,                      "PlayerWindow.UpdateCrown")
    WindowRegisterEventHandler(w, e.PLAYER_MAIN_ASSIST_UPDATED,         "PlayerWindow.UpdateMainAssist")
    WindowRegisterEventHandler(w, e.PLAYER_BATTLE_LEVEL_UPDATED,        "PlayerWindow.UpdatePlayerLevel")
    WindowRegisterEventHandler(w, e.ADVANCED_WAR_RELIC_UPDATE,          "PlayerWindow.UpdateRelicBonuses")
    m_stockPlayerUnhooked = false
end

local MoraleLevelSliceMap = {
    [1] = { slice = "Morale-Mini-1" },
    [2] = { slice = "Morale-Mini-2" },
    [3] = { slice = "Morale-Mini-3" },
    [4] = { slice = "Morale-Mini-4" },
}

local c_MAX_BUFF_SLOTS = 20
local c_BUFF_STRIDE    = 5
local c_CAREER_ICON_WINDOW = "CustomUIPlayerStatusWindowCareerIcon"
local c_GROUP_LEADER_CROWN_WINDOW = "CustomUIPlayerStatusWindowGroupLeaderCrown"
local c_WARBAND_LEADER_CROWN_WINDOW = "CustomUIPlayerStatusWindowWarbandLeaderCrown"
local c_PS_ROOT = "CustomUIPlayerStatusWindow"

-- Crown atlas/size parity with GroupIconsController WarbandCrown (EA_HUD_01 @ 162,138).
local c_GI_CROWN_TEX_W = 25
local c_GI_CROWN_TEX_H = 16
local c_GI_CROWN_TEXTURE = "EA_HUD_01"
local c_GI_CROWN_TEX_X = 162
local c_GI_CROWN_TEX_Y = 138
-- Keep in sync with GroupIconsController c_CROWN_ANCHOR_OPTICAL_OFFSET_X (atlas vs geometric center).
local c_GI_CROWN_ANCHOR_OPTICAL_OFFSET_X = -2
local c_GI_CROWN_ANCHOR_TOUCH_OFFSET_Y = 5 -- sync GroupIconsController c_CROWN_ANCHOR_TOUCH_OFFSET_Y

----------------------------------------------------------------
-- Local / Utility Functions
----------------------------------------------------------------

--- README §Notes: arg2 Point on target, arg4 RelativePoint on anchored window → crown sits above icon.
local function LayoutPlayerStatusLeaderCrownsLikeGroupIcons()
    local iconWin = c_CAREER_ICON_WINDOW
    if not DoesWindowExist(iconWin) then
        return
    end

    local function applyLayout(crownWin)
        if crownWin == nil or not DoesWindowExist(crownWin) then
            return
        end
        WindowClearAnchors(crownWin)
        WindowSetDimensions(crownWin, c_GI_CROWN_TEX_W, c_GI_CROWN_TEX_H)
        WindowAddAnchor(crownWin, "top", iconWin, "bottom", c_GI_CROWN_ANCHOR_OPTICAL_OFFSET_X, c_GI_CROWN_ANCHOR_TOUCH_OFFSET_Y)
        -- Match GroupIcons crown atlas exactly on warband crown; group crown keeps template UV (different art).
        if crownWin == c_WARBAND_LEADER_CROWN_WINDOW then
            DynamicImageSetTexture(crownWin, c_GI_CROWN_TEXTURE, c_GI_CROWN_TEX_X, c_GI_CROWN_TEX_Y)
            DynamicImageSetTextureDimensions(crownWin, c_GI_CROWN_TEX_W, c_GI_CROWN_TEX_H)
        end
    end

    applyLayout(c_GROUP_LEADER_CROWN_WINDOW)
    applyLayout(c_WARBAND_LEADER_CROWN_WINDOW)
end

--- Show the default player frame (LayoutEditor-aware).
function CustomUI.PlayerStatusWindow.ApplyAppearance()
    if LayoutEditor and LayoutEditor.windowsList and LayoutEditor.windowsList[c_PS_ROOT] then
        LayoutEditor.UserShow(c_PS_ROOT)
    elseif DoesWindowExist(c_PS_ROOT) then
        WindowSetShowing(c_PS_ROOT, true)
    end
    if DoesWindowExist(c_PS_ROOT) then
        WindowSetAlpha(c_PS_ROOT, 1)
    end
    CustomUI.PlayerStatusWindow.UpdateCrown()
end

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

    -- Parent the buff container to the player frame (not Root): same compositing subtree as stock target buffs
    -- (TargetUnitFrame parents BuffTracker to the frame root). Stock PlayerWindow.lua still uses Root; we tie
    -- icons to CustomUIPlayerStatusWindow so they stay on the HUD default tier with the rest of the bar.
    -- Runtime windows can persist across /reloadui; destroy any stale container before recreating.
    if DoesWindowExist( "CustomUIPlayerBuffs" ) then
        DestroyWindow( "CustomUIPlayerBuffs" )
    end
    CustomUI.PlayerStatusWindow.playerBuffs = CustomUI.BuffTracker:Create( "CustomUIPlayerBuffs", "CustomUIPlayerStatusWindow", GameData.BuffTargetType.SELF, c_MAX_BUFF_SLOTS, c_BUFF_STRIDE, SHOW_BUFF_FRAME_TIMER_LABELS )

    WindowClearAnchors( "CustomUIPlayerBuffs" )
    WindowAddAnchor( "CustomUIPlayerBuffs", "bottomleft", "CustomUIPlayerStatusWindow", "topleft", 100, -38 )
    CustomUI.BuffTracker.ApplyPlayerStatusRules( CustomUI.PlayerStatusWindow.playerBuffs )
    CustomUI.PlayerStatusWindow.ApplyBuffSettings()
    CustomUI.PlayerStatusWindow.playerBuffs:Show( false )  -- hidden until component Enable fires OnShown

    CustomUI.PlayerStatusWindow.UpdatePlayer()
    CustomUI.PlayerStatusWindow.OnRvRFlagUpdated()
    -- Max before current: StatusBar fill uses current vs max; also UpdateMaximum* re-applies current.
    CustomUI.PlayerStatusWindow.UpdateMaximumHitPoints()
    CustomUI.PlayerStatusWindow.UpdateMaximumActionPoints()
    CustomUI.PlayerStatusWindow.OnMoraleUpdated( 0, 0 )
    CustomUI.PlayerStatusWindow.UpdateAdvancementNag()
    CustomUI.PlayerStatusWindow.UpdateMainAssist( nil )
    CustomUI.PlayerStatusWindow.UpdateRelicBonuses()
    CustomUI.PlayerStatusWindow.ApplyAppearance()
end

function CustomUI.PlayerStatusWindow.Shutdown()
    UnregisterHandlers()
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
    CustomUI.PlayerStatusWindow.UpdateCurrentActionPoints()
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
    -- Re-apply current so the bar fill matches after max changes or out-of-order events.
    CustomUI.PlayerStatusWindow.UpdateCurrentHitPoints()
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
    if not GameData.Player then return end
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
    LayoutPlayerStatusLeaderCrownsLikeGroupIcons()
end

function CustomUI.PlayerStatusWindow.UpdatePlayerLevel()
    -- Career rank (GameData.Player.level), not bolstered battle rank (battleLevel).
    local careerRank = GameData.Player.level
    local color = PartyUtils.GetLevelTextColor( careerRank, careerRank )
    LabelSetText( "CustomUIPlayerStatusWindowLevelText", L"" .. careerRank )
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
    LayoutPlayerStatusLeaderCrownsLikeGroupIcons()
    WindowSetShowing( c_GROUP_LEADER_CROWN_WINDOW, GameData.Player.isGroupLeader == true )
    local wbLeader = false
    if GameData.Player ~= nil and GameData.Player.isWarbandLeader == true then
        wbLeader = true
    end
    WindowSetShowing( c_WARBAND_LEADER_CROWN_WINDOW, wbLeader )
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
    -- Tooltip content lives in View/PlayerStatusWindow.lua (PaintPortraitTooltip).
    if type(CustomUI.PlayerStatusWindow.PaintPortraitTooltip) == "function" then
        CustomUI.PlayerStatusWindow.PaintPortraitTooltip()
    end

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
    RegisterHandlers()
    CustomUI.PlayerStatusWindow.ApplyAppearance()
    if type(CustomUI.HideStockForReplace) == "function" then
        CustomUI.HideStockForReplace("PlayerWindow", m_stockReplaceTracked)
    elseif LayoutEditor.windowsList["PlayerWindow"] then
        LayoutEditor.UserHide("PlayerWindow")
    end
    UnhookStockPlayerWindowHandlers()
    -- Stock PlayerWindow keeps a live BuffTracker that won't receive updates while unhooked; clear it to avoid stale timers on restore.
    if type(PlayerWindow) == "table" and PlayerWindow.playerBuffs ~= nil then
        if type(PlayerWindow.playerBuffs.ClearAllBuffs) == "function" then
            PlayerWindow.playerBuffs:ClearAllBuffs()
        end
        if type(PlayerWindow.OnHidden) == "function" then
            PlayerWindow.OnHidden()
        else
            if type(PlayerWindow.playerBuffs.Show) == "function" then
                PlayerWindow.playerBuffs:Show(false)
            end
        end
    end
    -- Engine does not replay HP/AP events for the new handler window; pull live values from GameData.
    if GameData and GameData.Player and GameData.Player.hitPoints then
        CustomUI.PlayerStatusWindow.UpdateMaximumHitPoints()
    end
    if GameData and GameData.Player and GameData.Player.actionPoints then
        CustomUI.PlayerStatusWindow.UpdateMaximumActionPoints()
    end
    CustomUI.PlayerPetWindow.Enable()
    CustomUI.PlayerStatusWindow.ApplyBuffSettings()
    -- Resync buffs on enable: during stock ownership we may have missed effects events (especially in combat).
    if CustomUI.PlayerStatusWindow.playerBuffs ~= nil
        and type(CustomUI.PlayerStatusWindow.playerBuffs.Refresh) == "function"
    then
        CustomUI.PlayerStatusWindow.playerBuffs:Refresh()
    end
    return true
end

function PlayerStatusWindowComponent:Disable()
    CustomUI.PlayerPetWindow.Disable()
    UnregisterHandlers()
    -- Clear CUI buff tracker before handing back to stock to avoid stale entries across rapid toggles.
    if CustomUI.PlayerStatusWindow.playerBuffs ~= nil then
        if type(CustomUI.PlayerStatusWindow.playerBuffs.Clear) == "function" then
            CustomUI.PlayerStatusWindow.playerBuffs:Clear()
        end
        if type(CustomUI.PlayerStatusWindow.playerBuffs.Show) == "function" then
            CustomUI.PlayerStatusWindow.playerBuffs:Show(false)
        end
    end
    if LayoutEditor.windowsList["CustomUIPlayerStatusWindow"] then
        LayoutEditor.UserHide("CustomUIPlayerStatusWindow")
    end
    RehookStockPlayerWindowHandlers()
    local stockShown = false
    if type(CustomUI.RestoreStockAfterReplace) == "function" then
        stockShown = CustomUI.RestoreStockAfterReplace("PlayerWindow", m_stockReplaceTracked) == true
    elseif LayoutEditor.windowsList["PlayerWindow"] then
        LayoutEditor.UserShow("PlayerWindow")
        stockShown = true
    end
    -- Engine does not replay HP/AP events when handing back to stock; push a refresh so bars render immediately.
    -- BuffTracker is anchored to Root (not a child of PlayerWindow) — OnShown/OnHidden must match
    -- whether the stock status window is actually shown, or buffs leak while portrait stays hidden.
    if type(PlayerWindow) == "table" then
        if stockShown then
            if type(PlayerWindow.UpdateMaximumHitPoints) == "function" then
                PlayerWindow.UpdateMaximumHitPoints()
            end
            if type(PlayerWindow.UpdateCurrentHitPoints) == "function" then
                PlayerWindow.UpdateCurrentHitPoints()
            end
            if type(PlayerWindow.UpdateMaximumActionPoints) == "function" then
                PlayerWindow.UpdateMaximumActionPoints()
            end
            if type(PlayerWindow.UpdateCurrentActionPoints) == "function" then
                PlayerWindow.UpdateCurrentActionPoints()
            end
            if type(PlayerWindow.UpdateBasedOnUserSettings) == "function" then
                PlayerWindow.UpdateBasedOnUserSettings()
            end
            if type(PlayerWindow.OnShown) == "function" then
                PlayerWindow.OnShown()
            end
            if PlayerWindow.playerBuffs ~= nil and type(PlayerWindow.playerBuffs.Refresh) == "function" then
                PlayerWindow.playerBuffs:Refresh()
            end
        elseif type(PlayerWindow.OnHidden) == "function" then
            PlayerWindow.OnHidden()
        elseif PlayerWindow.playerBuffs ~= nil and type(PlayerWindow.playerBuffs.Show) == "function" then
            PlayerWindow.playerBuffs:Show(false)
        end
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
    CustomUI.PlayerStatusWindow.Shutdown()
end

----------------------------------------------------------------
-- Buff settings helpers
----------------------------------------------------------------

function CustomUI.PlayerStatusWindow.GetSettings()
    CustomUI.Settings.PlayerStatusWindow = CustomUI.Settings.PlayerStatusWindow or {}
    local v = CustomUI.Settings.PlayerStatusWindow
    -- Legacy unused keys: drop from persisted settings if still present.
    v.alwaysShowHitPoints = nil
    v.alwaysShowAPPoints = nil
    v.appearance = nil
    v.minimalShowApBar = nil
    v.minimalHpBarStyle = nil
    v.lowHpScreenFlash = nil
    v.lowHpScreenFlashThresholdPercent = nil
    v.buffs = v.buffs or {}
    local defs = CustomUI.BuffTracker.FilterDefaults
    for _, k in ipairs(CustomUI.BuffTracker.FilterSettingKeys) do
        if v.buffs[k] == nil then
            v.buffs[k] = defs[k]
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

CustomUI.RegisterComponent( "PlayerStatusWindow", PlayerStatusWindowComponent )