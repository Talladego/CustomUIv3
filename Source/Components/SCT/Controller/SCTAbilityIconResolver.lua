----------------------------------------------------------------
-- CustomUI.SCT.AbilityIconResolver
--
-- Ability icon resolution and related debug logging for SCT. This owns cache
-- lookups, ability table probing, live buff-list scans, and equipment proc
-- fallbacks. Entry/window layout stays in SCTEventEntry.lua.
----------------------------------------------------------------
if not CustomUI.SCT then CustomUI.SCT = {} end

CustomUI.SCT.AbilityIconResolver = CustomUI.SCT.AbilityIconResolver or {}

local Resolver = CustomUI.SCT.AbilityIconResolver

local function SctLogLuaDebug(msg)
    if CustomUI.DebugLogging ~= true then
        return
    end
    if LogLuaMessage and SystemData and SystemData.UiLogFilters and type(towstring) == "function" then
        LogLuaMessage("Lua", SystemData.UiLogFilters.DEBUG, towstring(msg))
    end
end

local function SctLogLuaWarning(msg)
    if CustomUI.DebugLogging ~= true then
        return
    end
    if LogLuaMessage and SystemData and SystemData.UiLogFilters and type(towstring) == "function" then
        LogLuaMessage("Lua", SystemData.UiLogFilters.WARNING, towstring(msg))
    end
end

local function SctNormalizeAbilityDisplayName(raw)
    if raw == nil then
        return nil
    end
    local clean = tostring(towstring(raw))
    clean = string.gsub(clean, "%^.", "")
    clean = string.gsub(clean, "^%s+", "")
    clean = string.gsub(clean, "%s+$", "")
    if clean == "" then
        return nil
    end
    return clean
end

function Resolver.TryGetAbilityDisplayNameForSuffix(abilityId, hintAbilityData)
    if not abilityId or abilityId == 0 then
        return nil
    end
    local clean
    if type(hintAbilityData) == "table" and hintAbilityData.name ~= nil then
        clean = SctNormalizeAbilityDisplayName(hintAbilityData.name)
    end
    if not clean and type(GetAbilityName) == "function" then
        clean = SctNormalizeAbilityDisplayName(GetAbilityName(abilityId))
    end
    return clean
end

function Resolver.MergeAbilityNameHintForSuffix(preIconAbilityData, abilityId, abilityLine, sct)
    if not abilityLine or not sct or sct.showAbilityNameInText ~= true or not abilityId or abilityId == 0 then
        return preIconAbilityData
    end
    local hint = CustomUI.SCT.AbilityIconCachePeekHint(abilityId)
    if not hint or not hint.name then
        return preIconAbilityData
    end
    if type(preIconAbilityData) ~= "table" then
        return hint
    end
    if preIconAbilityData.name == nil or tostring(preIconAbilityData.name or "") == "" then
        local merged = {}
        for k, v in pairs(preIconAbilityData) do
            merged[k] = v
        end
        merged.name = hint.name
        return merged
    end
    return preIconAbilityData
end

local function SctNormAbilityNameText(s)
    s = tostring(s or "")
    s = string.gsub(s, "%^.", "")
    s = string.lower(s)
    s = string.gsub(s, "[%p%c]", " ")
    s = string.gsub(s, "%s+", " ")
    s = string.gsub(s, "^%s+", "")
    s = string.gsub(s, "%s+$", "")
    return s
end

local function SctStrStartsWith(s, prefix)
    if not s or not prefix or prefix == "" then
        return false
    end
    return string.sub(s, 1, string.len(prefix)) == prefix
end

local function SctLogAbilityIconResolveOnce(abilityId, path, detail)
    if not abilityId or abilityId == 0 or not path or path == "" then
        return
    end
    CustomUI.SCT._abilityIconResolveLog = CustomUI.SCT._abilityIconResolveLog or {}
    local key = tostring(abilityId) .. "\0" .. tostring(path)
    if CustomUI.SCT._abilityIconResolveLog[key] then
        return
    end
    CustomUI.SCT._abilityIconResolveLog[key] = true
    local msg = "[CustomUI.SCT] abilityIconResolve abilityId=" .. tostring(abilityId)
        .. " path=" .. tostring(path)
        .. (detail and detail ~= "" and (" detail=" .. tostring(detail)) or "")
    SctLogLuaDebug(msg)
end

