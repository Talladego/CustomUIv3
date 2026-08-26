----------------------------------------------------------------
-- CustomUI.PortraitCareerBadge — portrait chrome layout (career badge, shared axis).
-- Used by PlayerStatus, GroupWindow, and TargetFrame portraits.
----------------------------------------------------------------

if not CustomUI then
    CustomUI = {}
end

CustomUI.PortraitCareerBadge = CustomUI.PortraitCareerBadge or {}

local Badge = CustomUI.PortraitCareerBadge

Badge.RING_W = 31
Badge.RING_H = 32
Badge.ICON_ATLAS = 32
Badge.ICON_DRAW = 20
Badge.RING_TEMPLATE = "LevelBackgroundTemplate"
Badge.PORTRAIT_AXIS_X = 0
Badge.PORTRAIT_BOTTOM_Y = 0
-- PlayerStatus / full PortraitFrame corner insets (105x111).
Badge.PORTRAIT_TOPLEFT_Y = 3
Badge.PORTRAIT_BOTTOMLEFT_Y = 70
Badge.CROWN_W = 25
Badge.CROWN_H = 16
Badge.RVR_W = 23
Badge.RVR_H = 29
-- RvR flag (0.55 scale) top inset on full 105x111 PortraitFrame.
Badge.RVR_TOP_Y = 11
Badge.PORTRAIT_FRAME_H_FULL = 111
Badge.PORTRAIT_FRAME_W_FULL = 105
-- GroupMemberUnitFrame PortraitFrame (templates_unitframes.xml).
Badge.PORTRAIT_FRAME_W_GROUP = 85
-- Scaled group frame: tune horizontal center (stock crown used +4; 0 was too far right, -4 too far left).
Badge.PORTRAIT_AXIS_X_GROUP = 0

function Badge.PortraitFrameWidth(portraitFrameWin)
    if portraitFrameWin == nil or not DoesWindowExist(portraitFrameWin) then
        return Badge.PORTRAIT_FRAME_W_FULL
    end
    local width = select(1, WindowGetDimensions(portraitFrameWin))
    width = tonumber(width)
    if width == nil or width <= 0 then
        return Badge.PORTRAIT_FRAME_W_FULL
    end
    return width
end

function Badge.AxisXForPortraitFrame(portraitFrameWin)
    local frameWidth = Badge.PortraitFrameWidth(portraitFrameWin)
    if frameWidth >= Badge.PORTRAIT_FRAME_W_FULL then
        return Badge.PORTRAIT_AXIS_X
    end
    if frameWidth <= Badge.PORTRAIT_FRAME_W_GROUP then
        return Badge.PORTRAIT_AXIS_X_GROUP
    end
    local span = Badge.PORTRAIT_FRAME_W_FULL - Badge.PORTRAIT_FRAME_W_GROUP
    local t = (frameWidth - Badge.PORTRAIT_FRAME_W_GROUP) / span
    return math.floor(Badge.PORTRAIT_AXIS_X_GROUP * (1 - t) + Badge.PORTRAIT_AXIS_X * t + 0.5)
end

function Badge.ScaleYOffsetForPortraitFrame(frameHeight, yFull)
    frameHeight = tonumber(frameHeight) or Badge.PORTRAIT_FRAME_H_FULL
    yFull = tonumber(yFull) or Badge.RVR_TOP_Y
    return math.floor(yFull * frameHeight / Badge.PORTRAIT_FRAME_H_FULL + 0.5)
end

function Badge.CornerYOffsetForPortraitFrame(portraitFrameWin, yFull)
    local frameHeight = Badge.PORTRAIT_FRAME_H_FULL
    if portraitFrameWin ~= nil and DoesWindowExist(portraitFrameWin) then
        local _, height = WindowGetDimensions(portraitFrameWin)
        height = tonumber(height)
        if height ~= nil and height > 0 then
            frameHeight = height
        end
    end
    return Badge.ScaleYOffsetForPortraitFrame(frameHeight, yFull)
end

