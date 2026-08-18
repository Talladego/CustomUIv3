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
    -- AP bar UI removed: always off. Archetype career rings UI removed: always on.
    s.showActionPointsBar = false
    s.colorCareerIconRingByArchetype = true
    s.colorMemberNamesByArchetype = nil
    if s.sortPartyMembersByRole == nil then
        s.sortPartyMembersByRole = false
    end
    if s.useTargetHudHpBarTexture == nil then
        s.useTargetHudHpBarTexture = false
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

    LabelSetText( CustomUISettingsWindowTabUnitFrames.contentsName.."AppearanceTargetHudHpBarStyleLabel", L"Archetype HP Bar" )
    ButtonSetCheckButtonFlag( CustomUISettingsWindowTabUnitFrames.contentsName.."AppearanceTargetHudHpBarStyleButton", false )

    LabelSetText( CustomUISettingsWindowTabUnitFrames.contentsName.."AppearanceSortPartyMembersByRoleLabel", L"Sort party by role" )
    ButtonSetCheckButtonFlag( CustomUISettingsWindowTabUnitFrames.contentsName.."AppearanceSortPartyMembersByRoleButton", false )
end

function CustomUISettingsWindowTabUnitFrames.UpdateSettings()
    ButtonSetPressedFlag( CustomUISettingsWindowTabUnitFrames.contentsName.."GeneralUnitFramesEnabledButton", CustomUI.IsComponentEnabled("UnitFrames") )

    local s = EnsureUnitFramesGroupsSettings()
    ButtonSetPressedFlag( CustomUISettingsWindowTabUnitFrames.contentsName.."AppearancePartyButton", s.groupsParty == true )
    ButtonSetPressedFlag( CustomUISettingsWindowTabUnitFrames.contentsName.."AppearanceWarbandButton", s.groupsWarband == true )
    ButtonSetPressedFlag( CustomUISettingsWindowTabUnitFrames.contentsName.."AppearanceScenarioButton", s.groupsScenario == true )
    ButtonSetPressedFlag( CustomUISettingsWindowTabUnitFrames.contentsName.."AppearanceTargetHudHpBarStyleButton", s.useTargetHudHpBarTexture == true )
    ButtonSetPressedFlag( CustomUISettingsWindowTabUnitFrames.contentsName.."AppearanceSortPartyMembersByRoleButton", s.sortPartyMembersByRole == true )
end

function CustomUISettingsWindowTabUnitFrames.ApplyCurrent()
    local enabled = ButtonGetPressedFlag( CustomUISettingsWindowTabUnitFrames.contentsName.."GeneralUnitFramesEnabledButton" )
    CustomUI.SetComponentEnabled( "UnitFrames", enabled )

    local s = EnsureUnitFramesGroupsSettings()
    local c = CustomUISettingsWindowTabUnitFrames.contentsName
    s.showActionPointsBar = false
    s.colorCareerIconRingByArchetype = true
    s.useTargetHudHpBarTexture = ButtonGetPressedFlag( c.."AppearanceTargetHudHpBarStyleButton" ) == true
    s.sortPartyMembersByRole = ButtonGetPressedFlag( c.."AppearanceSortPartyMembersByRoleButton" ) == true
    s.groupsParty = ButtonGetPressedFlag( c.."AppearancePartyButton" ) == true
    s.groupsWarband = ButtonGetPressedFlag( c.."AppearanceWarbandButton" ) == true
    s.groupsScenario = ButtonGetPressedFlag( c.."AppearanceScenarioButton" ) == true
    ApplyUnitFramesGroupsSettings()
end

function CustomUISettingsWindowTabUnitFrames.ResetSettings()
end

function CustomUISettingsWindowTabUnitFrames.OnToggleUnitFrames()
    EA_LabelCheckButton.Toggle()
end

function CustomUISettingsWindowTabUnitFrames.OnToggleTargetHudHpBarStyle()
    EA_LabelCheckButton.Toggle()
end

function CustomUISettingsWindowTabUnitFrames.OnToggleSortPartyMembersByRole()
    EA_LabelCheckButton.Toggle()
end

function CustomUISettingsWindowTabUnitFrames.OnToggleGroupsParty()
    EA_LabelCheckButton.Toggle()
end

function CustomUISettingsWindowTabUnitFrames.OnToggleGroupsWarband()
    EA_LabelCheckButton.Toggle()
end

function CustomUISettingsWindowTabUnitFrames.OnToggleGroupsScenario()
    EA_LabelCheckButton.Toggle()
end
