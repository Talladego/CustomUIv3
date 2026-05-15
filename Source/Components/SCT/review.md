# CustomUI.SCT — Code Review Report

**Status:** Functional review (2026-04-25). Doc-vs-code gap items moved to root [issues.md](../../issues.md) §Consolidated from auxiliary Markdown.

**Follow-up index:** See root [issues.md](../../issues.md) §**Consolidated from auxiliary Markdown** → SCT for open items.

**Reviewed against:** `plan.md` and `implementation.md`
**Files reviewed:** SCTSettings.lua (705 ln), SCTAnim.lua (264 ln), SCTAnchors.lua (207 ln), SCTEntry.lua (456 ln), SCTTracker.lua (401 ln), SCTHandlers.lua (286 ln), SCTController.lua (61 ln), SCT.xml, CustomUI_EventTextLabel.xml, SCTAbilityIcon.xml, CustomUI.mod
**Date:** 2026-04-25

---

## TL;DR

The refactor is functionally sound. All §5 public API functions are present and correct, the §6 Enable/Disable contract is correctly implemented, the §8 unified animation pipeline works, and §9 lane slots are implemented as planned. However there are several gaps between what `implementation.md` claims and what the code actually contains — most importantly, **every documented pcall boundary is absent from the code**, directly contradicting `implementation.md`. There are also file-size overages across four files, a minor Tracker:Destroy omission, and a Shutdown duplication.

---

## 1. Load Order

**Plan §4:** `SCTSettings → SCTAnchors → SCTAnim → SCTEntry → SCTTracker → SCTHandlers → SCTController → SCT.xml`

**Actual (CustomUI.mod):**
```
SCTSettings → CustomUI_EventTextLabel.xml → SCTAbilityIcon.xml
            → SCTAnim → SCTAnchors → SCTEntry → SCTTracker
            → SCTHandlers → SCTController → SCT.xml
```

SCTAnim and SCTAnchors are swapped vs the plan. The actual order is correct — SCTAnchors.lua does not depend on `_SctAnim`, but SCTEntry and SCTTracker both require `_SctAnim` to be populated before `_SctAnchors`. The plan's stated order would have been wrong if followed literally. The load-order comments inside the Lua files are self-consistent with the actual `.mod` file.

**Verdict:** Deviation from plan, but the actual order is functionally correct. `plan.md` contains a wrong load-order spec; `implementation.md` partially documents the actual order but the discrepancy is not called out.

---

## 2. File Sizes vs Plan Targets

| File | Plan target | Actual | Status |
| :--- | ---: | ---: | :--- |
| SCTController.lua | ~80 ln | 61 ln | ✅ Under |
| SCTSettings.lua | ~400 ln | 705 ln | ❌ +76% |
| SCTHandlers.lua | ~150 ln | 286 ln | ❌ +91% |
| SCTTracker.lua | ~250 ln | 401 ln | ❌ +60% |
| SCTEntry.lua | ~250 ln | 456 ln | ❌ +82% |
| SCTAnim.lua | ~300 ln | 264 ln | ✅ Under |
| SCTAnchors.lua | ~120 ln | 207 ln | ❌ +73% |

`SCTSettings.lua` is the largest gap and is called out in `implementation.md` as a known partial. `SCTEntry.lua` and `SCTHandlers.lua` are similarly over but not mentioned. `SCTHandlers.lua` contains `DestroyAllTrackers`, `Activate`, `Deactivate`, `OnCombatEvent`, point-gain handlers, `OnUpdate`, and `OnShutdown` — many of these belong in `SCTTracker` or `SCTController` per the plan's responsibility split.

**Verdict:** §10 cleanup / §12 acceptance ("no single file exceeds ~400 lines") is not met for five files.

---

## 3. pcall Boundaries — Critical Discrepancy

`implementation.md` explicitly states:

> **`pcall` retained** for plan §10 boundaries: **`AttachWindowToWorldObject`**, **`DetachWindowFromWorldObject`**, **`CreateWindowFromTemplate`** (with brief comments). **`tryUnregisterStock`** still uses **`pcall(UnregisterEventHandler, …)`**.

**None of these pcalls exist in the actual code.**

