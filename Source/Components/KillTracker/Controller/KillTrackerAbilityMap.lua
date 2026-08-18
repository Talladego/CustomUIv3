----------------------------------------------------------------
-- CustomUI.KillTracker.AbilityMap — ability name → iconNum
--
-- Duplicate ability names exist across careers (e.g. Witch Hunter Torment
-- 8085 vs Disciple Torment). Resolve with killer career when known.
-- Local player deathblows: prefer live spellbook (GetAbilityTable /
-- GetAbilityData iconNum; GetAbilityIcon if the client exposes it).
----------------------------------------------------------------
if not CustomUI then CustomUI = {} end
CustomUI.KillTracker = CustomUI.KillTracker or {}
CustomUI.KillTracker.AbilityMap = CustomUI.KillTracker.AbilityMap or {}

local AbilityMap = CustomUI.KillTracker.AbilityMap

-- Flat name → icon (only when a single career owns that name)
AbilityMap.ByName = AbilityMap.ByName or {}
-- name → true when multiple careers share the name (do not use ByName)
AbilityMap.Ambiguous = AbilityMap.Ambiguous or {}
-- careerLine → { nameKey → iconNum }
AbilityMap.ByCareerLine = AbilityMap.ByCareerLine or {}
-- nameKey → abilityId (local spellbook), for GetAbilityData / GetAbilityIcon
AbilityMap.LocalIdByName = AbilityMap.LocalIdByName or {}
-- nameKey → set of careerLines that indexed this ability name
AbilityMap.NameOwners = AbilityMap.NameOwners or {}
-- nameKey → careerLine when exactly one career owns the name
AbilityMap.CareerLineByName = AbilityMap.CareerLineByName or {}
AbilityMap.Built = false

local function NormKey(name)
	if name == nil then
		return nil
	end
	local s = tostring(towstring(name))
	s = string.gsub(s, "%^.", "")
	s = string.gsub(s, "^%s+", "")
	s = string.gsub(s, "%s+$", "")
	if s == "" then
		return nil
	end
	return string.lower(s)
end

local function NameKeyPlayer(name)
	local Parser = CustomUI.KillTracker.Parser
	if Parser and type(Parser.NormalizeNameKey) == "function" then
		return Parser.NormalizeNameKey(name)
	end
	return NormKey(name)
end

local function IsLocalPlayerName(name)
	local selfName = GameData and GameData.Player and GameData.Player.name
	if not selfName or not name then
		return false
	end
	local a = NameKeyPlayer(name)
	local b = NameKeyPlayer(selfName)
	return a ~= nil and a == b
end

local function IconFromAbilityId(abilityId)
	abilityId = tonumber(abilityId)
	if not abilityId or abilityId <= 0 then
		return nil
	end
	-- Some clients may expose GetAbilityIcon(id); stock RoR uses GetAbilityData.iconNum.
	if type(GetAbilityIcon) == "function" then
		local ok, icon = CustomUI.TryCallQuiet("KillTracker.GetAbilityIcon", GetAbilityIcon, abilityId)
		icon = tonumber(icon)
		if ok and icon and icon > 0 then
			return icon
		end
	end
	if type(GetAbilityData) == "function" then
		local ok, data = CustomUI.TryCallQuiet("KillTracker.GetAbilityData", GetAbilityData, abilityId)
		if ok and type(data) == "table" then
			local icon = tonumber(data.iconNum)
			if icon and icon > 0 then
				return icon
			end
		end
	end
	return nil
end

local function PutCareer(careerLine, name, iconNum)
	careerLine = tonumber(careerLine)
	local key = NormKey(name)
	iconNum = tonumber(iconNum)
	if not careerLine or careerLine <= 0 or not key or not iconNum or iconNum <= 0 then
		return
	end
	local bucket = AbilityMap.ByCareerLine[careerLine]
	if type(bucket) ~= "table" then
		bucket = {}
		AbilityMap.ByCareerLine[careerLine] = bucket
	end
	if bucket[key] == nil then
		bucket[key] = iconNum
	end

	-- Track which careers own this ability name (for open-RvR career icon inference).
	local owners = AbilityMap.NameOwners[key]
	if type(owners) ~= "table" then
		owners = {}
		AbilityMap.NameOwners[key] = owners
	end
	owners[careerLine] = true
	local onlyLine = nil
	local ownerCount = 0
	for line in pairs(owners) do
		ownerCount = ownerCount + 1
		onlyLine = line
	end
	if ownerCount == 1 then
		AbilityMap.CareerLineByName[key] = onlyLine
	else
		AbilityMap.CareerLineByName[key] = nil
	end

	if AbilityMap.Ambiguous[key] then
		AbilityMap.ByName[key] = nil
		return
	end
	local existing = AbilityMap.ByName[key]
	if existing == nil then
		AbilityMap.ByName[key] = iconNum
	elseif existing ~= iconNum then
		AbilityMap.Ambiguous[key] = true
		AbilityMap.ByName[key] = nil
	end
