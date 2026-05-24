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
local c_STOCK_HOSTILE_TARGET_WINDOW   = "TargetWindow" -- ea_targetwindow uses this window for event handlers

local c_MAX_BUFF_SLOTS = 20
local c_BUFF_STRIDE = 5

----------------------------------------------------------------
-- Module state
----------------------------------------------------------------

local m_enabled = false
local m_hostileFrame = nil
local m_friendlyFrame = nil
local m_initialized = false
local m_handlersRegistered = false
-- True until both stock target layout windows are registered with LayoutEditor and UserHide has been applied.
local m_stockTargetHidePending = false
local m_stockTargetUnhookPending = false
local m_stockTargetUnhooked = false

----------------------------------------------------------------
-- Local helpers
----------------------------------------------------------------

-- Forward decls (used before definition).
local TryUnhookStockTargetHandlers

local function CreateTargetFrame(frameName, unitId, buffTargetType, parentWindowName)
    if not DoesWindowExist(parentWindowName) then
        return nil
    end

    -- Runtime windows persist across /reloadui; destroy stale frame before recreating.
    if DoesWindowExist(frameName) then
        DestroyWindow(frameName)
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
    CustomUI.BuffTracker.ApplySharedDefaultLists(frame.m_BuffTracker)

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
    end
    if DoesWindowExist(windowName) then
        WindowSetShowing(windowName, false)
    end
end

local function RegisterHandlers()
    if m_handlersRegistered then return end
    -- Single handler: UpdateFromClient() must run once per event (see RefreshBothTargetsFromClient).
    WindowRegisterEventHandler(c_HOSTILE_WINDOW_NAME, SystemData.Events.PLAYER_TARGET_UPDATED, "CustomUI.TargetWindow.OnPlayerTargetUpdated")
    WindowRegisterEventHandler(c_HOSTILE_WINDOW_NAME, SystemData.Events.PLAYER_TARGET_EFFECTS_UPDATED, "CustomUI.TargetWindow.OnHostileEffectsUpdated")
    WindowRegisterEventHandler(c_FRIENDLY_WINDOW_NAME, SystemData.Events.PLAYER_TARGET_EFFECTS_UPDATED, "CustomUI.TargetWindow.OnFriendlyEffectsUpdated")
    WindowRegisterEventHandler(c_HOSTILE_WINDOW_NAME, SystemData.Events.PLAYER_COMBAT_FLAG_UPDATED, "CustomUI.TargetWindow.OnCombatFlagUpdated")
    m_handlersRegistered = true
end

local function UnregisterHandlers()
    if not m_handlersRegistered then return end
    local e = SystemData.Events
    WindowUnregisterEventHandler(c_HOSTILE_WINDOW_NAME, e.PLAYER_TARGET_UPDATED)
    WindowUnregisterEventHandler(c_HOSTILE_WINDOW_NAME, e.PLAYER_TARGET_EFFECTS_UPDATED)
    WindowUnregisterEventHandler(c_FRIENDLY_WINDOW_NAME, e.PLAYER_TARGET_EFFECTS_UPDATED)
    WindowUnregisterEventHandler(c_HOSTILE_WINDOW_NAME, e.PLAYER_COMBAT_FLAG_UPDATED)
    m_handlersRegistered = false
end

local function SetTargetFrameBuffTrackerShowing(frame, showing)
    local tracker = frame and frame.m_BuffTracker
    if tracker and type(tracker.Show) == "function" then
        tracker:Show(showing == true)
    end
end

local function RefreshWindowVisibility()
    local hostileVisible = false
    local friendlyVisible = false

    if m_enabled and m_hostileFrame then
        if type(CustomUI.TargetPresence) == "table"
            and type(CustomUI.TargetPresence.ShouldShow) == "function" then
            hostileVisible = CustomUI.TargetPresence.ShouldShow(c_HOSTILE_UNIT_ID)
        else
            hostileVisible = WindowGetShowing(m_hostileFrame:GetName())
        end
    end

    if m_enabled and m_friendlyFrame then
        if type(CustomUI.TargetPresence) == "table"
            and type(CustomUI.TargetPresence.ShouldShow) == "function" then
            friendlyVisible = CustomUI.TargetPresence.ShouldShow(c_FRIENDLY_UNIT_ID)
        else
            friendlyVisible = WindowGetShowing(m_friendlyFrame:GetName())
        end
    end

    if hostileVisible then
        SafeLayoutShow(c_HOSTILE_WINDOW_NAME)
    else
        SafeLayoutHide(c_HOSTILE_WINDOW_NAME)
    end
    SetTargetFrameBuffTrackerShowing(m_hostileFrame, hostileVisible)

    if friendlyVisible then
        SafeLayoutShow(c_FRIENDLY_WINDOW_NAME)
    else
        SafeLayoutHide(c_FRIENDLY_WINDOW_NAME)
    end
    SetTargetFrameBuffTrackerShowing(m_friendlyFrame, friendlyVisible)
