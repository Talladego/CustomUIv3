if not CustomUI then
    CustomUI = {}
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
    CustomUI.PrintMessage(L"Commands: /customui, /customui status, /customui components, /customui enable <name>, /customui disable <name>, /customui toggle <name>, /customui help")
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
		WindowUtils.ToggleShowing( "CustomUISettingsWindowTabbed" )
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
}

local function EnsureRootWindowInstances()
    if type(CreateWindow) ~= "function" then
        return
    end

    for i = 1, #ROOT_WINDOW_NAMES do
        local w = ROOT_WINDOW_NAMES[i]
        if type(DoesWindowExist) ~= "function" or not DoesWindowExist(w) then
            CreateWindow(w, false)
        end
    end
end

function CustomUI.Initialize()
    if CustomUI.State.initialized then
        return
    end

    EnsureRootWindowInstances()

    CustomUI.State.initialized = true
    CustomUI.State.loadCount = CustomUI.State.loadCount + 1
    CustomUI.State.slashRegistered = false

    CustomUI.RegisterSlashCommands()
    CustomUI.InitializeComponents()
    CustomUI.PrintStatusMessage()
end

function CustomUI.Shutdown()
    if not CustomUI.State.initialized then
        return
    end

    CustomUI.UnregisterSlashCommands()
    CustomUI.ShutdownComponents()

    CustomUI.State.initialized = false
end

