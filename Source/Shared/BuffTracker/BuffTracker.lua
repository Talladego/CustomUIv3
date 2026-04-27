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
--   -- Filtering (nil = show everything; all fields default true except playerCastOnly)
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
--   -- Black/whitelist by server effect ID
--   -- Blacklist: absolute removal after filter (overrides whitelist).
--   -- Whitelist: adds back effectIds that the filter removed (does not override blacklist).
--   -- Having the same effectId in both lists is a misconfiguration; blacklist wins.
--   tracker:SetBlacklist({ [12345] = true })
--   tracker:SetWhitelist({ [67890] = true })
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

-- Re-declared here because IsValidBuff is local-scoped in bufftracker.lua.
local function IsValidBuff( buffData )
    return ( buffData ~= nil
         and buffData.effectIndex ~= nil
         and buffData.iconNum     ~= nil
         and buffData.iconNum     >  0 )
end

-- Returns "buff", "debuff", or "neutral" for a given buff entry.
local function GetBuffCategory( buffData )
    local slice = DataUtils.GetAbilityTypeTextureAndColor( buffData )
    if     slice == "Buff-Frame"   then return "buff"
    elseif slice == "Debuff-Frame" then return "debuff"
    else                                return "neutral" end
end

-- Returns "short", "long", or "permanent" based on duration.
local function GetDurationCategory( buffData, threshold )
    if buffData == nil then return "permanent" end
    if   buffData.permanentUntilDispelled then return "permanent"
    elseif buffData.duration < threshold  then return "short"
    else                                       return "long" end
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
local function CompressBuffData( rawBuffData )
    local groups = {}  -- [key] = { list of buffData }
    local order  = {}  -- insertion-order list of keys

    for _, buffData in pairs( rawBuffData ) do
        local id = GetCompressionGroupKey( buffData )
        if not groups[ id ] then
            groups[ id ] = {}
            table.insert( order, id )
        end
        table.insert( groups[ id ], buffData )
    end

    local result = {}
    for _, id in ipairs( order ) do
        local group = groups[ id ]
        if #group == 1 then
            table.insert( result, group[1] )
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
            local compressed = {}
            for k, v in pairs( best ) do compressed[k] = v end
            compressed.stackCount = totalStacks
            table.insert( result, compressed )
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
    self.m_buffData = buffData

    local isValidBuff = IsValidBuff( buffData )

    if isValidBuff then
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

        if buffData.stackCount > 1 then
            LabelSetText  ( windowName .. "Timer", L"x" .. buffData.stackCount )
            WindowSetShowing( windowName .. "Timer", true )
        else
            WindowSetShowing( windowName .. "Timer",
                self.m_ShowingTimerLabels == SHOW_BUFF_FRAME_TIMER_LABELS )
        end

        self:Update( true )
    end

    self:Show( isValidBuff and self.m_IsTrackerShowing )
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

function CustomUI.BuffTracker.ApplyPlayerStatusRules( tracker )
    if tracker == nil then
        return
    end

    tracker:SetSortMode( CustomUI.BuffTracker.SortMode.PERM_LONG_SHORT )
    tracker:SetBuffGroups( CustomUI.BuffTracker.BuffGroups )

    if CustomUI.BuffTracker.DefaultBlacklist ~= nil then
        tracker:SetBlacklist( CustomUI.BuffTracker.DefaultBlacklist )
    end

    if CustomUI.BuffTracker.DefaultWhitelist ~= nil then
        tracker:SetWhitelist( CustomUI.BuffTracker.DefaultWhitelist )
    end
end

-- Seconds separating "short" from "long". Override per-tracker after Create.
CustomUI.BuffTracker.DurationThreshold = 60

