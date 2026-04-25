# CustomUI.SCT implementation notes (vs `plan.md`)

This file records how the current tree differs from `plan.md`, client-specific gotchas, and **plan §11 step status**. Update it when behavior or the plan changes.

---

## Status (smoke test)

- **SCT loads:** `SCTHandlers.lua` parses (no BOM), `SystemData.Events` deferred until `InstallHandlers`, `OnUpdate` / handler swap work.
- **Settings:** CustomUISettingsWindow SCT tab uses the §5 API only; persisted table stays behind `SCTSettings.lua` (`Settings()` helper).
- **Ability icons:** Template `CustomUI_SCTAbilityIcon` is registered using **`Interface` / `Windows`** XML (not `<Root>`). Icons **create** without uilog template errors; **size and position** still need tuning / more in-game testing (no code change in this refresh).

---

## Plan §11 — step checklist

| Step | Topic | Status |
| :--- | :--- | :--- |
| **1** | Public API on `SCTSettings.lua`, `Settings()` | **Done** |
| **2** | Settings window off `CustomUI.Settings.SCT` | **Done** (grep `CustomUISettingsWindow`: zero matches; under `Source/` only `SCTSettings.lua` + this `.md` mention the string) |
| **3** | Mechanical split into Anchors/Anim/Entry/Tracker/Handlers; delete monolith | **Partial:** `SCTHandlers.lua` + `_RuntimeForHandlers` bridge only; **`SCTEventText.lua`** still holds anchors, anim, entries, tracker |
| **4** | Strip defensive `if Fn` / pcalls per §10 | **Not started** (client needed targeted `pcall` / `DoesWindowExist` in a few places, e.g. `WindowGetParent`, load quirks) |
| **5** | Reparent anchors to `CustomUISCTWindow`; §7.2 single `CreateAnchor`; §7.3 animation stops | **Not started** — anchors still created under **`EA_Window_EventTextContainer`** (`SctEnsureEventTextRootAnchor`) |
| **6** | Unified `SCTAnim` pipeline (§8) | **Not started** |
| **7** | Enable/disable §6 + `_DumpHandlerState` | **Partial:** controller order, `_stockWasRegistered`, `_engineHandlerRowsCache`, boot probe / `pcall(InstallHandlers)`; **`_DumpHandlerState` not implemented** |
| **8** | Lane reserve/release (§9.1) | **Not verified** against plan (may still use older lane logic) |
| **9** | Drop redundant `m_active` in handlers | **Not started** |
| **10** | Final grep / file size / doc trim | **Not started** |

Next logical chunk after your icon testing: **Step 5** (reparent to `CustomUISCTWindow`) or resume **Step 3** (full split with a shared `_internal` table) depending on whether you want behavior stability or structure first.

---

## 1. RoR client Lua: `assert` return value

Some UI Lua builds use a stub `assert` that does **not** return its first argument on success. Do not use `local x = assert(tbl, "msg")` for wiring; use `local x = tbl` then `if not x then error(...) end`.

---

## 2. `SystemData.Events` must not run at `SCTHandlers.lua` chunk load

Build the six handler rows inside **`InstallHandlers`** via `sctEngineHandlers()`. Cache rows in **`_engineHandlerRowsCache`** for **`RestoreHandlers`** if `SystemData` is unavailable during teardown.

---

## 3. Encoding and BOM (`SCTHandlers.lua`)

The client rejects a **UTF-8 BOM** at file start (`'=' expected near` garbage). Keep **`SCTHandlers.lua`** as **UTF-8 without BOM** and ASCII-safe in comments/strings editors might re-save with BOM.

Strip example:

`node -e "const fs=require('fs');const p='.../SCTHandlers.lua';let b=fs.readFileSync(p);if(b[0]===0xEF&&b[1]===0xBB&&b[2]===0xBF)b=b.slice(3);fs.writeFileSync(p,b);"`

---

## 4. Module split (plan §4)

**Target load order:** `SCTSettings` → `SCTAnchors` → `SCTAnim` → `SCTEntry` → `SCTTracker` → `SCTHandlers` → `SCTController` → `SCT.xml`

**Actual:** `SCTSettings` → `SCTEventText` → `SCTHandlers` → `SCTController` → `SCT.xml`

**Bridge:** `CustomUI.SCT._RuntimeForHandlers` (defined at end of `SCTEventText.lua`) passes `SCTLog`, `SctLayoutDebugIsOn`, `SctAnchorName`, `SctEnsureEventTextRootAnchor` into handlers.

---

## 5. Enable / disable (plan §6)

Aligned: hide **`CustomUISCTWindow`** first, **`RestoreHandlers`**, **`DestroyAllTrackers`**. **`InstallHandlers`** sets **`m_active`** and **`_handlersInstalled`**. Stock restore uses **`_stockWasRegistered`**.

**Deviation:** XML **`OnShutdown`** on `CustomUISCTWindow` also runs restore + destroy (overlap with component shutdown is intentional safety).

**Legacy:** **`Deactivate()`** still exists; component **Disable** does not call it.

---

## 6. Logging (plan §10 vs shipped)

Plan §10 eventually gates **all** per-event **`SCTLog`** behind **`m_debug`**. Shipped today: **`CustomUI.SCT.m_debug`** + **`CustomUI.SCT.Trace()`** in **`SCTSettings.lua`** for optional traces; **`SCTEventText.lua`** **`SCTLog`** still logs whenever **`CustomUI.GetClientDebugLog`** exists (verbose). **`SCTController`** logs a one-line **boot probe** and **Enable** summary (`m_active`, `OnUpdate` type, `_handlersInstalled`); **`InstallHandlers`** wrapped in **`pcall`** with errors to uilog.

---

## 7. XML

- **`CustomUI_EventTextLabel.xml`:** matches plan intent (left align, `ignoreFormattingTags="false"`, etc.).
- **`SCTAbilityIcon.xml`:** root is **`Interface` > `Windows` > `Window name="CustomUI_SCTAbilityIcon"`** so the template loads like other addon XML. **Layout follow-up:** icon **size/position** vs label (anchors in `SctApplyAbilityIconLayout`) — adjust after more combat testing.

---

*Last updated: plan §11 status table, Step 1–2 noted done, Steps 3–10 honest backlog, ability icon XML + positioning note, logging §10 delta.*
