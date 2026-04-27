----------------------------------------------------------------
-- CustomUI.TargetWindow — Controller
-- Responsibilities: RegisterComponent, target events, two TargetFrame instances, and stock
--   show/hide. There is no View/ Lua; CustomUI.TargetFrame and XML templates carry UI.
-- CustomUI.mod loads this file before View/TargetWindow.xml; do not re-<Script> the controller in XML.
-- Combined replacement for stock hostile + friendly target windows (one component toggle).
----------------------------------------------------------------

if not CustomUI.TargetWindow then
    CustomUI.TargetWindow = {}
end

----------------------------------------------------------------
-- Constants
----------------------------------------------------------------

local c_HOSTILE_WINDOW_NAME = "CustomUIHostileTargetWindow"
local c_FRIENDLY_WINDOW_NAME = "CustomUIFriendlyTargetWindow"

local c_HOSTILE_FRAME_NAME = "CustomUIHostileTargetFrame"
local c_FRIENDLY_FRAME_NAME = "CustomUIFriendlyTargetFrame"

local c_HOSTILE_UNIT_ID = "selfhostiletarget"
local c_FRIENDLY_UNIT_ID = "selffriendlytarget"

-- Stock ea_targetwindow layout roots (see interface/default/ea_targetwindow/source/targetwindow.lua)
local c_STOCK_PRIMARY_TARGET_LAYOUT   = "PrimaryTargetLayoutWindow"
local c_STOCK_SECONDARY_TARGET_LAYOUT = "SecondaryTargetLayoutWindow"

local c_MAX_BUFF_SLOTS = 20
local c_BUFF_STRIDE = 5

----------------------------------------------------------------
-- Module state
----------------------------------------------------------------

local m_enabled = false
local m_hostileFrame = nil
local m_friendlyFrame = nil
local m_initialized = false
-- True until both stock target layout windows are registered with LayoutEditor and UserHide has been applied.
local m_stockTargetHidePending = false

----------------------------------------------------------------
-- Local helpers
----------------------------------------------------------------

local function CreateTargetFrame(frameName, unitId, buffTargetType, parentWindowName)
    if not DoesWindowExist(parentWindowName) then
        return nil
    end

    local frame = CustomUI.TargetFrame:Create(
        frameName,
        unitId,
        buffTargetType,
        c_MAX_BUFF_SLOTS,
        c_BUFF_STRIDE)

    if not frame then
        return nil
    end

    frame:SetParent(parentWindowName)

    local scale = WindowGetScale(parentWindowName)
    if scale then
        frame:SetScale(scale)
    end

    frame:SetAnchor({
        Point = "topleft",
        RelativePoint = "topleft",
        RelativeTo = parentWindowName,
        XOffset = 0,
        YOffset = 0,
    })

    frame.m_BuffTracker:SetBuffGroups(CustomUI.BuffTracker.BuffGroups)
    frame.m_BuffTracker:SetSortMode(CustomUI.BuffTracker.SortMode.PERM_LONG_SHORT)

    return frame
end

local function IsLayoutWindowRegistered(windowName)
    return LayoutEditor
        and type(LayoutEditor.windowsList) == "table"
        and LayoutEditor.windowsList[windowName] ~= nil
end

local function SafeLayoutShow(windowName)
    if IsLayoutWindowRegistered(windowName) then
        LayoutEditor.Show(windowName)
    else
        WindowSetShowing(windowName, true)
    end
end

local function SafeLayoutHide(windowName)
    if IsLayoutWindowRegistered(windowName) then
        LayoutEditor.Hide(windowName)
    else
        WindowSetShowing(windowName, false)
    end
end

local function SafeUserShow(windowName)
    if IsLayoutWindowRegistered(windowName) then
        LayoutEditor.UserShow(windowName)
    else
        WindowSetShowing(windowName, true)
    end
end

local function SafeUserHide(windowName)
    if IsLayoutWindowRegistered(windowName) then
        LayoutEditor.UserHide(windowName)
    else
        WindowSetShowing(windowName, false)
    end
end

local function RefreshWindowVisibility()
    -- WindowGetShowing reads the window's own flag without inheriting parent
    -- visibility, so it correctly reflects whether the sub-frame has a target
    -- even when the container window is currently hidden.
    local hostileVisible = m_enabled and m_hostileFrame
        and WindowGetShowing(m_hostileFrame:GetName())
    local friendlyVisible = m_enabled and m_friendlyFrame
        and WindowGetShowing(m_friendlyFrame:GetName())

    if hostileVisible then
        SafeLayoutShow(c_HOSTILE_WINDOW_NAME)
    else
        SafeLayoutHide(c_HOSTILE_WINDOW_NAME)
    end

    if friendlyVisible then
        SafeLayoutShow(c_FRIENDLY_WINDOW_NAME)
    else
        SafeLayoutHide(c_FRIENDLY_WINDOW_NAME)
    end
