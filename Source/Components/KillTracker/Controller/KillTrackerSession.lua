----------------------------------------------------------------
-- CustomUI.KillTracker.Session — dual kill/death bags (RAM only)
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

Session.RvR = Session.RvR or { Kills = {}, Deaths = {} }
Session.Scenario = Session.Scenario or { Kills = {}, Deaths = {} }

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
	if type(bag.Deaths) == "table" then
		for k in pairs(bag.Deaths) do
			bag.Deaths[k] = nil
		end
	else
		bag.Deaths = {}
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
	if (tonumber(prevZone) or 0) ~= (tonumber(ident.zone) or 0) then
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

local function FocusStatusMessage(focus)
	if focus == "siege" then
		return L"KillTracker: counting kills for this city siege instance."
	end
	if focus == "scenario" then
		return L"KillTracker: counting kills for this scenario instance."
	end
	return L"KillTracker: counting kills for the open-world RvR session."
end

--- Print to System General when RvR vs scenario/siege count focus changes.
function Session.AnnounceFocusIfChanged(force)
	if CustomUI.IsComponentEnabled and not CustomUI.IsComponentEnabled("KillTracker") then
		return
	end

	local focus = ResolveCountFocus()
	if force ~= true and focus == Session._announcedFocus then
		return
	end
	Session._announcedFocus = focus

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
		return "sync"
	end

	if Session._matchActive == true or Session._matchPostMode == true then
		Session.EndMatchInstance("force")
		return "end"
	end

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
	Session._matchActive = false
	Session._matchPostMode = false
	StoreIdentity(nil)
	Session.AnnounceFocusIfChanged()
end

function Session.Reset()
	Session.ResetRvR()
	ClearBag(Session.Scenario)
	Session._matchActive = false
	Session._matchPostMode = false
	StoreIdentity(nil)
	Session._announcedFocus = nil
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

function Session.IncrementVictim(victimName)
	local key = NameKey(victimName)
	if not key then
		return 0
	end
	local bag = ActiveBagNoSync()
	local nextCount = (bag.Deaths[key] or 0) + 1
	bag.Deaths[key] = nextCount
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

function Session.GetDeathCount(victimName)
	local key = NameKey(victimName)
	if not key then
		return 0
	end
	local bag = ActiveBagNoSync()
	return bag.Deaths[key] or 0
end
