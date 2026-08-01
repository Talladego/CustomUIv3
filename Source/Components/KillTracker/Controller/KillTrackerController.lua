----------------------------------------------------------------
-- CustomUI.KillTracker — Controller / component adapter
----------------------------------------------------------------
if not CustomUI then CustomUI = {} end
CustomUI.KillTracker = CustomUI.KillTracker or {}

local KT = CustomUI.KillTracker

local c_DEFAULT_SETTINGS = {
	replaceChatKills = true,
	showFeedWindow = false,
	showZone = true,
	showStreak = true,
	showCareerIcons = true,
	showAbilityIcons = true,
	showKillCount = true,
	maxVisibleRows = 10,
}

KT._eventsRegistered = false

function KT.EnsureSettings()
	CustomUI.Settings = CustomUI.Settings or { Components = {} }
	if CustomUI.Settings.Components == nil then
		CustomUI.Settings.Components = {}
	end
	if type(CustomUI.Settings.KillTracker) ~= "table" then
		CustomUI.Settings.KillTracker = {}
	end
	local s = CustomUI.Settings.KillTracker
	-- Older builds defaulted the overlay feed on; chat is the primary output now.
	if s._chatPrimaryMigrated ~= true then
		s.showFeedWindow = false
		s._chatPrimaryMigrated = true
	end
	for k, v in pairs(c_DEFAULT_SETTINGS) do
		if s[k] == nil then
			s[k] = v
		end
	end
	return s
end

function KT.GetSettings()
	return KT.EnsureSettings()
end

function KT.OnSettingsChanged()
	local s = KT.GetSettings()
	if KT.Window and type(KT.Window.OnSettingsChanged) == "function" then
		KT.Window.OnSettingsChanged()
	end
	if CustomUI.IsComponentEnabled and CustomUI.IsComponentEnabled("KillTracker") then
		if s.replaceChatKills ~= false and KT.Chat and KT.Chat.EnsureKillFiltersEnabled then
			KT.Chat.EnsureKillFiltersEnabled()
		end
	end
end

local function RegisterWorldEvents()
	if KT._eventsRegistered then
		return
	end
	if type(WindowRegisterEventHandler) ~= "function" then
		return
	end
	local events = SystemData and SystemData.Events
	if not events then
		return
	end

	local pairsList = {
		{ events.PLAYER_TARGET_UPDATED, "CustomUI.KillTracker.OnTargetUpdated" },
		{ events.GROUP_UPDATED, "CustomUI.KillTracker.OnRosterUpdated" },
		{ events.BATTLEGROUP_UPDATED, "CustomUI.KillTracker.OnRosterUpdated" },
		{ events.SCENARIO_BEGIN, "CustomUI.KillTracker.OnScenarioBegin" },
		{ events.CITY_SCENARIO_BEGIN, "CustomUI.KillTracker.OnScenarioBegin" },
		{ events.SCENARIO_END, "CustomUI.KillTracker.OnScenarioEnd" },
		{ events.CITY_SCENARIO_END, "CustomUI.KillTracker.OnScenarioEnd" },
		{ events.SCENARIO_PLAYERS_LIST_UPDATED, "CustomUI.KillTracker.OnRosterUpdated" },
		{ events.SCENARIO_PLAYER_HITS_UPDATED, "CustomUI.KillTracker.OnRosterUpdated" },
		{ events.LOADING_BEGIN, "CustomUI.KillTracker.OnLoadingBegin" },
		{ events.LOADING_END, "CustomUI.KillTracker.OnLoadingEnd" },
	}

	for i = 1, #pairsList do
		local ev, handler = pairsList[i][1], pairsList[i][2]
		if ev then
			CustomUI.TryCallQuiet("KillTracker.Register " .. handler, WindowRegisterEventHandler, "Root", ev, handler)
		end
	end
	KT._eventsRegistered = true
end

local function UnregisterWorldEvents()
	if not KT._eventsRegistered then
		return
	end
	local events = SystemData and SystemData.Events
	if not events or type(WindowUnregisterEventHandler) ~= "function" then
		KT._eventsRegistered = false
		return
	end

	local pairsList = {
		{ events.PLAYER_TARGET_UPDATED, "CustomUI.KillTracker.OnTargetUpdated" },
		{ events.GROUP_UPDATED, "CustomUI.KillTracker.OnRosterUpdated" },
		{ events.BATTLEGROUP_UPDATED, "CustomUI.KillTracker.OnRosterUpdated" },
		{ events.SCENARIO_BEGIN, "CustomUI.KillTracker.OnScenarioBegin" },
		{ events.CITY_SCENARIO_BEGIN, "CustomUI.KillTracker.OnScenarioBegin" },
		{ events.SCENARIO_END, "CustomUI.KillTracker.OnScenarioEnd" },
		{ events.CITY_SCENARIO_END, "CustomUI.KillTracker.OnScenarioEnd" },
		{ events.SCENARIO_PLAYERS_LIST_UPDATED, "CustomUI.KillTracker.OnRosterUpdated" },
		{ events.SCENARIO_PLAYER_HITS_UPDATED, "CustomUI.KillTracker.OnRosterUpdated" },
		{ events.LOADING_BEGIN, "CustomUI.KillTracker.OnLoadingBegin" },
		{ events.LOADING_END, "CustomUI.KillTracker.OnLoadingEnd" },
	}

	for i = 1, #pairsList do
		local ev, handler = pairsList[i][1], pairsList[i][2]
		if ev then
			CustomUI.TryCallQuiet("KillTracker.Unregister " .. handler, WindowUnregisterEventHandler, "Root", ev, handler)
		end
	end
	KT._eventsRegistered = false
