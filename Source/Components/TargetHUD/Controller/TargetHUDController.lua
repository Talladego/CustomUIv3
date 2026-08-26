----------------------------------------------------------------
-- CustomUI.TargetHUD — Controller
-- Responsibilities: RegisterComponent, target events, BuffTracker per HUD, layout visibility.
-- No View/ Lua; layout is in TargetHUD.xml. CustomUI.mod loads this controller before
-- View/TargetHUD.xml; do not re-<Script> the controller in that XML.
-- World-attached mini HUDs (no TargetUnitFrame). Hostile/friendly instances are XML;
-- self is CreateWindowFromTemplate at runtime (BuffHead). BuffTracker per side.
--
-- World bind policy:
--   • Hostile/friendly: live TargetInfo via TargetPresence.HasLiveTarget (no hold).
--     Deselect engine-detaches, then GroupIcons.RebindAllTrackedWorldObjects().
--   • Component disable: spatial squash — no engine detach (shared bind per worldObjNum).
--   • Self: CreateWindowFromTemplate under Root, attach GameData.Player.worldObjNum.
----------------------------------------------------------------

if not CustomUI.TargetHUD then
    CustomUI.TargetHUD = {}
end

----------------------------------------------------------------
-- Constants
----------------------------------------------------------------

local c_HOSTILE_WINDOW_NAME  = "CustomUIHostileTargetHUD"
local c_FRIENDLY_WINDOW_NAME = "CustomUIFriendlyTargetHUD"
local c_SELF_WINDOW_NAME     = "CustomUISelfTargetHUD"

local c_HOSTILE_UNIT_ID  = "selfhostiletarget"
local c_FRIENDLY_UNIT_ID = "selffriendlytarget"
local c_TARGET_PRESENCE_CONSUMER = "TargetHUD"

local c_MAX_BUFF_SLOTS = 10
local c_BUFF_STRIDE    = 10
local c_BUFF_ICON_GAP  = 2

local c_SIDE_KEYS = { "hostile", "friendly", "self" }

----------------------------------------------------------------
-- Module state
----------------------------------------------------------------

local m_enabled     = false
local m_initialized = false
local m_handlersRegistered = false
local m_selfHandlersRegistered = false
local m_selfGlobalHandlersRegistered = false

local m_sides = {}

local m_selfAttachPollTimer = 0
local m_selfAttachGraceTimer = 0
local c_SELF_ATTACH_POLL_INTERVAL = 0.5
local c_SELF_ATTACH_GRACE_SECONDS = 15

----------------------------------------------------------------
-- Local helpers
----------------------------------------------------------------

local function DebugLog(message)
    if CustomUI.DebugLogging ~= true then
        return
    end
    local dfn = type(CustomUI.GetClientDebugLog) == "function" and CustomUI.GetClientDebugLog() or nil
    if type(dfn) == "function" then
        dfn(towstring("[CustomUI.TargetHUD] " .. tostring(message)))
    end
end

local function SideSettingsActive(sideSettings)
    if sideSettings == nil then
        return false
    end
    return sideSettings.showHealthBar == true or sideSettings.showBuffTracker == true
end

local function GetPlayerWorldObjNum()
    local raw = GameData and GameData.Player and GameData.Player.worldObjNum
    if raw == nil or raw == 0 then
        return 0
    end
    local asNumber = tonumber(raw)
    if asNumber ~= nil then
        return asNumber
    end
    return raw
end

local function RequestSelfAttachRetry(graceSeconds)
    m_selfAttachGraceTimer = math.max(m_selfAttachGraceTimer, graceSeconds or c_SELF_ATTACH_GRACE_SECONDS)
    m_selfAttachPollTimer = 0
end

local function SideWindowHasTemplateStructure(windowName)
    return DoesWindowExist(windowName .. "HealthBar")
        and DoesWindowExist(windowName .. "TargetName")
end

local function IsFriendlyTargetSelf()
    local playerWid = GetPlayerWorldObjNum()
    if playerWid ~= 0 then
        local friendlyEntityId = 0
        if type(CustomUI.TargetPresence) == "table"
            and type(CustomUI.TargetPresence.GetLiveEntityId) == "function" then
            friendlyEntityId = CustomUI.TargetPresence.GetLiveEntityId(c_FRIENDLY_UNIT_ID) or 0
        else
            friendlyEntityId = TargetInfo:UnitEntityId(c_FRIENDLY_UNIT_ID) or 0
        end
        if friendlyEntityId ~= 0 and friendlyEntityId == playerWid then
            return true
        end
    end

    if GameData and GameData.Player and GameData.Player.name then
        local friendlyName = TargetInfo:UnitName(c_FRIENDLY_UNIT_ID)
        if friendlyName and friendlyName ~= L"" and friendlyName == GameData.Player.name then
            return true
        end
    end

    return false
end

