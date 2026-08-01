----------------------------------------------------------------
-- CustomUI.KillTracker.Chat
--
-- Stock RVR_KILLS_* lines stay in the Combat TextLog but are hidden on chat
-- LogDisplays. Reformatted lines use dedicated KillTracker filters with a white
-- base color; player names / abilities are colored via LINK tags.
----------------------------------------------------------------
if not CustomUI then CustomUI = {} end
CustomUI.KillTracker = CustomUI.KillTracker or {}
CustomUI.KillTracker.Chat = CustomUI.KillTracker.Chat or {}

local Chat = CustomUI.KillTracker.Chat

-- Dedicated Combat-log filter IDs (avoid collision with SystemData.ChatLogFilters).
-- Bumped off 1919/1920: TextLogAddFilterType keeps the first name for an id for the
-- client session, so "KillTracker Order" could not be cleared with L"".
Chat.FILTER_ORDER = 1931
Chat.FILTER_DESTRO = 1932
Chat.LEGACY_FILTER_ORDER = 1919
Chat.LEGACY_FILTER_DESTRO = 1920

Chat._hooked = false
Chat._originalTextLogAddEntry = nil
Chat._rewriting = false
Chat._savedFilters = Chat._savedFilters or {}
Chat._suppressing = false
Chat._filtersRegistered = false

-- Base line color is white; realm colors are applied via LINK on player names only.
local c_FILTER_RGB = { 255, 255, 255 }

local function StockOrderFilter()
	return SystemData.ChatLogFilters.RVR_KILLS_ORDER
end

local function StockDestroFilter()
	return SystemData.ChatLogFilters.RVR_KILLS_DESTRUCTION
end

local function IsStockRvrKillFilter(filterId)
	return filterId == StockOrderFilter() or filterId == StockDestroFilter()
end

local function MapToKillTrackerFilter(stockFilterId)
	if stockFilterId == StockDestroFilter() then
		return Chat.FILTER_DESTRO
	end
	return Chat.FILTER_ORDER
end

local function ForEachChatLogDisplay(callback)
	if type(EA_ChatTabManager) ~= "table" or type(EA_ChatTabManager.Tabs) ~= "table" then
		return
	end
	for _, tab in pairs(EA_ChatTabManager.Tabs) do
		if type(tab) == "table" and tab.used and tab.name then
			local display = tab.name .. "TextLog"
			if type(DoesWindowExist) ~= "function" or DoesWindowExist(display) then
				callback(display)
			end
		end
	end
end

local function RegisterCustomFilters()
	-- Always re-assert empty display names (prefix string is the 3rd arg).
	if type(TextLogAddFilterType) == "function" then
		CustomUI.TryCallQuiet(
			"KillTracker.TextLogAddFilterType.order",
			TextLogAddFilterType,
			"Combat",
			Chat.FILTER_ORDER,
			L""
		)
		CustomUI.TryCallQuiet(
			"KillTracker.TextLogAddFilterType.destro",
			TextLogAddFilterType,
			"Combat",
			Chat.FILTER_DESTRO,
			L""
		)
	end
	Chat._filtersRegistered = true
end

local function HideLegacyKillTrackerFilters(display)
	if type(LogDisplaySetFilterState) ~= "function" then
		return
	end
	CustomUI.TryCallQuiet(
		"KillTracker.HideLegacyOrder",
		LogDisplaySetFilterState,
		display,
		"Combat",
		Chat.LEGACY_FILTER_ORDER,
		false
	)
	CustomUI.TryCallQuiet(
		"KillTracker.HideLegacyDestro",
		LogDisplaySetFilterState,
		display,
		"Combat",
		Chat.LEGACY_FILTER_DESTRO,
		false
	)
end

