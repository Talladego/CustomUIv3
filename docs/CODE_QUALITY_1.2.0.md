# CustomUI Code Quality Report

**Scope:** read-only review of `/workspace` (CustomUI + CustomUISettingsWindow). No application code was changed and no fix PR was opened.

## Version

| Addon | Version | Location |
|---|---|---|
| **CustomUI** | **`1.2.0`** | `CustomUI.mod` (`<UiMod … version="1.2.0">`), `Source/CustomUI.lua` (`CustomUI.Version = "1.2.0"`) |
| **CustomUISettingsWindow** | **`1.3.0`** | `CustomUISettingsWindow/CustomUISettingsWindow.mod` |
| Settings blob | written as `CustomUI.Settings.version = CustomUI.Version` on init | `Source/CustomUI.lua` |

Companion settings addon is one minor version ahead of the core addon. Dates on both `.mod` files are `2026-08-22`.

---

## Overall verdict

This is a large, modular RoR UI replacement (~34k lines of Lua) with a real architecture: component register/enable/disable, stock-window hide/restore, and shared buff/target systems. The quality bar is uneven.

**Strengths:** explicit lifecycle on most components, `pcall` wrappers on risky hooks, stock-replace tracking that respects LayoutEditor user-hide, and a documented split between CustomUI and the settings addon.

**Weaknesses:** several **gameplay-affecting defaults and vote/rez automations**, **permanent client-setting writes**, **global hooks that are not always restored**, and a few **hot-path rebuild storms**. Two controllers (`GroupIconsController.lua` ~2975 lines, `UnitFramesController.lua` ~2741 lines) concentrate too much state. Settings UI has a dangerous stock-template override and version/doc drift.

This is **not production-clean**. It is usable as a feature-complete addon, but I would not treat the current tree as safe-to-ship without fixing the High items below, especially QoL defaults, AutoSurrender vote rules, AutoFPS persistence, and UnitFrames refresh cost.

---

## Top fixes (priority order)

1. **Turn QoL off by default, and default AutoSurrender / RezzAccept to off.** Fresh profiles currently enable the QoL component *and* every sub-feature. README says the opposite.
2. **Make AutoSurrender vote YES use the same “not winning” gate as vote-start** (`isTeamWinning()` / strictly behind). Kill-lead must not YES-vote a winning/tied team.
3. **Stop writing AutoFPS changes into `SystemData.Settings.Performance.perfLevel` without a crash-safe restore.** Snapshot the user’s level and restore on disable, shutdown, and logout.
4. **Stop routing `GROUP_STATUS_UPDATED` through a full `ApplyModeVisibility()` rebuild** in UnitFrames; update HP/AP in place. Stop forcing `GameData.Party.partyDirty = true` on every party build.
5. **Restore global hooks on disable/shutdown** (`TargetInfo.UpdateFromClient`, `BuffFrame.OnMouseOver*`, `ScenarioSummaryWindow.OnHidden`, SCT engine handlers). Call the saved original, or don’t replace it.
6. **Delete or rename the `EA_Window_SettingsTabbedScrollLimit` override** in the Group settings tab (missing `OnScrollLimitSelect`).
7. **Harden SCT event dispatch** so an orphaned window cannot stall a tracker forever; destroy-or-reuse if `DoesWindowExist(newName)` is true but the frame is not in `m_DisplayedEvents`.

---

## Critical

None that are guaranteed crashes or data-corruption on every load. The worst issues are High: they change combat/scenario behavior or persist client settings.

I considered rating QoL-defaults + AutoSurrender as Critical (fresh install can auto-surrender and auto-accept rezzes). They are **High** because they are gated on the QoL component remaining enabled; they are still the first things to fix.

---

## High

### H1. QoL is default-on; every sub-feature is default-on (docs are wrong)

**Files:** `Source/Components/QoL/Controller/QoLController.lua`

- Component: `DefaultEnabled = true` (line 236).
- Defaults: RedAlert, AutoSurrender (`useKillRule = true`), RezzAccept, AltTracker all `enabled = true` (lines 10–32).
- README claims QoL is `DefaultEnabled = false` and that only GroupIcons comes up enabled.

A new profile therefore starts AutoSurrender, auto-rez, low-HP flash, and backpack/tooltip hooks without an opt-in. Settings Apply also **re-enables** the QoL component if it was off (`CustomUISettingsWindow/source/CustomUISettingsWindowTabQoL.lua`, `ApplyCurrent`).

