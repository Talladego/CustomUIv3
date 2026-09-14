----------------------------------------------------------------
-- CustomUI.QoL.AltTracker — cross-character bag + gold tracking
----------------------------------------------------------------
if not CustomUI then CustomUI = {} end
CustomUI.QoL = CustomUI.QoL or {}
CustomUI.QoL.AltTracker = CustomUI.QoL.AltTracker or {}

local AT = CustomUI.QoL.AltTracker
local LOGIN_DELAY = 1.0
local MONEY_SNAPSHOT_DELAYS = { 0.5, 2.0, 5.0, 10.0 }
-- Extra bag/crafting passes after login (money already retries; inventory used to be one-shot).
local INVENTORY_RESCAN_DELAYS = { 1.0, 3.0, 8.0 }

local m_enabled = false
local m_handlersRegistered = false
local m_loginTimer = 0
local m_pendingLoginRescan = false
local m_moneySnapshotTimers = {}
local m_inventoryRescanTimers = {}
local m_backpackWasShowing = false
local m_emptyItemsBackpackRescanDone = false
local m_origPlayerUpdateMoney = nil
local m_origBackpackUpdateMoney = nil
local m_playerUpdateMoneyWrapper = nil
local m_backpackUpdateMoneyWrapper = nil

local function getSettings()
	return CustomUI.QoL.EnsureSettings().altTracker
end

local function getData()
	return AT.Data
end

local function getTips()
	return AT.Tooltips
end

function AT.OnMoneyMouseOver()
	local tips = getTips()
	if tips == nil or type(tips.ShowMoneyTooltip) ~= "function" then
		return
	end
	if type(tips.EnsureWindows) == "function" then
		tips.EnsureWindows()
	end
	tips.ShowMoneyTooltip("CustomUIAltTrackerMoneyHover")
end

function AT.OnMoneyMouseOverEnd()
	local tips = getTips()
	if tips and type(tips.HideMoneyTooltip) == "function" then
		tips.HideMoneyTooltip()
	end
end

function AT.OnInventorySlotUpdated()
	if not m_enabled then return end
	local data = getData()
	if data and type(data.QueueLoc) == "function" then
		data.QueueLoc("bag")
	end
end

function AT.OnCraftingSlotUpdated()
	if not m_enabled then return end
	local data = getData()
	if data and type(data.QueueLoc) == "function" then
		data.QueueLoc("crafting")
	end
end

function AT.OnCurrencySlotUpdated()
	if not m_enabled then return end
	local data = getData()
	if data and type(data.QueueLoc) == "function" then
		data.QueueLoc("currency")
	end
end

function AT.OnBankSlotUpdated()
	if not m_enabled then return end
	local data = getData()
	if data and type(data.QueueLoc) == "function" then
		data.QueueLoc("bank")
	end
end

function AT.OnInteractBankOpen()
	if not m_enabled then return end
	local data = getData()
	if data and type(data.ClearBank) == "function" then
		data.ClearBank()
	end
end

function AT.OnMoneyUpdated(currentMoney)
	if not m_enabled then return end
	local data = getData()
	if data and type(data.SnapshotMoney) == "function" then
		data.SnapshotMoney(currentMoney)
	elseif data and type(data.UpdateMoney) == "function" then
		local money = tonumber(currentMoney)
		if money ~= nil then
			data.UpdateMoney(money)
		end
	end
	local tips = getTips()
	if tips and type(tips.RefreshMoneyTooltipIfVisible) == "function" then
		tips.RefreshMoneyTooltipIfVisible()
	end
end

