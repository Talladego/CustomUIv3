----------------------------------------------------------------
-- CustomUI.TargetHUD — Controller
-- Responsibilities: RegisterComponent, target events, BuffTracker per HUD, layout visibility.
-- No View/ Lua; layout is in TargetHUD.xml. CustomUI.mod loads this controller before
-- View/TargetHUD.xml; do not re-<Script> the controller in that XML.
-- World-attached mini HUDs (no TargetUnitFrame); static layout in XML; BuffTracker per side.
----------------------------------------------------------------

if not CustomUI.TargetHUD then
    CustomUI.TargetHUD = {}
end

----------------------------------------------------------------
-- Constants
----------------------------------------------------------------

local c_HOSTILE_WINDOW_NAME  = "CustomUIHostileTargetHUD"
local c_FRIENDLY_WINDOW_NAME = "CustomUIFriendlyTargetHUD"

local c_HOSTILE_UNIT_ID  = "selfhostiletarget"
local c_FRIENDLY_UNIT_ID = "selffriendlytarget"

local c_MAX_BUFF_SLOTS = 10
local c_BUFF_STRIDE    = 10   -- single row; center alignment handled by BuffTracker
local c_BUFF_ICON_GAP  = 2

----------------------------------------------------------------
-- Module state
----------------------------------------------------------------

local m_enabled     = false
local m_initialized = false
local m_handlersRegistered = false

-- Per-HUD state tables (plain, no TargetUnitFrame).
local m_hostile  = { unitId = c_HOSTILE_UNIT_ID,  attachedId = 0, buffTracker = nil }
local m_friendly = { unitId = c_FRIENDLY_UNIT_ID, attachedId = 0, buffTracker = nil }

----------------------------------------------------------------
-- Local helpers
----------------------------------------------------------------

local function CreateHUDBuffTracker(parentWindowName, buffTargetType)
    -- Runtime windows persist across /reloadui; destroy stale container before recreating.
    local containerName = parentWindowName .. "Buff"
    if DoesWindowExist(containerName) then
        DestroyWindow(containerName)
    end
    local tracker = CustomUI.BuffTracker:Create(
        containerName,
        parentWindowName,
        buffTargetType,
        c_MAX_BUFF_SLOTS,
        c_BUFF_STRIDE,
        SHOW_BUFF_FRAME_TIMER_LABELS)

    -- Anchor the container below the health bar.
    WindowClearAnchors(parentWindowName .. "Buff")
    WindowAddAnchor(parentWindowName .. "Buff", "bottom", parentWindowName .. "HealthBar", "top", 0, -c_BUFF_ICON_GAP)

    tracker:SetAlignment(CustomUI.BuffTracker.Alignment.CENTER)
    tracker:SetFilter({ playerCastOnly = true })
    CustomUI.BuffTracker.ApplyPlayerStatusRules(tracker)
    tracker:SetForceShowTrackerPriority100(true)
    tracker:SetSortMode(CustomUI.BuffTracker.SortMode.SHORT_LONG_PERM)
    tracker:SetHandleInput(false)  -- HUD is a non-interactive overlay
    tracker:Show(true)
    return tracker
end

-- Sync buff container visibility to match HUD window state.
local function SyncBuffContainerVisibility(hud)
    if not hud.buffTracker then return end
    if type(hud.buffTracker._ApplyContainerVisibility) == "function" then
        hud.buffTracker:_ApplyContainerVisibility()
    end
end

local function DetachHUD(windowName, hud)
    if hud.attachedId ~= 0 then
        DetachWindowFromWorldObject(windowName, hud.attachedId)
    end
    WindowSetShowing(windowName, false)
    -- Hide buff container when HUD is hidden.
    if hud.buffTracker then
        hud.buffTracker:Clear()
        SyncBuffContainerVisibility(hud)
    end
end

