----------------------------------------------------------------
-- CustomUI.TargetRenownLookup
-- Async renown rank for other players via optional LibQuery
-- (GraphQL character.identity.renownRank through libquery_worker).
-- No-ops when LibQuery / worker is unavailable.
----------------------------------------------------------------

if not CustomUI then
    CustomUI = {}
end

CustomUI.TargetRenownLookup = CustomUI.TargetRenownLookup or {}

local Lookup = CustomUI.TargetRenownLookup

-- In-flight: queryName lower -> { { callback, meta }, ... }
local inflight = {}

local function StripWarGrammar(name)
    if name == nil then
        return nil
    end
    if type(name) == "wstring" and type(WStringsRemoveGrammar) == "function" then
        return WStringsRemoveGrammar(name)
    end
    return name
end

--- Exact-cased name for LibQuery `name: { eq }` (strip grammar / caret suffix).
function Lookup.FormatQueryName(name)
    if name == nil then
        return nil
    end

    name = StripWarGrammar(name)

    local s = name
    if type(s) == "wstring" and type(WStringToString) == "function" then
        s = WStringToString(s)
    end
    if type(s) ~= "string" then
        s = tostring(s)
    end
    if s == nil or s == "" then
        return nil
    end

    if #s >= 2 and string.sub(s, -2) == " ^" then
        s = string.sub(s, 1, -3)
    end

    local caret = string.find(s, "^", 1, true)
    if caret then
        s = string.sub(s, 1, caret - 1)
    end

    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    if s == "" then
        return nil
    end

    return s
end

function Lookup.IsAvailable()
    return type(LibQuery) == "table"
        and type(LibQuery.GetCharacterRenownRank) == "function"
end

function Lookup.IsPlayerUnit(unitId)
    if unitId == nil or type(TargetInfo) ~= "table" then
        return false
    end
    if type(TargetInfo.UnitIsNPC) == "function" and TargetInfo:UnitIsNPC(unitId) then
        return false
    end
    if type(TargetInfo.UnitCareer) == "function" then
        local career = tonumber(TargetInfo:UnitCareer(unitId)) or 0
        if career ~= 0 then
            return true
        end
    end
    if type(TargetInfo.UnitType) == "function"
        and SystemData
        and SystemData.TargetObjectType
    then
        local t = TargetInfo:UnitType(unitId)
        local T = SystemData.TargetObjectType
        return t == T.ALLY_PLAYER or t == T.ENEMY_PLAYER or t == T.SELF
    end
    return false
end

function Lookup.GetCachedRank(queryName)
    if not Lookup.IsAvailable() or queryName == nil or queryName == "" then
        return nil
    end
    if type(LibQuery.GetCharacterRenownRankCached) == "function" then
        local rank = LibQuery.GetCharacterRenownRankCached(queryName)
        if rank ~= nil then
            return tonumber(rank)
        end
    end
    return nil
end

--- Request renown for a player target.
--- callback(rankOrNil, meta) where meta = { entityId, queryName, unitId }
--- Callers must ignore stale replies (entityId / queryName mismatch).
function Lookup.Request(unitId, entityId, rawName, callback)
    if type(callback) ~= "function" then
        return false
    end

    local queryName = Lookup.FormatQueryName(rawName)
    local meta = { entityId = entityId, queryName = queryName, unitId = unitId }

    if not Lookup.IsAvailable() or queryName == nil or queryName == "" then
        callback(nil, meta)
        return false
    end

    local cached = Lookup.GetCachedRank(queryName)
    if cached ~= nil then
        -- Callers also paint GetCachedRank before Request. Deliver the cached
        -- rank once and do not start another worker fetch (that second callback
        -- was a redundant badge update on every resync).
        callback(cached, meta)
        return true
    end

    local key = string.lower(queryName)
    local waiters = inflight[key]
    if waiters then
        waiters[#waiters + 1] = { callback = callback, meta = meta }
        return cached ~= nil
    end

    inflight[key] = { { callback = callback, meta = meta } }
    LibQuery.GetCharacterRenownRank(queryName, function(rank)
        local list = inflight[key]
        inflight[key] = nil
        local n = tonumber(rank)
        if type(list) ~= "table" then
            return
        end
        for i = 1, #list do
            local entry = list[i]
            if entry and type(entry.callback) == "function" then
                entry.callback(n, entry.meta)
            end
        end
    end)
    return true
end
