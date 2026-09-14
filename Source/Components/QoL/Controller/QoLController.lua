----------------------------------------------------------------
-- CustomUI.QoL — coordinator for RedAlert, AutoSurrender, RezzAccept
----------------------------------------------------------------
if not CustomUI then CustomUI = {} end
CustomUI.QoL = CustomUI.QoL or {}

local QoL = CustomUI.QoL
local c_DRIVER = "CustomUIQoLDriver"

local DEFAULT_SETTINGS = {
	-- Opt-in mute: stock BUTTON_CLICK is 300; checked sets 0.
	muteButtonClickSound = false,
	redAlert = {
		enabled = true,
		thresholdPercent = 50,
		centerMessage = true,
	},
	autoSurrender = {
		-- Opt-in: voting/surrender automation must not arm on a fresh profile.
		enabled = false,
		statusMessages = true,
		useKillRule = true,
		scoreDiff = 100,
		preStartRetry = 30,
	},
	rezzAccept = {
		-- Opt-in: auto-accept rez dialogs are unsafe as a default.
		enabled = false,
	},
	altTracker = {
		enabled = true,
		includeBank = true,
		showCrossFaction = true,
		trackGold = true,
		pruneStaleDays = 30,
	},
}

QoL.SCORE_DIFF_OPTIONS = { 50, 100, 150, 200, 250 }
QoL.PRESTART_RETRY_OPTIONS = { 15, 30, 45, 60 }

local FEATURE_LABELS = {
	redAlert = L"RedAlert",
	autoSurrender = L"AutoSurrender",
	rezzAccept = L"RezzAccept",
	altTracker = L"AltTracker",
}

local m_lastFeatureState = {
	redAlert = nil,
	autoSurrender = nil,
	rezzAccept = nil,
	altTracker = nil,
}

function QoL.PrintSubFeatureMessage(featureName, message)
	if type(CustomUI.PrintMessage) ~= "function" then
		return
	end
	if type(featureName) == "string" then
		featureName = towstring(featureName)
	end
	if type(message) == "string" then
		message = towstring(message)
	end
	if type(featureName) ~= "wstring" or type(message) ~= "wstring" then
		return
	end
	CustomUI.PrintMessage(featureName .. L": " .. message)
end

local function seedFeatureState(settings)
	settings = settings or QoL.EnsureSettings()
	m_lastFeatureState.redAlert = settings.redAlert.enabled == true
	m_lastFeatureState.autoSurrender = settings.autoSurrender.enabled == true
	m_lastFeatureState.rezzAccept = settings.rezzAccept.enabled == true
	m_lastFeatureState.altTracker = settings.altTracker.enabled == true
end

local function announceFeatureStateIfChanged(key, enabled)
	local label = FEATURE_LABELS[key]
	if label == nil then
		return
	end
	enabled = enabled == true
	if m_lastFeatureState[key] == enabled then
		return
	end
	m_lastFeatureState[key] = enabled
	if type(CustomUI.PrintMessage) == "function" then
		CustomUI.PrintMessage(label .. (enabled and L": enabled" or L": disabled"))
	end
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

function QoL.EnsureSettings()
	CustomUI.Settings = CustomUI.Settings or { Components = {} }
	if type(CustomUI.Settings.QoL) ~= "table" then
		CustomUI.Settings.QoL = {}
	end
	CustomUI.Settings.QoL = mergeDefaults(DEFAULT_SETTINGS, CustomUI.Settings.QoL)
	CustomUI.Settings.QoL._migratedFromStandalone = nil
	if CustomUI.QoL.RedAlert and type(CustomUI.QoL.RedAlert.NormalizeSettings) == "function" then
		CustomUI.QoL.RedAlert.NormalizeSettings(CustomUI.Settings.QoL.redAlert)
	end
	return CustomUI.Settings.QoL
end

local function SetDriverShowing(show)
	if type(DoesWindowExist) ~= "function" or not DoesWindowExist(c_DRIVER) then
		return
	end
	if type(WindowSetShowing) == "function" then
		WindowSetShowing(c_DRIVER, show == true)
	end
end

local function NeedsDriver()
	local s = QoL.EnsureSettings()
	return s.redAlert.enabled == true
		or s.autoSurrender.enabled == true
		or s.altTracker.enabled == true
end