local function RegisterHandlers()
    if m_handlersRegistered then return end
    d("[TargetHUD] RegisterHandlers")
    WindowRegisterEventHandler(c_HOSTILE_WINDOW_NAME, SystemData.Events.PLAYER_TARGET_UPDATED, "CustomUI.TargetHUD.OnPlayerTargetUpdated")
    WindowRegisterEventHandler(c_HOSTILE_WINDOW_NAME,  SystemData.Events.PLAYER_TARGET_STATE_UPDATED,   "CustomUI.TargetHUD.OnHostileStateUpdated")
    WindowRegisterEventHandler(c_FRIENDLY_WINDOW_NAME, SystemData.Events.PLAYER_TARGET_STATE_UPDATED,   "CustomUI.TargetHUD.OnFriendlyStateUpdated")
    WindowRegisterEventHandler(c_HOSTILE_WINDOW_NAME,  SystemData.Events.PLAYER_TARGET_EFFECTS_UPDATED, "CustomUI.TargetHUD.OnHostileEffectsUpdated")
    WindowRegisterEventHandler(c_FRIENDLY_WINDOW_NAME, SystemData.Events.PLAYER_TARGET_EFFECTS_UPDATED, "CustomUI.TargetHUD.OnFriendlyEffectsUpdated")
    m_handlersRegistered = true
end

local function UnregisterHandlers()
    if not m_handlersRegistered then return end
    local e = SystemData.Events
    WindowUnregisterEventHandler(c_HOSTILE_WINDOW_NAME, e.PLAYER_TARGET_UPDATED)
    WindowUnregisterEventHandler(c_HOSTILE_WINDOW_NAME, e.PLAYER_TARGET_STATE_UPDATED)
    WindowUnregisterEventHandler(c_FRIENDLY_WINDOW_NAME, e.PLAYER_TARGET_STATE_UPDATED)
    WindowUnregisterEventHandler(c_HOSTILE_WINDOW_NAME, e.PLAYER_TARGET_EFFECTS_UPDATED)
    WindowUnregisterEventHandler(c_FRIENDLY_WINDOW_NAME, e.PLAYER_TARGET_EFFECTS_UPDATED)
    m_handlersRegistered = false
end

-- Drives HUD visuals from TargetInfo + CustomUI.TargetPresence (no UpdateFromClient here).
-- Returns the new attachedId (0 = no target).
local function RefreshHUDFromCache(hud, windowName)
    if type(CustomUI.TargetPresence) == "table"
        and type(CustomUI.TargetPresence.SyncFromTargetInfo) == "function" then
        CustomUI.TargetPresence.SyncFromTargetInfo(hud.unitId)
    end

    local hasTarget = false
    local entityId = 0
    if type(CustomUI.TargetPresence) == "table"
        and type(CustomUI.TargetPresence.ShouldShow) == "function"
        and type(CustomUI.TargetPresence.GetEntityId) == "function" then
        hasTarget = CustomUI.TargetPresence.ShouldShow(hud.unitId)
        entityId = CustomUI.TargetPresence.GetEntityId(hud.unitId)
    else
        entityId = TargetInfo:UnitEntityId(hud.unitId)
        hasTarget = entityId ~= nil and entityId ~= 0
    end

    if not m_enabled or not hasTarget or entityId == 0 then
        if hud.attachedId ~= 0 then
            DetachHUD(windowName, hud)
        end
        return 0
    end

    -- Update health bar.
    StatusBarSetCurrentValue(windowName .. "HealthBarBar", TargetInfo:UnitHealth(hud.unitId))

    -- Single label: <icon> career portrait + name + rank.
    local unitName   = TargetInfo:UnitName(hud.unitId)
    local unitLevel  = TargetInfo:UnitLevel(hud.unitId) or 0
    local careerLine = TargetInfo:UnitCareer(hud.unitId)
    local iconNum    = (careerLine and careerLine ~= 0) and Icons.GetCareerIconIDFromCareerLine(careerLine) or nil

    local nameText
    if iconNum then
        nameText = L"<icon" .. towstring(iconNum) .. L"> " .. unitName .. L" (" .. towstring(unitLevel) .. L")"
    else
        nameText = unitName .. L" (" .. towstring(unitLevel) .. L")"
    end

    local nameColor = TargetInfo:UnitRelationshipColor(hud.unitId)
    local labelName = windowName .. "TargetName"
    WindowSetShowing(labelName, true)
    LabelSetText(labelName, nameText)
    LabelSetTextColor(labelName, nameColor.r, nameColor.g, nameColor.b)

    -- Attach / re-attach world object window.
    if entityId ~= hud.attachedId or not WindowGetShowing(windowName) then
        if hud.attachedId ~= 0 then
            DetachWindowFromWorldObject(windowName, hud.attachedId)
        end
        AttachWindowToWorldObject(windowName, entityId)
        WindowSetShowing(windowName, true)
        if hud.buffTracker and entityId ~= hud.attachedId then
            -- Show the buff container now that the owner HUD is visible.
            SyncBuffContainerVisibility(hud)
            -- Clear old buffs entirely so they don't persist through the removal grace period.
            hud.buffTracker:Clear()
            -- Full refresh from engine buff cache; then force immediate rebuild.
            hud.buffTracker:Refresh(true)
            if hud.buffTracker.m_rebuildPending then
                hud.buffTracker.m_rebuildPending = false
                hud.buffTracker:OnBuffsChanged()
            end
        end
    end

    return entityId
