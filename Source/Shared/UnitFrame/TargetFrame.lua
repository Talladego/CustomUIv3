----------------------------------------------------------------
-- CustomUI.TargetFrame
-- **Current (shipped):** used by TargetWindow only. Not legacy. See README "Source/Shared".
-- Subclasses the stock TargetUnitFrame class.  Most methods
-- (UpdateUnit, UpdateStatusFrame, UpdateCombatState,
-- StopInterpolatingStatus, SetCareerIcon, etc.) are inherited from
-- TargetUnitFrame unchanged. Create(), UpdateLevel(), and UpdateHealth()
-- are overridden (HP% label on the status bar).
--
-- Create() mirrors TargetUnitFrame:Create() but substitutes
-- CustomUI.BuffTracker for BuffTracker, and does NOT register with
-- UnitFrames so stock ea_targetwindow keeps its own slot undisturbed.
--
-- Usage:
--   local frame = CustomUI.TargetFrame:Create(
--       "CustomUIHostileTargetFrame",  -- unique window name
--       "selfhostiletarget",           -- unitId
--       GameData.BuffTargetType.TARGET_HOSTILE,
--       maxBuffSlots, buffStride )
--
--   frame:SetParent( "CustomUIHostileTargetWindow" )
--   frame:SetScale ( WindowGetScale( "CustomUIHostileTargetWindow" ) )
--   frame:SetAnchor( { ... } )
--   frame.m_BuffTracker:SetBuffGroups( CustomUI.BuffTracker.BuffGroups )
--
-- Controller event routing (call these from WindowRegisterEventHandler):
--   frame:UpdateUnit()
--   frame:StopInterpolatingStatus()
--   frame:UpdateCombatState( isInCombat )
--   frame.m_BuffTracker:UpdateBuffs( updatedEffects, isFullList )
--   frame.m_BuffTracker:Update( timePassed )
--
-- Cleanup:
--   frame.m_BuffTracker:Shutdown()  -- must precede Destroy()
--   frame:Destroy()
----------------------------------------------------------------

if not CustomUI then CustomUI = {} end

----------------------------------------------------------------
-- Module guard
----------------------------------------------------------------

CustomUI.TargetFrame         = TargetUnitFrame:Subclass( "TargetUnitFrame" )
CustomUI.TargetFrame.__index = CustomUI.TargetFrame

----------------------------------------------------------------
-- Anchor tables mirroring stock TargetUnitFrame:Create layout
----------------------------------------------------------------

-- Status frame (health bar + name + tier + con) positioning.
-- Hostile: right of portrait.  Friendly: left of portrait (mirrored).
local c_STATUS_ANCHOR_HOSTILE =
{
    Point         = "left",
    RelativePoint = "right",
    XOffset       = 2,
    YOffset       = -4,
}

local c_STATUS_ANCHOR_FRIENDLY =
{
    Point         = "right",
    RelativePoint = "left",
    XOffset       = -18,
    YOffset       = -4,
}

----------------------------------------------------------------
-- Create
-- Mirrors TargetUnitFrame:Create() but uses CustomUI.BuffTracker.
-- buffTargetType  GameData.BuffTargetType.TARGET_HOSTILE or TARGET_FRIENDLY
-- maxBuffSlots    Total buff icon slots.
-- buffStride      Icons per row before wrapping.
--
-- Buff slots are always anchored relative to windowName.."Status", matching
-- the layout that stock TargetUnitFrame:Create() uses.
----------------------------------------------------------------

