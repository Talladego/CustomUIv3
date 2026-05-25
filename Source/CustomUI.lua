if not CustomUI then
    CustomUI = {}
end

-- Developer diagnostics: client `d()`, LogLuaMessage DEBUG, and optional WARNING mirrors.
-- Set `CustomUI.DebugLogging = true` in-game (or via a tiny loader) to re-enable.
if CustomUI.DebugLogging == nil then
    CustomUI.DebugLogging = false
end

CustomUI.Name = "CustomUI"
CustomUI.Version = "1.0"
CustomUI.SlashCommands = CustomUI.SlashCommands or { "customui", "cui" }
CustomUI.Components = CustomUI.Components or {}
CustomUI.ComponentOrder = CustomUI.ComponentOrder or {}
CustomUI.Settings = CustomUI.Settings or { Components = {} }
-- Old saves can supply CustomUI.Settings without a Components table; RegisterComponent/Enable use it.
if type(CustomUI.Settings) == "table" and CustomUI.Settings.Components == nil then
    CustomUI.Settings.Components = {}
end
CustomUI.State = CustomUI.State or
{
    initialized = false,
    loadCount = 0,
    slashRegistered = false,
}

CustomUI.FollowLeader = CustomUI.FollowLeader or
{
    macroName = "CustomUI Follow Leader",
    macroIcon = 49,
    leaderName = L"",
    trackedSlots = {},
    fullSlotsWarned = false,
    handlersRegistered = false,
}

local m_stockActionButtonOnLButtonUp = nil
local g_followActionButtonOnLButtonUpWrapper = nil