end

local function RefreshBothHUDsFromCache()
    m_hostile.attachedId  = RefreshHUDFromCache(m_hostile, c_HOSTILE_WINDOW_NAME)
    m_friendly.attachedId = RefreshHUDFromCache(m_friendly, c_FRIENDLY_WINDOW_NAME)
end

----------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------

function CustomUI.TargetHUD.Initialize()
    if m_initialized then return end

    if not DoesWindowExist(c_HOSTILE_WINDOW_NAME) then
        CreateWindowFromTemplate(c_HOSTILE_WINDOW_NAME,  "CustomUITargetHUDTemplate", "Root")
    end
    if not DoesWindowExist(c_FRIENDLY_WINDOW_NAME) then
        CreateWindowFromTemplate(c_FRIENDLY_WINDOW_NAME, "CustomUITargetHUDTemplate", "Root")
    end

    WindowSetShowing(c_HOSTILE_WINDOW_NAME,  false)
    WindowSetShowing(c_FRIENDLY_WINDOW_NAME, false)

    -- Initialise health bars to 0–100 scale with team colours.
    StatusBarSetMaximumValue(c_HOSTILE_WINDOW_NAME  .. "HealthBarBar", 100)
    StatusBarSetMaximumValue(c_FRIENDLY_WINDOW_NAME .. "HealthBarBar", 100)
    StatusBarSetForegroundTint(c_HOSTILE_WINDOW_NAME  .. "HealthBarBar", 200, 50,  50)
    StatusBarSetForegroundTint(c_FRIENDLY_WINDOW_NAME .. "HealthBarBar", 50,  200, 50)
    StatusBarSetBackgroundTint(c_HOSTILE_WINDOW_NAME  .. "HealthBarBar", 0, 0, 0)
    StatusBarSetBackgroundTint(c_FRIENDLY_WINDOW_NAME .. "HealthBarBar", 0, 0, 0)

    local function HideIfExists(name)
        if DoesWindowExist(name) then WindowSetShowing(name, false) end
    end
    HideIfExists(c_HOSTILE_WINDOW_NAME  .. "HealthBarBarText")
    HideIfExists(c_FRIENDLY_WINDOW_NAME .. "HealthBarBarText")

    m_hostile.buffTracker  = CreateHUDBuffTracker(c_HOSTILE_WINDOW_NAME,  GameData.BuffTargetType.TARGET_HOSTILE)
    m_friendly.buffTracker = CreateHUDBuffTracker(c_FRIENDLY_WINDOW_NAME, GameData.BuffTargetType.TARGET_FRIENDLY)

    if not m_hostile.buffTracker or not m_friendly.buffTracker then
        if m_hostile.buffTracker  then m_hostile.buffTracker:Shutdown();  m_hostile.buffTracker  = nil end
        if m_friendly.buffTracker then m_friendly.buffTracker:Shutdown(); m_friendly.buffTracker = nil end
        return
    end

    -- Apply persisted buff filter settings (if any)
    if type(CustomUI.TargetHUD.ApplyBuffSettings) == "function" then
        CustomUI.TargetHUD.ApplyBuffSettings()
    else
        if m_hostile.buffTracker then m_hostile.buffTracker:SetFilter({ playerCastOnly = true }) end
        if m_friendly.buffTracker then m_friendly.buffTracker:SetFilter({ playerCastOnly = true }) end
    end

    m_initialized = true
