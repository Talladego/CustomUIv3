CustomUISettingsWindowTabTargetHUD = {}

CustomUISettingsWindowTabTargetHUD.contentsName = "SWTabTargetHUDContentsScrollChild"

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

function CustomUISettingsWindowTabTargetHUD.Initialize()
    LabelSetText(CustomUISettingsWindowTabTargetHUD.contentsName .. "GeneralTitle", L"General")
    LabelSetText(CustomUISettingsWindowTabTargetHUD.contentsName .. "GeneralTargetHUDWindowEnabledLabel", L"Enabled")
    ButtonSetCheckButtonFlag(CustomUISettingsWindowTabTargetHUD.contentsName .. "GeneralTargetHUDWindowEnabledButton", true)

    local btH = CustomUISettingsWindowTabTargetHUD.contentsName .. "BuffTrackerHostile"
    local btF = CustomUISettingsWindowTabTargetHUD.contentsName .. "BuffTrackerFriendly"
    LabelSetText(btH .. "Title", L"Buff Tracker - Hostile target")
    LabelSetText(btF .. "Title", L"Buff Tracker - Friendly target")
    InitBuffTrackerSection(btH)
    InitBuffTrackerSection(btF)
end

function CustomUISettingsWindowTabTargetHUD.UpdateSettings()
    ButtonSetPressedFlag(CustomUISettingsWindowTabTargetHUD.contentsName .. "GeneralTargetHUDWindowEnabledButton", CustomUI.IsComponentEnabled("TargetHUD"))

    local btH = CustomUISettingsWindowTabTargetHUD.contentsName .. "BuffTrackerHostile"
    local btF = CustomUISettingsWindowTabTargetHUD.contentsName .. "BuffTrackerFriendly"
    SyncBuffButtonsToCfg(btH, CustomUI.TargetHUD.GetBuffFilterHostile())
    SyncBuffButtonsToCfg(btF, CustomUI.TargetHUD.GetBuffFilterFriendly())
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

    local btH = CustomUISettingsWindowTabTargetHUD.contentsName .. "BuffTrackerHostile"
    local btF = CustomUISettingsWindowTabTargetHUD.contentsName .. "BuffTrackerFriendly"
    ReadBuffButtonsToCfg(btH, CustomUI.TargetHUD.GetBuffFilterHostile())
    ReadBuffButtonsToCfg(btF, CustomUI.TargetHUD.GetBuffFilterFriendly())
    CustomUI.TargetHUD.ApplyBuffSettings()
end

function CustomUISettingsWindowTabTargetHUD.ResetSettings()
end

function CustomUISettingsWindowTabTargetHUD.OnBuffFilterChanged()
    EA_LabelCheckButton.Toggle()
end

function CustomUISettingsWindowTabTargetHUD.OnToggleTargetHUDWindow()
    EA_LabelCheckButton.Toggle()
end
