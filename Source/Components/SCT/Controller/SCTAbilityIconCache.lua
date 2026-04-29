----------------------------------------------------------------
-- CustomUI.SCT — session + persistent ability icon hints (LRU, capped).
-- Saved under CustomUI.Settings.SCT.abilityIconCache (shared profile / all characters).
-- Session RAM avoids re-querying; disk survives reload. One canonical verify per abilityId
-- per session (GetAbilityData + Player domains only); if verify finds no icon, cached iconNum
-- is still used when GetIconData succeeds. Stale textures drop the entry.
-- Optional per-entry `name` (plain string, capped) avoids empty abilityData when
-- GetAbilityData(abilityId) is nil after reload (proc/buff-resolved icons).
--
-- `weaponFallback`: icon came from equipped-item proc fallback (not buff/effect icon).
-- Entries with weaponFallback=true skip session/disk fast-path so GetBuffs can replace them
-- once the debuff appears; only non-fallback rows use cached shortcuts.
--
-- Load order: SCTSettings → **this file** → SCTAnim → SCTOverrides → …
----------------------------------------------------------------
if not CustomUI.SCT then CustomUI.SCT = {} end

local MAX_ENTRIES = 1024
local SCHEMA_REV = 2
local NAME_MAX_LEN = 160

----------------------------------------------------------------
-- Persistent store (CustomUI.Settings.SCT.abilityIconCache)
----------------------------------------------------------------

local function normalizePersistentCache(ac)
    if type(ac) ~= "table" then
        return false
    end
    if ac.schemaRev ~= SCHEMA_REV then
        ac.entries = {}
        ac.schemaRev = SCHEMA_REV
    end
    if type(ac.entries) ~= "table" then
        ac.entries = {}
    end
    return true
end

local function entriesRoot()
    local v = CustomUI.SCT.GetSettings()
    v.abilityIconCache = v.abilityIconCache or {}
    normalizePersistentCache(v.abilityIconCache)
    return v.abilityIconCache.entries
end

local function countEntries(entries)
    local n = 0
    for _ in pairs(entries) do
        n = n + 1
    end
    return n
end

local function nextLruSeq()
    CustomUI.SCT._sctAbilityIconLruSeq = (CustomUI.SCT._sctAbilityIconLruSeq or 0) + 1
    return CustomUI.SCT._sctAbilityIconLruSeq
end

local function clipPersistName(s)
    if type(s) ~= "string" or s == "" then
        return nil
    end
    if #s > NAME_MAX_LEN then
        return string.sub(s, 1, NAME_MAX_LEN)
    end
    return s
end

--- Best-effort display name for persistence (buff names win; weapon fallback uses combat ability name).
local function extractPersistName(abilityId, abilityData)
    if type(abilityData) == "table" and abilityData.weaponFallback == true then
        if type(GetAbilityName) == "function" then
            local raw = GetAbilityName(abilityId)
            if raw ~= nil then
                local s = clipPersistName(tostring(raw))
                if s then
                    return s
                end
            end
        end
    end
    if type(abilityData) == "table" and abilityData.name ~= nil then
        local s = clipPersistName(tostring(abilityData.name))
        if s then
            return s
        end
    end
    if type(GetAbilityName) == "function" then
        local raw = GetAbilityName(abilityId)
        if raw ~= nil then
            return clipPersistName(tostring(raw))
        end
    end
    return nil
end

local function evictOneLru(entries)
    local minId, minLru = nil, math.huge
    for id, ent in pairs(entries) do
        if type(ent) == "table" then
            local lr = tonumber(ent.lru) or 0
            if lr < minLru then
                minLru, minId = lr, id
            end
        end
    end
    if minId ~= nil then
        entries[minId] = nil
    end
end

--- Canonical iconNum from combat data + Player ability domains only (no buff/table/proc).
--- Lightweight read: session snapshot or disk row for display name (no verify / no GetIconData).
function CustomUI.SCT.AbilityIconCachePeekHint(abilityId)
    if not abilityId or abilityId == 0 then
        return nil
    end
    local store = CustomUI.SCT._sctResolvedAbilityIcon
    if type(store) == "table" then
        local e = store[abilityId]
        if type(e) == "table"
            and type(e.abilityData) == "table"
            and e.abilityData.weaponFallback ~= true
            and e.abilityData.name ~= nil
        then
            local n = tostring(e.abilityData.name)
            if n ~= "" then
                return { name = e.abilityData.name }
            end
        end
    end
    local entries = entriesRoot()
    local ent = entries[abilityId]
    if type(ent) == "table" and ent.weaponFallback == true then
        return nil
    end
    if type(ent) == "table" and type(ent.name) == "string" and ent.name ~= "" then
        return { name = ent.name }
    end
    return nil
end

function CustomUI.SCT.AbilityIconCacheProbeCanonical(abilityId)
    if not abilityId or abilityId == 0 then
        return nil
    end
    if type(GetAbilityData) ~= "function" then
        return nil
    end
    local data = GetAbilityData(abilityId)
    if type(data) == "table" and data.iconNum and data.iconNum > 0 then
        return data.iconNum
    end
    if type(Player) == "table"
        and type(Player.GetAbilityData) == "function"
        and type(Player.AbilityType) == "table"
    then
        local probeOrder = {
            Player.AbilityType.ABILITY,
            Player.AbilityType.GRANTED,
            Player.AbilityType.PASSIVE,
            Player.AbilityType.TACTIC,
            Player.AbilityType.MORALE,
            Player.AbilityType.PET,
        }
        for _, ty in ipairs(probeOrder) do
            if ty ~= nil then
                local pData = Player.GetAbilityData(abilityId, ty)
                if type(pData) == "table" and pData.iconNum and pData.iconNum > 0 then
                    return pData.iconNum
                end
            end
        end
    end
    return nil