function QoL.SyncSubFeatures(announceChanges)
	local s = QoL.EnsureSettings()
	local RA = CustomUI.QoL.RedAlert
	local AS = CustomUI.QoL.AutoSurrender
	local RZ = CustomUI.QoL.RezzAccept
	local ALT = CustomUI.QoL.AltTracker
	local BCS = CustomUI.QoL.ButtonClickSound

	if s.redAlert.enabled then
		RA.Enable()
	else
		RA.Disable()
	end
	if announceChanges == true then
		announceFeatureStateIfChanged("redAlert", s.redAlert.enabled == true)
	end

	if s.autoSurrender.enabled then
		AS.Enable()
	else
		AS.Disable()
	end
	if announceChanges == true then
		announceFeatureStateIfChanged("autoSurrender", s.autoSurrender.enabled == true)
	end

	if s.rezzAccept.enabled then
		RZ.Enable()
	else
		RZ.Disable()
	end
	if announceChanges == true then
		announceFeatureStateIfChanged("rezzAccept", s.rezzAccept.enabled == true)
	end

	if ALT then
		if s.altTracker.enabled then
			ALT.Enable()
		else
			ALT.Disable()
		end
		if announceChanges == true then
			announceFeatureStateIfChanged("altTracker", s.altTracker.enabled == true)
		end
	end

	-- Always enabled while QoL is on; checkbox only chooses mute vs stock.
	if BCS then
		BCS.Enable()
	end

	if announceChanges ~= true then
		seedFeatureState(s)
	end

	SetDriverShowing(NeedsDriver())
end

function QoL.OnUpdate(timePassed)
	if CustomUI.QoL.RedAlert then
		CustomUI.QoL.RedAlert.OnUpdate(timePassed)
	end
	if CustomUI.QoL.AutoSurrender then
		CustomUI.QoL.AutoSurrender.OnUpdate(timePassed)
	end
	if CustomUI.QoL.AltTracker then
		CustomUI.QoL.AltTracker.OnUpdate(timePassed)
	end
end

function QoL.OnSettingsChanged()
	QoL.SyncSubFeatures(true)
end

function QoL.InitializeSubModules()
	QoL.EnsureSettings()
	if CustomUI.QoL.RedAlert then CustomUI.QoL.RedAlert.Initialize() end
	if CustomUI.QoL.AutoSurrender then CustomUI.QoL.AutoSurrender.Initialize() end
	if CustomUI.QoL.RezzAccept then CustomUI.QoL.RezzAccept.Initialize() end
	if CustomUI.QoL.AltTracker then CustomUI.QoL.AltTracker.Initialize() end
	if CustomUI.QoL.ButtonClickSound then CustomUI.QoL.ButtonClickSound.Initialize() end
	seedFeatureState()
end

function QoL.EnableSubModules()
	QoL.SyncSubFeatures(false)
end

function QoL.DisableSubModules()
	if CustomUI.QoL.RedAlert then CustomUI.QoL.RedAlert.Disable() end
	if CustomUI.QoL.AutoSurrender then CustomUI.QoL.AutoSurrender.Disable() end
	if CustomUI.QoL.RezzAccept then CustomUI.QoL.RezzAccept.Disable() end
	if CustomUI.QoL.AltTracker then CustomUI.QoL.AltTracker.Disable() end
	if CustomUI.QoL.ButtonClickSound then CustomUI.QoL.ButtonClickSound.Disable() end
	m_lastFeatureState.redAlert = false
	m_lastFeatureState.autoSurrender = false
	m_lastFeatureState.rezzAccept = false
	m_lastFeatureState.altTracker = false
	SetDriverShowing(false)
end

function QoL.ShutdownSubModules()
	if CustomUI.QoL.RedAlert then CustomUI.QoL.RedAlert.Shutdown() end
	if CustomUI.QoL.AutoSurrender then CustomUI.QoL.AutoSurrender.Shutdown() end
	if CustomUI.QoL.RezzAccept then CustomUI.QoL.RezzAccept.Shutdown() end
	if CustomUI.QoL.AltTracker then CustomUI.QoL.AltTracker.Shutdown() end
	if CustomUI.QoL.ButtonClickSound then CustomUI.QoL.ButtonClickSound.Shutdown() end
	SetDriverShowing(false)
end

local QoLComponent = { Name = "QoL", DefaultEnabled = false }

function QoLComponent:Initialize()
	QoL.InitializeSubModules()
	SetDriverShowing(false)
	return true
end

function QoLComponent:Enable()
	if type(DoesWindowExist) == "function" and type(CreateWindow) == "function" and not DoesWindowExist(c_DRIVER) then
		CustomUI.TryCallQuiet("QoL.CreateDriver", CreateWindow, c_DRIVER, true)
	end
	QoL.EnableSubModules()
	return true
end

function QoLComponent:Disable()
	QoL.DisableSubModules()
	return true
end

function QoLComponent:Shutdown()
	QoL.ShutdownSubModules()
end

CustomUI.RegisterComponent("QoL", QoLComponent)
