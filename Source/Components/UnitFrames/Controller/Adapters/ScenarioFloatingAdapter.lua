----------------------------------------------------------------
-- UnitFrames ScenarioFloatingAdapter — stub (returns empty groups). Reserved for scenario snapshot shaping.
----------------------------------------------------------------

if not CustomUI then
    CustomUI = {}
end

CustomUI.UnitFramesScenarioFloatingAdapter = CustomUI.UnitFramesScenarioFloatingAdapter or {}

local Adapter = CustomUI.UnitFramesScenarioFloatingAdapter

function Adapter.Initialize()
end

function Adapter.Shutdown()
end

function Adapter.GetGroups()
    return {}
end