function CustomUI.TargetFrame:Create( windowName, unitId,
                                      buffTargetType,
                                      maxBuffSlots, buffStride )

    local newFrame = self:CreateFromTemplate( windowName )
    if newFrame == nil then return nil end

    -- Always draw HP% on the bar (TargetInfo health is already 0–100).
    newFrame.m_AlwaysShowHitPoints = true
    newFrame.m_UnitId              = unitId
    newFrame.m_Type                = 0
    newFrame.m_IsAStaticObject     = false
    newFrame.m_IsThePlayer         = false
    newFrame.m_IsFriendly          = ( unitId == "selffriendlytarget" )

    local portraitWindow  = windowName .. "PortraitFrame"
    local careerIconWindow = windowName .. "CareerIcon"

    -- Mirror portrait + career icon for the friendly side.
    if newFrame.m_IsFriendly then
        WindowClearAnchors( portraitWindow )
        WindowAddAnchor( portraitWindow, "topleft", windowName, "topleft", 0, 0 )

        WindowClearAnchors( careerIconWindow )
        WindowAddAnchor( careerIconWindow, "topleft", portraitWindow, "topleft", 0, 56 )
    else
        -- Sigil button (hostile only).
        local sigilButtonName = windowName .. "SigilButton"
        if CreateWindowFromTemplate( sigilButtonName, "UnitFrameHostileSigilButton", windowName ) then
            WindowAddAnchor( sigilButtonName, "right", portraitWindow, "right", 0, 0 )
            WindowSetShowing( sigilButtonName, false )
        end
    end

    -- Status frame (health bar, name, tier, con, swords).
    -- Copy the constant so we don't mutate the module-level table.
    local src          = newFrame.m_IsFriendly and c_STATUS_ANCHOR_FRIENDLY or c_STATUS_ANCHOR_HOSTILE
    local statusAnchor = { Point = src.Point, RelativePoint = src.RelativePoint,
                           XOffset = src.XOffset, YOffset = src.YOffset,
                           RelativeTo = portraitWindow }

    newFrame.m_StatusFrame = TargetUnitFrameStatus:Create(
        windowName .. "Status", windowName, statusAnchor, newFrame.m_IsFriendly )

    -- HP% label over the dynamically created HealthPercentBar (stock status
    -- container has TierLabel on the bar, but no HealthText like PlayerWindow).
    local healthTextName = windowName .. "StatusHealthText"
    local healthBarName  = windowName .. "StatusHealthPercentBar"
    if CreateWindowFromTemplate( healthTextName, "CustomUITargetHealthText", windowName .. "Status" ) then
        WindowClearAnchors( healthTextName )
        WindowAddAnchor( healthTextName, "topleft",     healthBarName, "topleft",     0, 0 )
        WindowAddAnchor( healthTextName, "bottomright", healthBarName, "bottomright", 0, 0 )
        WindowSetShowing( healthTextName, false )
    end

    -- Buff tracker — CustomUI subclass with square frame aesthetic.
    -- Prefix windowName.."CUIBuffs" avoids collision with the stock
    -- TargetUnitFrame tracker's windowName.."Buffs" slot names.
    -- Container is anchored below the Status frame, inset slightly to clear the border.
    newFrame.m_BuffTracker = CustomUI.BuffTracker:Create(
        windowName .. "CUIBuffs", windowName,
        buffTargetType, maxBuffSlots, buffStride, SHOW_BUFF_FRAME_TIMER_LABELS )

    local buffXOffset = newFrame.m_IsFriendly and 14 or 2
    local buffYOffset = newFrame.m_IsFriendly and -3 or -4
    WindowClearAnchors( windowName .. "CUIBuffs" )
    WindowAddAnchor( windowName .. "CUIBuffs", "bottomleft", windowName .. "Status", "topleft", buffXOffset, buffYOffset )
    newFrame.m_BuffTracker:Show( true )

    -- RvR flag indicator.
    newFrame.m_RvRFrame = RvRIndicator:Create( windowName .. "RvRFlagIndicator", windowName )

    -- Bail out if any required sub-frame failed.
    if newFrame.m_StatusFrame == nil
    or newFrame.m_BuffTracker == nil
    or newFrame.m_RvRFrame    == nil then
        newFrame:Destroy()
        return nil
    end

    newFrame.m_RvRFrame:SetAnchor( { Point        = "top",
                                     RelativePoint = "center",
                                     RelativeTo    = portraitWindow,
                                     XOffset       = 0, YOffset = 25 } )

    -- Name label colour and alignment.
    local nameInfo = newFrame.m_IsFriendly
                     and { color = DefaultColor.NAME_COLOR_PLAYER, align = "leftcenter" }
                     or  { color = DefaultColor.NAME_COLOR_THREAT, align = "rightcenter" }

    LabelSetTextColor(  windowName .. "StatusName",
                        nameInfo.color.r, nameInfo.color.g, nameInfo.color.b )
    LabelSetTextAlign(  windowName .. "StatusName", nameInfo.align )

    -- Level circle anchor.
    local levelAnchorInfo = newFrame.m_IsFriendly
                            and { point = "topleft",   relPoint = "topleft",   xo = 0,    yo = 3  }
                            or  { point = "topright",  relPoint = "center",    xo = -103, yo = 66 }
    WindowClearAnchors( windowName .. "LevelBackground" )
    WindowAddAnchor( windowName .. "LevelBackground",
                     levelAnchorInfo.point, portraitWindow,
                     levelAnchorInfo.relPoint, levelAnchorInfo.xo, levelAnchorInfo.yo )

    -- Mirror health-bar frame texture for hostile target.
    DynamicImageSetTextureOrientation( windowName .. "StatusHealthBarFrame",
                                       newFrame.m_IsFriendly )

    -- Combat swords start hidden.
    WindowSetShowing( windowName .. "StatusSwordLeft",  false )
    WindowSetShowing( windowName .. "StatusSwordRight", false )

    return newFrame
