--[[
    HandToolHorseBall.lua -- the horse ball tool: held in the hand, the primary action puts the big red ball down in front of you (HorseBall), the same action again picks it up. The ball is a real physics
    body that moving horses kick (HorseBall.update).
]]
HandToolHorseBall = {}
HandToolHorseBall.SPEC_TABLE_NAME = "spec_" .. g_currentModName .. ".horseBall"

function HandToolHorseBall.prerequisitesPresent(_)
    return true
end

function HandToolHorseBall.registerEventListeners(handToolType)
    SpecializationUtil.registerEventListener(handToolType, "onLoad", HandToolHorseBall)
    SpecializationUtil.registerEventListener(handToolType, "onRegisterActionEvents", HandToolHorseBall)
    SpecializationUtil.registerEventListener(handToolType, "onHeldStart", HandToolHorseBall)
    SpecializationUtil.registerEventListener(handToolType, "onHeldEnd", HandToolHorseBall)
end

function HandToolHorseBall:onLoad(_)
    self[HandToolHorseBall.SPEC_TABLE_NAME] = { actionEventId = nil }
end

function HandToolHorseBall:onRegisterActionEvents()
    local spec = self[HandToolHorseBall.SPEC_TABLE_NAME]
    if self:getIsActiveForInput(true) then
        local _, actionEventId = self:addActionEvent(InputAction.ACTIVATE_HANDTOOL, self, HandToolHorseBall.onAction, true, true, false, true, nil)
        spec.actionEventId = actionEventId
        g_inputBinding:setActionEventTextPriority(actionEventId, GS_PRIO_VERY_HIGH)
        g_inputBinding:setActionEventText(actionEventId, g_i18n:getText("action_horseBall"))
        g_inputBinding:setActionEventActive(actionEventId, self:getIsHeld())
    end
end

function HandToolHorseBall:onHeldStart()
    local spec = self[HandToolHorseBall.SPEC_TABLE_NAME]
    if spec.actionEventId ~= nil then
        g_inputBinding:setActionEventActive(spec.actionEventId, true)
    end
end

function HandToolHorseBall:onHeldEnd()
    local spec = self[HandToolHorseBall.SPEC_TABLE_NAME]
    if spec.actionEventId ~= nil then
        g_inputBinding:setActionEventActive(spec.actionEventId, false)
    end
end

function HandToolHorseBall:onAction(_, inputValue)
    if inputValue > 0.5 and HorseBall ~= nil then
        HorseDynamics.notify(HorseBall.toggle())
    end
end

