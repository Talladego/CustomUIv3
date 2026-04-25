# CustomUI.SCT — Refactor Plan

This plan is meant to be followed top to bottom. Every section either tells you what to write, where to put it, or how to verify a step. If a verification step fails, stop and fix it before moving on. Do not skip ahead.

---

## 1. Goals

1. **Stability.** Toggling SCT on/off any number of times leaves no orphan windows, no leaked event registrations, no double-processed engine events, no broken stock state.
2. **Clean mutual exclusivity with stock event text.**
   - **Disabled:** stock `EA_System_EventText` runs unmodified. CustomUI.SCT holds zero engine registrations, owns zero windows, consumes zero per-frame work.
   - **Enabled:** stock event-handler registrations are unhooked, CustomUI.SCT processes the engine events instead, stock's runtime is dormant.
3. **Unified animation pipeline.** Crit and non-crit floats share one base animation. Crits layer optional flair on top of that same pipeline.
4. **Settings-agnostic component.** SCT owns its saved variables and persistence. SCT exposes a stable getter/setter API. CustomUISettingsWindow imports that API and owns **nothing** about SCT — it only stores its own UI-state saved variables (which tab is open, etc.).

Inheritance from stock classes is allowed only when we actually call the stock implementation. We do not subclass for cosmetic effect.

## 2. Non-goals

- Reproducing every stock visual quirk pixel-for-pixel.
- Supporting partial enable (e.g. "only crit overrides"). Enable/disable is binary.
- Supporting other addons that hook stock by name. We document the swap behavior; we do not arbitrate ownership.

## 3. Ownership map (read this before touching anything)

| Concern | Owner |
| :-- | :-- |
| Saved variable `CustomUI.Settings.SCT` | **SCT** (`SCTSettings.lua`) |
| Schema, defaults, migrations of that table | SCT |
| Engine event registration for combat/xp/renown/influence/loading | SCT |
| All windows under `CustomUISCTWindow` (anchors, holders, labels, icons) | SCT |
| Animation math | SCT |
| The settings tab UI (sliders, color pickers, checkboxes for SCT) | CustomUISettingsWindow |
| Saved variables for "which tab is currently open" | CustomUISettingsWindow |

CustomUISettingsWindow is allowed to call **only** the functions in §5. It must not read or write `CustomUI.Settings.SCT` directly.

---

## 4. Module layout

Replace `Controller/SCTEventText.lua` (currently ~1775 lines) with the files below. All new files are under `Source/Components/SCT/`. Keep one responsibility per file. Target size given in parentheses; if a file exceeds that, split it further.

```
Controller/
  SCTController.lua       (~80 lines)   Component adapter. Initialize / Enable / Disable / Shutdown.
  SCTSettings.lua         (~400 lines)  Schema, defaults, migrations, public getters/setters.
  SCTHandlers.lua         (~150 lines)  Engine handler swap (Install/Restore) + the OnX handlers.
  SCTTracker.lua          (~250 lines)  Per-target tracker: queues, lane slots, dispatch, lifecycle.
  SCTEntry.lua            (~250 lines)  EventEntry / PointGainEntry: window create, text/color/icon.
  SCTAnim.lua             (~300 lines)  Animation driver + the 5 effect modules.
  SCTAnchors.lua          (~120 lines)  Anchor / holder / icon window helpers; reuse-safe creation.
View/
  SCT.xml                              CustomUISCTWindow (OnUpdate / OnShutdown driver).
  CustomUI_EventTextLabel.xml          Label template; required behavior described below.
  SCTAbilityIcon.xml                   Icon child template; required behavior described below.
```

**XML required behavior (do not assume current files match — verify, fix if not):**

- `CustomUI_Window_EventTextLabel` (in `CustomUI_EventTextLabel.xml`): a `Label` with `ignoreFormattingTags="false"` (so we can render the engine icon glyphs when needed; the runtime currently avoids `<icon#>` markup, but the template must allow it), `textalign="left"`, `wordwrap="false"`, `handleinput="false"`, `font="font_default_text_large"`, default size 400×100, default white color. The runtime overrides font/scale/size/color per entry.
- `CustomUI_SCTAbilityIcon` (in `SCTAbilityIcon.xml`): a window template containing a `DynamicImage` named `$parentIcon`. Runtime sets the texture/coords via `DynamicImageSetTexture` and resizes via `WindowSetDimensions`.
- `CustomUISCTWindow` (in `SCT.xml`): a top-level window with `OnUpdate="CustomUI.SCT.OnUpdate"` and `OnShutdown="CustomUI.SCT.OnShutdown"`. Hidden by default. **All SCT-owned anchors are children of this window** (see §7).

If any of these files diverge from the above, update the file before continuing — do not work around it in Lua.

**Load order in `CustomUI.mod`** (top to bottom):
```
SCTSettings → SCTAnchors → SCTAnim → SCTEntry → SCTTracker → SCTHandlers → SCTController → View/SCT.xml
```

After load, the only places that should reference `CustomUI.Settings.SCT` directly are functions inside `SCTSettings.lua`. Verify with grep before merging.

---

## 5. Public API surface (consumed by CustomUISettingsWindow)

CustomUISettingsWindow uses **only** these functions. Anything not listed here is internal to SCT.

