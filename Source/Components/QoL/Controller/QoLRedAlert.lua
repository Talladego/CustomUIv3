----------------------------------------------------------------
-- CustomUI.QoL.RedAlert — low-HP screen-edge vignette + center alert
----------------------------------------------------------------
if not CustomUI then CustomUI = {} end
CustomUI.QoL = CustomUI.QoL or {}
CustomUI.QoL.RedAlert = CustomUI.QoL.RedAlert or {}

local RA = CustomUI.QoL.RedAlert

RA.THRESHOLD_PERCENTS = { 25, 50, 75, 100 }

local c_FLASH_WINDOW = "CustomUIQoLRedAlertFlash"
local c_FLASH_DURATION = 1.5
local c_FLASH_START_ALPHA = 0.0
local c_FLASH_END_ALPHA = 1.0
local c_DAMAGE_ALERT_COLOR = { r = 255, g = 0, b = 0 }

local c_MSG_WINDOW = "CustomUIQoLRedAlertMessage"
local c_MSG_LABEL = "CustomUIQoLRedAlertMessageText"
local c_MSG_FADE_IN = 0.5
local c_MSG_DISPLAY = 3.5
local c_MSG_FADE_OUT = 1.5
local c_MSG_LIFE = c_MSG_DISPLAY + c_MSG_FADE_OUT
local c_MSG_COLOR = { r = 206, g = 44, b = 44 }
local c_MSG_FONT = "font_alert_outline_giant"
local c_MSG_DEFAULT_TEXT = L"LOW HEALTH"

local m_eventsRegistered = false
local m_flashTimer = 0
local m_wasBelowThreshold = false
local m_prevHitPoints = 1
local m_msgTimer = 0
local m_msgFading = false
local m_msgActive = false

local function getSettings()
	return CustomUI.QoL.EnsureSettings().redAlert
end

local function isFeatureEnabled()
	local s = getSettings()
	return s.enabled == true
end

local function SnapThresholdPercent(value)
	local t = tonumber(value) or 50
	local best, bestDist = 50, math.huge
	for _, pct in ipairs(RA.THRESHOLD_PERCENTS) do
		local dist = math.abs(t - pct)
		if dist < bestDist then
			bestDist = dist
			best = pct
		end
	end
	return best
end

function RA.NormalizeSettings(settings)
	if settings.enabled == nil then
		settings.enabled = true
	end
	if settings.thresholdPercent == nil then
		settings.thresholdPercent = 50
	else
		settings.thresholdPercent = SnapThresholdPercent(settings.thresholdPercent)
	end
	if settings.centerMessage == nil then
		settings.centerMessage = true
	end
	return settings
end

local function FlashWindowApiAvailable()
	return type(DoesWindowExist) == "function"
		and DoesWindowExist(c_FLASH_WINDOW)
		and type(WindowSetTintColor) == "function"
		and type(WindowSetShowing) == "function"
		and type(WindowStartAlphaAnimation) == "function"
end

local function EnsureFlashWindow()
	if type(DoesWindowExist) ~= "function" or type(CreateWindow) ~= "function" then
		return false
	end
	if DoesWindowExist(c_FLASH_WINDOW) then
		return true
	end
	local ok = CustomUI.TryCall("QoL.RedAlert.CreateFlash", CreateWindow, c_FLASH_WINDOW, false)
	return ok and DoesWindowExist(c_FLASH_WINDOW)
end

local function MsgWindowApiAvailable()
	return type(DoesWindowExist) == "function"
		and DoesWindowExist(c_MSG_WINDOW)
		and DoesWindowExist(c_MSG_LABEL)
end

local function EnsureMsgWindow()
	if type(DoesWindowExist) ~= "function" or type(CreateWindow) ~= "function" then
		return false
	end
	if DoesWindowExist(c_MSG_WINDOW) then
		return true
	end
	local ok = CustomUI.TryCall("QoL.RedAlert.CreateMessage", CreateWindow, c_MSG_WINDOW, false)
	return ok and DoesWindowExist(c_MSG_WINDOW)
end

local function GetMsgColor()
	if DefaultColor and DefaultColor.AlertTextColors and DefaultColor.AlertTextColors.Red then
		local c = DefaultColor.AlertTextColors.Red
		return c.r or c_MSG_COLOR.r, c.g or c_MSG_COLOR.g, c.b or c_MSG_COLOR.b
	end
	return c_MSG_COLOR.r, c_MSG_COLOR.g, c_MSG_COLOR.b
end

local function GetFontLinespacing()
	if WindowUtils and WindowUtils.FONT_DEFAULT_TEXT_LINESPACING then
		return WindowUtils.FONT_DEFAULT_TEXT_LINESPACING
	end
	return 20
end

