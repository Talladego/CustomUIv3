----------------------------------------------------------------
-- UnitFrames WarbandAdapter — stub (returns empty groups). Reserved for adapter-shaped data fetch.
----------------------------------------------------------------

if not CustomUI then
    CustomUI = {}
end

CustomUI.UnitFramesWarbandAdapter = CustomUI.UnitFramesWarbandAdapter or {}

local Adapter = CustomUI.UnitFramesWarbandAdapter

function Adapter.Initialize()
end

function Adapter.Shutdown()
end

function Adapter.GetGroups()
    return {}
end
