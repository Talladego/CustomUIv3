# CustomUI Code Quality Backlog

Last updated: 2026-04-24 (global cleanup: `CustomUI.MiniSettingsList`, `GetClientDebugLog`)

Notes: consolidated and refreshed after a focused code review of `Source/`, `CustomUISettingsWindow/`, and `CustomUI.mod`. This file tracks known bugs, design smells, and technical debt; items move into **Resolved** when fixed and are retained there for audit history.

## Audit summary (2026-04-18, verified 2026-04-23)

- The codebase is modular and well-documented: namespaced components (`CustomUI.*`), a clear Controller/View split, and reusable subsystems (`CustomUI.BuffTracker`, `CustomUI.TargetFrame`).
- Primary risks: hooks on `PetWindow.UpdatePet` without error isolation, almost no `WindowUnregisterEventHandler` pairing, unguarded `GameData` in some view paths, and SCT-specific issues (heal keying, `GetSettings` on hot paths, global/class overrides in `SCTEventText.lua`).
- `UnitFrames` correctly unregisters its window event handlers; most other components do not (see below).

## Component pattern verification (2026-04-18) — **resolved 2026-04-23**

- Controllers may still use `CreateWindowFromTemplate` for sub-widgets (e.g. target frames) as before.
- **Manifest-only `.mod`:** `<CreateWindow>` was removed from `CustomUI.mod`. Top-level window instances are created at the first step of `CustomUI.Initialize` via `EnsureRootWindowInstances()` in [Source/CustomUI.lua](Source/CustomUI.lua) (`CreateWindow(name, false)` for each root name, matching the old mod list, plus `CustomUISCTWindow`). This runs in the same `OnInitialize` order as the former pre-creates (after all `<File>` loads, before `InitializeComponents`) so **disabled** components that never run `Initialize()` still have instances for layout/saved settings. See [README.md](README.md) (Window creation pattern).
- Rationale: `InitializeComponents()` only calls `EnableComponent` → `Initialize` for **enabled** components; roots must exist regardless.

## High severity

1. **Fragile hook: `PetWindow.UpdatePet` (not `UpdatePetProxy`)**  
   - Evidence: [Source/Components/PlayerStatusWindow/Controller/PlayerPetWindowController.lua](Source/Components/PlayerStatusWindow/Controller/PlayerPetWindowController.lua) replaces `PetWindow.UpdatePet` with a wrapper that calls the saved stock function, then may hide the stock pet window. The comments note that `UpdatePetProxy` is often bypassed, which is why `UpdatePet` is hooked. The wrapper does not use `pcall` or forward extra arguments (stock signature appears to be `self` only).  
   - Risk: if the original throws, the hook can break UI code paths.  
   - Suggested fix: wrap the stock call in `pcall`, log failures, and re-apply the stock hide behavior after; keep `self` forwarding consistent with the engine.

2. **Missing `WindowUnregisterEventHandler` in most controllers**  
   - Evidence: `WindowRegisterEventHandler` is used in [PlayerStatusWindowController.lua](Source/Components/PlayerStatusWindow/Controller/PlayerStatusWindowController.lua), [PlayerPetWindowController.lua](Source/Components/PlayerStatusWindow/Controller/PlayerPetWindowController.lua), [TargetWindowController.lua](Source/Components/TargetWindow/Controller/TargetWindowController.lua), [TargetHUDController.lua](Source/Components/TargetHUD/Controller/TargetHUDController.lua), [GroupWindowController.lua](Source/Components/GroupWindow/Controller/GroupWindowController.lua). None of the matching `Shutdown`/adapter paths call `WindowUnregisterEventHandler`. [UnitFramesController.lua](Source/Components/UnitFrames/Controller/UnitFramesController.lua) *does* unregister its handlers (good reference).  
   - Risk: stale callbacks or duplicate registrations if the engine re-inits; unnecessary work.  
   - Suggested fix: for each `WindowRegisterEventHandler`, add `WindowUnregisterEventHandler` in `Shutdown`/`Disable`, or register only in `Enable` and unregister in `Disable`.

3. **Direct `GameData` / `GameData.Player` indexing without guards**  
   - Evidence: e.g. [PlayerStatusWindow.lua](Source/Components/PlayerStatusWindow/View/PlayerStatusWindow.lua) `UpdateHealthTextLabel` uses `GameData.Player.hitPoints` without checks; controller hot paths do the same. [PlayerPetWindowController.lua](Source/Components/PlayerStatusWindow/Controller/PlayerPetWindowController.lua) `HasPet()` uses `GameData.Player.Pet.name` unguarded.  
   - Risk: errors during early load or in a minimal harness.  
   - Suggested fix: add guards or a `SafeGet` helper where these run outside a known-safe window.

