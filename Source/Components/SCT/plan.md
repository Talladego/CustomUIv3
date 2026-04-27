# CustomUI.SCT — Refactor Plan v2 (deviation-only model)

This plan replaces the v1 plan. v1 attempted a full reimplementation of stock event text and tried to match it pixel-for-pixel. That goal is not load-bearing and produced ~2000 lines of code we have to maintain forever. v2 takes the opposite stance: **stock is the baseline; we layer deviations on top and only when needed.**

---

## 1. Design thesis

Stock `EA_System_EventText` is the canonical implementation of floating combat text. It exists in the client. It is correct by definition for the "default" case.

The user-visible promise is:

> With every SCT setting at its default value, SCT is **bit-identical** to stock easystem_eventtext. When the user changes a setting in the SCT settings tab, that setting — and only that setting — overlays its delta on stock behavior.

The architectural consequence: at defaults, **CustomUI runs zero per-event code**. Stock handlers stay registered. CustomUI's tracker tables stay empty. CustomUI's OnUpdate is a no-op or unregistered. There is no "CustomUI pipeline that happens to look like stock" — at defaults, *the actual stock pipeline is what runs*.

When any setting deviates from default, CustomUI swaps in: it unregisters stock, registers CustomUI handlers, and runs its own pipeline that **inherits from stock classes** and **overrides only the methods that produce the deviation**. Any non-overridden behavior delegates to stock via `__index`.

---

## 2. Feasibility

Confirmed by reading `interface/default/easystem_eventtext/source/system_eventtext.lua` (520 lines):

| Question | Answer |
| :--- | :--- |
| Can stock and CustomUI handlers both be registered for the same engine event? | Yes engine-wise, but it would double-render. So the swap is binary: stock OR CustomUI, never both. |
| Can we leave stock registered and just modify what stock produces? | No. Filtering ("don't show heals") requires dropping the event before tracker dispatch — only achievable by replacing the handler. |
| Are stock's classes subclassable? | Yes. `EA_System_EventEntry`, `EA_System_PointGainEntry`, `EA_System_EventTracker` are global, `Frame`-based, and use `Subclass`/metatable patterns we already reuse today. |
| Is per-entry rendering centralized? | Yes. `:SetupText` (lines 106 and 194 in stock) is the single per-entry render entry point. Color, font, text, scale, dimensions are all set there. Override that one method and the deviations apply post-create-pre-display. |
| Is animation centralized? | Yes. `:Update` is a flat 20-line linear interpolator on `m_AnimationData`. Untouched at defaults; replaced for crit flair. |
| Does stock have crit-specific visuals (shake/pulse/flash) we'd need to disable? | No. Stock crits float like every other entry. Our crit flair is purely additive. |
| Does stock's tracker have anything we'd need to override beyond entry creation? | At defaults, no. For deviations, we only need to override the entry classes used in `:DispatchOne`. |

**Verdict: feasible.** The override surface is small: `EventEntry:SetupText`, `PointGainEntry:SetupText`, optionally `EventEntry:Update` (only when crit flair is enabled), and `Tracker:DispatchOne` (only when ability icons or crit holders are enabled).

---

## 3. What "default" means

The component has one master switch (CustomUI component framework: enabled/disabled). When enabled, the component always owns the SCT runtime so positioning uses the same holder-based path whether settings are default or customized. `IsAtDefault()` still describes whether the settings values are stock-equivalent, but it no longer controls handler ownership. Disable the SCT component to restore stock handlers. The settings and their default values:

| Setting | Default |
| :--- | :--- |
| `outgoing.filters.show*` (per combat type) | `true` for all 9 types |
| `incoming.filters.show*` | `true` for all 9 types |
| `outgoing.filters.showXP/showRenown/showInfluence` | `true` |
| `outgoing.size[*]` / `incoming.size[*]` | `1.0` for all keys |
| `outgoing.color[*]` / `incoming.color[*]` | `1` (engine default) |
| `customColor.outgoing[*]` / `customColor.incoming[*]` | `nil` |
| `offsets.outgoing.x` / `offsets.incoming.x` / `offsets.points.x` | `0` |
| `critAnimShake` / `critAnimPulse` / `critAnimFlash` | `false` |
| `critSizeScale` | `1.0` |
| `textFont` | `1` (Default = stock font) |
| `showAbilityIcon` | `false` |