function AT.InstallMoneyHooks()
	if Player and type(Player.UpdateMoney) == "function" and m_origPlayerUpdateMoney == nil then
		m_origPlayerUpdateMoney = Player.UpdateMoney
		m_playerUpdateMoneyWrapper = function(currentMoney)
			m_origPlayerUpdateMoney(currentMoney)
			AT.OnMoneyUpdated(currentMoney)
		end
		Player.UpdateMoney = m_playerUpdateMoneyWrapper
	end
	if EA_Window_Backpack and type(EA_Window_Backpack.UpdateMoney) == "function" and m_origBackpackUpdateMoney == nil then
		m_origBackpackUpdateMoney = EA_Window_Backpack.UpdateMoney
		m_backpackUpdateMoneyWrapper = function(currentMoney)
			m_origBackpackUpdateMoney(currentMoney)
			AT.OnMoneyUpdated(currentMoney)
		end
		EA_Window_Backpack.UpdateMoney = m_backpackUpdateMoneyWrapper
	end
end

function AT.RemoveMoneyHooks()
	-- Only restore if our wrapper is still installed (FollowLeader pattern).
	if m_origPlayerUpdateMoney and Player and Player.UpdateMoney == m_playerUpdateMoneyWrapper then
		Player.UpdateMoney = m_origPlayerUpdateMoney
	end
	m_origPlayerUpdateMoney = nil
	m_playerUpdateMoneyWrapper = nil
	if m_origBackpackUpdateMoney and EA_Window_Backpack
		and EA_Window_Backpack.UpdateMoney == m_backpackUpdateMoneyWrapper then
		EA_Window_Backpack.UpdateMoney = m_origBackpackUpdateMoney
	end
	m_origBackpackUpdateMoney = nil
	m_backpackUpdateMoneyWrapper = nil
end

function AT.OnWorldReady()
	if not m_enabled then
		return
	end
	m_backpackWasShowing = false
	m_emptyItemsBackpackRescanDone = false
	AT.ScheduleLoginRescan()
	AT.ScheduleMoneySnapshots()
	AT.ScheduleInventoryRescans()
	if EA_Window_Backpack and type(EA_Window_Backpack.UpdateMoney) == "function" then
		if Player and Player.previousMoney ~= nil then
			pcall(EA_Window_Backpack.UpdateMoney, Player.previousMoney)
		elseif GameData and GameData.Player then
			pcall(EA_Window_Backpack.UpdateMoney, GameData.Player.money)
		end
	end
	local data = getData()
	if data and type(data.SnapshotMoney) == "function" then
		pcall(data.SnapshotMoney)
	end
end

function AT.ScheduleMoneySnapshots()
	m_moneySnapshotTimers = {}
	for i = 1, #MONEY_SNAPSHOT_DELAYS do
		m_moneySnapshotTimers[i] = MONEY_SNAPSHOT_DELAYS[i]
	end
end

function AT.ScheduleInventoryRescans()
	m_inventoryRescanTimers = {}
	for i = 1, #INVENTORY_RESCAN_DELAYS do
		m_inventoryRescanTimers[i] = INVENTORY_RESCAN_DELAYS[i]
	end
end

local function currentCharItemsEmpty()
	local data = getData()
	if data == nil or type(data.GetCurrentCharRecord) ~= "function" then
		return false
	end
	local ok, rec = pcall(data.GetCurrentCharRecord)
	if not ok or type(rec) ~= "table" or type(rec.items) ~= "table" then
		return false
	end
	return next(rec.items) == nil
end

function AT.MaybeRescanOnBackpackOpen()
	if not m_enabled then
		return
	end
	local showing = false
	if DoesWindowExist("EA_Window_Backpack") and type(WindowGetShowing) == "function" then
		showing = WindowGetShowing("EA_Window_Backpack") == true
	end
	if showing and not m_backpackWasShowing then
		if not m_emptyItemsBackpackRescanDone and currentCharItemsEmpty() then
			local data = getData()
			if data and type(data.RescanPlayerLocs) == "function" then
				pcall(data.RescanPlayerLocs)
			end
			m_emptyItemsBackpackRescanDone = true
		end
	end
	m_backpackWasShowing = showing
end

