----------------------------------------------------------------
-- CustomUI.MacroWindow — larger movable Macros editor with paged icons + Delete.
-- Replaces stock EA_Window_Macro while enabled (hide stock + hook main-menu Macros).
-- Disable bigger_macrowindow / standalone MacroIcons when using this component.
----------------------------------------------------------------

CustomUI.MacroWindow = CustomUI.MacroWindow or {}

local MacroWindow = CustomUI.MacroWindow

----------------------------------------------------------------
-- Constants / window names
----------------------------------------------------------------

local c_WINDOW_NAME = "CustomUIMacroWindow"
local c_PICKER_NAME = "CustomUIMacroIconSelectionWindow"
local c_ICONS_SCROLLBAR = "CustomUIMacroIconsScrollBar"
local c_STOCK_WINDOW_NAME = "EA_Window_Macro"
local c_PICKER_SCROLLBAR = "CustomUIMacroPickerIconsScrollbar"
local c_PICKER_SCROLL_CHILD = "CustomUIMacroPickerIconsScrollChild"

MacroWindow.NUM_MACROS = 48
MacroWindow.NUM_MACRO_ICONS = 36
MacroWindow.MACRO_ICONS_ID_BASE = 200
MacroWindow.activeId = 1
MacroWindow.iconNum = 0

local MAX_ICON = 25000
local STEP = MacroWindow.NUM_MACRO_ICONS

local m_enabled = false
local m_windowReady = false
local m_stockReplaceTracked = {}
local m_menuHooked = false
local m_stockOnOpenMacros = nil
local m_stockToggleMacroWindow = nil
local m_pageIndex = 0 -- 0-based page into dense valid-icon list
local m_pageSlotIds = {} -- [slot] = iconId for current page (nil = empty)
local m_validIconIds = nil -- dense list of defined icon IDs (built once)
local m_scrollReset = false
local m_wheelHandlersRegistered = false

local math_floor = math.floor
local math_max = math.max
local math_min = math.min

-- GetIconData returns this texture for undefined IDs ("NO ICON DEF" placeholder).
local c_UNDEFINED_ICON_TEX = "icon-00001"

----------------------------------------------------------------
-- Helpers
----------------------------------------------------------------

local function ChatPrint(msg)
    if type(EA_ChatWindow) == "table" and type(EA_ChatWindow.Print) == "function" then
        EA_ChatWindow.Print(msg, SystemData.ChatLogFilters.MISC)
        return
    end
    if type(TextLogAddEntry) == "function" then
        TextLogAddEntry("Chat", 0, msg)
    end
end

local function SlotIconWindow(slot)
    return c_WINDOW_NAME .. "IconSlot" .. slot .. "IconBase"
end

local function PickerSlotIconWindow(slot)
    return c_PICKER_NAME .. "IconSlot" .. slot .. "IconBase"
end

local function IsSlotEmpty(macro)
    if type(macro) ~= "table" then
        return true
    end
    local text = macro.text
    local name = macro.name
    local icon = tonumber(macro.iconNum) or 0
    local textEmpty = text == nil or text == L"" or text == ""
    local nameEmpty = name == nil or name == L"" or name == ""
    return textEmpty and (nameEmpty or icon == 0)
end

local function ConfirmThen(message, onYes)
    if type(DialogManager) == "table" and type(DialogManager.MakeTwoButtonDialog) == "function" then
        local yes = GetString(StringTables.Default.LABEL_YES)
        local no = GetString(StringTables.Default.LABEL_NO)
        DialogManager.MakeTwoButtonDialog(message, yes, onYes, no, nil)
        return
    end
    onYes()
end

----------------------------------------------------------------
-- Icon paging — dense list of defined IDs (skip "NO ICON DEF")
----------------------------------------------------------------

local function IsDefinedIconTexture(tex)
    if tex == nil or tex == "" or tex == c_UNDEFINED_ICON_TEX then
        return false
    end
    if type(tex) == "wstring" then
        return tex ~= L"icon-00001" and tex ~= L""
    end
    return true