4. **SCT heal detection / `"Heal"` key is wrong**  
   - Evidence: [SCTEventText.lua](Source/Components/SCT/Controller/SCTEventText.lua) — in `EA_System_EventEntry:SetupText`, `key` is set from combat type, then `if isHitOrCrit and hitAmount > 0 then key = "Heal" end` (see ~line 754). `isIncoming` is computed *after* that (see ~line 758). Positive hit/crit amounts for outgoing damage can be mislabeled as heal for scaling/color/filter. `_AddCombatEventText` has a similar positive-amount + `showHeal` filter path (~1421+).  
   - Suggested fix: derive heals using incoming direction (and/or engine heal-specific event data), not `hitAmount > 0` alone.

5. ~~**Buff grouping vs compression key mismatch**~~ — **Resolved / not a bug (2026-04-17)**  
   - `CompressBuffData` uses `effectIndex` intentionally: deduplicates same-cast entries from different casters.  
   - `_ApplyBuffGroups` uses `abilityId` intentionally: collapses logically equivalent ability variants.  
   - README documents the distinction. **Do not** "fix" compression to use `abilityId` for the same role as `effectIndex` without a design pass — that would be a different feature.

## Medium severity

6. **Hot-path `GetSettings()` in SCT**  
   - Evidence: `GetSettings()` is invoked from `SetupText`, `_AddCombatEventText`, and XP/Renown/Influence helpers; migration runs on each `GetSettings()` call. `_AddXpText` / `_AddRenownText` / `_AddInfluenceText` each call `GetSettings()` twice for one filter check (~1474–1475, ~1488–1489, ~1502–1503 in [SCTEventText.lua](Source/Components/SCT/Controller/SCTEventText.lua)).  
   - Suggested fix: cache settings after init; refresh on settings changes; use one local per helper.

7. **UnitFrames visibility polling**  
   - Evidence: [UnitFramesController.lua](Source/Components/UnitFrames/Controller/UnitFramesController.lua) — `m_visibilityPollElapsed` / `c_VISIBILITY_POLL_INTERVAL` (~792+).  
   - Suggested fix: prefer transitions and explicit game signals over periodic polling where feasible.

8. **Unused fields on `CustomUI.PlayerStatusWindow.Settings`**  
    - Evidence: [PlayerStatusWindowController.lua](Source/Components/PlayerStatusWindow/Controller/PlayerStatusWindowController.lua) — `alwaysShowHitPoints` and `alwaysShowAPPoints` (defaults ~32–34) are not read elsewhere.  
    - Suggested fix: remove or wire up in the view.

9. **Duplicate `BUFF_FILTER_DEFAULTS` tables**  
    - Evidence: identical defaults in [PlayerStatusWindowController.lua](Source/Components/PlayerStatusWindow/Controller/PlayerStatusWindowController.lua) and [TargetWindowController.lua](Source/Components/TargetWindow/Controller/TargetWindowController.lua) (~561+ and ~508+). [BuffFilterSection.lua](Source/Shared/BuffFilterSection.lua) only handles *labels and checkbox UI* (legacy tabs); it does **not** own default filter values.  
    - Suggested fix: e.g. `CustomUI.BuffFilterSection.DefaultFilterTable()` in shared code, used by both controllers and settings merge logic.

10. **`m_refreshing` in SCT settings tab (wrong file in older notes)**  
    - Evidence: [CustomUISettingsWindow/source/CustomUISettingsWindowTabSCT.lua](CustomUISettingsWindow/source/CustomUISettingsWindowTabSCT.lua) — `RefreshSctControls` sets `m_refreshing = true`, runs `SetupRow` for every row in a plain loop (~407–410), then clears the flag. Other sync functions wrap work in `pcall` (e.g. `SyncSctTextFontCombo`). If `SetupRow` throws, `m_refreshing` can stay `true` and block handlers that guard on it (~720+).  
    - Suggested fix: wrap the `SetupRow` loop in `pcall` or `pcall` per row, and clear `m_refreshing` in an error path.

11. **Group window test harness always shipped**  
    - Evidence: [GroupWindowTestHarness.lua](Source/Components/GroupWindow/Controller/GroupWindowTestHarness.lua) is in the mod; [CustomUI.lua](Source/CustomUI.lua) dispatches `gwharness` via slash. Default is off; `RefreshGroupState` only replaces data when [harness is enabled](Source/Components/GroupWindow/Controller/GroupWindowController.lua).  
    - Risk: extra surface in release builds.  
    - Suggested fix: dev-only mod flag, or exclude from release manifest.

## Low severity

12. **BuffTracker / `pairs()` where order might matter**  
    - Some merge paths use `pairs` over buff maps; final display is often sorted, but stable iteration is preferable where determinism helps debugging.