local function ResolveLiveTarget(unitId)
    if type(CustomUI.TargetPresence) == "table"
        and type(CustomUI.TargetPresence.HasLiveTarget) == "function"
        and type(CustomUI.TargetPresence.GetLiveEntityId) == "function" then
        if CustomUI.TargetPresence.HasLiveTarget(unitId) then
            return true, CustomUI.TargetPresence.GetLiveEntityId(unitId) or 0
        end
        return false, 0
    end

    local entityId = TargetInfo:UnitEntityId(unitId) or 0
    local unitName = TargetInfo:UnitName(unitId)
    if entityId ~= 0 and unitName ~= nil and unitName ~= L"" then
        return true, entityId
    end
    return false, 0
end

-- Self side enabled: permanent player overlay; takes over from Friendly when self is targeted.
local function SelfOverridesFriendlyTarget()
    return SideSettingsActive(CustomUI.TargetHUD.GetSideSettings("self"))
        and IsFriendlyTargetSelf()
end

local function CreateHUDBuffTracker(parentWindowName, buffTargetType, isSelf)
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

    tracker:SetAlignment(CustomUI.BuffTracker.Alignment.CENTER)
    if isSelf then
        CustomUI.BuffTracker.ApplyPlayerStatusRules(tracker)
    else
        tracker:SetFilter({ playerCastOnly = true })
        CustomUI.BuffTracker.ApplySharedDefaultLists(tracker)
        tracker:SetForceShowTrackerPriority100(true)
        tracker:SetSortMode(CustomUI.BuffTracker.SortMode.SHORT_LONG_PERM)
    end
    tracker:SetHandleInput(false)
    tracker:Show(true)
    return tracker
end

local function SyncBuffContainerVisibility(hud)
    if not hud or not hud.buffTracker then return end
    if type(hud.buffTracker._ApplyContainerVisibility) == "function" then
        hud.buffTracker:_ApplyContainerVisibility()
    end
end

local function ApplySideLayout(hud, sideKey)
    if hud == nil or sideKey == nil then
        return
    end
    local sideSettings = CustomUI.TargetHUD.GetSideSettings(sideKey)
    local windowName = hud.windowName
    local showHp = sideSettings.showHealthBar == true
    local showBuffs = sideSettings.showBuffTracker == true

    if DoesWindowExist(windowName .. "TargetName") then
        WindowSetShowing(windowName .. "TargetName", showHp)
    end
    if DoesWindowExist(windowName .. "HealthBar") then
        WindowSetShowing(windowName .. "HealthBar", showHp)
    end

    if hud.buffTracker and DoesWindowExist(windowName .. "Buff") then
        WindowClearAnchors(windowName .. "Buff")
        if showHp then
            WindowAddAnchor(windowName .. "Buff", "bottom", windowName .. "HealthBar", "top", 0, -c_BUFF_ICON_GAP)
        else
            WindowAddAnchor(windowName .. "Buff", "bottom", windowName, "bottom", 0, 0)
        end
        if showBuffs then
            hud.buffTracker:Show(true)
        else
            hud.buffTracker:Clear()
            hud.buffTracker:Show(false)
        end
        SyncBuffContainerVisibility(hud)
    end
end

local function NotifyGroupIconsWorldAttachChanged()
    if type(CustomUI.GroupIcons) == "table"
        and type(CustomUI.GroupIcons.RebindAllTrackedWorldObjects) == "function" then
        CustomUI.GroupIcons.RebindAllTrackedWorldObjects()
    end
end

-- Plain hide when not engine-attached (settings off, lost self wid, etc.).
local function DetachHUD(windowName, hud)
    WindowSetShowing(windowName, false)
    if hud.buffTracker then
        hud.buffTracker:Clear()
        SyncBuffContainerVisibility(hud)
    end
    hud.worldBound = false
    hud.spatialHidden = false
    hud.savedWorldAttachScale = nil
end

--- Component disable: spatial squash (GroupIcons roster pattern) — no engine detach.
local function SpatialHideHUD(hud)
    local windowName = hud.windowName
    if hud.spatialHidden or not DoesWindowExist(windowName) then
        return
    end
    if type(WindowGetScale) == "function" then
        hud.savedWorldAttachScale = WindowGetScale(windowName)
    end
    if WindowSetScale then
        WindowSetScale(windowName, 0.000001)
    end
    WindowSetShowing(windowName, false)
    if hud.buffTracker then
        hud.buffTracker:Clear()
        SyncBuffContainerVisibility(hud)
    end
    hud.spatialHidden = true
end

local function HideHUDForComponentDisable(hud)
    local boundId = hud.attachedId or 0
    if boundId ~= 0 and hud.worldBound then
        SpatialHideHUD(hud)
        return
    end
    DetachHUD(hud.windowName, hud)
end

local function DetachHUDFromEngine(windowName, entityId)
    if entityId == 0 or type(DetachWindowFromWorldObject) ~= "function" then
        return
    end
    CustomUI.TryCallQuiet("TargetHUD.DetachHUDFromEngine", DetachWindowFromWorldObject, windowName, entityId)
