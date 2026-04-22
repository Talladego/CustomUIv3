CustomUISettingsWindowTabGroupIcons = {}

CustomUISettingsWindowTabGroupIcons.contentsName = "SWTabGroupIconsContentsScrollChild"

function CustomUISettingsWindowTabGroupIcons.Initialize()
    -- General
    LabelSetText( CustomUISettingsWindowTabGroupIcons.contentsName.."GeneralTitle", L"General" )
    LabelSetText( CustomUISettingsWindowTabGroupIcons.contentsName.."GeneralGroupIconsEnabledLabel", L"Enabled" )
    ButtonSetCheckButtonFlag( CustomUISettingsWindowTabGroupIcons.contentsName.."GeneralGroupIconsEnabledButton", true )

end


function CustomUISettingsWindowTabGroupIcons.UpdateSettings()
    -- General
    ButtonSetPressedFlag( CustomUISettingsWindowTabGroupIcons.contentsName.."GeneralGroupIconsEnabledButton", CustomUI.IsComponentEnabled("GroupIcons") )

end

function CustomUISettingsWindowTabGroupIcons.ApplyCurrent()
	-- General: enable/disable is applied immediately on toggle, nothing to do here
end

function CustomUISettingsWindowTabGroupIcons.ResetSettings()
end
   
function CustomUISettingsWindowTabGroupIcons.OnToggleGroupIcons()
    EA_LabelCheckButton.Toggle()
    local enabled = ButtonGetPressedFlag( CustomUISettingsWindowTabGroupIcons.contentsName.."GeneralGroupIconsEnabledButton" )
    CustomUI.SetComponentEnabled( "GroupIcons", enabled )
end
