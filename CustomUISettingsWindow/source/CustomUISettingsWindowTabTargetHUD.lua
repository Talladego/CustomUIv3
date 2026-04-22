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
end

function CustomUISettingsWindowTabTargetHUD.ResetSettings()
end

local BUFF_CHECKBOX_KEYS = {
    BuffTrackerHostileBuffs = { "hostile", "showBuffs" },
    BuffTrackerHostileDebuffs = { "hostile", "showDebuffs" },
    BuffTrackerHostileNeutral = { "hostile", "showNeutral" },
    BuffTrackerHostileShort = { "hostile", "showShort" },
    BuffTrackerHostileLong = { "hostile", "showLong" },
    BuffTrackerHostilePermanent = { "hostile", "showPermanent" },
    BuffTrackerHostilePlayerCastOnly = { "hostile", "playerCastOnly" },
    BuffTrackerFriendlyBuffs = { "friendly", "showBuffs" },
    BuffTrackerFriendlyDebuffs = { "friendly", "showDebuffs" },
    BuffTrackerFriendlyNeutral = { "friendly", "showNeutral" },
    BuffTrackerFriendlyShort = { "friendly", "showShort" },
    BuffTrackerFriendlyLong = { "friendly", "showLong" },
    BuffTrackerFriendlyPermanent = { "friendly", "showPermanent" },
    BuffTrackerFriendlyPlayerCastOnly = { "friendly", "playerCastOnly" },
}

function CustomUISettingsWindowTabTargetHUD.OnBuffFilterChanged()
    EA_LabelCheckButton.Toggle()
    local winName = SystemData.ActiveWindow.name
    local suffix = string.sub(winName, #CustomUISettingsWindowTabTargetHUD.contentsName + 1)
    local entry = BUFF_CHECKBOX_KEYS[suffix]
    if not entry then return end
    local slot, key = entry[1], entry[2]
    local cfg = slot == "hostile" and CustomUI.TargetHUD.GetBuffFilterHostile() or CustomUI.TargetHUD.GetBuffFilterFriendly()
    cfg[key] = ButtonGetPressedFlag(winName .. "Button")
    CustomUI.TargetHUD.ApplyBuffSettings()
end

function CustomUISettingsWindowTabTargetHUD.OnToggleTargetHUDWindow()
    EA_LabelCheckButton.Toggle()
    local enabled = ButtonGetPressedFlag(CustomUISettingsWindowTabTargetHUD.contentsName .. "GeneralTargetHUDWindowEnabledButton")
    -- Same as Target tab: EnableComponent only saves Settings on success; persist the toggle first.
    CustomUI.Settings.Components = CustomUI.Settings.Components or {}
    CustomUI.Settings.Components.TargetHUD = enabled
    if enabled then
        CustomUI.EnableComponent("TargetHUD")
    else
        CustomUI.DisableComponent("TargetHUD")
    end
    ButtonSetPressedFlag(
        CustomUISettingsWindowTabTargetHUD.contentsName .. "GeneralTargetHUDWindowEnabledButton",
        CustomUI.IsComponentEnabled("TargetHUD"))
end