| Call site | Plan §10 | impl.md claim | Actual code |
| :--- | :--- | :--- | :--- |
| `AttachWindowToWorldObject` (SCTTracker:Create) | pcall | retained | **direct call** |
| `DetachWindowFromWorldObject` (SCTTracker:Destroy) | pcall | retained | **direct call** |
| `CreateWindowFromTemplate` (SctEnsureEventTextRootAnchor, Tracker:Update holder) | pcall | retained | **direct call** |
| `WindowGetParent` (SctApplyAbilityIconLayout) | pcall | retained | **removed 2026-04-26**; ability icons use cached `m_ParentWindow` |
| `UnregisterEventHandler` (tryUnregisterStock) | not required | pcall | **direct call** |

`tryUnregisterStock` (SCTHandlers.lua:203–209):
```lua
local function tryUnregisterStock(eventId, stockHandlerName)
    if not (eventId and stockHandlerName) then return false end
    UnregisterEventHandler(eventId, stockHandlerName)
    return true
end
```
No pcall. The function name suggests it was designed to be safe, but the pcall was removed at some point and `implementation.md` was not updated.

**Verdict:** `implementation.md` is factually wrong about these four pcall boundaries. The risk is real: `DetachWindowFromWorldObject` and `CreateWindowFromTemplate` in particular are the ones the plan flagged as having caused crashes in production (`WindowGetParent-on-destroyed-window` crash). Whether these direct calls have survived testing doesn't change that the documentation is wrong.

---

## 4. §6 Enable / Disable Contract

### 4.1 Correct
- Handler install/restore order matches §6.1/§6.2 exactly ✅
- `m_active = false` set before unregistering handlers ✅
- `_handlersInstalled` idempotency gate ✅
- `_stockWasRegistered` recorded before unregistering stock ✅
- Stock restored only where `_stockWasRegistered[id]` is true ✅
- All six handler strings in §6.3 are present ✅

### 4.2 Shutdown duplicates Disable

**Resolved (2026-04-26):** `SCTComponent:Shutdown()` now calls `self:Disable()` only, matching plan §6.5.

### 4.3 Orphan legacy functions

**Removed (2026-04-26):** `CustomUI.SCT.Activate` and `CustomUI.SCT.Deactivate` (the latter was dangerous if called out of component lifecycle: it destroyed trackers without `RestoreHandlers`).

### 4.4 Extra GetSettings() call in Enable

`SCTComponent:Enable()` calls `CustomUI.SCT.GetSettings()` after installing handlers. The plan doesn't require this. Harmless but unexplained.

---

## 5. §7 Window Lifetime

### 5.1 m_PendingEvents not cleared in Tracker:Destroy

**Resolved (2026-04-26):** `EventTracker:Destroy` drains the pending queue with `PopFront` until empty before displayed teardown.

(Former gap: plan §7.3 step 2 wanted pending drained; a forced `DestroyAllTrackers` during a burst could leave stale references if only `m_DisplayedEvents` was cleared.)

### 5.2 Reload-safe anchor creation

`SctEnsureEventTextRootAnchor` (SCTAnchors.lua:75–90) correctly implements §7.2: destroy existing anchor before create. ✅

### 5.3 Destruction animation stops

All `DestroyWindow` calls are preceded by `SctStopWindowAnimations`. ✅ Holder, label, and ability icon all follow the plan's hard rule.

---

## 6. §8 Animation Pipeline

### 6.1 Effect.Apply signature deviation

Plan §8.3 specifies: `Apply = function(entry, p, params)`

Actual (all five effects): `Apply = function(entry, localT, p, params)`

`localT` (seconds elapsed since effect start) was added as a third parameter to support the sinusoidal Shake calculation. The plan's §8.4 Shake description uses `localT` in its formula but the interface spec in §8.3 doesn't include it. All callers and all effects are self-consistent. Minor spec inconsistency — no functional issue.

### 6.2 Tuned constants that deviate from plan §8.6.1

| Constant | Plan value | Actual value | Note |
| :--- | ---: | ---: | :--- |
| `FLOAT_TAIL` | 0.75 | **0.60** | Tuned for snappier feel |
| `MIN_DISPLAY_TIME` | 4.0 | **3.4** | Tuned |
| `CRIT_LANE_OFFSET_X` | 80 px (plan) | **60 px** (tuned) | **2026-04-26:** single source `CRIT_LANE_OFFSET_X` in `SCTAnim` / `_SctAnim`, used by `SCTTracker` |

