----------------------------------------------------------------
-- CustomUI.KillTracker.AbilityMap — ability name → iconNum (best-effort)
----------------------------------------------------------------
if not CustomUI then CustomUI = {} end
CustomUI.KillTracker = CustomUI.KillTracker or {}
CustomUI.KillTracker.AbilityMap = CustomUI.KillTracker.AbilityMap or {}

local AbilityMap = CustomUI.KillTracker.AbilityMap

AbilityMap.ByName = AbilityMap.ByName or {}
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

local function Put(name, iconNum)
	local key = NormKey(name)
	iconNum = tonumber(iconNum)
	if not key or not iconNum or iconNum <= 0 then
		return
	end
	if AbilityMap.ByName[key] == nil then
		AbilityMap.ByName[key] = iconNum
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
	for _, ability in pairs(tbl) do
		if type(ability) == "table" and ability.name and ability.iconNum then
			Put(ability.name, ability.iconNum)
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
	for _, entry in pairs(ac.entries) do
		if type(entry) == "table" and entry.name and entry.iconNum then
			Put(entry.name, entry.iconNum)
		end
	end
end

local function IngestWarbuilderEntry(e)
	if type(e) ~= "table" or not e.ID then
		return
	end
	local iconNum = tonumber(e.Icon)
	if not iconNum or iconNum <= 0 then
		return
	end
	if type(GetAbilityName) == "function" then
		local ok, name = CustomUI.TryCallQuiet("KillTracker.GetAbilityName", GetAbilityName, e.ID)
		if ok and name and name ~= L"" then
			Put(name, iconNum)
		end
	end
end

local function IndexWarbuilder()
	if type(Warbuilder) ~= "table" or type(Warbuilder.Career) ~= "table" then
		return
	end
	for _, career in pairs(Warbuilder.Career) do
		if type(career) == "table" then
			if career.Core then
				for _, list in pairs({ career.Core.Ability, career.Core.Tactic, career.Core.Morale }) do
					if type(list) == "table" then
						for _, e in ipairs(list) do
							IngestWarbuilderEntry(e)
						end
					end
				end
			end
			if career.Path then
				for _, path in ipairs(career.Path) do
					if type(path) == "table" then
						if path.Core then
							for _, e in ipairs(path.Core) do
								IngestWarbuilderEntry(e)
							end
						end
						for _, e in ipairs(path) do
							IngestWarbuilderEntry(e)
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
	IndexLocalSpellbook()
	IndexSctCache()
	IndexWarbuilder()
	AbilityMap.Built = true
end

function AbilityMap.EnsureBuilt()
	if not AbilityMap.Built then
		AbilityMap.Rebuild()
	end
end

function AbilityMap.GetIconNum(abilityName)
	AbilityMap.EnsureBuilt()
	local key = NormKey(abilityName)
	if not key then
		return nil
	end
	return AbilityMap.ByName[key]
end

function AbilityMap.FormatIconMarkup(iconNum)
	iconNum = tonumber(iconNum)
	if not iconNum or iconNum <= 0 then
		return L""
	end
	return towstring(string.format("<icon%05d>", iconNum))
end
