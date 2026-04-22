----------------------------------------------------------------
-- CustomUI.SettingsWindow — Tab broker / settings window controller
-- Opens with /cui.  Components call RegisterTab() during their
-- own Initialize() to request a tab.  The window itself is lazy-
-- initialized on first OnShow so all registrations are complete
-- before any buttons are created.
----------------------------------------------------------------

if not CustomUI.SettingsWindow then
    CustomUI.SettingsWindow = {}
end

----------------------------------------------------------------
-- Constants
----------------------------------------------------------------

local c_WINDOW      = "CustomUISettingsWindow"
local c_TAB_BUTTONS = c_WINDOW .. "TabButtons"
local c_SOCKET      = c_WINDOW .. "Socket"

local c_SEP_LEFT   = c_TAB_BUTTONS .. "SeparatorLeft"
local c_SEP_RIGHT  = c_TAB_BUTTONS .. "SeparatorRight"

local c_TAB_TEMPLATE  = "CustomUISettingsWindowTabButton"
local c_TAB_H         = 35
local c_TAB_MAX_W     = 124
local c_TAB_LEFT_PAD  = 25   -- first tab x offset, matches stock



----------------------------------------------------------------
-- Module state
----------------------------------------------------------------

local m_tabs        = {}     -- all registered tab records (including nil-template ones)
local m_activeTabs  = {}     -- tabs with a template — these get buttons and are shown
local m_selectedTab = 0
local m_initialized = false

----------------------------------------------------------------
-- Debug
----------------------------------------------------------------

CustomUI.SettingsWindow.Debug = false

local function Dbg(msg)
    if CustomUI.SettingsWindow.Debug then
        d("[SettingsWindow] " .. tostring(msg))
    end
end

----------------------------------------------------------------
-- Public API
----------------------------------------------------------------

-- Called by components (or CustomUI itself) during Initialize().
-- label        : string shown on the tab button
-- templateName : XML template to instantiate into the socket, or nil
-- component    : component adapter table, or nil
function CustomUI.SettingsWindow.RegisterTab(label, templateName, component, onShownFn)
    if templateName == nil then return end
    -- Guard against double-registration (file loaded twice).
    for _, t in ipairs(m_tabs) do
        if t.label == label then return end
    end
    Dbg("RegisterTab: label=" .. tostring(label) .. " template=" .. tostring(templateName))
    table.insert(m_tabs, {
        label        = label,
        templateName = templateName,
        component    = component,
        onShown      = onShownFn,
        buttonName   = nil,
        contentName  = nil,
    })
end

function CustomUI.SettingsWindow.Open()
    WindowSetShowing(c_WINDOW, true)
end

function CustomUI.SettingsWindow.Close()
    WindowSetShowing(c_WINDOW, false)
end

----------------------------------------------------------------
-- Event handlers
----------------------------------------------------------------

-- OnInitialize fires once when the window is created by the engine.
-- Safe to set static text here — children exist at this point.
function CustomUI.SettingsWindow.OnInitialize()
    Dbg("OnInitialize")
    LabelSetText(c_WINDOW .. "TitleBarText", L"CustomUI Settings")
    ButtonSetText(c_WINDOW .. "ApplyButton",  L"Apply")
    ButtonSetText(c_WINDOW .. "ResetButton",  L"Reset")
    ButtonSetText(c_WINDOW .. "CancelButton", L"Cancel")
end

-- OnShown fires each time the window becomes visible.
-- Tab creation is lazy — deferred until first open so all RegisterTab calls are complete.
function CustomUI.SettingsWindow.OnShown()
    Dbg("OnShown m_initialized=" .. tostring(m_initialized))
    if not m_initialized then
        CustomUI.SettingsWindow.Initialize()
    else
        CustomUI.SettingsWindow.SelectTab(m_selectedTab)
    end
end

