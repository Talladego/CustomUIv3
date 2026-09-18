----------------------------------------------------------------
-- CustomUI.PlayerPetWindow — Controller
-- Responsibilities: suppress stock PetHealthWindow while PlayerStatus is enabled.
-- Pet HP is shown on the PlayerStatus portrait Pet badge; CustomUIPlayerPetFrame is
-- never shown. CustomUI.mod loads this file before View/PlayerPetWindow.xml.
----------------------------------------------------------------

if not CustomUI.PlayerPetWindow then
    CustomUI.PlayerPetWindow = {}
end

----------------------------------------------------------------
-- Constants
----------------------------------------------------------------

local c_WINDOW_NAME = "CustomUIPlayerPetWindow"  -- layout anchor (XML)
local c_FRAME_NAME  = "CustomUIPlayerPetFrame"   -- unit frame (runtime; kept hidden)

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

    CustomUI.PlayerPetWindow.OnPetUpdated()
end

function CustomUI.PlayerPetWindow.Shutdown()
    RestorePetProxyHook()

    local e = SystemData.Events
    WindowUnregisterEventHandler( c_WINDOW_NAME, e.PLAYER_PET_UPDATED        )
    WindowUnregisterEventHandler( c_WINDOW_NAME, e.PLAYER_PET_HEALTH_UPDATED )

    if petFrame then
        petFrame:Destroy()
        petFrame = nil
    end
end

----------------------------------------------------------------
-- Event Handlers — stock hide only; never show CustomUIPlayerPetFrame
----------------------------------------------------------------

function CustomUI.PlayerPetWindow.OnPetUpdated()
    HideCustomPetFrame()
    if not m_enabled then
        return
    end
    -- Re-apply stock hide each time a pet appears because PetWindow:UpdatePet()
    -- calls FadeInComponent(m_UnitFrame) which un-hides PetHealthWindow.
    EnsurePetHealthWindowRegistered()
    if type(CustomUI.HideStockForReplace) == "function" then
        CustomUI.HideStockForReplace("PetHealthWindow", m_stockReplaceTracked)
    elseif LayoutEditor.windowsList and LayoutEditor.windowsList["PetHealthWindow"] then
        LayoutEditor.UserHide("PetHealthWindow")
    end
    HideStockPetHealthWindow()
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
    EnsurePetHealthWindowRegistered()
    if type(CustomUI.HideStockForReplace) == "function" then
        CustomUI.HideStockForReplace("PetHealthWindow", m_stockReplaceTracked)
    elseif LayoutEditor.windowsList and LayoutEditor.windowsList["PetHealthWindow"] then
        LayoutEditor.UserHide("PetHealthWindow")
    end
    HideStockPetHealthWindow()
    CustomUI.PlayerPetWindow.OnPetUpdated()
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
