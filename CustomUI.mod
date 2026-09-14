<?xml version="1.0" encoding="UTF-8"?>
<ModuleFile xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
    <UiMod name="CustomUI" version="1.2.3" date="2026-09-14">
        <Author name="Talladego" email="" />
        <Description text="Modular Return of Reckoning UI replacement addon with component toggles and shared systems." />
        <VersionSettings gameVersion="1.4.8" windowsVersion="1.0" savedVariablesVersion="1.0" />
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
            <!-- Influence badge context menu (Current Area / manual live events). -->
            <Dependency name="EA_ContextMenu" optional="true" />
            <!-- Influence badge: event reward NPC claim snapshots (SelectEventRewards hook). -->
            <Dependency name="EA_InteractionWindow" optional="true" />
            <!-- Optional: stock PQ tracker exposes GetLocalAreaInfluenceID; badge works via GetAreaData if absent. -->
            <Dependency name="EA_ObjectiveTrackers" optional="true" />
            <!-- GroupWindow component: ensures stock group window assets are loaded so member rows render correctly. -->
            <Dependency name="EA_GroupWindow" />
            <!-- TargetWindow component: overrides target window hooks and layout. -->
            <Dependency name="EA_TargetWindow" />
            <!-- TargetWindow component: relies on TargetInfo batch logic from stock targetinfo. -->
            <Dependency name="EASystem_TargetInfo" />
            <!-- Common optional: slash command registration for /customui and /cui control commands. -->
            <Dependency name="LibSlash" optional="true" />
            <Dependency name="EA_CareerResourcesWindow" />
            <!-- SCT component: ensures stock easystem_eventtext loads first so our overrides apply last. -->
            <Dependency name="EASystem_EventText" />
            <!-- KillTracker: Combat TextLog listen + LayoutEditor feed. -->
            <Dependency name="EA_ChatWindow" />
            <!-- GroupIcons: career icon IDs via Icons.* -->
            <Dependency name="EATemplate_Icons" />
            <!-- GroupIcons scenario top damage/heal badges: scoreboard atlas EA_ScenarioSummary01_d8. -->
            <Dependency name="EA_ScenarioSummaryWindow" />
            <!-- QoL RedAlert vignette texture -->
            <Dependency name="EA_ScreenFlashWindow" />
            <!-- QoL AltTracker: backpack money frame + inventory events -->
            <Dependency name="EA_BackpackWindow" />
            <Dependency name="EASystem_ResourceFrames" />
        </Dependencies>
        <Files>
            <File name="Source/CustomUI.lua" />
            <!-- Shared: loaded before any component that depends on them -->
            <File name="Source/Shared/Shared.xml" />
            <File name="Source/Shared/Archetypes.lua" />
            <File name="Source/Shared/BuffTracker/BuffTrackerLayout.lua" />
            <File name="Source/Shared/BuffTracker/BuffTrackerGrouping.lua" />
            <File name="Source/Shared/BuffTracker/BuffTrackerRules.lua" />
            <File name="Source/Shared/BuffTracker/BuffTracker.lua" />
            <File name="Source/Shared/BuffTracker/BuffGroups.lua" />
            <File name="Source/Shared/BuffTracker/BuffLists.lua" />
            <File name="Source/Shared/BuffTracker/BuffFilterDefaults.lua" />
            <File name="Source/Shared/TargetPresence.lua" />
            <File name="Source/Shared/PortraitCareerBadge.lua" />
            <File name="Source/Shared/PortraitInfluenceTrack.lua" />
            <File name="Source/Shared/StockProgressBars.lua" />
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
            <File name="Source/Components/GroupWindow/View/GroupWindow.xml" />
            <File name="Source/Components/UnitFrames/Controller/UnitFramesEvents.lua" />
            <File name="Source/Components/UnitFrames/Controller/UnitFramesArchetypes.lua" />
            <File name="Source/Components/UnitFrames/Controller/UnitFramesSort.lua" />
            <File name="Source/Components/UnitFrames/Controller/UnitFramesRoster.lua" />
            <File name="Source/Components/UnitFrames/Controller/UnitFramesScenario.lua" />
            <File name="Source/Components/UnitFrames/Controller/UnitFramesWarband.lua" />
            <File name="Source/Components/UnitFrames/Controller/UnitFramesController.lua" />
            <File name="Source/Components/UnitFrames/View/UnitFrames.xml" />
            <File name="Source/Components/GroupIcons/Controller/GroupIconsSpatialProbe.lua" />
            <File name="Source/Components/GroupIcons/Controller/GroupIconsWarbandLeaders.lua" />
            <File name="Source/Components/GroupIcons/Controller/GroupIconsOutsiderTracker.lua" />
            <File name="Source/Components/GroupIcons/Controller/GroupIconsRoster.lua" />
            <File name="Source/Components/GroupIcons/Controller/GroupIconsScenarioStats.lua" />
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
            <File name="Source/Components/SCT/Controller/SCTAbilityIconResolver.lua" />
            <File name="Source/Components/SCT/Controller/SCTEventEntry.lua" />
            <File name="Source/Components/SCT/Controller/SCTEventTracker.lua" />
            <File name="Source/Components/SCT/Controller/SCTHandlers.lua" />
            <File name="Source/Components/SCT/Controller/SCTController.lua" />
            <File name="Source/Components/SCT/View/SCT.xml" />
            <!-- KillTracker component -->
            <File name="Source/Components/KillTracker/Controller/KillTrackerParser.lua" />
            <File name="Source/Components/KillTracker/Controller/KillTrackerSession.lua" />
            <File name="Source/Components/KillTracker/Controller/KillTrackerFormat.lua" />
            <File name="Source/Components/KillTracker/Controller/KillTrackerChat.lua" />
            <File name="Source/Components/KillTracker/Controller/KillTrackerCapture.lua" />
            <File name="Source/Components/KillTracker/Controller/KillTrackerWindow.lua" />
            <File name="Source/Components/KillTracker/Controller/KillTrackerController.lua" />
            <File name="Source/Components/KillTracker/View/KillTracker.xml" />
            <!-- AutoFPS component -->
            <File name="Source/Components/AutoFPS/Controller/AutoFPSController.lua" />
            <File name="Source/Components/AutoFPS/View/AutoFPS.xml" />
            <!-- QoL component -->
            <File name="Source/Components/QoL/Controller/QoLAltTrackerData.lua" />
            <File name="Source/Components/QoL/Controller/QoLAltTrackerTooltips.lua" />
            <File name="Source/Components/QoL/Controller/QoLAltTracker.lua" />
            <File name="Source/Components/QoL/View/QoLAltTracker.xml" />
            <File name="Source/Components/QoL/View/QoLAltTrackerGoldPanel.xml" />
            <File name="Source/Components/QoL/Controller/QoLRezzAccept.lua" />
            <File name="Source/Components/QoL/Controller/QoLRedAlert.lua" />
            <File name="Source/Components/QoL/Controller/QoLAutoSurrender.lua" />
            <File name="Source/Components/QoL/Controller/QoLButtonClickSound.lua" />
            <File name="Source/Components/QoL/Controller/QoLController.lua" />
            <File name="Source/Components/QoL/View/QoLRedAlert.xml" />
            <File name="Source/Components/QoL/View/QoLDriver.xml" />
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
            <SavedVariable name="CustomUI_AltTrackerDB" global="true" />
        </SavedVariables>
    </UiMod>
</ModuleFile>