--[[
    HorseHarnessItem.lua -- the harness as an object (vehicles/horseHarness: a dynamic shop vehicle you pick up with your hands and set down anywhere, like the ball). Bring a horse you ride next to it and
    press the game's own attach key (Q): the harness goes on the horse (the scripted harness HorseHarness draws on the horse is this one), the object is hidden and out of the physics while it is worn. The key again
    (with nothing hitched) takes it off: the object is put down beside the horse. A wagon is still hitched with the same key (HorseHitch): the key does that when a wagon is in reach.
    Hooks: the game's AttacherJoints.actionEventAttach (the Q handler on the horse's own attach event) is wrapped; HorseHitch shows the prompt (updateSaddle / silenceAttachKey).
    Worn state is not saved: after a reload the object lies where it was put on and the horse is bare.
]]
HorseHarnessItem = {}
HorseHarnessItem.REACH_M = 3.5               -- the object must be this close to the horse's root
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
function HorseHarnessItem.unequip(horse, ride)
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
    HorseHarnessItem.putDown(item, horse)
    say("taken off the horse")
    return "the harness is off: it lies beside the horse"
end

-- The object appears beside the horse (to its left, 2.2 m), on the ground.
function HorseHarnessItem.putDown(item, horse)
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
    local info = horse.spec_attacherJoints ~= nil and horse.spec_attacherJoints.attachableInfo or nil
    if info ~= nil and info.attachable ~= nil then
        return false                              -- a wagon is in reach: the key hitches it
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

-- the game's attach key on a horse: the harness first
if AttacherJoints ~= nil and AttacherJoints.actionEventAttach ~= nil and Utils ~= nil and not HorseHarnessItem.hooked then
    HorseHarnessItem.hooked = true
    AttacherJoints.actionEventAttach = Utils.overwrittenFunction(AttacherJoints.actionEventAttach, function(self, superFunc, ...)
        if HorseHarnessItem.handleAttach(self) then
            return
        end
        return superFunc(self, ...)
    end)
end