end

-- Count CustomUI target frames currently visible (mirrors stock TargetWindow.NumberOfTargetWindowsShowing intent).
local function CountShowingTargetFrames()
    local n = 0
    if m_hostileFrame and WindowGetShowing(m_hostileFrame:GetName()) then
        n = n + 1
    end
    if m_friendlyFrame and WindowGetShowing(m_friendlyFrame:GetName()) then
        n = n + 1
    end
    return n
end

local function TryHideStockTargetWindows()
    if not m_enabled then
        m_stockTargetHidePending = false
        return
    end

    if type(LayoutEditor) ~= "table" or type(LayoutEditor.windowsList) ~= "table" then
        m_stockTargetHidePending = true
        return
    end

    local havePrimary   = LayoutEditor.windowsList[c_STOCK_PRIMARY_TARGET_LAYOUT] ~= nil
    local haveSecondary = LayoutEditor.windowsList[c_STOCK_SECONDARY_TARGET_LAYOUT] ~= nil

    if havePrimary then
        LayoutEditor.UserHide(c_STOCK_PRIMARY_TARGET_LAYOUT)
    end
    if haveSecondary then
        LayoutEditor.UserHide(c_STOCK_SECONDARY_TARGET_LAYOUT)
    end

    -- Retry after reload / load-order races until stock TargetWindow.Initialize() has registered both.
    m_stockTargetHidePending = not (havePrimary and haveSecondary)
end

local function ShowStockTargetWindows()
    m_stockTargetHidePending = false

    if type(LayoutEditor) ~= "table" or type(LayoutEditor.windowsList) ~= "table" then
        return
    end

    if LayoutEditor.windowsList[c_STOCK_PRIMARY_TARGET_LAYOUT] then
        LayoutEditor.UserShow(c_STOCK_PRIMARY_TARGET_LAYOUT)
    end
    if LayoutEditor.windowsList[c_STOCK_SECONDARY_TARGET_LAYOUT] then
        LayoutEditor.UserShow(c_STOCK_SECONDARY_TARGET_LAYOUT)
    end
end

-- Must call TargetInfo:UpdateFromClient() at most once per PLAYER_TARGET_UPDATED — GetUpdatedTargets()
-- is consumed until the next event (see easystem_targetinfo/targetinfo.lua). Stock ea_targetwindow
-- uses a single handler; two handlers each calling UpdateFromClient breaks the other slot after reload.
local function RefreshBothTargetsFromClient(targetClassification)
    if targetClassification ~= nil
        and targetClassification ~= c_HOSTILE_UNIT_ID
        and targetClassification ~= c_FRIENDLY_UNIT_ID
    then
        return
    end

    if not m_hostileFrame or not m_friendlyFrame then
        return
    end

    local oldNumberOfTargets = CountShowingTargetFrames()

    local oldHostileEntityId = TargetInfo:UnitEntityId(c_HOSTILE_UNIT_ID)
    local oldFriendlyEntityId = TargetInfo:UnitEntityId(c_FRIENDLY_UNIT_ID)

    TargetInfo:UpdateFromClient()

    m_hostileFrame:UpdateUnit()
    m_friendlyFrame:UpdateUnit()

    local targetHasChanged = false

    if TargetInfo:UnitEntityId(c_HOSTILE_UNIT_ID) ~= oldHostileEntityId then
        m_hostileFrame:StopInterpolatingStatus()
        m_hostileFrame.m_BuffTracker:Refresh()
        targetHasChanged = true
    end
    if TargetInfo:UnitEntityId(c_FRIENDLY_UNIT_ID) ~= oldFriendlyEntityId then
        m_friendlyFrame:StopInterpolatingStatus()
        m_friendlyFrame.m_BuffTracker:Refresh()
        targetHasChanged = true
    end

    RefreshWindowVisibility()

    if m_enabled then
        TryHideStockTargetWindows()
    end

    if targetHasChanged then
        local newNumberOfTargets = CountShowingTargetFrames()
        if newNumberOfTargets < oldNumberOfTargets then
            Sound.Play(Sound.TARGET_DESELECT)
        else
            Sound.Play(Sound.TARGET_SELECT)
        end
    end