end

-- Deselect / no live target: engine detach so the overlay leaves the old world object.
-- Keeps attachedId so the next target can rebind correctly.
local function HideTargetHUD(hud)
    local windowName = hud.windowName
    local boundId = hud.attachedId or 0
    if boundId ~= 0 then
        DetachHUDFromEngine(windowName, boundId)
    end
    WindowSetShowing(windowName, false)
    if hud.buffTracker then
        hud.buffTracker:Clear()
        SyncBuffContainerVisibility(hud)
    end
    hud.worldBound = false
    hud.spatialHidden = false
    hud.savedWorldAttachScale = nil
    NotifyGroupIconsWorldAttachChanged()
end

local function RefreshBuffTrackerAfterAttach(hud, entityId, hadPreviousAttach)
    if not hud.buffTracker then
        return
    end
    local sideKey = hud.sideKey
    local sideSettings = CustomUI.TargetHUD.GetSideSettings(sideKey)
    if sideSettings.showBuffTracker ~= true then
        SyncBuffContainerVisibility(hud)
        return
    end
    SyncBuffContainerVisibility(hud)
    if entityId ~= hadPreviousAttach then
        hud.buffTracker:Clear()
        hud.buffTracker:Refresh(true)
        if hud.buffTracker.m_rebuildPending then
            hud.buffTracker.m_rebuildPending = false
            hud.buffTracker:OnBuffsChanged()
        end
    end
end

-- BuffHead Container:AttachTo — detach previous id, then attach this window to objectId.
local function BindHUDToWorldObject(hud, entityId, previousAttach)
    local windowName = hud.windowName
    if previousAttach ~= 0 then
        DetachHUDFromEngine(windowName, previousAttach)
    end
    if WindowSetScale and DoesWindowExist(windowName) then
        WindowSetScale(windowName, 1.0)
    end
    AttachWindowToWorldObject(windowName, entityId)
    WindowSetShowing(windowName, true)
    if type(ForceUpdateWorldObjectWindow) == "function" then
        CustomUI.TryCallQuiet(
            "TargetHUD.ForceUpdateWorldObjectWindow",
            ForceUpdateWorldObjectWindow,
            entityId,
            windowName
        )
    end
    RefreshBuffTrackerAfterAttach(hud, entityId, previousAttach)
    hud.worldBound = true
    hud.spatialHidden = false
    hud.savedWorldAttachScale = nil
    if not hud.isSelf then
        NotifyGroupIconsWorldAttachChanged()
    end
end

local function UpdateHealthBarDisplay(windowName, hpRounded)
    StatusBarSetCurrentValue(windowName .. "HealthBarBar", hpRounded)
    local healthTextName = windowName .. "HealthBarBarText"
    if DoesWindowExist(healthTextName) then
        LabelSetText(healthTextName, towstring(hpRounded) .. L"%")
        WindowSetShowing(healthTextName, true)
    end
end

local function AttachHUDToEntity(hud, windowName, entityId)
    local previousAttach = hud.attachedId or 0
    if entityId == previousAttach and hud.worldBound and not hud.spatialHidden
        and DoesWindowExist(windowName) and WindowGetShowing(windowName) then
        return entityId
    end
    BindHUDToWorldObject(hud, entityId, previousAttach)
    return entityId
end

-- Self: BuffHead AttachTo every forced rebind. A failed first attach used to set
-- worldBound=true and then skip forever, leaving the HUD at screen origin.
local function AttachSelfHUDToEntity(hud, windowName, entityId, forceRebind)
    if forceRebind == true then
        BindHUDToWorldObject(hud, entityId, hud.attachedId or 0)
        return entityId
    end
    return AttachHUDToEntity(hud, windowName, entityId)
end

local function UpdateTargetSideHealthOnly(hud)
    local sideSettings = CustomUI.TargetHUD.GetSideSettings(hud.sideKey)
    if sideSettings.showHealthBar ~= true then
        return
    end
    local hp = tonumber(TargetInfo:UnitHealth(hud.unitId)) or 0
    if hp < 0 then
        hp = 0
    elseif hp > 100 then
        hp = 100
    end
    UpdateHealthBarDisplay(hud.windowName, math.floor(hp + 0.5))
end

local function RefreshTargetSideFromEvent(hud)
    if not hud or not m_enabled then
        return
    end
    local sideSettings = CustomUI.TargetHUD.GetSideSettings(hud.sideKey)
    if not SideSettingsActive(sideSettings) then
        HideTargetHUD(hud)
        return
    end
    if hud.sideKey == "friendly" and SelfOverridesFriendlyTarget() then
        HideTargetHUD(hud)
        return
    end
    local hasLive, liveId = ResolveLiveTarget(hud.unitId)
    if not hasLive or liveId == 0 then
        HideTargetHUD(hud)
        return
    end
    -- HP/status ticks can arrive while TargetInfo still holds the old target briefly after
    -- deselect; never re-attach from those events — only PLAYER_TARGET_UPDATED does that.
    if not hud.worldBound then
        return
    end
    if hud.attachedId ~= liveId then
        hud.attachedId = RefreshTargetHUDFromCache(hud) or hud.attachedId or 0
        return
    end
    UpdateTargetSideHealthOnly(hud)
