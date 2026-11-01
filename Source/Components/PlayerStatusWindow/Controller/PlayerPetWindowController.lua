----------------------------------------------------------------
-- CustomUI.PlayerPetWindow — Controller
-- Responsibilities:
--   • Suppress stock PetHealthWindow while PlayerStatus is enabled (HP on portrait badge).
--   • Work around stock /reload bug: PetWindow:UpdatePet only FadeIn's the pet action bar
--     when the career window was hidden; after reload the bar often stays hidden even with
--     a live pet (pet data late, or window already "showing" with bar still false).
-- CustomUIPlayerPetFrame is never shown. CustomUI.mod loads this file before View/PlayerPetWindow.xml.
----------------------------------------------------------------

if not CustomUI.PlayerPetWindow then
    CustomUI.PlayerPetWindow = {}
end

----------------------------------------------------------------
-- Constants
----------------------------------------------------------------

local c_WINDOW_NAME = "CustomUIPlayerPetWindow"  -- layout anchor (XML)
local c_FRAME_NAME  = "CustomUIPlayerPetFrame"   -- unit frame (runtime; kept hidden)
local c_PET_ACTION_BAR = "EA_CareerResourceWindowActionBar"
local c_RELOAD_RESYNC_ATTEMPTS = 8
local c_RELOAD_RESYNC_INTERVAL = 0.25

----------------------------------------------------------------
-- Module state
----------------------------------------------------------------

local petFrame = nil
local m_enabled = false

local g_petHealthRegistered = false
local m_stockReplaceTracked = {} -- PetHealthWindow: true if we hid / registered-for-replace
local m_stockUpdatePetProxy = nil
--- Our Lua replacement for `PetWindow.UpdatePet` (C functions cannot hold custom fields — do not index `UpdatePet[...]`).
local g_ourUpdatePetWrapper = nil
local m_resyncing = false
local m_reloadResyncRemaining = 0
local m_reloadResyncElapsed = 0
local m_reloadEventsRegistered = false

local function HideStockPetHealthWindow()
    if DoesWindowExist("PetHealthWindow") then
        WindowSetShowing("PetHealthWindow", false)
    end
end

local function HideCustomPetFrame()
    if petFrame then
        petFrame:Show(false)
    end
    if LayoutEditor and LayoutEditor.Hide then
        LayoutEditor.Hide(c_WINDOW_NAME)
    end
    if DoesWindowExist(c_WINDOW_NAME) then
        WindowSetShowing(c_WINDOW_NAME, false)
    end
end

local function EnsurePetHealthWindowRegistered()
    if g_petHealthRegistered then return end
    if not DoesWindowExist("PetHealthWindow") then return end
    -- Stock never LayoutEditor-registers PetHealthWindow; use a plain name (no "(stock)").
    LayoutEditor.RegisterWindow(
        "PetHealthWindow",
        L"Pet Health",
        L"Pet health window.",
        false,
        false,
        true,
        nil
    )
    g_petHealthRegistered = true
end

local function PlayerHasPet()
    local pet = GameData and GameData.Player and GameData.Player.Pet
    return pet ~= nil and pet.name ~= nil and pet.name ~= L""
end

local function GetPetCareerDisplay()
    local display = CareerResource and CareerResource.m_CurrentDisplay
    if type(display) ~= "table" then
        return nil
    end
    if type(display.HasPet) ~= "function" or type(display.UpdatePet) ~= "function" then
        return nil
    end
    return display
end

--- Stock PetWindow:UpdatePet only FadeIn's m_Actionbar when the career window was hidden.
--- After /reload the bar can remain Show(false) while a pet is out — force it visible.
local function EnsurePetActionBarVisible()
    if m_resyncing or not PlayerHasPet() then
        return
    end
    m_resyncing = true

    local display = GetPetCareerDisplay()
    if display ~= nil then
        -- Prefer stock FadeIn path when the career window itself is still hidden.
        if type(display.IsShowing) == "function" and not display:IsShowing() then
            display:UpdatePet()
        end

        local bar = display.m_Actionbar
        if bar ~= nil then
            if type(bar.Show) == "function" then
                if Frame and Frame.FORCE_OVERRIDE ~= nil then
                    bar:Show(true, Frame.FORCE_OVERRIDE)
                else
                    bar:Show(true)
                end
            end
            if type(bar.SetAlpha) == "function" then
                bar:SetAlpha(1.0)
            end
        end
    end

    if DoesWindowExist(c_PET_ACTION_BAR) and WindowGetShowing(c_PET_ACTION_BAR) ~= true then
        WindowSetShowing(c_PET_ACTION_BAR, true)
    end

    if m_enabled then
        HideStockPetHealthWindow()
        HideCustomPetFrame()
    end

    m_resyncing = false
