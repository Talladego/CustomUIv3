----------------------------------------------------------------
-- CustomUI.KillTracker.Window — transparent LayoutEditor kill feed
----------------------------------------------------------------
if not CustomUI then CustomUI = {} end
CustomUI.KillTracker = CustomUI.KillTracker or {}
CustomUI.KillTracker.Window = CustomUI.KillTracker.Window or {}

local Win = CustomUI.KillTracker.Window

local c_ROOT = "CustomUIKillTrackerWindow"
local c_ROW_TEMPLATE = "CustomUIKillTrackerRow"
local c_ROW_PREFIX = "CustomUIKillTrackerRow"
local c_BASE_ROW_HEIGHT = 28
local c_BASE_ICON = 24
local c_CAREER_ATLAS = 32 -- EA_Image_CareerIcon / stock career slices
local c_ABILITY_ATLAS = 64 -- ability/buff GetIconData slices (SCT / BuffTracker)
local c_HISTORY_CAP = 50
local c_DEFAULT_WIDTH = 720
local c_MIN_WIDTH = 360
local c_MIN_HEIGHT = 40
local c_DEFAULT_FONT = "font_clear_small" -- Myriad Pro - Small (stock chat default)

-- Fallback if ChatSettings.Fonts is unavailable (same order/names as ea_chatwindow).
local c_CHAT_FONT_FALLBACK = {
	{ fontName = "font_journal_body", shownName = "Cronos Pro - Small", id = 1 },
	{ fontName = "font_journal_text", shownName = "Cronos Pro - Medium", id = 2 },
	{ fontName = "font_default_text_small", shownName = "Age of Reckoning - Small", id = 3 },
	{ fontName = "font_default_text_large", shownName = "Age of Reckoning - Large", id = 4 },
	{ fontName = "font_clear_tiny", shownName = "Myriad Pro - Very Small", id = 5 },
	{ fontName = "font_clear_small", shownName = "Myriad Pro - Small", id = 6 },
	{ fontName = "font_clear_medium", shownName = "Myriad Pro - Medium", id = 7 },
	{ fontName = "font_clear_large", shownName = "Myriad Pro - Large", id = 8 },
	{ fontName = "font_clear_small_bold", shownName = "Myriad Pro SemiExt - Small", id = 9 },
	{ fontName = "font_clear_medium_bold", shownName = "Myriad Pro SemiExt - Medium", id = 10 },
	{ fontName = "font_clear_large_bold", shownName = "Myriad Pro SemiExt - Large", id = 11 },
}

Win._history = Win._history or {}
Win._rowCount = 0
Win._layoutRegistered = false
Win._width = c_DEFAULT_WIDTH
Win._laidOutFont = nil
Win._clock = Win._clock or 0
Win._lastStamp = Win._lastStamp or 0

local c_MEASURE_WIDTH = 4000
local c_FADE_LEAD_SECONDS = 3 -- engine ease-out over the last N seconds of that message's life

-- Children that need their own alpha anim (labels ignore parent WindowSetAlpha for glyphs).
local c_ROW_FADE_SUFFIXES = {
	"KillerCareer", "KillerName", "KillerCount", "Text",
	"VictimCareer", "VictimName", "VictimCount",
	"AbilityIcon", "With", "AbilityName", "ZoneIn", "Zone",
}

local function EnsureSettings()
	return CustomUI.KillTracker.GetSettings and CustomUI.KillTracker.GetSettings() or {}
end

local function VisibleSeconds()
	local s = EnsureSettings()
	local mins = tonumber(s.visibleTimeMinutes) or 5
	if mins < 1 then
		mins = 1
	end
	if mins > 5 then
		mins = 5
	end
	return mins * 60
end

--- Monotonic-ish time for per-message lifetimes.
local function Now()
	if type(GetGameTime) == "function" then
		local ok, t = CustomUI.TryCallQuiet("KillTracker.GetGameTime", GetGameTime)
		if ok and type(t) == "number" then
			return t
		end
	end
	return Win._clock or 0
end

--- Unique stamp so rapid kills never share the same addedAt (oldest fades first).
local function NextStamp()
	local t = Now()
	local last = tonumber(Win._lastStamp) or 0
	if t <= last then
		t = last + 0.05
	end
	Win._lastStamp = t
	return t
end

local function EntryExpiresAt(entry)
	if not entry then
		return Now()
	end
	local exp = tonumber(entry.expiresAt)
	if exp then
		return exp
	end
	local added = tonumber(entry.addedAt) or Now()
	return added + VisibleSeconds()
