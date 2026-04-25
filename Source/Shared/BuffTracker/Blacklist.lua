----------------------------------------------------------------
-- CustomUI.Shared.BuffTracker.Blacklist
-- **Current (shipped):** `DefaultBlacklist` table; mod-loaded. Not legacy. See README "Source/Shared".
-- Effect IDs that are always hidden across all trackers by default.
--
-- Usage (from a component Controller after Create):
--   tracker:SetBlacklist( CustomUI.BuffTracker.DefaultBlacklist )
--
-- Keys are server effectIndex values (integers).
-- Values must be true.
----------------------------------------------------------------

CustomUI.BuffTracker.DefaultBlacklist = {
    -- [12345] = true,  -- Example: some unwanted aura
}