end

-- Drives target HUD visuals from live TargetInfo (no transient TargetPresence hold).
local function RefreshTargetHUDFromCache(hud)
    local sideKey = hud.sideKey
    local windowName = hud.windowName
    local sideSettings = CustomUI.TargetHUD.GetSideSettings(sideKey)

    if not m_enabled or not SideSettingsActive(sideSettings) then
        HideTargetHUD(hud)
        return hud.attachedId or 0
    end

    if sideKey == "friendly" and SelfOverridesFriendlyTarget() then
        HideTargetHUD(hud)
        return hud.attachedId or 0
    end

    local hasTarget, entityId = ResolveLiveTarget(hud.unitId)

    if not hasTarget or entityId == 0 then
        HideTargetHUD(hud)
        return hud.attachedId or 0
    end

    ApplySideLayout(hud, sideKey)

    if sideSettings.showHealthBar == true then
        local hp = tonumber(TargetInfo:UnitHealth(hud.unitId)) or 0
        if hp < 0 then
            hp = 0
        elseif hp > 100 then
            hp = 100
        end
        UpdateHealthBarDisplay(windowName, math.floor(hp + 0.5))

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
    end

    hud.attachedId = AttachHUDToEntity(hud, windowName, entityId)
    return hud.attachedId
end

local function RefreshSelfHUDFromCache(hud, forceRebind)
    local windowName = hud.windowName
    local sideSettings = CustomUI.TargetHUD.GetSideSettings("self")

    if not m_enabled or not SideSettingsActive(sideSettings) then
        if hud.attachedId ~= 0 then
            HideTargetHUD(hud)
        end
        return 0
    end

    local entityId = GetPlayerWorldObjNum()
    if entityId == 0 then
        if hud.attachedId ~= 0 then
            HideTargetHUD(hud)
        end
        return 0
    end

    ApplySideLayout(hud, "self")

    if sideSettings.showHealthBar == true and GameData and GameData.Player then
        local hpCur = tonumber(GameData.Player.hitPoints and GameData.Player.hitPoints.current) or 0
        local hpMax = tonumber(GameData.Player.hitPoints and GameData.Player.hitPoints.maximum) or 1
        if hpMax <= 0 then
            hpMax = 1
        end
        local hp = (hpCur / hpMax) * 100
        if hp < 0 then
            hp = 0
        elseif hp > 100 then
            hp = 100
        end
        UpdateHealthBarDisplay(windowName, math.floor(hp + 0.5))

        local unitName  = GameData.Player.name or L""
        local unitLevel = GameData.Player.level or 0
        local careerLine = GameData.Player.career and GameData.Player.career.line or 0
        local iconNum = (careerLine and careerLine ~= 0) and Icons.GetCareerIconIDFromCareerLine(careerLine) or nil

        local nameText
        if iconNum then
            nameText = L"<icon" .. towstring(iconNum) .. L"> " .. unitName .. L" (" .. towstring(unitLevel) .. L")"
        else
            nameText = unitName .. L" (" .. towstring(unitLevel) .. L")"
        end

        local labelName = windowName .. "TargetName"
        WindowSetShowing(labelName, true)
        LabelSetText(labelName, nameText)
        LabelSetTextColor(labelName, 50, 200, 50)
    end

    hud.attachedId = AttachSelfHUDToEntity(hud, windowName, entityId, forceRebind)
    return hud.attachedId
end

local function RefreshHUDFromCache(hud)
    if hud.isSelf then
        return RefreshSelfHUDFromCache(hud)
    end
    return RefreshTargetHUDFromCache(hud)
end

local function RefreshAllHUDsFromCache()
    for i = 1, #c_SIDE_KEYS do
        local sideKey = c_SIDE_KEYS[i]
        local hud = m_sides[sideKey]
        if hud then
            hud.attachedId = RefreshHUDFromCache(hud) or 0
        end
    end
end

local function RegisterTargetHandlers()
    if m_handlersRegistered then return end
    DebugLog("RegisterTargetHandlers")
    WindowRegisterEventHandler(c_HOSTILE_WINDOW_NAME, SystemData.Events.PLAYER_TARGET_UPDATED, "CustomUI.TargetHUD.OnPlayerTargetUpdated")
    WindowRegisterEventHandler(c_HOSTILE_WINDOW_NAME,  SystemData.Events.PLAYER_TARGET_STATE_UPDATED,   "CustomUI.TargetHUD.OnHostileStateUpdated")
    WindowRegisterEventHandler(c_FRIENDLY_WINDOW_NAME, SystemData.Events.PLAYER_TARGET_STATE_UPDATED,   "CustomUI.TargetHUD.OnFriendlyStateUpdated")
    WindowRegisterEventHandler(c_HOSTILE_WINDOW_NAME,  SystemData.Events.PLAYER_TARGET_EFFECTS_UPDATED, "CustomUI.TargetHUD.OnHostileEffectsUpdated")
    WindowRegisterEventHandler(c_FRIENDLY_WINDOW_NAME, SystemData.Events.PLAYER_TARGET_EFFECTS_UPDATED, "CustomUI.TargetHUD.OnFriendlyEffectsUpdated")
    m_handlersRegistered = true
