----------------------------------------------------------------
-- CustomUI.AutoFPS
-- Time-weighted FPS sampler that steps stock Video performance levels
-- (Very High / High Quality / Balanced / Fastest Framerate).
-- Custom 1 / Custom 2 leave the component dormant (no graphics writes).
-- The last manual stock choice is the ceiling: AutoFPS never selects a
-- higher-quality preset than that, and restores it on enable / load.
----------------------------------------------------------------
if not CustomUI then CustomUI = {} end
CustomUI.AutoFPS = CustomUI.AutoFPS or {}

local AutoFPS = CustomUI.AutoFPS

local c_DRIVER = "CustomUIAutoFPSDriver"

-- Engine combo indices (SystemData.Settings.Performance.PERF_LEVEL_*).
-- Quality rank is the same number: 1 Fastest ... 4 Very High.
local c_LEVEL_LOW = 1
local c_LEVEL_MEDIUM = 2
local c_LEVEL_HIGH = 3
local c_LEVEL_VERY_HIGH = 4
local c_LEVEL_CUSTOM1 = 5
local c_LEVEL_CUSTOM2 = 6

local c_FALLBACK_NAMES = {
    [c_LEVEL_LOW] = L"Fastest Framerate",
    [c_LEVEL_MEDIUM] = L"Balanced",
    [c_LEVEL_HIGH] = L"High Quality",
    [c_LEVEL_VERY_HIGH] = L"Very High",
    [c_LEVEL_CUSTOM1] = L"Custom 1",
    [c_LEVEL_CUSTOM2] = L"Custom 2",
}

local c_STRING_IDS = {
    [c_LEVEL_LOW] = "LABEL_PERFORMANCE_LOW",
    [c_LEVEL_MEDIUM] = "LABEL_PERFORMANCE_MEDIUM",
    [c_LEVEL_HIGH] = "LABEL_PERFORMANCE_HIGH",
    [c_LEVEL_VERY_HIGH] = "LABEL_PERFORMANCE_VERY_HIGH",
    [c_LEVEL_CUSTOM1] = "PERFORMANCE_CUSTOM1",
    [c_LEVEL_CUSTOM2] = "PERFORMANCE_CUSTOM2",
}

local c_DEFAULT_SETTINGS = {
    downshiftFps = 20,
    downshiftSeconds = 5,
    upshiftFps = 45,
    upshiftSeconds = 10,
    sampleWindowSeconds = 5,
    cooldownSeconds = 20,
    settleSeconds = 8,
    notifyChat = true,
    upshiftOutOfCombat = true,
    -- Persisted last *manual* Video level (1-6). Nil until first snapshot.
    manualPerfLevel = nil,
}

AutoFPS.DownshiftFpsOptions = { 10, 15, 20, 25, 30 }
AutoFPS.UpshiftFpsOptions = { 30, 35, 40, 45, 50, 60 }
AutoFPS.DownshiftSecondsOptions = { 3, 4, 5, 6, 8, 10 }
AutoFPS.UpshiftSecondsOptions = { 5, 8, 10, 15, 20 }
AutoFPS.SampleWindowOptions = { 3, 5, 8, 10 }
AutoFPS.CooldownOptions = { 10, 15, 20, 30, 45 }

local m_eventsRegistered = false
local m_now = 0
local m_inTransition = false
local m_settleUntil = 0
local m_lastZoneId = nil
local c_STALL_FRAME_SECONDS = 0.40
local m_ignoreSettingsUntil = 0
local m_cooldownUntil = 0
local m_lastKnownPerfLevel = nil
local m_appliedPerfLevel = nil
local m_sampleSum = 0
local m_sampleCount = 0
local m_samples = {}
local m_sampleHead = 1
local m_lowFor = 0
local m_highFor = 0
local m_avgFps = nil

local function IsStock(level)
    level = tonumber(level)
    return level == c_LEVEL_LOW
        or level == c_LEVEL_MEDIUM
        or level == c_LEVEL_HIGH
        or level == c_LEVEL_VERY_HIGH
