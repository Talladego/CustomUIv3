CustomUISettingsWindowTabGroup = {}

CustomUISettingsWindowTabGroup.contentsName = "SWTabGroupContentsScrollChild"

local BUFF_CHECKBOX_KEYS = {
    BuffTrackerBuffs          = "showBuffs",
    BuffTrackerDebuffs        = "showDebuffs",
    BuffTrackerNeutral        = "showNeutral",
    BuffTrackerShort          = "showShort",
    BuffTrackerLong           = "showLong",
    BuffTrackerPermanent      = "showPermanent",
    BuffTrackerPlayerCastOnly = "playerCastOnly",
}

local BADGE_CHECKBOX_KEYS = {
    BadgesCareer = "career",
    BadgesRank   = "rank",
}

function CustomUISettingsWindowTabGroup.Initialize()
    LabelSetText( CustomUISettingsWindowTabGroup.contentsName.."GeneralTitle", L"General" )
    LabelSetText( CustomUISettingsWindowTabGroup.contentsName.."GeneralGroupWindowEnabledLabel", L"Enabled" )
    ButtonSetCheckButtonFlag( CustomUISettingsWindowTabGroup.contentsName.."GeneralGroupWindowEnabledButton", true )

    local badges = CustomUISettingsWindowTabGroup.contentsName.."Badges"
    LabelSetText( badges.."Title", L"Badges" )
    LabelSetText( badges.."CareerLabel", L"Career Badge" )
    ButtonSetCheckButtonFlag( badges.."CareerButton", true )
    LabelSetText( badges.."RankLabel", L"Rank Badge" )
    ButtonSetCheckButtonFlag( badges.."RankButton", true )

    local bt = CustomUISettingsWindowTabGroup.contentsName.."BuffTracker"
    LabelSetText( bt.."Title", L"Buff Tracker" )
    LabelSetText( bt.."CategoryLabel",       L"Category" )
    LabelSetText( bt.."BuffsLabel",          L"Buffs" )
    ButtonSetCheckButtonFlag( bt.."BuffsButton",    true )
    LabelSetText( bt.."DebuffsLabel",        L"Debuffs" )
    ButtonSetCheckButtonFlag( bt.."DebuffsButton",  true )
    LabelSetText( bt.."NeutralLabel",        L"Neutral" )
    ButtonSetCheckButtonFlag( bt.."NeutralButton",  true )
    LabelSetText( bt.."DurationLabel",       L"Duration" )
    LabelSetText( bt.."ShortLabel",          L"Short (<60s)" )
    ButtonSetCheckButtonFlag( bt.."ShortButton",    true )
    LabelSetText( bt.."LongLabel",           L"Long (60s+)" )
    ButtonSetCheckButtonFlag( bt.."LongButton",     true )
    LabelSetText( bt.."PermanentLabel",      L"Permanent" )
    ButtonSetCheckButtonFlag( bt.."PermanentButton", true )
    LabelSetText( bt.."SourceLabel",         L"Source" )
    LabelSetText( bt.."PlayerCastOnlyLabel", L"My casts only" )
    ButtonSetCheckButtonFlag( bt.."PlayerCastOnlyButton", true )
end

function CustomUISettingsWindowTabGroup.UpdateSettings()
    ButtonSetPressedFlag( CustomUISettingsWindowTabGroup.contentsName.."GeneralGroupWindowEnabledButton", CustomUI.IsComponentEnabled("GroupWindow") )

    local badgeCfg = CustomUI.GroupWindow.GetSettings().badges
    local badges = CustomUISettingsWindowTabGroup.contentsName.."Badges"
    ButtonSetPressedFlag( badges.."CareerButton", badgeCfg.career ~= false )
    ButtonSetPressedFlag( badges.."RankButton",   badgeCfg.rank ~= false )

    local bt  = CustomUISettingsWindowTabGroup.contentsName.."BuffTracker"
    local cfg = CustomUI.GroupWindow.GetSettings().buffs
    ButtonSetPressedFlag( bt.."BuffsButton",          cfg.showBuffs )
    ButtonSetPressedFlag( bt.."DebuffsButton",        cfg.showDebuffs )
    ButtonSetPressedFlag( bt.."NeutralButton",        cfg.showNeutral )
    ButtonSetPressedFlag( bt.."ShortButton",          cfg.showShort )
    ButtonSetPressedFlag( bt.."LongButton",           cfg.showLong )
    ButtonSetPressedFlag( bt.."PermanentButton",      cfg.showPermanent )
    ButtonSetPressedFlag( bt.."PlayerCastOnlyButton", cfg.playerCastOnly )
end

function CustomUISettingsWindowTabGroup.ApplyCurrent()
    local enabled = ButtonGetPressedFlag( CustomUISettingsWindowTabGroup.contentsName.."GeneralGroupWindowEnabledButton" )
    CustomUI.SetComponentEnabled( "GroupWindow", enabled )

    local prefix = CustomUISettingsWindowTabGroup.contentsName
    local badgeCfg = CustomUI.GroupWindow.GetSettings().badges
    for suffix, key in pairs(BADGE_CHECKBOX_KEYS) do
        badgeCfg[key] = ButtonGetPressedFlag(prefix .. suffix .. "Button") == true
    end
    if type(CustomUI.GroupWindow.ApplyBadgeSettings) == "function" then
        CustomUI.GroupWindow.ApplyBadgeSettings()
    end

    local cfg = CustomUI.GroupWindow.GetSettings().buffs
    for suffix, key in pairs(BUFF_CHECKBOX_KEYS) do
        cfg[key] = ButtonGetPressedFlag(prefix .. suffix .. "Button") == true
    end
    CustomUI.GroupWindow.ApplyBuffSettings()
end

function CustomUISettingsWindowTabGroup.ResetSettings()
end

function CustomUISettingsWindowTabGroup.OnBuffFilterChanged()
    EA_LabelCheckButton.Toggle()
end

function CustomUISettingsWindowTabGroup.OnToggleBadge()
    EA_LabelCheckButton.Toggle()
end

function CustomUISettingsWindowTabGroup.OnToggleGroupWindow()
    EA_LabelCheckButton.Toggle()
end