end

-- Re-bind unit frames to whatever TargetInfo already holds (e.g. after Disable left stock UI
-- updating TargetInfo, or on Enable with no new PLAYER_TARGET_UPDATED). Do NOT call
-- TargetInfo:UpdateFromClient() here: without a pending batch, GetUpdatedTargets() is nil and
-- TargetInfo:ClearUnits() wipes current targets (easystem_targetinfo/targetinfo.lua).
local function ApplyTargetsFromCachedTargetInfo()
    if not m_hostileFrame or not m_friendlyFrame then
        return
    end

    m_hostileFrame:UpdateUnit()
    m_friendlyFrame:UpdateUnit()

    m_hostileFrame.m_BuffTracker:Refresh()
    m_friendlyFrame.m_BuffTracker:Refresh()

    RefreshWindowVisibility()

    if m_enabled then
        TryHideStockTargetWindows()
    end
end

----------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------

function CustomUI.TargetWindow.Initialize()
    if m_initialized then
        return
    end

    -- Windows are declared in CustomUI.mod so the engine restores their saved positions.
    -- CreateWindowFromTemplate is only needed if they somehow don't exist yet, and in
    -- that case we also set default anchors so they appear in a sensible place first time.
    if not DoesWindowExist(c_HOSTILE_WINDOW_NAME) then
        CreateWindowFromTemplate(c_HOSTILE_WINDOW_NAME,  "CustomUITargetWindowTemplate", "Root")
        WindowClearAnchors(c_HOSTILE_WINDOW_NAME)
        WindowAddAnchor(c_HOSTILE_WINDOW_NAME, "topright", "CustomUIPlayerStatusWindow", "topleft", 0, 0)
    end
    if not DoesWindowExist(c_FRIENDLY_WINDOW_NAME) then
        CreateWindowFromTemplate(c_FRIENDLY_WINDOW_NAME, "CustomUITargetWindowTemplate", "Root")
        WindowClearAnchors(c_FRIENDLY_WINDOW_NAME)
        WindowAddAnchor(c_FRIENDLY_WINDOW_NAME, "bottomleft", c_HOSTILE_WINDOW_NAME, "topleft", 0, 0)
    end


    if not IsLayoutWindowRegistered(c_HOSTILE_WINDOW_NAME) then
        LayoutEditor.RegisterWindow(
            c_HOSTILE_WINDOW_NAME,
            L"CustomUI: Hostile Target",
            L"Replacement hostile target window with buff tracking.",
            false,
            false,
            true,
            nil)
    end

    if not IsLayoutWindowRegistered(c_FRIENDLY_WINDOW_NAME) then
        LayoutEditor.RegisterWindow(
            c_FRIENDLY_WINDOW_NAME,
            L"CustomUI: Friendly Target",
            L"Replacement friendly target window with buff tracking.",
            false,
            false,
            true,
            nil)
    end

    SafeUserHide(c_HOSTILE_WINDOW_NAME)
    SafeUserHide(c_FRIENDLY_WINDOW_NAME)

    if not m_hostileFrame then
        m_hostileFrame = CreateTargetFrame(
            c_HOSTILE_FRAME_NAME,
            c_HOSTILE_UNIT_ID,
            GameData.BuffTargetType.TARGET_HOSTILE,
            c_HOSTILE_WINDOW_NAME)
    end

    if not m_friendlyFrame then
        m_friendlyFrame = CreateTargetFrame(
            c_FRIENDLY_FRAME_NAME,
            c_FRIENDLY_UNIT_ID,
            GameData.BuffTargetType.TARGET_FRIENDLY,
            c_FRIENDLY_WINDOW_NAME)
    end

    if not m_hostileFrame or not m_friendlyFrame then
        if m_hostileFrame then
            m_hostileFrame.m_BuffTracker:Shutdown()
            m_hostileFrame:Destroy()
            m_hostileFrame = nil
        end
        if m_friendlyFrame then
            m_friendlyFrame.m_BuffTracker:Shutdown()
            m_friendlyFrame:Destroy()
            m_friendlyFrame = nil
        end
        return
    end

    -- Single handler: UpdateFromClient() must run once per event (see RefreshBothTargetsFromClient).
    WindowRegisterEventHandler(c_HOSTILE_WINDOW_NAME, SystemData.Events.PLAYER_TARGET_UPDATED, "CustomUI.TargetWindow.OnPlayerTargetUpdated")
    WindowRegisterEventHandler(c_HOSTILE_WINDOW_NAME, SystemData.Events.PLAYER_TARGET_EFFECTS_UPDATED, "CustomUI.TargetWindow.OnHostileEffectsUpdated")
    WindowRegisterEventHandler(c_FRIENDLY_WINDOW_NAME, SystemData.Events.PLAYER_TARGET_EFFECTS_UPDATED, "CustomUI.TargetWindow.OnFriendlyEffectsUpdated")
    WindowRegisterEventHandler(c_HOSTILE_WINDOW_NAME, SystemData.Events.PLAYER_COMBAT_FLAG_UPDATED, "CustomUI.TargetWindow.OnCombatFlagUpdated")

    m_initialized = true

    ApplyTargetsFromCachedTargetInfo()
