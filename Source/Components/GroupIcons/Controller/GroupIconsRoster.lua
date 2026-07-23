----------------------------------------------------------------
-- CustomUI.GroupIcons.Roster
--
-- Roster and cache helpers for GroupIcons. The controller keeps event/timer
-- orchestration; this module owns roster membership caches, known/sticky
-- world object ids, and party/warband refresh passes.
----------------------------------------------------------------

if not CustomUI then
    CustomUI = {}
end

CustomUI.GroupIcons = CustomUI.GroupIcons or {}
CustomUI.GroupIcons.Roster = CustomUI.GroupIcons.Roster or {}

local Roster = CustomUI.GroupIcons.Roster

local c_MAX_PARTIES = 6
local c_MAX_MEMBERS = 6

function Roster.InvalidatePartyAndWarbandCaches()
    if GameData and GameData.Party then
        GameData.Party.partyDirty = true
        GameData.Party.warbandDirty = true
    end
end

function Roster.ClearGroupMembershipCache(state)
    for k in pairs(state.groupWorldObjs) do
        state.groupWorldObjs[k] = nil
    end
    for k in pairs(state.groupNames) do
        state.groupNames[k] = nil
    end
    for i = #state.groupNameList, 1, -1 do
        state.groupNameList[i] = nil
    end
end

