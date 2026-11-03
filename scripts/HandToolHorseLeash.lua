--[[
    HandToolHorseLeash.lua -- the leash: held in the hand, the primary action takes the nearest horse (a horse of a pasture, or one that stands loose) on the leash: it follows you; the same
    action again lets the leashed horses go. (HorseLead.leash; with no horse in reach it hooks the attacher joint you look at, the winch of FS25_WinchTow, as an easter egg)
]]
HandToolHorseLeash = {}
HandToolHorseLeash.SPEC_TABLE_NAME = "spec_" .. g_currentModName .. ".horseLeash"

function HandToolHorseLeash.prerequisitesPresent(_)
    return true
end

function HandToolHorseLeash.registerEventListeners(handToolType)
    SpecializationUtil.registerEventListener(handToolType, "onLoad", HandToolHorseLeash)
    SpecializationUtil.registerEventListener(handToolType, "onRegisterActionEvents", HandToolHorseLeash)
    SpecializationUtil.registerEventListener(handToolType, "onHeldStart", HandToolHorseLeash)
    SpecializationUtil.registerEventListener(handToolType, "onHeldEnd", HandToolHorseLeash)
end

-- The rope prop of the base game has a hidden static collision shape ("col", made for a pier): on a tool that moves with the player's hand it could push or block him, so every node
-- called "col" under the tool is deleted. Best effort: nothing is done when the nodes cannot be walked.
function HandToolHorseLeash.stripCollision(root)
    if root == nil or getNumOfChildren == nil or getChildAt == nil or getName == nil or delete == nil then
        return 0
    end
    local doomed = {}
    local function walk(node, depth)
        if depth > 8 then
            return
        end
        for i = 0, getNumOfChildren(node) - 1 do
            local child = getChildAt(node, i)
            if getName(child) == "col" then
                doomed[#doomed + 1] = child
            else
                walk(child, depth + 1)
            end
        end
    end
    pcall(walk, root, 0)
    local removed = 0
    for _, node in ipairs(doomed) do
        if pcall(delete, node) then
            removed = removed + 1
        end
    end
    return removed
end

function HandToolHorseLeash:onLoad(_)
    self[HandToolHorseLeash.SPEC_TABLE_NAME] = { actionEventId = nil }
    if HorseDynamics.gearOfTool(self) == "leather" and HorseRope ~= nil then
        HorseRope.leatherProp(self.rootNode)                    -- (the leather tool looks like leather in the hand)
    end
    local removed = HandToolHorseLeash.stripCollision(self.rootNode)
    if removed > 0 then
        print(string.format("[HorseDynamics] leash: removed %d collision shape(s) of the rope prop", removed))
    end
end

function HandToolHorseLeash:onRegisterActionEvents()
    local spec = self[HandToolHorseLeash.SPEC_TABLE_NAME]
    if self:getIsActiveForInput(true) then
        local _, actionEventId = self:addActionEvent(InputAction.ACTIVATE_HANDTOOL, self, HandToolHorseLeash.onAction, true, true, false, true, nil)
        spec.actionEventId = actionEventId
        g_inputBinding:setActionEventTextPriority(actionEventId, GS_PRIO_VERY_HIGH)
        g_inputBinding:setActionEventText(actionEventId, g_i18n:getText("action_horseLeash"))
        g_inputBinding:setActionEventActive(actionEventId, self:getIsHeld())
    end
end

function HandToolHorseLeash:onHeldStart()
    local spec = self[HandToolHorseLeash.SPEC_TABLE_NAME]
    if spec.actionEventId ~= nil then
        g_inputBinding:setActionEventActive(spec.actionEventId, true)
    end
    if HorseLead ~= nil then
        HorseLead.leashSource = self.rootNode                 -- the leashed horses' ropes start at the leash in the hand
    end
    local winch = g_currentMission ~= nil and g_currentMission.winchTow or nil
    if winch ~= nil then
        winch.hold(self.rootNode)                             -- (the winch easter egg: its rope starts at the leash in the hand)
        winch.hint = HorseHitch ~= nil and HorseHitch.leashHint or nil          -- (a log on the leash: the ring is round the harness ring of the horse a click would hand it to)
        winch.gate = HorseLead ~= nil and HorseLead.winchFree or nil     -- (and its green ring only shows where a click would hook, not when a horse is in reach)
    end
end

function HandToolHorseLeash:onHeldEnd()
    local spec = self[HandToolHorseLeash.SPEC_TABLE_NAME]
    if spec.actionEventId ~= nil then
        g_inputBinding:setActionEventActive(spec.actionEventId, false)
    end
    if HorseLead ~= nil and HorseLead.leashSource == self.rootNode then
        HorseLead.leashSource = nil                           -- (the ropes are hidden while the leash is put away; the horses stay led)
    end
    local winch = g_currentMission ~= nil and g_currentMission.winchTow or nil
    if winch ~= nil then
        winch.putAway(self.rootNode)                          -- (a vehicle on the winch is let go when the tool is put away)
    end
end

function HandToolHorseLeash:onAction(_, inputValue)
    if inputValue > 0.5 and HorseLead ~= nil then
        HorseDynamics.notify(HorseLead.leash(HorseDynamics.gearOfTool(self)))
    end
end