function Badge.LayoutTopLeft(win, portraitFrameWin, yOffset, width, height, xOffset)
    if win == nil or portraitFrameWin == nil then
        return false
    end
    if not DoesWindowExist(win) or not DoesWindowExist(portraitFrameWin) then
        return false
    end
    if width ~= nil and height ~= nil then
        WindowSetDimensions(win, width, height)
    end
    WindowClearAnchors(win)
    WindowAddAnchor(
        win,
        "topleft",
        portraitFrameWin,
        "topleft",
        xOffset or 0,
        yOffset or Badge.PORTRAIT_TOPLEFT_Y
    )
    return true
end

function Badge.LayoutTopRight(win, portraitFrameWin, yOffset, width, height, xOffset)
    if win == nil or portraitFrameWin == nil then
        return false
    end
    if not DoesWindowExist(win) or not DoesWindowExist(portraitFrameWin) then
        return false
    end
    if width ~= nil and height ~= nil then
        WindowSetDimensions(win, width, height)
    end
    WindowClearAnchors(win)
    local topY = yOffset
    if topY == nil then
        topY = Badge.CornerYOffsetForPortraitFrame(portraitFrameWin, Badge.PORTRAIT_TOPLEFT_Y)
    end
    WindowAddAnchor(
        win,
        "topright",
        portraitFrameWin,
        "topright",
        xOffset or 0,
        topY
    )
    return true
end

function Badge.LayoutBottomLeft(win, portraitFrameWin, yOffset, width, height, xOffset)
    if win == nil or portraitFrameWin == nil then
        return false
    end
    if not DoesWindowExist(win) or not DoesWindowExist(portraitFrameWin) then
        return false
    end
    if width ~= nil and height ~= nil then
        WindowSetDimensions(win, width, height)
    end
    WindowClearAnchors(win)
    WindowAddAnchor(
        win,
        "topleft",
        portraitFrameWin,
        "topleft",
        xOffset or 0,
        yOffset or Badge.PORTRAIT_BOTTOMLEFT_Y
    )
    return true
end

function Badge.LayoutBottomRight(win, portraitFrameWin, yOffset, width, height, xOffset)
    if win == nil or portraitFrameWin == nil then
        return false
    end
    if not DoesWindowExist(win) or not DoesWindowExist(portraitFrameWin) then
        return false
    end
    if width ~= nil and height ~= nil then
        WindowSetDimensions(win, width, height)
    end
    WindowClearAnchors(win)
    -- Mirror LayoutBottomLeft: rank uses topleft+Y; renown uses topright+same Y.
    local y = yOffset
    if y == nil then
        y = Badge.CornerYOffsetForPortraitFrame(portraitFrameWin, Badge.PORTRAIT_BOTTOMLEFT_Y)
    end
    WindowAddAnchor(
        win,
        "topright",
        portraitFrameWin,
        "topright",
        xOffset or 0,
        y
    )
    return true
end

function Badge.LayoutTopCenter(win, portraitFrameWin, yOffset, width, height)
    if win == nil or portraitFrameWin == nil then
        return false
    end
    if not DoesWindowExist(win) or not DoesWindowExist(portraitFrameWin) then
        return false
    end
    if width ~= nil and height ~= nil then
        WindowSetDimensions(win, width, height)
    end
    WindowClearAnchors(win)
    WindowAddAnchor(
        win,
        "top",
        portraitFrameWin,
        "top",
        Badge.AxisXForPortraitFrame(portraitFrameWin),
        yOffset or 0
    )
    return true
end

local function SetWindowLayerIfAvailable(win, layer)
    if win == nil or not DoesWindowExist(win) then
        return
    end
    if type(WindowSetLayer) ~= "function" or layer == nil then
        return
    end
    WindowSetLayer(win, layer)
end

-- Runtime-created Rank-Circle inherits overlay; stock CareerIcon is secondary (Group/Target).
-- Match PlayerStatusWindow.xml: both badge windows on popup so the icon draws inside the ring.
function Badge.PrepareBadgeLayers(backgroundWin, iconWin)
    SetWindowLayerIfAvailable(backgroundWin, Window.Layers.POPUP)
    SetWindowLayerIfAvailable(iconWin, Window.Layers.POPUP)
