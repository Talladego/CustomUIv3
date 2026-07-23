CustomUISettingsWindowTabTarget = {}

CustomUISettingsWindowTabTarget.contentsName = "SWTabTargetContentsScrollChild"

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

local function SyncBuffButtonsToCfg(prefix, cfg)
    ButtonSetPressedFlag(prefix .. "BuffsButton", cfg.showBuffs)
    ButtonSetPressedFlag(prefix .. "DebuffsButton", cfg.showDebuffs)
    ButtonSetPressedFlag(prefix .. "NeutralButton", cfg.showNeutral)
    ButtonSetPressedFlag(prefix .. "ShortButton", cfg.showShort)
    ButtonSetPressedFlag(prefix .. "LongButton", cfg.showLong)
    ButtonSetPressedFlag(prefix .. "PermanentButton", cfg.showPermanent)
    ButtonSetPressedFlag(prefix .. "PlayerCastOnlyButton", cfg.playerCastOnly)
end

local function ReadBuffButtonsToCfg(prefix, cfg)
    cfg.showBuffs = ButtonGetPressedFlag(prefix .. "BuffsButton") == true
    cfg.showDebuffs = ButtonGetPressedFlag(prefix .. "DebuffsButton") == true
    cfg.showNeutral = ButtonGetPressedFlag(prefix .. "NeutralButton") == true
    cfg.showShort = ButtonGetPressedFlag(prefix .. "ShortButton") == true
    cfg.showLong = ButtonGetPressedFlag(prefix .. "LongButton") == true
    cfg.showPermanent = ButtonGetPressedFlag(prefix .. "PermanentButton") == true
    cfg.playerCastOnly = ButtonGetPressedFlag(prefix .. "PlayerCastOnlyButton") == true
end

function CustomUISettingsWindowTabTarget.Initialize()
    LabelSetText(CustomUISettingsWindowTabTarget.contentsName .. "GeneralTitle", L"General")
    LabelSetText(CustomUISettingsWindowTabTarget.contentsName .. "GeneralTargetWindowEnabledLabel", L"Enabled")
    ButtonSetCheckButtonFlag(CustomUISettingsWindowTabTarget.contentsName .. "GeneralTargetWindowEnabledButton", true)

    local btH = CustomUISettingsWindowTabTarget.contentsName .. "BuffTrackerHostile"
    local btF = CustomUISettingsWindowTabTarget.contentsName .. "BuffTrackerFriendly"
    LabelSetText(btH .. "Title", L"Buff Tracker - Hostile target")
    LabelSetText(btF .. "Title", L"Buff Tracker - Friendly target")
    InitBuffTrackerSection(btH)
    InitBuffTrackerSection(btF)
end

function CustomUISettingsWindowTabTarget.UpdateSettings()
    ButtonSetPressedFlag(CustomUISettingsWindowTabTarget.contentsName .. "GeneralTargetWindowEnabledButton", CustomUI.IsComponentEnabled("TargetWindow"))

    local btH = CustomUISettingsWindowTabTarget.contentsName .. "BuffTrackerHostile"
    local btF = CustomUISettingsWindowTabTarget.contentsName .. "BuffTrackerFriendly"
    SyncBuffButtonsToCfg(btH, CustomUI.TargetWindow.GetBuffFilterHostile())
    SyncBuffButtonsToCfg(btF, CustomUI.TargetWindow.GetBuffFilterFriendly())
end

function CustomUISettingsWindowTabTarget.ApplyCurrent()
    local enabled = ButtonGetPressedFlag(CustomUISettingsWindowTabTarget.contentsName .. "GeneralTargetWindowEnabledButton")
    CustomUI.Settings.Components = CustomUI.Settings.Components or {}
    CustomUI.Settings.Components.TargetWindow = enabled
    if enabled then
        CustomUI.EnableComponent("TargetWindow")
    else
        CustomUI.DisableComponent("TargetWindow")
    end

    local btH = CustomUISettingsWindowTabTarget.contentsName .. "BuffTrackerHostile"
    local btF = CustomUISettingsWindowTabTarget.contentsName .. "BuffTrackerFriendly"
    ReadBuffButtonsToCfg(btH, CustomUI.TargetWindow.GetBuffFilterHostile())
    ReadBuffButtonsToCfg(btF, CustomUI.TargetWindow.GetBuffFilterFriendly())
    CustomUI.TargetWindow.ApplyBuffSettings()
end

function CustomUISettingsWindowTabTarget.ResetSettings()
end

function CustomUISettingsWindowTabTarget.OnBuffFilterChanged()
    EA_LabelCheckButton.Toggle()
end

function CustomUISettingsWindowTabTarget.OnToggleTargetWindow()
    EA_LabelCheckButton.Toggle()
end
