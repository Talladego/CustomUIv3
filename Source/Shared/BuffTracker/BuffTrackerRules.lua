----------------------------------------------------------------
-- CustomUI.BuffTrackerRules
--
-- Rule helpers for BuffTracker category and duration classification plus
-- filter evaluation. Compression and explicit group synthesis live in
-- BuffTrackerGrouping.lua; tracker lifecycle and pooling stay in BuffTracker.lua.
----------------------------------------------------------------

if not CustomUI then
    CustomUI = {}
end

CustomUI.BuffTrackerRules = CustomUI.BuffTrackerRules or {}

local BuffTrackerRules = CustomUI.BuffTrackerRules

-- Returns "buff", "debuff", or "neutral" for a given buff entry.
function BuffTrackerRules.GetBuffCategory(buffData)
    local slice = DataUtils.GetAbilityTypeTextureAndColor(buffData)
    if slice == "Buff-Frame" then
        return "buff"
    elseif slice == "Debuff-Frame" then
        return "debuff"
    else
        return "neutral"
    end
end

-- Returns "short", "long", or "permanent" based on duration.
function BuffTrackerRules.GetDurationCategory(buffData, threshold, prevCat, prevDur)
    if buffData == nil then
        return "permanent"
    end
    if buffData.permanentUntilDispelled then
        return "permanent"
    end

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

function BuffTrackerRules.PassesFilter(tracker, buffData)
    local cfg = tracker and tracker.m_filterConfig
    if cfg == nil then
        return true
    end

    local buffCat = BuffTrackerRules.GetBuffCategory(buffData)
    if buffCat == "buff" and not cfg.showBuffs then
        return false
    end
    if buffCat == "debuff" and not cfg.showDebuffs then
        return false
    end
    if buffCat == "neutral" and not cfg.showNeutral then
        return false
    end

    local durCat = BuffTrackerRules.GetDurationCategory(
        buffData,
        tracker.m_durationThreshold,
        buffData._layoutDurCat,
        buffData._layoutDur
    )
    if durCat == "short" and not cfg.showShort then
        return false
    end
    if durCat == "long" and not cfg.showLong then
        return false
    end
    if durCat == "permanent" and not cfg.showPermanent then
        return false
    end

    if cfg.playerCastOnly and not buffData.castByPlayer then
        return false
    end

    return true
end
