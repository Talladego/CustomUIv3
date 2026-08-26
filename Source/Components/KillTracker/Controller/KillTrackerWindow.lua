----------------------------------------------------------------
-- CustomUI.KillTracker.Window — zone-score LayoutEditor base + click-through feed above it
----------------------------------------------------------------
if not CustomUI then CustomUI = {} end
CustomUI.KillTracker = CustomUI.KillTracker or {}
CustomUI.KillTracker.Window = CustomUI.KillTracker.Window or {}

local Win = CustomUI.KillTracker.Window

local c_ROOT = "CustomUIKillTrackerWindow"
local c_SCORE = "CustomUIKillTrackerScoreWindow"
local c_ROW_TEMPLATE = "CustomUIKillTrackerRow"
local c_ROW_PREFIX = "CustomUIKillTrackerRow"
local c_BASE_ROW_HEIGHT = 28
local c_FEED_PAD = 4 -- inset from the top of the feed
local c_FEED_SCORE_GAP = 8 -- space between the newest kill line and the score bar
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

-- Row children that need explicit alpha (labels ignore parent WindowSetAlpha for glyphs).
local c_ROW_ALPHA_SUFFIXES = {
	"KillerName", "KillerCount", "Text",
	"VictimName", "VictimCount",
	"With", "AbilityName", "ZoneIn", "Zone",
}

local c_SCORE_ALPHA_SUFFIXES = {
	"Zone", "FirstLabel", "FirstCount", "SecondLabel", "SecondCount",
}

local function ForEachRowAlphaTarget(row, fn)
	fn(row)
	for i = 1, #c_ROW_ALPHA_SUFFIXES do
		local child = row .. c_ROW_ALPHA_SUFFIXES[i]
		if DoesWindowExist(child) then
			fn(child)
		end
	end
end

local function GetRootAlpha()
	if DoesWindowExist(c_SCORE) and type(WindowGetAlpha) == "function" then
		local a = tonumber(WindowGetAlpha(c_SCORE))
		if a then
			if a < 0 then
				a = 0
			elseif a > 1 then
				a = 1
			end
			return a
		end
	end
	return 1
end

--- Label glyphs do not inherit LayoutEditor window opacity; copy it onto FontAlpha.
local function ApplyTextOpacity(force)
	local alpha = GetRootAlpha()
	if force ~= true and Win._appliedFontAlpha == alpha then
		return
	end
	Win._appliedFontAlpha = alpha
	if type(WindowSetFontAlpha) ~= "function" then
		return
	end
	for i = 1, Win._rowCount do
		local row = c_ROW_PREFIX .. tostring(i)
		if DoesWindowExist(row) then
			ForEachRowAlphaTarget(row, function(win)
				WindowSetFontAlpha(win, alpha)
			end)
		end
	end
	if DoesWindowExist(c_SCORE) then
		WindowSetFontAlpha(c_SCORE, alpha)
		for i = 1, #c_SCORE_ALPHA_SUFFIXES do
			local child = c_SCORE .. c_SCORE_ALPHA_SUFFIXES[i]
			if DoesWindowExist(child) then
				WindowSetFontAlpha(child, alpha)
			end
		end
	end
end

--- Full child window alpha on relayout; text uses LayoutEditor opacity via FontAlpha.
local function EnsureRowOpaque(row)
	local fontAlpha = GetRootAlpha()
	ForEachRowAlphaTarget(row, function(win)
		if type(WindowStopAlphaAnimation) == "function" then
			CustomUI.TryCallQuiet("KillTracker.StopAlpha", WindowStopAlphaAnimation, win)
		end
		if type(WindowSetAlpha) == "function" then
			WindowSetAlpha(win, 1)
		end
		if type(WindowSetFontAlpha) == "function" then
			WindowSetFontAlpha(win, fontAlpha)
		end
	end)
end

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

--- Unique stamp so rapid kills never share the same addedAt (oldest expires first).
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

--- Size label to full text width; keep a shared row height so chained labels
--- do not sit on different vertical centers (short words looked staggered).
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
	local tw = 0
	if type(LabelGetTextDimensions) == "function" then
		tw = LabelGetTextDimensions(labelName)
	end
	tw = tonumber(tw) or 0
	if tw < 1 then
		tw = 1
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
			WindowSetDimensions(zoneInLabel, 1, rowH or 28)
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
			WindowSetDimensions(zoneLabel, 1, rowH or 28)
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

