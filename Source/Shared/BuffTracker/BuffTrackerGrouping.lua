----------------------------------------------------------------
-- CustomUI.BuffTrackerGrouping
--
-- Compression and explicit group-synthesis helpers for BuffTracker.
-- Tracker-owned synthetic table pooling stays in BuffTracker.lua and is
-- passed in via acquire/release callbacks so ownership remains local.
----------------------------------------------------------------

if not CustomUI then
    CustomUI = {}
end

CustomUI.BuffTrackerGrouping = CustomUI.BuffTrackerGrouping or {}

local BuffTrackerGrouping = CustomUI.BuffTrackerGrouping

function BuffTrackerGrouping.GetCompressionGroupKey(buffData)
    local abilityId = tonumber(buffData.abilityId)
    if abilityId and abilityId > 0 then
        return abilityId
    end

    local effectIndex = buffData.effectIndex
    if effectIndex ~= nil then
        return "e_" .. tostring(effectIndex)
    end

    return "?"
end

function BuffTrackerGrouping.BuildGroupLookup(groups)
    local lookup = {}
    if groups == nil then
        return lookup
    end

    for idx, group in ipairs(groups) do
        local abilityIds = group and group.abilityIds
        if type(abilityIds) == "table" then
            for _, abilityId in ipairs(abilityIds) do
                lookup[abilityId] = idx
            end
        end
    end

    return lookup
end

local function PickBestRepresentative(members)
    local best = members[1]
    for i = 2, #members do
        local candidate = members[i]
        if candidate.permanentUntilDispelled and not best.permanentUntilDispelled then
            best = candidate
        elseif not best.permanentUntilDispelled
            and not candidate.permanentUntilDispelled
            and candidate.duration > best.duration
        then
            best = candidate
        end
    end
    return best
end

local function ReleaseSyntheticResult(result, owner, opts)
    for i = #result, 1, -1 do
        local entry = result[i]
        if entry._isSynthetic and entry._syntheticOwner == owner then
            opts.releaseSynthetic(entry)
        end
        result[i] = nil
    end
end

function BuffTrackerGrouping.Compress(rawBuffData, scratch, opts)
    scratch = scratch or {}
    local groups = scratch.groups or {}
    local order = scratch.order or {}
    local result = scratch.result or {}
    scratch.groups = groups
    scratch.order = order
    scratch.result = result

    ReleaseSyntheticResult(result, "compress", opts)

    for k in pairs(groups) do
        groups[k] = nil
    end
    for i = #order, 1, -1 do
        order[i] = nil
    end

    for _, buffData in ipairs(rawBuffData) do
        local id = BuffTrackerGrouping.GetCompressionGroupKey(buffData)
        local members = groups[id]
        if not members then
            members = {}
            groups[id] = members
            order[#order + 1] = id
        end
        members[#members + 1] = buffData
    end

    for _, id in ipairs(order) do
        local members = groups[id]
        if #members == 1 then
            result[#result + 1] = members[1]
        else
            local best = PickBestRepresentative(members)
            local totalStacks = 0
            for i = 1, #members do
                totalStacks = totalStacks + (members[i].stackCount or 1)
            end

            local compressed = opts.acquireSynthetic(best)
            compressed.stackCount = totalStacks
            compressed._isSynthetic = true
            compressed._syntheticOwner = "compress"
            result[#result + 1] = compressed
        end
    end

    return result
end

function BuffTrackerGrouping.ApplyGroups(sourceData, buffGroups, groupLookup, scratch, opts)
    scratch = scratch or {}
    local groupBuckets = scratch.groupBuckets or {}
    local result = scratch.result or {}
    scratch.groupBuckets = groupBuckets
    scratch.result = result

    for k in pairs(groupBuckets) do
        groupBuckets[k] = nil
    end
    ReleaseSyntheticResult(result, "group", opts)

    for _, buffData in ipairs(sourceData) do
        local groupIdx = groupLookup[buffData.abilityId]
        if groupIdx then
            local members = groupBuckets[groupIdx]
            if not members then
                members = {}
                groupBuckets[groupIdx] = members
            end
            members[#members + 1] = buffData
        else
            result[#result + 1] = buffData
        end
    end

    for groupIdx, _ in ipairs(buffGroups) do
        local members = groupBuckets[groupIdx]
        if members then
            local best = PickBestRepresentative(members)
            local synthetic = opts.acquireSynthetic(best)
            synthetic.stackCount = #members
            synthetic._isSynthetic = true
            synthetic._syntheticOwner = "group"
            result[#result + 1] = synthetic
        end
    end

    return result
end
