----------------------------------------------------------------
-- CustomUI.QoL.AutoSurrender — scenario surrender automation
----------------------------------------------------------------
if not CustomUI then CustomUI = {} end
CustomUI.QoL = CustomUI.QoL or {}
CustomUI.QoL.AutoSurrender = CustomUI.QoL.AutoSurrender or {}

local AS = CustomUI.QoL.AutoSurrender

--[[
    Known server chat strings (RoR 2026):
      [Name] started surrender vote!
      You can now use commands .yes and .no to vote to vote for surrender.
      [Name] voted yes/no for surrender.
      Surrender vote for Forces of Order failed! Yes: N No: M Required number of votes: K
      You are unable to start surrender vote for another HH:MM:SS.ffffff seconds!
      A vote is still in progress.
      You are unable to surrender if you are not participating in scenario!
      You cannot surrender before scenario starts...
      You cannot surrender when you are winning.

    On scenario entry we read GameData.ScenarioData.timeLeft (same value shown on
    EA_Window_ScenarioTrackerLocationTimerValue) during PRE_MODE and probe only after
    the scenario starts. Surrender-unlock cooldown still comes from the server reply.
--]]

local TIME_DELAY   = 1
local VOTE_PAUSE   = 30
local NOT_IN_SCENARIO_PAUSE = 300
local SCENARIO_TRACKER_TIMER = "EA_Window_ScenarioTrackerLocationTimerValue"
local PRE_MODE  = (GameData and GameData.ScenarioMode and GameData.ScenarioMode.PRE_MODE) or 0
local RUNNING   = (GameData and GameData.ScenarioMode and GameData.ScenarioMode.RUNNING) or 1

local WINNING_TEAM_BLOCK_PATTERNS = {
    L"You cannot surrender when you are winning",
}

local ORDER  = (GameData and GameData.Realm and GameData.Realm.ORDER) or 1
local DESTRO = (GameData and GameData.Realm and GameData.Realm.DESTRUCTION) or 2

local inScenario        = false
local surrenderCooldown = TIME_DELAY
local needsTimerProbe   = false
local timerLearned      = false
local voteInProgress    = false
local votingAllowed     = false
local pendingCastVote   = false
local notParticipating  = false
local deferForScore     = false   -- timer open; waiting until strictly behind on score (server blocks ties/leads)
local waitingForScenarioStart = false
local lastScenarioMode  = nil
local announcedScenarioStart = false
local eventsRegistered  = false

local function getDefaults()
    return {
        enabled = true,
        statusMessages = true,
        useKillRule = true,
        scoreDiff = 100,
        preStartRetry = 30,
    }
end

local function getSettings()
    local qol = CustomUI.QoL.EnsureSettings()
    local s = qol.autoSurrender
    if type(s) ~= "table" then
        s = {}
        qol.autoSurrender = s
    end
    local d = getDefaults()
    if s.enabled == nil then s.enabled = d.enabled end
    if s.statusMessages == nil then s.statusMessages = d.statusMessages end
    if s.useKillRule == nil then s.useKillRule = d.useKillRule end
    if s.scoreDiff == nil then s.scoreDiff = d.scoreDiff end
    if s.preStartRetry == nil then s.preStartRetry = d.preStartRetry end
    if s.scoreDiff < 0 then s.scoreDiff = 0 end
    if s.preStartRetry < 5 then s.preStartRetry = 5 end
    return s
end

local function isFeatureEnabled()
    return getSettings().enabled == true
end



local killCache = {
	dirty = true,
	orderMaxKills = 0,
	destroMaxKills = 0,
}

local function Status(msg)
	if not getSettings().statusMessages then
		return
	end
	if CustomUI and CustomUI.QoL and type(CustomUI.QoL.PrintSubFeatureMessage) == "function" then
		CustomUI.QoL.PrintSubFeatureMessage(L"AutoSurrender", towstring(tostring(msg)))
	elseif type(CustomUI.PrintMessage) == "function" then
		CustomUI.PrintMessage(L"AutoSurrender: " .. towstring(tostring(msg)))
	end
end

