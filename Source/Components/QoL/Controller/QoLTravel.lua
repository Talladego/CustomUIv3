----------------------------------------------------------------
-- CustomUI.QoL.Travel — compact flight-master list (from TravelAddon)
-- Opt-in via /cui → QoL. Replaces EA_InteractionFlightMasterWindow while enabled.
-- Disable the standalone TravelAddon addon to avoid a double hook.
----------------------------------------------------------------
if not CustomUI then CustomUI = {} end
CustomUI.QoL = CustomUI.QoL or {}
CustomUI.QoL.Travel = CustomUI.QoL.Travel or {}

local Travel = CustomUI.QoL.Travel

-- ListBox ListData must be a top-level global name (XML table=).
CustomUIQoLTravelListData = CustomUIQoLTravelListData or {}

local c_WINDOW = "CustomUIQoLTravelWindow"
local c_SLASH = "cuitravel"

local ROW_HEIGHT = 31
local ROW_SPACING = 4
local WINDOW_WIDTH = 420
local LIST_WIDTH = 380
local HEADER_HEIGHT = 118
local BOTTOM_PAD = 18

local COLOR_DEFAULT = { r = 235, g = 235, b = 200 }
local COLOR_ORDER = { r = 107, g = 191, b = 255 }
local COLOR_DESTRO = { r = 255, g = 105, b = 105 }

local CAPITAL_ZONES = {
	[61] = true,  -- Karak Eight Peaks
	[62] = true,  -- Karaz-a-Karak
	[161] = true, -- Inevitable City
	[162] = true, -- Altdorf
}

local function BuildPairings()
	local pairings = {}
	local abbrev = {}
	if type(GameData) ~= "table" or type(GameData.Pairing) ~= "table" then
		return pairings, abbrev
	end
	local gd = GameData.Pairing.GREENSKIN_DWARVES
	local ec = GameData.Pairing.EMPIRE_CHAOS
	local ed = GameData.Pairing.ELVES_DARKELVES
	if gd ~= nil then
		table.insert(pairings, gd)
		abbrev[gd] = L"GvD"
	end
	if ec ~= nil then
		table.insert(pairings, ec)
		abbrev[ec] = L"EvC"
	end
	if ed ~= nil then
		table.insert(pairings, ed)
		abbrev[ed] = L"HEvDE"
	end
	local lotd = type(GameData.ExpansionMapRegion) == "table" and GameData.ExpansionMapRegion.TOMB_KINGS or nil
	if lotd ~= nil then
		table.insert(pairings, lotd)
		abbrev[lotd] = L"LotD"
	end
	return pairings, abbrev
end

local PAIRINGS, PAIRING_ABBREV = BuildPairings()

Travel.listData = CustomUIQoLTravelListData
Travel.listOrder = Travel.listOrder or {}
Travel.selectedPairing = Travel.selectedPairing
	or (type(GameData) == "table" and type(GameData.Pairing) == "table" and GameData.Pairing.GREENSKIN_DWARVES)
	or PAIRINGS[1]

local m_enabled = false
local m_initialized = false
local m_hookInstalled = false
local m_stockFlightShow = nil
local m_eventsRegistered = false
local m_slashRegistered = false
local m_uiSeeded = false

local function getSettings()
	return CustomUI.QoL.EnsureSettings().travel
end

local function isFeatureEnabled()
	local s = getSettings()
	return s.enabled == true
end

local function ZoneTier(zoneNum)
	if CAPITAL_ZONES[zoneNum] then
		return 100
	end
	local campaign = GetCampaignZoneData(zoneNum)
	if campaign and campaign.tierId and campaign.tierId > 0 then
		return campaign.tierId
	end
	return 50
end

local function IsZoneContested(zoneNum)
	local campaign = GetCampaignZoneData(zoneNum)
	if campaign == nil then
		return false
	end
	if campaign.isLocked then
		return false
	end
	return campaign.controllingRealm == GameData.Realm.NONE
