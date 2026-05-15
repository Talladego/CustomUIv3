# CustomUI Code Quality Backlog

**Last updated:** 2026-05-05 — BuffTracker + stock takeover optimization complete. Open items: Medium **#11** (GroupWindow test harness), UnitFrames hook lifecycle move, SCT doc cleanup.

**See also:** [plan.md](plan.md) for execution steps, [review.md](review.md) for detailed audit findings.

## Still open (summary)

## Consolidated from auxiliary Markdown

**Policy:** Actionable follow-ups that previously appeared only in [plan.md](plan.md), [review.md](review.md), [Source/Components/UnitFrames/plan.md](Source/Components/UnitFrames/plan.md), [Source/Components/PlayerStatusWindow/plan.md](Source/Components/PlayerStatusWindow/plan.md), [Source/Components/SCT/plan.md](Source/Components/SCT/plan.md), or [Source/Components/SCT/review.md](Source/Components/SCT/review.md) are summarized **here**. Those files retain **design narrative / regression checklists**; this section is the single **issue index** for cross-doc items.

| Source | What moved here |
|--------|------------------|
| [plan.md](plan.md) §Performance / Phase 3 | P2 smoke test; steps 11–15 status |
| [UnitFrames/plan.md](Source/Components/UnitFrames/plan.md) | BattlegroupHUD hook lifecycle |
| [PlayerStatusWindow/plan.md](Source/Components/PlayerStatusWindow/plan.md) | Pet hook — **resolved** in code (issues High **#1**–**#2**); plan kept for checklist |
| [Source/Components/SCT/review.md](Source/Components/SCT/review.md) | Doc drift (pcall claims, file sizes) |
| [review.md](review.md) (2026-05-02) | Residual items aligned with §Validation gaps / optional anchor audit |

### Performance & smoke ([plan.md](plan.md) §Performance)

- **P2 (pending in-game):** After BuffTracker P1, smoke-test all trackers (PlayerStatus, TargetWindow, TargetHUD, GroupWindow ×5, alignment, compression, blacklist/whitelist).
- **P3:** GroupIcons — outsiders **attach** (`AttachWindowToWorldObject`); probe-only staleness on interval; no per-frame `Move` on icon windows ([GroupIconsController.lua](Source/Components/GroupIcons/Controller/GroupIconsController.lua)).

### Phase 3 verification table ([plan.md](plan.md))

| Step | Topic | Status |
|------|--------|--------|
| 11 | SCT heal / `"Heal"` key | **Done** — issues High **#4**; optional scenario pass |
| 12 | Root `OnUpdate` / disabled | **Done** — Medium **#13** |
| 13 | GroupIcons FIFO vs active target | **Done** — Low **#18** |
| 14 | UnitFrames stub modules | **Done** — Low **#17** |
| 15 | GroupWindow test harness / manifest | **Open** — Medium **#11** |

### UnitFrames — BattlegroupHUD opacity hooks ([UnitFrames/plan.md](Source/Components/UnitFrames/plan.md))

- **Open:** Move hook install from `Initialize` into **`Enable`** and restore in **`Disable`** so stock `BattlegroupHUD` is untouched while UnitFrames is disabled (idempotent guards per plan).

### SCT — documentation / structure ([Source/Components/SCT/review.md](Source/Components/SCT/review.md))

- **Open (doc cleanup):** Reconcile `implementation.md` pcall claims with code; file-size vs plan targets; optional § load-order note in SCT `plan.md`.
- **In-game verify:** Same rows as [issues.md](issues.md) §**SCT component** (EventTracker expiry, combat tables at load, nil color fallback).

### Review audit residual ([review.md](review.md))

- Matches §**Validation gaps** below (regression harness, hook reload smoke, reset fault-injection).
- **Optional:** Per-tab settings XML anchor audit ([README.md](README.md) §Notes).

### CustomUISettingsWindow

- Developer layout pitfalls only — [CustomUISettingsWindow/README.md](CustomUISettingsWindow/README.md); no separate numbered backlog.

## Audit summary (2026-05-02, via review.md)

- Architecture remains sound: namespaced `CustomUI.*`, Controller/View split, manifest-only `.mod`, `EnsureRootWindowInstances`, shared BuffTracker/TargetFrame.
- **Lifecycle:** Player pet hook now uses `pcall` + `Enable`/`Disable`; PlayerStatus, TargetWindow, TargetHUD, GroupWindow attach/detach `WindowRegisterEventHandler` only while enabled (GroupIcons / UnitFrames already patterned).
- **Guards:** Common PlayerStatus view / pet paths now guard `GameData` / `GameData.Player`.
- Settings: `RefreshSctControls` now wraps the `SetupRow` loop in `pcall` and always clears `m_refreshing` (same file); smaller sync helpers (e.g. throttle sliders) still toggle `m_refreshing` without `pcall` — low risk.
- Static review only (review.md); items marked “verify against v2” need file-level confirmation in-game where noted.

## Performance & memory (2026-05-04)

Static review of hot paths (`OnUpdate`, BuffTracker, GroupIcons outsiders, SCT trackers). BuffTracker with sort: **not** per-frame full layout — timer labels every frame, full `OnBuffsChanged` on ~10 Hz throttle and on duration-category transitions, with reused scratch tables for filter maps (see **Medium #20** resolved). GroupIcons outsider rings **attach** to the world object; only the **probe** is moved on an interval to drop stale tracks (**Medium #21** / [plan.md](plan.md) P3). SCT `EventTrackers` is hard-capped with LRU eviction (**Medium #24**, 2026-05-04). BuffTracker throttle work still scales with **many simultaneous trackers** on player + targets + HUD + group rows.

| Area | Issue | Primary files |
|------|--------|----------------|
| BuffTracker | ~~Sort-on path fired full layout every frame~~ — **fixed:** throttle (~10 Hz) + immediate relayout when short/long/permanent category changes vs last layout; `postFilter` / `inResult` reused; `CompressBuffData` still allocates per resort. | [BuffTracker.lua](Source/Shared/BuffTracker/BuffTracker.lua) (`Update`, `OnBuffsChanged`) |
| Amplification | Same pattern on PlayerStatus, TargetWindow, TargetHUD (`ApplyPlayerStatusRules` + sort override), GroupWindow (**five** member trackers). | Controllers using `BuffTracker` |
| GroupIcons | Outsider rings: **`AttachWindowToWorldObject`** (engine-follow). Staleness: **`ValidateTrackedOutsidersProbeOnly`** — probe-only `MoveWindowToWorldObject` on **`c_OUTSIDER_PROBE_INTERVAL`**; no per-frame `Move` on icon windows. | [GroupIconsController.lua](Source/Components/GroupIcons/Controller/GroupIconsController.lua) |
| UnitFrames | ~~`SyncMouseOverBorderFromGlobalHover` every frame~~ — **fixed:** skipped when no custom group window is visible **and** there is no active hover member to clear; mode `"none"` clears hover tracking (Medium **#22**, 2026-05-04). | [UnitFramesController.lua](Source/Components/UnitFrames/Controller/UnitFramesController.lua) |
| Target UI | ~~Residual `OnUpdate` buff ticks while disabled~~ — **fixed:** `CustomUI.TargetWindow.OnUpdate` / `TargetWindow.Update` bail on `not m_enabled`; TargetHUD already guarded; handlers unregister on **Disable**; **#13** `SafeUserHide` + `WindowSetShowing` (Medium **#23**, 2026-05-04). | [TargetWindowController.lua](Source/Components/TargetWindow/Controller/TargetWindowController.lua), [TargetHUDController.lua](Source/Components/TargetHUD/Controller/TargetHUDController.lua) |
| SCT | ~~`EventTrackers` unbounded growth~~ — **fixed:** `c_EVENT_TRACKERS_MAX` + touch-order LRU; evict quiescent trackers first, then oldest-touch (**Medium #24**, 2026-05-04). Idle timeout (`c_TRACKER_IDLE_EVICT_TIME`) unchanged. Per-tracker throttle; icon LRU ([SCTAbilityIconCache.lua](Source/Components/SCT/Controller/SCTAbilityIconCache.lua)). | [SCTHandlers.lua](Source/Components/SCT/Controller/SCTHandlers.lua), [SCTOverrides.lua](Source/Components/SCT/Controller/SCTOverrides.lua) |

Medium performance backlog **#24** resolved (**#6**–**#8**, **#13**, **#20**–**#23**). Residual design: [plan.md](plan.md) §Performance & memory for optional tuning only.

## Component pattern verification (2026-04-18) — **resolved 2026-04-23**

- Controllers may still use `CreateWindowFromTemplate` for sub-widgets (e.g. target frames) as before.
- **Manifest-only `.mod`:** `<CreateWindow>` was removed from `CustomUI.mod`. Top-level window instances are created at the first step of `CustomUI.Initialize` via `EnsureRootWindowInstances()` in [Source/CustomUI.lua](Source/CustomUI.lua) (`CreateWindow(name, false)` for each root name, matching the old mod list, plus `CustomUISCTWindow`). This runs in the same `OnInitialize` order as the former pre-creates (after all `<File>` loads, before `InitializeComponents`) so **disabled** components that never run `Initialize()` still have instances for layout/saved settings. See [README.md](README.md) (Window creation pattern).
- Rationale: `InitializeComponents()` only calls `EnableComponent` → `Initialize` for **enabled** components; roots must exist regardless.

## Medium severity

6. ~~**Hot-path `GetSettings()` in SCT (verify v2)**~~ — **Resolved (2026-05-04)**  
   - [SCTSettings.lua](Source/Components/SCT/Controller/SCTSettings.lua): full `Settings()` normalize/migrate runs only while dirty; `notifyChange()` clears the flag, runs `ApplyMode()`, then `Settings()` once to refresh cache. Hot paths (`GetSettings`, `CombatType*Enabled`, getters) return the live table with **O(1)** reuse when clean. **`CustomUI.SCT.InvalidateSettingsNormalization()`** if something mutates `CustomUI.Settings.SCT` outside setters.

7. ~~**UnitFrames visibility polling**~~ — **Resolved (2026-05-04)**  
   - Removed `m_visibilityPollElapsed` / `c_VISIBILITY_POLL_INTERVAL`: `ApplyModeVisibility()` now ends with `RefreshTargetBorders()` + `RefreshMouseOverBorders()` after every layout pass; `Update()` only runs scenario distance polling + `SyncMouseOverBorderFromGlobalHover`. Registered `SCENARIO_GROUP_UPDATED`, `SCENARIO_PLAYERS_LIST_UPDATED`, `LOADING_END`, `PLAYER_ZONE_CHANGED`, `ENTER_WORLD` → `OnVisibilityStateChanged` for flag/roster lag vs group events; `OnWarbandMemberUpdated` refreshes borders after partial warband redraw.

8. ~~**Unused fields on `CustomUI.PlayerStatusWindow.Settings`**~~ — **Resolved (2026-05-04)**  
    - `CustomUI.PlayerStatusWindow.GetSettings()` clears legacy **`alwaysShowHitPoints`** / **`alwaysShowAPPoints`** from persisted `CustomUI.Settings.PlayerStatusWindow` if present (never wired; UI had no controls) ([PlayerStatusWindowController.lua](Source/Components/PlayerStatusWindow/Controller/PlayerStatusWindowController.lua)).

9. ~~**Duplicate buff-filter defaults / key lists**~~ — **Resolved (2026-05-04)**  
    - [BuffFilterDefaults.lua](Source/Shared/BuffTracker/BuffFilterDefaults.lua) defines **`CustomUI.BuffTracker.FilterDefaults`** and **`FilterSettingKeys`** (ordered merge keys). PlayerStatus, TargetWindow, TargetHUD, and GroupWindow **`GetSettings`** iterate **`FilterSettingKeys`** — no per-controller **`BUFF_FILTER_KEYS`** / **`BUFF_FILTER_DEFAULTS`** aliases.

10. ~~**`m_refreshing` in SCT settings tab — `RefreshSctControls` throws**~~ — **Resolved (2026-05-04)**  
    - `RefreshSctControls` uses `pcall` around the full `SetupRow` loop and **always** clears `m_refreshing`, logging on failure ([CustomUISettingsWindowTabSCT.lua](CustomUISettingsWindow/source/CustomUISettingsWindowTabSCT.lua)).  
    - Optional residual: narrow helpers like `SyncMessageThrottleSliders` still set `m_refreshing` without `pcall` — acceptable unless those calls start throwing.

11. **Group window test harness — keep until GroupWindow is complete**  
   - [GroupWindowTestHarness.lua](Source/Components/GroupWindow/Controller/GroupWindowTestHarness.lua) stays in-tree for now (`gwharness` slash via [CustomUI.lua](Source/CustomUI.lua)); default **off**; real group data paths unchanged when disabled.  
   - **When GroupWindow is feature-complete:** remove harness file(s) from [CustomUI.mod](CustomUI.mod) / slash dispatch and delete or archive the harness module.

12. ~~**`BeginLoading` / SCT — stale trackers across UI reload**~~ — **Resolved (2026-05-04)**  
   - `CustomUI.SCT.OnLoadingBegin` calls `DestroyAllTrackers()` and resets the incoming fan lane counter ([SCTHandlers.lua](Source/Components/SCT/Controller/SCTHandlers.lua)).

13. ~~**Root `OnUpdate` handlers while component disabled**~~ — **Resolved (2026-05-04)**  
   - UnitFrames, GroupIcons driver, SCT window already hid tick roots on disable. **Gap closed:** `PlayerStatusWindow`, `GroupWindow`, `PlayerPetWindow` now call `WindowSetShowing(..., false)` after `LayoutEditor.UserHide` on `Disable`; `TargetWindow` `SafeUserHide` always applies `WindowSetShowing(..., false)` when the window exists (layout-editor hide alone is not relied on for stopping ticks); `TargetHUD.OnUpdate` returns immediately when `m_enabled` is false ([PlayerStatusWindowController.lua](Source/Components/PlayerStatusWindow/Controller/PlayerStatusWindowController.lua), [GroupWindowController.lua](Source/Components/GroupWindow/Controller/GroupWindowController.lua), [PlayerPetWindowController.lua](Source/Components/PlayerStatusWindow/Controller/PlayerPetWindowController.lua), [TargetWindowController.lua](Source/Components/TargetWindow/Controller/TargetWindowController.lua), [TargetHUDController.lua](Source/Components/TargetHUD/Controller/TargetHUDController.lua)).

20. ~~**BuffTracker: full `OnBuffsChanged` every frame when sort mode is on**~~ — **Resolved (2026-05-04)**  
    - [BuffTracker.lua](Source/Shared/BuffTracker/BuffTracker.lua): `Update` ticks durations and refreshes timer labels every frame; full layout on **throttled** interval (~10 Hz) for intra-bucket duration reordering, **plus** immediate layout when a timed buff’s duration category (short / long / permanent vs `m_durationThreshold`) changes vs the snapshot taken at the last `OnBuffsChanged` (`_layoutDurCat`). Config/data paths still call `OnBuffsChanged` directly. `postFilter` and `inResult` are cleared and reused to reduce allocations per resort.

21. ~~**GroupIcons: outsider world follow cost per frame**~~ — **Resolved / revised (2026-05-04, 2026-05-05)**  
    - **History:** ~20 Hz throttle → choppy; full-rate probe + **`Move` on icons** → smoother but wasteful.  
    - **Current:** Outsider **`GroupIcon`** uses **`AttachWindowToWorldObject`** like roster. **`ValidateTrackedOutsidersProbeOnly`** runs on **`c_OUTSIDER_PROBE_INTERVAL`** (`MoveWindowToWorldObject` **probe only**) to untrack dead/unloaded wids ([GroupIconsController.lua](Source/Components/GroupIcons/Controller/GroupIconsController.lua)).

22. ~~**UnitFrames: hover border sync every frame**~~ — **Resolved (2026-05-04)**  
    - `UnitFrames.Update` calls `SyncMouseOverBorderFromGlobalHover` only when **some custom group window** is engine-visible (`WindowGetShowing`) **or** `m_mouseOverMemberWindow ~= nil` (clear stale border after roster hides). Display mode `"none"` resets hover tracking so idle skips cannot strand state ([UnitFramesController.lua](Source/Components/UnitFrames/Controller/UnitFramesController.lua)).

23. ~~**TargetWindow / TargetHUD: residual tick/work while disabled**~~ — **Resolved (2026-05-04)**  
    - Handlers **unregister on Disable**; hide paths per Medium **#13** (`SafeUserHide` + `WindowSetShowing`); **`CustomUI.TargetWindow.OnUpdate` and `CustomUI.TargetWindow.Update`** now return immediately when `not m_enabled` so BuffTracker `Update` cannot run from XML ticks while the component is off (both target windows inherit the same `OnUpdate`). **`CustomUI.TargetHUD.OnUpdate`** already guarded `m_enabled` ([TargetWindowController.lua](Source/Components/TargetWindow/Controller/TargetWindowController.lua), [TargetHUDController.lua](Source/Components/TargetHUD/Controller/TargetHUDController.lua)).

24. ~~**SCT: `EventTrackers` map growth**~~ — **Resolved (2026-05-04)**  

25. ~~**Stock UI handlers still running while stock windows are hidden (takeover unhooking).**~~  
   **Resolved (2026-05-05).**
   - When CustomUI replaces stock Player/Target/Group windows it hides stock via `LayoutEditor.UserHide`, but stock `WindowRegisterEventHandler` / `RegisterEventHandler` callbacks can still run while hidden, duplicating buff/target/group work.
   - **Fix:** CustomUI replacement components now unhook stock handlers on `Enable` and restore them on `Disable`:
     - `TargetWindow`: unhooks stock handlers registered on `TargetWindow` (`ea_targetwindow`) and re-registers on disable.
     - `PlayerStatusWindow`: unhooks stock `PlayerWindow` handler registrations and re-registers on disable.
     - `GroupWindow`: unhooks stock global `GroupWindow.*` event handlers (registered via `RegisterEventHandler`) and restores on disable.
   - See [plan.md](plan.md) §**Phase 2b — Stock component takeover** for the lifecycle contract.

26. ~~**Toggling stock ↔ CustomUI can strand stale buff state (Player/Target/Group).**~~  
   **Resolved (2026-05-05).**
   - Stress case: flipping ownership mid-combat can leave the non-owning side’s BuffTracker stale (0s timers, missing bars) because it missed effects updates while unhooked.
   - **Fix:** On takeover/handback, each replacement forces a resync:
     - `PlayerStatusWindow`: clear/hide stock buffs on CUI enable; refresh CUI buffs on enable; clear CUI on disable; refresh stock buffs + HP/AP on disable.
     - `TargetWindow`: refresh CUI buff trackers on enable; clear them on disable; call stock `TargetWindow.UpdateTarget(...)` after rehook/show.
     - `GroupWindow`: refresh CUI member trackers on enable; clear them on disable; call stock `GroupWindow.OnGroupUpdated()` after rehook/show.
    - `getOrCreateTracker` calls `enforceMaxEventTrackers` after each new tracker; **`c_EVENT_TRACKERS_MAX`** (72) with **`_sctTouchSeq`** updated on create + `markTrackerActive`. Eviction prefers **quiescent** trackers (empty displayed/pending/throttle queue), then oldest-touch among all; never drops the storage key being created ([SCTHandlers.lua](Source/Components/SCT/Controller/SCTHandlers.lua)).

## Low severity

14. ~~**BuffTracker / `pairs()` where order might matter**~~ — **Resolved (2026-05-05)**  
    - [`BuffTracker.lua`](Source/Shared/BuffTracker/BuffTracker.lua): **`_sortedMapKeys`** + sorted iteration over **`m_buffData`**, **`rawBuffData`**, **`postFilter`/`postCompress` paths**, whitelist warn pass, **`CopyBuffData`**, **`Refresh`/`UpdateBuffs`** merges, and scratch **`inResult`** clear.

15. ~~**Near-duplicate Blacklist/Whitelist**~~ — **Resolved (2026-05-05)**  
    - Single mod file [**`BuffLists.lua`**](Source/Shared/BuffTracker/BuffLists.lua) defines **`DefaultBlacklist`**, **`DefaultWhitelist`**, **`DefaultWhitelistAbility`**; removed **`Blacklist.lua`** / **`Whitelist.lua`** ([`CustomUI.mod`](CustomUI.mod)).

16. ~~**SCT diagnostic logging when `d` is absent**~~ — **Resolved (2026-05-05)**  
    - [`CustomUI.lua`](Source/CustomUI.lua): **`CustomUI.GetClientDebugLog()`** (`rawget(_G, "d")`) and **`CustomUI.SCTLog(msg)`** — when **`CustomUI.DebugLogging`** and no client **`d`**, falls back to **`LogLuaMessage(..., SystemData.UiLogFilters.DEBUG, ...)`** so **`uilog.log`** still receives traces (README updated).

17. ~~**UnitFrames `Model` / `Renderer` / `Adapters` stubs**~~ — **Resolved (2026-05-04)**  
    - Removed unused modules from [CustomUI.mod](CustomUI.mod); deleted `UnitFramesModel.lua`, `UnitFramesRenderer.lua`, `Adapters/WarbandAdapter.lua`, `Adapters/ScenarioFloatingAdapter.lua`. [UnitFramesController.lua](Source/Components/UnitFrames/Controller/UnitFramesController.lua) + [README.md](README.md) reference only **`UnitFramesEvents`** alongside the controller.

18. ~~**GroupIcons FIFO outsider cap (48)**~~ — **Resolved (2026-05-04)**  
    - When the pool is full, eviction walks FIFO oldest-first and **skips** world entity ids for non-empty **enemy player** / **ally player** slots in `TargetInfo` (`HOSTILE_TARGET`, `FRIENDLY_TARGET`) so your active target’s ring is not the first evicted when many strangers stream past ([GroupIconsController.lua](Source/Components/GroupIcons/Controller/GroupIconsController.lua)). Fallback evicts oldest if no candidate (should not occur with ≤2 protected ids).

19. ~~**Comments / headers referencing removed monolithic SCT**~~ — **Resolved (2026-05-04)**  
    - [issues.md](issues.md), [plan.md](plan.md), [review.md](review.md) point audits at [`SCTOverrides.lua`](Source/Components/SCT/Controller/SCTOverrides.lua) / [`SCTHandlers.lua`](Source/Components/SCT/Controller/SCTHandlers.lua) only. SCT controller Lua had no stale filename references.

## Resolved (since last sweep)

- **Manifest `<CreateWindow>` / component pattern** — 2026-04-23. Pre-creates moved from [CustomUI.mod](CustomUI.mod) to `EnsureRootWindowInstances()` in [Source/CustomUI.lua](Source/CustomUI.lua); `OnInitialize` now only calls `CustomUI.Initialize`.  
- **Legacy in-addon settings UI removed** — 2026-04-26. Deleted `Source/Settings/`, component `View/*Tab.xml` files, `CustomUI.<Name>.Tab` controller blocks, and `Source/Shared/BuffFilterSection.lua`; shipped settings live in [CustomUISettingsWindow](CustomUISettingsWindow/).  
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
- **SCT: `OnLoadingBegin` tears down all trackers** — 2026-05-04. Avoids stale floating text across loads; resets `_incomingFanLaneIndex`.
- **SCT settings: `RefreshSctControls` `pcall` + guaranteed `m_refreshing` clear** — 2026-05-04 ([CustomUISettingsWindowTabSCT.lua](CustomUISettingsWindow/source/CustomUISettingsWindowTabSCT.lua)).
- **SCT: signed hit/crit amounts (heal vs damage) documented + invalid amounts ignored** — 2026-05-04 ([SCTHandlers.lua](Source/Components/SCT/Controller/SCTHandlers.lua), [SCTOverrides.lua](Source/Components/SCT/Controller/SCTOverrides.lua)); aligns **`Heal`** row with positive amounts only.
- **BuffTracker: sort-on resort churn** — 2026-05-04 ([BuffTracker.lua](Source/Shared/BuffTracker/BuffTracker.lua)). Throttled full layout + duration-category dirty relayout + reused `postFilter`/`inResult` scratch tables (Medium **#20**).
- **UnitFrames: periodic visibility poll removed** — 2026-05-04 ([UnitFramesController.lua](Source/Components/UnitFrames/Controller/UnitFramesController.lua)). Event-driven `ApplyModeVisibility` + border refresh; extra hooks for scenario list/group + zone/load/world (Medium **#7**).
- **SCT: `GetSettings` / `Settings()` normalization cache** — 2026-05-04 ([SCTSettings.lua](Source/Components/SCT/Controller/SCTSettings.lua)). Dirty on `notifyChange`; optional `InvalidateSettingsNormalization` for rare external edits (Medium **#6**).
- **Root `OnUpdate` / disabled components** — 2026-05-04. Explicit `WindowSetShowing(..., false)` on disable for PlayerStatus, GroupWindow, PlayerPet; `TargetWindow.SafeUserHide` always hides the window when it exists; `TargetHUD.OnUpdate` guards `m_enabled` (Medium **#13**).
- **UnitFrames: idle skip for global hover sync** — 2026-05-04. `SyncMouseOverBorderFromGlobalHover` gated on visible group containers or pending hover clear; mode `"none"` clears hover cache (Medium **#22**).
- **TargetWindow/TargetHUD: no BuffTracker `Update` while disabled** — 2026-05-04. `TargetWindow.OnUpdate`/`TargetWindow.Update` early-return when `not m_enabled`; complements handler unregister + **#13** hide paths (Medium **#23**).
- **PlayerStatusWindow: legacy unused settings keys removed from persisted table** — 2026-05-04. `GetSettings` nils `alwaysShowHitPoints` / `alwaysShowAPPoints` (Medium **#8**).
- **GroupIcons: outsider follow** — 2026-05-04 / **2026-05-05**. **Attach** for motion; probe-only interval for staleness (**Medium #21**).
- **SCT: `EventTrackers` hard cap + LRU eviction** — 2026-05-04. `c_EVENT_TRACKERS_MAX`, `_sctTouchSeq`, quiescent-first eviction (Medium **#24**).
- **Buff filter schema: `FilterSettingKeys` + shared defaults** — 2026-05-04. Controllers use `CustomUI.BuffTracker.FilterSettingKeys` / `FilterDefaults` only (Medium **#9**).
- **UnitFrames: removed unused Model / Renderer / WarbandAdapter / ScenarioFloatingAdapter** — 2026-05-04 (Low **#17**).
- **GroupIcons: outsider FIFO eviction skips active player targets** — 2026-05-04. `BuildActiveTargetEntityIdGuard` + `PickOutsiderFifoEvictionVictim` (Low **#18**).
- **Docs: SCT audit pointers** — 2026-05-04. Root `issues` / `plan` / `review` cite v2 SCT only (Low **#19**).
- **BuffTracker: deterministic map iteration** — 2026-05-05. `_sortedMapKeys` on merge/filter passes (Low **#14**).
- **Buff lists module** — 2026-05-05. [`BuffLists.lua`](Source/Shared/BuffTracker/BuffLists.lua) replaces separate blacklist/whitelist files (Low **#15**).
- **`CustomUI.GetClientDebugLog` / `CustomUI.SCTLog`** — 2026-05-05. README + `uilog.log` fallback when client `d` absent (Low **#16**).