local function formatDuration(secs)
    secs = math.ceil(tonumber(secs) or 0)
    if secs >= 3600 then
        return string.format("%dh %dm", math.floor(secs / 3600), math.floor((secs % 3600) / 60))
    elseif secs >= 60 then
        return string.format("%dm %ds", math.floor(secs / 60), secs % 60)
    end
    return string.format("%ds", secs)
end

local function scoreLine()
    local sd = GameData.ScenarioData
    if not sd then return "" end
    return string.format(" (score %d - %d)", sd.orderPoints or 0, sd.destructionPoints or 0)
end

local function wstrToStr(w)
    if w == nil then return "" end
    local ok, s = pcall(WStringToString, w)
    return (ok and s) or tostring(w)
end

local function getScenarioData()
    return GameData and GameData.ScenarioData or nil
end

local function isPreStartPhase()
    local sd = getScenarioData()
    return sd ~= nil and sd.mode == PRE_MODE
end

-- Same seconds as EA_Window_ScenarioTracker.UpdateScenarioTimer (GameData.ScenarioData.timeLeft).
local function readScenarioStartSeconds()
    local sd = getScenarioData()
    if sd and sd.mode == PRE_MODE then
        local t = tonumber(sd.timeLeft)
        if t and t > 0 then return t end
    end
    if DoesWindowExist(SCENARIO_TRACKER_TIMER) then
        local ok, text = pcall(LabelGetText, SCENARIO_TRACKER_TIMER)
        if ok and text then
            local s = wstrToStr(text)
            local h, m, sec = s:match("^(%d+):(%d+):(%d+)$")
            if h then
                return tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(sec)
            end
            m, sec = s:match("^(%d+):(%d+)$")
            if m then
                return tonumber(m) * 60 + tonumber(sec)
            end
        end
    end
    return nil
end

local function onScenarioModeChanged(mode)
    if lastScenarioMode == PRE_MODE and mode == RUNNING then
        waitingForScenarioStart = false
        if not timerLearned then
            needsTimerProbe = true
            surrenderCooldown = TIME_DELAY
            if not announcedScenarioStart then
                announcedScenarioStart = true
                Status("Scenario started - probing surrender timer.")
            end
        end
    end
    lastScenarioMode = mode
end

-- During PRE_MODE, sync to the scenario start countdown instead of spamming .surrender.
local function updatePreStartWait()
    if not inScenario or timerLearned or notParticipating then return false end

    local sd = getScenarioData()
    if sd and sd.mode ~= lastScenarioMode then
        onScenarioModeChanged(sd.mode)
    end

    if not isPreStartPhase() then
        waitingForScenarioStart = false
        return false
    end

    waitingForScenarioStart = true
    local remain = readScenarioStartSeconds()
    if remain and remain > 0 then
        surrenderCooldown = remain + TIME_DELAY
        needsTimerProbe = false
        return true
    end

    if surrenderCooldown <= TIME_DELAY then
        surrenderCooldown = getSettings().preStartRetry
    end
    return true
end

local function parseCooldownSeconds(text)
    local s = wstrToStr(text)
    local h, m, sec = s:match("(%d+):(%d+):([%d%.]+)")
    if h then
        return math.ceil(tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(sec))
    end
    local n = tonumber(s:match("(%d+)"))
    if n then return n end
    return nil
end

local function applyCooldown(text, statusNote)
    local cd = parseCooldownSeconds(text)
    if cd and cd > 0 then
        surrenderCooldown = cd
        timerLearned = true
        needsTimerProbe = false
        local note = statusNote or "surrender vote unlocks"
        Status(note .. " in " .. formatDuration(cd) .. ".")
    end
end

local function isLosingByScore(diff)
    local sd = GameData.ScenarioData
    if not sd then return false end
    if GameData.Player.realm == ORDER then
        return sd.orderPoints + diff < sd.destructionPoints
    elseif GameData.Player.realm == DESTRO then
        return sd.destructionPoints + diff < sd.orderPoints
    end
    return false
end