end

function Badge.LayoutBottomCenter(win, portraitFrameWin, yOffset, width, height)
    if win == nil or portraitFrameWin == nil then
        return false
    end
    if not DoesWindowExist(win) or not DoesWindowExist(portraitFrameWin) then
        return false
    end
    if width ~= nil and height ~= nil then
        WindowSetDimensions(win, width, height)
    end
    WindowClearAnchors(win)
    WindowAddAnchor(
        win,
        "bottom",
        portraitFrameWin,
        "bottom",
        Badge.AxisXForPortraitFrame(portraitFrameWin),
        yOffset or 0
    )
    return true
end

function Badge.EnsureBackground(backgroundWin, parentWin, portraitFrameWin)
    if backgroundWin == nil or parentWin == nil or portraitFrameWin == nil then
        return false
    end
    if not DoesWindowExist(portraitFrameWin) or not DoesWindowExist(parentWin) then
        return false
    end

    if not DoesWindowExist(backgroundWin) then
        if type(CreateWindowFromTemplate) ~= "function" then
            return false
        end
        if not CreateWindowFromTemplate(backgroundWin, Badge.RING_TEMPLATE, parentWin) then
            return false
        end
    end

    Badge.PrepareBadgeLayers(backgroundWin, nil)
    return Badge.LayoutBottomCenter(backgroundWin, portraitFrameWin, Badge.PORTRAIT_BOTTOM_Y, Badge.RING_W, Badge.RING_H)
end

function Badge.EnsureBackgroundTopLeft(backgroundWin, parentWin, portraitFrameWin)
    if backgroundWin == nil or parentWin == nil or portraitFrameWin == nil then
        return false
    end
    if not DoesWindowExist(portraitFrameWin) or not DoesWindowExist(parentWin) then
        return false
    end

    if not DoesWindowExist(backgroundWin) then
        if type(CreateWindowFromTemplate) ~= "function" then
            return false
        end
        if not CreateWindowFromTemplate(backgroundWin, Badge.RING_TEMPLATE, parentWin) then
            return false
        end
    end

    Badge.PrepareBadgeLayers(backgroundWin, nil)
    local topY = Badge.CornerYOffsetForPortraitFrame(portraitFrameWin, Badge.PORTRAIT_TOPLEFT_Y)
    return Badge.LayoutTopLeft(backgroundWin, portraitFrameWin, topY, Badge.RING_W, Badge.RING_H, 0)
end

function Badge.EnsureBackgroundTopRight(backgroundWin, parentWin, portraitFrameWin)
    if backgroundWin == nil or parentWin == nil or portraitFrameWin == nil then
        return false
    end
    if not DoesWindowExist(portraitFrameWin) or not DoesWindowExist(parentWin) then
        return false
    end

    if not DoesWindowExist(backgroundWin) then
        if type(CreateWindowFromTemplate) ~= "function" then
            return false
        end
        if not CreateWindowFromTemplate(backgroundWin, Badge.RING_TEMPLATE, parentWin) then
            return false
        end
    end

    Badge.PrepareBadgeLayers(backgroundWin, nil)
    local topY = Badge.CornerYOffsetForPortraitFrame(portraitFrameWin, Badge.PORTRAIT_TOPLEFT_Y)
    return Badge.LayoutTopRight(backgroundWin, portraitFrameWin, topY, Badge.RING_W, Badge.RING_H, 0)
end

function Badge.LayoutTargetRankBadge(levelBackgroundWin, portraitFrameWin, isFriendly)
    if levelBackgroundWin == nil or portraitFrameWin == nil then
        return false
    end
    if not DoesWindowExist(levelBackgroundWin) or not DoesWindowExist(portraitFrameWin) then
        return false
    end
    local bottomY = Badge.CornerYOffsetForPortraitFrame(portraitFrameWin, Badge.PORTRAIT_BOTTOMLEFT_Y)
    if isFriendly == true then
        return Badge.LayoutBottomLeft(levelBackgroundWin, portraitFrameWin, bottomY, Badge.RING_W, Badge.RING_H, 0)
    end
    return Badge.LayoutBottomRight(levelBackgroundWin, portraitFrameWin, bottomY, Badge.RING_W, Badge.RING_H, 0)
