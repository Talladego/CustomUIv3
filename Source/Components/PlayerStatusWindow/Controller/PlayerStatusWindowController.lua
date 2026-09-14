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
local m_stockPlayerRehookPending = false
local m_stockReplaceTracked   = {} -- PlayerWindow: true if we hid, false if already user-hidden
-- Set-bonus point grants can land a tick after PLAYER_EQUIPMENT_SLOT_UPDATED.
local m_nagRefreshRemaining   = 0
local c_NAG_REFRESH_DELAY     = 0.25

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
    WindowRegisterEventHandler(w, e.PLAYER_RENOWN_RANK_UPDATED,         "CustomUI.PlayerStatusWindow.UpdateRenownRank")
    WindowRegisterEventHandler(w, e.PLAYER_CAREER_CATEGORY_UPDATED,     "CustomUI.PlayerStatusWindow.UpdateAdvancementNag")
    WindowRegisterEventHandler(w, e.PLAYER_ADVANCE_ALERT,               "CustomUI.PlayerStatusWindow.UpdateAdvancementNag")
    WindowRegisterEventHandler(w, e.PLAYER_SINGLE_ABILITY_UPDATED,      "CustomUI.PlayerStatusWindow.UpdateAdvancementNag")
    WindowRegisterEventHandler(w, e.PLAYER_ABILITIES_LIST_UPDATED,      "CustomUI.PlayerStatusWindow.UpdateAdvancementNag")
    WindowRegisterEventHandler(w, e.PLAYER_SKILLS_UPDATED,              "CustomUI.PlayerStatusWindow.UpdateAdvancementNag")
    WindowRegisterEventHandler(w, e.PLAYER_EQUIPMENT_SLOT_UPDATED,      "CustomUI.PlayerStatusWindow.RequestAdvancementNagRefresh")
    WindowRegisterEventHandler(w, e.ITEM_SET_DATA_UPDATED,              "CustomUI.PlayerStatusWindow.RequestAdvancementNagRefresh")
    WindowRegisterEventHandler(w, e.PLAYER_MORALE_UPDATED,              "CustomUI.PlayerStatusWindow.OnMoraleUpdated")
    WindowRegisterEventHandler(w, e.PLAYER_EFFECTS_UPDATED,             "CustomUI.PlayerStatusWindow.OnEffectsUpdated")
    WindowRegisterEventHandler(w, e.PLAYER_AGRO_MODE_UPDATED,           "CustomUI.PlayerStatusWindow.OnAgroModeUpdated")
    WindowRegisterEventHandler(w, e.PLAYER_KILLING_SPREE_UPDATED,       "CustomUI.PlayerStatusWindow.KillingSpreeUpdated")
    WindowRegisterEventHandler(w, e.PLAYER_HEALTH_FADE_UPDATED,         "CustomUI.PlayerStatusWindow.UpdateBasedOnUserSettings")
    WindowRegisterEventHandler(w, e.PLAYER_GROUP_LEADER_STATUS_UPDATED, "CustomUI.PlayerStatusWindow.UpdateCrown")
    WindowRegisterEventHandler(w, e.GROUP_UPDATED,                      "CustomUI.PlayerStatusWindow.UpdateCrown")
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
    WindowUnregisterEventHandler(w, e.PLAYER_RENOWN_RANK_UPDATED)
    WindowUnregisterEventHandler(w, e.PLAYER_CAREER_CATEGORY_UPDATED)
    WindowUnregisterEventHandler(w, e.PLAYER_ADVANCE_ALERT)
    WindowUnregisterEventHandler(w, e.PLAYER_SINGLE_ABILITY_UPDATED)
    WindowUnregisterEventHandler(w, e.PLAYER_ABILITIES_LIST_UPDATED)
    WindowUnregisterEventHandler(w, e.PLAYER_SKILLS_UPDATED)
    WindowUnregisterEventHandler(w, e.PLAYER_EQUIPMENT_SLOT_UPDATED)
    WindowUnregisterEventHandler(w, e.ITEM_SET_DATA_UPDATED)
    WindowUnregisterEventHandler(w, e.PLAYER_MORALE_UPDATED)
    WindowUnregisterEventHandler(w, e.PLAYER_EFFECTS_UPDATED)
    WindowUnregisterEventHandler(w, e.PLAYER_AGRO_MODE_UPDATED)
    WindowUnregisterEventHandler(w, e.PLAYER_KILLING_SPREE_UPDATED)
    WindowUnregisterEventHandler(w, e.PLAYER_HEALTH_FADE_UPDATED)
    WindowUnregisterEventHandler(w, e.PLAYER_GROUP_LEADER_STATUS_UPDATED)
    WindowUnregisterEventHandler(w, e.GROUP_UPDATED)
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
        m_stockPlayerRehookPending = false
        return
    end
    if not DoesWindowExist("PlayerWindow") then
        -- Keep unhooked flag; stock may recreate later. Retry via TryPendingStockRehook.
        m_stockPlayerRehookPending = true
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
    m_stockPlayerRehookPending = false