-- Server rejects .surrender on a lead *or* a tie ("You cannot surrender when you are winning").
local function isTeamWinning()
    local sd = GameData.ScenarioData
    if not sd then return false end
    if GameData.Player.realm == ORDER then
        return sd.orderPoints >= sd.destructionPoints
    elseif GameData.Player.realm == DESTRO then
        return sd.destructionPoints >= sd.orderPoints
    end
    return false
end

local function isStrictlyBehindOnScore()
    local sd = GameData.ScenarioData
    if not sd then return false end
    if GameData.Player.realm == ORDER then
        return sd.orderPoints < sd.destructionPoints
    elseif GameData.Player.realm == DESTRO then
        return sd.destructionPoints < sd.orderPoints
    end
    return false
end

local function markKillCacheDirty()
	killCache.dirty = true
end

local function refreshKillCache()
	killCache.orderMaxKills = 0
	killCache.destroMaxKills = 0

	if not getSettings().useKillRule then
		killCache.dirty = false
		return
	end

	local playerData = GameData.GetScenarioPlayers()
	if not playerData then
		killCache.dirty = false
		return
	end

	for _, value in ipairs(playerData) do
		local kills = tonumber(value.groupkills) or 0
		if tonumber(value.realm) == ORDER then
			if kills > killCache.orderMaxKills then
				killCache.orderMaxKills = kills
			end
		elseif tonumber(value.realm) == DESTRO then
			if kills > killCache.destroMaxKills then
				killCache.destroMaxKills = kills
			end
		end
	end

	killCache.dirty = false
end

local function isLosingByKills()
	if not getSettings().useKillRule then
		return false
	end
	if killCache.dirty then
		refreshKillCache()
	end

	if GameData.Player.realm == ORDER then
		return killCache.orderMaxKills < killCache.destroMaxKills
	elseif GameData.Player.realm == DESTRO then
		return killCache.destroMaxKills < killCache.orderMaxKills
	end
	return false
end

local function isLosingEnough()
    if isLosingByScore(getSettings().scoreDiff) then return true end
    if getSettings().useKillRule and isLosingByKills() then return true end
    return false
end

local function canStartSurrender()
    if isTeamWinning() then return false end
    return isLosingEnough()
end

local function checkScoreForDeferredSurrender()
    if not deferForScore or notParticipating or voteInProgress then return end
    -- Stay deferred through ties and leads; only resume once score is strictly behind.
    if not isStrictlyBehindOnScore() then return end
    deferForScore = false
    if isLosingEnough() then
        surrenderCooldown = 0
        Status("Behind on score" .. scoreLine() .. " - starting surrender vote.")
    else
        Status("Behind on score" .. scoreLine() .. "; waiting until down by " .. getSettings().scoreDiff .. ".")
    end
end

local function shouldSendSurrender()
    if notParticipating or voteInProgress then return false end
    if waitingForScenarioStart or isPreStartPhase() then return false end
    if deferForScore then return false end
    if needsTimerProbe then return true end
    return canStartSurrender()
end

local function sendSurrender(isProbe)
    SendChatText(L".surrender", ChatSettings.Channels[0].serverCmd)
    needsTimerProbe = false
    if isProbe then
        Status("Probing surrender timer" .. scoreLine() .. "...")
    else
        Status("Requesting surrender vote" .. scoreLine() .. "...")
    end
end

local function castVote()
    if isLosingEnough() then
        SendChatText(L".yes", ChatSettings.Channels[0].serverCmd)
        Status("Voting yes to surrender" .. scoreLine() .. ".")
    else
        SendChatText(L".no", ChatSettings.Channels[0].serverCmd)
        Status("Voting no on surrender" .. scoreLine() .. ".")
    end
    pendingCastVote = false
end

local function tryCastVote()
    if not pendingCastVote then return end
    if votingAllowed then
        castVote()
    end
end

local function matchesWinningBlock(text)
    for _, pattern in ipairs(WINNING_TEAM_BLOCK_PATTERNS) do
        if text:find(pattern) then return true end
    end
    return false
end

