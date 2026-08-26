----------------------------------------------------------------
-- CustomUI.QoL.AltTracker.Tooltips — item side panel + gold tooltip
----------------------------------------------------------------
if not CustomUI then CustomUI = {} end
CustomUI.QoL = CustomUI.QoL or {}
CustomUI.QoL.AltTracker = CustomUI.QoL.AltTracker or {}

local Tips = {}
CustomUI.QoL.AltTracker.Tooltips = Tips

local PANEL = "CustomUIAltTrackerItemPanel"
local PANEL_TITLE = PANEL .. "Title"
local MAX_ROWS = 28
local MAX_CHARS_PER_FACTION = 12
local GOLD_PANEL = "CustomUIAltTrackerGoldPanel"
local GOLD_PANEL_TITLE = GOLD_PANEL .. "Title"
local MAX_GOLD_ROWS = 28
local GOLD_PANEL_W = 280
local GOLD_NAME_W = 90
local GOLD_MONEY_W = 150
local ROW_HEIGHT = 16
local HEADER_HEIGHT = 26
local PANEL_PAD = 10
local NAME_LABEL_W = 124
local NAME_LABEL_H = 16
local COUNT_LABEL_W = 60
local CAREER_ATLAS = 32
local CAREER_DRAW = 14

local m_origCreate = nil
local m_origClear = nil
local m_hooksInstalled = false
local m_panelAttached = false
local m_moneyTooltipVisible = false

local function getSettings()
	if CustomUI and CustomUI.QoL and type(CustomUI.QoL.EnsureSettings) == "function" then
		return CustomUI.QoL.EnsureSettings().altTracker or {}
	end
	return {}
end

local function getData()
	return CustomUI.QoL.AltTracker and CustomUI.QoL.AltTracker.Data
end

local function rowWindows(index)
	local base = PANEL .. "Row" .. tostring(index)
	return base .. "Name", base .. "Count", base .. "Icon"
end

local function goldRowWindows(index)
	local base = GOLD_PANEL .. "Row" .. tostring(index)
	return base .. "Name", base .. "Money", base .. "Icon"
end

local function setCareerIcon(iconWin, careerLine)
	if not DoesWindowExist(iconWin) then
		return
	end
	careerLine = tonumber(careerLine) or 0
	local iconId = nil
	if careerLine > 0
		and type(Icons) == "table"
		and type(Icons.GetCareerIconIDFromCareerLine) == "function" then
		iconId = Icons.GetCareerIconIDFromCareerLine(careerLine)
	end
	iconId = tonumber(iconId)
	if not iconId or iconId <= 0 or type(GetIconData) ~= "function" then
		WindowSetShowing(iconWin, false)
		return
	end
	local texture, x, y = GetIconData(iconId)
	if not texture or texture == "" or texture == "icon000000" then
		WindowSetShowing(iconWin, false)
		return
	end
	DynamicImageSetTexture(iconWin, texture, x, y)
	if type(DynamicImageSetTextureDimensions) == "function" then
		DynamicImageSetTextureDimensions(iconWin, CAREER_ATLAS, CAREER_ATLAS)
	end
	if type(WindowSetDimensions) == "function" then
		WindowSetDimensions(iconWin, CAREER_DRAW, CAREER_DRAW)
	end
	WindowSetShowing(iconWin, true)
end

local function resetRow(nameWin, countWin, iconWin)
	if DoesWindowExist(nameWin) then
		LabelSetText(nameWin, L"")
		WindowSetDimensions(nameWin, NAME_LABEL_W, NAME_LABEL_H)
		WindowSetShowing(nameWin, false)
	end
	if DoesWindowExist(countWin) then
		LabelSetText(countWin, L"")
		WindowSetDimensions(countWin, COUNT_LABEL_W, NAME_LABEL_H)
		WindowSetShowing(countWin, false)
	end
	if DoesWindowExist(iconWin) then
		WindowSetShowing(iconWin, false)
	end
end

local function resetGoldRow(nameWin, moneyWin, iconWin)
	if DoesWindowExist(nameWin) then
		LabelSetText(nameWin, L"")
		WindowSetDimensions(nameWin, GOLD_NAME_W, NAME_LABEL_H)
		WindowSetShowing(nameWin, false)
	end
	if DoesWindowExist(moneyWin) then
		LabelSetText(moneyWin, L"")
		WindowSetDimensions(moneyWin, GOLD_MONEY_W, NAME_LABEL_H)
		WindowSetShowing(moneyWin, false)
	end
	if DoesWindowExist(iconWin) then
		WindowSetShowing(iconWin, false)
	end