end

local function IsDefinedIconId(iconId)
    iconId = tonumber(iconId)
    if not iconId or iconId <= 0 then
        return false
    end
    local tex = GetIconData(iconId)
    return IsDefinedIconTexture(tex)
end

--- One-time scan of the icon ID range. Undefined IDs return texture icon-00001.
local function EnsureValidIconCache()
    if type(m_validIconIds) == "table" then
        return m_validIconIds
    end

    local list = {}
    local first = MacroWindow.MACRO_ICONS_ID_BASE + 1
    for id = first, MAX_ICON do
        if IsDefinedIconId(id) then
            list[#list + 1] = id
        end
    end
    m_validIconIds = list
    return list
end

local function GetLastPageIndex()
    local list = EnsureValidIconCache()
    local n = #list
    if n <= 0 then
        return 0
    end
    return math_max(0, math_floor((n - 1) / STEP))
end

local function ClampPageIndex(page)
    page = tonumber(page) or 0
    return math_max(0, math_min(GetLastPageIndex(), math_floor(page)))
end

local function RefreshPickerIcons()
    local list = EnsureValidIconCache()
    m_pageIndex = ClampPageIndex(m_pageIndex)

    local start = (m_pageIndex * STEP) + 1
    for slot = 1, MacroWindow.NUM_MACRO_ICONS do
        local iconId = list[start + slot - 1]
        m_pageSlotIds[slot] = iconId
        local slotWin = c_PICKER_NAME .. "IconSlot" .. slot
        if iconId then
            local tex, x, y = GetIconData(iconId)
            DynamicImageSetTexture(PickerSlotIconWindow(slot), tex, x, y)
            if DoesWindowExist(slotWin) then
                WindowSetShowing(slotWin, true)
            end
        else
            DynamicImageSetTexture(PickerSlotIconWindow(slot), c_UNDEFINED_ICON_TEX, 0, 0)
            if DoesWindowExist(slotWin) then
                WindowSetShowing(slotWin, false)
            end
        end
    end

    if DoesWindowExist(c_ICONS_SCROLLBAR) then
        m_scrollReset = true
        VerticalScrollbarSetScrollPosition(c_ICONS_SCROLLBAR, m_pageIndex)
        m_scrollReset = false
    end
end

function MacroWindow.IconScrollPos()
    if m_scrollReset then
        return
    end
    if not DoesWindowExist(c_ICONS_SCROLLBAR) then
        return
    end

    local page = ClampPageIndex(VerticalScrollbarGetScrollPosition(c_ICONS_SCROLLBAR))
    if page == m_pageIndex then
        return
    end
    m_pageIndex = page
    RefreshPickerIcons()
end

function MacroWindow.IconMouseWheel(x, y, delta, flags)
    if delta == nil then
        -- Some clients pass (delta, flags) only.
        delta = x
    end
    delta = tonumber(delta) or 0
    if delta > 0 then
        m_pageIndex = ClampPageIndex(m_pageIndex - 1)
    elseif delta < 0 then
        m_pageIndex = ClampPageIndex(m_pageIndex + 1)
    else
        return
    end
    RefreshPickerIcons()
end

local function SetupIconPagingChrome()
    EnsureValidIconCache()
    local lastPage = GetLastPageIndex()
    if DoesWindowExist(c_ICONS_SCROLLBAR) then
        VerticalScrollbarSetMaxScrollPosition(c_ICONS_SCROLLBAR, lastPage)
        VerticalScrollbarSetScrollPosition(c_ICONS_SCROLLBAR, ClampPageIndex(m_pageIndex))
        WindowSetShowing(c_ICONS_SCROLLBAR, true)
    end

    -- Hide the ScrollWindow's content scrollbar; paging uses CustomUIMacroIconsScrollBar.
    if DoesWindowExist(c_PICKER_SCROLLBAR) then
        WindowSetShowing(c_PICKER_SCROLLBAR, false)
    end
end

local function RegisterWheelHandlers()
    if m_wheelHandlersRegistered then
        return
    end
    -- XML also wires OnMouseWheel; CoreEventHandler covers scroll-child / late-created slots.
    if type(WindowRegisterCoreEventHandler) == "function" then
        WindowRegisterCoreEventHandler(c_PICKER_NAME, "OnMouseWheel", "CustomUI.MacroWindow.IconMouseWheel")
        if DoesWindowExist(c_PICKER_SCROLL_CHILD) then
            WindowRegisterCoreEventHandler(c_PICKER_SCROLL_CHILD, "OnMouseWheel", "CustomUI.MacroWindow.IconMouseWheel")
        end
        if DoesWindowExist(c_ICONS_SCROLLBAR) then
            WindowRegisterCoreEventHandler(c_ICONS_SCROLLBAR, "OnMouseWheel", "CustomUI.MacroWindow.IconMouseWheel")
        end
        for k = 1, MacroWindow.NUM_MACRO_ICONS do
            WindowRegisterCoreEventHandler(
                c_PICKER_NAME .. "IconSlot" .. k,
                "OnMouseWheel",
                "CustomUI.MacroWindow.IconMouseWheel"
            )
        end
    end
    m_wheelHandlersRegistered = true
end

----------------------------------------------------------------
-- Macro UI
----------------------------------------------------------------

function MacroWindow.UpdateMacros()
    if not DoesWindowExist(c_WINDOW_NAME) then
        return
    end
    local macros = DataUtils.GetMacros()
    if type(macros) ~= "table" then
        return
    end
    for slot = 1, MacroWindow.NUM_MACROS do
        local macro = macros[slot]
        local iconNum = (macro and macro.iconNum) or 0
        local tex, x, y = GetIconData(iconNum)
        DynamicImageSetTexture(SlotIconWindow(slot), tex, x, y)
    end
end

function MacroWindow.UpdateDetails(slot)
    local macros = DataUtils.GetMacros()
    if type(macros) ~= "table" or type(macros[slot]) ~= "table" then
        return
    end
    local macro = macros[slot]

    MacroWindow.activeId = slot
    MacroWindow.iconNum = macro.iconNum or 0

    TextEditBoxSetText(c_WINDOW_NAME .. "DetailsName", macro.name or L"")
    TextEditBoxSetText(c_WINDOW_NAME .. "DetailsText", macro.text or L"")

    local tex, x, y = GetIconData(MacroWindow.iconNum)
    DynamicImageSetTexture(c_WINDOW_NAME .. "DetailsIconIconBase", tex, x, y)

    for index = 1, MacroWindow.NUM_MACROS do
        ButtonSetPressedFlag(c_WINDOW_NAME .. "IconSlot" .. index, index == slot)
    end
end

function MacroWindow.OnMacroUpdated(macroId)
    macroId = tonumber(macroId)
    if not macroId then
        return
    end
    if macroId == MacroWindow.activeId then
        MacroWindow.UpdateDetails(macroId)
    end
    local macros = DataUtils.GetMacros()
    if type(macros) == "table" and type(macros[macroId]) == "table" then
        local tex, x, y = GetIconData(macros[macroId].iconNum or 0)
        DynamicImageSetTexture(SlotIconWindow(macroId), tex, x, y)
    end
end

function MacroWindow.HideIconSelectionWindow()
    if DoesWindowExist(c_PICKER_NAME) and WindowGetShowing(c_PICKER_NAME) then
        WindowSetShowing(c_PICKER_NAME, false)
    end
end

function MacroWindow.Hide()
    if DoesWindowExist(c_WINDOW_NAME) then
        WindowSetShowing(c_WINDOW_NAME, false)
    end
    MacroWindow.HideIconSelectionWindow()
end

function MacroWindow.Toggle()
    if not DoesWindowExist(c_WINDOW_NAME) then
        return
    end
    local showing = WindowGetShowing(c_WINDOW_NAME)
    if showing then
        MacroWindow.Hide()
    else
        WindowSetShowing(c_WINDOW_NAME, true)
        MacroWindow.UpdateMacros()
        MacroWindow.UpdateDetails(MacroWindow.activeId or 1)
    end
end

function MacroWindow.OnShown()
    WindowUtils.OnShown(MacroWindow.Hide, WindowUtils.Cascade.MODE_AUTOMATIC)
end

function MacroWindow.OnHidden()
    WindowUtils.OnHidden()
    MacroWindow.HideIconSelectionWindow()
end

function MacroWindow.OnSave()
    SetMacroData(
        TextEditBoxGetText(c_WINDOW_NAME .. "DetailsName"),
        TextEditBoxGetText(c_WINDOW_NAME .. "DetailsText"),
        MacroWindow.iconNum,
        MacroWindow.activeId
    )
    local tex, x, y = GetIconData(MacroWindow.iconNum)
    DynamicImageSetTexture(SlotIconWindow(MacroWindow.activeId), tex, x, y)
    Sound.Play(Sound.BUTTON_CLICK)
end

local function ClearActiveMacroSlot()
    local slot = MacroWindow.activeId
    SetMacroData(L"", L"", 0, slot)

    -- Force cache refresh if the engine marks macros dirty.
    if type(GameData) == "table" and type(GameData.Macros) == "table" then
        GameData.Macros.macrosDirty = true
    end

    MacroWindow.UpdateMacros()
    MacroWindow.UpdateDetails(slot)

    local macros = DataUtils.GetMacros()
    local macro = macros and macros[slot]
    if not IsSlotEmpty(macro) then
        ChatPrint(L"[CustomUI] Macro delete failed: the client did not clear this slot. Clear the text and Save instead.")
        return
    end

    ChatPrint(L"[CustomUI] Macro slot " .. towstring(slot) .. L" cleared.")
    Sound.Play(Sound.BUTTON_CLICK)
end

function MacroWindow.OnDelete()
    ConfirmThen(L"Clear this macro slot?", ClearActiveMacroSlot)
end

function MacroWindow.DetailIconLButtonDown()
    local showing = WindowGetShowing(c_PICKER_NAME)
    if not showing then
        SetupIconPagingChrome()
        RefreshPickerIcons()
    end
    WindowSetShowing(c_PICKER_NAME, not showing)
end

function MacroWindow.DetailIconLButtonUp()
end

function MacroWindow.DetailIconRButtonDown()
end

function MacroWindow.DetailIconMouseOver()
    local text = GetString(StringTables.Default.TEXT_SELECT_ICON_BUTTON)
    Tooltips.CreateTextOnlyTooltip(SystemData.ActiveWindow.name, text)
    Tooltips.AnchorTooltip(Tooltips.ANCHOR_WINDOW_LEFT)
end

function MacroWindow.IconLButtonUp()
    local slot = WindowGetId(SystemData.ActiveWindow.name)
    if MacroWindow.activeId == slot then
        local macros = DataUtils.GetMacros()
        if type(macros) == "table" and type(macros[slot]) == "table" then
            Cursor.PickUp(Cursor.SOURCE_MACRO, slot, slot, macros[slot].iconNum, false)
        end
    else
        MacroWindow.UpdateDetails(slot)
    end
end

function MacroWindow.IconMouseDrag()
    if Cursor.IconOnCursor() then
        return
    end
    local slot = WindowGetId(SystemData.ActiveWindow.name)
    local macros = DataUtils.GetMacros()
    if type(macros) == "table" and type(macros[slot]) == "table" then
        Cursor.PickUp(Cursor.SOURCE_MACRO, slot, slot, macros[slot].iconNum, false)
    end
    MacroWindow.UpdateDetails(slot)
end

function MacroWindow.IconRButtonDown()
end

function MacroWindow.IconMouseOver()
end

function MacroWindow.SelectionIconLButtonDown()
    local slot = WindowGetId(SystemData.ActiveWindow.name)
    local iconId = m_pageSlotIds[slot]
    if not iconId then
        return
    end
    MacroWindow.iconNum = iconId
    local tex, x, y = GetIconData(MacroWindow.iconNum)
    DynamicImageSetTexture(c_WINDOW_NAME .. "DetailsIconIconBase", tex, x, y)
    MacroWindow.HideIconSelectionWindow()
end

function MacroWindow.SelectionIconLButtonUp()
end

function MacroWindow.SelectionIconRButtonDown()
end

function MacroWindow.SelectionIconMouseOver()
end

----------------------------------------------------------------
-- Window create / stock + menu hooks
----------------------------------------------------------------

function MacroWindow.OnWindowInitialize()
    if m_windowReady then
        return
    end

    LabelSetText(c_WINDOW_NAME .. "TitleBarText", GetString(StringTables.Default.LABEL_MACROS))
    ButtonSetText(c_WINDOW_NAME .. "DetailsSave", GetString(StringTables.Default.LABEL_SAVE))
    if DoesWindowExist(c_WINDOW_NAME .. "DetailsDelete") then
        ButtonSetText(c_WINDOW_NAME .. "DetailsDelete", L"Delete")
    end
    LabelSetText(c_WINDOW_NAME .. "DetailsNameTitle", GetString(StringTables.Default.LABEL_MACROS_NAME))
    LabelSetText(c_WINDOW_NAME .. "DetailsTextTitle", GetString(StringTables.Default.LABEL_MACROS_TEXT))
    if DoesWindowExist(c_PICKER_NAME .. "TitleBarText") then
        LabelSetText(c_PICKER_NAME .. "TitleBarText", GetString(StringTables.Default.LABEL_SELECT_ICON))
    end

    for slot = 1, MacroWindow.NUM_MACRO_ICONS do
        local tex, x, y = GetIconData(MacroWindow.MACRO_ICONS_ID_BASE + slot)
        DynamicImageSetTexture(PickerSlotIconWindow(slot), tex, x, y)
    end

    for slot = 1, MacroWindow.NUM_MACROS do
        ButtonSetCheckButtonFlag(c_WINDOW_NAME .. "IconSlot" .. slot, true)
    end

    WindowRegisterEventHandler(c_WINDOW_NAME, SystemData.Events.MACRO_UPDATED, "CustomUI.MacroWindow.OnMacroUpdated")
    WindowRegisterEventHandler(c_WINDOW_NAME, SystemData.Events.MACROS_LOADED, "CustomUI.MacroWindow.UpdateMacros")

    SetupIconPagingChrome()
    RegisterWheelHandlers()
    RefreshPickerIcons()

    MacroWindow.UpdateMacros()
    MacroWindow.UpdateDetails(1)

    WindowSetShowing(c_WINDOW_NAME, false)
    if DoesWindowExist(c_PICKER_NAME) then
        WindowSetShowing(c_PICKER_NAME, false)
    end

    m_windowReady = true
end

function MacroWindow.Shutdown()
    MacroWindow.HideIconSelectionWindow()
end

local function HideStockMacro()
    if type(CustomUI.HideStockForReplace) == "function" then
        CustomUI.HideStockForReplace(c_STOCK_WINDOW_NAME, m_stockReplaceTracked)
    elseif DoesWindowExist(c_STOCK_WINDOW_NAME) then
        WindowSetShowing(c_STOCK_WINDOW_NAME, false)
    end
end

local function RestoreStockMacro()
    if type(CustomUI.RestoreStockAfterReplace) == "function" then
        CustomUI.RestoreStockAfterReplace(c_STOCK_WINDOW_NAME, m_stockReplaceTracked)
    end
end

local function HookMainMenuMacros()
    if m_menuHooked or type(MainMenuWindow) ~= "table" then
        return
    end
    if type(MainMenuWindow.OnOpenMacros) == "function" then
        m_stockOnOpenMacros = MainMenuWindow.OnOpenMacros
        MainMenuWindow.OnOpenMacros = function()
            if m_enabled then
                MacroWindow.Toggle()
            elseif type(m_stockOnOpenMacros) == "function" then
                m_stockOnOpenMacros()
            end
        end
    end
    if type(MainMenuWindow.ToggleMacroWindow) == "function" then
        m_stockToggleMacroWindow = MainMenuWindow.ToggleMacroWindow
        MainMenuWindow.ToggleMacroWindow = function()
            if m_enabled then
                MacroWindow.Toggle()
            elseif type(m_stockToggleMacroWindow) == "function" then
                m_stockToggleMacroWindow()
            end
        end
    end
    m_menuHooked = true
end

local function UnhookMainMenuMacros()
    if not m_menuHooked or type(MainMenuWindow) ~= "table" then
        return
    end
    if m_stockOnOpenMacros ~= nil then
        MainMenuWindow.OnOpenMacros = m_stockOnOpenMacros
        m_stockOnOpenMacros = nil
    end
    if m_stockToggleMacroWindow ~= nil then
        MainMenuWindow.ToggleMacroWindow = m_stockToggleMacroWindow
        m_stockToggleMacroWindow = nil
    end
    m_menuHooked = false
end

----------------------------------------------------------------
-- Component adapter
----------------------------------------------------------------

local MacroWindowComponent = {
    Name = "MacroWindow",
    WindowName = c_WINDOW_NAME,
    DefaultEnabled = false,
}

function MacroWindowComponent:Initialize()
    if DoesWindowExist(c_WINDOW_NAME) then
        MacroWindow.OnWindowInitialize()
        if type(LayoutEditor) == "table" and type(LayoutEditor.RegisterWindow) == "function" then
            LayoutEditor.RegisterWindow(
                c_WINDOW_NAME,
                L"CustomUI Macros",
                L"CustomUI Macros window",
                false,
                false,
                true,
                nil
            )
            LayoutEditor.UserHide(c_WINDOW_NAME)
        end
    end
    return true
end

function MacroWindowComponent:Enable()
    m_enabled = true
    if DoesWindowExist(c_WINDOW_NAME) and not m_windowReady then
        MacroWindow.OnWindowInitialize()
    end
    HideStockMacro()
    HookMainMenuMacros()
    -- UserShow in LayoutEditor so the player can open it; keep closed until menu toggle.
    if DoesWindowExist(c_WINDOW_NAME) then
        if type(LayoutEditor) == "table" and type(LayoutEditor.UserShow) == "function" then
            LayoutEditor.UserShow(c_WINDOW_NAME)
        end
        WindowSetShowing(c_WINDOW_NAME, false)
    end
    return true
end

function MacroWindowComponent:Disable()
    m_enabled = false
    MacroWindow.Hide()
    UnhookMainMenuMacros()
    RestoreStockMacro()
    if DoesWindowExist(c_WINDOW_NAME) then
        WindowSetShowing(c_WINDOW_NAME, false)
        if type(LayoutEditor) == "table" and type(LayoutEditor.UserHide) == "function" then
            LayoutEditor.UserHide(c_WINDOW_NAME)
        end
    end
    return true
end

function MacroWindowComponent:Shutdown()
    MacroWindowComponent:Disable()
    MacroWindow.Shutdown()
end

function MacroWindowComponent:ResetToDefaults()
    if type(CustomUI.ResetWindowToDefault) == "function" then
        CustomUI.ResetWindowToDefault(c_WINDOW_NAME)
    elseif DoesWindowExist(c_WINDOW_NAME) then
        WindowRestoreDefaultSettings(c_WINDOW_NAME)
    end
    return true
end

CustomUI.RegisterComponent("MacroWindow", MacroWindowComponent)
