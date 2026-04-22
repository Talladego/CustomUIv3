# CustomUI — Settings window (implementation plan)

## Status: Complete

---

## Goal

A tabbed settings window that matches the stock EA_SettingsWindow appearance.
CustomUI owns the window structure. Components register tabs at load time.
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
