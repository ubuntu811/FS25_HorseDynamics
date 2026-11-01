--[[
    HorseGate.lua -- opens and closes a fence gate near the player with the leash click, so a horse on the rope does not have to be let go, the tool put away and the gate's own small trigger area found.

    A gate is a group of AnimatedObjects (the leaves; the game's own trigger and key work on them): the newer pasture fences keep them in segment.animatedObjects of the fence's segments
    (PlaceableHusbandryFence), the older fence placeables in spec_fence.animatedObjects. Pressing the key at a gate calls animatedObject:setDirection(direction * -1) (AnimatedObjectActivatable:onAnimationInputToggle);
    setDirection(0) of an idle gate opens it when it is closed and closes it when it is open, so that is exactly what is called here, for every leaf of the gate. The game's own farm check
    (getCanBeTriggered: land of another farm) is respected.
]]
HorseGate = {}
HorseGate.REACH_M = 4.5          -- a gate counts when its door or its trigger is this close to the player (horizontally)

-- The leaves of every gate, as groups: { animatedObject, ... } (the leaves of one gate), from every fence placeable.
function HorseGate.gates()
    local out = {}
    local system = g_currentMission ~= nil and g_currentMission.placeableSystem or nil
    for _, placeable in ipairs(system ~= nil and system.placeables or {}) do
        local fence = placeable.spec_husbandryFence ~= nil and placeable.spec_husbandryFence.fence or nil
        for _, segment in ipairs(fence ~= nil and fence.segments or {}) do
            if segment.animatedObjects ~= nil and #segment.animatedObjects > 0 then
                out[#out + 1] = segment.animatedObjects
            end
        end
        local old = placeable.spec_fence ~= nil and placeable.spec_fence.animatedObjects or nil
        for _, animatedObject in ipairs(old or {}) do
            out[#out + 1] = { animatedObject }
        end
    end
    return out
end

-- How far (horizontally) the player is from a gate: the nearest of its trigger and its moving parts, over all of its leaves.
function HorseGate.distance(leaves, px, pz)
    local best = math.huge
    local function consider(node)
        if node ~= nil then
            local x, _, z = getWorldTranslation(node)
            best = math.min(best, math.sqrt((x - px) ^ 2 + (z - pz) ^ 2))
        end
    end
    for _, leaf in ipairs(leaves) do
        consider(leaf.triggerNode)
        for _, part in pairs(leaf.animation ~= nil and leaf.animation.parts or {}) do
            consider(part.node)
        end
    end
    return best
end

-- The nearest gate within reach: leaves, distance. nil when there is none.
function HorseGate.nearest(px, pz)
    local found, foundDistance = nil, HorseGate.REACH_M
    for _, leaves in ipairs(HorseGate.gates()) do
        local d = HorseGate.distance(leaves, px, pz)
        if d <= foundDistance then
            found, foundDistance = leaves, d
        end
    end
    return found, foundDistance
end

-- Toggles the nearest gate within reach. Returns a message, or nil when there is no gate in reach.
function HorseGate.toggleNearest(px, pz)
    local leaves = HorseGate.nearest(px, pz)
    if leaves == nil then
        return nil
    end
    return HorseGate.toggle(leaves)
end

-- Toggles the given gate (its leaves). Returns a message.
function HorseGate.toggle(leaves)
    local moved, opening = 0, false
    for _, leaf in ipairs(leaves) do
        if leaf.getCanBeTriggered == nil or leaf:getCanBeTriggered() then
            local ok, err = pcall(leaf.setDirection, leaf, leaf.animation.direction * -1)
            if ok then
                moved = moved + 1
                opening = leaf.animation.direction > 0
            else
                print("[HorseDynamics] gate: could not be moved: " .. tostring(err))
            end
        end
    end
    if moved == 0 then
        return "this gate is not yours to open"
    end
    return opening and "gate opens" or "gate closes"
end
