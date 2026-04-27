----------------------------------------------------------------
-- CustomUI.SCT: Controller — component adapter + runtime ownership (v2)
--
-- If the component is enabled, CustomUI owns SCT runtime even when every
-- setting is stock-equivalent. Disable the component to restore stock SCT.
--
-- Load order: SCTSettings → SCTAnim → SCTOverrides → SCTHandlers → SCTController → SCT.xml
----------------------------------------------------------------
if not CustomUI.SCT then CustomUI.SCT = {} end

local SCT = CustomUI.SCT

SCT._mode = SCT._mode or nil  -- "P", "D", or nil (unknown/uninitialised)

----------------------------------------------------------------
-- ApplyMode — called after component/settings changes
----------------------------------------------------------------

function SCT.ApplyMode()
    local enabled = CustomUI.IsComponentEnabled and CustomUI.IsComponentEnabled("SCT")

    if not enabled then
        if SCT._mode == "D" or SCT._handlersInstalled then
            SCT._switchToP()
        else
            SCT._mode = "P"
        end
        return
    end

    if SCT._mode ~= "D" then SCT._switchToD() end
end

function SCT._switchToP()
    WindowSetShowing("CustomUISCTWindow", false)
    SCT.RestoreHandlers()
    SCT.DestroyAllTrackers()
    SCT._mode = "P"
end

function SCT._switchToD()
    SCT.InstallHandlers()
    WindowSetShowing("CustomUISCTWindow", true)
    SCT._mode = "D"
end

----------------------------------------------------------------
-- Component adapter
----------------------------------------------------------------

local SCTComponent = { Name = "SCT", DefaultEnabled = false }

function SCTComponent:Initialize()
    SCT.GetSettings()
    return true
end

function SCTComponent:Enable()
    SCT._switchToD()
    return true
end

function SCTComponent:Disable()
    SCT._switchToP()
    return true
end

function SCTComponent:Shutdown()
    self:Disable()
end

CustomUI.RegisterComponent("SCT", SCTComponent)
