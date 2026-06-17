# CustomUI Refactor Plan

## Goal

Reduce the largest controller/shared files without changing runtime behavior, saved settings, slash commands, XML event targets, or component lifecycle semantics. Each refactor should be small enough to smoke in-game before the next slice.

This plan is subordinate to the architecture rules in `README.md` and `.cursor/rules/customui.mdc`: controllers own lifecycle, hooks, and `RegisterComponent`; view helpers stay presentation-only; settings UI remains in the separate `CustomUISettingsWindow` addon.

## Status

As of 2026-05-26, the code-moving slices in this plan are implemented in the shipped repo:

- Phase 1 complete: `GroupIconsSpatialProbe.lua`, `GroupIconsOutsiderTracker.lua`, and `GroupIconsRoster.lua` are in `CustomUI.mod`, with `GroupIconsController.lua` acting as lifecycle/event coordinator.
- Phase 2 complete: `UnitFramesArchetypes.lua`, `UnitFramesSort.lua`, `UnitFramesRoster.lua`, `UnitFramesScenario.lua`, and `UnitFramesWarband.lua` now own the extracted data/sort paths; the controller stays focused on visibility, routing, and window updates.
- Phase 3 complete: `BuffTrackerLayout.lua`, `BuffTrackerRules.lua`, and `BuffTrackerGrouping.lua` are shipped and wired before `BuffTracker.lua`.
- Phase 4 complete: `SCTAbilityIconResolver.lua`, `SCTEventEntry.lua`, and `SCTEventTracker.lua` are shipped; `SCTOverrides.lua` now keeps only shared scaffold/constants/anchor helpers.

Remaining work is no longer large-slice controller decomposition. Any follow-up work is narrow and optional, or requires runtime validation, and is tracked in `TODO.md`.

## Refactor Rules

1. Keep behavior-preserving moves separate from behavior changes.
2. Preserve public names already called by XML, settings tabs, slash commands, hooks, or other components.
3. Load helper modules before the controller that consumes them in `CustomUI.mod`.
4. Prefer local module tables under the owning namespace, for example `CustomUI.GroupIcons.SpatialProbe`, over new globals.
5. Do not expose controller internals just to make extraction easier. If a helper needs many mutable controller locals, split a smaller concern first.
6. After each slice, smoke enable/disable, `/reloadui`, relevant target/group events, and the settings tab that touches the feature.

## Phase 1: GroupIcons (Completed)

**Current file:** `Source/Components/GroupIcons/Controller/GroupIconsController.lua`

This is the best first target because the current responsibilities are already distinct: roster markers, outsider tracking, and the world-object probe. Keep `GroupIconsController.lua` as the event/lifecycle coordinator.

### 1A. Extract Spatial Probe

Create `Source/Components/GroupIcons/Controller/GroupIconsSpatialProbe.lua`.

Owns:
- `CalibrateGroupIconsWorldProbeAnchors`
- `GetWorldProbeCalibration`
- `WorldObjectSpatialProbeIsGone`
- probe-window movement and anchor interpretation

API shape:
- `CustomUI.GroupIcons.SpatialProbe.GetCalibration()`
- `CustomUI.GroupIcons.SpatialProbe.IsGone(worldObjNum, calibration)`

Validation:
- Roster icons hide when world objects unload.
- Outsider rings untrack dead/off-screen entities.
- No per-frame movement is introduced for icon windows.

### 1B. Extract Outsider Tracker

Create `Source/Components/GroupIcons/Controller/GroupIconsOutsiderTracker.lua`.

Owns:
- tracked outsider map and FIFO order
- protected target eviction guard
- `TryTrackOutsider`, `UntrackOutsiderWid`, `UntrackAllOutsiders`
- target classification queue consumption

Leave ring drawing through the existing `GroupIcon` object until a later pass. The first extraction should not redesign rendering.

Validation:
- Hostile and friendly outsiders attach after target updates.
- Current hostile/friendly targets are not evicted before lower-priority outsiders.
- Group members are pruned from outsider tracking.

### 1C. Extract Roster Refresh

Create `Source/Components/GroupIcons/Controller/GroupIconsRoster.lua`.

Owns:
- party/warband/scenario roster refresh
- group membership cache
- sticky/live world object ID handling
- `RefreshParty`, `RefreshWarband`, and scenario roster helpers

Controller keeps:
- `Initialize`, `Enable`, `Disable`, `Shutdown`
- engine event handlers
- `OnUpdate` pacing and routing
- settings change entrypoint

Validation:
- Party-only, warband, and scenario toggles still select the right roster path.
- Self is never shown.
- Sticky IDs are learned but not used alone for attachment.

## Phase 2: UnitFrames (Completed)

**Current file:** `Source/Components/UnitFrames/Controller/UnitFramesController.lua`

Do not split data, sort, and rendering in one pass. The controller mixes event lifecycle, stock-window parity, scenario data merging, and UI writes; a broad extraction would be hard to verify.

### 2A. Consolidate Effective Archetype Logic

Create `Source/Components/UnitFrames/Controller/UnitFramesArchetypes.lua` only if the helpers cannot reasonably live in `Source/Shared/Archetypes.lua`.