end

local function EnsureWindow()
	if type(DoesWindowExist) ~= "function" or type(CreateWindow) ~= "function" then
		return false
	end
	if not DoesWindowExist(c_WINDOW) then
		if type(CustomUI.TryCallQuiet) == "function" then
			CustomUI.TryCallQuiet("QoL.Travel.CreateWindow", CreateWindow, c_WINDOW, false)
		else
			CreateWindow(c_WINDOW, false)
		end
	end
	return DoesWindowExist(c_WINDOW)
end

local function SeedUiChrome()
	if m_uiSeeded or not EnsureWindow() then
		return
	end
	LabelSetText(c_WINDOW .. "TitleBarText", L"Travel")
	LabelSetText(c_WINDOW .. "Status", L"Talk to a flight master to load destinations.")
	for index, pairing in ipairs(PAIRINGS) do
		local tabName = c_WINDOW .. "Tab" .. index
		WindowSetId(tabName, pairing)
		ButtonSetText(tabName, PAIRING_ABBREV[pairing] or towstring(pairing))
	end
	m_uiSeeded = true
end

local function RegisterSlash()
	if m_slashRegistered or LibSlash == nil or type(LibSlash.RegisterSlashCmd) ~= "function" then
		return
	end
	LibSlash.RegisterSlashCmd(c_SLASH, function()
		if isFeatureEnabled() then
			Travel.Toggle()
		elseif type(CustomUI.PrintMessage) == "function" then
			CustomUI.PrintMessage(L"Travel: enable under /cui → QoL.")
		end
	end)
	m_slashRegistered = true
end

local function UnregisterSlash()
	if not m_slashRegistered or LibSlash == nil or type(LibSlash.UnregisterSlashCmd) ~= "function" then
		m_slashRegistered = false
		return
	end
	LibSlash.UnregisterSlashCmd(c_SLASH)
	m_slashRegistered = false
end

local function RegisterEvents()
	if m_eventsRegistered or type(RegisterEventHandler) ~= "function" then
		return
	end
	local e = SystemData and SystemData.Events
	if type(e) ~= "table" then
		return
	end
	RegisterEventHandler(e.LOADING_END, "CustomUI.QoL.Travel.Hide")
	RegisterEventHandler(e.RELOAD_INTERFACE, "CustomUI.QoL.Travel.Hide")
	m_eventsRegistered = true
end

local function UnregisterEvents()
	if not m_eventsRegistered or type(UnregisterEventHandler) ~= "function" then
		m_eventsRegistered = false
		return
	end
	local e = SystemData and SystemData.Events
	if type(e) == "table" then
		UnregisterEventHandler(e.LOADING_END, "CustomUI.QoL.Travel.Hide")
		UnregisterEventHandler(e.RELOAD_INTERFACE, "CustomUI.QoL.Travel.Hide")
	end
	m_eventsRegistered = false
end

--- If standalone TravelAddon already wrapped Show, restore stock first so we own the hook.
local function DisarmStandaloneTravelAddon()
	if type(TravelAddon) ~= "table" then
		return
	end
	if type(TravelAddon.RestoreDefaultFlightMap) == "function" and TravelAddon._defaultFlightShow ~= nil then
		TravelAddon.RestoreDefaultFlightMap()
		if type(CustomUI.PrintMessage) == "function" then
			CustomUI.PrintMessage(L"Travel: disable the TravelAddon addon to avoid conflicts.")
		end
	end
end

local function InstallFlightMasterHook()
	if m_hookInstalled then
		return
	end
	if EA_InteractionFlightMasterWindow == nil or type(EA_InteractionFlightMasterWindow.Show) ~= "function" then
		return
	end
	DisarmStandaloneTravelAddon()
	m_stockFlightShow = EA_InteractionFlightMasterWindow.Show
	EA_InteractionFlightMasterWindow.Show = Travel.OnFlightMasterShow
	m_hookInstalled = true
end

