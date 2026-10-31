--[[
    HorseLead.lua -- leads the horses of a pasture: a horse becomes a vehicle (the game's own startRiding, no player), is claimed to be ridden by a virtual rider and steered by this
    script, follows the player in bursts (walks, stands a while, follows again), gives up when something blocks it, and is given back when it is at a stable with the player.

    What the game's scripts show (PlaceableHusbandryAnimals:startRiding, Rideable): taking a horse swaps the pasture animal for a Rideable VEHICLE (the cluster loses one animal, the vehicle is
    loaded at the animal's position with the horse's ridable xml, and keeps a copy of the cluster); a Rideable near a pasture goes back into it by itself (doHusbandryCheck). On the server a
    rideable that is not "controlled" is held still every frame and its steering zeroed; the gait and the steer are plain setters. So: startRiding with no player, then claim the horse is
    controlled (a per-instance getIsControlled) and set gait and steer ourselves each frame. Proven in the game with the AnimalLab prototype (a horse followed the player out of its pasture).

    HorseLead.command(nil, "start" | "stop" | "status") is the one entry point (keys and console call it).
]]
HorseLead = {}

local function say(format, ...)
    print(string.format("[HorseDynamics] " .. format, ...))
end

-- The vehicle the player sits in (the horse he rides), nil on foot.
local function playerVehicle()
    if g_localPlayer == nil or g_localPlayer.getCurrentVehicle == nil then
        return nil
    end
    local ok, vehicle = pcall(function() return g_localPlayer:getCurrentVehicle() end)
    if ok and vehicle ~= nil and vehicle.rootNode ~= nil then
        return vehicle
    end
    return nil
end

local function playerPosition()
    local node = nil
    if g_localPlayer ~= nil then
        node = g_localPlayer.rootNode
        local vehicle = playerVehicle()
        if vehicle ~= nil then
            node = vehicle.rootNode
        end
    end
    if node == nil and getCamera ~= nil then
        node = getCamera()
    end
    if node == nil then
        return nil
    end
    local x, y, z = getWorldTranslation(node)
    return x, y, z
end

