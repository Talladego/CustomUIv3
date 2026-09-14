CustomUISettingsWindowTabQoL = {}

CustomUISettingsWindowTabQoL.contentsName = "SWTabQoLContentsScrollChild"

local function EnsureQoLSettings()
    if CustomUI and CustomUI.QoL and type(CustomUI.QoL.EnsureSettings) == "function" then
        return CustomUI.QoL.EnsureSettings()
    end
    CustomUI.Settings = CustomUI.Settings or { Components = {} }
    CustomUI.Settings.QoL = CustomUI.Settings.QoL or {}
    return CustomUI.Settings.QoL
end

local function ApplyQoLSettings()
    if CustomUI and CustomUI.QoL and type(CustomUI.QoL.OnSettingsChanged) == "function" then
        CustomUI.QoL.OnSettingsChanged()
    end
end

local function ReadDaysEdit(windowName, fallback)
    if not DoesWindowExist(windowName) then
        return fallback
    end
    local text = TextEditBoxGetText(windowName)
    if text == nil or text == L"" then
        return fallback
    end
    local n = tonumber(text)
    if n == nil and type(WStringToString) == "function" then
        n = tonumber(WStringToString(text))
    end
    if n == nil or n < 0 then
        return fallback
    end
    return math.floor(n)
end

local function FillDaysEdit(windowName, value)
    if not DoesWindowExist(windowName) then
        return
    end
    value = tonumber(value) or 30
    if value < 0 then
        value = 0
    end
    TextEditBoxSetText(windowName, towstring(math.floor(value)))
end

local function FillNumericCombo(windowName, options, current)
    if not DoesWindowExist(windowName) then
        return
    end
    ComboBoxClearMenuItems(windowName)
    local selected = 1
    current = tonumber(current) or options[1]
    for i = 1, #options do
        ComboBoxAddMenuItem(windowName, towstring(options[i]))
        if options[i] == current then
            selected = i
        end
    end
    if #options > 0 then
        ComboBoxSetSelectedMenuItem(windowName, selected)
    end
end

local function ReadNumericCombo(windowName, options, fallback)
    if not DoesWindowExist(windowName) or #options == 0 then
        return fallback
    end
    local idx = tonumber(ComboBoxGetSelectedMenuItem(windowName)) or 1
    if idx < 1 then idx = 1 end
    if idx > #options then idx = #options end
    return options[idx]
end

local function FillThresholdCombo(windowName, current)
    if not DoesWindowExist(windowName) then
        return
    end
    local opts = (CustomUI and CustomUI.QoL and CustomUI.QoL.RedAlert and CustomUI.QoL.RedAlert.THRESHOLD_PERCENTS) or { 25, 50, 75, 100 }
    ComboBoxClearMenuItems(windowName)
    local selected = 1
    current = tonumber(current) or 50
    for i = 1, #opts do
        ComboBoxAddMenuItem(windowName, towstring(opts[i]) .. L"%")
        if opts[i] == current then
            selected = i
        end
    end
    ComboBoxSetSelectedMenuItem(windowName, selected)
end

local function ReadThresholdCombo(windowName, fallback)
    local opts = (CustomUI and CustomUI.QoL and CustomUI.QoL.RedAlert and CustomUI.QoL.RedAlert.THRESHOLD_PERCENTS) or { 25, 50, 75, 100 }
    if not DoesWindowExist(windowName) or #opts == 0 then
        return fallback
    end
    local idx = tonumber(ComboBoxGetSelectedMenuItem(windowName)) or 1
    if idx < 1 then idx = 1 end
    if idx > #opts then idx = #opts end
    return opts[idx]
end

local function SyncCombos()
    local c = CustomUISettingsWindowTabQoL.contentsName
    local s = EnsureQoLSettings()
    FillThresholdCombo(c .. "RedAlertThreshold", s.redAlert.thresholdPercent)
    local scoreOpts = (CustomUI and CustomUI.QoL and CustomUI.QoL.SCORE_DIFF_OPTIONS) or { 50, 100, 150, 200, 250 }
    local preOpts = (CustomUI and CustomUI.QoL and CustomUI.QoL.PRESTART_RETRY_OPTIONS) or { 15, 30, 45, 60 }
    FillNumericCombo(c .. "AutoSurrenderScoreDiff", scoreOpts, s.autoSurrender.scoreDiff)
    FillNumericCombo(c .. "AutoSurrenderPreStart", preOpts, s.autoSurrender.preStartRetry)
end

