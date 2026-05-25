CustomUISettingsWindowTabPlayer = {}

CustomUISettingsWindowTabPlayer.contentsName = "SWTabPlayerContentsScrollChild"

local function PlayerTabLowHpFlashComboWin()
    return CustomUISettingsWindowTabPlayer.contentsName .. "AppearanceLowHpScreenFlashThresholdRowThresholdCombo"
end

local m_lowHpFlashComboRefreshing = false

local function SyncLowHpFlashThresholdCombo()
    local w = PlayerTabLowHpFlashComboWin()
    if not DoesWindowExist(w) then
        return
    end
    m_lowHpFlashComboRefreshing = true
    ComboBoxClearMenuItems(w)
    local percents = CustomUI.PlayerStatusWindow.LOW_HP_SCREEN_FLASH_THRESHOLD_PERCENTS
    for _, pct in ipairs(percents) do
        ComboBoxAddMenuItem(w, towstring(pct) .. L"%")
    end
    local ps = CustomUI.PlayerStatusWindow.GetSettings()
    local sel = 2
    for i, pct in ipairs(percents) do
        if pct == ps.lowHpScreenFlashThresholdPercent then
            sel = i
            break
        end
    end
    ComboBoxSetSelectedMenuItem(w, sel)
    m_lowHpFlashComboRefreshing = false
end

function CustomUISettingsWindowTabPlayer.Initialize()
    -- General
    LabelSetText( CustomUISettingsWindowTabPlayer.contentsName.."GeneralTitle", L"General" )
    LabelSetText( CustomUISettingsWindowTabPlayer.contentsName.."GeneralPlayerStatusWindowEnabledLabel", L"Enabled" )
    ButtonSetCheckButtonFlag( CustomUISettingsWindowTabPlayer.contentsName.."GeneralPlayerStatusWindowEnabledButton", true )

    -- Appearance
    local ap = CustomUISettingsWindowTabPlayer.contentsName.."Appearance"
    LabelSetText(ap.."Title", L"Appearance")
    LabelSetText(ap.."MinimalAppearanceLabel", L"Minimal Appearance (DEPRECATED)")
    ButtonSetCheckButtonFlag(ap.."MinimalAppearanceButton", true)
    LabelSetText(ap.."MinimalShowApBarLabel", L"Show AP bar (minimal)")
    ButtonSetCheckButtonFlag(ap.."MinimalShowApBarButton", true)
    LabelSetText(ap.."MinimalHpBarArchetypeLabel", L"Archetype HP bar - CastBar strip (minimal)")
    ButtonSetCheckButtonFlag(ap.."MinimalHpBarArchetypeButton", false)
    LabelSetText(ap.."LowHpScreenFlashLabel", L"Low HP screen flash (damage)")
    ButtonSetCheckButtonFlag(ap.."LowHpScreenFlashButton", true)
    LabelSetText(ap.."LowHpScreenFlashThresholdRowThresholdLabel", L"Flash when HP falls below")
    SyncLowHpFlashThresholdCombo()
    local bt = CustomUISettingsWindowTabPlayer.contentsName.."BuffTracker"
    LabelSetText( bt.."Title", L"Buff Tracker" )
    LabelSetText( bt.."CategoryLabel",       L"Category" )
    LabelSetText( bt.."BuffsLabel",          L"Buffs" )
    ButtonSetCheckButtonFlag( bt.."BuffsButton",    true )
    LabelSetText( bt.."DebuffsLabel",        L"Debuffs" )
    ButtonSetCheckButtonFlag( bt.."DebuffsButton",  true )
    LabelSetText( bt.."NeutralLabel",        L"Neutral" )
    ButtonSetCheckButtonFlag( bt.."NeutralButton",  true )
    LabelSetText( bt.."DurationLabel",       L"Duration" )
    LabelSetText( bt.."ShortLabel",          L"Short (<60s)" )
    ButtonSetCheckButtonFlag( bt.."ShortButton",    true )
    LabelSetText( bt.."LongLabel",           L"Long (60s+)" )
    ButtonSetCheckButtonFlag( bt.."LongButton",     true )
    LabelSetText( bt.."PermanentLabel",      L"Permanent" )
    ButtonSetCheckButtonFlag( bt.."PermanentButton", true )
    LabelSetText( bt.."SourceLabel",         L"Source" )
    LabelSetText( bt.."PlayerCastOnlyLabel", L"My casts only" )
    ButtonSetCheckButtonFlag( bt.."PlayerCastOnlyButton", true )
end

function CustomUISettingsWindowTabPlayer.UpdateSettings()
    -- General
    ButtonSetPressedFlag( CustomUISettingsWindowTabPlayer.contentsName.."GeneralPlayerStatusWindowEnabledButton", CustomUI.IsComponentEnabled("PlayerStatusWindow") )

    -- Appearance
    local ap = CustomUISettingsWindowTabPlayer.contentsName.."Appearance"
    local ps = CustomUI.PlayerStatusWindow.GetSettings()
    ButtonSetPressedFlag(ap.."MinimalAppearanceButton", ps.appearance == "minimal")
    ButtonSetPressedFlag(ap.."MinimalShowApBarButton", ps.minimalShowApBar == true)
    ButtonSetPressedFlag(ap.."MinimalHpBarArchetypeButton", ps.minimalHpBarStyle == "archetype")
    ButtonSetPressedFlag(ap.."LowHpScreenFlashButton", ps.lowHpScreenFlash == true)
    SyncLowHpFlashThresholdCombo()
    
    -- Buff Tracker
    local bt  = CustomUISettingsWindowTabPlayer.contentsName.."BuffTracker"
    local cfg = CustomUI.PlayerStatusWindow.GetSettings().buffs
    ButtonSetPressedFlag( bt.."BuffsButton",         cfg.showBuffs )
    ButtonSetPressedFlag( bt.."DebuffsButton",       cfg.showDebuffs )
    ButtonSetPressedFlag( bt.."NeutralButton",       cfg.showNeutral )
    ButtonSetPressedFlag( bt.."ShortButton",         cfg.showShort )
    ButtonSetPressedFlag( bt.."LongButton",          cfg.showLong )
    ButtonSetPressedFlag( bt.."PermanentButton",     cfg.showPermanent )
    ButtonSetPressedFlag( bt.."PlayerCastOnlyButton", cfg.playerCastOnly )