end

local function FadeAnimType()
	local t = Window and Window.AnimationType
	return t and (t.EASE_OUT or t.SINGLE_NO_RESET) or nil
end

local function ForEachRowFadeTarget(row, fn)
	fn(row)
	for i = 1, #c_ROW_FADE_SUFFIXES do
		local child = row .. c_ROW_FADE_SUFFIXES[i]
		if DoesWindowExist(child) then
			fn(child)
		end
	end
end

local function SetRowAlphaStatic(row, alpha)
	alpha = tonumber(alpha) or 1
	if alpha < 0 then
		alpha = 0
	elseif alpha > 1 then
		alpha = 1
	end
	ForEachRowFadeTarget(row, function(win)
		if type(WindowStopAlphaAnimation) == "function" then
			CustomUI.TryCallQuiet("KillTracker.StopAlpha", WindowStopAlphaAnimation, win)
		end
		if type(WindowSetAlpha) == "function" then
			WindowSetAlpha(win, alpha)
		end
		if type(WindowSetFontAlpha) == "function" then
			WindowSetFontAlpha(win, alpha)
		end
	end)
end

local function StartRowFadeOut(row, startAlpha, duration)
	local animType = FadeAnimType()
	startAlpha = tonumber(startAlpha) or 1
	duration = tonumber(duration) or c_FADE_LEAD_SECONDS
	if startAlpha < 0.01 then
		startAlpha = 0.01
	elseif startAlpha > 1 then
		startAlpha = 1
	end
	if duration < 0.05 then
		duration = 0.05
	end
	if type(WindowStartAlphaAnimation) ~= "function" or not animType then
		SetRowAlphaStatic(row, startAlpha)
		return false
	end
	ForEachRowFadeTarget(row, function(win)
		if type(WindowStopAlphaAnimation) == "function" then
			CustomUI.TryCallQuiet("KillTracker.StopAlpha", WindowStopAlphaAnimation, win)
		end
		-- Seed font alpha so glyphs participate; engine anim then eases window alpha.
		if type(WindowSetFontAlpha) == "function" then
			WindowSetFontAlpha(win, startAlpha)
		end
		if type(WindowSetAlpha) == "function" then
			WindowSetAlpha(win, startAlpha)
		end
		CustomUI.TryCallQuiet(
			"KillTracker.StartAlpha",
			WindowStartAlphaAnimation,
			win,
			animType,
			startAlpha,
			0,
			duration,
			false,
			0,
			0
		)
	end)
	return true
end

--- Opaque until the fade window; then one-shot engine ease-out (not per-frame SetAlpha).
local function ApplyRowFade(row, entry, now)
	if not entry or not DoesWindowExist(row) then
		return
	end
	now = now or Now()
	local remain = EntryExpiresAt(entry) - now
	if remain <= 0 then
		SetRowAlphaStatic(row, 0)
		entry._fadeAnimRow = nil
		entry._fadeAnimActive = false
		return
	end
	if remain >= c_FADE_LEAD_SECONDS then
		if entry._fadeAnimActive or entry._fadeAnimRow then
			SetRowAlphaStatic(row, 1)
		else
			-- Cheap reset when already opaque (new/remapped row).
			if type(WindowSetAlpha) == "function" then
				WindowSetAlpha(row, 1)
			end
			if type(WindowSetFontAlpha) == "function" then
				WindowSetFontAlpha(row, 1)
			end
			ForEachRowFadeTarget(row, function(win)
				if win ~= row then
					if type(WindowSetAlpha) == "function" then
						WindowSetAlpha(win, 1)
					end
					if type(WindowSetFontAlpha) == "function" then
						WindowSetFontAlpha(win, 1)
					end
				end
			end)
		end
		entry._fadeAnimActive = false
		entry._fadeAnimRow = nil
		return
	end

	-- Mid-fade: (re)start only when first entering fade or the entry moved to another row.
	if entry._fadeAnimActive and entry._fadeAnimRow == row then
		return
	end
	local startAlpha = remain / c_FADE_LEAD_SECONDS
	if not entry._fadeAnimActive then
		-- Fresh entry into the fade window — full ease from opaque when close to the lead edge.
		if remain > c_FADE_LEAD_SECONDS * 0.9 then
			startAlpha = 1
		end
	end
	StartRowFadeOut(row, startAlpha, remain)
	entry._fadeAnimActive = true
	entry._fadeAnimRow = row
end

