----------------------------------------------------------------
-- CustomUI.SmartAssist
-- Scenario smart assist: one managed hotbar macro "/assist <player>".
-- Picks the alive same-realm ally within range with best
-- KillDamage → Deathblows → Total Damage. Never assists self.
-- Only sets an assist when you have no hostile target; clears the macro while you do.
-- Enable creates the macro; disable deletes it and clears bar slots.
-- Optional auto-assist is best-effort (RoR often ignores /assist from addon Lua).
----------------------------------------------------------------

if not CustomUI then
    CustomUI = {}
end

CustomUI.SmartAssist = CustomUI.SmartAssist or {}

local SmartAssist = CustomUI.SmartAssist

SmartAssist.MACRO_NAME = "CustomUI SmartAssist"
SmartAssist.ICON_ACTIVE = 23166
SmartAssist.ICON_DISABLED = 91010
SmartAssist.DEFAULT_RANGE = 100
SmartAssist.RANGE_MIN = 1
SmartAssist.RANGE_MAX = 500

local c_DISTANCE_FIX = 1 / 1.06
local c_MAX_MAP_POINTS = 511
local c_MAP_WINDOW = "EA_Window_OverheadMapMapDisplay"
local c_MAP_POINT_TYPE_FILTER = {
    [SystemData.MapPips.GROUP_MEMBER] = true,
    [SystemData.MapPips.WARBAND_MEMBER] = true,
    [SystemData.MapPips.DESTRUCTION_ARMY] = true,
    [SystemData.MapPips.ORDER_ARMY] = true,
}

-- Stickiness: map/alive flicker was causing rapid re-picks of weaker allies.
local c_SWITCH_HOLD_SEC = 8
local c_HYSTERESIS_KD = 1.20 -- challenger needs 20% more KillDamage to steal
local c_STICKY_RANGE_MULT = 1.35 -- keep current pick a bit past range edge
local c_REFRESH_INTERVAL = 0.5

local DEFAULT_SETTINGS = {
    enabled = false,
    range = SmartAssist.DEFAULT_RANGE,
    autoAssist = false,
    notify = false,
}

local m_handlersRegistered = false
local m_statsHeld = false
local m_macroSlot = nil
local m_lastAssistName = nil -- wstring or nil
local m_lastAutoFiredName = nil
local m_fullSlotsWarned = false
local m_distCache = {} -- [nameKey] = { index, rawName, distance }
local m_scanCursor = 1
local m_updateElapsed = 0
local m_stickyKey = nil
local m_stickyHoldLeft = 0

local function ScenarioStats()
    return CustomUI.GroupIcons and CustomUI.GroupIcons.ScenarioStats
end

local function mergeDefaults(defaults, current)
    local merged = {}
    current = type(current) == "table" and current or {}
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            merged[key] = mergeDefaults(value, current[key])
        elseif current[key] == nil then
            merged[key] = value
        else
            merged[key] = current[key]
        end
    end
    return merged
end

function SmartAssist.EnsureSettings()
    CustomUI.Settings = CustomUI.Settings or { Components = {} }
    if type(CustomUI.Settings.SmartAssist) ~= "table" then
        CustomUI.Settings.SmartAssist = {}
    end
    CustomUI.Settings.SmartAssist = mergeDefaults(DEFAULT_SETTINGS, CustomUI.Settings.SmartAssist)
    local range = tonumber(CustomUI.Settings.SmartAssist.range) or SmartAssist.DEFAULT_RANGE
    if range < SmartAssist.RANGE_MIN then
        range = SmartAssist.RANGE_MIN
    elseif range > SmartAssist.RANGE_MAX then
        range = SmartAssist.RANGE_MAX
    end
    CustomUI.Settings.SmartAssist.range = math.floor(range + 0.5)
    CustomUI.Settings.SmartAssist.enabled = CustomUI.Settings.SmartAssist.enabled == true
    CustomUI.Settings.SmartAssist.autoAssist = CustomUI.Settings.SmartAssist.autoAssist == true
    CustomUI.Settings.SmartAssist.notify = CustomUI.Settings.SmartAssist.notify == true
    return CustomUI.Settings.SmartAssist