Owns:
- normalized name lookup used for scoreboard/scenario archetype overrides
- scoreboard archetype index mapping
- effective archetype resolution used by HP tint, career ring tint, and role sorting

Keep the base career mapping and RGB palette in `CustomUI.Archetypes`.

Validation:
- Career ring tint, HP bar tint, and role sort agree for the same player.
- Scenario `experiencebonus` archetype override still works.
- Warband `RoRGroupScoreboard.playersDataRaw` override still works.

### 2B. Extract Sorting

Create `Source/Components/UnitFrames/Controller/UnitFramesSort.lua`.

Owns:
- `SortMembersForUnitFramesDisplay`
- bucket ranking and alphabetical/rank tie-breaks
- no direct window calls

API shape:
- `CustomUI.UnitFrames.Sort.MembersForDisplay(members)`

Validation:
- Party role sorting on/off preserves current display order behavior.
- Nil/unknown career rows still sort deterministically.

### 2C. Split Scenario and Warband Data Paths

Only after 2A and 2B are stable, consider:
- `UnitFramesScenario.lua` for `GameData.GetScenarioPlayerGroups`, scenario hit merging, self row, and map distance cache.
- `UnitFramesWarband.lua` for `PartyUtils`, `GetBattlegroupMemberData`, party-only rows, and warband party index resolution.

Controller keeps stock visibility handoff, tick-window visibility, layout registration, hooks, and event routing.

Validation:
- Idle mode restores stock windows.
- Scenario groups and open-world warband do not leak stale rows across mode changes.
- Distance cache clears keys not seen in the current scan.

## Phase 3: BuffTracker (Completed)

**Current file:** `Source/Shared/BuffTracker/BuffTracker.lua`

Avoid extracting memory pooling by itself. The pool is an implementation detail and should stay close to the code that owns table lifetimes unless a larger internal module can preserve that ownership cleanly.

Preferred slices:
- `BuffTrackerRules.lua`: category/duration filtering, whitelist/blacklist checks, group lookup, compression helpers.
- `BuffTrackerLayout.lua`: container dimensions, alignment, slot anchoring, scale, visibility, hit area.
- Keep `BuffFrame` widget behavior and tracker lifecycle in `BuffTracker.lua` until the rule/layout split is stable.

Validation:
- PlayerStatus, TargetWindow, TargetHUD, and GroupWindow trackers all render.
- Compression sums stacks across casters.
- Removal grace period still prevents stack flicker.
- Blacklist/whitelist/default filter behavior is unchanged.

## Phase 4: SCT (Completed)

**Current file:** `Source/Components/SCT/Controller/SCTOverrides.lua`

The current file is not just hardcoded override data. It includes anchor management, ability icon resolution, event entry classes, point-gain entries, and event trackers. Split by runtime responsibility, not by a presumed data/logic boundary.

Preferred slices:
- `SCTAbilityIconResolver.lua`: buff-list icon scan, equipment proc fallback, ability-data probing, and resolve logging. It should continue to use `SCTAbilityIconCache.lua`.
- `SCTEventEntry.lua`: `CustomUI.SCT.EventEntry` and `PointGainEntry` creation, setup, update, destroy, icon/suffix positioning.
- `SCTEventTracker.lua`: tracker creation, animation data initialization, update, expiry, and destroy.
- Leave global hook/override installation in `SCTOverrides.lua` or `SCTHandlers.lua` depending on ownership.

Validation:
- Incoming/outgoing damage and heals still render at the right anchors.
- Ability icons resolve from cache, buffs, player domains, and equipment fallbacks.
- Event trackers expire cleanly and destroy windows without leaks.
- Stock SCT handlers are restored on disable/shutdown.

## Manifest Order

When adding files, keep shared dependencies before components and helper files before consuming controllers. Example order for the first phase:

```xml
<File name="Source/Components/GroupIcons/Controller/GroupIconsSpatialProbe.lua" />
<File name="Source/Components/GroupIcons/Controller/GroupIconsOutsiderTracker.lua" />
<File name="Source/Components/GroupIcons/Controller/GroupIconsRoster.lua" />
<File name="Source/Components/GroupIcons/Controller/GroupIconsController.lua" />
<File name="Source/Components/GroupIcons/View/GroupIcons.xml" />
```

Do not add `<CreateWindow>` entries to `CustomUI.mod`, and do not re-include controller scripts from XML.

## Remaining Follow-ups

The remaining open items after this plan are intentionally narrower than the original phases:

- runtime validation for PlayerStatus minimal mode, shared target takeover, SCT tracker expiry, and broader component enable/disable handoff
- optional cleanup such as further shrinking `GroupIconsController.lua` / `CustomUI.lua`
- optional UnitFrames incremental improvements (for example, narrower scenario-row refreshes instead of whole-mode refreshes)

See `TODO.md` for the current backlog and validation checklist.

## Done Criteria

For each phase:

1. `CustomUI.mod` load order is updated.
2. Existing public entrypoints and XML handlers still exist.
3. No new settings UI is added inside CustomUI.
4. In-game smoke notes are added to `TODO.md` or the relevant issue section.
5. Any behavior change discovered during extraction is split into its own follow-up change.
