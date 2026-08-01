----------------------------------------------------------------
-- CustomUI.KillTracker.Session — dual kill/death bags (RAM only)
-- RvR: open-world session (survives zone loads; cleared on Disable)
-- Scenario: one match instance including city siege — reset on each
--   new instance (begin / lobby PRE_MODE / enter via loading / leave)
----------------------------------------------------------------
if not CustomUI then CustomUI = {} end
CustomUI.KillTracker = CustomUI.KillTracker or {}
CustomUI.KillTracker.Session = CustomUI.KillTracker.Session or {}

local Session = CustomUI.KillTracker.Session

Session.RvR = Session.RvR or { Kills = {}, Deaths = {} }
Session.Scenario = Session.Scenario or { Kills = {}, Deaths = {} }

-- Match-scope tracking (scenario / city siege instance)
Session._matchActive = Session._matchActive == true
Session._lastMode = Session._lastMode
Session._lastToken = Session._lastToken
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

local function ScenarioModeEnum()
	return GameData and GameData.ScenarioMode
end

--- True when physically in a scenario or city siege match.
--- Do not use isInScenarioGroup alone — it can linger between queues and
--- incorrectly keep / reuse the scenario bag across instances.
local function IsInMatch()
	local p = GameData and GameData.Player
	if type(p) ~= "table" then
		return false
	end
	if p.isInSiege == true then
		return true
	end
	if p.isInScenario == true then
		local modes = ScenarioModeEnum()
		local mode = ScenarioMode()
		-- ENDED: still in the instance until leave; keep scenario bag until leave/end reset.
		if modes and mode == modes.ENDED then
			return true
		end
		return true
	end
	return false
end

local function HasScenarioRosterRows()
	if type(GameData) ~= "table" or type(GameData.GetScenarioPlayerGroups) ~= "function" then
		return false
	end
	local pg = GameData.GetScenarioPlayerGroups()
	if type(pg) ~= "table" then
		return false
	end
	for _, pl in ipairs(pg) do
		local gi = tonumber(pl and pl.sgroupindex)
		if gi ~= nil and gi > 0 then
			return true
		end
	end
	return false
end

local function MatchToken()
	local p = GameData and GameData.Player
	if type(p) ~= "table" then
		return nil
	end
	local zone = tonumber(p.zone) or 0
	if p.isInSiege == true then
		local cityId = tonumber(GameData.CityScenarioData and GameData.CityScenarioData.id) or 0
		return "siege:" .. tostring(cityId) .. ":" .. tostring(zone)
	end
	if p.isInScenario == true then
		local scId = tonumber(GameData.ScenarioData and GameData.ScenarioData.id) or 0
		return "sc:" .. tostring(scId) .. ":" .. tostring(zone)
	end
	return nil
end

local function ResolveCountFocus()
	if IsInMatch() then
		if GameData.Player and GameData.Player.isInSiege == true then
			return "siege"
		end
		return "scenario"
	end

	local p = GameData and GameData.Player
	if type(p) == "table" and p.isInScenarioGroup == true and HasScenarioRosterRows() then
		return "scenario"
	end
	if HasScenarioRosterRows() and type(p) == "table" and (p.isInScenario == true or p.isInSiege == true) then
		if p.isInSiege == true then
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

--- Detect new scenario/city instance and clear the scenario bag.
--- Safe to call often (loading end, scenario events, before each kill).
function Session.SyncMatchScope()
	local inMatch = IsInMatch()
	if not inMatch then
		if Session._matchActive then
			ClearBag(Session.Scenario)
		end
		Session._matchActive = false
		Session._lastMode = nil
		Session._lastToken = nil
		Session.AnnounceFocusIfChanged()
		return
	end

	local modes = ScenarioModeEnum()
	local mode = ScenarioMode()
	local token = MatchToken()
	local shouldReset = false

	if not Session._matchActive then
		-- Fresh enter (loading into siege/scenario, or flags just flipped).
		shouldReset = true
	elseif token ~= nil and Session._lastToken ~= nil and token ~= Session._lastToken then
		shouldReset = true
	elseif modes and not (GameData.Player and GameData.Player.isInSiege == true) then
		-- Same map id can requeue: reset when a new lobby starts, or when
		-- RUNNING begins without having seen PRE_MODE (skipped lobby / reload edge).
		if mode == modes.PRE_MODE and Session._lastMode ~= modes.PRE_MODE then
			shouldReset = true
		elseif mode == modes.RUNNING
			and Session._lastMode ~= modes.RUNNING
			and Session._lastMode ~= modes.PRE_MODE
		then
			shouldReset = true
		end
	end

	if shouldReset then
		ClearBag(Session.Scenario)
	end

	Session._matchActive = true
	Session._lastMode = mode
	Session._lastToken = token
	Session.AnnounceFocusIfChanged()
end

--- Explicit new-instance signal (SCENARIO_BEGIN / CITY_SCENARIO_BEGIN).
function Session.BeginNewMatchInstance()
	ClearBag(Session.Scenario)
	Session._matchActive = IsInMatch()
	Session._lastMode = ScenarioMode()
	Session._lastToken = MatchToken()
	Session.AnnounceFocusIfChanged()
end

function Session.GetContext()
	Session.SyncMatchScope()

	local focus = ResolveCountFocus()
	if focus == "siege" or focus == "scenario" then
		return "scenario"
	end
	return "rvr"
end

function Session.GetActiveBag()
	if Session.GetContext() == "scenario" then
		return Session.Scenario
	end
	return Session.RvR
end

function Session.ResetRvR()
	ClearBag(Session.RvR)
end

function Session.ResetScenario()
	ClearBag(Session.Scenario)
	Session._matchActive = false
	Session._lastMode = nil
	Session._lastToken = nil
	Session.AnnounceFocusIfChanged()
end

function Session.Reset()
	Session.ResetRvR()
	ClearBag(Session.Scenario)
	Session._matchActive = false
	Session._lastMode = nil
	Session._lastToken = nil
	Session._announcedFocus = nil
end

function Session.IncrementKiller(killerName)
	local key = NameKey(killerName)
	if not key then
		return 0
	end
	local bag = Session.GetActiveBag()
	local nextCount = (bag.Kills[key] or 0) + 1
	bag.Kills[key] = nextCount
	return nextCount
end

function Session.IncrementVictim(victimName)
	local key = NameKey(victimName)
	if not key then
		return 0
	end
	local bag = Session.GetActiveBag()
	local nextCount = (bag.Deaths[key] or 0) + 1
	bag.Deaths[key] = nextCount
	return nextCount
end

function Session.GetKillerCount(killerName)
	local key = NameKey(killerName)
	if not key then
		return 0
	end
	local bag = Session.GetActiveBag()
	return bag.Kills[key] or 0
end

function Session.GetDeathCount(victimName)
	local key = NameKey(victimName)
	if not key then
		return 0
	end
	local bag = Session.GetActiveBag()
	return bag.Deaths[key] or 0
end
