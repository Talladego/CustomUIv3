CustomUISettingsWindowTabUnitFrames = {}

CustomUISettingsWindowTabUnitFrames.contentsName = "SWTabUnitFramesContentsScrollChild"

local function EnsureUnitFramesGroupsSettings()
    CustomUI.Settings = CustomUI.Settings or { Components = {} }
    if CustomUI.Settings.Components == nil then
        CustomUI.Settings.Components = {}
    end
    if type(CustomUI.Settings.UnitFrames) ~= "table" then
        CustomUI.Settings.UnitFrames = {}
    end
    local s = CustomUI.Settings.UnitFrames
    if s.groupsParty == nil then
        s.groupsParty = false
    end
    if s.groupsWarband == nil then
        s.groupsWarband = true
    end
    if s.groupsScenario == nil then
        s.groupsScenario = true
    end
    if s.showActionPointsBar == nil then
        s.showActionPointsBar = false
    end
    if s.colorMemberNamesByArchetype == nil then
        s.colorMemberNamesByArchetype = false
    end
    if s.sortPartyMembersByRole == nil then
        s.sortPartyMembersByRole = false
    end
    return s
end

local function ApplyUnitFramesGroupsSettings()
    if CustomUI and CustomUI.UnitFrames and type(CustomUI.UnitFrames.OnGroupsSettingsChanged) == "function" then
        CustomUI.UnitFrames.OnGroupsSettingsChanged()
    end
end

function CustomUISettingsWindowTabUnitFrames.Initialize()
    EnsureUnitFramesGroupsSettings()

    LabelSetText( CustomUISettingsWindowTabUnitFrames.contentsName.."GeneralTitle", L"General" )
    LabelSetText( CustomUISettingsWindowTabUnitFrames.contentsName.."GeneralUnitFramesEnabledLabel", L"Enabled" )
    ButtonSetCheckButtonFlag( CustomUISettingsWindowTabUnitFrames.contentsName.."GeneralUnitFramesEnabledButton", true )

    LabelSetText( CustomUISettingsWindowTabUnitFrames.contentsName.."AppearanceTitle", L"Appearance" )
    LabelSetText( CustomUISettingsWindowTabUnitFrames.contentsName.."AppearancePartyLabel", L"Party" )
    LabelSetText( CustomUISettingsWindowTabUnitFrames.contentsName.."AppearanceWarbandLabel", L"Warband" )
    LabelSetText( CustomUISettingsWindowTabUnitFrames.contentsName.."AppearanceScenarioLabel", L"Scenario" )
    ButtonSetCheckButtonFlag( CustomUISettingsWindowTabUnitFrames.contentsName.."AppearancePartyButton", true )
    ButtonSetCheckButtonFlag( CustomUISettingsWindowTabUnitFrames.contentsName.."AppearanceWarbandButton", true )
    ButtonSetCheckButtonFlag( CustomUISettingsWindowTabUnitFrames.contentsName.."AppearanceScenarioButton", true )

    LabelSetText( CustomUISettingsWindowTabUnitFrames.contentsName.."AppearanceShowActionPointsBarLabel", L"AP bar" )
    ButtonSetCheckButtonFlag( CustomUISettingsWindowTabUnitFrames.contentsName.."AppearanceShowActionPointsBarButton", false )

    LabelSetText( CustomUISettingsWindowTabUnitFrames.contentsName.."AppearanceColorNamesByArchetypeLabel", L"Archetype name colors" )
    ButtonSetCheckButtonFlag( CustomUISettingsWindowTabUnitFrames.contentsName.."AppearanceColorNamesByArchetypeButton", false )

    LabelSetText( CustomUISettingsWindowTabUnitFrames.contentsName.."AppearanceSortPartyMembersByRoleLabel", L"Sort party by role" )
    ButtonSetCheckButtonFlag( CustomUISettingsWindowTabUnitFrames.contentsName.."AppearanceSortPartyMembersByRoleButton", false )

end