### 5.1 Static descriptors (read-only)
```lua
CustomUI.SCT.GetSettingsRowDescriptors()  -- returns array {{suffix=..., key=..., hasIncoming=bool}, ...}
CustomUI.SCT.GetCombatTypeKeys()          -- returns array of strings
CustomUI.SCT.GetPointTypeKeys()           -- returns array of strings
CustomUI.SCT.GetTextFonts()               -- returns CustomUI.SCT.TEXT_FONTS
CustomUI.SCT.GetColorOptions()            -- returns CustomUI.SCT.COLOR_OPTIONS
CustomUI.SCT.GetTickScales()              -- returns CustomUI.SCT.TICK_SCALES
CustomUI.SCT.GetCritTickScales()          -- returns CustomUI.SCT.CRIT_SIZE_TICK_SCALES
CustomUI.SCT.GetColorPaletteRevision()    -- returns integer
CustomUI.SCT.GetColorPickerColumns()      -- returns integer
```

### 5.2 Per-setting getters
`direction` is the literal string `"outgoing"` or `"incoming"`. `key` is one of the keys returned by `GetCombatTypeKeys()` or `GetPointTypeKeys()`.

```lua
CustomUI.SCT.GetSize(direction, key)         -- number
CustomUI.SCT.GetColorIndex(direction, key)   -- integer (1 = engine default)
CustomUI.SCT.GetCustomColor(direction, key)  -- {r,g,b} or nil
CustomUI.SCT.GetFilter(direction, key)       -- bool
CustomUI.SCT.GetCritFlags()                  -- shake, pulse, flash (3 bools)
CustomUI.SCT.GetCritSizeScale()              -- number
CustomUI.SCT.GetTextFontIndex()              -- integer
CustomUI.SCT.GetTextFontName()               -- string
CustomUI.SCT.GetShowAbilityIcon()            -- bool
```

### 5.3 Per-setting setters
Setters validate, clamp, and persist. They never call back into the runtime.

```lua
CustomUI.SCT.SetSize(direction, key, scale)
CustomUI.SCT.SetColorIndex(direction, key, idx)
CustomUI.SCT.SetCustomColor(direction, key, rgb_or_nil)  -- nil = clear override
CustomUI.SCT.SetFilter(direction, key, bool)
CustomUI.SCT.SetCritFlags(shake, pulse, flash)           -- enforces shake/pulse exclusivity
CustomUI.SCT.SetCritSizeScale(scale)
CustomUI.SCT.SetTextFontIndex(idx)
CustomUI.SCT.SetShowAbilityIcon(bool)
```

### 5.4 Slider mappers
```lua
CustomUI.SCT.ScaleToSliderPos(scale)
CustomUI.SCT.SliderPosToScale(pos)
CustomUI.SCT.CritSizeToSliderPos(scale)
CustomUI.SCT.SliderPosToCritSize(pos)
```

### 5.5 Bulk operations
```lua
CustomUI.SCT.ResetColorsToStockDefault()
CustomUI.SCT.ApplySctSettingsTabFullReset()
```

### 5.6 Internal-only state (NOT public; do not import from CustomUISettingsWindow)

These exist on `CustomUI.SCT.*` but are not part of the public API. They are runtime-only flags. Settings UI must not read or write them.

| Symbol | Purpose |
| :-- | :-- |
| `CustomUI.SCT.m_active` | Runtime gate; managed by Enable/Disable. |
| `CustomUI.SCT.m_debug` | Verbose log gate (default false). Toggle from console only. |
| `CustomUI.SCT.m_sctLayoutDebug` | Pink/cyan debug overlays. Toggle via `SetSctLayoutDebug` / `ToggleSctLayoutDebug`. |
| `CustomUI.SCT._handlersInstalled`, `_stockWasRegistered` | Handler-swap bookkeeping. |
| `CustomUI.SCT.Trackers`, `TrackersCrit` | Live tracker tables. |
| `CustomUI.SCT.loading` | `true` between LOADING_BEGIN and LOADING_END. |

Master enable/disable for the SCT component itself is owned by the **CustomUI component framework** (`CustomUI.RegisterComponent("SCT", …)`, `CustomUI.IsComponentEnabled("SCT")`), **not** by SCT's saved variables. Settings UI reads the master-enabled state via `CustomUI.IsComponentEnabled` and toggles via the framework's normal API — there is no `CustomUI.SCT.GetEnabled` getter.

If any setting today reads or writes `CustomUI.Settings.SCT.*` from outside `SCTSettings.lua`, it must move behind a getter/setter in §5.2 / §5.3 or be deleted. Audit during Step 1.

### 5.7 Reference setter implementation (copy this pattern)
```lua
-- In SCTSettings.lua. `Settings()` is a private helper returning the migrated table.
function CustomUI.SCT.SetSize(direction, key, scale)
    assert(direction == "outgoing" or direction == "incoming", "bad direction")
    local v = Settings()
    if not v[direction] or not v[direction].size then return end
    -- snap to the nearest tick
    scale = CustomUI.SCT.SliderPosToScale(CustomUI.SCT.ScaleToSliderPos(scale))
    v[direction].size[key] = scale
end
```

The runtime reads through getters at the next event/frame, so setters never need to invalidate live windows. Existing displayed text continues with the values it captured at creation; new text picks up the new values. This matches stock behavior.

---

## 6. Enable/Disable contract

