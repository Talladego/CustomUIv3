----------------------------------------------------------------
-- CustomUI.QoL.RezzAccept — auto-accept resurrection prompts
----------------------------------------------------------------
if not CustomUI then CustomUI = {} end
CustomUI.QoL = CustomUI.QoL or {}
CustomUI.QoL.RezzAccept = CustomUI.QoL.RezzAccept or {}

local Rezz = CustomUI.QoL.RezzAccept
local RESURRECTION_ACCEPT = SystemData.Events.RESURRECTION_ACCEPT
local RESURRECTION_DECLINE = SystemData.Events.RESURRECTION_DECLINE

local m_handlersRegistered = false

local function getSettings()
	return CustomUI.QoL.EnsureSettings().rezzAccept
end

local function isFeatureEnabled()
	local s = getSettings()
	return s.enabled == true
end

local function isResurrectionDialog()
	local dlg = SystemData and SystemData.Dialogs and SystemData.Dialogs.AppDlg
	if not dlg then
		return false
	end
	if dlg.buttonEvent1 == RESURRECTION_ACCEPT or dlg.buttonEvent2 == RESURRECTION_ACCEPT then
		return true
	end
	if dlg.buttonEvent1 == RESURRECTION_DECLINE or dlg.buttonEvent2 == RESURRECTION_DECLINE then
		return true
	end
	return false
end

function Rezz.OnTwoButtonDialog()
	if not isFeatureEnabled() then
		return
	end
	if not isResurrectionDialog() then
		return
	end
	BroadcastEvent(RESURRECTION_ACCEPT)
end

function Rezz.RegisterHandlers()
	if m_handlersRegistered then
		return
	end
	RegisterEventHandler(SystemData.Events.APPLICATION_TWO_BUTTON_DIALOG, "CustomUI.QoL.RezzAccept.OnTwoButtonDialog")
	m_handlersRegistered = true
end

function Rezz.UnregisterHandlers()
	if not m_handlersRegistered then
		return
	end
	UnregisterEventHandler(SystemData.Events.APPLICATION_TWO_BUTTON_DIALOG, "CustomUI.QoL.RezzAccept.OnTwoButtonDialog")
	m_handlersRegistered = false
end

function Rezz.Enable()
	Rezz.RegisterHandlers()
end

function Rezz.Disable()
	Rezz.UnregisterHandlers()
end

function Rezz.Initialize()
end

function Rezz.Shutdown()
	Rezz.UnregisterHandlers()
end
