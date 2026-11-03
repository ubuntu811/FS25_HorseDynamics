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
HorseLead.RIDE_ARRIVE_M = 5                 -- stops this close to the player (the carrot's herd: at 3.5 m the first one stood with its mane in the camera, the rest queued behind it)
HorseLead.RIDE_ARRIVE_SPREAD_M = 2.5        -- ... plus a distance of its own for each horse (0 to this, chosen once), so the herd stands scattered round the player and not in a ring
HorseLead.RIDE_ARRIVE_MOUNTED_M = 2.4       -- ... this close to the horse (or vehicle) the player sits on: about a horse's length behind it
-- On the leash a rope is as long as it is (HorseRope.LENGTH_M): the horse does not wander off and pause, it stays within the rope, stops when you stop and starts again only when the rope is nearly taut.
-- All distances are from the horse's ROOT NODE, which is the middle of its body: facing you, its nose is about 1.5 m ahead of that (the head bone sits 1.14 m ahead, the nose about 1.6 m). So a stop at 3.4 m
-- is a nose 1.9 m from you; the first version stopped at 2.0 m and put the horse's face in the player's.
HorseLead.HEAD_REACH_M = 1.5
HorseLead.LEASH_REACH_M = 4              -- the leash only takes a horse this close to the player (the rope is 3 m: you walk up to a horse, you do not summon it; the carrot is the one that calls)
HorseLead.RIDE_ARRIVE_LEASH_M = 3.4         -- stops this close to the player (the nose is about 1.9 m from him, the rope hangs slack)
HorseLead.RIDE_LEASH_RESUME_M = 0.4         -- ... and walks on again only when it is this much further than that (no stop and go at the edge)
HorseLead.RIDE_GAITS_LEASH = { { "WALK", 3.4 }, { "CANTER", 4.0 }, { "TROT", 4.6 }, { "GALLOP", 9.4 } }   -- by rank, slowest first (see rideGait): a horse that has to stay on a 3 m rope is at the fastest useful gait at 3.2 m
HorseLead.RIDE_GAIT_MARGIN_LEASH_M = 0.4
-- A player who walks up to a horse (any horse that is led, not a mounted player): it steps back, while he is in front of it and closer than RIDE_BACKOFF_M, until he is RIDE_BACKOFF_END_M away
-- (root distances: its nose is then 1.2 m from him, and 1.6 m when it stops).
HorseLead.RIDE_BACKOFF_M = 2.7
HorseLead.RIDE_BACKOFF_END_M = 3.1
HorseLead.RIDE_BACKOFF_CONE = 1.0           -- radians: "in front of it" is within this angle of the way it faces
HorseLead.RIDE_KEEP_UP_MOUNTED_M = 6        -- a riding player does not wait for a pausing horse: the pause ends when it is this far behind
HorseLead.RIDE_WALK_M = 6                   -- starts to walk when further away than this
HorseLead.RIDE_TROT_M = 20                  -- (kept for the trot step below)
-- The gait steps up with the distance and eases back down as the horse closes in: { game gait name, from this far away }. A step is left only when the horse is RIDE_GAIT_MARGIN_M
-- inside its distance (no flicker between two gaits at the edge). The steps are by rank (slowest gait first, ordered by the horse's own top speeds, see rideGait). The horse's xml (character/animals/domesticated/horse/horse.xml):
-- walk 1.08, trot 2.5, canter 5.0, gallop 10 m/s, backwards 1.45, turnSpeed 40 degrees a second, minTurnRadius 3.5 m.
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
HorseLead.RIDE_TURN_RATE_STILL_DEFAULT = 3.5
HorseLead.RIDE_TURN_RATE_STILL = 3.5        -- rad/s: a horse that stands (paused, arrived) turns to face the player at this rate, in place (0: it turns only while it walks)
HorseLead.RIDE_FACE_MIN_M = 2.0             -- ... but not when the player is closer than this (it would spin around him)
HorseLead.RIDE_TURN_RATE = 7.0              -- rad/s (about 400 degrees a second): while it moves, the horse's heading is turned towards the player this fast (the game's own turning is 45 degrees a second: a gentle arc into the wall next to a gate). 0: only the steer is set
HorseLead.random = function(range) return range[1] + math.random() * (range[2] - range[1]) end
HorseLead.harnessSource = nil              -- the node of the harness tool while it is in the hand (it shows a collar), set by HandToolHorseHarness
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
-- Is the horse in the range of a pasture (the game takes a rideable there into it by itself)? true / false, nil when the game cannot say.
function HorseLead.inPastureRange(vehicle)
    local system = g_currentMission ~= nil and g_currentMission.husbandrySystem or nil
    if system == nil or system.getHusbandryInRideableRange == nil or vehicle == nil then
        return nil
    end
    local ok, inRange = pcall(system.getHusbandryInRideableRange, system, vehicle)
    if not ok then
        return nil
    end
    return inRange == true
end

-- Lets the horses with this flag go. Returns how many, and how many of them keep their halter. A horse that wears the harness is not given back: it stays where it is, wearing it. The halter: inside a pasture it
-- goes off (the horse goes back in), outside it stays on (a horse standing in the middle of nowhere does not lose its halter because the player let go of the lead): only the rope is gone, the horse stands there
-- as a ride that stays (the leash tool takes it again, a pasture takes it in).
function HorseLead.releaseFlagged(flag)
    local released, haltered = 0, 0
    for i = #HorseLead.rides, 1, -1 do
        local ride = HorseLead.rides[i]
        if ride[flag] then
            local keepHalter = flag == "leash" and ride.vehicle ~= nil and ride.halter ~= nil and HorseLead.inPastureRange(ride.vehicle) == false
            if (ride.harness or keepHalter) and ride.vehicle ~= nil then
                ride[flag] = nil
                ride.stay = ride.leash == nil and ride.carrot == nil or nil
                ride.halterOn = keepHalter or nil
                if keepHalter then
                    haltered = haltered + 1
                end
                if HorseRope ~= nil then
                    HorseRope.remove(ride, true, keepHalter)      -- (the halter and the rope go; with keepHalter only the rope: the harness and its trailer stay too)
                end
            else
                HorseLead.releaseRide(ride)
                table.remove(HorseLead.rides, i)
            end
            released = released + 1
        end
    end
    return released, haltered
end

-- Does this vehicle (a horse) wear the harness? (a work horse: the mount key does not take it, HorseDynamics hooks Player:requestToEnterVehicle)
function HorseLead.isHarnessed(vehicle)
    for _, ride in ipairs(HorseLead.rides) do
        if ride.harness and ride.vehicle == vehicle then
            return true
        end
    end
    return false
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

-- ===== the tack probe: what the horse model has for a bridle, to see whether a halter alone can be shown =====
-- The game shows the saddle and the bridle as ONE node (Rideable spec.equipmentNode, switched by setEquipmentVisibility together with spec.reinsNode, the reins, which it links to the rider's hands).
-- Whether that node has separate children (saddle, bridle) is in the model, not in the scripts: hdTack lists them and switches any node of the horse on or off by name.
local function nodeLine(node, depth, out)
    local visible = getVisibility ~= nil and getVisibility(node) or nil
    out[#out + 1] = string.format("%s%s%s", string.rep("  ", depth), getName(node), visible == nil and "" or (visible and "" or "  (hidden)"))
    if depth < 4 then
        for i = 0, getNumOfChildren(node) - 1 do
            nodeLine(getChildAt(node, i), depth + 1, out)
        end
    end
end

local function findNode(node, name)
    if getName(node) == name then
        return node
    end
    for i = 0, getNumOfChildren(node) - 1 do
        local found = findNode(getChildAt(node, i), name)
        if found ~= nil then
            return found
        end
    end
    return nil
end

-- hdTack [list | show | hide | <node name> on|off]: the nearest horse vehicle. Returns a message.
function HorseLead.tack(argument, state)
    local px, _, pz = playerPosition()
    local vehicle, best = nil, math.huge
    for _, candidate in ipairs(HorseLead.rideables()) do
        local x, _, z = getWorldTranslation(candidate.rootNode)
        local d = distance(x, z, px or x, pz or z)
        if d < best then
            vehicle, best = candidate, d
        end
    end
    if vehicle == nil then
        return "no horse vehicle: lead a horse first (the leash), it is one then"
    end
    local spec = vehicle.spec_rideable
    if argument == "show" or argument == "hide" then
        local ok, err = pcall(vehicle.setEquipmentVisibility, vehicle, argument == "show")
        return ok and ("equipment (saddle, bridle, reins) " .. (argument == "show" and "shown" or "hidden")) or ("failed: " .. tostring(err))
    elseif argument ~= nil and argument ~= "list" then
        local node = findNode(vehicle.rootNode, argument)
        if node == nil then
            return "no node called " .. argument .. " on this horse (hdTack list shows the tack nodes)"
        end
        pcall(setVisibility, node, state ~= "off")
        return string.format("%s %s", argument, state == "off" and "hidden" or "shown")
    end
    for _, key in ipairs({ "equipmentNode", "reinsNode", "leftReinNode" }) do
        local node = spec[key]
        if node == nil then
            say("tack: %s: none", key)
        else
            local lines = {}
            pcall(nodeLine, node, 0, lines)
            say("tack: %s:\n%s", key, table.concat(lines, "\n"))
        end
    end
    return "the tack nodes of the nearest horse are in the log"
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

-- How far the horse is that "start" would take: a loose horse vehicle or a horse of a pasture, whichever is nearer. nil when there is none.
-- The tools act on the horse you LOOK at, not on the nearest one: standing next to a log with a horse's rump behind it, the click went to the horse. The view ray of the camera passes within LOOK_RADIUS_M
-- of the middle of a horse's body (LOOK_HEIGHT_M above its root), at most `reach` metres along the ray. LOOK = false: the nearest horse, as before.
HorseLead.LOOK = true
HorseLead.LOOK_RADIUS_M = 1.1
HorseLead.LOOK_HEIGHT_M = 1.0

function HorseLead.viewRay()
    local player = g_localPlayer
    local camera = player ~= nil and player.getCurrentCameraNode ~= nil and player:getCurrentCameraNode() or nil
    if not HorseLead.LOOK or camera == nil then
        return nil
    end
    local ox, oy, oz = getWorldTranslation(camera)
    local dx, dy, dz = localDirectionToWorld(camera, 0, 0, -1)
    return { ox, oy, oz, dx, dy, dz }
end

-- How far along the ray a horse at (x, y, z) is, when the ray passes close enough to it: t, how far the ray misses its middle by; else nil.
function HorseLead.lookT(ray, x, y, z, reach)
    local vx, vy, vz = x - ray[1], y + HorseLead.LOOK_HEIGHT_M - ray[2], z - ray[3]
    local t = vx * ray[4] + vy * ray[5] + vz * ray[6]
    if t < 0 or t > reach then
        return nil
    end
    local qx, qy, qz = vx - ray[4] * t, vy - ray[5] * t, vz - ray[6] * t
    local miss = math.sqrt(qx * qx + qy * qy + qz * qz)
    if miss > HorseLead.LOOK_RADIUS_M then
        return nil
    end
    return t, miss
end

-- Several horses near each other: the one the ray points at, not the one that is nearest. A miss costs LOOK_MISS_WEIGHT metres of distance, so a horse dead ahead 3 m away beats one 1.5 m away that the ray
-- only grazes, while of two horses in a line the front one (the one you see) is the one.
HorseLead.LOOK_MISS_WEIGHT = 3
function HorseLead.lookScore(t, miss)
    return t + HorseLead.LOOK_MISS_WEIGHT * miss
end

-- The led horse the player looks at (see lookScore), within `reach`: ride, t. nil when none.
function HorseLead.lookedRide(ray, reach, filter)
    local best, bestScore, bestT = nil, math.huge, nil
    for _, ride in ipairs(HorseLead.rides) do
        if ride.vehicle ~= nil and ride.vehicle.rootNode ~= nil and (filter == nil or filter(ride)) then
            local x, y, z = getWorldTranslation(ride.vehicle.rootNode)
            local t, miss = HorseLead.lookT(ray, x, y, z, reach)
            if t ~= nil and HorseLead.lookScore(t, miss) < bestScore then
                best, bestScore, bestT = ride, HorseLead.lookScore(t, miss), t
            end
        end
    end
    return best, bestT
end

-- The led horse a tool acts on: the one looked at, or (LOOK off, or no camera) the nearest.
function HorseLead.pickRide(px, pz, reach, filter)
    local ray = HorseLead.viewRay()
    if ray ~= nil then
        return HorseLead.lookedRide(ray, reach, filter)
    end
    return HorseLead.nearestRide(px, pz, reach, filter)
end

function HorseLead.nearestHorseDistance(px, pz)
    local ray = HorseLead.viewRay()
    local best = math.huge
    if ray ~= nil then
        -- the horse looked at (a led one, a loose one, one of a pasture): how far along the ray it is; nil when there is none
        local bestScore = math.huge
        local function consider(x, y, z)
            local t, miss = HorseLead.lookT(ray, x, y, z, HorseLead.LEASH_REACH_M)
            if t ~= nil and HorseLead.lookScore(t, miss) < bestScore then
                bestScore, best = HorseLead.lookScore(t, miss), t
            end
        end
        for _, ride in ipairs(HorseLead.rides) do
            if ride.vehicle ~= nil and ride.vehicle.rootNode ~= nil then
                consider(getWorldTranslation(ride.vehicle.rootNode))
            end
        end
        for _, vehicle in ipairs(HorseLead.rideables()) do
            if not vehicle.isDeleted and vehicle.rootNode ~= nil then
                consider(getWorldTranslation(vehicle.rootNode))
            end
        end
        for _, entry in ipairs(HorseLead.husbandries()) do
            if entry.husbandry.animalTypeName == "HORSE" and entry.placeable.startRiding ~= nil then
                for _, item in ipairs(HorseLead.animals(entry)) do
                    consider(item.x, item.y or 0, item.z)
                end
            end
        end
        return best < math.huge and best or nil
    end
    local _, looseDistance = HorseLead.nearestLooseHorse(px, pz)
    if looseDistance ~= nil then
        best = looseDistance
    end
    for _, entry in ipairs(HorseLead.husbandries()) do
        if entry.husbandry.animalTypeName == "HORSE" and entry.placeable.startRiding ~= nil then
            for _, item in ipairs(HorseLead.animals(entry)) do
                best = math.min(best, distance(px, pz, item.x, item.z))
            end
        end
    end
    return best < math.huge and best or nil
end

-- Freezes the led horses: they stand completely still (see stepRide) until this is called again, or until no horse is led any more. Returns a message.
HorseLead.frozen = false
function HorseLead.toggleFreeze()
    HorseLead.frozen = not HorseLead.frozen
    if HorseLead.frozen and #HorseLead.rides == 0 then
        HorseLead.frozen = false
        return "no horse is led: nothing to freeze"
    end
    return HorseLead.frozen and "the led horses are frozen: they stand still (the same key lets them go on)" or "the led horses follow you again"
end

-- The led horse nearest to the player within `reach` metres: ride, distance. nil when there is none.
function HorseLead.nearestRide(px, pz, reach, filter)
    local best, bestDistance = nil, reach
    for _, ride in ipairs(HorseLead.rides) do
        if ride.vehicle ~= nil and ride.vehicle.rootNode ~= nil and (filter == nil or filter(ride)) then
            local x, _, z = getWorldTranslation(ride.vehicle.rootNode)
            local d = math.sqrt((x - px) ^ 2 + (z - pz) ^ 2)
            if d <= bestDistance then
                best, bestDistance = ride, d
            end
        end
    end
    return best, bestDistance
end

-- The harness tool, as a switch: the harness goes on the horse within reach, or comes off it when it has one. The halter and the harness are independent: a horse that is led on the leash (it wears the halter)
-- gets the harness on top, a horse that is not led is taken as a horse that STAYS (ride.stay: it is a vehicle so that it can wear things, it stands where it is, no halter, no rope) and wears only the harness.
-- Taking the harness off a horse that only stays gives it back to its pasture; a led horse stays led.
-- and harnessed. Taking the harness off leaves the horse on its leash (the leash tool lets it go). Returns a message.
function HorseLead.harness(gear)
    local px, _, pz = playerPosition()
    if px == nil then
        return "no player"
    end
    -- a trailer's joint in view and a harnessed horse near it: the click hitches (a hitched horse: unhitches), see HorseHitch
    local hitched = HorseHitch ~= nil and HorseHitch.click() or nil
    if hitched ~= nil then
        return hitched
    end
    local ride = HorseLead.pickRide(px, pz, HorseLead.LEASH_REACH_M)
    if ride == nil then
        local horseDistance = HorseLead.nearestHorseDistance(px, pz)
        if horseDistance ~= nil and horseDistance > HorseLead.LEASH_REACH_M then
            return string.format("no horse within %d m: walk up to one", HorseLead.LEASH_REACH_M)
        end
        if horseDistance == nil and HorseLead.viewRay() ~= nil then
            return string.format("look at the horse you mean (within %d m)", HorseLead.LEASH_REACH_M)
        end
        local before = #HorseLead.rides
        local message = HorseLead.command(nil, "start", true)
        ride = HorseLead.rides[#HorseLead.rides]
        if #HorseLead.rides <= before or ride == nil then
            return message
        end
        ride.stay = true
    end
    ride.harness = not ride.harness
    if ride.harness then
        ride.harnessGear = gear                              -- (rope or leather: the tool in the hand says)
        if ride.leash then
            return "harness on (the horse is on the leash: it wears the halter too, and follows you)"
        end
        return "harness on: the horse stands where it is, without a halter (the leash tool takes it along)"
    end
    if ride.stay and not ride.leash and not ride.carrot and not ride.halterOn then
        HorseLead.releaseRide(ride)
        for i = #HorseLead.rides, 1, -1 do
            if HorseLead.rides[i] == ride then
                table.remove(HorseLead.rides, i)
            end
        end
        return "harness off: the horse goes back to its pasture"
    end
    return "harness off"
end

HorseLead.playerPosition = playerPosition          -- (for HorseHitch: on foot the player, on a horse the horse)

-- Whether a click of the leash would go to the winch: no horse on the rope, none in reach, no gate nearer (the green ring of the winch shows only then).
function HorseLead.winchFree()
    if HorseLead.hasFlagged("leash") then
        return false
    end
    local px, _, pz = playerPosition()
    if px == nil then
        return false
    end
    local horseDistance = HorseLead.nearestHorseDistance(px, pz)
    if HorseGate ~= nil then
        local leaves, gateDistance = HorseGate.nearest(px, pz)
        if leaves ~= nil and (horseDistance == nil or gateDistance < horseDistance) then
            return false
        end
    end
    return horseDistance == nil or horseDistance > HorseLead.LEASH_REACH_M
end

-- The leash, as a switch: takes the nearest horse (a pasture horse, or one that stands loose), or lets the leashed ones go when there are some. Returns a message.
-- A fence gate in reach is for the gate: with horses on the rope the click opens or closes it instead of letting them go (walk on a few metres to let a horse go), and with no horse on the rope it does the
-- same when the gate is nearer than the horse the click would take (a horse right beside you still wins), so a gate can be dealt with without putting the tool away and finding its own trigger.
function HorseLead.leash(gear)
    -- an easter egg: the winch of FS25_WinchTow (published on g_currentMission.winchTow, mod globals are invisible between mods). A hooked vehicle is let go first (the same key); with no horse in reach
    -- the leash hooks the attacher joint you look at, a vehicle that then creeps after you at 2 km/h
    local winch = g_currentMission ~= nil and g_currentMission.winchTow or nil
    if winch ~= nil and winch.target ~= nil then
        return winch.toggle()
    end
    if HorseLead.hasFlagged("leash") then
        local gate = HorseLead.gateAtPlayer()
        if gate ~= nil then
            return gate
        end
        local released, haltered = HorseLead.releaseFlagged("leash")
        if haltered > 0 then
            return string.format("%d horse(s) let go: the halter stays on outside a pasture (the leash takes it again, in a pasture it comes off)", released)
        end
        return string.format("%d horse(s) let go", released)
    end
    local px, _, pz = playerPosition()
    if px ~= nil then
        -- a horse that stands there in its harness (ride.stay) within reach is the one the leash takes: the halter and the rope go on, it follows
        local staying = HorseLead.pickRide(px, pz, HorseLead.LEASH_REACH_M, function(r) return r.stay end)
        if staying ~= nil then
            staying.stay, staying.leash, staying.halterOn = nil, true, nil
            staying.halterGear = staying.halter ~= nil and staying.halterGear or gear      -- (a halter that is on keeps its gear)
            return "leashed: the horse wears the halter and follows you (it keeps the harness)"
        end
    end
    if HorseGate ~= nil and px ~= nil then
        local leaves, gateDistance = HorseGate.nearest(px, pz)
        if leaves ~= nil then
            local horseDistance = HorseLead.nearestHorseDistance(px, pz)
            if horseDistance == nil or gateDistance < horseDistance then
                return HorseGate.toggle(leaves)
            end
        end
    end
    if px ~= nil then
        local horseDistance = HorseLead.nearestHorseDistance(px, pz)
        if horseDistance == nil or horseDistance > HorseLead.LEASH_REACH_M then
            -- no horse in reach: a joint or a log in view is for the winch, else the leash says to walk up to a horse
            if winch ~= nil then
                local joint = winch.pick(true)
                local log, why = nil, nil
                if joint == nil and winch.pickLog ~= nil then
                    log, why = winch.pickLog()
                end
                if joint ~= nil or log ~= nil then
                    winch.hold(HorseLead.leashSource)
                    return winch.toggle()
                end
                if why ~= nil then
                    return why                                               -- (a log in view that cannot be hooked says why)
                end
            end
            if horseDistance ~= nil then
                return string.format("no horse within %d m: walk up to one (the carrot calls the whole pasture)", HorseLead.LEASH_REACH_M)
            end
        end
    end
    local before = #HorseLead.rides
    local message = HorseLead.command(nil, "start", true)
    local ride = HorseLead.rides[#HorseLead.rides]
    if #HorseLead.rides > before and ride ~= nil then
        ride.leash, ride.halterGear = true, gear
    end
    return message
end

function HorseLead.command(_, argument, look)
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
    -- the horse that is taken: with `look` (the tools) the one the player looks at (lookScore), else (the console) the nearest. A horse that is already a vehicle and stands about loose (left out in a
    -- savegame, ridden out earlier) competes with the horses of the pastures on the same terms.
    local ray = look and HorseLead.viewRay() or nil
    local function metric(x, y, z)
        if ray ~= nil then
            local t, miss = HorseLead.lookT(ray, x, y, z, HorseLead.LEASH_REACH_M)
            return t ~= nil and HorseLead.lookScore(t, miss) or nil, t
        end
        return distance(px, pz, x, z), distance(px, pz, x, z)
    end
    local loose, looseDistance, looseScore = nil, nil, math.huge
    for _, vehicle in ipairs(HorseLead.rideables()) do
        if not HorseLead.isClaimed(vehicle) and not vehicle.isDeleted and vehicle.rootNode ~= nil and not (vehicle.getIsControlled ~= nil and vehicle:getIsControlled()) and not (vehicle.getIsEntered ~= nil and vehicle:getIsEntered()) then
            local x, y, z = getWorldTranslation(vehicle.rootNode)
            local score, d = metric(x, y, z)
            if score ~= nil and score < looseScore then
                loose, looseDistance, looseScore = vehicle, d, score
            end
        end
    end
    local best, bestEntry, bestDistance, bestScore = nil, nil, math.huge, math.huge
    for _, entry in ipairs(HorseLead.husbandries()) do
        if entry.husbandry.animalTypeName == "HORSE" and entry.placeable.startRiding ~= nil then
            for _, item in ipairs(HorseLead.animals(entry)) do
                local score, d = metric(item.x, item.y or 0, item.z)
                if score ~= nil and score < bestScore then
                    best, bestEntry, bestDistance, bestScore = item, entry, d, score
                end
            end
        end
    end
    if loose ~= nil and looseScore < bestScore then
        HorseLead.claimVehicle(loose)
        local x, _, z = getWorldTranslation(loose.rootNode)
        HorseLead.rides[#HorseLead.rides + 1] = { vehicle = loose, known = {}, from = { x, z }, waited = 0, stableMs = 0 }
        say("ride: a loose horse vehicle %.0f m from you is taken over (%d in all)", looseDistance, #HorseLead.rides)
        return "a loose horse is following you now"
    end
    if best == nil then
        if ray ~= nil then
            return string.format("look at the horse you mean (within %d m)", HorseLead.LEASH_REACH_M)
        end
        return "no horse found (in a pasture, or standing loose)"
    end
    local ride, problem = HorseLead.startHorse(bestEntry, best, bestDistance)
    if ride == nil then
        return problem
    end
    return "the horse is being loaded as a vehicle, see the log"
end

-- The gait for the distance d, from the current one: up to the highest step whose distance d is beyond, down one step at a time once d is RIDE_GAIT_MARGIN_M inside the current step.
function HorseLead.rideGait(current, d, ladder, margin, topSpeeds)
    local gaits = Rideable.GAITTYPES
    local list = ladder or HorseLead.RIDE_GAITS
    -- the steps are by RANK: the gaits slowest first by the horse's own top speeds (its xml says walk 1.08, trot 2.5, canter 5.0, gallop 10 m/s: the game's enum puts canter before trot)
    local order = {}
    for _, step in ipairs(list) do
        if gaits[step[1]] ~= nil then
            order[#order + 1] = gaits[step[1]]
        end
    end
    if topSpeeds ~= nil then
        table.sort(order, function(a, b) return (topSpeeds[a] or 0) < (topSpeeds[b] or 0) end)
    end
    local steps = {}
    for _, step in ipairs(list) do
        if gaits[step[1]] ~= nil then
            steps[#steps + 1] = { gait = order[#steps + 1], from = step[2] }
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
    elseif level > 0 and d < steps[level].from - (margin or HorseLead.RIDE_GAIT_MARGIN_M) then
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
-- A led horse does not run into a wagon another horse pulls. The string of a pulling horse (HorseHitch: ride.hitch or ride.joined) is the segment from the horse to STRING_TAIL_M behind the wagon's origin; when the straight
-- way from the led horse to the player crosses it (or passes closer than STRING_CLEAR_M), the led horse aims at a point beside the pulling horse on ITS OWN side of the string instead, and goes along the wagon.
-- It did not: it aimed at the player through the wagon, bumped it, stood, and caught up at a gallop until it bumped again.
HorseLead.STRING_TAIL_M = 3
HorseLead.STRING_CLEAR_M = 2.2
HorseLead.STRING_PAST_M = 1                  -- (a horse that is not more than this far behind the pulling horse's origin is past the wagon)
HorseLead.STRING_SIDE_M = 3                   -- the point to aim at is this far to the side of the pulling horse

local function segmentDistance(ax, az, bx, bz, cx, cz, dx, dz)
    local function pointSegment(px, pz, sx, sz, ex, ez)
        local vx, vz = ex - sx, ez - sz
        local len2 = vx * vx + vz * vz
        local t = len2 > 0 and math.max(0, math.min(1, ((px - sx) * vx + (pz - sz) * vz) / len2)) or 0
        return distance(px, pz, sx + vx * t, sz + vz * t)
    end
    local d1x, d1z, d2x, d2z = bx - ax, bz - az, dx - cx, dz - cz
    local denominator = d1x * d2z - d1z * d2x
    if math.abs(denominator) > 1e-9 then
        local t = ((cx - ax) * d2z - (cz - az) * d2x) / denominator
        local u = ((cx - ax) * d1z - (cz - az) * d1x) / denominator
        if t >= 0 and t <= 1 and u >= 0 and u <= 1 then
            return 0
        end
    end
    return math.min(pointSegment(ax, az, cx, cz, dx, dz), pointSegment(bx, bz, cx, cz, dx, dz), pointSegment(cx, cz, ax, az, bx, bz), pointSegment(dx, dz, ax, az, bx, bz))
end

-- The point the led horse (at x, z) should aim at on its way to the player (px, pz): the player, or the side of a pulling horse. Returns the point and whether it is a way round.
function HorseLead.aimAround(ride, x, z, px, pz)
    for _, other in ipairs(HorseLead.rides) do
        local hitch = other ~= ride and (other.joined or other.hitch) or nil
        local wagon = hitch ~= nil and hitch.vehicle or nil
        if wagon ~= nil and not wagon.isDeleted and wagon.rootNode ~= nil and other.vehicle ~= nil and not other.vehicle.isDeleted and other.vehicle.rootNode ~= nil then
            local hx, _, hz = getWorldTranslation(other.vehicle.rootNode)
            local wx, _, wz = getWorldTranslation(wagon.rootNode)
            local length = distance(hx, hz, wx, wz)
            if length > 0.5 then
                local ux, uz = (wx - hx) / length, (wz - hz) / length
                local ex, ez = wx + ux * HorseLead.STRING_TAIL_M, wz + uz * HorseLead.STRING_TAIL_M
                local along = (x - hx) * ux + (z - hz) * uz                              -- (how far along the string the led horse is, from the pulling horse back to the wagon: level with the pulling horse or ahead of it there is nothing in the way)
                if along > HorseLead.STRING_PAST_M and segmentDistance(x, z, px, pz, hx, hz, ex, ez) < HorseLead.STRING_CLEAR_M then
                    local side = (ux * (z - hz) - uz * (x - hx)) >= 0 and 1 or -1       -- (+: the led horse is to the left of the string, looking from the pulling horse to the wagon)
                    return hx - uz * side * HorseLead.STRING_SIDE_M, hz + ux * side * HorseLead.STRING_SIDE_M, true
                end
            end
        end
    end
    return px, pz, false
end

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
        if ride.harness then
            -- a horse in its harness that somebody mounts is not given up: the player drives it (the game's own controls), the harness and what it pulls stay (until a proper wagon has a seat); only the
            -- halter and the lead rope go, the saddle has the reins
            if not ride.ridden then
                ride.ridden = true
                ride.leash, ride.stay, ride.carrot, ride.halterOn = nil, nil, nil, nil
                if HorseRope ~= nil then
                    HorseRope.remove(ride, true)
                end
                say("ride: the horse in its harness was mounted: you drive it, the harness and what it pulls stay on")
            end
            return false
        end
        say("ride: somebody mounted the horse: it is not led any more (the others keep following)")
        return true
    end
    if ride.ridden then
        -- the rider got off: the horse stands where it is, in its harness, with the virtual rider again
        ride.ridden = nil
        ride.stay = true
        HorseLead.claimVehicle(vehicle)
        say("ride: the rider got off: the horse stands in its harness")
    end
    if vehicle.isDeleted or spec == nil or px == nil then
        say("ride: the horse is gone (back in its pasture, or deleted)")
        return true
    end
    local x, _, z = getWorldTranslation(vehicle.rootNode)
    local d = distance(px, pz, x, z)
    -- a horse that stays (it wears the harness and nothing leads it): it stands where it is
    if ride.stay then
        spec.inputValues.currentGait = Rideable.GAITTYPES.STILL
        spec.inputValues.axisSteer = 0
        ride.backingMs, ride.backingOff, ride.markX, ride.stuckMs = 0, false, nil, 0
        return false
    end
    -- frozen: the led horses stand completely still, whatever the rest would do (no following, no backing away from you, no turning): to look at a harness, to walk round a horse
    if HorseLead.frozen then
        spec.inputValues.currentGait = Rideable.GAITTYPES.STILL
        spec.inputValues.axisSteer = 0
        ride.backingMs, ride.backingOff, ride.markX, ride.stuckMs = 0, false, nil, 0
        return false
    end
    -- at a stable with the player: given back (the game's own check then puts it into that stable, a different one from its own too, and deletes the vehicle). Only for the carrot's horses: a horse on
    -- the leash is held by the player until he lets go (walking it through a pasture's gate must not take it away from him).
    ride.stableMs = (ride.stableMs or 0) + dt
    if ride.stableMs >= HorseLead.RIDE_STABLE_CHECK_MS and not ride.leash then
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
    local aimX, aimZ, goingRound = HorseLead.aimAround(ride, x, z, px, pz)
    local diff = normalizeAngle(math.atan2(aimX - x, aimZ - z) - spec.currentTurnAngle)
    local mounted = playerVehicle() ~= nil
    local arriveM = mounted and HorseLead.RIDE_ARRIVE_MOUNTED_M or HorseLead.RIDE_ARRIVE_M
    local keepUpM = mounted and HorseLead.RIDE_KEEP_UP_MOUNTED_M or HorseLead.RIDE_KEEP_UP_M
    local leash = ride.leash == true
    if leash and not mounted then
        arriveM = HorseLead.RIDE_ARRIVE_LEASH_M
    elseif not mounted then
        ride.arriveExtra = ride.arriveExtra or HorseLead.random({ 0, HorseLead.RIDE_ARRIVE_SPREAD_M })
        arriveM = arriveM + ride.arriveExtra
    end
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
    -- walked into: a player who comes up to the horse (in front of it) makes it step back
    if not mounted then
        local inFront = math.abs(diff) < HorseLead.RIDE_BACKOFF_CONE
        if inFront and (d < HorseLead.RIDE_BACKOFF_M or (ride.backingOff and d < HorseLead.RIDE_BACKOFF_END_M)) then
            ride.backingOff = true
            spec.inputValues.currentGait = gaits.BACKWARDS or gaits.STILL
            HorseLead.easeSteer(spec, 0, dt)
            ride.markX, ride.stuckMs = nil, 0
            return false
        end
        ride.backingOff = false
    end
    -- the phase: following for a burst, then standing a while
    if ride.phase == nil then
        ride.phase, ride.phaseMs = "follow", HorseLead.random(HorseLead.RIDE_BURST_MS)
    end
    if leash then
        ride.phase, ride.phaseMs = "follow", math.huge          -- (a rope does not let a horse stop and wander: no bursts and pauses on the leash)
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
    local resumeM = arriveM + (leash and HorseLead.RIDE_LEASH_RESUME_M or 0)
    if ride.phase == "pause" or d < arriveM or (gait == gaits.STILL and d < resumeM) then
        gait = gaits.STILL
    else
        gait = HorseLead.rideGait(gait, d, leash and HorseLead.RIDE_GAITS_LEASH or nil, leash and HorseLead.RIDE_GAIT_MARGIN_LEASH_M or nil, spec.topSpeeds)
        if goingRound and gait == gaits.GALLOP then
            gait = gaits.TROT                                  -- (no gallop along a wagon: that is how it bumped into it)
        end
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
-- Where the rope of a rider who leads another horse starts: at the SIDE of the horse he sits on, at hand height by the saddle (y 1.15 was at his boot) (x: sideways in the horse's own space, + is its left, flip the sign for the other side; y: up;
-- z: forward). It started on the horse's back, in the middle, and looked as if it came out of the rider's seat.
HorseLead.MOUNTED_ANCHOR = { 0.36, 1.5, 0.30 }

-- The hand of the rider: the node the game links the horse's reins to (Rideable:onVehicleCharacterChanged: vehicle:getVehicleCharacter().playerModel.thirdPersonRightHandNode / LeftHandNode). The lead
-- rope starts there while the player rides; nil when the character is not loaded or has no such node (then the anchor at the horse's side above is used). The right hand first: the left is for the reins.
HorseLead.RIDER_HANDS = { "thirdPersonRightHandNode", "thirdPersonLeftHandNode" }

function HorseLead.riderHand(vehicle)
    if vehicle == nil or vehicle.getVehicleCharacter == nil then
        return nil
    end
    local ok, character = pcall(vehicle.getVehicleCharacter, vehicle)
    local model = ok and character ~= nil and character.playerModel or nil
    if model == nil then
        return nil
    end
    for _, name in ipairs(HorseLead.RIDER_HANDS) do
        local node = model[name]
        if node ~= nil and (entityExists == nil or entityExists(node)) then
            return node
        end
    end
    return nil
end

-- The hand of the player on foot, in the camera view where the character is seen (third person): the node the game links a hand tool to (HandTool:attachToolToHand: playerModel.thirdPersonRightHandNode, the left
-- one for a tool used with the left). nil in first person (the character is hidden there, the leash in the hand is attached to the camera) or when the model is not loaded.
HorseLead.PLAYER_HANDS = { "thirdPersonRightHandNode", "thirdPersonLeftHandNode" }
function HorseLead.playerHand()
    local player = g_localPlayer
    local model = player ~= nil and player.graphicsComponent ~= nil and player.graphicsComponent.model or nil
    if model == nil or (player.camera ~= nil and player.camera.isFirstPerson) then
        return nil
    end
    for _, name in ipairs(HorseLead.PLAYER_HANDS) do
        local node = model[name]
        if node ~= nil and (entityExists == nil or entityExists(node)) then
            return node
        end
    end
    return nil
end

function HorseLead.ropeSource()
    if HorseLead.leashSource ~= nil then
        return HorseLead.leashSource
    end
    if HorseRope == nil or g_localPlayer == nil then
        return nil
    end
    local vehicle = playerVehicle()
    if vehicle ~= nil then
        local hand = HorseLead.riderHand(vehicle)
        if hand ~= nil then
            return hand
        end
        local a = HorseLead.MOUNTED_ANCHOR
        return HorseRope.anchorOn(vehicle.rootNode, a[1], a[2], a[3])
    end
    local hand = HorseLead.playerHand()
    if hand ~= nil then
        return hand                                          -- (on foot, seen in third person: the rope starts in the hand, not 1.1 m above the capsule's foot)
    end
    return HorseRope.anchorOn(g_localPlayer.rootNode, 0, 1.1, 0)
end

function HorseLead.updateRide(dt)
    HorseLead.watchRidden(dt)
    if #HorseLead.rides == 0 then
        HorseLead.frozen = false                    -- (a horse led later is not born frozen)
    end
    if HorseRope ~= nil then
        -- the leash in the hand shows a short end of rope while no horse is on it (the tool itself has no model)
        local led = false
        for _, ride in ipairs(HorseLead.rides) do
            led = led or (ride.leash and ride.vehicle ~= nil)
        end
        HorseRope.syncStub(not led and HorseLead.leashSource or nil)
        HorseRope.syncCollar(HorseLead.harnessSource, HorseLead.harnessSourceGear)             -- (the harness tool in the hand shows a collar)
    end
    if HorseHitch ~= nil then
        HorseHitch.updatePlayer()                                              -- (the player is slowed by what the horses pull)
        HorseHitch.updateSaddle()                                              -- (the attach key on the horse you ride in its harness)
    end
    for i = #HorseLead.rides, 1, -1 do
        local ride = HorseLead.rides[i]
        if HorseLead.stepRide(ride, dt) then
            if HorseRope ~= nil then
                HorseRope.remove(ride)
            end
            table.remove(HorseLead.rides, i)
        else
            -- (only for a ride that is still there: syncing the harness of a ride that was just dropped, a horse somebody mounted, built a new harness for it that nothing ever updated or deleted again:
            -- a mass of orphaned ropes stretching across the yard)
            if HorseRope ~= nil and ride.leash and ride.vehicle ~= nil then
                HorseRope.sync(ride, HorseLead.ropeSource())
            elseif HorseRope ~= nil and ride.halterOn and ride.vehicle ~= nil then
                HorseRope.halterSync(ride)                                  -- (let go outside a pasture: the halter stays on, no rope)
            end
            if HorseHarness ~= nil and ride.vehicle ~= nil then
                HorseHarness.sync(ride)
            end
            if HorseHitch ~= nil and ride.joined ~= nil then
                HorseHitch.keepJoined(ride)                                 -- (the brake of what hangs on the horse's real joint)
            end
            if HorseHitch ~= nil and ride.hitch ~= nil then
                HorseHitch.update(ride, dt)
                -- a horse that pulls does not gallop, and walks with a heavy load (the player is slowed to match: HorseHitch.updatePlayer)
                local spec = ride.vehicle.spec_rideable
                if ride.hitch ~= nil and spec ~= nil and spec.inputValues ~= nil then
                    spec.inputValues.currentGait = HorseHitch.limitGait(ride, spec.inputValues.currentGait)
                end
            end
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