end

local function IndexAbilityTable(abilityType)
	if type(GetAbilityTable) ~= "function" or abilityType == nil then
		return
	end
	local ok, tbl = CustomUI.TryCallQuiet("KillTracker.GetAbilityTable", GetAbilityTable, abilityType)
	if not ok or type(tbl) ~= "table" then
		return
	end
	local selfLine = tonumber(GameData and GameData.Player and GameData.Player.career and GameData.Player.career.line)
	for _, ability in pairs(tbl) do
		if type(ability) == "table" and ability.name then
			local iconNum = tonumber(ability.iconNum)
			local id = tonumber(ability.id) or tonumber(ability.abilityId)
			if (not iconNum or iconNum <= 0) and id then
				iconNum = IconFromAbilityId(id)
			end
			if iconNum and iconNum > 0 then
				local key = NormKey(ability.name)
				if key then
					AbilityMap.LocalIdByName[key] = id
					if selfLine then
						PutCareer(selfLine, ability.name, iconNum)
					end
				end
			end
		end
	end
end

local function IndexLocalSpellbook()
	if type(GameData) ~= "table" or type(GameData.AbilityType) ~= "table" then
		return
	end
	local types = {
		GameData.AbilityType.STANDARD,
		GameData.AbilityType.TACTIC,
		GameData.AbilityType.PASSIVE,
		GameData.AbilityType.GRANTED,
		GameData.AbilityType.PET,
		GameData.AbilityType.MORALE,
	}
	for i = 1, #types do
		IndexAbilityTable(types[i])
	end
end

--- Live spellbook lookup for the local player's abilities (not the static map).
local function LookupLocalSpellbook(abilityName)
	local key = NormKey(abilityName)
	if not key then
		return nil
	end

	local cachedId = AbilityMap.LocalIdByName[key]
	if cachedId then
		local icon = IconFromAbilityId(cachedId)
		if icon then
			return icon
		end
	end

	if type(GetAbilityTable) ~= "function" or type(GameData) ~= "table" or type(GameData.AbilityType) ~= "table" then
		return nil
	end
	local types = {
		GameData.AbilityType.STANDARD,
		GameData.AbilityType.GRANTED,
		GameData.AbilityType.MORALE,
		GameData.AbilityType.TACTIC,
		GameData.AbilityType.PASSIVE,
		GameData.AbilityType.PET,
	}
	for i = 1, #types do
		local ok, tbl = CustomUI.TryCallQuiet("KillTracker.GetAbilityTable.live", GetAbilityTable, types[i])
		if ok and type(tbl) == "table" then
			for _, ability in pairs(tbl) do
				if type(ability) == "table" and NormKey(ability.name) == key then
					local id = tonumber(ability.id) or tonumber(ability.abilityId)
					if id then
						AbilityMap.LocalIdByName[key] = id
						local fromApi = IconFromAbilityId(id)
						if fromApi then
							return fromApi
						end
					end
					local iconNum = tonumber(ability.iconNum)
					if iconNum and iconNum > 0 then
						return iconNum
					end
				end
			end
		end
	end
	return nil
end

local function IndexSctCache()
	if type(CustomUI.SCT) ~= "table" or type(CustomUI.SCT.GetSettings) ~= "function" then
		return
	end
	local ok, settings = CustomUI.TryCallQuiet("KillTracker.SCT.GetSettings", CustomUI.SCT.GetSettings)
	if not ok or type(settings) ~= "table" then
		return
	end
	local ac = settings.abilityIconCache
	if type(ac) ~= "table" or type(ac.entries) ~= "table" then
		return
	end
	-- SCT cache is abilityId-keyed; names alone can collide — only fill unique ByName.
	for _, entry in pairs(ac.entries) do
		if type(entry) == "table" and entry.name and entry.iconNum then
			local key = NormKey(entry.name)
			local iconNum = tonumber(entry.iconNum)
			if key and iconNum and iconNum > 0 and not AbilityMap.Ambiguous[key] then
				local existing = AbilityMap.ByName[key]
				if existing == nil then
					AbilityMap.ByName[key] = iconNum
				elseif existing ~= iconNum then
					AbilityMap.Ambiguous[key] = true
					AbilityMap.ByName[key] = nil
				end
			end
		end
	end
