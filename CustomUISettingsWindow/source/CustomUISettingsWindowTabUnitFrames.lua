CustomUISettingsWindowTabUnitFrames = {}

CustomUISettingsWindowTabUnitFrames.contentsName = "SWTabUnitFramesContentsScrollChild"

function CustomUISettingsWindowTabUnitFrames.Initialize()
    -- General
    LabelSetText( CustomUISettingsWindowTabUnitFrames.contentsName.."GeneralTitle", L"General" )
    LabelSetText( CustomUISettingsWindowTabUnitFrames.contentsName.."GeneralUnitFramesEnabledLabel", L"Enabled" )
    ButtonSetCheckButtonFlag( CustomUISettingsWindowTabUnitFrames.contentsName.."GeneralUnitFramesEnabledButton", true )

end

function CustomUISettingsWindowTabUnitFrames.UpdateSettings()
    -- General
    ButtonSetPressedFlag( CustomUISettingsWindowTabUnitFrames.contentsName.."GeneralUnitFramesEnabledButton", CustomUI.IsComponentEnabled("UnitFrames") )

end

function CustomUISettingsWindowTabUnitFrames.ApplyCurrent()
    -- General: enable/disable is applied immediately on toggle, nothing to do here
end

function CustomUISettingsWindowTabUnitFrames.ResetSettings()

end

function CustomUISettingsWindowTabUnitFrames.OnToggleUnitFrames()
    EA_LabelCheckButton.Toggle()
    local enabled = ButtonGetPressedFlag( CustomUISettingsWindowTabUnitFrames.contentsName.."GeneralUnitFramesEnabledButton" )
    CustomUI.SetComponentEnabled( "UnitFrames", enabled )
end