end

local function rowTopY(rowIndex)
	return HEADER_HEIGHT + (rowIndex - 1) * ROW_HEIGHT
end

local function anchorGoldRowIcon(iconWin, rowIndex)
	if not DoesWindowExist(iconWin) then
		return
	end
	WindowClearAnchors(iconWin)
	WindowAddAnchor(iconWin, "topleft", GOLD_PANEL, "topleft", 10, rowTopY(rowIndex) + 1)
end

local function anchorGoldRowName(nameWin, rowIndex, xOffset, width)
	if not DoesWindowExist(nameWin) then
		return
	end
	WindowClearAnchors(nameWin)
	WindowAddAnchor(nameWin, "topleft", GOLD_PANEL, "topleft", xOffset or 26, rowTopY(rowIndex))
	WindowSetDimensions(nameWin, width or GOLD_NAME_W, NAME_LABEL_H)
end

local function anchorGoldRowMoney(moneyWin, rowIndex)
	if not DoesWindowExist(moneyWin) then
		return
	end
	WindowClearAnchors(moneyWin)
	WindowAddAnchor(moneyWin, "topright", GOLD_PANEL, "topright", -10, rowTopY(rowIndex))
	WindowSetDimensions(moneyWin, GOLD_MONEY_W, NAME_LABEL_H)
end

local function hideAllGoldRows()
	for i = 1, MAX_GOLD_ROWS do
		resetGoldRow(goldRowWindows(i))
	end
end

function Tips.HideGoldPanel()
	hideAllGoldRows()
	if DoesWindowExist(GOLD_PANEL) then
		WindowSetShowing(GOLD_PANEL, false)
	end
	m_moneyTooltipVisible = false
end

local function anchorRowIcon(iconWin, rowIndex)
	if not DoesWindowExist(iconWin) then
		return
	end
	WindowClearAnchors(iconWin)
	WindowAddAnchor(iconWin, "topleft", PANEL, "topleft", 10, rowTopY(rowIndex) + 1)
end

local function anchorRowName(nameWin, rowIndex, xOffset, width)
	if not DoesWindowExist(nameWin) then
		return
	end
	WindowClearAnchors(nameWin)
	WindowAddAnchor(nameWin, "topleft", PANEL, "topleft", xOffset or 26, rowTopY(rowIndex))
	WindowSetDimensions(nameWin, width or NAME_LABEL_W, NAME_LABEL_H)
end

local function anchorRowCount(countWin, rowIndex)
	if not DoesWindowExist(countWin) then
		return
	end
	WindowClearAnchors(countWin)
	WindowAddAnchor(countWin, "topright", PANEL, "topright", -10, rowTopY(rowIndex))
	WindowSetDimensions(countWin, COUNT_LABEL_W, NAME_LABEL_H)
end

local function setLabelColor(labelName, r, g, b)
	if not DoesWindowExist(labelName) then
		return
	end
	LabelSetTextColor(labelName, r or 255, g or 255, b or 255)
end

local function hideAllRows()
	for i = 1, MAX_ROWS do
		resetRow(rowWindows(i))
	end
end

function Tips.HideItemPanel()
	m_panelAttached = false
	if DoesWindowExist(PANEL) then
		WindowSetShowing(PANEL, false)
	end
	hideAllRows()
end

local function resolveAnchorWindow(fallback)
	local target = fallback
	if type(Tooltips) ~= "table" then
		return target
	end
	pcall(function()
		if type(Tooltips.GetLeftmostOrRightmostTooltip) == "function" then
			local t = Tooltips.GetLeftmostOrRightmostTooltip(PANEL, math.max)
			if type(t) == "string" and DoesWindowExist(t) then
				target = t
			end
		elseif Tooltips.curTooltipWindow and DoesWindowExist(Tooltips.curTooltipWindow) then
			target = Tooltips.curTooltipWindow
		end
	end)
	return target
end

local function formatItemCount(entry, includeBank)
	local bag = tonumber(entry.bagCount) or 0
	local total = tonumber(entry.totalCount) or bag
	if includeBank and total > bag then
		return tostring(bag) .. " (" .. tostring(total) .. ")"
	end
	return tostring(bag)