GroupIcons omitting `DefaultEnabled` is intentional (omit ⇒ enabled via `DefaultEnabled ~= false` in `Source/CustomUI.lua`). QoL being on is not documented and is much more dangerous.

### H2. AutoSurrender can vote YES while the team is winning or tied

**File:** `Source/Components/QoL/Controller/QoLAutoSurrender.lua`

- `canStartSurrender()` refuses when `isTeamWinning()` (score `>=`).
- `castVote()` only checks `isLosingEnough()`, which is true if **either** score deficit **or** kill-lead (`orderMaxKills < destroMaxKills`).

So a teammate-started vote can get an automatic `.yes` because one enemy has more kills, even when your team is ahead on points. README says the kill-leader rule cannot start a vote while tied/ahead; voting is not held to that rule.

Related: `shouldSendSurrender()` sends `.surrender` when `needsTimerProbe` is true with **no score check**. `OnScenarioEnd` clears `inScenario`, then `OnUpdate` immediately calls `onEnterScenario()` if `GameData.Player.isInScenario` is still true (post-mode scoreboard churn).

### H3. AutoFPS permanently writes the user’s Video / Performance profile

**File:** `Source/Components/AutoFPS/Controller/AutoFPSController.lua`

`ApplyLevel` assigns `SystemData.Settings.Performance.perfLevel` and broadcasts `USER_SETTINGS_CHANGED` (lines 253–287). That is the live UserSettings.xml graphics preset, not a CustomUI-only copy.

- Crash, kill, or logout while downshifted leaves the lowered preset.
- `AutoFPSComponent:Shutdown` does **not** restore `manualPerfLevel`; only `Disable` does. Normal `CustomUI.ShutdownComponents` calls Disable first, so reload is OK; abnormal unload is not.
- Enable-time `AdoptOrRestorePreferred` will also rewrite graphics if the live level disagrees with the saved preferred.

### H4. UnitFrames treats HP ticks as a full roster rebuild

**File:** `Source/Components/UnitFrames/Controller/UnitFramesController.lua`

`GROUP_STATUS_UPDATED` is bound to `UnitFrames.OnVisibilityStateChanged` (line 2517), which always calls `ApplyModeVisibility()` (lines 2179–2184, 2021–2066). That hides/shows every custom and stock group window and rebuilds the active mode.

`GROUP_STATUS_UPDATED` is the party HP/AP heartbeat. In a 6×6 warband this is a combat-frame tax far above an incremental bar update. Scenario hits already have `RefreshScenarioMemberFromHits`; status updates do not use it.

### H5. UnitFrames forces `partyDirty` on every party build

**Files:** `Source/Components/UnitFrames/Controller/UnitFramesWarband.lua` (`BuildPartyGroupData`, ~110–112), `Source/Components/UnitFrames/Controller/UnitFramesController.lua` (~1871–1873)

GroupIcons comments in the same addon warn **not** to set `partyDirty` because it wipes PartyUtils-hydrated `worldObjNum` after `/reloadui`. UnitFrames does it on every build, including paths driven by visibility/status updates.

`ApplyModeVisibility` also always nils `m_warbandPartyOnlyDataPartyIndex` before rebuild. If `ShowWarbandParty1DualModeWindows` returns early, later self HP/AP updates can query warband party 1 instead of the player’s real party.

### H6. `TargetInfo.UpdateFromClient` is replaced and never restored

**File:** `Source/CustomUI.lua` — `HookTargetInfo` (1194–1220), `CustomUI.Shutdown` (1255–1265)

- Stock function is saved in `originalUpdateFromClient` but **never called** and **never restored**.
- Re-init bails because `originalUpdateFromClient` is already set.
- Per-frame `TargetUpdateFlag` drops a second `UpdateFromClient` in the same tick (no batch, no `TargetPresence.OnCacheBatch`).

This is a process-wide patch for every consumer of `TargetInfo` (stock UI and other addons).

### H7. Settings tab redefines a **stock** template with a missing handler

**File:** `CustomUISettingsWindow/source/CustomUISettingsWindowTabGroup.xml` (lines 8–14)

The tab reopens `EA_Window_SettingsTabbedScrollLimit` and points `OnLButtonUp` at `CustomUISettingsWindowTabGroup.OnScrollLimitSelect`. That function **does not exist** in `CustomUISettingsWindowTabGroup.lua`.

Because the name is a stock EA template, this can break scroll-limit clicks in the **game’s** settings window, not only CustomUI.

