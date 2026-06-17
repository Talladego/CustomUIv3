----------------------------------------------------------------
-- CustomUI.UnitFrames.Warband
--
-- Party and warband data-path helpers used by UnitFramesController.
-- Keeps raw PartyUtils/GetGroupData access and sorted visible-member
-- assembly out of the controller's window update code.
----------------------------------------------------------------

if not CustomUI then
    CustomUI = {}
end

CustomUI.UnitFrames = CustomUI.UnitFrames or {}
CustomUI.UnitFrames.Warband = CustomUI.UnitFrames.Warband or {}

local UnitFramesWarband = CustomUI.UnitFrames.Warband
local UnitFramesRoster = CustomUI.UnitFrames.Roster or {}

local c_GROUP_MEMBERS = 6

function UnitFramesWarband.BuildWarbandGroupData(dataParty, opts)
    opts = opts or {}

    local warbandParty = nil
    if type(PartyUtils) == "table" and type(PartyUtils.GetWarbandParty) == "function" then
        warbandParty = PartyUtils.GetWarbandParty(dataParty)
    end
    local players = (warbandParty and warbandParty.players) or {}
    local numMembers = table.getn(players)

    local respectStockToggle = opts.respectStockWarbandToggle ~= false
    local showGroup = numMembers >= 1
    if respectStockToggle and type(opts.isGroupVisibleFn) == "function" then
        showGroup = opts.isGroupVisibleFn(dataParty)
    end

    if not showGroup or numMembers < 1 then
        return {
            showGroup = false,
            foundLeader = false,
            members = {},
            displayMembers = nil,
        }
    end

    local orderedMembers = nil
    local displayMembers = nil
    if type(UnitFramesRoster.BuildSortedWarbandMembers) == "function" then
        orderedMembers, displayMembers = UnitFramesRoster.BuildSortedWarbandMembers(dataParty, {
            sortByRole = opts.sortByRole == true,
            memberHasDisplayNameFn = opts.memberHasDisplayNameFn,
            sortMembersFn = opts.sortMembersFn,
        })
    end

    if orderedMembers == nil then
        orderedMembers = {}
        for memberIndex = 1, c_GROUP_MEMBERS do
            if type(UnitFramesRoster.GetWarbandMember) == "function" then
                orderedMembers[memberIndex] = UnitFramesRoster.GetWarbandMember(dataParty, memberIndex)
            end
        end
    end

    local members = {}
    local foundLeader = false
    for memberIndex = 1, c_GROUP_MEMBERS do
        local member = orderedMembers[memberIndex]
        local memberName = type(opts.toWString) == "function" and opts.toWString(member and member.name) or (member and member.name)
        if member ~= nil and memberName ~= nil and memberName ~= L"" then
            members[memberIndex] = member
            if member.isGroupLeader then
                foundLeader = true
            end
        end
    end

    return {
        showGroup = true,
        foundLeader = foundLeader,
        members = members,
        displayMembers = displayMembers,
    }
end

function UnitFramesWarband.GetWarbandDisplayMember(dataParty, memberIndex)
    if type(UnitFramesRoster.GetWarbandMember) ~= "function" then
        return nil
    end
    return UnitFramesRoster.GetWarbandMember(dataParty, memberIndex)
end

function UnitFramesWarband.GetPartyDisplayMember(memberIndex)
    local data = nil
    if type(PartyUtils) == "table" and type(PartyUtils.GetPartyData) == "function" then
        data = PartyUtils.GetPartyData()
    end
    if data == nil and type(GetGroupData) == "function" then
        data = GetGroupData()
    end
    if type(UnitFramesRoster.GetPartySlotMember) ~= "function" then
        return nil
    end
    return UnitFramesRoster.GetPartySlotMember(memberIndex, data)
end

function UnitFramesWarband.BuildPartyGroupData(opts)
    opts = opts or {}

    if GameData and GameData.Party then
        GameData.Party.partyDirty = true
    end

    local data = nil
    if type(PartyUtils) == "table" and type(PartyUtils.GetPartyData) == "function" then
        data = PartyUtils.GetPartyData()
    end
    if data == nil and type(GetGroupData) == "function" then
        data = GetGroupData()
    end

    local orderedMembers = nil
    local displayMembers = nil
    if type(UnitFramesRoster.BuildSortedPartyMembers) == "function" then
        orderedMembers, displayMembers = UnitFramesRoster.BuildSortedPartyMembers(data, {
            sortByRole = opts.sortByRole == true,
            memberHasDisplayNameFn = opts.memberHasDisplayNameFn,
            sortMembersFn = opts.sortMembersFn,
        })
    end

    if orderedMembers == nil then
        orderedMembers = {}
        for memberIndex = 1, c_GROUP_MEMBERS do
            if type(UnitFramesRoster.GetPartySlotMember) == "function" then
                orderedMembers[memberIndex] = UnitFramesRoster.GetPartySlotMember(memberIndex, data)
            end
        end
    end

    local members = {}
    local hasAny = false
    local foundLeader = false
    for memberIndex = 1, c_GROUP_MEMBERS do
        local member = orderedMembers[memberIndex]
        local memberName = type(opts.toWString) == "function" and opts.toWString(member and member.name) or (member and member.name)
        if member ~= nil and memberName ~= nil and memberName ~= L"" then
            members[memberIndex] = member
            hasAny = true
            if member.isGroupLeader then
                foundLeader = true
            end
        end
    end

    return {
        data = data,
        hasAny = hasAny,
        foundLeader = foundLeader,
        members = members,
        displayMembers = displayMembers,
    }
end