function CustomUISettingsWindowTabQoL.Initialize()
    local c = CustomUISettingsWindowTabQoL.contentsName
    LabelSetText(c .. "RedAlertTitle", L"Red Alert")
    LabelSetText(c .. "RedAlertEnabledLabel", L"Enabled")
    LabelSetText(c .. "RedAlertCenterMessageLabel", L"Center-screen message")
    LabelSetText(c .. "RedAlertThresholdLabel", L"HP threshold")
    ButtonSetText(c .. "RedAlertTestButton", L"Test flash")
    LabelSetText(c .. "AutoSurrenderTitle", L"Auto Surrender")
    LabelSetText(c .. "AutoSurrenderEnabledLabel", L"Enabled")
    LabelSetText(c .. "AutoSurrenderStatusMessagesLabel", L"Status chat messages")
    LabelSetText(c .. "AutoSurrenderKillRuleLabel", L"Kill-leader rule")
    LabelSetText(c .. "AutoSurrenderScoreDiffLabel", L"Score deficit")
    LabelSetText(c .. "AutoSurrenderPreStartLabel", L"Pre-start retry (sec)")
    LabelSetText(c .. "RezzAcceptTitle", L"Rezz Accept")
    LabelSetText(c .. "RezzAcceptEnabledLabel", L"Enabled")
    LabelSetText(c .. "RezzAcceptInfo", L"Automatically accepts resurrection prompts.")
    LabelSetText(c .. "AltTrackerTitle", L"Alt Tracker")
    LabelSetText(c .. "AltTrackerEnabledLabel", L"Enabled")
    LabelSetText(c .. "AltTrackerTrackGoldLabel", L"Track gold (backpack hover)")
    LabelSetText(c .. "AltTrackerIncludeBankLabel", L"Include bank in item counts")
    LabelSetText(c .. "AltTrackerCrossFactionLabel", L"Show cross-faction alts")
    LabelSetText(c .. "AltTrackerPruneDaysLabel", L"Prune stale characters")
    LabelSetText(c .. "AltTrackerPruneDaysSuffix", L"days (0 = off)")
    LabelSetText(c .. "AltTrackerInfo", L"Tracks bag items and gold across characters on this PC. Stale alts are removed on login.")
    LabelSetText(c .. "UiSoundTitle", L"UI Sound")
    LabelSetText(c .. "UiSoundMuteButtonClickLabel", L"Mute button click sound")
    LabelSetText(c .. "UiSoundInfo", L"Disables the standard UI button click sound while QoL is enabled.")
    SyncCombos()
    FillDaysEdit(c .. "AltTrackerPruneDaysEdit", EnsureQoLSettings().altTracker.pruneStaleDays)
end

function CustomUISettingsWindowTabQoL.UpdateSettings()
    local c = CustomUISettingsWindowTabQoL.contentsName
    local s = EnsureQoLSettings()
    ButtonSetPressedFlag(c .. "RedAlertEnabledButton", s.redAlert.enabled == true)
    ButtonSetPressedFlag(c .. "RedAlertCenterMessageButton", s.redAlert.centerMessage == true)
    ButtonSetPressedFlag(c .. "AutoSurrenderEnabledButton", s.autoSurrender.enabled == true)
    ButtonSetPressedFlag(c .. "AutoSurrenderStatusMessagesButton", s.autoSurrender.statusMessages == true)
    ButtonSetPressedFlag(c .. "AutoSurrenderKillRuleButton", s.autoSurrender.useKillRule == true)
    ButtonSetPressedFlag(c .. "RezzAcceptEnabledButton", s.rezzAccept.enabled == true)
    ButtonSetPressedFlag(c .. "AltTrackerEnabledButton", s.altTracker.enabled == true)
    ButtonSetPressedFlag(c .. "AltTrackerTrackGoldButton", s.altTracker.trackGold == true)
    ButtonSetPressedFlag(c .. "AltTrackerIncludeBankButton", s.altTracker.includeBank == true)
    ButtonSetPressedFlag(c .. "AltTrackerCrossFactionButton", s.altTracker.showCrossFaction == true)
    ButtonSetPressedFlag(c .. "UiSoundMuteButtonClickButton", s.muteButtonClickSound == true)
    FillDaysEdit(c .. "AltTrackerPruneDaysEdit", s.altTracker.pruneStaleDays)
    SyncCombos()
end

