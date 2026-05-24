----------------------------------------------------------------
-- CustomUI.TargetPresence
-- Stabilizes hostile/friendly target UI across transient TargetInfo gaps.
-- Does not call TargetInfo:UpdateFromClient() (see CustomUI HookTargetInfo).
----------------------------------------------------------------

if not CustomUI then
    CustomUI = {}
end

CustomUI.TargetPresence = CustomUI.TargetPresence or {}

local TP = CustomUI.TargetPresence

local c_HOSTILE_UNIT_ID  = TargetInfo and TargetInfo.HOSTILE_TARGET  or "selfhostiletarget"
local c_FRIENDLY_UNIT_ID = TargetInfo and TargetInfo.FRIENDLY_TARGET or "selffriendlytarget"

local c_EMPTY_STREAK_HIDE = 3
local c_MAX_HOLD_SECONDS  = 2.5

TP.m_slots = TP.m_slots or {
    [c_HOSTILE_UNIT_ID]  = { lastEntityId = 0, emptyStreak = 0, holdSeconds = 0, snapshot = nil },
    [c_FRIENDLY_UNIT_ID] = { lastEntityId = 0, emptyStreak = 0, holdSeconds = 0, snapshot = nil },
}

----------------------------------------------------------------
-- Local helpers
----------------------------------------------------------------

local function IsKnownUnitId(unitId)
    return unitId == c_HOSTILE_UNIT_ID or unitId == c_FRIENDLY_UNIT_ID
end

local function GetSlot(unitId)
    if not IsKnownUnitId(unitId) then
        return nil
    end
    return TP.m_slots[unitId]
end

local function ReadCacheName(unitId)
    if type(TargetInfo) ~= "table" or type(TargetInfo.UnitName) ~= "function" then
        return L""
    end
    return TargetInfo:UnitName(unitId) or L""
end

local function CopySnapshot(targetData)
    if type(targetData) ~= "table" then
        return nil
    end
    local entityId = targetData.entityid
    if entityId == nil or entityId == 0 then
        return nil
    end
    local name = targetData.name
    if name == nil or name == L"" then
        return nil
    end
    local copy = {}
    for k, v in pairs(targetData) do
        copy[k] = v
    end
    return copy
end

local function ReadCacheEntityId(unitId)
    if type(TargetInfo) ~= "table" or type(TargetInfo.UnitEntityId) ~= "function" then
        return 0
    end
    local entityId = TargetInfo:UnitEntityId(unitId)
    if entityId == nil then
        return 0
    end
    return entityId
end

-- Match stock TargetUnitFrame: a target without a name is treated as no target.
local function CacheLooksPresent(unitId)
    if ReadCacheEntityId(unitId) == 0 then
        return false
    end
    return ReadCacheName(unitId) ~= L""
end

local function SlotLooksEmptyInCache(unitId)
    return ReadCacheEntityId(unitId) == 0 or ReadCacheName(unitId) == L""
end

function TP.ClearTargetInfoSlot(unitId)
    if not IsKnownUnitId(unitId) then
        return
    end
    if type(TargetInfo) ~= "table" or type(TargetInfo.SetUnitInfo) ~= "function" then
        return
    end
    TargetInfo:SetUnitInfo(unitId, { entityid = 0, name = L"", healthPercent = 0 })
end

local function ForceClearSlot(unitId)
    local slot = GetSlot(unitId)
    if not slot then
        return
    end
    slot.lastEntityId = 0
    slot.emptyStreak = 0
    slot.holdSeconds = 0
    slot.snapshot = nil
    TP.ClearTargetInfoSlot(unitId)
end

local function ApplyGoodCache(slot, unitId)
    local entityId = ReadCacheEntityId(unitId)
    if entityId == 0 then
        return false
    end

    local unitData = TargetInfo and TargetInfo.m_Units and TargetInfo.m_Units[unitId]
    if type(unitData) == "table" then
        slot.snapshot = CopySnapshot(unitData)
    end
    slot.lastEntityId = entityId
    slot.emptyStreak = 0
    slot.holdSeconds = 0
    return true
end

local function CanHoldTransient(slot)
    if slot.lastEntityId == 0 or not slot.snapshot then
        return false
    end
    if (slot.emptyStreak or 0) >= c_EMPTY_STREAK_HIDE then
        return false
    end
    if (slot.holdSeconds or 0) >= c_MAX_HOLD_SECONDS then
        return false
    end
    return true
end

----------------------------------------------------------------
-- Public API
----------------------------------------------------------------

function TP.Reset()
    ForceClearSlot(c_HOSTILE_UNIT_ID)
    ForceClearSlot(c_FRIENDLY_UNIT_ID)
end

function TP.ResetSlot(unitId)
    if IsKnownUnitId(unitId) then
        ForceClearSlot(unitId)
    end
end