`baseXOffset` is legacy saved-var compatibility only; active X offsets are per category.

CustomUI SCT branches on three categories — incoming combat, outgoing combat, and point gain (XP/RP/Inf). Per-category X offsets are absolute positions relative to the world-object anchor and are stored as:

```lua
v.offsets = v.offsets or {
    incoming = { x = 0 }, -- player-targeted combat
    outgoing = { x = 0 }, -- non-player-targeted combat
    points   = { x = 0 }, -- XP / Renown / Influence
}
```

The active keys are `incoming`, `outgoing`, and `points`; `IsAtDefault()` treats `x = 0` for all three categories as the default. The override seam is documented in §5.3.

`IsAtDefault()` returns `true` iff every value above matches its default. It is recomputed on every `Set*` call (cheap; ~30 comparisons) and cached for UI/reset state only.

---

## 4. Architecture: two runtime ownership modes

### 4.1 Mode P (Passthrough) — SCT component disabled

- Stock handlers stay registered.
- `CustomUISCTWindow` is hidden; OnUpdate not active.
- `CustomUI.SCT.Trackers` and `TrackersCrit` are empty.
- Zero per-event Lua executes from CustomUI.

### 4.2 Mode D (CustomUI runtime) — SCT component enabled

- Stock handlers unregistered (recorded in `_stockWasRegistered`).
- CustomUI handlers registered.
- `CustomUISCTWindow` shown; OnUpdate runs CustomUI tracker updates.
- Entry classes are `CustomUI.SCT.EventEntry` / `PointGainEntry`, which **inherit from stock** and override only the methods named below.

### 4.3 Mode transitions

`ApplyMode()` is the single function that reconciles runtime ownership with the component enabled state:

```
ApplyMode():
    if not IsComponentEnabled("SCT"):
        if currently in Mode D: switch to Mode P
        return
    if not currently in Mode D: switch to Mode D
```

Switching to Mode P:
1. Hide `CustomUISCTWindow`.
2. Unregister CustomUI handlers.
3. Re-register stock handlers (those `_stockWasRegistered` flagged true).
4. Destroy all CustomUI trackers.

Switching to Mode D:
1. Unregister stock handlers (record in `_stockWasRegistered`).
2. Register CustomUI handlers.
3. Show `CustomUISCTWindow`.

`ApplyMode()` is called from:
- Component `Enable` / `Disable` / `Shutdown`
- Every public setter (`SetSize`, `SetColorIndex`, `SetCritFlags`, ...) — settings changes can still happen while disabled/enabled, but only the component master switch controls stock vs CustomUI runtime.

Mid-combat transitions are safe: CustomUI's `:Destroy` already drains queues and detaches anchors; stock starts clean on its first event after restore.

---

## 5. Override surface (enabled SCT runtime)

When SCT is enabled, CustomUI's classes inherit from stock and override only what's needed:

```lua
CustomUI.SCT.EventEntry      = StockEventEntry:Subclass("CustomUI_Window_EventTextLabel")
CustomUI.SCT.PointGainEntry  = StockPointGainEntry:Subclass("CustomUI_Window_EventTextLabel")
CustomUI.SCT.EventTracker    = setmetatable({}, { __index = StockEventTracker })
CustomUI.SCT.EventTracker.__index = CustomUI.SCT.EventTracker
```

### 5.1 EventEntry overrides

