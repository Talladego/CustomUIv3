----------------------------------------------------------------
-- CustomUI.QoL.AltTracker.Data — cross-character inventory + gold store
----------------------------------------------------------------
if not CustomUI then CustomUI = {} end
CustomUI.QoL = CustomUI.QoL or {}
CustomUI.QoL.AltTracker = CustomUI.QoL.AltTracker or {}

local Data = {}
CustomUI.QoL.AltTracker.Data = Data

local DB_VERSION = 1
local DEBOUNCE_SEC = 0.5

local tinsert = table.insert
local tsort   = table.sort
local pairs   = pairs
local ipairs  = ipairs
local floor   = math.floor

local LOC_DEFS = {}

local m_pendingLocs = {}
local m_debounceRemaining = 0
local m_needsProcess = false

local function narrow(value)
	if CustomUI and type(CustomUI.NarrowWString) == "function" then
		return CustomUI.NarrowWString(value)
	end
	if type(value) == "string" then
		return value
	end
	return tostring(value or "")
end

local function stripCharName(name)
	if type(name) ~= "wstring" then
		return narrow(name)
	end
	if type(wstring.match) == "function" then
		local stripped = wstring.match(name, L"([^\^]+).*")
		if stripped ~= nil then
			return narrow(stripped)
		end
	end
	return narrow(name)
end

local function currentFactionKey()
	if GameData and GameData.Player and GameData.Realm
		and GameData.Player.realm == GameData.Realm.ORDER then
		return "order"
	end
	return "destruction"
end

local function dayNum()
	local ok, t = pcall(GetTodaysDate)
	if not ok or type(t) ~= "table" then
		return 0
	end
	local y = t.todaysYear or 0
	local m = t.todaysMonth or 1
	local d = t.todaysDay or 1
	return ((y * 12) + (m - 1)) * 31 + (d - 1)
end

function Data.EnsureDB()
	if type(_G.CustomUI_AltTrackerDB) ~= "table" then
		_G.CustomUI_AltTrackerDB = {}
	end
	local db = _G.CustomUI_AltTrackerDB
	if type(db.version) ~= "number" then
		db.version = DB_VERSION
	end
	if type(db.realms) ~= "table" then
		db.realms = {}
	end
	return db
end

function Data.GetRealmKey()
	if GameData and GameData.Account and GameData.Account.ServerName then
		return narrow(GameData.Account.ServerName)
	end
	return "unknown"
end

function Data.MakeCharKey()
	local server = Data.GetRealmKey()
	local name = stripCharName(GameData and GameData.Player and GameData.Player.name or "")
	local account = ""
	if GameData and GameData.Account and GameData.Account.AccountName then
		account = narrow(GameData.Account.AccountName)
	end
	if account ~= "" then
		return account .. "::" .. name .. "@" .. server
	end
	local slot = (GameData and GameData.Account and GameData.Account.SelectedCharacterSlot) or 0
	return name .. "@" .. server .. "#" .. tostring(slot)
end

local function getRealmStore()
	local db = Data.EnsureDB()
	local realmKey = Data.GetRealmKey()
	local realm = db.realms[realmKey]
	if type(realm) ~= "table" then
		realm = { characters = {} }
		db.realms[realmKey] = realm
	end
	if type(realm.characters) ~= "table" then
		realm.characters = {}
	end
	return realm
end

function Data.GetCurrentCharRecord()
	local realm = getRealmStore()
	local key = Data.MakeCharKey()
	local rec = realm.characters[key]
	if type(rec) ~= "table" then
		rec = {
			displayName = stripCharName(GameData.Player.name),
			accountName = narrow(GameData.Account.AccountName or ""),
			faction = currentFactionKey(),
			slot = GameData.Account.SelectedCharacterSlot or 0,
			careerLine = 0,
			lastSeenDay = dayNum(),
			money = 0,
			items = {},
		}
		realm.characters[key] = rec
	end
	rec.displayName = stripCharName(GameData.Player.name)
	rec.accountName = narrow(GameData.Account.AccountName or "")
	rec.faction = currentFactionKey()
	rec.slot = GameData.Account.SelectedCharacterSlot or rec.slot or 0
	if GameData and GameData.Player and GameData.Player.career then
		local line = tonumber(GameData.Player.career.line)
		if line and line > 0 then
			rec.careerLine = line
		end
	end
	rec.lastSeenDay = dayNum()
	if type(rec.items) ~= "table" then
		rec.items = {}
	end
	return rec, key
