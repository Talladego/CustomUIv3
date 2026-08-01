----------------------------------------------------------------
-- CustomUI.KillTracker.CareerCache — name → career icon (best-effort)
--
-- Scenario roster uses compact careerId values (Enemy.ScenarioCareerIdToLine /
-- UnitFramesScenario), not PartyUtils careerLine indices. Resolve via that map
-- first, then Icons.GetCareerIconIDFromCareerNamesID, then careerLine.
----------------------------------------------------------------
if not CustomUI then CustomUI = {} end
CustomUI.KillTracker = CustomUI.KillTracker or {}
CustomUI.KillTracker.CareerCache = CustomUI.KillTracker.CareerCache or {}

local CareerCache = CustomUI.KillTracker.CareerCache

-- key → { line = careerLine|nil, iconId = number|nil }
CareerCache.ByName = CareerCache.ByName or {}

-- Same table as UnitFramesScenario / ScenarioBalance / Enemy.ScenarioCareerIdToLine.
local c_SCENARIO_CAREER_ID_TO_LINE = {
	[20] = GameData.CareerLine.IRON_BREAKER,
	[100] = GameData.CareerLine.SWORDMASTER,
	[64] = GameData.CareerLine.CHOSEN,
	[24] = GameData.CareerLine.BLACK_ORC,
	[60] = GameData.CareerLine.WITCH_HUNTER,
	[102] = GameData.CareerLine.WHITE_LION,
	[65] = GameData.CareerLine.MARAUDER,
	[105] = GameData.CareerLine.WITCH_ELF,
	[62] = GameData.CareerLine.BRIGHT_WIZARD,
	[67] = GameData.CareerLine.MAGUS,
	[107] = GameData.CareerLine.SORCERER,
	[23] = GameData.CareerLine.ENGINEER,
	[101] = GameData.CareerLine.SHADOW_WARRIOR,
	[27] = GameData.CareerLine.SQUIG_HERDER,
	[63] = GameData.CareerLine.WARRIOR_PRIEST,
	[106] = GameData.CareerLine.DISCIPLE,
	[103] = GameData.CareerLine.ARCHMAGE,
	[26] = GameData.CareerLine.SHAMAN,
	[22] = GameData.CareerLine.RUNE_PRIEST,
	[66] = GameData.CareerLine.ZEALOT,
	[104] = GameData.CareerLine.BLACKGUARD,
	[61] = GameData.CareerLine.KNIGHT,
	[25] = GameData.CareerLine.CHOPPA,
	[21] = GameData.CareerLine.SLAYER or GameData.CareerLine.HAMMERER,
}

local function NameKey(name)
	local Parser = CustomUI.KillTracker.Parser
	if Parser and type(Parser.NormalizeNameKey) == "function" then
		return Parser.NormalizeNameKey(name)
	end
	if name == nil then
		return nil
	end
	local s = tostring(towstring(name))
	local caret = string.find(s, "^", 1, true)
	if caret then
		s = string.sub(s, 1, caret - 1)
	end
	s = string.lower((s:gsub("^%s+", ""):gsub("%s+$", "")))
	if s == "" then
		return nil
	end
	return s
end

local function IconFromCareerLine(careerLine)
	careerLine = tonumber(careerLine)
	if not careerLine or careerLine == 0 then
		return nil
	end
	if type(Icons) ~= "table" or type(Icons.GetCareerIconIDFromCareerLine) ~= "function" then
		return nil
	end
	local iconId = Icons.GetCareerIconIDFromCareerLine(careerLine)
	if not iconId or iconId == 0 then
		return nil
	end
	return iconId
end

local function IconFromCareerNamesId(careerNamesId)
	careerNamesId = tonumber(careerNamesId)
	if not careerNamesId or careerNamesId == 0 then
		return nil
	end
	if type(Icons) ~= "table" or type(Icons.GetCareerIconIDFromCareerNamesID) ~= "function" then
		return nil
	end
	local iconId = Icons.GetCareerIconIDFromCareerNamesID(careerNamesId)
	if not iconId or iconId == 0 then
		return nil
	end
	return iconId
end

local function CareerLineFromScenarioCareerId(careerId)
	careerId = tonumber(careerId)
	if not careerId then
		return nil
	end
	-- Prefer shared UnitFrames helper when loaded.
	if type(CustomUI.UnitFrames) == "table"
		and type(CustomUI.UnitFrames.Scenario) == "table"
		and type(CustomUI.UnitFrames.Scenario.GetCareerLineFromPlayer) == "function"
	then
		local line = CustomUI.UnitFrames.Scenario.GetCareerLineFromPlayer({ careerId = careerId })
		if line then
			return line
		end
	end
	return c_SCENARIO_CAREER_ID_TO_LINE[careerId]
end

local function Remember(name, careerLine, iconId, careerNamesId)
	local key = NameKey(name)
	if not key then
		return
	end

	careerLine = tonumber(careerLine)
	if careerLine == 0 then
		careerLine = nil
	end
	iconId = tonumber(iconId)
	if iconId == 0 then
		iconId = nil
	end
	careerNamesId = tonumber(careerNamesId)
	if careerNamesId == 0 then
		careerNamesId = nil
	end

	if not careerLine and careerNamesId then
		careerLine = CareerLineFromScenarioCareerId(careerNamesId)
	end
	if not iconId and careerLine then
		iconId = IconFromCareerLine(careerLine)
	end
	if not iconId and careerNamesId then
		iconId = IconFromCareerNamesId(careerNamesId)
	end
	-- Reverse-map careerNames icon → line when map missed.
	if not careerLine and iconId and type(Icons) == "table" and type(Icons.careerLines) == "table" then
		for lineIdx, lineIcon in pairs(Icons.careerLines) do
			if lineIcon == iconId then
				careerLine = lineIdx
				break
			end
		end
	end

	if not careerLine and not iconId then
		return
	end

	local entry = CareerCache.ByName[key]
	if type(entry) ~= "table" then
		entry = {}
		CareerCache.ByName[key] = entry
	end
	if careerLine then
		entry.line = careerLine
	end
	if iconId then
		entry.iconId = iconId
	end