end

local function IsCustom(level)
    level = tonumber(level)
    return level == c_LEVEL_CUSTOM1 or level == c_LEVEL_CUSTOM2
end

local function ClampNumber(value, options, fallback)
    local n = tonumber(value)
    if n == nil then
        return fallback
    end
    for i = 1, #options do
        if options[i] == n then
            return n
        end
    end
    local best = options[1]
    local bestDist = math.abs(n - best)
    for i = 2, #options do
        local dist = math.abs(n - options[i])
        if dist < bestDist then
            best = options[i]
            bestDist = dist
        end
    end
    return best
end

function AutoFPS.EnsureSettings()
    CustomUI.Settings = CustomUI.Settings or { Components = {} }
    if CustomUI.Settings.Components == nil then
        CustomUI.Settings.Components = {}
    end
    if type(CustomUI.Settings.AutoFPS) ~= "table" then
        CustomUI.Settings.AutoFPS = {}
    end
    local s = CustomUI.Settings.AutoFPS
    for k, v in pairs(c_DEFAULT_SETTINGS) do
        if s[k] == nil then
            s[k] = v
        end
    end
    s.downshiftFps = ClampNumber(s.downshiftFps, AutoFPS.DownshiftFpsOptions, c_DEFAULT_SETTINGS.downshiftFps)
    s.upshiftFps = ClampNumber(s.upshiftFps, AutoFPS.UpshiftFpsOptions, c_DEFAULT_SETTINGS.upshiftFps)
    s.downshiftSeconds = ClampNumber(s.downshiftSeconds, AutoFPS.DownshiftSecondsOptions, c_DEFAULT_SETTINGS.downshiftSeconds)
    s.upshiftSeconds = ClampNumber(s.upshiftSeconds, AutoFPS.UpshiftSecondsOptions, c_DEFAULT_SETTINGS.upshiftSeconds)
    s.sampleWindowSeconds = ClampNumber(s.sampleWindowSeconds, AutoFPS.SampleWindowOptions, c_DEFAULT_SETTINGS.sampleWindowSeconds)
    s.cooldownSeconds = ClampNumber(s.cooldownSeconds, AutoFPS.CooldownOptions, c_DEFAULT_SETTINGS.cooldownSeconds)
    s.settleSeconds = tonumber(s.settleSeconds) or c_DEFAULT_SETTINGS.settleSeconds
    if s._settleMigrated ~= true and s.settleSeconds == 3 then
        s.settleSeconds = c_DEFAULT_SETTINGS.settleSeconds
        s._settleMigrated = true
    end
    if s.settleSeconds < 0 then
        s.settleSeconds = 0
    end
    if s.upshiftFps <= s.downshiftFps then
        s.upshiftFps = ClampNumber(s.downshiftFps + 15, AutoFPS.UpshiftFpsOptions, 45)
    end
    local manual = tonumber(s.manualPerfLevel)
    if manual ~= nil and not IsStock(manual) and not IsCustom(manual) then
        s.manualPerfLevel = nil
    else
        s.manualPerfLevel = manual
    end
    s.notifyChat = s.notifyChat ~= false
    s.upshiftOutOfCombat = s.upshiftOutOfCombat ~= false
    return s
end

function AutoFPS.GetSettings()
    return AutoFPS.EnsureSettings()
end

local function GetPerfLevel()
    local perf = SystemData and SystemData.Settings and SystemData.Settings.Performance
    return tonumber(perf and perf.perfLevel)
end

local function ProfileName(level)
    level = tonumber(level)
    local fallback = c_FALLBACK_NAMES[level] or L"Unknown"
    local key = c_STRING_IDS[level]
    local tables = StringTables and StringTables.UserSettings
    local id = key and tables and tables[key]
    if id == nil or type(GetStringFromTable) ~= "function" then
        return fallback
    end
    local ok, text = CustomUI.TryCallQuiet("AutoFPS.ProfileName", GetStringFromTable, "UserSettingsStrings", id)
    if ok and text ~= nil and text ~= L"" then
        return text
    end
    return fallback
