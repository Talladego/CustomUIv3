----------------------------------------------------------------
-- CustomUI.StockProgressBars
-- When PlayerStatus Rank / Renown / Influence badges are enabled,
-- hide the matching stock HUD bars:
--   Rank      → XpBarWindow
--   Renown    → RpBarWindow
--   Influence → PQ Tracker influence bar only (not the PQ objectives)
----------------------------------------------------------------

if not CustomUI then
    CustomUI = {}
end

CustomUI.StockProgressBars = CustomUI.StockProgressBars or {}

local Bars = CustomUI.StockProgressBars

local c_XP_WINDOW = "XpBarWindow"
local c_RP_WINDOW = "RpBarWindow"
local c_INFLUENCE_CONTAINER = "EA_Window_PublicQuestTrackerInfluence"
local c_INFLUENCE_BAR = "EA_Window_PublicQuestTrackerInfluenceBar"
local c_INFLUENCE_BAR_W = 300
local c_INFLUENCE_BAR_H = 14

local m_stockBarTracked = {}
local m_active = false
local m_influenceHooked = false
local m_stockUpdateInfluenceBar = nil
local m_stockUpdateTutorial = nil
local m_influenceCollapsed = false

local function badgeEnabled(key)
    local PS = CustomUI.PlayerStatusWindow
    if type(PS) ~= "table" or type(PS.IsBadgeEnabled) ~= "function" then
        return false
    end
    return PS.IsBadgeEnabled(key) == true
end

local function wantHideXp()
    return m_active and badgeEnabled("rank")
end

local function wantHideRp()
    return m_active and badgeEnabled("renown")
end

local function wantHideInfluence()
    return m_active and badgeEnabled("influence")
end

local function setWindowDims(windowName, w, h)
    if type(DoesWindowExist) == "function" and DoesWindowExist(windowName)
        and type(WindowSetDimensions) == "function"
    then
        WindowSetDimensions(windowName, w, h)
    end
end

local function setWindowShowing(windowName, showing)
    if type(DoesWindowExist) == "function" and DoesWindowExist(windowName)
        and type(WindowSetShowing) == "function"
    then
        WindowSetShowing(windowName, showing == true)
    end
end

local function collapseInfluenceBar()
    setWindowShowing(c_INFLUENCE_BAR, false)
    setWindowShowing(c_INFLUENCE_CONTAINER, false)
    setWindowDims(c_INFLUENCE_BAR, c_INFLUENCE_BAR_W, 0)
    setWindowDims(c_INFLUENCE_CONTAINER, c_INFLUENCE_BAR_W, 0)
    m_influenceCollapsed = true
    if type(EA_Window_PublicQuestTracker) == "table"
        and type(EA_Window_PublicQuestTracker.UpdateMainWindowSize) == "function"
    then
        EA_Window_PublicQuestTracker.UpdateMainWindowSize()
    end
end

local function restoreInfluenceBarLayout()
    if not m_influenceCollapsed then
        return
    end
    setWindowDims(c_INFLUENCE_BAR, c_INFLUENCE_BAR_W, c_INFLUENCE_BAR_H)
    setWindowDims(c_INFLUENCE_CONTAINER, c_INFLUENCE_BAR_W, c_INFLUENCE_BAR_H)
    m_influenceCollapsed = false
end

local function runStockInfluenceRefresh()
    -- AWM owns EA_Window_PublicQuestTrackerInfluence; UpdateInfluenceBar only toggles the Bar child.
    if type(m_stockUpdateTutorial) == "function" then
        m_stockUpdateTutorial()
    elseif type(EA_Window_PublicQuestTracker) == "table"
        and type(EA_Window_PublicQuestTracker.UpdateTutorial) == "function"
    then
        EA_Window_PublicQuestTracker.UpdateTutorial()
    end
    if type(m_stockUpdateInfluenceBar) == "function" then
        m_stockUpdateInfluenceBar()
    elseif type(EA_Window_PublicQuestTracker) == "table"
        and type(EA_Window_PublicQuestTracker.UpdateInfluenceBar) == "function"
    then
        EA_Window_PublicQuestTracker.UpdateInfluenceBar()
    end
end

local function afterStockInfluenceUpdate()
    if wantHideInfluence() then
        collapseInfluenceBar()
    end
end

local function unhookInfluenceUpdates()
    if not m_influenceHooked then
        return
    end
    if type(EA_Window_PublicQuestTracker) == "table" then
        if type(m_stockUpdateInfluenceBar) == "function" then
            EA_Window_PublicQuestTracker.UpdateInfluenceBar = m_stockUpdateInfluenceBar
        end
        if type(m_stockUpdateTutorial) == "function" then
            EA_Window_PublicQuestTracker.UpdateTutorial = m_stockUpdateTutorial
        end
    end
    m_stockUpdateInfluenceBar = nil
    m_stockUpdateTutorial = nil
    m_influenceHooked = false
end

local function ensureInfluenceHooks()
    if m_influenceHooked then
        return
    end
    if type(EA_Window_PublicQuestTracker) ~= "table" then
        return
    end

    local hookedAny = false
    if type(EA_Window_PublicQuestTracker.UpdateInfluenceBar) == "function" then
        m_stockUpdateInfluenceBar = EA_Window_PublicQuestTracker.UpdateInfluenceBar
        EA_Window_PublicQuestTracker.UpdateInfluenceBar = function(...)
            m_stockUpdateInfluenceBar(...)
            afterStockInfluenceUpdate()
        end
        hookedAny = true
    end
    if type(EA_Window_PublicQuestTracker.UpdateTutorial) == "function" then
        m_stockUpdateTutorial = EA_Window_PublicQuestTracker.UpdateTutorial
        EA_Window_PublicQuestTracker.UpdateTutorial = function(...)
            m_stockUpdateTutorial(...)
            afterStockInfluenceUpdate()
        end
        hookedAny = true
    end
    -- Only lock the hook flag when at least one wrapper landed (retry later if PQ tracker not ready).
    m_influenceHooked = hookedAny
end

local function applyXpRpVisibility()
    if type(CustomUI.HideStockForReplace) ~= "function"
        or type(CustomUI.RestoreStockAfterReplace) ~= "function"
    then
        return
    end

    if wantHideXp() then
        CustomUI.HideStockForReplace(c_XP_WINDOW, m_stockBarTracked)
    else
        CustomUI.RestoreStockAfterReplace(c_XP_WINDOW, m_stockBarTracked)
    end

    if wantHideRp() then
        CustomUI.HideStockForReplace(c_RP_WINDOW, m_stockBarTracked)
    else
        CustomUI.RestoreStockAfterReplace(c_RP_WINDOW, m_stockBarTracked)
    end
end

local function applyInfluenceVisibility()
    ensureInfluenceHooks()
    if wantHideInfluence() then
        collapseInfluenceBar()
        return
    end
    restoreInfluenceBarLayout()
    runStockInfluenceRefresh()
end

--- Apply or refresh stock XP / Renown / Influence bar visibility from badge settings.
--- @param active boolean|nil when false, restore all stock bars (PlayerStatus disabled).
function Bars.Apply(active)
    if active ~= nil then
        m_active = active == true
    end
    applyXpRpVisibility()
    applyInfluenceVisibility()
end

function Bars.Shutdown()
    m_active = false
    applyXpRpVisibility()
    restoreInfluenceBarLayout()
    runStockInfluenceRefresh()
    unhookInfluenceUpdates()
    if type(CustomUI.RestoreAllStockAfterReplace) == "function" then
        CustomUI.RestoreAllStockAfterReplace(m_stockBarTracked)
    end
end