end

--- After a full successful resolve, persist hint + LRU (evict when over cap).
--- @param abilityData table|nil snapshot from the resolver (may carry .name from buffs/items).
function CustomUI.SCT.AbilityIconCacheRecordResolve(abilityId, iconNum, abilityData)
    if not abilityId or abilityId == 0 or not iconNum or iconNum <= 0 then
        return
    end
    local entries = entriesRoot()
    local had = type(entries[abilityId]) == "table"
    if not had and countEntries(entries) >= MAX_ENTRIES then
        evictOneLru(entries)
    end
    entries[abilityId] = entries[abilityId] or {}
    local ent = entries[abilityId]
    ent.iconNum = iconNum
    ent.lru = nextLruSeq()
    local nm = extractPersistName(abilityId, abilityData)
    if nm then
        ent.name = nm
    end
    if type(abilityData) == "table" and abilityData.weaponFallback == true then
        ent.weaponFallback = true
    else
        ent.weaponFallback = nil
    end
end

--- Load from disk when session RAM misses; one verify pass per id; hydrates session RAM on success.
function CustomUI.SCT.AbilityIconCacheTryLoad(abilityId, _isIncomingReserved)
    if not abilityId or abilityId == 0 then
        return nil, nil
    end
    local entries = entriesRoot()
    local ent = entries[abilityId]
    if type(ent) ~= "table" or not ent.iconNum or ent.iconNum <= 0 then
        return nil, nil
    end
    -- Do not fast-path proc fallback icons: resolver must try GetBuffs again for DoT upgrades.
    if ent.weaponFallback == true then
        return nil, nil
    end

    CustomUI.SCT._sctIconPersistentVerifyDone = CustomUI.SCT._sctIconPersistentVerifyDone or {}
    if not CustomUI.SCT._sctIconPersistentVerifyDone[abilityId] then
        CustomUI.SCT._sctIconPersistentVerifyDone[abilityId] = true
        local probe = CustomUI.SCT.AbilityIconCacheProbeCanonical(abilityId)
        if probe and probe > 0 and tonumber(probe) ~= tonumber(ent.iconNum) then
            ent.iconNum = probe
        end
    end

    if type(GetIconData) ~= "function" then
        return nil, nil
    end
    local texture, x, y = GetIconData(ent.iconNum)
    if not texture or texture == "" or texture == "icon000000" then
        entries[abilityId] = nil
        CustomUI.SCT._sctIconPersistentVerifyDone[abilityId] = nil
        return nil, nil
    end

    ent.lru = nextLruSeq()

    local abilityData
    if GetAbilityData then
        abilityData = GetAbilityData(abilityId)
    end
    if type(abilityData) ~= "table" then
        abilityData = { iconNum = ent.iconNum }
    end
    if type(ent.name) == "string" and ent.name ~= "" then
        local existing = abilityData.name
        if existing == nil or tostring(existing) == "" then
            abilityData.name = ent.name
        end
    end
    abilityData.weaponFallback = nil

    CustomUI.SCT.AbilityIconSessionPut(abilityId, ent.iconNum, abilityData)
    return { texture = texture, x = x or 0, y = y or 0 }, abilityData
end

----------------------------------------------------------------
-- Session RAM (same reload lifetime as other SCT._ tables)
----------------------------------------------------------------

local function snapshotAbilityData(abilityData)
    if type(abilityData) ~= "table" then
        return nil
    end
    local t = {}
    for k, v in pairs(abilityData) do
        t[k] = v
    end
    return t
end

function CustomUI.SCT.AbilityIconSessionPut(abilityId, iconNum, abilityData)
    if not abilityId or abilityId == 0 or not iconNum or iconNum <= 0 then
        return
    end
    CustomUI.SCT._sctResolvedAbilityIcon = CustomUI.SCT._sctResolvedAbilityIcon or {}
    CustomUI.SCT._sctResolvedAbilityIcon[abilityId] = {
        iconNum = iconNum,
        abilityData = snapshotAbilityData(abilityData),
    }
end

--- Testing: clear session RAM + persistent SCT ability icon hints (saved under CustomUI.Settings.SCT).
function CustomUI.SCT.AbilityIconCacheClearAll()
    CustomUI.SCT._sctResolvedAbilityIcon = nil
    CustomUI.SCT._sctIconPersistentVerifyDone = nil
    CustomUI.SCT._sctAbilityIconLruSeq = nil
    if CustomUI.Settings and type(CustomUI.Settings.SCT) == "table" then
        local ac = CustomUI.Settings.SCT.abilityIconCache
        if type(ac) == "table" then
            ac.entries = {}
        end
    end
end

function CustomUI.SCT.AbilityIconSessionTryGet(abilityId)
    if not abilityId or abilityId == 0 then
        return nil, nil
    end
    local store = CustomUI.SCT._sctResolvedAbilityIcon
    if type(store) ~= "table" then
        return nil, nil
    end
    local e = store[abilityId]
    if type(e) ~= "table" or not e.iconNum or e.iconNum <= 0 then
        return nil, nil
    end
    if type(GetIconData) ~= "function" then
        return nil, nil
    end
    local texture, x, y = GetIconData(e.iconNum)
    if not texture or texture == "" or texture == "icon000000" then
        store[abilityId] = nil
        return nil, nil
    end
    if type(e.abilityData) == "table" and e.abilityData.weaponFallback == true then
        return nil, nil
    end
    return { texture = texture, x = x or 0, y = y or 0 }, e.abilityData
end