end

-- Count CustomUI target frames currently visible (mirrors stock TargetWindow.NumberOfTargetWindowsShowing intent).
local function CountShowingTargetFrames()
    local n = 0
    if m_hostileFrame then
        if type(CustomUI.TargetPresence) == "table"
            and type(CustomUI.TargetPresence.ShouldShow) == "function" then
            if CustomUI.TargetPresence.ShouldShow(c_HOSTILE_UNIT_ID) then
                n = n + 1
            end
        elseif WindowGetShowing(m_hostileFrame:GetName()) then
            n = n + 1
        end
    end
    if m_friendlyFrame then
        if type(CustomUI.TargetPresence) == "table"
            and type(CustomUI.TargetPresence.ShouldShow) == "function" then
            if CustomUI.TargetPresence.ShouldShow(c_FRIENDLY_UNIT_ID) then
                n = n + 1
            end
        elseif WindowGetShowing(m_friendlyFrame:GetName()) then
            n = n + 1
        end
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

    -- Unhook stock handlers independently of LayoutEditor registration state.
    TryUnhookStockTargetHandlers()
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

TryUnhookStockTargetHandlers = function()
    if not m_enabled then
        m_stockTargetUnhookPending = false
        return
    end

    if m_stockTargetUnhooked then
        return
    end

    if not DoesWindowExist(c_STOCK_HOSTILE_TARGET_WINDOW) then
        m_stockTargetUnhookPending = true
        return
    end

    local e = SystemData.Events
    -- ea_targetwindow/source/targetwindow.lua registers these on "TargetWindow".
    WindowUnregisterEventHandler(c_STOCK_HOSTILE_TARGET_WINDOW, e.PLAYER_COMBAT_FLAG_UPDATED)
    WindowUnregisterEventHandler(c_STOCK_HOSTILE_TARGET_WINDOW, e.PLAYER_TARGET_UPDATED)
    WindowUnregisterEventHandler(c_STOCK_HOSTILE_TARGET_WINDOW, e.PLAYER_TARGET_EFFECTS_UPDATED)

    m_stockTargetUnhooked = true
    m_stockTargetUnhookPending = false
end

local function TryRehookStockTargetHandlers()
    if not m_stockTargetUnhooked then
        return
    end
    if not DoesWindowExist(c_STOCK_HOSTILE_TARGET_WINDOW) then
        -- Stock UI not loaded / window missing; nothing to restore yet.
        m_stockTargetUnhooked = false
        return
    end

    local e = SystemData.Events
    WindowRegisterEventHandler(c_STOCK_HOSTILE_TARGET_WINDOW, e.PLAYER_COMBAT_FLAG_UPDATED, "TargetWindow.UpdateTargetCombat")
    WindowRegisterEventHandler(c_STOCK_HOSTILE_TARGET_WINDOW, e.PLAYER_TARGET_UPDATED, "TargetWindow.UpdateTarget")
    WindowRegisterEventHandler(c_STOCK_HOSTILE_TARGET_WINDOW, e.PLAYER_TARGET_EFFECTS_UPDATED, "TargetWindow.OnEffectsUpdated")
    m_stockTargetUnhooked = false
end

