----------------------------------------------------------------
-- CustomUI.SCT — override layer (v2, deviation-only model)
-- Subclasses stock EA_System_Event* classes.  At Mode P (all settings default) this
-- file's classes are never instantiated; stock runs unmodified.  At Mode D (any
-- deviation) our trackers and entries replace stock's, delegating to stock for every
-- behaviour we do not override.
--
-- Load order: SCTSettings → SCTAnim → SCTOverrides → SCTHandlers → SCTController → SCT.xml
----------------------------------------------------------------
if not CustomUI.SCT then CustomUI.SCT = {} end

local StockEventEntry    = _G["EA_System_EventEntry"]
local StockPointGainEntry = _G["EA_System_PointGainEntry"]
local StockEventTracker  = _G["EA_System_EventTracker"]

if not StockEventEntry or not StockPointGainEntry or not StockEventTracker then
    error("CustomUI SCT: stock EA_System_Event* classes not found — load EASystem_EventText first")
end

-- Event-type constants (mirrors stock locals; exposed on namespace for handlers).
CustomUI.SCT.COMBAT_EVENT   = 1
CustomUI.SCT.POINT_GAIN     = 2
CustomUI.SCT.XP_GAIN        = 1
CustomUI.SCT.RENOWN_GAIN    = 2
CustomUI.SCT.INFLUENCE_GAIN = 3

local COMBAT_EVENT   = CustomUI.SCT.COMBAT_EVENT
local POINT_GAIN     = CustomUI.SCT.POINT_GAIN

-- Live tracker tables (keyed by targetObjectNumber).
CustomUI.SCT.EventTrackers = CustomUI.SCT.EventTrackers or {}

----------------------------------------------------------------
-- Helpers
----------------------------------------------------------------

local function SctLogLuaDebug(msg)
    if LogLuaMessage and SystemData and SystemData.UiLogFilters and type(towstring) == "function" then
        LogLuaMessage("Lua", SystemData.UiLogFilters.DEBUG, towstring(msg))
    end
end

local function SctLogLuaWarning(msg)
    if LogLuaMessage and SystemData and SystemData.UiLogFilters and type(towstring) == "function" then
        LogLuaMessage("Lua", SystemData.UiLogFilters.WARNING, towstring(msg))
    end
end

local function SctStopAnimations(w)
    if not w or not DoesWindowExist(w) then return end
    WindowStopAlphaAnimation(w)
    WindowStopPositionAnimation(w)
    WindowStopScaleAnimation(w)
end

-- Optional layout refresh (not all client builds define this).
local function SctForceProcessAnchors(w)
    if not w or w == "" then return end
    local fn = WindowUtils and WindowUtils.ForceProcessAnchors
    if type(fn) == "function" then
        fn(w)
    end
end

local function SctForgetManagedFrame(windowName)
    if FrameManager and FrameManager.m_Frames and windowName and windowName ~= "" then
        FrameManager.m_Frames[windowName] = nil
    end
end

local function SctDestroyWindow(windowName)
    if not windowName or windowName == "" then return end
    SctStopAnimations(windowName)
    SctForgetManagedFrame(windowName)
    if DoesWindowExist(windowName) then
        DestroyWindow(windowName)
    end
end

-- Reload-safe anchor creation under CustomUISCTWindow.
local function SctCreateAnchor(anchorName)
    if not DoesWindowExist("CustomUISCTWindow") then return false end
    if DoesWindowExist(anchorName) then
        SctStopAnimations(anchorName)
        DestroyWindow(anchorName)
    end
    CreateWindowFromTemplate(anchorName, "EA_Window_EventTextAnchor", "CustomUISCTWindow")
    return DoesWindowExist(anchorName)
end
CustomUI.SCT.SctCreateAnchor = SctCreateAnchor

local function SctAnchorName(targetObjectNumber)
    return "CustomUI_SCT_EventTextAnchor" .. tostring(targetObjectNumber or "unknown")
end
CustomUI.SCT.SctAnchorName = SctAnchorName

local function SctHolderName(entryWindowName)
    return tostring(entryWindowName) .. "Holder"
end

local function SctAnchorLabelToHolder(labelName, holderName, xOffset, yOffset)
    if not DoesWindowExist(labelName) or not DoesWindowExist(holderName) then return end
    WindowClearAnchors(labelName)
    WindowAddAnchor(labelName, "center", holderName, "center", xOffset or 0, yOffset or 0)
end

local function SctCreateHolder(holderName, parentWindow, animationData)
    SctDestroyWindow(holderName)
    if not parentWindow or parentWindow == "" or not DoesWindowExist(parentWindow) then
        return false
    end
    CreateWindowFromTemplate(holderName, "EA_Window_EventTextAnchor", parentWindow)
    if not DoesWindowExist(holderName) then
        return false
    end
    WindowSetOffsetFromParent(holderName, animationData.start.x, animationData.start.y)
    WindowSetShowing(holderName, true)
    return true
end

local function SctMoveEntryHolder(entry, x, y)
    local holder = entry and entry.m_HolderWindow
    if holder and DoesWindowExist(holder) then
        WindowSetOffsetFromParent(holder, x, y)
    end
    if entry and entry.UpdateAbilityIconPosition then
        entry:UpdateAbilityIconPosition()
    end
end

local function SctUpdateEntryPosition(entry, elapsedTime, simulationSpeed)
    local simulationTime = elapsedTime * (simulationSpeed or 1)
    local ad = entry.m_AnimationData
    if not ad then return 0 end

    local animationStep = simulationTime / ad.maximumDisplayTime
    local stepX = (ad.target.x - ad.start.x) * animationStep
    local stepY = (ad.target.y - ad.start.y) * animationStep

    ad.current.x = ad.current.x + stepX
    ad.current.y = ad.current.y + stepY
    SctMoveEntryHolder(entry, ad.current.x, ad.current.y)

    entry.m_LifeSpan = (entry.m_LifeSpan or 0) + simulationTime
    return entry.m_LifeSpan
end

-- Optional combat text tweaks (amount formatting / ability name suffix).
local function SctStripLeadingCombatAmountSign(wName)
    if not wName or wName == "" or not DoesWindowExist(wName) then
        return
    end
    local t = LabelGetText(wName)
    if not t or t == L"" then
        return
    end
    local c1 = wstring.sub(t, 1, 1)
    if c1 == L"+" or c1 == L"-" then
        LabelSetText(wName, wstring.sub(t, 2))
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

-- Resolve display name for the optional beside-amount suffix label (same sources as legacy inline suffix).
local function SctTryGetAbilityDisplayNameForSuffix(abilityId, hintAbilityData)
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

