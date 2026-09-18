----------------------------------------------------------------
-- CustomUI.QoL.AutoSellTrash — sell grey junk on vendor open
----------------------------------------------------------------
if not CustomUI then CustomUI = {} end
CustomUI.QoL = CustomUI.QoL or {}
CustomUI.QoL.AutoSellTrash = CustomUI.QoL.AutoSellTrash or {}

local Sell = CustomUI.QoL.AutoSellTrash

-- Grey only (JunkDump RarityThreshold = 1).
local RARITY_GREY_MAX = 1
local BACKPACK_INVENTORY = (EA_Window_Backpack and EA_Window_Backpack.TYPE_INVENTORY) or 2

local m_handlersRegistered = false
local m_queue = {}
local m_sessionActive = false
local m_soldCount = 0
local m_reported = false

-- Static mount / teleport blocklist (from JunkDump).
local MOUNT_IDS = {
	[208017] = true, [208016] = true, [208015] = true, [186818] = true, [186817] = true,
	[186816] = true, [186815] = true, [186814] = true, [186813] = true,
	[208011] = true, [208010] = true, [208009] = true, [186812] = true, [186811] = true,
	[186810] = true, [186809] = true, [186808] = true, [186807] = true,
	[208028] = true, [208026] = true, [208025] = true, [186830] = true, [186829] = true,
	[186828] = true, [186827] = true, [186826] = true, [186825] = true,
	[208040] = true, [208039] = true, [208037] = true, [186842] = true, [186841] = true,
	[186840] = true, [186839] = true, [186838] = true, [186837] = true,
	[208005] = true, [208004] = true, [208003] = true, [186806] = true, [186805] = true,
	[186804] = true, [186803] = true, [186802] = true, [186801] = true,
	[208023] = true, [208022] = true, [208021] = true, [186824] = true, [186823] = true,
	[186822] = true, [186821] = true, [186820] = true, [186819] = true,
	[208034] = true, [208033] = true, [208031] = true, [186836] = true, [186835] = true,
	[186834] = true, [186833] = true, [186832] = true, [186831] = true,
	[186843] = true, [186844] = true, [186845] = true, [186852] = true, [208045] = true,
	[208046] = true, [208047] = true,
	[207287] = true, [207388] = true, [207389] = true, [207390] = true, [207391] = true,
	[65825] = true,
}

local function getSettings()
	return CustomUI.QoL.EnsureSettings().autoSellTrash
end

local function isFeatureEnabled()
	local s = getSettings()
	return s.enabled == true
end

local function narrowName(name)
	if name == nil then
		return ""
	end
	if type(name) == "wstring" and type(WStringToString) == "function" then
		return WStringToString(name) or ""
	end
	return tostring(name)
end

local function isDye(itemData)
	local n = narrowName(itemData and itemData.name)
	return string.find(n, " Dye", 1, true) ~= nil
		or string.sub(n, -4) == " Dye"
end

local function isMount(itemData)
	local uid = tonumber(itemData and itemData.uniqueID) or 0
	return MOUNT_IDS[uid] == true
end

local function isSlotLocked(slot)
	if type(EA_Window_Backpack) == "table" and type(EA_Window_Backpack.IsSlotLocked) == "function" then
		local ok, locked = pcall(EA_Window_Backpack.IsSlotLocked, slot)
		return ok and locked == true
	end
	return false
end

local function isSellableGrey(itemData, slot)
	if type(itemData) ~= "table" then
		return false
	end
	local uid = tonumber(itemData.uniqueID) or 0
	if uid == 0 then
		return false
	end
	local price = tonumber(itemData.sellPrice) or 0
	if price <= 0 then
		return false
	end
	local rarity = tonumber(itemData.rarity) or 99
	if rarity > RARITY_GREY_MAX then
		return false
	end
	if isSlotLocked(slot) or isDye(itemData) or isMount(itemData) then
		return false
	end
	return true
end

local function forceInventoryDirty()
	if type(GameData) == "table" and type(GameData.Player) == "table" then
		GameData.Player.itemsDirty = true
	end
