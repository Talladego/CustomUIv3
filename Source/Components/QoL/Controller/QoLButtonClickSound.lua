----------------------------------------------------------------
-- CustomUI.QoL.ButtonClickSound — mute UI button click SFX
--
-- Stock buttons: Sound.Play(Sound.BUTTON_CLICK) (defaultbutton.xml).
-- soundutils.lua copies GameData.Sound.BUTTON_CLICK (300) into
-- Sound.BUTTON_CLICK once at load — a number snapshot, not a live
-- GameData lookup. Mutating GameData.Sound.BUTTON_CLICK does nothing.
--
-- Working approach (NicoAddon): Sound.BUTTON_CLICK = 0
-- PlaySound(0) is a no-op; unmute restores the stock id (300).
----------------------------------------------------------------
if not CustomUI then CustomUI = {} end
CustomUI.QoL = CustomUI.QoL or {}
CustomUI.QoL.ButtonClickSound = CustomUI.QoL.ButtonClickSound or {}

local BCS = CustomUI.QoL.ButtonClickSound

-- GameData.Sound.BUTTON_CLICK reference id (see GameData.Sound dump).
local c_STOCK_BUTTON_CLICK = 300
local c_MUTED_BUTTON_CLICK = 0

local m_handlersRegistered = false
local m_stockId = c_STOCK_BUTTON_CLICK
local m_stockCaptured = false

local function isMuteRequested()
	local s = CustomUI.QoL.EnsureSettings()
	return s.muteButtonClickSound == true
end

local function captureStockId()
	if m_stockCaptured then
		return
	end
	-- Capture only while still non-zero (after mute, Sound.BUTTON_CLICK is 0).
	if type(Sound) == "table" and type(Sound.BUTTON_CLICK) == "number" and Sound.BUTTON_CLICK > 0 then
		m_stockId = Sound.BUTTON_CLICK
	elseif type(GameData) == "table"
		and type(GameData.Sound) == "table"
		and type(GameData.Sound.BUTTON_CLICK) == "number"
		and GameData.Sound.BUTTON_CLICK > 0
	then
		m_stockId = GameData.Sound.BUTTON_CLICK
	else
		m_stockId = c_STOCK_BUTTON_CLICK
	end
	m_stockCaptured = true
end

local function setSoundButtonClick(value)
	if type(Sound) ~= "table" then
		return false
	end
	Sound.BUTTON_CLICK = value
	return true
end

function BCS.Apply()
	if type(Sound) ~= "table" then
		return
	end
	captureStockId()
	if isMuteRequested() then
		setSoundButtonClick(c_MUTED_BUTTON_CLICK)
	else
		setSoundButtonClick(m_stockId)
	end
end

function BCS.Restore()
	if type(Sound) == "table" then
		-- Prefer last captured stock; fall back to dump id 300.
		setSoundButtonClick(m_stockCaptured and m_stockId or c_STOCK_BUTTON_CLICK)
	end
end

function BCS.OnWorldReady()
	-- Engine / interface reload may reset Sound.*; re-apply mute.
	m_stockCaptured = false
	BCS.Apply()
end

function BCS.RegisterHandlers()
	if m_handlersRegistered then
		return
	end
	local e = SystemData and SystemData.Events
	if type(e) ~= "table" then
		return
	end
	if e.LOADING_END then
		CustomUI.TryCall("QoL.ButtonClickSound.RegLoading", RegisterEventHandler, e.LOADING_END, "CustomUI.QoL.ButtonClickSound.OnWorldReady")
	end
	if e.ENTER_WORLD then
		CustomUI.TryCall("QoL.ButtonClickSound.RegEnterWorld", RegisterEventHandler, e.ENTER_WORLD, "CustomUI.QoL.ButtonClickSound.OnWorldReady")
	end
	if e.INTERFACE_RELOADED then
		CustomUI.TryCallQuiet("QoL.ButtonClickSound.RegReload", RegisterEventHandler, e.INTERFACE_RELOADED, "CustomUI.QoL.ButtonClickSound.OnWorldReady")
	end
	m_handlersRegistered = true
end

function BCS.UnregisterHandlers()
	if not m_handlersRegistered then
		return
	end
	local e = SystemData and SystemData.Events
	if type(e) == "table" then
		if e.LOADING_END then
			CustomUI.TryCallQuiet("QoL.ButtonClickSound.UnregLoading", UnregisterEventHandler, e.LOADING_END, "CustomUI.QoL.ButtonClickSound.OnWorldReady")
		end
		if e.ENTER_WORLD then
			CustomUI.TryCallQuiet("QoL.ButtonClickSound.UnregEnterWorld", UnregisterEventHandler, e.ENTER_WORLD, "CustomUI.QoL.ButtonClickSound.OnWorldReady")
		end
		if e.INTERFACE_RELOADED then
			CustomUI.TryCallQuiet("QoL.ButtonClickSound.UnregReload", UnregisterEventHandler, e.INTERFACE_RELOADED, "CustomUI.QoL.ButtonClickSound.OnWorldReady")
		end
	end
	m_handlersRegistered = false
end

function BCS.Enable()
	BCS.RegisterHandlers()
	BCS.Apply()
end

function BCS.Disable()
	BCS.UnregisterHandlers()
	BCS.Restore()
end

function BCS.Initialize()
end

function BCS.Shutdown()
	BCS.UnregisterHandlers()
	BCS.Restore()
end