end

-- TargetWindow level display should always show true career rank.
function CustomUI.TargetFrame:UpdateLevel(level, battleLevel, conColor)
    local windowName = self:GetName()
    local levelColor = self.m_IsFriendly and DefaultColor.WHITE or DefaultColor.BLACK

    LabelSetText(windowName .. "LevelText", L"" .. level)
    LabelSetTextColor(windowName .. "LevelText", levelColor.r, levelColor.g, levelColor.b)
    WindowSetTintColor(windowName .. "LevelBackgroundTint", conColor.r, conColor.g, conColor.b)
    WindowSetShowing(windowName .. "LevelBackgroundTint", not self.m_IsFriendly)
    WindowSetShowing(windowName .. "LevelText", self.m_IsAStaticObject == false)
    WindowSetShowing(windowName .. "LevelBackground", self.m_IsAStaticObject == false)
end

-- Stock UpdateHealth only fills the bar; overlay current HP as an integer percent
-- (same visual role as PlayerStatusWindow's current/max HealthText).
function CustomUI.TargetFrame:UpdateHealth()
    TargetUnitFrame.UpdateHealth(self)

    local windowName     = self:GetName()
    local healthTextName = windowName .. "StatusHealthText"
    if not DoesWindowExist(healthTextName) then
        return
    end

    local showHealth = (self.m_Type ~= SystemData.TargetObjectType.STATIC) or self.showHealthBar
    if not showHealth then
        WindowSetShowing(healthTextName, false)
        return
    end

    local hp = tonumber(TargetInfo:UnitHealth(self.m_UnitId)) or 0
    if hp < 0 then
        hp = 0
    elseif hp > 100 then
        hp = 100
    end
    local hpRounded = math.floor(hp + 0.5)

    LabelSetText(healthTextName, towstring(hpRounded) .. L"%")
    WindowSetShowing(healthTextName, true)

    -- TierLabel uses the same bar area (Champion / Hero / Lord / Friendly).
    -- Prefer HP% there; portrait skulls still convey threat for hostiles.
    local tierLabel = windowName .. "StatusTierLabel"
    if DoesWindowExist(tierLabel) then
        WindowSetShowing(tierLabel, false)
    end
end
