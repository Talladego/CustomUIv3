CustomUISettingsWindowTabSmartAssist = {}

CustomUISettingsWindowTabSmartAssist.contentsName = "SWTabSmartAssistContentsScrollChild"

local function EnsureSmartAssistSettings()
    if CustomUI and CustomUI.SmartAssist and type(CustomUI.SmartAssist.EnsureSettings) == "function" then
        return CustomUI.SmartAssist.EnsureSettings()
    end
    CustomUI.Settings = CustomUI.Settings or { Components = {} }
    if type(CustomUI.Settings.SmartAssist) ~= "table" then
        CustomUI.Settings.SmartAssist = {
            enabled = false,
            range = 100,
            notify = false,
        }
    end
    return CustomUI.Settings.SmartAssist
end

local function ApplySmartAssistSettings()
    if CustomUI and CustomUI.SmartAssist and type(CustomUI.SmartAssist.OnSettingsChanged) == "function" then
        CustomUI.SmartAssist.OnSettingsChanged()
    end
end

local function ClampRange(n)
    n = tonumber(n) or 100
    if n < 1 then
        n = 1
    elseif n > 500 then
        n = 500
    end
    return math.floor(n + 0.5)
end

function CustomUISettingsWindowTabSmartAssist.Initialize()
    local c = CustomUISettingsWindowTabSmartAssist.contentsName
    LabelSetText(c .. "GeneralTitle", L"SmartAssist")
    LabelSetText(c .. "GeneralEnabledLabel", L"Enable SmartAssist")
    LabelSetText(
        c .. "GeneralInfo",
        L"Creates one hotbar macro (CustomUI SmartAssist) that assists the best nearby ally by KillDamage, then Deathblows, then Total Damage. Works in scenarios and open-world party/warband. Never assists yourself. Sets an assist only with no hostile target; clears the macro while you have one. Bind the macro and press it yourself — RoR ignores /assist sent from addons. Disable deletes the macro and clears it from action bars."
    )
    LabelSetText(c .. "RangeTitle", L"Range")
    LabelSetText(c .. "RangeLabel", L"Assist range (ft)")
    LabelSetText(c .. "RangeInfo", L"Only allies within this map distance are considered (party, warband, and scenario map pips). Default 100.")
    LabelSetText(c .. "NotifyTitle", L"Notify")
    LabelSetText(c .. "NotifyEnabledLabel", L"Chat message when assist target changes")
    LabelSetText(
        c .. "NotifyInfo",
        L"Prints a CustomUI chat line whenever the managed macro picks a new player, including the lead reason and KD / DB / Damage. No pick until someone has combat scoreboard data."
    )
    ButtonSetCheckButtonFlag(c .. "GeneralEnabledButton", true)
    ButtonSetCheckButtonFlag(c .. "NotifyEnabledButton", true)
end

function CustomUISettingsWindowTabSmartAssist.UpdateSettings()
    local c = CustomUISettingsWindowTabSmartAssist.contentsName
    local s = EnsureSmartAssistSettings()
    ButtonSetPressedFlag(c .. "GeneralEnabledButton", s.enabled == true)
    ButtonSetPressedFlag(c .. "NotifyEnabledButton", s.notify == true)
    if DoesWindowExist(c .. "RangeEdit") then
        TextEditBoxSetText(c .. "RangeEdit", towstring(tostring(ClampRange(s.range))))
    end
end

function CustomUISettingsWindowTabSmartAssist.ApplyCurrent()
    local c = CustomUISettingsWindowTabSmartAssist.contentsName
    local s = EnsureSmartAssistSettings()
    s.enabled = ButtonGetPressedFlag(c .. "GeneralEnabledButton") == true
    s.notify = ButtonGetPressedFlag(c .. "NotifyEnabledButton") == true
    s.autoAssist = nil
    if DoesWindowExist(c .. "RangeEdit") then
        local text = TextEditBoxGetText(c .. "RangeEdit")
        local asString = text
        if type(text) == "wstring" and type(WStringToString) == "function" then
            asString = WStringToString(text)
        end
        s.range = ClampRange(tonumber(asString) or s.range)
    end
    ApplySmartAssistSettings()
end

function CustomUISettingsWindowTabSmartAssist.OnToggleEnabled()
    EA_LabelCheckButton.Toggle()
end

function CustomUISettingsWindowTabSmartAssist.OnToggleNotify()
    EA_LabelCheckButton.Toggle()
end
