
----------------------------------------------------------------
-- Global Variables
----------------------------------------------------------------

CustomUISettingsWindowTabbed = {}

CustomUISettingsWindowTabbed.TABS_PLAYER	    = 1
CustomUISettingsWindowTabbed.TABS_TARGET	        = 2
CustomUISettingsWindowTabbed.TABS_TARGETHUD		    = 3
CustomUISettingsWindowTabbed.TABS_GROUP		    = 4
CustomUISettingsWindowTabbed.TABS_UNITFRAMES	= 5
CustomUISettingsWindowTabbed.TABS_GROUPICONS	    = 6
CustomUISettingsWindowTabbed.TABS_SCT		= 7
CustomUISettingsWindowTabbed.TABS_MAX_NUMBER	= 7

local c_SCT_COLOR_PICKER_DEFAULT_BUTTON = "CustomUISettingsWindowTabbedSctColorPickerHostSctColorPickerDefaultButton"

local function SctSetDefaultColorButtonCaption()
    pcall(function()
        ButtonSetText( c_SCT_COLOR_PICKER_DEFAULT_BUTTON, L"Default" )
    end)
end

CustomUISettingsWindowTabbed.SelectedTab		= CustomUISettingsWindowTabbed.TABS_PLAYER


CustomUISettingsWindowTabbed.Tabs = {} 
CustomUISettingsWindowTabbed.Tabs[ CustomUISettingsWindowTabbed.TABS_PLAYER     ] = { window = "SWTabPlayer",     name="CustomUISettingsWindowTabbedTabButtonsPlayer",     label=L"Player",     tabClass=CustomUISettingsWindowTabPlayer }
CustomUISettingsWindowTabbed.Tabs[ CustomUISettingsWindowTabbed.TABS_TARGET     ] = { window = "SWTabTarget",     name="CustomUISettingsWindowTabbedTabButtonsTarget",     label=L"Target",     tabClass=CustomUISettingsWindowTabTarget }
CustomUISettingsWindowTabbed.Tabs[ CustomUISettingsWindowTabbed.TABS_TARGETHUD  ] = { window = "SWTabTargetHUD",  name="CustomUISettingsWindowTabbedTabButtonsTargetHUD",  label=L"TargetHUD",  tabClass=CustomUISettingsWindowTabTargetHUD }
CustomUISettingsWindowTabbed.Tabs[ CustomUISettingsWindowTabbed.TABS_GROUP      ] = { window = "SWTabGroup",      name="CustomUISettingsWindowTabbedTabButtonsGroup",      label=L"Group",      tabClass=CustomUISettingsWindowTabGroup }
CustomUISettingsWindowTabbed.Tabs[ CustomUISettingsWindowTabbed.TABS_UNITFRAMES ] = { window = "SWTabUnitFrames", name="CustomUISettingsWindowTabbedTabButtonsUnitFrames", label=L"UnitFrames", tabClass=CustomUISettingsWindowTabUnitFrames }
CustomUISettingsWindowTabbed.Tabs[ CustomUISettingsWindowTabbed.TABS_GROUPICONS ] = { window = "SWTabGroupIcons", name="CustomUISettingsWindowTabbedTabButtonsGroupIcons", label=L"GroupIcons", tabClass=CustomUISettingsWindowTabGroupIcons }
CustomUISettingsWindowTabbed.Tabs[ CustomUISettingsWindowTabbed.TABS_SCT        ] = { window = "SWTabSCT",        name="CustomUISettingsWindowTabbedTabButtonsSCT",        label=L"SCT",        tabClass=CustomUISettingsWindowTabSCT }


function CustomUISettingsWindowTabbed.OnShow()
    WindowUtils.OnShown()
    SctSetDefaultColorButtonCaption()
    -- SettingsWindowTabInterface.OnShown()
    CustomUISettingsWindowTabbed.UpdateSettings()
end

-- OnInitialize Handler()
function CustomUISettingsWindowTabbed.Initialize()

    LabelSetText( "CustomUISettingsWindowTabbedTitleBarText", L"CustomUI Settings" )
    
    CustomUISettingsWindowTabbed.SetTabLabels()
    
    --buttons on the bottom
    ButtonSetText( "CustomUISettingsWindowTabbedOkayButton", GetString( StringTables.Default.LABEL_OKAY ) )
    ButtonSetText( "CustomUISettingsWindowTabbedApplyButton", GetString( StringTables.Default.LABEL_APPLY ) )
    ButtonSetText( "CustomUISettingsWindowTabbedResetButton", GetString( StringTables.Default.LABEL_RESET ) )
    ButtonSetText( "CustomUISettingsWindowTabbedCancelButton", GetString( StringTables.Default.LABEL_CANCEL ) )
    SctSetDefaultColorButtonCaption()
    
    --could consider saving off and loading the tab they were looking at like GuildWindow does
    CustomUISettingsWindowTabbed.SelectTab(CustomUISettingsWindowTabbed.SelectedTab)

    CustomUISettingsWindowTabbed.UpdateSettings()
