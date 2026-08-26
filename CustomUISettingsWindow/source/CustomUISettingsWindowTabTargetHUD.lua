CustomUISettingsWindowTabTargetHUD = {}

CustomUISettingsWindowTabTargetHUD.contentsName = "SWTabTargetHUDContentsScrollChild"

local SIDE_SECTIONS = {
    { prefixKey = "BuffTrackerHostile",  sideKey = "hostile",  title = L"Hostile target" },
    { prefixKey = "BuffTrackerFriendly", sideKey = "friendly", title = L"Friendly target" },
    { prefixKey = "BuffTrackerSelf",     sideKey = "self",     title = L"Self (permanent on you)" },
}

local function SectionPrefix(section)
    return CustomUISettingsWindowTabTargetHUD.contentsName .. section.prefixKey
end

local function InitBuffTrackerSection(prefix)
    LabelSetText(prefix .. "CategoryLabel", L"Category")
    LabelSetText(prefix .. "BuffsLabel", L"Buffs")
    ButtonSetCheckButtonFlag(prefix .. "BuffsButton", true)
    LabelSetText(prefix .. "DebuffsLabel", L"Debuffs")
    ButtonSetCheckButtonFlag(prefix .. "DebuffsButton", true)
    LabelSetText(prefix .. "NeutralLabel", L"Neutral")
    ButtonSetCheckButtonFlag(prefix .. "NeutralButton", true)
    LabelSetText(prefix .. "DurationLabel", L"Duration")
    LabelSetText(prefix .. "ShortLabel", L"Short (<60s)")
    ButtonSetCheckButtonFlag(prefix .. "ShortButton", true)
    LabelSetText(prefix .. "LongLabel", L"Long (60s+)")
    ButtonSetCheckButtonFlag(prefix .. "LongButton", true)
    LabelSetText(prefix .. "PermanentLabel", L"Permanent")
    ButtonSetCheckButtonFlag(prefix .. "PermanentButton", true)
    LabelSetText(prefix .. "SourceLabel", L"Source")
    LabelSetText(prefix .. "PlayerCastOnlyLabel", L"My casts only")
    ButtonSetCheckButtonFlag(prefix .. "PlayerCastOnlyButton", true)
end

local function InitSideSection(section)
    local prefix = SectionPrefix(section)
    LabelSetText(prefix .. "Title", section.title)
    LabelSetText(prefix .. "ShowHealthBarLabel", L"Show HP bar")
    ButtonSetCheckButtonFlag(prefix .. "ShowHealthBarButton", true)
    LabelSetText(prefix .. "ShowBuffTrackerLabel", L"Show buff tracker")
    ButtonSetCheckButtonFlag(prefix .. "ShowBuffTrackerButton", true)
    InitBuffTrackerSection(prefix)
end

local function SyncBuffButtonsToCfg(prefix, cfg)
    ButtonSetPressedFlag(prefix .. "BuffsButton", cfg.showBuffs)
    ButtonSetPressedFlag(prefix .. "DebuffsButton", cfg.showDebuffs)
    ButtonSetPressedFlag(prefix .. "NeutralButton", cfg.showNeutral)
    ButtonSetPressedFlag(prefix .. "ShortButton", cfg.showShort)
    ButtonSetPressedFlag(prefix .. "LongButton", cfg.showLong)
    ButtonSetPressedFlag(prefix .. "PermanentButton", cfg.showPermanent)
    ButtonSetPressedFlag(prefix .. "PlayerCastOnlyButton", cfg.playerCastOnly)
end

local function SyncSideButtonsToSettings(section)
    local prefix = SectionPrefix(section)
    local sideSettings = CustomUI.TargetHUD.GetSideSettings(section.sideKey)
    ButtonSetPressedFlag(prefix .. "ShowHealthBarButton", sideSettings.showHealthBar)
    ButtonSetPressedFlag(prefix .. "ShowBuffTrackerButton", sideSettings.showBuffTracker)
    SyncBuffButtonsToCfg(prefix, sideSettings.buffs)
end

local function ReadSideButtonsToSettings(section)
    local prefix = SectionPrefix(section)
    local sideSettings = CustomUI.TargetHUD.GetSideSettings(section.sideKey)
    sideSettings.showHealthBar = ButtonGetPressedFlag(prefix .. "ShowHealthBarButton") == true
    sideSettings.showBuffTracker = ButtonGetPressedFlag(prefix .. "ShowBuffTrackerButton") == true
    sideSettings.buffs.showBuffs = ButtonGetPressedFlag(prefix .. "BuffsButton") == true
    sideSettings.buffs.showDebuffs = ButtonGetPressedFlag(prefix .. "DebuffsButton") == true
    sideSettings.buffs.showNeutral = ButtonGetPressedFlag(prefix .. "NeutralButton") == true
    sideSettings.buffs.showShort = ButtonGetPressedFlag(prefix .. "ShortButton") == true
    sideSettings.buffs.showLong = ButtonGetPressedFlag(prefix .. "LongButton") == true
    sideSettings.buffs.showPermanent = ButtonGetPressedFlag(prefix .. "PermanentButton") == true
    sideSettings.buffs.playerCastOnly = ButtonGetPressedFlag(prefix .. "PlayerCastOnlyButton") == true
end

function CustomUISettingsWindowTabTargetHUD.Initialize()
    LabelSetText(CustomUISettingsWindowTabTargetHUD.contentsName .. "GeneralTitle", L"General")
    LabelSetText(CustomUISettingsWindowTabTargetHUD.contentsName .. "GeneralTargetHUDWindowEnabledLabel", L"Enabled")
    ButtonSetCheckButtonFlag(CustomUISettingsWindowTabTargetHUD.contentsName .. "GeneralTargetHUDWindowEnabledButton", true)

    for i = 1, #SIDE_SECTIONS do
        InitSideSection(SIDE_SECTIONS[i])
    end
end

function CustomUISettingsWindowTabTargetHUD.UpdateSettings()
    ButtonSetPressedFlag(
        CustomUISettingsWindowTabTargetHUD.contentsName .. "GeneralTargetHUDWindowEnabledButton",
        CustomUI.IsComponentEnabled("TargetHUD")
    )

    for i = 1, #SIDE_SECTIONS do
        SyncSideButtonsToSettings(SIDE_SECTIONS[i])
    end
end

function CustomUISettingsWindowTabTargetHUD.ApplyCurrent()
    local enabled = ButtonGetPressedFlag(CustomUISettingsWindowTabTargetHUD.contentsName .. "GeneralTargetHUDWindowEnabledButton")
    CustomUI.Settings.Components = CustomUI.Settings.Components or {}
    CustomUI.Settings.Components.TargetHUD = enabled
    if enabled then
        CustomUI.EnableComponent("TargetHUD")
    else
        CustomUI.DisableComponent("TargetHUD")
    end

    for i = 1, #SIDE_SECTIONS do
        ReadSideButtonsToSettings(SIDE_SECTIONS[i])
    end
    CustomUI.TargetHUD.ApplySettings()
end

function CustomUISettingsWindowTabTargetHUD.ResetSettings()
end

function CustomUISettingsWindowTabTargetHUD.OnBuffFilterChanged()
    EA_LabelCheckButton.Toggle()
end

function CustomUISettingsWindowTabTargetHUD.OnSideToggleChanged()
    EA_LabelCheckButton.Toggle()
end

function CustomUISettingsWindowTabTargetHUD.OnToggleTargetHUDWindow()
    EA_LabelCheckButton.Toggle()
end
