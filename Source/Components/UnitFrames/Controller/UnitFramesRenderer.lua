if not CustomUI then
    CustomUI = {}
end

CustomUI.UnitFramesRenderer = CustomUI.UnitFramesRenderer or {}

local Renderer = CustomUI.UnitFramesRenderer

function Renderer.Initialize()
end

function Renderer.Shutdown()
end

function Renderer.RenderGroup(groupModel)
    return groupModel
end

function Renderer.RenderMemberSlot(groupModel, slotModel)
    return groupModel, slotModel
end