end

local function ScheduleReloadPetResync()
    m_reloadResyncRemaining = c_RELOAD_RESYNC_ATTEMPTS
    m_reloadResyncElapsed = 0
    EnsurePetActionBarVisible()
end

local function SuppressStockPetHealth()
    EnsurePetHealthWindowRegistered()
    if type(CustomUI.HideStockForReplace) == "function" then
        CustomUI.HideStockForReplace("PetHealthWindow", m_stockReplaceTracked)
    elseif LayoutEditor.windowsList and LayoutEditor.windowsList["PetHealthWindow"] then
        LayoutEditor.UserHide("PetHealthWindow")
    end
    HideStockPetHealthWindow()
end

local function InstallPetProxyHook()
    if m_stockUpdatePetProxy ~= nil then return end
    if type(PetWindow) ~= "table" or type(PetWindow.UpdatePet) ~= "function" then return end
    if PetWindow.UpdatePet == g_ourUpdatePetWrapper then
        return
    end
    m_stockUpdatePetProxy = PetWindow.UpdatePet
    -- Hook UpdatePet (the method, not the event proxy) because PetWindow:Create calls
    -- it directly — bypassing UpdatePetProxy entirely — so the event hook never fires
    -- for the initial pet show on reload. The m_enabled gate ensures we don't interfere
    -- with the career resources window when our component is disabled.
    g_ourUpdatePetWrapper = function( self )
        -- Never blind pcall: keep all stock returns intact when successful.
        local ok, r1, r2, r3, r4, r5 = CustomUI.TryCall(
            "PetWindow.UpdatePet",
            m_stockUpdatePetProxy,
            self
        )
        if not ok then
            return
        end
        if m_enabled then
            HideStockPetHealthWindow()
            HideCustomPetFrame()
        end
        -- Cover the stock gap: hasPet + already-showing skips FadeIn on the action bar.
        EnsurePetActionBarVisible()
        return r1, r2, r3, r4, r5
    end
    PetWindow.UpdatePet = g_ourUpdatePetWrapper
end

local function RestorePetProxyHook()
    if m_stockUpdatePetProxy == nil then return end
    if type( PetWindow ) == "table" and PetWindow.UpdatePet == g_ourUpdatePetWrapper then
        PetWindow.UpdatePet = m_stockUpdatePetProxy
    end
    g_ourUpdatePetWrapper = nil
    m_stockUpdatePetProxy = nil
end

----------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------

function CustomUI.PlayerPetWindow.Initialize()
    LayoutEditor.RegisterWindow( c_WINDOW_NAME,
                                 L"CustomUI: Player Pet",
                                 L"Stock pet health suppress anchor (portrait Pet badge replaces the frame).",
                                 false, false, true, nil )
    LayoutEditor.UserHide( c_WINDOW_NAME )

    petFrame = PlayerPetUnitFrame:Create( c_FRAME_NAME )
    petFrame:SetParent( c_WINDOW_NAME )
    petFrame:SetScale( WindowGetScale( c_WINDOW_NAME ) )
    petFrame:SetAnchor( { Point = "topleft", RelativePoint = "topleft",
                          RelativeTo = c_WINDOW_NAME, XOffset = 0, YOffset = 0 } )
    petFrame:Show( false )

    WindowRegisterEventHandler( c_WINDOW_NAME, SystemData.Events.PLAYER_PET_UPDATED,        "CustomUI.PlayerPetWindow.OnPetUpdated" )
    WindowRegisterEventHandler( c_WINDOW_NAME, SystemData.Events.PLAYER_PET_HEALTH_UPDATED, "CustomUI.PlayerPetWindow.OnPetHealthUpdated" )
    if not m_reloadEventsRegistered then
        WindowRegisterEventHandler( c_WINDOW_NAME, SystemData.Events.LOADING_END, "CustomUI.PlayerPetWindow.OnLoadingEnd" )
        if SystemData.Events.RELOAD_INTERFACE ~= nil then
            WindowRegisterEventHandler( c_WINDOW_NAME, SystemData.Events.RELOAD_INTERFACE, "CustomUI.PlayerPetWindow.OnLoadingEnd" )
        end
        m_reloadEventsRegistered = true
    end

    CustomUI.PlayerPetWindow.OnPetUpdated()
    ScheduleReloadPetResync()
end

