----------------------------------------------------------------
-- CustomUI.SCT — Scrolling Combat Text
-- Component adapter. Runtime logic lives in SCTEventText.lua;
-- settings schema and pure helpers in SCTSettings.lua.
-- External settings addons own all settings window XML and bindings.
----------------------------------------------------------------

if not CustomUI.SCT then
    CustomUI.SCT = {}
end

----------------------------------------------------------------
-- Component adapter
----------------------------------------------------------------

local SCTComponent = {
    Name           = "SCT",
    DefaultEnabled = false,
}

function SCTComponent:Initialize()
    pcall(function() CustomUI.SCT.GetSettings() end)
    return true
end

local function SCTCtrlLog(msg)
    if type(d) == "function" then d("[SCT:Controller] " .. tostring(msg)) end
end

function SCTComponent:Enable()
    SCTCtrlLog("Enable called")
    SCTCtrlLog("EA_System_EventText.AddCombatEventText is CustomUI override: " .. tostring(EA_System_EventText and EA_System_EventText.AddCombatEventText ~= nil))
    CustomUI.SCT.m_active = true
    pcall(function() CustomUI.SCT.GetSettings() end)
    SCTCtrlLog("Enable done — m_active: " .. tostring(CustomUI.SCT.m_active))
    return true
end

function SCTComponent:Disable()
    SCTCtrlLog("Disable called")
    CustomUI.SCT.Deactivate()
    SCTCtrlLog("Disable done")
    return true
end

function SCTComponent:Shutdown()
    SCTCtrlLog("Shutdown called")
    CustomUI.SCT.Deactivate()
end

CustomUI.RegisterComponent("SCT", SCTComponent)