end

function Data.UpdateMoney(moneyBrass)
	moneyBrass = tonumber(moneyBrass)
	if moneyBrass == nil then
		return false
	end
	local rec = Data.GetCurrentCharRecord()
	rec.money = moneyBrass
	return true
end

function Data.ReadMoneyFromFrame(frameName)
	if type(frameName) ~= "string" or not DoesWindowExist(frameName) then
		return nil
	end
	if type(MoneyFrame) ~= "table" or type(MoneyFrame.ConvertCurrencyToBrass) ~= "function" then
		return nil
	end
	local ok, brass = pcall(MoneyFrame.ConvertCurrencyToBrass, frameName)
	if ok and type(brass) == "number" and brass >= 0 then
		return brass
	end
	return nil
end

function Data.ReadLiveMoneyBrass(preferredBrass)
	local money = tonumber(preferredBrass)

	if money == nil and GameData and GameData.Player then
		money = tonumber(GameData.Player.money)
	end

	if (money == nil or money == 0) then
		local backpackMoney = Data.ReadMoneyFromFrame("EA_Window_BackpackMoney")
		if backpackMoney ~= nil then
			money = backpackMoney
		end
	end

	if (money == nil or money == 0) then
		local characterMoney = Data.ReadMoneyFromFrame("CharacterWindowPlayerMoney")
		if characterMoney ~= nil then
			money = characterMoney
		end
	end

	if money == nil and Player and Player.previousMoney ~= nil then
		money = tonumber(Player.previousMoney)
	end

	if money == nil then
		return nil
	end
	return money
end

function Data.SnapshotMoney(preferredBrass)
	if type(IsPlayerInitialized) == "function" and not IsPlayerInitialized() then
		return false
	end
	local money = Data.ReadLiveMoneyBrass(preferredBrass)
	if money == nil then
		return false
	end
	return Data.UpdateMoney(money)
end

local function zeroLocCounts(rec, locKey)
	for uid, counts in pairs(rec.items) do
		if type(counts) == "table" then
			counts[locKey] = nil
			if next(counts) == nil then
				rec.items[uid] = nil
			end
		end
	end
end

local function applyLocCounts(rec, locKey, tallies)
	zeroLocCounts(rec, locKey)
	for uid, count in pairs(tallies) do
		if count > 0 then
			rec.items[uid] = rec.items[uid] or {}
			rec.items[uid][locKey] = count
		end
	end
end

function Data.RescanLoc(locKey)
	local def
	for i = 1, #LOC_DEFS do
		if LOC_DEFS[i].key == locKey then
			def = LOC_DEFS[i]
			break
		end
	end
	if def == nil then
		return
	end
	local rec = Data.GetCurrentCharRecord()
	local tallies = {}
	local itemData
	if type(def.getData) == "function" then
		local ok, data = pcall(def.getData)
		if ok and type(data) == "table" then
			for slot = 1, #data do
				itemData = data[slot]
				if type(DataUtils) == "table" and type(DataUtils.IsValidItem) == "function" then
					if DataUtils.IsValidItem(itemData) then
						local uid = itemData.uniqueID
						local stack = tonumber(itemData.stackCount) or 1
						tallies[uid] = (tallies[uid] or 0) + stack
					end
				elseif itemData and tonumber(itemData.uniqueID) and itemData.uniqueID ~= 0 then
					local uid = itemData.uniqueID
					local stack = tonumber(itemData.stackCount) or 1
					tallies[uid] = (tallies[uid] or 0) + stack
				end
			end
		end
	end
	applyLocCounts(rec, locKey, tallies)
