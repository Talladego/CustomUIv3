----------------------------------------------------------------
-- CustomUI.QoL.ActionButtons
-- Action on down: cast a normal hotbar ability on button down.
-- One-click ground target: first press shows the template, release places it.
--
-- Hotbar /assist macros: the client drops /assist if addon code calls any Lua
-- function while the click is handled. Foreign buttons (macros, items, etc.)
-- must leave through a tail call after field reads only — same rule as
-- GCDsaver / LibSlash / StockPiler Macro.
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
-- Cached in Sync so click handlers never call EnsureSettings (assist-safe).
local m_actionOnDown = false
local m_oneClickGt = false

local function settings()
	return CustomUI.QoL.EnsureSettings()
end

local function cacheFeatureFlags()
	local s = settings()
	m_actionOnDown = s.actionOnDown.enabled == true
	m_oneClickGt = s.oneClickGtAoe.enabled == true
end

function AB.OnLButtonDown(self, flags, x, y)
	-- Non-ability / non-game-action: field reads then tail-call stock down.
	-- Do not call settings() or helpers here — macros share this path.
	if flags ~= SystemData.ButtonFlags.GAME_ACTION
		or not self
		or self.m_ActionType ~= GameData.PlayerActions.DO_ABILITY
		or not self.m_ActionId
		or self.m_ActionId == 0
	then
		if m_orgDown then
			return m_orgDown(self, flags, x, y)
		end
		return
	end

	local ground = AB.GroundTargets[self.m_ActionId] == true
	if m_orgDown then
		m_orgDown(self, flags, x, y)
	end
	if m_oneClickGt == true and ground then
		WindowGameAction(SystemData.ActiveWindow.name)
		return
	end
	if m_actionOnDown == true and not ground then
		WindowGameAction(SystemData.ActiveWindow.name)
	end
end

function AB.OnLButtonUp(self, flags, x, y)
	-- Swallow stock up only for normal abilities already fired on down.
	-- Everything else (including /assist macros) is field reads + tail call.
	if m_actionOnDown == true
		and flags == SystemData.ButtonFlags.GAME_ACTION
		and self
		and self.m_ActionType == GameData.PlayerActions.DO_ABILITY
		and self.m_ActionId
		and self.m_ActionId ~= 0
		and AB.GroundTargets[self.m_ActionId] ~= true
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
	-- unless QoL itself is enabled. Click handlers read the cached flags,
	-- so a disabled component clears those too.
	if not m_componentEnabled then
		m_actionOnDown = false
		m_oneClickGt = false
		AB.RemoveHooks()
		return
	end
	cacheFeatureFlags()
	if m_actionOnDown == true or m_oneClickGt == true then
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
	m_actionOnDown = false
	m_oneClickGt = false
	AB.RemoveHooks()
end

function AB.Initialize()
	RegisterEventHandler(SystemData.Events.ALL_MODULES_INITIALIZED, "CustomUI.QoL.ActionButtons.OnModulesInitialized")
end

function AB.Shutdown()
	AB.RemoveHooks()
end