end

local function ResetSampler()
    m_sampleSum = 0
    m_sampleCount = 0
    m_samples = {}
    m_sampleHead = 1
    m_lowFor = 0
    m_highFor = 0
    m_avgFps = nil
end

local function PauseSampling()
    ResetSampler()
    local s = AutoFPS.EnsureSettings()
    local extra = tonumber(s.settleSeconds) or 8
    local untilTime = m_now + extra
    if untilTime > m_settleUntil then
        m_settleUntil = untilTime
    end
end

local function GetZoneId()
    return GameData and GameData.Player and tonumber(GameData.Player.zone)
end

local function IsLoadingScreenShowing()
    if type(DoesWindowExist) ~= "function" or type(WindowGetShowing) ~= "function" then
        return false
    end
    if not DoesWindowExist("EA_Window_LoadingScreen") then
        return false
    end
    return WindowGetShowing("EA_Window_LoadingScreen") == true
end

local function IsEngineTransitioning()
    if SystemData and SystemData.LoadingData and SystemData.LoadingData.isLoading == true then
        return true
    end
    if DataUtils and type(DataUtils.IsWorldLoading) == "function" and DataUtils.IsWorldLoading() == true then
        return true
    end
    if SystemData and SystemData.StreamingData and SystemData.StreamingData.isStreaming == true then
        return true
    end
    if IsLoadingScreenShowing() then
        return true
    end
    return false
end

local function Notify(message)
    local s = AutoFPS.EnsureSettings()
    if s.notifyChat ~= true then
        return
    end
    if type(CustomUI.PrintMessage) == "function" then
        CustomUI.PrintMessage(L"AutoFPS: " .. message)
    end
end

local function SetDriverShowing(show)
    if type(DoesWindowExist) ~= "function" or not DoesWindowExist(c_DRIVER) then
        return
    end
    if type(WindowSetShowing) == "function" then
        CustomUI.TryCallQuiet("AutoFPS.SetDriverShowing", WindowSetShowing, c_DRIVER, show == true)
    end
end

local function ApplyLevel(level, reason)
    level = tonumber(level)
    if not IsStock(level) then
        return false
    end
    local perf = SystemData and SystemData.Settings and SystemData.Settings.Performance
    if type(perf) ~= "table" then
        return false
    end
    local current = tonumber(perf.perfLevel)
    if current == level then
        m_lastKnownPerfLevel = level
        m_appliedPerfLevel = level
        return true
    end
    local s = AutoFPS.EnsureSettings()
    m_ignoreSettingsUntil = m_now + 1
    m_cooldownUntil = m_now + (tonumber(s.cooldownSeconds) or 20)
    perf.perfLevel = level
    if type(BroadcastEvent) == "function" and SystemData.Events and SystemData.Events.USER_SETTINGS_CHANGED then
        CustomUI.TryCall("AutoFPS.ApplyPerfLevel", BroadcastEvent, SystemData.Events.USER_SETTINGS_CHANGED)
    end
    m_lastKnownPerfLevel = level
    m_appliedPerfLevel = level
    ResetSampler()
    local fromName = ProfileName(current)
    local toName = ProfileName(level)
    if reason == "downshift" then
        Notify(fromName .. L" -> " .. toName .. L" (low FPS)")
    elseif reason == "upshift" then
        Notify(fromName .. L" -> " .. toName .. L" (FPS recovered)")
    elseif reason == "restore" then
        Notify(L"Restored " .. toName)
    end
    return true
end

local function IsDormant(s)
    s = s or AutoFPS.EnsureSettings()
    return IsCustom(s.manualPerfLevel)
end

