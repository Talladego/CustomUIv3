----------------------------------------------------------------
-- CustomUISettingsWindowTabbed
-- Footer buttons match stock EA SettingsWindowTabbed:
--   Okay   = Apply all tabs, then close
--   Apply  = commit all tabs from widgets (and seal SCT live edits), stay open
--   Reset  = discard unapplied UI changes back to last-applied baseline (NOT factory defaults)
--   Cancel = Reset, then close
-- Pending edits for most tabs live in widgets until Apply/Okay.
-- SCT still writes live for preview; Cancel/Reset restore a settings baseline captured on open/Apply.
----------------------------------------------------------------

CustomUISettingsWindowTabbed = {}

CustomUISettingsWindowTabbed.TABS_PLAYER	    = 1
CustomUISettingsWindowTabbed.TABS_TARGET	        = 2
CustomUISettingsWindowTabbed.TABS_TARGETHUD		    = 3
CustomUISettingsWindowTabbed.TABS_GROUP		    = 4
CustomUISettingsWindowTabbed.TABS_UNITFRAMES	= 5
CustomUISettingsWindowTabbed.TABS_GROUPICONS	    = 6
CustomUISettingsWindowTabbed.TABS_SCT		= 7
CustomUISettingsWindowTabbed.TABS_KILLTRACKER	= 8
CustomUISettingsWindowTabbed.TABS_MAX_NUMBER	= 8

local c_SCT_COLOR_PICKER_DEFAULT_BUTTON = "CustomUISettingsWindowTabbedSctColorPickerHostSctColorPickerDefaultButton"

-- Deep copy of CustomUI.Settings at last Apply / window open (stock "last applied" baseline).
local m_settingsBaseline = nil

local function SctSetDefaultColorButtonCaption()
    ButtonSetText( c_SCT_COLOR_PICKER_DEFAULT_BUTTON, L"Default" )
end

local function DeepCopy(value)
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for k, v in pairs(value) do
        copy[k] = DeepCopy(v)
    end
    return copy
end

local function ReplaceTableContents(dst, src)
    if type(dst) ~= "table" or type(src) ~= "table" then
        return
    end
    for k in pairs(dst) do
        dst[k] = nil
    end
    for k, v in pairs(src) do
        if type(v) == "table" then
            dst[k] = DeepCopy(v)
        else
            dst[k] = v
        end
    end
end

local function CaptureSettingsBaseline()
    if type(CustomUI) ~= "table" or type(CustomUI.Settings) ~= "table" then
        m_settingsBaseline = nil
        return
    end
    m_settingsBaseline = DeepCopy(CustomUI.Settings)
end

local function ReapplyComponentsFromSettings()
    if type(CustomUI) ~= "table" then
        return
    end

    if type(CustomUI.ComponentOrder) == "table" and type(CustomUI.SetComponentEnabled) == "function" then
        local comps = (CustomUI.Settings and CustomUI.Settings.Components) or {}
        for _, name in ipairs(CustomUI.ComponentOrder) do
            local want = comps[name] == true
            if CustomUI.IsComponentEnabled(name) ~= want then
                CustomUI.SetComponentEnabled(name, want)
            end
        end
    end

    if CustomUI.PlayerStatusWindow and type(CustomUI.PlayerStatusWindow.ApplyBuffSettings) == "function" then
        CustomUI.PlayerStatusWindow.ApplyBuffSettings()
    end
    if CustomUI.TargetWindow and type(CustomUI.TargetWindow.ApplyBuffSettings) == "function" then
        CustomUI.TargetWindow.ApplyBuffSettings()
    end
    if CustomUI.TargetHUD and type(CustomUI.TargetHUD.ApplyBuffSettings) == "function" then
        CustomUI.TargetHUD.ApplyBuffSettings()
    end
    if CustomUI.GroupWindow and type(CustomUI.GroupWindow.ApplyBuffSettings) == "function" then
        CustomUI.GroupWindow.ApplyBuffSettings()
    end
    if CustomUI.UnitFrames and type(CustomUI.UnitFrames.OnGroupsSettingsChanged) == "function" then
        CustomUI.UnitFrames.OnGroupsSettingsChanged()
    end
    if CustomUI.GroupIcons and type(CustomUI.GroupIcons.OnSettingsChanged) == "function" then
        CustomUI.GroupIcons.OnSettingsChanged()
    end
    if CustomUI.KillTracker and type(CustomUI.KillTracker.OnSettingsChanged) == "function" then
        CustomUI.KillTracker.OnSettingsChanged()
    end
    -- SCT reads CustomUI.Settings.SCT; force a settings-changed refresh if available.
    if CustomUI.SCT then
        if type(CustomUI.SCT.NotifySettingsChanged) == "function" then
            CustomUI.SCT.NotifySettingsChanged()
        elseif type(CustomUI.SCT.OnSettingsChanged) == "function" then
            CustomUI.SCT.OnSettingsChanged()
        end
    end
