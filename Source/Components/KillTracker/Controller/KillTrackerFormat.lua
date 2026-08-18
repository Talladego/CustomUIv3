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

-- Zone-tint diagnostics. Enable with: CustomUI.KillTracker.DebugZone = true
if CustomUI.KillTracker.DebugZone == nil then
	CustomUI.KillTracker.DebugZone = false
end

local c_ORDER_RGB = { 0, 148, 225 }
local c_DESTRO_RGB = { 255, 39, 39 }
local c_ABILITY_RGB = { 255, 180, 40 }
local c_COUNT_RGB = { 175, 175, 175 } -- grey, slightly darker than white
local c_ZONE_LOCAL_RGB = { 0, 255, 0 } -- green when kill zone == local zone (cmap-style)
local c_ZONE_OTHER_RGB = { 255, 255, 255 }

local function ZoneDebug(msg)
	if CustomUI.KillTracker.DebugZone ~= true then
		return
	end
	if type(msg) == "string" then
		msg = towstring(msg)
	end
	if type(msg) ~= "wstring" then
		msg = towstring(tostring(msg))
	end
	msg = L"[KT.Zone] " .. msg
	local dfn = (CustomUI.GetClientDebugLog and CustomUI.GetClientDebugLog()) or rawget(_G, "d")
	if type(dfn) == "function" then
		dfn(msg)
	end
	if LogLuaMessage and SystemData and SystemData.UiLogFilters then
		LogLuaMessage("Lua", SystemData.UiLogFilters.DEBUG, msg)
	end
end

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

local function AbilityIconMarkup(abilityName, killerName, settings)
	if settings.showAbilityIcons == false then
		return L""
	end
	if abilityName == nil or abilityName == L"" then
		return L""
	end
	local AbilityMap = CustomUI.KillTracker.AbilityMap
	local iconNum = AbilityMap and AbilityMap.GetIconNum(abilityName, killerName)
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
	return LinkText(L"[" .. towstring(count) .. L"]", c_COUNT_RGB)
end

local function ResolveZoneLabel(parsed)
	if parsed and parsed.zone and parsed.zone ~= L"" then
		return parsed.zone
	end
	return Format.GetLocalZoneName()
end

----------------------------------------------------------------
-- Local-zone match (WAR FixString style)
--
-- EZGuard / WarTriage FixString: strip "^grammar" and KEEP wstrings.
-- Converting area.name through tostring/WStringToString produces a different
-- byte length than kill-chat text (uilog: killLen=13 vs cacheLen=16) so Lua
-- string compare never succeeds. Compare as wstrings instead.
----------------------------------------------------------------

--- Same helper used by EZGuard / WarTriage (wstring in, wstring out).
local function FixString(str)
	if str == nil then
		return L""
	end
	local ws = str
	if type(ws) ~= "wstring" then
		ws = towstring(ws)
	end
	-- Work on a private copy so we never mutate GameData strings.
	ws = L"" .. ws
	local pos = ws:find(L"^", 1, true)
	if pos then
		ws = ws:sub(1, pos - 1)
	end
	return ws
end

local function WStringLower(ws)
	if ws == nil or ws == L"" then
		return L""
	end
	if wstring and type(wstring.lower) == "function" then
		return wstring.lower(ws)
	end
	-- Fallback only — prefer staying on wstring path.
	local s = tostring(ws)
	if type(s) == "string" and s ~= "" and string.find(s, "wstring", 1, true) ~= 1 then
		return towstring(string.lower(s))
	end
	return ws
end

local function ZonesEqualW(a, b)
	a = WStringLower(FixString(a))
	b = WStringLower(FixString(b))
	if a == nil or b == nil or a == L"" or b == L"" then
		return false
	end
	return a == b
end

-- Cached FixString'd area name (wstring).
Format._cachedAreaW = Format._cachedAreaW or L""