end

local function NormalizeNameKey(name)
    if name == nil then
        return nil
    end
    local s = name
    if type(s) == "wstring" then
        if type(WStringsRemoveGrammar) == "function" then
            s = WStringsRemoveGrammar(s)
        end
        if type(WStringToString) == "function" then
            s = WStringToString(s)
        else
            s = tostring(s)
        end
    elseif type(s) ~= "string" then
        s = tostring(s)
    end
    if s == nil or s == "" then
        return nil
    end
    local caret = string.find(s, "^", 1, true)
    if caret then
        s = string.sub(s, 1, caret - 1)
    end
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    if s == "" then
        return nil
    end
    return string.lower(s)
end

local function StripForAssist(name)
    if name == nil then
        return nil
    end
    local s = name
    if type(s) == "wstring" then
        if type(WStringsRemoveGrammar) == "function" then
            s = WStringsRemoveGrammar(s)
        end
    end
    if type(s) == "wstring" then
        local base = s:match(L"([^^]+)^?([^^]*)")
        if base ~= nil and base ~= L"" then
            return base
        end
        return s
    end
    local str = tostring(s)
    local caret = string.find(str, "^", 1, true)
    if caret then
        str = string.sub(str, 1, caret - 1)
    end
    str = str:gsub("^%s+", ""):gsub("%s+$", "")
    if str == "" then
        return nil
    end
    return towstring(str)
end

local function SelfNameKey()
    return NormalizeNameKey(GameData and GameData.Player and GameData.Player.name)
end

local function SelfRealm()
    return GameData and GameData.Player and tonumber(GameData.Player.realm) or nil
end

local function IsScenarioContext()
    if GameData and GameData.Player then
        if GameData.Player.isInScenario == true then
            return true
        end
        if GameData.Player.isInSiege == true then
            return true
        end
    end
    return false
end

local c_HOSTILE_UNIT_ID = (TargetInfo and TargetInfo.HOSTILE_TARGET) or "selfhostiletarget"

--- Hostile healthPercent from TargetInfo unit table.
--- Returns nil when the unit/field is missing (UnitHealth alone cannot tell nil from 0).
--- Fractional (0,1) is treated as dead (same snap GroupIcons uses).
local function HostileTargetHealthKnown()
    if type(TargetInfo) ~= "table" then
        return nil
    end
    local units = TargetInfo.m_Units
    if type(units) == "table" then
        local unit = units[c_HOSTILE_UNIT_ID]
        if type(unit) ~= "table" or unit.healthPercent == nil then
            return nil
        end
        local hp = tonumber(unit.healthPercent) or 0
        if hp > 0 and hp < 1 then
            hp = 0
        end
        return hp
    end
    if type(TargetInfo.UnitHealth) ~= "function" then
        return nil
    end
    -- Fallback: stock UnitHealth collapses missing HP to 0 — cannot prove dead.
    return nil
end

local function HostileTargetPresent()
    local TP = CustomUI and CustomUI.TargetPresence
    if type(TP) == "table" and type(TP.HasLiveTarget) == "function" then
        if TP.HasLiveTarget(c_HOSTILE_UNIT_ID) == true then
            return true
        end
    end
    if type(TargetInfo) ~= "table" then
        return false
    end
    if type(TargetInfo.UnitEntityId) == "function" then
        local entityId = tonumber(TargetInfo:UnitEntityId(c_HOSTILE_UNIT_ID)) or 0
        if entityId > 0 then
            return true
        end
    end
    if type(TargetInfo.UnitName) == "function" then
        local name = TargetInfo:UnitName(c_HOSTILE_UNIT_ID)
        if name ~= nil and name ~= L"" then
            return true
        end
    end
    return false
end

--- True when TargetInfo has a living hostile target. Dead corpses count as no target.
--- Presence with unknown HP blocks assist (avoid filling the macro mid-tab-in).
local function HasHostileTarget()
    if not HostileTargetPresent() then
        return false
    end
    local hp = HostileTargetHealthKnown()
    if hp == nil then
        return true
    end
    return hp > 0
end