end

function CustomUI.TargetWindow.Shutdown()
    if m_hostileFrame then
        m_hostileFrame.m_BuffTracker:Shutdown()
        m_hostileFrame:Destroy()
        m_hostileFrame = nil
    end

    if m_friendlyFrame then
        m_friendlyFrame.m_BuffTracker:Shutdown()
        m_friendlyFrame:Destroy()
        m_friendlyFrame = nil
    end

    m_initialized = false
end

----------------------------------------------------------------
-- Event Handlers
----------------------------------------------------------------

function CustomUI.TargetWindow.OnShutdown()
    if SystemData.ActiveWindow.name == c_HOSTILE_WINDOW_NAME then
        CustomUI.TargetWindow.Shutdown()
    end
end

function CustomUI.TargetWindow.OnUpdate(timePassed)
    -- Stock windows may register after CustomUI enables this component; retry until UserHide sticks.
    if m_enabled and m_stockTargetHidePending then
        TryHideStockTargetWindows()
    end

    if SystemData.ActiveWindow.name == c_HOSTILE_WINDOW_NAME
        or SystemData.ActiveWindow.name == c_FRIENDLY_WINDOW_NAME then
        CustomUI.TargetWindow.Update(timePassed)
    end
end

function CustomUI.TargetWindow.Update(timePassed)
    if m_hostileFrame then
        m_hostileFrame.m_BuffTracker:Update(timePassed)
    end

    if m_friendlyFrame then
        m_friendlyFrame.m_BuffTracker:Update(timePassed)
    end
end

function CustomUI.TargetWindow.OnCombatFlagUpdated()
    if m_hostileFrame then
        m_hostileFrame:UpdateCombatState(GameData.Player.inCombat)
    end
end

function CustomUI.TargetWindow.OnHostileEffectsUpdated(updateType, updatedEffects, isFullList)
    if updateType == GameData.BuffTargetType.TARGET_HOSTILE and m_hostileFrame then
        m_hostileFrame.m_BuffTracker:UpdateBuffs(updatedEffects, isFullList)
    end
end

function CustomUI.TargetWindow.OnFriendlyEffectsUpdated(updateType, updatedEffects, isFullList)
    if updateType == GameData.BuffTargetType.TARGET_FRIENDLY and m_friendlyFrame then
        m_friendlyFrame.m_BuffTracker:UpdateBuffs(updatedEffects, isFullList)
    end
end

function CustomUI.TargetWindow.OnPlayerTargetUpdated(targetClassification)
    RefreshBothTargetsFromClient(targetClassification)
end

----------------------------------------------------------------
-- Component Adapter
----------------------------------------------------------------

local TargetWindowComponent = {
    Name = "TargetWindow",
    WindowName = c_HOSTILE_WINDOW_NAME,
    DefaultEnabled = false,
}

function TargetWindowComponent:Enable()
    if not m_initialized or not m_hostileFrame or not m_friendlyFrame then
        CustomUI.TargetWindow.Initialize()
    end

    if not m_hostileFrame or not m_friendlyFrame then
        return false
    end

    m_enabled = true
    SafeUserShow(c_HOSTILE_WINDOW_NAME)
    SafeUserShow(c_FRIENDLY_WINDOW_NAME)
    TryHideStockTargetWindows()
    ApplyTargetsFromCachedTargetInfo()
    return true
end

function TargetWindowComponent:Disable()
    m_enabled = false
    SafeUserHide(c_HOSTILE_WINDOW_NAME)
    SafeUserHide(c_FRIENDLY_WINDOW_NAME)
    ShowStockTargetWindows()
    return true
end

