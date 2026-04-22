----------------------------------------------------------------
-- CustomUI.MiniSettingsWindow - View
-- Data management and row population for the ListBox.
-- Mirrors the ChatFiltersWindow data/population pattern.
----------------------------------------------------------------

-- Simple one-dot global so the XML <ListData table="MiniSettingsData.rowListData"> can find it.
-- (The WAR engine's ListData parser only supports a single dot.)
MiniSettingsData = MiniSettingsData or {}
MiniSettingsData.rowListData           = {}
MiniSettingsData.componentNames        = {}
MiniSettingsData.componentEnabledState = {}

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
    MiniSettingsData.rowListData           = {}
    MiniSettingsData.componentNames        = {}
    MiniSettingsData.componentEnabledState = {}

    local rowIndex = 0

    for _, componentName in ipairs( CustomUI.ComponentOrder ) do
        rowIndex = rowIndex + 1
        MiniSettingsData.rowListData[rowIndex]           = { componentName = towstring( componentName ) }
        MiniSettingsData.componentNames[rowIndex]        = componentName
        MiniSettingsData.componentEnabledState[rowIndex] = CustomUI.IsComponentEnabled( componentName )
    end

    -- Build sequential display order and push to ListBox, which triggers PopulateRow.
    local order = {}
    for i = 1, #MiniSettingsData.rowListData do
        order[i] = i
    end
    ListBoxSetDisplayOrder( "CustomUIMiniSettingsWindowList", order )
end

----------------------------------------------------------------
-- State accessors (used by Controller to avoid direct MiniSettingsData access)
----------------------------------------------------------------

function CustomUI.MiniSettingsWindow.ToggleState( dataIndex )
    MiniSettingsData.componentEnabledState[dataIndex] = not MiniSettingsData.componentEnabledState[dataIndex]
    return MiniSettingsData.componentEnabledState[dataIndex]
end

function CustomUI.MiniSettingsWindow.GetPendingChanges()
    local changes = {}
    for i, componentName in ipairs( MiniSettingsData.componentNames ) do
        changes[i] = { name = componentName, enabled = MiniSettingsData.componentEnabledState[i] }
    end
    return changes
end

function CustomUI.MiniSettingsWindow.GetComponentName( dataIndex )
    return MiniSettingsData.componentNames[dataIndex]
end

function CustomUI.MiniSettingsWindow.SetState( dataIndex, enabled )
    MiniSettingsData.componentEnabledState[dataIndex] = ( enabled == true )
end

----------------------------------------------------------------
-- Population callback (mirrors ChatFiltersWindow.UpdateChatOptionRow).
-- Called by the engine whenever visible rows need updating.
----------------------------------------------------------------

function MiniSettingsData.PopulateRow()
    local list = CustomUIMiniSettingsWindowList
    if list == nil or list.PopulatorIndices == nil then
        return
    end

    for rowIndex, dataIndex in ipairs( list.PopulatorIndices ) do
        local checkBox = "CustomUIMiniSettingsWindowListRow" .. rowIndex .. "CheckBox"
        local enabled  = MiniSettingsData.componentEnabledState[dataIndex]
        ButtonSetPressedFlag( checkBox, enabled or false )
    end
end
