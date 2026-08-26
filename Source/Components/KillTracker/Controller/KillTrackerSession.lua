----------------------------------------------------------------
-- CustomUI.KillTracker.Session — kill tallies (RAM only)
--
-- Counts are observed combat-log tallies only (+1 per captured kill line).
-- Scenario Summary is not used for brackets.
--
-- RvR: open-world session (survives zone loads; cleared on Disable)
-- Scenario/siege: one match instance — bag cleared when a *new* instance
--   begins, or when the player leaves. Mid-match mode/id churn must not wipe.
--
-- Lifecycle mirrors stock ScenarioSummaryWindow / ScenarioGroupWindow:
--   Begin: SCENARIO_BEGIN (authoritative)
--          LOADING_END + isInSiege (CITY_SCENARIO_BEGIN is unreliable)
--          LOADING_END + isInScenario + PRE_MODE (missed BEGIN / rematch)
--   Post:  SCENARIO_POST_MODE / SCENARIO_END while still inside → mark post
--          (keep counts for scoreboard; next begin always resets)
--   Leave: LOADING_END when not in scenario/siege, or roster update while out
--          (ScenarioGroupWindow also ends when list updates out of instance)
----------------------------------------------------------------
if not CustomUI then CustomUI = {} end
CustomUI.KillTracker = CustomUI.KillTracker or {}
CustomUI.KillTracker.Session = CustomUI.KillTracker.Session or {}

local Session = CustomUI.KillTracker.Session

Session.RvR = Session.RvR or { Kills = {} }
Session.Scenario = Session.Scenario or { Kills = {} }

-- Order/Destro kill totals for the current open-RvR campaign lake
-- (pairing + tier), not a single map zone. Praag/Reikland/Chaos Wastes (T4
-- EvC) and split T2/T3 lakes share one tally. Resets when leaving that lake,
-- on a new scenario/siege instance, or in non-campaign zones. Not on area name.
Session.ZoneScore = Session.ZoneScore or {
	orderKills = 0,
	destroKills = 0,
	zoneId = 0,
	scopeKey = nil,
	orderKillers = {},
	destroKillers = {},
}

-- Match-scope tracking (scenario / city siege instance)
Session._matchActive = Session._matchActive == true
Session._matchKind = Session._matchKind -- "scenario" | "siege" | nil
Session._matchPostMode = Session._matchPostMode == true -- combat over; next begin must reset
Session._lastMode = Session._lastMode
Session._lastZone = Session._lastZone
Session._lastScId = Session._lastScId
Session._announcedFocus = Session._announcedFocus -- "rvr" | "scenario" | "siege"

-- Legacy single bags (clear if present from older sessions)
if Session.Kills then
	for k in pairs(Session.Kills) do
		Session.Kills[k] = nil
	end
	Session.Kills = nil
end
if Session.Deaths then
	for k in pairs(Session.Deaths) do
		Session.Deaths[k] = nil
	end
	Session.Deaths = nil
end

local function NameKey(name)
	local Parser = CustomUI.KillTracker.Parser
	if Parser and type(Parser.NormalizeNameKey) == "function" then
		return Parser.NormalizeNameKey(name)
	end
	return nil
end

local function ClearBag(bag)
	if type(bag) ~= "table" then
		return
	end
	if type(bag.Kills) == "table" then
		for k in pairs(bag.Kills) do
			bag.Kills[k] = nil
		end
	else
		bag.Kills = {}
	end
	-- Drop legacy death tallies if present from older sessions.
	if type(bag.Deaths) == "table" then
		for k in pairs(bag.Deaths) do
			bag.Deaths[k] = nil
		end
		bag.Deaths = nil
	end
end

local function ScenarioMode()
	return tonumber(GameData and GameData.ScenarioData and GameData.ScenarioData.mode)
end

local function PlayerZone()
	return tonumber(GameData and GameData.Player and GameData.Player.zone) or 0
end