end

local function toWString(value)
	if value == nil then
		return L""
	end
	if type(value) == "wstring" then
		return value
	end
	if type(towstring) == "function" then
		return towstring(tostring(value))
	end
	return value
end

-- When a faction has more than MAX_CHARS_PER_FACTION entries, keep the top (N-1)
-- by sort order and pin the logged-in character to the last visible row if needed.
local function limitFactionEntries(sortedRows)
	if type(sortedRows) ~= "table" or #sortedRows <= MAX_CHARS_PER_FACTION then
		return sortedRows
	end
	local selfIndex = nil
	for i = 1, #sortedRows do
		if sortedRows[i].isSelf then
			selfIndex = i
			break
		end
	end
	if selfIndex == nil or selfIndex <= MAX_CHARS_PER_FACTION then
		local limited = {}
		for i = 1, MAX_CHARS_PER_FACTION do
			limited[i] = sortedRows[i]
		end
		return limited
	end
	local limited = {}
	for i = 1, MAX_CHARS_PER_FACTION - 1 do
		limited[i] = sortedRows[i]
	end
	limited[MAX_CHARS_PER_FACTION] = sortedRows[selfIndex]
	return limited
end

local function buildFactionDisplayRows(rows, dataApi, valueField)
	if dataApi == nil or type(dataApi.PartitionByFaction) ~= "function" then
		local flat = {}
		for i = 1, #rows do
			flat[i] = { kind = "entry", entry = rows[i] }
		end
		return flat
	end

	local localRows, otherRows = dataApi.PartitionByFaction(rows, valueField)
	localRows = limitFactionEntries(localRows)
	otherRows = limitFactionEntries(otherRows)
	local displayRows = {}
	for i = 1, #localRows do
		displayRows[#displayRows + 1] = { kind = "entry", entry = localRows[i] }
	end
	if #localRows > 0 and #otherRows > 0 then
		local otherFaction = otherRows[1].faction or "destruction"
		local label = L"-- "
		if type(dataApi.GetFactionDisplayName) == "function" then
			label = label .. dataApi.GetFactionDisplayName(otherFaction)
		else
			label = label .. toWString(otherFaction)
		end
		label = label .. L" --"
		displayRows[#displayRows + 1] = { kind = "separator", label = label }
	end
	for i = 1, #otherRows do
		displayRows[#displayRows + 1] = { kind = "entry", entry = otherRows[i] }
	end
	return displayRows
end

local function sumMoneyRows(rows)
	local total = 0
	for i = 1, #rows do
		total = total + (tonumber(rows[i].money) or 0)
	end
	return total
end

local function buildGoldDisplayRows(rows, dataApi, hasBothFactions, totalBrass)
	local localRows, otherRows = {}, {}
	if dataApi ~= nil and type(dataApi.PartitionByFaction) == "function" then
		localRows, otherRows = dataApi.PartitionByFaction(rows, "money")
	else
		localRows = rows
	end

	local localTotal = sumMoneyRows(localRows)
	local otherTotal = sumMoneyRows(otherRows)
	localRows = limitFactionEntries(localRows)
	otherRows = limitFactionEntries(otherRows)

	local displayRows = {}
	for i = 1, #localRows do
		displayRows[#displayRows + 1] = { kind = "entry", entry = localRows[i] }
	end
	if hasBothFactions then
		displayRows[#displayRows + 1] = { kind = "total", money = localTotal }
		local otherFaction = otherRows[1] and otherRows[1].faction or "destruction"
		local label = L"-- "
		if type(dataApi.GetFactionDisplayName) == "function" then
			label = label .. dataApi.GetFactionDisplayName(otherFaction)
		else
			label = label .. toWString(otherFaction)
		end
		label = label .. L" --"
		displayRows[#displayRows + 1] = { kind = "separator", label = label }
		for i = 1, #otherRows do
			displayRows[#displayRows + 1] = { kind = "entry", entry = otherRows[i] }
		end
		displayRows[#displayRows + 1] = { kind = "total", money = otherTotal }
	elseif #rows > 1 then
		displayRows[#displayRows + 1] = { kind = "total", money = totalBrass }
	end
	return displayRows
end

local function formatMoneyBrass(brass)
	brass = tonumber(brass) or 0
	local gold, silver, copper
	if type(MoneyFrame) == "table" and type(MoneyFrame.ConvertBrassToCurrency) == "function" then
		gold, silver, copper = MoneyFrame.ConvertBrassToCurrency(brass)
	else
		gold = math.floor(brass / 10000)
		silver = math.floor((brass - gold * 10000) / 100)
		copper = math.mod(brass, 100)
	end
	local goldIcon = (type(MoneyFrame) == "table" and MoneyFrame.GoldIcon) or L"g"
	local silverIcon = (type(MoneyFrame) == "table" and MoneyFrame.SilverIcon) or L"s"
	local brassIcon = (type(MoneyFrame) == "table" and MoneyFrame.BrassIcon) or L"b"
	-- Always show all three coins; pad silver/brass to 2 digits for column alignment.
	return towstring(gold or 0) .. L" " .. goldIcon .. L" "
		.. wstring.format(L"%02d", silver or 0) .. L" " .. silverIcon .. L" "
		.. wstring.format(L"%02d", copper or 0) .. L" " .. brassIcon
end

function Tips.ShowItemPanel(itemData, anchorWin)
	local settings = getSettings()
	if settings.enabled ~= true then
		Tips.HideItemPanel()
		return
	end
	if type(itemData) ~= "table" then
		Tips.HideItemPanel()
		return
	end
	local uid = tonumber(itemData.uniqueID) or 0
	if uid == 0 then
		Tips.HideItemPanel()
		return
	end
	if not DoesWindowExist(PANEL) then
		return
	end

	local dataApi = getData()
	if dataApi == nil or type(dataApi.GetItemCounts) ~= "function" then
		Tips.HideItemPanel()
		return
	end

	local rows = dataApi.GetItemCounts(uid)
	if #rows == 0 then
		Tips.HideItemPanel()
		return
	end
	local displayRows = buildFactionDisplayRows(rows, dataApi, "totalCount")
	while #displayRows > MAX_ROWS do
		table.remove(displayRows)
	end

	LabelSetText(PANEL_TITLE, L"Inventory")
	hideAllRows()

	local includeBank = settings.includeBank == true
	for i = 1, #displayRows do
		local displayRow = displayRows[i]
		local nameWin, countWin, iconWin = rowWindows(i)
		if displayRow.kind == "separator" then
			if DoesWindowExist(iconWin) then
				WindowSetShowing(iconWin, false)
			end
			if DoesWindowExist(nameWin) then
				anchorRowName(nameWin, i, 10, 200)
				LabelSetText(nameWin, displayRow.label or L"")
				setLabelColor(nameWin, 160, 160, 160)
				WindowSetShowing(nameWin, true)
			end
			if DoesWindowExist(countWin) then
				WindowSetShowing(countWin, false)
			end
		else
			local entry = displayRow.entry
			local nameText = entry.plainName or entry.displayName or "?"
			local countText = formatItemCount(entry, includeBank)
			local r, g, b = 255, 255, 255
			if entry.isSelf then
				r, g, b = 0, 200, 0
			end
			anchorRowIcon(iconWin, i)
			setCareerIcon(iconWin, entry.careerLine)
			anchorRowName(nameWin, i)
			anchorRowCount(countWin, i)
			if DoesWindowExist(nameWin) then
				LabelSetText(nameWin, toWString(nameText))
				setLabelColor(nameWin, r, g, b)
				WindowSetShowing(nameWin, true)
			end
			if DoesWindowExist(countWin) then
				LabelSetText(countWin, towstring(countText))
				setLabelColor(countWin, r, g, b)
				WindowSetShowing(countWin, true)
			end
		end
	end

	local height = HEADER_HEIGHT + (#displayRows * ROW_HEIGHT) + PANEL_PAD
	local width = 220
	pcall(WindowSetDimensions, PANEL, width, height)

	local anchorTarget = resolveAnchorWindow(anchorWin)
	if type(Tooltips) == "table" and type(Tooltips.AddExtraWindow) == "function" then
		pcall(Tooltips.AddExtraWindow, PANEL, anchorTarget, itemData)
		m_panelAttached = true
	else
		WindowClearAnchors(PANEL)
		pcall(WindowAddAnchor, PANEL, "topright", anchorTarget, "topleft", 0, 0)
		WindowSetShowing(PANEL, true)
		m_panelAttached = true
	end
end

function Tips.HideMoneyTooltip()
	if m_moneyTooltipVisible and type(Tooltips) == "table" and type(Tooltips.ClearTooltip) == "function"
		and Tooltips.curTooltipWindow == GOLD_PANEL then
		pcall(Tooltips.ClearTooltip)
		return
	end
	Tips.HideGoldPanel()
end

local function resolveMoneyAnchor(preferred)
	if type(preferred) == "string" and preferred ~= "" and DoesWindowExist(preferred) then
		return preferred
	end
	if DoesWindowExist("CustomUIAltTrackerMoneyHover") then
		return "CustomUIAltTrackerMoneyHover"
	end
	if DoesWindowExist("EA_Window_BackpackMoney") then
		return "EA_Window_BackpackMoney"
	end
	return nil
end

local function anchorGoldPanelRight()
	local anchorTarget = "EA_Window_BackpackMoney"
	if not DoesWindowExist(anchorTarget) or not DoesWindowExist(GOLD_PANEL) then
		return false
	end
	WindowClearAnchors(GOLD_PANEL)
	WindowAddAnchor(GOLD_PANEL, "topright", anchorTarget, "topleft", 4, 0)
	return true
end

function Tips.ShowMoneyTooltip(anchorWin)
	local settings = getSettings()
	if settings.enabled ~= true or settings.trackGold ~= true then
		return
	end
	local dataApi = getData()
	if dataApi == nil or type(dataApi.GetAllGold) ~= "function" then
		return
	end
	if type(dataApi.SnapshotMoney) == "function" then
		pcall(dataApi.SnapshotMoney)
	end
	if not DoesWindowExist(GOLD_PANEL) then
		return
	end

	local rows, totalBrass = dataApi.GetAllGold()
	if #rows == 0 then
		return
	end

	local localRows, otherRows = dataApi.PartitionByFaction(rows, "money")
	local hasBothFactions = #localRows > 0 and #otherRows > 0
	local displayRows = buildGoldDisplayRows(rows, dataApi, hasBothFactions, totalBrass)
	while #displayRows > MAX_GOLD_ROWS do
		table.remove(displayRows)
	end

	local anchor = resolveMoneyAnchor(anchorWin)
	if anchor == nil then
		return
	end

	if type(Tooltips) == "table" and type(Tooltips.CreateCustomTooltip) == "function" then
		Tooltips.CreateCustomTooltip(anchor, GOLD_PANEL)
	else
		WindowSetShowing(GOLD_PANEL, true)
	end

	LabelSetText(GOLD_PANEL_TITLE, L"Gold Across Characters")
	hideAllGoldRows()

	for i = 1, #displayRows do
		local displayRow = displayRows[i]
		local nameWin, moneyWin, iconWin = goldRowWindows(i)
		if displayRow.kind == "separator" then
			if DoesWindowExist(iconWin) then
				WindowSetShowing(iconWin, false)
			end
			if DoesWindowExist(nameWin) then
				anchorGoldRowName(nameWin, i, 10, 250)
				LabelSetText(nameWin, displayRow.label or L"")
				setLabelColor(nameWin, 160, 160, 160)
				WindowSetShowing(nameWin, true)
			end
			if DoesWindowExist(moneyWin) then
				WindowSetShowing(moneyWin, false)
			end
		elseif displayRow.kind == "total" then
			if DoesWindowExist(iconWin) then
				WindowSetShowing(iconWin, false)
			end
			local r, g, b = 255, 255, 255
			anchorGoldRowName(nameWin, i, 26, GOLD_NAME_W)
			anchorGoldRowMoney(moneyWin, i)
			if DoesWindowExist(nameWin) then
				LabelSetText(nameWin, L"Total:")
				setLabelColor(nameWin, r, g, b)
				WindowSetShowing(nameWin, true)
			end
			if DoesWindowExist(moneyWin) then
				LabelSetText(moneyWin, formatMoneyBrass(displayRow.money))
				setLabelColor(moneyWin, r, g, b)
				WindowSetShowing(moneyWin, true)
			end
		else
			local entry = displayRow.entry
			local nameText = entry.plainName or entry.displayName or "?"
			local r, g, b = 255, 255, 255
			if entry.isSelf then
				r, g, b = 0, 200, 0
			end
			anchorGoldRowIcon(iconWin, i)
			setCareerIcon(iconWin, entry.careerLine)
			anchorGoldRowName(nameWin, i)
			anchorGoldRowMoney(moneyWin, i)
			if DoesWindowExist(nameWin) then
				LabelSetText(nameWin, toWString(nameText))
				setLabelColor(nameWin, r, g, b)
				WindowSetShowing(nameWin, true)
			end
			if DoesWindowExist(moneyWin) then
				LabelSetText(moneyWin, formatMoneyBrass(entry.money))
				setLabelColor(moneyWin, r, g, b)
				WindowSetShowing(moneyWin, true)
			end
		end
	end

	local height = HEADER_HEIGHT + (#displayRows * ROW_HEIGHT) + PANEL_PAD
	pcall(WindowSetDimensions, GOLD_PANEL, GOLD_PANEL_W, height)
	anchorGoldPanelRight()

	pcall(function()
		if Window and Window.Layers and Window.Layers.OVERLAY then
			WindowSetLayer(GOLD_PANEL, Window.Layers.OVERLAY)
		end
		WindowSetShowing(GOLD_PANEL, true)
	end)

	m_moneyTooltipVisible = true
end

function Tips.RefreshMoneyTooltipIfVisible()
	if not m_moneyTooltipVisible then
		return
	end
	if SystemData and SystemData.MouseOverWindow
		and SystemData.MouseOverWindow.name == "CustomUIAltTrackerMoneyHover" then
		Tips.ShowMoneyTooltip("CustomUIAltTrackerMoneyHover")
	end
end

function Tips.InstallHooks()
	if m_hooksInstalled then
		return
	end
	if type(Tooltips) ~= "table" then
		return
	end

	if type(Tooltips.CreateItemTooltip) == "function" then
		m_origCreate = Tooltips.CreateItemTooltip
		Tooltips.CreateItemTooltip = function(itemData, ...)
			local win = m_origCreate(itemData, ...)
			pcall(Tips.ShowItemPanel, itemData, win)
			return win
		end
	end

	if type(Tooltips.ClearTooltip) == "function" then
		m_origClear = Tooltips.ClearTooltip
		Tooltips.ClearTooltip = function(...)
			pcall(Tips.HideItemPanel)
			pcall(Tips.HideGoldPanel)
			m_moneyTooltipVisible = false
			if m_origClear then
				return m_origClear(...)
			end
		end
	end

	m_hooksInstalled = true
end

function Tips.RemoveHooks()
	if not m_hooksInstalled then
		return
	end
	if m_origCreate and type(Tooltips) == "table" then
		Tooltips.CreateItemTooltip = m_origCreate
	end
	if m_origClear and type(Tooltips) == "table" then
		Tooltips.ClearTooltip = m_origClear
	end
	m_origCreate = nil
	m_origClear = nil
	m_hooksInstalled = false
	Tips.HideItemPanel()
	Tips.HideGoldPanel()
end

function Tips.EnsureWindows()
	if type(CreateWindow) ~= "function" or type(DoesWindowExist) ~= "function" then
		return
	end
	if not DoesWindowExist(PANEL) then
		CustomUI.TryCallQuiet("AltTracker.CreateItemPanel", CreateWindow, PANEL, false)
	end
	if not DoesWindowExist("CustomUIAltTrackerMoneyHover") then
		CustomUI.TryCallQuiet("AltTracker.CreateMoneyHover", CreateWindow, "CustomUIAltTrackerMoneyHover", false)
	end
	if not DoesWindowExist(GOLD_PANEL) then
		CustomUI.TryCallQuiet("AltTracker.CreateGoldPanel", CreateWindow, GOLD_PANEL, false)
	end
end

function Tips.SyncMoneyHover(show)
	local hover = "CustomUIAltTrackerMoneyHover"
	if not DoesWindowExist(hover) then
		return
	end
	if show == true and DoesWindowExist("EA_Window_BackpackMoney") then
		pcall(function()
			local w, h = WindowGetDimensions("EA_Window_BackpackMoney")
			if type(w) == "number" and type(h) == "number" and w > 0 and h > 0 then
				WindowSetDimensions(hover, w, h)
			end
			WindowClearAnchors(hover)
			WindowAddAnchor(hover, "topleft", "EA_Window_BackpackMoney", "topleft", 0, 0)
		end)
	end
	if type(WindowSetShowing) == "function" then
		WindowSetShowing(hover, show == true)
	end
end