function Win.GetChatFonts()
	if type(ChatSettings) == "table" and type(ChatSettings.Fonts) == "table" and #ChatSettings.Fonts > 0 then
		return ChatSettings.Fonts
	end
	return c_CHAT_FONT_FALLBACK
end

function Win.FindFontEntry(fontName)
	local fonts = Win.GetChatFonts()
	for i = 1, #fonts do
		local e = fonts[i]
		if e and e.fontName == fontName then
			return e, i
		end
	end
	return nil, nil
end

function Win.ResolveFontName()
	local s = EnsureSettings()
	local name = s.fontName
	if type(name) == "string" and name ~= "" then
		local ent = Win.FindFontEntry(name)
		if ent then
			return name
		end
	end
	-- Migrate legacy fontSize (1..5) onto nearby chat fonts.
	local legacy = tonumber(s.fontSize)
	if legacy then
		local map = {
			"font_clear_tiny",
			"font_clear_small",
			"font_clear_medium",
			"font_clear_large",
			"font_default_text_large",
		}
		local mapped = map[legacy]
		if mapped then
			return mapped
		end
	end
	return c_DEFAULT_FONT
end

local function FontName()
	return Win.ResolveFontName()
end

local function FontScale()
	local ent = Win.FindFontEntry(FontName())
	local id = ent and tonumber(ent.id) or 6
	-- Rough row/icon scale from chat font id (1..11).
	return 0.82 + id * 0.035
end

local function RowHeight()
	return math.floor(c_BASE_ROW_HEIGHT * FontScale() + 0.5)
end

local function IconDraw()
	return math.floor(c_BASE_ICON * FontScale() + 0.5)
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

local function ApplyLabelFont(labelName)
	if not DoesWindowExist(labelName) then
		return
	end
	if type(LabelSetFont) == "function" and WindowUtils and WindowUtils.FONT_DEFAULT_TEXT_LINESPACING then
		CustomUI.TryCallQuiet(
			"KillTracker.LabelSetFont",
			LabelSetFont,
			labelName,
			FontName(),
			WindowUtils.FONT_DEFAULT_TEXT_LINESPACING
		)
	end
end

--- Size label to full text width.
--- LabelGetTextDimensions returns the *clipped* window size if the label is already
--- too narrow — that caused progressive truncation after font changes. Always expand
--- to a measure canvas first, then shrink to the measured text.
local function FitLabel(labelName, rowH)
	if not DoesWindowExist(labelName) then
		return
	end
	local h = rowH or 28
	if type(WindowSetDimensions) == "function" then
		WindowSetDimensions(labelName, c_MEASURE_WIDTH, h)
	end
	if type(WindowForceProcessAnchors) == "function" then
		CustomUI.TryCallQuiet("KillTracker.FitLabel.Force", WindowForceProcessAnchors, labelName)
	end
	local tw, th = 0, h
	if type(LabelGetTextDimensions) == "function" then
		tw, th = LabelGetTextDimensions(labelName)
	end
	tw = tonumber(tw) or 0
	th = tonumber(th) or 0
	if tw < 1 then
		tw = 1
	end
	if th > h then
		h = th
	end
	if type(WindowSetDimensions) == "function" then
		WindowSetDimensions(labelName, tw + 4, h)
	end
end

local function DestroyAllRows()
	for i = 1, Win._rowCount do
		local name = c_ROW_PREFIX .. tostring(i)
		if DoesWindowExist(name) and type(DestroyWindow) == "function" then
			CustomUI.TryCallQuiet("KillTracker.DestroyRow", DestroyWindow, name)
		end
	end
	Win._rowCount = 0
end

local c_COUNT_RGB = { 175, 175, 175 } -- grey, slightly darker than white

local function SetCountLabel(labelName, count, enabled, rowH)
	if not DoesWindowExist(labelName) then
		return
	end
	ApplyLabelFont(labelName)
	count = tonumber(count) or 0
	if enabled == false or count <= 0 then
		LabelSetText(labelName, L"")
		if type(WindowSetDimensions) == "function" then
			WindowSetDimensions(labelName, 1, rowH or 28)
		end
		WindowSetShowing(labelName, false)
		return
	end
	if type(WindowSetDimensions) == "function" then
		WindowSetDimensions(labelName, c_MEASURE_WIDTH, rowH or 28)
	end
	LabelSetText(labelName, L"[" .. towstring(count) .. L"]")
	LabelSetTextColor(labelName, c_COUNT_RGB[1], c_COUNT_RGB[2], c_COUNT_RGB[3])
	WindowSetShowing(labelName, true)
	FitLabel(labelName, rowH)