local function ScenarioId()
	return tonumber(GameData and GameData.ScenarioData and GameData.ScenarioData.id) or 0
end

local function CityScenarioId()
	return tonumber(GameData and GameData.CityScenarioData and GameData.CityScenarioData.id) or 0
end

--- Physically inside a scenario or city-siege instance.
--- Do not use isInScenarioGroup — it lingers in queue and is not an instance.
local function IsInMatchInstance()
	local p = GameData and GameData.Player
	if type(p) ~= "table" then
		return false
	end
	return p.isInScenario == true or p.isInSiege == true
end

local function MatchKind()
	local p = GameData and GameData.Player
	if type(p) ~= "table" then
		return nil
	end
	if p.isInSiege == true then
		return "siege"
	end
	if p.isInScenario == true then
		return "scenario"
	end
	return nil
end

--- Open-RvR lakes share GetCampaignZoneData pairingId+tierId (T4 three-zone
--- pairings, T2/T3 two-zone lakes). Cities, scenarios, and non-campaign maps
--- stay on their own key so a port to Altdorf does not keep the Praag tally.
local function GetScoreScopeKey()
	local zone = PlayerZone()
	if zone == 0 then
		return nil
	end
	if IsInMatchInstance() then
		return "m:" .. (MatchKind() or "match") .. ":" .. tostring(zone)
	end
	if GameDefs and type(GameDefs.ZoneCityIds) == "table" and GameDefs.ZoneCityIds[zone] ~= nil then
		return "c:" .. tostring(zone)
	end
	if type(GetCampaignZoneData) == "function" then
		local ok, data = false, nil
		if type(CustomUI.TryCallQuiet) == "function" then
			ok, data = CustomUI.TryCallQuiet("KillTracker.GetCampaignZoneData", GetCampaignZoneData, zone)
		else
			ok, data = true, GetCampaignZoneData(zone)
		end
		if ok and type(data) == "table" then
			local pairing = tonumber(data.pairingId) or 0
			local tier = tonumber(data.tierId) or 0
			if pairing > 0 and tier > 0 then
				return "p:" .. tostring(pairing) .. ":t:" .. tostring(tier)
			end
		end
	end
	return "z:" .. tostring(zone)
end

local function ClearKillerMap(map)
	if type(map) ~= "table" then
		return
	end
	for k in pairs(map) do
		map[k] = nil
	end
end

local c_ZONE_SUMMARY_TOP = 10

local function ZoneDisplayNameForId(zoneId)
	zoneId = tonumber(zoneId) or 0
	if zoneId > 0 and type(GetZoneName) == "function" then
		local name = GetZoneName(zoneId)
		if name ~= nil then
			local ws = name
			if type(ws) ~= "wstring" then
				ws = towstring(name)
			end
			ws = L"" .. ws
			local pos = ws:find(L"^", 1, true)
			if pos then
				ws = ws:sub(1, pos - 1)
			end
			if ws ~= L"" then
				return ws
			end
		end
	end
	return L"Zone"
end

