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