end

local function UnregisterTargetHandlers()
    if not m_handlersRegistered then return end
    local e = SystemData.Events
    WindowUnregisterEventHandler(c_HOSTILE_WINDOW_NAME, e.PLAYER_TARGET_UPDATED)
    WindowUnregisterEventHandler(c_HOSTILE_WINDOW_NAME, e.PLAYER_TARGET_STATE_UPDATED)
    WindowUnregisterEventHandler(c_FRIENDLY_WINDOW_NAME, e.PLAYER_TARGET_STATE_UPDATED)
    WindowUnregisterEventHandler(c_HOSTILE_WINDOW_NAME, e.PLAYER_TARGET_EFFECTS_UPDATED)
    WindowUnregisterEventHandler(c_FRIENDLY_WINDOW_NAME, e.PLAYER_TARGET_EFFECTS_UPDATED)
    m_handlersRegistered = false
end

local function RegisterSelfGlobalHandlers()
    if m_selfGlobalHandlersRegistered or type(RegisterEventHandler) ~= "function" then
        return
    end
    local e = SystemData.Events
    RegisterEventHandler(e.LOADING_END, "CustomUI.TargetHUD.OnSelfWorldUpdated")
    RegisterEventHandler(e.ENTER_WORLD, "CustomUI.TargetHUD.OnSelfWorldUpdated")
    RegisterEventHandler(e.INTERFACE_RELOADED, "CustomUI.TargetHUD.OnSelfWorldUpdated")
    RegisterEventHandler(e.PLAYER_ZONE_CHANGED, "CustomUI.TargetHUD.OnSelfWorldUpdated")
    m_selfGlobalHandlersRegistered = true
end

local function UnregisterSelfGlobalHandlers()
    if not m_selfGlobalHandlersRegistered or type(UnregisterEventHandler) ~= "function" then
        m_selfGlobalHandlersRegistered = false
        return
    end
    local e = SystemData.Events
    CustomUI.TryCallQuiet("TargetHUD.UnregLoadingEnd", UnregisterEventHandler, e.LOADING_END, "CustomUI.TargetHUD.OnSelfWorldUpdated")
    CustomUI.TryCallQuiet("TargetHUD.UnregEnterWorld", UnregisterEventHandler, e.ENTER_WORLD, "CustomUI.TargetHUD.OnSelfWorldUpdated")
    CustomUI.TryCallQuiet("TargetHUD.UnregInterfaceReloaded", UnregisterEventHandler, e.INTERFACE_RELOADED, "CustomUI.TargetHUD.OnSelfWorldUpdated")
    CustomUI.TryCallQuiet("TargetHUD.UnregZoneChanged", UnregisterEventHandler, e.PLAYER_ZONE_CHANGED, "CustomUI.TargetHUD.OnSelfWorldUpdated")
    m_selfGlobalHandlersRegistered = false
end

local function RegisterSelfHandlers()
    RegisterSelfGlobalHandlers()
    if m_selfHandlersRegistered then return end
    if not DoesWindowExist(c_SELF_WINDOW_NAME) then
        return
    end
    local e = SystemData.Events
    WindowRegisterEventHandler(c_SELF_WINDOW_NAME, e.PLAYER_CUR_HIT_POINTS_UPDATED, "CustomUI.TargetHUD.OnSelfHealthUpdated")
    WindowRegisterEventHandler(c_SELF_WINDOW_NAME, e.PLAYER_MAX_HIT_POINTS_UPDATED, "CustomUI.TargetHUD.OnSelfHealthUpdated")
    WindowRegisterEventHandler(c_SELF_WINDOW_NAME, e.PLAYER_EFFECTS_UPDATED,        "CustomUI.TargetHUD.OnSelfEffectsUpdated")
    m_selfHandlersRegistered = true
end

local function UnregisterSelfHandlers()
    UnregisterSelfGlobalHandlers()
    if not m_selfHandlersRegistered then return end
    if DoesWindowExist(c_SELF_WINDOW_NAME) then
        local e = SystemData.Events
        WindowUnregisterEventHandler(c_SELF_WINDOW_NAME, e.PLAYER_CUR_HIT_POINTS_UPDATED)
        WindowUnregisterEventHandler(c_SELF_WINDOW_NAME, e.PLAYER_MAX_HIT_POINTS_UPDATED)
        WindowUnregisterEventHandler(c_SELF_WINDOW_NAME, e.PLAYER_EFFECTS_UPDATED)
    end
    m_selfHandlersRegistered = false