local function SctTryBuffListIconResolve(abilityId, isIncoming)
    if not abilityId or abilityId == 0 then
        return nil, nil, nil
    end
    if type(GetBuffs) ~= "function" then
        return nil, nil, nil
    end
    if type(GameData) ~= "table" or type(GameData.BuffTargetType) ~= "table" then
        return nil, nil, nil
    end

    local now = nil
    if type(GetGameTime) == "function" then
        local ok, t = CustomUI.TryCallQuiet("SCTAbilityIconResolver.GetGameTime", GetGameTime)
        if ok then
            now = tonumber(t)
        end
    end
    CustomUI.SCT._sctBuffScanMiss = CustomUI.SCT._sctBuffScanMiss or {}
    local lastMiss = CustomUI.SCT._sctBuffScanMiss[abilityId]
    if now and lastMiss and (now - lastMiss) < 1 then
        return nil, nil, nil
    end

    local B = GameData.BuffTargetType
    local scanOrder = {}
    if isIncoming == true then
        scanOrder[#scanOrder + 1] = { tt = B.SELF,             tag = "buff:self" }
        scanOrder[#scanOrder + 1] = { tt = B.TARGET_HOSTILE,  tag = "buff:targetHostile" }
        scanOrder[#scanOrder + 1] = { tt = B.TARGET_FRIENDLY, tag = "buff:targetFriendly" }
    elseif isIncoming == false then
        scanOrder[#scanOrder + 1] = { tt = B.TARGET_HOSTILE,  tag = "buff:targetHostile" }
        scanOrder[#scanOrder + 1] = { tt = B.TARGET_FRIENDLY, tag = "buff:targetFriendly" }
        scanOrder[#scanOrder + 1] = { tt = B.SELF,            tag = "buff:self" }
    else
        scanOrder[#scanOrder + 1] = { tt = B.SELF,             tag = "buff:self" }
        scanOrder[#scanOrder + 1] = { tt = B.TARGET_HOSTILE,  tag = "buff:targetHostile" }
        scanOrder[#scanOrder + 1] = { tt = B.TARGET_FRIENDLY, tag = "buff:targetFriendly" }
    end

    local wantNorm = ""
    if type(GetAbilityName) == "function" then
        local raw = GetAbilityName(abilityId)
        if raw ~= nil then
            wantNorm = SctNormAbilityNameText(raw)
        end
    end

    for _, ent in ipairs(scanOrder) do
        if ent.tt ~= nil then
            local okList, allBuffs = CustomUI.TryCallQuiet(
                "SCTAbilityIconResolver.GetBuffs",
                GetBuffs,
                ent.tt
            )
            if okList and type(allBuffs) == "table" then
                for _, bd in pairs(allBuffs) do
                    if type(bd) == "table" and bd.iconNum and bd.iconNum > 0 then
                        local bid = tonumber(bd.abilityId)
                        if bid and bid == tonumber(abilityId) then
                            return bd.iconNum, bd.name, ent.tag
                        end
                        if wantNorm ~= "" and bd.name then
                            local bn = SctNormAbilityNameText(bd.name)
                            if bn ~= "" and (bn == wantNorm or SctStrStartsWith(bn, wantNorm) or SctStrStartsWith(wantNorm, bn)) then
                                return bd.iconNum, bd.name, ent.tag
                            end
                        end
                    end
                end
            end
        end
    end

    if now then
        CustomUI.SCT._sctBuffScanMiss[abilityId] = now
    end
    return nil, nil, nil
end

local function SctFindWeaponIconForProcAbilityId(procAbilityId)
    if not procAbilityId or procAbilityId == 0 then
        return nil
    end
    if not DataUtils or type(DataUtils.GetEquipmentData) ~= "function" then
        return nil
    end

    local wantNorm = ""
    if type(GetAbilityName) == "function" then
        local okName, rawName = CustomUI.TryCallQuiet(
            "SCTAbilityIconResolver.GetAbilityName",
            GetAbilityName,
            procAbilityId
        )
        if okName and rawName ~= nil then
            wantNorm = SctNormAbilityNameText(rawName)
        end
    end

    local TYPE_CONTINUOUS = (type(GameDefs) == "table" and GameDefs.ITEMBONUS_CONTINUOUS) or 5
    local TYPE_PROC = (type(GameDefs) == "table" and GameDefs.ITEMBONUS_PROC) or 4

    local function fieldMatchesProcAbilityId(fieldVal)
        if fieldVal == nil or fieldVal == false then
            return false
        end
        local fv = tonumber(fieldVal)
        local pid = tonumber(procAbilityId)
        if fv and pid and fv == pid then
            return true
        end
        return tostring(fieldVal) == tostring(procAbilityId)
    end

    local function bonusMatchesProcById(bonus)
        if type(bonus) ~= "table" then
            return false
        end
        local bonusType = bonus.type
        if bonusType ~= TYPE_CONTINUOUS and bonusType ~= TYPE_PROC then
            return false
        end
        return fieldMatchesProcAbilityId(bonus.reference) or fieldMatchesProcAbilityId(bonus.value)
    end

    local function normHaystackMatchesAbilityNeedle(hay, needle)
        if hay == "" or needle == "" then
            return false
        end
        if hay == needle then
            return true
        end
        if string.find(hay, needle, 1, true) ~= nil then
            return true
        end
        if SctStrStartsWith(hay, needle) or SctStrStartsWith(needle, hay) then
            return true
        end
        return false
    end

    local function passiveBonusTextMatchesAbilityName(bonus, itemLevel)
        if type(bonus) ~= "table" then
            return false
        end
        local bonusType = bonus.type
        if bonusType ~= TYPE_CONTINUOUS and bonusType ~= TYPE_PROC then
            return false
        end
        local ref = bonus.reference
        if ref == nil or ref == false or tonumber(ref) == 0 then
            return false
        end
        if type(GetAbilityDesc) ~= "function" then
            return false
        end
        local ok, desc = CustomUI.TryCallQuiet(
            "SCTAbilityIconResolver.GetAbilityDesc",
            GetAbilityDesc,
            ref,
            itemLevel or 0
        )
        if not ok or desc == nil then
            return false
        end
        local blob = SctNormAbilityNameText(desc)
        return normHaystackMatchesAbilityNeedle(blob, wantNorm)
    end

    local function itemScanBonuses(itemData, bonusPredicate)
        if type(itemData) ~= "table" then
            return false
        end
        local function scanBonusTable(bonusTable)
            if type(bonusTable) ~= "table" then
                return false
            end
            for _, bonus in pairs(bonusTable) do
                if bonusPredicate(bonus) then
                    return true
                end
            end
            return false
        end
        if scanBonusTable(itemData.bonus) then
            return true
        end
        local slots = tonumber(itemData.numEnhancementSlots) or 0
        for i = 1, slots do
            local enh = itemData.enhSlot and itemData.enhSlot[i]
            if type(enh) == "table" and scanBonusTable(enh.bonus) then
                return true
            end
        end
        return false
    end

    local function itemMatchesProcByTooltipText(itemData)
        if wantNorm == "" or type(itemData) ~= "table" then
            return false
        end
        local itemLevel = tonumber(itemData.iLevel) or 0
        if itemScanBonuses(itemData, function(bonus)
            return passiveBonusTextMatchesAbilityName(bonus, itemLevel)
        end) then
            return true
        end
        if itemData.description ~= nil then
            local descriptionNorm = SctNormAbilityNameText(itemData.description)
            if descriptionNorm ~= "" and normHaystackMatchesAbilityNeedle(descriptionNorm, wantNorm) then
                return true
            end
        end
        return false
    end

    local okEq, equipment = CustomUI.TryCallQuiet("SCTAbilityIconResolver.GetEquipmentData", DataUtils.GetEquipmentData)
    if not okEq or type(equipment) ~= "table" then
        equipment = {}
    end

    local trophy = {}
    if type(DataUtils.GetTrophyData) == "function" then
        local okTrophy, trophies = CustomUI.TryCallQuiet("SCTAbilityIconResolver.GetTrophyData", DataUtils.GetTrophyData)
        if okTrophy and type(trophies) == "table" then
            trophy = trophies
        end
    end

    local bestId, bestText = nil, nil
    local bestIdDps, bestTextDps = -1, -1
    local function considerItem(item)
        if type(item) ~= "table" or not item.iconNum or item.iconNum <= 0 then
            return
        end
        local dps = tonumber(item.dps) or 0
        if itemScanBonuses(item, bonusMatchesProcById) then
            if not bestId or dps > bestIdDps then
                bestId = item
                bestIdDps = dps
            end
        elseif itemMatchesProcByTooltipText(item) then
            if not bestText or dps > bestTextDps then
                bestText = item
                bestTextDps = dps
            end
        end
    end

    for _, item in pairs(equipment) do
        considerItem(item)
    end
    for _, item in pairs(trophy) do
        considerItem(item)
    end

    local best = bestId or bestText
    local matchKind = bestId and "bonusRef" or (bestText and "tooltipText") or nil
    if best and best.iconNum and best.iconNum > 0 then
        return best.iconNum, best, matchKind
    end

    return nil
end

local function SctStoreResolvedAbilityIcon(abilityId, iconNum, abilityData)
    CustomUI.SCT.AbilityIconSessionPut(abilityId, iconNum, abilityData)
    CustomUI.SCT.AbilityIconCacheRecordResolve(abilityId, iconNum, abilityData)
end

function Resolver.GetAbilityIconInfo(abilityId, isIncoming)
    if not abilityId or abilityId == 0 then
        return nil, nil, nil
    end

    local cachedInfo, cachedData = CustomUI.SCT.AbilityIconSessionTryGet(abilityId)
    if cachedInfo then
        return cachedInfo, cachedData, nil
    end

    local diskInfo, diskData = CustomUI.SCT.AbilityIconCacheTryLoad(abilityId, isIncoming)
    if diskInfo then
        return diskInfo, diskData, nil
    end

    local resolveSource = nil
    local data = GetAbilityData and GetAbilityData(abilityId)

    if (type(data) ~= "table" or not data.iconNum or data.iconNum <= 0)
        and type(Player) == "table"
        and type(Player.GetAbilityData) == "function"
        and type(Player.AbilityType) == "table"
    then
        local probeOrder = {
            { label = "ABILITY", v = Player.AbilityType.ABILITY },
            { label = "GRANTED", v = Player.AbilityType.GRANTED },
            { label = "PASSIVE", v = Player.AbilityType.PASSIVE },
            { label = "TACTIC", v = Player.AbilityType.TACTIC },
            { label = "MORALE", v = Player.AbilityType.MORALE },
            { label = "PET", v = Player.AbilityType.PET },
        }
        for _, entry in ipairs(probeOrder) do
            if entry.v ~= nil then
                local playerData = Player.GetAbilityData(abilityId, entry.v)
                if type(playerData) == "table" and playerData.iconNum and playerData.iconNum > 0 then
                    data = playerData
                    resolveSource = "playerDomain:" .. tostring(entry.label)
                    break
                end
            end
        end
    end

    if (type(data) ~= "table" or not data.iconNum or data.iconNum <= 0)
        and type(GetAbilityTable) == "function"
        and type(GetAbilityName) == "function"
        and type(GameData) == "table"
        and type(GameData.AbilityType) == "table"
    then
        local NORM_VER = 2
        local want = SctNormAbilityNameText(GetAbilityName(abilityId))
        if want ~= "" then
            CustomUI.SCT._abilityTableResolvedByName = CustomUI.SCT._abilityTableResolvedByName or {}
            if CustomUI.SCT._abilityTableResolvedByName[abilityId] then
                data = CustomUI.SCT._abilityTableResolvedByName[abilityId]
                resolveSource = "abilityTableName"
            else
                CustomUI.SCT._abilityTableNameIndex = CustomUI.SCT._abilityTableNameIndex or {}
                local function dbgStr(label, s)
                    s = tostring(s or "")
                    local bytes = {}
                    local n = math.min(#s, 24)
                    for i = 1, n do
                        bytes[#bytes + 1] = string.byte(s, i)
                    end
                    return label .. " len=" .. tostring(#s) .. " bytes[" .. table.concat(bytes, ",") .. "]"
                end

                local function ensureIndex(abilityTypeConst)
                    local cached = CustomUI.SCT._abilityTableNameIndex[abilityTypeConst]
                    if type(cached) == "table"
                        and cached.__count
                        and cached.__count > 0
                        and cached.__normVer == NORM_VER
                    then
                        return cached
                    end
                    local index = { __count = 0, __normVer = NORM_VER }
                    local ok, tbl = CustomUI.TryCallQuiet(
                        "SCTAbilityIconResolver.GetAbilityTable",
                        GetAbilityTable,
                        abilityTypeConst
                    )
                    if ok and type(tbl) == "table" then
                        for _, ability in pairs(tbl) do
                            if type(ability) == "table" and ability.name and ability.iconNum and ability.iconNum > 0 then
                                local key = SctNormAbilityNameText(ability.name)
                                if key ~= "" and not index[key] then
                                    index[key] = ability
                                    index.__count = index.__count + 1
                                end
                            end
                        end
                    end
                    CustomUI.SCT._abilityTableNameIndex[abilityTypeConst] = index
                    return index
                end

                local probeTypes = {
                    GameData.AbilityType.TACTIC,
                    GameData.AbilityType.PASSIVE,
                    GameData.AbilityType.GRANTED,
                    GameData.AbilityType.PET,
                    GameData.AbilityType.MORALE,
                    GameData.AbilityType.STANDARD,
                }

                local candidates = { want }
                if string.sub(want, -1) ~= "s" then
                    candidates[#candidates + 1] = want .. "s"
                else
                    candidates[#candidates + 1] = string.sub(want, 1, -2)
                end

                local found = nil
                for _, abilityType in ipairs(probeTypes) do
                    if abilityType ~= nil then
                        local idx = ensureIndex(abilityType)
                        for _, candidate in ipairs(candidates) do
                            local ability = idx and idx[candidate]
                            if ability and ability.iconNum and ability.iconNum > 0 then
                                found = ability
                                break
                            end
                        end
                        if found then
                            break
                        end
                    end
                end

                if not found then
                    for _, abilityType in ipairs(probeTypes) do
                        if abilityType ~= nil then
                            local ok, tbl = CustomUI.TryCallQuiet(
                                "SCTAbilityIconResolver.GetAbilityTable.scan",
                                GetAbilityTable,
                                abilityType
                            )
                            if ok and type(tbl) == "table" then
                                for _, ability in pairs(tbl) do
                                    if type(ability) == "table" and ability.name and ability.iconNum and ability.iconNum > 0 then
                                        local normalized = SctNormAbilityNameText(ability.name)
                                        if normalized ~= "" then
                                            for _, candidate in ipairs(candidates) do
                                                if normalized == candidate or SctStrStartsWith(normalized, candidate) or SctStrStartsWith(candidate, normalized) then
                                                    found = ability
                                                    break
                                                end
                                            end
                                        end
                                    end
                                    if found then
                                        break
                                    end
                                end
                            end
                        end
                        if found then
                            break
                        end
                    end
                end

                if found then
                    data = found
                    CustomUI.SCT._abilityTableResolvedByName[abilityId] = found
                    resolveSource = "abilityTableName"
                end

                if not found then
                    local rawName = GetAbilityName(abilityId)
                    local infoParts = {
                        dbgStr("rawName", rawName),
                        dbgStr("normName", want),
                    }
                    local parts = {}
                    for _, abilityType in ipairs(probeTypes) do
                        if abilityType ~= nil then
                            local idx = ensureIndex(abilityType)
                            local count = (type(idx) == "table" and idx.__count) or 0
                            parts[#parts + 1] = tostring(abilityType) .. "=" .. tostring(count)
                        end
                    end
                    local sample = {}
                    local function pushSample(tag, ability)
                        if #sample >= 6 then
                            return
                        end
                        sample[#sample + 1] = tag .. ":" .. tostring(ability.id) .. ":" .. tostring(ability.name) .. ":iconNum=" .. tostring(ability.iconNum)
                    end
                    local okTactic, tacticTable = CustomUI.TryCallQuiet(
                        "SCTAbilityIconResolver.GetAbilityTable.tactic",
                        GetAbilityTable,
                        GameData.AbilityType.TACTIC
                    )
                    if okTactic and type(tacticTable) == "table" then
                        for _, ability in pairs(tacticTable) do
                            if type(ability) == "table" and ability.name and ability.iconNum and ability.iconNum > 0 then
                                local normalized = SctNormAbilityNameText(ability.name)
                                if normalized ~= "" and (string.find(normalized, want, 1, true) ~= nil or string.find(want, normalized, 1, true) ~= nil) then
                                    pushSample("TACTIC", ability)
                                end
                            end
                            if #sample >= 6 then
                                break
                            end
                        end
                    end
                    local detail = "name=" .. tostring(rawName)
                        .. " candidates=" .. table.concat(candidates, "|")
                        .. " idxCounts{" .. table.concat(parts, ",") .. "}"
                        .. " {" .. table.concat(infoParts, " ; ") .. "}"
                        .. (#sample > 0 and (" samples=" .. table.concat(sample, " | ")) or "")
                    SctLogAbilityIconResolveOnce(abilityId, "abilityTableMiss", detail)
                end
            end
        end
    end

    local weaponProcAsFallback = false
    if type(data) ~= "table" or not data.iconNum or data.iconNum <= 0 then
        local procIconNum, procItem, procMatchKind = SctFindWeaponIconForProcAbilityId(abilityId)
        if procIconNum and type(GetIconData) == "function" then
            local texture = select(1, GetIconData(procIconNum))
            if texture and texture ~= "" and texture ~= "icon000000" then
                local abilityLabel = nil
                if type(GetAbilityName) == "function" then
                    abilityLabel = GetAbilityName(abilityId)
                end
                data = {
                    iconNum = procIconNum,
                    name = abilityLabel,
                    weaponFallback = true,
                }
                resolveSource = "weaponProcMatch"
                weaponProcAsFallback = true
                SctLogAbilityIconResolveOnce(
                    abilityId,
                    "weaponProcMatch",
                    procItem and ("weapon=" .. tostring(procItem.name) .. " iconNum=" .. tostring(procItem.iconNum)
                        .. " match=" .. tostring(procMatchKind or "?")) or ""
                )
            end
        end
    end

    if (type(data) ~= "table" or not data.iconNum or data.iconNum <= 0) or weaponProcAsFallback then
        local buffIcon, buffName, buffTag = SctTryBuffListIconResolve(abilityId, isIncoming)
        if buffIcon and buffIcon > 0 then
            data = { iconNum = buffIcon, name = buffName, weaponFallback = false }
            resolveSource = buffTag
        end
    end

    if type(data) ~= "table" or not data.iconNum or data.iconNum <= 0 then
        return nil, data, "iconNum<=0"
    end

    local texture, x, y = GetIconData(data.iconNum)
    if not texture or texture == "" or texture == "icon000000" then
        return nil, data, "GetIconData empty/icon000000"
    end

    local okDetail = (type(data) == "table" and data.name)
        and ("name=" .. tostring(data.name) .. " iconNum=" .. tostring(data.iconNum))
        or ("iconNum=" .. tostring(data.iconNum))
    SctLogAbilityIconResolveOnce(abilityId, resolveSource or "GetAbilityData", okDetail)
    SctStoreResolvedAbilityIcon(abilityId, data.iconNum, data)
    return { texture = texture, x = x or 0, y = y or 0 }, data, nil
end

function Resolver.DebugMissingAbilityIcon(abilityId, reason, abilityData)
    if not abilityId or abilityId == 0 then
        return
    end
    CustomUI.SCT._missingAbilityIconDbg = CustomUI.SCT._missingAbilityIconDbg or {}
    if CustomUI.SCT._missingAbilityIconDbg[abilityId] then
        return
    end
    CustomUI.SCT._missingAbilityIconDbg[abilityId] = true

    local name = nil
    if type(GetAbilityName) == "function" then
        name = GetAbilityName(abilityId)
    end
    if name == nil and type(abilityData) == "table" then
        name = abilityData.name
    end
    if name ~= nil then
        name = tostring(name)
    end
    local iconNum = (type(abilityData) == "table" and abilityData.iconNum) or nil
    local msg = "[CustomUI.SCT] missing ability icon"
        .. " abilityId=" .. tostring(abilityId)
        .. (name and (" name=" .. name) or "")
        .. (iconNum ~= nil and (" iconNum=" .. tostring(iconNum)) or "")
        .. (reason and (" (" .. tostring(reason) .. ")") or "")
    SctLogLuaWarning(msg)
end

function Resolver.DebugAbilityEventMissingAbilityId(textType, hitAmount)
    local key = "t" .. tostring(textType or "?")
    CustomUI.SCT._missingAbilityEventIdDbg = CustomUI.SCT._missingAbilityEventIdDbg or {}
    if CustomUI.SCT._missingAbilityEventIdDbg[key] then
        return
    end
    CustomUI.SCT._missingAbilityEventIdDbg[key] = true

    local msg = "[CustomUI.SCT] ability event has no abilityId"
        .. " textType=" .. tostring(textType)
        .. " hitAmount=" .. tostring(hitAmount)
        .. " (likely tactic/proc damage)"
    SctLogLuaWarning(msg)
end

function Resolver.DebugAbilityTextNoIcon(textType, hitAmount, abilityId)
    local key = "abilityTextNoIcon:" .. tostring(textType or "?") .. ":" .. tostring(abilityId or 0)
    CustomUI.SCT._abilityTextNoIconDbg = CustomUI.SCT._abilityTextNoIconDbg or {}
    if CustomUI.SCT._abilityTextNoIconDbg[key] then
        return
    end
    CustomUI.SCT._abilityTextNoIconDbg[key] = true

    local msg = "[CustomUI.SCT] Ability text had no icon"
        .. " textType=" .. tostring(textType)
        .. " abilityId=" .. tostring(abilityId)
        .. " hitAmount=" .. tostring(hitAmount)
    SctLogLuaWarning(msg)
end
