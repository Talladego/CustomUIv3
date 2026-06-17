if not CustomUI then CustomUI = {} end
if not CustomUI.BuffTracker then CustomUI.BuffTracker = {} end

-- Shared schema for buff-filter settings (`SetFilter` / settings tabs).
-- Keys must match checkbox binding maps in CustomUISettingsWindow (*TabPlayer/Group/Target/TargetHUD).
CustomUI.BuffTracker.FilterSettingKeys = {
    "showBuffs", "showDebuffs", "showNeutral",
    "showShort", "showLong", "showPermanent",
    "playerCastOnly",
}

CustomUI.BuffTracker.FilterDefaults = {
    showBuffs      = true,
    showDebuffs    = true,
    showNeutral    = true,
    showShort      = true,
    showLong       = true,
    showPermanent  = true,
    playerCastOnly = false,
}

function CustomUI.BuffTracker.EnsurePairedFilterSettings(settingsTable)
    local v = settingsTable or {}
    local keys = CustomUI.BuffTracker.FilterSettingKeys
    local defs = CustomUI.BuffTracker.FilterDefaults

    if v.buffs then
        v.buffsHostile = v.buffsHostile or {}
        v.buffsFriendly = v.buffsFriendly or {}
        for _, key in ipairs(keys) do
            local value = v.buffs[key]
            if v.buffsHostile[key] == nil then
                v.buffsHostile[key] = value ~= nil and value or defs[key]
            end
            if v.buffsFriendly[key] == nil then
                v.buffsFriendly[key] = value ~= nil and value or defs[key]
            end
        end
        v.buffs = nil
    end

    if v.buffsHostile and not v.buffsFriendly then
        v.buffsFriendly = {}
        for _, key in ipairs(keys) do
            v.buffsFriendly[key] = v.buffsHostile[key] ~= nil and v.buffsHostile[key] or defs[key]
        end
    elseif v.buffsFriendly and not v.buffsHostile then
        v.buffsHostile = {}
        for _, key in ipairs(keys) do
            v.buffsHostile[key] = v.buffsFriendly[key] ~= nil and v.buffsFriendly[key] or defs[key]
        end
    end

    v.buffsHostile = v.buffsHostile or {}
    v.buffsFriendly = v.buffsFriendly or {}
    for _, key in ipairs(keys) do
        if v.buffsHostile[key] == nil then
            v.buffsHostile[key] = defs[key]
        end
        if v.buffsFriendly[key] == nil then
            v.buffsFriendly[key] = defs[key]
        end
    end

    return v
end

function CustomUI.BuffTracker.ApplyPairedFilters(settingsTable, hostileTracker, friendlyTracker)
    if hostileTracker then
        hostileTracker:SetFilter(settingsTable and settingsTable.buffsHostile)
    end
    if friendlyTracker then
        friendlyTracker:SetFilter(settingsTable and settingsTable.buffsFriendly)
    end
end