end

local function ApplyZoneLabels(zoneInLabel, zoneLabel, entry, settings, rowH)
	local showZone = settings.showZone ~= false and entry.zone and entry.zone ~= L""
	if DoesWindowExist(zoneInLabel) then
		if showZone then
			LabelSetText(zoneInLabel, L" in ")
			LabelSetTextColor(zoneInLabel, 255, 255, 255)
			WindowSetShowing(zoneInLabel, true)
			FitLabel(zoneInLabel, rowH)
		else
			LabelSetText(zoneInLabel, L"")
			if type(WindowSetDimensions) == "function" then
				WindowSetDimensions(zoneInLabel, 1, 1)
			end
			WindowSetShowing(zoneInLabel, false)
		end
	end
	if not DoesWindowExist(zoneLabel) then
		return
	end
	if not showZone then
		LabelSetText(zoneLabel, L"")
		if type(WindowSetDimensions) == "function" then
			WindowSetDimensions(zoneLabel, 1, 1)
		end
		WindowSetShowing(zoneLabel, false)
		return
	end
	local r, g, b = 255, 255, 255
	local Format = CustomUI.KillTracker.Format
	if Format and type(Format.GetZoneTextRgb) == "function" then
		local zoneRgb = Format.GetZoneTextRgb(entry.zone)
		if type(zoneRgb) == "table" then
			r = zoneRgb[1] or r
			g = zoneRgb[2] or g
			b = zoneRgb[3] or b
		end
	end
	LabelSetText(zoneLabel, towstring(entry.zone))
	LabelSetTextColor(zoneLabel, r, g, b)
	WindowSetShowing(zoneLabel, true)
	FitLabel(zoneLabel, rowH)
	LabelSetTextColor(zoneLabel, r, g, b)
end

local function SetIcon(windowName, iconId, atlasSize)
	if not DoesWindowExist(windowName) then
		return
	end
	atlasSize = tonumber(atlasSize) or c_CAREER_ATLAS
	iconId = tonumber(iconId)
	if not iconId or iconId <= 0 or type(GetIconData) ~= "function" then
		if type(WindowSetDimensions) == "function" then
			WindowSetDimensions(windowName, 1, 1)
		end
		WindowSetShowing(windowName, false)
		return
	end
	local texture, x, y = GetIconData(iconId)
	if not texture or texture == "" or texture == "icon000000" then
		if type(WindowSetDimensions) == "function" then
			WindowSetDimensions(windowName, 1, 1)
		end
		WindowSetShowing(windowName, false)
		return
	end
	DynamicImageSetTexture(windowName, texture, x, y)
	if type(DynamicImageSetTextureDimensions) == "function" then
		DynamicImageSetTextureDimensions(windowName, atlasSize, atlasSize)
	end
	local draw = IconDraw()
	if type(WindowSetDimensions) == "function" then
		WindowSetDimensions(windowName, draw, draw)
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

local function ReadRootWidth()
	if DoesWindowExist(c_ROOT) and type(WindowGetDimensions) == "function" then
		local w = WindowGetDimensions(c_ROOT)
		w = tonumber(w)
		if w and w >= c_MIN_WIDTH then
			Win._width = w
			return w
		end
	end
	return Win._width or c_DEFAULT_WIDTH
end