----------------------------------------------------------------
-- Create
-- windowName  : name for the container window and slot prefix
-- parentName  : parent window for the container
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
    -- Components anchor this window; slots are internal.
    CreateWindowFromTemplate( windowName, "CustomUIBuffContainerTemplate", parentName )
    WindowSetDimensions( windowName, containerW, containerH )
    WindowSetShowing( windowName, false )

    local newTracker = {
        m_containerName     = windowName,
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
        m_blacklist         = {},
        m_whitelist         = {},
        m_forceShowTrackerPriority100 = false,
        m_compiledSortFunc  = nil,
        m_compressMultiCast = true,
        m_groupBuffs        = true,
        m_buffGroups        = nil,
        m_groupLookup       = {},
        -- Raw escape hooks
        filterFunc          = nil,
        sortFunc            = nil,
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
    self:OnBuffsChanged()
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
    self:OnBuffsChanged()
end

-- idTable: { [effectIndex] = true }.  Pass nil or {} to clear.
function CustomUI.BuffTracker:SetBlacklist( idTable )
    self.m_blacklist = idTable or {}
    self:_WarnListConflicts()
    self:OnBuffsChanged()
end

-- idTable: { [effectIndex] = true }.  Pass nil or {} to clear.
function CustomUI.BuffTracker:SetWhitelist( idTable )
    self.m_whitelist = idTable or {}
    self:_WarnListConflicts()
    self:OnBuffsChanged()
end

function CustomUI.BuffTracker:SetForceShowTrackerPriority100( enabled )
    self.m_forceShowTrackerPriority100 = enabled == true
    self:_RebuildSortFunc()
    self:OnBuffsChanged()
end

function CustomUI.BuffTracker:SetCompressMultiCast( enabled )
    self.m_compressMultiCast = enabled == true
    self:OnBuffsChanged()
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
    self:OnBuffsChanged()
end

function CustomUI.BuffTracker:SetGroupBuffs( enabled )
    self.m_groupBuffs = enabled == true
    self:OnBuffsChanged()
end

-- Sets the alignment mode for slot layout within the container.
-- "left"   : slots placed left-to-right from the container's topleft (default).
-- "center" : visible slots re-centered horizontally on each OnBuffsChanged.
function CustomUI.BuffTracker:SetAlignment( mode )
    self.m_alignment = mode or CustomUI.BuffTracker.Alignment.LEFT
    self:OnBuffsChanged()
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
    if self.m_containerName and DoesWindowExist( self.m_containerName ) then
        WindowSetScale( self.m_containerName, scale )
    end
end

-- Clears all displayed buffs and triggers a layout refresh.
-- Use on target change or when the tracked unit becomes invalid.
function CustomUI.BuffTracker:Clear()
    self.m_buffData = {}
    self:OnBuffsChanged()
end

-- Shows or hides the container window.
function CustomUI.BuffTracker:Show( show )
    if self.m_containerName and DoesWindowExist( self.m_containerName ) then
        WindowSetShowing( self.m_containerName, show == true )
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
function CustomUI.BuffTracker:Shutdown()
    if self.m_containerName and DoesWindowExist( self.m_containerName ) then
        DestroyWindow( self.m_containerName )
    end
    self.m_containerName = nil
    self.m_buffFrames    = {}
end

----------------------------------------------------------------
-- Internal helpers
----------------------------------------------------------------

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

        local catA = GetDurationCategory( a, threshold )
        local catB = GetDurationCategory( b, threshold )
        local priA = priority[ catA ]
        local priB = priority[ catB ]

        if priA ~= priB then
            return priA > priB
        end

        if catA == "permanent" then
            local nameA = tostring( a.name or "" )
            local nameB = tostring( b.name or "" )
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

        return tostring( a.name or "" ) < tostring( b.name or "" )
    end
end

function CustomUI.BuffTracker:_PassesFilter( buffData )
    local cfg = self.m_filterConfig
    if cfg == nil then return true end

    local buffCat = GetBuffCategory( buffData )
    if buffCat == "buff"    and not cfg.showBuffs   then return false end
    if buffCat == "debuff"  and not cfg.showDebuffs then return false end
    if buffCat == "neutral" and not cfg.showNeutral then return false end

    local durCat = GetDurationCategory( buffData, self.m_durationThreshold )
    if durCat == "short"     and not cfg.showShort     then return false end
    if durCat == "long"      and not cfg.showLong      then return false end
    if durCat == "permanent" and not cfg.showPermanent then return false end

    if cfg.playerCastOnly and not buffData.castByPlayer then return false end

    return true
end

function CustomUI.BuffTracker:_ApplyBuffGroups( sourceData )
    local groupBuckets = {}
    local result       = {}

    for _, buffData in pairs( sourceData ) do
        local groupIdx = self.m_groupLookup[ buffData.abilityId ]
        if groupIdx then
            if not groupBuckets[ groupIdx ] then
                groupBuckets[ groupIdx ] = { members = {} }
            end
            table.insert( groupBuckets[ groupIdx ].members, buffData )
        else
            table.insert( result, buffData )
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
            local synthetic = {}
            for k, v in pairs( best ) do synthetic[k] = v end
            synthetic.stackCount = #members
            table.insert( result, synthetic )
        end
    end

    return result
end

function CustomUI.BuffTracker:_WarnListConflicts()
    for effectId in pairs( self.m_whitelist ) do
        if self.m_blacklist[ effectId ] then
            LogLuaMessage( "Lua", SystemData.UiLogFilters.WARNING,
                L"[CustomUI] effectIndex " .. tostring( effectId )
                .. L" is in both blacklist and whitelist. Both rules are ignored; filter result applies." )
        end
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
    -- Tick durations in m_buffData.
    for _, buffData in pairs( self.m_buffData ) do
        if IsValidBuff( buffData ) and not buffData.permanentUntilDispelled then
            buffData.duration = math.max( 0, buffData.duration - elapsedTime )
        end
    end

    if self.m_compiledSortFunc or self.sortFunc then
        -- Re-sort and reassign slots. SetBuff shares the same buffData reference
        -- so frame timer labels see the already-ticked duration — no second tick needed.
        self:OnBuffsChanged()
    else
        -- No sort: just refresh timer labels on each frame (stock behaviour).
        for _, buffFrame in ipairs( self.m_buffFrames ) do
            buffFrame:Update( false )
        end
    end
end

----------------------------------------------------------------
-- Refresh / UpdateBuffs
----------------------------------------------------------------

local function CopyBuffData( src )
    local copy = {}
    for k, v in pairs( src ) do copy[k] = v end
    return copy
end

function CustomUI.BuffTracker:Refresh()
    local allBuffs = GetBuffs( self.m_targetType )
    self.m_buffData = {}
    if allBuffs then
        for id, buffData in pairs( allBuffs ) do
            self.m_buffData[id] = CopyBuffData( buffData )
        end
    end
    self:OnBuffsChanged()
end

function CustomUI.BuffTracker:UpdateBuffs( updatedBuffsTable, isFullList )
    if not updatedBuffsTable then return end

    if isFullList then
        self.m_buffData = {}
    end

    for buffId, buffData in pairs( updatedBuffsTable ) do
        if IsValidBuff( buffData ) then
            self.m_buffData[buffId] = CopyBuffData( buffData )
        elseif not isFullList then
            self.m_buffData[buffId] = nil
        end
    end

    self:OnBuffsChanged()
end

----------------------------------------------------------------
-- OnBuffsChanged
----------------------------------------------------------------

function CustomUI.BuffTracker:OnBuffsChanged()
    local whitelist  = self.m_whitelist
    local blacklist  = self.m_blacklist

    local postFilter = {}
    local inResult   = {}

    for _, buffData in pairs( self.m_buffData ) do
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
        local inWhite    = whitelist[ effectId ]
        local conflicted = inBlack and inWhite
        local passes     = self.filterFunc
                           and self.filterFunc( buffData )
                           or  self:_PassesFilter( buffData )

        if conflicted then
            if passes then
                table.insert( postFilter, buffData )
                inResult[ effectId ] = true
            end
        elseif not inBlack then
            if passes then
                table.insert( postFilter, buffData )
                inResult[ effectId ] = true
            end
        end
        end
    end

    for _, buffData in pairs( self.m_buffData ) do
        local effectId = buffData.effectIndex
        if whitelist[ effectId ]
           and not blacklist[ effectId ]
           and not inResult[ effectId ] then
            table.insert( postFilter, buffData )
            inResult[ effectId ] = true
        end
    end

    local postCompress = self.m_compressMultiCast
                         and CompressBuffData( postFilter )
                         or  postFilter

    local finalData = postCompress
    if self.m_groupBuffs and self.m_buffGroups then
        finalData = self:_ApplyBuffGroups( postCompress )
    end

    local sortFn = self.sortFunc or self.m_compiledSortFunc
    if sortFn then
        table.sort( finalData, sortFn )
    end

    local maxBuffIndex = #finalData
    for buffSlot, buffFrame in ipairs( self.m_buffFrames ) do
        if buffSlot <= maxBuffIndex then
            buffFrame:SetBuff( finalData[ buffSlot ] )
        else
            buffFrame:SetBuff( nil )
        end
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

    self.m_VisibleRowCount = self:GetVisibleRowCount( maxBuffIndex )
end
