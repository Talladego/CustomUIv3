----------------------------------------------------------------
-- CustomUI.KillTracker.Format — shared enriched kill line + row model
--
-- Compact chat format:
--   [careerIcon]<Killer>[killCount] killed [careerIcon]<Victim>[deathCount] with [abilityIcon]<Ability>[ in Zone]
--
-- Zone suffix only for open-world RvR (not scenario / city siege).
-- Colors: white filter base; player names realm LINK (Order blue / Destruction red);
-- ability names gold LINK.
----------------------------------------------------------------
if not CustomUI then CustomUI = {} end
CustomUI.KillTracker = CustomUI.KillTracker or {}
CustomUI.KillTracker.Format = CustomUI.KillTracker.Format or {}

local Format = CustomUI.KillTracker.Format

local c_ORDER_RGB = { 0, 148, 225 }
local c_DESTRO_RGB = { 255, 39, 39 }
local c_ABILITY_RGB = { 255, 180, 40 }

function Format.GetRealmColors(filterType)
	local order = SystemData.ChatLogFilters.RVR_KILLS_ORDER
	local destro = SystemData.ChatLogFilters.RVR_KILLS_DESTRUCTION
	if filterType == order then
		return c_ORDER_RGB, c_DESTRO_RGB -- killer Order, victim Destruction
	end
	if filterType == destro then
		return c_DESTRO_RGB, c_ORDER_RGB
	end
	return c_ORDER_RGB, c_DESTRO_RGB
end

local function LinkText(text, rgb)
	local plain = tostring(towstring(text or L""))
	plain = string.gsub(plain, "\"", "")
	if plain == "" then
		return L""
	end
	local colored = string.format(
		"<LINK data=\"0\" color=\"%d,%d,%d\" text=\"%s\">",
		rgb[1],
		rgb[2],
		rgb[3],
		plain
	)
	return towstring(colored)
end

local function FormatIconMarkup(iconId)
	iconId = tonumber(iconId)
	if not iconId or iconId <= 0 then
		return L""
	end
	return towstring(string.format("<icon%05d>", iconId))
end

local function CareerIconMarkup(name, settings)
	if settings.showCareerIcons == false then
		return L""
	end
	local CareerCache = CustomUI.KillTracker.CareerCache
	local iconId = CareerCache and CareerCache.GetCareerIconId(name)
	return FormatIconMarkup(iconId)
end

local function AbilityIconMarkup(abilityName, settings)
	if settings.showAbilityIcons == false then
		return L""
	end
	if abilityName == nil or abilityName == L"" then
		return L""
	end
	local AbilityMap = CustomUI.KillTracker.AbilityMap
	local iconNum = AbilityMap and AbilityMap.GetIconNum(abilityName)
	return FormatIconMarkup(iconNum)
end

local function CountBracket(count, enabled)
	if enabled == false then
		return L""
	end
	count = tonumber(count) or 0
	if count <= 0 then
		return L""
	end
	return L"[" .. towstring(count) .. L"]"
end

local function ResolveZoneLabel(parsed)
	if parsed and parsed.zone and parsed.zone ~= L"" then
		return parsed.zone
	end
	local zoneId = GameData and GameData.Player and GameData.Player.zone
	if zoneId and type(GetZoneName) == "function" then
		local name = GetZoneName(zoneId)
		if name and name ~= L"" then
			return name
		end
	end
	return L""
end

--- True when open-world RvR (not scenario / city siege).
local function ShouldShowZone(settings)
	if settings.showZone == false then
		return false
	end
	local Session = CustomUI.KillTracker.Session
	if Session and type(Session.GetContext) == "function" then
		return Session.GetContext() == "rvr"
	end
	local p = GameData and GameData.Player
	if type(p) == "table" and (p.isInScenario == true or p.isInSiege == true) then
		return false
	end
	return true
end

--- Build display model + chat wstring.
--- Format: [career]<Killer>[kills] killed [career]<Victim>[deaths] with [ability]<Ability>[ in Zone]
function Format.Build(parsed, filterType, killCount, deathCount, settings)
	settings = settings or {}
	local killerRgb, victimRgb = Format.GetRealmColors(filterType)

	local killerIcon = CareerIconMarkup(parsed.killer, settings)
	local victimIcon = CareerIconMarkup(parsed.victim, settings)
	local abilityIcon = AbilityIconMarkup(parsed.ability, settings)

	local killerLink = LinkText(parsed.killer, killerRgb)
	local victimLink = LinkText(parsed.victim, victimRgb)

	local killBracket = CountBracket(killCount, settings.showKillCount)
	local deathBracket = CountBracket(deathCount, settings.showKillCount)

	local line = killerIcon .. killerLink .. killBracket
		.. L" killed "
		.. victimIcon .. victimLink .. deathBracket

	if parsed.ability and parsed.ability ~= L"" then
		line = line .. L" with " .. abilityIcon .. LinkText(parsed.ability, c_ABILITY_RGB)
	end

	local zone = L""
	if ShouldShowZone(settings) then
		zone = ResolveZoneLabel(parsed)
		if zone ~= L"" then
			line = line .. L" in " .. zone
		end
	end

	return {
		chatText = line,
		victim = parsed.victim,
		killer = parsed.killer,
		verb = parsed.verb,
		ability = parsed.ability,
		zone = zone ~= L"" and zone or (parsed.zone or L""),
		streak = parsed.streak,
		killCount = killCount or 0,
		deathCount = deathCount or 0,
		killerRgb = killerRgb,
		victimRgb = victimRgb,
		victimCareerIcon = CustomUI.KillTracker.CareerCache.GetCareerIconId(parsed.victim),
		killerCareerIcon = CustomUI.KillTracker.CareerCache.GetCareerIconId(parsed.killer),
		abilityIconNum = CustomUI.KillTracker.AbilityMap.GetIconNum(parsed.ability),
		filterType = filterType,
	}
end