The component has exactly two observable states: **disabled** and **enabled**. Both states must be reachable from the other an unbounded number of times without state drift. `Initialize` runs once at addon load. `Enable`/`Disable` may be called any number of times after that. `Shutdown` is `Disable` plus the promise that we will not be called again.

### 6.1 Enable sequence (in `SCTController:Enable`)

```
1. SCTHandlers.Install()
   1a. For each of the six stock handlers (see §6.3 for the list):
       - Try UnregisterEventHandler(eventId, stockHandlerName).
       - Record success/failure in CustomUI.SCT._stockWasRegistered[eventId].
   1b. For each of the six CustomUI handlers:
       - RegisterEventHandler(eventId, customUIHandlerName).
   1c. CustomUI.SCT.m_active = true
   1d. CustomUI.SCT._handlersInstalled = true

2. WindowSetShowing("CustomUISCTWindow", true)   -- starts the OnUpdate driver
```

### 6.2 Disable sequence (in `SCTController:Disable`)

```
1. WindowSetShowing("CustomUISCTWindow", false)  -- stops the OnUpdate driver immediately

2. SCTHandlers.Restore()
   2a. CustomUI.SCT.m_active = false
   2b. For each of the six CustomUI handlers:
       - UnregisterEventHandler(eventId, customUIHandlerName).
   2c. For each eventId where _stockWasRegistered[eventId] was true:
       - RegisterEventHandler(eventId, stockHandlerName).
   2d. CustomUI.SCT._handlersInstalled = false

3. SCTTracker.DestroyAll()  -- destroys every tracker, anchor, holder, label, icon SCT created
```

### 6.3 Handler table

| Engine event | Stock handler name | CustomUI handler name |
| :-- | :-- | :-- |
| `WORLD_OBJ_COMBAT_EVENT` | `EA_System_EventText.AddCombatEventText` | `CustomUI.SCT.OnCombatEvent` |
| `WORLD_OBJ_XP_GAINED` | `EA_System_EventText.AddXpText` | `CustomUI.SCT.OnXpText` |
| `WORLD_OBJ_RENOWN_GAINED` | `EA_System_EventText.AddRenownText` | `CustomUI.SCT.OnRenownText` |
| `WORLD_OBJ_INFLUENCE_GAINED` | `EA_System_EventText.AddInfluenceText` | `CustomUI.SCT.OnInfluenceText` |
| `LOADING_BEGIN` | `EA_System_EventText.BeginLoading` | `CustomUI.SCT.OnLoadingBegin` |
| `LOADING_END` | `EA_System_EventText.EndLoading` | `CustomUI.SCT.OnLoadingEnd` |

### 6.4 Why this order

- Stopping our OnUpdate before swapping handlers means we cannot half-process anything.
- Restoring stock's registrations **before** destroying our trackers means any event the engine dispatches between those two steps reaches stock's handler — not nothing.
- Recording which stock handlers were actually present before we unregistered them means Restore is symmetric: we never create phantom registrations stock didn't originally have.

### 6.5 Idempotency

Both `Install` and `Restore` early-return if `_handlersInstalled` already matches the desired state. Calling Enable twice is a no-op after the first; same for Disable. `Shutdown` calls `Disable`. There is no separate Shutdown body.

### 6.6 Stock dormancy when enabled

Stock's `EA_Window_EventText` window keeps ticking its own OnUpdate, but with no engine events reaching its trackers it stays at zero work and produces nothing visible. We do not modify stock window state, do not redefine stock globals, do not touch stock-owned windows. Other addons that read or extend stock see real stock objects.

### 6.7 Component framework wiring

`SCTController.lua` is the only place that calls `CustomUI.RegisterComponent("SCT", SCTComponent)`. The component table exposes `Initialize`, `Enable`, `Disable`, `Shutdown` — the framework calls these. Master enable state is read via `CustomUI.IsComponentEnabled("SCT")`. The component name string `"SCT"` must match what other parts of CustomUI (e.g. main `CustomUI.lua`, settings UI) use to reference this component; do not rename it without a global search.

---

## 7. Window lifetime and naming

All CustomUI SCT windows are children of CustomUI-owned parents — never of stock-owned containers. After `Tracker.DestroyAll()` runs, every window we created is gone.

### 7.1 Tree

```
CustomUISCTWindow                                   (View/SCT.xml; OnUpdate driver)
  CustomUI_SCT_EventTextAnchor<targetId>            per-target world-attached anchor (non-crit)
    CustomUI_SCT_EventTextAnchor<targetId>Event<n>      non-crit event label
      ...AbilityIcon                                    optional icon child
    CustomUI_SCT_EventTextAnchor<targetId>PointGain<n>  XP / renown / influence label
  CustomUI_SCT_EventTextAnchorCrit<targetId>        per-target crit anchor
    ...Holder<n>                                        crit holder (carries lane/float motion)
      ...Holder<n>Event<n>                              crit label (carries flair animation)
        ...AbilityIcon                                  optional icon child
```

Anchors are attached to the world object via `AttachWindowToWorldObject`. `Tracker:Destroy` calls `DetachWindowFromWorldObject` before `DestroyWindow`.

### 7.2 Reload-safe anchor creation

A tracker is created on the first event for a target after Enable. On creation:

```lua
function SCTAnchors.CreateAnchor(anchorName)
    if DoesWindowExist(anchorName) then
        DestroyWindow(anchorName)  -- destroys all descendants too
    end
    CreateWindowFromTemplate(anchorName, "EA_Window_EventTextAnchor", "CustomUISCTWindow")
end
```

This is the **single** path for anchor creation. Always destroy first if it exists. Because `DestroyWindow(anchor)` cascades to every child, the freshly recreated anchor has no `Event<n>` / `Holder<n>` / `PointGain<n>` descendants — and the new tracker's `m_NextEntryIndex` (§9.3) starts at `0`. Together these two invariants guarantee no window-name collision can survive a `/reloadui` and eliminate the "phantom child window blocks dispatch forever" failure mode.

### 7.3 Destruction order (in `Tracker:Destroy`)

**Hard rule:** before any `DestroyWindow(W)`, all engine-driven animations on `W` and on every descendant of `W` must be stopped. Engine alpha/position/scale animations hold internal references to the window; destroying a window with a live animation (or destroying its parent while it has live animations) has caused `WindowGetParent`-on-destroyed-window crashes in production. The rule is unconditional and applies to anchors, holders, labels, and icon children.

`StopAllAnimations(windowName)` helper used everywhere below:
```lua
function StopAllAnimations(w)
    if not DoesWindowExist(w) then return end
    WindowStopAlphaAnimation(w)
    WindowStopPositionAnimation(w)
    WindowStopScaleAnimation(w)
end
```

`Tracker:Destroy`:
1. Drain `m_Displayed` queue, calling `entry:Destroy()` on each (which handles its own animation stops, see below).
2. Drain `m_Pending` queue (no windows attached yet, just clear).
3. `StopAllAnimations(m_Anchor)`.
4. `DetachWindowFromWorldObject(m_Anchor, m_TargetObject)`.
5. `DestroyWindow(m_Anchor)` — cascades to any remaining child holder/label.

`entry:Destroy()`:
1. If an ability icon child exists, `StopAllAnimations` on it then `DestroyWindow` it.
2. `StopAllAnimations(m_Window)`.
3. If `m_Holder` exists: `StopAllAnimations(m_Holder)` then `DestroyWindow(m_Holder)` (cascades to `m_Window`). Done.
4. Otherwise `DestroyWindow(m_Window)`.
5. If the entry held a crit lane slot, call `tracker:ReleaseLane(self.m_LaneSlot)`.

`SCTTracker.DestroyAll()` iterates `Trackers` and `TrackersCrit`, calls `Destroy` on each, sets both tables to `{}`.

---

## 8. Animation pipeline (unified)

One model for every entry. Crit and non-crit run the same loop; crits add a list of overlay effects.

### 8.1 Entry shape

```lua
entry = {
    m_Window         = "<windowName>",       -- the label window
    m_Holder         = "<holderName>",       -- crit holder, or nil
    m_LifeSpan       = 0,
    m_BaseAnim = {
        start    = { x, y },
        target   = { x, y },
        current  = { x, y },
        maxTime  = number,                   -- seconds; engine alpha animation aligns to this
        targetWindow = "<windowName>",       -- the holder if present, else the label
    },
    m_Effects = {                            -- ordered list; each runs only during its own time window
        { effect = SCTAnim.Effects.LaneMove,   startAt = 0.00, duration = 0.15, params = {...} },
        { effect = SCTAnim.Effects.Grow,       startAt = 0.15, duration = 0.20, params = {...} },
        { effect = SCTAnim.Effects.Shake,      startAt = 0.35, duration = 0.75, params = {...} },
        { effect = SCTAnim.Effects.ColorFlash, startAt = 0.35, duration = 0.75, params = {...} },
    },
}
```

For non-crits, `m_Holder` is nil, `m_Effects` is empty, and `m_BaseAnim.targetWindow` is the label.

**Point-gain entries** (XP, renown, influence) use the **same entry shape and same `Update` driver**. They are non-crit by construction: `m_Holder = nil`, `m_Effects = {}`, `m_BaseAnim.targetWindow` is the label. The only difference from a non-crit combat entry is in `SetupText` (different localized string, different default color) — not in animation. There is one driver, not two.

### 8.1.1 Lifetime: single source of truth

`m_BaseAnim.maxTime` is the authoritative lifetime of the entry. Both the tracker's destroy decision **and** the engine alpha animation are driven from it:

- The tracker pops + destroys the entry when `entry.m_LifeSpan > entry.m_BaseAnim.maxTime`.
- The engine alpha animation is started at dispatch time with arguments derived from the same number, **always targeting the label window** (`entry.m_Window`), never the holder. The holder, if present, exists to carry position/scale motion; the visible glyph fades on its own window. Fading the holder would also fade any descendant we add later (e.g. ability icon child) at unrelated rates — keep fade on the label only:
  ```lua
  local fadeDuration = ENTRY_FADE_DURATION              -- §8.6.1
  local fadeDelay    = entry.m_BaseAnim.maxTime - fadeDuration
  WindowStartAlphaAnimation(entry.m_Window, Window.AnimationType.EASE_OUT,
      1, 0, fadeDuration, false, math.max(0, fadeDelay), 0)
  -- Ability icon child (if present) gets its own matching alpha animation
  -- so it fades in lockstep with the label glyph.
  ```

