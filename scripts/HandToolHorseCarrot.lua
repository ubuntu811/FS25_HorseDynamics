--[[
    HandToolHorseCarrot.lua -- the carrot: held in the hand, the primary action calls every horse of the pasture you are in (or the nearest horse pasture); the horses come and follow
    (HorseLead.callPasture); the same action again lets them go (HorseLead.carrot is the switch). Right Ctrl + V gives back every horse; they also go back by themselves at a stable.
]]
HandToolHorseCarrot = {}
HandToolHorseCarrot.SPEC_TABLE_NAME = "spec_" .. g_currentModName .. ".horseCarrot"

function HandToolHorseCarrot.prerequisitesPresent(_)
    return true
end

function HandToolHorseCarrot.registerEventListeners(handToolType)
    SpecializationUtil.registerEventListener(handToolType, "onLoad", HandToolHorseCarrot)
    SpecializationUtil.registerEventListener(handToolType, "onRegisterActionEvents", HandToolHorseCarrot)
    SpecializationUtil.registerEventListener(handToolType, "onHeldStart", HandToolHorseCarrot)
    SpecializationUtil.registerEventListener(handToolType, "onHeldEnd", HandToolHorseCarrot)
end

function HandToolHorseCarrot:onLoad(_)
    self[HandToolHorseCarrot.SPEC_TABLE_NAME] = { actionEventId = nil }
end

function HandToolHorseCarrot:onRegisterActionEvents()
    local spec = self[HandToolHorseCarrot.SPEC_TABLE_NAME]
    if self:getIsActiveForInput(true) then
        local _, actionEventId = self:addActionEvent(InputAction.ACTIVATE_HANDTOOL, self, HandToolHorseCarrot.onAction, true, true, false, true, nil)
        spec.actionEventId = actionEventId
        g_inputBinding:setActionEventTextPriority(actionEventId, GS_PRIO_VERY_HIGH)
        g_inputBinding:setActionEventText(actionEventId, g_i18n:getText("action_horseCarrot"))
        g_inputBinding:setActionEventActive(actionEventId, self:getIsHeld())
    end
end

function HandToolHorseCarrot:onHeldStart()
    local spec = self[HandToolHorseCarrot.SPEC_TABLE_NAME]
    if spec.actionEventId ~= nil then
        g_inputBinding:setActionEventActive(spec.actionEventId, true)
    end
end

function HandToolHorseCarrot:onHeldEnd()
    local spec = self[HandToolHorseCarrot.SPEC_TABLE_NAME]
    if spec.actionEventId ~= nil then
        g_inputBinding:setActionEventActive(spec.actionEventId, false)
    end
end

function HandToolHorseCarrot:onAction(_, inputValue)
    if inputValue > 0.5 and HorseLead ~= nil then
        HorseDynamics.notify(HorseLead.carrot())
    end
end
