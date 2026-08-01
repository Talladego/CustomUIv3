----------------------------------------------------------------
-- CustomUI.KillTracker.Window — movable kill feed (label rows)
----------------------------------------------------------------
if not CustomUI then CustomUI = {} end
CustomUI.KillTracker = CustomUI.KillTracker or {}
CustomUI.KillTracker.Window = CustomUI.KillTracker.Window or {}

local Win = CustomUI.KillTracker.Window

local c_ROOT = "CustomUIKillTrackerWindow"
local c_ROW_TEMPLATE = "CustomUIKillTrackerRow"
local c_ROW_PREFIX = "CustomUIKillTrackerRow"
local c_ROW_HEIGHT = 28
local c_HISTORY_CAP = 50
local c_ICON_ATLAS = 32
local c_ICON_DRAW = 24

Win._history = Win._history or {}
Win._rowCount = 0
Win._layoutRegistered = false

local function EnsureSettings()
	return CustomUI.KillTracker.GetSettings and CustomUI.KillTracker.GetSettings() or {}
end

local function MaxVisible()
	local s = EnsureSettings()
	local n = tonumber(s.maxVisibleRows) or 10
	if n < 1 then
		n = 1
	end
	if n > 20 then
		n = 20
	end
	return n
end

local function SetIcon(windowName, iconId)
	if not DoesWindowExist(windowName) then
		return
	end
	iconId = tonumber(iconId)
	if not iconId or iconId <= 0 or type(GetIconData) ~= "function" then
		WindowSetShowing(windowName, false)
		return
	end
	local texture, x, y = GetIconData(iconId)
	if not texture or texture == "" or texture == "icon000000" then
		WindowSetShowing(windowName, false)
		return
	end
	DynamicImageSetTexture(windowName, texture, x, y)
	if type(DynamicImageSetTextureDimensions) == "function" then
		DynamicImageSetTextureDimensions(windowName, c_ICON_ATLAS, c_ICON_ATLAS)
	end
	if type(WindowSetDimensions) == "function" then
		WindowSetDimensions(windowName, c_ICON_DRAW, c_ICON_DRAW)
	end
	WindowSetShowing(windowName, true)
end

local function EnsureRow(index)
	local name = c_ROW_PREFIX .. tostring(index)
	if not DoesWindowExist(name) then
		CreateWindowFromTemplate(name, c_ROW_TEMPLATE, c_ROOT)
		Win._rowCount = math.max(Win._rowCount, index)
	end
	return name
end

local function LayoutRows()
	local maxVis = MaxVisible()
	local history = Win._history
	local count = #history
	local showCount = math.min(count, maxVis)

	-- Newest at bottom: take last showCount entries
	local startIdx = count - showCount + 1
	if startIdx < 1 then
		startIdx = 1
	end

	for i = 1, maxVis do
		local row = EnsureRow(i)
		WindowClearAnchors(row)
		if i <= showCount then
			local entry = history[startIdx + i - 1]
			local y = (i - 1) * c_ROW_HEIGHT
			WindowAddAnchor(row, "topleft", c_ROOT, "topleft", 4, 4 + y)
			WindowSetShowing(row, true)

			local settings = EnsureSettings()
			-- Compact: [killerIcon] Killer[k] killed [victimIcon] Victim[d] with [abilityIcon] Ability
			SetIcon(row .. "KillerCareer", settings.showCareerIcons ~= false and entry.killerCareerIcon or nil)
			SetIcon(row .. "VictimCareer", settings.showCareerIcons ~= false and entry.victimCareerIcon or nil)
			SetIcon(row .. "AbilityIcon", settings.showAbilityIcons ~= false and entry.abilityIconNum or nil)

			local killerLabel = row .. "KillerName"
			local victimLabel = row .. "VictimName"
			local textLabel = row .. "Text"

			local killerText = towstring(entry.killer or L"")
			if settings.showKillCount ~= false and entry.killCount and entry.killCount > 0 then
				killerText = killerText .. L"[" .. towstring(entry.killCount) .. L"]"
			end
			LabelSetText(killerLabel, killerText)
			if entry.killerRgb then
				LabelSetTextColor(killerLabel, entry.killerRgb[1], entry.killerRgb[2], entry.killerRgb[3])
			end

			LabelSetText(textLabel, L" killed ")

			local victimText = towstring(entry.victim or L"")
			if settings.showKillCount ~= false and entry.deathCount and entry.deathCount > 0 then
				victimText = victimText .. L"[" .. towstring(entry.deathCount) .. L"]"
			end
			LabelSetText(victimLabel, victimText)
			if entry.victimRgb then
				LabelSetTextColor(victimLabel, entry.victimRgb[1], entry.victimRgb[2], entry.victimRgb[3])
			end

			local ability = L""
			if entry.ability and entry.ability ~= L"" then
				ability = L" with " .. entry.ability
			end
			LabelSetText(row .. "AbilityName", ability)
			LabelSetTextColor(row .. "AbilityName", 255, 180, 40)
		else
			WindowSetShowing(row, false)
		end
	end

	-- Hide unused rows beyond maxVis that may exist from a prior larger setting
	for i = maxVis + 1, Win._rowCount do
		local row = c_ROW_PREFIX .. tostring(i)
		if DoesWindowExist(row) then
			WindowSetShowing(row, false)
		end
	end

	local h = 8 + showCount * c_ROW_HEIGHT
	if h < 40 then
		h = 40
	end
	WindowSetDimensions(c_ROOT, 520, h)
end

function Win.Initialize()
	if not DoesWindowExist(c_ROOT) then
		return
	end
	if not Win._layoutRegistered and type(LayoutEditor) == "table" and type(LayoutEditor.RegisterWindow) == "function" then
		LayoutEditor.RegisterWindow(
			c_ROOT,
			L"CustomUI: Kill Tracker",
			L"RvR Order/Destruction kill feed with career and ability icons.",
			false,
			false,
			true,
			nil
		)
		Win._layoutRegistered = true
	end
	if type(LayoutEditor) == "table" and type(LayoutEditor.UserHide) == "function" then
		LayoutEditor.UserHide(c_ROOT)
	else
		WindowSetShowing(c_ROOT, false)
	end
end

function Win.Show()
	if not DoesWindowExist(c_ROOT) then
		return
	end
	if type(LayoutEditor) == "table" and type(LayoutEditor.UserShow) == "function" then
		LayoutEditor.UserShow(c_ROOT)
	else
		WindowSetShowing(c_ROOT, true)
	end
	LayoutRows()
end

function Win.Hide()
	if not DoesWindowExist(c_ROOT) then
		return
	end
	if type(LayoutEditor) == "table" and type(LayoutEditor.UserHide) == "function" then
		LayoutEditor.UserHide(c_ROOT)
	else
		WindowSetShowing(c_ROOT, false)
	end
end

function Win.Clear()
	for i = #Win._history, 1, -1 do
		Win._history[i] = nil
	end
	LayoutRows()
end

function Win.PushKill(model)
	if type(model) ~= "table" then
		return
	end
	Win._history[#Win._history + 1] = model
	while #Win._history > c_HISTORY_CAP do
		table.remove(Win._history, 1)
	end
	if EnsureSettings().showFeedWindow == true then
		LayoutRows()
	end
end

function Win.OnSettingsChanged()
	local s = EnsureSettings()
	if s.showFeedWindow == true
		and CustomUI.IsComponentEnabled
		and CustomUI.IsComponentEnabled("KillTracker")
	then
		Win.Show()
	else
		Win.Hide()
	end
end