end

local function IngestWarbuilderEntry(careerLine, e)
	if type(e) ~= "table" or not e.ID then
		return
	end
	local iconNum = tonumber(e.Icon)
	if not iconNum or iconNum <= 0 then
		iconNum = IconFromAbilityId(e.ID)
	end
	if not iconNum or iconNum <= 0 then
		return
	end
	if type(GetAbilityName) ~= "function" then
		return
	end
	local ok, name = CustomUI.TryCallQuiet("KillTracker.GetAbilityName", GetAbilityName, e.ID)
	if ok and name and name ~= L"" then
		PutCareer(careerLine, name, iconNum)
	end
end

local function IndexWarbuilder()
	if type(Warbuilder) ~= "table" or type(Warbuilder.Career) ~= "table" then
		return
	end
	for _, career in pairs(Warbuilder.Career) do
		if type(career) == "table" then
			local careerLine = tonumber(career.Line)
			if careerLine and careerLine > 0 then
				if career.Core then
					for _, list in pairs({ career.Core.Ability, career.Core.Tactic, career.Core.Morale }) do
						if type(list) == "table" then
							for _, e in ipairs(list) do
								IngestWarbuilderEntry(careerLine, e)
							end
						end
					end
				end
				if career.Path then
					for _, path in ipairs(career.Path) do
						if type(path) == "table" then
							if path.Core then
								for _, e in ipairs(path.Core) do
									IngestWarbuilderEntry(careerLine, e)
								end
							end
							for _, e in ipairs(path) do
								IngestWarbuilderEntry(careerLine, e)
							end
						end
					end
				end
			end
		end
	end
end

function AbilityMap.Rebuild()
	for k in pairs(AbilityMap.ByName) do
		AbilityMap.ByName[k] = nil
	end
	for k in pairs(AbilityMap.Ambiguous) do
		AbilityMap.Ambiguous[k] = nil
	end
	for k in pairs(AbilityMap.LocalIdByName) do
		AbilityMap.LocalIdByName[k] = nil
	end
	for k in pairs(AbilityMap.CareerLineByName) do
		AbilityMap.CareerLineByName[k] = nil
	end
	for k, owners in pairs(AbilityMap.NameOwners) do
		if type(owners) == "table" then
			for line in pairs(owners) do
				owners[line] = nil
			end
		end
		AbilityMap.NameOwners[k] = nil
	end
	for line, bucket in pairs(AbilityMap.ByCareerLine) do
		if type(bucket) == "table" then
			for k in pairs(bucket) do
				bucket[k] = nil
			end
		end
		AbilityMap.ByCareerLine[line] = nil
	end
	IndexLocalSpellbook()
	IndexWarbuilder()
	IndexSctCache()
	AbilityMap.Built = true
end

function AbilityMap.EnsureBuilt()
	if not AbilityMap.Built then
		AbilityMap.Rebuild()
	end
end

--- Career line when exactly one career owns this ability name (nil if shared / unknown).
function AbilityMap.GetUniqueCareerLine(abilityName)
	AbilityMap.EnsureBuilt()
	local key = NormKey(abilityName)
	if not key then
		return nil
	end
	return tonumber(AbilityMap.CareerLineByName[key])
end

--- Resolve icon for an ability on a kill line.
--- @param abilityName wstring|string
--- @param killerName wstring|string|nil killer from the kill message (for career disambiguation)
function AbilityMap.GetIconNum(abilityName, killerName)
	AbilityMap.EnsureBuilt()
	local key = NormKey(abilityName)
	if not key then
		return nil
	end

	-- Local player: always prefer live spellbook / GetAbilityData (or GetAbilityIcon).
	if killerName and IsLocalPlayerName(killerName) then
		local localIcon = LookupLocalSpellbook(abilityName)
		if localIcon then
			return localIcon
		end
	end

	local careerLine = nil
	local CareerCache = CustomUI.KillTracker.CareerCache
	if killerName and CareerCache and type(CareerCache.GetCareerLine) == "function" then
		careerLine = tonumber(CareerCache.GetCareerLine(killerName))
	end
	if careerLine and careerLine > 0 then
		local bucket = AbilityMap.ByCareerLine[careerLine]
		if type(bucket) == "table" and bucket[key] then
			return bucket[key]
		end
	end

	-- Unique name across careers only.
	if not AbilityMap.Ambiguous[key] then
		return AbilityMap.ByName[key]
	end
	return nil
end