local function ApplyCustomFilterDisplay(display)
	if type(LogDisplaySetFilterState) ~= "function" then
		return
	end
	CustomUI.TryCallQuiet(
		"KillTracker.ShowKTOrder",
		LogDisplaySetFilterState,
		display,
		"Combat",
		Chat.FILTER_ORDER,
		true
	)
	CustomUI.TryCallQuiet(
		"KillTracker.ShowKTDestro",
		LogDisplaySetFilterState,
		display,
		"Combat",
		Chat.FILTER_DESTRO,
		true
	)
	if type(LogDisplaySetFilterColor) == "function" then
		CustomUI.TryCallQuiet(
			"KillTracker.ColorKTOrder",
			LogDisplaySetFilterColor,
			display,
			"Combat",
			Chat.FILTER_ORDER,
			c_FILTER_RGB[1],
			c_FILTER_RGB[2],
			c_FILTER_RGB[3]
		)
		CustomUI.TryCallQuiet(
			"KillTracker.ColorKTDestro",
			LogDisplaySetFilterColor,
			display,
			"Combat",
			Chat.FILTER_DESTRO,
			c_FILTER_RGB[1],
			c_FILTER_RGB[2],
			c_FILTER_RGB[3]
		)
	end
end

--- Hide stock Order/Destruction kills; show KillTracker filters instead.
function Chat.SuppressStockKillFilters()
	RegisterCustomFilters()

	if not Chat._suppressing then
		Chat._savedFilters = {}
		ForEachChatLogDisplay(function(display)
			local saved = { display = display, filters = {} }
			local stock = { StockOrderFilter(), StockDestroFilter() }
			for i = 1, #stock do
				local fid = stock[i]
				local prev = true
				if type(LogDisplayGetFilterState) == "function" then
					local ok, state = CustomUI.TryCallQuiet(
						"KillTracker.LogDisplayGetFilterState",
						LogDisplayGetFilterState,
						display,
						"Combat",
						fid
					)
					if ok and state ~= nil then
						prev = state and true or false
					end
				end
				saved.filters[fid] = prev
			end
			Chat._savedFilters[#Chat._savedFilters + 1] = saved
		end)
		Chat._suppressing = true
	end

	ForEachChatLogDisplay(function(display)
		if type(LogDisplaySetFilterState) == "function" then
			CustomUI.TryCallQuiet(
				"KillTracker.HideStockOrder",
				LogDisplaySetFilterState,
				display,
				"Combat",
				StockOrderFilter(),
				false
			)
			CustomUI.TryCallQuiet(
				"KillTracker.HideStockDestro",
				LogDisplaySetFilterState,
				display,
				"Combat",
				StockDestroFilter(),
				false
			)
		end
		HideLegacyKillTrackerFilters(display)
		ApplyCustomFilterDisplay(display)
	end)
end

function Chat.ApplySuppressOnly()
	if not Chat._suppressing then
		Chat.SuppressStockKillFilters()
		return
	end
	RegisterCustomFilters()
	ForEachChatLogDisplay(function(display)
		if type(LogDisplaySetFilterState) == "function" then
			CustomUI.TryCallQuiet(
				"KillTracker.HideStockOrder",
				LogDisplaySetFilterState,
				display,
				"Combat",
				StockOrderFilter(),
				false
			)
			CustomUI.TryCallQuiet(
				"KillTracker.HideStockDestro",
				LogDisplaySetFilterState,
				display,
				"Combat",
				StockDestroFilter(),
				false
			)
		end
		HideLegacyKillTrackerFilters(display)
		ApplyCustomFilterDisplay(display)
	end)
end

function Chat.EnsureKillFiltersEnabled()
	Chat.SuppressStockKillFilters()
end

function Chat.RestoreStockKillFilters()
	ForEachChatLogDisplay(function(display)
		if type(LogDisplaySetFilterState) == "function" then
			CustomUI.TryCallQuiet(
				"KillTracker.HideKTOrder",
				LogDisplaySetFilterState,
				display,
				"Combat",
				Chat.FILTER_ORDER,
				false
			)
			CustomUI.TryCallQuiet(
				"KillTracker.HideKTDestro",
				LogDisplaySetFilterState,
				display,
				"Combat",
				Chat.FILTER_DESTRO,
				false
			)
		end
	end)

	if Chat._suppressing and type(Chat._savedFilters) == "table" then
		for i = 1, #Chat._savedFilters do
			local saved = Chat._savedFilters[i]
			if saved and saved.display and type(saved.filters) == "table" then
				for fid, prev in pairs(saved.filters) do
					if type(LogDisplaySetFilterState) == "function" then
						CustomUI.TryCallQuiet(
							"KillTracker.RestoreStockFilter",
							LogDisplaySetFilterState,
							saved.display,
							"Combat",
							fid,
							prev and true or false
						)
					end
				end
			end
		end
	end
	Chat._savedFilters = {}
	Chat._suppressing = false
end

function Chat.IsEnrichedText(text)
	if text == nil then
		return false
	end
	local s = tostring(towstring(text))
	if string.find(s, "<LINK", 1, true) then
		return true
	end
	if string.find(s, "<icon", 1, true) then
		return true
	end
	return false
end

local function ProcessAndFormat(rawText, stockFilterId)
	local KT = CustomUI.KillTracker
	local Parser = KT.Parser
	if not Parser or type(Parser.ParseKillLine) ~= "function" then
		return nil
	end
	local parsed = Parser.ParseKillLine(rawText)
	if not parsed then
		return nil
	end

	-- Refresh roster/target careers before icon lookup (scenario careerId mapping).
	if KT.CareerCache and type(KT.CareerCache.RefreshFromWorld) == "function" then
		KT.CareerCache.RefreshFromWorld()
	end

	local settings = KT.GetSettings and KT.GetSettings() or {}
	local killCount = 0
	local deathCount = 0
	if KT.Session then
		if type(KT.Session.IncrementKiller) == "function" then
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

	if settings.showFeedWindow == true and KT.Window and type(KT.Window.PushKill) == "function" then
		KT.Window.PushKill(model)
	end

	return model
end

function Chat.InjectFormattedLine(chatText, stockFilterId)
	if chatText == nil or chatText == L"" then
		return
	end
	if type(TextLogAddEntry) ~= "function" then
		return
	end
	local outFilter = MapToKillTrackerFilter(stockFilterId)
	Chat._rewriting = true
	CustomUI.TryCallQuiet(
		"KillTracker.TextLogAddEntry",
		TextLogAddEntry,
		"Combat",
		outFilter,
		chatText
	)
	Chat._rewriting = false
	Chat.ApplySuppressOnly()
end

function Chat.HandleStockKillLine(rawText, stockFilterId)
	local settings = CustomUI.KillTracker.GetSettings and CustomUI.KillTracker.GetSettings() or {}
	if settings.replaceChatKills == false then
		return
	end
	local model = ProcessAndFormat(rawText, stockFilterId)
	if not model then
		return
	end
	Chat.InjectFormattedLine(model.chatText, stockFilterId)
end

local function HookedTextLogAddEntry(logName, filterId, text)
	local original = Chat._originalTextLogAddEntry
	if type(original) ~= "function" then
		return
	end

	if Chat._rewriting then
		return original(logName, filterId, text)
	end

	local KT = CustomUI.KillTracker
	local settings = KT.GetSettings and KT.GetSettings() or {}
	local enabled = CustomUI.IsComponentEnabled and CustomUI.IsComponentEnabled("KillTracker")
	if enabled
		and settings.replaceChatKills ~= false
		and logName == "Combat"
		and IsStockRvrKillFilter(filterId)
		and not Chat.IsEnrichedText(text)
	then
		local model = ProcessAndFormat(text, filterId)
		if model and model.chatText then
			-- Drop stock filter entry; write only the KillTracker-filtered line.
			Chat._rewriting = true
			local ok = original(logName, MapToKillTrackerFilter(filterId), model.chatText)
			Chat._rewriting = false
			Chat.ApplySuppressOnly()
			return ok
		end
	end

	return original(logName, filterId, text)
end

function Chat.InstallHook()
	if Chat._hooked then
		return
	end
	if type(TextLogAddEntry) ~= "function" then
		return
	end
	Chat._originalTextLogAddEntry = TextLogAddEntry
	TextLogAddEntry = HookedTextLogAddEntry
	Chat._hooked = true
end

function Chat.RemoveHook()
	if not Chat._hooked then
		return
	end
	if Chat._originalTextLogAddEntry then
		TextLogAddEntry = Chat._originalTextLogAddEntry
	end
	Chat._originalTextLogAddEntry = nil
	Chat._hooked = false
	Chat._rewriting = false
end

function Chat.IsSuppressing()
	return Chat._suppressing == true
end