local function StopCenterMessage()
	m_msgTimer = 0
	m_msgFading = false
	m_msgActive = false
	if DoesWindowExist(c_MSG_WINDOW) then
		if type(WindowStopAlphaAnimation) == "function" then
			CustomUI.TryCallQuiet("QoL.RedAlert.StopMsgAlpha", WindowStopAlphaAnimation, c_MSG_WINDOW)
		end
		WindowSetShowing(c_MSG_WINDOW, false)
	end
end

local function ShowCenterMessage(text)
	local s = getSettings()
	if s.centerMessage ~= true then
		return
	end
	if not EnsureMsgWindow() or not MsgWindowApiAvailable() then
		return
	end
	local msg = text
	if msg == nil or msg == L"" then
		msg = c_MSG_DEFAULT_TEXT
	elseif type(msg) ~= "wstring" and type(towstring) == "function" then
		msg = towstring(tostring(msg))
	end
	local r, g, b = GetMsgColor()
	LabelSetText(c_MSG_LABEL, msg)
	if type(LabelSetFont) == "function" then
		LabelSetFont(c_MSG_LABEL, c_MSG_FONT, GetFontLinespacing())
	end
	if type(LabelSetTextColor) == "function" then
		LabelSetTextColor(c_MSG_LABEL, r, g, b)
	end
	local animType = Window and Window.AnimationType and Window.AnimationType.SINGLE_NO_RESET
	if animType == nil then
		return
	end
	if type(WindowStopAlphaAnimation) == "function" then
		CustomUI.TryCallQuiet("QoL.RedAlert.RestartMsgAlpha", WindowStopAlphaAnimation, c_MSG_WINDOW)
	end
	if type(WindowSetAlpha) == "function" then
		WindowSetAlpha(c_MSG_WINDOW, 0)
	end
	if type(WindowSetFontAlpha) == "function" then
		WindowSetFontAlpha(c_MSG_WINDOW, 0)
	end
	WindowSetShowing(c_MSG_WINDOW, true)
	WindowStartAlphaAnimation(c_MSG_WINDOW, animType, 0, 1, c_MSG_FADE_IN, true, 0, 0)
	m_msgTimer = 0
	m_msgFading = true
	m_msgActive = true
end

local function TickCenterMessage(timePassed)
	if not m_msgActive or type(timePassed) ~= "number" or timePassed <= 0 then
		return
	end
	m_msgTimer = m_msgTimer + timePassed
	local animType = Window and Window.AnimationType and Window.AnimationType.SINGLE_NO_RESET
	if animType == nil then
		StopCenterMessage()
		return
	end
	if m_msgTimer > c_MSG_FADE_IN and m_msgTimer < c_MSG_DISPLAY and m_msgFading then
		m_msgFading = false
	elseif m_msgTimer > c_MSG_DISPLAY and not m_msgFading then
		WindowStartAlphaAnimation(c_MSG_WINDOW, animType, 1, 0, c_MSG_FADE_OUT, true, 0, 0)
		m_msgFading = true
	elseif m_msgTimer > c_MSG_LIFE and m_msgFading then
		StopCenterMessage()
	end
end

local function ApplyDamageTint()
	if FlashWindowApiAvailable() then
		WindowSetTintColor(c_FLASH_WINDOW, c_DAMAGE_ALERT_COLOR.r, c_DAMAGE_ALERT_COLOR.g, c_DAMAGE_ALERT_COLOR.b)
	end
end

local function StopFlash()
	m_flashTimer = 0
	if DoesWindowExist(c_FLASH_WINDOW) then
		WindowSetShowing(c_FLASH_WINDOW, false)
	end
end

local function StartFlash()
	if not FlashWindowApiAvailable() or m_flashTimer > 0 then
		return
	end
	ApplyDamageTint()
	if type(WindowSetAlpha) == "function" then
		WindowSetAlpha(c_FLASH_WINDOW, c_FLASH_START_ALPHA)
	end
	WindowSetShowing(c_FLASH_WINDOW, true)
	local animType = Window and Window.AnimationType and Window.AnimationType.POP_AND_EASE
	if animType == nil then
		StopFlash()
		return
	end
	WindowStartAlphaAnimation(c_FLASH_WINDOW, animType, c_FLASH_START_ALPHA, c_FLASH_END_ALPHA, c_FLASH_DURATION, true, 0, 0)
	m_flashTimer = c_FLASH_DURATION
end

local function TickFlashCooldown(timePassed)
	if type(timePassed) ~= "number" or timePassed <= 0 or m_flashTimer <= 0 then
		return
	end
	m_flashTimer = m_flashTimer - timePassed
	if m_flashTimer <= 0 then
		StopFlash()
	end
end

local function GetThresholdFraction()
	local p = tonumber(getSettings().thresholdPercent) or 50
	if p < 1 then p = 1 end
	if p > 100 then p = 100 end
	return p / 100
end

local function IsStrictlyBelowThreshold()
	if not GameData or not GameData.Player or not GameData.Player.hitPoints then
		return false
	end
	local hp = GameData.Player.hitPoints
	local maxHp = hp.maximum
	if maxHp == nil or maxHp <= 0 then
		return false
	end
	return (hp.current or 0) / maxHp < GetThresholdFraction()
