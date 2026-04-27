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

-- Per-HUD state tables (plain, no TargetUnitFrame).
local m_hostile  = { unitId = c_HOSTILE_UNIT_ID,  attachedId = 0, buffTracker = nil }
local m_friendly = { unitId = c_FRIENDLY_UNIT_ID, attachedId = 0, buffTracker = nil }

----------------------------------------------------------------
-- Local helpers
----------------------------------------------------------------

local function CreateHUDBuffTracker(parentWindowName, buffTargetType)
    local tracker = CustomUI.BuffTracker:Create(
        parentWindowName .. "Buff",
        parentWindowName,
        buffTargetType,
        c_MAX_BUFF_SLOTS,
        c_BUFF_STRIDE,
        SHOW_BUFF_FRAME_TIMER_LABELS)

    -- Anchor the container below the health bar.
    -- Point = anchor point on the health bar (bottom edge).
    -- RelativePoint = anchor point on the buff container (top edge).
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

local function DetachHUD(windowName, attachedId)
    if attachedId ~= 0 then
        DetachWindowFromWorldObject(windowName, attachedId)
    end
    WindowSetShowing(windowName, false)
end

-- Drives all HUD visuals from TargetInfo **without** calling UpdateFromClient().
-- Without a pending PLAYER_TARGET_UPDATED batch, GetUpdatedTargets() is nil and
-- TargetInfo:ClearUnits() wipes current targets (same as TargetWindow).
-- Returns the new attachedId (0 = no target).
local function RefreshHUDFromCache(hud, windowName)
    local entityId  = TargetInfo:UnitEntityId(hud.unitId)
    local hasTarget = entityId ~= nil and entityId ~= 0

    if not m_enabled or not hasTarget then
        if hud.attachedId ~= 0 then
            DetachHUD(windowName, hud.attachedId)
        end
        if hud.buffTracker then
            hud.buffTracker:Clear()
        end
        return 0
    end

    -- Update health bar.
    StatusBarSetCurrentValue(windowName .. "HealthBarBar", TargetInfo:UnitHealth(hud.unitId))

    -- Update name label.
    local unitName   = TargetInfo:UnitName(hud.unitId)
    local unitLevel  = TargetInfo:UnitBattleLevel(hud.unitId) or TargetInfo:UnitLevel(hud.unitId) or 0
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
    if entityId ~= hud.attachedId then
        if hud.attachedId ~= 0 then
            DetachWindowFromWorldObject(windowName, hud.attachedId)
        end
        AttachWindowToWorldObject(windowName, entityId)
        WindowSetShowing(windowName, true)
        if hud.buffTracker then
            hud.buffTracker:Clear()
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
        -- Default behaviour: make HUD show player-cast only (preserves previous behaviour)
        if m_hostile.buffTracker then m_hostile.buffTracker:SetFilter({ playerCastOnly = true }) end
        if m_friendly.buffTracker then m_friendly.buffTracker:SetFilter({ playerCastOnly = true }) end
    end

    -- Single handler: UpdateFromClient() must run once per event (see TargetWindowController).
    WindowRegisterEventHandler(c_HOSTILE_WINDOW_NAME, SystemData.Events.PLAYER_TARGET_UPDATED, "CustomUI.TargetHUD.OnPlayerTargetUpdated")
    WindowRegisterEventHandler(c_HOSTILE_WINDOW_NAME,  SystemData.Events.PLAYER_TARGET_STATE_UPDATED,   "CustomUI.TargetHUD.OnHostileStateUpdated")
    WindowRegisterEventHandler(c_FRIENDLY_WINDOW_NAME, SystemData.Events.PLAYER_TARGET_STATE_UPDATED,   "CustomUI.TargetHUD.OnFriendlyStateUpdated")
    WindowRegisterEventHandler(c_HOSTILE_WINDOW_NAME,  SystemData.Events.PLAYER_TARGET_EFFECTS_UPDATED, "CustomUI.TargetHUD.OnHostileEffectsUpdated")
    WindowRegisterEventHandler(c_FRIENDLY_WINDOW_NAME, SystemData.Events.PLAYER_TARGET_EFFECTS_UPDATED, "CustomUI.TargetHUD.OnFriendlyEffectsUpdated")

    m_initialized = true
end

function CustomUI.TargetHUD.OnShutdown()
    if SystemData.ActiveWindow.name == c_HOSTILE_WINDOW_NAME then
        CustomUI.TargetHUD.Shutdown()
    end
end

function CustomUI.TargetHUD.Shutdown()
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

function CustomUI.TargetHUD.GetSettings()
    CustomUI.Settings.TargetHUD = CustomUI.Settings.TargetHUD or {}
    local v = CustomUI.Settings.TargetHUD

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

function CustomUI.TargetHUD.OnPlayerTargetUpdated(targetClassification)
    if targetClassification ~= nil
        and targetClassification ~= c_HOSTILE_UNIT_ID
        and targetClassification ~= c_FRIENDLY_UNIT_ID
    then
        return
    end
    TargetInfo:UpdateFromClient()
    RefreshBothHUDsFromCache()
end

function CustomUI.TargetHUD.OnUpdate(timePassed)
    if SystemData.ActiveWindow.name ~= c_HOSTILE_WINDOW_NAME then return end
    if m_hostile.buffTracker  then m_hostile.buffTracker:Update(timePassed)  end
    if m_friendly.buffTracker then m_friendly.buffTracker:Update(timePassed) end
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
    end
end

function CustomUI.TargetHUD.OnFriendlyEffectsUpdated(updateType, updatedEffects, isFullList)
    if updateType == GameData.BuffTargetType.TARGET_FRIENDLY and m_friendly.buffTracker then
        m_friendly.buffTracker:UpdateBuffs(updatedEffects, isFullList)
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
    RefreshBothHUDsFromCache()
    return true
end

function TargetHUDComponent:Disable()
    m_enabled = false
    DetachHUD(c_HOSTILE_WINDOW_NAME,  m_hostile.attachedId)
    DetachHUD(c_FRIENDLY_WINDOW_NAME, m_friendly.attachedId)
    m_hostile.attachedId  = 0
    m_friendly.attachedId = 0
    return true
end

function TargetHUDComponent:ResetToDefaults()
    return true
end

function TargetHUDComponent:Shutdown()
end
CustomUI.RegisterComponent("TargetHUD", TargetHUDComponent)