end

function CareerCache.Clear()
	for k in pairs(CareerCache.ByName) do
		CareerCache.ByName[k] = nil
	end
end

function CareerCache.GetCareerLine(name)
	local key = NameKey(name)
	if not key then
		return nil
	end
	local entry = CareerCache.ByName[key]
	if type(entry) == "table" then
		return entry.line
	end
	-- Legacy: bare careerLine number
	if type(entry) == "number" then
		return entry
	end
	return nil
end

function CareerCache.GetCareerIconId(name)
	local key = NameKey(name)
	if not key then
		return nil
	end
	local entry = CareerCache.ByName[key]
	if type(entry) == "table" then
		if entry.iconId and entry.iconId ~= 0 then
			return entry.iconId
		end
		return IconFromCareerLine(entry.line)
	end
	if type(entry) == "number" then
		return IconFromCareerLine(entry)
	end
	return nil
end

local function IngestScenarioPlayer(player)
	if type(player) ~= "table" or not player.name then
		return
	end
	local careerId = tonumber(player.careerId)
	local careerLine = tonumber(player.careerLine)
	if (not careerLine or careerLine == 0) and careerId then
		careerLine = CareerLineFromScenarioCareerId(careerId)
	end
	if (not careerLine or careerLine == 0) and player.career then
		careerLine = tonumber(player.career)
	end
	Remember(player.name, careerLine, nil, careerId)
end

local function IngestScenarioPlayers()
	-- Preferred: GetScenarioPlayerGroups (has careerId for all scenario members).
	if type(GameData) == "table" and type(GameData.GetScenarioPlayerGroups) == "function" then
		local ok, groups = CustomUI.TryCallQuiet(
			"KillTracker.GetScenarioPlayerGroups",
			GameData.GetScenarioPlayerGroups
		)
		if ok and type(groups) == "table" then
			for _, player in pairs(groups) do
				IngestScenarioPlayer(player)
			end
		end
	end
	if type(GameData) == "table" and type(GameData.GetScenarioPlayers) == "function" then
		local ok, players = CustomUI.TryCallQuiet(
			"KillTracker.GetScenarioPlayers",
			GameData.GetScenarioPlayers
		)
		if ok and type(players) == "table" then
			for _, player in pairs(players) do
				IngestScenarioPlayer(player)
			end
		end
	end
end

local function IngestPartyMember(member)
	if type(member) ~= "table" or not member.name then
		return
	end
	Remember(member.name, member.careerLine or member.career, nil, member.careerId)
end

local function IngestParty()
	if type(GetGroupData) == "function" then
		local ok, data = CustomUI.TryCallQuiet("KillTracker.GetGroupData", GetGroupData)
		if ok and type(data) == "table" then
			for _, member in pairs(data) do
				IngestPartyMember(member)
			end
		end
	end
	if type(PartyUtils) == "table" and type(PartyUtils.GetPartyData) == "function" then
		local ok, data = CustomUI.TryCallQuiet("KillTracker.GetPartyData", PartyUtils.GetPartyData)
		if ok and type(data) == "table" then
			for _, member in pairs(data) do
				IngestPartyMember(member)
			end
		end
	end
	if type(GetBattlegroupMemberData) == "function" then
		local ok, bands = CustomUI.TryCallQuiet("KillTracker.GetBattlegroupMemberData", GetBattlegroupMemberData)
		if ok and type(bands) == "table" then
			for _, party in pairs(bands) do
				if type(party) == "table" then
					for _, member in pairs(party) do
						IngestPartyMember(member)
					end
				end
			end
		end
	end
end

local function IngestTarget(unitId)
	if type(TargetInfo) ~= "table" then
		return
	end
	local name
	local career
	if type(TargetInfo.UnitName) == "function" then
		name = TargetInfo:UnitName(unitId)
	end
	if type(TargetInfo.UnitCareer) == "function" then
		career = TargetInfo:UnitCareer(unitId)
	end
	if name and career then
		Remember(name, career, nil, nil)
	end
end

local function IngestScoreboard()
	if type(RoRGroupScoreboard) ~= "table" or type(RoRGroupScoreboard.playersDataRaw) ~= "table" then
		return
	end
	for _, pdata in pairs(RoRGroupScoreboard.playersDataRaw) do
		if type(pdata) == "table" and pdata.name then
			Remember(pdata.name, pdata.career, pdata.careerIcon, nil)
		end
	end
end

function CareerCache.RefreshFromWorld()
	IngestScenarioPlayers()
	IngestParty()
	IngestScoreboard()
	IngestTarget("selfhostiletarget")
	IngestTarget("selffriendlytarget")
	IngestTarget("mouseovertarget")
end

function CareerCache.OnTargetUpdated()
	IngestTarget("selfhostiletarget")
	IngestTarget("selffriendlytarget")
	IngestTarget("mouseovertarget")
end

function CareerCache.Remember(name, careerLine, iconId, careerNamesId)
	Remember(name, careerLine, iconId, careerNamesId)
end