function AT.RegisterHandlers()
	if m_handlersRegistered then
		return
	end
	local e = SystemData and SystemData.Events
	if type(e) ~= "table" or type(RegisterEventHandler) ~= "function" then
		return
	end
	RegisterEventHandler(e.PLAYER_INVENTORY_SLOT_UPDATED, "CustomUI.QoL.AltTracker.OnInventorySlotUpdated")
	RegisterEventHandler(e.PLAYER_CRAFTING_SLOT_UPDATED, "CustomUI.QoL.AltTracker.OnCraftingSlotUpdated")
	RegisterEventHandler(e.PLAYER_CURRENCY_SLOT_UPDATED, "CustomUI.QoL.AltTracker.OnCurrencySlotUpdated")
	RegisterEventHandler(e.PLAYER_BANK_SLOT_UPDATED, "CustomUI.QoL.AltTracker.OnBankSlotUpdated")
	RegisterEventHandler(e.INTERACT_OPEN_BANK, "CustomUI.QoL.AltTracker.OnInteractBankOpen")
	RegisterEventHandler(e.PLAYER_MONEY_UPDATED, "CustomUI.QoL.AltTracker.OnMoneyUpdated")
	RegisterEventHandler(e.LOADING_END, "CustomUI.QoL.AltTracker.OnWorldReady")
	RegisterEventHandler(e.ENTER_WORLD, "CustomUI.QoL.AltTracker.OnWorldReady")
	if e.INTERFACE_RELOADED then
		RegisterEventHandler(e.INTERFACE_RELOADED, "CustomUI.QoL.AltTracker.OnWorldReady")
	end
	m_handlersRegistered = true
end

function AT.UnregisterHandlers()
	if not m_handlersRegistered then
		return
	end
	local e = SystemData and SystemData.Events
	if type(e) ~= "table" or type(UnregisterEventHandler) ~= "function" then
		m_handlersRegistered = false
		return
	end
	UnregisterEventHandler(e.PLAYER_INVENTORY_SLOT_UPDATED, "CustomUI.QoL.AltTracker.OnInventorySlotUpdated")
	UnregisterEventHandler(e.PLAYER_CRAFTING_SLOT_UPDATED, "CustomUI.QoL.AltTracker.OnCraftingSlotUpdated")
	UnregisterEventHandler(e.PLAYER_CURRENCY_SLOT_UPDATED, "CustomUI.QoL.AltTracker.OnCurrencySlotUpdated")
	UnregisterEventHandler(e.PLAYER_BANK_SLOT_UPDATED, "CustomUI.QoL.AltTracker.OnBankSlotUpdated")
	UnregisterEventHandler(e.INTERACT_OPEN_BANK, "CustomUI.QoL.AltTracker.OnInteractBankOpen")
	UnregisterEventHandler(e.PLAYER_MONEY_UPDATED, "CustomUI.QoL.AltTracker.OnMoneyUpdated")
	UnregisterEventHandler(e.LOADING_END, "CustomUI.QoL.AltTracker.OnWorldReady")
	UnregisterEventHandler(e.ENTER_WORLD, "CustomUI.QoL.AltTracker.OnWorldReady")
	if e.INTERFACE_RELOADED then
		UnregisterEventHandler(e.INTERFACE_RELOADED, "CustomUI.QoL.AltTracker.OnWorldReady")
	end
	m_handlersRegistered = false
end

function AT.ScheduleLoginRescan()
	m_pendingLoginRescan = true
	m_loginTimer = LOGIN_DELAY
end