| Method | When overridden | What we do |
| :--- | :--- | :--- |
| `:Create` | When SCT is enabled | Create a zero-size motion holder under the world-attached anchor, create the stock label under that holder, and center-anchor the label locally. |
| `:SetupText` | When SCT is enabled | Call `StockEventEntry.SetupText(self, ...)`. Then post-process: apply size scale, `critSizeScale` (multiplied with size for crits), color override (preset or custom RGB), font, ability-icon child, crit flair pre-state. |
| `:Update` | When SCT is enabled | Copy stock's animation math but move the holder, not the label. Run crit effects on the label visual layer. |
| `:Destroy` | Always | Stop animations, destroy icon child/sibling, label, and holder. |

#### 5.1.1 Holder-based scale isolation

The label template is `400×100` with `textalign="center"`. `WindowSetScale` pivots from the window's top-left, so scaling the same window that owns the world-object offset causes visible displacement. This is especially fragile when user offsets, point-gain spray offsets, crit motion, and per-row size sliders all combine.

The enabled CustomUI runtime therefore splits position from visuals:

```text
world-attached event anchor
  -> zero-size motion holder (`EA_Window_EventTextAnchor`)
      -> visible event label center-anchored to the holder
```

`EventEntry:Create` / `PointGainEntry:Create` create the holder under the world-attached anchor, create the stock label under that holder, and anchor the label `center` to holder `center` at local `0,0`.

`EventEntry:Update` / `PointGainEntry:Update` copy stock's animation math but write `WindowSetOffsetFromParent` to the holder, not the label. `m_AnimationData` remains the source of truth for stock spacing and lifetime checks. Size sliders and crit pulse call `WindowSetScale` on the label only, so no anchor-offset compensation is required for normal centered text.

When the ability icon is enabled, the icon is a sibling under the world-attached anchor and is anchored relative to the label. The label may switch to `textalign="left"` for the row layout, but base position is still owned by the holder.

### 5.2 PointGainEntry overrides

| Method | When overridden | What we do |
| :--- | :--- | :--- |
| `:Create` | When SCT is enabled | Same holder + center-anchored label model as `EventEntry`. |
| `:SetupText` | When SCT is enabled | Call `StockPointGainEntry.SetupText(self, ...)`. Then post-process: size scale, color override, font. (No icon, no crit.) |
| `:Update` / `:Destroy` | When SCT is enabled | Move/destroy the holder+label pair. |

### 5.3 EventTracker overrides

| Method | When overridden | What we do |
| :--- | :--- | :--- |
| `:InitializeAnimationData` | Always when SCT is enabled | Call stock to preserve Y/timing/fade defaults, then replace `start.x`, `target.x`, and `current.x` with the category X offset. Point-gain spray still adds to `target.x` later in `:Update`. The holder moves from this animation data; label scale stays local to the holder. |
| `:Create` | Always | Identical to stock, but use `CustomUI.SCT.EventEntry` / `PointGainEntry` for the entries it dispatches. |
| `:Destroy` | Never (stock already unparents and destroys cleanly) | Pure inheritance. |
| `:Update` | Never | Pure inheritance — same float math, same destroy timing. |

Crit holders (used by Shake/LaneMove) are an *additional* window inserted between anchor and label, only when crit flair is on. Implemented in `:DispatchOne` (which we override) or in `:SetupText` (preferred — no need to override DispatchOne if the holder is created lazily inside `:Create`).

### 5.4 Handler functions

Six handler functions (`OnCombatEvent`, `OnXpText`, `OnRenownText`, `OnInfluenceText`, `OnLoadingBegin`, `OnLoadingEnd`) replace the six stock handlers when SCT is enabled. They:

1. Apply filters (drop events if filtered).
2. Look up or create a `CustomUI.SCT.EventTracker`.
3. Forward to `tracker:AddEvent` (inherited from stock).

Filtering is the only logic in these handlers. Everything else delegates.

---

## 6. Module layout (target: ≤ 1000 lines total, down from ~2300)

