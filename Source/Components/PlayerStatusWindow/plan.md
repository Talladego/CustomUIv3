## PlayerStatusWindow / PlayerPetWindow — stock-extension review plan

### Why this plan exists

This component currently **monkey-patches a stock table**:

- `PetWindow.UpdatePet` is replaced in `Controller/PlayerPetWindowController.lua` (stored and restored via `m_stockUpdatePetProxy`).

Even though behavior is gated behind `m_enabled`, installing the override during `Initialize()` means **stock is still modified while the component is disabled**, which can impact other addons that:

- call `PetWindow.UpdatePet` directly,
- wrap/hook `PetWindow.UpdatePet`, or
- rely on the original function identity.

### Goal

Ensure **stock is untouched when the component is disabled**, while preserving:

- hiding `PetHealthWindow` whenever CustomUI pet window is enabled,
- the reload edge case where stock `PetWindow:Create` calls `UpdatePet()` directly (bypassing proxy events),
- correct show/hide behavior when a pet appears/disappears.

### Planned refactor

#### 1) Install stock hook only while enabled

- Move `InstallPetProxyHook()` call from `CustomUI.PlayerPetWindow.Initialize()` into `PlayerPetWindowComponent:Enable()`.
- Keep `RestorePetProxyHook()` in `Disable()` (and in `Shutdown()` as a final safety net).

Outcome: `PetWindow.UpdatePet` remains **exactly stock** unless CustomUI component is enabled.

#### 2) Make hook idempotent and symmetric

- `Enable()` should be safe to call repeatedly: only install once.
- `Disable()` should restore only if installed.
- Track state with `m_stockUpdatePetProxy ~= nil`.

#### 3) Keep stock window hiding behavior component-scoped

When enabled:

- continue calling `EnsurePetHealthWindowRegistered()` and `LayoutEditor.UserHide("PetHealthWindow")` + `WindowSetShowing("PetHealthWindow", false)` where needed.

When disabled:

- show/unregister stock window as currently done.

#### 4) Regression checklist

- **Disabled**: Pet appears → only stock pet UI shows; no CustomUI hide occurs; `PetWindow.UpdatePet` is stock.
- **Enabled**: Pet appears → CustomUI window shows; stock `PetHealthWindow` stays hidden (even after stock FadeIn logic).
- Toggle enabled/disabled repeatedly without leaking hook or leaving stock window hidden.

