# CustomUISettingsWindow — Developer Notes

Second UiMod (`CustomUISettingsWindow`) that depends on **`CustomUI`**. The game
must load the parent addon first; the `.mod` file declares that dependency. The
shell is created on initialize (`CreateWindow` for `CustomUISettingsWindowTabbed`);
players open it with **`/cui`** or **`/customui`** (registered by CustomUI).

**Tabs (load order in `CustomUISettingsWindow.mod`):** Player → Target →
TargetHUD → Group → UnitFrames → GroupIcons → SCT, plus the shared
`CustomUISettingsWindowTabbed` chrome.

Most of the tab XML follows the stock `EA_SettingsWindow` pattern: a
`ScrollWindow` whose `ScrollChild` contains one or more sibling "section" windows
(General, BuffTracker, SCT, …), each with their own title, background and
controls.

The rest of this document records the layout-engine pitfalls we hit while
adding the SCT tab, the workarounds we landed on, and the diagnostic workflow
to use when layout breaks again. Reading this **before** touching an `*.xml`
layout will save a lot of time.

---

## 1. The golden rule: `$parent` is safe, sibling `$parent<Name>` is not

In the WAR / RoR UI engine, inside an `<Anchor …/>`:

- `relativeTo="$parent"` (or omitted entirely) works — it resolves to the
  window's own XML parent.
- `relativeTo="$parent<SiblingName>"` is **not reliable**.
- `relativeTo="<FullyQualifiedName>"` where the window is a sibling is **also
  not reliable** (we tested with the real, existing name and it still failed).

When the sibling reference fails, the engine does **not** log an error. It
silently drops the anchor and falls back to pinning the window near the top of
some outer ancestor (in our case the tab socket at `y≈22`), only honoring the
`AbsPoint` offset. The child still has its correct `Size`, so nothing looks
obviously broken in diagnostics — but on screen the section ends up above the
scroll viewport (`y≈32` with our 10 px offset) where it is clipped and
invisible.

We confirmed this twice:

- `<Anchor relativeTo="$parentGeneral">` on `$parentSCT` → SCT ended at
  `y≈32` instead of below `$parentGeneral` at `y≈527`.
- `<Anchor relativeTo="SWTabSCTContentsScrollChildGeneral">` (fully qualified)
  → same result.

### What to do instead

**Pattern A — preferred XML form.** Pin siblings to the shared XML parent
with explicit Y offsets. This is what the stock `ea_settingswindow` tabs do,
and it is the most reliable form in this engine.

```xml
<!-- First section -->
<Window name="$parentGeneral">
    <Size><AbsPoint x="500" y="80"/></Size>
    <Anchors>
        <Anchor point="topleft"  relativePoint="topleft"><AbsPoint x="0" y="0"/></Anchor>
        <Anchor point="topright" relativePoint="topright"><AbsPoint x="0" y="0"/></Anchor>
    </Anchors>
</Window>

<!-- Second section, directly below the first, using an absolute Y offset -->
<Window name="$parentSCT">
    <Size><AbsPoint x="820" y="460"/></Size>
    <Anchors>
        <Anchor point="topleft" relativePoint="topleft"><AbsPoint x="0" y="90"/></Anchor>
    </Anchors>
</Window>
```

`y=90` is "General.height (80) + gap (10)". Avoid relying on the engine to
compute that for you via a sibling anchor.

**Pattern B — Lua fallback when the offset depends on content.** If the
first section can change height dynamically, re-anchor in Lua using
`WindowAddAnchor` with fully qualified names — it works from Lua even though
the equivalent XML form does not:

```lua
WindowClearAnchors("SWTabSCTContentsScrollChildSCT")
WindowAddAnchor("SWTabSCTContentsScrollChildSCT", "topleft",
    "SWTabSCTContentsScrollChildGeneral", "bottomleft", 0, 10)
WindowAddAnchor("SWTabSCTContentsScrollChildSCT", "topright",
    "SWTabSCTContentsScrollChildGeneral", "bottomright", 0, 10)
WindowForceProcessAnchors("SWTabSCTContentsScrollChildSCT")
```

Important guard rails for Pattern B:

- Only run this when the tab is actually showing
  (`DoesWindowExist(tab) and WindowGetShowing(tab)`). XML `OnUpdate` on an
  inactive tab will still fire — `WindowGetShowing` is the reliable check.
- Wrap each call in `pcall`. A failed `WindowAddAnchor` after
  `WindowClearAnchors` leaves the window with **no anchors at all**, which
  is worse than the original problem.
