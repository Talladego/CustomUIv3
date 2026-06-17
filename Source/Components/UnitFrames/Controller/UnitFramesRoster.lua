----------------------------------------------------------------
-- CustomUI.UnitFrames.Roster
--
-- Raw party/warband member access helpers used by UnitFramesController.
-- Keeps PartyUtils quirks and local-player snapshot logic out of the
-- controller's rendering and mode-switch code.
----------------------------------------------------------------

if not CustomUI then
    CustomUI = {}
end

CustomUI.UnitFrames = CustomUI.UnitFrames or {}
CustomUI.UnitFrames.Roster = CustomUI.UnitFrames.Roster or {}

local UnitFramesRoster = CustomUI.UnitFrames.Roster

local c_GROUP_MEMBERS = 6
local c_WARBAND_GROUPS = 4

-- Stock PartyUtils.GetWarbandMember can error when party.players[slot] is nil
-- but the warband dirty flag is set. Treat as empty slot instead of failing.
function UnitFramesRoster.GetWarbandMember(dataParty, memberIndex)
    if type(PartyUtils) ~= "table" or type(PartyUtils.GetWarbandMember) ~= "function" then
        return nil
    end

    local ok, member = pcall(PartyUtils.GetWarbandMember, dataParty, memberIndex)
    if ok then
        return member
    end

    return nil
end

function UnitFramesRoster.BuildLocalPlayerSnapshot()
    if GameData == nil or GameData.Player == nil then
        return nil
    end

    local player = GameData.Player
    if player.name == nil or player.name == L"" then
        return nil
    end

    local hp = 0
    if player.hitPoints and tonumber(player.hitPoints.maximum) and tonumber(player.hitPoints.maximum) > 0 then
        hp = 100 * (tonumber(player.hitPoints.current) or 0) / tonumber(player.hitPoints.maximum)
    end

    local ap = 0
    if player.actionPoints and tonumber(player.actionPoints.maximum) and tonumber(player.actionPoints.maximum) > 0 then
        ap = 100 * (tonumber(player.actionPoints.current) or 0) / tonumber(player.actionPoints.maximum)
    end

    if hp < 0 then hp = 0 elseif hp > 100 then hp = 100 end
    if ap < 0 then ap = 0 elseif ap > 100 then ap = 100 end

    local careerLine = nil
    if player.career ~= nil and player.career.line ~= nil then
        careerLine = player.career.line
    end

    return {
        name = player.name,
        healthPercent = hp,
        actionPointPercent = ap,
        moraleLevel = 0,
        level = tonumber(player.rank) or tonumber(player.level) or 0,
        battleLevel = tonumber(player.battleRank) or tonumber(player.battleLevel) or 0,
        isRVRFlagged = player.isRVRFlagged == true,
        zoneNum = tonumber(player.zoneNum) or tonumber(player.zoneNumber) or 0,
        online = true,
        isDistant = false,
        worldObjNum = tonumber(player.worldObjNum) or 0,
        isGroupLeader = player.isGroupLeader == true,
        careerLine = careerLine,
    }
end

function UnitFramesRoster.GetPartySlotMember(memberIndex, fallbackData)
    if memberIndex == nil or memberIndex < 1 or memberIndex > c_GROUP_MEMBERS then
        return nil
    end

    if memberIndex == 1 then
        return UnitFramesRoster.BuildLocalPlayerSnapshot()
    end

    local mateIndex = memberIndex - 1
    if type(PartyUtils) == "table" and type(PartyUtils.GetPartyMember) == "function" then
        local maxWithoutSelf = tonumber(PartyUtils.PLAYERS_PER_PARTY_WITHOUT_LOCAL) or 5
        if mateIndex >= 1 and mateIndex <= maxWithoutSelf then
            local member = PartyUtils.GetPartyMember(mateIndex)
            if member ~= nil then
                return member
            end
        end
    end

    if type(fallbackData) == "table" then
        return fallbackData[mateIndex]
    end

    return nil
end

-- Battlegroup with UnitFrames Party on + Warband off: show the party the
-- local player belongs to (not always warband party slot 1).
function UnitFramesRoster.ResolveLocalPlayerWarbandPartyIndex()
    if GameData == nil or GameData.Player == nil then
        return nil
    end

    local playerName = GameData.Player.name
    if playerName == nil or playerName == L"" then
        return nil
    end

    if type(PartyUtils) ~= "table" or type(PartyUtils.IsPlayerInWarband) ~= "function" then
        return nil
    end

    local partyIndex = tonumber(PartyUtils.IsPlayerInWarband(playerName))
    if partyIndex == nil or partyIndex < 1 or partyIndex > c_WARBAND_GROUPS then
        return nil
    end

    return partyIndex
end

-- Build the sorted visible member list for one warband party when role sorting
-- is enabled. Returns `sortedSlots, displayMembers`.
function UnitFramesRoster.BuildSortedWarbandMembers(dataParty, opts)
    opts = opts or {}
    if opts.sortByRole ~= true then
        return nil, nil
    end

    local collected = {}
    for memberIndex = 1, c_GROUP_MEMBERS do
        local member = UnitFramesRoster.GetWarbandMember(dataParty, memberIndex)
        if type(opts.memberHasDisplayNameFn) == "function" and opts.memberHasDisplayNameFn(member) then
            collected[#collected + 1] = member
        end
    end

    local sortedSlots = collected
    if type(opts.sortMembersFn) == "function" then
        sortedSlots = opts.sortMembersFn(collected)
    end

    local displayMembers = {}
    for i = 1, table.getn(sortedSlots or {}) do
        displayMembers[i] = sortedSlots[i]
    end

    return sortedSlots, displayMembers
end

-- Build the sorted visible member list for the plain party view when role
-- sorting is enabled. Returns `sortedSlots, displayMembers`.
function UnitFramesRoster.BuildSortedPartyMembers(data, opts)
    opts = opts or {}
    if opts.sortByRole ~= true then
        return nil, nil
    end

    local collected = {}
    for memberIndex = 1, c_GROUP_MEMBERS do
        local member = UnitFramesRoster.GetPartySlotMember(memberIndex, data)
        if type(opts.memberHasDisplayNameFn) == "function" and opts.memberHasDisplayNameFn(member) then
            collected[#collected + 1] = member
        end
    end

    local sortedSlots = collected
    if type(opts.sortMembersFn) == "function" then
        sortedSlots = opts.sortMembersFn(collected)
    end

    local displayMembers = {}
    for i = 1, table.getn(sortedSlots or {}) do
        displayMembers[i] = sortedSlots[i]
    end

    return sortedSlots, displayMembers
end