function AT.OnUpdate(timePassed)
	if not m_enabled then
		return
	end
	local data = getData()
	if data and type(data.OnUpdate) == "function" then
		data.OnUpdate(timePassed)
	end
	timePassed = tonumber(timePassed) or 0
	if m_pendingLoginRescan then
		m_loginTimer = m_loginTimer - timePassed
		if m_loginTimer <= 0 then
			m_pendingLoginRescan = false
			if data and type(data.FullLoginRescan) == "function" then
				data.FullLoginRescan()
			end
		end
	end
	if #m_moneySnapshotTimers > 0 then
		for i = #m_moneySnapshotTimers, 1, -1 do
			m_moneySnapshotTimers[i] = m_moneySnapshotTimers[i] - timePassed
			if m_moneySnapshotTimers[i] <= 0 then
				if data and type(data.SnapshotMoney) == "function" then
					pcall(data.SnapshotMoney)
				end
				table.remove(m_moneySnapshotTimers, i)
			end
		end
	end
	if #m_inventoryRescanTimers > 0 then
		for i = #m_inventoryRescanTimers, 1, -1 do
			m_inventoryRescanTimers[i] = m_inventoryRescanTimers[i] - timePassed
			if m_inventoryRescanTimers[i] <= 0 then
				if data and type(data.RescanPlayerLocs) == "function" then
					pcall(data.RescanPlayerLocs)
				end
				table.remove(m_inventoryRescanTimers, i)
			end
		end
	end
	AT.MaybeRescanOnBackpackOpen()
	AT.SyncMoneyHoverVisibility()
end

function AT.SyncMoneyHoverVisibility()
	local settings = getSettings()
	local show = m_enabled and settings.trackGold == true
	if DoesWindowExist("EA_Window_Backpack") and type(WindowGetShowing) == "function" then
		show = show and WindowGetShowing("EA_Window_Backpack") == true
	end
	local tips = getTips()
	if tips and type(tips.SyncMoneyHover) == "function" then
		tips.SyncMoneyHover(show)
	end
end

function AT.ApplySettings()
	if m_enabled then
		AT.Disable()
		if getSettings().enabled == true then
			AT.Enable()
		end
	else
		if getSettings().enabled == true then
			AT.Enable()
		end
	end
end

function AT.Enable()
	if m_enabled then
		return
	end
	m_enabled = true
	local data = getData()
	if data then
		if type(data.EnsureDB) == "function" then
			data.EnsureDB()
		end
		if type(data.InitLocDefs) == "function" then
			data.InitLocDefs()
		end
		if type(data.PruneStaleCharacters) == "function" then
			pcall(data.PruneStaleCharacters)
		end
		if type(data.ImportShiniesDB) == "function" then
			pcall(data.ImportShiniesDB)
		end
	end
	local tips = getTips()
	if tips then
		if type(tips.EnsureWindows) == "function" then
			tips.EnsureWindows()
		end
		if type(tips.InstallHooks) == "function" then
			tips.InstallHooks()
		end
	end
	AT.RegisterHandlers()
	AT.InstallMoneyHooks()
	if Player and Player.previousMoney ~= nil then
		AT.OnMoneyUpdated(Player.previousMoney)
	elseif GameData and GameData.Player then
		AT.OnMoneyUpdated(GameData.Player.money)
	end
	AT.OnWorldReady()
	AT.SyncMoneyHoverVisibility()
end

function AT.Disable()
	if not m_enabled then
		return
	end
	local data = getData()
	if data and type(data.SnapshotMoney) == "function" then
		pcall(data.SnapshotMoney)
	end
	m_enabled = false
	m_pendingLoginRescan = false
	m_moneySnapshotTimers = {}
	m_inventoryRescanTimers = {}
	m_backpackWasShowing = false
	m_emptyItemsBackpackRescanDone = false
	AT.RemoveMoneyHooks()
	AT.UnregisterHandlers()
	local tips = getTips()
	if tips then
		if type(tips.RemoveHooks) == "function" then
			tips.RemoveHooks()
		end
		if type(tips.SyncMoneyHover) == "function" then
			tips.SyncMoneyHover(false)
		end
	end
	local data = getData()
	if data and type(data.ProcessPending) == "function" then
		data.ProcessPending()
	end
end

function AT.Initialize()
	local data = getData()
	if data and type(data.EnsureDB) == "function" then
		data.EnsureDB()
	end
	if data and type(data.InitLocDefs) == "function" then
		data.InitLocDefs()
	end
end

function AT.Shutdown()
	AT.Disable()
end
