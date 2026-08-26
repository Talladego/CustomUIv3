CustomUISettingsWindowTabAutoFPS = {}

CustomUISettingsWindowTabAutoFPS.contentsName = "SWTabAutoFPSContentsScrollChild"

local function EnsureAutoFPSSettings()
    if CustomUI and CustomUI.AutoFPS and type(CustomUI.AutoFPS.EnsureSettings) == "function" then
        return CustomUI.AutoFPS.EnsureSettings()
    end
    CustomUI.Settings = CustomUI.Settings or { Components = {} }
    if type(CustomUI.Settings.AutoFPS) ~= "table" then
        CustomUI.Settings.AutoFPS = {}
    end
    return CustomUI.Settings.AutoFPS
end

local function ApplyAutoFPSSettings()
    if CustomUI and CustomUI.AutoFPS and type(CustomUI.AutoFPS.OnSettingsChanged) == "function" then
        CustomUI.AutoFPS.OnSettingsChanged()
    end
end

local function ComboOptions(kind)
    local afps = CustomUI and CustomUI.AutoFPS
    if kind == "downshiftFps" then
        return (afps and afps.DownshiftFpsOptions) or { 10, 15, 20, 25, 30 }
    end
    if kind == "upshiftFps" then
        return (afps and afps.UpshiftFpsOptions) or { 30, 35, 40, 45, 50, 60 }
    end
    if kind == "downshiftSeconds" then
        return (afps and afps.DownshiftSecondsOptions) or { 3, 4, 5, 6, 8, 10 }
    end
    if kind == "upshiftSeconds" then
        return (afps and afps.UpshiftSecondsOptions) or { 5, 8, 10, 15, 20 }
    end
    if kind == "sampleWindowSeconds" then
        return (afps and afps.SampleWindowOptions) or { 3, 5, 8, 10 }
    end
    if kind == "cooldownSeconds" then
        return (afps and afps.CooldownOptions) or { 10, 15, 20, 30, 45 }
    end
    return {}
end

local function ComboLabel(kind, value)
    value = tonumber(value) or 0
    if kind == "downshiftFps" or kind == "upshiftFps" then
        return towstring(value) .. L" FPS"
    end
    return towstring(value) .. L" s"
end

local function FillCombo(windowName, kind, current)
    if not DoesWindowExist(windowName) then
        return
    end
    ComboBoxClearMenuItems(windowName)
    local opts = ComboOptions(kind)
    local selected = 1
    for i = 1, #opts do
        ComboBoxAddMenuItem(windowName, ComboLabel(kind, opts[i]))
        if opts[i] == current then
            selected = i
        end
    end
    if #opts > 0 then
        ComboBoxSetSelectedMenuItem(windowName, selected)
    end
end

local function ReadCombo(windowName, kind, fallback)
    local opts = ComboOptions(kind)
    if not DoesWindowExist(windowName) or #opts == 0 then
        return fallback
    end
    local idx = tonumber(ComboBoxGetSelectedMenuItem(windowName)) or 1
    if idx < 1 then
        idx = 1
    end
    if idx > #opts then
        idx = #opts
    end
    return opts[idx]
end

local function SyncCombos()
    local c = CustomUISettingsWindowTabAutoFPS.contentsName
    local s = EnsureAutoFPSSettings()
    FillCombo(c .. "ThresholdsDownshiftFps", "downshiftFps", s.downshiftFps)
    FillCombo(c .. "ThresholdsDownshiftSeconds", "downshiftSeconds", s.downshiftSeconds)
    FillCombo(c .. "ThresholdsUpshiftFps", "upshiftFps", s.upshiftFps)
    FillCombo(c .. "ThresholdsUpshiftSeconds", "upshiftSeconds", s.upshiftSeconds)
    FillCombo(c .. "ThresholdsSampleWindow", "sampleWindowSeconds", s.sampleWindowSeconds)
    FillCombo(c .. "ThresholdsCooldown", "cooldownSeconds", s.cooldownSeconds)
end

local function SyncStatus()
    local c = CustomUISettingsWindowTabAutoFPS.contentsName
    local w = c .. "StatusText"
    if not DoesWindowExist(w) then
        return
    end
    local text = L"Enable AutoFPS, then Apply."
    if CustomUI and CustomUI.AutoFPS and type(CustomUI.AutoFPS.GetStatusText) == "function" then
        text = CustomUI.AutoFPS.GetStatusText()
    end
    LabelSetText(w, text)