--- Flat player list from GetScenarioPlayerGroups (same shape GroupIcons uses).
--- Returns map nameKey -> isAlive. Empty map means "no HP data yet".
local function BuildAliveByKey()
    local alive = {}
    if type(GameData) ~= "table" or type(GameData.GetScenarioPlayerGroups) ~= "function" then
        return alive
    end
    local ok, groups = CustomUI.TryCallQuiet("SmartAssist.GetScenarioPlayerGroups", GameData.GetScenarioPlayerGroups)
    if not ok or type(groups) ~= "table" then
        return alive
    end
    for _, player in ipairs(groups) do
        if type(player) == "table" and player.name ~= nil then
            local key = NormalizeNameKey(player.name)
            if key ~= nil then
                local hp = tonumber(player.health)
                if hp == nil then
                    hp = tonumber(player.healthPercent)
                end
                hp = hp or 0
                if hp > 0 and hp < 1 then
                    hp = 0
                end
                alive[key] = hp > 0
            end
        end
    end
    return alive
end

local function IsCandidateAlive(key, aliveByKey)
    if key == nil then
        return false
    end
    -- No roster HP yet: do not filter everyone out (scoreboard often arrives first).
    if next(aliveByKey) == nil then
        return true
    end
    local flag = aliveByKey[key]
    if flag == nil then
        -- On scoreboard but missing from groups: allow until proven dead.
        return true
    end
    return flag == true
end

--- Known distance must be within range; unknown distance is allowed (map pips are flaky).
local function IsWithinRange(dist, range)
    if dist == nil then
        return true
    end
    return dist <= range
end

local function LookupMapDistance(nameKey, rawName)
    if nameKey == nil or type(GetMapPointData) ~= "function" then
        return nil
    end
    if not DoesWindowExist(c_MAP_WINDOW) then
        return nil
    end

    local cache = m_distCache[nameKey]
    if cache ~= nil and cache.index ~= nil then
        local mpd = GetMapPointData(c_MAP_WINDOW, cache.index)
        if mpd
            and mpd.name
            and mpd.pointType
            and c_MAP_POINT_TYPE_FILTER[mpd.pointType]
            and NormalizeNameKey(mpd.name) == nameKey
        then
            local dist = math.floor((tonumber(mpd.distance) or 0) * c_DISTANCE_FIX)
            cache.distance = dist
            cache.rawName = mpd.name
            return dist
        end
        m_distCache[nameKey] = nil
    end

    -- Budgeted walk from cursor.
    local scanned = 0
    local budget = 64
    while scanned < budget do
        local mpd = GetMapPointData(c_MAP_WINDOW, m_scanCursor)
        if mpd and mpd.name and mpd.pointType and c_MAP_POINT_TYPE_FILTER[mpd.pointType] then
            local key = NormalizeNameKey(mpd.name)
            if key ~= nil then
                local dist = math.floor((tonumber(mpd.distance) or 0) * c_DISTANCE_FIX)
                m_distCache[key] = { index = m_scanCursor, rawName = mpd.name, distance = dist }
                if key == nameKey then
                    m_scanCursor = m_scanCursor + 1
                    if m_scanCursor > c_MAX_MAP_POINTS then
                        m_scanCursor = 1
                    end
                    return dist
                end
            end
        end
        m_scanCursor = m_scanCursor + 1
        if m_scanCursor > c_MAX_MAP_POINTS then
            m_scanCursor = 1
            break
        end
        scanned = scanned + 1
    end
    return nil
end

local function GetMacrosTable()
    if type(DataUtils) == "table" and type(DataUtils.GetMacros) == "function" then
        return DataUtils.GetMacros() or {}
    end
    if type(GetMacrosData) == "function" then
        return GetMacrosData() or {}
    end
    return {}
end