local function LocalRealmIsDestruction()
	local realms = GameData and GameData.Realm
	local realm = GameData and GameData.Player and GameData.Player.realm
	if type(realms) == "table" and realms.DESTRUCTION ~= nil then
		return realm == realms.DESTRUCTION
	end
	return tonumber(realm) == 2
end

local function FactionRgb(isOrder)
	local Format = CustomUI.KillTracker.Format
	if isOrder then
		if Format and type(Format.GetOrderRgb) == "function" then
			local rgb = Format.GetOrderRgb()
			if type(rgb) == "table" then
				return rgb[1] or 0, rgb[2] or 148, rgb[3] or 225
			end
		end
		return 0, 148, 225
	end
	if Format and type(Format.GetDestroRgb) == "function" then
		local rgb = Format.GetDestroRgb()
		if type(rgb) == "table" then
			return rgb[1] or 255, rgb[2] or 39, rgb[3] or 39
		end
	end
	return 255, 39, 39
end

local c_SCORE_COUNT_DIGITS = L"0000"

--- Width of a 4-digit column at the current feed font (cached until font changes).
local function ScoreCountColumnWidth(measureLabel, rowH)
	local font = FontName()
	local cached = tonumber(Win._scoreCountWidth)
	if cached and cached > 0 and Win._scoreCountFont == font then
		return cached
	end
	if not DoesWindowExist(measureLabel) then
		return 36
	end
	ApplyLabelFont(measureLabel)
	if type(WindowSetDimensions) == "function" then
		WindowSetDimensions(measureLabel, c_MEASURE_WIDTH, rowH)
	end
	LabelSetText(measureLabel, c_SCORE_COUNT_DIGITS)
	if type(WindowForceProcessAnchors) == "function" then
		CustomUI.TryCallQuiet("KillTracker.ScoreCount.Force", WindowForceProcessAnchors, measureLabel)
	end
	local tw = 36
	if type(LabelGetTextDimensions) == "function" then
		tw = tonumber(LabelGetTextDimensions(measureLabel)) or tw
	end
	if tw < 16 then
		tw = 16
	end
	Win._scoreCountWidth = tw + 4
	Win._scoreCountFont = font
	return Win._scoreCountWidth
end

local function SetScoreCountLabel(labelName, count, columnW, rowH)
	if not DoesWindowExist(labelName) then
		return
	end
	ApplyLabelFont(labelName)
	if type(LabelSetTextAlign) == "function" then
		CustomUI.TryCallQuiet("KillTracker.ScoreCount.Align", LabelSetTextAlign, labelName, "rightcenter")
	end
	if type(WindowSetDimensions) == "function" then
		WindowSetDimensions(labelName, columnW, rowH)
	end
	LabelSetText(labelName, towstring(count))
	LabelSetTextColor(labelName, 255, 255, 255)
	WindowSetShowing(labelName, true)
end

