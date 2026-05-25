# CustomUI Codebase Refactoring Plan

## Overview
This document outlines the strategy for modularizing the largest monolithic files in the CustomUI codebase. The goal is to separate concerns (Data, View, and Controller logic), improve maintainability, reduce file sizes, and make future enhancements easier.

---

## 1. UnitFrames Refactoring
**Current File:** `Source\Components\UnitFrames\Controller\UnitFramesController.lua` (~3,000 lines)
**Issue:** Handles everything from engine event hooking and data hydration (party, warband, scenario) to complex sorting, overhead map distance scanning, and UI rendering.

**New Structure:**
*   **`UnitFramesData.lua`**
    *   *Responsibilities:* Data retrieval and hydration.
    *   *Contents:* Fetching data from `PartyUtils`, `GetBattlegroupMemberData()`, and `GameData.GetScenarioPlayerGroups()`. Contains the complex scenario hits merging and overhead map distance calculations.
*   **`UnitFramesSort.lua`**
    *   *Responsibilities:* Array sorting algorithms.
    *   *Contents:* The specific role-based sorting logic (`SortMembersForUnitFramesDisplay`, `UnitFramesGetEffectiveArchetypeForPlayer`).
*   **`UnitFramesView.lua`**
    *   *Responsibilities:* UI manipulation.
    *   *Contents:* UI rendering helpers (e.g., `SetMemberHpBarValues`, `ApplyStatusSettings`, `SetCareerIcon`, layouts for crowns and rings).
*   **`UnitFramesController.lua`**
    *   *Responsibilities:* Orchestration.
    *   *Contents:* Hooks into `SystemData.Events`, listens to settings changes, asks `UnitFramesData` for the state, passes state to `UnitFramesSort`, and instructs `UnitFramesView` to render.

---

## 2. Scrolling Combat Text (SCT) Overrides
**Current File:** `Source\Components\SCT\Controller\SCTOverrides.lua` (~1,600 lines)
**Issue:** Combines the logic for parsing and applying combat event overrides with massive, hardcoded configuration tables for specific abilities and formatting rules.

**New Structure:**
*   **`SCTOverrideData.lua`**
    *   *Responsibilities:* Pure data storage.
    *   *Contents:* Large tables mapping ability IDs to custom text, icons, colors, or formatting instructions.
*   **`SCTOverrides.lua`**
    *   *Responsibilities:* Logic and application.
    *   *Contents:* Functions that intercept `SCT` events, look up entries in `SCTOverrideData`, and apply the necessary transformations to the combat text payload before rendering.

---

## 3. Group Icons Refactoring
**Current File:** `Source\Components\GroupIcons\Controller\GroupIconsController.lua` (~1,550 lines)
**Issue:** Tightly couples three different concerns: rendering icons for your group, tracking outsiders (hostiles/friendlies) via an LRU/FIFO pool, and performing a spatial probe for screen attachment.

**New Structure:**
*   **`GroupIconsSpatialProbe.lua`**
    *   *Responsibilities:* Screen projection and validation.
    *   *Contents:* The AutoMark-style coordinate calibration (`CalibrateGroupIconsWorldProbeAnchors`) and `WorldObjectSpatialProbeIsGone` logic used to detect if a world object is off-screen or dead.
*   **`GroupIconsOutsiderTracker.lua`**
    *   *Responsibilities:* Tracking non-group members.
    *   *Contents:* The TargetInfo FIFO pool (`c_MAX_TRACKED_OUTSIDERS`), eviction logic, and ring rendering for enemies or friendly outsiders.
*   **`GroupIconsRoster.lua`**
    *   *Responsibilities:* Group member icons.
    *   *Contents:* Logic for attaching icons to your own Party/Warband/Scenario members, handling crowns, and archetype tints.
*   **`GroupIconsController.lua`**
    *   *Responsibilities:* Initialization and Event Routing.
    *   *Contents:* Core event loop (`OnUpdate`), routing `TargetInfo` updates to the `OutsiderTracker`, and party updates to the `Roster`.

---

## 4. Buff Tracker Refactoring
**Current File:** `Source\Shared\BuffTracker\BuffTracker.lua` (~1,500 lines)
**Issue:** Manages buff cache retrieval, sorting, an internal memory pooling system to reduce garbage collection, and raw UI widget anchoring/rendering.

**New Structure:**
*   **`BuffTrackerMemory.lua`**
    *   *Responsibilities:* Memory allocation and GC avoidance.
    *   *Contents:* The `_GetTableFromPool` and `_ReleaseTableToPool` logic.
*   **`BuffTrackerLayout.lua`**
    *   *Responsibilities:* Visual arrangement of buffs.
    *   *Contents:* Icon grid math, `WindowAddAnchor`, dimensions scaling, tooltip hooking, and visual duration formatting.
*   **`BuffTracker.lua`**
    *   *Responsibilities:* Core tracker logic.
    *   *Contents:* Cache polling (`Refresh`), buff filtering, and triggering the layout engine when the duration buckets change.

---

## Implementation Checklist

For each module being refactored, follow these steps strictly to ensure nothing breaks:

1.  **Extract Data/Views:** Move tables and pure functions to the new files.
2.  **Expose via Namespace:** Assign the extracted functions and tables to the shared global namespace (e.g., `CustomUI.UnitFrames.Data.GetRoster()`) so the core controller can reach them.
3.  **Update Manifest:** Add the new `.lua` files to `CustomUI.mod` (and optionally `CustomUISettingsWindow.mod` if shared there) in the correct loading order. **Data/Helpers must load before Controllers.**
4.  **Wire Up Controller:** Replace the old local implementations in the Controller with calls to the new namespaced modules.
5.  **Test:** Run the specific feature in-game, verifying no nil-reference errors occur during `OnUpdate` or initialization loops.