local function AdoptOrRestorePreferred()
    local s = AutoFPS.EnsureSettings()
    local current = GetPerfLevel()
    if current == nil then
        return
    end
    if s.manualPerfLevel == nil then
        s.manualPerfLevel = current
    elseif current ~= s.manualPerfLevel then
        if IsCustom(current) then
            -- Live Video tab is Custom 1/2: that is now the manual choice.
            s.manualPerfLevel = current
        elseif IsCustom(s.manualPerfLevel) then
            -- Left Custom for a stock preset while AutoFPS was off.
            s.manualPerfLevel = current
        elseif IsStock(current) and IsStock(s.manualPerfLevel) then
            -- Stock mismatch is the last auto-downshift persisted in UserSettings.xml.
            ApplyLevel(s.manualPerfLevel, "restore")
        else
            s.manualPerfLevel = current
        end
    end
    m_lastKnownPerfLevel = GetPerfLevel()
    m_appliedPerfLevel = GetPerfLevel()
end

local function PushSample(dt)
    local s = AutoFPS.EnsureSettings()
    local window = tonumber(s.sampleWindowSeconds) or 5
    m_sampleCount = m_sampleCount + 1
    m_samples[m_sampleCount] = dt
    m_sampleSum = m_sampleSum + dt
    while m_sampleSum > window and m_sampleHead < m_sampleCount do
        local old = m_samples[m_sampleHead]
        if old ~= nil then
            m_sampleSum = m_sampleSum - old
            m_samples[m_sampleHead] = nil
        end
        m_sampleHead = m_sampleHead + 1
    end
    local n = m_sampleCount - m_sampleHead + 1
    if m_sampleSum > 0 and n > 0 then
        m_avgFps = n / m_sampleSum
    end
    -- Compact rarely so the array does not grow forever.
    if m_sampleHead > 200 then
        local compact = {}
        local count = 0
        for i = m_sampleHead, m_sampleCount do
            count = count + 1
            compact[count] = m_samples[i]
        end
        m_samples = compact
        m_sampleCount = count
        m_sampleHead = 1
    end
end

local function InCombat()
    return GameData and GameData.Player and GameData.Player.inCombat == true
end

local function StepToward(currentLevel, delta, ceiling)
    local rank = tonumber(currentLevel)
    if not IsStock(rank) then
        return nil
    end
    local nextLevel = rank + delta
    if nextLevel < c_LEVEL_LOW then
        return nil
    end
    if nextLevel > c_LEVEL_VERY_HIGH then
        return nil
    end
    local maxLevel = tonumber(ceiling) or c_LEVEL_VERY_HIGH
    if not IsStock(maxLevel) then
        maxLevel = c_LEVEL_VERY_HIGH
    end
    if nextLevel > maxLevel then
        return nil
    end
    return nextLevel
end

local function EvaluateShift(dt)
    local s = AutoFPS.EnsureSettings()
    if IsDormant(s) then
        m_lowFor = 0
        m_highFor = 0
        return
    end
    if m_now < m_cooldownUntil or m_now < m_settleUntil or m_inTransition then
        return
    end
    local avg = m_avgFps
    if avg == nil then
        return
    end
    local downFps = tonumber(s.downshiftFps) or 20
    local upFps = tonumber(s.upshiftFps) or 45
    if avg < downFps then
        m_lowFor = m_lowFor + dt
        m_highFor = 0
    elseif avg > upFps then
        m_highFor = m_highFor + dt
        m_lowFor = 0
    else
        m_lowFor = 0
        m_highFor = 0
    end

    local current = GetPerfLevel() or m_appliedPerfLevel
    local ceiling = s.manualPerfLevel
    if not IsStock(ceiling) then
        return
    end
    if IsStock(current) and current > ceiling then
        ApplyLevel(ceiling, "restore")
        return
    end

    if m_lowFor >= (tonumber(s.downshiftSeconds) or 5) then
        local nextLevel = StepToward(current, -1, ceiling)
        if nextLevel ~= nil and nextLevel ~= current then
            ApplyLevel(nextLevel, "downshift")
        else
            m_lowFor = 0
        end
        return
    end

    if m_highFor >= (tonumber(s.upshiftSeconds) or 10) then
        if s.upshiftOutOfCombat == true and InCombat() then
            return
        end
        local nextLevel = StepToward(current, 1, ceiling)
        if nextLevel ~= nil and nextLevel ~= current then
            ApplyLevel(nextLevel, "upshift")
        else
            m_highFor = 0
        end
    end