end

function CustomUI.PlayerStatusWindow.TryPendingStockRehook()
    -- Only when Disable/Shutdown asked to restore and the stock window was missing.
    if m_stockPlayerRehookPending then
        RehookStockPlayerWindowHandlers()
    end
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
local c_CAREER_ICON_BACKGROUND_WINDOW = "CustomUIPlayerStatusWindowCareerIconBackground"
local c_PORTRAIT_FRAME_WINDOW = "CustomUIPlayerStatusWindowPortraitFrame"
local c_RENOWN_RANK_BACKGROUND_WINDOW = "CustomUIPlayerStatusWindowRenownRankBackground"
local c_RENOWN_RANK_TEXT_WINDOW = "CustomUIPlayerStatusWindowRenownRankText"
local c_INFLUENCE_BADGE_BACKGROUND_WINDOW = "CustomUIPlayerStatusWindowInfluenceBadgeBackground"
local c_INFLUENCE_BADGE_TEXT_WINDOW = "CustomUIPlayerStatusWindowInfluenceBadgeText"
local c_RANK_NAG_WINDOW = "CustomUIPlayerStatusWindowAdvancementIndicator"
local c_RENOWN_NAG_WINDOW = "CustomUIPlayerStatusWindowRenownIndicator"
local c_INFLUENCE_NAG_WINDOW = "CustomUIPlayerStatusWindowInfluenceIndicator"
local c_GROUP_LEADER_CROWN_WINDOW = "CustomUIPlayerStatusWindowGroupLeaderCrown"
local c_WARBAND_LEADER_CROWN_WINDOW = "CustomUIPlayerStatusWindowWarbandLeaderCrown"
local c_PS_ROOT = "CustomUIPlayerStatusWindow"

-- GroupMemberUnitFrame / GroupWindow: gold Warband-Leader-Crown slice on party leader too.
local c_LEADER_CROWN_GOLD_SLICE = "Warband-Leader-Crown"

local m_leaderCrownGoldApplied = false

----------------------------------------------------------------
-- Local / Utility Functions
----------------------------------------------------------------

local function EnsurePlayerStatusLeaderCrownsGold()
    if m_leaderCrownGoldApplied == true then
        return
    end
    if type(DynamicImageSetTextureSlice) ~= "function" then
        return
    end
    for _, crownWin in ipairs({ c_GROUP_LEADER_CROWN_WINDOW, c_WARBAND_LEADER_CROWN_WINDOW }) do
        if DoesWindowExist(crownWin) then
            DynamicImageSetTextureSlice(crownWin, c_LEADER_CROWN_GOLD_SLICE)
        end
    end
    m_leaderCrownGoldApplied = true
end

--- Pin leader crowns to portrait top center (PortraitCareerBadge axis).
local function LayoutPlayerStatusLeaderCrowns()
    local portraitWin = c_PORTRAIT_FRAME_WINDOW
    local Badge = CustomUI.PortraitCareerBadge
    if not DoesWindowExist(portraitWin) or Badge == nil then
        return
    end

    EnsurePlayerStatusLeaderCrownsGold()

    local function applyLayout(crownWin)
        if crownWin == nil or not DoesWindowExist(crownWin) then
            return
        end
        Badge.LayoutTopCenter(crownWin, portraitWin, 0, Badge.CROWN_W, Badge.CROWN_H)
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
    WindowSetShowing( c_RANK_NAG_WINDOW, false )
    WindowSetShowing( c_RENOWN_NAG_WINDOW, false )
    WindowSetShowing( c_INFLUENCE_NAG_WINDOW, false )
    WindowSetShowing( "CustomUIPlayerStatusWindowGroupLeaderCrown",      false )
    WindowSetShowing( "CustomUIPlayerStatusWindowWarbandLeaderCrown",    false )
    WindowSetShowing( "CustomUIPlayerStatusWindowDeathPortrait",         false )
    WindowSetShowing( c_CAREER_ICON_WINDOW,                               false )
    WindowSetShowing( c_CAREER_ICON_BACKGROUND_WINDOW,                   false )
    WindowSetShowing( c_RENOWN_RANK_BACKGROUND_WINDOW,                    false )
    WindowSetShowing( c_RENOWN_RANK_TEXT_WINDOW,                          false )
    WindowSetShowing( c_INFLUENCE_BADGE_BACKGROUND_WINDOW,                false )
    WindowSetShowing( c_INFLUENCE_BADGE_TEXT_WINDOW,                      false )
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
    CustomUI.PlayerStatusWindow.UpdateRelicBonuses()
    CustomUI.PlayerStatusWindow.ApplyAppearance()
