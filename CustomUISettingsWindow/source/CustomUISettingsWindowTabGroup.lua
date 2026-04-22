CustomUISettingsWindowTabGroup = {}

CustomUISettingsWindowTabGroup.contentsName = "SWTabGroupContentsScrollChild"

function CustomUISettingsWindowTabGroup.Initialize()
    -- General
    LabelSetText( CustomUISettingsWindowTabGroup.contentsName.."GeneralTitle", L"General" )
    LabelSetText( CustomUISettingsWindowTabGroup.contentsName.."GeneralGroupWindowEnabledLabel", L"Enabled" )
    ButtonSetCheckButtonFlag( CustomUISettingsWindowTabGroup.contentsName.."GeneralGroupWindowEnabledButton", true )

    -- Buff Tracker
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
    -- General
    ButtonSetPressedFlag( CustomUISettingsWindowTabGroup.contentsName.."GeneralGroupWindowEnabledButton", CustomUI.IsComponentEnabled("GroupWindow") )

    -- Buff Tracker
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
    -- General: enable/disable is applied immediately on toggle, nothing to do here

    -- Buff Tracker: applied immediately on toggle, nothing to do here
end

function CustomUISettingsWindowTabGroup.ResetSettings()

end

local BUFF_CHECKBOX_KEYS = {
    BuffTrackerBuffs          = "showBuffs",
    BuffTrackerDebuffs        = "showDebuffs",
    BuffTrackerNeutral        = "showNeutral",
    BuffTrackerShort          = "showShort",
    BuffTrackerLong           = "showLong",
    BuffTrackerPermanent      = "showPermanent",
    BuffTrackerPlayerCastOnly = "playerCastOnly",
}

function CustomUISettingsWindowTabGroup.OnBuffFilterChanged()
    EA_LabelCheckButton.Toggle()
    local winName = SystemData.ActiveWindow.name
    local suffix = string.sub(winName, #CustomUISettingsWindowTabGroup.contentsName + 1)
    local key = BUFF_CHECKBOX_KEYS[suffix]
    if not key then return end
    local cfg = CustomUI.GroupWindow.GetSettings().buffs
    cfg[key] = ButtonGetPressedFlag(winName .. "Button")
    CustomUI.GroupWindow.ApplyBuffSettings()
end

function CustomUISettingsWindowTabGroup.OnToggleGroupWindow()
    EA_LabelCheckButton.Toggle()
    local enabled = ButtonGetPressedFlag( CustomUISettingsWindowTabGroup.contentsName.."GeneralGroupWindowEnabledButton" )
    CustomUI.SetComponentEnabled( "GroupWindow", enabled )
end
