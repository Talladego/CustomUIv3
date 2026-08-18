----------------------------------------------------------------
-- CustomUI.KillTracker — Controller / component adapter
----------------------------------------------------------------
if not CustomUI then CustomUI = {} end
CustomUI.KillTracker = CustomUI.KillTracker or {}

local KT = CustomUI.KillTracker

local c_DEFAULT_SETTINGS = {
	replaceChatKills = false,
	showZone = true,
	showCareerIcons = true,
	showAbilityIcons = true,
	showKillCount = true,
	maxVisibleRows = 10,
	fontName = "font_clear_small", -- Myriad Pro - Small (stock chat fonts)
	visibleTimeMinutes = 5, -- feed line lifetime (1–5), same options as stock chat
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
	-- Feed window is primary; stop preferring chat inject from older builds.
	if s._feedPrimaryMigrated ~= true then
		s.replaceChatKills = false
		s._feedPrimaryMigrated = true
		s._chatPrimaryMigrated = true
	end
	for k, v in pairs(c_DEFAULT_SETTINGS) do
		if s[k] == nil then
			s[k] = v
		end
	end
	-- Migrate fontSize slider → chat fontName once.
	if s.fontName == nil or s.fontName == "" then
		local map = {
			"font_clear_tiny",
			"font_clear_small",
			"font_clear_medium",
			"font_clear_large",
			"font_default_text_large",
		}
		local legacy = tonumber(s.fontSize)
		s.fontName = (legacy and map[legacy]) or c_DEFAULT_SETTINGS.fontName
	end
	do
		local mins = tonumber(s.visibleTimeMinutes) or 5
		if mins < 1 then
			mins = 1
		end
		if mins > 5 then
			mins = 5
		end
		s.visibleTimeMinutes = mins
	end
	return s
end

function KT.GetSettings()
	return KT.EnsureSettings()
end

--- Parse a stock RVR kill line, update session counts, push feed row.
--- Optional chat inject when replaceChatKills is enabled.
function KT.ProcessKillLine(rawText, stockFilterId)
	local Parser = KT.Parser
	if not Parser or type(Parser.ParseKillLine) ~= "function" then
		return nil
	end
	local parsed = Parser.ParseKillLine(rawText)
	if not parsed then
		return nil
	end

	if KT.CareerCache and type(KT.CareerCache.RefreshFromWorld) == "function" then
		KT.CareerCache.RefreshFromWorld()
	end
	if KT.Format and type(KT.Format.UpdateLocalAreaCache) == "function" then
		KT.Format.UpdateLocalAreaCache()
	end
	-- Open RvR: unique abilities imply killer career when Social/target cache missed them.
	if KT.CareerCache and type(KT.CareerCache.InferFromUniqueAbility) == "function" then
		KT.CareerCache.InferFromUniqueAbility(parsed.killer, parsed.ability)
	end

	-- Pick RvR vs scenario bag once before counting (sync can clear on enter/leave).
	if KT.Session and type(KT.Session.SyncMatchScope) == "function" then
		KT.Session.SyncMatchScope()
	end

	local settings = KT.GetSettings()
	local killCount = 0
	local deathCount = 0
	local selfKill = Parser.IsSelfKill and Parser.IsSelfKill(parsed)
	if KT.Session then
		-- Self-inflicted / same-name lines: show in feed, count death only (not a DB kill).
		if selfKill then
			if type(KT.Session.GetKillerCount) == "function" then
				killCount = KT.Session.GetKillerCount(parsed.killer)
			end
		elseif type(KT.Session.IncrementKiller) == "function" then
			killCount = KT.Session.IncrementKiller(parsed.killer)
		end
		if type(KT.Session.IncrementVictim) == "function" then
			deathCount = KT.Session.IncrementVictim(parsed.victim)
		end
	end

	local Format = KT.Format
	if not Format or type(Format.Build) ~= "function" then
		return nil
	end
	local model = Format.Build(parsed, stockFilterId, killCount, deathCount, settings)
	if model and selfKill then
		model.isSelfKill = true
	end

	if KT.Window and type(KT.Window.PushKill) == "function" then
		KT.Window.PushKill(model)
	end

	if settings.replaceChatKills == true and KT.Chat and type(KT.Chat.InjectFormattedLine) == "function" then
		KT.Chat.InjectFormattedLine(model.chatText, stockFilterId)
	end

	return model
end

function KT.OnSettingsChanged()
	local s = KT.GetSettings()
	if KT.Window and type(KT.Window.OnSettingsChanged) == "function" then
		KT.Window.OnSettingsChanged()
	elseif KT.Window and type(KT.Window.Reflow) == "function" then
		KT.Window.Reflow()
	end
	if CustomUI.IsComponentEnabled and CustomUI.IsComponentEnabled("KillTracker") then
		if s.replaceChatKills == true and KT.Chat and KT.Chat.EnsureKillFiltersEnabled then
			KT.Chat.EnsureKillFiltersEnabled()
		elseif KT.Chat and KT.Chat.RestoreStockKillFilters then
			KT.Chat.RestoreStockKillFilters()
			if KT.Chat.RemoveHook then
				KT.Chat.RemoveHook()
			end
		end
	end
end

local function WorldEventHandlers()
	local events = SystemData and SystemData.Events
	if not events then
		return nil
	end
	return {
		{ events.PLAYER_TARGET_UPDATED, "CustomUI.KillTracker.OnTargetUpdated" },
		{ events.GROUP_UPDATED, "CustomUI.KillTracker.OnRosterUpdated" },
		{ events.BATTLEGROUP_UPDATED, "CustomUI.KillTracker.OnRosterUpdated" },
		{ events.SCENARIO_BEGIN, "CustomUI.KillTracker.OnScenarioBegin" },
		{ events.CITY_SCENARIO_BEGIN, "CustomUI.KillTracker.OnScenarioBegin" },
		{ events.SCENARIO_END, "CustomUI.KillTracker.OnScenarioEnd" },
		{ events.CITY_SCENARIO_END, "CustomUI.KillTracker.OnScenarioEnd" },
		{ events.SCENARIO_POST_MODE, "CustomUI.KillTracker.OnScenarioPostMode" },
		{ events.SCENARIO_PLAYERS_LIST_UPDATED, "CustomUI.KillTracker.OnRosterUpdated" },
		{ events.SCENARIO_PLAYER_HITS_UPDATED, "CustomUI.KillTracker.OnRosterUpdated" },
		{ events.LOADING_END, "CustomUI.KillTracker.OnLoadingEnd" },
		{ events.PLAYER_ZONE_CHANGED, "CustomUI.KillTracker.OnZoneChanged" },
		{ events.PLAYER_AREA_NAME_CHANGED, "CustomUI.KillTracker.OnZoneChanged" },
		{ events.SOCIAL_FRIENDS_UPDATED, "CustomUI.KillTracker.OnSocialListsUpdated" },
		{ events.SOCIAL_IGNORE_UPDATED, "CustomUI.KillTracker.OnSocialListsUpdated" },
		{ events.GUILD_ROSTER_INIT, "CustomUI.KillTracker.OnSocialListsUpdated" },
		{ events.GUILD_MEMBER_UPDATED, "CustomUI.KillTracker.OnSocialListsUpdated" },
		{ events.GUILD_MEMBER_ADDED, "CustomUI.KillTracker.OnSocialListsUpdated" },
		{ events.GUILD_MEMBER_REMOVED, "CustomUI.KillTracker.OnSocialListsUpdated" },
	}
end

local function RegisterWorldEvents()
	if KT._eventsRegistered then
		return
	end
	if type(WindowRegisterEventHandler) ~= "function" then
		return
	end
	local pairsList = WorldEventHandlers()
	if not pairsList then
		return
	end

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
	if type(WindowUnregisterEventHandler) ~= "function" then
		KT._eventsRegistered = false
		return
	end
	local pairsList = WorldEventHandlers()
	if pairsList then
		for i = 1, #pairsList do
			local ev, handler = pairsList[i][1], pairsList[i][2]
			if ev then
				CustomUI.TryCallQuiet("KillTracker.Unregister " .. handler, WindowUnregisterEventHandler, "Root", ev, handler)
			end
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
	-- ScenarioGroupWindow: list updates after leave can arrive when flags are
	-- already clear — force-end a stale scenario bag.
	if KT.Session and type(KT.Session.OnPossiblyLeftMatch) == "function" then
		KT.Session.OnPossiblyLeftMatch()
	end
end

function KT.OnSocialListsUpdated()
	if KT.CareerCache and type(KT.CareerCache.RefreshSocialLists) == "function" then
		KT.CareerCache.RefreshSocialLists()
	elseif KT.CareerCache and KT.CareerCache.RefreshFromWorld then
		KT.CareerCache.RefreshFromWorld()
	end
end

function KT.OnScenarioBegin()
	-- Stock ScenarioSummaryWindow: SCENARIO_BEGIN is the authoritative new-round signal.
	if KT.Session and KT.Session.BeginNewMatchInstance then
		KT.Session.BeginNewMatchInstance()
	elseif KT.Session and KT.Session.BeginMatchInstance then
		KT.Session.BeginMatchInstance("scenario-begin")
	end
	if KT.Window and KT.Window.Clear then
		KT.Window.Clear()
	end
	KT.OnRosterUpdated()
end

function KT.OnScenarioEnd()
	-- Stock ScenarioSummaryWindow does not listen to SCENARIO_END (it uses
	-- POST_MODE + leave). ScenarioGroupWindow tears down UI immediately.
	-- Keep [N] until leave, but mark post so the next begin always resets.
	if KT.Session and type(KT.Session.MarkPostMode) == "function" then
		KT.Session.MarkPostMode()
	end
	if KT.Session and type(KT.Session.EndMatchInstance) == "function" then
		KT.Session.EndMatchInstance("scenario-end")
	elseif KT.Session and KT.Session.SyncMatchScope then
		KT.Session.SyncMatchScope()
	end
	KT.OnRosterUpdated()
end

function KT.OnScenarioPostMode()
	-- Match combat over; keep the instance bag until leave.
	if KT.Session and type(KT.Session.MarkPostMode) == "function" then
		KT.Session.MarkPostMode()
	end
end

function KT.OnZoneChanged()
	-- Refresh cached area name (kill lines use sub-zone; area.name can be briefly empty).
	if KT.Format and type(KT.Format.UpdateLocalAreaCache) == "function" then
		KT.Format.UpdateLocalAreaCache()
	end
	-- Retint zone name green/white against local area OR main zone name.
	if KT.Window and type(KT.Window.Reflow) == "function" then
		KT.Window.Reflow()
	end
end

function KT.OnLoadingEnd()
	-- Stock ScenarioSummaryWindow.OnLoadingEnd: CITY_SCENARIO_BEGIN is unreliable,
	-- so LoadingEnd + isInSiege is the city begin. We also use LoadingEnd for
	-- missed SCENARIO_BEGIN (PRE_MODE) and for leave-instance cleanup.
	local action = nil
	if KT.Session and type(KT.Session.OnLoadingEnd) == "function" then
		action = KT.Session.OnLoadingEnd()
	elseif KT.Session and KT.Session.SyncMatchScope then
		KT.Session.SyncMatchScope()
	end
	if action == "begin" and KT.Window and KT.Window.Clear then
		KT.Window.Clear()
	end
	if KT.CareerCache and KT.CareerCache.RefreshFromWorld then
		KT.CareerCache.RefreshFromWorld()
	end
	if KT.AbilityMap and KT.AbilityMap.Rebuild then
		KT.AbilityMap.Rebuild()
	end
	-- Re-tint zone labels (green when kill zone == current local zone).
	if KT.Window and type(KT.Window.Reflow) == "function" then
		KT.Window.Reflow()
	end
	local s = KT.GetSettings()
	if s.replaceChatKills == true and KT.Chat and KT.Chat.EnsureKillFiltersEnabled then
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
	if KT.Format and type(KT.Format.UpdateLocalAreaCache) == "function" then
		KT.Format.UpdateLocalAreaCache()
	end
	if KT.CareerCache and KT.CareerCache.RefreshFromWorld then
		KT.CareerCache.RefreshFromWorld()
	end

	local s = KT.GetSettings()
	-- Optional legacy chat rewrite; default is feed-only (stock chat filters untouched).
	if KT.Chat and s.replaceChatKills == true then
		if KT.Chat.InstallHook then
			KT.Chat.InstallHook()
		end
		if KT.Chat.SuppressStockKillFilters then
			KT.Chat.SuppressStockKillFilters()
		elseif KT.Chat.EnsureKillFiltersEnabled then
			KT.Chat.EnsureKillFiltersEnabled()
		end
	elseif KT.Chat then
		if KT.Chat.RemoveHook then
			KT.Chat.RemoveHook()
		end
		if KT.Chat.RestoreStockKillFilters then
			KT.Chat.RestoreStockKillFilters()
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

	if KT.Window and KT.Window.Show then
		KT.Window.Show()
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