function CustomUISettingsWindowTabQoL.ApplyCurrent()
    local c = CustomUISettingsWindowTabQoL.contentsName
    local s = EnsureQoLSettings()
    s.redAlert.enabled = ButtonGetPressedFlag(c .. "RedAlertEnabledButton") == true
    s.redAlert.centerMessage = ButtonGetPressedFlag(c .. "RedAlertCenterMessageButton") == true
    s.redAlert.thresholdPercent = ReadThresholdCombo(c .. "RedAlertThreshold", 50)
    s.autoSurrender.enabled = ButtonGetPressedFlag(c .. "AutoSurrenderEnabledButton") == true
    s.autoSurrender.statusMessages = ButtonGetPressedFlag(c .. "AutoSurrenderStatusMessagesButton") == true
    s.autoSurrender.useKillRule = ButtonGetPressedFlag(c .. "AutoSurrenderKillRuleButton") == true
    local scoreOpts = (CustomUI and CustomUI.QoL and CustomUI.QoL.SCORE_DIFF_OPTIONS) or { 50, 100, 150, 200, 250 }
    local preOpts = (CustomUI and CustomUI.QoL and CustomUI.QoL.PRESTART_RETRY_OPTIONS) or { 15, 30, 45, 60 }
    s.autoSurrender.scoreDiff = ReadNumericCombo(c .. "AutoSurrenderScoreDiff", scoreOpts, 100)
    s.autoSurrender.preStartRetry = ReadNumericCombo(c .. "AutoSurrenderPreStart", preOpts, 30)
    s.rezzAccept.enabled = ButtonGetPressedFlag(c .. "RezzAcceptEnabledButton") == true
    s.altTracker.enabled = ButtonGetPressedFlag(c .. "AltTrackerEnabledButton") == true
    s.altTracker.trackGold = ButtonGetPressedFlag(c .. "AltTrackerTrackGoldButton") == true
    s.altTracker.includeBank = ButtonGetPressedFlag(c .. "AltTrackerIncludeBankButton") == true
    s.altTracker.showCrossFaction = ButtonGetPressedFlag(c .. "AltTrackerCrossFactionButton") == true
    s.altTracker.pruneStaleDays = ReadDaysEdit(c .. "AltTrackerPruneDaysEdit", s.altTracker.pruneStaleDays or 30)
    s.muteButtonClickSound = ButtonGetPressedFlag(c .. "UiSoundMuteButtonClickButton") == true
    if CustomUI and type(CustomUI.SetComponentEnabled) == "function" and type(CustomUI.IsComponentEnabled) == "function" then
        if not CustomUI.IsComponentEnabled("QoL") then
            CustomUI.SetComponentEnabled("QoL", true)
        end
    end
    ApplyQoLSettings()
end

function CustomUISettingsWindowTabQoL.ResetSettings()
end

function CustomUISettingsWindowTabQoL.OnToggleRedAlertEnabled()
    EA_LabelCheckButton.Toggle()
end

function CustomUISettingsWindowTabQoL.OnToggleRedAlertMessage()
    EA_LabelCheckButton.Toggle()
end

function CustomUISettingsWindowTabQoL.OnToggleAutoSurrenderEnabled()
    EA_LabelCheckButton.Toggle()
end

function CustomUISettingsWindowTabQoL.OnToggleAutoSurrenderStatus()
    EA_LabelCheckButton.Toggle()
end

function CustomUISettingsWindowTabQoL.OnToggleAutoSurrenderKills()
    EA_LabelCheckButton.Toggle()
end

function CustomUISettingsWindowTabQoL.OnToggleRezzAcceptEnabled()
    EA_LabelCheckButton.Toggle()
end

function CustomUISettingsWindowTabQoL.OnToggleAltTrackerEnabled()
    EA_LabelCheckButton.Toggle()
end

function CustomUISettingsWindowTabQoL.OnToggleAltTrackerGold()
    EA_LabelCheckButton.Toggle()
end

function CustomUISettingsWindowTabQoL.OnToggleAltTrackerBank()
    EA_LabelCheckButton.Toggle()
end

function CustomUISettingsWindowTabQoL.OnToggleAltTrackerCrossFaction()
    EA_LabelCheckButton.Toggle()
end

function CustomUISettingsWindowTabQoL.OnToggleMuteButtonClick()
    EA_LabelCheckButton.Toggle()
end

function CustomUISettingsWindowTabQoL.OnComboChanged()
end

function CustomUISettingsWindowTabQoL.OnRedAlertTest()
    if CustomUI and CustomUI.QoL and CustomUI.QoL.RedAlert and type(CustomUI.QoL.RedAlert.TestFlash) == "function" then
        CustomUI.QoL.RedAlert.TestFlash()
    end
end
