CustomUISettingsWindowTabKillTracker = {}

CustomUISettingsWindowTabKillTracker.contentsName = "SWTabKillTrackerContentsScrollChild"

-- Same options as stock SettingsWindowTabChat.ChatFadeTime (minutes).
CustomUISettingsWindowTabKillTracker.VisTimeMinutes = { 1, 2, 3, 4, 5 }

local function EnsureKillTrackerSettings()
	if CustomUI and CustomUI.KillTracker and type(CustomUI.KillTracker.EnsureSettings) == "function" then
		return CustomUI.KillTracker.EnsureSettings()
	end
	CustomUI.Settings = CustomUI.Settings or { Components = {} }
	if type(CustomUI.Settings.KillTracker) ~= "table" then
		CustomUI.Settings.KillTracker = {}
	end
	return CustomUI.Settings.KillTracker
end

local function ApplyKillTrackerSettings()
	if CustomUI and CustomUI.KillTracker and type(CustomUI.KillTracker.OnSettingsChanged) == "function" then
		CustomUI.KillTracker.OnSettingsChanged()
	end
end

local function GetChatFonts()
	if CustomUI and CustomUI.KillTracker and CustomUI.KillTracker.Window and type(CustomUI.KillTracker.Window.GetChatFonts) == "function" then
		return CustomUI.KillTracker.Window.GetChatFonts()
	end
	if type(ChatSettings) == "table" and type(ChatSettings.Fonts) == "table" then
		return ChatSettings.Fonts
	end
	return {}
end

local function FontShownName(entry)
	if not entry then
		return L""
	end
	if entry.shownName ~= nil then
		if type(entry.shownName) == "wstring" then
			return entry.shownName
		end
		return towstring(tostring(entry.shownName))
	end
	return towstring(tostring(entry.fontName or ""))
end

local function VisTimeLabel(minutes)
	minutes = tonumber(minutes) or 1
	if type(GetStringFormat) == "function" and StringTables and StringTables.Default and StringTables.Default.LABEL_X_MIN then
		local ok, text = pcall(GetStringFormat, StringTables.Default.LABEL_X_MIN, { minutes })
		if ok and text ~= nil then
			return text
		end
	end
	return towstring(minutes) .. L" min"
end

local function SyncFontCombo()
	local c = CustomUISettingsWindowTabKillTracker.contentsName
	local w = c .. "DisplayFont"
	if not DoesWindowExist(w) then
		return
	end
	local fonts = GetChatFonts()
	ComboBoxClearMenuItems(w)
	for i = 1, #fonts do
		ComboBoxAddMenuItem(w, FontShownName(fonts[i]))
	end
	local s = EnsureKillTrackerSettings()
	local want = s.fontName
	if CustomUI and CustomUI.KillTracker and CustomUI.KillTracker.Window and type(CustomUI.KillTracker.Window.ResolveFontName) == "function" then
		want = CustomUI.KillTracker.Window.ResolveFontName()
	end
	local selected = 6 -- Myriad Pro - Small
	for i = 1, #fonts do
		if fonts[i] and fonts[i].fontName == want then
			selected = i
			break
		end
	end
	if #fonts > 0 then
		ComboBoxSetSelectedMenuItem(w, selected)
	end
end

local function SyncVisTimeCombo()
	local c = CustomUISettingsWindowTabKillTracker.contentsName
	local w = c .. "DisplayVisTime"
	if not DoesWindowExist(w) then
		return
	end
	ComboBoxClearMenuItems(w)
	local opts = CustomUISettingsWindowTabKillTracker.VisTimeMinutes
	for i = 1, #opts do
		ComboBoxAddMenuItem(w, VisTimeLabel(opts[i]))
	end
	local s = EnsureKillTrackerSettings()
	local want = tonumber(s.visibleTimeMinutes) or 5
	local selected = 5
	for i = 1, #opts do
		if opts[i] == want then
			selected = i
			break
		end
	end
	ComboBoxSetSelectedMenuItem(w, selected)
end

local function RowsSliderPosFromCount(n)
	n = tonumber(n) or 10
	if n < 1 then
		n = 1
	end
	if n > 20 then
		n = 20
	end
	return (n - 1) / 19
end

local function RowsCountFromSliderPos(pos)
	pos = tonumber(pos) or 0.5
	local n = math.floor(pos * 19 + 1.5)
	if n < 1 then
		n = 1
	end
	if n > 20 then
		n = 20
	end
	return n
end