-- Must call TargetInfo:UpdateFromClient() at most once per PLAYER_TARGET_UPDATED — GetUpdatedTargets()
-- is consumed until the next event (see easystem_targetinfo/targetinfo.lua). Stock ea_targetwindow
-- uses a single handler; two handlers each calling UpdateFromClient breaks the other slot after reload.
local function RefreshBothTargetsFromClient(targetClassification, targetId, targetType)
    if targetClassification ~= nil
        and targetClassification ~= TargetInfo.HOSTILE_TARGET
        and targetClassification ~= TargetInfo.FRIENDLY_TARGET
    then
        return
    end

    if not m_hostileFrame or not m_friendlyFrame then
        return
    end

    local oldNumberOfTargets = CountShowingTargetFrames()

    local oldHostileEntityId = TargetInfo:UnitEntityId(c_HOSTILE_UNIT_ID)
    local oldFriendlyEntityId = TargetInfo:UnitEntityId(c_FRIENDLY_UNIT_ID)

    if type(CustomUI.TargetPresence) == "table"
        and type(CustomUI.TargetPresence.NoteTargetEvent) == "function" then
        CustomUI.TargetPresence.NoteTargetEvent(targetClassification, targetId)
    end

    TargetInfo:UpdateFromClient()

    if type(CustomUI.TargetPresence) == "table"
        and type(CustomUI.TargetPresence.OnTargetRefreshComplete) == "function" then
        CustomUI.TargetPresence.OnTargetRefreshComplete(targetClassification)
    end

    if type(CustomUI.TargetPresence) == "table"
        and type(CustomUI.TargetPresence.InjectCacheIfHeld) == "function" then
        CustomUI.TargetPresence.InjectCacheIfHeld(c_HOSTILE_UNIT_ID)
        CustomUI.TargetPresence.InjectCacheIfHeld(c_FRIENDLY_UNIT_ID)
    end

    m_hostileFrame:UpdateUnit()
    m_friendlyFrame:UpdateUnit()

    if type(CustomUI.TargetPresence) == "table"
        and type(CustomUI.TargetPresence.StabilizeFrame) == "function" then
        CustomUI.TargetPresence.StabilizeFrame(m_hostileFrame, c_HOSTILE_UNIT_ID)
        CustomUI.TargetPresence.StabilizeFrame(m_friendlyFrame, c_FRIENDLY_UNIT_ID)
    end

    local targetHasChanged = false

    if TargetInfo:UnitEntityId(c_HOSTILE_UNIT_ID) ~= oldHostileEntityId then
        m_hostileFrame:StopInterpolatingStatus()
        m_hostileFrame.m_BuffTracker:Refresh( true )
        targetHasChanged = true
    end
    if TargetInfo:UnitEntityId(c_FRIENDLY_UNIT_ID) ~= oldFriendlyEntityId then
        m_friendlyFrame:StopInterpolatingStatus()
        m_friendlyFrame.m_BuffTracker:Refresh( true )
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
-- TargetInfo:UpdateFromClient() here: without a pending batch, GetUpdatedTargets() is nil;
-- CustomUI's hooked UpdateFromClient preserves the existing cache (see TargetPresence.lua).
local function ApplyTargetsFromCachedTargetInfo()
    if not m_hostileFrame or not m_friendlyFrame then
        return
    end

    if type(CustomUI.TargetPresence) == "table"
        and type(CustomUI.TargetPresence.SyncFromTargetInfo) == "function" then
        CustomUI.TargetPresence.SyncFromTargetInfo(c_HOSTILE_UNIT_ID)
        CustomUI.TargetPresence.SyncFromTargetInfo(c_FRIENDLY_UNIT_ID)
    end

    if type(CustomUI.TargetPresence) == "table"
        and type(CustomUI.TargetPresence.InjectCacheIfHeld) == "function" then
        CustomUI.TargetPresence.InjectCacheIfHeld(c_HOSTILE_UNIT_ID)
        CustomUI.TargetPresence.InjectCacheIfHeld(c_FRIENDLY_UNIT_ID)
    end

    m_hostileFrame:UpdateUnit()
    m_friendlyFrame:UpdateUnit()

    if type(CustomUI.TargetPresence) == "table"
        and type(CustomUI.TargetPresence.StabilizeFrame) == "function" then
        CustomUI.TargetPresence.StabilizeFrame(m_hostileFrame, c_HOSTILE_UNIT_ID)
        CustomUI.TargetPresence.StabilizeFrame(m_friendlyFrame, c_FRIENDLY_UNIT_ID)
    end

    m_hostileFrame.m_BuffTracker:Refresh( true )
    m_friendlyFrame.m_BuffTracker:Refresh( true )

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

    m_initialized = true

    -- Buff trackers start with nil filter (shows everything); sync persisted settings before Refresh.
    CustomUI.TargetWindow.ApplyBuffSettings()
    ApplyTargetsFromCachedTargetInfo()
end

function CustomUI.TargetWindow.Shutdown()
    if type(CustomUI.TargetPresence) == "table"
        and type(CustomUI.TargetPresence.Reset) == "function" then
        CustomUI.TargetPresence.Reset()
    end
    UnregisterHandlers()
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
    if not m_enabled then
        return
    end

    -- Stock windows may register after CustomUI enables this component; retry until UserHide sticks.
    if m_stockTargetHidePending then
        TryHideStockTargetWindows()
    end

    if SystemData.ActiveWindow.name == c_HOSTILE_WINDOW_NAME
        or SystemData.ActiveWindow.name == c_FRIENDLY_WINDOW_NAME then
        CustomUI.TargetWindow.Update(timePassed)
    end
end

function CustomUI.TargetWindow.Update(timePassed)
    if not m_enabled then
        return
    end

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

