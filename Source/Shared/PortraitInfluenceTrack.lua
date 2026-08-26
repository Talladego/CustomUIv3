----------------------------------------------------------------
-- CustomUI.PortraitInfluenceTrack
-- PlayerStatus influence badge track (Current Area / manual live event).
-- Current Area follows local area influence like stock PQ Influence bar.
-- Live events (RvR/Scenario/Dungeon Week, etc.) are manual menu picks only.
-- Does not require a modified EA_ObjectiveTrackers InfluenceBarTrack.
----------------------------------------------------------------

if not CustomUI then
    CustomUI = {}
end

CustomUI.PortraitInfluenceTrack = CustomUI.PortraitInfluenceTrack or {}

local Track = CustomUI.PortraitInfluenceTrack

Track.MODE_CURRENT_AREA = "current_area"
Track.MODE_LIVE_EVENT = "live_event"
-- Legacy saved-variable modes (migrated in ensureSettings).
Track.MODE_AUTO = "auto"
Track.MODE_ZONE = "zone"

Track._refreshHandlers = Track._refreshHandlers or {}
Track._eventsRegistered = false
Track._registeredEventSpecs = Track._registeredEventSpecs or {}

local NUM_REWARD_LEVELS = 3

local function tryCall(context, fn, ...)
    if type(CustomUI.TryCallQuiet) == "function" then
        return CustomUI.TryCallQuiet(context, fn, ...)
    end
    if type(fn) ~= "function" then
        return false
    end
    local results = { pcall(fn, ...) }
    local ok = table.remove(results, 1)
    if ok then
        if #results == 0 then
            return true
        end
        return true, unpack(results)
    end
    return false
end

local function tryCallLoud(context, fn, ...)
    if type(CustomUI.TryCall) == "function" then
        return CustomUI.TryCall(context, fn, ...)
    end
    return tryCall(context, fn, ...)
end

local function resolveHandler(handler)
    if type(handler) == "function" then
        return handler
    end
    if type(handler) ~= "string" or handler == "" then
        return nil
    end
    local target = _G
    for part in string.gmatch(handler, "[^%.]+") do
        if type(target) ~= "table" then
            return nil
        end
        target = target[part]
    end
    if type(target) == "function" then
        return target
    end
    return nil
end

function Track.InvokeRefreshHandler()
    local seen = {}
    if type(Track._refreshHandlers) ~= "table" then
        return
    end
    for _, handlerRef in ipairs(Track._refreshHandlers) do
        if seen[handlerRef] ~= true then
            seen[handlerRef] = true
            local handler = resolveHandler(handlerRef)
            if handler ~= nil then
                handler()
            end
        end
    end
end