function TargetWindowComponent:ResetToDefaults()
    if type(CustomUI.ResetWindowToDefault) == "function" then
        CustomUI.ResetWindowToDefault(c_HOSTILE_WINDOW_NAME)
        CustomUI.ResetWindowToDefault(c_FRIENDLY_WINDOW_NAME)
    else
        if DoesWindowExist(c_HOSTILE_WINDOW_NAME) then
            WindowRestoreDefaultSettings(c_HOSTILE_WINDOW_NAME)
        end

        if DoesWindowExist(c_FRIENDLY_WINDOW_NAME) then
            WindowRestoreDefaultSettings(c_FRIENDLY_WINDOW_NAME)
        end
    end

    if m_hostileFrame and DoesWindowExist(c_HOSTILE_WINDOW_NAME) then
        local scale = WindowGetScale(c_HOSTILE_WINDOW_NAME)
        if scale then m_hostileFrame:SetScale(scale) end
    end

    if m_friendlyFrame and DoesWindowExist(c_FRIENDLY_WINDOW_NAME) then
        local scale = WindowGetScale(c_FRIENDLY_WINDOW_NAME)
        if scale then m_friendlyFrame:SetScale(scale) end
    end

    return true
end

function TargetWindowComponent:Shutdown()
end
CustomUI.RegisterComponent("TargetWindow", TargetWindowComponent)

----------------------------------------------------------------
-- Buff settings helpers
----------------------------------------------------------------

local BUFF_FILTER_KEYS = {
    "showBuffs", "showDebuffs", "showNeutral",
    "showShort", "showLong", "showPermanent",
    "playerCastOnly",
}

local BUFF_FILTER_DEFAULTS = {
    showBuffs      = true,
    showDebuffs    = true,
    showNeutral    = true,
    showShort      = true,
    showLong       = true,
    showPermanent  = true,
    playerCastOnly = false,
}

function CustomUI.TargetWindow.GetSettings()
    CustomUI.Settings.TargetWindow = CustomUI.Settings.TargetWindow or {}
    local v = CustomUI.Settings.TargetWindow

    if v.buffs then
        v.buffsHostile = v.buffsHostile or {}
        v.buffsFriendly = v.buffsFriendly or {}
        for _, k in ipairs(BUFF_FILTER_KEYS) do
            local val = v.buffs[k]
            if v.buffsHostile[k] == nil then
                v.buffsHostile[k] = val ~= nil and val or BUFF_FILTER_DEFAULTS[k]
            end
            if v.buffsFriendly[k] == nil then
                v.buffsFriendly[k] = val ~= nil and val or BUFF_FILTER_DEFAULTS[k]
            end
        end
        v.buffs = nil
    end

    if v.buffsHostile and not v.buffsFriendly then
        v.buffsFriendly = {}
        for _, k in ipairs(BUFF_FILTER_KEYS) do
            v.buffsFriendly[k] = v.buffsHostile[k] ~= nil and v.buffsHostile[k] or BUFF_FILTER_DEFAULTS[k]
        end
    elseif v.buffsFriendly and not v.buffsHostile then
        v.buffsHostile = {}
        for _, k in ipairs(BUFF_FILTER_KEYS) do
            v.buffsHostile[k] = v.buffsFriendly[k] ~= nil and v.buffsFriendly[k] or BUFF_FILTER_DEFAULTS[k]
        end
    end

    v.buffsHostile = v.buffsHostile or {}
    v.buffsFriendly = v.buffsFriendly or {}
    for _, k in ipairs(BUFF_FILTER_KEYS) do
        if v.buffsHostile[k] == nil then
            v.buffsHostile[k] = BUFF_FILTER_DEFAULTS[k]
        end
        if v.buffsFriendly[k] == nil then
            v.buffsFriendly[k] = BUFF_FILTER_DEFAULTS[k]
        end
    end
    return v
end

-- Settings API for CustomUISettingsWindow (and callers); returns the live filter tables.
function CustomUI.TargetWindow.GetBuffFilterHostile()
    return CustomUI.TargetWindow.GetSettings().buffsHostile
end

function CustomUI.TargetWindow.GetBuffFilterFriendly()
    return CustomUI.TargetWindow.GetSettings().buffsFriendly
end

function CustomUI.TargetWindow.ApplyBuffSettings()
    local s = CustomUI.TargetWindow.GetSettings()
    if m_hostileFrame and m_hostileFrame.m_BuffTracker then
        m_hostileFrame.m_BuffTracker:SetFilter(s.buffsHostile)
    end
    if m_friendlyFrame and m_friendlyFrame.m_BuffTracker then
        m_friendlyFrame.m_BuffTracker:SetFilter(s.buffsFriendly)
    end
end
