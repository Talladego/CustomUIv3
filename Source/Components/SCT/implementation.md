# CustomUI.SCT — Implementation Notes (v2)

**Repo:** changes on `main`. **Plan:** `plan.md` (v2, deviation-only model).

---

## Progress vs plan

### Completed steps

| Step | Status | Notes |
| :--- | :--- | :--- |
| **1** — `IsAtDefault()` + `notifyChange()` hooks | **Done** | Added to end of `SCTSettings.lua`. Every public setter calls `notifyChange()` which invalidates `_isAtDefault` cache and calls `ApplyMode()` lazily. `SetBaseXOffset` is now a no-op (LEGACY). |
| **2** — `SCTOverrides.lua` | **Done** | New file. `EventEntry`, `PointGainEntry`, `EventTracker` subclass stock. Entries now use a zero-size motion holder with the visible label center-anchored inside it (plan §5.1.1), so label scale does not mutate animation offsets. Ability icon helpers inlined. |
| **3** — Crit effects | **Done** | `SCTAnim.lua` rewritten: Shake, Pulse, ColorFlash only. Dead v1 pipeline stubs marked `LEGACY (v2 SCT)`. Effects called from `EventEntry:Update` in SCTOverrides. |
| **4** — `SCTHandlers.lua` | **Done** | Thin filter+dispatch. `getOrCreateTracker()` helper. `OnUpdate` and `OnShutdown` driver here (called by `CustomUISCTWindow` XML). |
| **4** — `SCTController.lua` | **Done** | `ApplyMode()`, `_switchToP()`, `_switchToD()`. Component adapter `Enable` switches directly to Mode D because the framework writes the saved enabled flag after `Enable` returns; setters still call `ApplyMode`. `Disable`/`Shutdown` call `_switchToP`. |
| **5a** — Legacy marking + load order | **Done** | `SCTAnchors.lua`, `SCTEntry.lua`, `SCTTracker.lua` have `LEGACY (v2 SCT, 2026-04-25)` headers. Commented out of `CustomUI.mod`. New load order: `SCTSettings → SCTAnim → SCTOverrides → SCTHandlers → SCTController → SCT.xml`. |
| **6** — Remove `baseXOffset` slider | **Done** | Slider `$parentRowBaseXOffset` removed from XML. `SyncBaseXOffsetSlider`, `OnBaseXOffsetChanged`, tooltip block removed from Lua. `c_SCT_ROW_ORDER` entry removed. `SetBaseXOffset` in `SCTSettings.lua` is now a no-op. |
| **7** — Per-category X offsets | **Done** | Added Outgoing, Incoming, and Points X-offset sliders to CustomUISettingsWindow. Offsets replace stock X in `EventTracker:InitializeAnimationData`, so `0` is centered on the world-object anchor; point queue spray is added afterward. |
| **Template** — `textalign="center"` | **Done** | `CustomUI_EventTextLabel.xml` changed to `textalign="center"` to match stock and support holder-local center anchoring. |

### Pending steps

| Step | Status |
| :--- | :--- |
| **5b** — Delete legacy files | Pending — soak one play session first |
| **7** — Trim docs | Pending |

---

## Mode P / Mode D invariants

- Component disabled → Mode P: `_mode = "P"`, `CustomUISCTWindow` hidden, stock handlers registered, `EventTrackers = {}`.
- Component enabled → Mode D: `_mode = "D"`, `CustomUISCTWindow` shown, CustomUI handlers registered, holder-based runtime active even when `IsAtDefault() == true`.
- `Enable` switches directly to Mode D; every public `Set*` setter calls `ApplyMode()` via `notifyChange()`.
- `_switchToP()`: hide window → `RestoreHandlers()` → `DestroyAllTrackers()`.
- `_switchToD()`: `InstallHandlers()` → show window.

---

## Architecture deviations from plan

| Point | Detail |
| :--- | :--- |
| `EventTracker:Update` override | Plan §5.3 said override `:Create`; actual override point is `:Update` because stock's `:Update` hardcodes `EA_System_EventEntry:Create`. Override copies stock's Update verbatim with our entry classes substituted. |
| `EventTracker:Destroy` override | Added to drain `m_PendingEvents` (plan §7.3 gap) and stop anchor animations before `DetachWindowFromWorldObject`. |
| Holder-based entry movement | `EventEntry:Update` / `PointGainEntry:Update` copy stock's animation math and move the holder. The label remains center-anchored to the holder, so size sliders and pulse scale the label without anchor compensation. |
| Crit effects order in `EventEntry:Update` | Base float moves the holder first; Shake/Pulse/ColorFlash then affect only the label visual layer. |
| Heal filter | Checked in `OnCombatEvent` against `outgoing.filters.showHeal`; consistent with v1 behaviour. Heal = positive hit/crit amount regardless of direction. |

---

## Client gotchas carried forward

- `assert` return value: do not use `local x = assert(expr)` — some builds return nil. Use explicit nil check.
- `SystemData.Events` must not run at file load — wrapped inside `sctEngineHandlers()` function.
- BOM on Lua files — keep UTF-8 without BOM, especially `SCTHandlers.lua`.

---

## Suggested next session

1. Load in client. Verify SCT disabled uses stock event text with no CustomUI windows.
2. Enable SCT at default settings — verify CustomUI handlers are active and text position is stable.
3. Set one size slider to ≠ 1.0 — verify text scales correctly and stays centered on the world object.
4. Test crit flags (Shake, Pulse, Flash individually and combined).
5. Test ability icon toggle.
6. `/reloadui` while SCT is enabled.
7. If all pass: run Step 5b (delete legacy files, remove LEGACY comments).