end

function CustomUI.PlayerStatusWindow.Shutdown()
    UnregisterHandlers()
    if CustomUI.PlayerStatusWindow.playerBuffs ~= nil
        and type(CustomUI.PlayerStatusWindow.playerBuffs.Shutdown) == "function" then
        CustomUI.PlayerStatusWindow.playerBuffs:Shutdown()
    end
    -- XML OnShutdown may skip Disable(); restore stock handlers/windows if we had unhooked them.
    if m_stockPlayerUnhooked then
        RehookStockPlayerWindowHandlers()
        if type(CustomUI.RestoreStockAfterReplace) == "function" then
            CustomUI.RestoreStockAfterReplace("PlayerWindow", m_stockReplaceTracked)
        elseif LayoutEditor.windowsList["PlayerWindow"] then
            LayoutEditor.UserShow("PlayerWindow")
        end
    end
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

    if ( m_nagRefreshRemaining > 0 ) then
        m_nagRefreshRemaining = m_nagRefreshRemaining - timePassed
        if ( m_nagRefreshRemaining <= 0 ) then
            m_nagRefreshRemaining = 0
            CustomUI.PlayerStatusWindow.UpdateAdvancementNag()
        end
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

local function HasUnspentPointsInRange(pointsData, firstCategory, lastCategory)
    if type(pointsData) ~= "table" then
        return false
    end
    for category = firstCategory, lastCategory do
        local pointsLeft = pointsData[category]
        if type(pointsLeft) == "number" and pointsLeft > 0 then
            return true
        end
    end
    return false
end

-- Stock trainer (EA_Window_InteractionRenownTraining.GetPointsAvailable) reads only
-- RENOWN_STATS_A. Categories STATS_B..RENOWN_REALM can keep stale leftovers after a spend.
local function HasUnspentRenownPoints(pointsData)
    if type(pointsData) ~= "table" then
        return false
    end
    local cc = GameData.CareerCategory
    local remaining = tonumber(pointsData[cc.RENOWN_STATS_A]) or 0
    return remaining > 0
end

local function HasUnclaimedInfluenceRewards()
    local Track = CustomUI.PortraitInfluenceTrack
    if type(Track) ~= "table" or type(Track.GetBadgeSnapshot) ~= "function" then
        return false
    end
    local snapshot = Track.GetBadgeSnapshot()
    return type(snapshot) == "table" and snapshot.unclaimed == true
end

function CustomUI.PlayerStatusWindow.UpdateAdvancementNag()
    local pointsData = GameData.Player.GetAdvancePointsAvailable()
    local cc = GameData.CareerCategory
    -- One yellow AdvancementIndicator per badge, anchored left of that badge.
    local showRankNag = CustomUI.PlayerStatusWindow.IsBadgeEnabled("rank")
        and HasUnspentPointsInRange(pointsData, cc.CAREER_ABILITY, cc.SPECIALIZATION)
    local showRenownNag = CustomUI.PlayerStatusWindow.IsBadgeEnabled("renown")
        and HasUnspentRenownPoints(pointsData)
    local showInfluenceNag = CustomUI.PlayerStatusWindow.IsBadgeEnabled("influence")
        and HasUnclaimedInfluenceRewards()

    WindowSetShowing( c_RANK_NAG_WINDOW, showRankNag )
    WindowSetShowing( c_RENOWN_NAG_WINDOW, showRenownNag )
    WindowSetShowing( c_INFLUENCE_NAG_WINDOW, showInfluenceNag )