--- Stock chat career glyph from a GetScenarioPlayers() row (same as ScenarioSummaryWindow).
local function CareerIconMarkup(row)
    if type(row) ~= "table" or type(Icons) ~= "table" then
        return L""
    end
    local iconNum = nil
    local careerId = tonumber(row.careerId)
    if careerId ~= nil and careerId ~= 0 and type(Icons.GetCareerIconIDFromCareerNamesID) == "function" then
        iconNum = Icons.GetCareerIconIDFromCareerNamesID(careerId)
    end
    if (iconNum == nil or iconNum == 0)
        and tonumber(row.careerLine) ~= nil
        and tonumber(row.careerLine) ~= 0
        and type(Icons.GetCareerIconIDFromCareerLine) == "function"
    then
        iconNum = Icons.GetCareerIconIDFromCareerLine(tonumber(row.careerLine))
    end
    if iconNum == nil or iconNum == 0 then
        return L""
    end
    return L"<icon" .. towstring(iconNum) .. L"> "
end

local function FormatAssistNotifyDetail(picked)
    if type(picked) ~= "table" then
        return L""
    end
    local reason = picked.reason or "KillDamage"
    local kd = tonumber(picked.killDamage) or 0
    local db = tonumber(picked.deathBlows) or 0
    local td = tonumber(picked.totalDamage) or 0
    return towstring(reason)
        .. L" lead - KD "
        .. towstring(tostring(kd))
        .. L", DB "
        .. towstring(tostring(db))
        .. L", Dmg "
        .. towstring(tostring(td))
end

local function FormatAssistNotifyLine(assistName, picked)
    local icon = CareerIconMarkup(picked and picked.row)
    local detail = FormatAssistNotifyDetail(picked)
    if detail ~= nil and detail ~= L"" then
        return L"SmartAssist: assisting " .. icon .. assistName .. L" (" .. detail .. L")"
    end
    return L"SmartAssist: assisting " .. icon .. assistName
end

local function ClearSticky()
    m_stickyKey = nil
    m_stickyHoldLeft = 0
end

local function DetailFromRow(SS, key, row, reason)
    return {
        key = key,
        name = row and row.name or nil,
        row = row,
        killDamage = SS.RowKillDamage(row),
        deathBlows = SS.RowDeathBlows(row),
        totalDamage = SS.RowTotalDamage(row),
        reason = reason or "KillDamage",
    }
end

local function FindRealmRowByKey(key, realm)
    if key == nil or realm == nil then
        return nil
    end
    if type(GameData) ~= "table" or type(GameData.GetScenarioPlayers) ~= "function" then
        return nil
    end
    local ok, list = CustomUI.TryCallQuiet("SmartAssist.GetScenarioPlayers", GameData.GetScenarioPlayers)
    if not ok or type(list) ~= "table" then
        return nil
    end
    for _, row in ipairs(list) do
        if type(row) == "table" and tonumber(row.realm) == realm and row.name ~= nil then
            if NormalizeNameKey(row.name) == key then
                return row
            end
        end
    end
    return nil
end

local function StickyStillEligible(SS, key, row, aliveByKey, range)
    if key == nil or type(row) ~= "table" or SS == nil then
        return false
    end
    if type(SS.RowHasAssistCombatData) == "function" and not SS.RowHasAssistCombatData(row) then
        return false
    end
    -- Only drop when groups explicitly mark them dead (unknown = keep).
    if aliveByKey[key] == false then
        return false
    end
    local dist = LookupMapDistance(key, row.name)
    local stickyRange = (tonumber(range) or SmartAssist.DEFAULT_RANGE) * c_STICKY_RANGE_MULT
    if dist ~= nil and dist > stickyRange then
        return false
    end
    return true
end

local function ChallengerStealsSticky(SS, challengerRow, stickyRow)
    if type(challengerRow) ~= "table" or type(stickyRow) ~= "table" or SS == nil then
        return false
    end
    local akd = SS.RowKillDamage(challengerRow)
    local bkd = SS.RowKillDamage(stickyRow)
    if bkd <= 0 then
        return akd > 0
    end
    return akd > (bkd * c_HYSTERESIS_KD)
end

local function CommitSticky(key, hold)
    m_stickyKey = key
    if hold then
        m_stickyHoldLeft = c_SWITCH_HOLD_SEC
    end
end