--- Zone score row: "<Zone>: Order Kills: xx Destro Kills: xx" (local realm first).
--- This window is the LayoutEditor base; always shown while KillTracker is enabled.
local function ApplyScoreRow(width, rowH)
	if not DoesWindowExist(c_SCORE) then
		return 0
	end
	rowH = rowH or RowHeight()

	local orderKills, destroKills = 0, 0
	local Session = CustomUI.KillTracker.Session
	if Session and type(Session.GetZoneScore) == "function" then
		orderKills, destroKills = Session.GetZoneScore()
	end
	orderKills = tonumber(orderKills) or 0
	destroKills = tonumber(destroKills) or 0

	width = tonumber(width) or Win._width or c_DEFAULT_WIDTH
	if type(WindowSetDimensions) == "function" then
		WindowSetDimensions(c_SCORE, math.max(width, 1), rowH)
	end
	WindowSetShowing(c_SCORE, true)

	local zoneLabel = c_SCORE .. "Zone"
	local firstLabel = c_SCORE .. "FirstLabel"
	local firstCount = c_SCORE .. "FirstCount"
	local secondLabel = c_SCORE .. "SecondLabel"
	local secondCount = c_SCORE .. "SecondCount"
	local columnW = ScoreCountColumnWidth(firstCount, rowH)

	local zoneName = L""
	local Format = CustomUI.KillTracker.Format
	if Format and type(Format.GetMapZoneName) == "function" then
		zoneName = Format.GetMapZoneName()
	end
	if zoneName == nil or zoneName == L"" then
		zoneName = L"Zone"
	end

	local firstIsOrder = not LocalRealmIsDestruction()
	local firstKills = firstIsOrder and orderKills or destroKills
	local secondKills = firstIsOrder and destroKills or orderKills
	Win._scoreFirstIsOrder = firstIsOrder

	local fitLabels = { zoneLabel, firstLabel, secondLabel }
	for i = 1, #fitLabels do
		if DoesWindowExist(fitLabels[i]) and type(WindowSetDimensions) == "function" then
			WindowSetDimensions(fitLabels[i], c_MEASURE_WIDTH, rowH)
		end
		ApplyLabelFont(fitLabels[i])
	end

	if DoesWindowExist(zoneLabel) then
		LabelSetText(zoneLabel, towstring(zoneName) .. L": ")
		LabelSetTextColor(zoneLabel, 255, 255, 255)
		FitLabel(zoneLabel, rowH)
		LabelSetTextColor(zoneLabel, 255, 255, 255)
	end

	if DoesWindowExist(firstLabel) then
		if firstIsOrder then
			LabelSetText(firstLabel, L"Order Kills: ")
		else
			LabelSetText(firstLabel, L"Destro Kills: ")
		end
		local r, g, b = FactionRgb(firstIsOrder)
		LabelSetTextColor(firstLabel, r, g, b)
		FitLabel(firstLabel, rowH)
		LabelSetTextColor(firstLabel, r, g, b)
	end

	SetScoreCountLabel(firstCount, firstKills, columnW, rowH)

	if DoesWindowExist(secondLabel) then
		if firstIsOrder then
			LabelSetText(secondLabel, L"Destro Kills: ")
		else
			LabelSetText(secondLabel, L"Order Kills: ")
		end
		local r, g, b = FactionRgb(not firstIsOrder)
		LabelSetTextColor(secondLabel, r, g, b)
		FitLabel(secondLabel, rowH)
		LabelSetTextColor(secondLabel, r, g, b)
	end

	SetScoreCountLabel(secondCount, secondKills, columnW, rowH)

	if type(WindowForceProcessAnchors) == "function" then
		CustomUI.TryCallQuiet("KillTracker.ForceScoreAnchors", WindowForceProcessAnchors, c_SCORE)
	end
	-- Feed height no longer includes the score row; it sits above this window.
	return 0
end

local c_TOP_KILLERS_LIMIT = 10

local function ShowFactionKillersTooltip(isOrder)
	if type(Tooltips) ~= "table" or type(Tooltips.CreateTextOnlyTooltip) ~= "function" then
		return
	end

	local anchorWindow = SystemData and SystemData.ActiveWindow and SystemData.ActiveWindow.name
	if anchorWindow == nil or anchorWindow == "" then
		anchorWindow = c_SCORE
	end

	local Session = CustomUI.KillTracker.Session
	local list = {}
	if Session and type(Session.GetTopFactionKillers) == "function" then
		list = Session.GetTopFactionKillers(isOrder == true, c_TOP_KILLERS_LIMIT) or {}
	end

	local heading = isOrder and L"Top Order Killers" or L"Top Destro Killers"
	local r, g, b = FactionRgb(isOrder == true)

	Tooltips.CreateTextOnlyTooltip(anchorWindow)
	Tooltips.SetTooltipText(1, 1, heading)
	if type(Tooltips.SetTooltipColor) == "function" then
		Tooltips.SetTooltipColor(1, 1, r, g, b)
	elseif type(Tooltips.SetTooltipColorDef) == "function" and Tooltips.COLOR_HEADING then
		Tooltips.SetTooltipColorDef(1, 1, Tooltips.COLOR_HEADING)
	end

	local line = 2
	if #list == 0 then
		Tooltips.SetTooltipText(line, 1, L"No kills recorded yet.")
		line = line + 1
	else
		-- TooltipRow (rows 2+): Col1 left, Col2 center, Col3 right.
		-- Use column 3 so counts sit on the right edge (not Col2, which centers).
		local countCol = Tooltips.COLUMN_RIGHT_LEFT_ALIGN or 3
		for i = 1, #list do
			local row = list[i]
			local name = towstring(row and row.name or L"?")
			local count = tonumber(row and row.count) or 0
			Tooltips.SetTooltipText(line, 1, towstring(i) .. L". " .. name)
			Tooltips.SetTooltipText(line, countCol, towstring(count))
			line = line + 1
		end
	end

	if type(Tooltips.Finalize) == "function" then
		Tooltips.Finalize()
	end
	if type(Tooltips.AnchorTooltip) == "function" then
		if Tooltips.ANCHOR_WINDOW_VARIABLE then
			Tooltips.AnchorTooltip(Tooltips.ANCHOR_WINDOW_VARIABLE)
		else
			Tooltips.AnchorTooltip({
				Point = "top",
				RelativeTo = anchorWindow,
				RelativePoint = "bottom",
				XOffset = 0,
				YOffset = -4,
			})
		end
	end