13. **Near-duplicate Blacklist/Whitelist**  
    - [Blacklist.lua](Source/Shared/BuffTracker/Blacklist.lua) and [Whitelist.lua](Source/Shared/BuffTracker/Whitelist.lua) are largely parallel; could be one parameterized module.

14. **SCT diagnostic logging when `d` is absent**  
    - Evidence: [SCTEventText.lua](Source/Components/SCT/Controller/SCTEventText.lua) — `SCTLog` uses `CustomUI.GetClientDebugLog()` (`rawget(_G, "d")`). If the client does not expose `d`, `[SCT]` strings are silent (opt-in dev logging).

## SCT component ([Source/Components/SCT/](Source/Components/SCT/))

Last updated: 2026-04-23.

### High severity

- **Global overwrite of `EA_System_EventText` dispatchers** ([SCTEventText.lua](Source/Components/SCT/Controller/SCTEventText.lua) end of file): `AddCombatEventText`, `AddXpText`, etc. are replaced. `_stock` stores prior function pointers. Other addons that rely on the exact table layout or hook the same entry points can conflict. Document in README if unavoidable.

- **Heal / `"Heal"` key** — same as main **High #4** (SetupText ~754–760; ensure key uses incoming heal semantics, not `hitAmount > 0` alone).

### Medium severity

- **`EA_System_EventTracker:Update` expiry** (~1092–1101 in [SCTEventText.lua](Source/Components/SCT/Controller/SCTEventText.lua)): expiry uses `DEFAULT_FRIENDLY_EVENT_ANIMATION_PARAMETERS.maximumDisplayTime` for displayed event lifetime, not a per-tracker or per-`animData` value. If friendly/hostile point-gain parameters diverge, behavior may be wrong.

- **Crit / loading**: `BeginLoading` sets `loading` so `EA_System_EventText.Update` returns early (~1379–1383); crit trackers are not updated during load, nor cleared at load start. `Deactivate()` clears `EventTrackersCrit`. If SCT stays enabled across a load, old crit state may resume after load. Consider clearing crit trackers in `BeginLoading` (mirror `Deactivate`’s crit cleanup) if stale floating text is observed.

- **`CombatEventText` built at file load** (~26–37): indexes `GameData.CombatEvent` and `StringTables`. If the table is not ready, entries can be `nil` until re-init. Defer to `Initialize()` or guard.

- **Nil-safety for `DefaultColor.GetCombatEventColor` in `SetupText`**: if `color` is nil, `LabelSetTextColor` may error. Add a white fallback.

- **Hot-path `GetSettings()`** — same as **Medium #6** above.

### Low severity

- **Filter / delegate duplication in `_AddCombatEventText`**: some branches read `filters` directly; others use helper functions that re-read settings — hard to read; could unify.

- **Crit anchor sequence** (`CritTrackerSeq` / crit lane): monotonic counters on long sessions — low risk; reset on `Deactivate` if needed.

- **Anchor/window churn** for per-target anchors — possible future pooling.

## Validation gaps (action items)

- No regression harness covering enable/disable/reset sequences across all components.
- No smoke test for hook install/uninstall (`PetWindow.UpdatePet`, etc.) across reloads.
- No clear fault-injection path to verify `ResetAllToDefaults` surfaces component-level failures to the user.

## Best practice recommendations

- Use `pcall` in stock hooks and forward the correct `self` / arguments the engine uses.
- For every `WindowRegisterEventHandler`, add explicit unregistration or move registration to `Enable` with symmetric `Disable`.
- Top-level root windows: `EnsureRootWindowInstances` at addon `Initialize` in [Source/CustomUI.lua](Source/CustomUI.lua); per-component `Initialize` still does `RegisterWindow` / sub-`CreateWindowFromTemplate` as today; keep `.mod` as `<File>` manifest only.
- Prefer `CustomUI.*`; use `CustomUI.GetClientDebugLog()` for optional client `d` (see README). Engine-required globals (e.g. XML `Lua` / event targets) are unavoidable—document in file headers.
- Extract shared default tables (buff filters) to shared modules.
- Remove dead code, empty stubs, and dev-only files from release builds where possible.
- Cache settings on hot paths (SCT) and refresh on change.

**Quick wins (low risk):**

- Safe `pcall` around the stock `PetWindow.UpdatePet` call; keep hide-after success behavior.
- `GameData` guards in `UpdateHealthTextLabel` and a few other view helpers.
- Remove unused `alwaysShowHitPoints` / `alwaysShowAPPoints` from `CustomUI.PlayerStatusWindow.Settings`.
- Wrap `RefreshSctControls`’s `SetupRow` loop so `m_refreshing` always clears.