end

function CustomUI.PlayerStatusWindow.RequestAdvancementNagRefresh()
    CustomUI.PlayerStatusWindow.UpdateAdvancementNag()
    m_nagRefreshRemaining = c_NAG_REFRESH_DELAY
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
    CustomUI.PlayerStatusWindow.UpdateRenownRank()
    CustomUI.PlayerStatusWindow.UpdateInfluenceBadge()
    CustomUI.PlayerStatusWindow.UpdateCareerIcon()
    CustomUI.PlayerStatusWindow.UpdateAdvancementNag()
    CustomUI.PlayerStatusWindow.UpdateCrown()
end

local function SetCareerIconShowing(showing)
    local Badge = CustomUI.PortraitCareerBadge
    if Badge then
        Badge.SetShowing(c_CAREER_ICON_WINDOW, c_CAREER_ICON_BACKGROUND_WINDOW, showing)
    else
        WindowSetShowing(c_CAREER_ICON_WINDOW, showing)
        WindowSetShowing(c_CAREER_ICON_BACKGROUND_WINDOW, showing)
    end
end

function CustomUI.PlayerStatusWindow.UpdateCareerIcon()
    if not CustomUI.PlayerStatusWindow.IsBadgeEnabled("career") then
        SetCareerIconShowing(false)
        return
    end
    if not GameData.Player then return end
    local career = GameData.Player.career or {}
    local careerLine = tonumber(career.line)
    local Badge = CustomUI.PortraitCareerBadge

    if Badge and Badge.LayoutAndApplyTopLeft(
        c_CAREER_ICON_WINDOW,
        c_CAREER_ICON_BACKGROUND_WINDOW,
        c_PS_ROOT,
        c_PORTRAIT_FRAME_WINDOW,
        careerLine
    ) then
        return
    end

    SetCareerIconShowing(false)
end

local function SetRenownRankShowing(showing)
    WindowSetShowing( c_RENOWN_RANK_BACKGROUND_WINDOW, showing )
    WindowSetShowing( c_RENOWN_RANK_TEXT_WINDOW, showing )
end

function CustomUI.PlayerStatusWindow.UpdateRenownRank()
    if not CustomUI.PlayerStatusWindow.IsBadgeEnabled("renown") then
        SetRenownRankShowing(false)
        LayoutPlayerStatusLeaderCrowns()
        CustomUI.PlayerStatusWindow.UpdateAdvancementNag()
        return
    end
    local renown = GameData.Player and GameData.Player.Renown
    local rank = renown and tonumber(renown.curRank)
    if rank == nil then
        SetRenownRankShowing( false )
        LayoutPlayerStatusLeaderCrowns()
        CustomUI.PlayerStatusWindow.UpdateAdvancementNag()
        return
    end

    local color = (DefaultColor and DefaultColor.COLOR_RENOWN_GAIN) or (DefaultColor and DefaultColor.PURPLE) or { r = 194, g = 56, b = 153 }
    LabelSetText( c_RENOWN_RANK_TEXT_WINDOW, L"" .. rank )
    LabelSetTextColor( c_RENOWN_RANK_TEXT_WINDOW, color.r, color.g, color.b )
    LabelSetTextAlign( c_RENOWN_RANK_TEXT_WINDOW, "center" )

    -- Center on the Rank-Circle. Scale 3-digit ranks; keep center anchor (with optical -1 X).
    local rootScale = 1.0
    if DoesWindowExist(c_PS_ROOT) and type(WindowGetScale) == "function" then
        rootScale = WindowGetScale(c_PS_ROOT) or 1.0
    end
    local textScale = (rank >= 100) and 0.68 or 1.0
    if type(WindowSetScale) == "function" and DoesWindowExist(c_RENOWN_RANK_TEXT_WINDOW) then
        WindowSetScale(c_RENOWN_RANK_TEXT_WINDOW, rootScale * textScale)
    end
    if DoesWindowExist(c_RENOWN_RANK_TEXT_WINDOW) and DoesWindowExist(c_RENOWN_RANK_BACKGROUND_WINDOW) then
        WindowClearAnchors(c_RENOWN_RANK_TEXT_WINDOW)
        WindowAddAnchor(
            c_RENOWN_RANK_TEXT_WINDOW,
            "center",
            c_RENOWN_RANK_BACKGROUND_WINDOW,
            "center",
            -1,
            0
        )
    end

    SetRenownRankShowing( true )
    LayoutPlayerStatusLeaderCrowns()
    CustomUI.PlayerStatusWindow.UpdateAdvancementNag()
