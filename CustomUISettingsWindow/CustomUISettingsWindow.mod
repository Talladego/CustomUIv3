<?xml version="1.0" encoding="UTF-8"?>
<ModuleFile xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" >

    <UiMod name="CustomUISettingsWindow" version="1.1" date="4/20/2026" >
        <Author name="Talladego" email="" />
        <Description text="This module contains the Custom UI Settings Window." />
        <Dependencies>        
			<Dependency name="EA_SettingsWindow" />
            <Dependency name="EATemplate_DefaultWindowSkin" />
            <Dependency name="EASystem_Utils" />
            <Dependency name="EASystem_ActionBarClusterManager" optional="true" />
            <Dependency name="EASystem_AdvancedWindowManager" optional="true"/>
            <Dependency name="EA_Window_Help" optional="true"/>
            <Dependency name="CustomUI" />
        </Dependencies>
        <Files>
            <!-- <File name="Textures/SettingsWindowTextures.xml" /> -->
            <File name="Source/CustomUISettingsWindowTemplates.xml" />
            <File name="Source/CustomUISettingsWindowTabPlayer.xml" />
            <File name="Source/CustomUISettingsWindowTabTarget.xml" />
            <File name="Source/CustomUISettingsWindowTabTargetHUD.xml" />
            <File name="Source/CustomUISettingsWindowTabGroup.xml" />
            <File name="Source/CustomUISettingsWindowTabUnitFrames.xml" />
            <File name="Source/CustomUISettingsWindowTabGroupIcons.xml" />
            <File name="Source/CustomUISettingsWindowTabSCT.xml" />
            <File name="Source/CustomUISettingsWindowTabbed.xml" />
        </Files>
        <SavedVariables>
            <!-- <SavedVariable name="SettingsWindowTabInterface.SavedMessageSettings" /> -->
            <!-- <SavedVariable name="SettingsWindowTabServer.SavedSettings" />			 -->
        </SavedVariables>
        <OnInitialize>
            <CreateWindow name="CustomUISettingsWindowTabbed" show="true" />
        </OnInitialize>             
    </UiMod>
    
</ModuleFile>    