end

function KT.OnTargetUpdated()
	if KT.CareerCache and KT.CareerCache.OnTargetUpdated then
		KT.CareerCache.OnTargetUpdated()
	end
end

function KT.OnRosterUpdated()
	if KT.CareerCache and KT.CareerCache.RefreshFromWorld then
		KT.CareerCache.RefreshFromWorld()
	end
end

function KT.OnScenarioBegin()
	if KT.Session and KT.Session.BeginNewMatchInstance then
		KT.Session.BeginNewMatchInstance()
	elseif KT.Session and KT.Session.ResetScenario then
		KT.Session.ResetScenario()
	end
	if KT.Window and KT.Window.Clear then
		KT.Window.Clear()
	end
	KT.OnRosterUpdated()
end

function KT.OnScenarioEnd()
	if KT.Session and KT.Session.ResetScenario then
		KT.Session.ResetScenario()
	end
	if KT.Window and KT.Window.Clear then
		KT.Window.Clear()
	end
	KT.OnRosterUpdated()
end

function KT.OnLoadingBegin()
	-- RvR bag survives zone loads. Match leave/enter is resolved on LOADING_END
	-- and before each kill via Session.SyncMatchScope.
	if KT.Window and KT.Window.Clear then
		KT.Window.Clear()
	end
end

function KT.OnLoadingEnd()
	if KT.Session and KT.Session.SyncMatchScope then
		KT.Session.SyncMatchScope()
	end
	if KT.CareerCache and KT.CareerCache.RefreshFromWorld then
		KT.CareerCache.RefreshFromWorld()
	end
	if KT.AbilityMap and KT.AbilityMap.Rebuild then
		KT.AbilityMap.Rebuild()
	end
	local s = KT.GetSettings()
	if s.replaceChatKills ~= false and KT.Chat and KT.Chat.EnsureKillFiltersEnabled then
		KT.Chat.EnsureKillFiltersEnabled()
	end
end

----------------------------------------------------------------
-- Component adapter
----------------------------------------------------------------

local KillTrackerComponent = { Name = "KillTracker", DefaultEnabled = false }

function KillTrackerComponent:Initialize()
	KT.EnsureSettings()
	if KT.Window and type(KT.Window.Initialize) == "function" then
		KT.Window.Initialize()
	end
	return true
end

function KillTrackerComponent:Enable()
	KT.EnsureSettings()
	if KT.AbilityMap and KT.AbilityMap.EnsureBuilt then
		KT.AbilityMap.EnsureBuilt()
	end
	if KT.CareerCache and KT.CareerCache.RefreshFromWorld then
		KT.CareerCache.RefreshFromWorld()
	end

	local s = KT.GetSettings()
	if KT.Chat and s.replaceChatKills ~= false then
		if KT.Chat.InstallHook then
			KT.Chat.InstallHook()
		end
		-- Hide stock Order/Destruction lines; show KillTracker-filter reformatted lines.
		if KT.Chat.SuppressStockKillFilters then
			KT.Chat.SuppressStockKillFilters()
		elseif KT.Chat.EnsureKillFiltersEnabled then
			KT.Chat.EnsureKillFiltersEnabled()
		end
	end

	KT.StartCapture()
	RegisterWorldEvents()

	if KT.Session then
		if KT.Session.SyncMatchScope then
			KT.Session.SyncMatchScope()
		end
		if KT.Session.AnnounceFocusIfChanged then
			KT.Session.AnnounceFocusIfChanged(true)
		end
	end

	if s.showFeedWindow == true and KT.Window and KT.Window.Show then
		KT.Window.Show()
	elseif KT.Window and KT.Window.Hide then
		KT.Window.Hide()
	end
	return true
end

function KillTrackerComponent:Disable()
	KT.StopCapture()
	UnregisterWorldEvents()

	if KT.Chat then
		if KT.Chat.RemoveHook then
			KT.Chat.RemoveHook()
		end
		if KT.Chat.RestoreStockKillFilters then
			KT.Chat.RestoreStockKillFilters()
		end
	end
	if KT.Session and KT.Session.Reset then
		KT.Session.Reset()
	end
	if KT.Window and KT.Window.Hide then
		KT.Window.Hide()
	end
	return true
end

function KillTrackerComponent:Shutdown()
	self:Disable()
end

CustomUI.RegisterComponent("KillTracker", KillTrackerComponent)