```
Source/Components/SCT/
  Controller/
    SCTSettings.lua    (~450 ln)  Schema, defaults, IsAtDefault, public API.
    SCTOverrides.lua   (~300 ln)  EventEntry / PointGainEntry / EventTracker subclasses.
                                  All override methods live here. Stock delegation via __index.
    SCTHandlers.lua    (~120 ln)  Six handlers + Install/Restore + filter checks.
    SCTAnim.lua        (~120 ln)  Crit effect tables (Shake / Pulse / ColorFlash).
    SCTController.lua  (~80 ln)   Component adapter + ApplyMode dispatcher.
  View/
    SCT.xml                       CustomUISCTWindow (OnUpdate hook only when SCT is enabled).
    CustomUI_EventTextLabel.xml   Label template (unchanged).
    SCTAbilityIcon.xml            Icon template (unchanged).
```

### Files deleted in this refactor

- `SCTAnchors.lua` — anchor/holder/icon helpers move into `SCTOverrides.lua`, where they're used.
- `SCTEntry.lua`, `SCTTracker.lua` — replaced by `SCTOverrides.lua`.
- The unified-pipeline machinery: `m_BaseAnim`, `m_Effects` array, `_finished` tracking, `Effects.LaneMove`, `Effects.Grow` — gone. Stock's `:Update` is the base anim. `Effects.Shake`, `Effects.Pulse`, `Effects.ColorFlash` survive as small overlay functions invoked from `EventEntry:Update`.

These items are not deleted in the same commit they become unused — they are marked as legacy first (§6.1), verified unused, then deleted in Step 5b.

### 6.1 Legacy marking convention

When v2 code lands alongside v1 code that is destined for removal, mark the v1 code immediately so a future pass can delete it safely. Reuse the existing project convention (`<!-- LEGACY: -->` blocks already used in `CustomUI.mod`).

**Files (whole-file legacy):** add a header at the top of the file, on the very first line:

```lua
-- LEGACY (v2 SCT refactor, 2026-04-25): replaced by SCTOverrides.lua. Safe to delete once
-- Step 5a verifies no remaining references. Do not extend or fix bugs in this file.
```

**Module manifest:** comment the file out in `CustomUI.mod` with a `LEGACY:` marker (matching the existing in-addon `*Tab.xml` block):

```xml
<!-- LEGACY (v2 SCT, 2026-04-25): superseded by SCTOverrides.lua. Remove in Step 5b. -->
<!-- <File name="Source/Components/SCT/Controller/SCTEntry.lua" /> -->
```

**Functions / globals (partial-file legacy):** wrap the dead block with a comment fence and *delete the body*, leaving only a stub that errors if anyone calls it:

```lua
-- LEGACY (v2 SCT, 2026-04-25): replaced by EventEntry:Update center-pivot pattern. Remove with Step 5b.
function CritFlashOffsetForCenterPivot(...) error("LEGACY: CritFlashOffsetForCenterPivot removed") end
```

This makes accidental callers fail loudly during gate testing rather than silently using the old code path.

**Settings fields (saved-var legacy):** when a setting becomes a no-op (e.g. `baseXOffset` in Step 6), keep the field in `Settings()` migration but add a one-line `-- LEGACY (v2 SCT):` comment above it. Don't delete saved-var entries — that breaks user saves on first load. Field stays; consumer goes away.

**Grep target.** All legacy markers use the literal token `LEGACY (v2 SCT` so they're easy to find:

```
grep -rn "LEGACY (v2 SCT" Source/
```

Step 5b's gate is "this grep returns zero matches and `IsAtDefault()`+all override behavior still works."

### Code that survives unchanged

- The public API on `SCTSettings.lua` (CustomUISettingsWindow already consumes it).
- `SCTAbilityIcon.xml` — unchanged.
- The reload-safe anchor invariant (destroy-then-create on `CreateAnchor`).

### Code touched in this refactor

- `CustomUI_EventTextLabel.xml` — set `textalign="center"` (currently `"left"`) so scale 1.0 matches stock and §5.1.1 centering math is valid. The icon-on case still flips to `"left"` at runtime.

