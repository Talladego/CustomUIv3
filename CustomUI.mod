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
            <!-- GroupWindow component: ensures stock group window assets are loaded so member/pet frames render correctly. -->
            <Dependency name="EA_GroupWindow" />
            <!-- Common optional: slash command registration for /customui and /cui control commands. -->
            <Dependency name="LibSlash" optional="true" />
            <Dependency name="EA_CareerResourcesWindow" />
            <!-- SCT component: ensures stock easystem_eventtext loads first so our overrides apply last. -->
            <Dependency name="EASystem_EventText" />
        </Dependencies>
        <Files>
            <File name="Source/CustomUI.lua" />
            <!-- LibConfig libraries (provide in-addon config GUI) -->
            <!-- <File name="LibConfig/LibStub.lua" /> -->
            <!-- <File name="LibConfig/LibGUI.lua" /> -->
            <!-- <File name="LibConfig/LibConfig.lua" /> -->
            <!-- <File name="Source/CustomUIConfig.lua" /> -->
            <!-- <File name="Source/CustomUI_config.lua" /> -->
            <!-- <File name="Source/CustomUIConfigViews.xml" /> -->
            <!-- <File name="Source/CustomUIConfigList.lua" /> -->
            <!-- Shared: loaded before any component that depends on them -->
            <File name="Source/Shared/Shared.xml" />
            <File name="Source/Shared/BuffTracker/BuffTracker.lua" />
            <File name="Source/Shared/BuffTracker/BuffGroups.lua" />
            <File name="Source/Shared/BuffTracker/Blacklist.lua" />
            <File name="Source/Shared/BuffTracker/Whitelist.lua" />
            <File name="Source/Shared/BuffFilterSection.lua" />
            <File name="Source/Shared/UnitFrame/TargetFrame.lua" />
            <!-- <File name="Source/Settings/Controller/MiniSettingsWindowController.lua" /> -->
            <!-- <File name="Source/Settings/View/MiniSettingsWindow.xml" /> -->
            <!-- <File name="Source/Settings/View/SettingsWindow.xml" /> -->
            <!-- <File name="Source/Settings/Controller/SettingsWindowController.lua" /> -->
            <File name="Source/Components/PlayerStatusWindow/Controller/PlayerStatusWindowController.lua" />
            <File name="Source/Components/PlayerStatusWindow/View/PlayerStatusWindow.xml" />
            <!-- LEGACY in-addon settings tab XML (do not add new settings UI here; use CustomUISettingsWindow addon) -->
            <File name="Source/Components/PlayerStatusWindow/View/PlayerStatusWindowTab.xml" />
            <File name="Source/Components/TargetWindow/Controller/TargetWindowController.lua" />
            <File name="Source/Components/TargetWindow/View/TargetWindow.xml" />
            <File name="Source/Components/TargetWindow/View/TargetWindowTab.xml" />
            <File name="Source/Components/PlayerStatusWindow/Controller/PlayerPetWindowController.lua" />
            <File name="Source/Components/PlayerStatusWindow/View/PlayerPetWindow.xml" />
            <File name="Source/Components/TargetHUD/Controller/TargetHUDController.lua" />
            <File name="Source/Components/TargetHUD/View/TargetHUD.xml" />
            <File name="Source/Components/TargetHUD/View/TargetHUDTab.xml" />
            <File name="Source/Components/GroupWindow/Controller/GroupWindowController.lua" />
            <File name="Source/Components/GroupWindow/Controller/GroupWindowTestHarness.lua" />
            <File name="Source/Components/GroupWindow/View/GroupWindow.xml" />
            <File name="Source/Components/GroupWindow/View/GroupWindowTab.xml" />
            <File name="Source/Components/UnitFrames/Controller/UnitFramesModel.lua" />
            <File name="Source/Components/UnitFrames/Controller/UnitFramesEvents.lua" />
            <File name="Source/Components/UnitFrames/Controller/UnitFramesRenderer.lua" />
            <File name="Source/Components/UnitFrames/Controller/Adapters/WarbandAdapter.lua" />
            <File name="Source/Components/UnitFrames/Controller/Adapters/ScenarioFloatingAdapter.lua" />
            <File name="Source/Components/UnitFrames/Controller/UnitFramesController.lua" />
            <File name="Source/Components/UnitFrames/View/UnitFrames.xml" />
            <File name="Source/Components/UnitFrames/View/UnitFramesTab.xml" />
            <File name="Source/Components/GroupIcons/Controller/GroupIconsController.lua" />
            <File name="Source/Components/GroupIcons/View/GroupIcons.xml" />
            <File name="Source/Components/GroupIcons/View/GroupIconsTab.xml" />
            <!-- end LEGACY in-addon settings tab XML -->
            <File name="Source/Components/SCT/Controller/SCTSettings.lua" />
            <File name="Source/Components/SCT/Controller/SCTEventText.lua" />
            <File name="Source/Components/SCT/Controller/SCTController.lua" />
            <File name="Source/Components/SCT/View/SCT.xml" />
        </Files>
        <OnInitialize>
            <!-- <CreateWindow name="CustomUIMiniSettingsWindow" show="false" /> -->
            <CreateWindow name="CustomUIPlayerStatusWindow" show="false" />
            <CreateWindow name="CustomUIPlayerPetWindow" show="false" />
            <CreateWindow name="CustomUIHostileTargetWindow"  show="false" />
            <CreateWindow name="CustomUIFriendlyTargetWindow" show="false" />
            <CreateWindow name="CustomUIHostileTargetHUD"  show="false" />
            <CreateWindow name="CustomUIFriendlyTargetHUD" show="false" />
            <!-- <CreateWindow name="CustomUISettingsWindow" show="false" /> -->
            <!-- <CreateWindow name="CustomUIConfigSCTListWindow" show="false" /> -->
            <CreateWindow name="CustomUIGroupWindow" show="false" />
            <CreateWindow name="CustomUIUnitFramesRoot" show="false" />
            <CreateWindow name="CustomUIUnitFramesGroup1Window" show="false" />
            <CreateWindow name="CustomUIUnitFramesGroup2Window" show="false" />
            <CreateWindow name="CustomUIUnitFramesGroup3Window" show="false" />
            <CreateWindow name="CustomUIUnitFramesGroup4Window" show="false" />
            <CreateWindow name="CustomUIUnitFramesGroup5Window" show="false" />
            <CreateWindow name="CustomUIUnitFramesGroup6Window" show="false" />
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