local function RestoreFlightMasterHook()
	if not m_hookInstalled then
		return
	end
	if EA_InteractionFlightMasterWindow ~= nil and m_stockFlightShow ~= nil then
		EA_InteractionFlightMasterWindow.Show = m_stockFlightShow
	end
	m_stockFlightShow = nil
	m_hookInstalled = false
end

function Travel.OnShown()
	if type(WindowUtils) == "table" and type(WindowUtils.OnShown) == "function" then
		WindowUtils.OnShown(Travel.OnHidden, WindowUtils.Cascade.MODE_AUTOMATIC)
	end
end

function Travel.OnHidden()
	if type(WindowUtils) == "table" and type(WindowUtils.OnHidden) == "function" then
		WindowUtils.OnHidden()
	end
end

function Travel.Show()
	if not EnsureWindow() then
		return
	end
	SeedUiChrome()
	WindowSetShowing(c_WINDOW, true)
	Travel.RefreshList()
end

function Travel.Hide()
	if type(DoesWindowExist) == "function" and DoesWindowExist(c_WINDOW) then
		WindowSetShowing(c_WINDOW, false)
	end
end

function Travel.Toggle()
	if not EnsureWindow() then
		return
	end
	if WindowGetShowing(c_WINDOW) then
		Travel.Hide()
	else
		Travel.Show()
	end
end

function Travel.OnFlightMasterShow()
	if not isFeatureEnabled() then
		if m_stockFlightShow then
			m_stockFlightShow()
		end
		return
	end
	Travel.selectedPairing = GetZonePairing() or Travel.selectedPairing
	Travel.UpdateTabs()
	Travel.Show()
	if DoesWindowExist("EA_InteractionFlightMasterWindow") then
		WindowSetShowing("EA_InteractionFlightMasterWindow", false)
	end
end

function Travel.OnTabClick()
	local pairing = WindowGetId(SystemData.ActiveWindow.name)
	if pairing == nil or pairing == 0 then
		return
	end
	Travel.selectedPairing = pairing
	Travel.UpdateTabs()
	Travel.RefreshList()
end

function Travel.UpdateTabs()
	if not EnsureWindow() then
		return
	end
	for index, pairing in ipairs(PAIRINGS) do
		ButtonSetPressedFlag(c_WINDOW .. "Tab" .. index, pairing == Travel.selectedPairing)
	end
end

function Travel.FitWindowToRows(count)
	if not EnsureWindow() then
		return
	end
	local rows = math.max(count, 1)
	local listHeight = (rows * ROW_HEIGHT) + (math.max(rows - 1, 0) * ROW_SPACING)
	local windowHeight = HEADER_HEIGHT + listHeight + BOTTOM_PAD

	if ListBoxSetVisibleRowCount then
		ListBoxSetVisibleRowCount(c_WINDOW .. "List", rows)
	end

	WindowSetDimensions(c_WINDOW .. "List", LIST_WIDTH, listHeight)
	WindowSetDimensions(c_WINDOW, WINDOW_WIDTH, windowHeight)
end

