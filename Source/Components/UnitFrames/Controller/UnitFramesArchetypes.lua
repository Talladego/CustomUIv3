----------------------------------------------------------------
-- CustomUI.UnitFrames.Archetypes
--
-- Shared player-name normalization and scoreboard/scenario archetype
-- override lookup used by UnitFrames sorting and per-player tinting.
--
-- RoR scoreboard semantics (ror_groupscoreboard / OpenParty):
--   archtype == 0  → primary career role (heal for WP/DoK/etc.)
--   archtype  > 0  → alt-spec icon index (1–4); treat hybrid healers as DPS
-- Do NOT map 1–4 as tank/dps/heal — those are ArchTypeIcons indices only.
----------------------------------------------------------------

if not CustomUI then
    CustomUI = {}
end

CustomUI.UnitFrames = CustomUI.UnitFrames or {}
CustomUI.UnitFrames.Archetypes = CustomUI.UnitFrames.Archetypes or {}

local UnitFramesArchetypes = CustomUI.UnitFrames.Archetypes

-- Populated from GRP_STATS packets (and RoRGroupScoreboard.playersDataRaw).
-- Key = NormalizeLookupName(name, true); value = scoreboard archtype (0 = primary, >0 = alt-spec).
local archtypeByNormalizedName = {}

local function StripWarGrammar(name)
    if name == nil then
        return nil
    end
    if type(name) == "wstring" and type(WStringsRemoveGrammar) == "function" then
        return WStringsRemoveGrammar(name)
    end
    return name
end

local function NamesProbablyMatch(playerNameStr, candidateNameStr)
    if playerNameStr == nil or candidateNameStr == nil then
        return false
    end
    if playerNameStr == candidateNameStr then
        return true
    end
    -- Party/scenario names carry a WAR grammar prefix; scoreboard names usually do not.
    if string.sub(playerNameStr, 2) == candidateNameStr then
        return true
    end
    if playerNameStr == string.sub(candidateNameStr, 2) then
        return true
    end
    return string.sub(playerNameStr, 2) == string.sub(candidateNameStr, 2)
end

--- Normalize a player name for alt-spec lookup.
--- @param name any wstring|string player name
--- @param stripGrammar boolean|nil When true, strip the WAR grammar prefix (party/scenario roster names).
function UnitFramesArchetypes.NormalizeLookupName(name, stripGrammar)
    if name == nil then
        return nil
    end

    if stripGrammar == true then
        name = StripWarGrammar(name)
    end

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

    -- Scenario names can carry a trailing " ^" marker; trim only that explicit suffix.
    if #s >= 2 and string.sub(s, -2) == " ^" then
        s = string.sub(s, 1, -3)
    end

    -- Strip realm/name grammar segment suffix from first '^' onward.
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

local function ArchtypeIndexFromExperienceBonus(expBonus)
    if expBonus == nil then
        return nil
    end
    local s = expBonus
    if type(s) == "wstring" and type(WStringToString) == "function" then
        s = WStringToString(s)
    end
    if type(s) ~= "string" then
        s = tostring(s)
    end
    if s == nil or s == "" then
        return nil
    end
    return tonumber(string.sub(s, -1))
end

--- Store scoreboard archtype. 0 is meaningful (primary / heal) and clears a stale alt-spec entry.
local function RememberArchtypeForName(name, archtypeIndex)
    local key = UnitFramesArchetypes.NormalizeLookupName(name, true)
    if not key then
        return
    end
    local arch = tonumber(archtypeIndex)
    if arch == nil then
        return
    end
    if arch < 0 then
        arch = 0
    end
    archtypeByNormalizedName[key] = arch
end

function UnitFramesArchetypes.ClearArchtypeCache()
    archtypeByNormalizedName = {}
end

--- Parse a GRP_STATS chat packet and cache active-spec indices by player name.
function UnitFramesArchetypes.IngestGrpStatsPacket(text)
    if text == nil or text == "" then
        return
    end
    if type(json) ~= "table" or type(json.decode) ~= "function" then
        return
    end

    local payload = string.gsub(text, "GRP_STATS:", "")
    local ok, tbl = CustomUI.TryCallQuiet("UnitFramesArchetypes.json.decode", json.decode, payload)
    if not ok or type(tbl) ~= "table" then
        return
    end

    local scoreboard = tbl.scoreboard
    if type(scoreboard) ~= "table" or scoreboard.name == nil then
        return
    end

    -- Explicitly remember 0 so switching heal←DPS clears the orange alt-spec tint.
    RememberArchtypeForName(scoreboard.name, tonumber(scoreboard.archetype) or 0)
end

--- Merge any rows already held by RoRGroupScoreboard into the local cache.
function UnitFramesArchetypes.SyncCacheFromScoreboard()
    if RoRGroupScoreboard == nil or RoRGroupScoreboard.playersDataRaw == nil then
        return
    end
    for _, pdata in pairs(RoRGroupScoreboard.playersDataRaw) do
        if pdata and pdata.name then
            RememberArchtypeForName(pdata.name, tonumber(pdata.archtype) or 0)
        end
    end
