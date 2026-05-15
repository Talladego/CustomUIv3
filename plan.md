# CustomUI — Settings window (implementation plan)

> **Backlog index:** Phased verification, P2/P3 performance notes, and cross-file follow-ups: [issues.md](issues.md) §**Consolidated from auxiliary Markdown**.

## Implementation status (2026-05-04)

**Performance & memory:** P1 ✅ P3 ❌ reverted (MoveWindowToWorldObject must run every frame) P4 ✅ P5 — merged into Step 7 P6 ✅  
**Phase 1:** Steps 1–5 all ✅  
**Phase 2:** Steps 6–9 ✅ Step 10 ✅ (verified: no change needed — `Settings()` mutates table in-place, per-event call count is 2–3, cheap after first call)  
**Phase 3:** Steps 11–15 pending (verification/design pass; not code changes)

---

## Code quality & fix plan (2026-05-02)

Cross-reference: [review.md](review.md) (full audit), [issues.md](issues.md) (numbered backlog). Execution order follows review **Suggested improvements**.

### Performance & memory (2026-05-04)

Cross-reference: [issues.md](issues.md) §Performance & memory (**Medium #20–#24** resolved in tracker/controller code as of 2026-05-04). Goal: cut per-frame CPU and GC churn without changing visible buff/SCT behavior unless settings demand it.

| Step | Action | Primary files | Depends on |
|------|--------|----------------|------------|
| P1 ✅ | **BuffTracker:** Stop calling `OnBuffsChanged()` from `Update()` on every frame when a sort mode is active. On each frame: tick durations, then refresh timer labels via `buffFrame:Update(false)` (same call the no-sort path uses at [`Update`](Source/Shared/BuffTracker/BuffTracker.lua) ~702–706). Resort/relayout via `OnBuffsChanged()` only when (a) data changes (`UpdateBuffs` / `Refresh` / `SetFilter` / `SetBlacklist` / `SetWhitelist*` / `SetSortMode` / `SetCompressMultiCast` / `SetBuffGroups` / `SetGroupBuffs` / `SetAlignment` / `Clear`) **or** (b) a throttled tick (~10 Hz) — the throttle is **required**, not optional: the compiled sort key uses duration (bucket threshold at `m_durationThreshold` plus duration tie-breakers, see [`_RebuildSortFunc`](Source/Shared/BuffTracker/BuffTracker.lua) ~541–572), so order can change purely from elapsed time with no event. Setters listed above already call `OnBuffsChanged` directly — keep that and skip the throttle for them. | [BuffTracker.lua](Source/Shared/BuffTracker/BuffTracker.lua) | None |
| P2 (pending in-game) | After P1, smoke-test all trackers: PlayerStatus, TargetWindow, TargetHUD, GroupWindow (five rows), center alignment, compression, blacklist/whitelist. | Component controllers | P1 |
| P3 ✅ | **GroupIcons:** Outsiders use **`AttachWindowToWorldObject`** like roster; staleness via **`ValidateTrackedOutsidersProbeOnly`** (probe-only `MoveWindowToWorldObject` on **`c_OUTSIDER_PROBE_INTERVAL`**). See [issues.md](issues.md) §Consolidated & §Performance. | [GroupIconsController.lua](Source/Components/GroupIcons/Controller/GroupIconsController.lua) | None |
| P4 ✅ | **UnitFrames:** Cache last hover identity (`SystemData.MouseOverWindow` ref or string); skip `ResolveMemberWindowFromHoverWindowChain` when unchanged. | [UnitFramesController.lua](Source/Components/UnitFrames/Controller/UnitFramesController.lua) | None |
| P5 ✅ (merged into Step 7) | **TargetWindow / TargetHUD:** Both controllers already have an `m_enabled` flag with partial coverage (e.g. [TargetWindow `UpdateState`/`OnPlayerTargetUpdated`](Source/Components/TargetWindow/Controller/TargetWindowController.lua) ~159/238/269, [TargetHUD `OnUpdate`](Source/Components/TargetHUD/Controller/TargetHUDController.lua) ~82). The unguarded handlers are the effects + combat-flag registrations at TargetWindow ~354–357 and TargetHUD ~184–188. **Prefer the Enable/Disable register-unregister pattern from step 7 over local `m_enabled` early-returns** — doing both is duplicate work and the lifecycle sweep already covers these files. If step 7 is deferred, an `m_enabled` early-return at the top of each effects/combat-flag handler is the temporary fallback. | [TargetWindowController.lua](Source/Components/TargetWindow/Controller/TargetWindowController.lua), [TargetHUDController.lua](Source/Components/TargetHUD/Controller/TargetHUDController.lua) | Coordinate with / prefer step 7 |
| P6 ✅ | **SCT:** Current eviction at [`OnUpdate`](Source/Components/SCT/Controller/SCTHandlers.lua) ~140–149 only destroys trackers when both queues are empty **and** `not inCombat`. Add idle-during-combat eviction: when `m_DisplayedEvents:Front() == nil` and `m_PendingEvents:Front() == nil` for T seconds (track via per-tracker last-active timestamp updated in `AddEvent` / `Update`), destroy even while `inCombat`. Optional LRU cap as a defensive backstop. `DestroyAllTrackers` already clears on Disable/Shutdown — keep. | [SCTHandlers.lua](Source/Components/SCT/Controller/SCTHandlers.lua), [SCTController.lua](Source/Components/SCT/Controller/SCTController.lua) | None |

**Suggested order:** P1 → P2 → P4 (quick win) → P3 → P5 → P6. Verify with in-game FPS and `/script` memory if available; no automated harness yet ([issues.md](issues.md) Validation gaps).

### Performance & memory — follow-ups (2026-05-05)

Cross-reference: [issues.md](issues.md) §**BuffTracker performance & quality review (2026-05-05)** (**#25–#36**). These are post-P1 optimizations focused on eliminating avoidable `table.sort`/allocations and reducing work when trackers are hidden.

| Step | Action | Primary files | Depends on |
|------|--------|----------------|------------|
| P7 ✅ | **BuffTracker:** Replace `_sortedMapKeys(t)` iteration with `pairs(t)` everywhere ordering is not semantically observable; kept sorted only for `_WarnListConflicts` (debug-only) and the single `OnBuffsChanged` filter pass (stable NONE-mode display). | [BuffTracker.lua](Source/Shared/BuffTracker/BuffTracker.lua) | None |
| P8 ✅ | **BuffTracker:** Remove sorted iteration from `CopyBuffData` and synthetic-record builds (`CompressBuffData`, `_ApplyBuffGroups`) — plain `pairs`/`ipairs`. | [BuffTracker.lua](Source/Shared/BuffTracker/BuffTracker.lua) | P7 |
| P9 ✅ | **BuffTracker:** Nil-safe stacks (`stackCount or 1`) in `SetBuff`; dead `true and` removed from same-effect shortcut path. | [BuffTracker.lua](Source/Shared/BuffTracker/BuffTracker.lua) | None |
| P10 ✅ | **BuffTracker:** Reduce per-frame timer label updates: `m_visibleSlotCount` set in `OnBuffsChanged`; `Update` iterates only `1..visibleCount`. | [BuffTracker.lua](Source/Shared/BuffTracker/BuffTracker.lua) | P1 |
| P11 ✅ | **BuffTracker:** Hidden-container early-out: if the tracker container window is not showing, skip the full `OnBuffsChanged` pipeline. Mark dirty and replay when shown. | [BuffTracker.lua](Source/Shared/BuffTracker/BuffTracker.lua) | P1 |
| P12 ✅ | **BuffTracker:** Decorate-sort (duration category): `OnBuffsChanged` precomputes `buffData._sortDurCat` once per rebuild for the compiled sort function; comparator uses the cached value. | [BuffTracker.lua](Source/Shared/BuffTracker/BuffTracker.lua) | P7–P10 recommended first |
| P13 ✅ | **BuffTracker:** Gate `_layoutDurCat` snapshot pass behind `if self.m_compiledSortFunc or self.sortFunc then …`. Also merged tick+prune into a single `pairs` pass in `Update` (issues **#31**, **#25**). | [BuffTracker.lua](Source/Shared/BuffTracker/BuffTracker.lua) | None |
| P14 ✅ | **BuffTracker:** Reuse scratch tables inside `CompressBuffData` / `_ApplyBuffGroups` (mirror `m_scratchPostFilter` / `m_scratchInResult` pattern) — issues **#34**. | [BuffTracker.lua](Source/Shared/BuffTracker/BuffTracker.lua) | P7 |
| P15 ✅ | **BuffTracker:** Coalesce repeated rebuild triggers when multiple setter calls are made back-to-back — issues **#35**. | [BuffTracker.lua](Source/Shared/BuffTracker/BuffTracker.lua) | After P7–P12 |
| P16 ✅ | **BuffTracker:** Reduce `Refresh` churn by updating `m_buffData` in-place (reuse per-buff tables by buffId; prune missing keys) — issues **#36**. | [BuffTracker.lua](Source/Shared/BuffTracker/BuffTracker.lua) | None |

**Completed this session:** P7 ✅ P8 ✅ P9 ✅ P10 ✅ P11 ✅ P12 ✅ P13 ✅ P14 ✅ P15 ✅ P16 ✅  
**Open:** None (BuffTracker follow-ups **#25–#36** complete; remaining work is in-game smoke under P2).  
**Validation focus:** See [issues.md](issues.md) §Validation / smoke under items **#28–#30**.

### `pcall` convention (required)

Every `pcall` **must** capture results explicitly (e.g. `local ok, a, b = pcall(fn, ...)`). Blind calls that discard the boolean success flag, the error object on failure, or **return values** from the wrapped function are not allowed. Engine/stock functions often return values to their callers—the wrapper must forward those on success (multiple returns via `select`, unpacked locals, or an equivalent pattern), handle failures (`not ok`) with logging or fallback behavior, and only then run addon-side logic such as forcing hides.

### Phase 1 — Quick wins (≤1 file each, low risk)

| Step | Action | Primary files |
|------|--------|----------------|
| 1 ✅ | Wrap stock `PetWindow.UpdatePet` in `pcall` per §`pcall` convention — capture `ok` + all stock returns, forward on success, log on failure; then hide logic | [PlayerPetWindowController.lua](Source/Components/PlayerStatusWindow/Controller/PlayerPetWindowController.lua) |
| 2 ✅ | Guard `GameData.Player` reads: `UpdateHealthTextLabel`, `UpdateCareerIcon`; guard `HasPet()` when `Pet` nil | [PlayerStatusWindow.lua](Source/Components/PlayerStatusWindow/View/PlayerStatusWindow.lua), [PlayerPetWindowController.lua](Source/Components/PlayerStatusWindow/Controller/PlayerPetWindowController.lua) |
| 3 ✅ | `pcall` around `RefreshSctControls` row loop per §`pcall` convention — bind `ok, err` (or returns from inner fn); always clear `m_refreshing`; log on failure | [CustomUISettingsWindowTabSCT.lua](CustomUISettingsWindow/source/CustomUISettingsWindowTabSCT.lua) |
| 4 ✅ | Remove or wire `alwaysShowHitPoints` / `alwaysShowAPPoints` | [PlayerStatusWindowController.lua](Source/Components/PlayerStatusWindow/Controller/PlayerStatusWindowController.lua) |
| 5 ✅ | Docs sweep (**Low #19**, 2026-05-04): root `issues.md` / `plan.md` / `review.md` cite v2 [`SCTOverrides.lua`](Source/Components/SCT/Controller/SCTOverrides.lua) / [`SCTHandlers.lua`](Source/Components/SCT/Controller/SCTHandlers.lua) only; no Lua edits required (controller sources had no stale monolithic filename). |

### Phase 2 — Lifecycle & shared structure

| Step | Action | Primary files |
|------|--------|----------------|
| 6 ✅ | Move `PetWindow.UpdatePet` hook install to `Enable`, restore original on `Disable`/`Shutdown`; prevent wrapper-of-wrapper | [PlayerPetWindowController.lua](Source/Components/PlayerStatusWindow/Controller/PlayerPetWindowController.lua); align with [PlayerStatusWindow/plan.md](Source/Components/PlayerStatusWindow/plan.md) |
| 7 ✅ | Add symmetric `WindowUnregisterEventHandler` (or `Enable`-only registration) for all controllers — **include GroupIcons**; optional helper tuple list | Player/Target/HUD/Group/GroupIcons/Pet/PlayerStatus controllers; template: [UnitFramesController.lua](Source/Components/UnitFrames/Controller/UnitFramesController.lua) |
| 8 ✅ | Shared buff-filter schema in [BuffFilterDefaults.lua](Source/Shared/BuffTracker/BuffFilterDefaults.lua): `FilterDefaults` + **`FilterSettingKeys`**; all buff-filter `GetSettings` use them (2026-05-04). | [PlayerStatusWindowController.lua](Source/Components/PlayerStatusWindow/Controller/PlayerStatusWindowController.lua), [TargetWindowController.lua](Source/Components/TargetWindow/Controller/TargetWindowController.lua), [TargetHUDController.lua](Source/Components/TargetHUD/Controller/TargetHUDController.lua), [GroupWindowController.lua](Source/Components/GroupWindow/Controller/GroupWindowController.lua) |
| 9 ✅ | On SCT `BeginLoading`, tear down crit trackers (`DestroyAllTrackers` or shared disable path) | SCT controller stack ([issues.md](issues.md) §Medium #12) |
| 10 ✅ | **`Settings()` normalization cache:** dirty flag cleared in `notifyChange` (then `ApplyMode` + one `Settings()` to warm cache). `GetSettings` / getters skip migrate loops when clean. `CustomUI.SCT.InvalidateSettingsNormalization()` for rare edits outside setters. | [SCTSettings.lua](Source/Components/SCT/Controller/SCTSettings.lua) |

### Phase 2b — Stock component takeover (unhook + restore)

**Goal:** When a CustomUI component *replaces* a stock window, it must also be responsible for:

- **Taking over:** hide stock *and* stop stock background work by unregistering stock event handlers / OnUpdate drivers where possible.
- **Handing back:** when the CustomUI component disables, restore the stock handlers and show stock windows again.

**Why:** `LayoutEditor.UserHide` / `WindowSetShowing(false)` typically stops XML `OnUpdate` ticks, but **does not** stop `WindowRegisterEventHandler` callbacks. Hidden stock windows can still process high-frequency events (buff updates, group updates, target updates), duplicating work while CustomUI is active.

#### Design principles

- **Component-owned:** The replacing component controls the entire lifecycle (unhook on `Enable`, rehook on `Disable`).
- **Idempotent:** Every hook/unhook must be safe to call multiple times (reloads, partial init, load-order races).
- **Restorable:** Always store original handler bindings when possible, or fall back to calling the stock `Initialize()`/refresh functions to recreate them.
- **Defensive:** Only touch stock windows/handlers if they exist; tolerate other addons modifying stock behavior.

#### Implementation plan

| Step | Action | Primary files | Notes |
|------|--------|----------------|------|
| S1 ✅ | Add a small shared helper module (or functions in `Source/CustomUI.lua`) to manage stock hook state: `UnhookStock(windowName, eventId, handlerName?)` + `RehookStock(...)`, with per-component state tables (`m_stockHooks = { ... }`). | `Source/CustomUI.lua` or new `Source/Shared/StockHooks.lua` | Implemented as **per-component local unhook/rehook functions** + state flags (no shared module yet, by design). |
| S2 ✅ | **TargetWindow takeover:** unhook stock `ea_targetwindow` event handlers (not just hide `PrimaryTargetLayoutWindow` / `SecondaryTargetLayoutWindow`). Rehook on disable. | `Source/Components/TargetWindow/Controller/TargetWindowController.lua` | Unhooks handlers registered on stock `TargetWindow` for `PLAYER_TARGET_UPDATED`, `PLAYER_TARGET_EFFECTS_UPDATED`, `PLAYER_COMBAT_FLAG_UPDATED`; re-registers on disable. |
| S3 ✅ | **PlayerStatusWindow takeover:** unhook stock `PlayerWindow` handlers that drive buffs/effects/OnUpdate work; rehook on disable. | `Source/Components/PlayerStatusWindow/Controller/PlayerStatusWindowController.lua` | Unhooks all stock `PlayerWindow.Initialize()` event registrations; restores them on disable. |
| S4 ✅ | **GroupWindow takeover:** unhook stock `GroupWindow` handlers (group status/effects/buffs); rehook on disable. | `Source/Components/GroupWindow/Controller/GroupWindowController.lua` | Stock uses global `RegisterEventHandler`; CustomUI now calls `UnregisterEventHandler` for the stock bindings and restores them on disable. |
| S5 | **TargetHUD:** if TargetHUD is purely additive (no stock equivalent), no stock takeover needed. If it replaces a stock HUD element, apply the same pattern. | `Source/Components/TargetHUD/Controller/TargetHUDController.lua` | Currently CustomUI TargetHUD is its own world-attached windows; stock is target windows, not HUD. |

**Additional hardening (2026-05-05):** For rapid ownership flips (stress test), each replacement now forces buff/state resync on handoff:

- `PlayerStatusWindow`: refresh CUI buffs on enable; clear CUI on disable; refresh stock buffs + push HP/AP on disable.
- `TargetWindow`: refresh CUI buff trackers on enable; clear on disable; force stock `TargetWindow.UpdateTarget(...)` after rehook/show.
- `GroupWindow`: refresh CUI member trackers on enable; clear on disable; force stock `GroupWindow.OnGroupUpdated()` after rehook/show.

#### How to “rehook” stock safely

Because stock code is not designed as a public “unregister/re-register API”, we’ll use a layered approach per stock component:

- **Preferred:** Call `WindowUnregisterEventHandler(stockWindow, eventId)` for each event the stock window registered. On restore, call `WindowRegisterEventHandler(stockWindow, eventId, "Stock.Handler")`.
- **Fallback:** If we can’t reliably enumerate/restore individual handlers (client updates, addon drift), call the stock component’s `Initialize()` / `OnShown()` equivalent to rebuild its registrations after showing it again.
- **Always:** Restore stock visibility (`LayoutEditor.UserShow` where registered; `WindowSetShowing(true)` otherwise).

#### Validation checklist

- Toggle each CustomUI replacement on/off repeatedly (and across `/reloadui`) and verify:
  - Stock windows do not process buff/group/target events while hidden (no logs, no CPU spikes).
  - Returning control to stock restores normal behavior immediately (targets update, group updates, player buffs show).
  - No missing handlers after a zone change / scenario begin-end cycle.

### Phase 3 — Verification & design decisions

**Canonical status:** [issues.md](issues.md) §**Consolidated from auxiliary Markdown** (Phase 3 table). Briefly: steps **11–14** done or superseded; step **15** (GroupWindow harness) **open** — Medium **#11**.

---

## PlayerStatusWindow — “Minimal Appearance” (planned)

### Goal

Add an **optional alternative appearance** for `CustomUI.PlayerStatusWindow` called **“Minimal Appearance”** that:

- Uses the **UnitFrames player row look** as the base: HP bar style options (normal vs TargetHUD-tintable archetype), **AP bar** (optional, **default on**), career icon (+ optional ring), name, and HP% text, plus a **black frame/contour border**.
- **Width matches** the existing `CustomUIPlayerStatusWindow` width exactly (currently **270px** in `View/PlayerStatusWindow.xml`).
- **Height matches** UnitFrames member rows (currently **55px** in `View/UnitFrames.xml` template `CustomUIBGMember`).
- Is implemented as an **in-place appearance swap** on the existing `CustomUIPlayerStatusWindow` root so users do **not** need to reposition a second window.

### Reference geometry (current code)

- `CustomUIPlayerStatusWindow` size: **270×111** (`Source/Components/PlayerStatusWindow/View/PlayerStatusWindow.xml`).
- UnitFrames row template `CustomUIBGMember`: **139×55** (`Source/Components/UnitFrames/View/UnitFrames.xml`).

### Proposed implementation approach (in-place)

#### 1) Settings + mode switch

- Add `appearance = "default" | "minimal"` to `CustomUI.Settings.PlayerStatusWindow` (default `"default"`).
- Expose a selector in `CustomUISettingsWindowTabPlayer` (or dedicated PlayerStatusWindow tab, depending on current settings UI) to switch appearance.
- Add `CustomUI.PlayerStatusWindow.ApplyAppearance()` that:
  - Shows/hides the existing default widgets (portrait, status container, killing spree arc, relic/rvr widgets, etc.)
  - Shows/hides the minimal widgets container
  - Re-anchors the **existing** `CustomUIPlayerBuffs` container relative to whichever appearance is active.

#### 2) Minimal UI container (new XML inside existing root)

Add a new child window under `CustomUIPlayerStatusWindow`, e.g.:

- `CustomUIPlayerStatusWindowMinimal` (or `$parentMinimal`)
  - Size: **270×55**
  - Black contour border: reuse the same slice as UnitFrames contour (`WarbandUnitFrame-Frame`) tinted black, or a dedicated border template if we already have one.
  - Two HP bar variants (like UnitFrames):
    - normal filled/background (green/black) OR
    - TargetHUD-tintable “CastBar” strip with archetype tint + missing-HP red tint
  - Labels:
    - name (same font family as UnitFrames `LabelName`, clipped to fit 270)
    - HP percent (reuse UnitFrames `LabelHealth` style; for the local player we can display “NN%” or “cur/max (NN%)” depending on preference)
  - Career icon:
    - use the same atlas logic as UnitFrames (icon + optional ring tinted by archetype setting)
  - **Leader crown**:
    - include the same warband/group leader crown behavior as the existing PlayerStatusWindow (and keep the existing GroupIcons-aligned crown anchoring behavior).

Key constraint: **Do not reuse `CustomUIBGMember` directly** as-is because it is 139px wide and bakes in fixed anchors and bar widths; instead, create a **PlayerStatusMinimal template** that borrows the same assets/slices but with 270px width.

#### 3) Data/model reuse (keep controller logic)

Keep `PlayerStatusWindowController.lua` as the single source of truth for:

- Player name, career icon, and HP/AP values (already event-driven)
- Archetype-coloring decision (borrow UnitFrames setting semantics)
- BuffTracker ownership + settings

Add a minimal rendering path that:

- Writes to the minimal labels/statusbars when appearance is minimal
- Leaves existing default UI updates intact but gated behind `appearance == "default"`

#### 4) HP bar archetype option parity with UnitFrames

Implement the same options the UnitFrames “player row” effectively supports:

- **normal HP bar** (green fill) OR
- **TargetHUD-tintable bar** (archetype tint + red missing tint)

To avoid duplicating palette logic, either:

- (Preferred) factor the shared archetype RGB resolver into a small shared helper (e.g. `Source/Shared/ArchetypeColors.lua`), used by both UnitFrames and PlayerStatusWindow, or
- duplicate the small mapping in PlayerStatusWindow if we want to avoid a shared module.

#### 5) Buff placement + visibility

Minimal appearance still needs the existing `CustomUIPlayerBuffs` tracker. For the first pass we keep buffs exactly as today:

- Keep the same tracker instance and filter settings.
- Keep the current **layout and position** (5×4 anchored as it is now). No re-anchor work in the initial Minimal pass.

### Essential items to confirm (possible “missed” requirements)

- **AP bar**: include as optional; **default on** (matches UnitFrames feel). Provide a toggle in settings.
- **Morale/advancement/renown indicators**: default PlayerStatusWindow shows these; minimal spec did not request them. Decide whether to hide entirely or keep as optional overlays.
- **RvR flag / relic bonus / killing spree**: currently part of default window; minimal spec did not request them. If omitted, ensure no controller logic depends on their visibility.
- **Mouse input + tooltips**: default portrait/career icon have tooltip behavior. Minimal should keep at least the career icon tooltip; decide if portrait tooltip is intentionally removed.
- **Leader crown**: include (required). Main assist crown can remain default-mode only for now unless requested later.

### Validation

- Switching `appearance` should not change window position (same root) and should not require layout editor resets.
- Toggle default ↔ minimal while in combat and verify:
  - HP bar continues to update (no event replay gaps)
  - Buffs remain correct (Refresh-on-swap)
  - No lingering hidden-window OnUpdate cost (minimal container should not add per-frame work)

### Settings window / tabs (maintenance)

- Apply/Reset/Cancel and SCT color-picker lifecycle are **in good shape** (review.md S1, S3).
- Optional: one-pass XML anchor audit per tab (README §Notes — `Point` vs `RelativePoint`); tab Lua forward-decl checks per README.

---

## Status: Complete (settings window shell)

---

## Goal

A tabbed settings window that matches the stock EA_SettingsWindow appearance.
The **CustomUISettingsWindow** addon owns the window implementation; components expose settings data only (see project README). Tabs register from that addon at load time.
The window is opened with `/cui` and stays empty until at least one tab is registered.

---

## Visual Design

- Fixed width: 900px (matches stock EA_SettingsWindow)
- Height: 600px
- Tab buttons: `EA_Button_Tab` via `CustomUISettingsWindowTabButton` template (124px × 35px each, capped)
- Tab width shrinks if count exceeds available strip space: `min(124, stripWidth / tabCount)`
- Tab buttons chain right-to-left (stock pattern): Tab1 anchored at `topleft+25`, each subsequent tab's `right` anchored to previous tab's `left`
- Tab separator: `EA_Window_TabSeparatorLeftSide` and `EA_Window_TabSeparatorRightSide` as static XML children of the tab strip, each with two same-point anchors — one to the strip edge, one to the outermost tab — to stretch across the empty space. No middle separator needed.
- Background, titlebar, button bar: stock templates
- Bottom buttons: Apply, Reset, Cancel
- Content socket fills space between tab strip and button bar

---

## Window Structure (SettingsWindow.xml)

```
CustomUISettingsWindow                    movable, layer=secondary, 900×600
  $parentBackground                       EA_Window_DefaultBackgroundFrame
  $parentTitleBar                         EA_TitleBar_Default  "CustomUI Settings"
  $parentTabButtons                       plain container, anchored to titlebar bottom, hidden until tabs registered
    $parentSeparatorLeft                  EA_Window_TabSeparatorLeftSide, layer=background — second anchor set in Lua
    $parentSeparatorRight                 EA_Window_TabSeparatorRightSide, layer=background — second anchor set in Lua
  CustomUISettingsWindowSocket            plain container, anchored between tab strip and button bar
  $parentButtonBackground                 EA_Window_DefaultButtonBottomFrame, 75px height at bottom
  $parentCancelButton                     CustomUISettingsWindowButton
  $parentResetButton                      CustomUISettingsWindowButton
  $parentApplyButton                      CustomUISettingsWindowButton
```

Tab buttons are NOT declared in XML — created at runtime in `Initialize()`.
Tab content windows are NOT declared in XML — created at runtime via component-supplied template names.

---

## Separator anchoring (Lua, after button loop)

Stock double-anchor stretch pattern (from `ea_settingswindowtabbed.xml`):

- `SeparatorLeft`: two `bottomleft` anchors — one to strip's `bottomleft`, one to **rightmost** tab's `topright`
- `SeparatorRight`: two `bottomright` anchors — one to strip's `bottomright`, one to **leftmost** tab's `topleft`

Because buttons chain right-to-left, `Tab1` (first created) is the rightmost and `prevBtnName` (last created) is the leftmost.

---

## Controller API (SettingsWindowController.lua)

### Public

```lua
-- Called by components at file scope to request a tab.
-- Silently ignored if templateName is nil or label is already registered (dedup guard).
CustomUI.SettingsWindow.RegisterTab(label, templateName, component)

CustomUI.SettingsWindow.Open()
CustomUI.SettingsWindow.Close()
```

### Internal

```lua
CustomUI.SettingsWindow.Initialize()   -- lazy, runs once on first OnShow
CustomUI.SettingsWindow.SelectTab(i)   -- show/hide content, set button pressed states
CustomUI.SettingsWindow.OnApply()      -- iterates tabs, calls component:ApplySettings() if present
CustomUI.SettingsWindow.OnReset()      -- iterates tabs, calls component:ResetSettings() if present
CustomUI.SettingsWindow.OnCancel()     -- iterates tabs, calls component:CancelSettings() if present, then Close()
```

### Tab registration record

```lua
-- m_tabs[i] = {
--   label        = "My Component",
--   templateName = "MyTabTemplate",  -- must be non-nil to register
--   component    = componentRef,     -- component adapter, or nil
--   buttonName   = nil,              -- set during Initialize()
--   contentName  = nil,              -- set during Initialize()
-- }
```

---

## Component tab interface

Each component that registers a tab provides:

- An XML template window (e.g. `CustomUIGroupWindowTab`) declared in `View/<Name>Tab.xml`
- A `CustomUI.<Name>.Tab` table with:
  - `Tab.OnShown(contentName)` — called when tab is selected; syncs checkbox state and sets label text
  - `Tab.OnToggleEnable()` — checkbox handler; toggles component enabled state
- A `RegisterTab(label, templateName, component)` call at file scope in the controller

### Minimal tab XML pattern

```xml
<Window name="CustomUI<Name>Tab" movable="false" savesettings="false" hidden="true">
    <Windows>
        <Button name="$parentEnableCheckBox" inherits="EA_Button_DefaultCheckBox">
            <Anchors><Anchor point="topleft" relativePoint="topleft"><AbsPoint x="20" y="20" /></Anchor></Anchors>
            <EventHandlers>
                <EventHandler event="OnLButtonUp" function="CustomUI.<Name>.Tab.OnToggleEnable" />
            </EventHandlers>
        </Button>
        <Label name="$parentEnableLabel" inherits="EA_Label_DefaultText">
            <Size><AbsPoint x="200" y="24" /></Size>
            <Anchors>
                <Anchor point="right" relativePoint="left" relativeTo="$parentEnableCheckBox"><AbsPoint x="8" y="0" /></Anchor>
            </Anchors>
        </Label>
    </Windows>
</Window>
```

### Minimal Lua pattern

```lua
CustomUI.<Name>.Tab = {}

function CustomUI.<Name>.Tab.OnShown(contentName)
    ButtonSetPressedFlag(contentName .. "EnableCheckBox", CustomUI.IsComponentEnabled("<Name>"))
    LabelSetText(contentName .. "EnableLabel", L"Enable <Name>")
end

function CustomUI.<Name>.Tab.OnToggleEnable()
    local newState = not CustomUI.IsComponentEnabled("<Name>")
    CustomUI.SetComponentEnabled("<Name>", newState)
    ButtonSetPressedFlag(SystemData.ActiveWindow.name, newState)
end

CustomUI.SettingsWindow.RegisterTab("<Label>", "CustomUI<Name>Tab", <Name>Component)
```

---

## Load Order Constraint

SettingsWindow XML and controller must load **before** any component controller.

```
Settings/View/SettingsWindow.xml
Settings/Controller/SettingsWindowController.lua
... component files ...
```

---

## Registered tabs (current)

| Label | Template | Component |
|---|---|---|
| Player Status | `CustomUIPlayerStatusWindowTab` | `PlayerStatusWindowComponent` |
| Target Window | `CustomUITargetWindowTab` | `TargetWindowComponent` |
| Pet Window | `CustomUIPlayerPetWindowTab` | `PlayerPetWindowComponent` |
| Target HUD | `CustomUITargetHUDTab` | `TargetHUDComponent` |
| Group Window | `CustomUIGroupWindowTab` | `GroupWindowComponent` |
| Unit Frames | `CustomUIUnitFramesTab` | `UnitFramesComponent` |

---

## Sequence

1. Addon loads → components call `RegisterTab` at file scope → tab records queued in `m_tabs`
2. Player opens window (`/cui`) → `OnShown` fires → `Initialize()` runs once
3. `Initialize()` → creates buttons, anchors separators in Lua, creates content windows, selects tab 1
4. Player clicks tab → `OnTabClicked` → `SelectTab(WindowGetId(...))` → calls `Tab.OnShown(contentName)`
5. Player clicks Apply/Reset/Cancel → iterates `m_tabs`, calls optional component callbacks