--- Returns assist display name (wstring) or nil; second return is pick detail table.
--- Ranking comes from GroupIcons ScenarioStats (KillDamage → Deathblows → Total Damage).
--- No pick until someone has real KD/DB/damage. Sticky + hysteresis dampens flicker.
--- opts.dryRun = true: rank only; do not mutate sticky/hold state (for DebugStatus).
function SmartAssist.PickAssistTarget(opts)
    opts = opts or {}
    local dryRun = opts.dryRun == true
    local settings = SmartAssist.EnsureSettings()
    local range = tonumber(settings.range) or SmartAssist.DEFAULT_RANGE
    local selfKey = SelfNameKey()
    local realm = SelfRealm()
    local SS = ScenarioStats()
    if realm == nil or SS == nil or type(SS.PickBestAssistCandidate) ~= "function" then
        return nil
    end

    local aliveByKey = BuildAliveByKey()
    local best = SS.PickBestAssistCandidate({
        realm = realm,
        normalizeNameKey = NormalizeNameKey,
        excludeKey = selfKey,
        requireCombatData = true,
        accept = function(key, row)
            if not IsCandidateAlive(key, aliveByKey) then
                return false
            end
            local dist = LookupMapDistance(key, row.name)
            return IsWithinRange(dist, range)
        end,
    })

    local stickyKey = m_stickyKey
    if stickyKey == selfKey then
        stickyKey = nil
        if not dryRun then
            ClearSticky()
        end
    end

    local stickyRow = nil
    if stickyKey ~= nil then
        stickyRow = FindRealmRowByKey(stickyKey, realm)
    end
    local stickyOk = stickyRow ~= nil and StickyStillEligible(SS, stickyKey, stickyRow, aliveByKey, range)

    if stickyOk then
        local bestIsOther = best ~= nil and best.key ~= nil and best.key ~= stickyKey
        local maySwitch = m_stickyHoldLeft <= 0
            and bestIsOther
            and ChallengerStealsSticky(SS, best.row, stickyRow)
        if maySwitch then
            if not dryRun then
                CommitSticky(best.key, true)
            end
            return StripForAssist(best.row.name), best
        end
        local held = DetailFromRow(SS, stickyKey, stickyRow, "held")
        return StripForAssist(stickyRow.name), held
    end

    -- Sticky gone/dead/out of slack range: take best, or clear.
    if best ~= nil and best.row ~= nil then
        if not dryRun then
            CommitSticky(best.key, true)
        end
        return StripForAssist(best.row.name), best
    end

    if not dryRun then
        ClearSticky()
    end
    return nil
end

local function FindMacroSlotByName(macroName)
    local macros = GetMacrosTable()
    local expected = towstring(macroName)
    for i = 1, #macros do
        if macros[i] and macros[i].name == expected then
            return i
        end
    end
    return nil
end

local function FindEmptyMacroSlot()
    local macros = GetMacrosTable()
    for i = 1, #macros do
        local row = macros[i]
        if row
            and (row.iconNum == 0 or row.iconNum == nil)
            and (row.text == nil or row.text == L"")
            and (row.name == nil or row.name == L"")
        then
            return i
        end
    end
    return nil
end

--- Diagnostic snapshot for /script or RoRMCP (read-only; does not mutate sticky).
function SmartAssist.DebugStatus()
    local settings = SmartAssist.EnsureSettings()
    local macros = GetMacrosTable()
    local slot = FindMacroSlotByName(SmartAssist.MACRO_NAME)
    local row = slot and macros[slot]
    local aliveByKey = BuildAliveByKey()
    local aliveCount = 0
    for _ in pairs(aliveByKey) do
        aliveCount = aliveCount + 1
    end
    local nPlayers = 0
    local ok, list = pcall(function()
        return GameData.GetScenarioPlayers()
    end)
    if ok and type(list) == "table" then
        nPlayers = #list
    end
    local pick, picked = SmartAssist.PickAssistTarget({ dryRun = true })
    local SS = ScenarioStats()
    return {
        enabled = settings.enabled == true,
        range = settings.range,
        autoAssist = settings.autoAssist == true,
        notify = settings.notify == true,
        inScenario = IsScenarioContext(),
        realm = SelfRealm(),
        macroSlot = slot,
        macroIcon = row and row.iconNum or nil,
        hasAssistText = row ~= nil and row.text ~= nil and row.text ~= L"",
        nPlayers = nPlayers,
        aliveKeys = aliveCount,
        pick = pick,
        pickReason = picked and picked.reason or nil,
        pickKd = picked and picked.killDamage or nil,
        pickDb = picked and picked.deathBlows or nil,
        pickDmg = picked and picked.totalDamage or nil,
        stickyKey = m_stickyKey,
        stickyHoldLeft = m_stickyHoldLeft,
        hasHostileTarget = HasHostileTarget(),
        streaming = SS and SS.IsStreaming and SS.IsStreaming() or false,
        statsHeld = m_statsHeld == true,
    }
