# CustomUI

CustomUI is a modular Return of Reckoning addon that replaces and enhances stock UI components behind a single settings surface and slash-command workflow.

## Documentation

- **`README.md`**: architecture overview, component list, and contributor-facing conventions.
- **`issues.md`**: code quality backlog (bugs, tech debt, and audit notes; keep items here until resolved).
- **`plan.md`**: historical implementation plan notes (some sections reflect older patterns; treat as reference, not the current source of truth).
- **`CustomUISettingsWindow/README.md`**: developer notes for the **separate** settings UI addon (tab layout + XML anchoring pitfalls + diagnostics).
- **Component refactor plans** (scoped follow-ups):
  - **`Source/Components/SCT/plan.md`**: historical notes from the v2 SCT migration (handler swap + stock subclasses); v2 is **complete** — runtime lives in `SCTOverrides.lua` / `SCTHandlers.lua`.
  - **`Source/Components/PlayerStatusWindow/plan.md`**: PlayerPetWindow stock-hook lifecycle tightening.
  - **`Source/Components/UnitFrames/plan.md`**: BattlegroupHUD stock-hook lifecycle tightening (**next open component work** — see Components table).

## Installation

Place **CustomUI** and **CustomUISettingsWindow** under the game’s `Interface\AddOns\` as sibling folders, each with its own `.mod` and full script/XML tree (overwrite files to update; `/reloadui` in the client picks up changes).

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
| `SCT` | `easystem_eventtext` combat/point-gain floating text | ✅ **Complete** (v2: handler swap + `SCTOverrides`; settings tab in CustomUISettingsWindow) |

All components default to **disabled** except `PlayerStatusWindow`. **Next engineering focus:** `UnitFrames` (adapter integration — still 🚧 in the table above).

## Settings window

`/cui` and `/customui` call `WindowUtils.ToggleShowing("CustomUISettingsWindowTabbed")` (see
`Source/CustomUI.lua`). The visible UI lives in the separate **CustomUISettingsWindow**
add-on, which must be enabled alongside CustomUI. Tabs are **not** created via
`CustomUI.SettingsWindow.RegisterTab` at runtime: that broker and its
`Source/Settings/` shell were removed; the active UI is a fixed tab strip in
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

**Load order (important):** `CustomUI.mod` lists each component’s `Controller/*.lua` **before** that component’s `View/*.xml` so the `CustomUI.<Name>.*` API exists when the template is parsed. **Do not** add a second `<Script file="...Controller/...">` in the same XML; that re-executes the controller. The one exception to “controller not in XML” is **PlayerStatusWindow**: `PlayerStatusWindow.xml` loads **only** `View/PlayerStatusWindow.lua` (no controller script) because the mod already included `PlayerStatusWindowController.lua` earlier.

**File headers:** `Source/CustomUI.lua` and the top of each `*Controller.lua` / `View/*.lua` state what belongs in that file (state vs presentation, engine hooks vs tooltips, etc.). **SCT** uses `SCTSettings.lua`, `SCTOverrides.lua`, `SCTHandlers.lua`, `SCTAnim.lua`, and `SCTController.lua` under `Controller/` (no separate View lua); templates live under `View/` — the `/cui` settings grid is the **CustomUISettingsWindow** addon. Match those headers when you add new code.

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
			Shared.xml
			BuffTracker/
				BuffTracker.lua
				BuffGroups.lua
				Blacklist.lua
				Whitelist.lua
			UnitFrame/
				TargetFrame.lua
		Components/
			PlayerStatusWindow/
				Controller/
					PlayerStatusWindowController.lua
				View/
					PlayerStatusWindow.lua        ← view lua (tooltips, label helpers)
					PlayerStatusWindow.xml
			TargetWindow/
				Controller/
					TargetWindowController.lua
				View/
					TargetWindow.xml
			PlayerPetWindow/
				Controller/
					PlayerPetWindowController.lua
				View/
					PlayerPetWindow.xml
			GroupWindow/
				Controller/
					GroupWindowController.lua
					GroupWindowTestHarness.lua    ← dev test harness, gated at runtime
				View/
					GroupWindow.xml
			GroupIcons/
				Controller/
					GroupIconsController.lua
				View/
					GroupIcons.xml
			TargetHUD/
				Controller/
					TargetHUDController.lua
				View/
					TargetHUD.xml
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
			SCT/
				Controller/
					SCTSettings.lua
					SCTAbilityIconCache.lua
					SCTAnim.lua
					SCTOverrides.lua              ← stock EventEntry / PointGainEntry / EventTracker subclasses
					SCTHandlers.lua               ← engine handler swap + dispatch
					SCTController.lua             ← RegisterComponent adapter
				View/
					CustomUI_EventTextLabel.xml
					CustomUI_SCTAbilityNameSuffix.xml
					SCTAbilityIcon.xml
					SCT.xml                       ← CustomUISCTWindow + OnUpdate
					(settings tab: CustomUISettingsWindowTabSCT.* — not in this mod)
```

### `Source/Shared` (what is current)

| Path | Status | Role |
|------|--------|------|
| `Shared.xml` | **Current** | Defines `CustomUIBuffContainerTemplate`; `BuffTracker` creates slot windows from it. |
| `BuffTracker/` (`BuffTracker.lua`, `BuffGroups.lua`, `Blacklist.lua`, `Whitelist.lua`) | **Current** | Core buff list behavior: trackers used by `PlayerStatusWindow`, `TargetWindow` (via `TargetFrame`), `GroupWindow`, `TargetHUD`. Blacklist/Whitelist are default tables; BuffGroups is merge metadata. |
| `UnitFrame/TargetFrame.lua` | **Current** | Stock `TargetUnitFrame` subclass with `CustomUI.BuffTracker`; used only by **TargetWindow**. |

All of the above are loaded from `CustomUI.mod` on the main path and are required for shipped components.

### Removed legacy settings code

The old in-addon `CustomUI.SettingsWindow` / `MiniSettingsWindow` shells and per-component `*Tab.xml` + `CustomUI.<Name>.Tab` handlers were removed after the standalone **CustomUISettingsWindow** became the shipped `/cui` UI. Do not reintroduce `Source/Settings/`, `CustomUI.SettingsWindow.RegisterTab`, component `View/*Tab.xml`, or `CustomUI.<Name>.Tab`; add settings UI in `CustomUISettingsWindow` instead.


## Best Practices and Design Rules

### Safe Hooking and Wrappers
- Always use `pcall` when wrapping or hooking engine or stock functions to prevent errors from propagating and breaking the UI.
- Forward all arguments (`...`) and return values in wrappers to preserve original behavior.
- Log errors in wrappers for easier debugging.

### Event Handler Lifecycle
- For every `WindowRegisterEventHandler`, ensure a matching `WindowUnregisterEventHandler` is called in `Shutdown` or `Disable`.
- Prefer registering handlers in `Enable` and unregistering in `Disable` for clear lifecycle management.

### Window Creation Pattern
- Keep `CustomUI.mod` as a **manifest** (`<File>` load order and `OnInitialize` entry only; no `<CreateWindow>` for component roots).
- **Root** top-level windows (names in each component’s `View/*.xml`) are instantiated once at the start of `CustomUI.Initialize` via `EnsureRootWindowInstances()` in `Source/CustomUI.lua` (`CreateWindow(name, false)`), so they exist even when a component is **disabled** in settings and its `Initialize()` never runs (layout editor, saved positions, `DoesWindowExist`).
- Each component’s `Initialize()` still calls `RegisterWindow`, `LayoutEditor.UserHide`, and `CreateWindowFromTemplate` for child widgets (target templates, etc.) as documented elsewhere.

### Global Namespace Safety
- Prefer `CustomUI.*` tables and locals. For `ListData table="…"`, use the same `Namespace.field` style as stock (e.g. `LayoutEditor.windowBrowserDataList` in the client); do not introduce a new bare global for list data.
- Optional client debug logging reads `rawget(_G, "d")` only via `CustomUI.GetClientDebugLog()` in `Source/CustomUI.lua`; addons must not assign global `d`.

### Shared Defaults and Code
- Extract duplicated tables or logic (such as buff filter defaults) into shared modules under `Shared/`.

### SCT Component Global Overwrites
- SCT must receive engine combat/point events, but it should do so without replacing stock globals. Prefer **handler swapping** (unregister stock event handlers, register CustomUI handlers) and **inheriting stock classes** rather than redefining them. See `Source/Components/SCT/plan.md`.

### Code Hygiene
- Remove dead code, commented-out blocks, and dev/test harnesses from release builds.

---


1. Create a namespaced table under `CustomUI` (e.g. `CustomUI.ExampleComponent`).
2. Put mutable state and runtime logic in `Controller/`.
3. Only add a View lua file when there is real view-layer code (tooltips, label updates). Omit it when all rendering is delegated to stock frame APIs.
4. Bind XML event handlers to namespaced functions (e.g. `CustomUI.ExampleComponent.Initialize`).
5. Call `LayoutEditor.UserHide(windowName)` immediately after `RegisterWindow` in `Initialize()`.
6. Register the component adapter from the controller file via `CustomUI.RegisterComponent`.
7. In `Enable`: `UserShow` the CustomUI window, `UserHide` the stock window.
8. In `Disable`: `UserHide` the CustomUI window, `UserShow` (and if needed `UnregisterWindow`) the stock window.
9. Keep manifest load order explicit in `CustomUI.mod`: core shared files first, then each component's controller then xml.
10. Settings UI: use the separate **CustomUISettingsWindow** addon for tabs and handlers; components expose data via `GetSettings()`-style APIs (see SCT: `GetSettingsRowDescriptors`, `SliderPosToScale`). Do not add in-addon `CustomUI.SettingsWindow.RegisterTab` or per-component `*Tab.xml`.

## Runtime usage

- Open settings: `/customui` or `/cui` (window **CustomUISettingsWindowTabbed** from the **CustomUISettingsWindow** addon). The old in-addon settings windows were removed.
- `/customui mini` — prints a deprecation notice; use `/cui` instead.
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

`SCTOverrides.lua` + `SCTHandlers.lua` implement CustomUI SCT by **subclassing stock `EA_System_*` entry/tracker classes** and **swapping engine event-handler registrations** on enable/disable (so stock and CustomUI SCT cannot both process the same engine events).

- `CustomUI.SCT.EventEntry` and `CustomUI.SCT.PointGainEntry` subclass the stock entry classes (custom scale, color, and crit animation).
- `CustomUI.SCT.EventTracker` is derived from the stock tracker but spawns CustomUI entries.
- `CustomUI.SCT.InstallHandlers()` / `RestoreHandlers()` swap `RegisterEventHandler` bindings between stock `EA_System_EventText.*` handlers and `CustomUI.SCT.*` handlers.

Stock `EA_System_EventText` functions and stock class globals remain intact for other addons to call/hook.

### Enable / disable

- **Enabled**: CustomUI handlers are registered; stock handlers are unregistered; only CustomUI SCT renders.
- **Disabled**: stock handlers are restored; CustomUI handlers are unregistered; stock SCT renders.

CustomUI SCT animation updates run from the placeholder `CustomUISCTWindow` `OnUpdate` handler in `View/SCT.xml`, not from stock `EA_System_EventText.Update`.

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

`CustomUI.PlayerPetWindow` wraps `PetWindow.UpdatePet` with a thin hook that calls the original and then forces `PetHealthWindow` hidden again:

- Current behavior: the wrapper is installed during `Initialize()` and gated by `m_enabled`. Planned follow-up is to install only on `Enable` and restore on `Disable`/`Shutdown` so stock is untouched while disabled (see `Source/Components/PlayerStatusWindow/plan.md`).
- `Enable` also hides `PetHealthWindow` immediately via `LayoutEditor.UserHide` and `WindowSetShowing`.
- `Disable` restores the wrapper, re-shows `PetHealthWindow`, and unregisters it from `LayoutEditor`.
- The saved original is stored at module scope and re-wrap is guarded, so repeated enable/disable cycles don't produce wrapper-of-wrapper corruption.

This preserves normal stock takeover behavior when the CustomUI component is disabled, without destroying stock windows.
