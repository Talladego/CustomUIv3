----------------------------------------------------------------
-- CustomUI.QoL.ActionButtons
-- Action on down: cast a normal hotbar ability on button down.
-- One-click ground target: first press shows the template, release places it.
----------------------------------------------------------------
if not CustomUI then CustomUI = {} end
CustomUI.QoL = CustomUI.QoL or {}
CustomUI.QoL.ActionButtons = CustomUI.QoL.ActionButtons or {}

local AB = CustomUI.QoL.ActionButtons

-- Ground-target abilities. The first WindowGameAction shows the template;
-- the stock button-up call places it.
AB.GroundTargets = {
	[651] = true,   -- Hail of Doom
	[9251] = true,  -- Mistress of the Marsh
	[9309] = true,  -- Flames of the Phoenix
	[8177] = true,  -- Rain of Fire
	[8222] = true,  -- Conflagration of Doom
	[9142] = true,  -- Rain of Steel
	[1581] = true,  -- Artillery Barrage
	[1537] = true,  -- Napalm Grenade
	[1541] = true,  -- Phosphorous Shells
	[1524] = true,  -- Land Mine
	[1612] = true,  -- Master Rune of Fury
	[1615] = true,  -- Master Rune of Speed
	[1618] = true,  -- Master Rune of Adamant
	[6039] = true,  -- Runic Conduit
	[32583] = true, -- Runic Conduit
	[1927] = true,  -- Sticky Feetz
	[8572] = true,  -- Ritual of Innervation
	[8574] = true,  -- Ritual of Superiority
	[8577] = true,  -- Ritual of Lunacy
	[6040] = true,  -- Ritual Nexus
	[35594] = true, -- Ritual Nexus
	[8494] = true,  -- Dissolving Mist
	[8498] = true,  -- Tzeentch's Firestorm
	[8541] = true,  -- Daemonic Infestation
	[9485] = true,  -- Pit of Shades
}

local m_ready = false
local m_componentEnabled = false
local m_hooked = false
local m_orgDown = nil
local m_orgUp = nil
local m_down = nil
local m_up = nil

local function settings()
	return CustomUI.QoL.EnsureSettings()
end

local function isGroundTarget(button)
	return button
		and button.m_ActionId
		and AB.GroundTargets[button.m_ActionId] == true
end

local function isNormalAbility(button)
	return button
		and button.m_ActionId
		and button.m_ActionId ~= 0
		and button.m_ActionType == GameData.PlayerActions.DO_ABILITY
		and not isGroundTarget(button)
end

function AB.OnLButtonDown(self, flags, x, y)
	if m_orgDown then
		m_orgDown(self, flags, x, y)
	end
	if flags ~= SystemData.ButtonFlags.GAME_ACTION then
		return
	end
	local s = settings()
	if s.oneClickGtAoe.enabled == true and isGroundTarget(self) then
		WindowGameAction(SystemData.ActiveWindow.name)
		return
	end
	if s.actionOnDown.enabled == true and isNormalAbility(self) then
		WindowGameAction(SystemData.ActiveWindow.name)
	end
end

function AB.OnLButtonUp(self, flags, x, y)
	local s = settings()
	if s.actionOnDown.enabled == true
		and flags == SystemData.ButtonFlags.GAME_ACTION
		and isNormalAbility(self)
	then
		return
	end
	if m_orgUp then
		return m_orgUp(self, flags, x, y)
	end
end

function AB.InstallHooks()
	if m_hooked or type(ActionButton) ~= "table" then
		return
	end
	m_orgDown = ActionButton.OnLButtonDown
	m_orgUp = ActionButton.OnLButtonUp
	m_down = AB.OnLButtonDown
	m_up = AB.OnLButtonUp
	ActionButton.OnLButtonDown = m_down
	ActionButton.OnLButtonUp = m_up
	m_hooked = true
end

function AB.RemoveHooks()
	if not m_hooked or type(ActionButton) ~= "table" then
		m_hooked = false
		return
	end
	local restoredDown = ActionButton.OnLButtonDown ~= m_down
	local restoredUp = ActionButton.OnLButtonUp ~= m_up
	if ActionButton.OnLButtonDown == m_down then
		ActionButton.OnLButtonDown = m_orgDown
		restoredDown = true
	end
	if ActionButton.OnLButtonUp == m_up then
		ActionButton.OnLButtonUp = m_orgUp
		restoredUp = true
	end
	if restoredDown and restoredUp then
		m_hooked = false
		m_orgDown = nil
		m_orgUp = nil
	end
end

function AB.Sync()
	if not m_ready then
		return
	end
	-- Initialize runs for a disabled QoL component and still registers
	-- ALL_MODULES_INITIALIZED. Feature checkboxes must not hook the hotbar
	-- unless QoL itself is enabled.
	if not m_componentEnabled then
		AB.RemoveHooks()
		return
	end
	local s = settings()
	if s.actionOnDown.enabled == true or s.oneClickGtAoe.enabled == true then
		AB.InstallHooks()
	else
		AB.RemoveHooks()
	end
end

function AB.OnModulesInitialized()
	m_ready = true
	AB.Sync()
end

function AB.Enable()
	m_componentEnabled = true
	AB.Sync()
end

function AB.Disable()
	m_componentEnabled = false
	AB.RemoveHooks()
end

function AB.Initialize()
	RegisterEventHandler(SystemData.Events.ALL_MODULES_INITIALIZED, "CustomUI.QoL.ActionButtons.OnModulesInitialized")
end

function AB.Shutdown()
	AB.RemoveHooks()
end