Anything that adjusts the lifetime (extra crit phases, longer flash) writes only to `m_BaseAnim.maxTime`; everything downstream re-derives. There is no second clock.

### 8.2 Update loop (in `SCTEntry:Update`)

```lua
function EventEntry:Update(dt, simSpeed)
    local simTime = dt * simSpeed
    self.m_LifeSpan = self.m_LifeSpan + simTime

    -- 1. Run any active effects (in declaration order).
    for _, slot in ipairs(self.m_Effects) do
        local localT = self.m_LifeSpan - slot.startAt
        if localT >= 0 and localT <= slot.duration then
            local p = slot.duration > 0 and (localT / slot.duration) or 1
            slot.effect.Apply(self, p, slot.params)
        elseif localT > slot.duration and not slot._finished then
            slot.effect.Finish(self, slot.params)
            slot._finished = true
        end
    end

    -- 2. Run the base scroll/drift on whichever window owns motion.
    local anim = self.m_BaseAnim
    local step = simTime / anim.maxTime
    anim.current.x = anim.current.x + (anim.target.x - anim.start.x) * step
    anim.current.y = anim.current.y + (anim.target.y - anim.start.y) * step
    WindowSetOffsetFromParent(anim.targetWindow, anim.current.x, anim.current.y)

    return self.m_LifeSpan
end
```

That is the entire driver. There are no phase strings, no nested if/elseif chains.

### 8.3 Effect interface

Every effect implements:

```lua
SCTAnim.Effects.<Name> = {
    Apply  = function(entry, p, params) ... end,    -- p in [0,1] over the effect's window
    Finish = function(entry, params) ... end,       -- restore neutral state
}
```

### 8.4 The five effects

Each effect is ~30–60 lines of math. No window-existence guards, no pcalls.

- **LaneMove** — moves the holder horizontally from a side lane into the center column. `params = { fromX, toX, y }`. `Apply` interpolates X with ease-out; `Finish` writes the final X.
- **Grow** — scales the label from `fromScale` to `toScale`. `params = { fromScale, toScale }`. `Apply` writes `WindowSetScale` and the center-pivot offset compensation. `Finish` writes `toScale` and the rest offset.
- **Shake** — adds sinusoidal jitter to the holder's offset (or label if no holder). `params = { amplitude, frequency, verticalScale, baseX, baseY }`. `Apply` writes `base + amp*(1-p)*sin(2π·f·localT)`. `Finish` writes `(baseX, baseY)`.
- **Pulse** — adds sinusoidal scale modulation to the label. `params = { frequency, scaleDelta, restScale, baseW, baseH }`. `Apply` writes `restScale * (1 + delta*(1-p)*sin(...))` plus center-pivot compensation. `Finish` writes `restScale`.
- **ColorFlash** — drives the label color through Base→White→Base→Black→Base→…→target sequence. `params = { targetR, targetG, targetB }`. `Apply` writes `LabelSetTextColor`. `Finish` writes the target color.

### 8.5 Composition rules

- **Lane move + grow** are sequential: lane move first, then grow.
- **Shake + pulse** are mutually exclusive (settings already enforce this; `SetCritFlags` re-checks).
- **ColorFlash** runs concurrently with shake or pulse.
- **Float** is the same base scroll/drift every entry already runs — the holder/label moves vertically toward `m_BaseAnim.target.y` continuously. There is no "float phase". For crits with a holder, the base anim targets the holder; for non-crits, it targets the label. That is the only difference between crit and non-crit motion.

### 8.6 Building the effect list (in `Tracker:DispatchOne`)

```lua
local effects = {}
local t = 0
if entry.m_Holder then
    table.insert(effects, { effect = LaneMove, startAt = t, duration = LANE_DUR, params = {...} })
    t = t + LANE_DUR
end
if anyFlair then
    table.insert(effects, { effect = Grow, startAt = t, duration = GROW_DUR, params = {...} })
    t = t + GROW_DUR
    local mainEnd = t
    if shake  then table.insert(effects, { effect = Shake,      startAt = t, duration = SHAKE_DUR, params = {...} }); mainEnd = math.max(mainEnd, t + SHAKE_DUR) end
    if pulse  then table.insert(effects, { effect = Pulse,      startAt = t, duration = PULSE_DUR, params = {...} }); mainEnd = math.max(mainEnd, t + PULSE_DUR) end
    if flash  then table.insert(effects, { effect = ColorFlash, startAt = t, duration = FLASH_DUR, params = {...} }); mainEnd = math.max(mainEnd, t + FLASH_DUR) end
    t = mainEnd
end
entry.m_Effects = effects
entry.m_BaseAnim.maxTime = math.max(MIN_DISPLAY_TIME, t + FLOAT_TAIL)

-- Start fade. The label fades on its own animation; if an ability icon child
-- exists, start the same animation on it so the two fade in lockstep.
local fadeDelay = math.max(0, entry.m_BaseAnim.maxTime - ENTRY_FADE_DURATION)
WindowStartAlphaAnimation(entry.m_Window, Window.AnimationType.EASE_OUT,
    1, 0, ENTRY_FADE_DURATION, false, fadeDelay, 0)
if entry.m_AbilityIconWindow then
    WindowStartAlphaAnimation(entry.m_AbilityIconWindow, Window.AnimationType.EASE_OUT,
        1, 0, ENTRY_FADE_DURATION, false, fadeDelay, 0)
end
```

