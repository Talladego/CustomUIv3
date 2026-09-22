----------------------------------------------------------------
-- CustomUI.QoL.BattleFatigueHeal — clear healer penalties on open
----------------------------------------------------------------
if not CustomUI then CustomUI = {} end
CustomUI.QoL = CustomUI.QoL or {}
CustomUI.QoL.BattleFatigueHeal = CustomUI.QoL.BattleFatigueHeal or {}

local Heal = CustomUI.QoL.BattleFatigueHeal

local COOLDOWN_SECONDS = 2
local m_handlersRegistered = false
local m_lastHealTime = nil

local function getSettings()
	return CustomUI.QoL.EnsureSettings().battleFatigueHeal
end

local function isFeatureEnabled()
	local s = getSettings()
	return s.enabled == true
end

local function cooldownActive()
	if m_lastHealTime == nil or type(GetComputerTime) ~= "function" then
		return false
	end
	local now = GetComputerTime()
	local elapsed = now - m_lastHealTime
	-- Negative elapsed = midnight wrap; treat as expired.
	if elapsed < 0 then
		m_lastHealTime = nil
		return false
	end
	return elapsed < COOLDOWN_SECONDS
end

local function resolvePenalties(penaltyCount, costToRemove)
	local count = tonumber(penaltyCount)
	local cost = tonumber(costToRemove)
	if (count == nil or cost == nil)
		and type(EA_Window_InteractionHealer) == "table" then
		if count == nil then
			count = tonumber(EA_Window_InteractionHealer.penaltyCount)
		end
		if cost == nil then
			cost = tonumber(EA_Window_InteractionHealer.costToRemoveSinglePenalty)
		end
	end
	return count or 0, cost or 0
end

local function canAfford(count, unitCost)
	if count <= 0 then
		return false
	end
	local total = count * unitCost
	if total <= 0 then
		-- Free clear (unlikely); allow.
		return true
	end
	local money = nil
	if type(GameData) == "table" and type(GameData.Player) == "table" then
		money = tonumber(GameData.Player.money)
	end
	if money == nil and type(Player) == "table" and type(Player.GetMoney) == "function" then
		local ok, m = pcall(Player.GetMoney)
		if ok then
			money = tonumber(m)
		end
	end
	if money == nil then
		-- Unknown balance: allow and let the server reject.
		return true
	end
	return money >= total
end

local function hideHealerWindow()
	if type(DoesWindowExist) == "function" and DoesWindowExist("EA_Window_InteractionHealer")
		and type(WindowSetShowing) == "function" then
		WindowSetShowing("EA_Window_InteractionHealer", false)
	end
end

local function purchaseAll(count)
	SystemData.UserInput.NumPenaltiesRequestingToHeal = count
	BroadcastEvent(SystemData.Events.INTERACT_PURCHASE_HEAL)
	hideHealerWindow()
	if type(EA_Window_InteractionHealer) == "table"
		and type(EA_Window_InteractionHealer.Hide) == "function" then
		pcall(EA_Window_InteractionHealer.Hide)
	end
end

function Heal.OnShowHealer(penaltyCount, costToRemove)
	if not isFeatureEnabled() then
		return
	end
	if cooldownActive() then
		-- Still suppress flash on a duplicate open within the cooldown window.
		hideHealerWindow()
		return
	end
	local count, unitCost = resolvePenalties(penaltyCount, costToRemove)
	if count <= 0 then
		return
	end
	if not canAfford(count, unitCost) then
		if type(CustomUI.PrintMessage) == "function" then
			CustomUI.PrintMessage(L"BattleFatigueHeal: not enough money to clear penalties.")
		end
		return
	end
	purchaseAll(count)
	if type(CustomUI.PrintMessage) == "function" then
		CustomUI.PrintMessage(
			L"BattleFatigueHeal: cleared " .. towstring(count) .. L" penalty(ies)."
		)
	end
	if type(GetComputerTime) == "function" then
		m_lastHealTime = GetComputerTime()
	else
		m_lastHealTime = 1
	end
end

function Heal.RegisterHandlers()
	if m_handlersRegistered then
		return
	end
	local e = SystemData and SystemData.Events
	if type(e) ~= "table" or type(RegisterEventHandler) ~= "function" then
		return
	end
	RegisterEventHandler(e.INTERACT_SHOW_HEALER, "CustomUI.QoL.BattleFatigueHeal.OnShowHealer")
	m_handlersRegistered = true
end

function Heal.UnregisterHandlers()
	if not m_handlersRegistered then
		return
	end
	local e = SystemData and SystemData.Events
	if type(e) == "table" and type(UnregisterEventHandler) == "function" then
		UnregisterEventHandler(e.INTERACT_SHOW_HEALER, "CustomUI.QoL.BattleFatigueHeal.OnShowHealer")
	end
	m_handlersRegistered = false
	m_lastHealTime = nil
end

function Heal.Enable()
	Heal.RegisterHandlers()
end

function Heal.Disable()
	Heal.UnregisterHandlers()
end

function Heal.Initialize()
end

function Heal.Shutdown()
	Heal.UnregisterHandlers()
end