function Format.UpdateLocalAreaCache()
	local p = GameData and GameData.Player
	if type(p) == "table" and type(p.area) == "table" then
		local fixed = FixString(p.area.name)
		if fixed ~= nil and fixed ~= L"" and fixed ~= Format._cachedAreaW then
			Format._cachedAreaW = fixed
			ZoneDebug(L"cache area updated")
		end
	end
	return Format._cachedAreaW
end

function Format.GetLocalZoneName()
	Format.UpdateLocalAreaCache()
	if Format._cachedAreaW ~= nil and Format._cachedAreaW ~= L"" then
		return Format._cachedAreaW
	end
	local p = GameData and GameData.Player
	if p and p.zone ~= nil and type(GetZoneName) == "function" then
		local zoneName = FixString(GetZoneName(p.zone))
		if zoneName ~= L"" then
			return zoneName
		end
	end
	return L""
end

function Format.IsLocalZone(zoneLabel)
	local killW = FixString(zoneLabel)
	if killW == L"" then
		ZoneDebug(L"IsLocalZone: empty kill zone")
		return false
	end

	Format.UpdateLocalAreaCache()

	local candidates = {}
	local function Add(v)
		local f = FixString(v)
		if f ~= nil and f ~= L"" then
			candidates[#candidates + 1] = f
		end
	end

	Add(Format._cachedAreaW)
	local p = GameData and GameData.Player
	if type(p) == "table" then
		if type(p.area) == "table" then
			Add(p.area.name)
		end
		if p.zone ~= nil and type(GetZoneName) == "function" then
			Add(GetZoneName(p.zone))
		end
	end
	if type(MapGetPlayerLocationMaps) == "function" and type(GetZoneName) == "function" then
		local ok, maps = false, nil
		if type(CustomUI.TryCallQuiet) == "function" then
			ok, maps = CustomUI.TryCallQuiet("KillTracker.MapGetPlayerLocationMaps", MapGetPlayerLocationMaps)
		else
			ok, maps = pcall(MapGetPlayerLocationMaps)
		end
		if ok and type(maps) == "table" and maps[2] ~= nil then
			Add(GetZoneName(maps[2]))
		end
	end

	for i = 1, #candidates do
		if ZonesEqualW(killW, candidates[i]) then
			ZoneDebug(L"local zone match")
			return true
		end
	end

	ZoneDebug(L"local zone miss")
	return false
end

function Format.GetZoneTextRgb(zoneLabel)
	if Format.IsLocalZone(zoneLabel) then
		return c_ZONE_LOCAL_RGB
	end
	return c_ZONE_OTHER_RGB
end

--- True when open-world RvR (not scenario / city siege).
--- Uses flags only — do not call Session.GetContext() here (that Syncs and can
--- clear bags as a side effect while building a kill line).
local function ShouldShowZone(settings)
	if settings.showZone == false then
		return false
	end
	local Session = CustomUI.KillTracker.Session
	if Session and type(Session.IsMatchContext) == "function" and Session.IsMatchContext() then
		return false
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
	local abilityIcon = AbilityIconMarkup(parsed.ability, parsed.killer, settings)

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
			-- Match feed: green when kill zone is the player's current zone.
			if Format.IsLocalZone(zone) then
				line = line .. L" in " .. LinkText(zone, c_ZONE_LOCAL_RGB)
			else
				line = line .. L" in " .. zone
			end
		end
	end

	return {
		chatText = line,
		victim = parsed.victim,
		killer = parsed.killer,
		verb = parsed.verb,
		ability = parsed.ability,
		zone = zone,
		streak = parsed.streak,
		killCount = killCount or 0,
		deathCount = deathCount or 0,
		killerRgb = killerRgb,
		victimRgb = victimRgb,
		victimCareerIcon = CustomUI.KillTracker.CareerCache.GetCareerIconId(parsed.victim),
		killerCareerIcon = CustomUI.KillTracker.CareerCache.GetCareerIconId(parsed.killer),
		abilityIconNum = CustomUI.KillTracker.AbilityMap.GetIconNum(parsed.ability, parsed.killer),
		filterType = filterType,
	}
end