end

function Data.RescanPlayerLocs()
	Data.RescanLoc("bag")
	Data.RescanLoc("crafting")
	Data.RescanLoc("currency")
end

function Data.RescanBank()
	Data.RescanLoc("bank")
end

function Data.ClearBank()
	local rec = Data.GetCurrentCharRecord()
	zeroLocCounts(rec, "bank")
end

function Data.QueueLoc(locKey)
	m_pendingLocs[locKey] = true
	m_needsProcess = true
	m_debounceRemaining = DEBOUNCE_SEC
end

function Data.QueuePlayerRescan()
	Data.QueueLoc("bag")
	Data.QueueLoc("crafting")
	Data.QueueLoc("currency")
end

function Data.ProcessPending()
	if not m_needsProcess then
		return
	end
	m_needsProcess = false
	for locKey in pairs(m_pendingLocs) do
		Data.RescanLoc(locKey)
		m_pendingLocs[locKey] = nil
	end
end

function Data.OnUpdate(timePassed)
	if not m_needsProcess then
		return
	end
	m_debounceRemaining = m_debounceRemaining - (tonumber(timePassed) or 0)
	if m_debounceRemaining <= 0 then
		Data.ProcessPending()
	end
end

local function getSettings()
	if CustomUI and CustomUI.QoL and type(CustomUI.QoL.EnsureSettings) == "function" then
		local s = CustomUI.QoL.EnsureSettings()
		return s.altTracker or {}
	end
	return {}
end

local function toWString(value)
	if value == nil then
		return L""
	end
	if type(value) == "wstring" then
		return value
	end
	if type(towstring) == "function" then
		return towstring(tostring(value))
	end
	return value
end

local function resolveCareerLine(rec, isSelf)
	local line = tonumber(rec.careerLine) or 0
	if line <= 0 and isSelf and GameData and GameData.Player and GameData.Player.career then
		line = tonumber(GameData.Player.career.line) or 0
	end
	return line
end

local function careerIconPrefix(careerLine)
	careerLine = tonumber(careerLine) or 0
	if careerLine <= 0 then
		return L""
	end
	if type(Icons) ~= "table" or type(Icons.GetCareerIconIDFromCareerLine) ~= "function" then
		return L""
	end
	local iconNum = Icons.GetCareerIconIDFromCareerLine(careerLine)
	if iconNum == nil or iconNum == 0 then
		return L""
	end
	return L"<icon" .. towstring(iconNum) .. L"> "
end

local function displayNamePlain(rec)
	local name = rec.displayName or "?"
	return toWString(name)
end

local function displayLabel(rec, isSelf)
	local name = rec.displayName or "?"
	return careerIconPrefix(resolveCareerLine(rec, isSelf)) .. toWString(name)
end

local function sortWithinFaction(rows, valueField)
	valueField = valueField or "money"
	tsort(rows, function(a, b)
		local av = tonumber(a[valueField]) or 0
		local bv = tonumber(b[valueField]) or 0
		if av ~= bv then
			return av > bv
		end
		return tostring(a.plainName or a.displayName) < tostring(b.plainName or b.displayName)
	end)
end

function Data.GetLocalFactionKey()
	return currentFactionKey()
end

function Data.GetFactionDisplayName(factionKey)
	if type(GetRealmName) == "function" and GameData and GameData.Realm then
		if factionKey == "order" then
			return GetRealmName(GameData.Realm.ORDER)
		end
		return GetRealmName(GameData.Realm.DESTRUCTION)
	end
	if factionKey == "order" then
		return L"Order"
	end
	return L"Destruction"
end