end

local function RegisterHandlers()
    RegisterTargetHandlers()
    RegisterSelfHandlers()
end

local function UnregisterHandlers()
    UnregisterTargetHandlers()
    UnregisterSelfHandlers()
end

local function EnsureSideWindow(windowName)
    if DoesWindowExist(windowName) and not SideWindowHasTemplateStructure(windowName) then
        DestroyWindow(windowName)
    end
    if not DoesWindowExist(windowName) then
        CreateWindowFromTemplate(windowName, "CustomUITargetHUDTemplate", "Root")
    end
    WindowSetShowing(windowName, false)
end

-- BuffHead Container:Create — runtime CreateWindowFromTemplate under Root, then attach.
local function EnsureSelfSideWindow(hud)
    local windowName = hud.windowName
    if DoesWindowExist(windowName) then
        DestroyWindow(windowName)
    end
    CreateWindowFromTemplate(windowName, "CustomUITargetHUDTemplate", "Root")
    WindowSetShowing(windowName, false)
end

local function InitSideRuntime(sideKey, def)
    local hud = {
        sideKey      = sideKey,
        windowName   = def.windowName,
        unitId       = def.unitId,
        isSelf       = def.isSelf == true,
        attachedId   = 0,
        worldBound   = false,
        spatialHidden = false,
        savedWorldAttachScale = nil,
        buffTracker  = nil,
    }
    m_sides[sideKey] = hud

    if def.isSelf then
        EnsureSelfSideWindow(hud)
    else
        EnsureSideWindow(def.windowName)
    end

    if def.isSelf then
        StatusBarSetMaximumValue(def.windowName .. "HealthBarBar", 100)
        StatusBarSetForegroundTint(def.windowName .. "HealthBarBar", 50, 200, 50)
    else
        StatusBarSetMaximumValue(def.windowName .. "HealthBarBar", 100)
        if sideKey == "hostile" then
            StatusBarSetForegroundTint(def.windowName .. "HealthBarBar", 200, 50, 50)
        else
            StatusBarSetForegroundTint(def.windowName .. "HealthBarBar", 50, 200, 50)
        end
    end
    StatusBarSetBackgroundTint(def.windowName .. "HealthBarBar", 0, 0, 0)

    if DoesWindowExist(def.windowName .. "HealthBarBarText") then
        LabelSetText(def.windowName .. "HealthBarBarText", L"")
        WindowSetShowing(def.windowName .. "HealthBarBarText", false)
    end

    hud.buffTracker = CreateHUDBuffTracker(def.windowName, def.buffTargetType, def.isSelf)
    ApplySideLayout(hud, sideKey)
    return hud
end

----------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------

function CustomUI.TargetHUD.Initialize()
    if m_initialized then return end

    local sideDefs = {
        hostile = {
            windowName     = c_HOSTILE_WINDOW_NAME,
            unitId         = c_HOSTILE_UNIT_ID,
            isSelf         = false,
            buffTargetType = GameData.BuffTargetType.TARGET_HOSTILE,
        },
        friendly = {
            windowName     = c_FRIENDLY_WINDOW_NAME,
            unitId         = c_FRIENDLY_UNIT_ID,
            isSelf         = false,
            buffTargetType = GameData.BuffTargetType.TARGET_FRIENDLY,
        },
        self = {
            windowName     = c_SELF_WINDOW_NAME,
            unitId         = nil,
            isSelf         = true,
            buffTargetType = GameData.BuffTargetType.SELF,
        },
    }

    local allTrackersOk = true
    for i = 1, #c_SIDE_KEYS do
        local sideKey = c_SIDE_KEYS[i]
        local hud = InitSideRuntime(sideKey, sideDefs[sideKey])
        if not hud.buffTracker then
            allTrackersOk = false
        end
    end

    if not allTrackersOk then
        for i = 1, #c_SIDE_KEYS do
            local hud = m_sides[c_SIDE_KEYS[i]]
            if hud and hud.buffTracker then
                hud.buffTracker:Shutdown()
                hud.buffTracker = nil
            end
        end
        return
    end

    CustomUI.TargetHUD.ApplySettings()

    m_initialized = true
end

function CustomUI.TargetHUD.Shutdown()
    if type(CustomUI.TargetPresence) == "table"
        and type(CustomUI.TargetPresence.Release) == "function" then
        CustomUI.TargetPresence.Release(c_TARGET_PRESENCE_CONSUMER)
    end
    UnregisterHandlers()

    for i = 1, #c_SIDE_KEYS do
        local hud = m_sides[c_SIDE_KEYS[i]]
        if hud then
            if hud.buffTracker then
                hud.buffTracker:Shutdown()
                hud.buffTracker = nil
            end
            if DoesWindowExist(hud.windowName) then
                WindowSetShowing(hud.windowName, false)
            end
            hud.attachedId = 0
        end
    end

    m_enabled     = false
    m_initialized = false
end

----------------------------------------------------------------