end

-- Initializes all the text on the tab buttons
function CustomUISettingsWindowTabbed.SetTabLabels()
    for index, TabData in ipairs(CustomUISettingsWindowTabbed.Tabs) 
    do
        -- ButtonSetText(TabData.name, GetStringFromTable( "UserSettingsStrings", TabData.label ) )
		ButtonSetText(TabData.name, TabData.label )
    end
end

function CustomUISettingsWindowTabbed.UpdateSettings()

    -- Reload the current settings
    for index, TabIndex in ipairs(CustomUISettingsWindowTabbed.Tabs) 
    do
        if TabIndex.tabClass ~= nil then
            TabIndex.tabClass.UpdateSettings()
        end
    end
end

function CustomUISettingsWindowTabbed.OnCancelButton()
    -- Do not call OnResetButton here: Close (X), Cancel, and Enter use this path. Resetting the
    -- *selected* tab was resetting SCT colors (CustomUISettingsWindowTabSCT.ResetColorsToStockDefault)
    -- whenever the SCT tab was active, which is never what "close" should do. Use the footer Reset
    -- button for tab-scoped defaults.
    WindowSetShowing( "CustomUISettingsWindowTabbed", false )
end

function CustomUISettingsWindowTabbed.OnResetButton()
    local tab = CustomUISettingsWindowTabbed.Tabs[CustomUISettingsWindowTabbed.SelectedTab]
    if tab and tab.tabClass and tab.tabClass.ResetSettings then
        tab.tabClass.ResetSettings()
    end
    CustomUISettingsWindowTabbed.UpdateSettings()
end

function CustomUISettingsWindowTabbed.SelectTab(tabNumber)

    if tabNumber ~= nil and tabNumber >= CustomUISettingsWindowTabbed.TABS_PLAYER and tabNumber <= CustomUISettingsWindowTabbed.TABS_MAX_NUMBER then
        if not ButtonGetDisabledFlag(CustomUISettingsWindowTabbed.Tabs[tabNumber].name) then
            CustomUISettingsWindowTabbed.SelectedTab = tabNumber
            
            for index, TabIndex in ipairs(CustomUISettingsWindowTabbed.Tabs) do
                if (index ~= tabNumber) then
                    ButtonSetPressedFlag( TabIndex.name, false )
                    WindowSetShowing( TabIndex.window, false )
                else
                    ButtonSetPressedFlag( TabIndex.name, true )
                    WindowSetShowing( TabIndex.window, true )
                end
            end
        end

    end
end

-- EventHandler for OnLButtonUp when a user L- clicks a tab
function CustomUISettingsWindowTabbed.OnLButtonUpTab()
    CustomUISettingsWindowTabbed.SelectTab(WindowGetId (SystemData.ActiveWindow.name))
end

-- Same idea as SettingsWindowTabbed.OnMouseOverTab, but tab text is local wstrings (no UserSettingsStrings table).
function CustomUISettingsWindowTabbed.OnMouseOverTab()
    local windowName = SystemData.ActiveWindow.name
    local windowIndex = WindowGetId(windowName)
    local tab = CustomUISettingsWindowTabbed.Tabs[windowIndex]
    if tab == nil then
        return
    end
    local tipText = tab.tooltip or tab.label
    Tooltips.CreateTextOnlyTooltip(windowName, nil)
    Tooltips.SetTooltipText(1, 1, tipText)
    Tooltips.SetTooltipColorDef(1, 1, Tooltips.COLOR_HEADING)
    Tooltips.Finalize()
    local anchor = { Point = "bottom", RelativeTo = windowName, RelativePoint = "top", XOffset = 0, YOffset = 32 }
    Tooltips.AnchorTooltip(anchor)
    Tooltips.SetTooltipAlpha(1)
end

function CustomUISettingsWindowTabbed.OnApplyButton()

    -- Set the Options
    for index, TabIndex in ipairs(CustomUISettingsWindowTabbed.Tabs) do
        if TabIndex.tabClass ~= nil then
            TabIndex.tabClass.ApplyCurrent()
        end
    end
    
    BroadcastEvent( SystemData.Events.USER_SETTINGS_CHANGED )
end

function CustomUISettingsWindowTabbed.OnOkayButton()

    CustomUISettingsWindowTabbed.OnApplyButton()

    -- Close the window     
    WindowSetShowing( "CustomUISettingsWindowTabbed", false )
end

function CustomUISettingsWindowTabbed.DoLoginPerformanceWarning()

    if ( SystemData.Settings.Performance.perfLevelOverridden and 
         SystemData.Settings.ShowWarning[SystemData.Settings.DlgWarning.WARN_PERFORMANCE] )        
    then
        SystemData.Settings.Performance.perfLevelOverridden = false
        DialogManager.MakeOneButtonDialog(GetPregameString(StringTables.Pregame.LABEL_PERFORMANCE_OVERRIDDEN), GetPregameString(StringTables.Pregame.LABEL_OKAY), nil, nil, DialogManager.UNTYPED_ID)
    end

end