end

local function SetInfluenceBadgeShowing(showing)
    WindowSetShowing(c_INFLUENCE_BADGE_BACKGROUND_WINDOW, showing)
    WindowSetShowing(c_INFLUENCE_BADGE_TEXT_WINDOW, showing)
end

local function LayoutInfluenceBadge()
    local Badge = CustomUI.PortraitCareerBadge
    if Badge == nil or not DoesWindowExist(c_INFLUENCE_BADGE_BACKGROUND_WINDOW) then
        return
    end
    Badge.LayoutBottomCenter(
        c_INFLUENCE_BADGE_BACKGROUND_WINDOW,
        c_PORTRAIT_FRAME_WINDOW,
        Badge.PORTRAIT_BOTTOM_Y,
        Badge.RING_W,
        Badge.RING_H
    )
    if DoesWindowExist(c_INFLUENCE_BADGE_TEXT_WINDOW) then
        WindowSetDimensions(c_INFLUENCE_BADGE_TEXT_WINDOW, Badge.RING_W, Badge.RING_H)
        WindowClearAnchors(c_INFLUENCE_BADGE_TEXT_WINDOW)
        WindowAddAnchor(
            c_INFLUENCE_BADGE_TEXT_WINDOW,
            "center",
            c_INFLUENCE_BADGE_BACKGROUND_WINDOW,
            "center",
            -1,
            0
        )
    end
end

function CustomUI.PlayerStatusWindow.UpdateInfluenceBadge()
    if not CustomUI.PlayerStatusWindow.IsBadgeEnabled("influence") then
        SetInfluenceBadgeShowing(false)
        CustomUI.PlayerStatusWindow.UpdateAdvancementNag()
        return
    end

    if not DoesWindowExist(c_INFLUENCE_BADGE_BACKGROUND_WINDOW)
        or not DoesWindowExist(c_INFLUENCE_BADGE_TEXT_WINDOW)
    then
        return
    end

    local Track = CustomUI.PortraitInfluenceTrack
    local snapshot = { empty = true, value = 0, unclaimed = false }
    if type(Track) == "table" and type(Track.GetBadgeSnapshot) == "function" then
        local okSnap = Track.GetBadgeSnapshot()
        if type(okSnap) == "table" then
            snapshot = okSnap
        end
    end

    local empty = snapshot.empty == true
    local value = tonumber(snapshot.value) or 0
    local maxTiers = 3
    if type(TomeWindow) == "table" and tonumber(TomeWindow.NUM_REWARD_LEVELS) then
        maxTiers = tonumber(TomeWindow.NUM_REWARD_LEVELS)
    end
    if value < 0 then
        value = 0
    elseif value > maxTiers then
        value = maxTiers
    end

    local color = (DefaultColor and DefaultColor.COLOR_INFLUENCE_GAIN) or { r = 0, g = 170, b = 163 }
    if empty then
        LabelSetText(c_INFLUENCE_BADGE_TEXT_WINDOW, L"-")
    else
        LabelSetText(c_INFLUENCE_BADGE_TEXT_WINDOW, L"" .. value)
    end
    LabelSetTextColor(c_INFLUENCE_BADGE_TEXT_WINDOW, color.r, color.g, color.b)
    LabelSetTextAlign(c_INFLUENCE_BADGE_TEXT_WINDOW, "center")

    LayoutInfluenceBadge()
    SetInfluenceBadgeShowing(true)
    CustomUI.PlayerStatusWindow.UpdateAdvancementNag()
end

function CustomUI.PlayerStatusWindow.OnLButtonUpInfluenceBadge()
    local Track = CustomUI.PortraitInfluenceTrack
    if type(Track) == "table" and type(Track.OpenTrackedSourceTome) == "function" then
        Track.OpenTrackedSourceTome()
    end
end

function CustomUI.PlayerStatusWindow.OnRButtonUpInfluenceBadge()
    local Track = CustomUI.PortraitInfluenceTrack
    if type(Track) == "table" and type(Track.ShowTrackContextMenu) == "function" then
        Track.ShowTrackContextMenu(c_INFLUENCE_BADGE_BACKGROUND_WINDOW)
    end
end