### H8. SCT always assumes stock EventText handlers were registered

**File:** `Source/Components/SCT/Controller/SCTHandlers.lua` — `InstallHandlers` / `RestoreHandlers` (115–146)

Install unregisters `EA_System_EventText.*` and sets `_stockWasRegistered[id] = true` for every event without checking. Restore always re-registers stock. If another addon owned those handlers, or install failed halfway, disable can double-register stock or leave CustomUI’s handlers in a bad state.

### H9. SCT tracker can stall forever on an orphaned window name

**File:** `Source/Components/SCT/Controller/SCTEventTracker.lua` — `Update` (120–170)

Pending combat/point events are popped only when `DoesWindowExist(newName)` is false. If that name exists but is not in `m_DisplayedEvents` (failed create, leaked destroy, `/reloadui` residue), the queue never drains.

### H10. TargetWindow disable can drop stock handlers if the stock window is gone

**File:** `Source/Components/TargetWindow/Controller/TargetWindowController.lua` — `TryRehookStockTargetHandlers` (311–326)

If `m_stockTargetUnhooked` and `TargetWindow` does not exist, the flag is cleared **without** re-registering stock. Later, stock never gets `PLAYER_TARGET_UPDATED` / combat / effects until a full UI reload.

`CustomUI.TargetWindow.Shutdown` also does not rehook or `ShowStockTargetWindows()`. Normal addon shutdown calls Disable first; XML `OnShutdown` does not.

### H11. Target / TargetHUD settings write enable-state before `EnableComponent`

**Files:**  
`CustomUISettingsWindow/source/CustomUISettingsWindowTabTarget.lua` (`ApplyCurrent` 84–92)  
`CustomUISettingsWindow/source/CustomUISettingsWindowTabTargetHUD.lua` (same pattern)

They set `CustomUI.Settings.Components.* = enabled` then call Enable/Disable. If enable fails, saved state says on and runtime stays off. Other tabs use `SetComponentEnabled`, which only writes after success.

### H12. RezzAccept is unconditional (worse because of H1)

**File:** `Source/Components/QoL/Controller/QoLRezzAccept.lua`

Any two-button dialog whose buttons include `RESURRECTION_ACCEPT` or `RESURRECTION_DECLINE` immediately `BroadcastEvent(RESURRECTION_ACCEPT)`. No death check, delay, rezzer, or location filter. Fine as an explicit opt-in; unsafe as a default.

---

## Medium

### Bugs / logic