---

## 7. Default-state invariants

These are testable claims, not aspirations:

1. With component disabled: `EA_System_EventText.AddCombatEventText` is registered for `WORLD_OBJ_COMBAT_EVENT`. No CustomUI handler is registered for that event.
2. With component enabled and `IsAtDefault() == true`: `EA_System_EventText.AddCombatEventText` is **not** registered. `CustomUI.SCT.OnCombatEvent` is registered.
3. With component enabled and any single setting deviated: same handler ownership as #2; only render/filter behavior changes.
4. Toggling a setting back to its default: handlers stay CustomUI-owned while SCT remains enabled. Disabling SCT restores stock.
5. `/reloadui` while in Mode P: stock continues unmodified.
6. `/reloadui` while SCT is enabled: CustomUI restarts in Mode D and re-swaps handlers.

---

## 8. Implementation steps

Each step is one commit with a verification gate.

### Step 1 — Add `IsAtDefault()` to `SCTSettings.lua`

Pure addition, no behavioral change. Compares each field to its default constant. Used by Step 4 onward.

**Gate:** Toggle one setting via the settings UI; `IsAtDefault()` flips correctly. Reset all; flips back to true.

### Step 2 — Write `SCTOverrides.lua` (single file)

Subclass stock. Implement `:SetupText` overrides for both entry classes by calling stock's then post-applying overrides. Implement `:Destroy` extension for ability icon. Subclass `EventTracker` so `:Create` dispatches our entry classes.

Crit visuals are deferred to Step 3 — for now, `EventEntry:SetupText` post-processing only applies size/color/font/icon (no crit flair).

**Gate:** Force Mode D (skip `IsAtDefault` check). With every setting at default, the in-game output is visually indistinguishable from stock. With size at 1.25× for "Hit", hits are 25% bigger and nothing else changes.

### Step 3 — Crit overlay in `EventEntry:Update`

Move Shake/Pulse/ColorFlash into `SCTAnim.lua`. In `EventEntry:Update`, always move the motion holder with stock's animation math. If the entry is crit and any crit flag is enabled, run effects on the label visual layer: Shake adjusts the label's local center-anchor offset, Pulse scales the label, and Flash changes label color.

**Gate:** Enable Shake-only — crit shakes, non-crits unchanged. Enable Flash-only — crit color cycles, position unchanged. Combinations work.

### Step 4 — `ApplyMode()` and mode reconciliation

Add `ApplyMode()` to `SCTController.lua`. Call from Enable / Disable / Shutdown. Hook every public setter in `SCTSettings.lua` to call `ApplyMode()` after writing the value.

**Gate (enabled runtime):** Component enabled. All settings default. CustomUI handler registered. Set `outgoing.size["Hit"]` to 1.25 via the settings UI, then back to 1.0. Handler ownership remains CustomUI until the SCT component is disabled.

**Gate (mid-combat swap):** Take damage from a target dummy continuously while toggling a setting in and out of default. No double text, no missing text spans > 1 second.

### Step 5a — Mark v1 modules legacy and unwire from load order

Do **not** delete files yet. Per §6.1:

1. Add `LEGACY (v2 SCT, <date>)` header line to `SCTAnchors.lua`, `SCTEntry.lua`, `SCTTracker.lua`.
2. In `CustomUI.mod`, comment out the `<File>` lines for those modules with a `<!-- LEGACY (v2 SCT): … -->` marker. The new load order becomes: `SCTSettings → SCTAnim → SCTOverrides → SCTHandlers → SCTController → SCT.xml`.
3. Inside `SCTAnim.lua`, mark dead constants/effects with `LEGACY (v2 SCT)` comments and replace their bodies with `error()` stubs (LaneMove, Grow, the `m_BaseAnim`/`m_Effects` pipeline glue). Step 6 of v1 code is not reached anymore but a stray reference would now fail loudly.