end

--- Live scoreboard row for a player name, if present.
local function FindScoreboardArchtype(playerNameStr)
    if not playerNameStr or not RoRGroupScoreboard or not RoRGroupScoreboard.playersDataRaw then
        return nil, false
    end

    for _, pdata in pairs(RoRGroupScoreboard.playersDataRaw) do
        if pdata and pdata.name then
            local scoreboardNameStr = UnitFramesArchetypes.NormalizeLookupName(pdata.name, true)
            if scoreboardNameStr and scoreboardNameStr ~= "" then
                if NamesProbablyMatch(playerNameStr, scoreboardNameStr) then
                    local archtypeIndex = tonumber(pdata.archtype) or 0
                    RememberArchtypeForName(pdata.name, archtypeIndex)
                    return archtypeIndex, true
                end
            end
        end
    end

    return nil, false
end

local function FindScenarioArchtype(playerNameStr)
    if not playerNameStr or type(GameData.GetScenarioPlayers) ~= "function" then
        return nil, false
    end

    local scenarioPlayers = GameData.GetScenarioPlayers()
    if not scenarioPlayers or type(scenarioPlayers) ~= "table" then
        return nil, false
    end

    for _, player in ipairs(scenarioPlayers) do
        if player and player.name then
            local scenarioNameStr = UnitFramesArchetypes.NormalizeLookupName(player.name, true)
            if scenarioNameStr and scenarioNameStr ~= "" then
                if NamesProbablyMatch(playerNameStr, scenarioNameStr) then
                    local archtypeIndex = ArchtypeIndexFromExperienceBonus(player.experiencebonus)
                    if archtypeIndex ~= nil then
                        RememberArchtypeForName(player.name, archtypeIndex)
                        return archtypeIndex, true
                    end
                    return nil, true
                end
            end
        end
    end

    return nil, false
end

--- Returns `archtypeIndex, matched`.
--- archtypeIndex: 0 = primary career role; >0 = alt-spec (DPS for hybrid healers).
--- Prefer live scoreboard over cache so heal-after-DPS updates are not stuck orange.
function UnitFramesArchetypes.ResolveOverrideIndexForPlayer(playerName)
    if playerName == nil then
        return nil, false
    end

    local playerNameStr = UnitFramesArchetypes.NormalizeLookupName(playerName, true)
    if not playerNameStr or playerNameStr == "" then
        return nil, false
    end

    local liveArch, liveMatched = FindScoreboardArchtype(playerNameStr)
    if liveMatched then
        return liveArch, true
    end

    local scenarioArch, scenarioMatched = FindScenarioArchtype(playerNameStr)
    if scenarioMatched then
        return scenarioArch, true
    end

    local cached = archtypeByNormalizedName[playerNameStr]
    if cached ~= nil then
        return cached, true
    end

    return nil, false
end

--- Map scoreboard archtype + career to CustomUI.Archetypes palette id.
--- >0 = alt-spec → DPS for heal careers (OpenParty / scoreboard ArchType overlay).
--- 0 / nil = primary → career-line archetype (WP heal stays green).
function UnitFramesArchetypes.MapOverrideIndexToPalette(index, careerLine)
    local careerArch = CustomUI.Archetypes.GetArchetypeForCareerLine(careerLine)
    local numericIndex = tonumber(index)

    if numericIndex ~= nil and numericIndex > 0 then
        if careerArch == CustomUI.Archetypes.HEAL then
            return CustomUI.Archetypes.DPS
        end
        -- Non-heal careers: alt-spec icon does not change tank/dps palette.
        return careerArch or CustomUI.Archetypes.DPS
    end

    return careerArch
end

--- True when scoreboard/scenario says this player is on alt-spec (archtype > 0).
function UnitFramesArchetypes.IsAltSpec(playerName)
    local overrideIndex, matched = UnitFramesArchetypes.ResolveOverrideIndexForPlayer(playerName)
    return matched == true and tonumber(overrideIndex) ~= nil and tonumber(overrideIndex) > 0
end

--- Returns `r, g, b, matchedPlayerRow`.
function UnitFramesArchetypes.ResolvePaletteRgbForPlayer(playerName, careerLine)
    local overrideIndex, matched = UnitFramesArchetypes.ResolveOverrideIndexForPlayer(playerName)
    if not matched then
        return nil, nil, nil, false
    end

    local effectiveArch = UnitFramesArchetypes.MapOverrideIndexToPalette(overrideIndex, careerLine)
    local r, g, b = CustomUI.Archetypes.GetColorForArchetype(effectiveArch)
    if r and g and b then
        return r, g, b, true
    end

    return nil, nil, nil, true
end
