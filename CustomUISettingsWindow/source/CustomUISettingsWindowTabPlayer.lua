CustomUISettingsWindowTabPlayer = {}

CustomUISettingsWindowTabPlayer.contentsName = "SWTabPlayerContentsScrollChild"

-- Stock-style: toggles only flip widgets; ApplyCurrent commits to CustomUI.

local BUFF_CHECKBOX_KEYS = {
    BuffTrackerBuffs         = "showBuffs",
    BuffTrackerDebuffs       = "showDebuffs",
    BuffTrackerNeutral       = "showNeutral",
    BuffTrackerShort         = "showShort",
    BuffTrackerLong          = "showLong",
    BuffTrackerPermanent     = "showPermanent",
    BuffTrackerPlayerCastOnly = "playerCastOnly",
}

function CustomUISettingsWindowTabPlayer.Initialize()
    LabelSetText( CustomUISettingsWindowTabPlayer.contentsName.."GeneralTitle", L"General" )
    LabelSetText( CustomUISettingsWindowTabPlayer.contentsName.."GeneralPlayerStatusWindowEnabledLabel", L"Enabled" )
    ButtonSetCheckButtonFlag( CustomUISettingsWindowTabPlayer.contentsName.."GeneralPlayerStatusWindowEnabledButton", true )

    local bt = CustomUISettingsWindowTabPlayer.contentsName.."BuffTracker"
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

function CustomUISettingsWindowTabPlayer.UpdateSettings()
    ButtonSetPressedFlag( CustomUISettingsWindowTabPlayer.contentsName.."GeneralPlayerStatusWindowEnabledButton", CustomUI.IsComponentEnabled("PlayerStatusWindow") )

    local bt  = CustomUISettingsWindowTabPlayer.contentsName.."BuffTracker"
    local cfg = CustomUI.PlayerStatusWindow.GetSettings().buffs
    ButtonSetPressedFlag( bt.."BuffsButton",         cfg.showBuffs )
    ButtonSetPressedFlag( bt.."DebuffsButton",       cfg.showDebuffs )
    ButtonSetPressedFlag( bt.."NeutralButton",       cfg.showNeutral )
    ButtonSetPressedFlag( bt.."ShortButton",         cfg.showShort )
    ButtonSetPressedFlag( bt.."LongButton",          cfg.showLong )
    ButtonSetPressedFlag( bt.."PermanentButton",     cfg.showPermanent )
    ButtonSetPressedFlag( bt.."PlayerCastOnlyButton", cfg.playerCastOnly )
end

function CustomUISettingsWindowTabPlayer.ApplyCurrent()
    local enabled = ButtonGetPressedFlag( CustomUISettingsWindowTabPlayer.contentsName.."GeneralPlayerStatusWindowEnabledButton" )
    CustomUI.SetComponentEnabled( "PlayerStatusWindow", enabled )

    local cfg = CustomUI.PlayerStatusWindow.GetSettings().buffs
    local prefix = CustomUISettingsWindowTabPlayer.contentsName
    for suffix, key in pairs(BUFF_CHECKBOX_KEYS) do
        cfg[key] = ButtonGetPressedFlag(prefix .. suffix .. "Button") == true
    end
    CustomUI.PlayerStatusWindow.ApplyBuffSettings()
end

function CustomUISettingsWindowTabPlayer.ResetSettings()
    -- Footer Reset restores the settings baseline in Tabbed; nothing tab-local.
end

function CustomUISettingsWindowTabPlayer.OnBuffFilterChanged()
    EA_LabelCheckButton.Toggle()
end

function CustomUISettingsWindowTabPlayer.OnTogglePlayerStatusWindow()
    EA_LabelCheckButton.Toggle()
end