end

local function ForEachMacroActionButton(macroSlot, fn)
    if not macroSlot or type(fn) ~= "function" then
        return
    end
    if type(ActionBars) ~= "table" or type(ActionBars.m_Bars) ~= "table" then
        return
    end
    local doMacro = GameData and GameData.PlayerActions and GameData.PlayerActions.DO_MACRO
    for i = 1, #ActionBars.m_Bars do
        local bar = ActionBars.m_Bars[i]
        for j = 1, #(bar.m_Buttons or {}) do
            local button = bar.m_Buttons[j]
            if button
                and button.m_ActionType == doMacro
                and button.m_ActionId == macroSlot
            then
                fn(button)
            end
        end
    end
end

local function ClearMacroFromActionBars(macroSlot)
    ForEachMacroActionButton(macroSlot, function(button)
        if type(button.SetActionData) == "function" then
            button:SetActionData(0, 0)
        end
    end)
end

local function WriteMacro(assistName)
    if type(SetMacroData) ~= "function" then
        return false
    end
    local slot = m_macroSlot or FindMacroSlotByName(SmartAssist.MACRO_NAME)
    if slot == nil then
        slot = FindEmptyMacroSlot()
    end
    if slot == nil then
        if not m_fullSlotsWarned and type(CustomUI.PrintMessage) == "function" then
            CustomUI.PrintMessage(L"SmartAssist: all macro slots are full.")
            m_fullSlotsWarned = true
        end
        return false
    end
    m_macroSlot = slot
    m_fullSlotsWarned = false

    local name = towstring(SmartAssist.MACRO_NAME)
    local text = L""
    local icon = SmartAssist.ICON_DISABLED
    if assistName ~= nil and assistName ~= L"" then
        text = L"/assist " .. assistName
        icon = SmartAssist.ICON_ACTIVE
    end

    if type(GetMacrosData) == "function" then
        local macros = GetMacrosData() or {}
        local row = macros[slot]
        if row and row.name == name and row.text == text and tonumber(row.iconNum) == icon then
            return true
        end
    end

    SetMacroData(name, text, icon, slot)
    return true
end

local function DeleteMacroAndClearBars()
    local slot = m_macroSlot or FindMacroSlotByName(SmartAssist.MACRO_NAME)
    if slot ~= nil then
        ClearMacroFromActionBars(slot)
        if type(SetMacroData) == "function" then
            SetMacroData(L"", L"", 0, slot)
        end
    end
    m_macroSlot = nil
    m_lastAssistName = nil
    m_lastAutoFiredName = nil
end

local function HoldStatsStream(want)
    want = want == true
    if want == m_statsHeld then
        if want then
            local SS = ScenarioStats()
            if SS and type(SS.Start) == "function" then
                SS.Start()
            end
        end
        return
    end
    local SS = ScenarioStats()
    if want then
        if SS and type(SS.Acquire) == "function" then
            SS.Acquire()
        elseif SS and type(SS.Start) == "function" then
            SS.Start()
        end
        m_statsHeld = true
    else
        if SS and type(SS.Release) == "function" then
            SS.Release()
        elseif SS and type(SS.Stop) == "function" then
            SS.Stop()
        end
        m_statsHeld = false
    end
end