local function SctDestroyAbilityNameSuffix(entry)
    if not entry then return end
    local sw = entry.m_AbilityNameSuffixWindow
    if sw and entry.m_AbilityIconAnchorRightWindow == sw then
        entry.m_AbilityIconAnchorRightWindow = nil
    end
    if not sw then return end
    SctStopAnimations(sw)
    if DoesWindowExist(sw) then
        DestroyWindow(sw)
    end
    entry.m_AbilityNameSuffixWindow = nil
end

-- Second label under holder, anchored to the right of the amount label (RoR anchor quirk matches ability icon).
local function SctApplyAbilityNameSuffix(entry, wName, holderName, cleanName, fontName, scale)
    if not cleanName or cleanName == "" or not wName or wName == "" or not DoesWindowExist(wName) then
        return false
    end
    if not holderName or holderName == "" or not DoesWindowExist(holderName) then
        return false
    end
    local suffixWin = wName .. "AbilityNameSuffix"
    if DoesWindowExist(suffixWin) then
        DestroyWindow(suffixWin)
    end
    CreateWindowFromTemplate(suffixWin, "CustomUI_SCTAbilityNameSuffix", holderName)
    if not DoesWindowExist(suffixWin) then
        return false
    end

    LabelSetText(suffixWin, L" (" .. towstring(cleanName) .. L")")
    if fontName and fontName ~= "" and fontName ~= "font_default_text_large" then
        LabelSetFont(suffixWin, fontName, WindowUtils.FONT_DEFAULT_TEXT_LINESPACING)
    end
    if type(LabelGetTextColor) == "function" then
        local r, g, b = LabelGetTextColor(wName)
        if r ~= nil and g ~= nil and b ~= nil then
            LabelSetTextColor(suffixWin, r, g, b)
        end
    end
    LabelSetTextAlign(suffixWin, "left")

    local sc = scale or 1.0
    WindowSetScale(suffixWin, sc)
    WindowSetRelativeScale(suffixWin, sc)

    local sufW, sufH = LabelGetTextDimensions(suffixWin)
    sufW = (sufW and sufW > 0) and sufW or 40
    sufH = (sufH and sufH > 0) and sufH or 24
    WindowSetDimensions(suffixWin, sufW, sufH)

    local _, mainH = LabelGetTextDimensions(wName)
    mainH = (mainH and mainH > 0) and mainH or sufH
    local yOff = math.floor(((mainH - sufH) / 2) + 0.5)
    -- Same inverted pairing as SctPositionAbilityIcon ("after text"): places suffix to the RIGHT of the amount.
    local gap = math.floor((2 * sc) + 0.5)
    WindowClearAnchors(suffixWin)
    WindowAddAnchor(suffixWin, "topright", wName, "topleft", gap, yOff)
    SctForceProcessAnchors(suffixWin)
    WindowSetShowing(suffixWin, true)

    entry.m_AbilityNameSuffixWindow = suffixWin
    entry.m_AbilityIconAnchorRightWindow = suffixWin
    return true
end

-- Merge icon resolver payload with a name-only peek so suffix can use disk/session name when
-- GetAbilityData(abilityId).name is empty but persistent/session cache has the label.
local function SctMergeAbilityNameHintForSuffix(preIconAbilityData, abilityId, abilityLine, sct)
    if not abilityLine or not sct or sct.showAbilityNameInText ~= true or not abilityId or abilityId == 0 then
        return preIconAbilityData
    end
    local h = CustomUI.SCT.AbilityIconCachePeekHint(abilityId)
    if not h or not h.name then
        return preIconAbilityData
    end
    if type(preIconAbilityData) ~= "table" then
        return h
    end
    if preIconAbilityData.name == nil or tostring(preIconAbilityData.name or "") == "" then
        local m = {}
        for k, v in pairs(preIconAbilityData) do
            m[k] = v
        end
        m.name = h.name
        return m
    end
    return preIconAbilityData
end

-- Ability icon helpers --------------------------------------------------------

-- Normalized ability/buff name for cross-source matching (matches GetAbilityTable path).
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

-- Prefix match without allocating substrings (used by buff scan + proc/equipment matching).
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