function Data.PartitionByFaction(rows, valueField)
	local myFaction = currentFactionKey()
	local localRows = {}
	local otherRows = {}
	if type(rows) ~= "table" then
		return localRows, otherRows, myFaction
	end
	for i = 1, #rows do
		local row = rows[i]
		if row.faction == myFaction then
			tinsert(localRows, row)
		else
			tinsert(otherRows, row)
		end
	end
	sortWithinFaction(localRows, valueField)
	sortWithinFaction(otherRows, valueField)
	return localRows, otherRows, myFaction
end

function Data.GetItemCounts(uniqueID)
	uniqueID = tonumber(uniqueID) or 0
	if uniqueID == 0 then
		return {}
	end
	local settings = getSettings()
	local realm = getRealmStore()
	local results = {}
	local selfKey = Data.MakeCharKey()
	local myFaction = currentFactionKey()

	for key, rec in pairs(realm.characters) do
		if type(rec) == "table" and type(rec.items) == "table" then
			if settings.showCrossFaction == true or rec.faction == myFaction then
				local counts = rec.items[uniqueID]
				if type(counts) == "table" then
					local bag = (tonumber(counts.bag) or 0)
						+ (tonumber(counts.crafting) or 0)
						+ (tonumber(counts.currency) or 0)
					local bank = tonumber(counts.bank) or 0
					local total = bag
					if settings.includeBank == true then
						total = bag + bank
					end
					if total > 0 then
						local isSelf = (key == selfKey)
						tinsert(results, {
							key = key,
							faction = rec.faction or myFaction,
							displayName = displayLabel(rec, isSelf),
							plainName = displayNamePlain(rec),
							careerLine = resolveCareerLine(rec, isSelf),
							bagCount = bag,
							bankCount = bank,
							totalCount = total,
							isSelf = isSelf,
						})
					end
				end
			end
		end
	end

	return results
end

function Data.GetAllGold()
	local settings = getSettings()
	local realm = getRealmStore()
	local results = {}
	local selfKey = Data.MakeCharKey()
	local myFaction = currentFactionKey()
	local totalBrass = 0

	for key, rec in pairs(realm.characters) do
		if type(rec) == "table" and rec.displayName then
			if settings.showCrossFaction == true or rec.faction == myFaction then
				local money = tonumber(rec.money) or 0
				local isSelf = (key == selfKey)
				if isSelf then
					local live = Data.ReadLiveMoneyBrass()
					if live ~= nil then
						money = live
					end
				end
				tinsert(results, {
					key = key,
					faction = rec.faction or myFaction,
                    displayName = displayLabel(rec, isSelf),
                    plainName = displayNamePlain(rec),
					careerLine = resolveCareerLine(rec, isSelf),
					money = money,
					isSelf = isSelf,
				})
				totalBrass = totalBrass + money
			end
		end
	end

	return results, totalBrass
end

function Data.InitLocDefs()
	LOC_DEFS = {}
	if not GameData or not GameData.ItemLocs then
		return
	end
	if type(DataUtils) ~= "table" then
		return
	end
	tinsert(LOC_DEFS, { key = "bag", getData = DataUtils.GetItems })
	tinsert(LOC_DEFS, { key = "crafting", getData = DataUtils.GetCraftingItems })
	tinsert(LOC_DEFS, { key = "currency", getData = DataUtils.GetCurrencyItems })
	tinsert(LOC_DEFS, { key = "bank", getData = DataUtils.GetBankData })
end