function CustomUI.SettingsWindow.Initialize()
    if m_initialized then return end

    Dbg("Initialize: total registered tabs=" .. tostring(#m_tabs))
    for i, tab in ipairs(m_tabs) do
        Dbg("  tab[" .. i .. "] label=" .. tostring(tab.label) .. " template=" .. tostring(tab.templateName))
    end

    m_activeTabs = m_tabs

    Dbg("Initialize: activeTabs=" .. tostring(#m_activeTabs))

    if #m_activeTabs == 0 then
        m_initialized = true
        return
    end

    WindowSetShowing(c_TAB_BUTTONS, true)

    -- Compute tab button width: fit all active tabs in the strip, capped at max.
    local stripW = WindowGetDimensions(c_TAB_BUTTONS)
    local tabW   = math.min(c_TAB_MAX_W, math.floor(stripW / #m_activeTabs))
    Dbg("Initialize: stripW=" .. tostring(stripW) .. " tabW=" .. tostring(tabW))

    local prevBtnName = nil

    for i, tab in ipairs(m_activeTabs) do
        -- Create tab button.
        local btnName = c_WINDOW .. "Tab" .. i
        local btnOk = CreateWindowFromTemplate(btnName, c_TAB_TEMPLATE, c_TAB_BUTTONS)
        Dbg("  CreateButton[" .. i .. "] name=" .. btnName .. " ok=" .. tostring(btnOk))
        WindowSetDimensions(btnName, tabW, c_TAB_H)
        WindowSetId(btnName, i)

        ButtonSetText(btnName, towstring(tab.label))

        -- Anchor: first button at left pad, subsequent chain rightward by placing each
        -- new button's right edge against the previous button's left edge (stock pattern).
        WindowClearAnchors(btnName)
        if prevBtnName == nil then
            WindowAddAnchor(btnName, "topleft", c_TAB_BUTTONS, "topleft", c_TAB_LEFT_PAD, 0)
        else
            WindowAddAnchor(btnName, "right", prevBtnName, "left", 0, 0)
        end

        tab.buttonName = btnName
        prevBtnName = btnName

        -- Create content window.
        local contentName = c_WINDOW .. "Content" .. i
        local contentOk = CreateWindowFromTemplate(contentName, tab.templateName, c_SOCKET)
        Dbg("  CreateContent[" .. i .. "] name=" .. contentName .. " template=" .. tostring(tab.templateName) .. " ok=" .. tostring(contentOk))
        if contentOk then
            WindowClearAnchors(contentName)
            WindowAddAnchor(contentName, "topleft",     c_SOCKET, "topleft",     0, 0)
            WindowAddAnchor(contentName, "bottomright", c_SOCKET, "bottomright", 0, 0)
            WindowSetShowing(contentName, false)
            tab.contentName = contentName
        end
    end

    -- Add second anchor to each cap to stretch them, matching the stock double-anchor pattern.
    -- Tab1 (first created) is rightmost; prevBtnName (last created) is leftmost.
    local rightmostBtn = c_WINDOW .. "Tab1"
    local leftmostBtn  = prevBtnName
    WindowAddAnchor(c_SEP_LEFT,  "bottomleft",  rightmostBtn, "topright", 0, -6)
    WindowAddAnchor(c_SEP_RIGHT, "bottomright", leftmostBtn,  "topleft",  0, -6)

    m_initialized = true

    -- Select first tab.
    CustomUI.SettingsWindow.SelectTab(1)
end

----------------------------------------------------------------
-- Tab selection
----------------------------------------------------------------

function CustomUI.SettingsWindow.SelectTab(index)
    Dbg("SelectTab: index=" .. tostring(index) .. " activeTabs=" .. tostring(#m_activeTabs))
    if index < 1 or index > #m_activeTabs then return end

    m_selectedTab = index

    for i, tab in ipairs(m_activeTabs) do
        local pressed = (i == index)
        if tab.buttonName  and DoesWindowExist(tab.buttonName)  then
            ButtonSetPressedFlag(tab.buttonName, pressed)
        end
        if tab.contentName and DoesWindowExist(tab.contentName) then
            WindowSetShowing(tab.contentName, pressed)
        end
        if pressed and tab.onShown then
            tab.onShown(tab.contentName)
        end
    end
end

function CustomUI.SettingsWindow.OnTabClicked()
    local id = WindowGetId(SystemData.ActiveWindow.name)
    Dbg("OnTabClicked: window=" .. tostring(SystemData.ActiveWindow.name) .. " id=" .. tostring(id))
    CustomUI.SettingsWindow.SelectTab(id)
end

----------------------------------------------------------------
-- Bottom button handlers
----------------------------------------------------------------

function CustomUI.SettingsWindow.OnApply()
    for _, tab in ipairs(m_tabs) do
        if tab.component and tab.component.ApplySettings then
            tab.component:ApplySettings()
        end
    end
end

function CustomUI.SettingsWindow.OnReset()
    for _, tab in ipairs(m_tabs) do
        if tab.component and tab.component.ResetSettings then
            tab.component:ResetSettings()
        end
    end
end

function CustomUI.SettingsWindow.OnCancel()
    for _, tab in ipairs(m_tabs) do
        if tab.component and tab.component.CancelSettings then
            tab.component:CancelSettings()
        end
    end
    CustomUI.SettingsWindow.Close()
end