end

function Badge.LayoutIcon(iconWin, backgroundWin)
    if iconWin == nil or backgroundWin == nil then
        return
    end
    if not DoesWindowExist(iconWin) or not DoesWindowExist(backgroundWin) then
        return
    end

    WindowSetDimensions(iconWin, Badge.ICON_DRAW, Badge.ICON_DRAW)
    WindowClearAnchors(iconWin)
    WindowAddAnchor(iconWin, "center", backgroundWin, "center", 0, 0)
    Badge.PrepareBadgeLayers(backgroundWin, iconWin)
end

function Badge.ApplyCareerLine(iconWin, careerLine)
    if iconWin == nil or not DoesWindowExist(iconWin) then
        return false
    end
    careerLine = tonumber(careerLine)
    if careerLine == nil or careerLine == 0 then
        return false
    end
    if type(Icons) ~= "table" or type(Icons.GetCareerIconIDFromCareerLine) ~= "function" then
        return false
    end

    local iconId = Icons.GetCareerIconIDFromCareerLine(careerLine)
    if iconId == nil or iconId == 0 then
        return false
    end
    if type(GetIconData) ~= "function" then
        return false
    end

    local iconTexture, iconX, iconY = GetIconData(iconId)
    if iconTexture == nil then
        return false
    end

    DynamicImageSetTexture(iconWin, iconTexture, iconX, iconY)
    if type(DynamicImageSetTextureDimensions) == "function" then
        DynamicImageSetTextureDimensions(iconWin, Badge.ICON_ATLAS, Badge.ICON_ATLAS)
    end
    return true
end

function Badge.SetShowing(iconWin, backgroundWin, showing)
    local show = showing == true
    if backgroundWin ~= nil and DoesWindowExist(backgroundWin) then
        WindowSetShowing(backgroundWin, show)
    end
    if iconWin ~= nil and DoesWindowExist(iconWin) then
        WindowSetShowing(iconWin, show)
    end
end

function Badge.LayoutAndApply(iconWin, backgroundWin, parentWin, portraitFrameWin, careerLine)
    if not Badge.EnsureBackground(backgroundWin, parentWin, portraitFrameWin) then
        Badge.SetShowing(iconWin, backgroundWin, false)
        return false
    end
    Badge.LayoutIcon(iconWin, backgroundWin)
    if not Badge.ApplyCareerLine(iconWin, careerLine) then
        Badge.SetShowing(iconWin, backgroundWin, false)
        return false
    end
    Badge.SetShowing(iconWin, backgroundWin, true)
    return true
end

function Badge.LayoutAndApplyTopRight(iconWin, backgroundWin, parentWin, portraitFrameWin, careerLine)
    if not Badge.EnsureBackgroundTopRight(backgroundWin, parentWin, portraitFrameWin) then
        Badge.SetShowing(iconWin, backgroundWin, false)
        return false
    end
    Badge.LayoutIcon(iconWin, backgroundWin)
    if not Badge.ApplyCareerLine(iconWin, careerLine) then
        Badge.SetShowing(iconWin, backgroundWin, false)
        return false
    end
    Badge.SetShowing(iconWin, backgroundWin, true)
    return true
end

function Badge.LayoutAndApplyTopLeft(iconWin, backgroundWin, parentWin, portraitFrameWin, careerLine)
    if not Badge.EnsureBackgroundTopLeft(backgroundWin, parentWin, portraitFrameWin) then
        Badge.SetShowing(iconWin, backgroundWin, false)
        return false
    end
    Badge.LayoutIcon(iconWin, backgroundWin)
    if not Badge.ApplyCareerLine(iconWin, careerLine) then
        Badge.SetShowing(iconWin, backgroundWin, false)
        return false
    end
    Badge.SetShowing(iconWin, backgroundWin, true)
    return true
end
