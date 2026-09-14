----------------------------------------------------------------
-- CustomUI.QoL.ButtonClickSound — mute UI button click SFX
-- Stock: GameData.Sound.BUTTON_CLICK = 300; mute sets 0.
----------------------------------------------------------------
if not CustomUI then CustomUI = {} end
CustomUI.QoL = CustomUI.QoL or {}
CustomUI.QoL.ButtonClickSound = CustomUI.QoL.ButtonClickSound or {}

local BCS = CustomUI.QoL.ButtonClickSound

local c_STOCK_BUTTON_CLICK = 300
local c_MUTED_BUTTON_CLICK = 0

local m_handlersRegistered = false
local m_active = false

local function isMuteRequested()
	local s = CustomUI.QoL.EnsureSettings()
	return s.muteButtonClickSound == true
end

local function setButtonClickSound(value)
	if type(GameData) ~= "table" or type(GameData.Sound) ~= "table" then
		return false
	end
	GameData.Sound.BUTTON_CLICK = value
	return true
end

function BCS.Apply()
	local mute = isMuteRequested()
	local value = mute and c_MUTED_BUTTON_CLICK or c_STOCK_BUTTON_CLICK
	if setButtonClickSound(value) then
		m_active = mute
	end
end

function BCS.Restore()
	setButtonClickSound(c_STOCK_BUTTON_CLICK)
	m_active = false
end

function BCS.OnWorldReady()
	-- Engine may reset GameData.Sound on load; re-apply mute if still requested.
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
