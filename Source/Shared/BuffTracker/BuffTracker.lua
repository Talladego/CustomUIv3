----------------------------------------------------------------
-- CustomUI.Shared.BuffTracker
-- **Current (shipped):** mod-loaded; not legacy. Used by PlayerStatusWindow, GroupWindow,
--   TargetHUD, and TargetWindow (via TargetFrame). See README "Source/Shared".
-- Subclasses the stock BuffFrame / BuffTracker to allow per-tracker
-- customization of frame texture, icon size, sorting, and filtering.
--
-- Stock classes (BuffFrame, BuffTracker) are loaded via the
-- EATemplate_UnitFrames dependency and must remain untouched.
--
-- Usage:
--   parentName: prefer the hosting unit-frame root (e.g. CustomUIPlayerStatusWindow,
--   CustomUIGroupWindowMember1, TargetUnitFrame). Container is forced to layer "default".
--   local tracker = CustomUI.BuffTracker:Create(
--       windowName, parentName,
--       GameData.BuffTargetType.SELF,
--       maxSlots, stride, SHOW_BUFF_FRAME_TIMER_LABELS
--   )
--
--   -- Placement: anchor the container window after Create().
--   WindowClearAnchors( windowName )
--   WindowAddAnchor( windowName, anchorPoint, relativeTo, relativePoint, x, y )
--
--   -- Scale: one call scales all slots.
--   tracker:SetScale( 0.85 )
--
--   -- Alignment (default: "left")
--   tracker:SetAlignment( "center" )  -- re-centers visible slots on each update
--   tracker:SetAlignment( "left" )    -- left-to-right from container origin
--
--   -- Sort order (default: NONE = raw as returned by GetBuffs)
--   tracker:SetSortMode( CustomUI.BuffTracker.SortMode.PERM_LONG_SHORT )
--
--   -- Filtering (nil = show everything; defaults + key order: BuffFilterDefaults.lua → FilterDefaults / FilterSettingKeys)
--   tracker:SetFilter({
--       showBuffs      = true,   -- standard beneficial effects
--       showDebuffs    = true,   -- harmful effects
--       showNeutral    = true,   -- unclassified effects
--       playerCastOnly = false,  -- restrict to effects cast by the player
--       showShort      = true,   -- duration < DurationThreshold seconds
--       showLong       = true,   -- duration >= DurationThreshold seconds
--       showPermanent  = true,   -- no-expiry effects
--   })
--   tracker:SetFilter( nil )     -- clear; show everything
--
--   -- Blacklist by effectIndex; whitelist by effectIndex and/or abilityId (SetWhitelist / SetWhitelistAbility). Defaults: BuffLists.lua.
--   -- Blacklist: absolute removal unless conflict path (see OnBuffsChanged).
--   -- Whitelist: adds back rows the filter removed when effectIndex or abilityId matches.
--   -- Same effectIndex on black + white: warning; filter alone applies.
--   tracker:SetBlacklist({ [12345] = true })
--   tracker:SetWhitelist({ [67890] = true })
--   tracker:SetWhitelistAbility({ [947] = true })  -- tonumber( buffData.abilityId )
--
--   -- Buff compression: merge multiple instances of the same logical ability into one icon
--   -- (same abilityId from different casters, or multiple effect slots for one ability).
--   -- Groups by abilityId when present; falls back to effectIndex if abilityId is missing.
--   -- The compressed icon shows "xN" and uses the longest duration in the group.
--   -- Runs after filter and black/whitelist so those rules prune members first.
--   tracker:SetCompressMultiCast( false )  -- default: true
--
--   -- Buff grouping: merge explicitly defined effect groups into one icon per group
--   -- Groups are defined in BuffGroups.lua.  The icon comes from whichever group
--   -- member is present; duration uses the longest in the group; count shows "xN".
--   -- Groups are keyed by abilityId (stable) NOT effectIndex (dynamic per-cast).
--   -- Grouping activates automatically once SetBuffGroups() is called (default: on).
--   tracker:SetBuffGroups( CustomUI.BuffTracker.BuffGroups )
--   tracker:SetGroupBuffs( false )         -- default: true
--
--   -- Clear all displayed buffs (e.g. on target change).
--   tracker:Clear()
--
--   -- Raw escape hooks: override compiled filter/sort entirely when non-nil
--   tracker.filterFunc = function( buffData ) return true end
--   tracker.sortFunc   = function( a, b ) return a.name < b.name end
----------------------------------------------------------------

----------------------------------------------------------------
-- Local helpers
----------------------------------------------------------------

local function WStringToStringSafe( ws )
    if ws == nil then return "" end
    if type(ws) == "wstring" and type(WStringToString) == "function" then
        return WStringToString( ws )
    end
    return tostring( ws )
end

local c_REMOVE_GRACE_PERIOD = 0.25

local function BuffsMatch( a, b )
    if not a or not b then return false end
    local aidA = tonumber( a.abilityId )
    local aidB = tonumber( b.abilityId )
    if aidA and aidB and aidA > 0 and aidB > 0 then
        return aidA == aidB
    end
    local nameA = a.name and WStringToStringSafe( a.name ) or ""
    local nameB = b.name and WStringToStringSafe( b.name ) or ""
    if nameA ~= "" and nameB ~= "" then
        return nameA == nameB
    end
    return false
end

-- Re-declared here because IsValidBuff is local-scoped in bufftracker.lua.
local function IsValidBuff( buffData )
    return ( buffData ~= nil
         and buffData.effectIndex ~= nil
         and buffData.iconNum     ~= nil
         and buffData.iconNum     >  0 )
end



