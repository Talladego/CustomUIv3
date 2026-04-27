----------------------------------------------------------------
-- CustomUI.GroupIcons — Controller
-- Responsibilities: RegisterComponent, event-driven world icon placement, icon slot pool.
-- No View/ Lua; window template is View/GroupIcons.xml, logic stays here. CustomUI.mod loads
-- this file before the XML; the XML has no <Script> for the controller.
-- Places a career icon on each party / warband / scenario member’s world object. Modes:
-- Party (GetGroupData, up to 5 + self), Warband/Scenario (battlegroup data, 4×6 members).
-- 36 pre-allocated icon slots, reused; no polling.
----------------------------------------------------------------

if not CustomUI.GroupIcons then
    CustomUI.GroupIcons = {}
end

----------------------------------------------------------------
-- Constants
----------------------------------------------------------------

local c_MAX_PARTIES  = 6
local c_MAX_MEMBERS  = 6
local c_ICON_SIZE    = 40   -- DynamicImage and Content: square icon in pixels
-- GetIconData atlas cell size in texture pixels (map tooltip / main menu pattern; do not add TexDims in XML).
local c_ATLAS_ICON   = 64
local c_OFFSET_Y     = 50   -- empty vertical gap (pixels) *below* the icon inside the outer window, toward the world-attach end
local c_OUTER_H      = c_OFFSET_Y + c_ICON_SIZE   -- outer must contain icon + gap (see View/GroupIcons.xml; AttachWindowToWorldObject uses outer)

----------------------------------------------------------------
-- GroupIcon — one reusable slot
----------------------------------------------------------------

local GroupIcon = {}
GroupIcon.__index = GroupIcon

function GroupIcon.New(partyIndex, memberIndex)
    local self = setmetatable({}, GroupIcon)
    self.partyIndex  = partyIndex
    self.memberIndex = memberIndex
    self.isEnabled   = false
    self.windowName  = nil
    self.playerName  = nil
    self.worldObjNum = 0
    return self
end

function GroupIcon:_windowName()
    return "CustomUIGroupIcon_" .. self.partyIndex .. "_" .. self.memberIndex
end

function GroupIcon:Attach(name, worldObjNum, careerLine)
    self:_detach()

    self.windowName  = self:_windowName()
    self.playerName  = name
    self.worldObjNum = worldObjNum

    CreateWindowFromTemplate(self.windowName, "CustomUIGroupIcon", "Root")
    if WindowSetDimensions and DoesWindowExist(self.windowName) then
        WindowSetDimensions(self.windowName, c_ICON_SIZE, c_OUTER_H)
    end

    -- Career icon: SetTexture (offset) then SetTextureDimensions (source size). XML has no TexDims
    -- so this is the only UV-size path — avoids 2x2 tiling from TexDims + other state fighting.
    local texture, tx, ty = GetIconData(Icons.GetCareerIconIDFromCareerLine(careerLine))
    local iconWin = self.windowName .. "ContentIcon"
    DynamicImageSetTexture(iconWin, texture, tx, ty)
    DynamicImageSetTextureDimensions(iconWin, c_ATLAS_ICON, c_ATLAS_ICON)

    -- Click to target.
    WindowSetGameActionData(self.windowName .. "Content", GameData.PlayerActions.SET_TARGET, 0, name)
    CustomUI.GroupIcons.windowToName[self.windowName .. "Content"] = name

    -- Icon in the *top* c_ICON_SIZE strip; c_OFFSET_Y is empty space below the icon so the
    -- world attachment (outer window bounds) lines up. Do not push Content down: that drew
    -- outside a 40×40 outer and misaligned the texture relative to AttachWindowToWorldObject.
    WindowClearAnchors(self.windowName .. "Content")
    WindowAddAnchor(self.windowName .. "Content", "topleft", self.windowName, "topleft", 0, 0)

    AttachWindowToWorldObject(self.windowName, worldObjNum)
end

function GroupIcon:_detach()
    if not self.windowName then return end
    if self.worldObjNum ~= 0 then
        DetachWindowFromWorldObject(self.windowName, self.worldObjNum)
    end
    if DoesWindowExist(self.windowName) then
        DestroyWindow(self.windowName)
    end
    CustomUI.GroupIcons.windowToName[self.windowName .. "Content"] = nil
    self.windowName  = nil
    self.playerName  = nil
    self.worldObjNum = 0
end

function GroupIcon:Update(name, worldObjNum, careerLine)
    if not self.isEnabled then return end
    if worldObjNum == 0 then
        self:_detach()
        return
    end
    -- Re-attach if the player or world object changed.
    if not self.windowName
        or self.playerName  ~= name
        or self.worldObjNum ~= worldObjNum
    then
        self:Attach(name, worldObjNum, careerLine)
    end
end

function GroupIcon:Enable()
    self.isEnabled = true
end

function GroupIcon:Disable()
    self:_detach()
    self.isEnabled = false
end

----------------------------------------------------------------
-- Module state
----------------------------------------------------------------

local m_icons = {}      -- m_icons[partyIndex][memberIndex] = GroupIcon