end

function CustomUISettingsWindowTabPlayer.OnToggleMinimalAppearance()
    EA_LabelCheckButton.Toggle()
    local ap = CustomUISettingsWindowTabPlayer.contentsName.."Appearance"
    local minimal = ButtonGetPressedFlag(ap.."MinimalAppearanceButton")
    local s = CustomUI.PlayerStatusWindow.GetSettings()
    s.appearance = minimal and "minimal" or "default"
    if CustomUI.IsComponentEnabled("PlayerStatusWindow") then
        CustomUI.PlayerStatusWindow.ApplyAppearance()
    end
end

function CustomUISettingsWindowTabPlayer.OnToggleMinimalShowApBar()
    EA_LabelCheckButton.Toggle()
    local ap = CustomUISettingsWindowTabPlayer.contentsName.."Appearance"
    local showAp = ButtonGetPressedFlag(ap.."MinimalShowApBarButton")
    local s = CustomUI.PlayerStatusWindow.GetSettings()
    s.minimalShowApBar = showAp == true
    if CustomUI.IsComponentEnabled("PlayerStatusWindow") then
        CustomUI.PlayerStatusWindow.ApplyAppearance()
    end
end

function CustomUISettingsWindowTabPlayer.OnToggleMinimalHpBarArchetype()
    EA_LabelCheckButton.Toggle()
    local ap = CustomUISettingsWindowTabPlayer.contentsName.."Appearance"
    local on = ButtonGetPressedFlag(ap.."MinimalHpBarArchetypeButton")
    local s = CustomUI.PlayerStatusWindow.GetSettings()
    s.minimalHpBarStyle = on and "archetype" or "standard"
    if CustomUI.IsComponentEnabled("PlayerStatusWindow") then
        CustomUI.PlayerStatusWindow.ApplyAppearance()
    end
end

function CustomUISettingsWindowTabPlayer.OnToggleLowHpScreenFlash()
    EA_LabelCheckButton.Toggle()
    local ap = CustomUISettingsWindowTabPlayer.contentsName.."Appearance"
    local on = ButtonGetPressedFlag(ap.."LowHpScreenFlashButton")
    CustomUI.PlayerStatusWindow.GetSettings().lowHpScreenFlash = on == true
    CustomUI.PlayerStatusWindow.SyncLowHpScreenFlashFromSettings()
end

function CustomUISettingsWindowTabPlayer.OnLowHpScreenFlashThresholdComboSelChanged()
    if m_lowHpFlashComboRefreshing then
        return
    end
    local w = PlayerTabLowHpFlashComboWin()
    if not DoesWindowExist(w) then
        return
    end
    local idx = ComboBoxGetSelectedMenuItem(w)
    local percents = CustomUI.PlayerStatusWindow.LOW_HP_SCREEN_FLASH_THRESHOLD_PERCENTS
    if type(idx) ~= "number" or idx < 1 or idx > #percents then
        return
    end
    CustomUI.PlayerStatusWindow.GetSettings().lowHpScreenFlashThresholdPercent = percents[idx]
    CustomUI.PlayerStatusWindow.SyncLowHpScreenFlashFromSettings()
end

function CustomUISettingsWindowTabPlayer.ApplyCurrent()
    -- General: enable/disable is applied immediately on toggle, nothing to do here

    -- Buff Tracker: applied immediately on toggle, nothing to do here
end

function CustomUISettingsWindowTabPlayer.ResetSettings()

end

local BUFF_CHECKBOX_KEYS = {
    BuffTrackerBuffs         = "showBuffs",
    BuffTrackerDebuffs       = "showDebuffs",
    BuffTrackerNeutral       = "showNeutral",
    BuffTrackerShort         = "showShort",
    BuffTrackerLong          = "showLong",
    BuffTrackerPermanent     = "showPermanent",
    BuffTrackerPlayerCastOnly = "playerCastOnly",
}

function CustomUISettingsWindowTabPlayer.OnBuffFilterChanged()
    EA_LabelCheckButton.Toggle()
    local winName = SystemData.ActiveWindow.name
    -- strip the scroll child prefix to get the suffix
    local suffix = string.sub(winName, #CustomUISettingsWindowTabPlayer.contentsName + 1)
    local key = BUFF_CHECKBOX_KEYS[suffix]
    if not key then return end
    local cfg = CustomUI.PlayerStatusWindow.GetSettings().buffs
    cfg[key] = ButtonGetPressedFlag(winName .. "Button")
    CustomUI.PlayerStatusWindow.ApplyBuffSettings()
end

function CustomUISettingsWindowTabPlayer.OnTogglePlayerStatusWindow()
    EA_LabelCheckButton.Toggle()
    local enabled = ButtonGetPressedFlag( CustomUISettingsWindowTabPlayer.contentsName.."GeneralPlayerStatusWindowEnabledButton" )
    CustomUI.SetComponentEnabled( "PlayerStatusWindow", enabled )
end