function Data.ImportShiniesDB()
	if type(_G.ShiniesDB) ~= "table" then
		return
	end
	if _G.CustomUI_AltTrackerDB and _G.CustomUI_AltTrackerDB._shiniesImported == true then
		return
	end
	local account = narrow(GameData and GameData.Account and GameData.Account.AccountName or "")
	local server = Data.GetRealmKey()
	local faction = currentFactionKey()
	local factionLabel = (faction == "order") and "Order" or "Destruction"
	local frKey = factionLabel .. " - " .. server
	local fr = ShiniesDB.factionrealm and ShiniesDB.factionrealm[frKey]
	if type(fr) ~= "table" or type(fr.chars) ~= "table" then
		return
	end
	local realm = getRealmStore()
	local imported = 0
	for slot, charData in pairs(fr.chars) do
		slot = tonumber(slot) or 0
		if slot > 0 and type(charData) == "table" and type(charData.totals) == "table" then
			local slotInfo = GameData.Account.CharacterSlot and GameData.Account.CharacterSlot[slot]
			if slotInfo and tonumber(slotInfo.Level) and slotInfo.Level > 0 then
				local name = stripCharName(slotInfo.Name)
				local key
				if account ~= "" then
					key = account .. "::" .. name .. "@" .. server
				else
					key = name .. "@" .. server .. "#" .. tostring(slot)
				end
				local rec = realm.characters[key]
				if type(rec) ~= "table" then
					rec = {
						displayName = name,
						accountName = account,
						faction = faction,
						slot = slot,
						lastSeenDay = dayNum(),
						money = 0,
						items = {},
					}
					realm.characters[key] = rec
				end
				local locMap = {
					[GameData.ItemLocs.INVENTORY] = "bag",
					[GameData.ItemLocs.CRAFTING_ITEM] = "crafting",
					[GameData.ItemLocs.CURRENCY_ITEM] = "currency",
					[GameData.ItemLocs.BANK] = "bank",
				}
				for itemLoc, locKey in pairs(locMap) do
					local locTotals = charData.totals[itemLoc]
					if type(locTotals) == "table" then
						for uid, entry in pairs(locTotals) do
							uid = tonumber(uid) or 0
							local count = type(entry) == "table" and tonumber(entry.count) or 0
							if uid > 0 and count > 0 then
								rec.items[uid] = rec.items[uid] or {}
								rec.items[uid][locKey] = (rec.items[uid][locKey] or 0) + count
								imported = imported + 1
							end
						end
					end
				end
			end
		end
	end
	local db = Data.EnsureDB()
	db._shiniesImported = true
	if imported > 0 and CustomUI and type(CustomUI.PrintMessage) == "function" then
		CustomUI.PrintMessage(L"AltTracker: imported Shinies inventory data.")
	end
end

local function getPruneThresholdDays()
	local settings = getSettings()
	local days = tonumber(settings.pruneStaleDays)
	if days == nil then
		days = 30
	end
	if days < 0 then
		days = 0
	end
	return math.floor(days)
end

function Data.PruneStaleCharacters()
	local thresholdDays = getPruneThresholdDays()
	if thresholdDays <= 0 then
		return 0
	end
	if type(IsPlayerInitialized) == "function" and not IsPlayerInitialized() then
		return 0
	end
	local today = dayNum()
	if today <= 0 then
		return 0
	end
	local db = Data.EnsureDB()
	local selfKey = nil
	if GameData and GameData.Player and type(Data.MakeCharKey) == "function" then
		local ok, key = pcall(Data.MakeCharKey)
		if ok then
			selfKey = key
		end
	end
	local removed = 0
	for _, realm in pairs(db.realms) do
		if type(realm) == "table" and type(realm.characters) == "table" then
			local toRemove = {}
			for key, rec in pairs(realm.characters) do
				if key ~= selfKey and type(rec) == "table" then
					local lastSeen = tonumber(rec.lastSeenDay) or 0
					if lastSeen > 0 and (today - lastSeen) > thresholdDays then
						toRemove[#toRemove + 1] = key
					end
				end
			end
			for i = 1, #toRemove do
				realm.characters[toRemove[i]] = nil
				removed = removed + 1
			end
		end
	end
	if removed > 0 and CustomUI and type(CustomUI.PrintMessage) == "function" then
		CustomUI.PrintMessage(L"AltTracker: pruned " .. towstring(removed) .. L" stale character record(s).")
	end
	return removed
end

function Data.FullLoginRescan()
	Data.GetCurrentCharRecord()
	Data.PruneStaleCharacters()
	Data.SnapshotMoney()
	Data.RescanPlayerLocs()
end