local function onEnterScenario()
    voteInProgress    = false
    votingAllowed     = false
    pendingCastVote   = false
    notParticipating  = false
    deferForScore     = false
    timerLearned      = false
    needsTimerProbe   = true
    surrenderCooldown = TIME_DELAY
    inScenario        = true
    announcedScenarioStart = false
    waitingForScenarioStart = false
    markKillCacheDirty()
    local sd = getScenarioData()
    lastScenarioMode = sd and sd.mode or nil
    if isPreStartPhase() then
        waitingForScenarioStart = true
        local remain = readScenarioStartSeconds()
        if remain and remain > 0 then
            surrenderCooldown = remain + TIME_DELAY
            needsTimerProbe = false
            Status("Scenario pre-start - " .. formatDuration(remain) .. " until start.")
        else
            Status("Scenario pre-start - waiting for tracker timer.")
        end
    else
        announcedScenarioStart = true
        Status("Scenario entered - will probe surrender timer shortly.")
    end
end

local function onLeaveScenario()
    if inScenario then
        Status("Scenario ended - idle.")
    end
    inScenario        = false
    needsTimerProbe   = false
    timerLearned      = false
    voteInProgress    = false
    votingAllowed     = false
    pendingCastVote   = false
    notParticipating  = false
    deferForScore     = false
    waitingForScenarioStart = false
    lastScenarioMode  = nil
    announcedScenarioStart = false
    surrenderCooldown = TIME_DELAY
    markKillCacheDirty()
end

local function registerEventHandlers()
    if eventsRegistered then return end
    RegisterEventHandler(TextLogGetUpdateEventId("Chat"), "CustomUI.QoL.AutoSurrender.OnChatTextUpdate")
    RegisterEventHandler(SystemData.Events.SCENARIO_BEGIN, "CustomUI.QoL.AutoSurrender.OnScenarioBegin")
    RegisterEventHandler(SystemData.Events.SCENARIO_END, "CustomUI.QoL.AutoSurrender.OnScenarioEnd")
    RegisterEventHandler(SystemData.Events.SCENARIO_POST_MODE, "CustomUI.QoL.AutoSurrender.ExitScenario")
    RegisterEventHandler(SystemData.Events.SCENARIO_UPDATE_POINTS, "CustomUI.QoL.AutoSurrender.OnScoreUpdate")
    RegisterEventHandler(SystemData.Events.CITY_SCENARIO_UPDATE_POINTS, "CustomUI.QoL.AutoSurrender.OnScoreUpdate")
    RegisterEventHandler(SystemData.Events.SCENARIO_PLAYER_HITS_UPDATED, "CustomUI.QoL.AutoSurrender.OnKillStatsUpdated")
    RegisterEventHandler(SystemData.Events.SCENARIO_PLAYERS_LIST_STATS_UPDATED, "CustomUI.QoL.AutoSurrender.OnKillStatsUpdated")
    eventsRegistered = true
end

local function unregisterEventHandlers()
    if not eventsRegistered then return end
    UnregisterEventHandler(TextLogGetUpdateEventId("Chat"), "CustomUI.QoL.AutoSurrender.OnChatTextUpdate")
    UnregisterEventHandler(SystemData.Events.SCENARIO_BEGIN, "CustomUI.QoL.AutoSurrender.OnScenarioBegin")
    UnregisterEventHandler(SystemData.Events.SCENARIO_END, "CustomUI.QoL.AutoSurrender.OnScenarioEnd")
    UnregisterEventHandler(SystemData.Events.SCENARIO_POST_MODE, "CustomUI.QoL.AutoSurrender.ExitScenario")
    UnregisterEventHandler(SystemData.Events.SCENARIO_UPDATE_POINTS, "CustomUI.QoL.AutoSurrender.OnScoreUpdate")
    UnregisterEventHandler(SystemData.Events.CITY_SCENARIO_UPDATE_POINTS, "CustomUI.QoL.AutoSurrender.OnScoreUpdate")
    UnregisterEventHandler(SystemData.Events.SCENARIO_PLAYER_HITS_UPDATED, "CustomUI.QoL.AutoSurrender.OnKillStatsUpdated")
    UnregisterEventHandler(SystemData.Events.SCENARIO_PLAYERS_LIST_STATS_UPDATED, "CustomUI.QoL.AutoSurrender.OnKillStatsUpdated")
    eventsRegistered = false
