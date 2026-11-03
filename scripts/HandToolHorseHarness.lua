--[[
    HandToolHorseHarness.lua -- the harness tool: held in the hand, the primary action puts a draught harness on the horse beside you (taking the nearest horse on the leash first when none is led),
    and takes it off again. (HorseLead.harness)
]]
HandToolHorseHarness = {}
HandToolHorseHarness.SPEC_TABLE_NAME = "spec_" .. g_currentModName .. ".horseHarness"

function HandToolHorseHarness.prerequisitesPresent(_)
    return true
end

function HandToolHorseHarness.registerEventListeners(handToolType)
    SpecializationUtil.registerEventListener(handToolType, "onLoad", HandToolHorseHarness)
    SpecializationUtil.registerEventListener(handToolType, "onRegisterActionEvents", HandToolHorseHarness)
    SpecializationUtil.registerEventListener(handToolType, "onHeldStart", HandToolHorseHarness)
    SpecializationUtil.registerEventListener(handToolType, "onHeldEnd", HandToolHorseHarness)
end

function HandToolHorseHarness:onLoad(_)
    self[HandToolHorseHarness.SPEC_TABLE_NAME] = { actionEventId = nil }
    if HorseDynamics.gearOfTool(self) == "leather" and HorseRope ~= nil then
        HorseRope.leatherProp(self.rootNode)                    -- (the leather tool looks like leather in the hand)
    end
end

function HandToolHorseHarness:onRegisterActionEvents()
    local spec = self[HandToolHorseHarness.SPEC_TABLE_NAME]
    if self:getIsActiveForInput(true) then
        local _, actionEventId = self:addActionEvent(InputAction.ACTIVATE_HANDTOOL, self, HandToolHorseHarness.onAction, true, true, false, true, nil)
        spec.actionEventId = actionEventId
        g_inputBinding:setActionEventTextPriority(actionEventId, GS_PRIO_VERY_HIGH)
        g_inputBinding:setActionEventText(actionEventId, g_i18n:getText("action_horseHarness"))
        g_inputBinding:setActionEventActive(actionEventId, self:getIsHeld())
    end
end

function HandToolHorseHarness:onHeldStart()
    local spec = self[HandToolHorseHarness.SPEC_TABLE_NAME]
    if spec.actionEventId ~= nil then
        g_inputBinding:setActionEventActive(spec.actionEventId, true)
    end
    if HorseLead ~= nil then
        HorseLead.harnessSource = self.rootNode                 -- the collar in the hand hangs from the tool
        HorseLead.harnessSourceGear = HorseDynamics.gearOfTool(self)
    end
    local winch = g_currentMission ~= nil and g_currentMission.winchTow or nil
    if winch ~= nil and HorseHitch ~= nil then
        winch.hold(self.rootNode, false)                      -- (the green ring of the winch shows on the joint a click would hitch a harnessed horse to, never on a log)
        winch.gate = HorseHitch.ringFree
    end
end

function HandToolHorseHarness:onHeldEnd()
    local spec = self[HandToolHorseHarness.SPEC_TABLE_NAME]
    if spec.actionEventId ~= nil then
        g_inputBinding:setActionEventActive(spec.actionEventId, false)
    end
    if HorseLead ~= nil and HorseLead.harnessSource == self.rootNode then
        HorseLead.harnessSource = nil
    end
    local winch = g_currentMission ~= nil and g_currentMission.winchTow or nil
    if winch ~= nil then
        winch.putAway(self.rootNode)
    end
end

function HandToolHorseHarness:onAction(_, inputValue)
    if inputValue > 0.5 and HorseLead ~= nil then
        HorseDynamics.notify(HorseLead.harness(HorseDynamics.gearOfTool(self)))
    end
end