The comment at `FLOAT_TAIL` explains the intent. `MIN_DISPLAY_TIME` at 3.4 breaks the plan's stated rationale ("matches stock's `maximumDisplayTime` default"), though the difference is small.

### 6.3 Effect list construction (§8.6) moved into Tracker:Update

Plan §8.6 places effect-list construction in `Tracker:DispatchOne`. The actual code builds the effect list inline in `Tracker:Update` (SCTTracker.lua:222–306), which is `DispatchOne`'s effective location. Functionally equivalent; no separate `DispatchOne` method was extracted. The code block is ~85 lines, contributing to the file size overage.

### 6.4 Base animation and effect pipeline: correct

`m_BaseAnim` shape matches plan §8.1. ✅  
Fade starts on `entry.m_Window`, not the holder. ✅  
Ability icon gets a matching alpha animation. ✅  
`maxTime` is the single source of truth for lifetime and fade delay. ✅  
`PointGainEntry` uses the same entry shape with empty `m_Effects`. ✅

---

## 7. §9 Tracker Model

### 7.1 Correct
- `m_LaneSlots`, `ReserveLane`, `ReleaseLane` match §9.1 exactly ✅
- If `ReserveLane` returns nil, dispatch is skipped and retried next frame ✅
- Crit trackers destroy when both queues empty regardless of combat ✅
- Non-crit trackers check `GameData.Player.inCombat` before destroying ✅
- Window naming via `m_NextEntryIndex` counter (§9.3) ✅

### 7.2 Per-frame pop logic (§9.2 deviation)

Plan: "pop [the front] and call `entry:Destroy()`, then re-check the new front (an entry that has been waiting can be popped immediately on the same frame)."

Actual: the iterator loop only pops when `index == self.m_DisplayedEvents:Begin()`. There is no re-check of the new front on the same frame. An entry that expired while waiting at position 2 will not be popped until the next OnUpdate call. This is a minor behavioral deviation — entries live at most one extra frame — but it diverges from the plan's "immediate re-check" spec.

---

## 8. §10 Error & Logging Policy

### 8.1 SCTAnchors.lua logging

`implementation.md` is updated (2026-04-26) to match shipped behavior: `sctWriteEngineLog` is gated by `CustomUI.SCT.m_sctFileLog ~= false` (controllable via `SetSctFileLog` where exposed). `SctPcallFailed` always uses `LogLuaMessage` at WARNING for boundary failures, then the same string through `sctWriteEngineLog("warning", …)`.

### 8.2 Per-event logging

There are no per-event `SCTLog` calls in the handlers (`OnCombatEvent`, `OnXpText`, etc.). The §12 acceptance criterion ("per-event SCTLog output is empty unless `m_debug` is true") is met by absence.

### 8.3 CritFlashOffsetForCenterPivot duplicated

**Resolved (2026-04-26):** the unused duplicate was removed from `SCTAnchors.lua`; the only implementation remains in `SCTAnim` / `CustomUI.SCT._SctAnim.CritFlashOffsetForCenterPivot`.

---

## 9. §5 Public API — Complete

All functions from §5.1 through §5.5 are present in `SCTSettings.lua`. The `Settings()` private helper is the only direct reader of `CustomUI.Settings.SCT`. ✅

`CustomUI.SCT.GetCritAnimFlags` (line 571) is an alias for `GetCritFlags` — acceptable bridge, correctly implemented.

---

## 10. XML

| File | Plan requirement | Actual | Status |
| :--- | :--- | :--- | :--- |
| `CustomUI_Window_EventTextLabel` | `ignoreFormattingTags="false"`, `textalign="left"`, `wordwrap="false"`, `handleinput="false"`, 400×100 default | Matches | ✅ |
| `CustomUI_SCTAbilityIcon` | `DynamicImage` named `$parentIcon` | Present; `<Interface><Windows>` root (not `<Root>`) | ✅ |
| `CustomUISCTWindow` | `OnUpdate`, `OnShutdown`; hidden by default; no size/anchor required | Matches | ✅ |

