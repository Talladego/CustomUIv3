----------------------------------------------------------------
-- CustomUI.Shared.BuffTracker.BuffGroups
-- **Current (shipped):** data for `SetBuffGroups`; mod-loaded. Not legacy. See README "Source/Shared".
-- Named groups of effect IDs that trackers can merge into single icons.
--
-- All stat-variant abilities (e.g. "Brute's Theft of Strength",
-- "Brute's Theft of Toughness", ...) share one icon and behave as
-- one logical effect, so they are collapsed into a single buff slot.
--
-- Usage (from a component Controller after Create):
--   tracker:SetBuffGroups( CustomUI.BuffTracker.BuffGroups )
--   tracker:SetGroupBuffs( true )
--
-- Each entry:
--   name      (string)  Internal identifier for the group (Lua string, developer reference only).
--                       Not displayed in-game; the synthetic icon inherits the name from
--                       whichever group member's buffData was selected as the base entry.
--   abilityIds (table)  Server abilityId values (integers) belonging to
--                       the group.  Use abilityId, NOT effectIndex — effectIndex
--                       is a dynamic per-cast slot and is not stable across casts.
--                       Any subset of abilityIds may be active at once.
----------------------------------------------------------------

CustomUI.BuffTracker.BuffGroups = {

    -- Black Orc: Brute's Theft of [Stat]
    -- Icon 2554.  All seven stat-steal variants collapse into one slot.
    -- abilityIds verified in-game via GetBuffs dump.
    {
        name       = "BrutesTheft",
        abilityIds = {
            3232,  -- Brute's Theft of Strength       (effectIndex: unverified)
            3233,  -- Brute's Theft of Intelligence   (effectIndex: unverified)
            3234,  -- Brute's Theft of Willpower      (effectIndex: unverified)
            3235,  -- Brute's Theft of Toughness      (effectIndex: unverified)
            3236,  -- Brute's Theft of Initiative     (effectIndex: unverified)
            3237,  -- Brute's Theft of Weapon Skill   (effectIndex: unverified)
            3238,  -- Brute's Theft of Ballistic Skill (effectIndex: unverified)
        },
    },

    -- Swordmaster: Nature's Theft of [Stat]
    -- Icon 13374.  All seven stat-steal variants collapse into one slot.
    -- abilityIds verified in-game via GetBuffs dump (2026-04-14).
    {
        name       = "NaturesTheft",
        abilityIds = {
            3687,  -- Nature's Theft of Strength
            3688,  -- Nature's Theft of Intelligence
            3689,  -- Nature's Theft of Willpower
            3690,  -- Nature's Theft of Toughness
            3691,  -- Nature's Theft of Initiative
            3692,  -- Nature's Theft of Weapon Skill
            3693,  -- Nature's Theft of Ballistic Skill
        },
    },

}
