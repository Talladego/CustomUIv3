----------------------------------------------------------------
-- CustomUI.UnitFrames.Archetypes
--
-- Shared player-name normalization and scoreboard/scenario archetype
-- override lookup used by UnitFrames sorting and per-player tinting.
----------------------------------------------------------------

if not CustomUI then
    CustomUI = {}
end

CustomUI.UnitFrames = CustomUI.UnitFrames or {}
CustomUI.UnitFrames.Archetypes = CustomUI.UnitFrames.Archetypes or {}

local UnitFramesArchetypes = CustomUI.UnitFrames.Archetypes

local c_SCOREBOARD_ARCHETYPE_TO_PALETTE = {
    [1] = CustomUI.Archetypes.TANK,
    [2] = CustomUI.Archetypes.DPS,
    [3] = CustomUI.Archetypes.DPS,
    [4] = CustomUI.Archetypes.HEAL,
}

-- Populated from GRP_STATS packets (and optionally RoRGroupScoreboard.playersDataRaw).
-- Key = NormalizeLookupName(name, false); value = scoreboard archetype index (1–4).
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

local function RememberArchtypeForName(name, archtypeIndex)
    local key = UnitFramesArchetypes.NormalizeLookupName(name, false)
    local arch = tonumber(archtypeIndex)
    if key and arch and arch > 0 then
        archtypeByNormalizedName[key] = arch
    end
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
    local ok, tbl = pcall(json.decode, payload)
    if not ok or type(tbl) ~= "table" then
        return
    end

    local scoreboard = tbl.scoreboard
    if type(scoreboard) ~= "table" or scoreboard.name == nil then
        return
    end

    RememberArchtypeForName(scoreboard.name, scoreboard.archetype)
end

--- Merge any rows already held by RoRGroupScoreboard into the local cache.
function UnitFramesArchetypes.SyncCacheFromScoreboard()
    if RoRGroupScoreboard == nil or RoRGroupScoreboard.playersDataRaw == nil then
        return
    end
    for _, pdata in pairs(RoRGroupScoreboard.playersDataRaw) do
        if pdata and pdata.name then
            RememberArchtypeForName(pdata.name, pdata.archtype)
        end
    end
end

--- Returns `overrideIndex, matchedPlayerRow`.
function UnitFramesArchetypes.ResolveOverrideIndexForPlayer(playerName)
    if playerName == nil then
        return nil, false
    end

    local playerNameStr = UnitFramesArchetypes.NormalizeLookupName(playerName, true)
    if not playerNameStr or playerNameStr == "" then
        return nil, false
    end

    local cached = archtypeByNormalizedName[playerNameStr]
    if cached and cached > 0 then
        return cached, true
    end

    if RoRGroupScoreboard and RoRGroupScoreboard.playersDataRaw then
        for _, pdata in pairs(RoRGroupScoreboard.playersDataRaw) do
            if pdata and pdata.name then
                local scoreboardNameStr = UnitFramesArchetypes.NormalizeLookupName(pdata.name, false)
                if scoreboardNameStr and scoreboardNameStr ~= "" then
                    if NamesProbablyMatch(playerNameStr, scoreboardNameStr) then
                        local archtypeIndex = tonumber(pdata.archtype)
                        if archtypeIndex and archtypeIndex > 0 then
                            RememberArchtypeForName(pdata.name, archtypeIndex)
                            return archtypeIndex, true
                        end
                        return nil, true
                    end
                end
            end
        end
    end

    if type(GameData.GetScenarioPlayers) == "function" then
        local scenarioPlayers = GameData.GetScenarioPlayers()
        if scenarioPlayers and type(scenarioPlayers) == "table" then
            for _, player in ipairs(scenarioPlayers) do
                if player and player.name then
                    local scenarioNameStr = UnitFramesArchetypes.NormalizeLookupName(player.name, true)
                    if scenarioNameStr and scenarioNameStr ~= "" then
                        if NamesProbablyMatch(playerNameStr, scenarioNameStr) then
                            local archtypeIndex = ArchtypeIndexFromExperienceBonus(player.experiencebonus)
                            if archtypeIndex and archtypeIndex > 0 then
                                RememberArchtypeForName(player.name, archtypeIndex)
                                return archtypeIndex, true
                            end
                            return nil, true
                        end
                    end
                end
            end
        end
    end

    return nil, false
end

function UnitFramesArchetypes.MapOverrideIndexToPalette(index, careerLine)
    local effectiveArch = nil
    local numericIndex = tonumber(index)
    if numericIndex and numericIndex > 0 then
        effectiveArch = c_SCOREBOARD_ARCHETYPE_TO_PALETTE[numericIndex]
    end

    if effectiveArch == nil then
        effectiveArch = CustomUI.Archetypes.GetArchetypeForCareerLine(careerLine)
        if effectiveArch == CustomUI.Archetypes.HEAL then
            effectiveArch = CustomUI.Archetypes.DPS
        end
    end

    return effectiveArch
end

--- Returns `r, g, b, matchedPlayerRow`.
function UnitFramesArchetypes.ResolvePaletteRgbForPlayer(playerName, careerLine)
    local overrideIndex, matched = UnitFramesArchetypes.ResolveOverrideIndexForPlayer(playerName)
    if not matched then
        return nil, nil, nil, false
    end

    if overrideIndex == nil then
        return nil, nil, nil, true
    end

    local effectiveArch = UnitFramesArchetypes.MapOverrideIndexToPalette(overrideIndex, careerLine)
    local r, g, b = CustomUI.Archetypes.GetColorForArchetype(effectiveArch)
    if r and g and b then
        return r, g, b, true
    end

    return nil, nil, nil, true
end
