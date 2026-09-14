# CODE_QUALITY — CustomUIv3 1.2.1

Report-only review (GrokBot). Issues are the work queue; this file mirrors the summary.

| Field | Value |
| --- | --- |
| Version | **1.2.1** |
| HEAD | `3ea35f6d25f15218d84786abfa38a86590a6473d` |
| Date | 2026-09-14 |
| Prior | 1.2.0 (2026-09-13); H1–H12 closed in #3–#14 |
| Summary Issue | [#19](https://github.com/Talladego/CustomUIv3/issues/19) |

## Verdict

- **Critical:** none
- **High (new):** 4 — #15, #16, #17, #18
- Prior H1–H12: **re-verified fixed** on HEAD (do not re-file)

## Prior H1–H12 re-verify

| ID | Topic | HEAD |
| --- | --- | --- |
| H1 | QoL defaults | QoL off by default; AS/Rezz opt-in |
| H2 | AutoSurrender winning/tie YES | gated in `castVote` / `canStartSurrender` |
| H3 | AutoFPS sticky perfLevel | restore on Disable/Shutdown/session end |
| H4 | UnitFrames HP rebuild | in-place self + party-only status path |
| H5 | partyDirty every build | empty-cache recovery only |
| H6 | TargetInfo hook never restored | `UnhookTargetInfo` on Shutdown |
| H7 | SettingsTabbedScrollLimit | not present as defect in current settings UI |
| H8 | SCT EventText assumption | `_stockWasRegistered` gate |
| H9 | SCT orphan stall | window checks + tracker cap |
| H10 | TargetWindow stock drop | rehook + pending rehook |
| H11 | enable-before-Enable | RegisterComponent nil init only |
| H12 | RezzAccept unconditional | dead + dialog checks |

## New High findings

### #15 PlayerStatusWindow stock rehook / Shutdown

XML `OnShutdown` → `CustomUI.PlayerStatusWindow.Shutdown` does not rehook stock `PlayerWindow` handlers. `RehookStockPlayerWindowHandlers` clears `m_stockPlayerUnhooked` when `PlayerWindow` is missing (no pending retry). Can leave stock HP/AP/effects dead after teardown.

### #16 GroupWindow XML OnShutdown skips stock rehook

Same class as TargetWindow H10: `Disable` rehooks; `CustomUI.GroupWindow.Shutdown` does not.

### #17 AltTracker hook restore stomps later wrappers

Money/tooltip global restores are unconditional; FollowLeader already identity-checks. Disabling AltTracker can break later addon wrappers.

### #18 FollowLeader ActionBars nil crash

`ApplyFollowLeaderActionToMacroSlots` uses `ActionBars:` without the nil guard present in `GetMacroSlots`, while falling back to cached `trackedSlots`.

## Deferred (not High Issues)

- BuffTracker nested pending-removal scans (throttled) — Medium residual
- Megacontroller size (GroupIcons / UnitFrames) — structure debt
- AutoSurrender `ChatSettings.Channels[0]` unguarded — Medium
- `severity:critical` label missing on repo (no Critical findings this pass)

## Labels / publishing notes

Open Issues: summary #19; bugs #15–#18. Docs path requires `!docs/CODE_QUALITY_*.md` (or API push) because `.gitignore` has `**/*.md`.