### 8.6.1 Animation constants (define in `SCTAnim.lua`)

These are the only timing constants in the animation system. All other timing is derived from these via §8.6 and §8.1.1.

| Constant | Value | Meaning |
| :-- | :-- | :-- |
| `LANE_DUR` | `0.15` | Crit holder slides from off-axis lane into center column. |
| `GROW_DUR` | `0.20` | Label scales from `fromScale` to crit `endScale`. |
| `SHAKE_DUR` | `0.75` | Damped sinusoidal shake duration. |
| `PULSE_DUR` | `0.75` | Damped scale pulse duration. |
| `FLASH_DUR` | `0.75` | Color flash sequence duration. |
| `FLOAT_TAIL` | `0.75` | Trailing base-drift time after the last crit effect ends, before fade-out completes. For non-crit entries this is the entire post-effect display window. |
| `MIN_DISPLAY_TIME` | `4.0` | Lower bound on `m_BaseAnim.maxTime`; matches stock's `maximumDisplayTime` default so non-crit entries last at least as long as stock. |
| `ENTRY_FADE_DURATION` | `0.75` | Engine alpha-animation duration; the alpha fade starts at `maxTime - ENTRY_FADE_DURATION`. |
| `MINIMUM_EVENT_SPACING` | `36` | Vertical spacing between stacked entries in a tracker queue (also the threshold for "out of starting box"). |
| `CRIT_LANE_OFFSET_X` | `80` | Horizontal lane offset for crit slots; slot 1 = `+80`, slot 2 = `-80`. |

Tunable per-effect parameters (`amplitude`, `frequency`, `verticalScale`, `scaleDelta`, `endScale`, etc.) are passed in the `params` table of each effect slot and may be sourced from settings. They are not separate top-level constants here.

### 8.7 Holder usage rule

A holder window is created **only** when `m_Effects` contains at least one effect whose target is `"holder"` (currently: LaneMove, optionally Shake). Non-crits and crits-with-no-flair use the label window directly. The pipeline treats the holder as transparent: an effect targeting `"holder"` falls back to the label when no holder exists.

---

## 9. Tracker model

`SCTTracker` is a plain Lua table-based class. It does not subclass any stock class. Per-target instance:

```lua
{
    m_TargetObject     = number,
    m_Anchor           = "<anchorName>",
    m_IsCritTracker    = bool,
    m_Pending          = Queue:Create(),
    m_Displayed        = Queue:Create(),
    m_ScrollSpeed      = 1,
    m_NextEntryIndex   = 0,                 -- monotonic counter for window names
    m_LaneSlots        = { [1] = false, [2] = false }, -- crit only; false = free, true = taken
}
```

### 9.1 Lane slot reservation (crit trackers only)

```lua
function Tracker:ReserveLane()
    for slot = 1, 2 do
        if not self.m_LaneSlots[slot] then
            self.m_LaneSlots[slot] = true
            return slot
        end
    end
    return nil  -- no slot available; caller delays dispatch this frame
end

function Tracker:ReleaseLane(slot)
    if slot then self.m_LaneSlots[slot] = false end
end
```

Slot 1 maps to `+CRIT_LANE_OFFSET_X`, slot 2 maps to `-CRIT_LANE_OFFSET_X`. The entry stores its `m_LaneSlot` so `entry:Destroy()` can call `tracker:ReleaseLane(entry.m_LaneSlot)`.

If `ReserveLane` returns nil, leave the event at the front of `m_Pending` and try again next frame. This naturally throttles rapid crit bursts.

### 9.2 Lifecycle

- **Create** lazily on first event for a target. `OnCombatEvent` / `AddPointGain` looks up the right tracker table and creates if missing.
- **Update** runs from `OnUpdate` per frame. Iterates `m_Displayed` from front to back, calls `entry:Update(dt, simSpeed)` on **every** entry every frame — `m_LifeSpan` and effect state advance for all displayed entries continuously, even when not at the front. This matches stock: trailing entries keep animating and fading on their own clocks; the front-only check governs only **destroy timing**, not lifespan accumulation. After updating, if the front entry's `m_LifeSpan > m_BaseAnim.maxTime`, pop it and call `entry:Destroy()`, then re-check the new front (an entry that has been waiting can be popped immediately on the same frame). Then dispatch from `m_Pending` if the queue has space.
- **Destroy** when both queues are empty. Non-crit trackers destroy only when **also** out of combat: read `(GameData and GameData.Player and GameData.Player.inCombat) == true`. If `GameData.Player` is nil (pre-login / handoff) treat as **not in combat**. No debouncing — the check runs once per `OnUpdate` per tracker; transient `inCombat` flips between frames cause at most one extra/one fewer-frame delay before destruction, which is harmless. Crit trackers destroy as soon as both queues are empty regardless of combat state.
- **DestroyAll** is the single sweep used on Disable / Shutdown.

### 9.3 Window names

```lua
local newName = self.m_Anchor .. (eventType == COMBAT_EVENT and "Event" or "PointGain") .. self.m_NextEntryIndex
self.m_NextEntryIndex = self.m_NextEntryIndex + 1
```

Use a monotonic counter, not `m_Displayed:End()`. The counter resets only when the tracker is destroyed and recreated. With reload-safe anchor creation (§7.2) collisions are impossible.

---

## 10. Error & logging policy

