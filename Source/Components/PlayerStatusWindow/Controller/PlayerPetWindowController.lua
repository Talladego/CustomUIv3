----------------------------------------------------------------
-- CustomUI.PlayerPetWindow - Controller
-- Moveable replacement for the stock PetHealthWindow.
-- Uses PlayerPetUnitFrame:Create() directly, bypassing UnitFrames
-- registration so the stock PetHealthWindow (ea_careerresourceswindow)
-- keeps its own slot undisturbed.
--
-- Shows when a pet is present and the component is enabled.
-- Hides when no pet exists regardless of enabled state.
----------------------------------------------------------------

if not CustomUI.PlayerPetWindow then
    CustomUI.PlayerPetWindow = {}
end

----------------------------------------------------------------
-- Constants
----------------------------------------------------------------

local c_WINDOW_NAME = "CustomUIPlayerPetWindow"  -- layout anchor (XML)
local c_FRAME_NAME  = "CustomUIPlayerPetFrame"   -- unit frame (runtime)

----------------------------------------------------------------
-- Module state
----------------------------------------------------------------

local petFrame = nil
local m_enabled = false

local g_petHealthRegistered = false
local m_stockUpdatePetProxy = nil

local function HideStockPetHealthWindow()
    if DoesWindowExist("PetHealthWindow") then
        WindowSetShowing("PetHealthWindow", false)
    end
end

local function InstallPetProxyHook()
    if m_stockUpdatePetProxy ~= nil then return end
    if type(PetWindow) ~= "table" or type(PetWindow.UpdatePet) ~= "function" then return end
    m_stockUpdatePetProxy = PetWindow.UpdatePet
    -- Hook UpdatePet (the method, not the event proxy) because PetWindow:Create calls
    -- it directly — bypassing UpdatePetProxy entirely — so the event hook never fires
    -- for the initial pet show on reload. The m_enabled gate ensures we don't interfere
    -- with the career resources window when our component is disabled.
    function PetWindow:UpdatePet()
        m_stockUpdatePetProxy(self)
        if m_enabled then HideStockPetHealthWindow() end
    end
end

local function RestorePetProxyHook()
    if m_stockUpdatePetProxy == nil then return end
    if type(PetWindow) == "table" then
        PetWindow.UpdatePet = m_stockUpdatePetProxy
    end
    m_stockUpdatePetProxy = nil
end

local function EnsurePetHealthWindowRegistered()
    if g_petHealthRegistered then return end
    if not DoesWindowExist( "PetHealthWindow" ) then return end
    LayoutEditor.RegisterWindow( "PetHealthWindow",
                                 L"Pet Health (stock)",
                                 L"Stock pet health window — hidden while CustomUI: Player Pet is enabled.",
                                 false, false, true, nil )
    g_petHealthRegistered = true
end

----------------------------------------------------------------
-- Local helpers
----------------------------------------------------------------

local function HasPet()
    return GameData.Player.Pet.name ~= L""
end

local function UpdateFrame()
    petFrame:SetPlayersPetName( GameData.Player.Pet.name )
    petFrame:UpdateLevel( GameData.Player.Pet.level )
    petFrame:UpdateHealth( GameData.Player.Pet.healthPercent )
end

----------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------

function CustomUI.PlayerPetWindow.Initialize()
    LayoutEditor.RegisterWindow( c_WINDOW_NAME,
                                 L"CustomUI: Player Pet",
                                 L"Moveable player pet health and level display.",
                                 false, false, true, nil )
    LayoutEditor.UserHide( c_WINDOW_NAME )  -- hidden until component Enable()

    petFrame = PlayerPetUnitFrame:Create( c_FRAME_NAME )
    petFrame:SetParent( c_WINDOW_NAME )
    petFrame:SetScale( WindowGetScale( c_WINDOW_NAME ) )
    petFrame:SetAnchor( { Point = "topleft", RelativePoint = "topleft",
                          RelativeTo = c_WINDOW_NAME, XOffset = 0, YOffset = 0 } )

    WindowRegisterEventHandler( c_WINDOW_NAME, SystemData.Events.PLAYER_PET_UPDATED,        "CustomUI.PlayerPetWindow.OnPetUpdated" )
    WindowRegisterEventHandler( c_WINDOW_NAME, SystemData.Events.PLAYER_PET_HEALTH_UPDATED, "CustomUI.PlayerPetWindow.OnPetHealthUpdated" )

    InstallPetProxyHook()
    CustomUI.PlayerPetWindow.OnPetUpdated()
end

function CustomUI.PlayerPetWindow.Shutdown()
    RestorePetProxyHook()

    if petFrame then
        petFrame:Destroy()
        petFrame = nil
    end
end

----------------------------------------------------------------
-- Event Handlers
----------------------------------------------------------------

function CustomUI.PlayerPetWindow.OnPetUpdated()
    if not petFrame then return end

    if HasPet() then
        UpdateFrame()
        petFrame:SetPetPortrait()
        petFrame:Show( true )
        if m_enabled then
            LayoutEditor.Show( c_WINDOW_NAME )
        end
        -- Re-apply stock hide each time a pet appears because PetWindow:UpdatePet()
        -- calls FadeInComponent(m_UnitFrame) which un-hides PetHealthWindow.
        if m_enabled then
            EnsurePetHealthWindowRegistered()
            if LayoutEditor.windowsList and LayoutEditor.windowsList["PetHealthWindow"] then
                LayoutEditor.UserHide( "PetHealthWindow" )
            end
            HideStockPetHealthWindow()
        end

    else
        petFrame:Show( false )
        LayoutEditor.Hide( c_WINDOW_NAME )
    end
end

function CustomUI.PlayerPetWindow.OnPetHealthUpdated()
    if petFrame and HasPet() then
        petFrame:UpdateHealth( GameData.Player.Pet.healthPercent )
    end
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
    LayoutEditor.UserShow( self.WindowName )
    EnsurePetHealthWindowRegistered()
    HideStockPetHealthWindow()
    CustomUI.PlayerPetWindow.OnPetUpdated()
    return true
end

function PlayerPetWindowComponent:Disable()
    m_enabled = false
    LayoutEditor.UserHide( self.WindowName )
    if LayoutEditor.windowsList["PetHealthWindow"] then
        LayoutEditor.UserShow( "PetHealthWindow" )
        LayoutEditor.UnregisterWindow( "PetHealthWindow" )
        g_petHealthRegistered = false
    end
    return true
end

function PlayerPetWindowComponent:ResetToDefaults()
    if type(CustomUI.ResetWindowToDefault) == "function" then
        CustomUI.ResetWindowToDefault(self.WindowName)
    elseif DoesWindowExist(self.WindowName) then
        WindowRestoreDefaultSettings(self.WindowName)
    end

    if petFrame and DoesWindowExist(self.WindowName) then
        petFrame:SetScale(WindowGetScale(self.WindowName))
    end

    return true
end

function PlayerPetWindowComponent:Shutdown()
    RestorePetProxyHook()
end

-- Public surface called by PlayerStatusWindowComponent.
function CustomUI.PlayerPetWindow.Enable()  PlayerPetWindowComponent:Enable()  end
function CustomUI.PlayerPetWindow.Disable() PlayerPetWindowComponent:Disable() end
function CustomUI.PlayerPetWindow.Shutdown() PlayerPetWindowComponent:Shutdown() end