end

local function getInventoryData()
	forceInventoryDirty()
	if type(DataUtils) == "table" and type(DataUtils.GetItems) == "function" then
		local ok, data = pcall(DataUtils.GetItems)
		if ok and type(data) == "table" then
			return data
		end
	end
	if type(GetInventoryItemData) == "function" then
		local ok, data = pcall(GetInventoryItemData)
		if ok and type(data) == "table" then
			return data
		end
	end
	return nil
end

local function clearSession()
	m_queue = {}
	m_sessionActive = false
	m_soldCount = 0
	m_reported = false
end

local function buildQueue()
	m_queue = {}
	local data = getInventoryData()
	if type(data) ~= "table" then
		return
	end
	for slot, itemData in pairs(data) do
		local slotNum = tonumber(slot)
		if slotNum and isSellableGrey(itemData, slotNum) then
			m_queue[#m_queue + 1] = {
				slot = slotNum,
				backpack = BACKPACK_INVENTORY,
				stack = tonumber(itemData.stackCount) or 1,
			}
		end
	end
end

local function sellOne(entry)
	local data = getInventoryData()
	if type(data) ~= "table" or type(entry) ~= "table" then
		return false
	end
	local item = data[entry.slot]
	if not isSellableGrey(item, entry.slot) then
		return false
	end
	if type(GameData) ~= "table" or type(GameData.InteractStoreData) ~= "table" then
		return false
	end
	GameData.InteractStoreData.CurrentItemIndex = entry.slot
	GameData.InteractStoreData.NumItems = tonumber(item.stackCount) or entry.stack or 1
	GameData.InteractStoreData.CurrentBackpackIndex = entry.backpack or BACKPACK_INVENTORY
	BroadcastEvent(SystemData.Events.INTERACT_SELL_ITEM)
	return true
end

local function reportIfDone()
	if m_reported or m_soldCount <= 0 then
		return
	end
	m_reported = true
	if type(CustomUI.PrintMessage) == "function" then
		CustomUI.PrintMessage(L"AutoSellTrash: sold " .. towstring(m_soldCount) .. L" grey item(s).")
	end
end

function Sell.OnShowStore()
	if not isFeatureEnabled() then
		return
	end
	if not m_sessionActive then
		m_sessionActive = true
		m_soldCount = 0
		m_reported = false
		buildQueue()
	end
	if #m_queue == 0 then
		reportIfDone()
		return
	end
	local entry = table.remove(m_queue, 1)
	if sellOne(entry) then
		m_soldCount = m_soldCount + 1
	end
	if #m_queue == 0 then
		reportIfDone()
	end
end

function Sell.OnInteractDone()
	clearSession()
end

function Sell.RegisterHandlers()
	if m_handlersRegistered then
		return
	end
	local e = SystemData and SystemData.Events
	if type(e) ~= "table" or type(RegisterEventHandler) ~= "function" then
		return
	end
	RegisterEventHandler(e.INTERACT_SHOW_STORE, "CustomUI.QoL.AutoSellTrash.OnShowStore")
	RegisterEventHandler(e.INTERACT_DONE, "CustomUI.QoL.AutoSellTrash.OnInteractDone")
	m_handlersRegistered = true
end

function Sell.UnregisterHandlers()
	if not m_handlersRegistered then
		return
	end
	local e = SystemData and SystemData.Events
	if type(e) == "table" and type(UnregisterEventHandler) == "function" then
		UnregisterEventHandler(e.INTERACT_SHOW_STORE, "CustomUI.QoL.AutoSellTrash.OnShowStore")
		UnregisterEventHandler(e.INTERACT_DONE, "CustomUI.QoL.AutoSellTrash.OnInteractDone")
	end
	m_handlersRegistered = false
	clearSession()
end

function Sell.Enable()
	Sell.RegisterHandlers()
end

function Sell.Disable()
	Sell.UnregisterHandlers()
end

function Sell.Initialize()
end

function Sell.Shutdown()
	Sell.UnregisterHandlers()
end