- **No defensive guards on engine globals.** Functions like `DoesWindowExist`, `WindowSetScale`, `LabelSetText` always exist in the RoR runtime. Call them directly. This removes ~150 lines of `if Fn then Fn(...) end` noise and stops masking real failures.
- **No pcall around our own code paths.** A bug should fail loudly once, not silently every frame. The current double-pcall pattern in tracker→entry update is removed.
- **Existence checks remain only where they are real branches** (`DoesWindowExist(anchor)` to decide create-vs-reuse; `DoesWindowExist(holder)` before `DestroyWindow`).
- **Documented brittle-boundary exception.** A small set of engine calls are known to assert or otherwise mis-behave on edge inputs that we cannot fully validate from Lua. Wrap **only these** in `pcall`, with a comment explaining why:
  - `AttachWindowToWorldObject(anchor, targetObjectNumber)` — target object may have despawned in the same frame.
  - `DetachWindowFromWorldObject(anchor, targetObjectNumber)` — same as above.
  - `CreateWindowFromTemplate(name, template, parent)` — asserts on duplicate names; we mitigate via §7.2 but leave the pcall as belt-and-braces.

  Every other call stays unguarded. If a new candidate boundary appears in the future, add it to this list with its rationale; do not silently sprinkle pcalls.
- **Logging is gated.** A new `CustomUI.SCT.m_debug` boolean (default `false`) controls per-event log lines. Helper:

```lua
local function SCTLog(msg)
    if not CustomUI.SCT.m_debug then return end
    local dbg = CustomUI.GetClientDebugLog()
    if dbg then dbg("[SCT] " .. tostring(msg)) end
end
```

Tracker-level errors (e.g. anchor creation failure) log unconditionally with a different prefix.

---

## 11. Step-by-step implementation

Each step ends with a verification gate. **Do not advance until the gate passes.** Each step should be one commit so it can be reverted independently.

### Step 1 — Add the public API surface to existing `SCTSettings.lua`
- Add every function from §5 as a thin wrapper around the existing settings table. No behavioral changes.
- Internalize the existing `GetSettings()` as a file-local `Settings()` helper.
- **Gate:** `grep -n "CustomUI.Settings.SCT" Source` returns matches **only** in `SCTSettings.lua`. Existing settings UI still loads and edits values correctly.

### Step 2 — Migrate CustomUISettingsWindow tabs to the public API
- Replace every direct read/write of `CustomUI.Settings.SCT.*` in CustomUISettingsWindow with the corresponding getter/setter.
- **Gate:** `grep -rn "CustomUI.Settings.SCT" CustomUISettingsWindow` returns zero matches. Open the SCT settings tab; every slider/checkbox/color picker reads its current value correctly and writes back correctly.

### Step 3 — Mechanical file split
- Move the existing `SCTEventText.lua` content into `SCTAnchors.lua`, `SCTAnim.lua`, `SCTEntry.lua`, `SCTTracker.lua`, `SCTHandlers.lua` with **no behavioral changes**. Pure cut-and-paste plus the load-order update in `CustomUI.mod`.
- Delete `SCTEventText.lua`.
- **Gate:** SCT enabled, behavior indistinguishable from pre-split in all of these scenarios:
  - solo target dummy: hits, abilities, blocks, parries, evades all show as before
  - taking damage: incoming numbers in correct color/size/position
  - XP / renown / influence gain show as before
  - one crit per toggle combination plays as before
  - `git diff` shows only file moves, load-order edits, and `require`/load wiring; no logic changes outside those.

### Step 4 — Strip defensive guards and pcalls
- In the moved files, remove all `if FunctionName then FunctionName(...) end` patterns and all pcalls that wrap our own code.
- Keep `DoesWindowExist` checks only where they pick a code path.
- **Gate:** SCT enabled in a fight — same visuals as Step 3. No new errors in client log.

### Step 5 — Reparent + reload-safe anchor creation (§7.2)
- **Reparent every SCT-owned anchor to `CustomUISCTWindow`.** Audit all `CreateWindowFromTemplate(...)` calls in the SCT component; any that pass `EA_Window_EventTextContainer` (or any non-CustomUI window) as the parent must be changed to `CustomUISCTWindow`. This includes anchors, holders, debug overlay windows, and the ability icon child template parent chain.
- Replace all anchor-creation paths with the single `SCTAnchors.CreateAnchor` function shown in §7.2.
- Replace `m_Displayed:End()`-based naming with the monotonic `m_NextEntryIndex` (§9.3).
- Apply the §7.3 stop-animations-before-destroy rule everywhere a `DestroyWindow` is called.
- **Gate (parenting):** `grep -rn "EA_Window_EventTextContainer" Source/Components/SCT/` returns zero matches. Every `CreateWindowFromTemplate` call in the component passes `"CustomUISCTWindow"` as parent (or a window that is itself a descendant of it).
- **Gate (reload):** Enable SCT, take damage, `/reloadui` mid-fight, take damage again. New floating text appears. Run a temporary `/customui sct dumpwindows` console command (add it for this gate; remove after) that prints `DoesWindowExist("CustomUISCTWindow")` and the list of children — there are no `CustomUI_SCT_*` windows other than the live trackers' anchors.
- **Gate (animations):** Enable SCT, take damage to spawn ~10 entries, run `/reloadui` while entries are mid-animation. No `WindowGetParent`-on-destroyed-window errors in the client log.

