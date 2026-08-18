----------------------------------------------------------------
-- CustomUI.GroupIcons.OutsiderTracker
--
-- Outsider tracking helpers for GroupIcons. The controller continues to own
-- event routing and timer pacing; this module owns outsider slot bookkeeping,
-- eviction, and prune/validation passes.
----------------------------------------------------------------

if not CustomUI then
    CustomUI = {}
end

CustomUI.GroupIcons = CustomUI.GroupIcons or {}
CustomUI.GroupIcons.OutsiderTracker = CustomUI.GroupIcons.OutsiderTracker or {}

local OutsiderTracker = CustomUI.GroupIcons.OutsiderTracker

function OutsiderTracker.BuildActiveTargetEntityIdGuard()
    local guard = {}
    if not TargetInfo then
        return guard
    end

    local function addIfPlayerSlot(unitId)
        if not unitId then
            return
        end
        if TargetInfo:UnitName(unitId) == L"" then
            return
        end
        local unitType = TargetInfo:UnitType(unitId)
        if unitType ~= SystemData.TargetObjectType.ENEMY_PLAYER
            and unitType ~= SystemData.TargetObjectType.ALLY_PLAYER
        then
            return
        end
        local entityId = TargetInfo:UnitEntityId(unitId)
        if entityId and entityId ~= 0 then
            guard[entityId] = true
        end
    end

    addIfPlayerSlot(TargetInfo.HOSTILE_TARGET)
    addIfPlayerSlot(TargetInfo.FRIENDLY_TARGET)
    return guard
end

function OutsiderTracker.TrackFifoRemove(state, wid)
    for i = 1, #state.trackFIFOOrder do
        if state.trackFIFOOrder[i] == wid then
            table.remove(state.trackFIFOOrder, i)
            return
        end
    end
end

function OutsiderTracker.PickFifoEvictionVictim(state, protected)
    for i = 1, #state.trackFIFOOrder do
        local wid = state.trackFIFOOrder[i]
        if not protected[wid] then
            return wid
        end
    end
    return nil
end

function OutsiderTracker.UntrackWid(state, wid)
    OutsiderTracker.TrackFifoRemove(state, wid)
    local idx = state.trackWidToSlot[wid]
    if not idx then
        return false
    end

    state.trackWidToSlot[wid] = nil
    state.trackMeta[wid] = nil
    state.slotOccupantWid[idx] = nil

    local icon = state.outsiderPool[idx]
    if icon then
        icon:Disable()
    end
    return true
end