local function TryAutoFire(assistName)
    local settings = SmartAssist.EnsureSettings()
    if settings.autoAssist ~= true then
        return
    end
    if assistName == nil or assistName == L"" then
        return
    end
    if m_lastAutoFiredName ~= nil and m_lastAutoFiredName == assistName then
        return
    end
    m_lastAutoFiredName = assistName

    local fired = false
    local slot = m_macroSlot
    if slot ~= nil then
        ForEachMacroActionButton(slot, function(button)
            if button.m_Name and type(WindowGameAction) == "function" then
                local actionWin = button.m_Name .. "Action"
                if DoesWindowExist(actionWin) then
                    CustomUI.TryCallQuiet("SmartAssist.WindowGameAction", WindowGameAction, actionWin)
                    fired = true
                end
            end
        end)
    end
    if not fired and type(SendChatText) == "function" then
        -- Best-effort; RoR often ignores /assist from addon Lua.
        CustomUI.TryCallQuiet("SmartAssist.SendChatText", SendChatText, L"/assist " .. assistName, L"")
    end
end

local function RefreshAssist()
    local settings = SmartAssist.EnsureSettings()
    if settings.enabled ~= true then
        return
    end

    if not IsScenarioContext() then
        HoldStatsStream(false)
        ClearSticky()
        m_lastAssistName = nil
        m_lastAutoFiredName = nil
        WriteMacro(nil)
        return
    end

    HoldStatsStream(true)

    -- Never set (and always clear) assist while you have a living hostile target.
    -- Always WriteMacro(nil) so a stale post-/reload macro cannot linger.
    if HasHostileTarget() then
        ClearSticky()
        m_lastAssistName = nil
        m_lastAutoFiredName = nil
        WriteMacro(nil)
        return
    end

    local assistName, picked = SmartAssist.PickAssistTarget()
    local changed = (assistName == nil and m_lastAssistName ~= nil)
        or (assistName ~= nil and (m_lastAssistName == nil or m_lastAssistName ~= assistName))

    WriteMacro(assistName)
    m_lastAssistName = assistName

    if changed and assistName ~= nil then
        if settings.notify == true and type(CustomUI.PrintMessage) == "function" then
            CustomUI.PrintMessage(FormatAssistNotifyLine(assistName, picked))
        end
        TryAutoFire(assistName)
    elseif assistName == nil then
        m_lastAutoFiredName = nil
    end
end

local function UnregisterHandlers()
    if not m_handlersRegistered then
        return
    end
    local E = SystemData and SystemData.Events
    if E then
        if E.SCENARIO_PLAYERS_LIST_STATS_UPDATED then
            UnregisterEventHandler(E.SCENARIO_PLAYERS_LIST_STATS_UPDATED, "CustomUI.SmartAssist.OnScenarioStatsUpdated")
        end
        if E.SCENARIO_BEGIN then
            UnregisterEventHandler(E.SCENARIO_BEGIN, "CustomUI.SmartAssist.OnScenarioBegin")
        end
        if E.SCENARIO_END then
            UnregisterEventHandler(E.SCENARIO_END, "CustomUI.SmartAssist.OnScenarioEnd")
        end
        if E.LOADING_END then
            UnregisterEventHandler(E.LOADING_END, "CustomUI.SmartAssist.OnLoadingEnd")
        end
        if E.MACROS_LOADED then
            UnregisterEventHandler(E.MACROS_LOADED, "CustomUI.SmartAssist.OnMacrosLoaded")
        end
        if E.PLAYER_TARGET_UPDATED then
            UnregisterEventHandler(E.PLAYER_TARGET_UPDATED, "CustomUI.SmartAssist.OnPlayerTargetUpdated")
        end
    end
    m_handlersRegistered = false
end

local function RegisterHandlers()
    if m_handlersRegistered then
        return
    end
    local E = SystemData and SystemData.Events
    if not E then
        return
    end
    if E.SCENARIO_PLAYERS_LIST_STATS_UPDATED then
        RegisterEventHandler(E.SCENARIO_PLAYERS_LIST_STATS_UPDATED, "CustomUI.SmartAssist.OnScenarioStatsUpdated")
    end
    if E.SCENARIO_BEGIN then
        RegisterEventHandler(E.SCENARIO_BEGIN, "CustomUI.SmartAssist.OnScenarioBegin")
    end
    if E.SCENARIO_END then
        RegisterEventHandler(E.SCENARIO_END, "CustomUI.SmartAssist.OnScenarioEnd")
    end
    if E.LOADING_END then
        RegisterEventHandler(E.LOADING_END, "CustomUI.SmartAssist.OnLoadingEnd")
    end
    if E.MACROS_LOADED then
        RegisterEventHandler(E.MACROS_LOADED, "CustomUI.SmartAssist.OnMacrosLoaded")
    end
    if E.PLAYER_TARGET_UPDATED then
        RegisterEventHandler(E.PLAYER_TARGET_UPDATED, "CustomUI.SmartAssist.OnPlayerTargetUpdated")
    end
    m_handlersRegistered = true