end

function AS.OnScenarioBegin()
    onEnterScenario()
end

function AS.OnScenarioEnd()
    onLeaveScenario()
end

function AS.OnScoreUpdate()
    if not inScenario then return end
    markKillCacheDirty()
    checkScoreForDeferredSurrender()
end

function AS.OnKillStatsUpdated()
    if not inScenario then return end
    markKillCacheDirty()
end

function AS.OnChatTextUpdate(updateType, filterType)
    if not isFeatureEnabled() then return end
    if not GameData.Player.isInScenario then return end
    if updateType ~= SystemData.TextLogUpdate.ADDED then return end

    local _, filterId, text = TextLogGetEntry("Chat", TextLogGetNumEntries("Chat") - 1)
    if text == nil then return end

    if text:find(L"started surrender vote!") then
        voteInProgress = true
        pendingCastVote = true
        Status("Team surrender vote started - will auto-vote when polling opens.")
        tryCastVote()

    elseif text:find(L"You can now use commands .yes and .no") then
        voteInProgress = true
        votingAllowed = true
        tryCastVote()

    elseif text:find(L" for surrender.") and text:find(L"voted ") then
        voteInProgress = true

    elseif text:find(L"Surrender vote for") then
        voteInProgress = false
        votingAllowed = false
        pendingCastVote = false
        surrenderCooldown = TIME_DELAY
        Status("Surrender vote finished.")

    elseif text:find(L"You are unable to start surrender vote for another") then
        voteInProgress = false
        applyCooldown(text, "Next surrender attempt")

    elseif text:find(L"A vote is still in progress") then
        voteInProgress = true
        surrenderCooldown = math.max(surrenderCooldown, VOTE_PAUSE)
        Status("Surrender vote in progress - waiting.")

    elseif text:find(L"You are unable to surrender if you are not participating") then
        notParticipating = true
        voteInProgress = false
        needsTimerProbe = false
        surrenderCooldown = NOT_IN_SCENARIO_PAUSE
        Status("Not participating in scenario - auto-surrender disabled.")

    elseif matchesWinningBlock(text) then
        -- Timer gate is open; server rejects leads and ties ("winning").
        timerLearned = true
        needsTimerProbe = false
        deferForScore = true
        surrenderCooldown = TIME_DELAY
        Status("Vote window open but not behind on score" .. scoreLine() .. " - monitoring.")

    elseif text:find(L"You cannot surrender before scenario starts") then
        -- Quietly wait for start; do not re-announce countdown (already told on enter).
        applyCooldown(text, "Surrender unlock")
        if not timerLearned then
            local remain = readScenarioStartSeconds()
            if remain and remain > 0 then
                surrenderCooldown = remain + TIME_DELAY
            else
                surrenderCooldown = math.max(surrenderCooldown, getSettings().preStartRetry)
            end
            needsTimerProbe = false
            waitingForScenarioStart = true
        end
    end
end

function AS.ExitScenario()
    BroadcastEvent(SystemData.Events.SCENARIO_FINAL_SCOREBOARD_CLOSED)
end

function AS.OnUpdate(elapsed)
    if not isFeatureEnabled() then
        return
    end
    if not inScenario then
        if GameData.Player.isInScenario then
            onEnterScenario()
        end
        return
    end

    if not GameData.Player.isInScenario then
        onLeaveScenario()
        return
    end

    checkScoreForDeferredSurrender()
    updatePreStartWait()

    surrenderCooldown = surrenderCooldown - elapsed
    if surrenderCooldown > 0 then return end
    surrenderCooldown = TIME_DELAY

    if shouldSendSurrender() then
        sendSurrender(needsTimerProbe)
    end
end


function AS.Enable()
    if not isFeatureEnabled() then
        return
    end
    registerEventHandlers()
end

function AS.Disable()
    unregisterEventHandlers()
    onLeaveScenario()
end

function AS.Initialize()
end

function AS.Shutdown()
    AS.Disable()
end