-- Stable iteration for hash-like buff maps (Low #14): deterministic merge paths / debugging.
-- OBSOLETE: Use tracker:_GetSortedKeys( t ) which uses a scratch table to avoid allocations.
local function _sortedMapKeys( t )
    if t == nil then return {} end
    local ks = {}
    for k in pairs( t ) do
        ks[ #ks + 1 ] = k
    end
    table.sort( ks, function( a, b )
        local na, nb = tonumber( a ), tonumber( b )
        if na and nb then return na < nb end
        return tostring( a ) < tostring( b )
    end )
    return ks
end

-- Returns "buff", "debuff", or "neutral" for a given buff entry.
local function GetBuffCategory( buffData )
    local slice = DataUtils.GetAbilityTypeTextureAndColor( buffData )
    if     slice == "Buff-Frame"   then return "buff"
    elseif slice == "Debuff-Frame" then return "debuff"
    else                                return "neutral" end
end

-- Returns "short", "long", or "permanent" based on duration.
local function GetDurationCategory( buffData, threshold, prevCat, prevDur )
    if buffData == nil then return "permanent" end
    if buffData.permanentUntilDispelled then return "permanent" end

    local duration = buffData.duration or 0

    if prevCat == nil or prevDur == nil then
        if duration < threshold then
            return "short"
        else
            return "long"
        end
    end

    if prevCat == "short" then
        local isRecast = (duration - prevDur) > 3.0
        local goesSignificantlyAbove = duration >= (threshold + 3.0)
        if isRecast or goesSignificantlyAbove then
            return "long"
        else
            return "short"
        end
    elseif prevCat == "long" then
        if duration < threshold then
            return "short"
        else
            return "long"
        end
    else
        if duration < threshold then
            return "short"
        else
            return "long"
        end
    end
end

-- Priority tables indexed by SortMode integer value. Higher value = sorted first.
-- durationAscending = true means shortest duration sorts first within a timed bucket.
local c_SORT_PRIORITY = {
    [1] = { short = 3, long = 2, permanent = 1, durationAscending = true  },  -- SHORT_LONG_PERM
    [2] = { permanent = 3, long = 2, short = 1, durationAscending = false },  -- PERM_LONG_SHORT
    [3] = { permanent = 3, short = 2, long = 1, durationAscending = true  },  -- PERM_SHORT_LONG
    [4] = { long = 3, short = 2, permanent = 1, durationAscending = false },  -- LONG_SHORT_PERM
}

-- Icon geometry constants matching CustomUI.BuffFrame:SetBuff().
local c_ICON_SIZE = 32
local c_ICON_GAP  = 2
local c_SLOT_W    = c_ICON_SIZE + c_ICON_GAP
local c_CONTAINER_RUNTIME_PARENT = "Root"

-- Performance constants
local c_SORT_THROTTLE_INTERVAL = 0.1
local c_REFRESH_THROTTLE_INTERVAL = 0.5

-- Compression group key: prefer abilityId (stable per ability; same for all casters).
-- effectIndex is unique per cast, so grouping only by effectIndex never merges
-- the same debuff/buff from two different players. Fallback preserves behaviour when
-- abilityId is absent.
local function GetCompressionGroupKey( buffData )
    local aid = tonumber( buffData.abilityId )
    if aid and aid > 0 then
        return aid
    end
    local eid = buffData.effectIndex
    if eid ~= nil then
        return "e_" .. tostring( eid )
    end
    return "?"
end

-- Collapses entries that share a compression key into a single synthetic buffData.
-- The entry with the longest remaining duration is used as the base; permanent beats timed.
-- stackCount is set to the sum of member stackCount (same as multi-row merge).
local function CompressBuffData( self, rawBuffData, scratch )
    scratch = scratch or {}
    local groups = scratch.groups or {}
    local order  = scratch.order  or {}
    local result = scratch.result or {}
    scratch.groups = groups
    scratch.order  = order
    scratch.result = result

    -- Release synthetic tables from previous pass back to pool
    for i = #result, 1, -1 do
        local entry = result[i]
        if entry._isSynthetic and entry._syntheticOwner == "compress" then
            self:_ReleaseTableToPool( entry )
        end
        result[i] = nil
    end

    for k in pairs( groups ) do
        groups[k] = nil
    end
    for i = #order, 1, -1 do
        order[i] = nil
    end

    for _, buffData in ipairs( rawBuffData ) do
        local id = GetCompressionGroupKey( buffData )
        local grp = groups[id]
        if not grp then
            grp = {}
            groups[id] = grp
            order[#order + 1] = id
        end
        grp[#grp + 1] = buffData
    end

    for _, id in ipairs( order ) do
        local group = groups[id]
        if #group == 1 then
            result[#result + 1] = group[1]
        else
            local best = group[1]
            for i = 2, #group do
                local c = group[i]
                if c.permanentUntilDispelled and not best.permanentUntilDispelled then
                    best = c
                elseif not best.permanentUntilDispelled
                   and not c.permanentUntilDispelled
                   and c.duration > best.duration then
                    best = c
                end
            end
            local totalStacks = 0
            for i = 1, #group do totalStacks = totalStacks + (group[i].stackCount or 1) end
            
            local compressed = self:_GetTableFromPool( best )
            compressed.stackCount = totalStacks
            compressed._isSynthetic = true
            compressed._syntheticOwner = "compress"
            result[#result + 1] = compressed
        end
    end

    return result
end

----------------------------------------------------------------
-- CustomUI.BuffFrame
-- Inherits all stock behaviour; sole override is SetBuff(), which
-- replaces the EA_BuffFrames01 slice system with a fixed
-- EA_SquareFrame texture so buff icons match action-button styling.
----------------------------------------------------------------

if not CustomUI then CustomUI = {} end

CustomUI.BuffFrame = BuffFrame:Subclass( "BuffIcon" )

function CustomUI.BuffFrame:SetBuff( buffData )
    local isValidBuff = IsValidBuff( buffData )
    local prev        = self.m_buffData

    -- Sort-mode trackers call OnBuffsChanged ~10 Hz; re-applying the same effect reset alpha/tints every tick and
    -- restarts stock fade animation → visible flicker. Same-effect refresh: timer only (duration lives on buffData).
    local isSameVisual = false
    if isValidBuff and prev ~= nil
       and self.m_displayedEffectIndex == buffData.effectIndex
       and self.m_displayedIconNum == buffData.iconNum
       and self.m_displayedStackCount == ( buffData.stackCount or 1 )
    then
        isSameVisual = true
    end

    if isSameVisual then
        self.m_buffData = buffData
        self:Update( true )
        self:Show( self.m_IsTrackerShowing )
        return
    end

    self.m_buffData = buffData

    if isValidBuff then
        self.m_displayedEffectIndex = buffData.effectIndex
        self.m_displayedIconNum     = buffData.iconNum
        self.m_displayedStackCount  = buffData.stackCount or 1

        local windowName       = self:GetName()
        local texture, x, y   = GetIconData( buffData.iconNum )

        DynamicImageSetTexture( windowName .. "IconBase", texture, x, y )
        WindowSetAlpha    ( windowName, 1.0 )
        WindowSetFontAlpha( windowName, 1.0 )

        -- Frame overlay: always use the action-button square frame.
        DynamicImageSetTexture          ( windowName .. "Frame", "EA_SquareFrame", 0, 0 )
        DynamicImageSetTextureDimensions( windowName .. "Frame", 64, 64 )
        WindowSetDimensions             ( windowName .. "Frame", 32, 32 )

        local _, _, _, buffRed, buffGreen, buffBlue =
            DataUtils.GetAbilityTypeTextureAndColor( buffData )

        if buffRed and buffGreen and buffBlue then
            WindowSetTintColor( windowName .. "Frame", buffRed, buffGreen, buffBlue )
        else
            WindowSetTintColor( windowName .. "Frame", 255, 255, 255 )
        end

        local stacks = buffData.stackCount or 1
        if stacks > 1 then
            LabelSetText  ( windowName .. "Timer", L"x" .. stacks )
            WindowSetShowing( windowName .. "Timer", true )
        else
            WindowSetShowing( windowName .. "Timer",
                self.m_ShowingTimerLabels == SHOW_BUFF_FRAME_TIMER_LABELS )
        end

        self:Update( true )
    else
        self.m_displayedEffectIndex = nil
        self.m_displayedIconNum     = nil
        self.m_displayedStackCount  = nil
    end

    self:Show( isValidBuff and self.m_IsTrackerShowing )
end

----------------------------------------------------------------
-- Replace BuffFrame.OnMouseOver to use GetActiveWindow() instead of
-- GetMouseOverWindow().  The XML template registers this function by
-- name, so the engine always calls BuffFrame.OnMouseOver regardless of
-- which class created the slot window.
--
-- Root cause: the stock handler uses FrameManager:GetMouseOverWindow()
-- which resolves SystemData.MouseOverWindow.name.  When buff frames are
-- nested inside a container window with handleinput="true" (as required
-- for our layout), the engine may set MouseOverWindow to the container
-- for slots that are not in the topmost hit-test position — in practice
-- any slot not in the first row.  GetActiveWindow() resolves
-- SystemData.ActiveWindow.name, which is always the specific slot window
-- that owns the registered OnMouseOver handler, regardless of nesting.
--
-- A module-level variable replaces g_currentMouseOverBuff (a local in
-- the stock bufftracker.lua that we cannot reach) so the timer update
-- callback continues to work correctly.
----------------------------------------------------------------

local _customui_currentMouseOverBuff = nil

do
    local _origOnMouseOverEnd = BuffFrame.OnMouseOverEnd

    BuffFrame.OnMouseOver = function()
        local buffFrame = FrameManager:GetActiveWindow()
        if buffFrame == nil then
            return
        end

        local buffData = buffFrame.m_buffData
        if IsValidBuff( buffData ) then
            _customui_currentMouseOverBuff = buffFrame

            Tooltips.CreateTextOnlyTooltip( SystemData.ActiveWindow.name, nil )
            Tooltips.SetTooltipColorDef( 1, 1, Tooltips.COLOR_HEADING )
            Tooltips.SetTooltipColorDef( 1, 2, Tooltips.COLOR_HEADING )
            Tooltips.SetTooltipActionText(
                GetString( StringTables.Default.TEXT_R_CLICK_TO_REMOVE_EFFECT ) )

            BuffFrame.PopulateTooltipFields( buffData, true )

            Tooltips.AnchorTooltip( { Point        = "bottom",
                                       RelativeTo    = SystemData.ActiveWindow.name,
                                       RelativePoint = "top",
                                       XOffset       = 0,
                                       YOffset       = 20 } )
            Tooltips.SetUpdateCallback( function()
                if _customui_currentMouseOverBuff == nil then return end
                local data = _customui_currentMouseOverBuff.m_buffData
                if IsValidBuff( data ) then
                    BuffFrame.PopulateTooltipFields( data, false )
                end
            end )
        end
    end

    BuffFrame.OnMouseOverEnd = function()
        _customui_currentMouseOverBuff = nil
        if _origOnMouseOverEnd then
            _origOnMouseOverEnd()
        end
    end
end

----------------------------------------------------------------
-- Optional debug instrumentation: log active/mouseover window names.
-- Enable via CustomUI.DebugLogging = true  (wraps the already-replaced handler above)
----------------------------------------------------------------

if CustomUI.DebugLogging == true and not CustomUI._BuffFrameTooltipDebugWrapped then
    CustomUI._BuffFrameTooltipDebugWrapped = true

    local _patchedOnMouseOver    = BuffFrame.OnMouseOver
    local _patchedOnMouseOverEnd = BuffFrame.OnMouseOverEnd

    BuffFrame.OnMouseOver = function()
        local aw  = SystemData and SystemData.ActiveWindow  and SystemData.ActiveWindow.name
        local mow = SystemData and SystemData.MouseOverWindow and SystemData.MouseOverWindow.name
        LogLuaMessage( "Lua", SystemData.UiLogFilters.INFO,
            L"[CustomUI] BuffFrame.OnMouseOver active=" .. towstring( tostring( aw ) )
            .. L" mouseover=" .. towstring( tostring( mow ) ) )
        if _patchedOnMouseOver then
            return _patchedOnMouseOver()
        end
    end

    BuffFrame.OnMouseOverEnd = function()
        local aw  = SystemData and SystemData.ActiveWindow  and SystemData.ActiveWindow.name
        local mow = SystemData and SystemData.MouseOverWindow and SystemData.MouseOverWindow.name
        LogLuaMessage( "Lua", SystemData.UiLogFilters.INFO,
            L"[CustomUI] BuffFrame.OnMouseOverEnd active=" .. towstring( tostring( aw ) )
            .. L" mouseover=" .. towstring( tostring( mow ) ) )
        if _patchedOnMouseOverEnd then
            return _patchedOnMouseOverEnd()
        end
    end
end

----------------------------------------------------------------
-- CustomUI.BuffTracker
-- Inherits all stock behaviour.
-- Overrides: Create, OnBuffsChanged.
-- See file header for full public API.
----------------------------------------------------------------

CustomUI.BuffTracker         = {}
CustomUI.BuffTracker.__index = CustomUI.BuffTracker
setmetatable( CustomUI.BuffTracker, { __index = BuffTracker } )

function CustomUI.BuffTracker:DebugLog( msg )
    if CustomUI.DebugLogging == true then
        local nameStr = tostring(self.m_containerName or "?")
        local wmsg = towstring("[" .. nameStr .. "] " .. tostring(msg))
        local dfn = rawget(_G, "d")
        if type(dfn) == "function" then
            dfn(wmsg)
        elseif CustomUI.PrintMessage then
            CustomUI.PrintMessage(wmsg)
        else
            TextLogAddEntry("Chat", 0, L"[CustomUI] " .. wmsg)
        end
    end
end

-- Sort mode constants.
CustomUI.BuffTracker.SortMode = {
    NONE            = 0,  -- raw order from GetBuffs (default)
    SHORT_LONG_PERM = 1,  -- short → long → permanent
    PERM_LONG_SHORT = 2,  -- permanent → long → short
    PERM_SHORT_LONG = 3,  -- permanent → short → long
    LONG_SHORT_PERM = 4,  -- long → short → permanent
}

-- Alignment mode constants.
CustomUI.BuffTracker.Alignment = {
    LEFT   = "left",
    CENTER = "center",
}

-- Applies shipped DefaultBlacklist / DefaultWhitelist / DefaultWhitelistAbility when present.
function CustomUI.BuffTracker.ApplySharedDefaultLists( tracker )
    if tracker == nil then
        return
    end

    if CustomUI.BuffTracker.DefaultBlacklist ~= nil then
        tracker:SetBlacklist( CustomUI.BuffTracker.DefaultBlacklist )
    end

    if CustomUI.BuffTracker.DefaultWhitelist ~= nil then
        tracker:SetWhitelist( CustomUI.BuffTracker.DefaultWhitelist )
    end

    if CustomUI.BuffTracker.DefaultWhitelistAbility ~= nil then
        tracker:SetWhitelistAbility( CustomUI.BuffTracker.DefaultWhitelistAbility )
    end
end

function CustomUI.BuffTracker.ApplyPlayerStatusRules( tracker )
    if tracker == nil then
        return
    end

    tracker:SetSortMode( CustomUI.BuffTracker.SortMode.PERM_LONG_SHORT )
    tracker:SetBuffGroups( CustomUI.BuffTracker.BuffGroups )
    CustomUI.BuffTracker.ApplySharedDefaultLists( tracker )
end

-- Seconds separating "short" from "long". Override per-tracker after Create.
CustomUI.BuffTracker.DurationThreshold = 60

----------------------------------------------------------------
-- Create
-- windowName  : name for the container window and slot prefix
-- parentName  : visual owner used for anchors, visibility, and inherited scale
-- buffTargetType, maxBuffCount, buffRowStride, showTimerLabels: as before
--
-- The container window is sized to hold maxBuffCount slots at their
-- natural icon size.  After Create(), anchor the container yourself:
--   WindowAddAnchor( windowName, point, relativeTo, relativePoint, x, y )
----------------------------------------------------------------

function CustomUI.BuffTracker:Create( windowName, parentName,
                                      buffTargetType, maxBuffCount, buffRowStride,
                                      showTimerLabels )
    local cols = buffRowStride
    local rows = math.ceil( maxBuffCount / buffRowStride )
    local containerW = cols * c_ICON_SIZE + (cols - 1) * c_ICON_GAP
    local containerH = rows * c_ICON_SIZE + (rows - 1) * c_ICON_GAP

    -- Create the container window that owns all slot windows.
    -- Keep it under Root so the owner's hit bounds cannot clip interactive buff slots.
    -- Components still anchor this window relative to their own frames; slots are internal.
    CreateWindowFromTemplate( windowName, "CustomUIBuffContainerTemplate", c_CONTAINER_RUNTIME_PARENT )
    WindowSetDimensions( windowName, containerW, containerH )
    WindowSetShowing( windowName, false )
    -- Note: the parent container must keep handleinput enabled or child BuffIcon slots
    -- may not receive mouse events (tooltips rely on BuffFrame.OnMouseOver).

    local newTracker = {
        m_containerName     = windowName,
        m_ownerName         = parentName,
        m_containerW        = containerW,
        m_containerH        = containerH,
        m_requestedShow     = false,
        m_relativeScale     = 1.0,
        m_buffData          = {},
        m_targetType        = buffTargetType,
        m_maxBuffs          = maxBuffCount,
        m_buffFrames        = {},
        m_buffRowStride     = buffRowStride,
        m_cols              = cols,
        m_rows              = rows,
        m_alignment         = CustomUI.BuffTracker.Alignment.LEFT,
        -- Sort / filter state
        m_sortMode          = nil,
        m_durationThreshold = CustomUI.BuffTracker.DurationThreshold,
        m_filterConfig      = nil,
        m_blacklist          = {},
        m_whitelist          = {},
        m_whitelistAbility   = {},
        m_forceShowTrackerPriority100 = false,
        m_compiledSortFunc  = nil,
        m_compressMultiCast = true,
        m_groupBuffs        = true,
        m_buffGroups        = nil,
        m_groupLookup       = {},
        -- Raw escape hooks
        filterFunc          = nil,
        sortFunc            = nil,
        -- Reused across OnBuffsChanged to cut allocations (sort-on trackers).
        m_scratchPostFilter = {},
        m_scratchInResult   = {},
        m_scratchCompress   = {},
        m_scratchGroups     = {},
        m_visibleSlotCount  = 0,
        -- Follow-up #29: coalesce rebuild work while hidden.
        m_dirtyWhileHidden  = false,
        -- Follow-up #35: batch/coalesce setter-triggered rebuilds.
        m_batchDepth        = 0,
        m_rebuildPending    = false,
        -- Performance optimizations: throttling and memory pooling
        m_timeSinceLastRefresh = 999,
        m_tablePool            = {},
        m_scratchSeen          = {},
        m_scratchSortedKeys    = {},
    }

    -- Create all slot windows parented to the container.
    -- Left-aligned anchor chain: slot 1 at topleft, subsequent slots chain right
    -- then wrap to next row.  SetAlignment("center") re-anchors on each update.
    for buffSlot = 1, maxBuffCount do
        local buffFrameName = windowName .. buffSlot
        local buffFrame     = CustomUI.BuffFrame:Create(
                                  buffFrameName, windowName,
                                  buffSlot, buffTargetType, showTimerLabels )

        if buffFrame ~= nil then
            newTracker.m_buffFrames[ buffSlot ] = buffFrame
            -- Some parent layouts place the buff container outside its parent's bounds; make
            -- sure each slot window always participates in hit-testing for tooltips.
            WindowSetHandleInput( buffFrameName, true )

            local col = (buffSlot - 1) % buffRowStride
            local row = math.floor( (buffSlot - 1) / buffRowStride )
            local xOff = col * c_SLOT_W
            local yOff = row * (c_ICON_SIZE + c_ICON_GAP)

            WindowClearAnchors( buffFrameName )
            -- Point = anchor point on the container (topleft).
            -- RelativePoint = anchor point on the slot being placed (topleft).
            WindowAddAnchor( buffFrameName, "topleft", windowName, "topleft", xOff, yOff )
        end
    end

    newTracker = setmetatable( newTracker, self )

    newTracker.m_sortResortElapsed = 0

    newTracker:_ApplyContainerHitArea()
    newTracker:_ApplyContainerScale()

    newTracker:_RebuildSortFunc()
    newTracker:Refresh()

    return newTracker
end

----------------------------------------------------------------
-- Public configuration API
----------------------------------------------------------------

function CustomUI.BuffTracker:SetSortMode( mode )
    self.m_sortMode = mode
    self:_RebuildSortFunc()
    self:_RequestRebuild()
end

function CustomUI.BuffTracker:SetFilter( config )
    if config == nil then
        self.m_filterConfig = nil
    else
        self.m_filterConfig = {
            showBuffs      = config.showBuffs      ~= false,
            showDebuffs    = config.showDebuffs    ~= false,
            showNeutral    = config.showNeutral    ~= false,
            showShort      = config.showShort      ~= false,
            showLong       = config.showLong       ~= false,
            showPermanent  = config.showPermanent  ~= false,
            playerCastOnly = config.playerCastOnly == true,  -- uses buffData.castByPlayer
        }
    end
    self:_RequestRebuild()
end

-- idTable: { [effectIndex] = true }.  Pass nil or {} to clear.
function CustomUI.BuffTracker:SetBlacklist( idTable )
    self.m_blacklist = idTable or {}
    self:_WarnListConflicts()
    self:_RequestRebuild()
end

-- idTable: { [effectIndex] = true }.  Pass nil or {} to clear.
function CustomUI.BuffTracker:SetWhitelist( idTable )
    self.m_whitelist = idTable or {}
    self:_WarnListConflicts()
    self:_RequestRebuild()
end

-- idTable: { [abilityId] = true } — matches tonumber( buffData.abilityId ). Pass nil or {} to clear.
function CustomUI.BuffTracker:SetWhitelistAbility( idTable )
    self.m_whitelistAbility = idTable or {}
    self:_WarnListConflicts()
    self:_RequestRebuild()
end

function CustomUI.BuffTracker:SetForceShowTrackerPriority100( enabled )
    self.m_forceShowTrackerPriority100 = enabled == true
    self:_RebuildSortFunc()
    self:_RequestRebuild()
end

function CustomUI.BuffTracker:SetCompressMultiCast( enabled )
    self.m_compressMultiCast = enabled == true
    self:_RequestRebuild()
end

function CustomUI.BuffTracker:SetBuffGroups( groups )
    self.m_buffGroups  = (groups and #groups > 0) and groups or nil
    self.m_groupLookup = {}
    if self.m_buffGroups then
        for idx, grp in ipairs( self.m_buffGroups ) do
            for _, abilityId in ipairs( grp.abilityIds ) do
                self.m_groupLookup[ abilityId ] = idx
            end
        end
    end
    self:_RequestRebuild()
end

function CustomUI.BuffTracker:SetGroupBuffs( enabled )
    self.m_groupBuffs = enabled == true
    self:_RequestRebuild()
end

-- Sets the alignment mode for slot layout within the container.
-- "left"   : slots placed left-to-right from the container's topleft (default).
-- "center" : visible slots re-centered horizontally on each OnBuffsChanged.
function CustomUI.BuffTracker:SetAlignment( mode )
    self.m_alignment = mode or CustomUI.BuffTracker.Alignment.LEFT
    self:_RequestRebuild()
end

-- Enables or disables mouse input on the container and all slot windows.
-- Pass false for non-interactive overlays (e.g. world-attached HUDs).
function CustomUI.BuffTracker:SetHandleInput( enabled )
    local flag = enabled ~= false
    if self.m_containerName and DoesWindowExist( self.m_containerName ) then
        WindowSetHandleInput( self.m_containerName, flag )
    end
    for _, frame in ipairs( self.m_buffFrames ) do
        WindowSetHandleInput( frame:GetName(), flag )
    end
end

-- Scales the container window (and all slots inherit the scale).
function CustomUI.BuffTracker:SetScale( scale )
    self.m_relativeScale = tonumber( scale ) or 1.0
    self:_ApplyContainerScale()
end

-- Clears all displayed buffs and triggers a layout refresh.
-- Use on target change or when the tracked unit becomes invalid.
function CustomUI.BuffTracker:Clear()
    for _, buffData in pairs( self.m_buffData ) do
        self:_ReleaseTableToPool( buffData )
    end
    self.m_buffData = {}
    self:_RequestRebuild()
end

-- Shows or hides the container window.
function CustomUI.BuffTracker:Show( show )
    self.m_requestedShow = show == true
    self:_ApplyContainerVisibility()
    if self:IsShowing() and self.m_dirtyWhileHidden then
        self.m_dirtyWhileHidden = false
        self:_RequestRebuild()
    end
end

-- Returns true if the container is currently showing.
function CustomUI.BuffTracker:IsShowing()
    if self.m_containerName and DoesWindowExist( self.m_containerName ) then
        return WindowGetShowing( self.m_containerName )
    end
    return false
end

-- Returns the container window name so callers can anchor it.
function CustomUI.BuffTracker:GetContainerName()
    return self.m_containerName
end

-- Destroys the container and all slot windows.
-- Each slot Frame must be explicitly removed from FrameManager before the container
-- window is destroyed; otherwise stale Frame Lua objects remain in FrameManager and
-- block re-registration when the tracker is recreated (e.g. group member rejoin).
function CustomUI.BuffTracker:Shutdown()
    for _, frame in ipairs( self.m_buffFrames ) do
        if frame and DoesWindowExist( frame:GetName() ) then
            frame:Destroy()
        end
    end
    if self.m_containerName and DoesWindowExist( self.m_containerName ) then
        DestroyWindow( self.m_containerName )
    end
    self.m_containerName = nil
    self.m_buffFrames    = {}
    self.m_visibleSlotCount = 0
end

----------------------------------------------------------------
-- Internal helpers
----------------------------------------------------------------

function CustomUI.BuffTracker:_GetTableFromPool( src )
    local t = table.remove( self.m_tablePool ) or {}
    if src then
        for k, v in pairs( src ) do
            t[k] = v
        end
    end
    return t
end

function CustomUI.BuffTracker:_ReleaseTableToPool( t )
    if t == nil then return end
    for k in pairs( t ) do
        t[k] = nil
    end
    table.insert( self.m_tablePool, t )
end

function CustomUI.BuffTracker:_GetSortedKeys( t )
    local ks = self.m_scratchSortedKeys
    local n = 0
    for k in pairs( t ) do
        n = n + 1
        ks[n] = k
    end
    -- Clear trailing old keys
    for i = #ks, n + 1, -1 do
        ks[i] = nil
    end

    table.sort( ks, function( a, b )
        local typeA, typeB = type( a ), type( b )
        if typeA == "number" and typeB == "number" then
            return a < b
        end
        local na, nb = tonumber( a ), tonumber( b )
        if na and nb then return na < nb end
        return tostring( a ) < tostring( b )
    end )
    return ks
end

function CustomUI.BuffTracker:_RebuildSortFunc()
    local priority  = c_SORT_PRIORITY[ self.m_sortMode ]
    local threshold = self.m_durationThreshold
    local forceP100First = self.m_forceShowTrackerPriority100 == true

    if priority == nil then
        self.m_compiledSortFunc = nil
        return
    end

    self.m_compiledSortFunc = function( a, b )
        if a == nil or b == nil then return false end

        if forceP100First then
            local aP = tonumber( a.trackerPriority ) == 100
            local bP = tonumber( b.trackerPriority ) == 100
            if aP ~= bP then
                return aP
            end
        end

        local catA = a._sortDurCat or GetDurationCategory( a, threshold, a._sortDurCat, a._sortDur )
        local catB = b._sortDurCat or GetDurationCategory( b, threshold, b._sortDurCat, b._sortDur )
        local priA = priority[ catA ]
        local priB = priority[ catB ]

        if priA ~= priB then
            return priA > priB
        end

        if catA == "permanent" then
            local nameA = WStringToStringSafe( a.name )
            local nameB = WStringToStringSafe( b.name )
            if nameA ~= nameB then return nameA < nameB end

            local abilityA = tonumber( a.abilityId ) or -1
            local abilityB = tonumber( b.abilityId ) or -1
            if abilityA ~= abilityB then return abilityA < abilityB end

            local effectA = tonumber( a.effectIndex ) or -1
            local effectB = tonumber( b.effectIndex ) or -1
            return effectA < effectB
        end

        local durationA = tonumber( a.duration ) or 0
        local durationB = tonumber( b.duration ) or 0
        if durationA ~= durationB then
            if priority.durationAscending then
                return durationA < durationB
            else
                return durationA > durationB
            end
        end

        local abilityA = tonumber( a.abilityId ) or -1
        local abilityB = tonumber( b.abilityId ) or -1
        if abilityA ~= abilityB then return abilityA < abilityB end

        local effectA = tonumber( a.effectIndex ) or -1
        local effectB = tonumber( b.effectIndex ) or -1
        if effectA ~= effectB then return effectA < effectB end

        return WStringToStringSafe( a.name ) < WStringToStringSafe( b.name )
    end
end

function CustomUI.BuffTracker:_PassesFilter( buffData )
    local cfg = self.m_filterConfig
    if cfg == nil then return true end

    local buffCat = GetBuffCategory( buffData )
    if buffCat == "buff"    and not cfg.showBuffs   then return false end
    if buffCat == "debuff"  and not cfg.showDebuffs then return false end
    if buffCat == "neutral" and not cfg.showNeutral then return false end

    local durCat = GetDurationCategory( buffData, self.m_durationThreshold, buffData._layoutDurCat, buffData._layoutDur )
    if durCat == "short"     and not cfg.showShort     then return false end
    if durCat == "long"      and not cfg.showLong      then return false end
    if durCat == "permanent" and not cfg.showPermanent then return false end

    if cfg.playerCastOnly and not buffData.castByPlayer then return false end

    return true
end

function CustomUI.BuffTracker:_ApplyBuffGroups( sourceData )
    local scratch      = self.m_scratchGroups
    local groupBuckets = scratch.groupBuckets or {}
    local result       = scratch.result       or {}
    scratch.groupBuckets = groupBuckets
    scratch.result       = result

    for k in pairs( groupBuckets ) do
        groupBuckets[k] = nil
    end

    -- Release synthetic tables from previous pass
    for i = #result, 1, -1 do
        local entry = result[i]
        if entry._isSynthetic and entry._syntheticOwner == "group" then
            self:_ReleaseTableToPool( entry )
        end
        result[i] = nil
    end

    for _, buffData in ipairs( sourceData ) do
        local groupIdx = self.m_groupLookup[ buffData.abilityId ]
        if groupIdx then
            local bucket = groupBuckets[ groupIdx ]
            if not bucket then
                bucket = { members = {} }
                groupBuckets[ groupIdx ] = bucket
            end
            local members = bucket.members
            members[#members + 1] = buffData
        else
            result[#result + 1] = buffData
        end
    end

    for groupIdx, grp in ipairs( self.m_buffGroups ) do
        local bucket = groupBuckets[ groupIdx ]
        if bucket then
            local members = bucket.members
            local best = members[1]
            for i = 2, #members do
                local c = members[i]
                if c.permanentUntilDispelled and not best.permanentUntilDispelled then
                    best = c
                elseif not best.permanentUntilDispelled
                   and not c.permanentUntilDispelled
                   and c.duration > best.duration then
                    best = c
                end
            end
            local synthetic = self:_GetTableFromPool( best )
            synthetic.stackCount = #members
            synthetic._isSynthetic = true
            synthetic._syntheticOwner = "group"
            result[#result + 1] = synthetic
        end
    end

    return result
end

-- Follow-up #35: coalesce multiple setter calls into one rebuild.
function CustomUI.BuffTracker:BeginBatch()
    self.m_batchDepth = (self.m_batchDepth or 0) + 1
end

function CustomUI.BuffTracker:EndBatch()
    local d = (self.m_batchDepth or 0) - 1
    if d < 0 then d = 0 end
    self.m_batchDepth = d
    if d == 0 and self.m_rebuildPending then
        self.m_rebuildPending = false
        self:_RequestRebuild()
    end
end

function CustomUI.BuffTracker:_RequestRebuild( immediate )
    self.m_rebuildPending = true

    if (self.m_batchDepth or 0) > 0 then
        return
    end
    if not self:IsShowing() then
        self.m_dirtyWhileHidden = true
        return
    end

    if immediate or (self.m_sortResortElapsed or 0) >= c_SORT_THROTTLE_INTERVAL then
        self.m_rebuildPending = false
        self.m_sortResortElapsed = 0
        self:OnBuffsChanged()
    end
end

function CustomUI.BuffTracker:_WarnListConflicts()
    if CustomUI.DebugLogging ~= true then
        return
    end
    for _, effectId in ipairs( _sortedMapKeys( self.m_whitelist ) ) do
        if self.m_blacklist[ effectId ] then
            LogLuaMessage( "Lua", SystemData.UiLogFilters.WARNING,
                L"[CustomUI] effectIndex " .. tostring( effectId )
                .. L" is in both blacklist and whitelist. Both rules are ignored; filter result applies." )
        end
    end
end

function CustomUI.BuffTracker:_IsOwnerShowing()
    if self.m_ownerName == nil or self.m_ownerName == "" then
        return true
    end
    if not DoesWindowExist( self.m_ownerName ) then
        return false
    end

    local current = self.m_ownerName
    local guard = 0
    while current ~= nil and current ~= "" and DoesWindowExist( current ) do
        if WindowGetShowing( current ) ~= true then
            return false
        end
        if type( WindowGetParent ) ~= "function" then
            return true
        end
        current = WindowGetParent( current )
        guard = guard + 1
        if guard > 20 then
            return true
        end
    end

    return true
end

function CustomUI.BuffTracker:_ApplyContainerVisibility()
    if self.m_containerName and DoesWindowExist( self.m_containerName ) then
        WindowSetShowing( self.m_containerName,
            self.m_requestedShow == true and self:_IsOwnerShowing() )
    end
end

function CustomUI.BuffTracker:_ApplyContainerScale()
    if not ( self.m_containerName and DoesWindowExist( self.m_containerName ) ) then
        return
    end

    local ownerScale = 1.0
    if self.m_ownerName and DoesWindowExist( self.m_ownerName ) then
        ownerScale = tonumber( WindowGetScale( self.m_ownerName ) ) or 1.0
    end

    WindowSetScale( self.m_containerName, ownerScale * ( self.m_relativeScale or 1.0 ) )
end

function CustomUI.BuffTracker:_ApplyContainerHitArea()
    if self.m_containerName
       and self.m_containerW
       and self.m_containerH
       and DoesWindowExist( self.m_containerName ) then
        WindowSetDimensions( self.m_containerName, self.m_containerW, self.m_containerH )
    end
end

-- Resizes the container to exactly fit the visible slots and re-anchors them
-- left-to-right from topleft.  Because the container anchor uses a center point
-- (e.g. "top"->"bottom"), shrinking the container to the visible row width
-- automatically centers it over that anchor target — no offset math needed.
-- Hidden slots are parked at topleft (0,0) so stale anchors can't influence layout.
function CustomUI.BuffTracker:_ApplyCenterAlignment( visibleSlots )
    local container = self.m_containerName
    local count     = #visibleSlots
    local rowW      = count > 0 and (count * c_ICON_SIZE + (count - 1) * c_ICON_GAP) or 1
    local rowH      = count > 0 and c_ICON_SIZE or 1

    WindowSetDimensions( container, rowW, rowH )

    -- Park hidden frames at topleft so they don't influence layout.
    for _, frame in ipairs( self.m_buffFrames ) do
        local name = frame:GetName()
        WindowClearAnchors( name )
        WindowAddAnchor( name, "topleft", container, "topleft", 0, 0 )
    end

    -- Place visible frames left-to-right from the container's topleft.
    for i, frame in ipairs( visibleSlots ) do
        local name = frame:GetName()
        local xOff = (i - 1) * c_SLOT_W
        WindowClearAnchors( name )
        WindowAddAnchor( name, "topleft", container, "topleft", xOff, 0 )
    end
end

----------------------------------------------------------------
-- Update (tick durations + re-sort)
----------------------------------------------------------------

function CustomUI.BuffTracker:Update( elapsedTime )
    local wasShowing = self:IsShowing()
    self:_ApplyContainerScale()
    self:_ApplyContainerVisibility()
    if not wasShowing and self:IsShowing() and self.m_dirtyWhileHidden then
        self.m_dirtyWhileHidden = false
        self:_RequestRebuild()
    end

    self.m_sortResortElapsed = (self.m_sortResortElapsed or 0) + elapsedTime
    self.m_timeSinceLastRefresh = (self.m_timeSinceLastRefresh or 0) + elapsedTime

    -- Tick durations and prune expired/pending removal buffs in a single pass.
    -- Removing an existing key during pairs() is safe in Lua 5.1.
    local pruned = false
    for bk, buffData in pairs( self.m_buffData ) do
        if IsValidBuff( buffData ) then
            if buffData._pendingRemovalTime then
                local t = buffData._pendingRemovalTime - elapsedTime
                if t <= 0 then
                    self:_ReleaseTableToPool( buffData )
                    self.m_buffData[ bk ] = nil
                    pruned = true
                else
                    buffData._pendingRemovalTime = t
                    if not buffData.permanentUntilDispelled then
                        local d = ( buffData.duration or 0 ) - elapsedTime
                        if d < 0 then d = 0 end
                        buffData.duration = d
                        if buffData._layoutDur then
                            buffData._layoutDur = math.max(0, buffData._layoutDur - elapsedTime)
                        end
                        if buffData._sortDur then
                            buffData._sortDur = math.max(0, buffData._sortDur - elapsedTime)
                        end
                    end
                end
            elseif not buffData.permanentUntilDispelled then
                local d = ( buffData.duration or 0 ) - elapsedTime
                if d <= 0 then
                    self:_ReleaseTableToPool( buffData )
                    self.m_buffData[ bk ] = nil
                    pruned = true
                else
                    buffData.duration = d
                    if buffData._layoutDur then
                        buffData._layoutDur = buffData._layoutDur - elapsedTime
                    end
                    if buffData._sortDur then
                        buffData._sortDur = buffData._sortDur - elapsedTime
                    end
                end
            end
        end
    end
    if pruned then
        self.m_rebuildPending = true
    end

    -- Tick timer labels for visible slots only (smooth countdown).
    -- Cap by m_maxBuffs: OnBuffsChanged only has slots for that many frames (#finalData can exceed it).
    local visCount = math.min( self.m_visibleSlotCount or 0, self.m_maxBuffs or 0 )
    for buffSlot = 1, visCount do
        local frame = self.m_buffFrames[ buffSlot ]
        if frame and frame.Update and frame.m_buffData and frame.m_buffData.effectIndex then
            if frame.m_buffData._isSynthetic and not frame.m_buffData.permanentUntilDispelled then
                local d = (frame.m_buffData.duration or 0) - elapsedTime
                if d < 0 then d = 0 end
                frame.m_buffData.duration = d
            end
            frame:Update( false )
        end
    end

    local sortActive = self.m_compiledSortFunc or self.sortFunc
    local durCatChanged = false

    if sortActive and not pruned then
        local threshold = self.m_durationThreshold
        for _, buffData in pairs( self.m_buffData ) do
            if IsValidBuff( buffData ) and not buffData.permanentUntilDispelled then
                local catNow = GetDurationCategory( buffData, threshold, buffData._layoutDurCat, buffData._layoutDur )
                local prev   = buffData._layoutDurCat
                if prev ~= nil and catNow ~= prev then
                    durCatChanged = true
                    break
                end
            end
        end
    end

    if durCatChanged then
        self.m_rebuildPending = false
        self.m_sortResortElapsed = 0
        self:OnBuffsChanged()
    elseif self.m_rebuildPending and self.m_sortResortElapsed >= c_SORT_THROTTLE_INTERVAL then
        self.m_rebuildPending = false
        self.m_sortResortElapsed = 0
        self:OnBuffsChanged()
    end
end

----------------------------------------------------------------
-- Refresh / UpdateBuffs
----------------------------------------------------------------

local function CopyBuffData( src )
    local copy = {}
    for k, v in pairs( src ) do
        copy[ k ] = v
    end
    return copy
end

local function AssignBuffData( dst, src )
    for k in pairs( dst ) do
        if type(k) ~= "string" or k:sub(1,1) ~= "_" then
            dst[k] = nil
        end
    end
    for k, v in pairs( src ) do
        dst[k] = v
    end
end

function CustomUI.BuffTracker:Refresh( force )
    if not force and ( self.m_timeSinceLastRefresh or 999 ) < c_REFRESH_THROTTLE_INTERVAL then
        self:_RequestRebuild()
        return
    end
    self.m_timeSinceLastRefresh = 0

    local allBuffs = GetBuffs( self.m_targetType )
    local buffData = self.m_buffData
    local seen = self.m_scratchSeen or {}
    self.m_scratchSeen = seen
    for k in pairs( seen ) do seen[k] = nil end

    if allBuffs then
        for id, buffEntry in pairs( allBuffs ) do
            -- Purge any matching pending removal buffs first (excluding same id to prevent corrupting table pool)
            for oldId, oldBuff in pairs( buffData ) do
                if oldId ~= id and oldBuff._pendingRemovalTime and BuffsMatch( oldBuff, buffEntry ) then
                    self:_ReleaseTableToPool( oldBuff )
                    buffData[oldId] = nil
                end
            end

            local existing = buffData[id]
            if existing then
                if existing._pendingRemovalTime then
                    existing._pendingRemovalTime = nil
                end
                AssignBuffData( existing, buffEntry )
            else
                buffData[id] = self:_GetTableFromPool( buffEntry )
            end
            seen[id] = true
        end
    end
    for id, existing in pairs( buffData ) do
        if not seen[id] then
            if not existing._pendingRemovalTime then
                existing._pendingRemovalTime = c_REMOVE_GRACE_PERIOD
            end
        end
    end
    self:_RequestRebuild( force == true )
end

function CustomUI.BuffTracker:UpdateBuffs( updatedBuffsTable, isFullList )
    if not updatedBuffsTable then return end

    if isFullList then
        local seen = self.m_scratchSeen or {}
        self.m_scratchSeen = seen
        for k in pairs( seen ) do seen[k] = nil end

        for buffId, buffData in pairs( updatedBuffsTable ) do
            if IsValidBuff( buffData ) then
                -- Purge any matching pending removal buffs first (excluding same id to prevent corrupting table pool)
                for oldId, oldBuff in pairs( self.m_buffData ) do
                    if oldId ~= buffId and oldBuff._pendingRemovalTime and BuffsMatch( oldBuff, buffData ) then
                        self:_ReleaseTableToPool( oldBuff )
                        self.m_buffData[oldId] = nil
                    end
                end

                local existing = self.m_buffData[buffId]
                if existing then
                    if existing._pendingRemovalTime then
                        existing._pendingRemovalTime = nil
                    end
                    AssignBuffData( existing, buffData )
                else
                    self.m_buffData[buffId] = self:_GetTableFromPool( buffData )
                end
                seen[buffId] = true
            end
        end
        for id, existing in pairs( self.m_buffData ) do
            if not seen[id] then
                if not existing._pendingRemovalTime then
                    existing._pendingRemovalTime = c_REMOVE_GRACE_PERIOD
                end
            end
        end
    else
        for buffId, buffData in pairs( updatedBuffsTable ) do
            local existing = self.m_buffData[buffId]

            if IsValidBuff( buffData ) then
                -- Purge any matching pending removal buffs first (excluding same id to prevent corrupting table pool)
                for oldId, oldBuff in pairs( self.m_buffData ) do
                    if oldId ~= buffId and oldBuff._pendingRemovalTime and BuffsMatch( oldBuff, buffData ) then
                        self:_ReleaseTableToPool( oldBuff )
                        self.m_buffData[oldId] = nil
                    end
                end

                if existing then
                    if existing._pendingRemovalTime then
                        existing._pendingRemovalTime = nil
                    end
                    AssignBuffData( existing, buffData )
                else
                    self.m_buffData[buffId] = self:_GetTableFromPool( buffData )
                end
            else
                if existing then
                    if not existing._pendingRemovalTime then
                        existing._pendingRemovalTime = c_REMOVE_GRACE_PERIOD
                    end
                end
            end
        end
    end

    self:_RequestRebuild()
end

----------------------------------------------------------------
-- OnBuffsChanged
----------------------------------------------------------------

function CustomUI.BuffTracker:OnBuffsChanged()
    -- Follow-up #29: skip full pipeline while hidden; rebuild on next Show(true).
    if not self:IsShowing() then
        self.m_dirtyWhileHidden = true
        return
    end

    local whitelist         = self.m_whitelist
    local whitelistAbility  = self.m_whitelistAbility
    local blacklist         = self.m_blacklist

    local postFilter = self.m_scratchPostFilter
    local inResult   = self.m_scratchInResult
    for i = #postFilter, 1, -1 do
        postFilter[i] = nil
    end
    for k in pairs( inResult ) do
        inResult[ k ] = nil
    end

    local function WhitelistHits( buffData )
        local effectId = buffData.effectIndex
        local aid      = tonumber( buffData.abilityId )
        return (effectId ~= nil and whitelist[effectId])
            or (aid ~= nil and whitelistAbility[aid])
    end

    -- Single pass: filter + blacklist/whitelist + whitelist add-back merged.
    -- Sorted iteration preserves stable display order for NONE sort mode.
    for _, bk in ipairs( self:_GetSortedKeys( self.m_buffData ) ) do
        local buffData = self.m_buffData[ bk ]
        if self.m_forceShowTrackerPriority100
           and tonumber( buffData.trackerPriority ) == 100 then
            local effectId = buffData.effectIndex
            if effectId ~= nil and not inResult[ effectId ] then
                table.insert( postFilter, buffData )
                inResult[ effectId ] = true
            end
        else
            local effectId   = buffData.effectIndex
            local inBlack    = blacklist[ effectId ]
            local inWhite    = WhitelistHits( buffData )
            local conflicted = inBlack and inWhite
            local passes     = self.filterFunc
                               and self.filterFunc( buffData )
                               or  self:_PassesFilter( buffData )

            local shouldAdd
            if conflicted then
                shouldAdd = passes              -- black+white conflict: filter decides
            elseif not inBlack then
                shouldAdd = passes or inWhite   -- not blacklisted: filter OR whitelisted
            end
            -- (blacklisted and not conflicted: never add, even if whitelisted)

            if shouldAdd and effectId ~= nil and not inResult[ effectId ] then
                table.insert( postFilter, buffData )
                inResult[ effectId ] = true
            end
        end
    end

    local postCompress = self.m_compressMultiCast
                         and CompressBuffData( self, postFilter, self.m_scratchCompress )
                         or  postFilter

    local finalData = postCompress
    if self.m_groupBuffs and self.m_buffGroups then
        finalData = self:_ApplyBuffGroups( postCompress )
    end

    local sortFn = self.sortFunc or self.m_compiledSortFunc
    if sortFn then
        -- Follow-up #30: decorate-sort duration category once per rebuild (compiled sort only).
        if sortFn == self.m_compiledSortFunc then
            local threshold = self.m_durationThreshold
            for i = 1, #finalData do
                local b = finalData[i]
                if b then
                    b._sortDurCat = GetDurationCategory( b, threshold, b._sortDurCat, b._sortDur )
                    b._sortDur = b.duration
                end
            end
        end
        table.sort( finalData, sortFn )
    end

    local maxBuffIndex = #finalData
    for buffSlot, buffFrame in ipairs( self.m_buffFrames ) do
        if buffSlot <= maxBuffIndex then
            local bd = finalData[ buffSlot ]
            buffFrame:SetBuff( bd )
        else
            buffFrame:SetBuff( nil )
        end
    end

    -- Re-apply full container dimensions after slot visibility changes.  The engine's
    -- layout pass (triggered by the SetBuff show/hide calls above) auto-fits the container
    -- to its currently-visible children, collapsing its height to just the first row.
    -- Slots in rows 2+ end up outside the container's hit bounds and never fire OnMouseOver.
    -- CENTER alignment resizes the container itself inside _ApplyCenterAlignment below, so
    -- we only need this for LEFT-aligned trackers.
    if self.m_alignment == CustomUI.BuffTracker.Alignment.LEFT
       and self.m_containerName then
        self:_ApplyContainerHitArea()
    end

    -- Apply center alignment after slots have been shown/hidden.
    if self.m_alignment == CustomUI.BuffTracker.Alignment.CENTER then
        local visibleSlots = {}
        for _, frame in ipairs( self.m_buffFrames ) do
            if frame:IsShowing() then
                table.insert( visibleSlots, frame )
            end
        end
        self:_ApplyCenterAlignment( visibleSlots )
    end

    -- Visible slots cannot exceed created frames (m_maxBuffs); #finalData may be larger.
    local visibleSlots = math.min( maxBuffIndex, self.m_maxBuffs or maxBuffIndex )
    self.m_VisibleRowCount  = self:GetVisibleRowCount( visibleSlots )
    self.m_visibleSlotCount = visibleSlots

    -- Snapshot duration categories for dirty detection in Update (sort-on path only).
    if self.m_compiledSortFunc or self.sortFunc then
        local threshold = self.m_durationThreshold
        for _, buffData in pairs( self.m_buffData ) do
            if IsValidBuff( buffData ) then
                buffData._layoutDurCat = GetDurationCategory( buffData, threshold, buffData._layoutDurCat, buffData._layoutDur )
                buffData._layoutDur = buffData.duration
            end
        end
    end
end