end

function CustomUI.TargetHUD.OnShutdown()
    if SystemData.ActiveWindow.name == c_HOSTILE_WINDOW_NAME then
        CustomUI.TargetHUD.Shutdown()
    end
end

function CustomUI.TargetHUD.Shutdown()
    if type(CustomUI.TargetPresence) == "table"
        and type(CustomUI.TargetPresence.Reset) == "function" then
        CustomUI.TargetPresence.Reset()
    end
    UnregisterHandlers()
    if m_hostile.buffTracker  then m_hostile.buffTracker:Shutdown();  m_hostile.buffTracker  = nil end
    if m_friendly.buffTracker then m_friendly.buffTracker:Shutdown(); m_friendly.buffTracker = nil end

    if DoesWindowExist(c_HOSTILE_WINDOW_NAME) then
        if m_hostile.attachedId ~= 0 then DetachWindowFromWorldObject(c_HOSTILE_WINDOW_NAME, m_hostile.attachedId) end
        WindowSetShowing(c_HOSTILE_WINDOW_NAME, false)
    end
    if DoesWindowExist(c_FRIENDLY_WINDOW_NAME) then
        if m_friendly.attachedId ~= 0 then DetachWindowFromWorldObject(c_FRIENDLY_WINDOW_NAME, m_friendly.attachedId) end
        WindowSetShowing(c_FRIENDLY_WINDOW_NAME, false)
    end

    m_hostile.attachedId  = 0
    m_friendly.attachedId = 0
    m_enabled     = false
    m_initialized = false
end

----------------------------------------------------------------

function CustomUI.TargetHUD.GetSettings()
    CustomUI.Settings.TargetHUD = CustomUI.Settings.TargetHUD or {}
    local v = CustomUI.Settings.TargetHUD
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

function CustomUI.TargetHUD.GetBuffFilterHostile()
    return CustomUI.TargetHUD.GetSettings().buffsHostile
end

function CustomUI.TargetHUD.GetBuffFilterFriendly()
    return CustomUI.TargetHUD.GetSettings().buffsFriendly
end

function CustomUI.TargetHUD.ApplyBuffSettings()
    local s = CustomUI.TargetHUD.GetSettings()
    if m_hostile and m_hostile.buffTracker then
        m_hostile.buffTracker:SetFilter(s.buffsHostile)
    end
    if m_friendly and m_friendly.buffTracker then
        m_friendly.buffTracker:SetFilter(s.buffsFriendly)
    end
end

----------------------------------------------------------------
-- Event Handlers
----------------------------------------------------------------

function CustomUI.TargetHUD.OnPlayerTargetUpdated(targetClassification, targetId, targetType)
    if targetClassification ~= nil
        and targetClassification ~= TargetInfo.HOSTILE_TARGET
        and targetClassification ~= TargetInfo.FRIENDLY_TARGET
    then
        return
    end
    if type(CustomUI.TargetPresence) == "table"
        and type(CustomUI.TargetPresence.NoteTargetEvent) == "function" then
        CustomUI.TargetPresence.NoteTargetEvent(targetClassification, targetId)
    end
    TargetInfo:UpdateFromClient()
    if type(CustomUI.TargetPresence) == "table"
        and type(CustomUI.TargetPresence.OnTargetRefreshComplete) == "function" then
        CustomUI.TargetPresence.OnTargetRefreshComplete(targetClassification)
    end
    RefreshBothHUDsFromCache()