function CustomUI.PlayerPetWindow.Shutdown()
    RestorePetProxyHook()
    m_reloadResyncRemaining = 0

    local e = SystemData.Events
    WindowUnregisterEventHandler( c_WINDOW_NAME, e.PLAYER_PET_UPDATED        )
    WindowUnregisterEventHandler( c_WINDOW_NAME, e.PLAYER_PET_HEALTH_UPDATED )
    if m_reloadEventsRegistered then
        WindowUnregisterEventHandler( c_WINDOW_NAME, e.LOADING_END )
        if e.RELOAD_INTERFACE ~= nil then
            WindowUnregisterEventHandler( c_WINDOW_NAME, e.RELOAD_INTERFACE )
        end
        m_reloadEventsRegistered = false
    end

    if petFrame then
        petFrame:Destroy()
        petFrame = nil
    end
end

----------------------------------------------------------------
-- Event Handlers — stock hide only; never show CustomUIPlayerPetFrame
----------------------------------------------------------------

function CustomUI.PlayerPetWindow.OnLoadingEnd()
    ScheduleReloadPetResync()
end

--- Called from CustomUI global update while post-reload retries remain.
function CustomUI.PlayerPetWindow.OnGlobalUpdate(timePassed)
    if m_reloadResyncRemaining <= 0 then
        return
    end
    m_reloadResyncElapsed = m_reloadResyncElapsed + (timePassed or 0)
    if m_reloadResyncElapsed < c_RELOAD_RESYNC_INTERVAL then
        return
    end
    m_reloadResyncElapsed = 0
    m_reloadResyncRemaining = m_reloadResyncRemaining - 1
    EnsurePetActionBarVisible()
    if PlayerHasPet()
        and DoesWindowExist(c_PET_ACTION_BAR)
        and WindowGetShowing(c_PET_ACTION_BAR) == true
    then
        m_reloadResyncRemaining = 0
    end
end

function CustomUI.PlayerPetWindow.OnPetUpdated()
    HideCustomPetFrame()
    EnsurePetActionBarVisible()
    if not m_enabled then
        return
    end
    -- Re-apply stock hide each time a pet appears because PetWindow:UpdatePet()
    -- calls FadeInComponent(m_UnitFrame) which un-hides PetHealthWindow.
    SuppressStockPetHealth()
end

function CustomUI.PlayerPetWindow.OnPetHealthUpdated()
    -- Portrait Pet badge owns HP display; keep custom frame hidden.
    HideCustomPetFrame()
end

----------------------------------------------------------------
-- Component Adapter
----------------------------------------------------------------

local PlayerPetWindowComponent = {
    Name           = "PlayerPetWindow",
    WindowName     = c_WINDOW_NAME,
    DefaultEnabled = false,
}

function PlayerPetWindowComponent:Enable()
    m_enabled = true
    InstallPetProxyHook()
    LayoutEditor.UserHide( self.WindowName )
    HideCustomPetFrame()
    SuppressStockPetHealth()
    CustomUI.PlayerPetWindow.OnPetUpdated()
    ScheduleReloadPetResync()
    return true
end

function PlayerPetWindowComponent:Disable()
    m_enabled = false
    RestorePetProxyHook()
    LayoutEditor.UserHide( self.WindowName )
    HideCustomPetFrame()
    -- Restore visibility only if we hid it; keep "Pet Health" registered (stock has no LE entry of its own).
    if type(CustomUI.RestoreStockAfterReplace) == "function" then
        CustomUI.RestoreStockAfterReplace("PetHealthWindow", m_stockReplaceTracked)
    elseif LayoutEditor.windowsList and LayoutEditor.windowsList["PetHealthWindow"] then
        LayoutEditor.UserShow("PetHealthWindow")
    end
    return true
end

function PlayerPetWindowComponent:ResetToDefaults()
    if type(CustomUI.ResetWindowToDefault) == "function" then
        CustomUI.ResetWindowToDefault(self.WindowName)
    elseif DoesWindowExist(self.WindowName) then
        WindowRestoreDefaultSettings(self.WindowName)
    end
    HideCustomPetFrame()
    return true
end

function PlayerPetWindowComponent:Shutdown()
    RestorePetProxyHook()
end

-- Public surface called by PlayerStatusWindowComponent.
function CustomUI.PlayerPetWindow.Enable()  PlayerPetWindowComponent:Enable()  end
function CustomUI.PlayerPetWindow.Disable() PlayerPetWindowComponent:Disable() end
function CustomUI.PlayerPetWindow.Shutdown() PlayerPetWindowComponent:Shutdown() end
