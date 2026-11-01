----------------------------------------------------------------
-- CustomUI.SmartAssist.GroupStats
-- Open-world party/warband combat scoreboard via GRP_STATS chat packets
-- (same source RoRGroupScoreboard uses). Independent cache — does not read
-- or require RoRGroupScoreboard.
----------------------------------------------------------------

if not CustomUI then
    CustomUI = {}
end

CustomUI.SmartAssist = CustomUI.SmartAssist or {}
CustomUI.SmartAssist.GroupStats = CustomUI.SmartAssist.GroupStats or {}

local GroupStats = CustomUI.SmartAssist.GroupStats

local m_active = false
local m_directCallback = nil
-- Exclusive (single-function) chain. The wrapper closes over its own original;
-- these are only for restore when our wrapper is still the slot.
local m_rpExclusiveOrig = nil
local m_rpExclusiveWrap = nil
-- List-style fallback when Register is missing or rejects the callback.
local m_rpWrapTable = nil
local m_rpWrapKey = nil
local m_rpWrapOrig = nil
local m_rpListWrap = nil
local m_byCharId = {} -- [charId] = row

local function NormalizeNameKey(name)
    if name == nil then
        return nil
    end
    local s = name
    if type(s) == "wstring" then
        if type(WStringsRemoveGrammar) == "function" then
            s = WStringsRemoveGrammar(s)
        end
        if type(WStringToString) == "function" then
            s = WStringToString(s)
        else
            s = tostring(s)
        end
    elseif type(s) ~= "string" then
        s = tostring(s)
    end
    if s == nil or s == "" then
        return nil
    end
    local caret = string.find(s, "^", 1, true)
    if caret then
        s = string.sub(s, 1, caret - 1)
    end
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    if s == "" then
        return nil
    end
    return string.lower(s)
end

local function SelfRealm()
    return GameData and GameData.Player and tonumber(GameData.Player.realm) or nil
end

--- Normalize a GRP_STATS scoreboard object into a ScenarioStats-compatible row.
--- Accepts raw packet keys (deathBlows/damage) and scoreboard-normalized keys (deathblows/damagedealt).
local function BuildRow(charId, v)
    local name = v.name
    if type(name) == "string" then
        name = towstring(name)
    end
    local killDamage = tonumber(v.killDamage) or tonumber(v.killdamagedealt) or 0
    local deathBlows = tonumber(v.deathBlows) or tonumber(v.deathblows) or 0
    local damage = tonumber(v.damage) or tonumber(v.damagedealt) or tonumber(v.totalDamage) or 0
    return {
        name = name,
        key = NormalizeNameKey(name),
        charId = tonumber(charId) or tonumber(v.charId),
        careerLine = tonumber(v.career) or tonumber(v.careerLine),
        careerId = nil,
        realm = SelfRealm(),
        -- ScenarioStats.Row* field names:
        killdamagedealt = killDamage,
        deathblows = deathBlows,
        damagedealt = damage,
        killDamage = killDamage,
        deathBlows = deathBlows,
        totalDamage = damage,
    }
end

local function RowKillDamage(row)
    if type(row) ~= "table" then
        return 0
    end
    return tonumber(row.killdamagedealt) or tonumber(row.killDamage) or 0
end

local function RowDeathBlows(row)
    if type(row) ~= "table" then
        return 0
    end
    return tonumber(row.deathblows) or tonumber(row.deathBlows) or 0
end

local function RowTotalDamage(row)
    if type(row) ~= "table" then
        return 0
    end
    return tonumber(row.damagedealt) or tonumber(row.totalDamage) or 0
end

function GroupStats.RowKillDamage(row)
    return RowKillDamage(row)
end

function GroupStats.RowDeathBlows(row)
    return RowDeathBlows(row)
end

function GroupStats.RowTotalDamage(row)
    return RowTotalDamage(row)
end

function GroupStats.RowHasAssistCombatData(row)
    return RowKillDamage(row) > 0 or RowDeathBlows(row) > 0 or RowTotalDamage(row) > 0
end