function Travel.RefreshList()
	if not EnsureWindow() then
		return
	end
	SeedUiChrome()

	for index in pairs(CustomUIQoLTravelListData) do
		CustomUIQoLTravelListData[index] = nil
	end
	Travel.listOrder = {}

	local raw = GetFlightMasterData()
	if raw == nil then
		LabelSetText(c_WINDOW .. "Status", L"No flight master data.")
		Travel.FitWindowToRows(0)
		ListBoxSetDisplayOrder(c_WINDOW .. "List", {})
		return
	end

	local count = 0
	for _, flight in ipairs(raw) do
		if flight.pairing == Travel.selectedPairing then
			count = count + 1
			CustomUIQoLTravelListData[count] = {
				name = GetZoneName(flight.zoneNum) or towstring("Zone " .. flight.zoneNum),
				zoneNum = flight.zoneNum,
				flightPointID = flight.flightPointID,
				cost = flight.cost or 0,
				zoneAvailable = flight.zoneAvailable and true or false,
				pairing = flight.pairing,
				tier = ZoneTier(flight.zoneNum),
				isCapital = CAPITAL_ZONES[flight.zoneNum] and true or false,
				isContested = IsZoneContested(flight.zoneNum),
			}
			table.insert(Travel.listOrder, count)
		end
	end

	table.sort(Travel.listOrder, function(a, b)
		local left = CustomUIQoLTravelListData[a]
		local right = CustomUIQoLTravelListData[b]
		if left.tier ~= right.tier then
			return left.tier < right.tier
		end
		return left.zoneNum < right.zoneNum
	end)

	if count == 0 then
		LabelSetText(c_WINDOW .. "Status", L"No destinations for this pairing.")
	else
		LabelSetText(c_WINDOW .. "Status", towstring(count) .. L" destinations")
	end

	Travel.FitWindowToRows(count)
	ListBoxSetDisplayOrder(c_WINDOW .. "List", Travel.listOrder)
end

function Travel.PopulateList()
	local listBox = _G[c_WINDOW .. "List"]
	local indices = listBox and listBox.PopulatorIndices
	if indices == nil then
		return
	end

	for rowIndex, dataIndex in ipairs(indices) do
		local rowWindow = c_WINDOW .. "ListRow" .. rowIndex
		local entry = CustomUIQoLTravelListData[dataIndex]
		if entry ~= nil then
			ButtonSetText(rowWindow, L"")
			LabelSetText(rowWindow .. "Name", entry.name)
			MoneyFrame.FormatMoney(rowWindow .. "Cost", entry.cost, MoneyFrame.HIDE_EMPTY_WINDOWS)

			local color = COLOR_DEFAULT
			if entry.isContested then
				if GameData.Player.realm == GameData.Realm.ORDER then
					color = COLOR_ORDER
				elseif GameData.Player.realm == GameData.Realm.DESTRUCTION then
					color = COLOR_DESTRO
				end
			end
			LabelSetTextColor(rowWindow .. "Name", color.r, color.g, color.b)

			local here = (entry.zoneNum == GameData.Player.zone)
			local disabled = (not entry.zoneAvailable) or here
			ButtonSetDisabledFlag(rowWindow, disabled)
		end
	end
end

function Travel.OnDestinationClick()
	local rowWindow = SystemData.ActiveWindow.name
	if ButtonGetDisabledFlag(rowWindow) then
		return
	end

	local rowIndex = WindowGetId(rowWindow)
	local dataIndex = ListBoxGetDataIndex(c_WINDOW .. "List", rowIndex)
	local entry = CustomUIQoLTravelListData[dataIndex]
	if entry == nil or not entry.zoneAvailable then
		return
	end

	SystemData.UserInput.SelectedFlightPoint = entry.flightPointID
	BroadcastEvent(SystemData.Events.INTERACT_SELECT_FLIGHT_POINT)
	if PlayInteractSound then
		PlayInteractSound("travel_accept")
	end
end

function Travel.Initialize()
	if m_initialized then
		return
	end
	m_initialized = true
	if #PAIRINGS == 0 then
		PAIRINGS, PAIRING_ABBREV = BuildPairings()
	end
	Travel.selectedPairing = (type(GetZonePairing) == "function" and GetZonePairing()) or Travel.selectedPairing or PAIRINGS[1]
end

function Travel.Enable()
	m_enabled = true
	EnsureWindow()
	SeedUiChrome()
	Travel.UpdateTabs()
	InstallFlightMasterHook()
	RegisterEvents()
	RegisterSlash()
end

function Travel.Disable()
	m_enabled = false
	Travel.Hide()
	RestoreFlightMasterHook()
	UnregisterEvents()
	UnregisterSlash()
end

function Travel.Shutdown()
	Travel.Disable()
	m_initialized = false
	m_uiSeeded = false
end