function Roster.RegisterGroupMember(state, member, opts)
    if not member or not member.name then
        return
    end
    local name = opts.toWString(member.name)
    if member.worldObjNum and member.worldObjNum ~= 0 then
        state.groupWorldObjs[member.worldObjNum] = true
    end
    state.groupNames[name] = true
    state.groupNameList[#state.groupNameList + 1] = name
end

local function RememberStickyRosterWid(state, nameW, wid, opts)
    local key = opts.normalizeNameKey(nameW)
    local w = tonumber(wid) or 0
    if key ~= nil and w ~= 0 then
        state.stickyRosterWidByKey[key] = w
    end
end

function Roster.ResolveAttachWorldId(state, nameW, liveWidFromData, opts)
    local w = tonumber(liveWidFromData) or 0
    if w ~= 0 then
        RememberStickyRosterWid(state, nameW, w, opts)
        return w
    end

    local key = opts.normalizeNameKey(nameW)
    if key == nil then
        return 0
    end

    local known = state.knownByNameKey[key]
    local knownWid = known and tonumber(known.wid) or 0
    if knownWid ~= 0 then
        RememberStickyRosterWid(state, nameW, knownWid, opts)
        return knownWid
    end

    local stickyWid = tonumber(state.stickyRosterWidByKey[key]) or 0
    if stickyWid ~= 0 then
        return stickyWid
    end

    return 0
end

local function PruneStickyRosterWids(state, validKeys)
    if validKeys == nil then
        return
    end
    for key in pairs(state.stickyRosterWidByKey) do
        if not validKeys[key] then
            state.stickyRosterWidByKey[key] = nil
        end
    end
end

local function RosterWorldObjectNameMatchesPlayer(wid, expectedNameW, opts)
    if wid == nil or wid == 0 or type(GetNameForObject) ~= "function" then
        return true
    end
    local ok, nm = CustomUI.TryCallQuiet("GroupIconsRoster.RosterWorldObjectNameMatchesPlayer", GetNameForObject, wid)
    if not ok or nm == nil then
        return true
    end
    local w = opts.toWString(nm)
    if w == nil or w == L"" then
        return true
    end
    return opts.safeWStringEquals(w, opts.toWString(expectedNameW))
end

local function ClearStickyAndKnownWidForEntity(state, key, badWid)
    if key == nil then
        return
    end
    local bw = tonumber(badWid) or 0
    if bw == 0 then
        return
    end
    local sw = tonumber(state.stickyRosterWidByKey[key]) or 0
    if sw == bw then
        state.stickyRosterWidByKey[key] = nil
    end
    local known = state.knownByNameKey[key]
    if known and tonumber(known.wid) == bw then
        state.knownByNameKey[key] = nil
    end
end

function Roster.ValidateIconWorldObjects(state, opts)
    for p = 1, c_MAX_PARTIES do
        for m = 1, c_MAX_MEMBERS do
            local icon = state.icons[p][m]
            if icon.isEnabled and icon.worldObjNum ~= 0 and icon.playerName then
                local wid = icon.worldObjNum
                if not RosterWorldObjectNameMatchesPlayer(wid, icon.playerName, opts) then
                    local key = opts.normalizeNameKey(icon.playerName)
                    ClearStickyAndKnownWidForEntity(state, key, wid)
                    icon:Update(icon.playerName, 0, icon.lastCareerLine, false, false, icon.lastCareerNamesId)
                end
            end
        end
    end
end

function Roster.LearnKnownWorldObject(state, name, wid, careerLine, opts)
    local key = opts.normalizeNameKey(name)
    local w = tonumber(wid) or 0
    if key == nil or w == 0 then
        return false
    end

    local prev = state.knownByNameKey[key]
    if prev ~= nil and prev.wid == w and (careerLine == nil or prev.careerLine == careerLine) then
        return false
    end

    RememberStickyRosterWid(state, name, w, opts)
    state.knownByNameKey[key] = {
        wid = w,
        careerLine = tonumber(careerLine),
        t = type(CustomUI) == "table" and CustomUI.Time or nil,
    }
    if type(opts.debugLog) == "function" then
        opts.debugLog("LearnKnownWorldObject: " .. tostring(key) .. " wid=" .. tostring(w) .. " careerLine=" .. tostring(careerLine))
    end
    return true
end

local function GetPartySlotMember(memberIndex, fallbackData)
    if memberIndex == nil or memberIndex < 1 then
        return nil
    end
    if type(PartyUtils) == "table" and type(PartyUtils.GetPartyMember) == "function" then
        local maxWithoutSelf = tonumber(PartyUtils.PLAYERS_PER_PARTY_WITHOUT_LOCAL) or 5
        if memberIndex <= maxWithoutSelf then
            local member = PartyUtils.GetPartyMember(memberIndex)
            if member ~= nil then
                return member
            end
        end
    end
    if type(fallbackData) == "table" then
        return fallbackData[memberIndex]
    end
    return nil
end

function Roster.RegisterAllForPruning(state, opts)
    Roster.InvalidatePartyAndWarbandCaches()
    Roster.ClearGroupMembershipCache(state)

    local data = nil
    if type(PartyUtils) == "table" and type(PartyUtils.GetPartyData) == "function" then
        data = PartyUtils.GetPartyData()
    end
    if data == nil then
        data = GetGroupData()
    end
    if type(data) == "table" then
        for m = 1, c_MAX_MEMBERS do
            local member = GetPartySlotMember(m, data)
            if member and member.name then
                local liveWid = tonumber(member.worldObjNum) or 0
                local wid = Roster.ResolveAttachWorldId(state, member.name, liveWid, opts)
                Roster.RegisterGroupMember(state, { name = member.name, worldObjNum = (wid ~= 0 and wid) or nil }, opts)
            end
        end
    end

    if opts.isWarBandActive() then
        local parties = GetBattlegroupMemberData()
        if type(parties) == "table" then
            for p = 1, c_MAX_PARTIES do
                local party = parties[p]
                for m = 1, c_MAX_MEMBERS do
                    local member = party and party.players and party.players[m]
                    if type(PartyUtils) == "table" and type(PartyUtils.GetWarbandMember) == "function" then
                        local hydrated = PartyUtils.GetWarbandMember(p, m)
                        if hydrated ~= nil then
                            member = hydrated
                        end
                    end
                    if member and member.name then
                        local liveWid = tonumber(member.worldObjNum) or 0
                        local wid = Roster.ResolveAttachWorldId(state, member.name, liveWid, opts)
                        Roster.RegisterGroupMember(state, { name = member.name, worldObjNum = (wid ~= 0 and wid) or nil }, opts)
                    end
                end
            end
        end
    end
end

function Roster.RefreshParty(state, opts)
    Roster.InvalidatePartyAndWarbandCaches()
    local data = nil
    if type(PartyUtils) == "table" and type(PartyUtils.GetPartyData) == "function" then
        data = PartyUtils.GetPartyData()
    end
    if data == nil then
        data = GetGroupData()
    end
    if not data then
        return
    end

    local attachable = 0
    local validStickyKeys = {}
    for m = 1, c_MAX_MEMBERS do
        local member = GetPartySlotMember(m, data)
        local icon = state.icons[1][m]
        local memberName = member and opts.toWString(member.name)
        if member and memberName ~= nil and memberName ~= L"" then
            local nk = opts.normalizeNameKey(member.name)
            if nk ~= nil then
                validStickyKeys[nk] = true
            end
            local liveWid = tonumber(member.worldObjNum) or 0
            local wid = Roster.ResolveAttachWorldId(state, member.name, liveWid, opts)
            Roster.RegisterGroupMember(state, { name = member.name, worldObjNum = (wid ~= 0 and wid) or nil }, opts)
            if wid ~= 0 and not opts.isSelfMember(memberName) then
                attachable = attachable + 1
                icon:Enable()
                icon:Update(memberName, wid, member.careerLine, member.isGroupLeader == true, false)
            else
                icon:Disable()
            end
        else
            icon:Disable()
        end
    end

    PruneStickyRosterWids(state, validStickyKeys)
    if type(opts.debugLog) == "function" then
        opts.debugLog("RefreshParty: attachableMembers=" .. tostring(attachable))
    end

    for p = 2, c_MAX_PARTIES do
        for m = 1, c_MAX_MEMBERS do
            state.icons[p][m]:Disable()
        end
    end
end

function Roster.RefreshWarband(state, showAll, showParty1, partiesOverride, opts)
    Roster.InvalidatePartyAndWarbandCaches()
    local parties = partiesOverride or GetBattlegroupMemberData()
    if not parties then
        return
    end

    if type(opts.debugLog) == "function" then
        opts.debugLog("RefreshWarband: showAll=" .. tostring(showAll) .. " showParty1=" .. tostring(showParty1))
    end

    showAll = showAll == true
    showParty1 = showParty1 == true

    local validStickyKeys = {}
    for p = 1, c_MAX_PARTIES do
        local party = parties[p]
        for m = 1, c_MAX_MEMBERS do
            local member = party and party.players and party.players[m]
            if type(PartyUtils) == "table" and type(PartyUtils.GetWarbandMember) == "function" then
                local hydrated = PartyUtils.GetWarbandMember(p, m)
                if hydrated ~= nil then
                    member = hydrated
                end
            end
            local icon = state.icons[p][m]
            local shouldShow = showAll or (showParty1 and p == 1)
            local memberName = member and opts.toWString(member.name)
            if shouldShow and member and memberName ~= nil and memberName ~= L"" then
                local nk = opts.normalizeNameKey(member.name)
                if nk ~= nil then
                    validStickyKeys[nk] = true
                end
                local liveWid = tonumber(member.worldObjNum) or 0
                local wid = Roster.ResolveAttachWorldId(state, member.name, liveWid, opts)
                Roster.RegisterGroupMember(state, { name = member.name, worldObjNum = (wid ~= 0 and wid) or nil }, opts)
                if wid ~= 0 and not opts.isSelfMember(memberName) then
                    icon:Enable()
                    icon:Update(memberName, wid, member.careerLine, member.isGroupLeader == true, false)
                else
                    icon:Disable()
                end
            else
                icon:Disable()
            end
        end
    end

    PruneStickyRosterWids(state, validStickyKeys)
end
