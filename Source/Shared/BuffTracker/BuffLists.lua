----------------------------------------------------------------
-- CustomUI.Shared.BuffTracker — default blacklist / whitelist tables
-- **Merged module** (was Blacklist.lua + Whitelist.lua). Mod-loaded; see README "Source/Shared".
--
-- Usage (unchanged):
--   tracker:SetBlacklist( CustomUI.BuffTracker.DefaultBlacklist )
--   tracker:SetWhitelist( CustomUI.BuffTracker.DefaultWhitelist )
--   tracker:SetWhitelistAbility( CustomUI.BuffTracker.DefaultWhitelistAbility )
--
-- Keys:
--   DefaultBlacklist / DefaultWhitelist: server effectIndex (integers); values true.
--   DefaultWhitelistAbility: abilityId from buffData (tonumber).
-- Semantics match BuffTracker.lua (whitelist rescues filter drops; blacklist on effect wins when keyed on effectIndex).
----------------------------------------------------------------

CustomUI.BuffTracker.DefaultBlacklist = {
    -- [12345] = true,  -- Example: some unwanted aura
}

CustomUI.BuffTracker.DefaultWhitelist = {
    -- [effectIndexHere] = true,
}

----------------------------------------------------------------
-- Guard + Save Da Runts (source: repo `guard_whitelist.csv` Icon/Id rows)
----------------------------------------------------------------
CustomUI.BuffTracker.DefaultWhitelistAbility = {
    [1363] = true, -- Guard
    [1674] = true, -- Save Da Runts
    [8013] = true, -- Guard
    [8325] = true, -- Guard
    [9008] = true, -- Guard
    [9325] = true, -- Guard
}
