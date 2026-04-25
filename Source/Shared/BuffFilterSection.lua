----------------------------------------------------------------
-- CustomUI.BuffFilterSection — **only legacy file under Source/Shared** (removal candidate)
-- All other `Shared/*` is current. Used only by in-addon settings tabs: `CustomUI.<Name>.Tab` +
-- `*Tab.xml` (Player/Group/Target*/TargetHUD). CustomUISettingsWindow does not call this.
-- Remove when: all those Tab tables and *Tab.xml entries are removed from CustomUI.mod, then
-- delete this file if nothing references it. See README "Legacy code (removal candidates)".
----------------------------------------------------------------

CustomUI.BuffFilterSection = {}

local CHECKBOX_KEYS = {
    showBuffs      = "BuffsCheckBox",
    showDebuffs    = "DebuffsCheckBox",
    showNeutral    = "NeutralCheckBox",
    showShort      = "ShortCheckBox",
    showLong       = "LongCheckBox",
    showPermanent  = "PermanentCheckBox",
    playerCastOnly = "PlayerCastOnlyCheckBox",
}

-- Sets all label strings for the buff filter section under contentName.
function CustomUI.BuffFilterSection.SetupLabels(contentName)
    LabelSetText(contentName .. "BuffSectionLabel",    L"Buff display")
    LabelSetText(contentName .. "CategoryLabel",       L"Category")
    LabelSetText(contentName .. "BuffsLabel",          L"Buffs")
    LabelSetText(contentName .. "DebuffsLabel",        L"Debuffs")
    LabelSetText(contentName .. "NeutralLabel",        L"Neutral")
    LabelSetText(contentName .. "DurationLabel",       L"Duration")
    LabelSetText(contentName .. "ShortLabel",          L"Short (<60s)")
    LabelSetText(contentName .. "LongLabel",           L"Long (60s+)")
    LabelSetText(contentName .. "PermanentLabel",      L"Permanent")
    LabelSetText(contentName .. "SourceLabel",         L"Source")
    LabelSetText(contentName .. "PlayerCastOnlyLabel", L"My casts only")
end

-- Syncs all filter checkboxes to the values in cfg (a buffs settings table).
function CustomUI.BuffFilterSection.RefreshControls(contentName, cfg)
    if not contentName or not DoesWindowExist(contentName) or not cfg then return end
    for key, suffix in pairs(CHECKBOX_KEYS) do
        local winName = contentName .. suffix
        if DoesWindowExist(winName) then
            ButtonSetPressedFlag(winName, cfg[key] == true)
        end
    end
end

-- Call from each tab's OnFilterChanged. getSettingsFn returns the buffs cfg table;
-- applyFn is called after the value is toggled to propagate the change.
function CustomUI.BuffFilterSection.OnFilterChanged(getSettingsFn, applyFn)
    local winName = SystemData.ActiveWindow.name
    local key
    for k, suffix in pairs(CHECKBOX_KEYS) do
        if string.sub(winName, -#suffix) == suffix then
            key = k
            break
        end
    end
    if not key then return end
    local cfg = getSettingsFn()
    cfg[key] = not cfg[key]
    ButtonSetPressedFlag(winName, cfg[key])
    applyFn()
end