--- Called from PLAYER_TARGET_UPDATED before TargetInfo:UpdateFromClient().
--- Do not clear on targetId==0; that value is often wrong during HP/status ticks (see NerfedButtons).
function TP.NoteTargetEvent(targetClassification, targetId)
    if not IsKnownUnitId(targetClassification) then
        return
    end

    if targetId ~= nil and targetId ~= 0 then
        local slot = GetSlot(targetClassification)
        slot.lastEntityId = targetId
        slot.emptyStreak = 0
        slot.holdSeconds = 0
    end
end

--- Merge engine batch into presence state (called from hooked UpdateFromClient).
function TP.OnCacheBatch(targets)
    if type(targets) ~= "table" then
        return
    end

    for unitId, targetData in pairs(targets) do
        if IsKnownUnitId(unitId) then
            local entityId = targetData and targetData.entityid or 0
            local name = targetData and targetData.name or L""
            if entityId == nil or entityId == 0 or name == nil or name == L"" then
                ForceClearSlot(unitId)
            else
                local slot = GetSlot(unitId)
                slot.snapshot = CopySnapshot(targetData)
                slot.lastEntityId = entityId
                slot.emptyStreak = 0
                slot.holdSeconds = 0
            end
        end
    end
end

--- After UpdateFromClient, reconcile slots that lost their target in the cache.
function TP.OnTargetRefreshComplete(targetClassification)
    local unitIds = {}
    if IsKnownUnitId(targetClassification) then
        table.insert(unitIds, targetClassification)
    else
        unitIds = { c_HOSTILE_UNIT_ID, c_FRIENDLY_UNIT_ID }
    end

    for i = 1, #unitIds do
        local unitId = unitIds[i]
        if SlotLooksEmptyInCache(unitId) then
            ForceClearSlot(unitId)
        elseif CacheLooksPresent(unitId) then
            ApplyGoodCache(GetSlot(unitId), unitId)
        else
            local slot = GetSlot(unitId)
            if not CanHoldTransient(slot) then
                ForceClearSlot(unitId)
            end
        end
    end
end

--- Read current TargetInfo without consuming GetUpdatedTargets().
function TP.SyncFromTargetInfo(unitId)
    local slot = GetSlot(unitId)
    if not slot then
        return
    end

    if CacheLooksPresent(unitId) then
        ApplyGoodCache(slot, unitId)
        return
    end

    slot.emptyStreak = (slot.emptyStreak or 0) + 1
    if not CanHoldTransient(slot) then
        ForceClearSlot(unitId)
    end
end

--- Restore a held snapshot only during a short transient cache gap (not after deselect).
function TP.InjectCacheIfHeld(unitId)
    local slot = GetSlot(unitId)
    if not slot or not CanHoldTransient(slot) then
        return false
    end
    if CacheLooksPresent(unitId) then
        return false
    end
    if type(TargetInfo) ~= "table" or type(TargetInfo.SetUnitInfo) ~= "function" then
        return false
    end
    TargetInfo:SetUnitInfo(unitId, slot.snapshot)
    return true
end

--- Whether the UI should treat this slot as having a target.
function TP.ShouldShow(unitId)
    local slot = GetSlot(unitId)
    if not slot then
        return false
    end

    if CacheLooksPresent(unitId) then
        return ApplyGoodCache(slot, unitId)
    end

    if slot.lastEntityId == 0 then
        return false
    end

    return CanHoldTransient(slot)
end

function TP.GetEntityId(unitId)
    if not TP.ShouldShow(unitId) then
        return 0
    end

    local cacheId = ReadCacheEntityId(unitId)
    if cacheId ~= 0 then
        return cacheId
    end

    local slot = GetSlot(unitId)
    return slot and slot.lastEntityId or 0
end

function TP.StabilizeFrame(frame, unitId)
    if not frame or type(frame.Show) ~= "function" or type(frame.IsShowing) ~= "function" then
        return
    end

    local shouldShow = TP.ShouldShow(unitId)
    local isShowing = frame:IsShowing()

    if shouldShow and not isShowing then
        TP.InjectCacheIfHeld(unitId)
        if type(frame.UpdateUnit) == "function" then
            frame:UpdateUnit()
        else
            frame:Show(true, Frame.FORCE_OVERRIDE)
        end
        return
    end

    if not shouldShow and isShowing then
        frame:Show(false, Frame.FORCE_OVERRIDE)
    end
end

function TP.OnGlobalUpdate(timePassed)
    if not timePassed or timePassed <= 0 then
        return
    end

    for _, unitId in ipairs({ c_HOSTILE_UNIT_ID, c_FRIENDLY_UNIT_ID }) do
        local slot = GetSlot(unitId)
        if slot.lastEntityId ~= 0 and not CacheLooksPresent(unitId) then
            slot.holdSeconds = (slot.holdSeconds or 0) + timePassed
            if not CanHoldTransient(slot) then
                ForceClearSlot(unitId)
            end
        end
    end
end
