----------------------------------------------------------------
-- CustomUI.MiniSettingsWindow — View
-- LEGACY (removal candidate) / **DEPRECATED:** Shipped settings UX is the **CustomUISettingsWindow** addon (`/cui`). This
--   small list window is not loaded from `CustomUI.mod` (see commented `<File>` entries). Kept
--   only for reference or a local fork that re-enables it. Do not extend; add UI in
--   CustomUISettingsWindow instead.
-- ListData uses `CustomUI.MiniSettingsList.*` (`Table.field` style, like stock ListData).
----------------------------------------------------------------

if not CustomUI.MiniSettingsList then
    CustomUI.MiniSettingsList = {}
end
local M = CustomUI.MiniSettingsList
M.rowListData           = {}
M.componentNames        = {}
M.componentEnabledState = {}

----------------------------------------------------------------
-- Widget initialisation
----------------------------------------------------------------

function CustomUI.MiniSettingsWindow.Initialize()
    LabelSetText( "CustomUIMiniSettingsWindowTitleBarText",  L"CustomUI" )
    ButtonSetText( "CustomUIMiniSettingsWindowResetButton",  L"Reset" )
    LabelSetText( "CustomUIMiniSettingsWindowHeaderLabel",   L"Components" )
end

----------------------------------------------------------------
-- Rebuild data tables and refresh the ListBox display order.
-- Called from OnShown (mirrors ChatFiltersWindow.ResetChannelList).
----------------------------------------------------------------

function CustomUI.MiniSettingsWindow.RefreshData()
    M.rowListData           = {}
    M.componentNames        = {}
    M.componentEnabledState = {}

    local rowIndex = 0

    for _, componentName in ipairs( CustomUI.ComponentOrder ) do
        rowIndex = rowIndex + 1
        M.rowListData[rowIndex]           = { componentName = towstring( componentName ) }
        M.componentNames[rowIndex]        = componentName
        M.componentEnabledState[rowIndex] = CustomUI.IsComponentEnabled( componentName )
    end

    -- Build sequential display order and push to ListBox, which triggers PopulateRow.
    local order = {}
    for i = 1, #M.rowListData do
        order[i] = i
    end
    ListBoxSetDisplayOrder( "CustomUIMiniSettingsWindowList", order )
end

----------------------------------------------------------------
-- State accessors (used by Controller to avoid direct list-table access)
----------------------------------------------------------------

function CustomUI.MiniSettingsWindow.ToggleState( dataIndex )
    M.componentEnabledState[dataIndex] = not M.componentEnabledState[dataIndex]
    return M.componentEnabledState[dataIndex]
end

function CustomUI.MiniSettingsWindow.GetPendingChanges()
    local changes = {}
    for i, componentName in ipairs( M.componentNames ) do
        changes[i] = { name = componentName, enabled = M.componentEnabledState[i] }
    end
    return changes
end

function CustomUI.MiniSettingsWindow.GetComponentName( dataIndex )
    return M.componentNames[dataIndex]
end

function CustomUI.MiniSettingsWindow.SetState( dataIndex, enabled )
    M.componentEnabledState[dataIndex] = ( enabled == true )
end

----------------------------------------------------------------
-- Population callback (mirrors ChatFiltersWindow.UpdateChatOptionRow).
-- Called by the engine whenever visible rows need updating.
----------------------------------------------------------------

function M.PopulateRow()
    local list = CustomUIMiniSettingsWindowList
    if list == nil or list.PopulatorIndices == nil then
        return
    end

    for rowIndex, dataIndex in ipairs( list.PopulatorIndices ) do
        local checkBox = "CustomUIMiniSettingsWindowListRow" .. rowIndex .. "CheckBox"
        local enabled  = M.componentEnabledState[dataIndex]
        ButtonSetPressedFlag( checkBox, enabled or false )
    end
end