end

function CustomUISettingsWindowTabAutoFPS.Initialize()
    local c = CustomUISettingsWindowTabAutoFPS.contentsName
    LabelSetText(c .. "GeneralTitle", L"General")
    LabelSetText(c .. "GeneralAutoFPSEnabledLabel", L"Enabled")
    ButtonSetCheckButtonFlag(c .. "GeneralAutoFPSEnabledButton", true)
    LabelSetText(c .. "GeneralNotifyChatLabel", L"Chat notifications")
    ButtonSetCheckButtonFlag(c .. "GeneralNotifyChatButton", true)
    LabelSetText(c .. "GeneralUpshiftCombatLabel", L"Upshift only out of combat")
    ButtonSetCheckButtonFlag(c .. "GeneralUpshiftCombatButton", true)

    LabelSetText(c .. "ThresholdsTitle", L"Thresholds")
    LabelSetText(c .. "ThresholdsDownshiftFpsLabel", L"Downshift below")
    LabelSetText(c .. "ThresholdsDownshiftSecondsLabel", L"Downshift after")
    LabelSetText(c .. "ThresholdsUpshiftFpsLabel", L"Upshift above")
    LabelSetText(c .. "ThresholdsUpshiftSecondsLabel", L"Upshift after")
    LabelSetText(c .. "ThresholdsSampleWindowLabel", L"Average window")
    LabelSetText(c .. "ThresholdsCooldownLabel", L"Cooldown after switch")

    LabelSetText(c .. "StatusTitle", L"Status")
    SyncCombos()
    SyncStatus()
end

function CustomUISettingsWindowTabAutoFPS.UpdateSettings()
    local c = CustomUISettingsWindowTabAutoFPS.contentsName
    local enabled = false
    if CustomUI and type(CustomUI.IsComponentEnabled) == "function" then
        enabled = CustomUI.IsComponentEnabled("AutoFPS")
    end
    ButtonSetPressedFlag(c .. "GeneralAutoFPSEnabledButton", enabled)

    local s = EnsureAutoFPSSettings()
    ButtonSetPressedFlag(c .. "GeneralNotifyChatButton", s.notifyChat ~= false)
    ButtonSetPressedFlag(c .. "GeneralUpshiftCombatButton", s.upshiftOutOfCombat ~= false)
    SyncCombos()
    SyncStatus()
end

function CustomUISettingsWindowTabAutoFPS.ApplyCurrent()
    local c = CustomUISettingsWindowTabAutoFPS.contentsName
    if CustomUI and type(CustomUI.SetComponentEnabled) == "function" then
        CustomUI.SetComponentEnabled("AutoFPS", ButtonGetPressedFlag(c .. "GeneralAutoFPSEnabledButton"))
    end
    local s = EnsureAutoFPSSettings()
    s.notifyChat = ButtonGetPressedFlag(c .. "GeneralNotifyChatButton") == true
    s.upshiftOutOfCombat = ButtonGetPressedFlag(c .. "GeneralUpshiftCombatButton") == true
    s.downshiftFps = ReadCombo(c .. "ThresholdsDownshiftFps", "downshiftFps", 20)
    s.downshiftSeconds = ReadCombo(c .. "ThresholdsDownshiftSeconds", "downshiftSeconds", 5)
    s.upshiftFps = ReadCombo(c .. "ThresholdsUpshiftFps", "upshiftFps", 45)
    s.upshiftSeconds = ReadCombo(c .. "ThresholdsUpshiftSeconds", "upshiftSeconds", 10)
    s.sampleWindowSeconds = ReadCombo(c .. "ThresholdsSampleWindow", "sampleWindowSeconds", 5)
    s.cooldownSeconds = ReadCombo(c .. "ThresholdsCooldown", "cooldownSeconds", 20)
    ApplyAutoFPSSettings()
    SyncStatus()
end

function CustomUISettingsWindowTabAutoFPS.ResetSettings()
end

function CustomUISettingsWindowTabAutoFPS.OnToggleEnabled()
    EA_LabelCheckButton.Toggle()
end

function CustomUISettingsWindowTabAutoFPS.OnToggleNotifyChat()
    EA_LabelCheckButton.Toggle()
end

function CustomUISettingsWindowTabAutoFPS.OnToggleUpshiftCombat()
    EA_LabelCheckButton.Toggle()
end

function CustomUISettingsWindowTabAutoFPS.OnComboChanged()
end
