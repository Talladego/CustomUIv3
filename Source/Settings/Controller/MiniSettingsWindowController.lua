----------------------------------------------------------------
-- CustomUI.MiniSettingsWindow — Controller
-- LEGACY (removal candidate) / **DEPRECATED:** Use **CustomUISettingsWindow** for component toggles and tabs. This file is
--   not loaded from `CustomUI.mod`. See View/MiniSettingsWindow.lua for the same notice.
----------------------------------------------------------------

if not CustomUI.MiniSettingsWindow then
    CustomUI.MiniSettingsWindow = {}
end

local function ResolveComponentToggleTarget(componentName)
    return componentName
end

local function IsToggleStateApplied(componentName)
    return CustomUI.IsComponentEnabled(componentName)
end

----------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------

function CustomUI.MiniSettingsWindow.Shutdown()
end

function CustomUI.MiniSettingsWindow.OnShown()
    WindowUtils.OnShown()
    CustomUI.MiniSettingsWindow.RefreshData()
end

function CustomUI.MiniSettingsWindow.OnHidden()
    WindowUtils.OnHidden()
end

----------------------------------------------------------------
-- Visibility
----------------------------------------------------------------

function CustomUI.MiniSettingsWindow.Show()
    WindowSetShowing( "CustomUIMiniSettingsWindow", true )
end

function CustomUI.MiniSettingsWindow.Hide()
    WindowSetShowing( "CustomUIMiniSettingsWindow", false )
end

function CustomUI.MiniSettingsWindow.IsVisible()
    return WindowGetShowing( "CustomUIMiniSettingsWindow" )
end

function CustomUI.MiniSettingsWindow.Toggle()
    if CustomUI.MiniSettingsWindow.IsVisible() then
        CustomUI.MiniSettingsWindow.Hide()
    else
        CustomUI.MiniSettingsWindow.Show()
    end
end

----------------------------------------------------------------
-- Checkbox toggle (mirrors ChatFiltersWindow.OnToggleChannel)
----------------------------------------------------------------

function CustomUI.MiniSettingsWindow.OnToggleComponent()
    local windowIndex  = WindowGetId( SystemData.ActiveWindow.name )
    local windowParent = WindowGetParent( SystemData.ActiveWindow.name )
    local dataIndex    = ListBoxGetDataIndex( windowParent, windowIndex )

    if not dataIndex or dataIndex < 1 then
        return
    end

    local componentName = CustomUI.MiniSettingsWindow.GetComponentName( dataIndex )
    if type(componentName) ~= "string" or componentName == "" then
        return
    end

    local toggleTarget = ResolveComponentToggleTarget(componentName)
    local newState = CustomUI.MiniSettingsWindow.ToggleState( dataIndex )
    local checkBox  = "CustomUIMiniSettingsWindowListRow" .. windowIndex .. "CheckBox"

    if CustomUI.SetComponentEnabled( toggleTarget, newState ) then
        local appliedState = IsToggleStateApplied(componentName)
        CustomUI.MiniSettingsWindow.SetState( dataIndex, appliedState )
        ButtonSetPressedFlag( checkBox, appliedState )
        CustomUI.MiniSettingsWindow.RefreshData()
        return
    end

    CustomUI.MiniSettingsWindow.SetState( dataIndex, not newState )
    ButtonSetPressedFlag( checkBox, not newState )

    if CustomUI.PrintMessage then
        CustomUI.PrintMessage( L"Unable to update component: " .. towstring( componentName ) )
    end
end

----------------------------------------------------------------
-- Apply (mirrors ChatFiltersWindow.SetAllFiltersChanges)
----------------------------------------------------------------

function CustomUI.MiniSettingsWindow.Apply()
    -- Legacy handler retained for XML compatibility; checkboxes now apply immediately.
    CustomUI.MiniSettingsWindow.Hide()
end

function CustomUI.MiniSettingsWindow.ResetAllToDefaults()
    if type(CustomUI.ResetAllToDefaults) ~= "function" then
        return
    end

    CustomUI.ResetAllToDefaults()
    CustomUI.MiniSettingsWindow.RefreshData()
end
