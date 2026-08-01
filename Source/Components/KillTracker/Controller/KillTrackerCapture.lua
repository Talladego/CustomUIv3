----------------------------------------------------------------
-- CustomUI.KillTracker.Capture — Combat TextLog RVR_KILLS_* listener
----------------------------------------------------------------
if not CustomUI then CustomUI = {} end
CustomUI.KillTracker = CustomUI.KillTracker or {}

local KT = CustomUI.KillTracker

KT._combatLogEventId = nil
KT._captureEnabled = false

local function IsRvrKillFilter(filterType)
	return filterType == SystemData.ChatLogFilters.RVR_KILLS_ORDER
		or filterType == SystemData.ChatLogFilters.RVR_KILLS_DESTRUCTION
end

function KT.OnCombatLogUpdated(updateType, filterType)
	if not KT._captureEnabled then
		return
	end
	if updateType ~= SystemData.TextLogUpdate.ADDED then
		return
	end

	-- Ignore our own KillTracker-filter injects (and any other non-stock filters).
	if not IsRvrKillFilter(filterType) then
		return
	end

	local num = TextLogGetNumEntries("Combat")
	if not num or num < 1 then
		return
	end
	local _, _, msg = TextLogGetEntry("Combat", num - 1)
	if msg == nil then
		return
	end

	-- Already rewritten by TextLogAddEntry hook — do not double-count / inject.
	if KT.Chat and KT.Chat.IsEnrichedText and KT.Chat.IsEnrichedText(msg) then
		return
	end

	-- C++ path: stock line is hidden via suppressed RVR_KILLS filters; inject
	-- reformatted line under KillTracker Order/Destruction filter ids.
	if KT.Chat and type(KT.Chat.HandleStockKillLine) == "function" then
		KT.Chat.HandleStockKillLine(msg, filterType)
	end
end

function KT.StartCapture()
	if KT._captureEnabled then
		return
	end
	if type(TextLogGetUpdateEventId) ~= "function" then
		return
	end
	local ok, eventId = CustomUI.TryCallQuiet(
		"KillTracker.TextLogGetUpdateEventId",
		TextLogGetUpdateEventId,
		"Combat"
	)
	if not ok or not eventId then
		return
	end
	KT._combatLogEventId = eventId
	CustomUI.TryCallQuiet(
		"KillTracker.RegisterCombatLog",
		RegisterEventHandler,
		eventId,
		"CustomUI.KillTracker.OnCombatLogUpdated"
	)
	KT._captureEnabled = true
end

function KT.StopCapture()
	if not KT._captureEnabled then
		return
	end
	if KT._combatLogEventId then
		CustomUI.TryCallQuiet(
			"KillTracker.UnregisterCombatLog",
			UnregisterEventHandler,
			KT._combatLogEventId,
			"CustomUI.KillTracker.OnCombatLogUpdated"
		)
	end
	KT._combatLogEventId = nil
	KT._captureEnabled = false
end