end

local function ReleaseFlashHold()
	StopFlash()
	StopCenterMessage()
end

local function ResetThresholdLatch()
	m_wasBelowThreshold = false
end

local function SyncFlashHold()
	if not FlashWindowApiAvailable() then
		return
	end
	if not (isFeatureEnabled() and IsStrictlyBelowThreshold()) then
		StopFlash()
	end
end

local function UpdateFlashOnHpChanged()
	if not isFeatureEnabled() then
		ResetThresholdLatch()
		ReleaseFlashHold()
		return
	end
	if not GameData or not GameData.Player or not GameData.Player.hitPoints then
		return
	end
	local hpCur = GameData.Player.hitPoints.current
	local belowNow = IsStrictlyBelowThreshold()
	local crossedInto = belowNow and not m_wasBelowThreshold
	m_wasBelowThreshold = belowNow
	SyncFlashHold()
	if not belowNow then
		return
	end
	local tookDamage = hpCur < m_prevHitPoints
	if hpCur > 0 and (tookDamage or crossedInto) then
		StartFlash()
		ShowCenterMessage(c_MSG_DEFAULT_TEXT)
	end
end

function RA.OnHitPointsUpdated()
	UpdateFlashOnHpChanged()
	if GameData and GameData.Player and GameData.Player.hitPoints then
		m_prevHitPoints = GameData.Player.hitPoints.current
	end
end

function RA.OnPlayerReady()
	EnsureFlashWindow()
	EnsureMsgWindow()
	ApplyDamageTint()
	if GameData and GameData.Player and GameData.Player.hitPoints then
		m_prevHitPoints = GameData.Player.hitPoints.current
	end
	ResetThresholdLatch()
	SyncFlashHold()
end

function RA.RegisterEvents()
	if m_eventsRegistered then
		return
	end
	local e = SystemData.Events
	RegisterEventHandler(e.PLAYER_CUR_HIT_POINTS_UPDATED, "CustomUI.QoL.RedAlert.OnHitPointsUpdated")
	RegisterEventHandler(e.PLAYER_MAX_HIT_POINTS_UPDATED, "CustomUI.QoL.RedAlert.OnHitPointsUpdated")
	RegisterEventHandler(e.LOADING_END, "CustomUI.QoL.RedAlert.OnPlayerReady")
	RegisterEventHandler(e.ENTER_WORLD, "CustomUI.QoL.RedAlert.OnPlayerReady")
	m_eventsRegistered = true
end

function RA.UnregisterEvents()
	if not m_eventsRegistered then
		return
	end
	local e = SystemData.Events
	CustomUI.TryCallQuiet("QoL.RedAlert.UnregCurHp", UnregisterEventHandler, e.PLAYER_CUR_HIT_POINTS_UPDATED, "CustomUI.QoL.RedAlert.OnHitPointsUpdated")
	CustomUI.TryCallQuiet("QoL.RedAlert.UnregMaxHp", UnregisterEventHandler, e.PLAYER_MAX_HIT_POINTS_UPDATED, "CustomUI.QoL.RedAlert.OnHitPointsUpdated")
	CustomUI.TryCallQuiet("QoL.RedAlert.UnregLoading", UnregisterEventHandler, e.LOADING_END, "CustomUI.QoL.RedAlert.OnPlayerReady")
	CustomUI.TryCallQuiet("QoL.RedAlert.UnregEnterWorld", UnregisterEventHandler, e.ENTER_WORLD, "CustomUI.QoL.RedAlert.OnPlayerReady")
	m_eventsRegistered = false
end

function RA.OnUpdate(timePassed)
	if not isFeatureEnabled() then
		return
	end
	TickFlashCooldown(timePassed)
	TickCenterMessage(timePassed)
end

function RA.TestFlash()
	StartFlash()
	ShowCenterMessage(c_MSG_DEFAULT_TEXT)
end

function RA.Initialize()
	EnsureFlashWindow()
	EnsureMsgWindow()
	if FlashWindowApiAvailable() then
		WindowSetShowing(c_FLASH_WINDOW, false)
		ApplyDamageTint()
	end
	if MsgWindowApiAvailable() then
		WindowSetShowing(c_MSG_WINDOW, false)
	end
	m_flashTimer = 0
	StopCenterMessage()
	if GameData and GameData.Player and GameData.Player.hitPoints then
		m_prevHitPoints = GameData.Player.hitPoints.current
	else
		m_prevHitPoints = 1
	end
	ResetThresholdLatch()
end

function RA.Enable()
	if not isFeatureEnabled() then
		return
	end
	RA.RegisterEvents()
	RA.OnPlayerReady()
end

function RA.Disable()
	RA.UnregisterEvents()
	ReleaseFlashHold()
	ResetThresholdLatch()
end

function RA.Shutdown()
	RA.Disable()
end
