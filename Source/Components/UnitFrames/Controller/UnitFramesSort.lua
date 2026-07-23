----------------------------------------------------------------
-- CustomUI.UnitFrames.Sort
--
-- Role-based member sorting for party, warband, and scenario rows.
-- Keeps sorting state/UI concerns out of UnitFramesController.lua.
----------------------------------------------------------------

if not CustomUI then
    CustomUI = {}
end

CustomUI.UnitFrames = CustomUI.UnitFrames or {}
CustomUI.UnitFrames.Sort = CustomUI.UnitFrames.Sort or {}

local UnitFramesSort = CustomUI.UnitFrames.Sort
local UnitFramesArchetypes = CustomUI.UnitFrames.Archetypes or {}

local c_UF_SORT_BUCKET_UNKNOWN = 9

local c_UF_SORT_TANK = {
    [GameData.CareerLine.IRON_BREAKER] = true,
    [GameData.CareerLine.SWORDMASTER] = true,
    [GameData.CareerLine.KNIGHT] = true,
    [GameData.CareerLine.BLACK_ORC] = true,
    [GameData.CareerLine.CHOSEN] = true,
    [GameData.CareerLine.BLACKGUARD] = true,
}

local c_UF_SORT_MELEE_DPS = {
    [GameData.CareerLine.WHITE_LION] = true,
    [GameData.CareerLine.WITCH_HUNTER] = true,
    [GameData.CareerLine.MARAUDER] = true,
    [GameData.CareerLine.WITCH_ELF] = true,
    [GameData.CareerLine.CHOPPA] = true,
}

local c_UF_SORT_RANGED_DPS = {
    [GameData.CareerLine.BRIGHT_WIZARD] = true,
    [GameData.CareerLine.ENGINEER] = true,
    [GameData.CareerLine.SHADOW_WARRIOR] = true,
    [GameData.CareerLine.MAGUS] = true,
    [GameData.CareerLine.SORCERER] = true,
    [GameData.CareerLine.SQUIG_HERDER] = true,
}

local c_UF_SORT_HEAL = {
    [GameData.CareerLine.WARRIOR_PRIEST] = true,
    [GameData.CareerLine.RUNE_PRIEST] = true,
    [GameData.CareerLine.ARCHMAGE] = true,
    [GameData.CareerLine.DISCIPLE] = true,
    [GameData.CareerLine.ZEALOT] = true,
    [GameData.CareerLine.SHAMAN] = true,
}

if GameData.CareerLine.SLAYER then
    c_UF_SORT_MELEE_DPS[GameData.CareerLine.SLAYER] = true
end

if GameData.CareerLine.HAMMERER then
    c_UF_SORT_MELEE_DPS[GameData.CareerLine.HAMMERER] = true
end

local function ToSortNameString(name)
    if name == nil then
        return nil
    end
    if type(name) == "wstring" and type(WStringToString) == "function" then
        name = WStringToString(name)
    end
    if type(name) ~= "string" then
        name = tostring(name)
    end
    return name
end

function UnitFramesSort.NormalizeArchetypeLookupName(name)
    if type(UnitFramesArchetypes.NormalizeLookupName) ~= "function" then
        return nil
    end
    return UnitFramesArchetypes.NormalizeLookupName(name, true)
end

function UnitFramesSort.GetBucketForCareerLine(line)
    line = tonumber(line)
    if line == nil then
        return c_UF_SORT_BUCKET_UNKNOWN
    end
    if c_UF_SORT_TANK[line] then
        return 1
    end
    if c_UF_SORT_MELEE_DPS[line] then
        return 2
    end
    if c_UF_SORT_RANGED_DPS[line] then
        return 3
    end
    if c_UF_SORT_HEAL[line] then
        return 4
    end
    return c_UF_SORT_BUCKET_UNKNOWN
end

function UnitFramesSort.GetEffectiveArchetypeForPlayer(playerName, careerLine)
    if playerName == nil then
        return UnitFramesSort.GetBucketForCareerLine(careerLine)
    end

    -- Scoreboard archtype > 0 = alt-spec (not tank/dps/heal bucket ids). Hybrid healers sort as DPS.
    if type(UnitFramesArchetypes.IsAltSpec) == "function" and UnitFramesArchetypes.IsAltSpec(playerName) then
        local line = tonumber(careerLine)
        if line ~= nil and c_UF_SORT_HEAL[line] then
            -- Melee hybrids (WP/DoK) → melee DPS bucket; caster hybrids → ranged.
            if line == GameData.CareerLine.WARRIOR_PRIEST or line == GameData.CareerLine.DISCIPLE then
                return 2
            end
            return 3
        end
    end

    return UnitFramesSort.GetBucketForCareerLine(careerLine)
end

local function CareerAlphabeticalSortKey(line)
    line = tonumber(line)
    if line == nil or type(GetCareerLine) ~= "function" then
        return "~"
    end
    local w = GetCareerLine(line, nil)
    local s = ToSortNameString(w)
    if s == nil or s == "" then
        return "~"
    end
    return string.lower(s)
end

local function BattleRankDescendingSortKey(member)
    return tonumber(member and member.battleLevel) or tonumber(member and member.battleRank) or 0
end

function UnitFramesSort.MembersForDisplay(members)
    if type(members) ~= "table" or table.getn(members) < 2 then
        return members
    end

    local enriched = {}
    for i = 1, table.getn(members) do
        local member = members[i]
        local line = member and member.careerLine
        local name = member and (member.name or (member.player and member.player.name))
        table.insert(enriched, {
            m = member,
            bucket = UnitFramesSort.GetEffectiveArchetypeForPlayer(name, line),
            careerKey = CareerAlphabeticalSortKey(line),
            br = BattleRankDescendingSortKey(member),
            ord = i,
        })
    end

    table.sort(enriched, function(a, b)
        if a.bucket ~= b.bucket then
            return a.bucket < b.bucket
        end
        if a.careerKey ~= b.careerKey then
            return a.careerKey < b.careerKey
        end
        if a.br ~= b.br then
            return a.br > b.br
        end
        return a.ord < b.ord
    end)

    local out = {}
    for i = 1, table.getn(enriched) do
        out[i] = enriched[i].m
    end
    return out
end