-- The pastures: { placeable, husbandry (the AnimalClusterHusbandry), id (the engine's husbandryId), animalType }
function HorseLead.husbandries()
    local out = {}
    local system = g_currentMission ~= nil and g_currentMission.husbandrySystem or nil
    for _, placeable in ipairs(system ~= nil and system.placeables or {}) do
        local spec = placeable.spec_husbandryAnimals
        local husbandry = spec ~= nil and spec.clusterHusbandry or nil
        if husbandry ~= nil and husbandry.husbandryId ~= nil then
            out[#out + 1] = { placeable = placeable, husbandry = husbandry, id = husbandry.husbandryId, animalType = spec.animalType }
        end
    end
    return out
end

-- The animals of one pasture, by engine animal id: { animalId, x, y, z, rx, ry, rz, rootNode, visualIndex }
function HorseLead.animals(entry)
    local list = {}
    for animalId in pairs(entry.husbandry.animalIdToCluster or {}) do
        local item = { animalId = animalId, visualIndex = (entry.husbandry.animalIdToVisualAnimalIndex or {})[animalId] }
        local ok = pcall(function()
            item.x, item.y, item.z = getAnimalPosition(entry.id, animalId)
            item.rx, item.ry, item.rz = getAnimalRotation(entry.id, animalId)
            item.rootNode = getAnimalRootNode(entry.id, animalId)
        end)
        if ok and item.x ~= nil then
            list[#list + 1] = item
        end
    end
    table.sort(list, function(a, b) return a.animalId < b.animalId end)
    return list
end

local function distance(ax, az, bx, bz)
    return math.sqrt((ax - bx) ^ 2 + (az - bz) ^ 2)
end

-- ===== the virtual rider: a horse of a pasture, steered by this script =====
-- What the game's scripts show (PlaceableHusbandryAnimals:startRiding, Rideable): taking a horse swaps the pasture animal for a Rideable VEHICLE (the cluster loses one animal, the vehicle is
-- loaded at the animal's position with the horse's ridable xml, and keeps a copy of the cluster); a Rideable near a pasture goes back into it by itself (doHusbandryCheck). On the server a
-- rideable that is not "controlled" is held still every frame and its steering zeroed; the gait and the steer are plain setters. So: startRiding with no player, then claim the horse is
-- controlled (a per-instance getIsControlled) and set gait and steer ourselves each frame, towards the player.
HorseLead.RIDE_ARRIVE_M = 3.5               -- stops this close to the player
HorseLead.RIDE_ARRIVE_MOUNTED_M = 2.4       -- ... this close to the horse (or vehicle) the player sits on: about a horse's length behind it
HorseLead.RIDE_KEEP_UP_MOUNTED_M = 6        -- a riding player does not wait for a pausing horse: the pause ends when it is this far behind
HorseLead.RIDE_WALK_M = 6                   -- starts to walk when further away than this
HorseLead.RIDE_TROT_M = 20                  -- (kept for the trot step below)
-- The gait steps up with the distance and eases back down as the horse closes in: { game gait name, from this far away }. A step is left only when the horse is RIDE_GAIT_MARGIN_M
-- inside its distance (no flicker between two gaits at the edge). The game's speeds for a horse: walk 2.5, canter 3.5, trot 5, gallop 10 m/s (the xml may differ).
HorseLead.RIDE_GAITS = { { "WALK", 6 }, { "CANTER", 12 }, { "TROT", 20 }, { "GALLOP", 45 } }
HorseLead.RIDE_GAIT_MARGIN_M = 3
HorseLead.RIDE_FIND_MS = 5000               -- how long to wait for the vehicle to be loaded
-- A horse that is led on a rope does not walk a straight line at a steady pace: it follows for a few seconds, stands, looks about, follows again. The follow phase lasts a random
-- time in RIDE_BURST_MS, the stand a random time in RIDE_PAUSE_MS (cut short when the player gets further than RIDE_KEEP_UP_M away, and none at all while it trots to catch up).
HorseLead.RIDE_BURST_MS = { 3500, 8000 }
HorseLead.RIDE_PAUSE_MS = { 1500, 4500 }
HorseLead.RIDE_KEEP_UP_M = 14
HorseLead.RIDE_STEER_GAIN = 1.2             -- steer (-1..1) per radian of heading error: gentle, it does not slam to full lock
HorseLead.RIDE_STEER_DEADBAND = 0.08        -- radians: no steering for a smaller error (no twitching on a straight run)
HorseLead.RIDE_STEER_RATE = 2.0             -- the steer moves at most this far per second (the horse eases into a turn and out of it)
HorseLead.RIDE_TURN_RATE_STILL = 3.5        -- rad/s: a horse that stands (paused, arrived) turns to face the player at this rate, in place (0: it turns only while it walks)
HorseLead.RIDE_FACE_MIN_M = 2.0             -- ... but not when the player is closer than this (it would spin around him)
HorseLead.RIDE_TURN_RATE = 7.0              -- rad/s (about 400 degrees a second): while it moves, the horse's heading is turned towards the player this fast (the game's own turning is 45 degrees a second: a gentle arc into the wall next to a gate). 0: only the steer is set
HorseLead.random = function(range) return range[1] + math.random() * (range[2] - range[1]) end
HorseLead.leashSource = nil                -- the node of the leash tool while it is in the hand (the rope starts there), set by HandToolHorseLeash
HorseLead.rides = {}                        -- the horses being led: { vehicle, known, from, waited, phase, phaseMs, stableMs }
HorseLead.RIDE_CLAIM_FALLBACK_MS = 1500    -- a vehicle that does not appear within 10 m of its horse is looked for further away after this long (nearest new one within RIDE_CLAIM_FAR_M)
HorseLead.RIDE_CLAIM_FAR_M = 80
HorseLead.RIDE_UNSTICK_TRIES = 2            -- a stuck horse backs up and turns this many times before it is given up on
HorseLead.RIDE_BACK_MS = 1800
HorseLead.CARROT_LOOSE_M = 80               -- the carrot also takes loose horse vehicles this close
HorseLead.NUDGE_M = 3.0                     -- a stuck horse is put this far away (the game's own setWorldPosition: the character controller follows)
HorseLead.WATCH_HALT_MS = 2500              -- a ridden horse that has been halted (blocked) this long is moved out of whatever holds it
HorseLead.WATCH_COOLDOWN_MS = 6000
HorseLead.RIDE_STUCK_MS = 4000              -- told to move, but not moved RIDE_STUCK_M in this long (a fence, a wall): it gives up following and is released
HorseLead.RIDE_STUCK_M = 0.5
HorseLead.RIDE_STABLE_CHECK_MS = 1000       -- how often a horse is checked for being at a stable
HorseLead.RIDE_STABLE_PLAYER_M = 15         -- ... and given back only when the player is within this of it (leading them there, not passing a stable)

local function normalizeAngle(angle)
    while angle > math.pi do angle = angle - 2 * math.pi end
    while angle < -math.pi do angle = angle + 2 * math.pi end
    return angle
end

function HorseLead.rideables()
    local list = {}
    local vehicles = g_currentMission ~= nil and g_currentMission.vehicleSystem ~= nil and g_currentMission.vehicleSystem.vehicles or {}
    for _, vehicle in ipairs(vehicles) do
        if vehicle.spec_rideable ~= nil and vehicle.rootNode ~= nil then
            list[#list + 1] = vehicle
        end
    end
    return list
end

-- The nearest horse vehicle that nobody rides and that is not being led: vehicle, distance (or nil).
function HorseLead.nearestLooseHorse(px, pz)
    local led = {}
    for _, ride in ipairs(HorseLead.rides) do
        if ride.vehicle ~= nil then
            led[ride.vehicle] = true
        end
    end
    local best, bestDistance = nil, math.huge
    for _, vehicle in ipairs(HorseLead.rideables()) do
        local ridden = vehicle.getIsEntered ~= nil and vehicle:getIsEntered() or (vehicle.getIsControlled ~= nil and vehicle:getIsControlled())
        if not led[vehicle] and not ridden and not vehicle.isDeleted then
            local x, _, z = getWorldTranslation(vehicle.rootNode)
            local d = distance(px, pz, x, z)
            if d < bestDistance then
                best, bestDistance = vehicle, d
            end
        end
    end
    return best, bestDistance
end

-- The virtual rider is a FLAG on the vehicle (rfVirtualRider), not a replacement of its getIsControlled: the game must see the horse as free (so that a player can mount it with the
-- enter key), and say "controlled" only inside the one game function that holds an uncontrolled rideable still (Rideable:onUpdateInterpolation, hooked below). getIsControlled is a FIELD of the
-- vehicle (the game copies it there), so it is swapped for the duration of that call and put back after it, error or not.
function HorseLead.claimVehicle(vehicle)
    vehicle.rfVirtualRider = true
end

function HorseLead.unclaimVehicle(vehicle)
    vehicle.rfVirtualRider = nil
end

-- Calls superFunc with the vehicle reporting "controlled" when it has a virtual rider. Returns what superFunc returns.
function HorseLead.withVirtualRider(self, superFunc, ...)
    if not self.rfVirtualRider then
        return superFunc(self, ...)
    end
    local own = self.getIsControlled
    self.getIsControlled = function() return true end
    local results = { pcall(superFunc, self, ...) }
    self.getIsControlled = own
    if not results[1] then
        error(results[2], 0)
    end
    return unpack(results, 2)
end

-- Does somebody else control this vehicle (a player who mounted it)? Asked outside the hook, so the game's own answer.
function HorseLead.isTakenOver(vehicle)
    local entered = vehicle.getIsEntered ~= nil and vehicle:getIsEntered()
    local controlled = vehicle.getIsControlled ~= nil and vehicle:getIsControlled()
    return entered == true or controlled == true
end

-- Gives a horse back: the virtual rider off, steering and gait reset, and the game's own check asked for (a rideable near a pasture goes back into it: doHusbandryCheck).
function HorseLead.releaseRide(ride)
    if HorseRope ~= nil then
        HorseRope.remove(ride)
    end
    local vehicle = ride.vehicle
    if vehicle ~= nil then
        HorseLead.unclaimVehicle(vehicle)
        local spec = vehicle.spec_rideable
        if spec ~= nil then
            spec.inputValues.axisSteer = 0
            spec.inputValues.currentGait = Rideable.GAITTYPES.STILL
            spec.doHusbandryCheck = 2000
        end
    end
end

-- Takes one pasture horse as a vehicle (the game's own startRiding with no player); the ride waits for its vehicle in updateRide. Returns the ride, or nil and why not.
function HorseLead.startHorse(entry, item, distanceToPlayer)
    local cluster = entry.husbandry.animalIdToCluster[item.animalId]
    local clusterId = cluster ~= nil and (cluster.id or (cluster.getId ~= nil and cluster:getId())) or nil
    if clusterId == nil then
        return nil, "the horse's cluster has no id (cannot call startRiding)"
    end
    local known = {}
    for _, vehicle in ipairs(HorseLead.rideables()) do
        known[vehicle] = true
    end
    local ok, err = pcall(entry.placeable.startRiding, entry.placeable, clusterId, nil)
    if not ok then
        say("ride: startRiding(%s) failed: %s", tostring(clusterId), tostring(err))
        return nil, "startRiding failed, see the log"
    end
    local ride = { known = known, from = { item.x, item.z }, waited = 0, stableMs = 0 }
    HorseLead.rides[#HorseLead.rides + 1] = ride
    say("ride: startRiding(cluster %s, no player) called for the horse %.0f m from you; waiting for the vehicle (%d in all)", tostring(clusterId), distanceToPlayer or 0, #HorseLead.rides)
    return ride
end

-- Is this vehicle already taken by one of the rides?
function HorseLead.isClaimed(vehicle)
    for _, ride in ipairs(HorseLead.rides) do
        if ride.vehicle == vehicle then
            return true
        end
    end
    return false
end

-- The horse pasture the player is in (the outline polygon of its outdoor area), else the nearest one with a horse within HorseLead.PASTURE_REACH_M: entry, or nil.
HorseLead.PASTURE_REACH_M = 40
function HorseLead.pastureOfPlayer(px, pz)
    local nearest, nearestDistance = nil, math.huge
    for _, entry in ipairs(HorseLead.husbandries()) do
        if entry.husbandry.animalTypeName == "HORSE" and entry.placeable.startRiding ~= nil then
            local spec = entry.placeable.spec_husbandryAnimals
            local polygon = spec ~= nil and spec.outdoorContourPolygon or nil
            if polygon ~= nil and polygon.getIsPosInside ~= nil then
                local ok, inside = pcall(polygon.getIsPosInside, polygon, px, pz)
                if ok and inside then
                    return entry
                end
            end
            for _, item in ipairs(HorseLead.animals(entry)) do
                local d = distance(px, pz, item.x, item.z)
                if d < nearestDistance then
                    nearest, nearestDistance = entry, d
                end
            end
        end
    end
    if nearest ~= nil and nearestDistance <= HorseLead.PASTURE_REACH_M then
        return nearest
    end
    return nil
end

-- The carrot: every horse of the pasture the player is in comes. Returns a message.
function HorseLead.callPasture()
    local px, _, pz = playerPosition()
    if px == nil then
        return "no player position"
    end
    local entry = HorseLead.pastureOfPlayer(px, pz)
    local count = 0
    local loose = HorseLead.rideables()                        -- (the horse vehicles that exist now: the ones the pasture horses are about to become are not among them)
    if entry ~= nil then
        for _, item in ipairs(HorseLead.animals(entry)) do
            local ride = HorseLead.startHorse(entry, item, distance(px, pz, item.x, item.z))
            if ride ~= nil then
                ride.carrot = true
                count = count + 1
            end
        end
    end
    -- and the horses that stand about as vehicles near you (released earlier, stuck somewhere, left out): the carrot gathers the herd
    for _, vehicle in ipairs(loose) do
        if not HorseLead.isClaimed(vehicle) and not vehicle.isDeleted and not HorseLead.isTakenOver(vehicle) then
            local x, _, z = getWorldTranslation(vehicle.rootNode)
            if distance(px, pz, x, z) <= HorseLead.CARROT_LOOSE_M then
                HorseLead.claimVehicle(vehicle)
                HorseLead.rides[#HorseLead.rides + 1] = { vehicle = vehicle, known = {}, from = { x, z }, waited = 0, stableMs = 0, carrot = true }
                count = count + 1
            end
        end
    end
    if count == 0 then
        return entry == nil and "no horse pasture here, and no loose horse near" or "no horse could be called"
    end
    return string.format("%d horse(s) come", count)
end

-- Lets go of every led horse that carries `flag` (ride.leash, ride.carrot): returns how many.
function HorseLead.releaseFlagged(flag)
    local released = 0
    for i = #HorseLead.rides, 1, -1 do
        local ride = HorseLead.rides[i]
        if ride[flag] then
            HorseLead.releaseRide(ride)
            table.remove(HorseLead.rides, i)
            released = released + 1
        end
    end
    return released
end

function HorseLead.hasFlagged(flag)
    for _, ride in ipairs(HorseLead.rides) do
        if ride[flag] then
            return true
        end
    end
    return false
end

-- The carrot, as a switch: calls the pasture's horses; used again it lets the ones it called go (HorseLead.callPasture marks them). Returns a message.
function HorseLead.carrot()
    if HorseLead.hasFlagged("carrot") then
        return string.format("%d horse(s) let go", HorseLead.releaseFlagged("carrot"))
    end
    return HorseLead.callPasture()
end

-- A fence gate within reach of the player is opened or closed (HorseGate). Returns a message, nil when there is none.
function HorseLead.gateAtPlayer()
    if HorseGate == nil then
        return nil
    end
    local px, _, pz = playerPosition()
    if px == nil then
        return nil
    end
    return HorseGate.toggleNearest(px, pz)
end

-- The leash, as a switch: takes the nearest horse (a pasture horse, or one that stands loose), or lets the leashed ones go when there are some. Returns a message.
-- Near a fence gate the click is for the gate first: with horses on the rope it opens or closes the gate instead of letting them go (the release key still does), and with no horse to take it does the
-- same, so a gate can be dealt with without putting the tool away and finding the gate's own trigger.
function HorseLead.leash()
    if HorseLead.hasFlagged("leash") then
        return HorseLead.gateAtPlayer() or string.format("%d horse(s) let go", HorseLead.releaseFlagged("leash"))
    end
    local before = #HorseLead.rides
    local message = HorseLead.command(nil, "start")
    local ride = HorseLead.rides[#HorseLead.rides]
    if #HorseLead.rides > before and ride ~= nil then
        ride.leash = true
        return message
    end
    return HorseLead.gateAtPlayer() or message
end

function HorseLead.command(_, argument)
    if argument == "free" then
        return HorseLead.freeNearest()
    elseif argument == "stop" then
        local count = #HorseLead.rides
        if count == 0 then
            return "no horse is being steered"
        end
        for _, ride in ipairs(HorseLead.rides) do
            HorseLead.releaseRide(ride)
        end
        HorseLead.rides = {}
        say("ride: stopped %d horse(s); each goes back into a stable by itself when it is near one", count)
        return string.format("stopped %d horse(s)", count)
    elseif argument ~= nil and argument ~= "start" and argument ~= "status" then
        return "usage: hdLead [start|stop|status|free]  (start again for each further horse; free moves the nearest horse out of whatever holds it)"
    end
    if argument == "status" then
        local found = 0
        for _, ride in ipairs(HorseLead.rides) do
            if ride.vehicle ~= nil then
                found = found + 1
            end
        end
        return string.format("%d horse(s) following, %d waiting for their vehicle", found, #HorseLead.rides - found)
    end
    for _, ride in ipairs(HorseLead.rides) do
        if ride.vehicle == nil then
            return "the previous horse is still being loaded: try again in a moment"
        end
    end
    local px, _, pz = playerPosition()
    if px == nil then
        return "no player position"
    end
    -- a horse that is already a vehicle and stands about loose (left out in a savegame, ridden out earlier): taken over when it is nearer than any horse of a pasture
    local loose, looseDistance = HorseLead.nearestLooseHorse(px, pz)
    local best, bestEntry, bestDistance = nil, nil, math.huge
    for _, entry in ipairs(HorseLead.husbandries()) do
        if entry.husbandry.animalTypeName == "HORSE" and entry.placeable.startRiding ~= nil then
            for _, item in ipairs(HorseLead.animals(entry)) do
                local d = distance(px, pz, item.x, item.z)
                if d < bestDistance then
                    best, bestEntry, bestDistance = item, entry, d
                end
            end
        end
    end
    if loose ~= nil and looseDistance < bestDistance then
        HorseLead.claimVehicle(loose)
        local x, _, z = getWorldTranslation(loose.rootNode)
        HorseLead.rides[#HorseLead.rides + 1] = { vehicle = loose, known = {}, from = { x, z }, waited = 0, stableMs = 0 }
        say("ride: a loose horse vehicle %.0f m from you is taken over (%d in all)", looseDistance, #HorseLead.rides)
        return "a loose horse is following you now"
    end
    if best == nil then
        return "no horse found (in a pasture, or standing loose)"
    end
    local ride, problem = HorseLead.startHorse(bestEntry, best, bestDistance)
    if ride == nil then
        return problem
    end
    return "the horse is being loaded as a vehicle, see the log"
end

-- The gait for the distance d, from the current one: up to the highest step whose distance d is beyond, down one step at a time once d is RIDE_GAIT_MARGIN_M inside the current step.
function HorseLead.rideGait(current, d)
    local gaits = Rideable.GAITTYPES
    local steps = {}
    for _, step in ipairs(HorseLead.RIDE_GAITS) do
        if gaits[step[1]] ~= nil then
            steps[#steps + 1] = { gait = gaits[step[1]], from = step[2] }
        end
    end
    local level = 0
    for i, step in ipairs(steps) do
        if step.gait == current then
            level = i
        end
    end
    local wanted = 0
    for i, step in ipairs(steps) do
        if d > step.from then
            wanted = i
        end
    end
    if wanted > level then
        level = wanted
    elseif level > 0 and d < steps[level].from - HorseLead.RIDE_GAIT_MARGIN_M then
        level = level - 1
    end
    return level == 0 and gaits.WALK or steps[level].gait
end

-- Puts a horse vehicle `metres` away in the direction (dx, dz), on the ground, facing that way: the game's own setWorldPosition (Rideable / CCTDrivable move the character controller with it),
-- the call the game uses to reset a vehicle. A horse pinned between bushes or in a collider cannot walk out; this does not need it to. Returns true when the call went through.
function HorseLead.nudge(vehicle, dx, dz, metres)
    if vehicle == nil or vehicle.setWorldPosition == nil or vehicle.rootNode == nil then
        return false
    end
    local length = math.sqrt(dx * dx + dz * dz)
    if length < 1e-6 then
        return false
    end
    local x, y, z = getWorldTranslation(vehicle.rootNode)
    local tx, tz = x + dx / length * metres, z + dz / length * metres
    local ty = y
    if getTerrainHeightAtWorldPos ~= nil and g_terrainNode ~= nil then
        ty = getTerrainHeightAtWorldPos(g_terrainNode, tx, 0, tz)
    end
    local ok, err = pcall(vehicle.setWorldPosition, vehicle, tx, ty + 0.2, tz, 0, math.atan2(dx, dz), 0, 1, true)
    if not ok then
        say("ride: moving the horse out failed: %s", tostring(err))
    end
    return ok
end

-- The console command / rescue: the horse vehicle nearest to the player (also the one he sits on) is put 3 m behind itself (the way it came: it was blocked in front). Returns a message.
function HorseLead.freeNearest()
    local px, _, pz = playerPosition()
    if px == nil then
        return "no player position"
    end
    local best, bestDistance = nil, math.huge
    for _, vehicle in ipairs(HorseLead.rideables()) do
        if not vehicle.isDeleted then
            local x, _, z = getWorldTranslation(vehicle.rootNode)
            local d = distance(px, pz, x, z)
            if d < bestDistance then
                best, bestDistance = vehicle, d
            end
        end
    end
    if best == nil or bestDistance > 8 then
        return "no horse within 8 m"
    end
    local angle = best.spec_rideable ~= nil and best.spec_rideable.currentTurnAngle or 0
    if HorseLead.nudge(best, -math.sin(angle), -math.cos(angle), HorseLead.NUDGE_M) then
        say("free: the nearest horse (%.1f m) was put %.0f m behind itself", bestDistance, HorseLead.NUDGE_M)
        return "the horse was moved out"
    end
    return "could not move the horse, see the log"
end

-- A horse that a player rides and that stays halted (the game halts a horse that moves less than it should for 0.9 s; again and again means it is pinned): moved out after WATCH_HALT_MS.
HorseLead.haltedFor = setmetatable({}, { __mode = "k" })
HorseLead.nudgedAt = setmetatable({}, { __mode = "k" })
HorseLead.clock = 0
function HorseLead.watchRidden(dt)
    HorseLead.clock = HorseLead.clock + dt
    for _, vehicle in ipairs(HorseLead.rideables()) do
        local spec = vehicle.spec_rideable
        local entered = vehicle.getIsEntered ~= nil and vehicle:getIsEntered()
        if entered and spec ~= nil and (spec.haltTimer or 0) > 0 then
            HorseLead.haltedFor[vehicle] = (HorseLead.haltedFor[vehicle] or 0) + dt
            if HorseLead.haltedFor[vehicle] >= HorseLead.WATCH_HALT_MS and HorseLead.clock - (HorseLead.nudgedAt[vehicle] or -1e9) >= HorseLead.WATCH_COOLDOWN_MS then
                HorseLead.haltedFor[vehicle] = 0
                HorseLead.nudgedAt[vehicle] = HorseLead.clock
                local angle = spec.currentTurnAngle or 0
                if HorseLead.nudge(vehicle, -math.sin(angle), -math.cos(angle), HorseLead.NUDGE_M) then
                    say("ride: the horse you ride was stuck (halted again and again): put %.0f m behind itself", HorseLead.NUDGE_M)
                end
            end
        else
            HorseLead.haltedFor[vehicle] = nil
        end
    end
end

-- The steer eases towards its target (a rate limit), instead of jumping to it every frame.
function HorseLead.easeSteer(spec, target, dt)
    local maxStep = HorseLead.RIDE_STEER_RATE * dt / 1000
    local current = spec.inputValues.axisSteer or 0
    spec.inputValues.axisSteer = current + math.max(-maxStep, math.min(maxStep, target - current))
end

-- one horse, one frame: find the vehicle, steer it, give it back when it is at a stable. Returns true when the horse is done (gone, lost, or given back).
function HorseLead.stepRide(ride, dt)
    if ride.vehicle == nil then
        ride.waited = ride.waited + dt
        local found, foundDistance = nil, math.huge
        for _, vehicle in ipairs(HorseLead.rideables()) do
            if not ride.known[vehicle] and not HorseLead.isClaimed(vehicle) then
                local x, _, z = getWorldTranslation(vehicle.rootNode)
                local d = distance(x, z, ride.from[1], ride.from[2])
                if (d < 10 or (ride.waited > HorseLead.RIDE_CLAIM_FALLBACK_MS and d < HorseLead.RIDE_CLAIM_FAR_M)) and d < foundDistance then
                    found, foundDistance = vehicle, d
                end
            end
        end
        if found ~= nil then
            ride.vehicle = found
            HorseLead.claimVehicle(found)                                            -- (the virtual rider)
            say("ride: the horse is a vehicle now%s; steering it towards you (Right Ctrl + V or hdLead stop to end)", foundDistance >= 10 and string.format(" (found %.0f m from where it stood)", foundDistance) or "")
            return false
        end
        if ride.waited > HorseLead.RIDE_FIND_MS then
            say("ride: no new rideable vehicle appeared near the horse within %d ms", HorseLead.RIDE_FIND_MS)
            return true
        end
        return false
    end
    local vehicle = ride.vehicle
    local spec = vehicle.spec_rideable
    local px, _, pz = playerPosition()
    if not vehicle.isDeleted and HorseLead.isTakenOver(vehicle) then
        HorseLead.unclaimVehicle(vehicle)
        say("ride: somebody mounted the horse: it is not led any more (the others keep following)")
        return true
    end
    if vehicle.isDeleted or spec == nil or px == nil then
        say("ride: the horse is gone (back in its pasture, or deleted)")
        return true
    end
    local x, _, z = getWorldTranslation(vehicle.rootNode)
    local d = distance(px, pz, x, z)
    -- at a stable with the player: given back (the game's own check then puts it into that stable, a different one from its own too, and deletes the vehicle)
    ride.stableMs = (ride.stableMs or 0) + dt
    if ride.stableMs >= HorseLead.RIDE_STABLE_CHECK_MS then
        ride.stableMs = 0
        local system = g_currentMission ~= nil and g_currentMission.husbandrySystem or nil
        if system ~= nil and system.getHusbandryInRideableRange ~= nil then
            local ok, inRange, husbandry = pcall(system.getHusbandryInRideableRange, system, vehicle)
            if ok and not inRange then
                ride.leftStable = true                    -- (a pasture horse starts inside its own stable's range: it only counts as arriving after it has been out of every range)
            elseif ok and inRange and husbandry ~= nil and ride.leftStable and d < HorseLead.RIDE_STABLE_PLAYER_M then
                HorseLead.releaseRide(ride)
                say("ride: the horse is at a stable and you are with it: given back, the game takes it in")
                return true
            end
        end
    end
    local diff = normalizeAngle(math.atan2(px - x, pz - z) - spec.currentTurnAngle)
    local mounted = playerVehicle() ~= nil
    local arriveM = mounted and HorseLead.RIDE_ARRIVE_MOUNTED_M or HorseLead.RIDE_ARRIVE_M
    local keepUpM = mounted and HorseLead.RIDE_KEEP_UP_MOUNTED_M or HorseLead.RIDE_KEEP_UP_M
    local gaits = Rideable.GAITTYPES
    local gait = spec.inputValues.currentGait
    -- backing out of whatever it is stuck in: reverse and turn for a moment, then try again
    if (ride.backingMs or 0) > 0 then
        ride.backingMs = ride.backingMs - dt
        spec.inputValues.currentGait = gaits.BACKWARDS or gaits.STILL
        HorseLead.easeSteer(spec, ride.backSteer or 1, dt)
        ride.markX, ride.stuckMs = nil, 0
        return false
    end
    -- the phase: following for a burst, then standing a while
    if ride.phase == nil then
        ride.phase, ride.phaseMs = "follow", HorseLead.random(HorseLead.RIDE_BURST_MS)
    end
    if ride.phase == "pause" then
        ride.phaseMs = ride.phaseMs - dt
        if ride.phaseMs <= 0 or d > keepUpM then
            ride.phase, ride.phaseMs = "follow", HorseLead.random(HorseLead.RIDE_BURST_MS)
        end
    elseif gait ~= gaits.STILL then
        ride.phaseMs = ride.phaseMs - dt                       -- (the burst counts while it moves)
        if ride.phaseMs <= 0 and d <= keepUpM then
            ride.phase, ride.phaseMs = "pause", HorseLead.random(HorseLead.RIDE_PAUSE_MS)
        end
    end
    local steerTarget = 0
    if ride.phase == "pause" or d < arriveM then
        gait = gaits.STILL
    else
        gait = HorseLead.rideGait(gait, d)
        if math.abs(diff) > HorseLead.RIDE_STEER_DEADBAND then
            steerTarget = math.max(-1, math.min(1, diff * HorseLead.RIDE_STEER_GAIN))
        end
    end
    spec.inputValues.currentGait = gait
    -- the heading itself is turned towards the player (a plain field of the Rideable: its movement and its looks follow it; setWorldPosition writes it too): fast while it moves (the game's own turning is
    -- 45 degrees a second: a gentle arc into the wall next to a gate), slower when it stands, in place. The steer stays at zero, so the game's slow turning does not fight it.
    if HorseLead.RIDE_TURN_RATE > 0 and spec.currentTurnAngle ~= nil then
        steerTarget = 0
        spec.inputValues.axisSteer = 0
        if d >= HorseLead.RIDE_FACE_MIN_M and math.abs(diff) > HorseLead.RIDE_STEER_DEADBAND then
            local rate = gait ~= gaits.STILL and HorseLead.RIDE_TURN_RATE or HorseLead.RIDE_TURN_RATE_STILL
            local maxTurn = rate * dt / 1000
            spec.currentTurnAngle = spec.currentTurnAngle + math.max(-maxTurn, math.min(maxTurn, diff))
            spec.currentTurnSpeed = 0
        end
    end
    -- the steer eases towards its target (a rate limit), instead of jumping to it every frame
    HorseLead.easeSteer(spec, steerTarget, dt)
    -- told to move but not moving (a fence, a wall, a tree): it gives up following; next to its pasture the game's stable check takes it in
    if ride.markX == nil or distance(x, z, ride.markX, ride.markZ) >= HorseLead.RIDE_STUCK_M then
        ride.markX, ride.markZ, ride.stuckMs = x, z, 0
    elseif gait ~= gaits.STILL then
        ride.stuckMs = (ride.stuckMs or 0) + dt
        if ride.stuckMs >= HorseLead.RIDE_STUCK_MS then
            ride.unstickTries = (ride.unstickTries or 0) + 1
            if ride.unstickTries > HorseLead.RIDE_UNSTICK_TRIES then
                if not ride.nudged then
                    -- backing up did not free it (pinned between bushes, in a collider): put it a few metres towards the player, once
                    ride.nudged = true
                    ride.stuckMs, ride.markX = 0, nil
                    if HorseLead.nudge(vehicle, px - x, pz - z, HorseLead.NUDGE_M) then
                        say("ride: a horse is stuck even after backing up: put %.0f m towards you", HorseLead.NUDGE_M)
                        return false
                    end
                end
                HorseLead.releaseRide(ride)
                say("ride: the horse cannot get on (something is in its way, even after backing up %d times and being moved): released; it stands there as a vehicle, or goes into a pasture it is next to", HorseLead.RIDE_UNSTICK_TRIES)
                return true
            end
            ride.backingMs = HorseLead.RIDE_BACK_MS
            ride.backSteer = (ride.unstickTries % 2 == 1) and 1 or -1
            ride.stuckMs, ride.markX = 0, nil
            say("ride: a horse is stuck: backing up and turning (try %d of %d)", ride.unstickTries, HorseLead.RIDE_UNSTICK_TRIES)
        end
    else
        ride.stuckMs = 0
    end
    return false
end

-- each frame: every horse that is being led
-- The node a leashed horse's rope starts at: the leash in the hand, else the saddle of the horse (or the vehicle) the player sits on, else the player's chest. The horse is still led when the tool is put away
-- or the player mounts, so the rope stays.
function HorseLead.ropeSource()
    if HorseLead.leashSource ~= nil then
        return HorseLead.leashSource
    end
    if HorseRope == nil or g_localPlayer == nil then
        return nil
    end
    local vehicle = playerVehicle()
    if vehicle ~= nil then
        return HorseRope.anchorOn(vehicle.rootNode, 0, 1.3, 0.2)
    end
    return HorseRope.anchorOn(g_localPlayer.rootNode, 0, 1.1, 0)
end

function HorseLead.updateRide(dt)
    HorseLead.watchRidden(dt)
    if HorseRope ~= nil then
        -- the leash in the hand shows a short end of rope while no horse is on it (the tool itself has no model)
        local led = false
        for _, ride in ipairs(HorseLead.rides) do
            led = led or (ride.leash and ride.vehicle ~= nil)
        end
        HorseRope.syncStub(not led and HorseLead.leashSource or nil)
    end
    for i = #HorseLead.rides, 1, -1 do
        local ride = HorseLead.rides[i]
        if HorseLead.stepRide(ride, dt) then
            if HorseRope ~= nil then
                HorseRope.remove(ride)
            end
            table.remove(HorseLead.rides, i)
        elseif HorseRope ~= nil and ride.leash and ride.vehicle ~= nil then
            HorseRope.sync(ride, HorseLead.ropeSource())
        end
    end
end

-- ===== hook (the game's class, patched once when this file loads) =====
if Rideable ~= nil and Rideable.onUpdateInterpolation ~= nil and Utils ~= nil and Utils.overwrittenFunction ~= nil and not HorseLead.hooked then
    HorseLead.hooked = true
    Rideable.onUpdateInterpolation = Utils.overwrittenFunction(Rideable.onUpdateInterpolation, function(self, superFunc, ...)
        return HorseLead.withVirtualRider(self, superFunc, ...)
    end)
end