end

-- OnUpdate fires on EACH HUD window (hostile/friendly) while they are visible.
-- Used for buff timer ticks and periodic buff pruning.
function CustomUI.TargetHUD.OnUpdate(timePassed)
    if not m_enabled then return end
    local wn = SystemData.ActiveWindow.name
    if wn == c_HOSTILE_WINDOW_NAME then
        if m_hostile.buffTracker then m_hostile.buffTracker:Update(timePassed) end
    elseif wn == c_FRIENDLY_WINDOW_NAME then
        if m_friendly.buffTracker then m_friendly.buffTracker:Update(timePassed) end
    end
end

function CustomUI.TargetHUD.OnHostileStateUpdated()
    RefreshBothHUDsFromCache()
end

function CustomUI.TargetHUD.OnFriendlyStateUpdated()
    RefreshBothHUDsFromCache()
end

function CustomUI.TargetHUD.OnHostileEffectsUpdated(updateType, updatedEffects, isFullList)
    if updateType == GameData.BuffTargetType.TARGET_HOSTILE and m_hostile.buffTracker then
        m_hostile.buffTracker:UpdateBuffs(updatedEffects, isFullList)
        -- Force immediate rebuild — no external tick is guaranteed for world-attached HUDs.
        SyncBuffContainerVisibility(m_hostile)
        if m_hostile.buffTracker.m_rebuildPending then
            m_hostile.buffTracker.m_rebuildPending = false
            m_hostile.buffTracker:OnBuffsChanged()
        end
    end
end

function CustomUI.TargetHUD.OnFriendlyEffectsUpdated(updateType, updatedEffects, isFullList)
    if updateType == GameData.BuffTargetType.TARGET_FRIENDLY and m_friendly.buffTracker then
        m_friendly.buffTracker:UpdateBuffs(updatedEffects, isFullList)
        -- Force immediate rebuild — no external tick is guaranteed for world-attached HUDs.
        SyncBuffContainerVisibility(m_friendly)
        if m_friendly.buffTracker.m_rebuildPending then
            m_friendly.buffTracker.m_rebuildPending = false
            m_friendly.buffTracker:OnBuffsChanged()
        end
    end
end

----------------------------------------------------------------
-- Component Adapter
----------------------------------------------------------------

local TargetHUDComponent = {
    Name           = "TargetHUD",
    WindowName     = c_HOSTILE_WINDOW_NAME,
    DefaultEnabled = false,
}

function TargetHUDComponent:Enable()
    if not m_initialized then
        CustomUI.TargetHUD.Initialize()
    end

    if not m_hostile.buffTracker or not m_friendly.buffTracker then
        return false
    end

    m_enabled = true
    RegisterHandlers()
    RefreshBothHUDsFromCache()
    return true
end

function TargetHUDComponent:Disable()
    m_enabled = false
    if type(CustomUI.TargetPresence) == "table"
        and type(CustomUI.TargetPresence.Reset) == "function" then
        CustomUI.TargetPresence.Reset()
    end
    UnregisterHandlers()
    DetachHUD(c_HOSTILE_WINDOW_NAME,  m_hostile)
    DetachHUD(c_FRIENDLY_WINDOW_NAME, m_friendly)
    m_hostile.attachedId  = 0
    m_friendly.attachedId = 0
    return true
end

function TargetHUDComponent:ResetToDefaults()
    return true
end

function TargetHUDComponent:Shutdown()
    CustomUI.TargetHUD.Shutdown()
end
CustomUI.RegisterComponent("TargetHUD", TargetHUDComponent)