end

function SmartAssist.OnScenarioStatsUpdated()
    if SmartAssist.EnsureSettings().enabled == true then
        RefreshAssist()
    end
end

function SmartAssist.OnScenarioBegin()
    ClearSticky()
    m_lastAssistName = nil
    m_lastAutoFiredName = nil
    if SmartAssist.EnsureSettings().enabled == true then
        RefreshAssist()
    end
end

function SmartAssist.OnScenarioEnd()
    ClearSticky()
    if SmartAssist.EnsureSettings().enabled == true then
        HoldStatsStream(false)
        m_lastAssistName = nil
        m_lastAutoFiredName = nil
        WriteMacro(nil)
    end
end

function SmartAssist.OnLoadingEnd()
    if SmartAssist.EnsureSettings().enabled == true then
        RefreshAssist()
    end
end

function SmartAssist.OnMacrosLoaded()
    local settings = SmartAssist.EnsureSettings()
    if settings.enabled == true then
        m_macroSlot = FindMacroSlotByName(SmartAssist.MACRO_NAME)
        RefreshAssist()
    end
end

function SmartAssist.OnPlayerTargetUpdated()
    if SmartAssist.EnsureSettings().enabled == true then
        RefreshAssist()
    end
end

--- Periodic distance refresh while enabled in scenario.
function SmartAssist.OnUpdate(timePassed)
    local dt = tonumber(timePassed) or 0
    if m_stickyHoldLeft > 0 then
        m_stickyHoldLeft = math.max(0, m_stickyHoldLeft - dt)
    end
    local settings = SmartAssist.EnsureSettings()
    if settings.enabled ~= true or not IsScenarioContext() then
        return
    end
    m_updateElapsed = m_updateElapsed + dt
    if m_updateElapsed < c_REFRESH_INTERVAL then
        return
    end
    m_updateElapsed = 0
    RefreshAssist()
end

function SmartAssist.Enable()
    local settings = SmartAssist.EnsureSettings()
    settings.enabled = true
    ClearSticky()
    RegisterHandlers()
    m_macroSlot = FindMacroSlotByName(SmartAssist.MACRO_NAME)
    WriteMacro(nil)
    RefreshAssist()
end

function SmartAssist.Disable()
    UnregisterHandlers()
    HoldStatsStream(false)
    ClearSticky()
    DeleteMacroAndClearBars()
    local settings = SmartAssist.EnsureSettings()
    settings.enabled = false
end

function SmartAssist.Sync()
    local settings = SmartAssist.EnsureSettings()
    if settings.enabled == true then
        RegisterHandlers()
        m_macroSlot = FindMacroSlotByName(SmartAssist.MACRO_NAME) or m_macroSlot
        if m_macroSlot == nil or FindMacroSlotByName(SmartAssist.MACRO_NAME) == nil then
            WriteMacro(nil)
        end
        RefreshAssist()
    else
        UnregisterHandlers()
        HoldStatsStream(false)
        ClearSticky()
        m_lastAssistName = nil
        m_lastAutoFiredName = nil
        if FindMacroSlotByName(SmartAssist.MACRO_NAME) ~= nil or m_macroSlot ~= nil then
            DeleteMacroAndClearBars()
        end
    end
end

function SmartAssist.OnSettingsChanged()
    SmartAssist.Sync()
end

function SmartAssist.Initialize()
    SmartAssist.EnsureSettings()
    SmartAssist.Sync()
end

function SmartAssist.Shutdown()
    UnregisterHandlers()
    HoldStatsStream(false)
    -- Leave macro in place on reload shutdown; only Disable deletes.
end