function CustomUISettingsWindowTabKillTracker.Initialize()
	local c = CustomUISettingsWindowTabKillTracker.contentsName
	LabelSetText(c .. "GeneralTitle", L"General")
	LabelSetText(c .. "GeneralKillTrackerEnabledLabel", L"Enabled")
	ButtonSetCheckButtonFlag(c .. "GeneralKillTrackerEnabledButton", true)

	LabelSetText(c .. "DisplayTitle", L"Display")
	LabelSetText(c .. "DisplayFontLabel", L"Font")
	if type(GetString) == "function" and StringTables and StringTables.Default and StringTables.Default.LABEL_VISIBLE_TIME then
		LabelSetText(c .. "DisplayVisTimeLabel", GetString(StringTables.Default.LABEL_VISIBLE_TIME))
	else
		LabelSetText(c .. "DisplayVisTimeLabel", L"Visible Time")
	end
	LabelSetText(c .. "DisplayMaxRowsLabel", L"Max visible rows")
	LabelSetText(c .. "DisplayCareerIconsLabel", L"Career icons")
	LabelSetText(c .. "DisplayAbilityIconsLabel", L"Ability icons")
	LabelSetText(c .. "DisplayKillCountLabel", L"Kill / death counts")
	LabelSetText(c .. "DisplayZoneLabel", L"Zone (open RvR)")

	ButtonSetCheckButtonFlag(c .. "DisplayCareerIconsButton", true)
	ButtonSetCheckButtonFlag(c .. "DisplayAbilityIconsButton", true)
	ButtonSetCheckButtonFlag(c .. "DisplayKillCountButton", true)
	ButtonSetCheckButtonFlag(c .. "DisplayZoneButton", true)

	SyncFontCombo()
	SyncVisTimeCombo()
end

function CustomUISettingsWindowTabKillTracker.UpdateSettings()
	local c = CustomUISettingsWindowTabKillTracker.contentsName
	ButtonSetPressedFlag(
		c .. "GeneralKillTrackerEnabledButton",
		CustomUI.IsComponentEnabled("KillTracker")
	)

	local s = EnsureKillTrackerSettings()
	SyncFontCombo()
	SyncVisTimeCombo()
	if DoesWindowExist(c .. "DisplayMaxRows") then
		SliderBarSetCurrentPosition(c .. "DisplayMaxRows", RowsSliderPosFromCount(s.maxVisibleRows))
	end
	ButtonSetPressedFlag(c .. "DisplayCareerIconsButton", s.showCareerIcons ~= false)
	ButtonSetPressedFlag(c .. "DisplayAbilityIconsButton", s.showAbilityIcons ~= false)
	ButtonSetPressedFlag(c .. "DisplayKillCountButton", s.showKillCount ~= false)
	ButtonSetPressedFlag(c .. "DisplayZoneButton", s.showZone ~= false)
end

function CustomUISettingsWindowTabKillTracker.ApplyCurrent()
	local c = CustomUISettingsWindowTabKillTracker.contentsName
	local enabled = ButtonGetPressedFlag(c .. "GeneralKillTrackerEnabledButton")
	CustomUI.SetComponentEnabled("KillTracker", enabled)

	local s = EnsureKillTrackerSettings()
	local fonts = GetChatFonts()
	if DoesWindowExist(c .. "DisplayFont") and #fonts > 0 then
		local idx = ComboBoxGetSelectedMenuItem(c .. "DisplayFont")
		idx = tonumber(idx) or 1
		if idx < 1 then
			idx = 1
		end
		if idx > #fonts then
			idx = #fonts
		end
		local ent = fonts[idx]
		if ent and ent.fontName then
			s.fontName = ent.fontName
		end
	end
	if DoesWindowExist(c .. "DisplayVisTime") then
		local opts = CustomUISettingsWindowTabKillTracker.VisTimeMinutes
		local idx = ComboBoxGetSelectedMenuItem(c .. "DisplayVisTime")
		idx = tonumber(idx) or 5
		if idx < 1 then
			idx = 1
		end
		if idx > #opts then
			idx = #opts
		end
		s.visibleTimeMinutes = opts[idx]
	end
	if DoesWindowExist(c .. "DisplayMaxRows") then
		s.maxVisibleRows = RowsCountFromSliderPos(SliderBarGetCurrentPosition(c .. "DisplayMaxRows"))
	end
	s.showCareerIcons = ButtonGetPressedFlag(c .. "DisplayCareerIconsButton") == true
	s.showAbilityIcons = ButtonGetPressedFlag(c .. "DisplayAbilityIconsButton") == true
	s.showKillCount = ButtonGetPressedFlag(c .. "DisplayKillCountButton") == true
	s.showZone = ButtonGetPressedFlag(c .. "DisplayZoneButton") == true
	s.replaceChatKills = false

	ApplyKillTrackerSettings()
end

function CustomUISettingsWindowTabKillTracker.ResetSettings()
end

function CustomUISettingsWindowTabKillTracker.OnToggleEnabled()
	EA_LabelCheckButton.Toggle()
end

function CustomUISettingsWindowTabKillTracker.OnToggleCareerIcons()
	EA_LabelCheckButton.Toggle()
end

function CustomUISettingsWindowTabKillTracker.OnToggleAbilityIcons()
	EA_LabelCheckButton.Toggle()
end

function CustomUISettingsWindowTabKillTracker.OnToggleKillCount()
	EA_LabelCheckButton.Toggle()
end

function CustomUISettingsWindowTabKillTracker.OnToggleZone()
	EA_LabelCheckButton.Toggle()
end

function CustomUISettingsWindowTabKillTracker.OnFontChanged()
end

function CustomUISettingsWindowTabKillTracker.OnVisTimeChanged()
end

function CustomUISettingsWindowTabKillTracker.OnMaxRowsChanged()
end
