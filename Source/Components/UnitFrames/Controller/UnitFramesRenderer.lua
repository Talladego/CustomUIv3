----------------------------------------------------------------
-- CustomUI.UnitFramesRenderer — placeholder render pass (no-op)
-- Present for future split of XML-bound updates vs pure layout; UnitFramesController owns all UI mutation today.
----------------------------------------------------------------

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