function Track.AddRefreshListener(handlerName)
    if handlerName == nil or handlerName == "" then
        return
    end
    if type(Track._refreshHandlers) ~= "table" then
        Track._refreshHandlers = {}
    end
    for _, existing in ipairs(Track._refreshHandlers) do
        if existing == handlerName then
            return
        end
    end
    Track._refreshHandlers[#Track._refreshHandlers + 1] = handlerName
end

function Track.RemoveRefreshListener(handlerName)
    if handlerName == nil or handlerName == "" or type(Track._refreshHandlers) ~= "table" then
        return
    end
    local nextHandlers = {}
    for _, existing in ipairs(Track._refreshHandlers) do
        if existing ~= handlerName then
            nextHandlers[#nextHandlers + 1] = existing
        end
    end
    Track._refreshHandlers = nextHandlers
end

local function ensureSettings()
    CustomUI.Settings = CustomUI.Settings or {}
    local settings = CustomUI.Settings.influenceTrack
    if type(settings) ~= "table" then
        settings = {
            mode = Track.MODE_CURRENT_AREA,
            eventId = nil,
            showEndedEvents = true,
            eventRewardCache = {},
        }
        CustomUI.Settings.influenceTrack = settings
    end
    -- Legacy: Auto / Zone → Current Area (area influence only; live events are manual).
    if settings.mode == Track.MODE_AUTO or settings.mode == Track.MODE_ZONE then
        settings.mode = Track.MODE_CURRENT_AREA
        settings.eventId = nil
    end
    if settings.mode ~= Track.MODE_LIVE_EVENT and settings.mode ~= Track.MODE_CURRENT_AREA then
        settings.mode = Track.MODE_CURRENT_AREA
    end
    if type(settings.eventRewardCache) ~= "table" then
        settings.eventRewardCache = {}
    end
    -- One-time wipe: older builds stuck false "purchased=true" via monotonic merge and never
    -- cleared them when the NPC reported unclaimed. Claims rebuild from NPC open / Select.
    if settings.eventRewardCacheResetV3 ~= true then
        settings.eventRewardCache = {}
        settings.eventRewardCacheResetV3 = true
    end
    if settings.showEndedEvents == nil then
        settings.showEndedEvents = true
    end
    -- Drop unused legacy keys if present.
    settings.liveEventKey = nil
    settings.eventTitle = nil
    return settings
end

local function isTruthyFlag(value)
    return value == true or value == 1
end

local function getNumRewardLevels()
    if type(TomeWindow) == "table" and tonumber(TomeWindow.NUM_REWARD_LEVELS) then
        return tonumber(TomeWindow.NUM_REWARD_LEVELS)
    end
    return NUM_REWARD_LEVELS
end

local function trimString(value)
    if value == nil then
        return ""
    end
    if type(value) == "string" then
        return value
    end
    if type(WStringToString) == "function" then
        local ok, text = tryCall("trimString.WStringToString", WStringToString, value)
        if ok and type(text) == "string" then
            return text
        end
    end
    return tostring(value)
end

local function normalizeEventTitle(title)
    local text = string.lower(trimString(title))
    text = string.gsub(text, "%s+", " ")
    text = string.gsub(text, "[^%w%s%-_]", "")
    text = string.gsub(text, "%s+", "_")
    if text == "" then
        text = "event"
    end
    return text
end

local function buildEventKey(eventId, title)
    return tostring(eventId or 0) .. ":" .. normalizeEventTitle(title)
end

local function defaultLiveEventTitle(eventId)
    if type(towstring) == "function" then
        return L"Live Event " .. towstring(eventId or 0)
    end
    return L"Live Event"
end

local function getLocalZoneInfluenceId()
    -- Prefer stock PQ helper when present; otherwise GetAreaData (engine).
    if type(EA_Window_PublicQuestTracker) == "table"
        and type(EA_Window_PublicQuestTracker.GetLocalAreaInfluenceID) == "function"
    then
        local ok, influenceId = tryCall(
            "getLocalZoneInfluenceId.PQ",
            EA_Window_PublicQuestTracker.GetLocalAreaInfluenceID
        )
        if ok then
            local id = tonumber(influenceId)
            if id ~= nil and id > 0 then
                return id
            end
            return nil
        end
    end

    if type(GetAreaData) ~= "function" then
        return nil
    end
    local okArea, areaData = tryCall("getLocalZoneInfluenceId.GetAreaData", GetAreaData)
    if not okArea or type(areaData) ~= "table" then
        return nil
    end
    for _, value in ipairs(areaData) do
        if type(value) == "table" then
            local id = tonumber(value.influenceID)
            if id ~= nil and id ~= 0 then
                return id
            end
        end
    end
    return nil
end

local function findLiveEventListEntry(eventId)
    if type(GetLiveEventList) ~= "function" then
        return nil
    end
    local okList, liveEventList = tryCall("findLiveEventListEntry.GetLiveEventList", GetLiveEventList)
    if not okList or type(liveEventList) ~= "table" then
        return nil
    end
    local trackedId = tonumber(eventId)
    for _, event in ipairs(liveEventList) do
        if type(event) == "table" and tonumber(event.id) == trackedId then
            return event
        end
    end
    return nil
end

local function fetchLiveEventData(eventId, eventHint)
    local eventData = {}
    if type(eventHint) == "table" then
        for key, value in pairs(eventHint) do
            eventData[key] = value
        end
    end
    if trimString(eventData.title) == ""
        and type(GetLiveEventData) == "function"
        and (eventHint ~= nil or findLiveEventListEntry(eventId) ~= nil)
    then
        local okData, apiData = tryCall("fetchLiveEventData.GetLiveEventData", GetLiveEventData, eventId)
        if okData and type(apiData) == "table" then
            for key, value in pairs(apiData) do
                eventData[key] = value
            end
        end
    end
    eventData.id = eventData.id or eventId
    eventData.title = eventData.title or eventData.name or defaultLiveEventTitle(eventId)
    return eventData
end

local function fetchLiveEventTasks(eventId)
    if type(GetLiveEventTasks) ~= "function" then
        return nil
    end
    local okTasks, tasks = tryCall("fetchLiveEventTasks.GetLiveEventTasks", GetLiveEventTasks, eventId)
    if okTasks and type(tasks) == "table" then
        return tasks
    end
    return nil
end

local function isEventEnded(eventData, tasks)
    if type(eventData) == "table" and eventData.ended == true then
        return true
    end
    if type(tasks) == "table" and tasks.ended == true then
        return true
    end
    return false
end

local function isEventEligible(eventData, tasks)
    if type(eventData) == "table" and eventData.eligible == false then
        return false
    end
    if type(tasks) == "table" and tasks.eligible == false then
        return false
    end
    return true
end

local function shouldDisplayLiveEventInMenu(ended, eligible)
    local settings = ensureSettings()
    if settings.showEndedEvents ~= true and ended == true then
        return false
    end
    return eligible ~= false
end

local function getRewardThresholds(tasks)
    local thresholds = {}
    if type(tasks) ~= "table" or type(tasks.rewards) ~= "table" then
        return thresholds
    end
    for level = 1, getNumRewardLevels() do
        local reward = tasks.rewards[level]
        local threshold = tonumber(reward and reward.threshold)
        if threshold ~= nil and threshold > 0 then
            thresholds[level] = threshold
        end
    end
    return thresholds
end

local function getCachedEventTier(settings, eventId, level)
    if type(settings.eventRewardCache) ~= "table" then
        return nil
    end
    local entry = settings.eventRewardCache[tostring(eventId)]
    if type(entry) ~= "table" or type(entry.tiers) ~= "table" then
        return nil
    end
    return entry.tiers[level]
end

-- Live-event claim state:
--   • Threshold met + no purchased record → unclaimed (do not require an NPC visit).
--   • purchased comes from INTERACT_SHOW_EVENT_REWARDS and/or SelectEventRewards.
--   • purchased is monotonic: once true, never cleared.
local function getLiveEventRewardsReceived(eventId, tasks, currentValue, thresholds)
    local received = {}
    if type(thresholds) ~= "table" then
        return received
    end
    local settings = ensureSettings()
    local current = tonumber(currentValue) or 0
    for level = 1, getNumRewardLevels() do
        local threshold = thresholds[level]
        if threshold == nil or current < threshold then
            received[level] = false
        else
            local tierCache = getCachedEventTier(settings, eventId, level)
            -- Reached + missing/false purchased → treat as not received (unclaimed).
            received[level] = type(tierCache) == "table" and isTruthyFlag(tierCache.purchased)
        end
    end
    return received
end

-- Mark tiers purchased after SelectEventRewards; INTERACT_SHOW_EVENT_REWARDS only
-- snapshots claim state when the NPC window opens, not when Select is pressed.
local function markEventRewardTiersPurchased(eventId, purchasedLevels)
    local id = tonumber(eventId)
    if id == nil and eventId ~= nil then
        id = tonumber(tostring(eventId))
    end
    if id == nil or type(purchasedLevels) ~= "table" then
        return false
    end

    local settings = ensureSettings()
    local key = tostring(id)
    local entry = settings.eventRewardCache[key]
    if type(entry) ~= "table" then
        entry = { tiers = {} }
        settings.eventRewardCache[key] = entry
    end
    if type(entry.tiers) ~= "table" then
        entry.tiers = {}
    end

    local changed = false
    for level, purchased in pairs(purchasedLevels) do
        local levelIndex = tonumber(level)
        if levelIndex ~= nil and purchased == true then
            local tier = entry.tiers[levelIndex]
            if type(tier) ~= "table" then
                tier = {}
                entry.tiers[levelIndex] = tier
            end
            if tier.purchased ~= true then
                changed = true
            end
            tier.purchased = true
            tier.eligible = false
        end
    end

    if changed or entry.updatedAt == nil then
        entry.updatedAt = type(GetGameTime) == "function" and GetGameTime() or 0
    end

    return changed or next(purchasedLevels) ~= nil
end

local function readPressedEventRewardLevels()
    local purchasedLevels = {}
    local numLevels = getNumRewardLevels()
    local maxPerLevel = 4
    if type(TomeWindow) == "table" and tonumber(TomeWindow.MAX_REWARDS_PER_LEVEL) then
        maxPerLevel = tonumber(TomeWindow.MAX_REWARDS_PER_LEVEL)
    end

    if type(ButtonGetPressedFlag) ~= "function" then
        return purchasedLevels
    end

    for level = 1, numLevels do
        for reward = 1, maxPerLevel do
            local buttonName = "EA_Window_InteractionEventRewardsLevel" .. level .. "Reward" .. reward
            if DoesWindowExist(buttonName)
                and ButtonGetPressedFlag(buttonName) == true
                -- Ignore disabled icons (already claimed / not eligible); only a live player pick counts.
                and (type(ButtonGetDisabledFlag) ~= "function" or ButtonGetDisabledFlag(buttonName) ~= true)
            then
                purchasedLevels[level] = true
                break
            end
        end
    end

    return purchasedLevels
end

local function hookInteractionRewardSelection()
    if Track._eventRewardSelectHooked == true then
        return
    end
    if type(EA_Window_InteractionEventRewards) ~= "table"
        or type(EA_Window_InteractionEventRewards.SelectEventRewards) ~= "function"
    then
        return
    end
    if EA_Window_InteractionEventRewards.SelectEventRewards == Track._originalSelectEventRewards then
        return
    end

    Track._originalSelectEventRewards = EA_Window_InteractionEventRewards.SelectEventRewards
    EA_Window_InteractionEventRewards.SelectEventRewards = function()
        local selectButton = "EA_Window_InteractionEventRewardsSelect"
        if type(ButtonGetDisabledFlag) == "function"
            and DoesWindowExist(selectButton)
            and ButtonGetDisabledFlag(selectButton) == true
        then
            return Track._originalSelectEventRewards()
        end

        local eventId = EA_Window_InteractionEventRewards.currentEvent
        local purchasedLevels = readPressedEventRewardLevels()
        Track._originalSelectEventRewards()

        if markEventRewardTiersPurchased(eventId, purchasedLevels) then
            Track.InvokeRefreshHandler()
        end
    end
    Track._eventRewardSelectHooked = true
end

local function unhookInteractionRewardSelection()
    if Track._eventRewardSelectHooked ~= true then
        return
    end
    if type(EA_Window_InteractionEventRewards) == "table"
        and type(Track._originalSelectEventRewards) == "function"
    then
        EA_Window_InteractionEventRewards.SelectEventRewards = Track._originalSelectEventRewards
    end
    Track._originalSelectEventRewards = nil
    Track._eventRewardSelectHooked = false
end

function Track.GetMode()
    return ensureSettings().mode
end

function Track.IsUserLiveEventMode()
    return Track.GetMode() == Track.MODE_LIVE_EVENT
end

function Track.IsCurrentAreaMode()
    return Track.GetMode() == Track.MODE_CURRENT_AREA
end

--- Current Area → local zone influence (stock). Live event → manual selection only.
function Track.ResolveEffectiveTrack()
    local mode = Track.GetMode()
    local settings = ensureSettings()

    if mode == Track.MODE_LIVE_EVENT then
        local eventId = tonumber(settings.eventId)
        if eventId == nil then
            return { kind = "none", reason = "manual_missing" }
        end
        local listEntry = findLiveEventListEntry(eventId)
        local eventData = fetchLiveEventData(eventId, listEntry)
        return {
            kind = "live",
            eventId = eventId,
            title = eventData.title,
            reason = "manual",
        }
    end

    return {
        kind = "zone",
        influenceId = getLocalZoneInfluenceId(),
        reason = "area",
    }
end

function Track.SetModeCurrentArea()
    local settings = ensureSettings()
    settings.mode = Track.MODE_CURRENT_AREA
    settings.eventId = nil
end

--- @deprecated Use SetModeCurrentArea
function Track.SetModeAuto()
    Track.SetModeCurrentArea()
end

function Track.SetModeLiveEvent(eventId, eventKey, eventTitle)
    local settings = ensureSettings()
    settings.mode = Track.MODE_LIVE_EVENT
    settings.eventId = tonumber(eventId)
end

function Track.GetShowEndedEvents()
    return ensureSettings().showEndedEvents == true
end

function Track.ToggleShowEndedEvents()
    local settings = ensureSettings()
    settings.showEndedEvents = not (settings.showEndedEvents == true)
    return settings.showEndedEvents == true
end

function Track.GetTrackedEventId()
    if Track.GetMode() == Track.MODE_LIVE_EVENT then
        return tonumber(ensureSettings().eventId)
    end
    return nil
end

function Track.GetActiveLiveEventChoices()
    local choices = {}
    if type(GetLiveEventList) ~= "function" then
        return choices
    end
    local okList, liveEventList = tryCall("GetActiveLiveEventChoices.GetLiveEventList", GetLiveEventList)
    if not okList or type(liveEventList) ~= "table" then
        return choices
    end
    for _, event in ipairs(liveEventList) do
        if type(event) == "table" and event.id ~= nil then
            local ended = event.ended == true
            local eligible = event.eligible ~= false
            if shouldDisplayLiveEventInMenu(ended, eligible) then
                local eventData = fetchLiveEventData(event.id, event)
                local tasks = fetchLiveEventTasks(event.id)
                choices[#choices + 1] = {
                    eventId = tonumber(event.id) or event.id,
                    eventKey = buildEventKey(event.id, eventData.title),
                    title = eventData.title,
                    eligible = isEventEligible(eventData, tasks),
                    ended = ended or isEventEnded(eventData, tasks),
                }
            end
        end
    end
    table.sort(choices, function(left, right)
        local leftTitle = string.lower(trimString(left.title))
        local rightTitle = string.lower(trimString(right.title))
        if leftTitle ~= rightTitle then
            return leftTitle < rightTitle
        end
        return (tonumber(left.eventId) or 0) < (tonumber(right.eventId) or 0)
    end)
    return choices
end

local function influencePointsToWString(value)
    local n = math.floor(tonumber(value) or 0)
    if type(towstring) == "function" then
        return towstring(n)
    end
    return L"" .. n
end

local function appendBadgeStatLine(statLines, label, valueText)
    if type(statLines) ~= "table" or label == nil or label == L"" or valueText == nil or valueText == L"" then
        return
    end
    local labelText = label
    if wstring.find(labelText, L":", 1) == nil then
        labelText = labelText .. L":"
    end
    statLines[#statLines + 1] = { label = labelText, value = valueText }
end

local function visitLiveEventTaskTree(taskList, visitor, includeSubtasks)
    if type(taskList) ~= "table" or type(visitor) ~= "function" then
        return
    end
    for _, task in ipairs(taskList) do
        if type(task) == "table" and task.taskId ~= nil then
            visitor(task)
            if includeSubtasks == true and type(task.subtasks) == "table" then
                visitLiveEventTaskTree(task.subtasks, visitor, true)
            end
        end
    end
end

--- Top-level live-event tasks only (Tome main list). Subtasks are detail-page only.
local function collectLiveEventBadgeStatLines(tasksRoot)
    local entries = {}
    visitLiveEventTaskTree(tasksRoot, function(task)
        if type(task) ~= "table" or task.isOnlyText then
            return
        end
        if tonumber(task.taskId) == 0 then
            return
        end
        local maxValue = tonumber(task.maxValue)
        if maxValue == nil or maxValue <= 0 then
            return
        end
        local current = tonumber(task.currentValue) or 0
        local valueText = influencePointsToWString(current) .. L"/" .. influencePointsToWString(maxValue)
        local label = task.name
        if label == nil or label == L"" then
            label = L"Progress"
        end
        entries[#entries + 1] = {
            taskId = tonumber(task.taskId) or 0,
            label = label,
            value = valueText,
        }
    end, false)
    table.sort(entries, function(a, b)
        return a.taskId < b.taskId
    end)
    local statLines = {}
    for _, entry in ipairs(entries) do
        appendBadgeStatLine(statLines, entry.label, entry.value)
    end
    return statLines
end

local function computeZoneBadgeStats(influenceData)
    local value = 0
    local unclaimed = false
    if type(influenceData) ~= "table" or type(influenceData.rewardLevel) ~= "table" then
        return value, unclaimed
    end
    local current = tonumber(influenceData.curValue) or 0
    for level = 1, getNumRewardLevels() do
        local tier = influenceData.rewardLevel[level]
        if type(tier) == "table" then
            local needed = tonumber(tier.amountNeeded)
            if needed ~= nil and current >= needed then
                value = value + 1
                if tier.rewardsRecieved ~= true then
                    unclaimed = true
                end
            end
        end
    end
    return value, unclaimed
end

local function computeLiveBadgeStats(eventId, tasks)
    local value = 0
    local unclaimed = false
    if type(tasks) ~= "table" then
        return value, unclaimed
    end
    local thresholds = getRewardThresholds(tasks)
    local current = tonumber(tasks.overallCurrentValue) or 0
    local received = getLiveEventRewardsReceived(eventId, tasks, current, thresholds)
    for level = 1, getNumRewardLevels() do
        local threshold = thresholds[level]
        if threshold ~= nil and current >= threshold then
            value = value + 1
            if received[level] ~= true then
                unclaimed = true
            end
        end
    end
    return value, unclaimed
end

local function defaultZoneInfluenceTitle()
    if type(GetString) == "function" then
        local areaLabel = GetString(StringTables.Default.LABEL_AREA_INFLUENCE)
        if areaLabel ~= nil and areaLabel ~= L"" then
            return areaLabel
        end
    end
    return L"Local zone influence"
end

local function wstringNonEmpty(value)
    return value ~= nil and value ~= L""
end

local function joinHeadingParts(left, right)
    if wstringNonEmpty(left) and wstringNonEmpty(right) then
        return left .. L" - " .. right
    end
    if wstringNonEmpty(left) then
        return left
    end
    if wstringNonEmpty(right) then
        return right
    end
    return nil
end

local function getFriendlyRaceName()
    if type(StringUtils) ~= "table"
        or type(StringUtils.GetFriendlyRaceForCurrentPairing) ~= "function"
    then
        return nil
    end
    local pairing = nil
    if type(GetZonePairing) == "function" then
        local okPair, pairValue = tryCall("getFriendlyRaceName.GetZonePairing", GetZonePairing)
        if okPair then
            pairing = pairValue
        end
    end
    local okRace, raceName = tryCall(
        "getFriendlyRaceName.GetFriendlyRace",
        StringUtils.GetFriendlyRaceForCurrentPairing,
        pairing,
        false
    )
    if okRace and wstringNonEmpty(raceName) then
        return raceName
    end
    return nil
end

--- WAR Story chapter / Open-RvR titles use pairing race + entry title
--- (e.g. "Empire - Chapter 12"). Place entries use title + name
--- (e.g. "Altdorf - Sigmar's Crypts").
local function isWarJournalChapterStyleTitle(title)
    local text = string.lower(trimString(title))
    if text == "" then
        return false
    end
    if string.find(text, "chapter", 1, true) ~= nil then
        return true
    end
    if string.find(text, "open rvr", 1, true) ~= nil then
        return true
    end
    if string.find(text, "rvr", 1, true) ~= nil and string.find(text, "tier", 1, true) ~= nil then
        return true
    end
    return false
end

--- Prefer Tome WAR Story entry title/name; fall back to chapter/zone APIs.
local function buildZoneInfluenceHeading(influenceId, influenceData)
    local tomeEntry = nil
    if type(influenceData) == "table" then
        tomeEntry = tonumber(influenceData.tomeEntry)
    end
    if tomeEntry ~= nil
        and tomeEntry ~= 0
        and type(TomeGetWarJournalEntryData) == "function"
    then
        local okEntry, entry = tryCall(
            "buildZoneInfluenceHeading.TomeGetWarJournalEntryData",
            TomeGetWarJournalEntryData,
            tomeEntry
        )
        if okEntry and type(entry) == "table" and wstringNonEmpty(entry.title) then
            if isWarJournalChapterStyleTitle(entry.title) then
                local joined = joinHeadingParts(getFriendlyRaceName(), entry.title)
                if joined ~= nil then
                    return joined
                end
                return entry.title
            end
            local joined = joinHeadingParts(entry.title, entry.name)
            if joined ~= nil then
                return joined
            end
        end
    end

    local id = tonumber(influenceId)
    if id ~= nil
        and id > 0
        and type(influenceData) == "table"
        and influenceData.isRvRInfluence ~= true
        and not (influenceData.zoneNum == 0 and influenceData.zoneAreaNum == 0)
        and type(GetChapterShortName) == "function"
    then
        local okChap, chapterName = tryCall(
            "buildZoneInfluenceHeading.GetChapterShortName",
            GetChapterShortName,
            id
        )
        if okChap and wstringNonEmpty(chapterName) then
            local joined = joinHeadingParts(getFriendlyRaceName(), chapterName)
            if joined ~= nil then
                return joined
            end
            return chapterName
        end
    end

    if type(influenceData) == "table"
        and tonumber(influenceData.zoneNum) ~= nil
        and influenceData.zoneNum ~= 0
        and type(GetZoneName) == "function"
    then
        local okZone, zoneName = tryCall(
            "buildZoneInfluenceHeading.GetZoneName",
            GetZoneName,
            influenceData.zoneNum
        )
        local areaName = nil
        if tonumber(influenceData.zoneAreaNum) ~= nil
            and influenceData.zoneAreaNum ~= 0
            and type(GetZoneAreaName) == "function"
        then
            local okArea, areaValue = tryCall(
                "buildZoneInfluenceHeading.GetZoneAreaName",
                GetZoneAreaName,
                influenceData.zoneNum,
                influenceData.zoneAreaNum
            )
            if okArea then
                areaName = areaValue
            end
        end
        if okZone then
            local joined = joinHeadingParts(zoneName, areaName)
            if joined ~= nil then
                return joined
            end
        end
    end

    return defaultZoneInfluenceTitle()
end

function Track.GetBadgeSnapshot()
    local mode = Track.GetMode()
    local effective = Track.ResolveEffectiveTrack()
    local snapshot = {
        value = 0,
        empty = true,
        unclaimed = false,
        mode = mode,
        effectiveKind = effective.kind,
        eventId = effective.eventId,
        influenceId = effective.influenceId,
        available = true,
        autoReason = effective.reason,
    }

    if effective.kind == "live" and effective.eventId ~= nil then
        local tasks = fetchLiveEventTasks(effective.eventId)
        if tasks ~= nil then
            snapshot.value, snapshot.unclaimed = computeLiveBadgeStats(effective.eventId, tasks)
            snapshot.empty = false
        end
        return snapshot
    end

    if effective.kind == "zone" then
        local influenceId = effective.influenceId or getLocalZoneInfluenceId()
        snapshot.influenceId = influenceId
        if influenceId ~= nil
            and type(DataUtils) == "table"
            and type(DataUtils.GetInfluenceData) == "function"
        then
            local ok, influenceData = tryCall(
                "GetBadgeSnapshot.GetInfluenceData",
                DataUtils.GetInfluenceData,
                influenceId
            )
            if ok and type(influenceData) == "table" then
                snapshot.value, snapshot.unclaimed = computeZoneBadgeStats(influenceData)
                snapshot.empty = false
            end
        end
    end

    return snapshot
end

----------------------------------------------------------------
-- Verbose tooltip (match EA_ObjectiveTrackers influence-bar style)
----------------------------------------------------------------

local INFLUENCE_TOOLTIP_REWARD_AVAILABLE = { r = 255, g = 255, b = 0 }
local INFLUENCE_TOOLTIP_REWARD_RECEIVED = { r = 150, g = 150, b = 150 }

local function appendTooltipTextLine(bodyLines, text, colorDef)
    if type(bodyLines) ~= "table" or text == nil or text == L"" then
        return
    end
    bodyLines[#bodyLines + 1] = { kind = "text", text = text, color = colorDef }
end

local function appendTooltipStatLine(bodyLines, label, value)
    if type(bodyLines) ~= "table" or label == nil or value == nil or value == L"" then
        return
    end
    bodyLines[#bodyLines + 1] = { kind = "stat", label = label, value = value }
end

local function appendTooltipMutedLine(bodyLines, text)
    local muted = type(Tooltips) == "table" and Tooltips.COLOR_EXTRA_TEXT_DEFAULT or nil
    appendTooltipTextLine(bodyLines, text, muted)
end

local function appendTooltipBodyLine(bodyLines, text)
    local bodyColor = type(Tooltips) == "table" and Tooltips.COLOR_BODY or nil
    appendTooltipTextLine(bodyLines, text, bodyColor)
end

local function appendTooltipHeadingLine(bodyLines, text)
    local heading = type(Tooltips) == "table" and Tooltips.COLOR_HEADING or nil
    appendTooltipTextLine(bodyLines, text, heading)
end

local function getZoneRewardTierTooltipMeta()
    if type(StringTables) ~= "table" or StringTables.Default == nil then
        return {
            { label = L"Basic", received = nil, avail = nil },
            { label = L"Advanced", received = nil, avail = nil },
            { label = L"Elite", received = nil, avail = nil },
        }
    end
    local d = StringTables.Default
    return {
        { label = L"Basic", received = d.TEXT_BASIC_REWARD_RECEIVED, avail = d.TEXT_BASIC_REWARD_AVAILIABLE },
        { label = L"Advanced", received = d.TEXT_ADVANCED_REWARD_RECEIVED, avail = d.TEXT_ADVANCED_REWARD_AVAILIABLE },
        { label = L"Elite", received = d.TEXT_ELITE_REWARD_RECEIVED, avail = d.TEXT_ELITE_REWARD_AVAILIABLE },
    }
end

local function appendCurrentInfluenceLine(bodyLines, curValue)
    local current = tonumber(curValue)
    if current == nil then
        return
    end
    local label = L"Current Influence:"
    if type(GetString) == "function"
        and type(StringTables) == "table"
        and StringTables.Default ~= nil
        and StringTables.Default.LABEL_CURRENT_INFLUENCE ~= nil
    then
        local stockLabel = GetString(StringTables.Default.LABEL_CURRENT_INFLUENCE)
        if stockLabel ~= nil and stockLabel ~= L"" then
            label = stockLabel
        end
    end
    if wstring.find(label, L":", 1) == nil then
        label = label .. L":"
    end
    appendTooltipStatLine(bodyLines, label, influencePointsToWString(current))
end

local function getNeedMoreInfluenceStatusText()
    if type(GetString) == "function"
        and type(StringTables) == "table"
        and StringTables.Default ~= nil
        and StringTables.Default.TEXT_NEED_INFL_POINTS ~= nil
    then
        local stock = GetString(StringTables.Default.TEXT_NEED_INFL_POINTS)
        if stock ~= nil and stock ~= L"" then
            return stock
        end
    end
    return L"Need more influence"
end

local function appendTierProgressLine(bodyLines, tierLabel, curValue, amountNeeded, stringIdReceived, stringIdAvailable, rewardsReceived)
    if tierLabel == nil then
        return
    end
    local needed = tonumber(amountNeeded)
    if needed == nil then
        return
    end
    local current = tonumber(curValue) or 0
    local tierLabelText = tierLabel
    if wstring.find(tierLabelText, L":", 1) == nil then
        tierLabelText = tierLabelText .. L":"
    end
    appendTooltipStatLine(
        bodyLines,
        tierLabelText,
        influencePointsToWString(current) .. L" / " .. influencePointsToWString(needed)
    )
    if type(GetString) == "function" then
        local status = nil
        local statusColor = INFLUENCE_TOOLTIP_REWARD_AVAILABLE
        if rewardsReceived == true and stringIdReceived ~= nil then
            status = GetString(stringIdReceived)
            statusColor = INFLUENCE_TOOLTIP_REWARD_RECEIVED
        elseif current >= needed and stringIdAvailable ~= nil then
            status = GetString(stringIdAvailable)
        elseif current < needed then
            -- Same wording as Event Reward NPC disabled-tier overlay.
            status = getNeedMoreInfluenceStatusText()
            statusColor = INFLUENCE_TOOLTIP_REWARD_RECEIVED
        end
        if status ~= nil and status ~= L"" then
            appendTooltipTextLine(bodyLines, status, statusColor)
        end
    end
end

local function buildZoneInfluenceDescription(influenceData)
    if type(influenceData) ~= "table" or type(GetStringFormat) ~= "function" then
        return nil
    end
    if influenceData.zoneNum == 0 and influenceData.zoneAreaNum == 0 then
        return nil
    end

    local player = GameData and GameData.Player
    if type(player) == "table" and player.isInSiege and type(GetCityNameForRealm) == "function" then
        local cityName = GetCityNameForRealm(player.realm)
        return GetStringFormat(
            StringTables.Default.TEXT_PQ_TRACKER_INFLUENCE_CITY_BAR,
            { influenceData.npcName, cityName }
        )
    end
    if influenceData.isRvRInfluence == true and type(GetZoneName) == "function" then
        local zoneName = GetZoneName(influenceData.zoneNum)
        return GetStringFormat(
            StringTables.Default.TEXT_PQ_TRACKER_INFLUENCE_RVR_BAR,
            { influenceData.npcName, zoneName }
        )
    end
    if type(GetZoneName) == "function" and type(GetZoneAreaName) == "function" then
        local zoneName = GetZoneName(influenceData.zoneNum)
        local areaName = GetZoneAreaName(influenceData.zoneNum, influenceData.zoneAreaNum)
        return GetStringFormat(
            StringTables.Default.TEXT_PQ_TRACKER_INFLUENCE_BAR,
            { influenceData.npcName, areaName, zoneName }
        )
    end
    return nil
end

local function appendZoneInfluenceValueLines(bodyLines, influenceData)
    if type(bodyLines) ~= "table" or type(influenceData) ~= "table" then
        return
    end
    appendCurrentInfluenceLine(bodyLines, influenceData.curValue)
    if type(influenceData.rewardLevel) ~= "table" then
        return
    end
    local tierMeta = getZoneRewardTierTooltipMeta()
    for level = 1, getNumRewardLevels() do
        local tier = influenceData.rewardLevel[level]
        local meta = tierMeta[level]
        if type(tier) == "table" and meta ~= nil then
            appendTierProgressLine(
                bodyLines,
                meta.label,
                influenceData.curValue,
                tier.amountNeeded,
                meta.received,
                meta.avail,
                tier.rewardsRecieved == true
            )
        end
    end
end

-- Live-event reward.threshold is often a discrete progress unit (10/20/30), not
-- influence points. When a single dominant gather-influence task exposes the real
-- max (e.g. RvR Week 10000), map thresholds onto that scale for display.
-- Seasonal task events (Pie Week) keep the raw thresholds.
local LIVE_EVENT_INFLUENCE_SCALE_MIN_RATIO = 50

local function getFinalRewardThreshold(thresholds)
    if type(thresholds) ~= "table" then
        return nil
    end
    local finalThreshold = nil
    for level = 1, getNumRewardLevels() do
        local threshold = tonumber(thresholds[level])
        if threshold ~= nil and threshold > 0 then
            finalThreshold = threshold
        end
    end
    return finalThreshold
end

local function findLiveEventInfluenceScaleTask(tasks, finalThreshold)
    finalThreshold = tonumber(finalThreshold)
    if type(tasks) ~= "table" or finalThreshold == nil or finalThreshold <= 0 then
        return nil
    end

    local candidates = {}
    local totalMax = 0
    visitLiveEventTaskTree(tasks, function(task)
        if type(task) ~= "table" or task.isOnlyText then
            return
        end
        if tonumber(task.taskId) == 0 then
            return
        end
        local maxValue = tonumber(task.maxValue)
        if maxValue == nil or maxValue <= 0 then
            return
        end
        candidates[#candidates + 1] = {
            current = tonumber(task.currentValue) or 0,
            maxValue = maxValue,
        }
        totalMax = totalMax + maxValue
    end, false)

    if candidates[1] == nil then
        return nil
    end

    table.sort(candidates, function(a, b)
        return a.maxValue > b.maxValue
    end)
    local best = candidates[1]
    if best.maxValue < finalThreshold * LIVE_EVENT_INFLUENCE_SCALE_MIN_RATIO then
        return nil
    end

    -- Prefer a lone large task, or one that clearly dominates the event totals.
    if #candidates > 1 and (best.maxValue / totalMax) < 0.75 then
        return nil
    end

    return {
        current = best.current,
        maxValue = best.maxValue,
        finalThreshold = finalThreshold,
    }
end

local function scaleLiveEventThresholdToInfluence(threshold, scaleInfo)
    threshold = tonumber(threshold)
    if threshold == nil or type(scaleInfo) ~= "table" then
        return nil
    end
    local finalThreshold = tonumber(scaleInfo.finalThreshold)
    local maxValue = tonumber(scaleInfo.maxValue)
    if finalThreshold == nil or finalThreshold <= 0 or maxValue == nil or maxValue <= 0 then
        return nil
    end
    return math.floor((threshold / finalThreshold) * maxValue + 0.5)
end

local function appendLiveEventTierWithStatus(bodyLines, eventId, tasks)
    if type(tasks) ~= "table" then
        return
    end
    local thresholds = getRewardThresholds(tasks)
    local current = tonumber(tasks.overallCurrentValue) or 0
    local received = getLiveEventRewardsReceived(eventId, tasks, current, thresholds)
    local scaleInfo = findLiveEventInfluenceScaleTask(tasks, getFinalRewardThreshold(thresholds))
    local displayCurrent = current
    if scaleInfo ~= nil then
        displayCurrent = scaleInfo.current
    end
    local tierMeta = getZoneRewardTierTooltipMeta()
    for level = 1, getNumRewardLevels() do
        local needed = thresholds[level]
        local meta = tierMeta[level]
        if needed ~= nil and meta ~= nil then
            local displayNeeded = needed
            if scaleInfo ~= nil then
                local scaled = scaleLiveEventThresholdToInfluence(needed, scaleInfo)
                if scaled ~= nil then
                    displayNeeded = scaled
                end
            end
            appendTierProgressLine(
                bodyLines,
                meta.label,
                displayCurrent,
                displayNeeded,
                meta.received,
                meta.avail,
                received[level] == true
            )
        end
    end
end

function Track.HasEventRewardCache(eventId)
    local id = tonumber(eventId)
    if id == nil then
        return false
    end
    local settings = ensureSettings()
    local entry = settings.eventRewardCache[tostring(id)]
    return type(entry) == "table" and type(entry.tiers) == "table"
end

--- Full tooltip payload for the portrait badge (EAOT-style verbosity).
function Track.GetBadgeTooltip()
    local effective = Track.ResolveEffectiveTrack()
    local result = {
        available = false,
        heading = L"",
        bodyLines = {},
        actionText = nil,
    }

    local clickRewards = L"Click to view the area WAR Story entry and available rewards"
    if type(GetString) == "function"
        and type(StringTables) == "table"
        and StringTables.Default ~= nil
        and StringTables.Default.TEXT_CLICK_VIEW_REWARDS ~= nil
    then
        local stock = GetString(StringTables.Default.TEXT_CLICK_VIEW_REWARDS)
        if stock ~= nil and stock ~= L"" then
            clickRewards = stock
        end
    end

    if effective.kind == "live" and effective.eventId ~= nil then
        local listEntry = findLiveEventListEntry(effective.eventId)
        local eventData = fetchLiveEventData(effective.eventId, listEntry)
        local tasks = fetchLiveEventTasks(effective.eventId)
        local title = effective.title or eventData.title or defaultLiveEventTitle(effective.eventId)
        if title == nil or title == L"" then
            title = L"Live Event"
        end

        if tasks == nil then
            result.available = true
            result.heading = title
            appendTooltipBodyLine(result.bodyLines, L"Live event data is unavailable.")
            appendTooltipMutedLine(result.bodyLines, L"Right-click to select Current Area or another live event")
            return result
        end

        result.available = true
        result.heading = title
        result.actionText = clickRewards

        if eventData.subTitle ~= nil and eventData.subTitle ~= L"" then
            appendTooltipBodyLine(result.bodyLines, eventData.subTitle)
        end

        local taskLines = collectLiveEventBadgeStatLines(tasks)
        if taskLines[1] ~= nil then
            for _, entry in ipairs(taskLines) do
                appendTooltipStatLine(result.bodyLines, entry.label, entry.value)
            end
        else
            appendCurrentInfluenceLine(result.bodyLines, tasks.overallCurrentValue)
        end
        appendLiveEventTierWithStatus(result.bodyLines, effective.eventId, tasks)

        appendTooltipMutedLine(result.bodyLines, L"Right-click to change track source")
        if not Track.HasEventRewardCache(effective.eventId) then
            appendTooltipMutedLine(
                result.bodyLines,
                L"Open the event reward NPC to confirm claimed tiers"
            )
        end
        return result
    end

    if effective.kind == "zone" then
        local influenceId = effective.influenceId or getLocalZoneInfluenceId()
        result.heading = defaultZoneInfluenceTitle()

        if influenceId == nil
            or type(DataUtils) ~= "table"
            or type(DataUtils.GetInfluenceData) ~= "function"
        then
            result.available = true
            appendTooltipBodyLine(result.bodyLines, L"No area influence to track in this location.")
            appendTooltipMutedLine(result.bodyLines, L"Right-click to track a live event")
            return result
        end
        local ok, influenceData = tryCall(
            "GetBadgeTooltip.GetInfluenceData",
            DataUtils.GetInfluenceData,
            influenceId
        )
        if not ok or type(influenceData) ~= "table" then
            result.available = true
            appendTooltipBodyLine(result.bodyLines, L"No area influence to track in this location.")
            appendTooltipMutedLine(result.bodyLines, L"Right-click to track a live event")
            return result
        end

        result.available = true
        result.heading = buildZoneInfluenceHeading(influenceId, influenceData)
        result.actionText = clickRewards

        local description = buildZoneInfluenceDescription(influenceData)
        if description ~= nil and description ~= L"" then
            appendTooltipBodyLine(result.bodyLines, description)
        end
        appendZoneInfluenceValueLines(result.bodyLines, influenceData)
        appendTooltipMutedLine(result.bodyLines, L"Right-click to track a live event")
        return result
    end

    -- Manual live event missing / unavailable: still show a tip.
    result.available = true
    result.heading = defaultZoneInfluenceTitle()
    appendTooltipBodyLine(result.bodyLines, L"No area influence to track in this location.")
    appendTooltipMutedLine(result.bodyLines, L"Right-click to track a live event")
    return result
end

--- Always use CustomUI's verbose tooltip (zone + live). Stock EAOT is thin;
--- do not pass through OnMouseOverInfluenceBar.
function Track.ShowBadgeTooltip(anchorWindow, tooltipAnchor)
    local tip = Track.GetBadgeTooltip()
    if tip.available ~= true then
        return false
    end

    local anchor = anchorWindow or SystemData.ActiveWindow.name
    Tooltips.CreateTextOnlyTooltip(anchor)
    Tooltips.SetTooltipText(1, 1, tip.heading)
    if type(Tooltips) == "table" and Tooltips.COLOR_HEADING ~= nil then
        Tooltips.SetTooltipColorDef(1, 1, Tooltips.COLOR_HEADING)
    end

    local valueColumn = (type(Tooltips) == "table" and Tooltips.COLUMN_RIGHT_LEFT_ALIGN) or 3
    local row = 2
    for _, entry in ipairs(tip.bodyLines) do
        if type(entry) == "table" and entry.kind == "stat" then
            if entry.label ~= nil and entry.label ~= L"" then
                Tooltips.SetTooltipText(row, 1, entry.label)
                if Tooltips.COLOR_HEADING ~= nil then
                    Tooltips.SetTooltipColorDef(row, 1, Tooltips.COLOR_HEADING)
                end
            end
            if entry.value ~= nil and entry.value ~= L"" then
                Tooltips.SetTooltipText(row, valueColumn, entry.value)
                if Tooltips.COLOR_BODY ~= nil then
                    Tooltips.SetTooltipColorDef(row, valueColumn, Tooltips.COLOR_BODY)
                end
            end
            row = row + 1
        elseif type(entry) == "table" and entry.kind == "text" and entry.text ~= nil and entry.text ~= L"" then
            Tooltips.SetTooltipText(row, 1, entry.text)
            if entry.color ~= nil then
                if type(entry.color) == "table" and entry.color.r ~= nil and Tooltips.SetTooltipColor ~= nil then
                    Tooltips.SetTooltipColor(row, 1, entry.color.r, entry.color.g, entry.color.b)
                elseif Tooltips.SetTooltipColorDef ~= nil then
                    Tooltips.SetTooltipColorDef(row, 1, entry.color)
                end
            elseif Tooltips.COLOR_BODY ~= nil then
                Tooltips.SetTooltipColorDef(row, 1, Tooltips.COLOR_BODY)
            end
            row = row + 1
        end
    end

    if tip.actionText ~= nil and tip.actionText ~= L"" and type(Tooltips.SetTooltipActionText) == "function" then
        Tooltips.SetTooltipActionText(tip.actionText)
    end

    Tooltips.Finalize()
    local tipAnchor = tooltipAnchor
    if type(tipAnchor) ~= "table"
        and type(CustomUI.PlayerStatusWindow) == "table"
        and type(CustomUI.PlayerStatusWindow.TOOLTIP_ANCHOR) == "table"
    then
        tipAnchor = CustomUI.PlayerStatusWindow.TOOLTIP_ANCHOR
    end
    if type(tipAnchor) == "table" then
        Tooltips.AnchorTooltip(tipAnchor)
    elseif Tooltips.ANCHOR_WINDOW_LEFT ~= nil then
        Tooltips.AnchorTooltip(Tooltips.ANCHOR_WINDOW_LEFT)
    end
    return true
end

function Track.OpenTrackedLiveEventTome()
    local eventId = Track.GetTrackedEventId()
    if eventId == nil then
        return false
    end
    if type(TomeWindow) == "table" and type(TomeWindow.OpenTomeToEntry) == "function" then
        local section = GameData and GameData.Tome and GameData.Tome.SECTION_LIVE_EVENT
        local ok = tryCall("OpenTrackedLiveEventTome", TomeWindow.OpenTomeToEntry, section, eventId)
        if ok then
            return true
        end
    end
    return false
end

function Track.OpenTrackedSourceTome()
    local effective = Track.ResolveEffectiveTrack()
    if effective.kind == "live" then
        return Track.OpenTrackedLiveEventTome()
    end
    if effective.kind ~= "zone" then
        return false
    end
    local influenceId = effective.influenceId or getLocalZoneInfluenceId()
    if influenceId == nil
        or type(DataUtils) ~= "table"
        or type(DataUtils.GetInfluenceData) ~= "function"
    then
        return false
    end
    local ok, influenceData = tryCall("OpenTrackedSourceTome.GetInfluenceData", DataUtils.GetInfluenceData, influenceId)
    if not ok or type(influenceData) ~= "table" then
        return false
    end
    if influenceData.zoneNum == 0 and influenceData.zoneAreaNum == 0 then
        return false
    end
    if type(TomeWindow) == "table" and type(TomeWindow.OpenTomeToEntry) == "function" then
        local opened = tryCall(
            "OpenTrackedSourceTome.OpenTomeToEntry",
            TomeWindow.OpenTomeToEntry,
            influenceData.tomeSection,
            influenceData.tomeEntry
        )
        return opened == true
    end
    return false
end

local function menuLabel(text, selected)
    if selected then
        return L"* " .. text
    end
    return text
end

function Track.ShowTrackContextMenu(anchorWindow)
    if type(EA_Window_ContextMenu) ~= "table"
        or type(EA_Window_ContextMenu.CreateContextMenu) ~= "function"
        or type(EA_Window_ContextMenu.AddMenuItem) ~= "function"
        or type(EA_Window_ContextMenu.Finalize) ~= "function"
    then
        return false
    end

    local menuId = EA_Window_ContextMenu.CONTEXT_MENU_1 or 1
    local ok = tryCallLoud(
        "ShowTrackContextMenu.CreateContextMenu",
        EA_Window_ContextMenu.CreateContextMenu,
        anchorWindow or "Root",
        menuId,
        nil
    )
    if not ok then
        return false
    end

    tryCallLoud(
        "ShowTrackContextMenu.auto",
        EA_Window_ContextMenu.AddMenuItem,
        menuLabel(L"Current Area", Track.IsCurrentAreaMode()),
        function()
            Track.SetModeCurrentArea()
            Track.InvokeRefreshHandler()
        end,
        false,
        true,
        menuId
    )

    if type(EA_Window_ContextMenu.AddMenuDivider) == "function" then
        tryCall("ShowTrackContextMenu.divider", EA_Window_ContextMenu.AddMenuDivider, menuId)
    end

    local choices = Track.GetActiveLiveEventChoices()
    local trackedId = tonumber(ensureSettings().eventId)
    for _, choice in ipairs(choices) do
        local eventId = choice.eventId
        local eventKey = choice.eventKey
        local title = choice.title or defaultLiveEventTitle(eventId)
        local selected = Track.IsUserLiveEventMode() and trackedId == tonumber(eventId)
        tryCall(
            "ShowTrackContextMenu.live",
            EA_Window_ContextMenu.AddMenuItem,
            menuLabel(title, selected),
            function()
                Track.SetModeLiveEvent(eventId, eventKey, title)
                Track.InvokeRefreshHandler()
            end,
            false,
            true,
            menuId
        )
    end

    if choices[1] == nil then
        tryCall(
            "ShowTrackContextMenu.empty",
            EA_Window_ContextMenu.AddMenuItem,
            L"(No live events)",
            function() end,
            true,
            false,
            menuId
        )
    end

    if type(EA_Window_ContextMenu.AddMenuDivider) == "function" then
        tryCall("ShowTrackContextMenu.divider2", EA_Window_ContextMenu.AddMenuDivider, menuId)
    end

    tryCall(
        "ShowTrackContextMenu.showEnded",
        EA_Window_ContextMenu.AddMenuItem,
        menuLabel(L"Show events that have ended", Track.GetShowEndedEvents()),
        function()
            Track.ToggleShowEndedEvents()
            Track.InvokeRefreshHandler()
        end,
        false,
        true,
        menuId
    )

    tryCall("ShowTrackContextMenu.Finalize", EA_Window_ContextMenu.Finalize, menuId)
    return true
end

local function cacheEventRewardsFromInteraction(rewardData)
    if type(rewardData) ~= "table" then
        return
    end
    local settings = ensureSettings()
    local gameTime = type(GetGameTime) == "function" and GetGameTime() or 0
    for eventId, eventEntry in pairs(rewardData) do
        local id = tonumber(eventId)
        if id == nil and eventId ~= nil then
            id = tonumber(tostring(eventId))
        end
        if id ~= nil and type(eventEntry) == "table" and type(eventEntry.rewards) == "table" then
            local key = tostring(id)
            local prevEntry = settings.eventRewardCache[key]
            local prevTier = type(prevEntry) == "table" and prevEntry.tiers or nil
            local tiers = {}
            local seenLevels = {}
            for level, tier in ipairs(eventEntry.rewards) do
                if type(tier) == "table" then
                    seenLevels[level] = true
                    -- NPC snapshot is authoritative for tiers it includes (can clear false claims).
                    -- Select-hook claims only stick across opens when the NPC omits that tier.
                    tiers[level] = {
                        eligible = isTruthyFlag(tier.eligible),
                        purchased = isTruthyFlag(tier.purchased),
                    }
                end
            end
            -- Keep Select/prior claims only for tiers omitted from this payload.
            if type(prevTier) == "table" then
                for level, prev in pairs(prevTier) do
                    if type(prev) == "table"
                        and prev.purchased == true
                        and seenLevels[level] ~= true
                    then
                        tiers[level] = {
                            eligible = false,
                            purchased = true,
                        }
                    end
                end
            end
            settings.eventRewardCache[key] = { tiers = tiers, updatedAt = gameTime }
        end
    end
end

function Track.OnInteractShowEventRewards(interactTarget, rewardData)
    hookInteractionRewardSelection()
    cacheEventRewardsFromInteraction(rewardData)
    Track.InvokeRefreshHandler()
end

function Track.OnPlayerInfluenceRewardsUpdated()
    if type(GameData) == "table" and type(GameData.Player) == "table" then
        GameData.Player.influenceDataDirty = true
    end
    Track.InvokeRefreshHandler()
end

function Track.OnRefreshEvents()
    hookInteractionRewardSelection()
    Track.InvokeRefreshHandler()
end

local function rememberRegisteredEvent(eventId, handlerName)
    Track._registeredEventSpecs[#Track._registeredEventSpecs + 1] = {
        eventId = eventId,
        handlerName = handlerName,
    }
end

function Track.UnregisterEvents()
    if type(UnregisterEventHandler) == "function" and type(Track._registeredEventSpecs) == "table" then
        for _, spec in ipairs(Track._registeredEventSpecs) do
            if spec.eventId ~= nil and spec.handlerName ~= nil then
                tryCallLoud(
                    "UnregisterEvents." .. tostring(spec.handlerName),
                    UnregisterEventHandler,
                    spec.eventId,
                    spec.handlerName
                )
            end
        end
    end
    Track._registeredEventSpecs = {}
    Track._eventsRegistered = false
end

function Track.RegisterEvents()
    if Track._eventsRegistered or type(RegisterEventHandler) ~= "function" then
        return
    end
    if type(SystemData) ~= "table" or type(SystemData.Events) ~= "table" then
        return
    end

    Track._registeredEventSpecs = {}
    local events = SystemData.Events

    -- Live-event tome updates (window does not register these).
    local liveRefresh = {
        events.TOME_LIVE_EVENT_LOADED,
        events.TOME_LIVE_EVENT_TASKS_UPDATED,
        events.TOME_LIVE_EVENT_OVERALL_COUNTER_UPDATED,
        events.TOME_LIVE_EVENT_TASK_COUNTER_UPDATED,
        -- Area / influence: single bus via refresh listeners (not also on the window).
        events.PLAYER_AREA_CHANGED,
        events.PLAYER_INFLUENCE_UPDATED,
    }
    for _, eventId in ipairs(liveRefresh) do
        if eventId ~= nil then
            local handlerName = "CustomUI.PortraitInfluenceTrack.OnRefreshEvents"
            local ok = tryCallLoud(
                "RegisterEvents.OnRefreshEvents." .. tostring(eventId),
                RegisterEventHandler,
                eventId,
                handlerName
            )
            if ok then
                rememberRegisteredEvent(eventId, handlerName)
            end
        end
    end

    if events.PLAYER_INFLUENCE_REWARDS_UPDATED ~= nil then
        local handlerName = "CustomUI.PortraitInfluenceTrack.OnPlayerInfluenceRewardsUpdated"
        local ok = tryCallLoud(
            "RegisterEvents.PLAYER_INFLUENCE_REWARDS_UPDATED",
            RegisterEventHandler,
            events.PLAYER_INFLUENCE_REWARDS_UPDATED,
            handlerName
        )
        if ok then
            rememberRegisteredEvent(events.PLAYER_INFLUENCE_REWARDS_UPDATED, handlerName)
        end
    end

    if events.INTERACT_SHOW_EVENT_REWARDS ~= nil then
        local handlerName = "CustomUI.PortraitInfluenceTrack.OnInteractShowEventRewards"
        local ok = tryCallLoud(
            "RegisterEvents.INTERACT_SHOW_EVENT_REWARDS",
            RegisterEventHandler,
            events.INTERACT_SHOW_EVENT_REWARDS,
            handlerName
        )
        if ok then
            rememberRegisteredEvent(events.INTERACT_SHOW_EVENT_REWARDS, handlerName)
        end
    end

    Track._eventsRegistered = true
end

function Track.Shutdown()
    unhookInteractionRewardSelection()
    Track.UnregisterEvents()
end

function Track.Initialize()
    ensureSettings()
    Track.RegisterEvents()
    hookInteractionRewardSelection()
end