--- Sorted killer list from a map without touching scope (safe before reset).
local function TopKillersFromMap(map, limit)
	local list = {}
	if type(map) ~= "table" then
		return list
	end
	limit = tonumber(limit) or c_ZONE_SUMMARY_TOP
	if limit < 1 then
		limit = 1
	end
	for _, entry in pairs(map) do
		if type(entry) == "table" then
			local count = tonumber(entry.count) or 0
			if count > 0 and entry.name ~= nil and entry.name ~= L"" then
				list[#list + 1] = { name = entry.name, count = count }
			end
		end
	end
	table.sort(list, function(a, b)
		if a.count ~= b.count then
			return a.count > b.count
		end
		return tostring(a.name or "") < tostring(b.name or "")
	end)
	if #list > limit then
		for i = #list, limit + 1, -1 do
			list[i] = nil
		end
	end
	return list
end

--- Chat summary of the lake/zone score about to be cleared (CustomUI.PrintMessage).
--- ASCII punctuation only in chat bodies (UTF-8 em dash → mojibake; see docs/api/lua-chat-strings.md).
local function ChatLinkText(text, rgb)
	local plain = tostring(towstring(text or L""))
	plain = string.gsub(plain, "\"", "")
	if plain == "" then
		return L""
	end
	rgb = rgb or { 255, 255, 255 }
	return towstring(string.format(
		"<LINK data=\"0\" color=\"%d,%d,%d\" text=\"%s\">",
		rgb[1] or 255,
		rgb[2] or 255,
		rgb[3] or 255,
		plain
	))
end

local function FactionRgbForChat(isOrder)
	local Format = CustomUI.KillTracker.Format
	if isOrder then
		if Format and type(Format.GetOrderRgb) == "function" then
			local rgb = Format.GetOrderRgb()
			if type(rgb) == "table" then
				return rgb
			end
		end
		return { 0, 148, 225 }
	end
	if Format and type(Format.GetDestroRgb) == "function" then
		local rgb = Format.GetDestroRgb()
		if type(rgb) == "table" then
			return rgb
		end
	end
	return { 255, 39, 39 }
end

local function FormatTopKillersLine(list)
	local bits = L""
	for i = 1, #list do
		local row = list[i]
		if bits ~= L"" then
			bits = bits .. L", "
		end
		bits = bits
			.. towstring(i)
			.. L". "
			.. towstring(row.name)
			.. L" "
			.. towstring(row.count)
	end
	return bits
end

local function AnnounceZoneScoreBeforeReset(score)
	if type(score) ~= "table" then
		return
	end
	if CustomUI.IsComponentEnabled and not CustomUI.IsComponentEnabled("KillTracker") then
		return
	end
	if type(CustomUI.PrintMessage) ~= "function" then
		return
	end

	local orderKills = tonumber(score.orderKills) or 0
	local destroKills = tonumber(score.destroKills) or 0
	if orderKills <= 0 and destroKills <= 0 then
		return
	end

	local place = ZoneDisplayNameForId(score.zoneId)
	local total = orderKills + destroKills
	local orderRgb = FactionRgbForChat(true)
	local destroRgb = FactionRgbForChat(false)

	CustomUI.PrintMessage(L"KillTracker: " .. place .. L" session ended.")
	CustomUI.PrintMessage(
		ChatLinkText(L"Order", orderRgb)
			.. L" kills: "
			.. ChatLinkText(towstring(orderKills), orderRgb)
			.. L"  |  "
			.. ChatLinkText(L"Destro", destroRgb)
			.. L" kills: "
			.. ChatLinkText(towstring(destroKills), destroRgb)
			.. L"  ("
			.. towstring(total)
			.. L" total)"
	)

	local orderTop = TopKillersFromMap(score.orderKillers, c_ZONE_SUMMARY_TOP)
	if #orderTop > 0 then
		CustomUI.PrintMessage(
			ChatLinkText(L"Top Order", orderRgb) .. L": " .. FormatTopKillersLine(orderTop)
		)
	end
	local destroTop = TopKillersFromMap(score.destroKillers, c_ZONE_SUMMARY_TOP)
	if #destroTop > 0 then
		CustomUI.PrintMessage(
			ChatLinkText(L"Top Destro", destroRgb) .. L": " .. FormatTopKillersLine(destroTop)
		)
	end
end

local function ResetZoneScore()
	local score = Session.ZoneScore
	if type(score) == "table" then
		AnnounceZoneScoreBeforeReset(score)
	end
	if type(score) ~= "table" then
		Session.ZoneScore = {
			orderKills = 0,
			destroKills = 0,
			zoneId = 0,
			scopeKey = nil,
			orderKillers = {},
			destroKillers = {},
		}
		score = Session.ZoneScore
	end
	score.orderKills = 0
	score.destroKills = 0
	score.zoneId = PlayerZone()
	score.scopeKey = GetScoreScopeKey()
	if type(score.orderKillers) ~= "table" then
		score.orderKillers = {}
	else
		ClearKillerMap(score.orderKillers)
	end
	if type(score.destroKillers) ~= "table" then
		score.destroKillers = {}
	else
		ClearKillerMap(score.destroKillers)
	end
end

local function BumpFactionKiller(map, killerName)
	local key = NameKey(killerName)
	if not key or type(map) ~= "table" then
		return
	end
	local entry = map[key]
	if type(entry) ~= "table" then
		entry = { name = towstring(killerName), count = 0 }
		map[key] = entry
	end
	entry.count = (tonumber(entry.count) or 0) + 1
	if killerName ~= nil and killerName ~= L"" then
		entry.name = towstring(killerName)
	end
end

--- Bind totals to the current campaign lake (or zone if none). Ignores zone 0.
--- Does not touch per-player bags. @return boolean true if the score was reset
local function EnsureZoneScoreScope()
	local key = GetScoreScopeKey()
	if key == nil then
		return false
	end
	local score = Session.ZoneScore
	if type(score) ~= "table" then
		ResetZoneScore()
		return true
	end
	if score.scopeKey == key then
		score.zoneId = PlayerZone()
		return false
	end
	ResetZoneScore()
	return true
end

local function CaptureIdentity()
	local kind = MatchKind()
	if not kind then
		return nil
	end
	local zone = PlayerZone()
	local id = (kind == "siege") and CityScenarioId() or ScenarioId()
	return {
		kind = kind,
		zone = zone,
		id = id,
		mode = ScenarioMode(),
	}
end

--- Same instance if kind+zone match; id 0→N is an enrich, not a new match.
--- After POST_MODE, never treat the next enter as the same instance.
local function SameInstance(prevKind, prevZone, prevId, ident)
	if Session._matchPostMode == true then
		return false
	end
	if not ident or not prevKind then
		return false
	end
	if ident.kind ~= prevKind then
		return false
	end
	local prevZ = tonumber(prevZone) or 0
	local newZ = tonumber(ident.zone) or 0
	-- Distinct known zones ⇒ different instance. 0 is "not yet known" (loading).
	if prevZ > 0 and newZ > 0 and prevZ ~= newZ then
		return false
	end
	local a = tonumber(prevId) or 0
	local b = tonumber(ident.id) or 0
	-- Distinct known ids ⇒ different instance. 0 on either side is "not yet known".
	if a > 0 and b > 0 and a ~= b then
		return false
	end
	return true
end

local function StoreIdentity(ident)
	if not ident then
		Session._matchKind = nil
		Session._lastZone = nil
		Session._lastScId = nil
		Session._lastMode = nil
		return
	end
	Session._matchKind = ident.kind
	Session._lastZone = ident.zone
	-- Keep a known non-zero id if the live snapshot still reports 0.
	if (tonumber(ident.id) or 0) > 0 or not Session._lastScId or Session._lastScId == 0 then
		Session._lastScId = ident.id
	end
	Session._lastMode = ident.mode
end

local function IsPreMode()
	local modes = GameData and GameData.ScenarioMode
	if type(modes) ~= "table" or modes.PRE_MODE == nil then
		return false
	end
	return ScenarioMode() == modes.PRE_MODE
end

local function IsPostMode()
	local modes = GameData and GameData.ScenarioMode
	if type(modes) ~= "table" then
		return Session._matchPostMode == true
	end
	local mode = ScenarioMode()
	if modes.POST_MODE ~= nil and mode == modes.POST_MODE then
		return true
	end
	if modes.ENDED ~= nil and mode == modes.ENDED then
		return true
	end
	return Session._matchPostMode == true
end

local function ResolveCountFocus()
	if IsInMatchInstance() then
		if MatchKind() == "siege" then
			return "siege"
		end
		return "scenario"
	end
	-- Still treat as scenario bag only while we have an active instance flag
	-- (brief flag lag after load). Queue-only isInScenarioGroup must not win.
	if Session._matchActive == true and Session._matchKind then
		if Session._matchKind == "siege" then
			return "siege"
		end
		return "scenario"
	end
	return "rvr"
end

local function FixDisplayName(str)
	if str == nil then
		return L""
	end
	local ws = str
	if type(ws) ~= "wstring" then
		ws = towstring(str)
	end
	ws = L"" .. ws
	local pos = ws:find(L"^", 1, true)
	if pos then
		ws = ws:sub(1, pos - 1)
	end
	return ws
end

local function GetPairingDisplayName(pairingId)
	pairingId = tonumber(pairingId) or 0
	if pairingId < 1 then
		return L""
	end
	local tables = StringTables and StringTables.MapSystem
	if type(GetStringFromTable) == "function" and type(tables) == "table" then
		local stringId = tables["LABEL_PAIRING_" .. tostring(pairingId)]
		if stringId == nil and tables.LABEL_PAIRING_1 ~= nil then
			stringId = tables.LABEL_PAIRING_1 + pairingId - 1
		end
		if stringId ~= nil then
			local name = FixDisplayName(GetStringFromTable("MapSystem", stringId))
			if name ~= L"" then
				return name
			end
		end
	end
	local pairings = GameData and GameData.Pairing
	if type(pairings) == "table" then
		if pairingId == pairings.GREENSKIN_DWARVES then
			return L"Dwarf vs Greenskin"
		end
		if pairingId == pairings.EMPIRE_CHAOS then
			return L"Empire vs Chaos"
		end
		if pairingId == pairings.ELVES_DARKELVES then
			return L"High Elf vs Dark Elf"
		end
	end
	return L""
end

local function ReadTrackingPlace()
	local zoneId = PlayerZone()
	local zoneName = L""
	if zoneId > 0 and type(GetZoneName) == "function" then
		zoneName = FixDisplayName(GetZoneName(zoneId))
	end

	local pairingId, tierId = 0, 0
	if zoneId > 0 and type(GetCampaignZoneData) == "function" then
		local ok, data = false, nil
		if type(CustomUI.TryCallQuiet) == "function" then
			ok, data = CustomUI.TryCallQuiet("KillTracker.GetCampaignZoneData.announce", GetCampaignZoneData, zoneId)
		else
			ok, data = true, GetCampaignZoneData(zoneId)
		end
		if ok and type(data) == "table" then
			pairingId = tonumber(data.pairingId) or 0
			tierId = tonumber(data.tierId) or 0
		end
	end

	return zoneName, pairingId, tierId
end

local function TrackingScopeText()
	local zoneName, pairingId, tierId = ReadTrackingPlace()
	local pairingName = GetPairingDisplayName(pairingId)
	local bits = L""
	if pairingName ~= L"" then
		bits = pairingName
	end
	if tierId > 0 then
		if bits ~= L"" then
			bits = bits .. L" T" .. towstring(tierId)
		else
			bits = L"T" .. towstring(tierId)
		end
	end
	if zoneName ~= L"" and bits ~= L"" then
		return zoneName .. L", " .. bits
	end
	if zoneName ~= L"" then
		return zoneName
	end
	return bits
end

local function FocusStatusMessage(focus)
	local base
	if focus == "siege" then
		base = L"KillTracker: counting kills for this city siege instance"
	elseif focus == "scenario" then
		base = L"KillTracker: counting kills for this scenario instance"
	else
		base = L"KillTracker: counting kills for the open-world RvR session"
	end
	local detail = TrackingScopeText()
	if detail ~= nil and detail ~= L"" then
		return base .. L" (" .. detail .. L")."
	end
	return base .. L"."
end

--- Print to System General when RvR vs scenario/siege count focus or lake changes.
function Session.AnnounceFocusIfChanged(force)
	if CustomUI.IsComponentEnabled and not CustomUI.IsComponentEnabled("KillTracker") then
		return
	end

	local focus = ResolveCountFocus()
	local token = focus .. "|" .. (GetScoreScopeKey() or "")
	if force ~= true and token == Session._announcedFocus then
		return
	end
	Session._announcedFocus = token

	if type(CustomUI.PrintMessage) == "function" then
		CustomUI.PrintMessage(FocusStatusMessage(focus))
	end
end

--- Combat finished (scoreboard) but player may still be inside the instance.
--- Keep the scenario bag until leave; force a fresh bag on the next begin.
function Session.MarkPostMode()
	if Session._matchActive == true or IsInMatchInstance() then
		Session._matchPostMode = true
		local mode = ScenarioMode()
		if mode ~= nil then
			Session._lastMode = mode
		end
	end
end

--- Start (or confirm) a match instance. Clears the scenario bag when entering
--- a different instance, after leaving POST_MODE, or when no match is active yet.
--- @return boolean true if the scenario bag was cleared
function Session.BeginMatchInstance(reason)
	-- After scoreboard, a *new* enter must reset. While still inside the same
	-- instance in POST_MODE, keep the bag (counts stay useful until leave).
	if Session._matchPostMode == true then
		if IsInMatchInstance() then
			StoreIdentity(CaptureIdentity())
			Session.AnnounceFocusIfChanged()
			return false
		end
		Session.BeginNewMatchInstance()
		return true
	end

	local ident = CaptureIdentity()
	if not ident and not IsInMatchInstance() then
		-- BEGIN event can race ahead of flags; still open a fresh bag.
		if Session._matchActive then
			return false
		end
		ClearBag(Session.Scenario)
		ResetZoneScore()
		Session._matchActive = true
		Session._matchPostMode = false
		Session._matchKind = Session._matchKind or "scenario"
		Session._lastMode = ScenarioMode()
		Session.AnnounceFocusIfChanged()
		return true
	end

	if Session._matchActive
		and SameInstance(Session._matchKind, Session._lastZone, Session._lastScId, ident)
	then
		StoreIdentity(ident)
		Session.AnnounceFocusIfChanged()
		return false
	end

	ClearBag(Session.Scenario)
	ResetZoneScore()
	Session._matchActive = true
	Session._matchPostMode = false
	StoreIdentity(ident or {
		kind = "scenario",
		zone = PlayerZone(),
		id = 0,
		mode = ScenarioMode(),
	})
	Session.AnnounceFocusIfChanged()
	return true
end

--- Leave the match instance and clear the scenario bag.
function Session.EndMatchInstance(reason)
	if not Session._matchActive and not IsInMatchInstance() then
		Session._matchActive = false
		Session._matchPostMode = false
		StoreIdentity(nil)
		Session.AnnounceFocusIfChanged()
		return
	end

	-- SCENARIO_END / POST_MODE fire while still inside (scoreboard). Keep the
	-- bag so [N] stays meaningful until leave; mark so the next begin resets.
	if reason ~= "force" and IsInMatchInstance() then
		Session.MarkPostMode()
		return
	end

	ClearBag(Session.Scenario)
	ResetZoneScore()
	Session._matchActive = false
	Session._matchPostMode = false
	StoreIdentity(nil)
	Session.AnnounceFocusIfChanged()
end

--- Reconcile with GameData flags. Safe to call often (loading end, before kills).
function Session.SyncMatchScope()
	local inMatch = IsInMatchInstance()
	if inMatch then
		-- Stay on the scoreboard bag; do not clear mid-post.
		if IsPostMode() then
			Session.MarkPostMode()
			StoreIdentity(CaptureIdentity())
			Session.AnnounceFocusIfChanged()
			return
		end
		local ident = CaptureIdentity()
		if not Session._matchActive then
			Session.BeginMatchInstance("sync-enter")
		elseif ident
			and not SameInstance(Session._matchKind, Session._lastZone, Session._lastScId, ident)
		then
			Session.BeginMatchInstance("sync-identity-change")
		else
			StoreIdentity(ident)
			Session.AnnounceFocusIfChanged()
		end
		return
	end

	if Session._matchActive or Session._matchPostMode then
		Session.EndMatchInstance("force")
		return
	end

	Session._matchPostMode = false
	Session.AnnounceFocusIfChanged()
end

--- Explicit new-instance signal (SCENARIO_BEGIN / forced LOADING_END begin).
function Session.BeginNewMatchInstance()
	-- Force a fresh bag even if flags/identity still look like the previous
	-- match (engine BEGIN is authoritative for a new round).
	ClearBag(Session.Scenario)
	ResetZoneScore()
	Session._matchActive = true
	Session._matchPostMode = false
	local ident = CaptureIdentity()
	if ident then
		StoreIdentity(ident)
	else
		Session._matchKind = MatchKind() or "scenario"
		Session._lastZone = PlayerZone()
		Session._lastScId = (Session._matchKind == "siege") and CityScenarioId() or ScenarioId()
		Session._lastMode = ScenarioMode()
	end
	Session.AnnounceFocusIfChanged()
end

--- LOADING_END helper: stock ScenarioSummary uses this as city-begin; also
--- catches missed SCENARIO_BEGIN (PRE_MODE) and leave-instance.
--- @return string action taken: "begin" | "end" | "sync" | "none"
function Session.OnLoadingEnd()
	if IsInMatchInstance() then
		local p = GameData and GameData.Player
		local inSiege = type(p) == "table" and p.isInSiege == true
		local needsFresh = Session._matchPostMode == true
			or Session._matchActive ~= true
			or (inSiege and Session._matchKind ~= "siege")
			or (not inSiege and IsPreMode())

		if needsFresh then
			Session.BeginNewMatchInstance()
			return "begin"
		end
		Session.SyncMatchScope()
		EnsureZoneScoreScope()
		return "sync"
	end

	if Session._matchActive == true or Session._matchPostMode == true then
		Session.EndMatchInstance("force")
		EnsureZoneScoreScope()
		return "end"
	end

	EnsureZoneScoreScope()
	Session.AnnounceFocusIfChanged()
	return "none"
end

--- ScenarioGroupWindow pattern: roster/list updates after leave can arrive
--- when flags are already clear. Only force-end after POST_MODE — never during
--- a SCENARIO_BEGIN race (flags may still be false while _matchActive is set).
function Session.OnPossiblyLeftMatch()
	if not IsInMatchInstance() and Session._matchPostMode == true then
		Session.EndMatchInstance("force")
		return true
	end
	return false
end

--- Which bag to count into. Does not sync — call SyncMatchScope first when needed.
local function ActiveBagNoSync()
	if IsInMatchInstance() or Session._matchActive == true then
		return Session.Scenario
	end
	return Session.RvR
end

function Session.GetContext()
	Session.SyncMatchScope()
	local focus = ResolveCountFocus()
	if focus == "siege" or focus == "scenario" then
		return "scenario"
	end
	return "rvr"
end

--- True when counts should go to the scenario/siege bag (no sync side effects).
function Session.IsMatchContext()
	return IsInMatchInstance() or Session._matchActive == true
end

function Session.GetActiveBag()
	return ActiveBagNoSync()
end

function Session.ResetRvR()
	ClearBag(Session.RvR)
end

function Session.ResetScenario()
	ClearBag(Session.Scenario)
	ResetZoneScore()
	Session._matchActive = false
	Session._matchPostMode = false
	StoreIdentity(nil)
	Session.AnnounceFocusIfChanged()
end

function Session.Reset()
	Session.ResetRvR()
	ClearBag(Session.Scenario)
	ResetZoneScore()
	Session._matchActive = false
	Session._matchPostMode = false
	StoreIdentity(nil)
	Session._announcedFocus = nil
end

--- Map-zone Order/Destro kill totals. Safe to call often.
function Session.GetZoneScore()
	EnsureZoneScoreScope()
	local score = Session.ZoneScore
	if type(score) ~= "table" then
		return 0, 0, 0
	end
	return tonumber(score.orderKills) or 0, tonumber(score.destroKills) or 0, tonumber(score.zoneId) or 0
end

--- PLAYER_ZONE_CHANGED (not area). Open-RvR campaign lakes (same pairing+tier)
--- keep the zone score; a different lake/city/scenario still resets.
--- Also resyncs match bags so scenario swaps cannot keep the previous [N] counts.
--- @return boolean true if zone score reset
function Session.OnPlayerZoneChanged()
	-- Ignore loading/unknown zone 0; do not treat it as a new instance.
	if PlayerZone() == 0 then
		return false
	end
	Session.SyncMatchScope()
	return EnsureZoneScoreScope()
end

--- +1 for the killer's realm. RVR_KILLS_ORDER = Order got the kill.
--- @param killerName wstring|string|nil display name for top-killer tooltips
function Session.IncrementFactionKill(filterType, killerName)
	local filters = SystemData and SystemData.ChatLogFilters
	if type(filters) ~= "table" then
		return
	end
	EnsureZoneScoreScope()
	local score = Session.ZoneScore
	if type(score) ~= "table" then
		return
	end
	if filterType == filters.RVR_KILLS_ORDER then
		score.orderKills = (tonumber(score.orderKills) or 0) + 1
		if type(score.orderKillers) ~= "table" then
			score.orderKillers = {}
		end
		BumpFactionKiller(score.orderKillers, killerName)
	elseif filterType == filters.RVR_KILLS_DESTRUCTION then
		score.destroKills = (tonumber(score.destroKills) or 0) + 1
		if type(score.destroKillers) ~= "table" then
			score.destroKillers = {}
		end
		BumpFactionKiller(score.destroKillers, killerName)
	end
end

--- Top killers for the current zone-score lake (Order or Destruction).
--- @param isOrder boolean true = Order killers, false = Destruction
--- @param limit number|nil max rows (default 10)
--- @return table array of { name = wstring, count = number }
function Session.GetTopFactionKillers(isOrder, limit)
	EnsureZoneScoreScope()
	local score = Session.ZoneScore
	if type(score) ~= "table" then
		return {}
	end
	local map = isOrder and score.orderKillers or score.destroKillers
	if type(map) ~= "table" then
		return {}
	end

	limit = tonumber(limit) or 10
	if limit < 1 then
		limit = 1
	elseif limit > 50 then
		limit = 50
	end

	local list = {}
	for _, entry in pairs(map) do
		if type(entry) == "table" then
			local count = tonumber(entry.count) or 0
			if count > 0 and entry.name ~= nil and entry.name ~= L"" then
				list[#list + 1] = { name = entry.name, count = count }
			end
		end
	end

	table.sort(list, function(a, b)
		if a.count ~= b.count then
			return a.count > b.count
		end
		local an = tostring(a.name or "")
		local bn = tostring(b.name or "")
		return an < bn
	end)

	if #list > limit then
		for i = #list, limit + 1, -1 do
			list[i] = nil
		end
	end
	return list
end

--- Observed combat-log tallies only (+1 per captured kill line). No Scenario Summary.
function Session.IncrementKiller(killerName)
	local key = NameKey(killerName)
	if not key then
		return 0
	end
	local bag = ActiveBagNoSync()
	local nextCount = (bag.Kills[key] or 0) + 1
	bag.Kills[key] = nextCount
	return nextCount
end

function Session.GetKillerCount(killerName)
	local key = NameKey(killerName)
	if not key then
		return 0
	end
	local bag = ActiveBagNoSync()
	return bag.Kills[key] or 0
end
