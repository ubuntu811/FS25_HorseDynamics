--[[
    HorseHarnessItem.lua -- the harness as an object (vehicles/horseHarness: a dynamic shop vehicle you pick up with your hands and set down anywhere, like the ball).
    Carry it up to a horse (hands holding it, within AUTO_M of the horse): it goes on (the scripted harness HorseHarness draws on the horse is this one), the object is hidden and out of the physics while worn.
    Look at the horse in its harness and click (the hands' pick-up key): the harness is in your hand again. The attach key (Q) from the saddle does the same as before (puts on a lying one / takes it off).
    Hooks: HandToolHands.onUpdate (appended: auto-equip, the prompt) and HandToolHands.onPickUpAction (overwritten: the click on a harnessed horse), HorseHitch.onSaddleAttach (the Q key, via HorseJoint).
    Worn state is not saved: after a reload the object lies where it was put on and the horse is bare.
]]
HorseHarnessItem = {}
HorseHarnessItem.REACH_M = 3.5               -- the object must be this close to the horse's root
HorseHarnessItem.AUTO_M = 2.0                -- a carried harness this close to a horse's root goes on
HorseHarnessItem.TAKE_M = 4.0                -- a harnessed horse this far along the look ray can be clicked
HorseHarnessItem.LOOK_R = 1.2                -- ... and the ray passes this close to its middle
HorseHarnessItem.REARM_M = 3.0               -- a harness taken off a horse goes on it again only after it has been this far from it
HorseHarnessItem.GEAR = "leather"            -- the harness the scripts draw: leather straps
HorseHarnessItem.items = setmetatable({}, { __mode = "k" })     -- the harness objects that exist

local function say(format, ...)
    print(string.format("[HorseDynamics] harness item: " .. format, ...))
end

local function rootPos(vehicle)
    if vehicle == nil or vehicle.rootNode == nil or (entityExists ~= nil and not entityExists(vehicle.rootNode)) then
        return nil
    end
    return getWorldTranslation(vehicle.rootNode)
end

-- The ride of this horse, if the scripts have one.
function HorseHarnessItem.rideOf(horse)
    for _, ride in ipairs(HorseLead.rides) do
        if ride.vehicle == horse then
            return ride
        end
    end
    return nil
end

-- The nearest harness object lying within reach of the horse (not worn, not deleted), or nil.
function HorseHarnessItem.candidate(horse)
    local hx, _, hz = rootPos(horse)
    if hx == nil then
        return nil
    end
    local best, bestD = nil, HorseHarnessItem.REACH_M
    for item in pairs(HorseHarnessItem.items) do
        if not item.isDeleted and item.horseWornBy == nil then
            local x, _, z = rootPos(item)
            if x ~= nil then
                local d = math.sqrt((x - hx) ^ 2 + (z - hz) ^ 2)
                if d < bestD then
                    best, bestD = item, d
                end
            end
        end
    end
    return best
end

-- Puts the object's harness on the horse: a ride for it (the harness code lives in the rides), harness on, the object out of the world.
function HorseHarnessItem.equip(horse, item)
    local ride = HorseHarnessItem.rideOf(horse)
    if ride == nil then
        local x, _, z = rootPos(horse)
        ride = { vehicle = horse, known = {}, from = { x, z }, waited = 0, stableMs = 0 }
        HorseLead.rides[#HorseLead.rides + 1] = ride
        ride.createdForHarness = true
    end
    ride.harness = true
    ride.harnessGear = HorseHarnessItem.GEAR
    ride.harnessItem = item
    if horse.getIsEntered ~= nil and horse:getIsEntered() then
        ride.ridden = true                       -- (a horse in its harness that somebody sits on is kept: HorseLead.stepRide)
    else
        ride.stay = true
        HorseLead.claimVehicle(horse)
    end
    item.horseWornBy = horse
    pcall(item.removeFromPhysics, item)
    pcall(item.setVisibility, item, false)
    say("put on the horse")
    return "the harness is on: press the attach key again to take it off"
end

-- Takes the harness off: the object is put down beside the horse and into the physics again.
function HorseHarnessItem.unequip(horse, ride, at)
    local item = ride.harnessItem
    ride.harness, ride.harnessItem = nil, nil
    if HorseHarness ~= nil and HorseHarness.destroy ~= nil then
        pcall(HorseHarness.destroy, ride)
    end
    if ride.createdForHarness and ride.ridden then
        HorseLead.releaseRide(ride)               -- (a horse that is only ridden: the ride goes, the game has it back)
        for i = #HorseLead.rides, 1, -1 do
            if HorseLead.rides[i] == ride then
                table.remove(HorseLead.rides, i)
            end
        end
    end
    item.rearm = horse
    HorseHarnessItem.putDown(item, horse, at)
    say("taken off the horse")
    return "the harness is off: it lies beside the horse"
end

-- The object appears beside the horse (to its left, 2.2 m), on the ground; at = { x, y, z } puts it there instead.
function HorseHarnessItem.putDown(item, horse, at)
    if item == nil or item.isDeleted then
        return
    end
    local hx, _, hz = rootPos(horse)
    if hx == nil then
        hx, hz = rootPos(item)
        if hx == nil then
            return
        end
    end
    local dx, _, dz = 1, 0, 0
    if horse ~= nil and horse.rootNode ~= nil then
        dx, _, dz = localDirectionToWorld(horse.rootNode, 1, 0, 0)
    end
    local x, z = hx + dx * 2.2, hz + dz * 2.2
    local y = getTerrainHeightAtWorldPos(g_terrainNode, x, 0, z) + 0.3
    if at ~= nil then
        x, y, z = at[1], at[2], at[3]            -- (in front of the player: the hands take it from there)
    end
    pcall(item.setAbsolutePosition, item, x, y, z, 0, math.atan2(dx, dz), 0)
    pcall(item.addToPhysics, item)
    pcall(item.setVisibility, item, true)
    item.horseWornBy = nil
end

-- Called by the Q handler on the horse: true when the key was used here (the harness put on or off), false: the game's own handler goes on (a wagon).
function HorseHarnessItem.handleAttach(horse)
    if horse == nil or horse.spec_rideable == nil then
        return false
    end
    local ride = HorseHarnessItem.rideOf(horse)
    if ride ~= nil and ride.harness and ride.harnessItem ~= nil then
        if ride.hitch ~= nil or ride.joined ~= nil then
            return false                          -- hitched: the key unhitches (the game's handler / HorseHitch)
        end
        HorseDynamics.notify(HorseHarnessItem.unequip(horse, ride))
        return true
    end
    if ride == nil or not ride.harness then
        local item = HorseHarnessItem.candidate(horse)
        if item ~= nil then
            HorseDynamics.notify(HorseHarnessItem.equip(horse, item))
            return true
        end
    end
    return false
end

-- What the key on this horse should say about the harness (the prompt, HorseHitch): nil = nothing to offer.
function HorseHarnessItem.promptFor(horse)
    local ride = HorseHarnessItem.rideOf(horse)
    if ride ~= nil and ride.harness then
        if ride.harnessItem ~= nil and ride.hitch == nil and ride.joined == nil then
            return g_i18n:getText("hd_takeHarnessOff", g_currentModName)
        end
        return nil
    end
    if HorseHarnessItem.candidate(horse) ~= nil then
        return g_i18n:getText("hd_putHarnessOn", g_currentModName)
    end
    return nil
end

-- A harness object whose horse is gone (deleted, back in a pasture) is put back into the world where the horse was.
function HorseHarnessItem.update(_)
    HorseHarnessItem.install()
    for item in pairs(HorseHarnessItem.items) do
        local horse = item.horseWornBy
        if horse ~= nil and not item.isDeleted then
            local ride = HorseHarnessItem.rideOf(horse)
            if horse.isDeleted or ride == nil or ride.harnessItem ~= item then
                HorseHarnessItem.putDown(item, horse.isDeleted and nil or horse)
                say("the horse is gone: the harness is put back in the world")
            end
        end
    end
end

-- ---------------------------------------------------------------------------------------------- the hands

local function localHands()
    local player = g_localPlayer
    local hands = player ~= nil and player.hands or nil
    if hands ~= nil and hands.getIsHoldingItem ~= nil and hands.spec_hands ~= nil then
        return hands
    end
    return nil
end

-- The harness object the hands hold (and the hands), or nil.
function HorseHarnessItem.held()
    local hands = localHands()
    if hands == nil or not hands:getIsHoldingItem() then
        return nil
    end
    local node = hands:getHeldItem()
    for item in pairs(HorseHarnessItem.items) do
        if not item.isDeleted and item.rootNode == node then
            return item, hands
        end
    end
    return nil
end

-- Every horse (a rideable vehicle with a root).
local function eachHorse()
    local vehicles = g_currentMission ~= nil and g_currentMission.vehicleSystem ~= nil and g_currentMission.vehicleSystem.vehicles or {}
    local list = {}
    for _, vehicle in ipairs(vehicles) do
        if vehicle.spec_rideable ~= nil and not vehicle.isDeleted and rootPos(vehicle) ~= nil then
            list[#list + 1] = vehicle
        end
    end
    return list
end

-- A carried harness within reach of a bare horse goes on it: the hands let go, the horse wears it.
function HorseHarnessItem.autoEquip()
    local item, hands = HorseHarnessItem.held()
    if item == nil then
        return
    end
    local ix, _, iz = rootPos(item)
    if ix == nil then
        return
    end
    for _, horse in ipairs(eachHorse()) do
        local hx, _, hz = rootPos(horse)
        local d = math.sqrt((ix - hx) ^ 2 + (iz - hz) ^ 2)
        if item.rearm == horse then
            if d > HorseHarnessItem.REARM_M then
                item.rearm = nil
            end
        elseif d < HorseHarnessItem.AUTO_M then
            local ride = HorseHarnessItem.rideOf(horse)
            if ride == nil or not ride.harness then
                hands:dropHeldItem()
                HorseHarnessItem.notifyOn(HorseHarnessItem.equip(horse, item))
                return
            end
        end
    end
end

function HorseHarnessItem.notifyOn(text)
    if HorseDynamics ~= nil and HorseDynamics.notify ~= nil then
        HorseDynamics.notify(text)
    end
end

-- The horse in a harness from an object that the look ray passes (the player's targeter), with its ride; nil when there is none or something is hitched.
function HorseHarnessItem.lookedAtWorn()
    local player = g_localPlayer
    if player == nil or player.targeter == nil or player.targeter.getLastLookRay == nil then
        return nil
    end
    local ox, oy, oz, dx, dy, dz = player.targeter:getLastLookRay()
    if ox == nil or dx == nil then
        return nil
    end
    for _, ride in ipairs(HorseLead.rides) do
        local horse = ride.vehicle
        if ride.harness and ride.harnessItem ~= nil and ride.hitch == nil and ride.joined == nil and not ride.harnessItem.isDeleted and horse ~= nil and not horse.isDeleted then
            local hx, hy, hz = rootPos(horse)
            if hx ~= nil then
                local px, py, pz = hx - ox, hy + 1.0 - oy, hz - oz
                local t = px * dx + py * dy + pz * dz
                if t > 0 and t < HorseHarnessItem.TAKE_M then
                    local qx, qy, qz = px - dx * t, py - dy * t, pz - dz * t
                    if math.sqrt(qx * qx + qy * qy + qz * qz) < HorseHarnessItem.LOOK_R then
                        return horse, ride
                    end
                end
            end
        end
    end
    return nil
end

-- The click on a harnessed horse: the harness comes off into the hands (set down in front of the player, picked up from there).
function HorseHarnessItem.takeToHand(horse, ride, hands)
    local item = ride.harnessItem
    local player = g_localPlayer
    local ox, oy, oz, dx, dy, dz = player.targeter:getLastLookRay()
    local at = { ox + dx * 1.5, oy + dy * 1.5, oz + dz * 1.5 }
    HorseHarnessItem.notifyOn(HorseHarnessItem.unequip(horse, ride, at))
    if item ~= nil and not item.isDeleted and hands:pickUpTarget({ node = item.rootNode, distance = 1.5 }) then
        say("in your hand")
    end
end

-- Hooks on the game's hands (installed once the class exists).
function HorseHarnessItem.install()
    if HorseHarnessItem.hooked or HandToolHands == nil or Utils == nil then
        return
    end
    HorseHarnessItem.hooked = true
    HandToolHands.onUpdate = Utils.appendedFunction(HandToolHands.onUpdate, function(self, dt)
        if self ~= localHands() then
            return
        end
        HorseHarnessItem.autoEquip()
        if not self:getIsHoldingItem() and HorseHarnessItem.lookedAtWorn() ~= nil then
            local id = self.spec_hands.pickUpActionEventId
            if id ~= nil then
                g_inputBinding:setActionEventActive(id, true)
                g_inputBinding:setActionEventText(id, g_i18n:getText("hd_takeHarnessOff", g_currentModName))
            end
        end
    end)
    HandToolHands.onPickUpAction = Utils.overwrittenFunction(HandToolHands.onPickUpAction, function(self, superFunc, ...)
        if self == localHands() and not self:getIsHoldingItem() then
            local horse, ride = HorseHarnessItem.lookedAtWorn()
            if horse ~= nil then
                HorseHarnessItem.takeToHand(horse, ride, self)
                return
            end
        end
        return superFunc(self, ...)
    end)
end
HorseHarnessItem.install()