function CustomUI.TargetHUD.GetSettings()
    CustomUI.Settings.TargetHUD = CustomUI.Settings.TargetHUD or {}
    if type(CustomUI.BuffTracker.EnsureTargetHUDSettings) == "function" then
        return CustomUI.BuffTracker.EnsureTargetHUDSettings(CustomUI.Settings.TargetHUD)
    end
    return CustomUI.Settings.TargetHUD
end

function CustomUI.TargetHUD.GetSideSettings(sideKey)
    return CustomUI.TargetHUD.GetSettings()[sideKey]
end

function CustomUI.TargetHUD.GetBuffFilterHostile()
    return CustomUI.TargetHUD.GetSideSettings("hostile").buffs
end

function CustomUI.TargetHUD.GetBuffFilterFriendly()
    return CustomUI.TargetHUD.GetSideSettings("friendly").buffs
end

function CustomUI.TargetHUD.GetBuffFilterSelf()
    return CustomUI.TargetHUD.GetSideSettings("self").buffs
end

function CustomUI.TargetHUD.ApplySettings()
    for i = 1, #c_SIDE_KEYS do
        local sideKey = c_SIDE_KEYS[i]
        local hud = m_sides[sideKey]
        if hud then
            ApplySideLayout(hud, sideKey)
            if hud.buffTracker then
                hud.buffTracker:SetFilter(CustomUI.TargetHUD.GetSideSettings(sideKey).buffs)
            end
        end
    end
    if m_enabled then
        RefreshAllHUDsFromCache()
    end
end

function CustomUI.TargetHUD.ApplyBuffSettings()
    CustomUI.TargetHUD.ApplySettings()
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

    local refreshHostile = targetClassification == nil
        or targetClassification == TargetInfo.HOSTILE_TARGET
    local refreshFriendly = targetClassification == nil
        or targetClassification == TargetInfo.FRIENDLY_TARGET

    if type(CustomUI.TargetPresence) == "table"
        and type(CustomUI.TargetPresence.RefreshFromEvent) == "function" then
        CustomUI.TargetPresence.RefreshFromEvent(targetClassification, targetId)
    else
        if type(CustomUI.TargetPresence) == "table"
            and type(CustomUI.TargetPresence.NoteTargetEvent) == "function" then
            CustomUI.TargetPresence.NoteTargetEvent(targetClassification, targetId)
        end
        TargetInfo:UpdateFromClient()
        if type(CustomUI.TargetPresence) == "table"
            and type(CustomUI.TargetPresence.OnTargetRefreshComplete) == "function" then
            CustomUI.TargetPresence.OnTargetRefreshComplete(targetClassification)
        end
    end

    if refreshHostile then
        local hud = m_sides.hostile
        if hud then
            hud.attachedId = RefreshHUDFromCache(hud) or hud.attachedId or 0
        end
    end
    if refreshFriendly then
        local hud = m_sides.friendly
        if hud then
            hud.attachedId = RefreshHUDFromCache(hud) or hud.attachedId or 0
        end
    end
    local selfHud = m_sides.self
    if selfHud then
        RefreshSelfHUDFromCache(selfHud, true)
    end
end

function CustomUI.TargetHUD.OnHostileStateUpdated()
    RefreshTargetSideFromEvent(m_sides.hostile)
end

function CustomUI.TargetHUD.OnFriendlyStateUpdated()
    RefreshTargetSideFromEvent(m_sides.friendly)
end

function CustomUI.TargetHUD.OnHostileEffectsUpdated(updateType, updatedEffects, isFullList)
    local hud = m_sides.hostile
    local sideSettings = CustomUI.TargetHUD.GetSideSettings("hostile")
    if not hud or not hud.worldBound
        or updateType ~= GameData.BuffTargetType.TARGET_HOSTILE
        or not hud.buffTracker
        or sideSettings.showBuffTracker ~= true
    then
        return
    end
    hud.buffTracker:UpdateBuffs(updatedEffects, isFullList)
    SyncBuffContainerVisibility(hud)
    if hud.buffTracker.m_rebuildPending then
        hud.buffTracker.m_rebuildPending = false
        hud.buffTracker:OnBuffsChanged()
    end
end

function CustomUI.TargetHUD.OnFriendlyEffectsUpdated(updateType, updatedEffects, isFullList)
    if SelfOverridesFriendlyTarget() then
        return
    end
    local hud = m_sides.friendly
    local sideSettings = CustomUI.TargetHUD.GetSideSettings("friendly")
    if not hud or not hud.worldBound
        or updateType ~= GameData.BuffTargetType.TARGET_FRIENDLY
        or not hud.buffTracker
        or sideSettings.showBuffTracker ~= true
    then
        return
    end
    hud.buffTracker:UpdateBuffs(updatedEffects, isFullList)
    SyncBuffContainerVisibility(hud)
    if hud.buffTracker.m_rebuildPending then
        hud.buffTracker.m_rebuildPending = false
        hud.buffTracker:OnBuffsChanged()
    end