----------------------------------------------------------------
-- Internal helpers
----------------------------------------------------------------

local function DisableAll()
    for p = 1, c_MAX_PARTIES do
        for m = 1, c_MAX_MEMBERS do
            m_icons[p][m]:Disable()
        end
    end
end

-- Refresh from party data (group / solo).
local function RefreshParty()
    local data = GetGroupData()
    if not data then return end
    for m = 1, c_MAX_MEMBERS do
        local member = data[m]
        local icon   = m_icons[1][m]
        if member and member.name and member.worldObjNum and member.worldObjNum ~= 0 then
            icon:Enable()
            icon:Update(member.name, member.worldObjNum, member.careerLine)
        else
            icon:Disable()
        end
    end
    -- Disable unused parties.
    for p = 2, c_MAX_PARTIES do
        for m = 1, c_MAX_MEMBERS do
            m_icons[p][m]:Disable()
        end
    end
end

-- Refresh from warband / scenario data.
local function RefreshWarband()
    local parties = GetBattlegroupMemberData()
    if not parties then return end
    for p = 1, c_MAX_PARTIES do
        local party = parties[p]
        for m = 1, c_MAX_MEMBERS do
            local member = party and party.players and party.players[m]
            local icon   = m_icons[p][m]
            if member and member.name and member.worldObjNum and member.worldObjNum ~= 0 then
                icon:Enable()
                icon:Update(member.name, member.worldObjNum, member.careerLine)
            else
                icon:Disable()
            end
        end
    end
end

local function RefreshAll()
    DisableAll()
    if GameData.Player.isInBattlegroup or GameData.Player.isInScenario then
        RefreshWarband()
    else
        RefreshParty()
    end
end

----------------------------------------------------------------
-- Event handlers
----------------------------------------------------------------

function CustomUI.GroupIcons.OnGroupUpdated()
    RefreshAll()
end

function CustomUI.GroupIcons.OnBattlegroupUpdated()
    RefreshAll()
end

function CustomUI.GroupIcons.OnScenarioUpdated()
    RefreshAll()
end

function CustomUI.GroupIcons.OnZoneChanged()
    RefreshAll()
end

-- Called when clicking a group icon window.
function CustomUI.GroupIcons.OnIconClicked()
    -- WindowSetGameActionData handles targeting automatically on LButtonDown.
    -- This handler exists so XML can bind to a named function.
end

----------------------------------------------------------------
-- Component adapter
----------------------------------------------------------------

local GroupIconsComponent = {}

function GroupIconsComponent:Initialize()
    CustomUI.GroupIcons.windowToName = {}
    for p = 1, c_MAX_PARTIES do
        m_icons[p] = {}
        for m = 1, c_MAX_MEMBERS do
            m_icons[p][m] = GroupIcon.New(p, m)
        end
    end
    return true
end

function GroupIconsComponent:Enable()
    WindowRegisterEventHandler("Root", SystemData.Events.GROUP_UPDATED,           "CustomUI.GroupIcons.OnGroupUpdated")
    WindowRegisterEventHandler("Root", SystemData.Events.GROUP_PLAYER_ADDED,      "CustomUI.GroupIcons.OnGroupUpdated")
    WindowRegisterEventHandler("Root", SystemData.Events.BATTLEGROUP_UPDATED,     "CustomUI.GroupIcons.OnBattlegroupUpdated")
    WindowRegisterEventHandler("Root", SystemData.Events.BATTLEGROUP_MEMBER_UPDATED, "CustomUI.GroupIcons.OnBattlegroupUpdated")
    WindowRegisterEventHandler("Root", SystemData.Events.SCENARIO_GROUP_UPDATED,  "CustomUI.GroupIcons.OnScenarioUpdated")
    WindowRegisterEventHandler("Root", SystemData.Events.SCENARIO_PLAYERS_LIST_GROUPS_UPDATED, "CustomUI.GroupIcons.OnScenarioUpdated")
    WindowRegisterEventHandler("Root", SystemData.Events.PLAYER_ZONE_CHANGED,     "CustomUI.GroupIcons.OnZoneChanged")
    RefreshAll()
    return true
end

function GroupIconsComponent:Disable()
    WindowUnregisterEventHandler("Root", SystemData.Events.GROUP_UPDATED)
    WindowUnregisterEventHandler("Root", SystemData.Events.GROUP_PLAYER_ADDED)
    WindowUnregisterEventHandler("Root", SystemData.Events.BATTLEGROUP_UPDATED)
    WindowUnregisterEventHandler("Root", SystemData.Events.BATTLEGROUP_MEMBER_UPDATED)
    WindowUnregisterEventHandler("Root", SystemData.Events.SCENARIO_GROUP_UPDATED)
    WindowUnregisterEventHandler("Root", SystemData.Events.SCENARIO_PLAYERS_LIST_GROUPS_UPDATED)
    WindowUnregisterEventHandler("Root", SystemData.Events.PLAYER_ZONE_CHANGED)
    DisableAll()
end

function GroupIconsComponent:Shutdown()
    self:Disable()
end

CustomUI.RegisterComponent("GroupIcons", GroupIconsComponent)
