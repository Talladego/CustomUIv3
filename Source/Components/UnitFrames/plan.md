## UnitFrames — stock-extension review plan

### Why this plan exists

`Controller/UnitFramesController.lua` currently replaces stock functions on `BattlegroupHUD`:

- `BattlegroupHUD.OnMenuClickSetBackgroundOpacity`
- `BattlegroupHUD.OnOpacitySlide`

It stores originals and restores them in `UnitFrames.Shutdown()`, but the override is installed during `UnitFrames.Initialize()` (not tied to component enable/disable). That means **stock behavior can be modified even when the component is disabled**, which can affect other addons that hook or call these stock functions.

### Goal

Keep stock `BattlegroupHUD` functions **untouched while UnitFrames is disabled**, while preserving:

- the context-menu opacity slider working for CustomUI unit frame windows,
- stock behavior for stock windows,
- clean restore on disable/reload.

### Planned refactor

#### 1) Install BattlegroupHUD hooks only while enabled

- Move the hook installation blocks (currently in `UnitFrames.Initialize()`) into `UnitFrames.Enable()`.
- Restore originals in `UnitFrames.Disable()` (and keep a defensive restore in `UnitFrames.Shutdown()`).

This makes the component symmetric:

- **Enable**: install hooks, show/hide stock windows appropriately.
- **Disable**: restore hooks, show stock windows.

#### 2) Make hook install/restore idempotent

- Guard installation by `m_stockOnMenuClickSetBackgroundOpacity == nil` / `m_stockOnOpacitySlide == nil`.
- Guard restore similarly and always nil out after restoration.

#### 3) Keep behavior routing identical

Keep current routing logic:

- If context menu was opened from a CustomUI member window → update CustomUI alpha.
- Otherwise → delegate to stock handlers.

#### 4) Regression checklist

- **Disabled**: BattlegroupHUD opacity context menu behaves exactly stock; no CustomUI interception.
- **Enabled**: opacity context menu works when opened from CustomUI windows; stock still works elsewhere.
- Toggle enabled/disabled repeatedly without leaving hooks installed.

