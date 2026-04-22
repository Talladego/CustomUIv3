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
end

function CustomUISettingsWindowTabTarget.ResetSettings()
end

-- Suffix after contentsName (e.g. BuffTrackerHostileBuffs) → slot + filter key
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

function CustomUISettingsWindowTabTarget.OnBuffFilterChanged()
    EA_LabelCheckButton.Toggle()
    local winName = SystemData.ActiveWindow.name
    local suffix = string.sub(winName, #CustomUISettingsWindowTabTarget.contentsName + 1)
    local entry = BUFF_CHECKBOX_KEYS[suffix]
    if not entry then return end
    local slot, key = entry[1], entry[2]
    local cfg = slot == "hostile" and CustomUI.TargetWindow.GetBuffFilterHostile() or CustomUI.TargetWindow.GetBuffFilterFriendly()
    cfg[key] = ButtonGetPressedFlag(winName .. "Button")
    CustomUI.TargetWindow.ApplyBuffSettings()
end

function CustomUISettingsWindowTabTarget.OnToggleTargetWindow()
    EA_LabelCheckButton.Toggle()
    local enabled = ButtonGetPressedFlag(CustomUISettingsWindowTabTarget.contentsName .. "GeneralTargetWindowEnabledButton")
    -- CustomUI.EnableComponent only writes Settings.Components on success. Persist the choice first
    -- so a transient Enable() failure (or load-order) still saves and the next /reload can retry.
    CustomUI.Settings.Components = CustomUI.Settings.Components or {}
    CustomUI.Settings.Components.TargetWindow = enabled
    if enabled then
        CustomUI.EnableComponent("TargetWindow")
    else
        CustomUI.DisableComponent("TargetWindow")
    end
    ButtonSetPressedFlag(
        CustomUISettingsWindowTabTarget.contentsName .. "GeneralTargetWindowEnabledButton",
        CustomUI.IsComponentEnabled("TargetWindow"))
end