function CustomUI.TargetWindow.OnPlayerTargetUpdated(targetClassification, targetId, targetType)
    RefreshBothTargetsFromClient(targetClassification, targetId, targetType)
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
    RegisterHandlers()
    SafeUserShow(c_HOSTILE_WINDOW_NAME)
    SafeUserShow(c_FRIENDLY_WINDOW_NAME)
    TryHideStockTargetWindows()
    TryUnhookStockTargetHandlers()
    CustomUI.TargetWindow.ApplyBuffSettings()
    ApplyTargetsFromCachedTargetInfo()
    -- Harden toggles: resync buffs immediately in case we missed effects events while stock owned the UI.
    if m_hostileFrame and m_hostileFrame.m_BuffTracker and type(m_hostileFrame.m_BuffTracker.Refresh) == "function" then
        m_hostileFrame.m_BuffTracker:Refresh()
    end
    if m_friendlyFrame and m_friendlyFrame.m_BuffTracker and type(m_friendlyFrame.m_BuffTracker.Refresh) == "function" then
        m_friendlyFrame.m_BuffTracker:Refresh()
    end
    return true
end

function TargetWindowComponent:Disable()
    m_enabled = false
    if type(CustomUI.TargetPresence) == "table"
        and type(CustomUI.TargetPresence.Reset) == "function" then
        CustomUI.TargetPresence.Reset()
    end
    UnregisterHandlers()
    -- Clear CustomUI trackers before handing back to stock to avoid stale state across rapid toggles.
    if m_hostileFrame and m_hostileFrame.m_BuffTracker and type(m_hostileFrame.m_BuffTracker.Clear) == "function" then
        m_hostileFrame.m_BuffTracker:Clear()
    end
    if m_friendlyFrame and m_friendlyFrame.m_BuffTracker and type(m_friendlyFrame.m_BuffTracker.Clear) == "function" then
        m_friendlyFrame.m_BuffTracker:Clear()
    end
    SetTargetFrameBuffTrackerShowing(m_hostileFrame, false)
    SetTargetFrameBuffTrackerShowing(m_friendlyFrame, false)
    SafeUserHide(c_HOSTILE_WINDOW_NAME)
    SafeUserHide(c_FRIENDLY_WINDOW_NAME)
    TryRehookStockTargetHandlers()
    ShowStockTargetWindows()
    -- Force stock to rebuild unit + buff state immediately after rehook/show.
    if type(TargetWindow) == "table" and type(TargetWindow.UpdateTarget) == "function" then
        TargetWindow.UpdateTarget("selfhostiletarget")
        TargetWindow.UpdateTarget("selffriendlytarget")
    end
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
    -- Shutdown is called by CustomUI core; fully tear down handlers/frames.
    CustomUI.TargetWindow.Shutdown()
end
CustomUI.RegisterComponent("TargetWindow", TargetWindowComponent)

----------------------------------------------------------------
-- Buff settings helpers
----------------------------------------------------------------

function CustomUI.TargetWindow.GetSettings()
    CustomUI.Settings.TargetWindow = CustomUI.Settings.TargetWindow or {}
    local v = CustomUI.Settings.TargetWindow
    local keys = CustomUI.BuffTracker.FilterSettingKeys
    local defs = CustomUI.BuffTracker.FilterDefaults

    if v.buffs then
        v.buffsHostile = v.buffsHostile or {}
        v.buffsFriendly = v.buffsFriendly or {}
        for _, k in ipairs(keys) do
            local val = v.buffs[k]
            if v.buffsHostile[k] == nil then
                v.buffsHostile[k] = val ~= nil and val or defs[k]
            end
            if v.buffsFriendly[k] == nil then
                v.buffsFriendly[k] = val ~= nil and val or defs[k]
            end
        end
        v.buffs = nil
    end

    if v.buffsHostile and not v.buffsFriendly then
        v.buffsFriendly = {}
        for _, k in ipairs(keys) do
            v.buffsFriendly[k] = v.buffsHostile[k] ~= nil and v.buffsHostile[k] or defs[k]
        end
    elseif v.buffsFriendly and not v.buffsHostile then
        v.buffsHostile = {}
        for _, k in ipairs(keys) do
            v.buffsHostile[k] = v.buffsFriendly[k] ~= nil and v.buffsFriendly[k] or defs[k]
        end
    end

    v.buffsHostile = v.buffsHostile or {}
    v.buffsFriendly = v.buffsFriendly or {}
    for _, k in ipairs(keys) do
        if v.buffsHostile[k] == nil then
            v.buffsHostile[k] = defs[k]
        end
        if v.buffsFriendly[k] == nil then
            v.buffsFriendly[k] = defs[k]
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