function CustomUI.PlayerStatusWindow.UpdatePlayerLevel()
    if not CustomUI.PlayerStatusWindow.IsBadgeEnabled("rank") then
        WindowSetShowing( "CustomUIPlayerStatusWindowLevelBackground", false )
        WindowSetShowing( "CustomUIPlayerStatusWindowLevelText", false )
        CustomUI.PlayerStatusWindow.UpdateAdvancementNag()
        return
    end
    -- Career rank (GameData.Player.level), not bolstered battle rank (battleLevel).
    local careerRank = GameData.Player.level
    local color = (DefaultColor and DefaultColor.COLOR_EXPERIENCE_GAIN) or { r = 255, g = 170, b = 0 }
    LabelSetText( "CustomUIPlayerStatusWindowLevelText", L"" .. careerRank )
    LabelSetTextColor( "CustomUIPlayerStatusWindowLevelText", color.r, color.g, color.b )
    WindowSetShowing( "CustomUIPlayerStatusWindowLevelBackground", true )
    WindowSetShowing( "CustomUIPlayerStatusWindowLevelText", true )
    CustomUI.PlayerStatusWindow.UpdateAdvancementNag()
end

function CustomUI.PlayerStatusWindow.UpdateCrown()
    LayoutPlayerStatusLeaderCrowns()
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
    local Track = CustomUI.PortraitInfluenceTrack
    if type(Track) == "table" then
        if type(Track.Initialize) == "function" then
            Track.Initialize()
        end
        if type(Track.AddRefreshListener) == "function" then
            Track.AddRefreshListener("CustomUI.PlayerStatusWindow.UpdateInfluenceBadge")
        end
    end
    CustomUI.PlayerStatusWindow.UpdateInfluenceBadge()
    CustomUI.PlayerStatusWindow.ApplyAppearance()
    if type(CustomUI.StockProgressBars) == "table" and type(CustomUI.StockProgressBars.Apply) == "function" then
        CustomUI.StockProgressBars.Apply(true)
    end
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
    local Track = CustomUI.PortraitInfluenceTrack
    if type(Track) == "table" then
        if type(Track.RemoveRefreshListener) == "function" then
            Track.RemoveRefreshListener("CustomUI.PlayerStatusWindow.UpdateInfluenceBadge")
        end
        if type(Track.Shutdown) == "function" then
            Track.Shutdown()
        end
    end
    if type(CustomUI.StockProgressBars) == "table" and type(CustomUI.StockProgressBars.Shutdown) == "function" then
        CustomUI.StockProgressBars.Shutdown()
    end
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
    v.badges = v.badges or {}
    local badgeDefs = {
        career = true,
        rank = true,
        renown = true,
        influence = true,
    }
    for key, defaultValue in pairs(badgeDefs) do
        if v.badges[key] == nil then
            v.badges[key] = defaultValue
        end
    end
    return v
end

function CustomUI.PlayerStatusWindow.IsBadgeEnabled(badgeKey)
    local badges = CustomUI.PlayerStatusWindow.GetSettings().badges
    if type(badges) ~= "table" then
        return true
    end
    return badges[badgeKey] ~= false
end

function CustomUI.PlayerStatusWindow.ApplyBuffSettings()
    local tracker = CustomUI.PlayerStatusWindow.playerBuffs
    if not tracker then return end
    local cfg = CustomUI.PlayerStatusWindow.GetSettings().buffs
    tracker:SetFilter(cfg)
end

function CustomUI.PlayerStatusWindow.ApplyBadgeSettings()
    CustomUI.PlayerStatusWindow.UpdateCareerIcon()
    CustomUI.PlayerStatusWindow.UpdatePlayerLevel()
    CustomUI.PlayerStatusWindow.UpdateRenownRank()
    CustomUI.PlayerStatusWindow.UpdateInfluenceBadge()
    CustomUI.PlayerStatusWindow.UpdateAdvancementNag()
    if type(CustomUI.StockProgressBars) == "table" and type(CustomUI.StockProgressBars.Apply) == "function" then
        local playerStatusOn = type(CustomUI.IsComponentEnabled) == "function"
            and CustomUI.IsComponentEnabled("PlayerStatusWindow") == true
        CustomUI.StockProgressBars.Apply(playerStatusOn)
    end
end

CustomUI.RegisterComponent( "PlayerStatusWindow", PlayerStatusWindowComponent )