end

function Win.OnMouseOverFirstScore()
	local firstIsOrder = Win._scoreFirstIsOrder
	if firstIsOrder == nil then
		firstIsOrder = not LocalRealmIsDestruction()
	end
	ShowFactionKillersTooltip(firstIsOrder == true)
end

function Win.OnMouseOverSecondScore()
	local firstIsOrder = Win._scoreFirstIsOrder
	if firstIsOrder == nil then
		firstIsOrder = not LocalRealmIsDestruction()
	end
	ShowFactionKillersTooltip(firstIsOrder ~= true)
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
	if DoesWindowExist(c_SCORE) and type(WindowGetDimensions) == "function" then
		local w = WindowGetDimensions(c_SCORE)
		w = tonumber(w)
		if w and w >= c_MIN_WIDTH then
			Win._width = w
			return w
		end
	end
	return Win._width or c_DEFAULT_WIDTH
end

--- Pin feed topleft feedH pixels above the counter, then set height so it fills
--- down to the score row. SetDimensions-before-anchor grew from an implicit
--- topleft and parked the lines below the counter.
local function GlueFeedAboveScore(width, feedH)
	if not DoesWindowExist(c_ROOT) or not DoesWindowExist(c_SCORE) then
		return
	end
	feedH = math.max(tonumber(feedH) or 1, 1)
	width = math.max(tonumber(width) or 1, 1)
	if type(WindowSetScale) == "function" and type(WindowGetScale) == "function" then
		local scale = WindowGetScale(c_SCORE)
		if scale then
			WindowSetScale(c_ROOT, scale)
		end
	end
	if type(WindowClearAnchors) ~= "function" or type(WindowAddAnchor) ~= "function" then
		return
	end
	WindowClearAnchors(c_ROOT)
	CustomUI.TryCall(
		"KillTracker.GlueFeedTopLeft",
		WindowAddAnchor,
		c_ROOT,
		"topleft",
		c_SCORE,
		"topleft",
		0,
		-feedH
	)
	CustomUI.TryCall(
		"KillTracker.GlueFeedTopRight",
		WindowAddAnchor,
		c_ROOT,
		"topright",
		c_SCORE,
		"topright",
		0,
		-feedH
	)
	if type(WindowSetDimensions) == "function" then
		WindowSetDimensions(c_ROOT, width, feedH)
	end
	if type(WindowForceProcessAnchors) == "function" then
		CustomUI.TryCallQuiet("KillTracker.GlueFeed.Force", WindowForceProcessAnchors, c_ROOT)
	end
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
		Win._scoreCountWidth = nil
		Win._scoreCountFont = nil
	end

	local maxVis = MaxVisible()
	local history = Win._history
	local count = #history
	local settings = EnsureSettings()
	local showFeed = settings.showKillMessages ~= false
	local showCount = 0
	if showFeed then
		showCount = math.min(count, maxVis)
	end
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
			WindowAddAnchor(row, "topleft", c_ROOT, "topleft", c_FEED_PAD, c_FEED_PAD + y)
			WindowSetShowing(row, true)

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
			-- Same kill bag as the killer; do not show death tallies.
			SetCountLabel(victimCountLabel, entry.victimKillCount, settings.showKillCount, rowH)

			local hasAbility = entry.ability and entry.ability ~= L""
			if hasAbility then
				LabelSetText(withLabel, L" with ")
				LabelSetTextColor(withLabel, 255, 255, 255)
				FitLabel(withLabel, rowH)
				WindowSetShowing(withLabel, true)
			else
				LabelSetText(withLabel, L"")
				if type(WindowSetDimensions) == "function" then
					WindowSetDimensions(withLabel, 1, rowH)
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
					WindowSetDimensions(abilityLabel, 1, rowH)
				end
				WindowSetShowing(abilityLabel, false)
			end

			ApplyZoneLabels(zoneInLabel, zoneLabel, entry, settings, rowH)

			if type(WindowForceProcessAnchors) == "function" then
				CustomUI.TryCallQuiet("KillTracker.ForceRowAnchors", WindowForceProcessAnchors, row)
			end

			EnsureRowOpaque(row)
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

	ApplyScoreRow(width, rowH)
	local h = c_FEED_PAD + showCount * rowH + c_FEED_SCORE_GAP
	if showCount <= 0 then
		h = 1
	end
	if DoesWindowExist(c_ROOT) then
		WindowSetShowing(c_ROOT, showCount > 0)
	end
	GlueFeedAboveScore(width, h)
	ApplyTextOpacity(true)