**Needs in-game verification:**

- SCT: fix heal key using real combat event semantics, then verify filters/colors in scenarios.

**Medium-term:**

- Systematic `WindowUnregisterEventHandler` for all components (use UnitFrames as a template).
- Extract shared `BUFF_FILTER_DEFAULTS` to shared Lua (not only UI in `BuffFilterSection`).
- Optional CI: UTF-8 (no BOM), load order in `CustomUI.mod`, simple global scan.

## Suggested next steps (from backlog)

- (A) Pet hook + `GameData` guards.  
- (B) SCT: heal key + `GetSettings` cache + `m_refreshing` hardening.  
- (C) Event unregister sweep across components.

## Resolved (since last sweep)

- **Manifest `<CreateWindow>` / component pattern** — 2026-04-23. Pre-creates moved from [CustomUI.mod](CustomUI.mod) to `EnsureRootWindowInstances()` in [Source/CustomUI.lua](Source/CustomUI.lua); `OnInitialize` now only calls `CustomUI.Initialize`.  
- **Global namespace (ListBox + debug `d`)** — 2026-04-24. Deprecated in-addon list data uses `CustomUI.MiniSettingsList` (see [MiniSettingsWindow.xml](Source/Settings/View/MiniSettingsWindow.xml), not mod-loaded); optional logging via `CustomUI.GetClientDebugLog()` in [CustomUI.lua](Source/CustomUI.lua), [SCTEventText.lua](Source/Components/SCT/Controller/SCTEventText.lua), controllers, and [CustomUISettingsWindowTabSCT.lua](CustomUISettingsWindow/source/CustomUISettingsWindowTabSCT.lua) (`EmitDebugLine`).  
- **GroupWindow: group member pet frames not implemented — code removed** — 2026-04-23. Removed `GroupPetUnitFrame` / `c_ENABLE_GROUP_PET_WINDOWS` paths, pet-only state, and no-op `LogPetStateChange` / `LogRosterChanges` from [GroupWindowController.lua](Source/Components/GroupWindow/Controller/GroupWindowController.lua); dropped harness `Pet` stubs in [GroupWindowTestHarness.lua](Source/Components/GroupWindow/Controller/GroupWindowTestHarness.lua). Player pet window (`PlayerPetWindow`) is unchanged.  
- **LibConfig / in-addon config GUI experiment removed** — 2026-04-23. Dropped `LibStub("LibConfig")`, `CustomUI_config`, and `CustomUI.LibConfig` from [CustomUI.lua](Source/CustomUI.lua); removed commented LibConfig and `CustomUIConfigSCTListWindow` lines from [CustomUI.mod](CustomUI.mod). Settings UI is the standalone [CustomUISettingsWindow](CustomUISettingsWindow/) addon.  
- **`CustomUISettingsWindowTabPlayer` buff checkboxes had no effect** — fixed 2026-04-20. `BUFF_CHECKBOX_KEYS` keys corrected (dropped `Button` suffix); pressed state read from child button name.  
- **SettingsWindow tab broker implemented** — 2026-04-18. Tabbed settings window with lazy init, stock separator pattern, components registered with enable checkbox tabs.  
- **RegisterTab duplicate/nil guard** — 2026-04-18. `RegisterTab` now silently ignores nil-template calls and deduplicates by label.  
- **Tab button chaining direction** — 2026-04-18. Corrected to stock right-to-left pattern (`right`→`left`); separator anchoring updated.  
- **Tab separator visual** — 2026-04-18. Left/right caps use stock double-anchor stretch pattern.  
- **UnitFrames never restores BattlegroupHUD callbacks** — fixed 2026-04-17.  
- **UnitFrames event handlers leaked on re-init** — fixed 2026-04-17.  
- **Component handler failures swallowed without diagnostics** — fixed 2026-04-17.  
- **TargetHUDController anonymous closure event handlers** — fixed 2026-04-17.  
- **UnitFrames library files misfiled under `Shared/`** — fixed 2026-04-17.  
- **Dead `SettingsWindow.xml` files removed** — 2026-04-17.  
- **Dev-only files trimmed** — 2026-04-17.  
- **README documentation refreshed** — 2026-04-17.  
- **PlayerPetWindow stock reappearance** — fixed 2026-04-16 (historical).  
- **SCT: settings saved to stock `EA_ScrollingCombatText_Settings`** — fixed 2026-04-19. Uses `CustomUI.Settings.SCT` only.  
- **SCT: settings reset on tab open** — fixed 2026-04-19 (`m_refreshing` / combo init).  
- **SCT: checkboxes, sliders, scale, disable path** — fixed in earlier sessions (see previous changelog in git history if needed).
