# CustomUI Code Quality Backlog

Last updated: 2026-04-20 (session 3)

Notes: consolidated and refreshed after a focused code review of `Source/` (controllers, views, and shared libraries). This file tracks known bugs, design smells, and technical debt; items move into **Resolved** when fixed and are retained there for audit history.

## Audit summary (2026-04-18)
- The codebase is modular and well-documented: namespaced components (`CustomUI.*`), a clear Controller/View split, and reusable subsystems (`CustomUI.BuffTracker`, `CustomUI.TargetFrame`).
- Primary risks discovered: fragile hook wrappers, inconsistent buff grouping keys, and a few places that assume `GameData` is present without guards. Several medium issues are about event lifecycle and test/harness hygiene.

## Component pattern verification (2026-04-18)

- I updated `README.md` with the canonical component implementation pattern (XML templates → controller instantiation → controller handles runtime mutations → shared logic in `Source/Shared`).
- Verification summary:
   - Controllers instantiate their component windows using `CreateWindowFromTemplate` where needed (examples: `TargetWindow` uses `CustomUITargetWindowTemplate` in `Source/Components/TargetWindow/View/TargetWindow.xml`; `TargetHUD` uses `CustomUITargetHUDTemplate` in `Source/Components/TargetHUD/View/TargetHUD.xml`).
   - Shared code (`Source/Shared/UnitFrame/TargetFrame.lua`) uses `CreateWindowFromTemplate` to create small, reusable sub-widgets (e.g. sigil button). This is acceptable because it's part of a shared UI primitive used by multiple controllers.
   - Deviation found: `CustomUI.mod` contains `<CreateWindow ... />` entries inside the `<OnInitialize>` section that pre-create `CustomUI` windows (e.g. `CustomUIMiniSettingsWindow`, `CustomUIPlayerStatusWindow`, `CustomUIHostileTargetWindow`, etc.). Per the documented pattern, the `.mod` file should act only as a manifest and not create component windows directly. These `<CreateWindow>` entries should be removed or minimized and window creation moved into each component's `Initialize()` (controller) unless there is a strong engine/ordering reason to pre-create them.

Recommended immediate action:
   - Remove the `<CreateWindow>` entries from `CustomUI.mod` and ensure each component's `Initialize()` creates its own window from the XML template (or calls `CreateWindowFromTemplate` if a runtime creation step is needed).
   - If certain windows must be pre-created for engine persistence of saved settings, document those exceptions explicitly in `README.md` and narrow the `<CreateWindow>` list to only those cases.


## High Severity

1. **Fragile hook wrapper: `PetWindow.UpdatePetProxy`**
   - Evidence: [Source/Components/PlayerPetWindow/Controller/PlayerPetWindowController.lua] creates a wrapper that calls the original but does not preserve arguments/returns or protect via `pcall`.
   - Risk: if the original throws, the hook can abort UI code paths or drop return values expected by the caller; subtle behavioral changes may appear in edge cases.
   - Suggested fix: install a safe wrapper that forwards `...` to the original, uses `pcall` to isolate errors, re-applies the stock hide, logs failures, and returns original results.

