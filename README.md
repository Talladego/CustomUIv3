# CustomUI

CustomUI is a modular Return of Reckoning addon that replaces and enhances stock UI components behind a single settings surface and slash-command workflow.

## Deployment

If your tree includes `deploy.ps1` at the repo root, run it in PowerShell:

```powershell
.\deploy.ps1
```

It prompts for the game install folder, defaulting to the path from the Windows registry (`HKCU\Return of Reckoning\Return of Reckoning`), or `C:\Games\Return of Reckoning` if the key is missing, then copies the CustomUI add-on (typically `CustomUI.mod` and `Source/`) into `Interface\AddOns\CustomUI`. Files overwrite in place, so the client can be running.

If you deploy by hand, place both **CustomUI** and **CustomUISettingsWindow** under the game’s `Interface\AddOns\` (sibling folders), each with its own `.mod` and script/XML tree intact.

If PowerShell blocks scripts on first run:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

## What this addon does

- Registers modular components under one addon namespace.
- Lets you enable/disable components at runtime via the settings window (`/cui`) or slash commands.
- Hides the corresponding stock window when a CustomUI replacement is enabled; restores it on disable.
- Provides shared subsystems (buff tracking, unit frames) reused across multiple components.
- Keeps component lifecycle handling (initialize/enable/disable/shutdown) consistent.

## Components

| Component | Replaces | Status |
|---|---|---|
| `PlayerStatusWindow` | `ea_playerstatuswindow` | ✅ Enabled by default |
| `TargetWindow` | `ea_targetwindow` (hostile + friendly slots) | ✅ Implemented |
| `PlayerPetWindow` | `PetHealthWindow` in `ea_careerresourceswindow` | ✅ Implemented |
| `GroupWindow` | `ea_groupwindow` | ✅ Implemented |
| `TargetHUD` | — (new world-attached HUDs for hostile and friendly targets) | ✅ Implemented |
| `UnitFrames` | `ea_groupwindow` warband layout and scenario group frames | 🚧 In progress (adapter pattern not yet integrated) |
| `GroupIcons` | — (career icons on world objects for party / warband / scenario members) | ✅ Implemented |
| `SCT` | `easystem_eventtext` combat/point-gain floating text | ✅ Implemented |

All components default to **disabled** except `PlayerStatusWindow`.

## Settings window

`/cui` and `/customui` call `WindowUtils.ToggleShowing("CustomUISettingsWindowTabbed")` (see
`Source/CustomUI.lua`). The visible UI lives in the separate **CustomUISettingsWindow**
add-on, which must be enabled alongside CustomUI. Tabs are **not** created via
`CustomUI.SettingsWindow.RegisterTab` at runtime: that broker and its
`Source/Settings/View/SettingsWindow.xml` shell are **legacy** (commented out in
`CustomUI.mod`); the active UI is a fixed tab strip in
`CustomUISettingsWindowTabbed.lua` / `.xml` plus one `CustomUISettingsWindowTab<Name>.*`
pair per feature.

Each per-tab script binds controls to the matching component’s public APIs (for
example `CustomUI.IsComponentEnabled`, `CustomUI.PlayerStatusWindow.GetSettings()`).
The footer **Apply / Reset / Cancel** handlers in `CustomUISettingsWindowTabbed` call
into the selected tab class (`UpdateSettings`, `ApplyCurrent`, `ResetSettings`, etc.)
where implemented.

Tab layout, `SWTab<Name>Contents*` naming, and the XML section-stacking rules are in
`CustomUISettingsWindow/README.md`. `plan.md` still describes the older
`RegisterTab` pattern for historical context only.


## Shared subsystems

### CustomUI.BuffTracker

A `BuffTracker` subclass that extends the stock frame with:

- **Buff grouping** (`SetBuffGroups`) — collapses multiple ability IDs (e.g. all variants of Nature's Theft) into a single icon using the stable `abilityId` key.
- **Sort modes** (`SetSortMode`) — `PERM_LONG_SHORT` sorts permanent buffs first, then by descending duration.
- **Compression** (`CompressBuffData`) — merges multiple instances of the same logical ability into one icon (including different casters); sums `stackCount` correctly so two casters each with ×3 stacks show as ×6. Groups by `abilityId` when present, else by `effectIndex`. Distinct from **buff grouping** (`SetBuffGroups`), which collapses configured `abilityId` variants (e.g. stat lines) into one icon.
- **Stack display** — shows `xN` on the timer label when `stackCount > 1`; falls back to duration when the count drops to 1 (never shows ×1).
- **Filter** (`SetFilter`) — category (buff/debuff/neutral), duration bucket (short/long/permanent), and caster (`playerCastOnly`) gates. Pass `nil` to show everything.
- **Blacklist / Whitelist** — `Blacklist.lua` and `Whitelist.lua` filter buffs by `effectIndex`; blacklist removes unconditionally, whitelist adds back what the filter removed. Conflicted IDs cancel both rules and fall back to the filter result.

### CustomUI.TargetFrame

A `TargetUnitFrame` subclass used by `TargetWindow` for both hostile and friendly targets. Inherits all stock health-bar, portrait, and `UpdateUnit` logic; adds a `CustomUI.BuffTracker` instance for per-target buff display.

### BuffGroups.lua

Defines named groups of `abilityId` values to collapse into one icon. Current groups:

- `NaturesTheft` — abilityIds 3687–3693 (all variants, verified in-game)
- `BrutesTheft` — abilityIds 3232–3238 (unverified, needs Black Orc target)

## Current architecture

CustomUI uses a namespace-first, controller/view split pattern.

### Namespace pattern

- Root addon namespace: `CustomUI`
- Component namespaces: `CustomUI.PlayerStatusWindow`, `CustomUI.TargetWindow`, etc.

This avoids global table pollution and makes ownership explicit.

### Separation pattern

Each component uses:

- `Controller/` — state, lifecycle, event registration, business logic, and the component adapter (`Enable`/`Disable`/`Shutdown`).
- `View/` — rendering helpers, tooltip/text formatting, and input forwarding handlers. Only present when there is meaningful view-layer code (e.g. `PlayerStatusWindow`). Controller-only components that delegate all rendering to stock frame APIs do not need a View lua file.
- `View/*.xml` — window definitions and XML event bindings to namespaced Lua functions.

### Window visibility contract

- `LayoutEditor.UserHide(windowName)` is called immediately after `RegisterWindow` in every `Initialize()` so windows start hidden regardless of component state.
- `Enable()` calls `LayoutEditor.UserShow`.
- `Disable()` calls `LayoutEditor.UserHide`.
- The corresponding stock window is hidden via `LayoutEditor.UserHide` on `Enable` and restored via `LayoutEditor.UserShow` on `Disable`.

### Folder layout

```text
CustomUI/
	CustomUI.mod
	README.md
	issues.md
	plan.md
	CustomUISettingsWindow/   ← separate UiMod; tab XML/Lua, own README
		CustomUISettingsWindow.mod
		source/ …
	Source/
		CustomUI.lua
		Shared/
			BuffTracker/
				BuffTracker.lua
				BuffGroups.lua
				Blacklist.lua
				Whitelist.lua
			UnitFrame/
				TargetFrame.lua
		Settings/
			Controller/
				SettingsWindowController.lua
				MiniSettingsWindowController.lua
			View/
				SettingsWindow.xml
				MiniSettingsWindow.lua
				MiniSettingsWindow.xml
		Components/
			PlayerStatusWindow/
				Controller/
					PlayerStatusWindowController.lua
				View/
					PlayerStatusWindow.lua        ← view lua (tooltips, label helpers)
					PlayerStatusWindow.xml
					PlayerStatusWindowTab.xml
			TargetWindow/
				Controller/
					TargetWindowController.lua
				View/
					TargetWindow.xml
					TargetWindowTab.xml
			PlayerPetWindow/
				Controller/
					PlayerPetWindowController.lua
				View/
					PlayerPetWindow.xml
					PlayerPetWindowTab.xml
			GroupWindow/
				Controller/
					GroupWindowController.lua
					GroupWindowTestHarness.lua    ← dev test harness, gated at runtime
				View/
					GroupWindow.xml
					GroupWindowTab.xml
			GroupIcons/
				Controller/
					GroupIconsController.lua
				View/
					GroupIcons.xml
					GroupIconsTab.xml
			TargetHUD/
				Controller/
					TargetHUDController.lua
				View/
					TargetHUD.xml
					TargetHUDTab.xml
			UnitFrames/
				Controller/
					UnitFramesController.lua
					UnitFramesModel.lua           ← library (not yet integrated)
					UnitFramesEvents.lua          ← library (not yet integrated)
					UnitFramesRenderer.lua        ← library (not yet integrated)
					Adapters/
						WarbandAdapter.lua        ← stub for planned adapter pattern
						ScenarioFloatingAdapter.lua
				View/
					UnitFrames.xml
					UnitFramesTab.xml
			SCT/
				Controller/
					SCTSettings.lua               ← settings helpers, GetSettings(), color/size/filter keys
					SCTEventText.lua              ← EA_System_EventEntry/PointGainEntry/EventTracker/EventText overrides
					SCTController.lua             ← component adapter only (no settings-window bindings)
				View/
					SCT.xml                       ← anchor/container window definitions
					(SCT settings grid lives in the CustomUISettingsWindow addon, not in CustomUI.)
```

## Design rules for new components

1. Create a namespaced table under `CustomUI` (e.g. `CustomUI.ExampleComponent`).
2. Put mutable state and runtime logic in `Controller/`.
3. Only add a View lua file when there is real view-layer code (tooltips, label updates). Omit it when all rendering is delegated to stock frame APIs.
4. Bind XML event handlers to namespaced functions (e.g. `CustomUI.ExampleComponent.Initialize`).
5. Call `LayoutEditor.UserHide(windowName)` immediately after `RegisterWindow` in `Initialize()`.
6. Register the component adapter from the controller file via `CustomUI.RegisterComponent`.
7. In `Enable`: `UserShow` the CustomUI window, `UserHide` the stock window.
8. In `Disable`: `UserHide` the CustomUI window, `UserShow` (and if needed `UnregisterWindow`) the stock window.
9. Keep manifest load order explicit in `CustomUI.mod`: core shared files first, then each component's controller then xml.
10. Settings UI: use the separate **CustomUISettingsWindow** addon for tabs and handlers; components expose data via `GetSettings()`-style APIs (see SCT: `GetSettingsRowDescriptors`, `SliderPosToScale`). Legacy in-addon `RegisterTab` + `*Tab.xml` is optional/remnant only.

## Runtime usage

- Open settings: `/customui` or `/cui`
- Status output: `/customui status`
- List components: `/customui components`
- Enable component: `/customui enable <name>`
- Disable component: `/customui disable <name>`
- Toggle component: `/customui toggle <name>`
- UnitFrames scenario-mode debug log: `/customui ufdebug <on|off|status>`
- Help: `/customui help`

## Notes

- XML and Lua files should be saved without BOM to avoid parser errors in RoR's Lua loader.
- Window names in XML (e.g. `CustomUIGroupWindow`) are widget IDs and remain stable even if Lua namespaces are refactored.
- `buffData.abilityId` is the stable server ability ID and is the correct key for buff grouping. `buffData.effectIndex` is a dynamic per-cast slot that changes every cast and must not be used as a grouping key.
- **Anchor convention (easy to get backwards):** `Point` is the anchor point on the *target* window (the one you are anchoring *to*). `RelativePoint` is the point on the *element being anchored*. So `WindowAddAnchor(name, "bottom", target, "top", x, y)` means: attach the `bottom` of `target` to the `top` of `name`. In XML, `point` and `relativePoint` follow the same convention.
- **Lua `local function` order:** a local helper is only visible to code *below* it in the file. Callers that appear earlier must use a forward declaration (`local Foo` then `function Foo() end`) or the helper must be moved above. Otherwise calls resolve to a missing global (`nil` function) at runtime. See `CustomUISettingsWindow/README.md` §6.

## SCT component details

The SCT component cannot follow the standard window-visibility contract because the engine dispatches floating text by calling named global functions (`EA_System_EventText.AddCombatEventText` etc.) rather than through a window show/hide mechanism.

### Architecture

`SCTEventText.lua` permanently replaces four stock dispatch functions and two stock frame classes at load time:

- `EA_System_EventEntry` and `EA_System_PointGainEntry` — replaced with CustomUI subclasses that support custom scale, color, and crit animation.
- `EA_System_EventText.AddCombatEventText`, `AddXpText`, `AddRenownText`, `AddInfluenceText` — replaced with wrapper functions that fall through to `_stock.*` originals when `m_active` is false.

The stock functions are saved in a module-local `_stock` table before being overwritten, so when SCT is disabled the stock dispatch is fully restored for the four handlers. The class replacements are permanent.

### Enable / disable

- **Enabled** (`m_active = true`): wrappers intercept all events, apply filter/size/color settings, run crit animation.
- **Disabled** (`m_active = false`): wrappers forward to `_stock.*` unchanged; `EA_System_EventEntry:SetupText` uses stock defaults (no custom scale/color/animation).

`Activate()` is called from `EA_System_EventText.Initialize()` (run by the engine's `<OnInitialize>`) but only sets `m_active = true` when `CustomUI.IsComponentEnabled("SCT")` returns true, so the component respects the saved enabled state from the first frame.

### Settings

Settings live in `CustomUI.Settings.SCT` (never in `EA_ScrollingCombatText_Settings`). Per-type rows in the settings tab control:

- **Show** — filter checkbox; hides that event type entirely.
- **Size** — 5-step slider mapped to `{ 0.75, 0.875, 1.0, 1.25, 1.75 }` scale factors.
- **Color** — preset palette combo; index 1 = engine default (no override), indices 2–8 are fixed RGB presets.

The tab uses an `m_refreshing` guard to prevent `OnSelChanged` / `OnSlide` / `OnLButtonUp` events fired during `RefreshControls` from overwriting saved settings.

## PlayerPetWindow stock suppression details

### Problem observed

When `PlayerPetWindow` was enabled, stock `PetHealthWindow` could still reappear on pet summon/update even after `LayoutEditor.UserHide`.

### Root cause

Stock `PetWindow:UpdatePet()` — triggered via `PetWindow.UpdatePetProxy` — calls `FadeInComponent(self.m_UnitFrame)`, which force-shows the stock pet health frame. This bypasses LayoutEditor hidden state.

### Final solution (reversible)

`CustomUI.PlayerPetWindow` wraps `PetWindow.UpdatePetProxy` with a thin hook that calls the original and then forces `PetHealthWindow` hidden again:

- The wrapper is installed on `Enable` and restored on `Disable` / `Shutdown`, so it does not affect stock behavior while the component is disabled.
- `Enable` also hides `PetHealthWindow` immediately via `LayoutEditor.UserHide` and `WindowSetShowing`.
- `Disable` restores the wrapper, re-shows `PetHealthWindow`, and unregisters it from `LayoutEditor`.
- The saved original is stored at module scope and re-wrap is guarded, so repeated enable/disable cycles don't produce wrapper-of-wrapper corruption.

This preserves normal stock takeover behavior when the CustomUI component is disabled, without destroying stock windows.