local function ChallengerWins(challenger, incumbent)
    local akd, bkd = RowKillDamage(challenger), RowKillDamage(incumbent)
    if akd ~= bkd then
        return akd > bkd
    end
    local adb, bdb = RowDeathBlows(challenger), RowDeathBlows(incumbent)
    if adb ~= bdb then
        return adb > bdb
    end
    return RowTotalDamage(challenger) > RowTotalDamage(incumbent)
end

local function LeadReason(winner, runnerUp)
    if winner == nil then
        return "KillDamage"
    end
    if runnerUp == nil then
        if RowKillDamage(winner) > 0 then
            return "KillDamage"
        end
        if RowDeathBlows(winner) > 0 then
            return "Deathblows"
        end
        return "Total Damage"
    end
    if RowKillDamage(winner) ~= RowKillDamage(runnerUp) then
        return "KillDamage"
    end
    if RowDeathBlows(winner) ~= RowDeathBlows(runnerUp) then
        return "Deathblows"
    end
    return "Total Damage"
end

function GroupStats.Clear()
    m_byCharId = {}
end

--- Drop rows whose normalized name is not on the current party/warband roster.
--- rosterKeys is nameKey -> present (any non-nil value). Dead members stay;
--- names missing from the roster are removed. No-op when rosterKeys is nil.
function GroupStats.PruneToRoster(rosterKeys)
    if type(rosterKeys) ~= "table" then
        return
    end
    for charId, row in pairs(m_byCharId) do
        local key = nil
        if type(row) == "table" then
            key = row.key or NormalizeNameKey(row.name)
        end
        if key == nil or rosterKeys[key] == nil then
            m_byCharId[charId] = nil
        end
    end
end

function GroupStats.Count()
    local n = 0
    for _ in pairs(m_byCharId) do
        n = n + 1
    end
    return n
end

function GroupStats.GetRowByKey(key)
    if key == nil then
        return nil
    end
    for _, row in pairs(m_byCharId) do
        if row.key == key then
            return row
        end
    end
    return nil
end

--- Best party/warband ally by KillDamage → Deathblows → Total Damage.
--- opts.normalizeNameKey, opts.excludeKey, opts.requireCombatData (default true),
--- opts.accept(key, row) -> bool.
function GroupStats.PickBestAssistCandidate(opts)
    opts = opts or {}
    local normalizeNameKey = opts.normalizeNameKey or NormalizeNameKey
    local excludeKey = opts.excludeKey
    local accept = opts.accept
    local requireCombatData = opts.requireCombatData ~= false
    local realm = SelfRealm()

    local bestRow, bestKey = nil, nil
    local runnerUp = nil

    for _, row in pairs(m_byCharId) do
        if type(row) == "table" and row.name ~= nil then
            row.realm = realm
            local key = row.key or normalizeNameKey(row.name)
            row.key = key
            if key ~= nil and key ~= excludeKey then
                local okAccept = true
                if requireCombatData and not GroupStats.RowHasAssistCombatData(row) then
                    okAccept = false
                end
                if okAccept and type(accept) == "function" then
                    okAccept = accept(key, row) == true
                end
                if okAccept then
                    if bestRow == nil then
                        bestRow = row
                        bestKey = key
                    elseif ChallengerWins(row, bestRow) then
                        runnerUp = bestRow
                        bestRow = row
                        bestKey = key
                    elseif runnerUp == nil or ChallengerWins(row, runnerUp) then
                        runnerUp = row
                    end
                end
            end
        end
    end

    if bestKey == nil or bestRow == nil then
        return nil
    end
    return {
        key = bestKey,
        name = bestRow.name,
        row = bestRow,
        killDamage = RowKillDamage(bestRow),
        deathBlows = RowDeathBlows(bestRow),
        totalDamage = RowTotalDamage(bestRow),
        reason = LeadReason(bestRow, runnerUp),
    }
end

local function DecodeGrpStats(text)
    if type(text) ~= "string" or type(json) ~= "table" or type(json.decode) ~= "function" then
        return nil
    end
    -- Prefer offset form used by RoRGroupScoreboard (skip "GRP_STATS:").
    local ok, decoded = pcall(json.decode, text, 11)
    if ok and type(decoded) == "table" then
        return decoded
    end
    local payload = string.gsub(text, "^GRP_STATS:", "")
    ok, decoded = pcall(json.decode, payload)
    if ok and type(decoded) == "table" then
        return decoded
    end
    return nil