end

function CustomUI.TargetHUD.OnUpdate(timePassed)
    if not m_enabled then return end
    local wn = SystemData.ActiveWindow.name
    local hud = nil
    if wn == c_HOSTILE_WINDOW_NAME then
        hud = m_sides.hostile
    elseif wn == c_FRIENDLY_WINDOW_NAME then
        hud = m_sides.friendly
    elseif wn == c_SELF_WINDOW_NAME then
        hud = m_sides.self
    end
    if hud and hud.buffTracker then
        hud.buffTracker:Update(timePassed)
    end
end

function CustomUI.TargetHUD.OnSelfHealthUpdated()
    local hud = m_sides.self
    if hud then
        RefreshHUDFromCache(hud)
    end
end

function CustomUI.TargetHUD.OnSelfWorldUpdated()
    RequestSelfAttachRetry(c_SELF_ATTACH_GRACE_SECONDS)
    local hud = m_sides.self
    if hud then
        RefreshSelfHUDFromCache(hud, true)
    end
end

function CustomUI.TargetHUD.OnSelfEffectsUpdated(updatedEffects, isFullList)
    local hud = m_sides.self
    local sideSettings = CustomUI.TargetHUD.GetSideSettings("self")
    if hud and hud.buffTracker and sideSettings.showBuffTracker == true then
        hud.buffTracker:UpdateBuffs(updatedEffects, isFullList)
        SyncBuffContainerVisibility(hud)
        if hud.buffTracker.m_rebuildPending then
            hud.buffTracker.m_rebuildPending = false
            hud.buffTracker:OnBuffsChanged()
        end
    end
end

function CustomUI.TargetHUD.OnGlobalUpdate(timePassed)
    if not m_enabled then
        return
    end

    local hud = m_sides.self
    if not hud then
        return
    end
    if not SideSettingsActive(CustomUI.TargetHUD.GetSideSettings("self")) then
        return
    end

    if m_selfAttachGraceTimer > 0 then
        m_selfAttachGraceTimer = m_selfAttachGraceTimer - timePassed
    end

    local wid = GetPlayerWorldObjNum()
    if wid == 0 then
        return
    end

    local windowName = hud.windowName
    local showing = DoesWindowExist(windowName) and WindowGetShowing(windowName)
    local needsAttach = (hud.attachedId ~= wid) or not hud.worldBound or not showing
    local graceRetry = m_selfAttachGraceTimer > 0

    if not needsAttach and not graceRetry then
        return
    end

    m_selfAttachPollTimer = m_selfAttachPollTimer - timePassed
    if needsAttach or m_selfAttachPollTimer <= 0 then
        m_selfAttachPollTimer = c_SELF_ATTACH_POLL_INTERVAL
        RefreshSelfHUDFromCache(hud, true)
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

    local trackersOk = true
    for i = 1, #c_SIDE_KEYS do
        local hud = m_sides[c_SIDE_KEYS[i]]
        if not hud or not hud.buffTracker then
            trackersOk = false
            break
        end
    end
    if not trackersOk then
        return false
    end

    m_enabled = true
    RequestSelfAttachRetry(c_SELF_ATTACH_GRACE_SECONDS)
    if type(CustomUI.TargetPresence) == "table"
        and type(CustomUI.TargetPresence.Acquire) == "function" then
        CustomUI.TargetPresence.Acquire(c_TARGET_PRESENCE_CONSUMER)
    end
    RegisterHandlers()
    for i = 1, #c_SIDE_KEYS do
        local hud = m_sides[c_SIDE_KEYS[i]]
        if hud and hud.spatialHidden then
            hud.spatialHidden = false
            hud.savedWorldAttachScale = nil
        end
    end
    CustomUI.TargetHUD.ApplySettings()
    RefreshAllHUDsFromCache()

    local selfHud = m_sides.self
    if selfHud then
        RefreshSelfHUDFromCache(selfHud, true)
        if selfHud.buffTracker and type(selfHud.buffTracker.Refresh) == "function" then
            selfHud.buffTracker:Refresh(true)
        end
    end
    return true
end

function TargetHUDComponent:Disable()
    m_enabled = false
    m_selfAttachPollTimer = 0
    m_selfAttachGraceTimer = 0
    if type(CustomUI.TargetPresence) == "table"
        and type(CustomUI.TargetPresence.Release) == "function" then
        CustomUI.TargetPresence.Release(c_TARGET_PRESENCE_CONSUMER)
    end
    UnregisterHandlers()
    for i = 1, #c_SIDE_KEYS do
        local hud = m_sides[c_SIDE_KEYS[i]]
        if hud then
            HideHUDForComponentDisable(hud)
        end
    end
    return true
end

function TargetHUDComponent:ResetToDefaults()
    return true
end

function TargetHUDComponent:Shutdown()
    CustomUI.TargetHUD.Shutdown()
end
CustomUI.RegisterComponent("TargetHUD", TargetHUDComponent)