2. ~~**Buff grouping vs compression key mismatch**~~ — **Resolved / Not a bug (2026-04-17)**
   - `CompressBuffData` uses `effectIndex` intentionally: it deduplicates same-cast entries from different casters (per-cast slot, correct for that purpose).
   - `_ApplyBuffGroups` uses `abilityId` intentionally: it collapses logically equivalent ability variants (e.g. all Nature's Theft stat variants) into one icon.
   - These are two separate, complementary pipelines. The README has been updated to clarify the distinction.

## Medium Severity

3. **Missing explicit event unregistration in some controllers**
   - Evidence: several controllers register with `WindowRegisterEventHandler` during `Initialize()` (e.g. PlayerStatusWindow, TargetWindow, GroupWindow) but do not always unregister the matching handlers in `Shutdown()` or `Disable()` paths.
   - Risk: stale callbacks or double registrations after repeat enable/disable cycles; harder to reason about lifecycle and can leak CPU/time.
   - Suggested fix: for every `WindowRegisterEventHandler` add a corresponding `WindowUnregisterEventHandler` in `Shutdown`/`Disable`, or move registration to `Enable` with symmetric unregister in `Disable`.

4. **Direct `GameData` indexing without guards in view helpers**
   - Evidence: view helpers such as `UpdateHealthTextLabel` index `GameData.Player.hitPoints` directly.
   - Risk: during early load or test harness runs `GameData` may be nil and cause Lua errors; diagnostics and tests can exercise these paths.
   - Suggested fix: add small guards `if GameData and GameData.Player and GameData.Player.hitPoints then ... end` or a `SafeGet` helper.

5. **UnitFrames excessive polling / aggressive hide behavior**
   - Evidence: `UnitFramesController` polls visibility and calls hide routines frequently rather than on transitions.
   - Risk: conflicts with user workflows and other addons; avoidable CPU usage.
   - Suggested fix: debounce/harden to act only on transitions or explicit signals.

6. **Stale or inaccurate backlog entries**
   - Evidence: earlier entries about `TargetHUD` wiring were outdated — `TargetHUD` XML and controller now include proper named handlers and are wired. (Audit removed the stale blocking entry.)

7. **`c_ENABLE_GROUP_PET_WINDOWS` permanently `false` — pet frame code is dead**
   - Evidence: `GroupWindowController.lua` line 34 sets `c_ENABLE_GROUP_PET_WINDOWS = false`. Every code path that creates, shows, or manages pet frames (~lines 722–759) branches immediately to `HidePetFrame` without doing anything.
   - Risk: code is maintained and read but has no runtime effect; any future change to the pet logic is wasted work unless the flag is enabled.
   - Suggested fix: either enable the flag and verify pet frames work, or delete the pet frame code paths and the constant.

8. **`LogPetStateChange` / `LogRosterChanges` are empty no-ops**
   - Evidence: `GroupWindowController.lua` — both functions contain only `return`; they are called 6+ times throughout the file.
   - Risk: no harm, but misleading to readers and a sign of abandoned debug instrumentation.
   - Suggested fix: delete both functions and their call sites.

9. **Unused fields on `CustomUI.PlayerStatusWindow.Settings`**
   - Evidence: `PlayerStatusWindowController.lua` lines ~32–35 define `alwaysShowHitPoints` and `alwaysShowAPPoints`; neither field is read or written anywhere else in the codebase.
   - Suggested fix: remove both fields.

10. **LibConfig guard block runs every session with no effect**
    - Evidence: `CustomUI.lua` lines ~556–566 attempt to load `LibStub("LibConfig")` and call `CustomUI_config.OnInitialize`, but both modules are commented out in `CustomUI.mod`.
    - Risk: dead code runs on every session startup; confusing to future readers.
    - Suggested fix: remove the block, or re-enable LibConfig if it is still intended.

11. **Duplicate `BUFF_FILTER_DEFAULTS` in PlayerStatusWindow and TargetWindow controllers**
    - Evidence: identical default tables (`showBuffs`, `showDebuffs`, `showNeutral`, `showShort`, `showLong`, `showPermanent`, `playerCastOnly`) are defined independently in both controllers.
    - Risk: the two can drift if a new filter key is added to one but not the other.
    - Suggested fix: extract to `BuffFilterSection.lua` as `CustomUI.BuffFilterSection.DefaultSettings()` and reference it from both controllers.

## Low Severity

12. **Dev/test harnesses shipped in release**
    - Evidence: `GroupWindowTestHarness.lua` is packaged and loaded unconditionally via `CustomUI.mod`.
    - Risk: increases memory/maintenance surface; accidental activation in production.
    - Suggested fix: gate behind a dev-only setting or remove from release builds.

13. **Broad global for MiniSettings data**
    - Evidence: `MiniSettingsData` is a global used by the XML ListBox population code; collisions are possible.
    - Suggested fix: keep the engine-required single-dot global but minimize its scope and clear it on Shutdown.

14. **BuffTracker ordering non-determinism**
    - Evidence: group collapse uses `pairs()` in some collection phases; final sorting hides this in most cases but a stable-iteration approach is preferred.
    - Suggested fix: iterate groups with `ipairs()` over explicit arrays or maintain insertion order explicitly.

15. **Near-duplicate blacklist/whitelist boilerplate**
    - Evidence: `Blacklist.lua` and `Whitelist.lua` differ only by variable name and could be consolidated.

16. **Stale commented-out code blocks in `CustomUI.lua` and `CustomUI.mod`**
    - Evidence: three blocks of commented-out `MiniSettingsWindow` calls in `CustomUI.lua` (lines ~245, 340–342, 397–399, 511–516) and two blocks of commented-out file entries in `CustomUI.mod` (LibConfig files ~36–42; MiniSettingsWindow files ~51–54), plus commented `<CreateWindow>` entries. MiniSettingsWindow is fully disabled; the call sites and manifest entries should be removed together.

17. **`CustomUISettingsWindowTabPlayer.OnBuffFilterChanged` — buff checkbox fix (2026-04-20)**
    - Evidence: `BUFF_CHECKBOX_KEYS` used keys with `Button` suffix (e.g. `BuffTrackerBuffsButton`) but `SystemData.ActiveWindow.name` on `OnLButtonUp` of `EA_LabelCheckButton` returns the outer window name (no `Button` suffix). Key lookup always failed; filter changes had no effect.
    - Fix applied: keys corrected to outer window names; pressed-state read from `winName .. "Button"` child.

## Validation Gaps (action items)

- No regression harness covering enable/disable/reset sequences across all components.
- No smoke test for hook-install/uninstall behavior (UnitFrames / PlayerPetWindow) across reloads.
- No clear fault-injection path to verify `ResetAllToDefaults` surfaces component-level failures to the user.

## SCT component (`Source/Components/SCT/`)

Last updated: 2026-04-19.

### High severity

- **Global overwrite of `EA_System_EventText` and related globals** (`SCTEventText.lua`): `EA_System_EventEntry` and `EA_System_PointGainEntry` are replaced unconditionally at file load; `_stock` only saves the four dispatch functions, not the class definitions. Disabling SCT restores the dispatch functions but leaves the replaced classes in place. Risk: conflicts with other addons that extend or depend on stock class definitions.

- **Heal detection is wrong** (`SetupText`, line 200): `if isHitOrCrit and hitAmount > 0 then key = "Heal"` maps all positive hit/crit amounts to the "Heal" key. Outgoing damage can also be positive; the condition was likely intended to detect incoming heals (where the player is the target and amount is positive) but does not distinguish them from taking damage. Result: damage and heals share the same size/color/filter slot and the "Heal" filter row in the settings has no effect on actual healing. Needs either a separate heal combat event type check or an explicit `isIncoming and isHitOrCrit and hitAmount > 0` condition.

### Medium severity

- **`_AddXpText` / `_AddRenownText` / `_AddInfluenceText` call `GetSettings()` twice** per event (`SCTEventText.lua` lines 628-629, 642-643, 656-657): pattern `(CustomUI.SCT.GetSettings().outgoing or {}).filters and CustomUI.SCT.GetSettings().outgoing.filters.showXP` invokes `GetSettings()` (including its migration pass) twice. Cache the result in a local.

- **`EA_System_EventTracker:Update` uses hardcoded expiry constant** (line 379): expiry check compares against `DEFAULT_FRIENDLY_EVENT_ANIMATION_PARAMETERS.maximumDisplayTime` directly instead of the tracker's own `animData.maximumDisplayTime`. Hostile and point-gain trackers have the same value now but this will silently break if display times diverge.

- **Crit trackers not purged on map transition** (`SCTEventText.lua`): `BeginLoading` sets `loading = true` (pausing updates) but does not destroy entries in `EventTrackersCrit`. `Deactivate()` purges them, but if the component stays enabled across a load, crit tracker entries from the previous map can linger until they expire naturally. At minimum, `BeginLoading` should call the same cleanup loop that `Deactivate` runs on the crit table.

- **`m_refreshing` flag not reset on error** (`SCTController.lua`, `RefreshControls`): `SetupRow` calls are not wrapped in `pcall` inside the `m_refreshing = true` block. If any call throws, `m_refreshing` stays `true` permanently and all subsequent user interactions with the settings tab are silently ignored. Wrap the loop body or the whole block in `pcall` with a reset in the error branch.

- **GameData lookups at file-load time** (`SCTEventText.lua`): `CombatEventText` table is built at module load. If `GameData` or `StringTables` are not yet populated at that point, the table entries silently become `nil`. Defer to `Initialize()` or guard with `pcall`.

- **Nil-safety for color resolution** (`EA_System_EventEntry:SetupText`): `DefaultColor.GetCombatEventColor(...)` return value is used as `color.r / color.g / color.b` without a nil check. If the engine returns nil for an unsupported event type, the subsequent `LabelSetTextColor` call will error. Add a fallback `color = color or { r=255, g=255, b=255 }`.

- **Hot-path `GetSettings()` calls**: `GetSettings()` is called on every combat event and every `SetupText` invocation. It runs migration checks on every call. Cache the result after `Initialize()` and invalidate/refresh only when settings change.

### Low severity

- **`_AddCombatEventText` filter resolution is duplicated** (lines 573-595): for `isHitOrCrit` events it reads `filters` directly from the settings table; for other types it delegates to `CombatTypeIncomingEnabled` / `CombatTypeOutgoingEnabled` which re-read the same table internally. The two paths are logically equivalent but expressed differently, making the filter logic harder to follow and maintain.

- **Crit anchor window naming collides on high-frequency combat** (`SCTEventText.lua` line 605): `CritTrackerSeq` is a monotonically increasing integer that is never reset while the component is active. On a long play session with heavy crit traffic, the counter can grow large. Not an immediate problem but consider resetting on `Deactivate()`.

- **Anchor/window churn**: creating and destroying anchor windows per target per combat event — consider pooling for frequently hit targets.

### Resolved since last review

- **Settings saved to stock `EA_ScrollingCombatText_Settings`** — fixed 2026-04-19. SCT now uses `CustomUI.Settings.SCT` exclusively; stock saved variables are untouched.
- **Settings reset on tab open** — fixed 2026-04-19. `ComboBoxAddMenuItem` fired `OnSelChanged` during `RefreshControls`, overwriting stored values. Guarded with `m_refreshing` flag.
- **Checkbox state not persisting** — fixed (earlier session). Engine fires `OnLButtonUp` before toggling button state; handler now toggles the stored value directly.
- **Slider max capped at 0.75** — fixed (earlier session). `SliderBarSetCurrentPosition` takes normalized 0–1; was passing 1-based tick index.
- **Crash at scale > 1.0** — fixed (earlier session). Missing `WindowSetScale` paired with `WindowSetRelativeScale` and `ForceProcessAnchors`.
- **SCT active regardless of enable checkbox** — fixed (earlier session). `Activate()` now checks `IsComponentEnabled("SCT")`.
- **Stock SCT behavior lost when CustomUI SCT disabled** — fixed (earlier session). Handlers fall through to `_stock.*` when `m_active` is false.

## Recommendations (next actions)

- High-priority (fast):
  - Implement a safe wrapper for `PetWindow.UpdatePetProxy` that forwards `...`, wraps the original call in `pcall`, logs failures, and returns original results.
  - Add `GameData` guards to a few critical view helpers (`PlayerStatusWindow.UpdateHealthTextLabel`, etc.).
  - Delete `LogPetStateChange`, `LogRosterChanges`, and their call sites (`GroupWindowController.lua`).
  - Remove unused `alwaysShowHitPoints` / `alwaysShowAPPoints` from `CustomUI.PlayerStatusWindow.Settings`.
  - Remove the LibConfig guard block from `CustomUI.lua` (dead since modules are commented out).

- Higher-confidence change (requires in-game verification):
  - Align `BuffTracker` compression/grouping to use `abilityId` for cross-caster grouping; add an optional debug dump of `GetBuffs()` to validate before enabling.
  - Decide on pet frame code: enable `c_ENABLE_GROUP_PET_WINDOWS` and verify, or delete the dead code paths.

- Medium-term:
  - Add explicit `WindowUnregisterEventHandler` calls in `Shutdown`/`Disable` for all registered handlers, or move registration to `Enable` with symmetric unregister in `Disable`.
  - Gate dev/test harness files behind a dev flag or remove from `CustomUI.mod` for release.
  - Extract `BUFF_FILTER_DEFAULTS` to `BuffFilterSection.lua` to avoid the PlayerStatusWindow/TargetWindow drift risk.
  - Add a CI script (or developer script) that checks: all Lua/XML files are UTF-8 without BOM, no accidental globals (basic grep), and `CustomUI.mod` load order (core → shared → components).

## Suggested quick choices for immediate work

- (A) Apply quick safe fixes now: `PetWindow.UpdatePetProxy` wrapper safety + `GameData` guards + dead no-op function removal (small, low-risk).
- (B) Implement `abilityId` grouping and add an in-game dump verification mode (medium risk; needs manual verification).
- (C) Large refactor: finish adapter integration for `UnitFrames` (high effort; split into follow-up tasks).

## Resolved (since last sweep)

- **`CustomUISettingsWindowTabPlayer` buff checkboxes had no effect** — fixed 2026-04-20. `BUFF_CHECKBOX_KEYS` keys corrected (dropped `Button` suffix); pressed-state read from child button name.
- **SettingsWindow tab broker implemented** — 2026-04-18. Tabbed settings window with lazy init, stock separator pattern, all 6 components registered with enable checkbox tabs.
- **RegisterTab duplicate/nil guard** — 2026-04-18. `RegisterTab` now silently ignores nil-template calls and deduplicates by label.
- **Tab button chaining direction** — 2026-04-18. Corrected to stock right-to-left pattern (`right`→`left`); separator anchoring updated to match.
- **Tab separator visual** — 2026-04-18. Left/right caps use stock double-anchor stretch pattern from `ea_settingswindowtabbed.xml`; second anchor set in Lua after buttons are created.
- **UnitFrames never restores BattlegroupHUD callbacks** — fixed 2026-04-17.
- **UnitFrames event handlers leaked on re-init** — fixed 2026-04-17.
- **Component handler failures swallowed without diagnostics** — fixed 2026-04-17.
- **TargetHUDController anonymous closure event handlers** — fixed 2026-04-17.
- **UnitFrames library files misfiled under `Shared/`** — fixed 2026-04-17.
- **Dead `SettingsWindow.xml` files removed** — 2026-04-17.
- **Dev-only files trimmed** — 2026-04-17.
- **README documentation refreshed** — 2026-04-17.
- **PlayerPetWindow stock reappearance** — fixed 2026-04-16 (historical).