- On failure, restore a known-good bootstrap anchor (see SCT lua history
  in git).

**Lua: opening a panel beside a small control (e.g. a color swatch).** The
`WindowAddAnchor` parameter order in stock examples is
`(moving, pointOnMoving, target, pointOnTarget, dx, dy)` (see Pattern B
above). Pairing `topleft` on the moved window with `topright` on the
anchor control did not always place the panel on the **expected** side in
our tests. Anchoring with **`topleft` to `topleft` and a positive `dx`**
that equals **control width + gap** (e.g. 20 + 6 for the SCT swatch) is
unambiguous. For z-order, put the `ColorPicker` and its frame inside a
**`layer="popup"`** **host** `Window` and show/hide that host from Lua so
the metal does not remain visible after the grid is closed.

### Why row stacking was broken too

The same failure mode applies to row-to-row anchors:

```xml
<!-- Broken: all rows end up at the same Y -->
<Anchor point="topleft" relativePoint="bottomleft" relativeTo="$parentRowHit">
```

In `CustomUISettingsWindowTabSCT.lua` we now re-anchor all SCT rows in
`Initialize()` via `ReanchorSctRows()`, using
`"SWTabSCTContentsScrollChildSCT"` as the anchor target and a per-row Y
offset (`c_SCT_FIRST_ROW_Y + (i - 1) * c_SCT_ROW_HEIGHT`). This is the
runtime version of Pattern A.

---

## 2. ScrollWindow / ScrollChild naming

Each tab uses the stock pattern:

```xml
<ScrollWindow name="$parentContents"
              childscrollwindow="SWTabSCTContentsScrollChild"
              scrollbar="SWTabSCTContentsScrollbar" ...>
    <Windows>
        <VerticalScrollbar name="$parentScrollbar" .../>
        <Window name="$parentScrollChild">
            <Windows>
                <Window name="$parentGeneral">…</Window>
                <Window name="$parentSCT">…</Window>
            </Windows>
        </Window>
    </Windows>
</ScrollWindow>
```

`childscrollwindow="SWTabSCTContentsScrollChild"` **overrides** the
`$parent`-derived name of the `<Window name="$parentScrollChild">`. At
runtime the scroll child is addressable as the short name
`SWTabSCTContentsScrollChild`, and all descendants prefix off that short
name — e.g. `SWTabSCTContentsScrollChildGeneral`,
`SWTabSCTContentsScrollChildSCTRowHitOutShow`, etc.

Use these short names when calling any window API from Lua, and keep the
`childscrollwindow` attribute consistent across the sibling files
(`CustomUISettingsWindowTab*.xml`). Every tab in this add-on follows this
`SWTab<TabName>Contents*` convention; if you add a new tab, keep it.

### Size behaviour

- `$parentGeneral` has `Size x=500` but two horizontal anchors to
  `$parent` (the scroll child). At runtime the horizontal anchors win and
  the section is stretched to the scroll child's width (~858 with the
  current dialog). The explicit `Size.x` is effectively ignored — only
  `Size.y` is used.
- `$parentSCT` has a single anchor (`topleft` only) and `Size x=820 y=460`.
  With no second horizontal anchor the explicit `Size` wins and the
  section is exactly 820×460. Mixing a single anchor with explicit `Size`
  is fine; mixing **dual** horizontal anchors with an explicit `Size.x`
  different from the parent width creates a conflict that can hide the
  window — avoid.

---

## 3. `SystemData` / pointer tracking

Stock tabs use
`SettingsWindowTabbed.OnMouseOverTooltipElement`, which reads `WindowSetId`
to look up a localized tooltip. CustomUI tabs don't use that pipeline — they
set labels directly via `LabelSetText` in each tab's `Initialize()` (see the
`L"General"`, `L"Enabled"`, `L"Scrolling Combat Text"` calls). You can
ignore `WindowSetId` entirely here.

The SCT tab does expose an optional pointer tracer
(`CustomUISettingsWindowTabSCT.DebugPointer`) that polls
`SystemData.MouseOverWindow` and `SystemData.ActiveWindow` each frame — used
for diagnosing hit-test / input routing problems. It only logs when set to
`true` from the client console.

---

## 4. Diagnostic workflow

The SCT tab carries a self-diagnostic you can turn back on whenever layout
misbehaves. It's gated on the same flag as the input tracer:

```lua
-- in client console, after /reloadui
CustomUISettingsWindowTabSCT.DebugInput = true
```

