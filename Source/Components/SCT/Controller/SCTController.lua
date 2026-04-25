----------------------------------------------------------------
-- CustomUI.SCT: Controller (component adapter)
-- Responsibilities: RegisterComponent, Enable/Disable, wiring SCT to CustomUI; no separate
--   View/ layer for SCT; the heavy runtime lives in SCTEventText.lua
--   and SCTHandlers.lua, not under View/ (that folder is a minimal placeholder; settings UX is
--   CustomUISettingsWindow). SCTSettings.lua: schema, GetSettings, migrations. Load order
--   in CustomUI.mod: SCTSettings, SCTEventText, SCTHandlers, SCTController, then View/SCT.xml (no
--   duplicate <Script> of this file in XML).
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
    local dbg = CustomUI.GetClientDebugLog()
    if type(dbg) == "function" then dbg("[SCT:Controller] " .. tostring(msg)) end
end

function SCTComponent:Enable()
    SCTCtrlLog("Enable called")
    SCTCtrlLog("Installing CustomUI SCT event handlers (no stock overrides)")
    local ih = CustomUI.SCT and CustomUI.SCT.InstallHandlers
    if type(ih) == "function" then
        local ok, err = pcall(ih)
        if not ok then
            SCTCtrlLog("InstallHandlers failed: " .. tostring(err))
        end
    else
        SCTCtrlLog("InstallHandlers missing (SCTHandlers.lua parse/load failed? Check uilog for BOM/UTF-8 errors on that file)")
    end
    if WindowSetShowing then
        pcall(function() WindowSetShowing("CustomUISCTWindow", true) end)
    end
    pcall(function() CustomUI.SCT.GetSettings() end)
    SCTCtrlLog("Enable done; m_active: " .. tostring(CustomUI.SCT.m_active)
        .. " OnUpdate: " .. tostring(type(CustomUI.SCT.OnUpdate))
        .. " handlersInstalled: " .. tostring(CustomUI.SCT._handlersInstalled))
    if CustomUI.SCT.Trace then
        CustomUI.SCT.Trace("Enable path complete")
    end
    return true
end

function SCTComponent:Disable()
    SCTCtrlLog("Disable called")
    if WindowSetShowing then
        pcall(function() WindowSetShowing("CustomUISCTWindow", false) end)
    end
    if CustomUI.SCT and CustomUI.SCT.RestoreHandlers then
        CustomUI.SCT.RestoreHandlers()
    end
    if CustomUI.SCT and CustomUI.SCT.DestroyAllTrackers then
        CustomUI.SCT.DestroyAllTrackers()
    end
    SCTCtrlLog("Disable done")
    return true
end

function SCTComponent:Shutdown()
    SCTCtrlLog("Shutdown called")
    if WindowSetShowing then
        pcall(function() WindowSetShowing("CustomUISCTWindow", false) end)
    end
    if CustomUI.SCT and CustomUI.SCT.RestoreHandlers then
        CustomUI.SCT.RestoreHandlers()
    end
    if CustomUI.SCT and CustomUI.SCT.DestroyAllTrackers then
        CustomUI.SCT.DestroyAllTrackers()
    end
end

local function SCTBootProbe()
    local dbg = CustomUI.GetClientDebugLog()
    if type(dbg) ~= "function" then return end
    dbg(string.format(
        "[SCT:Controller] boot probe: OnUpdate=%s InstallHandlers=%s RestoreHandlers=%s _RuntimeForHandlers=%s",
        type(CustomUI.SCT.OnUpdate),
        type(CustomUI.SCT.InstallHandlers),
        type(CustomUI.SCT.RestoreHandlers),
        type(CustomUI.SCT._RuntimeForHandlers)
    ))
end
pcall(SCTBootProbe)

CustomUI.RegisterComponent("SCT", SCTComponent)