### Step 6 — Unified animation pipeline (§8)
- Implement `SCTAnim.lua` with the five effects per §8.4. Each effect is a small file-local table with `Apply` and `Finish`.
- Replace `EventEntry:Update`'s phase soup with the loop in §8.2. The new `EventEntry:Update` is ≤30 lines.
- Move effect-list construction into `Tracker:DispatchOne` per §8.6.
- **Gate:** Test each crit toggle combination — `none`, `shake`, `pulse`, `flash`, `shake+flash`, `pulse+flash`. Each plays as before. Non-crit floats are unchanged. Diff against stock event text behavior with SCT disabled — they look the same as before this step.

### Step 7 — Enable/Disable sequencing (§6)
- Implement `SCTHandlers.Install` / `SCTHandlers.Restore` per §6.1 / §6.2. Record which stock handlers were actually present (`_stockWasRegistered`).
- Rewrite `SCTController:Enable` / `Disable` / `Shutdown` to the exact sequences in §6. `Shutdown` calls `Disable`.
- Add a temporary debug helper `CustomUI.SCT._DumpHandlerState()` (remove after this step). For each of the six event ids in §6.3 it reports:
  - the value of `_stockWasRegistered[eventId]` and `_handlersInstalled` (purely Lua-side state).
  - **best-effort live registration probe**, in this order of preference:
    1. If the engine exposes a registration-introspection function in this build, use it. Confirm in lua-stubs / docs before relying on it.
    2. Otherwise, perform an unregister-then-reregister round-trip on a known-safe handler name and observe whether the unregister succeeded. This mutates state for one frame; do it only at idle (no live trackers, no pending events) to avoid masking a real event.
  - **Do not** use synthetic engine-event injection in this helper. It can have gameplay side effects (XP toasts, combat-state changes, achievement triggers) and is unsafe outside a private dev client. If neither (1) nor (2) is feasible, drop live introspection and rely on the Lua-side bookkeeping plus the in-combat behavioral gates below.
- The helper is **dev-only**: gate it behind `CustomUI.SCT.m_debug` and remove from the codebase once Step 7 verification passes.
- **Gate (idempotence):** Call `Enable()` 5 times then `Disable()` 5 times. `_DumpHandlerState()` after the run reports the same handlers registered as before the test started.
- **Gate (out of combat toggle):** Toggle SCT 20 times via the settings UI's enable checkbox. After the final toggle, `_DumpHandlerState()` matches the baseline captured before the test.
- **Gate (in combat toggle):** Same as above while taking damage from a target dummy. No doubled text (each event produces one float, never two). No missed events lasting longer than one second after re-enable.

### Step 8 — Lane slot reservation (§9.1)
- Replace the modulo-based lane assignment with reserve-on-dispatch / release-on-destroy.
- **Gate:** Trigger a rapid burst of crits (e.g. AoE on multiple targets at once). No two simultaneously visible crits sit in the same lane.

### Step 9 — Drop redundant `m_active` reads from runtime
- Handlers are only registered when active, so the entry-guards `if not CustomUI.SCT.m_active then return end` inside `OnCombatEvent`/`OnXpText`/etc. are redundant. Remove them.
- The dead-code branch in `EventEntry:SetupText` that handles `not m_active` is unreachable. Remove it.
- Keep `m_active` as a single boolean read by `OnUpdate`'s entry guard, or remove it entirely if `WindowSetShowing(false)` reliably stops OnUpdate (verify on your platform; if uncertain, keep the flag).
- **Gate:** SCT enabled, behavior unchanged. SCT disabled, no CustomUI work happens (verify by adding a temporary print to OnUpdate and confirming no output when disabled).

### Step 10 — Final cleanup
- Confirm no file in the component exceeds the targets in §4. Split further if any does.
- Confirm `grep -rn "CustomUI.Settings.SCT" Source/Components/SCT/` only matches `SCTSettings.lua`.
- Confirm `grep -rn "EA_System_Event" Source/Components/SCT/` only appears in: (a) `SCTHandlers.lua` for handler-name strings, (b) docstrings.
- Update this `plan.md` to a short "What this component does" doc, or delete it.

---

## 12. Acceptance criteria

The refactor is done when **all** of the following hold:

- Toggling SCT enabled/disabled in any state (out of combat, in combat, mid-crit, during loading screen, immediately before/after `/reloadui`) leaves no observable drift after one round-trip: same `CustomUI.Settings.SCT` table contents, same handlers registered (verified per Step 7's `_DumpHandlerState`), no orphan windows under `CustomUISCTWindow` or anywhere else (verified per Step 5's window-dump helper).
- With SCT disabled, stock event text appears with stock visuals and stock timing — verified by comparing against an unmodified client.
- With SCT enabled, no stock event text appears anywhere.
- `/reloadui` mid-combat with SCT enabled: text continues on the next event with no orphan windows.
- The SCT component has zero references to any `CustomUISettingsWindow*` symbol.
- The CustomUISettingsWindow addon has zero references to `CustomUI.Settings.SCT` (only public getters/setters from §5).
- `SCTEventText.lua` does not exist after the refactor; no single file in the component exceeds ~400 lines.
- Per-event SCTLog output is empty unless `CustomUI.SCT.m_debug` is true.