end

function AutoFPS.OnUpdate(timePassed)
    if type(CustomUI.IsComponentEnabled) == "function" and not CustomUI.IsComponentEnabled("AutoFPS") then
        return
    end
    local dt = tonumber(timePassed)
    if dt == nil or dt <= 0 then
        return
    end
    m_now = m_now + dt

    local transitioning = IsEngineTransitioning()
    if transitioning and not m_inTransition then
        m_inTransition = true
        PauseSampling()
        return
    end
    if not transitioning and m_inTransition then
        m_inTransition = false
        PauseSampling()
        return
    end
    if m_inTransition or m_now < m_settleUntil then
        return
    end

    local zone = GetZoneId()
    if zone ~= nil then
        if m_lastZoneId ~= nil and zone ~= m_lastZoneId then
            m_lastZoneId = zone
            PauseSampling()
            return
        end
        m_lastZoneId = zone
    end

    -- Single stall frames (load hitch, alt-tab) are not sustained low FPS.
    if dt >= c_STALL_FRAME_SECONDS then
        return
    end

    PushSample(dt)
    EvaluateShift(dt)
end

function AutoFPS.OnUserSettingsChanged()
    if type(CustomUI.IsComponentEnabled) == "function" and not CustomUI.IsComponentEnabled("AutoFPS") then
        return
    end
    if m_now < m_ignoreSettingsUntil then
        m_lastKnownPerfLevel = GetPerfLevel()
        return
    end
    local current = GetPerfLevel()
    if current == nil or current == m_lastKnownPerfLevel then
        return
    end
    -- Any perfLevel change we did not write is a manual Video-tab choice.
    local s = AutoFPS.EnsureSettings()
    s.manualPerfLevel = current
    m_lastKnownPerfLevel = current
    m_appliedPerfLevel = current
    ResetSampler()
    if IsCustom(current) then
        Notify(L"Custom profile selected; AutoFPS idle")
    else
        Notify(L"Preferred profile: " .. ProfileName(current))
    end
end

function AutoFPS.OnLoadingBegin()
    m_inTransition = true
    PauseSampling()
end

function AutoFPS.OnLoadingEnd()
    m_inTransition = IsEngineTransitioning()
    PauseSampling()
    local zone = GetZoneId()
    if zone ~= nil then
        m_lastZoneId = zone
    end
end

function AutoFPS.OnZoneChanged()
    local zone = GetZoneId()
    if zone ~= nil then
        m_lastZoneId = zone
    end
    PauseSampling()
end

function AutoFPS.GetAverageFps()
    return m_avgFps
end

