----------------------------------------------------------------
-- CustomUI.PlayerStatusWindow — View
-- Responsibilities: presentation only — label text, tooltips, and thin input handlers
--   that forward to game actions. No RegisterComponent, no long-lived state machine,
--   no WindowRegisterEventHandler (those are in the controller). The mod loads
--   PlayerStatusWindowController.lua before this file (via the window XML <Script>).
-- Controllers that own lifecycle + events: ..Controller/PlayerStatusWindowController.lua
----------------------------------------------------------------

-- Health text label
function CustomUI.PlayerStatusWindow.UpdateHealthTextLabel()
    local healthText = GameData.Player.hitPoints.current .. L"/" .. GameData.Player.hitPoints.maximum
    LabelSetText( "CustomUIPlayerStatusWindowStatusContainerHealthText", healthText )
end

-- Action-points text label (disabled until a small-enough font is available)
function CustomUI.PlayerStatusWindow.UpdateAPTextLabel()
    -- local apText = GameData.Player.actionPoints.current .. L"/" .. GameData.Player.actionPoints.maximum
    -- LabelSetText( "CustomUIPlayerStatusWindowStatusContainerAPText", apText )
end

----------------------------------------------------------------
-- Tooltips
----------------------------------------------------------------

function CustomUI.PlayerStatusWindow.MouseoverHitPoints()
    Tooltips.CreateTextOnlyTooltip( SystemData.ActiveWindow.name )
    Tooltips.SetTooltipText( 1, 1, GetString( StringTables.Default.LABEL_HIT_POINTS ) )
    Tooltips.SetTooltipColorDef( 1, 1, Tooltips.COLOR_HEADING )
    Tooltips.SetTooltipText( 2, 1, GetString( StringTables.Default.TEXT_HP_BAR_DESC ) )
    Tooltips.SetTooltipText( 3, 1, GetString( StringTables.Default.TEXT_STATUS_BAR_RIGHT_CLICK ) )
    Tooltips.SetTooltipColorDef( 3, 1, Tooltips.COLOR_EXTRA_TEXT_DEFAULT )
    Tooltips.Finalize()
    Tooltips.AnchorTooltip( CustomUI.PlayerStatusWindow.TOOLTIP_ANCHOR )
end

function CustomUI.PlayerStatusWindow.MouseoverEndHitPoints() end

function CustomUI.PlayerStatusWindow.MouseoverActionPoints()
    Tooltips.CreateTextOnlyTooltip( SystemData.ActiveWindow.name )
    Tooltips.SetTooltipText( 1, 1, GetString( StringTables.Default.LABEL_ACTION_POINTS ) )
    Tooltips.SetTooltipColorDef( 1, 1, Tooltips.COLOR_HEADING )
    Tooltips.SetTooltipText( 2, 1, GetString( StringTables.Default.TEXT_AP_BAR_DESC ) )
    Tooltips.SetTooltipText( 3, 1, GetString( StringTables.Default.TEXT_STATUS_BAR_RIGHT_CLICK ) )
    Tooltips.SetTooltipColorDef( 3, 1, Tooltips.COLOR_EXTRA_TEXT_DEFAULT )
    Tooltips.Finalize()
    Tooltips.AnchorTooltip( CustomUI.PlayerStatusWindow.TOOLTIP_ANCHOR )
end

function CustomUI.PlayerStatusWindow.MouseoverEndActionPoints() end

function CustomUI.PlayerStatusWindow.OnMouseoverRvRIndicator()
    Tooltips.CreateTextOnlyTooltip( SystemData.ActiveWindow.name, GetString( StringTables.Default.TOOLTIP_RVR_INDICATOR ) )
    Tooltips.AnchorTooltip( CustomUI.PlayerStatusWindow.TOOLTIP_ANCHOR )
end

function CustomUI.PlayerStatusWindow.MouseOverLevel()
    local levelString = PartyUtils.GetLevelText( GameData.Player.level, GameData.Player.battleLevel )
    if ( GameData.Player.level ~= GameData.Player.battleLevel ) then
        Tooltips.CreateTextOnlyTooltip( SystemData.ActiveWindow.name )
        local statusString = nil
        if ( GetBolsterBuddy() ) then
            statusString = GetStringFromTable( "HUDStrings", StringTables.HUD.LABEL_APPRENTICE )
        end
        Tooltips.SetTooltipText( 1, 1, levelString )
        if ( statusString ) then
            Tooltips.SetTooltipText( 2, 1, statusString )
        end
        Tooltips.Finalize()
        Tooltips.AnchorTooltip( CustomUI.PlayerStatusWindow.TOOLTIP_ANCHOR )
    end