-- Scan live buff lists (player + current target) when ability tables lack iconNum.
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
        local ok, t = pcall(GetGameTime)
        if ok then now = tonumber(t) end
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
        scanOrder[#scanOrder + 1] = { tt = B.SELF,             tag = "buff:self" }
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
            local okList, allBuffs = pcall(GetBuffs, ent.tt)
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

    -- Normalized combat ability label (GetAbilityName); used when bonus.reference != combat abilityId.
    local wantNorm = ""
    if type(GetAbilityName) == "function" then
        local okN, rawName = pcall(GetAbilityName, procAbilityId)
        if okN and rawName ~= nil then
            wantNorm = SctNormAbilityNameText(rawName)
        end
    end

    -- Stock GameDefs (easystem_utils/gamedefs.lua): CONTINUOUS=5 links proc text via GetAbilityDesc(reference).
    -- ITEMBONUS_PROC=4 exists for the same reference pattern on some data paths; do not require GameDefs
    -- table (load order) — fall back to numeric literals.
    local TYPE_CONTINUOUS = (type(GameDefs) == "table" and GameDefs.ITEMBONUS_CONTINUOUS) or 5
    local TYPE_PROC = (type(GameDefs) == "table" and GameDefs.ITEMBONUS_PROC) or 4

    -- Match combat abilityId to item bonus rows. Stock tooltips use reference for GetAbilityDesc;
    -- gamedefs also documents value for some CONTINUOUS rows — check both.
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

    local function bonusMatchesProcById(b)
        if type(b) ~= "table" then
            return false
        end
        local t = b.type
        if t ~= TYPE_CONTINUOUS and t ~= TYPE_PROC then
            return false
        end
        return fieldMatchesProcAbilityId(b.reference) or fieldMatchesProcAbilityId(b.value)
    end

    -- Tooltip-style proc text (same source as ItemUtils passives): compare normalized strings when IDs differ.
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

    local function passiveBonusTextMatchesAbilityName(b, itemLevel)
        if type(b) ~= "table" then
            return false
        end
        local t = b.type
        if t ~= TYPE_CONTINUOUS and t ~= TYPE_PROC then
            return false
        end
        local ref = b.reference
        if ref == nil or ref == false or tonumber(ref) == 0 then
            return false
        end
        if type(GetAbilityDesc) ~= "function" then
            return false
        end
        local ok, desc = pcall(GetAbilityDesc, ref, itemLevel or 0)
        if not ok or desc == nil then
            return false
        end
        local blob = SctNormAbilityNameText(desc)
        return normHaystackMatchesAbilityNeedle(blob, wantNorm)
    end

    -- Base bonuses + enhancement slots (same traversal as itemtooltips).
    local function itemScanBonuses(itemData, bonusPred)
        if type(itemData) ~= "table" then
            return false
        end
        local function scanBonusTable(bonusTbl)
            if type(bonusTbl) ~= "table" then
                return false
            end
            for _, b in pairs(bonusTbl) do
                if bonusPred(b) then
                    return true
                end
            end
            return false
        end
        if scanBonusTable(itemData.bonus) then
            return true
        end
        local n = tonumber(itemData.numEnhancementSlots) or 0
        for i = 1, n do
            local es = itemData.enhSlot and itemData.enhSlot[i]
            if type(es) == "table" and scanBonusTable(es.bonus) then
                return true
            end
        end
        return false
    end

    local function itemMatchesProcById(itemData)
        return itemScanBonuses(itemData, bonusMatchesProcById)
    end

    local function itemMatchesProcByTooltipText(itemData)
        if wantNorm == "" or type(itemData) ~= "table" then
            return false
        end
        local ilevel = tonumber(itemData.iLevel) or 0
        local function bonusMatchesTooltip(b)
            return passiveBonusTextMatchesAbilityName(b, ilevel)
        end
        if itemScanBonuses(itemData, bonusMatchesTooltip) then
            return true
        end
        -- Rare: proc name only on item flavor/description line.
        if itemData.description ~= nil then
            local dn = SctNormAbilityNameText(itemData.description)
            if dn ~= "" and normHaystackMatchesAbilityNeedle(dn, wantNorm) then
                return true
            end
        end
        return false
    end

    local ok, eq = pcall(DataUtils.GetEquipmentData)
    if not ok or type(eq) ~= "table" then
        eq = {}
    end

    local trophy = {}
    if type(DataUtils.GetTrophyData) == "function" then
        local okT, tr = pcall(DataUtils.GetTrophyData)
        if okT and type(tr) == "table" then
            trophy = tr
        end
    end

    -- Prefer ID match; else tooltip/description text match. Higher DPS breaks ties (dual wield).
    local bestId, bestText = nil, nil
    local bestIdDps, bestTextDps = -1, -1
    local function considerItem(item)
        if type(item) ~= "table" or not item.iconNum or item.iconNum <= 0 then
            return
        end
        local dps = tonumber(item.dps) or 0
        if itemMatchesProcById(item) then
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

    for _, item in pairs(eq) do
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

-- Session + persistent icon hints live in SCTAbilityIconCache.lua (LRU disk, RAM fast path).
local function SctStoreResolvedAbilityIcon(abilityId, iconNum, abilityData)
    CustomUI.SCT.AbilityIconSessionPut(abilityId, iconNum, abilityData)
    CustomUI.SCT.AbilityIconCacheRecordResolve(abilityId, iconNum, abilityData)
end

local function SctGetAbilityIconInfo(abilityId, isIncoming)
    if not abilityId or abilityId == 0 then return nil, nil, nil end

    local cachedInfo, cachedData = CustomUI.SCT.AbilityIconSessionTryGet(abilityId)
    if cachedInfo then
        return cachedInfo, cachedData, nil
    end

    local diskInfo, diskData = CustomUI.SCT.AbilityIconCacheTryLoad(abilityId, isIncoming)
    if diskInfo then
        return diskInfo, diskData, nil
    end

    local resolveSource = nil

    -- Primary path: combat ability data
    local data = GetAbilityData and GetAbilityData(abilityId)

    -- Fallback: ask Player's ability domains (tactics/morale/granted/passive/pet/etc).
    -- This is NOT a hardcoded mapping; it's probing the client’s own ability stores.
    if (type(data) ~= "table" or not data.iconNum or data.iconNum <= 0)
        and type(Player) == "table"
        and type(Player.GetAbilityData) == "function"
        and type(Player.AbilityType) == "table"
    then
        local probeOrder = {
            { label = "ABILITY",  v = Player.AbilityType.ABILITY },
            { label = "GRANTED",  v = Player.AbilityType.GRANTED },
            { label = "PASSIVE",  v = Player.AbilityType.PASSIVE },
            { label = "TACTIC",   v = Player.AbilityType.TACTIC },
            { label = "MORALE",   v = Player.AbilityType.MORALE },
            { label = "PET",      v = Player.AbilityType.PET },
        }
        for _, ent in ipairs(probeOrder) do
            if ent.v ~= nil then
                local pData = Player.GetAbilityData(abilityId, ent.v)
                if type(pData) == "table" and pData.iconNum and pData.iconNum > 0 then
                    data = pData
                    resolveSource = "playerDomain:" .. tostring(ent.label)
                    break
                end
            end
        end
    end

    -- Fallback: search the client-side ability tables by NAME and use the first iconNum found.
    -- This helps for proc/tactic sub-abilities where the combat abilityId has iconNum=0 but the
    -- corresponding tactic/passive entry has a valid iconNum.
    if (type(data) ~= "table" or not data.iconNum or data.iconNum <= 0)
        and type(GetAbilityTable) == "function"
        and type(GetAbilityName) == "function"
        and type(GameData) == "table"
        and type(GameData.AbilityType) == "table"
    then
        local NORM_VER = 2

        local want = SctNormAbilityNameText(GetAbilityName(abilityId))
        if want ~= "" then
            -- Cache per missing combat abilityId so we only do the heavier scan once.
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
                    -- Cache can be created too early (empty ability tables at login). If the cached
                    -- index is empty, rebuild on demand.
                    local cached = CustomUI.SCT._abilityTableNameIndex[abilityTypeConst]
                    if type(cached) == "table"
                        and cached.__count
                        and cached.__count > 0
                        and cached.__normVer == NORM_VER
                    then
                        return cached
                    end
                    local t = { __count = 0, __normVer = NORM_VER }
                    local ok, tbl = pcall(GetAbilityTable, abilityTypeConst)
                    if ok and type(tbl) == "table" then
                        for _, a in pairs(tbl) do
                            if type(a) == "table" and a.name and a.iconNum and a.iconNum > 0 then
                                local k = SctNormAbilityNameText(a.name)
                                if k ~= "" and not t[k] then
                                    t[k] = a
                                    t.__count = t.__count + 1
                                end
                            end
                        end
                    end
                    CustomUI.SCT._abilityTableNameIndex[abilityTypeConst] = t
                    return t
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
                -- Heuristics: pluralize whole string, and also singularize.
                if string.sub(want, -1) ~= "s" then
                    candidates[#candidates + 1] = want .. "s"
                else
                    candidates[#candidates + 1] = string.sub(want, 1, -2)
                end

                local found = nil
                for _, ty in ipairs(probeTypes) do
                    if ty ~= nil then
                        local idx = ensureIndex(ty)
                        for _, cand in ipairs(candidates) do
                            local a = idx and idx[cand]
                            if a and a.iconNum and a.iconNum > 0 then
                                found = a
                                break
                            end
                        end
                        if found then break end
                    end
                end

                -- If exact name lookup fails, do a cheap prefix match scan against the live table.
                -- This catches cases where the engine adds hidden suffixes, spacing, or formatting,
                -- but the normalized name still begins with the combat name (e.g. Enchantment → Enchantments).
                if not found then
                    for _, ty in ipairs(probeTypes) do
                        if ty ~= nil then
                            local ok, tbl = pcall(GetAbilityTable, ty)
                            if ok and type(tbl) == "table" then
                                for _, a in pairs(tbl) do
                                    if type(a) == "table" and a.name and a.iconNum and a.iconNum > 0 then
                                        local n = SctNormAbilityNameText(a.name)
                                        if n ~= "" then
                                            for _, cand in ipairs(candidates) do
                                                if n == cand or SctStrStartsWith(n, cand) or SctStrStartsWith(cand, n) then
                                                    found = a
                                                    break
                                                end
                                            end
                                        end
                                    end
                                    if found then break end
                                end
                            end
                        end
                        if found then break end
                    end
                end

                if found then
                    data = found
                    CustomUI.SCT._abilityTableResolvedByName[abilityId] = found
                    resolveSource = "abilityTableName"
                end
                -- If we still didn't find anything, log once so we can diagnose the miss.
                if not found then
                    local rawName = GetAbilityName(abilityId)
                    local infoParts = {
                        dbgStr("rawName", rawName),
                        dbgStr("normName", want),
                    }
                    local parts = {}
                    for _, ty in ipairs(probeTypes) do
                        if ty ~= nil then
                            local idx = ensureIndex(ty)
                            local cnt = (type(idx) == "table" and idx.__count) or 0
                            parts[#parts + 1] = tostring(ty) .. "=" .. tostring(cnt)
                        end
                    end
                    -- Try to find a "nearby" candidate in the TACTIC table by prefix and log the first few.
                    local sample = {}
                    local function pushSample(tag, a)
                        if #sample >= 6 then return end
                        sample[#sample + 1] = tag .. ":" .. tostring(a.id) .. ":" .. tostring(a.name) .. ":iconNum=" .. tostring(a.iconNum)
                    end
                    local okT, tblT = pcall(GetAbilityTable, GameData.AbilityType.TACTIC)
                    if okT and type(tblT) == "table" then
                        for _, a in pairs(tblT) do
                            if type(a) == "table" and a.name and a.iconNum and a.iconNum > 0 then
                                local nn = SctNormAbilityNameText(a.name)
                                if nn ~= "" and (string.find(nn, want, 1, true) ~= nil or string.find(want, nn, 1, true) ~= nil) then
                                    pushSample("TACTIC", a)
                                end
                            end
                            if #sample >= 6 then break end
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

    -- Weapon proc (gear ITEMBONUS_CONTINUOUS reference == abilityId): works without a target.
    -- Use before GetBuffs so direct-hit / no-target lines still show the proc item icon; buff scan
    -- may replace with the on-unit effect icon once a target/self lists the DoT.
    local weaponProcAsFallback = false
    if (type(data) ~= "table" or not data.iconNum or data.iconNum <= 0) then
        local procIconNum, procItem, procMatchKind = SctFindWeaponIconForProcAbilityId(abilityId)
        if procIconNum and type(GetIconData) == "function" then
            local ptex, _, _ = GetIconData(procIconNum)
            if ptex and ptex ~= "" and ptex ~= "icon000000" then
                local abiLabel = nil
                if type(GetAbilityName) == "function" then
                    abiLabel = GetAbilityName(abilityId)
                end
                data = {
                    iconNum = procIconNum,
                    name = abiLabel,
                    weaponFallback = true,
                }
                resolveSource = "weaponProcMatch"
                weaponProcAsFallback = true
                SctLogAbilityIconResolveOnce(abilityId, "weaponProcMatch",
                    procItem and ("weapon=" .. tostring(procItem.name) .. " iconNum=" .. tostring(procItem.iconNum)
                        .. " match=" .. tostring(procMatchKind or "?")) or "")
            end
        end
    end

    -- Live buff lists: by abilityId or normalized name; may refine weaponProcMatch for DoTs on target.
    if (type(data) ~= "table" or not data.iconNum or data.iconNum <= 0) or weaponProcAsFallback then
        local bIcon, bName, bTag = SctTryBuffListIconResolve(abilityId, isIncoming)
        if bIcon and bIcon > 0 then
            data = { iconNum = bIcon, name = bName, weaponFallback = false }
            resolveSource = bTag
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

local function SctDbgMissingAbilityIcon(abilityId, reason, abilityData)
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
    -- Do not TextLogAddEntry here: some client builds do not have a TextLog named "uilog"
    -- and the engine will spam errors.
end

local function SctDbgAbilityEventMissingAbilityId(textType, hitAmount)
    -- De-dupe by textType only; procs can be frequent.
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
    -- Do not TextLogAddEntry here: some client builds do not have a TextLog named "uilog".
end

local function SctDbgAbilityTextNoIcon(textType, hitAmount, abilityId)
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
    -- Do not TextLogAddEntry here: some client builds do not have a TextLog named "uilog".
end

local function SctCreateAbilityIcon(iconWinName, parentWinName, iconInfo, textH, abilityData)
    if not iconInfo or not DoesWindowExist(parentWinName) then return false end
    if DoesWindowExist(iconWinName) then DestroyWindow(iconWinName) end
    CreateWindowFromTemplate(iconWinName, "CustomUI_SCTAbilityIcon", parentWinName)
    if not DoesWindowExist(iconWinName) then return false end

    local size = math.floor(math.max(12, (textH or 24) * 0.9))
    WindowSetDimensions(iconWinName, size, size)
    DynamicImageSetTexture(iconWinName .. "Icon", iconInfo.texture, iconInfo.x, iconInfo.y)
    DynamicImageSetTextureDimensions(iconWinName .. "Icon", 64, 64)

    -- Frame border: same approach as BuffTracker (EA_SquareFrame tinted by ability type).
    if DoesWindowExist(iconWinName .. "Frame") then
        DynamicImageSetTexture(iconWinName .. "Frame", "EA_SquareFrame", 0, 0)
        DynamicImageSetTextureDimensions(iconWinName .. "Frame", 64, 64)
        WindowSetDimensions(iconWinName .. "Frame", size, size)

        local r, g, b
        if abilityData and DataUtils and DataUtils.GetAbilityTypeTextureAndColor then
            local _, _, _, rr, gg, bb = DataUtils.GetAbilityTypeTextureAndColor(abilityData)
            r, g, b = rr, gg, bb
        end
        if r and g and b then
            WindowSetTintColor(iconWinName .. "Frame", r, g, b)
        else
            WindowSetTintColor(iconWinName .. "Frame", 255, 255, 255)
        end
    end

    WindowSetShowing(iconWinName, true)
    return true
end

local function SctDestroyAbilityIcon(entry)
    if not entry.m_AbilityIconWindow then return end
    SctStopAnimations(entry.m_AbilityIconWindow)
    if DoesWindowExist(entry.m_AbilityIconWindow) then
        DestroyWindow(entry.m_AbilityIconWindow)
    end
    entry.m_AbilityIconWindow = nil
end

local function SctPositionAbilityIcon(entry, iconWinName, textW, textH)
    if not DoesWindowExist(iconWinName) or not DoesWindowExist(entry:GetName()) then return end

    -- IMPORTANT: LabelGetTextDimensions can change after scale/font updates, and crit animations
    -- can drive scale over time (pulse). Re-measure whenever we lay out the icon.
    local wName = entry:GetName()
    local before = CustomUI.SCT.GetAbilityIconBeforeText and CustomUI.SCT.GetAbilityIconBeforeText()
    -- Icon after text: attach to the right edge of the optional ability-name suffix label when present.
    local anchorRight = wName
    if not before and entry.m_AbilityIconAnchorRightWindow and entry.m_AbilityIconAnchorRightWindow ~= ""
        and DoesWindowExist(entry.m_AbilityIconAnchorRightWindow)
    then
        anchorRight = entry.m_AbilityIconAnchorRightWindow
    end

    local _, mainH = LabelGetTextDimensions(wName)
    local curW, curH = LabelGetTextDimensions(anchorRight)
    if curW and curW > 0 then textW = curW end
    if curH and curH > 0 then textH = curH end
    if mainH and mainH > 0 then textH = mainH end
    textW = (textW and textW > 0) and textW or 80
    textH = (textH and textH > 0) and textH or 24

    local scale = entry.m_CurrentVisualScale or entry.m_EffectiveScale or 1.0

    -- Keep the icon window at a stable base size and scale it with the entry, so the crit pulse
    -- (WindowSetScale on the label) produces matching motion/scale without width-drift.
    local baseSize = math.floor(math.max(12, textH * 0.9))
    WindowSetDimensions(iconWinName, baseSize, baseSize)
    WindowSetScale(iconWinName, scale)
    WindowSetRelativeScale(iconWinName, scale)

    WindowClearAnchors(iconWinName)

    -- Anchor direction note (RoR client quirk): "point" behaves like the target side in practice,
    -- so to place the icon to the RIGHT of the label we use point=topright → relativePoint=topleft.
    -- (This is intentionally inverted from the usual UI convention.)
    -- User-tuned spacing: 10px at scale 1.0, multiplied by effective visual scale.
    local gap = math.floor((10 * scale) + 0.5)
    local yOff = math.floor(((textH - baseSize) / 2) + 0.5) - math.floor((3 * scale) + 0.5)
    if before then
        -- Mirror of the "icon after text" case: inverted client anchor semantics (see comment above).
        WindowAddAnchor(iconWinName, "topleft", wName, "topright", -gap, yOff)
    else
        WindowAddAnchor(iconWinName, "topright", anchorRight, "topleft", gap, yOff)
    end
    SctForceProcessAnchors(iconWinName)
end

----------------------------------------------------------------
-- Crit effects (from SCTAnim — loaded before this file)
----------------------------------------------------------------

local function SctGetEffects()
    return CustomUI.SCT._SctAnim and CustomUI.SCT._SctAnim.Effects
end

----------------------------------------------------------------
-- CustomUI.SCT.EventEntry
-- Template: CustomUI_Window_EventTextLabel (our label, 400×100, textalign=center)
----------------------------------------------------------------

CustomUI.SCT.EventEntry = StockEventEntry:Subclass("CustomUI_Window_EventTextLabel")

function CustomUI.SCT.EventEntry:Create(windowName, parentWindow, animationData)
    local holderName = SctHolderName(windowName)
    SctDestroyWindow(windowName)
    if not SctCreateHolder(holderName, parentWindow, animationData) then
        return nil
    end

    local frame = StockEventEntry.Create(self, windowName, holderName, animationData)
    if frame then
        frame.m_Anchor = parentWindow
        frame.m_HolderWindow = holderName
        frame.m_VisualOffsetX = 0
        frame.m_VisualOffsetY = 0
        SctAnchorLabelToHolder(windowName, holderName, 0, 0)
        SctMoveEntryHolder(frame, frame.m_AnimationData.current.x, frame.m_AnimationData.current.y)
    end
    return frame
end

function CustomUI.SCT.EventEntry:SetVisualOffset(x, y)
    self.m_VisualOffsetX = x or 0
    self.m_VisualOffsetY = y or 0
    SctAnchorLabelToHolder(self:GetName(), self.m_HolderWindow, self.m_VisualOffsetX, self.m_VisualOffsetY)
    self:UpdateAbilityIconPosition()
end

function CustomUI.SCT.EventEntry:SetVisualScale(scale)
    local wName = self:GetName()
    if not DoesWindowExist(wName) then return end
    self.m_CurrentVisualScale = scale or self.m_EffectiveScale or 1.0
    WindowSetScale(wName, self.m_CurrentVisualScale)
    WindowSetRelativeScale(wName, self.m_CurrentVisualScale)
    local sfx = self.m_AbilityNameSuffixWindow
    if sfx and sfx ~= "" and DoesWindowExist(sfx) then
        WindowSetScale(sfx, self.m_CurrentVisualScale)
        WindowSetRelativeScale(sfx, self.m_CurrentVisualScale)
    end
    self:UpdateAbilityIconLayout()
end

function CustomUI.SCT.EventEntry:UpdateAbilityIconLayout()
    if not self.m_AbilityIconWindow or not DoesWindowExist(self.m_AbilityIconWindow) then return end
    SctPositionAbilityIcon(
        self,
        self.m_AbilityIconWindow,
        self.m_AbilityIconTextW,
        self.m_AbilityIconTextH
    )
end

function CustomUI.SCT.EventEntry:UpdateAbilityIconPosition()
    if not self.m_AbilityIconWindow or not DoesWindowExist(self.m_AbilityIconWindow) then return end
    -- Icon is anchored to the label; movement happens through anchor resolution.
    SctForceProcessAnchors(self.m_AbilityIconWindow)
end

function CustomUI.SCT.EventEntry:SetupText(hitTargetObjectNumber, hitAmount, textType, abilityId)
    -- 1. Stock renders text, color, and alpha.
    StockEventEntry.SetupText(self, hitTargetObjectNumber, hitAmount, textType)

    local wName = self:GetName()
    SctDestroyAbilityNameSuffix(self)
    self.m_AbilityIconAnchorRightWindow = nil

    local sct   = CustomUI.SCT.GetSettings()

    local isHitOrCrit = (textType == GameData.CombatEvent.HIT)
                     or (textType == GameData.CombatEvent.ABILITY_HIT)
                     or (textType == GameData.CombatEvent.CRITICAL)
                     or (textType == GameData.CombatEvent.ABILITY_CRITICAL)
    local abilityLine = (textType == GameData.CombatEvent.ABILITY_HIT)
                     or (textType == GameData.CombatEvent.ABILITY_CRITICAL)

    local isIncoming = (type(GameData) == "table" and GameData.Player
        and hitTargetObjectNumber == GameData.Player.worldObjNum)

    -- Pre-resolve ability icon / hint data once so name suffix and icon share cache (session + disk).
    local preIconInfo, preIconAbilityData, preIconReason = nil, nil, nil
    if abilityId and abilityId ~= 0 then
        if sct.showAbilityIcon then
            preIconInfo, preIconAbilityData, preIconReason = SctGetAbilityIconInfo(abilityId, isIncoming)
        end
    end
    local nameHintAbilityData = preIconAbilityData
    if abilityLine and sct.showAbilityNameInText and abilityId and abilityId ~= 0 then
        nameHintAbilityData = SctMergeAbilityNameHintForSuffix(preIconAbilityData, abilityId, abilityLine, sct)
    end

    local suffixClean = nil
    if abilityLine and sct.showAbilityNameInText and abilityId and abilityId ~= 0 then
        suffixClean = SctTryGetAbilityDisplayNameForSuffix(abilityId, nameHintAbilityData)
    end

    -- 1b. Optional text mutations (must run before font/scale so measurements match on-screen text).
    if isHitOrCrit then
        SctStripLeadingCombatAmountSign(wName)
    end
    -- Left-align only when we render a beside-text ability icon (measured width + holder layout).
    -- Ability-name suffix alone stays stock-centered so horizontal anchor matches vanilla SCT.
    local layoutLeft = (preIconInfo ~= nil)
    if layoutLeft then
        LabelSetTextAlign(wName, "left")
    else
        LabelSetTextAlign(wName, "center")
    end

    -- 2. Direction and key (isIncoming computed above).
    local key = CustomUI.SCT.KeyForCombatType(textType)
    if isHitOrCrit and hitAmount > 0 then key = "Heal" end

    local isCrit = (textType == GameData.CombatEvent.CRITICAL)
                or (textType == GameData.CombatEvent.ABILITY_CRITICAL)
    self.m_IsCrit = isCrit

    local iconInfo, iconAbilityData, iconReason
    if sct.showAbilityIcon then
        -- If this is an "ability" combat event but abilityId is missing/0, it's often a proc/tactic.
        if (textType == GameData.CombatEvent.ABILITY_HIT or textType == GameData.CombatEvent.ABILITY_CRITICAL)
            and (not abilityId or abilityId == 0)
        then
            SctDbgAbilityEventMissingAbilityId(textType, hitAmount)
        end

        iconInfo, iconAbilityData, iconReason = preIconInfo, preIconAbilityData, preIconReason
        -- If the row is "Ability" but we still have no icon, log it (covers non-ABILITY_* edge cases).
        if not iconInfo and key == "Ability" then
            SctDbgAbilityTextNoIcon(textType, hitAmount, abilityId)
        end
        if not iconInfo and abilityId and abilityId ~= 0 then
            local ad = iconAbilityData
            if type(ad) ~= "table" then
                -- If we got no table at all, probe once for a clearer message.
                ad = GetAbilityData and GetAbilityData(abilityId)
            end
            if type(ad) ~= "table" then
                SctDbgMissingAbilityIcon(abilityId, "GetAbilityData returned nil", nil)
            elseif not ad.iconNum then
                SctDbgMissingAbilityIcon(abilityId, "abilityData.iconNum missing", ad)
            elseif ad.iconNum <= 0 then
                SctDbgMissingAbilityIcon(abilityId, "abilityData.iconNum<=0", ad)
            else
                -- If iconNum was present but texture resolve failed, keep the more specific reason.
                SctDbgMissingAbilityIcon(abilityId, iconReason or "GetIconData returned empty/icon000000", ad)
            end
        end
    end

    -- 3. Font override.
    local fontName = CustomUI.SCT.GetTextFontName()
    if fontName ~= "font_default_text_large" then
        LabelSetFont(wName, fontName, WindowUtils.FONT_DEFAULT_TEXT_LINESPACING)
    end

    -- 4. Color override (custom RGB > preset > stock default already set by stock).
    local tr, tg, tb
    local colorIdx, customRGB
    if isIncoming then
        colorIdx  = CustomUI.SCT.GetColorIndex("incoming", key)
        customRGB = CustomUI.SCT.GetCustomColor("incoming", key)
    else
        colorIdx  = CustomUI.SCT.GetColorIndex("outgoing", key)
        customRGB = CustomUI.SCT.GetCustomColor("outgoing", key)
    end
    if customRGB and customRGB[1] then
        tr, tg, tb = customRGB[1], customRGB[2], customRGB[3]
        LabelSetTextColor(wName, tr, tg, tb)
    elseif colorIdx and colorIdx > 1 then
        local opt = CustomUI.SCT.COLOR_OPTIONS[colorIdx]
        if opt and opt.rgb then
            tr, tg, tb = opt.rgb[1], opt.rgb[2], opt.rgb[3]
            LabelSetTextColor(wName, tr, tg, tb)
        end
    end
    -- Store target color for crit color-flash restore.
    self.m_TargetR = tr
    self.m_TargetG = tg
    self.m_TargetB = tb

    -- 5. Scale: per-type size × critSizeScale (crits only).
    local sizeTable = isIncoming and sct.incoming or sct.outgoing
    local scale = (sizeTable and sizeTable.size and sizeTable.size[key]) or 1.0
    if isCrit then
        scale = scale * (sct.critSizeScale or 1.0)
    end
    self.m_EffectiveScale = scale
    self:SetVisualScale(scale)

    -- Tight amount-label bounds before optional name suffix / icon (template is 400×100).
    local needsTightMain = (suffixClean ~= nil) or (iconInfo ~= nil)
    if needsTightMain then
        local tw, th = LabelGetTextDimensions(wName)
        tw = (tw and tw > 0) and tw or 80
        th = (th and th > 0) and th or 24
        WindowSetDimensions(wName, tw, th)
    end

    local holderName = self.m_HolderWindow
    if suffixClean and holderName and holderName ~= "" and DoesWindowExist(holderName) then
        SctApplyAbilityNameSuffix(self, wName, holderName, suffixClean, fontName, scale)
    end

    -- 6. Ability icon. Parent it to the same holder as the label so it cannot drift
    -- away from the text during animations/offsets; we still position it using measured
    -- glyph extents so it sits to the right of the rendered number (and name suffix if any).
    if iconInfo then
        local textW, textH = LabelGetTextDimensions(wName)
        textW = (textW and textW > 0) and textW or 80
        textH = (textH and textH > 0) and textH or 24

        if not needsTightMain then
            WindowSetDimensions(wName, textW, textH)
        end

        local iconWin = wName .. "AbilityIcon"
        local parent  = self.m_HolderWindow
        local abilityData = iconAbilityData or (abilityId and GetAbilityData and GetAbilityData(abilityId))
        if parent and parent ~= "" and DoesWindowExist(parent) then
            if SctCreateAbilityIcon(iconWin, parent, iconInfo, textH, abilityData) then
                self.m_AbilityIconWindow = iconWin
                self.m_AbilityIconTextW = textW
                self.m_AbilityIconTextH = textH
                SctPositionAbilityIcon(self, iconWin, textW, textH)
            end
        end
    end

    -- 7. Store crit effect timer.
    self.m_CritT = 0
end

function CustomUI.SCT.EventEntry:Update(elapsedTime, simulationSpeed)
    local lifeElapsed = SctUpdateEntryPosition(self, elapsedTime, simulationSpeed)

    if self.m_IsCrit then
        local sh, pu, cf = CustomUI.SCT.GetCritFlags()
        if sh or pu or cf then
            local Effects = SctGetEffects()
            if Effects then
                local simTime = elapsedTime * (simulationSpeed or 1)
                self.m_CritT = (self.m_CritT or 0) + simTime
                local t = self.m_CritT
                if sh and Effects.Shake  then Effects.Shake.Apply(self, t)  end
                if pu and Effects.Pulse  then Effects.Pulse.Apply(self, t)  end
                if cf and Effects.ColorFlash then
                    Effects.ColorFlash.Apply(self, t, self.m_TargetR, self.m_TargetG, self.m_TargetB)
                end
            end
        else
            self:SetVisualOffset(0, 0)
        end
    else
        self:SetVisualOffset(0, 0)
    end

    return lifeElapsed
end

function CustomUI.SCT.EventEntry:Destroy()
    SctDestroyAbilityIcon(self)
    SctDestroyAbilityNameSuffix(self)
    self.m_AbilityIconAnchorRightWindow = nil
    SctStopAnimations(self:GetName())
    SctDestroyWindow(self:GetName())
    SctDestroyWindow(self.m_HolderWindow)
end

----------------------------------------------------------------
-- CustomUI.SCT.PointGainEntry
----------------------------------------------------------------

CustomUI.SCT.PointGainEntry = StockPointGainEntry:Subclass("CustomUI_Window_EventTextLabel")

function CustomUI.SCT.PointGainEntry:Create(windowName, parentWindow, animationData)
    local holderName = SctHolderName(windowName)
    SctDestroyWindow(windowName)
    if not SctCreateHolder(holderName, parentWindow, animationData) then
        return nil
    end

    local frame = StockPointGainEntry.Create(self, windowName, holderName, animationData)
    if frame then
        frame.m_Anchor = parentWindow
        frame.m_HolderWindow = holderName
        SctAnchorLabelToHolder(windowName, holderName, 0, 0)
        SctMoveEntryHolder(frame, frame.m_AnimationData.current.x, frame.m_AnimationData.current.y)
    end
    return frame
end

function CustomUI.SCT.PointGainEntry:SetupText(hitTargetObjectNumber, pointAmount, pointType)
    -- 1. Stock renders text, color, alpha.
    StockPointGainEntry.SetupText(self, hitTargetObjectNumber, pointAmount, pointType)

    local wName = self:GetName()
    local sct   = CustomUI.SCT.GetSettings()
    local key   = CustomUI.SCT.KeyForPointType(pointType)

    -- 2. Font override.
    local fontName = CustomUI.SCT.GetTextFontName()
    if fontName ~= "font_default_text_large" then
        LabelSetFont(wName, fontName, WindowUtils.FONT_DEFAULT_TEXT_LINESPACING)
    end

    -- 3. Color override.
    local colorIdx  = CustomUI.SCT.GetColorIndex("outgoing", key)
    local customRGB = CustomUI.SCT.GetCustomColor("outgoing", key)
    if customRGB and customRGB[1] then
        LabelSetTextColor(wName, customRGB[1], customRGB[2], customRGB[3])
    elseif colorIdx and colorIdx > 1 then
        local opt = CustomUI.SCT.COLOR_OPTIONS[colorIdx]
        if opt and opt.rgb then
            LabelSetTextColor(wName, opt.rgb[1], opt.rgb[2], opt.rgb[3])
        end
    end

    -- 4. Scale.
    local scale = (sct.outgoing and sct.outgoing.size and sct.outgoing.size[key]) or 1.0
    if scale ~= 1.0 then
        WindowSetScale(wName, scale)
        WindowSetRelativeScale(wName, scale)
    end
end

function CustomUI.SCT.PointGainEntry:Update(elapsedTime, simulationSpeed)
    return SctUpdateEntryPosition(self, elapsedTime, simulationSpeed)
end

function CustomUI.SCT.PointGainEntry:Destroy()
    SctStopAnimations(self:GetName())
    SctDestroyWindow(self:GetName())
    SctDestroyWindow(self.m_HolderWindow)
end

----------------------------------------------------------------
-- CustomUI.SCT.EventTracker
-- Inherits from stock; overrides Update to dispatch our entry classes.
----------------------------------------------------------------

CustomUI.SCT.EventTracker = setmetatable({}, { __index = StockEventTracker })
CustomUI.SCT.EventTracker.__index = CustomUI.SCT.EventTracker

function CustomUI.SCT.EventTracker:Create(anchorWindowName, targetObjectNumber)
    -- Delegate to stock Create; stock sets up all fields and calls AttachWindowToWorldObject.
    local tracker = StockEventTracker.Create(self, anchorWindowName, targetObjectNumber)
    -- Ensure our metatable is applied (stock Create sets metatable to `self`).
    return tracker
end

function CustomUI.SCT.EventTracker:InitializeAnimationData(displayType)
    local animData = StockEventTracker.InitializeAnimationData(self, displayType)
    local category
    if displayType == COMBAT_EVENT then
        category = (self.m_TargetObject == GameData.Player.worldObjNum) and "incoming" or "outgoing"
    else
        category = "points"
    end

    local xOffset = CustomUI.SCT.GetXOffset and CustomUI.SCT.GetXOffset(category) or 0
    local yOffset = CustomUI.SCT.GetYOffset and CustomUI.SCT.GetYOffset(category) or 0

    if category == "points" then
        -- Stock DEFAULT_POINT_GAIN_* uses a hard-coded pixel anchor (e.g. x=-200,y=-90).
        -- Points offsets are relative to the world-object (self): default (0,0) is the anchor.
        -- Preserve stock start→target deltas so float timing/distance stay stock; only re-base XY.
        local sx = animData.start.x or 0
        local sy = animData.start.y or 0
        local tx = animData.target.x or 0
        local ty = animData.target.y or 0
        animData.start.x = xOffset
        animData.start.y = yOffset
        animData.target.x = xOffset + (tx - sx)
        animData.target.y = yOffset + (ty - sy)
        animData.current.x = animData.start.x
        animData.current.y = animData.start.y
    else
        -- Combat text: category X is absolute relative to the world-object anchor; Y adds to stock.
        animData.start.x = xOffset
        animData.target.x = xOffset
        animData.current.x = xOffset
        animData.start.y = (animData.start.y or 0) + yOffset
        animData.target.y = (animData.target.y or 0) + yOffset
        animData.current.y = (animData.current.y or 0) + yOffset
    end
    return animData
end

-- Full override of Update: identical to stock except entry classes are ours.
-- Any change to stock's Update logic must be reflected here.
function CustomUI.SCT.EventTracker:Update(elapsedTime)
    local clearForPendingDispatch = true

    for index = self.m_DisplayedEvents:Begin(), self.m_DisplayedEvents:End() do
        local lifeElapsed = self.m_DisplayedEvents[index]:Update(elapsedTime, self.m_CurrentScrollSpeed)

        if lifeElapsed > (self.m_DisplayedEvents[index].m_AnimationData and
                          self.m_DisplayedEvents[index].m_AnimationData.maximumDisplayTime or 4)
           and index == self.m_DisplayedEvents:Begin()
        then
            local condemned = self.m_DisplayedEvents:PopFront()
            condemned:Destroy()
            clearForPendingDispatch = false
        elseif not self.m_DisplayedEvents[index]:IsOutOfStartingBox() then
            clearForPendingDispatch = false
        end
    end

    if not self.m_PendingEvents:IsEmpty() and clearForPendingDispatch then
        local eventType = self.m_PendingEvents:Front().event

        if eventType == COMBAT_EVENT then
            local newName = self.m_Anchor .. "Event" .. self.m_DisplayedEvents:End()
            if not DoesWindowExist(newName) then
                local eventData    = self.m_PendingEvents:PopFront()
                local animData     = self:InitializeAnimationData(eventType)
                local pendingCount = self.m_PendingEvents:End() - self.m_PendingEvents:Begin() + 1
                animData.target.y  = animData.target.y - (pendingCount * 36)

                local frame = CustomUI.SCT.EventEntry:Create(newName, self.m_Anchor, animData)
                if frame then
                    frame:SetupText(self.m_TargetObject, eventData.amount, eventData.type, eventData.abilityId)
                    WindowSetShowing(frame:GetName(), true)
                    WindowStartAlphaAnimation(frame:GetName(), Window.AnimationType.EASE_OUT,
                        1, 0, animData.fadeDuration, false, animData.fadeDelay, 0)
                    -- Sync icon / ability-name suffix fade.
                    if frame.m_AbilityIconWindow and DoesWindowExist(frame.m_AbilityIconWindow) then
                        WindowStartAlphaAnimation(frame.m_AbilityIconWindow, Window.AnimationType.EASE_OUT,
                            1, 0, animData.fadeDuration, false, animData.fadeDelay, 0)
                    end
                    local sfx = frame.m_AbilityNameSuffixWindow
                    if sfx and sfx ~= "" and DoesWindowExist(sfx) then
                        WindowStartAlphaAnimation(sfx, Window.AnimationType.EASE_OUT,
                            1, 0, animData.fadeDuration, false, animData.fadeDelay, 0)
                    end
                    self.m_DisplayedEvents:PushBack(frame)
                end
            end
        else
            local newName = self.m_Anchor .. "PointGain" .. self.m_DisplayedEvents:End()
            if not DoesWindowExist(newName) then
                local eventData     = self.m_PendingEvents:PopFront()
                local animData      = self:InitializeAnimationData(eventType)
                local pendingCount  = self.m_PendingEvents:End() - self.m_PendingEvents:Begin() + 1
                animData.target.x   = animData.target.x + (math.pow(-1, pendingCount) * pendingCount * 18)
                animData.target.y   = animData.target.y - (pendingCount * 36)

                local frame = CustomUI.SCT.PointGainEntry:Create(newName, self.m_Anchor, animData)
                if frame then
                    frame:SetupText(self.m_TargetObject, eventData.amount, eventData.type)
                    WindowSetShowing(frame:GetName(), true)
                    WindowStartAlphaAnimation(frame:GetName(), Window.AnimationType.EASE_OUT,
                        1, 0, animData.fadeDuration, false, animData.fadeDelay, 0)
                    self.m_DisplayedEvents:PushBack(frame)
                end
            end
        end
    end

    if self.m_PendingEvents:IsEmpty() then
        self.m_CurrentScrollSpeed = math.max(
            self.m_MinimumScrollSpeed,
            self.m_CurrentScrollSpeed - self.m_ScrollAcceleration)
    else
        self.m_CurrentScrollSpeed = math.min(
            self.m_MaximumScrollSpeed,
            self.m_CurrentScrollSpeed + self.m_ScrollAcceleration)
    end
end

function CustomUI.SCT.EventTracker:Destroy()
    -- Drain pending (no windows yet).
    while self.m_PendingEvents:Front() ~= nil do
        self.m_PendingEvents:PopFront()
    end
    -- Drain displayed (our EventEntry:Destroy handles icons + animations).
    while self.m_DisplayedEvents:Front() ~= nil do
        self.m_DisplayedEvents:PopFront():Destroy()
    end
    -- Stop anchor animations before detach + destroy.
    if self.m_Anchor and DoesWindowExist(self.m_Anchor) then
        SctStopAnimations(self.m_Anchor)
        DetachWindowFromWorldObject(self.m_Anchor, self.m_TargetObject)
        DestroyWindow(self.m_Anchor)
    end
end

function CustomUI.SCT.DestroyAllTrackers()
    for id, tracker in pairs(CustomUI.SCT.EventTrackers or {}) do
        tracker:Destroy()
        CustomUI.SCT.EventTrackers[id] = nil
    end
    CustomUI.SCT.EventTrackers = {}
end