**Gate:** Full settings reset. Output identical to stock side-by-side against an unmodified client. All v1 acceptance scenarios still pass. Run `grep -rn "SCT.EventTracker\|SCT.EventEntry\|SCT.PointGainEntry\|_SctAnchors\|_SctAnim" Source/Components/SCT/` and confirm only `SCTOverrides.lua`, `SCTAnim.lua`, and `SCTHandlers.lua` are matched — no references in marked-legacy files leak through.

### Step 5b — Delete legacy after one stable session

After Step 5a has soaked through at least one play session with no regressions, delete the marked-legacy files and stub functions outright. Remove the commented `<File>` lines from `CustomUI.mod`.

**Gate:** `grep -rn "LEGACY (v2 SCT" Source/` returns zero matches under `Source/Components/SCT/`. Build and full SCT acceptance pass unchanged.

### Step 6 — Remove `baseXOffset` from settings UI

`baseXOffset` is no longer an applied deviation. Remove the slider row from `CustomUISettingsWindowTabSCT.xml/.lua`. Leave the saved-variable field and getter/setter present so old saves don't error, but the setter becomes a no-op (clamps to 0). `IsAtDefault()` ignores the field.

**Gate:** SCT tab no longer shows a Base X Offset slider. Existing saves load without error. Setting field is forced to 0.

### Step 7 — Documentation

Trim or delete `implementation.md`. Trim this `plan.md` to a one-page "what this component does" doc, or delete it.

---

## 9. Acceptance criteria

The refactor is done when **all** of the following hold:

1. With component disabled OR all settings default: stock event text appears with stock visuals and stock timing. Confirmed by side-by-side compare against unmodified client.
2. Toggling any single setting away from default and back: handlers swap to CustomUI then swap back to stock, with no orphan windows in either direction.
3. The settings UI never directly reads or writes `CustomUI.Settings.SCT`.
4. `SCTOverrides.lua` calls into `StockEventEntry.SetupText`, `StockPointGainEntry.SetupText`, and `StockEventTracker.Create`; entry `Update` / `Destroy` are documented deviations because holders own motion and cleanup.
5. Total Lua line count under `Source/Components/SCT/` is ≤ 1000 (currently ~2300). No single file exceeds 500 lines.
6. `/reloadui` mid-Mode-D continues correctly. `/reloadui` mid-Mode-P leaves stock untouched.

---

## 10. Risks and mitigations

| Risk | Mitigation |
| :--- | :--- |
| Stock changes between RoR client patches and breaks our subclass assumptions. | The only stock methods we depend on are `:Create`, `:SetupText`, `:Update`, `:Destroy`, `:InitializeAnimationData` — names that have been stable. If a name changes we'll see immediate hard failures, not silent drift. |
| User changes a setting mid-combat-burst — handler swap mid-burst. | `ApplyMode()` always runs in setter calls (out of combat path), but the engine event queue may have already-dispatched events in flight. Worst case: one frame of duplicated or missing text. Acceptable. |
| Filter-only deviations (e.g., user only disables "show heals") still trigger Mode D and run the full subclass machinery, even though stock could just pre-filter. | This is fine. The cost is one extra function call per event. Filters being the most common deviation does not justify added complexity. |
| Entry holder lifetime under custom `Tracker:Update`. | The tracker queue stores the entry object; `EventEntry:Destroy` / `PointGainEntry:Destroy` tear down icon, label, and holder together without delegating to stock destroy. |
| `IsAtDefault()` cache invalidation. | Recomputed from scratch on every setter call. No incremental dirty tracking — too easy to get wrong. ~30 comparisons is cheap. |

---

## 11. Out of scope

- Reproducing v1's `_DumpHandlerState` introspection helper. Behavioral gates replace it.
- Supporting partial enable (e.g., "only color overrides apply, but filters and sizes are off"). Granularity is at the per-setting level — every setting is independently a deviation.
- Migrating saved-variable schema. v1's schema stays.
- Multi-step animation queuing across entries. Stock handles this, we delegate.
