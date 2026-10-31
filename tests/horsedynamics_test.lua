-- plain Lua with a fake engine: leading horses (a pasture horse becomes a vehicle with a virtual rider), the gaits, bursts and pauses, giving up, taking over a loose horse, giving them back at a stable, the keys
local passed, failed = 0, 0
local realPrint = print
local function check(name, ok) if ok then passed = passed + 1 else failed = failed + 1; realPrint("  FAIL " .. name) end end
local log = {}
print = function(text) log[#log + 1] = text end

g_currentModDirectory = "mods/FS25_HorseDynamics/"
local commands, listeners = {}, {}
addConsoleCommand = function(name, _, method, target) commands[name] = function(...) return target[method](target, ...) end end
addModEventListener = function(l) listeners[#listeners + 1] = l end
getUserProfileAppPath = function() return "profile/" end
createFolder = function() end
local saved = {}
XMLFile = {
    loadIfExists = function(_, path) if saved[path] == nil then return nil end local v = saved[path]; return { getBool = function() return v end, delete = function() end } end,
    create = function(_, path) local self = {}; function self:setBool(_, v) saved[path] = v end function self:save() end function self:delete() end return self end,
}
Utils = { overwrittenFunction = function(old, new) return function(self, ...) return new(self, old, ...) end end,
    getFilename = function(name) return (name:gsub("^%$data", "C:/Game/data")) end }
local created = {}
AnimalClusterHusbandry = { create = function(self, xmlFilename) created[#created + 1] = { type = self.animalTypeName, xml = xmlFilename }; return 7 end }

-- the world: one pasture with three horses
local nodes = { [101] = { name = "horse_a", pos = { 10, 0, 10 }, children = { 201, 202 } }, [102] = { name = "horse_b", pos = { 40, 0, 10 }, children = {} }, [103] = { name = "horse_c", pos = { 12, 0, 30 }, children = {} },
    [201] = { name = "skeleton", pos = { 0, 0, 0 }, children = { 301 } }, [202] = { name = "body", pos = { 0, 0, 0 }, children = {}, shape = true }, [301] = { name = "head", pos = { 0, 0, 0 }, children = {} }, [900] = { pos = { 12, 0, 12 } } }
local animals = { [1] = { 101, 0 }, [2] = { 102, 1 }, [3] = { 103, 0 } }
local engineKeepsNode = false          -- when true the "engine" puts a moved animal back
local engineHome = {}
g_localPlayer = { rootNode = 900 }
getWorldTranslation = function(node) local p = nodes[node].pos; return p[1], p[2], p[3] end
setWorldTranslation = function(node, x, y, z) nodes[node].pos = { x, y, z } end
getName = function(node) return nodes[node].name end
getNumOfChildren = function(node) return #nodes[node].children end
getChildAt = function(node, i) return nodes[node].children[i + 1] end
ClassIds = { SHAPE = 1 }
getHasClassId = function(node) return nodes[node].shape == true end
isHusbandryReady = function() return true end
getAnimalRootNode = function(husbandryId, animalId) return animals[animalId][1] end
getAnimalPosition = function(husbandryId, animalId) local p = nodes[animals[animalId][1]].pos; return p[1], p[2], p[3] end
getAnimalRotation = function() return 0, 1.5, 0 end
-- engine functions that have to do with animals, as the scan will find them
getNumAnimals = function() end
setHusbandryAnimalTarget = function() end
AnimalSystem = {}
notRelated = function() end

local husbandry = { husbandryId = 7, animalTypeName = "HORSE", animalIdToCluster = { [1] = {}, [2] = {}, [3] = {} }, animalIdToVisualAnimalIndex = { [1] = 1, [2] = 2, [3] = 1 } }
g_currentMission = { husbandrySystem = { placeables = { { getName = function() return "Pasture" end, spec_husbandryAnimals = { clusterHusbandry = husbandry, animalType = { name = "HORSE", configFilename = "$dataS/horse/animals.xml" } } }, { spec_other = {} } } } }

dofile("scripts/HorseLead.lua")
dofile("scripts/HorseDynamics.lua")
local L = HorseLead
check("loaded: the console command and an update listener", commands.hdLead ~= nil and #listeners == 1)

-- the virtual rider
L.random = function(range) return range[1] end                       -- (deterministic: the shortest burst / pause)
Rideable = { GAITTYPES = { BACKWARDS = 0, STILL = 1, WALK = 2, CANTER = 3, TROT = 4, GALLOP = 5 } }
g_currentMission.husbandrySystem.placeables[1].startRiding = function() end
check("alRide without a cluster id: says so", commands.hdLead("start"):find("no id", 1, true) ~= nil)
husbandry.animalIdToCluster[1].id = 11
husbandry.animalIdToCluster[3].id = 13
local pasture = g_currentMission.husbandrySystem.placeables[1]
local startCalls, vehicles = {}, {}
g_currentMission.vehicleSystem = { vehicles = vehicles }
pasture.startRiding = nil
check("alRide on a pasture without startRiding: no horse found", commands.hdLead("start") == "no horse found (in a pasture, or standing loose)")
pasture.startRiding = function(self, clusterId, player)
    startCalls[#startCalls + 1] = { clusterId, player }
    nodes[500] = { pos = { 10, 0, 10 }, children = {} }                 -- the horse as a vehicle appears where the animal stood
    vehicles[#vehicles + 1] = { rootNode = 500, spec_rideable = { currentTurnAngle = 0, inputValues = { axisSteer = 0, currentGait = 1 }, doHusbandryCheck = 0 } }
end
log = {}
check("alRide start: the game's startRiding is called with the cluster id of the nearest horse and no player", commands.hdLead("start"):find("loaded", 1, true) ~= nil and startCalls[1][1] == 11 and startCalls[1][2] == nil and #L.rides == 1)
check("a second start while the first horse is still loading is refused (try again in a moment)", commands.hdLead("start"):find("still being loaded", 1, true) ~= nil)
L.updateRide(50)
local horse = vehicles[1]
check("the new vehicle is found and claimed as controlled", L.rides[1].vehicle == horse and horse.rfVirtualRider == true)
-- the player is at (12, 12): from (10, 10) that is 2.8 m away: arrived, still
L.updateRide(50)
check("closer than the arrive distance: standing still, no steering", horse.spec_rideable.inputValues.currentGait == Rideable.GAITTYPES.STILL and horse.spec_rideable.inputValues.axisSteer == 0)
nodes[900].pos = { 10, 0, 40 }                                          -- the player is 30 m ahead (+z): heading 0, straight on
L.updateRide(50)
check("far away and straight ahead: trot, no steering", horse.spec_rideable.inputValues.currentGait == Rideable.GAITTYPES.TROT and horse.spec_rideable.inputValues.axisSteer == 0)
nodes[900].pos = { 40, 0, 10 }                                          -- 30 m to the side (+x): heading pi/2, to the left of angle 0: steer positive
L.updateRide(50)
local turned = horse.spec_rideable.currentTurnAngle
check("the player to the side: the heading itself turns towards them at the turn rate (7 rad/s: 0.35 rad in one 50 ms frame), the steer stays zero", math.abs(turned - 0.35) < 1e-6 and horse.spec_rideable.inputValues.axisSteer == 0)
for _ = 1, 20 do L.updateRide(50) end
check("... and faces them within a fraction of a second, without overshooting (pi/2)", math.abs(horse.spec_rideable.currentTurnAngle - math.pi / 2) < 1e-6 and horse.spec_rideable.inputValues.axisSteer == 0)
nodes[900].pos = { 10, 0, -30 }                                         -- now 40 m behind it: it turns round, at most the turn rate per frame
local before = horse.spec_rideable.currentTurnAngle
L.updateRide(50)
check("a player behind: still at most the turn rate per frame (no snapping through half a circle in one frame)", math.abs(horse.spec_rideable.currentTurnAngle - before) <= 0.35 + 1e-6 and horse.spec_rideable.currentTurnAngle ~= before)
horse.spec_rideable.currentTurnAngle = math.pi / 2
nodes[900].pos = { 10, 0, 18 }                                          -- 8 m ahead
for _ = 1, 5 do L.updateRide(50) end                                     -- (one gait down per frame, from the trot of 30 m)
check("8 m away: walk", horse.spec_rideable.inputValues.currentGait == Rideable.GAITTYPES.WALK)
nodes[900].pos = { 10, 0, 14 }                                          -- 4 m: still walking (hysteresis), then stops under the arrive distance
L.updateRide(50)
check("between arrive and walk distance it keeps walking", horse.spec_rideable.inputValues.currentGait == Rideable.GAITTYPES.WALK)
-- standing: it turns to face the player in place; riding: it comes closer
L.rides[1].phase, L.rides[1].phaseMs = "follow", 100000
horse.spec_rideable.currentTurnAngle = math.pi / 2                       -- facing +x
nodes[900].pos = { 10, 0, 12.6 }                                         -- 2.6 m away, straight on (+z): arrived, and it is standing
local standX, standZ = getWorldTranslation(horse.rootNode)
L.updateRide(50)
check("arrived and standing: it still turns to face the player, in place (3.5 rad/s: 0.175 rad a frame), the steer zero", horse.spec_rideable.inputValues.currentGait == Rideable.GAITTYPES.STILL
    and math.abs(horse.spec_rideable.currentTurnAngle - (math.pi / 2 - 0.175)) < 1e-6 and horse.spec_rideable.inputValues.axisSteer == 0 and getWorldTranslation(horse.rootNode) == standX)
for _ = 1, 20 do L.updateRide(50) end
check("... until it faces him", math.abs(horse.spec_rideable.currentTurnAngle) < 1e-6)
horse.spec_rideable.currentTurnAngle = math.pi / 2
nodes[900].pos = { 10, 0, 11.5 }                                         -- 1.5 m: too close to bother turning
L.updateRide(50)
check("a player right next to it: no turning around him", horse.spec_rideable.currentTurnAngle == math.pi / 2)
nodes[900].pos = { 10, 0, 12.6 }
g_localPlayer.getCurrentVehicle = function() return { rootNode = 900 } end
L.updateRide(50)
check("the player rides: 2.6 m behind the ridden horse is not close enough yet, the follower walks on (on foot it would stand)", horse.spec_rideable.inputValues.currentGait == Rideable.GAITTYPES.WALK)
nodes[900].pos = { 10, 0, 12.2 }
L.updateRide(50)
check("... and it stops at 2.2 m, closer than on foot", horse.spec_rideable.inputValues.currentGait == Rideable.GAITTYPES.STILL)
g_localPlayer.getCurrentVehicle = nil
horse.spec_rideable.currentTurnAngle = math.pi / 2
nodes[900].pos = { 10, 0, 18 }
-- follow in bursts: it follows for a while, then stands, then follows again
nodes[900].pos = { 10, 0, 22 }                                          -- 12 m: inside the keep-up distance, so it may pause
horse.spec_rideable.inputValues.axisSteer = 0
L.rides[1].phase, L.rides[1].phaseMs = "follow", 300
for _ = 1, 8 do L.updateRide(50) end
check("after its burst the horse stands (gait still, steering eased back to zero)", L.rides[1].phase == "pause" and horse.spec_rideable.inputValues.currentGait == Rideable.GAITTYPES.STILL)
for _ = 1, 40 do L.updateRide(50) end
check("... and after the pause it follows again", L.rides[1].phase == "follow" and horse.spec_rideable.inputValues.currentGait == Rideable.GAITTYPES.WALK)
L.rides[1].phase, L.rides[1].phaseMs = "pause", 100000
nodes[900].pos = { 10, 0, 40 }                                          -- the player walks off (30 m): no standing about
L.updateRide(50)
check("a pause is cut short when the player gets far away (it keeps up)", L.rides[1].phase == "follow" and horse.spec_rideable.inputValues.currentGait == Rideable.GAITTYPES.TROT)
L.rides[1].phase, L.rides[1].phaseMs = "follow", 1
L.updateRide(50)
check("while trotting after the player (far away) it does not pause", L.rides[1].phase == "follow")
nodes[900].pos = { 10, 0, 14 }
horse.spec_rideable.inputValues.currentGait = Rideable.GAITTYPES.WALK
-- the gait steps up with the distance and down again with a margin
local G = Rideable.GAITTYPES
check("gait by distance from standing: walk, canter, trot, gallop", L.rideGait(G.STILL, 8) == G.WALK and L.rideGait(G.STILL, 15) == G.CANTER and L.rideGait(G.STILL, 30) == G.TROT and L.rideGait(G.STILL, 60) == G.GALLOP)
check("closing in from a gallop: it holds the gait until 3 m inside the step, then drops one gait at a time", L.rideGait(G.GALLOP, 44) == G.GALLOP and L.rideGait(G.GALLOP, 41) == G.TROT
    and L.rideGait(G.TROT, 18) == G.TROT and L.rideGait(G.TROT, 16) == G.CANTER and L.rideGait(G.CANTER, 10) == G.CANTER and L.rideGait(G.CANTER, 8) == G.WALK and L.rideGait(G.WALK, 4) == G.WALK)
check("a gait the game does not have is left out of the steps", (function()
    local canter = Rideable.GAITTYPES.CANTER
    Rideable.GAITTYPES.CANTER = nil
    local g = L.rideGait(G.STILL, 15)
    Rideable.GAITTYPES.CANTER = canter
    return g == G.WALK
end)())
check("alRide stop: the virtual rider is off, steering and gait reset, the stable check is asked for", (function()
    local r = commands.hdLead("stop")
    return r == "stopped 1 horse(s)" and horse.rfVirtualRider == nil and horse.spec_rideable.inputValues.currentGait == Rideable.GAITTYPES.STILL and horse.spec_rideable.doHusbandryCheck == 2000 and #L.rides == 0
end)())
nodes[900].pos = { 12, 0, 12 }
vehicles[#vehicles + 1] = nil
-- no vehicle appears: gives up after the wait
pasture.startRiding = function() end
commands.hdLead("start")
for _ = 1, 120 do L.updateRide(50) end
check("no vehicle appears: it gives up and says so", #L.rides == 0 and log[#log]:find("no new rideable vehicle", 1, true) ~= nil)
check("alRide bad argument", commands.hdLead("gallop"):find("usage", 1, true) ~= nil)

-- several horses, and giving them back at a stable
pasture.startRiding = function(self, clusterId)
    local node = 600 + clusterId
    nodes[node] = { pos = { nodes[900].pos[1] + 2, 0, nodes[900].pos[3] + 2 }, children = {} }
    vehicles[#vehicles + 1] = { rootNode = node, spec_rideable = { currentTurnAngle = 0, inputValues = { axisSteer = 0, currentGait = 1 }, doHusbandryCheck = 0 }, clusterId = clusterId }
end
nodes[101].pos, nodes[102].pos, nodes[103].pos = { 10, 0, 10 }, { 40, 0, 10 }, { 12, 0, 30 }
nodes[900].pos = { 12, 0, 12 }
local firstRides = #L.rides
commands.hdLead("start")
L.updateRide(50)
local nearest = vehicles[#vehicles]
check("start adds a horse: it is found and claimed", #L.rides == 1 and L.rides[1].vehicle == nearest)
husbandry.animalIdToCluster[3].id = 13
husbandry.animalIdToCluster[2].id = 12
commands.hdLead("start")
L.updateRide(50)
check("start again adds another horse to the string (two following)", #L.rides == 2 and L.rides[2].vehicle ~= nil and L.rides[2].vehicle ~= L.rides[1].vehicle and commands.hdLead("status"):find("2 horse(s) following", 1, true) ~= nil)
-- a stable in range with the player near: given back
local inRange, stable = false, {}
g_currentMission.husbandrySystem.getHusbandryInRideableRange = function(_, vehicle) return inRange, inRange and stable or nil end
log = {}
for _ = 1, 30 do L.updateRide(50) end
check("not at a stable: both keep following", #L.rides == 2)
inRange = true
for _ = 1, 30 do L.updateRide(50) end
check("at a stable with the player close: both are given back (the game's own check is asked for) and the list is empty", #L.rides == 0 and nearest.rfVirtualRider == nil and nearest.spec_rideable.doHusbandryCheck == 2000 and (log[#log]):find("given back", 1, true) ~= nil)
-- a pasture horse starts inside its own stable's range: not handed back until it has been out of range once
inRange = true
commands.hdLead("start")
L.updateRide(50)
nodes[900].pos = { 12, 0, 12 }
for _ = 1, 60 do L.updateRide(50) end
check("a horse that starts inside a stable's range (its own pasture) is NOT handed back at once, however long it stays", #L.rides == 1)
inRange = false
for _ = 1, 30 do L.updateRide(50) end
check("... it is out of range now (it has left): still led", #L.rides == 1 and L.rides[1].leftStable == true)
inRange = true
for _ = 1, 30 do L.updateRide(50) end
check("... and when it comes into a stable's range again with the player close, it is handed back", #L.rides == 0)
nodes[900].pos = { 12, 0, 12 }
-- a stable far from the player: the horse is only passing
commands.hdLead("start")
L.updateRide(50)
nodes[900].pos = { 300, 0, 300 }
for _ = 1, 40 do L.updateRide(50) end
check("a horse at a stable while the player is far away is not given back", #L.rides == 1)
commands.hdLead("stop")
check("stop with nothing led says so", commands.hdLead("stop") == "no horse is being steered")
g_currentMission.husbandrySystem.getHusbandryInRideableRange = nil
nodes[900].pos = { 12, 0, 12 }

-- stuck: told to move, not moving
nodes[900].pos = { 12, 0, 12 }
commands.hdLead("start")
L.updateRide(50)
nodes[900].pos = { 12, 0, 40 }                                        -- the player walks off: the horse is told to follow
local blocked = L.rides[#L.rides]
check("a fresh horse is led", blocked ~= nil and blocked.vehicle ~= nil)
local gaveUp, backed = false, 0
log = {}
for _ = 1, 600 do                                                    -- the horse never moves (the fake never moves it): it backs up twice, then is given up on
    L.updateRide(50)
    if #L.rides == 0 then gaveUp = true break end
end
for _, line in ipairs(log) do if line:find("backing up and turning", 1, true) then backed = backed + 1 end end
check("a horse that is told to move but does not (a fence, a sprayer): it backs up and turns twice first", backed == 2 and blocked.vehicle.spec_rideable.inputValues.currentGait ~= nil)
check("... and is then released, not led for ever", gaveUp and blocked.vehicle.rfVirtualRider == nil and blocked.vehicle.spec_rideable.doHusbandryCheck == 2000)
nodes[900].pos = { 12, 0, 12 }
-- a loose horse vehicle (a savegame left it out): taken over when it is the nearest
local stray = { rootNode = 700, spec_rideable = { currentTurnAngle = 0, inputValues = { axisSteer = 0, currentGait = 1 }, doHusbandryCheck = 0 }, getIsEntered = function() return false end, getIsControlled = function() return false end }
nodes[700] = { pos = { 13, 0, 13 }, children = {} }
vehicles[#vehicles + 1] = stray
for _, v in ipairs(vehicles) do v.isDeleted = true end
stray.isDeleted = nil
local r = commands.hdLead("start")
check("a loose horse vehicle nearer than any pasture horse is taken over (no waiting: it is a vehicle already)", r:find("loose horse", 1, true) ~= nil and #L.rides == 1 and L.rides[1].vehicle == stray and stray.rfVirtualRider == true)
commands.hdLead("stop")
stray.getIsEntered = function() return true end
vehicles[#vehicles + 1] = nil
check("a horse somebody rides is not taken", select(1, L.nearestLooseHorse(12, 12)) ~= stray)
nodes[700] = nil


-- the keys and the entry point
local registered = {}
InputAction = { HORSEDYN_CALL = 1, HORSEDYN_RELEASE = 2 }
GS_PRIO_LOW = 0
g_inputBinding = { registerActionEvent = function(_, action, target, method) registered[action] = method; return true, action end, setActionEventTextPriority = function() end, setActionEventTextVisibility = function() end }
HorseDynamics.registerActionEvents()
check("both keys are registered", registered[1] ~= nil and registered[2] ~= nil)
check("the call key leads a horse (or says why not), the release key gives them back", (function()
    local before = #L.rides
    HorseDynamics.onCall()
    HorseDynamics.onRelease()
    return #L.rides == 0
end)())
check("the update listener drives the horses", (function() listeners[1].update(listeners[1], 50) return true end)())

-- the carrot (every horse of the pasture the player is in) and the leash (the nearest one, toggled)
HorseLead.rides = {}
local pastureSpec = g_currentMission.husbandrySystem.placeables[1].spec_husbandryAnimals
pastureSpec.outdoorContourPolygon = { getIsPosInside = function(_, x, z) return x >= 0 and x <= 60 and z >= 0 and z <= 60 end }
local started = {}
local pasture3 = g_currentMission.husbandrySystem.placeables[1]
pasture3.startRiding = function(self, clusterId)
    started[#started + 1] = clusterId
    local node = 800 + clusterId
    local home = nodes[({ [11] = 101, [12] = 102, [13] = 103 })[clusterId]].pos
    nodes[node] = { pos = { home[1], 0, home[3] }, children = {} }
    vehicles[#vehicles + 1] = { rootNode = node, spec_rideable = { currentTurnAngle = 0, inputValues = { axisSteer = 0, currentGait = 1 }, doHusbandryCheck = 0 } }
end
local realisticStart = pasture3.startRiding
for _, v in ipairs(vehicles) do v.isDeleted = true end
nodes[900].pos = { 30, 0, 30 }                                           -- the player stands inside the pasture polygon
husbandry.animalIdToCluster[1].id, husbandry.animalIdToCluster[2].id, husbandry.animalIdToCluster[3].id = 11, 12, 13
check("the pasture of the player is found by its outline polygon", HorseLead.pastureOfPlayer(30, 30) ~= nil)
nodes[900].pos = { 500, 0, 500 }
check("far from every pasture there is none (and no loose horse near)", HorseLead.pastureOfPlayer(500, 500) == nil and HorseLead.callPasture() == "no horse pasture here, and no loose horse near")
nodes[900].pos = { 30, 0, 30 }
for _, v in ipairs(vehicles) do v.isDeleted = true end                    -- (the loose horses of the earlier tests are gone)
local msg = HorseLead.callPasture()
check("the carrot: startRiding for every horse of the pasture (three), all pending at once", msg == "3 horse(s) come" and #started == 3 and #HorseLead.rides == 3)
for _ = 1, 3 do L.updateRide(50) end
local claimed = {}
for _, ride in ipairs(HorseLead.rides) do if ride.vehicle ~= nil then claimed[ride.vehicle] = true end end
local distinct = 0
for _ in pairs(claimed) do distinct = distinct + 1 end
check("every horse claims a vehicle of its own (none twice)", distinct == 3)
check("the carrot is a switch: the horses it called are flagged", HorseLead.hasFlagged("carrot"))
check("used again it lets all of them go (no second call of the pasture)", HorseLead.carrot() == "3 horse(s) let go" and #HorseLead.rides == 0 and #started == 3)
check("a third use calls the pasture again (and takes the loose horses the second use left standing)", HorseLead.carrot():find("horse(s) come", 1, true) ~= nil and #HorseLead.rides >= 3)
HorseLead.command(nil, "stop")
-- the leash toggles the nearest horse
for _, v in ipairs(vehicles) do v.isDeleted = true end
nodes[900].pos = { 12, 0, 12 }
local leashMessage = HorseLead.leash()
L.updateRide(50)
check("the leash takes the nearest horse and marks the ride", #HorseLead.rides == 1 and HorseLead.rides[1].leash == true)
check("used again it lets the leashed horse go", HorseLead.leash() == "1 horse(s) let go" and #HorseLead.rides == 0)

-- the carrot also gathers loose horse vehicles near the player
for _, v in ipairs(vehicles) do v.isDeleted = true end
L.rides = {}
nodes[900].pos = { 30, 0, 30 }
nodes[720] = { pos = { 40, 0, 30 }, children = {} }
nodes[721] = { pos = { 400, 0, 400 }, children = {} }
local looseNear = { rootNode = 720, spec_rideable = { currentTurnAngle = 0, inputValues = { axisSteer = 0, currentGait = 1 }, doHusbandryCheck = 0 } }
local looseFar = { rootNode = 721, spec_rideable = { currentTurnAngle = 0, inputValues = { axisSteer = 0, currentGait = 1 }, doHusbandryCheck = 0 } }
vehicles[#vehicles + 1] = looseNear
vehicles[#vehicles + 1] = looseFar
pasture3.startRiding = function() end
husbandry.animalIdToCluster[1].id = 11
local gathered = HorseLead.carrot()
check("the carrot also takes the loose horse near you (not the one 400 m away): the herd is gathered", looseNear.rfVirtualRider == true and looseFar.rfVirtualRider == nil and #HorseLead.rides >= 1)
HorseLead.command(nil, "stop")
nodes[720], nodes[721] = nil, nil
looseNear.isDeleted, looseFar.isDeleted = true, true

-- a vehicle that appears further away than 10 m from where the horse stood is found after a moment (the nearest new one)
for _, v in ipairs(vehicles) do v.isDeleted = true end
L.rides = {}
nodes[900].pos = { 12, 0, 12 }
pasture3.startRiding = function(self, clusterId)
    nodes[730] = { pos = { 40, 0, 10 }, children = {} }                      -- 30 m from where the horse (cluster 11, at 10 10) stood
    vehicles[#vehicles + 1] = { rootNode = 730, spec_rideable = { currentTurnAngle = 0, inputValues = { axisSteer = 0, currentGait = 1 }, doHusbandryCheck = 0 } }
end
husbandry.animalIdToCluster[1].id = 11
commands.hdLead("start")
for _ = 1, 10 do L.updateRide(50) end                                        -- 0.5 s: not yet (only vehicles within 10 m count at first)
check("a vehicle 30 m from where the horse stood is not taken at once", L.rides[1] ~= nil and L.rides[1].vehicle == nil)
for _ = 1, 40 do L.updateRide(50) end                                        -- past the fallback time
check("... but after the fallback time the nearest new vehicle is taken, so the horse is not lost", L.rides[1] ~= nil and L.rides[1].vehicle ~= nil and L.rides[1].vehicle.rootNode == 730)
HorseLead.command(nil, "stop")
nodes[900].pos = { 12, 0, 12 }

-- pinned horses: the nudge (the game's own setWorldPosition), the last resort of a led horse, hdLead free, and the watchdog for a ridden horse
nodes[760] = { pos = { 100, 5, 100 }, children = {} }
local moves = {}
local function pinnedHorse(node)
    return { rootNode = node, spec_rideable = { currentTurnAngle = 0, haltTimer = 0, inputValues = { axisSteer = 0, currentGait = 1 }, doHusbandryCheck = 0 },
        setWorldPosition = function(self, x, y, z, rx, ry, rz, i, changeInterp) moves[#moves + 1] = { x = x, y = y, z = z, ry = ry, i = i, changeInterp = changeInterp }; nodes[self.rootNode].pos = { x, y, z } end }
end
local horse760 = pinnedHorse(760)
check("nudge: puts the horse 3 m in the given direction, on the ground (a little above), facing that way, for component 1 with interpolation reset",
    L.nudge(horse760, 1, 0, 3) and math.abs(moves[1].x - 103) < 1e-6 and math.abs(moves[1].z - 100) < 1e-6 and moves[1].i == 1 and moves[1].changeInterp == true and math.abs(moves[1].ry - math.pi / 2) < 1e-6)
check("nudge: no direction, or a vehicle without setWorldPosition: false, nothing moved", L.nudge(horse760, 0, 0, 3) == false and L.nudge({ rootNode = 760 }, 1, 0, 3) == false and #moves == 1)
local failingMove = pinnedHorse(760)
failingMove.setWorldPosition = function() error("no physics") end
check("nudge: an error of the engine call is caught", L.nudge(failingMove, 1, 0, 3) == false)

-- a led horse that stays stuck: backs up twice, is moved towards the player once, then released
for _, v in ipairs(vehicles) do v.isDeleted = true end
moves = {}
L.rides = {}
nodes[900].pos = { 12, 0, 12 }
nodes[761] = { pos = { 12, 0, 40 }, children = {} }
local stuckHorse = pinnedHorse(761)
stuckHorse.setWorldPosition = function(self, x, y, z, rx, ry, rz, i, ci) moves[#moves + 1] = { x = x, z = z } end      -- (it does not really move: the fake keeps it where it is)
vehicles[#vehicles + 1] = stuckHorse
L.rides[1] = { vehicle = stuckHorse, known = {}, from = { 12, 40 }, waited = 0, stableMs = 0 }
L.claimVehicle(stuckHorse)
log = {}
for _ = 1, 900 do
    L.updateRide(50)
    if #L.rides == 0 then break end
end
local nudgedTowards = moves[1] ~= nil and moves[1].z < 40 and math.abs(moves[1].x - 12) < 1
check("a led horse that stays stuck after backing up is put 3 m towards the player once, and only then released", #moves == 1 and nudgedTowards and #L.rides == 0 and stuckHorse.rfVirtualRider == nil)
local sawNudge = false
for _, line in ipairs(log) do if line:find("put 3 m towards you", 1, true) then sawNudge = true end end
check("... and the log says so", sawNudge)
stuckHorse.isDeleted = true

-- hdLead free: the nearest horse vehicle (also the one that is ridden) is put 3 m behind itself
moves = {}
nodes[762] = { pos = { 14, 0, 14 }, children = {} }
local ridden = pinnedHorse(762)
ridden.spec_rideable.currentTurnAngle = 0                              -- heading +z: behind is -z
vehicles[#vehicles + 1] = ridden
check("hdLead free moves the nearest horse out, behind itself", commands.hdLead("free") == "the horse was moved out" and #moves == 1 and math.abs(moves[1].z - 11) < 1e-6 and math.abs(moves[1].x - 14) < 1e-6)
ridden.isDeleted = true
check("hdLead free with no horse near says so", commands.hdLead("free") == "no horse within 8 m")

-- the watchdog: a ridden horse halted again and again is moved out, once per cooldown; a free or a not halted horse is left alone
moves = {}
nodes[763] = { pos = { 14, 0, 14 }, children = {} }
local watched = pinnedHorse(763)
watched.getIsEntered = function() return true end
watched.spec_rideable.haltTimer = 900
vehicles[#vehicles + 1] = watched
for _ = 1, 40 do L.watchRidden(50) end                                  -- 2 s: not yet
check("watchdog: a ridden horse halted for less than 2.5 s is left alone", #moves == 0)
for _ = 1, 20 do L.watchRidden(50) end                                  -- past 2.5 s
check("watchdog: halted for 2.5 s: put 3 m behind itself", #moves == 1)
for _ = 1, 100 do L.watchRidden(50) end                                 -- still halted: the cooldown holds it back for 6 s
check("watchdog: not again within the cooldown", #moves == 1)
watched.spec_rideable.haltTimer = 0
moves = {}
for _ = 1, 200 do L.watchRidden(50) end
check("watchdog: a horse that is not halted is left alone", #moves == 0)
watched.getIsEntered = function() return false end
watched.spec_rideable.haltTimer = 900
for _ = 1, 200 do L.watchRidden(50) end
check("watchdog: a horse nobody rides is left alone (led horses have their own stuck handling)", #moves == 0)
watched.isDeleted = true
nodes[900].pos = { 12, 0, 12 }

-- the leash rope: a chain of the game's winch rope pieces (ForestryRope) with hanging points between, from the player to the horse's rein node
local ropes, loadCalls, pendingLoads = {}, {}, {}
ForestryRope = {}
ForestryRope.__index = ForestryRope
function ForestryRope.new(vehicle, linkNode)
    local r = setmetatable({ linkNode = linkNode, visibility = true, deleted = false, updates = 0 }, ForestryRope)
    ropes[#ropes + 1] = r
    return r
end
function ForestryRope:onI3DLoaded() self.referenceFrame = 4242 end
function ForestryRope:link(node) self.linkNode = node end
function ForestryRope:setVisibility(v) self.visibility = v end
function ForestryRope:setTargetNode(node, dirty) self.targetNode, self.activeDirty = node, dirty end
function ForestryRope:update() self.updates = self.updates + 1 end
function ForestryRope:delete() self.deleted = true end
local function loadAll() for _, load in ipairs(pendingLoads) do load() end pendingLoads = {} end
g_i3DManager = { loadSharedI3DFileAsync = function(_, filename, a, b, callback, object) loadCalls[#loadCalls + 1] = filename; pendingLoads[#pendingLoads + 1] = function() callback(object) end; return 7 end }
local nextNode, gone = 2000, {}
createTransformGroup = function(name) nextNode = nextNode + 1; nodes[nextNode] = { name = name, pos = { 0, 0, 0 }, children = {} }; return nextNode end
link = function(parent, child) nodes[child].parent = parent end
getRootNode = function() return 1 end
setTranslation = function(node, x, y, z) nodes[node].pos = { x, y, z } end
delete = function(node) gone[node] = true; nodes[node] = nil end
entityExists = function(node) return nodes[node] ~= nil end
local terrain = 0
g_terrainNode = 5
getTerrainHeightAtWorldPos = function() return terrain end
nodes[321] = { pos = { 10, 1.5, 10 }, children = {} }                     -- the leash in the hand
nodes[322] = { pos = { 10, 1.5, 10 }, children = {} }
nodes[555] = { pos = { 16, 1.5, 10 }, children = {} }                     -- the horse's rein node, 6 m away
dofile("scripts/HorseRope.lua")
local ropeHorse = { rootNode = 1, spec_rideable = { leftReinNode = 555 } }
check("the rope is tied to the horse's rein node (else the rein parent, else the root node)", HorseRope.targetNodeOf(ropeHorse) == 555
    and HorseRope.targetNodeOf({ rootNode = 1, spec_rideable = { leftReinParentNode = 556 } }) == 556 and HorseRope.targetNodeOf({ rootNode = 9 }) == 9)
local ropeRide = { vehicle = ropeHorse }
HorseRope.sync(ropeRide, nil)
check("nothing to hang the rope from: no rope is made", ropeRide.rope == nil and #ropes == 0)
HorseRope.sync(ropeRide, 321)
local chain = ropeRide.rope
check("a rope is made of SEGMENTS pieces on the winch rope shape (path resolved, node 4), the first linked to the source, the others to the points between",
    chain ~= nil and #ropes == HorseRope.SEGMENTS and #chain.mids == HorseRope.SEGMENTS - 1 and loadCalls[1] == "C:/Game/data/shared/forestry/ropes.i3d" and ropes[1].i3dRopePath == "4"
    and ropes[1].linkNode == 321 and ropes[2].linkNode == chain.mids[1] and ropes[HorseRope.SEGMENTS].linkNode == chain.mids[HorseRope.SEGMENTS - 1] and ropes[1].diameter == HorseRope.DIAMETER)
check("... and none is tied before its shape has loaded (the game's update would fail on a missing frame)", ropes[1].targetNode == nil and ropes[HorseRope.SEGMENTS].targetNode == nil)
loadAll()
HorseRope.sync(ropeRide, 321)
local last = HorseRope.SEGMENTS
check("once loaded, piece k is tied to point k, the last one to the rein node, all following every frame (active) and shown",
    ropes[1].targetNode == chain.mids[1] and ropes[3].targetNode == chain.mids[3] and ropes[last].targetNode == 555 and ropes[2].activeDirty == true and ropes[1].visibility == true and #ropes == last)
local mid3, mid1 = nodes[chain.mids[3]].pos, nodes[chain.mids[1]].pos
check("the points hang below the straight line: 6 m span, the cap of the sag in the middle (a bit less nearer the ends), on the line in x", math.abs(mid3[2] - (1.5 - HorseRope.SAG_MAX_M)) < 1e-6
    and math.abs(mid3[1] - 13) < 1e-6 and mid1[2] < 1.5 and mid1[2] > mid3[2] and math.abs(mid1[1] - 11) < 1e-6)
check("the pieces follow the points in the same frame (updated after the points moved)", ropes[1].updates >= 1 and ropes[last].updates >= 1)
terrain = 1.4
HorseRope.sync(ropeRide, 321)
check("the points stay above the ground", nodes[chain.mids[3]].pos[2] >= 1.4 + HorseRope.GROUND_CLEARANCE_M - 1e-9)
terrain = 0
nodes[555].pos = { 10.5, 1.5, 10 }                                        -- 0.5 m: a short rope hangs less
HorseRope.sync(ropeRide, 321)
check("a short distance: the sag is smaller than the cap", nodes[chain.mids[3]].pos[2] > 1.5 - HorseRope.SAG_MAX_M and nodes[chain.mids[3]].pos[2] < 1.5)
nodes[555].pos = { 16, 1.5, 10 }
HorseRope.sync(ropeRide, nil)
check("nothing to hang it from: every piece is hidden, none deleted", ropes[1].visibility == false and ropes[last].visibility == false and ropes[1].deleted == false)
HorseRope.sync(ropeRide, 322)
check("a new source (maybe another node): the first piece is linked to it and all are shown again", ropes[1].linkNode == 322 and ropes[1].visibility == true and ropes[last].visibility == true)
HorseRope.remove(ropeRide)
check("the horse is let go: every piece and every point is deleted", ropes[1].deleted == true and ropes[last].deleted == true and gone[chain.mids[1]] == true and gone[chain.mids[last - 1]] == true and ropeRide.rope == nil)
local savedForestry = ForestryRope
ForestryRope = nil
local noEngine = { vehicle = ropeHorse }
HorseRope.sync(noEngine, 321)
check("without ForestryRope in the game nothing happens and nothing is retried every frame", noEngine.rope == nil and noEngine.ropeFailed == true)
ForestryRope = savedForestry

-- the anchor for the rope when the leash is not in the hand
nodes[960], nodes[961] = { pos = { 0, 0, 0 }, children = {} }, { pos = { 0, 0, 0 }, children = {} }
local anchor1 = HorseRope.anchorOn(960, 0, 1.1, 0)
check("an anchor node hangs from the parent at the offset", nodes[anchor1].parent == 960 and nodes[anchor1].pos[2] == 1.1)
check("the same parent: the same node", HorseRope.anchorOn(960, 0, 1.1, 0) == anchor1)
local anchor2 = HorseRope.anchorOn(961, 0, 1.3, 0.2)
check("another parent (the player mounts): a new node on it, the old one deleted", anchor2 ~= anchor1 and nodes[anchor2].parent == 961 and gone[anchor1] == true)
nodes[961] = nil
nodes[anchor2] = nil                                                      -- (the horse is deleted: its child goes with it)
local anchor3 = HorseRope.anchorOn(960, 0, 1.1, 0)
check("a parent whose node was deleted with it: a fresh one is made, without touching the dead one", anchor3 ~= anchor2 and nodes[anchor3] ~= nil and gone[anchor2] == nil)

-- the rope follows the leash ride: made on the first frame with the tool in the hand, kept when it is put away or the player mounts, removed when the horse is let go
for _, v in ipairs(vehicles) do v.isDeleted = true end
ropes, loadCalls = {}, {}
L.rides = {}
nodes[900].pos = { 12, 0, 12 }
local leashHorse = pinnedHorse(770)
nodes[770] = { pos = { 14, 0, 14 }, children = {} }
vehicles[#vehicles + 1] = leashHorse
L.claimVehicle(leashHorse)
L.rides[1] = { vehicle = leashHorse, known = {}, from = { 14, 14 }, waited = 0, stableMs = 0, leash = true }
L.leashSource = 321
L.updateRide(50)
check("a leashed horse gets a rope while the leash tool is in the hand, starting at it", L.rides[1].rope ~= nil and ropes[1].linkNode == 321)
L.leashSource = nil
L.updateRide(50)
local onFoot = ropes[1].linkNode
check("the leash put away: the horse stays led and the rope stays, now from the player's chest", #L.rides == 1 and ropes[1].visibility == true and onFoot ~= 321 and nodes[onFoot].parent == 900 and nodes[onFoot].pos[2] == 1.1)
nodes[901] = { pos = { 12, 0, 12 }, children = {} }
g_localPlayer.getCurrentVehicle = function() return { rootNode = 901 } end
L.updateRide(50)
check("the player mounts a horse: the rope hangs from its saddle", ropes[1].linkNode ~= onFoot and nodes[ropes[1].linkNode].parent == 901 and ropes[1].visibility == true)
g_localPlayer.getCurrentVehicle = nil
-- the gates: the leash click opens and closes the gate in reach
dofile("scripts/HorseGate.lua")
local function leaf(trigger, part)
    local l = { triggerNode = trigger, animation = { direction = 0, time = 0, parts = { { node = part } } }, allowed = true }
    function l:getCanBeTriggered() return self.allowed end
    function l:setDirection(d) self.animation.direction = d; if d == 0 then self.animation.direction = self.animation.time > 0 and -1 or 1 end end   -- (as the game's)
    return l
end
nodes[980], nodes[981], nodes[982], nodes[983] = { pos = { 20, 0, 12 }, children = {} }, { pos = { 14, 0, 12 }, children = {} }, { pos = { 200, 0, 200 }, children = {} }, { pos = { 80, 0, 80 }, children = {} }
local a1, a2, b1, c1 = leaf(980, 981), leaf(980, 981), leaf(982, 982), leaf(983, 983)
g_currentMission.placeableSystem = { placeables = {
    { spec_husbandryFence = { fence = { segments = { { animatedObjects = { a1, a2 } }, {}, { animatedObjects = { b1 } } } } } },
    { spec_fence = { animatedObjects = { c1 } } },
    { spec_other = {} } } }
local function settle(...) for _, l in ipairs({ ... }) do l.animation.time = l.animation.direction > 0 and 1 or 0; l.animation.direction = 0 end end
check("the gate's distance is that of its door or trigger, whichever is nearer (the door 2 m away, the trigger 8 m)", math.abs(HorseGate.distance({ a1 }, 12, 12) - 2) < 1e-9)
check("no gate within reach: nothing happens", HorseGate.toggleNearest(40, 12) == nil and a1.animation.direction == 0)
check("a gate in reach opens, every leaf of it; another gate far away is left alone", HorseGate.toggleNearest(12, 12) == "gate opens" and a1.animation.direction == 1 and a2.animation.direction == 1 and b1.animation.direction == 0)
settle(a1, a2)
check("used again it closes", HorseGate.toggleNearest(12, 12) == "gate closes" and a1.animation.direction == -1 and a2.animation.direction == -1)
settle(a1, a2)
a1.allowed, a2.allowed = false, false
check("a gate on land of another farm (the game's own check says no): not opened, and it says so", HorseGate.toggleNearest(12, 12) == "this gate is not yours to open" and a1.animation.direction == 0)
a1.allowed, a2.allowed = true, true
check("the older fence placeables' gates are found too", HorseGate.toggleNearest(80, 80) == "gate opens" and c1.animation.direction == 1)
-- the leash switch: with the horse on the rope, the click near a gate is for the gate; away from it it lets the horse go
check("a led horse and a gate in reach: the click opens the gate, the horse stays led", HorseLead.leash() == "gate opens" and #L.rides == 1 and ropes[1].deleted == false and a1.animation.direction == 1)
nodes[900].pos = { 40, 0, 12 }
check("... and away from the gate it lets the horse go, as before", HorseLead.leash() == "1 horse(s) let go" and #L.rides == 0)
nodes[900].pos = { 12, 0, 12 }
settle(a1, a2)
local realCommand = HorseLead.command
HorseLead.command = function() return "no horse nearby" end
check("no horse to take and a gate in reach: the click is for the gate", HorseLead.leash() == "gate closes")
nodes[900].pos = { 40, 0, 12 }
check("... and without a gate in reach it says what it said before", HorseLead.leash() == "no horse nearby")
HorseLead.command = realCommand
nodes[900].pos = { 12, 0, 12 }
HorseLead.command(nil, "stop")
check("the horses are given back: the rope is deleted", ropes[1].deleted == true)
leashHorse.isDeleted = true

-- the leash in the hand with no horse on it: a short end of rope instead of a model
L.rides = {}
local ropesBefore = #ropes
L.leashSource = 321
L.updateRide(50)
local stub = HorseRope.stub
check("the leash in the hand and no horse on it: one short piece of rope from the tool", stub ~= nil and #ropes == ropesBefore + 1 and ropes[#ropes].linkNode == 321 and stub.rope.segments == 1)
loadAll()
L.updateRide(50)
local stubRope = ropes[#ropes]
check("... hanging 20 cm straight down from the tool, shown", stubRope.targetNode == stub.targetNode and math.abs(nodes[stub.targetNode].pos[2] - (nodes[321].pos[2] - HorseRope.STUB_M)) < 1e-9 and stubRope.visibility == true)
L.leashSource = nil
L.updateRide(50)
check("the tool put away: the end of rope is hidden", stubRope.visibility == false)

-- the hand tools: the actions call the right functions
g_currentModName = "FS25_HorseDynamics"
InputAction.ACTIVATE_HANDTOOL = 3
g_i18n = { getText = function(_, key) return key end }
g_i18n.getText = function(self, key) return key end
SpecializationUtil = { registerEventListener = function(type, name) type[name] = true end }
dofile("scripts/HandToolHorseCarrot.lua")
dofile("scripts/HandToolHorseLeash.lua")
local carrotType, leashType = {}, {}
HandToolHorseCarrot.registerEventListeners(carrotType)
HandToolHorseLeash.registerEventListeners(leashType)
check("both tools register their listeners", carrotType.onRegisterActionEvents and carrotType.onHeldStart and leashType.onRegisterActionEvents and leashType.onHeldEnd)
-- the rope prop's collision shape is removed from the leash
nodes[950] = { name = "horseLeash", children = { 951, 952 } }
nodes[951] = { name = "graphics", children = { 953 } }
nodes[952] = { name = "handNode", children = {} }
nodes[953] = { name = "rope", children = { 954, 955, 956 } }
nodes[954] = { name = "LOD0", children = {} }
nodes[955] = { name = "LOD1", children = {} }
nodes[956] = { name = "col", children = {} }
local deletedNodes = {}
delete = function(node) deletedNodes[#deletedNodes + 1] = node end
check("the leash's collision shape (a node called col, found in the rope's children) is deleted, the rest stays", HandToolHorseLeash.stripCollision(950) == 1 and deletedNodes[1] == 956 and #deletedNodes == 1)
check("no root or no engine functions: nothing happens, no error", HandToolHorseLeash.stripCollision(nil) == 0)
local called = {}
local oldCall, oldLeash = HorseLead.carrot, HorseLead.leash
HorseLead.carrot = function() called[#called + 1] = "carrot" return "x" end
HorseLead.leash = function() called[#called + 1] = "leash" return "y" end
HandToolHorseCarrot.onAction({}, nil, 1)
HandToolHorseLeash.onAction({}, nil, 1)
HandToolHorseCarrot.onAction({}, nil, 0)
check("the primary action of the carrot calls the pasture, of the leash toggles the leash, a release of the button does nothing", #called == 2 and called[1] == "carrot" and called[2] == "leash")
HorseLead.carrot, HorseLead.leash = oldCall, oldLeash

-- the real game: the virtual rider is a flag; the game sees the horse as free (a player can mount it), and "controlled" only inside the hold-still function
local gameFunction = function() return false end
local realVehicle = { rootNode = 1, getIsControlled = gameFunction, spec_rideable = { inputValues = { axisSteer = 0, currentGait = 1 }, doHusbandryCheck = 0 } }
L.claimVehicle(realVehicle)
check("claimed: only a flag is set, the game's own getIsControlled is untouched (the horse still looks free to the enter key)", realVehicle.rfVirtualRider == true and realVehicle.getIsControlled == gameFunction and realVehicle.getIsControlled() == false)
local seenInside, seenSelf
local function holdStill(self, a, b) seenInside = self:getIsControlled(); seenSelf = self; return a + b, "second" end
local r1, r2 = L.withVirtualRider(realVehicle, holdStill, 2, 3)
check("inside the hold-still function the horse reports controlled, and the function's results are passed through", seenInside == true and r1 == 5 and r2 == "second")
check("... and afterwards the game's own function is back, so a player can mount", realVehicle.getIsControlled == gameFunction and realVehicle.getIsControlled() == false)
local failing = function() error("boom") end
check("an error inside is passed on, and the game's function is still put back", not pcall(L.withVirtualRider, realVehicle, failing) and realVehicle.getIsControlled == gameFunction)
local plain = { getIsControlled = gameFunction }
local plainInside
L.withVirtualRider(plain, function(self) plainInside = self:getIsControlled() end)
check("a horse without a virtual rider is left alone (nobody else's horse is affected)", plainInside == false and plain.getIsControlled == gameFunction)
local classLevel = { rootNode = 1 }
L.claimVehicle(classLevel)
local insideClass
L.withVirtualRider(classLevel, function(self) insideClass = self:getIsControlled() end)
check("a vehicle whose getIsControlled is the class's (no field of its own) works too and has none afterwards", insideClass == true and classLevel.getIsControlled == nil)
L.unclaimVehicle(realVehicle)
check("unclaimed: the flag is gone", realVehicle.rfVirtualRider == nil)
local releasedRide = { vehicle = { rootNode = 1, getIsControlled = gameFunction, spec_rideable = { inputValues = { axisSteer = 0.5, currentGait = 3 }, doHusbandryCheck = 0 } } }
L.claimVehicle(releasedRide.vehicle)
L.releaseRide(releasedRide)
check("releaseRide takes the rider off and asks for the stable check", releasedRide.vehicle.rfVirtualRider == nil and releasedRide.vehicle.spec_rideable.doHusbandryCheck == 2000)
-- the hook is installed on the game's class when it is there
do
    -- the hook itself: load the file again against a fake Rideable class whose hold-still function asks getIsControlled, as the game's does
    local keepHorseLead, keepOnUpdate = HorseLead, Rideable.onUpdateInterpolation
    Rideable.onUpdateInterpolation = function(self) return self:getIsControlled() end
    dofile("scripts/HorseLead.lua")
    local claimedHorse = { rfVirtualRider = true, getIsControlled = function() return false end }
    local freeHorse = { getIsControlled = function() return false end }
    check("the hook: the game's hold-still function sees a claimed horse as controlled, any other horse as it is, and the claimed horse is free again afterwards",
        Rideable.onUpdateInterpolation(claimedHorse) == true and Rideable.onUpdateInterpolation(freeHorse) == false and claimedHorse.getIsControlled() == false)
    HorseLead, Rideable.onUpdateInterpolation = keepHorseLead, keepOnUpdate
end

-- a player mounts a following horse: it is dropped, the others keep following
pasture3.startRiding = realisticStart
husbandry.animalIdToCluster[1].id, husbandry.animalIdToCluster[2].id, husbandry.animalIdToCluster[3].id = 11, 12, 13
for _, v in ipairs(vehicles) do v.isDeleted = true end
nodes[900].pos = { 12, 0, 12 }
L.rides = {}
commands.hdLead("start")
L.updateRide(50)
commands.hdLead("start")
L.updateRide(50)
local twoHorses = { L.rides[1] and L.rides[1].vehicle, L.rides[2] and L.rides[2].vehicle }
check("two horses are led", #L.rides == 2 and twoHorses[1] ~= nil and twoHorses[2] ~= nil)
twoHorses[1].getIsEntered = function() return true end                  -- the player presses the enter key on the first
L.updateRide(50)
check("a horse that a player has mounted is dropped from the string and its rider flag removed; the other keeps being led", #L.rides == 1 and twoHorses[1].rfVirtualRider == nil and L.rides[1].vehicle == twoHorses[2] and twoHorses[2].rfVirtualRider == true)
check("... and it says so", (log[#log] or ""):find("mounted", 1, true) ~= nil)
twoHorses[1].getIsEntered = nil
HorseLead.command(nil, "stop")

print = realPrint
print(string.format("horsedynamics_test: %d/%d passed", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