end

function Win.OnResizeEnd()
	ReadRootWidth()
	LayoutRows()
end

function Win.Initialize()
	if not DoesWindowExist(c_SCORE) then
		return
	end
	-- New row template children (count labels); drop any stale row instances.
	Win._laidOutFont = nil
	DestroyAllRows()
	if not Win._layoutRegistered and type(LayoutEditor) == "table" and type(LayoutEditor.RegisterWindow) == "function" then
		LayoutEditor.RegisterWindow(
			c_SCORE,
			L"CustomUI: Kill Tracker",
			L"Zone kill counter. Kill lines grow upward from this row. Move and resize width in Layout Editor.",
			true, -- allowSizeWidth
			false, -- allowSizeHeight (one row; Lua sets height from font)
			true, -- allowHiding
			nil,
			{ "topleft" },
			true, -- neverLockAspect
			{ x = c_MIN_WIDTH, y = c_BASE_ROW_HEIGHT },
			"CustomUI.KillTracker.Window.OnResizeEnd",
			"CustomUI.KillTracker.Window.OnResizeEnd"
		)
		Win._layoutRegistered = true
	end
	if type(LayoutEditor) == "table"
		and type(LayoutEditor.RegisterEditCallback) == "function"
		and not Win._layoutEditCallback
	then
		LayoutEditor.RegisterEditCallback(function(code)
			if LayoutEditor and code == LayoutEditor.EDITING_END then
				LayoutRows()
			end
		end)
		Win._layoutEditCallback = true
	end
	ReadRootWidth()
	if type(LayoutEditor) == "table" and type(LayoutEditor.UserHide) == "function" then
		LayoutEditor.UserHide(c_SCORE)
	else
		WindowSetShowing(c_SCORE, false)
	end
	if DoesWindowExist(c_ROOT) then
		WindowSetShowing(c_ROOT, false)
	end
end

function Win.Show()
	if not DoesWindowExist(c_SCORE) then
		return
	end
	if type(LayoutEditor) == "table" and type(LayoutEditor.UserShow) == "function" then
		LayoutEditor.UserShow(c_SCORE)
	else
		WindowSetShowing(c_SCORE, true)
	end
	LayoutRows()
end

function Win.Hide()
	if DoesWindowExist(c_ROOT) then
		WindowSetShowing(c_ROOT, false)
	end
	if not DoesWindowExist(c_SCORE) then
		return
	end
	if type(LayoutEditor) == "table" and type(LayoutEditor.UserHide) == "function" then
		LayoutEditor.UserHide(c_SCORE)
	else
		WindowSetShowing(c_SCORE, false)
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

--- Remove expired lines from history and relayout (no fade-out animation).
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
	-- LayoutEditor opacity slider only sets WindowSetAlpha; copy it to glyphs.
	ApplyTextOpacity()
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
