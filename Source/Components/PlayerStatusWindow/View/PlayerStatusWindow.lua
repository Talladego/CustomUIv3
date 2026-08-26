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
    local hp = GameData.Player and GameData.Player.hitPoints
    if not hp then return end
    local healthText = hp.current .. L"/" .. hp.maximum
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
    local p = GameData and GameData.Player
    if not p then return end

    local rankHeading = GetString( StringTables.Default.LABEL_RANK )
    if rankHeading == nil or rankHeading == L"" then
        rankHeading = L"Career Rank"
    end

    local line = 1
    Tooltips.CreateTextOnlyTooltip( SystemData.ActiveWindow.name )
    Tooltips.SetTooltipText( line, 1, rankHeading .. L": " .. (L"" .. (p.level or 0)) )
    Tooltips.SetTooltipColorDef( line, 1, Tooltips.COLOR_HEADING )
    line = line + 1

    local exp = p.Experience
    local curPoints = exp and exp.curXpEarned or 0
    local maxPoints = exp and exp.curXpNeeded or 0
    local expLine
    if maxPoints == 0 then
        expLine = GetString( StringTables.Default.TEXT_CUR_EXP_MAXIMUM )
    else
        local percent = wstring.format( L"%d", curPoints / maxPoints * 100 )
        expLine = GetStringFormat( StringTables.Default.TEXT_CUR_EXP, { curPoints, maxPoints, percent } )
    end
    if expLine == nil or expLine == L"" then
        if maxPoints == 0 then
            expLine = L"Current Exp: Maximum"
        else
            expLine = L"Current Exp: " .. curPoints .. L"/" .. maxPoints
        end
    end
    Tooltips.SetTooltipText( line, 1, expLine )
    Tooltips.SetTooltipColorDef( line, 1, Tooltips.COLOR_HEADING )
    line = line + 1

    local careerLevel = tonumber(p.level) or 0
    local battleLevel = tonumber(p.battleLevel) or careerLevel
    if careerLevel ~= battleLevel then
        local bolsterText = PartyUtils.GetLevelText( careerLevel, battleLevel )
        Tooltips.SetTooltipText( line, 1, bolsterText )
        line = line + 1
        if type(GetBolsterBuddy) == "function" and GetBolsterBuddy() then
            local statusString = GetStringFromTable( "HUDStrings", StringTables.HUD.LABEL_APPRENTICE )
            if statusString ~= nil and statusString ~= L"" then
                Tooltips.SetTooltipText( line, 1, statusString )
            end
        end
    end

    Tooltips.Finalize()
    Tooltips.AnchorTooltip( CustomUI.PlayerStatusWindow.TOOLTIP_ANCHOR )
end

function CustomUI.PlayerStatusWindow.MouseOverCareerIcon()
    local p = GameData and GameData.Player
    if not p then return end
    local careerName = L""
    if p.career and p.career.name then
        careerName = p.career.name
    end

    Tooltips.CreateTextOnlyTooltip( SystemData.ActiveWindow.name )
    Tooltips.SetTooltipText( 1, 1, careerName )
    Tooltips.SetTooltipColorDef( 1, 1, Tooltips.COLOR_HEADING )
    Tooltips.Finalize()
    Tooltips.AnchorTooltip( CustomUI.PlayerStatusWindow.TOOLTIP_ANCHOR )
end

function CustomUI.PlayerStatusWindow.MouseOverRenownRank()
    local p = GameData and GameData.Player
    if not p or not p.Renown then return end
    local rank = p.Renown.curRank
    local title = p.Renown.curTitle
    local heading = GetString( StringTables.Default.LABEL_RENOWN_RANK )
    if heading == nil or heading == L"" then
        heading = L"Renown Rank"
    end

    Tooltips.CreateTextOnlyTooltip( SystemData.ActiveWindow.name )
    Tooltips.SetTooltipText( 1, 1, heading .. L": " .. (L"" .. rank) )
    Tooltips.SetTooltipColorDef( 1, 1, Tooltips.COLOR_HEADING )

    local line = 2
    if title ~= nil and title ~= L"" then
        Tooltips.SetTooltipText( line, 1, title )
        line = line + 1
    end

    local curPoints = tonumber(p.Renown.curRenownEarned) or 0
    local maxPoints = tonumber(p.Renown.curRenownNeeded) or 0
    local percent = L"0"
    if maxPoints > 0 then
        percent = wstring.format( L"%d", curPoints / maxPoints * 100 )
    end
    local renownLine = GetStringFormat( StringTables.Default.TEXT_CUR_RENOWN, { curPoints, maxPoints, percent } )
    if renownLine == nil or renownLine == L"" then
        renownLine = L"Current Renown: " .. curPoints .. L"/" .. maxPoints .. L" (" .. percent .. L"%)"
    end
    Tooltips.SetTooltipText( line, 1, renownLine )
    Tooltips.SetTooltipColorDef( line, 1, Tooltips.COLOR_HEADING )

    Tooltips.Finalize()
    Tooltips.AnchorTooltip( CustomUI.PlayerStatusWindow.TOOLTIP_ANCHOR )
end

function CustomUI.PlayerStatusWindow.MouseOverInfluenceBadge()
    -- Refresh before tip so badge matches current area (area changes may race).
    if type(CustomUI.PlayerStatusWindow.UpdateInfluenceBadge) == "function" then
        CustomUI.PlayerStatusWindow.UpdateInfluenceBadge()
    end
    local Track = CustomUI.PortraitInfluenceTrack
    if type(Track) == "table" and type(Track.ShowBadgeTooltip) == "function" then
        Track.ShowBadgeTooltip(
            SystemData.ActiveWindow.name,
            CustomUI.PlayerStatusWindow.TOOLTIP_ANCHOR
        )
    end
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
    if not GameData.Player then return end
    Tooltips.CreateTextOnlyTooltip( SystemData.ActiveWindow.name )
    Tooltips.SetTooltipText( 1, 1, GameData.Player.name )
    Tooltips.SetTooltipColorDef( 1, 1, Tooltips.COLOR_HEADING )
    local levelString = PartyUtils.GetLevelText( GameData.Player.level, GameData.Player.battleLevel )
    Tooltips.SetTooltipText( 2, 1, GetStringFormat( StringTables.Default.LABEL_RANK_X, { levelString } ) )
    local careerName = GameData.Player.career and GameData.Player.career.name or L""
    Tooltips.SetTooltipText( 3, 1, GetStringFormatFromTable( "HUDStrings", StringTables.HUD.LABEL_HUD_PLAYER_WINDOW_TOOLTIP_CAREER_NAME, { careerName } ) )
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