| ID | Where | Issue |
|---|---|---|
| M1 | `Source/Shared/TargetPresence.lua` `OnCacheBatch` | Empty/`entityid==0` batch rows call `ForceClearSlot` immediately, skipping hold/snapshot. Conflicts with the flicker-avoidance comment on the TargetInfo hook. `emptyStreak` is barely used (incremented only on enable-time sync). Unreachable `else` in `OnTargetRefreshComplete`. |
| M2 | `Source/CustomUI.lua` Follow Leader | `BuildFollowLeaderMacroText` ignores `leaderName` and always returns `/follow`. Click hook then `SendChatText(L"/follow ", L"")` after stock click — empty `/follow` is “current target,” not necessarily the leader. `ApplyFollowLeaderActionToMacroSlots` calls `ActionBars:BarAndButtonIdFromSlot` with no nil guard. |
| M3 | `Source/CustomUI.lua` `ResetAllToDefaults` | Reset uses `DefaultEnabled == true`; register uses `~= false`. Today only GroupIcons relies on omit-means-true, so reset still works for it after normalize — the two rules can diverge for any future omit. |
| M4 | `Source/Shared/BuffTracker/BuffTracker.lua` | Replaces global `BuffFrame.OnMouseOver` / `OnMouseOverEnd` at load; never restored. Affects every buff frame in the client. |
| M5 | `Source/Components/GroupIcons/Controller/GroupIconsScenarioStats.lua` | `ScenarioSummaryWindow.OnHidden` is wrapped once and never restored on Disable (`ScenarioStats.Stop` only). |
| M6 | `Source/Components/PlayerStatusWindow/Controller/PlayerPetWindowController.lua` | Full `CustomUI.PlayerPetWindow.Shutdown` (unregister + destroy) is defined at 139–150, then **overwritten** at 253 with a stub that only restores the pet hook. Pet events registered in `Initialize` are not torn down by the public Shutdown. PlayerPet is not a registered component. |
| M7 | `Source/Components/SCT/Controller/SCTEventEntry.lua` `SetupText` | Default color index 1 leaves `m_TargetR/G/B` nil; crit `ColorFlash` falls back to white — flash is invisible on default-colored text. |
| M8 | `Source/Components/SCT/Controller/SCTSettings.lua` | Full reset writes `stripCombatAmountSign = false`; normalizer forces it back to `true`. Size reset vs `IsAtDefault()` also disagree. |
| M9 | `Source/Components/KillTracker/Controller/KillTrackerParser.lua` | Names are `[%a]+` only. Hyphenated / accented / multi-word names fail or fall through to a names-only parse with empty ability/zone. |
| M10 | `Source/Components/KillTracker/Controller/KillTrackerCapture.lua` | Always reads Combat log index `num-1` on any RVR ADDED event; concurrent lines can attach the wrong message. |
| M11 | `Source/Components/UnitFrames/Controller/UnitFramesController.lua` | `OnMenuClickSetBackgroundOpacity` wrapper both branches call stock identically — CustomUI member rows never pick up the menu opacity (slider path does). |
| M12 | `Source/Components/UnitFrames/Controller/UnitFramesArchetypes.lua` | `ClearArchtypeCache` is never called; alt-spec tints can persist across scenarios. RoR `Packet` hook skips `IngestGrpStatsPacket`. |
| M13 | `Source/Components/TargetHUD/Controller/TargetHUDController.lua` | Disable uses spatial squash (`WindowSetScale(…, 0.000001)`) and **does not** `DetachWindowFromWorldObject`. Comment says this matches GroupIcons; leftover binds can still fight other world-attach UIs. |
| M14 | `Source/Shared/PortraitInfluenceTrack.lua` | Partial `RegisterEvents` still sets `_eventsRegistered = true`, so failed handlers are never retried. |
| M15 | `Source/Shared/StockProgressBars.lua` | Influence-bar hooks install only when the PQ tracker already exists; late load leaves the stock influence bar visible. |
| M16 | `Source/Components/QoL/Controller/QoLAltTracker.lua` + `QoLAltTrackerTooltips.lua` | Global patches of `Player.UpdateMoney`, `EA_Window_Backpack.UpdateMoney`, `Tooltips.CreateItemTooltip`, `Tooltips.ClearTooltip` — restore is order-dependent vs other addons. |
| M17 | Settings tabs UnitFrames / GroupIcons | `Ensure*Settings()` mutates `CustomUI.Settings` at tab `Initialize` (write-through before Apply). |
| M18 | `CustomUISettingsWindow/source/` vs `.mod` `Source/` | Manifest and every `<Script file="Source/…">` use uppercase `Source/`; on-disk folder is `source/`. Fine on Windows/WAR; broken on case-sensitive packaging or CI. |

### Structure

| ID | Where | Issue |
|---|---|---|
| M19 | `GroupIconsController.lua` (~2975), `UnitFramesController.lua` (~2741), `BuffTracker.lua` (~1602), `PortraitInfluenceTrack.lua` (~1726), `CustomUISettingsWindowTabSCT.lua` (~1395) | God-files. GroupIcons/UnitFrames still hold roster, world-attach, events, and settings after a partial split. Hard to test and easy to regress. |
| M20 | Dual teardown | XML `OnShutdown` vs `CustomUI.ShutdownComponents` (Disable then Shutdown). Several components implement different work in each path (PlayerStatus, TargetWindow, PlayerPet, AutoFPS, UnitFrames). |
| M21 | Global hook style | TargetInfo, ActionButton, BuffFrame, EventText, ScenarioSummary, money/tooltip, PQ influence — no shared hook registry, inconsistent restore. |
| M22 | Settings vs core versions | Settings `1.3.0` vs CustomUI `1.2.0`. README/settings README still describe 8 tabs / 1040×800; UI is 10 tabs / 1300×800. Root `TODO.md` and `CustomUISettingsWindow/TODO.md` are referenced and missing. |
| M23 | SCT constants | `XP_GAIN = 1` aliases `COMBAT_EVENT`; `RENOWN_GAIN = 2` aliases `POINT_GAIN` (`SCTOverrides.lua`). Works only because of check order. |
| M24 | Settings layout | Heavy `$parent<Sibling>` anchors (documented as unreliable). Tab strip is 10×124px vs 1250px button row — last tab can clip. |

### Performance