end

local function RestoreSettingsBaseline()
    if type(CustomUI) ~= "table" or type(CustomUI.Settings) ~= "table" or type(m_settingsBaseline) ~= "table" then
        return false
    end
    ReplaceTableContents(CustomUI.Settings, m_settingsBaseline)
    ReapplyComponentsFromSettings()
    return true
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
CustomUISettingsWindowTabbed.Tabs[ CustomUISettingsWindowTabbed.TABS_KILLTRACKER ] = { window = "SWTabKillTracker", name="CustomUISettingsWindowTabbedTabButtonsKillTracker", label=L"Kills", tabClass=CustomUISettingsWindowTabKillTracker }


function CustomUISettingsWindowTabbed.OnShow()
    WindowUtils.OnShown()
    SctSetDefaultColorButtonCaption()
    CustomUISettingsWindowTabbed.UpdateSettings()
    -- Baseline = last applied / currently live settings (stock Cancel/Reset target).
    CaptureSettingsBaseline()
end

function CustomUISettingsWindowTabbed.Initialize()

    if CustomUI and type(CustomUI.ShowSettings) ~= "function" then
        CustomUI.ShowSettings = function()
            WindowUtils.ToggleShowing("CustomUISettingsWindowTabbed")
        end
    end

    LabelSetText( "CustomUISettingsWindowTabbedTitleBarText", L"CustomUI Settings" )
    
    CustomUISettingsWindowTabbed.SetTabLabels()
    
    ButtonSetText( "CustomUISettingsWindowTabbedOkayButton", GetString( StringTables.Default.LABEL_OKAY ) )
    ButtonSetText( "CustomUISettingsWindowTabbedApplyButton", GetString( StringTables.Default.LABEL_APPLY ) )
    ButtonSetText( "CustomUISettingsWindowTabbedResetButton", GetString( StringTables.Default.LABEL_RESET ) )
    ButtonSetText( "CustomUISettingsWindowTabbedCancelButton", GetString( StringTables.Default.LABEL_CANCEL ) )
    SctSetDefaultColorButtonCaption()
    
    CustomUISettingsWindowTabbed.SelectTab(CustomUISettingsWindowTabbed.SelectedTab)

    CustomUISettingsWindowTabbed.UpdateSettings()
    CaptureSettingsBaseline()
end

function CustomUISettingsWindowTabbed.SetTabLabels()
    for index, TabData in ipairs(CustomUISettingsWindowTabbed.Tabs) 
    do
		ButtonSetText(TabData.name, TabData.label )
    end
end

function CustomUISettingsWindowTabbed.UpdateSettings()
    for index, TabIndex in ipairs(CustomUISettingsWindowTabbed.Tabs) 
    do
        if TabIndex.tabClass ~= nil then
            TabIndex.tabClass.UpdateSettings()
        end
    end
end

-- Stock: Cancel = Reset, then close.
function CustomUISettingsWindowTabbed.OnCancelButton()
    CustomUISettingsWindowTabbed.OnResetButton()
    WindowSetShowing( "CustomUISettingsWindowTabbed", false )
end

-- Stock: Reset discards unapplied widget/live-preview changes back to last-applied settings
-- (NOT factory defaults). SCT tab factory reset is intentionally not invoked here.
function CustomUISettingsWindowTabbed.OnResetButton()
    RestoreSettingsBaseline()
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

function CustomUISettingsWindowTabbed.OnLButtonUpTab()
    CustomUISettingsWindowTabbed.SelectTab(WindowGetId (SystemData.ActiveWindow.name))
end

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
    for index, TabIndex in ipairs(CustomUISettingsWindowTabbed.Tabs) do
        if TabIndex.tabClass ~= nil then
            TabIndex.tabClass.ApplyCurrent()
        end
    end
    -- Seal current live settings as the new Cancel/Reset baseline (includes SCT live edits).
    CaptureSettingsBaseline()
    BroadcastEvent( SystemData.Events.USER_SETTINGS_CHANGED )
end

function CustomUISettingsWindowTabbed.OnOkayButton()
    CustomUISettingsWindowTabbed.OnApplyButton()
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