local function LayoutRows()
	if not DoesWindowExist(c_ROOT) then
		return
	end

	-- Fresh row widgets when font changes so LabelSetFont / dimensions cannot stick.
	local font = FontName()
	if Win._laidOutFont ~= font then
		DestroyAllRows()
		Win._laidOutFont = font
	end

	local maxVis = MaxVisible()
	local history = Win._history
	local count = #history
	local showCount = math.min(count, maxVis)
	local rowH = RowHeight()
	local width = ReadRootWidth()

	local startIdx = count - showCount + 1
	if startIdx < 1 then
		startIdx = 1
	end

	for i = 1, maxVis do
		local row = EnsureRow(i)
		WindowClearAnchors(row)
		-- Wide enough that child labels are not clipped while measuring / laying out.
		if type(WindowSetDimensions) == "function" then
			WindowSetDimensions(row, math.max(width, c_MEASURE_WIDTH), rowH)
		end
		if i <= showCount then
			local entry = history[startIdx + i - 1]
			local y = (i - 1) * rowH
			WindowAddAnchor(row, "topleft", c_ROOT, "topleft", 4, 4 + y)
			WindowSetShowing(row, true)

			local settings = EnsureSettings()
			SetIcon(row .. "KillerCareer", settings.showCareerIcons ~= false and entry.killerCareerIcon or nil, c_CAREER_ATLAS)
			SetIcon(row .. "VictimCareer", settings.showCareerIcons ~= false and entry.victimCareerIcon or nil, c_CAREER_ATLAS)
			SetIcon(row .. "AbilityIcon", settings.showAbilityIcons ~= false and entry.abilityIconNum or nil, c_ABILITY_ATLAS)

			local killerLabel = row .. "KillerName"
			local killerCountLabel = row .. "KillerCount"
			local victimLabel = row .. "VictimName"
			local victimCountLabel = row .. "VictimCount"
			local textLabel = row .. "Text"
			local withLabel = row .. "With"
			local abilityLabel = row .. "AbilityName"
			local zoneInLabel = row .. "ZoneIn"
			local zoneLabel = row .. "Zone"

			-- Expand → font → text → measure → shrink (see FitLabel).
			if type(WindowSetDimensions) == "function" then
				WindowSetDimensions(killerLabel, c_MEASURE_WIDTH, rowH)
				WindowSetDimensions(victimLabel, c_MEASURE_WIDTH, rowH)
				WindowSetDimensions(textLabel, c_MEASURE_WIDTH, rowH)
				WindowSetDimensions(withLabel, c_MEASURE_WIDTH, rowH)
				WindowSetDimensions(abilityLabel, c_MEASURE_WIDTH, rowH)
				if DoesWindowExist(zoneInLabel) then
					WindowSetDimensions(zoneInLabel, c_MEASURE_WIDTH, rowH)
				end
				if DoesWindowExist(zoneLabel) then
					WindowSetDimensions(zoneLabel, c_MEASURE_WIDTH, rowH)
				end
			end

			ApplyLabelFont(killerLabel)
			ApplyLabelFont(victimLabel)
			ApplyLabelFont(textLabel)
			ApplyLabelFont(withLabel)
			ApplyLabelFont(abilityLabel)
			if DoesWindowExist(zoneInLabel) then
				ApplyLabelFont(zoneInLabel)
			end
			if DoesWindowExist(zoneLabel) then
				ApplyLabelFont(zoneLabel)
			end

			LabelSetText(killerLabel, towstring(entry.killer or L""))
			if entry.killerRgb then
				LabelSetTextColor(killerLabel, entry.killerRgb[1], entry.killerRgb[2], entry.killerRgb[3])
			else
				LabelSetTextColor(killerLabel, 255, 255, 255)
			end
			FitLabel(killerLabel, rowH)
			SetCountLabel(killerCountLabel, entry.killCount, settings.showKillCount, rowH)

			LabelSetText(textLabel, L" killed ")
			LabelSetTextColor(textLabel, 255, 255, 255)
			FitLabel(textLabel, rowH)

			LabelSetText(victimLabel, towstring(entry.victim or L""))
			if entry.victimRgb then
				LabelSetTextColor(victimLabel, entry.victimRgb[1], entry.victimRgb[2], entry.victimRgb[3])
			else
				LabelSetTextColor(victimLabel, 255, 255, 255)
			end
			FitLabel(victimLabel, rowH)
			SetCountLabel(victimCountLabel, entry.deathCount, settings.showKillCount, rowH)

			local hasAbility = entry.ability and entry.ability ~= L""
			if hasAbility then
				LabelSetText(withLabel, L" with ")
				LabelSetTextColor(withLabel, 255, 255, 255)
				FitLabel(withLabel, rowH)
				WindowSetShowing(withLabel, true)
			else
				LabelSetText(withLabel, L"")
				if type(WindowSetDimensions) == "function" then
					WindowSetDimensions(withLabel, 1, 1)
				end
				WindowSetShowing(withLabel, false)
			end

			if hasAbility then
				LabelSetText(abilityLabel, towstring(entry.ability))
				LabelSetTextColor(abilityLabel, 255, 180, 40)
				WindowSetShowing(abilityLabel, true)
				FitLabel(abilityLabel, rowH)
			else
				LabelSetText(abilityLabel, L"")
				if type(WindowSetDimensions) == "function" then
					WindowSetDimensions(abilityLabel, 1, 1)
				end
				WindowSetShowing(abilityLabel, false)
			end

			ApplyZoneLabels(zoneInLabel, zoneLabel, entry, settings, rowH)

			if type(WindowForceProcessAnchors) == "function" then
				CustomUI.TryCallQuiet("KillTracker.ForceRowAnchors", WindowForceProcessAnchors, row)
			end

			-- Relayout re-seeds widgets; allow fade anim to restart from remaining time.
			entry._fadeAnimActive = false
			entry._fadeAnimRow = nil
			ApplyRowFade(row, entry, Now())
		else
			WindowSetShowing(row, false)
		end
	end

	for i = maxVis + 1, Win._rowCount do
		local row = c_ROW_PREFIX .. tostring(i)
		if DoesWindowExist(row) then
			WindowSetShowing(row, false)
		end
	end

	local h = 8 + showCount * rowH
	if h < c_MIN_HEIGHT then
		h = c_MIN_HEIGHT
	end
	-- Preserve LayoutEditor width; only grow/shrink height to fit rows.
	WindowSetDimensions(c_ROOT, width, h)