This enables two kinds of diagnostics:

1. **Init-time dump** (runs in `Initialize()`) — reports `dim` and `pos` for
   the scroll child and key SCT windows. `pos` is typically `0,0` at init
   because screen coords are assigned on first layout pass, so only `dim`
   is meaningful here.
2. **Runtime dump** (fires once on `OnUpdate` the first time the SCT
   section has `WindowGetShowing=true` and a positive screen `y`). This is
   the authoritative one — it tells you where the window **actually**
   ends up.

Each line looks like:

```
[CustomUI SCT diag runtime] SWTabSCTContentsScrollChildSCT exists=true showing=true dim=820x460 pos=888.5,518.4
```

Interpretation cheatsheet:

| What you see | What it means |
|---|---|
| `exists=true showing=true dim=0x0 pos=0,0` at runtime | Window created but never laid out (bad anchor or clipped by a zero-sized parent). |
| `exists=true dim=0xH` at init | Normal for the scroll child before the tab is laid out; runtime should show non-zero width. |
| `pos=888.5, 32.4` for a window that should be at 527 | Classic "sibling `$parent<Name>` in `relativeTo` silently failed"  fallback to tab socket + offset. Switch to Pattern A or Pattern B. |
| `dim=<parent.width>x<Size.y>` for a window with dual horizontal anchors | Horizontal anchors overrode the explicit `Size.x`. Intentional for General; unintentional for SCT-sized sections. |

Tail it with:

```powershell
Get-Content "c:\Games\Return of Reckoning\logs\uilog.log" -Tail 200 |
    Select-String "CustomUI SCT diag"
```

Wider filter (any CustomUI layout / script error):

```powershell
Get-Content "c:\Games\Return of Reckoning\logs\uilog.log" -Tail 200 |
    Select-String -Pattern "CustomUI|SCT|Script Call failed|WindowAddAnchor"
```

The bulk of `WindowGetParent: Window ... does not exist` errors at reload
time are **not** caused by this tab — they come from cleanup passes over
dynamically-destroyed buff/action-bar slots in other CustomUI components and
can be ignored when debugging settings-window layout.

---

## 5. File map

On disk the Lua/XML live under `CustomUISettingsWindow/source/` (paths in the
`.mod` file use `Source/...`; on Windows the casing of that folder is not
important).

```
CustomUISettingsWindow/
  CustomUISettingsWindow.mod              UiMod manifest (tabs + dependency on CustomUI).
  source/
    CustomUISettingsWindowTemplates.xml   Shared templates (TooltipCheckButton, etc.).
    CustomUISettingsWindowTabbed.xml      Outer tabbed dialog + tab strip.
    CustomUISettingsWindowTabbed.lua      Tab shell logic.
    CustomUISettingsWindowTabPlayer.xml   (+ .lua) … per-tab pair
    CustomUISettingsWindowTabTarget.xml
    CustomUISettingsWindowTabTargetHUD.xml
    CustomUISettingsWindowTabGroup.xml
    CustomUISettingsWindowTabUnitFrames.xml
    CustomUISettingsWindowTabGroupIcons.xml
    CustomUISettingsWindowTabSCT.xml
```

When adding a new tab:

1. Copy an existing `CustomUISettingsWindowTab<Name>.{xml,lua}` pair that
   uses the same structure you want.
2. Rename the root window, `childscrollwindow` and `scrollbar` attributes
   consistently (`SWTab<NewName>Contents*`).
3. Add a `<File name="Source/CustomUISettingsWindowTab<NewName>.xml" />`
   entry to `CustomUISettingsWindow.mod`.
4. Wire the tab button in `CustomUISettingsWindowTabbed.xml` / `.lua`.
5. For multi-section tabs, **use Pattern A** above for section stacking,
   not sibling `relativeTo` anchors.

---

## 6. Lua: `local function` must be in scope for callers

In Lua, a `local function Foo()` is only visible to code **below** it in the
same chunk. If `RefreshX()` (defined earlier) calls `Foo()`, the name resolves
to a **global** `Foo` unless you forward-declare locals:

```lua
local Foo
function Foo() ... end  -- or: local function Foo() ... end after the declaration
```

or move the full `local function Foo()` **above** every function that calls it.
Placing helpers after early callers is a common source of
`attempt to call global 'Foo' (a nil value)` in handlers (e.g. target update
paths). Fix by reordering or forward-declaring—no need to make helpers global.
