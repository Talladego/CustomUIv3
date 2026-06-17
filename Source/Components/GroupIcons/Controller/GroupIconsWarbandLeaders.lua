----------------------------------------------------------------
-- CustomUI.GroupIcons.WarbandLeaders
--
-- Known friendly warband-leader names for outsider icon sizing (1.5× + Group-Leader-Crown).
-- Hostile warband leaders are not exposed by the game — only open-party / ally data is used.
--
-- Sources (ea_openpartywindow):
--   • GetOpenPartyFullList()         — nearby (SOCIAL_OPENPARTY_UPDATED)
--   • GetOpenPartyNotificationList() — area flyout (SOCIAL_OPENPARTY_NOTIFY)
--   • GetOpenPartyWorldList()        — world tab (SOCIAL_OPENPARTY_WORLD_UPDATED)
--     Warband entries: leaderName + isWarband == true
--   • Own warband (when active): isWarbandLeader members + GetWarbandLeader()
----------------------------------------------------------------

if not CustomUI then
    CustomUI = {}
end

CustomUI.GroupIcons = CustomUI.GroupIcons or {}
CustomUI.GroupIcons.WarbandLeaders = CustomUI.GroupIcons.WarbandLeaders or {}

local WarbandLeaders = CustomUI.GroupIcons.WarbandLeaders

local m_keySet = {}
local m_fingerprint = ""
local m_requestDelay = 0
local c_REQUEST_COOLDOWN = 2

local function AddLeaderName(name, normalizeNameKey, into)
    if type(normalizeNameKey) ~= "function" or name == nil or into == nil then
        return
    end
    local key = normalizeNameKey(name)
    if key ~= nil then
        into[key] = true
    end
end

local function CollectOpenPartyList(list, normalizeNameKey, into)
    if type(list) ~= "table" then
        return
    end
    for _, data in ipairs(list) do
        if data and data.isWarband == true and data.leaderName ~= nil then
            AddLeaderName(data.leaderName, normalizeNameKey, into)
        end
    end
end

local function CollectOwnWarbandLeaders(normalizeNameKey, into)
    if type(IsWarBandActive) ~= "function" or not IsWarBandActive() then
        return
    end

    local warband = nil
    if type(PartyUtils) == "table" and type(PartyUtils.GetWarbandData) == "function" then
        warband = PartyUtils.GetWarbandData()
    elseif type(GetBattlegroupMemberData) == "function" then
        warband = GetBattlegroupMemberData()
    end

    if type(warband) == "table" then
        for _, party in ipairs(warband) do
            local players = party and party.players
            if type(players) == "table" then
                for _, member in ipairs(players) do
                    if member and member.name and member.isWarbandLeader == true then
                        AddLeaderName(member.name, normalizeNameKey, into)
                    end
                end
            end
        end
    end

    if type(PartyUtils) == "table" and type(PartyUtils.GetWarbandLeader) == "function" then
        local leader = PartyUtils.GetWarbandLeader()
        if leader and leader.name then
            AddLeaderName(leader.name, normalizeNameKey, into)
        end
    end
end

local function FingerprintKeySet(keySet)
    local keys = {}
    for key in pairs(keySet) do
        keys[#keys + 1] = key
    end
    table.sort(keys)
    return table.concat(keys, "\0")
end

--- Rebuild leader-name keys. @return boolean true when the set changed (new leader, transfer, or drop-off).
function WarbandLeaders.Refresh(opts)
    opts = opts or {}
    local normalizeNameKey = opts.normalizeNameKey

    local nextSet = {}

    if type(GetOpenPartyFullList) == "function" then
        CollectOpenPartyList(GetOpenPartyFullList(), normalizeNameKey, nextSet)
    end
    if type(GetOpenPartyNotificationList) == "function" then
        CollectOpenPartyList(GetOpenPartyNotificationList(), normalizeNameKey, nextSet)
    end
    if type(GetOpenPartyWorldList) == "function" then
        CollectOpenPartyList(GetOpenPartyWorldList(), normalizeNameKey, nextSet)
    end

    CollectOwnWarbandLeaders(normalizeNameKey, nextSet)

    local fp = FingerprintKeySet(nextSet)
    local changed = fp ~= m_fingerprint
    m_fingerprint = fp
    m_keySet = nextSet
    return changed
end

--- Poll server for nearby warband LFG entries (throttled). No-op when disabled via opts.enabled == false.
function WarbandLeaders.RequestNearbyData(opts)
    opts = opts or {}
    if opts.enabled == false then
        return
    end
    if m_requestDelay > 0 then
        return
    end
    if type(SendOpenPartySearchRequest) ~= "function" then
        return
    end
    if GameData == nil or GameData.OpenPartyRequestType == nil then
        return
    end
    local reqType = GameData.OpenPartyRequestType.WARBANDS
    if reqType == nil then
        reqType = GameData.OpenPartyRequestType.ALL_BRIEF
    end
    SendOpenPartySearchRequest(reqType)
    m_requestDelay = c_REQUEST_COOLDOWN
end

--- @param dt number seconds since last OnUpdate tick
function WarbandLeaders.TickRequestCooldown(dt)
    if m_requestDelay <= 0 then
        return
    end
    m_requestDelay = m_requestDelay - (tonumber(dt) or 0)
    if m_requestDelay < 0 then
        m_requestDelay = 0
    end
end

--- @return boolean
function WarbandLeaders.IsKnown(name, normalizeNameKey)
    if type(normalizeNameKey) ~= "function" or name == nil then
        return false
    end
    local key = normalizeNameKey(name)
    return key ~= nil and m_keySet[key] == true
end