end

--- Chat channel-9 payload: "GRP_STATS:{...json...}"
--- No-op while SmartAssist is not listening, including a pass-through wrapper
--- left in place because a later addon chained after us.
function GroupStats.OnPacket(text)
    if m_active ~= true then
        return
    end
    local decoded = DecodeGrpStats(text)
    if decoded == nil then
        return
    end

    local charId = tonumber(decoded.characterId)
    local board = decoded.scoreboard
    if charId == nil then
        return
    end

    if type(board) ~= "table" or board.name == nil then
        m_byCharId[charId] = nil
        return
    end

    m_byCharId[charId] = BuildRow(charId, board)

    local SA = CustomUI.SmartAssist
    if SA ~= nil and type(SA.OnGroupStatsUpdated) == "function" then
        SA.OnGroupStatsUpdated()
    end
end

function GroupStats.IsListening()
    return m_active == true
end

--- Opportunistic warm-start after /reload if another addon already holds rows.
--- Ranking still uses our cache; this does not require RoRGroupScoreboard.
function GroupStats.TryBootstrap()
    if GroupStats.Count() > 0 then
        return false
    end
    if type(RoRGroupScoreboard) ~= "table" or type(RoRGroupScoreboard.playersDataRaw) ~= "table" then
        return false
    end
    local added = false
    for charId, v in pairs(RoRGroupScoreboard.playersDataRaw) do
        if type(v) == "table" and v.name ~= nil then
            local id = tonumber(charId) or tonumber(v.charId)
            if id ~= nil then
                m_byCharId[id] = BuildRow(id, v)
                added = true
            end
        end
    end
    return added
end

local function ListHasFn(list, fn)
    if type(list) ~= "table" or type(fn) ~= "function" then
        return false
    end
    for _, existingFn in pairs(list) do
        if existingFn == fn then
            return true
        end
    end
    return false
end

local function ListKeptFns(before, after)
    if type(after) ~= "table" then
        return false
    end
    for _, fn in pairs(before) do
        if type(fn) == "function" and not ListHasFn(after, fn) then
            return false
        end
    end
    return true
end

--- Put the list slot back if Register replaced it, and drop our callback if it
--- was added somewhere we are not going to keep.
local function RestoreListSlot(RP, previousList)
    if type(ror_PacketHandling.Unregister) == "function" then
        pcall(ror_PacketHandling.Unregister, "GRP_STATS", GroupStats.OnPacket)
    end
    if previousList ~= nil and RP["GRP_STATS"] ~= previousList then
        RP["GRP_STATS"] = previousList
    end
end

--- List-style builds keep a callback table. Register/Unregister adds and removes
--- our function without replacing someone else's entry. If Register drops the
--- callbacks that were already there, undo and let the caller chain one entry.
local function TryRegisterListCallback(RP, existing)
    if type(ror_PacketHandling.Register) ~= "function"
        or type(ror_PacketHandling.Unregister) ~= "function"
    then
        return false
    end
    if ListHasFn(existing, GroupStats.OnPacket) then
        m_directCallback = GroupStats.OnPacket
        return true
    end
    local before = {}
    for key, fn in pairs(existing) do
        before[key] = fn
    end
    local ok = pcall(ror_PacketHandling.Register, "GRP_STATS", GroupStats.OnPacket)
    if not ok then
        RestoreListSlot(RP, existing)
        return false
    end
    local now = RP["GRP_STATS"]
    local emptyBefore = next(before) == nil
    if now == GroupStats.OnPacket and emptyBefore then
        m_directCallback = GroupStats.OnPacket
        return true
    end
    if ListHasFn(now, GroupStats.OnPacket) and ListKeptFns(before, now) then
        m_directCallback = GroupStats.OnPacket
        return true
    end
    RestoreListSlot(RP, existing)
    return false
end