function OutsiderTracker.UntrackAll(state)
    local wids = {}
    for wid in pairs(state.trackWidToSlot) do
        wids[#wids + 1] = wid
    end
    for i = 1, #wids do
        OutsiderTracker.UntrackWid(state, wids[i])
    end
    for i = #state.trackFIFOOrder, 1, -1 do
        state.trackFIFOOrder[i] = nil
    end
end

function OutsiderTracker.TryTrack(state, wid, playerName, career, opts)
    if not wid or wid == 0 then
        return false
    end

    if opts.isGroupWorldObject(wid) or opts.isGroupMemberName(playerName) then
        if state.trackWidToSlot[wid] then
            OutsiderTracker.UntrackWid(state, wid)
            return true
        end
        return false
    end

    local realmRing = true
    local isFriendly = opts.isFriendly == true
    local useLeaderScale = false
    local showGroupLeaderCrown = false
    if type(opts.resolveOutsiderLeaderVisuals) == "function" then
        useLeaderScale, showGroupLeaderCrown = opts.resolveOutsiderLeaderVisuals(playerName, isFriendly)
        useLeaderScale = useLeaderScale == true
        showGroupLeaderCrown = showGroupLeaderCrown == true
    end

    if state.trackWidToSlot[wid] then
        local idx = state.trackWidToSlot[wid]
        local icon = state.outsiderPool[idx]
        if icon then
            icon:Enable()
            icon:Update(playerName, wid, career, false, realmRing, nil, useLeaderScale, showGroupLeaderCrown)
        end
        state.trackMeta[wid] = { name = playerName, isFriendly = isFriendly }
        return true
    end

    local function findFreeSlot()
        for i = 1, opts.maxTrackedOutsiders do
            if state.slotOccupantWid[i] == nil then
                return i
            end
        end
        return nil
    end

    local freeIdx = findFreeSlot()
    if freeIdx == nil then
        local protected = OutsiderTracker.BuildActiveTargetEntityIdGuard()
        local victim = OutsiderTracker.PickFifoEvictionVictim(state, protected)
        if victim == nil then
            victim = state.trackFIFOOrder[1]
        end
        if victim ~= nil then
            OutsiderTracker.UntrackWid(state, victim)
        end
        freeIdx = findFreeSlot()
    end
    if freeIdx == nil then
        return false
    end

    state.slotOccupantWid[freeIdx] = wid
    state.trackWidToSlot[wid] = freeIdx
    state.trackMeta[wid] = { name = playerName, isFriendly = isFriendly }
    table.insert(state.trackFIFOOrder, wid)

    local icon = state.outsiderPool[freeIdx]
    if icon then
        icon:Enable()
        icon:Update(playerName, wid, career, false, realmRing, nil, useLeaderScale, showGroupLeaderCrown)
    end
    return true
end

function OutsiderTracker.ConsiderClassification(state, classification, opts)
    local unitType = TargetInfo:UnitType(classification)
    if unitType ~= SystemData.TargetObjectType.ENEMY_PLAYER
        and unitType ~= SystemData.TargetObjectType.ALLY_PLAYER
    then
        return false
    end

    local wid = TargetInfo:UnitEntityId(classification)
    if wid == 0 then
        return false
    end

    local playerName = opts.toWString(TargetInfo:UnitName(classification))
    if playerName == L"" then
        return false
    end
    if opts.isSelfMember(playerName) then
        return false
    end

    local settings = opts.ensureSettings()
    local socialHighlight = type(opts.isSocialHighlightedName) == "function"
        and opts.isSocialHighlightedName(playerName) == true
    if unitType == SystemData.TargetObjectType.ALLY_PLAYER then
        -- Guild/Friends gold may track allies even when Friendly outsider icons are off.
        if not settings.showFriendly and not socialHighlight then
            return false
        end
    elseif unitType == SystemData.TargetObjectType.ENEMY_PLAYER then
        if not settings.showHostile then
            return false
        end
    end

    local career = TargetInfo:UnitCareer(classification)
    opts.learnKnownWorldObject(playerName, wid, career)
    opts.isFriendly = (unitType == SystemData.TargetObjectType.ALLY_PLAYER)
    return OutsiderTracker.TryTrack(state, wid, playerName, career, opts)
end

function OutsiderTracker.PruneAgainstRoster(state, opts)
    local wids = {}
    for wid in pairs(state.trackWidToSlot) do
        wids[#wids + 1] = wid
    end
    for i = 1, #wids do
        local wid = wids[i]
        local meta = state.trackMeta[wid]
        local name = meta and meta.name
        if opts.isGroupWorldObject(wid) or (name and opts.isGroupMemberName(name)) then
            OutsiderTracker.UntrackWid(state, wid)
        end
    end
end

function OutsiderTracker.ValidateTracked(state, cal, opts)
    if not next(state.trackWidToSlot) then
        return
    end

    opts = opts or {}
    local maxBatch = tonumber(opts.maxBatch) or 0
    local wids = {}
    for wid in pairs(state.trackWidToSlot) do
        wids[#wids + 1] = wid
    end
    table.sort(wids)

    local startIndex = 1
    local endIndex = #wids
    if maxBatch > 0 and #wids > maxBatch then
        startIndex = tonumber(state.probeCursor) or 1
        if startIndex < 1 or startIndex > #wids then
            startIndex = 1
        end
        endIndex = math.min(#wids, startIndex + maxBatch - 1)
        local nextCursor = endIndex + 1
        if nextCursor > #wids then
            nextCursor = 1
        end
        state.probeCursor = nextCursor
    else
        state.probeCursor = 1
    end

    local toUntrack = {}
    for i = startIndex, endIndex do
        local wid = wids[i]
        local idx = state.trackWidToSlot[wid]
        local icon = state.outsiderPool[idx]
        local win = icon and icon.windowName
        if not win or not DoesWindowExist(win) then
            toUntrack[#toUntrack + 1] = wid
        else
            local meta = state.trackMeta[wid]
            local name = meta and meta.name
            if name == nil or name == L"" then
                toUntrack[#toUntrack + 1] = wid
            elseif opts.nameMismatch(name, wid) then
                toUntrack[#toUntrack + 1] = wid
            elseif cal and opts.isGone(wid, cal) then
                toUntrack[#toUntrack + 1] = wid
            end
        end
    end

    for i = 1, #toUntrack do
        OutsiderTracker.UntrackWid(state, toUntrack[i])
    end
end