---

## 11. §12 Acceptance Criteria — Status

| Criterion | Status | Notes |
| :--- | :--- | :--- |
| Toggle stability (no orphan windows, no leaked registrations) | ✅ Verified in-game | Per implementation.md |
| Stock event text appears when SCT disabled | ✅ Behavioral | Per implementation.md |
| No stock event text when SCT enabled | ✅ Behavioral | Per implementation.md |
| `/reloadui` mid-combat: text continues, no orphan windows | ✅ Verified in-game | Per implementation.md |
| SCT has zero references to `CustomUISettingsWindow*` | ✅ | |
| SettingsWindow has zero references to `CustomUI.Settings.SCT` | ✅ Step 2 done | |
| Legacy monolithic SCT Lua (v1) | ✅ Removed — audit [`SCTOverrides.lua`](../Controller/SCTOverrides.lua) / [`SCTHandlers.lua`](../Controller/SCTHandlers.lua) | |
| No file exceeds ~400 lines | ❌ | 5 files over target |
| Per-event SCTLog gated by `m_debug` | ✅ (no per-event log calls exist) | |
| `baseXOffset=0` centers event X on world object | ✅ | |

---

## 12. Summary of Gaps by Priority

### P1 — Fix or document explicitly

*Items 1–2 addressed 2026-04-26; see §13.*

| # | Finding | Location |
| :--- | :--- | :--- |
| 1 | ~~`implementation.md` vs code: pcalls…~~ | §13 |
| 2 | ~~`Activate` / `Deactivate`~~ | Removed |

### P2 — Small correctness gaps

*Items 3–6 addressed 2026-04-26; see §13.*

| # | Finding | Location |
| :--- | :--- | :--- |
| 3 | ~~`Tracker:Destroy` pending queue~~ | §13 |
| 4 | ~~`Shutdown` vs `Disable`~~ | §13 |
| 5 | ~~`CRIT_LANE_OFFSET_X` magic number~~ | §13 |
| 6 | ~~`CritFlashOffsetForCenterPivot` duplicate~~ | §13 |

### P3 — Documentation / cleanup

| # | Finding | Location |
| :--- | :--- | :--- |
| 7 | `implementation.md` §6 incorrectly describes `SCTAnchors.lua` logging as unconditional. Actual code gates it via `m_sctFileLog`. | impl.md §6 |
| 8 | Effect `Apply` signature is `(entry, localT, p, params)` but plan §8.3 spec says `(entry, p, params)`. All callers are consistent; only the spec is wrong. | plan.md §8.3 |
| 9 | `FLOAT_TAIL` (0.60 vs 0.75) and `MIN_DISPLAY_TIME` (3.4 vs 4.0) deviate from plan constants. Already noted in impl.md for FLOAT_TAIL. `MIN_DISPLAY_TIME` change breaks plan's stated rationale ("matches stock") without comment. | SCTAnim.lua:97–98 |
| 10 | Five files exceed their line-count targets. Largest gaps: SCTSettings.lua (+76%), SCTEntry.lua (+82%), SCTHandlers.lua (+91%). | §10 cleanup not complete |
| 11 | `plan.md` should be trimmed or deleted per Step 10. | plan.md |

---

## 13. Follow-up resolution (2026-04-26)

| Priority | Item | Status |
| :--- | :--- | :--- |
| P1 | Plan §10 / impl: `pcall` on engine boundaries + `SctPcallFailed` (always `LogLuaMessage` WARNING; optional TextLog via `m_sctFileLog`) | Done |
| P1 | Remove `Activate` / `Deactivate` | Done |
| P1 | `implementation.md` aligned with code (logging, load order, pcalls) | Done |
| P2 | `EventTracker:Destroy` drains `m_PendingEvents` | Done |
| P2 | `Shutdown` → `Disable()` | Done |
| P2 | `CRIT_LANE_OFFSET_X` in `_SctAnim`, tracker uses it | Done |
| P2 | Single `CritFlashOffsetForCenterPivot` (removed duplicate from `SCTAnchors`) | Done |
| P2 | Ability-icon layout avoids `WindowGetParent` race by using cached label parent (`m_ParentWindow`) | Done |