function AutoFPS.GetStatusText()
    local s = AutoFPS.EnsureSettings()
    local current = GetPerfLevel()
    local parts = {}
    local function Add(text)
        parts[#parts + 1] = text
    end
    if type(CustomUI.IsComponentEnabled) == "function" and not CustomUI.IsComponentEnabled("AutoFPS") then
        return L"Disabled."
    end
    if IsDormant(s) then
        Add(L"Idle: " .. ProfileName(s.manualPerfLevel) .. L" (custom profiles are not auto-switched).")
    else
        Add(L"Preferred: " .. ProfileName(s.manualPerfLevel) .. L".")
        Add(L"Current: " .. ProfileName(current) .. L".")
        if IsStock(s.manualPerfLevel) and s.manualPerfLevel == c_LEVEL_LOW then
            Add(L"At Fastest Framerate; AutoFPS will not change it.")
        end
    end
    if m_avgFps ~= nil then
        Add(L"Avg FPS: " .. towstring(math.floor(m_avgFps + 0.5)) .. L".")
    else
        Add(L"Avg FPS: gathering.")
    end
    if m_inTransition or m_now < m_settleUntil then
        Add(L"Paused (zone / loading).")
    end
    local text = parts[1] or L""
    for i = 2, #parts do
        text = text .. L" " .. parts[i]
    end
    return text
end

function AutoFPS.PrintStatus()
    if type(CustomUI.PrintMessage) == "function" then
        CustomUI.PrintMessage(AutoFPS.GetStatusText())
    end
end

function AutoFPS.OnSettingsChanged()
    AutoFPS.EnsureSettings()
    ResetSampler()
end

local function EventSpecs()
    local events = SystemData and SystemData.Events
    if not events then
        return nil
    end
    return {
        { events.USER_SETTINGS_CHANGED, "CustomUI.AutoFPS.OnUserSettingsChanged" },
        { events.LOADING_BEGIN, "CustomUI.AutoFPS.OnLoadingBegin" },
        { events.LOADING_END, "CustomUI.AutoFPS.OnLoadingEnd" },
        { events.PLAYER_ZONE_CHANGED, "CustomUI.AutoFPS.OnZoneChanged" },
        { events.ENTER_WORLD, "CustomUI.AutoFPS.OnLoadingEnd" },
        { events.RELOAD_INTERFACE, "CustomUI.AutoFPS.OnLoadingEnd" },
    }
end

local function RegisterEvents()
    if m_eventsRegistered then
        return
    end
    local specs = EventSpecs()
    if not specs or type(RegisterEventHandler) ~= "function" then
        return
    end
    for i = 1, #specs do
        if specs[i][1] ~= nil then
            CustomUI.TryCall("AutoFPS.RegisterEvent", RegisterEventHandler, specs[i][1], specs[i][2])
        end
    end
    m_eventsRegistered = true
end

local function UnregisterEvents()
    if not m_eventsRegistered then
        return
    end
    local specs = EventSpecs()
    if specs and type(UnregisterEventHandler) == "function" then
        for i = 1, #specs do
            CustomUI.TryCallQuiet("AutoFPS.UnregisterEvent", UnregisterEventHandler, specs[i][1], specs[i][2])
        end
    end
    m_eventsRegistered = false
end

local AutoFPSComponent = { Name = "AutoFPS", DefaultEnabled = false }

function AutoFPSComponent:Initialize()
    AutoFPS.EnsureSettings()
    SetDriverShowing(false)
    return true
end

function AutoFPSComponent:Enable()
    AutoFPS.EnsureSettings()
    if type(DoesWindowExist) == "function" and type(CreateWindow) == "function" and not DoesWindowExist(c_DRIVER) then
        CustomUI.TryCallQuiet("AutoFPS.CreateDriver", CreateWindow, c_DRIVER, true)
    end
    SetDriverShowing(true)
    RegisterEvents()
    ResetSampler()
    m_lastZoneId = GetZoneId()
    m_inTransition = IsEngineTransitioning()
    if m_inTransition then
        PauseSampling()
    end
    AdoptOrRestorePreferred()
    return true
end

function AutoFPSComponent:Disable()
    UnregisterEvents()
    local s = AutoFPS.EnsureSettings()
    local current = GetPerfLevel()
    if IsStock(s.manualPerfLevel) and IsStock(current) and current ~= s.manualPerfLevel then
        ApplyLevel(s.manualPerfLevel, "restore")
    end
    SetDriverShowing(false)
    ResetSampler()
    return true
end

function AutoFPSComponent:Shutdown()
    UnregisterEvents()
    SetDriverShowing(false)
    ResetSampler()
end

CustomUI.RegisterComponent("AutoFPS", AutoFPSComponent)