end

function Win.OnResizeEnd()
	ReadRootWidth()
	LayoutRows()
end

function Win.Initialize()
	if not DoesWindowExist(c_ROOT) then
		return
	end
	-- New row template children (count labels); drop any stale row instances.
	Win._laidOutFont = nil
	DestroyAllRows()
	if not Win._layoutRegistered and type(LayoutEditor) == "table" and type(LayoutEditor.RegisterWindow) == "function" then
		LayoutEditor.RegisterWindow(
			c_ROOT,
			L"CustomUI: Kill Tracker",
			L"Transparent RvR kill feed. Move and resize in Layout Editor.",
			true, -- allowSizeWidth
			true, -- allowSizeHeight
			true, -- allowHiding
			nil,
			nil,
			true, -- neverLockAspect
			{ x = c_MIN_WIDTH, y = c_MIN_HEIGHT },
			"CustomUI.KillTracker.Window.OnResizeEnd",
			nil
		)
		Win._layoutRegistered = true
	end
	ReadRootWidth()
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
	-- Fresh copy so shared tables cannot overwrite another line's lifetime.
	local entry = {}
	for k, v in pairs(model) do
		entry[k] = v
	end
	local stamp = NextStamp()
	entry.addedAt = stamp
	entry.expiresAt = stamp + VisibleSeconds()
	Win._history[#Win._history + 1] = entry
	while #Win._history > c_HISTORY_CAP do
		table.remove(Win._history, 1)
	end
	LayoutRows()
end

--- Per-message expiry: oldest lines fade and drop first; newer ones stay opaque.
function Win.OnUpdate(timePassed)
	local dt = tonumber(timePassed) or 0
	if dt < 0 then
		dt = 0
	end
	Win._clock = (Win._clock or 0) + dt

	if not CustomUI.IsComponentEnabled or not CustomUI.IsComponentEnabled("KillTracker") then
		return
	end

	local now = Now()
	local removed = false
	-- Remove expired from front-biased history (oldest first).
	for i = #Win._history, 1, -1 do
		local entry = Win._history[i]
		if now >= EntryExpiresAt(entry) then
			table.remove(Win._history, i)
			removed = true
		end
	end

	if removed then
		LayoutRows()
		return
	end

	if #Win._history == 0 then
		return
	end

	-- Kick off one-shot ease-out when a line enters the fade window; do not
	-- stomp alpha every frame (that was the choppy look).
	local maxVis = MaxVisible()
	local count = #Win._history
	local showCount = math.min(count, maxVis)
	local startIdx = count - showCount + 1
	if startIdx < 1 then
		startIdx = 1
	end
	for i = 1, showCount do
		local entry = Win._history[startIdx + i - 1]
		local row = c_ROW_PREFIX .. tostring(i)
		if DoesWindowExist(row) and entry then
			ApplyRowFade(row, entry, now)
		end
	end
end

function Win.OnSettingsChanged()
	-- Re-stamp expiry from each message's own addedAt using the new visible time.
	local vis = VisibleSeconds()
	local now = Now()
	for i = 1, #Win._history do
		local entry = Win._history[i]
		if entry then
			local added = tonumber(entry.addedAt) or now
			entry.expiresAt = added + vis
		end
	end
	Win._laidOutFont = nil
	if CustomUI.IsComponentEnabled and CustomUI.IsComponentEnabled("KillTracker") then
		Win.Show()
	else
		Win.Hide()
	end
end

function Win.Reflow()
	Win._laidOutFont = nil
	LayoutRows()
end