| ID | Where | Issue |
|---|---|---|
| M25 | BuffTracker `UpdateBuffs` / grace purge | Nested `pairs` over `m_buffData` per incoming buff (O(n²) on busy targets). |
| M26 | BuffTracker `Update` | Scale + visibility walk every tick per tracker (cached writes, but owner-chain walk remains). |
| M27 | UnitFrames archetypes | `FindScenarioArchtype` / scoreboard scans are O(n) per member per paint. |
| M28 | GroupIcons | Post-enable warm refresh: up to 30 full `RefreshAll` passes (~0.35s). OnUpdate driver plus ~5 Hz outsider probe is acceptable; the warm storm is not. |
| M29 | GroupWindow `Update` | 0.25s poll refreshes all five members even when the roster signature is unchanged. |
| M30 | SCT settings tab | `OnUpdate` on the shown tab (`OnUpdateDebugPointer`) for hover tooltips every frame. |
| M31 | `TargetPresence.OnGlobalUpdate` | `ipairs({ hostile, friendly })` allocates a new table every tick. TargetPresence/TargetHUD global ticks run even when those components are disabled. |
| M32 | SCT resolver | Session maps (`_abilityTableNameIndex`, miss logs, etc.) never evict. |
| M33 | SCT throttle | Overflow drops oldest events silently. |

---

## Low

- **Follow-leader handlers** register on every addon init (`CustomUI.Initialize`), even if unused.
- **`NormalizePlayerName`** / KillTracker `NormalizeNameKey`: `string.find(n, "^", 1, true)` is a literal caret strip (OK for WAR names, easy to misread).
- **KillTracker** disable resets session bags; LayoutEditor edit callback is never unregistered.
- **RedAlert** uses strict `<` threshold; exact 50% does not flash. Rapid ticks retrigger flash while still below.
- **AltTracker** `DB_VERSION` unused; bank open zeroes counts before rescan; day math assumes 31-day months.
- **SCT** `EventEntry:Destroy` may skip `FrameManager` cleanup; `CopyBuffData` in BuffTracker is unused.
- **Player tab** README mentions a pet toggle that does not exist; KillTracker Apply forces `replaceChatKills = false`.
- **Orphan settings assets:** `templates_settingswindowtabbed.xml` not in `.mod`; textures XML commented out; per-tab `ResetSettings()` never called (footer Reset uses baseline restore — correct, but the API is dead).
- **UnitFrames** `ShutdownWindow` is empty; scenario map cache is invalidated every OnUpdate.
- **DefaultEnabled** for GroupIcons is implicit; QoL is explicit `true` — two different conventions in one register function.

---

## What I would not treat as bugs

- SCT incoming **round-robin across Heal/Damage/Mit lanes** (`SCTHandlers.lua` ~319–339) is documented as left/center/right fan-out. Events still carry amount/type; this is overlap control, not heal-as-damage routing.
- WAR `EditBox` + `TextEditBoxGetText` / `TextEditBoxSetText` on the QoL prune-days field is stock API, not a mismatch.
- Tab Lua files not listed in `CustomUISettingsWindow.mod` is normal: XML `<Script>` loads them.
- TargetHUD spatial-hide-on-disable is an explicit GroupIcons-style choice, not an accidental leak (still a coupling risk — see M13).

---

## Architecture snapshot

```
CustomUI 1.2.0
  Source/CustomUI.lua          core: register, slash, TargetInfo hook, follow macro
  Source/Shared/               BuffTracker, TargetPresence, badges, TargetFrame
  Source/Components/*/         Controller + View per feature
CustomUISettingsWindow 1.3.0   separate addon; /cui → CustomUISettingsWindowTabbed
```

Components: PlayerStatusWindow, TargetWindow, GroupWindow, TargetHUD, UnitFrames, GroupIcons, SCT, KillTracker, AutoFPS, QoL. PlayerPetWindow is a helper owned by PlayerStatus, not a `/customui` component.

---

## Suggested fix sequence (no code in this pass)

1. Defaults + AutoSurrender + RezzAccept (H1, H2, H12) — gameplay.
2. AutoFPS restore/snapshot (H3) — user settings integrity.
3. UnitFrames status path + `partyDirty` (H4, H5) — combat performance / roster attach.
4. Hook restore registry (H6, H8, M4, M5) — disable/reload safety.
5. Settings template + ApplyCurrent (H7, H11) — stock UI + saved-state correctness.
6. SCT stall + crit flash (H9, M7) — combat text reliability.
