<?xml version="1.0" encoding="UTF-8"?>
<ModuleFile xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
    <UiMod name="CustomUI" version="1.0" date="13/04/2026">
        <Author name="" email="" />
        <Description text="Boilerplate addon scaffold for CustomUI." />
        <Dependencies>
            <!-- Common core: shared utility helpers used throughout the default UI code. -->
            <Dependency name="EASystem_Utils" />
            <!-- Common core: generic window helper functions and show/hide toggles. -->
            <Dependency name="EASystem_WindowUtils" />
            <!-- Common core: default frame/title/button templates used by CustomUI windows. -->
            <Dependency name="EATemplate_DefaultWindowSkin" />
            <!-- PlayerStatusWindow component: status bar/unit frame templates used by the copied player frame. -->
            <Dependency name="EATemplate_UnitFrames" />
            <!-- PlayerStatusWindow component: legacy template assets still referenced by the stock copy. -->
            <Dependency name="EA_LegacyTemplates" />
            <!-- PlayerStatusWindow component: tooltip helpers used by mouseover handlers. -->
            <Dependency name="EASystem_Tooltips" />
            <!-- PlayerStatusWindow component: layout editor registration for moving/saving the window position. -->
            <Dependency name="EASystem_LayoutEditor" />
            <!-- PlayerStatusWindow component: references player tactic/career context used by stock logic. -->
            <Dependency name="EA_TacticsWindow" />
            <!-- PlayerStatusWindow component: ensures stock player status resources are loaded so this component can reuse default assets. -->
            <Dependency name="EA_PlayerStatusWindow" />
            <!-- GroupWindow component: ensures stock group window assets are loaded so member rows render correctly. -->
            <Dependency name="EA_GroupWindow" />
            <!-- Common optional: slash command registration for /customui and /cui control commands. -->
            <Dependency name="LibSlash" optional="true" />
            <Dependency name="EA_CareerResourcesWindow" />
            <!-- SCT component: ensures stock easystem_eventtext loads first so our overrides apply last. -->
            <Dependency name="EASystem_EventText" />
        </Dependencies>
        <Files>
            <File name="Source/CustomUI.lua" />
            <!-- Shared: loaded before any component that depends on them -->
            <File name="Source/Shared/Shared.xml" />
            <File name="Source/Shared/BuffTracker/BuffTracker.lua" />
            <File name="Source/Shared/BuffTracker/BuffGroups.lua" />
            <File name="Source/Shared/BuffTracker/Blacklist.lua" />
            <File name="Source/Shared/BuffTracker/Whitelist.lua" />
            <File name="Source/Shared/UnitFrame/TargetFrame.lua" />
            <File name="Source/Components/PlayerStatusWindow/Controller/PlayerStatusWindowController.lua" />
            <File name="Source/Components/PlayerStatusWindow/View/PlayerStatusWindow.xml" />
            <File name="Source/Components/TargetWindow/Controller/TargetWindowController.lua" />
            <File name="Source/Components/TargetWindow/View/TargetWindow.xml" />
            <File name="Source/Components/PlayerStatusWindow/Controller/PlayerPetWindowController.lua" />
            <File name="Source/Components/PlayerStatusWindow/View/PlayerPetWindow.xml" />
            <File name="Source/Components/TargetHUD/Controller/TargetHUDController.lua" />
            <File name="Source/Components/TargetHUD/View/TargetHUD.xml" />
            <File name="Source/Components/GroupWindow/Controller/GroupWindowController.lua" />
            <File name="Source/Components/GroupWindow/Controller/GroupWindowTestHarness.lua" />
            <File name="Source/Components/GroupWindow/View/GroupWindow.xml" />
            <File name="Source/Components/UnitFrames/Controller/UnitFramesModel.lua" />
            <File name="Source/Components/UnitFrames/Controller/UnitFramesEvents.lua" />
            <File name="Source/Components/UnitFrames/Controller/UnitFramesRenderer.lua" />
            <File name="Source/Components/UnitFrames/Controller/Adapters/WarbandAdapter.lua" />
            <File name="Source/Components/UnitFrames/Controller/Adapters/ScenarioFloatingAdapter.lua" />
            <File name="Source/Components/UnitFrames/Controller/UnitFramesController.lua" />
            <File name="Source/Components/UnitFrames/View/UnitFrames.xml" />
            <File name="Source/Components/GroupIcons/Controller/GroupIconsController.lua" />
            <File name="Source/Components/GroupIcons/View/GroupIcons.xml" />
            <!-- SCT component (v2 load order) -->
            <File name="Source/Components/SCT/Controller/SCTSettings.lua" />
            <File name="Source/Components/SCT/Controller/SCTAbilityIconCache.lua" />
            <File name="Source/Components/SCT/View/CustomUI_EventTextLabel.xml" />
            <File name="Source/Components/SCT/View/CustomUI_SCTAbilityNameSuffix.xml" />
            <File name="Source/Components/SCT/View/SCTAbilityIcon.xml" />
            <File name="Source/Components/SCT/Controller/SCTAnim.lua" />
            <File name="Source/Components/SCT/Controller/SCTOverrides.lua" />
            <File name="Source/Components/SCT/Controller/SCTHandlers.lua" />
            <File name="Source/Components/SCT/Controller/SCTController.lua" />
            <File name="Source/Components/SCT/View/SCT.xml" />
            <!-- LEGACY (v2 SCT, 2026-04-25): superseded by SCTOverrides.lua. Remove in Step 5b. -->
            <!-- <File name="Source/Components/SCT/Controller/SCTAnchors.lua" /> -->
            <!-- <File name="Source/Components/SCT/Controller/SCTEntry.lua" /> -->
            <!-- <File name="Source/Components/SCT/Controller/SCTTracker.lua" /> -->
        </Files>
        <OnInitialize>
            <!-- Component root windows: instantiated in Source/CustomUI.lua (EnsureRootWindowInstances) -->
            <CallFunction name="CustomUI.Initialize" />
        </OnInitialize>
        <OnShutdown>
            <CallFunction name="CustomUI.Shutdown" />
        </OnShutdown>
        <SavedVariables>
            <SavedVariable name="CustomUI.Settings" />
        </SavedVariables>
    </UiMod>
</ModuleFile>