function CustomUISettingsWindowTabUnitFrames.UpdateSettings()
    -- General
    ButtonSetPressedFlag( CustomUISettingsWindowTabUnitFrames.contentsName.."GeneralUnitFramesEnabledButton", CustomUI.IsComponentEnabled("UnitFrames") )

    local s = EnsureUnitFramesGroupsSettings()
    ButtonSetPressedFlag( CustomUISettingsWindowTabUnitFrames.contentsName.."AppearancePartyButton", s.groupsParty == true )
    ButtonSetPressedFlag( CustomUISettingsWindowTabUnitFrames.contentsName.."AppearanceWarbandButton", s.groupsWarband == true )
    ButtonSetPressedFlag( CustomUISettingsWindowTabUnitFrames.contentsName.."AppearanceScenarioButton", s.groupsScenario == true )
    ButtonSetPressedFlag( CustomUISettingsWindowTabUnitFrames.contentsName.."AppearanceShowActionPointsBarButton", s.showActionPointsBar == true )
    ButtonSetPressedFlag( CustomUISettingsWindowTabUnitFrames.contentsName.."AppearanceColorNamesByArchetypeButton", s.colorMemberNamesByArchetype == true )
    ButtonSetPressedFlag( CustomUISettingsWindowTabUnitFrames.contentsName.."AppearanceSortPartyMembersByRoleButton", s.sortPartyMembersByRole == true )

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

function CustomUISettingsWindowTabUnitFrames.OnToggleShowActionPointsBar()
    EA_LabelCheckButton.Toggle()
    local s = EnsureUnitFramesGroupsSettings()
    s.showActionPointsBar = ButtonGetPressedFlag( CustomUISettingsWindowTabUnitFrames.contentsName.."AppearanceShowActionPointsBarButton" ) == true
    ApplyUnitFramesGroupsSettings()
end

function CustomUISettingsWindowTabUnitFrames.OnToggleColorNamesByArchetype()
    EA_LabelCheckButton.Toggle()
    local s = EnsureUnitFramesGroupsSettings()
    s.colorMemberNamesByArchetype = ButtonGetPressedFlag( CustomUISettingsWindowTabUnitFrames.contentsName.."AppearanceColorNamesByArchetypeButton" ) == true
    ApplyUnitFramesGroupsSettings()
end

function CustomUISettingsWindowTabUnitFrames.OnToggleSortPartyMembersByRole()
    EA_LabelCheckButton.Toggle()
    local s = EnsureUnitFramesGroupsSettings()
    s.sortPartyMembersByRole = ButtonGetPressedFlag( CustomUISettingsWindowTabUnitFrames.contentsName.."AppearanceSortPartyMembersByRoleButton" ) == true
    ApplyUnitFramesGroupsSettings()
end

function CustomUISettingsWindowTabUnitFrames.OnToggleGroupsParty()
    EA_LabelCheckButton.Toggle()
    local s = EnsureUnitFramesGroupsSettings()
    s.groupsParty = ButtonGetPressedFlag( CustomUISettingsWindowTabUnitFrames.contentsName.."AppearancePartyButton" ) == true
    ApplyUnitFramesGroupsSettings()
end

function CustomUISettingsWindowTabUnitFrames.OnToggleGroupsWarband()
    EA_LabelCheckButton.Toggle()
    local s = EnsureUnitFramesGroupsSettings()
    s.groupsWarband = ButtonGetPressedFlag( CustomUISettingsWindowTabUnitFrames.contentsName.."AppearanceWarbandButton" ) == true
    ApplyUnitFramesGroupsSettings()
end

function CustomUISettingsWindowTabUnitFrames.OnToggleGroupsScenario()
    EA_LabelCheckButton.Toggle()
    local s = EnsureUnitFramesGroupsSettings()
    s.groupsScenario = ButtonGetPressedFlag( CustomUISettingsWindowTabUnitFrames.contentsName.."AppearanceScenarioButton" ) == true
    ApplyUnitFramesGroupsSettings()
end