-- Controller / View (per component under Source/Components/<Name>/):
--   Controller: owns state, RegisterComponent, lifecycle (Initialize, Enable, Disable, Shutdown),
--   engine event/hook registration, and coordination with Shared/. Call View helpers when present.
--   View: optional View/<Name>.lua for labels, tooltips, and other presentation-only code; XML
--   event targets may live in View or (for stock-frame-heavy components) on the same namespace
--   from the controller when no View lua exists. See README.md and .cursor/rules/customui.mdc.
--   Load order: list Controller/*.lua before View/*.xml in CustomUI.mod; do not re-<Script> the
--   same *Controller.lua inside that template (PlayerStatusWindow.xml is the exception: it loads
--   only View/PlayerStatusWindow.lua after the mod already loaded the controller).
--   Root window instances: first step of CustomUI.Initialize (EnsureRootWindowInstances); .mod
--   lists files only—no <CreateWindow> in the manifest.
--
-- Settings UI: ship in the separate CustomUISettingsWindow addon (window CustomUISettingsWindowTabbed).
-- Removed legacy paths: CustomUI.SettingsWindow / MiniSettingsWindow, Source/Settings,
--   in-addon View/*Tab.xml, and CustomUI.<Name>.Tab. Do not reintroduce them; add
--   settings UI in CustomUISettingsWindow only.

local function CallComponentHandler(component, handlerName)
    local handler = component and component[handlerName]

    if type(handler) == "function" then
        local result = handler(component)
        -- Handlers that do not return a value are treated as success.
        return result ~= false
    end

    return true
end

local function CountRegisteredComponents()
    return #CustomUI.ComponentOrder
end

local function NormalizeComponentName(componentName)
    if type(componentName) ~= "string" then
        return nil
    end

    local trimmedName = componentName:match("^%s*(.-)%s*$")

    if trimmedName == "" then
        return nil
    end

    local loweredName = string.lower(trimmedName)

    if loweredName == "hostiletargetwindow" or loweredName == "friendlytargetwindow" then
        loweredName = "targetwindow"
    end

    for _, registeredName in ipairs(CustomUI.ComponentOrder) do
        if string.lower(registeredName) == loweredName then
            return registeredName
        end
    end

    if loweredName == "targetwindow" then
        return "TargetWindow"
    end

    return trimmedName
end

local function ResolveTargetWindowDefaultEnabled(defaultEnabled)
    if defaultEnabled == true then
        return true
    end

    if CustomUI.Settings.Components.TargetWindow ~= nil then
        return CustomUI.Settings.Components.TargetWindow == true
    end

    if CustomUI.Settings.Components.HostileTargetWindow == true
    or CustomUI.Settings.Components.FriendlyTargetWindow == true then
        return true
    end

    return false
end

local function ResetWindowToDefault(windowName)
    if type(windowName) ~= "string" or windowName == "" then
        return
    end

    if type(LayoutEditor) == "table"
    and type(LayoutEditor.Settings) == "table" then
        LayoutEditor.Settings[windowName] = nil

        if type(LayoutEditor.windowsList) == "table"
        and LayoutEditor.windowsList[windowName] ~= nil then
            local windowData = LayoutEditor.windowsList[windowName]
            windowData.isLocked = false

            if windowData.isDefaultHidden == true then
                LayoutEditor.UserHide(windowName)
            else
                LayoutEditor.UserShow(windowName)
            end
        end
    end

    if DoesWindowExist(windowName) then
        WindowRestoreDefaultSettings(windowName)
    end
end

local function CountEnabledComponents()
    local enabledCount = 0

    for _, componentName in ipairs(CustomUI.ComponentOrder) do
        if CustomUI.IsComponentEnabled(componentName) then
            enabledCount = enabledCount + 1
        end
    end

    return enabledCount
end

function CustomUI.GetRegisteredComponentCount()
    return CountRegisteredComponents()
end

function CustomUI.GetEnabledComponentCount()
    return CountEnabledComponents()
end

function CustomUI.GetComponentStatusText()
    local registeredCount = CountRegisteredComponents()
    local enabledCount = CountEnabledComponents()

    if registeredCount == 0 then
        return L"components: none registered"
    end

    return L"components: " .. towstring(enabledCount) .. L"/" .. towstring(registeredCount) .. L" enabled"
end

function CustomUI.PrintMessage(message)
    if type(message) == "string" then
        message = towstring(message)
    end

    if type(message) ~= "wstring" then
        return
    end

    local output = L"[CustomUI] " .. message

    if EA_ChatWindow and EA_ChatWindow.Print then
        EA_ChatWindow.Print(output)
        return
    end

    TextLogAddEntry("Chat", 0, output)
end

--- Optional client debug hook (`d`). Do not assign global `d` from addons; read-only via this accessor (README).
function CustomUI.GetClientDebugLog()
    return rawget(_G, "d")
end

--- SCT / diagnostic trace when `CustomUI.DebugLogging` is true: uses client `d()` if present, otherwise DEBUG `LogLuaMessage` (Low #16 — visible without `d`).
function CustomUI.SCTLog(message)
    if CustomUI.DebugLogging ~= true then
        return
    end
    if type(message) == "string" then
        message = towstring(message)
    end
    if type(message) ~= "wstring" then
        return
    end
    local dfn = CustomUI.GetClientDebugLog()
    if type(dfn) == "function" then
        dfn(message)
        return
    end
    if LogLuaMessage and SystemData and SystemData.UiLogFilters then
        LogLuaMessage("Lua", SystemData.UiLogFilters.DEBUG, L"[CustomUI.SCT] " .. message)
    end
end

function CustomUI.PrintStatusMessage()
    local message = L"v" .. towstring(CustomUI.Version) .. L" loaded, " .. CustomUI.GetComponentStatusText()
    CustomUI.PrintMessage(message)
end

function CustomUI.PrintComponentStatuses()
    if CountRegisteredComponents() == 0 then
        CustomUI.PrintMessage(L"No components registered.")
        return
    end

    for _, componentName in ipairs(CustomUI.ComponentOrder) do
        local statusText = L"disabled"

        if CustomUI.IsComponentEnabled(componentName) then
            statusText = L"enabled"
        end

        CustomUI.PrintMessage(towstring(componentName) .. L": " .. statusText)
    end
end

function CustomUI.PrintHelp()
    CustomUI.PrintMessage(L"Commands: /customui, /customui status, /customui components, /customui enable <name>, /customui disable <name>, /customui toggle <name>, /customui clear icon cache, /customui followmacro, /customui help")
end

local function NormalizePlayerName(nameValue)
    if nameValue == nil then
        return L""
    end

    local n = tostring(nameValue)
    local pos = string.find(n, "^", 1, true)
    if pos then
        n = string.sub(n, 1, pos - 1)
    end
    n = n:gsub("^%s+", ""):gsub("%s+$", "")
    return towstring(n)
end

local function BuildFollowLeaderMacroText(leaderName)
    return L"/follow"
end

local function GetMacroId(macroName)
    local macros = GetMacrosData and GetMacrosData() or {}
    local expected = towstring(macroName)
    for i = 1, #macros do
        if macros[i].name == expected then
            return i
        end
    end
    return nil
end

local function GetMacroSlots(macroId)
    local slots = {}
    if not macroId or not ActionBars or not ActionBars.m_Bars then
        return slots
    end
    for i = 1, #ActionBars.m_Bars do
        local bar = ActionBars.m_Bars[i]
        for j = 1, #(bar.m_Buttons or {}) do
            local b = bar.m_Buttons[j]
            if b and b.m_ActionType == GameData.PlayerActions.DO_MACRO and b.m_ActionId == macroId then
                slots[#slots + 1] = b.m_HotBarSlot
            end
        end
    end
    return slots
end

local function IsFollowLeaderMacroSlot(slot)
    if type(slot) ~= "number" then
        return false
    end

    local slots = CustomUI.FollowLeader.trackedSlots or {}
    for i = 1, #slots do
        if slots[i] == slot then
            return true
        end
    end

    local macroId = GetMacroId(CustomUI.FollowLeader.macroName)
    if not macroId then
        return false
    end

    slots = GetMacroSlots(macroId)
    if #slots > 0 then
        CustomUI.FollowLeader.trackedSlots = slots
    end

    for i = 1, #slots do
        if slots[i] == slot then
            return true
        end
    end

    return false
end

local function InstallFollowLeaderActionHook()
    if m_stockActionButtonOnLButtonUp ~= nil then
        return
    end
    if type(ActionButton) ~= "table" or type(ActionButton.OnLButtonUp) ~= "function" then
        return
    end

    m_stockActionButtonOnLButtonUp = ActionButton.OnLButtonUp
    g_followActionButtonOnLButtonUpWrapper = function(self, flags, x, y)
        local shouldFollowOnClick = self and type(self.GetSlot) == "function" and not Cursor.IconOnCursor()
            and IsFollowLeaderMacroSlot(self:GetSlot())

        local ok, r1, r2, r3, r4, r5 = pcall(m_stockActionButtonOnLButtonUp, self, flags, x, y)

        if shouldFollowOnClick then
            SendChatText(L"/follow ", L"")
        end

        if not ok then
            if CustomUI.DebugLogging == true then
                LogLuaMessage("Lua", SystemData.UiLogFilters.WARNING,
                    L"[CustomUI] ActionButton.OnLButtonUp stock error: " .. towstring(r1))
            end
            return
        end

        return r1, r2, r3, r4, r5
    end

    ActionButton.OnLButtonUp = g_followActionButtonOnLButtonUpWrapper
end

local function RestoreFollowLeaderActionHook()
    if m_stockActionButtonOnLButtonUp == nil then
        return
    end

    if type(ActionButton) == "table" and ActionButton.OnLButtonUp == g_followActionButtonOnLButtonUpWrapper then
        ActionButton.OnLButtonUp = m_stockActionButtonOnLButtonUp
    end

    g_followActionButtonOnLButtonUpWrapper = nil
    m_stockActionButtonOnLButtonUp = nil
end

local function ApplyFollowLeaderActionToMacroSlots(macroName, leaderName)
    local macroId = GetMacroId(macroName)
    if not macroId then
        CustomUI.FollowLeader.trackedSlots = {}
        return
    end
    local slots = GetMacroSlots(macroId)
    if #slots > 0 then
        CustomUI.FollowLeader.trackedSlots = slots
    else
        slots = CustomUI.FollowLeader.trackedSlots or {}
    end
    for i = 1, #slots do
        local hbar, buttonId = ActionBars:BarAndButtonIdFromSlot(slots[i])
        local button = hbar and hbar.m_Buttons and hbar.m_Buttons[buttonId]
        if button and button.m_Name then
            local actionWindow = button.m_Name .. "Action"
            if leaderName ~= nil and leaderName ~= L"" then
                WindowSetGameActionData(actionWindow, GameData.PlayerActions.SET_TARGET, 0, leaderName)
            else
                WindowSetGameActionData(actionWindow, GameData.PlayerActions.DO_MACRO, macroId, L"")
            end
        end
    end
end

local function GetCurrentFriendlyTargetName()
    if type(TargetInfo) ~= "table" or type(TargetInfo.UpdateFromClient) ~= "function" or type(TargetInfo.UnitName) ~= "function" then
        return L""
    end
    TargetInfo:UpdateFromClient()
    return NormalizePlayerName(TargetInfo:UnitName("selffriendlytarget"))
end

local function ResolveCurrentLeaderName()
    local playerName = NormalizePlayerName(GameData and GameData.Player and GameData.Player.name)

    if IsWarBandActive and IsWarBandActive() and not (GameData and GameData.Player and GameData.Player.isInScenario) then
        local info = PartyUtils and PartyUtils.GetWarbandLeader and PartyUtils.GetWarbandLeader()
        local wbLeaderName = NormalizePlayerName(info and info.name)
        if wbLeaderName ~= L"" and wbLeaderName ~= playerName then
            return wbLeaderName
        end
        return L""
    end

    local partyData = PartyUtils and PartyUtils.GetPartyData and PartyUtils.GetPartyData() or {}
    for _, memberData in ipairs(partyData) do
        if memberData and memberData.isGroupLeader and memberData.name then
            local partyLeaderName = NormalizePlayerName(memberData.name)
            if partyLeaderName ~= L"" and partyLeaderName ~= playerName then
                return partyLeaderName
            end
        end
    end

    return L""
end

local function UpdateMacroDefinition(macroName, macroText, macroIcon)
    if type(GetMacrosData) ~= "function" or type(SetMacroData) ~= "function" then
        return false
    end

    local macros = GetMacrosData() or {}
    local targetName = towstring(macroName)
    local macroSlot = nil

    for i = 1, #macros do
        local row = macros[i]
        if row.name == targetName then
            macroSlot = i
            break
        elseif row.iconNum == 0 and macroSlot == nil then
            macroSlot = i
        end
    end

    if macroSlot ~= nil then
        SetMacroData(targetName, macroText, macroIcon, macroSlot)
        CustomUI.FollowLeader.fullSlotsWarned = false
        return true
    end

    if not CustomUI.FollowLeader.fullSlotsWarned then
        CustomUI.PrintMessage(L"Could not create Follow Leader macro because all macro slots are full.")
        CustomUI.FollowLeader.fullSlotsWarned = true
    end
    return false
end

function CustomUI.RefreshFollowLeaderMacro()
    local leaderName = ResolveCurrentLeaderName()
    CustomUI.FollowLeader.leaderName = leaderName
    local text = BuildFollowLeaderMacroText(leaderName)
    UpdateMacroDefinition(CustomUI.FollowLeader.macroName, text, CustomUI.FollowLeader.macroIcon)
    ApplyFollowLeaderActionToMacroSlots(CustomUI.FollowLeader.macroName, leaderName)
end

function CustomUI.OnFollowLeaderStateChanged()
    CustomUI.RefreshFollowLeaderMacro()
end

function CustomUI.RegisterFollowLeaderHandlers()
    if CustomUI.FollowLeader.handlersRegistered then
        return
    end

    RegisterEventHandler(SystemData.Events.GROUP_SET_LEADER,                   "CustomUI.OnFollowLeaderStateChanged")
    RegisterEventHandler(SystemData.Events.GROUP_PLAYER_ADDED,                 "CustomUI.OnFollowLeaderStateChanged")
    RegisterEventHandler(SystemData.Events.PLAYER_GROUP_LEADER_STATUS_UPDATED, "CustomUI.OnFollowLeaderStateChanged")
    RegisterEventHandler(SystemData.Events.GROUP_ACCEPT_INVITATION,            "CustomUI.OnFollowLeaderStateChanged")
    RegisterEventHandler(SystemData.Events.BATTLEGROUP_ACCEPT_INVITATION,      "CustomUI.OnFollowLeaderStateChanged")
    RegisterEventHandler(SystemData.Events.GROUP_SETTINGS_UPDATED,             "CustomUI.OnFollowLeaderStateChanged")
    RegisterEventHandler(SystemData.Events.GROUP_LEAVE,                        "CustomUI.OnFollowLeaderStateChanged")
    RegisterEventHandler(SystemData.Events.BATTLEGROUP_UPDATED,                "CustomUI.OnFollowLeaderStateChanged")

    InstallFollowLeaderActionHook()

    CustomUI.FollowLeader.handlersRegistered = true
end

function CustomUI.UnregisterFollowLeaderHandlers()
    if not CustomUI.FollowLeader.handlersRegistered then
        return
    end

    UnregisterEventHandler(SystemData.Events.GROUP_SET_LEADER,                   "CustomUI.OnFollowLeaderStateChanged")
    UnregisterEventHandler(SystemData.Events.GROUP_PLAYER_ADDED,                 "CustomUI.OnFollowLeaderStateChanged")
    UnregisterEventHandler(SystemData.Events.PLAYER_GROUP_LEADER_STATUS_UPDATED, "CustomUI.OnFollowLeaderStateChanged")
    UnregisterEventHandler(SystemData.Events.GROUP_ACCEPT_INVITATION,            "CustomUI.OnFollowLeaderStateChanged")
    UnregisterEventHandler(SystemData.Events.BATTLEGROUP_ACCEPT_INVITATION,      "CustomUI.OnFollowLeaderStateChanged")
    UnregisterEventHandler(SystemData.Events.GROUP_SETTINGS_UPDATED,             "CustomUI.OnFollowLeaderStateChanged")
    UnregisterEventHandler(SystemData.Events.GROUP_LEAVE,                        "CustomUI.OnFollowLeaderStateChanged")
    UnregisterEventHandler(SystemData.Events.BATTLEGROUP_UPDATED,                "CustomUI.OnFollowLeaderStateChanged")

    RestoreFollowLeaderActionHook()

    CustomUI.FollowLeader.handlersRegistered = false
end

function CustomUI.RegisterSlashCommands()
    if CustomUI.State.slashRegistered or LibSlash == nil then
        return
    end

    for _, slashCommand in ipairs(CustomUI.SlashCommands) do
        LibSlash.RegisterSlashCmd(slashCommand, CustomUI.HandleSlashCommand)
    end

    CustomUI.State.slashRegistered = true
end

function CustomUI.UnregisterSlashCommands()
    if not CustomUI.State.slashRegistered or LibSlash == nil then
        return
    end

    for _, slashCommand in ipairs(CustomUI.SlashCommands) do
        LibSlash.UnregisterSlashCmd(slashCommand)
    end

    CustomUI.State.slashRegistered = false
end

function CustomUI.HandleSlashCommand(input)
    local command = "status"
    local argument = nil
    local trimmedInput = ""

    if type(input) == "string" then
        trimmedInput = input:match("^%s*(.-)%s*$")

        if trimmedInput ~= "" then
            local parsedCommand, parsedArgument = trimmedInput:match("^(%S+)%s*(.-)$")
            command = string.lower(parsedCommand or command)
            argument = parsedArgument
        end
    end

    if CustomUI.GroupWindowTestHarness
    and type(CustomUI.GroupWindowTestHarness.HandleSlashCommand) == "function"
    and CustomUI.GroupWindowTestHarness.HandleSlashCommand(trimmedInput) then
        return
    end

    if trimmedInput == "" then
        if type(CustomUI.ShowSettings) == "function" then
            CustomUI.ShowSettings()
        else
            if CustomUI.PrintMessage then
                CustomUI.PrintMessage(L"Settings module not installed.")
            end
        end
        return
    end

    if trimmedInput == "mini" then
        if CustomUI.PrintMessage then
            CustomUI.PrintMessage(L"Open /cui for CustomUI settings.")
        end
        return
    end

    if command == "status" then
        CustomUI.PrintStatusMessage()
        CustomUI.PrintComponentStatuses()
        return
    end

    if command == "components" then
        CustomUI.PrintComponentStatuses()
        return
    end

    if command == "help" then
        CustomUI.PrintHelp()
        return
    end

    if command == "followmacro" then
        CustomUI.RefreshFollowLeaderMacro()
        if CustomUI.FollowLeader.leaderName ~= L"" then
            CustomUI.PrintMessage(L"Follow Leader macro updated for: " .. CustomUI.FollowLeader.leaderName)
        else
            CustomUI.PrintMessage(L"Follow Leader macro updated (no party/warband leader detected; follows current target).")
        end
        return
    end

    if command == "clear" then
        local arg = string.lower(string.gsub((argument or ""):match("^%s*(.-)%s*$") or "", "%s+", " "))
        if arg == "icon cache" then
            if CustomUI.SCT and type(CustomUI.SCT.AbilityIconCacheClearAll) == "function" then
                CustomUI.SCT.AbilityIconCacheClearAll()
                CustomUI.PrintMessage(L"SCT ability icon cache cleared (session + saved hints).")
            else
                CustomUI.PrintMessage(L"SCT module not loaded; icon cache not cleared.")
            end
            return
        end
    end

    if command == "enable" or command == "disable" or command == "toggle" then
        local componentName = NormalizeComponentName(argument)

        if not componentName or not CustomUI.GetComponent(componentName) then
            CustomUI.PrintMessage(L"Unknown component: " .. towstring(argument or ""))
            return
        end

        local success = false

        if command == "enable" then
            success = CustomUI.EnableComponent(componentName)
        elseif command == "disable" then
            success = CustomUI.DisableComponent(componentName)
        else
            success = CustomUI.ToggleComponent(componentName)
        end

        if success then
            local stateText = L"disabled"

            if CustomUI.IsComponentEnabled(componentName) then
                stateText = L"enabled"
            end

            CustomUI.PrintMessage(towstring(componentName) .. L": " .. stateText)

        else
            CustomUI.PrintMessage(L"Unable to update component: " .. towstring(componentName))
        end

        return
    end

    CustomUI.PrintHelp()
end

function CustomUI.RegisterComponent(componentName, componentTable)
    if type(componentName) ~= "string" or componentName == "" then
        return nil
    end

    if type(componentTable) ~= "table" then
        componentTable = {}
    end

    componentTable.Name = componentName
    componentTable.Initialized = componentTable.Initialized or false
    componentTable.Enabled = componentTable.Enabled or false
    componentTable.DefaultEnabled = componentTable.DefaultEnabled ~= false

    if componentName == "TargetWindow" and CustomUI.Settings.Components[componentName] == nil then
        CustomUI.Settings.Components[componentName] = ResolveTargetWindowDefaultEnabled(componentTable.DefaultEnabled)
        CustomUI.Settings.Components.HostileTargetWindow = nil
        CustomUI.Settings.Components.FriendlyTargetWindow = nil
    elseif CustomUI.Settings.Components[componentName] == nil then
        CustomUI.Settings.Components[componentName] = componentTable.DefaultEnabled
    end

    CustomUI.Components[componentName] = componentTable

    local existsInOrder = false

    for _, registeredName in ipairs(CustomUI.ComponentOrder) do
        if registeredName == componentName then
            existsInOrder = true
            break
        end
    end

    if not existsInOrder then
        table.insert(CustomUI.ComponentOrder, componentName)
    end

    if CustomUI.State.initialized and not componentTable.Initialized then
        CustomUI.InitializeComponent(componentName)

        if CustomUI.IsComponentEnabled(componentName) then
            CustomUI.EnableComponent(componentName)
        end
    end

    return componentTable
end

function CustomUI.GetComponent(componentName)
    return CustomUI.Components[componentName]
end

function CustomUI.IsComponentEnabled(componentName)
    return CustomUI.Settings.Components[componentName] == true
end

function CustomUI.InitializeComponent(componentName)
    local component = CustomUI.Components[componentName]

    if not component or component.Initialized then
        return
    end

    local ok = CallComponentHandler(component, "Initialize")

    if ok then
        component.Initialized = true
    end
end

function CustomUI.EnableComponent(componentName)
    local component = CustomUI.Components[componentName]

    if not component then
        return false
    end

    if not component.Initialized then
        CustomUI.InitializeComponent(componentName)
        if not component.Initialized then
            return false
        end
    end

    if component.Enabled then
        return true
    end

    if CallComponentHandler(component, "Enable") then
        component.Enabled = true
        CustomUI.Settings.Components[componentName] = true
        return true
    end

    return false
end

function CustomUI.DisableComponent(componentName)
    local component = CustomUI.Components[componentName]

    if not component then
        return false
    end

    if component.Initialized then
        local disabled = CallComponentHandler(component, "Disable")
        if not disabled then
            return false
        end
        component.Enabled = false
    end

    CustomUI.Settings.Components[componentName] = false
    return true
end

function CustomUI.SetComponentEnabled(componentName, isEnabled)
    if isEnabled then
        return CustomUI.EnableComponent(componentName)
    end

    return CustomUI.DisableComponent(componentName)
end

function CustomUI.ToggleComponent(componentName)
    return CustomUI.SetComponentEnabled(componentName, not CustomUI.IsComponentEnabled(componentName))
end

function CustomUI.ResetWindowToDefault(windowName)
    ResetWindowToDefault(windowName)
end

function CustomUI.ResetAllToDefaults()
    for _, componentName in ipairs(CustomUI.ComponentOrder) do
        local component = CustomUI.Components[componentName]
        CallComponentHandler(component, "ResetToDefaults")
    end

    for _, componentName in ipairs(CustomUI.ComponentOrder) do
        local component = CustomUI.Components[componentName]
        local defaultEnabled = component ~= nil and component.DefaultEnabled == true
        CustomUI.Settings.Components[componentName] = defaultEnabled
        CustomUI.SetComponentEnabled(componentName, defaultEnabled)
    end

    return true
end

function CustomUI.InitializeComponents()
    for _, componentName in ipairs(CustomUI.ComponentOrder) do
        if CustomUI.IsComponentEnabled(componentName) then
            CustomUI.EnableComponent(componentName)
        end
    end
end

function CustomUI.ShutdownComponents()
    for _, componentName in ipairs(CustomUI.ComponentOrder) do
        local component = CustomUI.Components[componentName]

        if component then
            if component.Enabled then
                CallComponentHandler(component, "Disable")
                component.Enabled = false
            end

            if component.Initialized then
                CallComponentHandler(component, "Shutdown")
                component.Initialized = false
            end
        end
    end
end

-- Top-level window names from View/*.xml loaded by CustomUI.mod. We instantiate them with
-- CreateWindow (same as the former <CreateWindow> list in the .mod) at the first step of
-- CustomUI.Initialize, after all <File> scripts and templates are available but before
-- any component's Initialize runs. This keeps the mod manifest as files only and still
-- guarantees instances exist for disabled components (which never run Initialize) so
-- saved layout, DoesWindowExist, and the layout editor can resolve window names.
local ROOT_WINDOW_NAMES = {
    "CustomUIPlayerStatusWindow",
    "CustomUILowHpScreenFlashWindow",
    -- Sibling overlay in PlayerStatusWindow.xml; must be instantiated here (anchors to CustomUIPlayerStatusWindow).
    "CustomUIPlayerStatusWindowMinimal",
    "CustomUIPlayerPetWindow",
    "CustomUIHostileTargetWindow",
    "CustomUIFriendlyTargetWindow",
    "CustomUIHostileTargetHUD",
    "CustomUIFriendlyTargetHUD",
    "CustomUIGroupWindow",
    "CustomUIUnitFramesRoot",
    "CustomUIUnitFramesGroup1Window",
    "CustomUIUnitFramesGroup2Window",
    "CustomUIUnitFramesGroup3Window",
    "CustomUIUnitFramesGroup4Window",
    "CustomUIUnitFramesGroup5Window",
    "CustomUIUnitFramesGroup6Window",
    "CustomUISCTWindow", -- SCT root placeholder; was not in the old .mod list
    "CustomUIGroupIconsWorldProbe",
    "CustomUIGroupIconsDriver",
    -- Stock vignette overlay (EA_ScreenFlashWindow); CreateWindow is often omitted from the stock mod on RoR.
    "ScreenFlashWindow",
    "CustomUIGlobalUpdateDriver",
}

local originalUpdateFromClient = nil

function CustomUI.OnGlobalUpdate(timePassed)
    CustomUI.TargetUpdateFlag = false
    if type(CustomUI.TargetPresence) == "table"
        and type(CustomUI.TargetPresence.OnGlobalUpdate) == "function" then
        CustomUI.TargetPresence.OnGlobalUpdate(timePassed)
    end
end

local function HookTargetInfo()
    if type(TargetInfo) ~= "table" or type(TargetInfo.UpdateFromClient) ~= "function" or originalUpdateFromClient then
        return
    end

    originalUpdateFromClient = TargetInfo.UpdateFromClient
    TargetInfo.UpdateFromClient = function(self)
        if CustomUI.TargetUpdateFlag then
            return
        end

        local targets = GetUpdatedTargets()
        if targets ~= nil then
            for unitId, targetData in pairs(targets) do
                TargetInfo:SetUnitInfo(unitId, targetData)
            end
            if type(CustomUI.TargetPresence) == "table"
                and type(CustomUI.TargetPresence.OnCacheBatch) == "function" then
                CustomUI.TargetPresence.OnCacheBatch(targets)
            end
        end
        -- Do not ClearUnits() when GetUpdatedTargets() is nil (batch already consumed).
        -- A spurious second UpdateFromClient() was wiping the cache and flickering target UI.

        CustomUI.TargetUpdateFlag = true
    end
end

local function EnsureRootWindowInstances()
    if type(CreateWindow) ~= "function" then
        return
    end

    for i = 1, #ROOT_WINDOW_NAMES do
        local w = ROOT_WINDOW_NAMES[i]
        if type(DoesWindowExist) ~= "function" or not DoesWindowExist(w) then
            CreateWindow(w, w == "CustomUIGlobalUpdateDriver")
        end
    end
end

function CustomUI.Initialize()
    if CustomUI.State.initialized then
        return
    end

    HookTargetInfo()
    EnsureRootWindowInstances()

    CustomUI.State.initialized = true
    CustomUI.State.loadCount = CustomUI.State.loadCount + 1
    CustomUI.State.slashRegistered = false

    CustomUI.RegisterSlashCommands()
    CustomUI.RegisterFollowLeaderHandlers()
    CustomUI.RefreshFollowLeaderMacro()
    CustomUI.InitializeComponents()
    CustomUI.PrintStatusMessage()
end

function CustomUI.Shutdown()
    if not CustomUI.State.initialized then
        return
    end

    CustomUI.UnregisterSlashCommands()
    CustomUI.UnregisterFollowLeaderHandlers()
    CustomUI.ShutdownComponents()

    CustomUI.State.initialized = false
end