end

function CustomUI.PlayerStatusWindow.MouseOverCareerIcon()
    local careerName = L""
    if GameData.Player.career and GameData.Player.career.name then
        careerName = GameData.Player.career.name
    end

    Tooltips.CreateTextOnlyTooltip( SystemData.ActiveWindow.name )
    Tooltips.SetTooltipText( 1, 1, careerName )
    Tooltips.SetTooltipColorDef( 1, 1, Tooltips.COLOR_HEADING )
    Tooltips.Finalize()
    Tooltips.AnchorTooltip( CustomUI.PlayerStatusWindow.TOOLTIP_ANCHOR )
end

function CustomUI.PlayerStatusWindow.MouseOverRelicBonus()
    if ( CustomUI.PlayerStatusWindow.RelicOwnershipCount < 1 ) then return end

    Tooltips.CreateTextOnlyTooltip( SystemData.ActiveWindow.name )
    Tooltips.SetTooltipText( 1, 1, GetStringFromTable( "RvRCityStrings", StringTables.RvRCity.TEXT_RELIC_BONUS ) )
    local currentLine = 2

    if ( wstring.len( CustomUI.PlayerStatusWindow.RelicBonusText[GameData.Pairing.GREENSKIN_DWARVES].value ) > 1 ) then
        Tooltips.SetTooltipText( currentLine, 1, CustomUI.PlayerStatusWindow.RelicBonusText[GameData.Pairing.GREENSKIN_DWARVES].value )
        currentLine = currentLine + 1
    end

    if ( wstring.len( CustomUI.PlayerStatusWindow.RelicBonusText[GameData.Pairing.EMPIRE_CHAOS].value ) > 1 ) then
        Tooltips.SetTooltipText( currentLine, 1, CustomUI.PlayerStatusWindow.RelicBonusText[GameData.Pairing.EMPIRE_CHAOS].value )
        currentLine = currentLine + 1
    end

    if ( wstring.len( CustomUI.PlayerStatusWindow.RelicBonusText[GameData.Pairing.ELVES_DARKELVES].value ) > 1 ) then
        Tooltips.SetTooltipText( currentLine, 1, CustomUI.PlayerStatusWindow.RelicBonusText[GameData.Pairing.ELVES_DARKELVES].value )
        currentLine = currentLine + 1
    end

    Tooltips.Finalize()
    Tooltips.AnchorTooltip( CustomUI.PlayerStatusWindow.TOOLTIP_ANCHOR )
end

----------------------------------------------------------------
-- Portrait (controller routes hover here; see MouseOverPortrait in controller)
----------------------------------------------------------------

function CustomUI.PlayerStatusWindow.PaintPortraitTooltip()
    Tooltips.CreateTextOnlyTooltip( SystemData.ActiveWindow.name )
    Tooltips.SetTooltipText( 1, 1, GameData.Player.name )
    Tooltips.SetTooltipColorDef( 1, 1, Tooltips.COLOR_HEADING )
    local levelString = PartyUtils.GetLevelText( GameData.Player.level, GameData.Player.battleLevel )
    Tooltips.SetTooltipText( 2, 1, GetStringFormat( StringTables.Default.LABEL_RANK_X, { levelString } ) )
    Tooltips.SetTooltipText( 3, 1, GetStringFormatFromTable( "HUDStrings", StringTables.HUD.LABEL_HUD_PLAYER_WINDOW_TOOLTIP_CAREER_NAME, { GameData.Player.career.name } ) )
    Tooltips.Finalize()
    Tooltips.AnchorTooltip( CustomUI.PlayerStatusWindow.TOOLTIP_ANCHOR )
end

----------------------------------------------------------------
-- Input Forwarding
----------------------------------------------------------------

function CustomUI.PlayerStatusWindow.OnLButtonDown()
    BroadcastEvent( SystemData.Events.TARGET_SELF )
end

function CustomUI.PlayerStatusWindow.OnRButtonUp()
    CustomUI.PlayerStatusWindow.ShowMenu()
end
