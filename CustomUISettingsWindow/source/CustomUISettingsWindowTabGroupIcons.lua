CustomUISettingsWindowTabGroupIcons = {}

CustomUISettingsWindowTabGroupIcons.contentsName = "SWTabGroupIconsContentsScrollChild"

local function EnsureGroupIconsSettings()
    CustomUI.Settings = CustomUI.Settings or { Components = {} }
    if CustomUI.Settings.Components == nil then
        CustomUI.Settings.Components = {}
    end
    if type(CustomUI.Settings.GroupIcons) ~= "table" then
        CustomUI.Settings.GroupIcons = {}
    end
    local s = CustomUI.Settings.GroupIcons
    if s.showParty == nil then s.showParty = true end
    if s.showWarband == nil then s.showWarband = true end
    if s.archetypeColors == nil then s.archetypeColors = true end
    if s.showFriendly == nil then s.showFriendly = true end
    if s.showHostile == nil then s.showHostile = true end
    return s
end

local function ApplyGroupIconsSettings()
    if CustomUI and CustomUI.GroupIcons and type(CustomUI.GroupIcons.OnSettingsChanged) == "function" then
        CustomUI.GroupIcons.OnSettingsChanged()
    end
end

function CustomUISettingsWindowTabGroupIcons.Initialize()
    -- General
    LabelSetText( CustomUISettingsWindowTabGroupIcons.contentsName.."GeneralTitle", L"General" )
    LabelSetText( CustomUISettingsWindowTabGroupIcons.contentsName.."GeneralGroupIconsEnabledLabel", L"Enabled" )
    ButtonSetCheckButtonFlag( CustomUISettingsWindowTabGroupIcons.contentsName.."GeneralGroupIconsEnabledButton", true )

    -- Icons
    EnsureGroupIconsSettings()
    LabelSetText( CustomUISettingsWindowTabGroupIcons.contentsName.."IconsTitle", L"Icons" )
    LabelSetText( CustomUISettingsWindowTabGroupIcons.contentsName.."IconsPartyLabel", L"Party" )
    LabelSetText( CustomUISettingsWindowTabGroupIcons.contentsName.."IconsWarbandLabel", L"Warband" )
    LabelSetText( CustomUISettingsWindowTabGroupIcons.contentsName.."IconsArchetypeColorsLabel", L"Archetype colors" )
    LabelSetText( CustomUISettingsWindowTabGroupIcons.contentsName.."IconsFriendlyLabel", L"Friendly" )
    LabelSetText( CustomUISettingsWindowTabGroupIcons.contentsName.."IconsHostileLabel", L"Hostile" )

    ButtonSetCheckButtonFlag( CustomUISettingsWindowTabGroupIcons.contentsName.."IconsPartyButton", true )
    ButtonSetCheckButtonFlag( CustomUISettingsWindowTabGroupIcons.contentsName.."IconsWarbandButton", true )
    ButtonSetCheckButtonFlag( CustomUISettingsWindowTabGroupIcons.contentsName.."IconsArchetypeColorsButton", true )
    ButtonSetCheckButtonFlag( CustomUISettingsWindowTabGroupIcons.contentsName.."IconsFriendlyButton", true )
    ButtonSetCheckButtonFlag( CustomUISettingsWindowTabGroupIcons.contentsName.."IconsHostileButton", true )

end


function CustomUISettingsWindowTabGroupIcons.UpdateSettings()
    -- General
    ButtonSetPressedFlag( CustomUISettingsWindowTabGroupIcons.contentsName.."GeneralGroupIconsEnabledButton", CustomUI.IsComponentEnabled("GroupIcons") )

    -- Icons
    local s = EnsureGroupIconsSettings()
    ButtonSetPressedFlag( CustomUISettingsWindowTabGroupIcons.contentsName.."IconsPartyButton", s.showParty == true )
    ButtonSetPressedFlag( CustomUISettingsWindowTabGroupIcons.contentsName.."IconsWarbandButton", s.showWarband == true )
    ButtonSetPressedFlag( CustomUISettingsWindowTabGroupIcons.contentsName.."IconsArchetypeColorsButton", s.archetypeColors == true )
    ButtonSetPressedFlag( CustomUISettingsWindowTabGroupIcons.contentsName.."IconsFriendlyButton", s.showFriendly == true )
    ButtonSetPressedFlag( CustomUISettingsWindowTabGroupIcons.contentsName.."IconsHostileButton", s.showHostile == true )

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

function CustomUISettingsWindowTabGroupIcons.OnToggleParty()
    EA_LabelCheckButton.Toggle()
    local s = EnsureGroupIconsSettings()
    s.showParty = ButtonGetPressedFlag( CustomUISettingsWindowTabGroupIcons.contentsName.."IconsPartyButton" ) == true
    ApplyGroupIconsSettings()
end

function CustomUISettingsWindowTabGroupIcons.OnToggleWarband()
    EA_LabelCheckButton.Toggle()
    local s = EnsureGroupIconsSettings()
    s.showWarband = ButtonGetPressedFlag( CustomUISettingsWindowTabGroupIcons.contentsName.."IconsWarbandButton" ) == true
    ApplyGroupIconsSettings()
end

function CustomUISettingsWindowTabGroupIcons.OnToggleArchetypeColors()
    EA_LabelCheckButton.Toggle()
    local s = EnsureGroupIconsSettings()
    s.archetypeColors = ButtonGetPressedFlag( CustomUISettingsWindowTabGroupIcons.contentsName.."IconsArchetypeColorsButton" ) == true
    ApplyGroupIconsSettings()
end

function CustomUISettingsWindowTabGroupIcons.OnToggleFriendly()
    EA_LabelCheckButton.Toggle()
    local s = EnsureGroupIconsSettings()
    s.showFriendly = ButtonGetPressedFlag( CustomUISettingsWindowTabGroupIcons.contentsName.."IconsFriendlyButton" ) == true
    ApplyGroupIconsSettings()
end

function CustomUISettingsWindowTabGroupIcons.OnToggleHostile()
    EA_LabelCheckButton.Toggle()
    local s = EnsureGroupIconsSettings()
    s.showHostile = ButtonGetPressedFlag( CustomUISettingsWindowTabGroupIcons.contentsName.."IconsHostileButton" ) == true
    ApplyGroupIconsSettings()
end
