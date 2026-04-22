----------------------------------------------------------------
-- CustomUI.Shared.BuffTracker.Whitelist
-- Effect IDs that are always shown across all trackers by default,
-- bypassing blacklist and filter config.
--
-- Usage (from a component Controller after Create):
--   tracker:SetWhitelist( CustomUI.BuffTracker.DefaultWhitelist )
--
-- Keys are server effectIndex values (integers).
-- Values must be true.
----------------------------------------------------------------

CustomUI.BuffTracker.DefaultWhitelist = {
    -- [67890] = true,  -- Example: an important proc to always show
}
