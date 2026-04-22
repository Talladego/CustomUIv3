CustomUISettingsWindowTabPlayer = {}

CustomUISettingsWindowTabPlayer.contentsName = "SWTabPlayerContentsScrollChild"

function CustomUISettingsWindowTabPlayer.Initialize()
    -- General
    LabelSetText( CustomUISettingsWindowTabPlayer.contentsName.."GeneralTitle", L"General" )
    LabelSetText( CustomUISettingsWindowTabPlayer.contentsName.."GeneralPlayerStatusWindowEnabledLabel", L"Enabled" )
    ButtonSetCheckButtonFlag( CustomUISettingsWindowTabPlayer.contentsName.."GeneralPlayerStatusWindowEnabledButton", true )

    -- Buff Tracker
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
    -- General
    ButtonSetPressedFlag( CustomUISettingsWindowTabPlayer.contentsName.."GeneralPlayerStatusWindowEnabledButton", CustomUI.IsComponentEnabled("PlayerStatusWindow") )
    
    -- Buff Tracker
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
    -- General: enable/disable is applied immediately on toggle, nothing to do here

    -- Buff Tracker: applied immediately on toggle, nothing to do here
end

function CustomUISettingsWindowTabPlayer.ResetSettings()

end

local BUFF_CHECKBOX_KEYS = {
    BuffTrackerBuffs         = "showBuffs",
    BuffTrackerDebuffs       = "showDebuffs",
    BuffTrackerNeutral       = "showNeutral",
    BuffTrackerShort         = "showShort",
    BuffTrackerLong          = "showLong",
    BuffTrackerPermanent     = "showPermanent",
    BuffTrackerPlayerCastOnly = "playerCastOnly",
}

function CustomUISettingsWindowTabPlayer.OnBuffFilterChanged()
    EA_LabelCheckButton.Toggle()
    local winName = SystemData.ActiveWindow.name
    -- strip the scroll child prefix to get the suffix
    local suffix = string.sub(winName, #CustomUISettingsWindowTabPlayer.contentsName + 1)
    local key = BUFF_CHECKBOX_KEYS[suffix]
    if not key then return end
    local cfg = CustomUI.PlayerStatusWindow.GetSettings().buffs
    cfg[key] = ButtonGetPressedFlag(winName .. "Button")
    CustomUI.PlayerStatusWindow.ApplyBuffSettings()
end

function CustomUISettingsWindowTabPlayer.OnTogglePlayerStatusWindow()
    EA_LabelCheckButton.Toggle()
    local enabled = ButtonGetPressedFlag( CustomUISettingsWindowTabPlayer.contentsName.."GeneralPlayerStatusWindowEnabledButton" )
    CustomUI.SetComponentEnabled( "PlayerStatusWindow", enabled )
end