--- Last resort on a list build: chain one existing callback. The original is
--- closed over by this wrapper alone.
local function InstallListCallbackWrap(existing)
    for key, fn in pairs(existing) do
        if type(fn) == "function" and fn ~= GroupStats.OnPacket then
            local prev = fn
            local wrap = function(text)
                if type(prev) == "function" then
                    prev(text)
                end
                if m_active then
                    GroupStats.OnPacket(text)
                end
            end
            m_rpWrapTable = existing
            m_rpWrapKey = key
            m_rpWrapOrig = prev
            m_rpListWrap = wrap
            existing[key] = wrap
            return true
        end
    end
    return false
end

local function EnsureRpListening()
    -- One hook until Shutdown is top-of-chain and restores it. A later addon's
    -- wrapper may still call ours; do not wrap that successor (double OnPacket,
    -- and a shared upvalue reassignment overflows with other addons).
    if m_rpExclusiveWrap ~= nil or m_rpListWrap ~= nil or m_directCallback ~= nil then
        return true
    end
    if type(ror_PacketHandling) ~= "table" then
        return false
    end
    local RP = ror_PacketHandling.RP
    if type(RP) ~= "table" then
        return false
    end

    local existing = RP["GRP_STATS"]

    -- Live RoR builds often store a single function (not a list). Chain it.
    if type(existing) == "function" then
        if existing == GroupStats.OnPacket then
            m_directCallback = existing
            return true
        end
        -- Capture prev in this closure; never read m_rpExclusiveOrig inside the wrap.
        local prev = existing
        m_rpExclusiveOrig = prev
        local wrap = function(text)
            if type(prev) == "function" then
                prev(text)
            end
            if m_active then
                GroupStats.OnPacket(text)
            end
        end
        m_rpExclusiveWrap = wrap
        RP["GRP_STATS"] = wrap
        return true
    end

    -- Multi-callback list builds (VinyUI-style Register).
    if type(existing) == "table" then
        if TryRegisterListCallback(RP, existing) then
            return true
        end
        return InstallListCallbackWrap(existing)
    end

    if type(ror_PacketHandling.Register) == "function" then
        m_directCallback = GroupStats.OnPacket
        ror_PacketHandling.Register("GRP_STATS", m_directCallback)
        return true
    end
    return false
end

--- Listen for GRP_STATS into our own cache.
--- Important: exclusive ror_PacketHandling keeps the registered function in RP[phrase];
--- replacing RoRGroupScoreboard.Packet alone does not receive packets.
--- RefreshAssist calls this every assist tick. Once packets are feeding, this
--- returns without wrapping again and without walking another scoreboard.
function GroupStats.Initialize()
    if m_active then
        return
    end
    if not EnsureRpListening() then
        return
    end
    m_active = true
    GroupStats.TryBootstrap()
end

function GroupStats.Shutdown()
    -- Stop feeding before unhooking. A wrapper we cannot remove then only calls
    -- the original it closed over.
    m_active = false

    if m_directCallback ~= nil
        and type(ror_PacketHandling) == "table"
        and type(ror_PacketHandling.Unregister) == "function"
    then
        local ok = pcall(ror_PacketHandling.Unregister, "GRP_STATS", m_directCallback)
        if ok then
            m_directCallback = nil
        end
    end

    if m_rpListWrap ~= nil and m_rpWrapTable ~= nil and m_rpWrapKey ~= nil then
        if m_rpWrapTable[m_rpWrapKey] == m_rpListWrap then
            m_rpWrapTable[m_rpWrapKey] = m_rpWrapOrig
            m_rpListWrap = nil
            m_rpWrapTable = nil
            m_rpWrapKey = nil
            m_rpWrapOrig = nil
        end
    end

    if m_rpExclusiveWrap ~= nil
        and type(ror_PacketHandling) == "table"
        and type(ror_PacketHandling.RP) == "table"
        and ror_PacketHandling.RP["GRP_STATS"] == m_rpExclusiveWrap
        and type(m_rpExclusiveOrig) == "function"
    then
        ror_PacketHandling.RP["GRP_STATS"] = m_rpExclusiveOrig
        m_rpExclusiveWrap = nil
        m_rpExclusiveOrig = nil
    end

    GroupStats.Clear()
end
