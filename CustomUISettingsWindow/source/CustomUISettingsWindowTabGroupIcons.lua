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
    -- Archetype colors UI removed: always cyan roster rings.
    s.archetypeColors = false
    if s.highlightSocial == nil then s.highlightSocial = true end
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
    LabelSetText( CustomUISettingsWindowTabGroupIcons.contentsName.."GeneralTitle", L"General" )
    LabelSetText( CustomUISettingsWindowTabGroupIcons.contentsName.."GeneralGroupIconsEnabledLabel", L"Enabled" )
    ButtonSetCheckButtonFlag( CustomUISettingsWindowTabGroupIcons.contentsName.."GeneralGroupIconsEnabledButton", true )

    EnsureGroupIconsSettings()
    LabelSetText( CustomUISettingsWindowTabGroupIcons.contentsName.."IconsTitle", L"Icons" )
    LabelSetText( CustomUISettingsWindowTabGroupIcons.contentsName.."IconsPartyLabel", L"Party" )
    LabelSetText( CustomUISettingsWindowTabGroupIcons.contentsName.."IconsWarbandLabel", L"Warband" )
    LabelSetText( CustomUISettingsWindowTabGroupIcons.contentsName.."IconsFriendlyLabel", L"Friendly" )
    LabelSetText( CustomUISettingsWindowTabGroupIcons.contentsName.."IconsHostileLabel", L"Hostile" )
    LabelSetText( CustomUISettingsWindowTabGroupIcons.contentsName.."IconsGoldSocialLabel", L"Guild/Friends" )

    ButtonSetCheckButtonFlag( CustomUISettingsWindowTabGroupIcons.contentsName.."IconsPartyButton", true )
    ButtonSetCheckButtonFlag( CustomUISettingsWindowTabGroupIcons.contentsName.."IconsWarbandButton", true )
    ButtonSetCheckButtonFlag( CustomUISettingsWindowTabGroupIcons.contentsName.."IconsFriendlyButton", true )
    ButtonSetCheckButtonFlag( CustomUISettingsWindowTabGroupIcons.contentsName.."IconsHostileButton", true )
    ButtonSetCheckButtonFlag( CustomUISettingsWindowTabGroupIcons.contentsName.."IconsGoldSocialButton", true )
end

function CustomUISettingsWindowTabGroupIcons.UpdateSettings()
    ButtonSetPressedFlag( CustomUISettingsWindowTabGroupIcons.contentsName.."GeneralGroupIconsEnabledButton", CustomUI.IsComponentEnabled("GroupIcons") )

    local s = EnsureGroupIconsSettings()
    ButtonSetPressedFlag( CustomUISettingsWindowTabGroupIcons.contentsName.."IconsPartyButton", s.showParty == true )
    ButtonSetPressedFlag( CustomUISettingsWindowTabGroupIcons.contentsName.."IconsWarbandButton", s.showWarband == true )
    ButtonSetPressedFlag( CustomUISettingsWindowTabGroupIcons.contentsName.."IconsFriendlyButton", s.showFriendly == true )
    ButtonSetPressedFlag( CustomUISettingsWindowTabGroupIcons.contentsName.."IconsHostileButton", s.showHostile == true )
    ButtonSetPressedFlag( CustomUISettingsWindowTabGroupIcons.contentsName.."IconsGoldSocialButton", s.highlightSocial == true )
end

function CustomUISettingsWindowTabGroupIcons.ApplyCurrent()
    local enabled = ButtonGetPressedFlag( CustomUISettingsWindowTabGroupIcons.contentsName.."GeneralGroupIconsEnabledButton" )
    CustomUI.SetComponentEnabled( "GroupIcons", enabled )

    local s = EnsureGroupIconsSettings()
    local c = CustomUISettingsWindowTabGroupIcons.contentsName
    s.showParty = ButtonGetPressedFlag( c.."IconsPartyButton" ) == true
    s.showWarband = ButtonGetPressedFlag( c.."IconsWarbandButton" ) == true
    s.archetypeColors = false
    s.showFriendly = ButtonGetPressedFlag( c.."IconsFriendlyButton" ) == true
    s.showHostile = ButtonGetPressedFlag( c.."IconsHostileButton" ) == true
    s.highlightSocial = ButtonGetPressedFlag( c.."IconsGoldSocialButton" ) == true
    ApplyGroupIconsSettings()
end

function CustomUISettingsWindowTabGroupIcons.ResetSettings()
end

function CustomUISettingsWindowTabGroupIcons.OnToggleGroupIcons()
    EA_LabelCheckButton.Toggle()
end

function CustomUISettingsWindowTabGroupIcons.OnToggleParty()
    EA_LabelCheckButton.Toggle()
end

function CustomUISettingsWindowTabGroupIcons.OnToggleWarband()
    EA_LabelCheckButton.Toggle()
end

function CustomUISettingsWindowTabGroupIcons.OnToggleFriendly()
    EA_LabelCheckButton.Toggle()
end

function CustomUISettingsWindowTabGroupIcons.OnToggleHostile()
    EA_LabelCheckButton.Toggle()
end

function CustomUISettingsWindowTabGroupIcons.OnToggleGoldSocial()
    EA_LabelCheckButton.Toggle()
end
