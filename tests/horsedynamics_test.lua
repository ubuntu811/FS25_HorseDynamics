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
nodes[900].pos = { 10, 0, 15.5 }                                        -- 5.5 m: still walking (the carrot's arrive distance is 5 m, plus a spread of its own per horse: 0 in the tests)
L.updateRide(50)
check("between arrive and walk distance it keeps walking", horse.spec_rideable.inputValues.currentGait == Rideable.GAITTYPES.WALK)
nodes[900].pos = { 10, 0, 14.5 }                                        -- 4.5 m: inside the arrive distance, it stops
L.updateRide(50)
check("inside the arrive distance (5 m) it stops (it stood with its mane in the camera at 3.5 m)", horse.spec_rideable.inputValues.currentGait == Rideable.GAITTYPES.STILL)
check("each carrot horse gets a distance of its own: 0 to 2.5 m more (0 here: the tests' random is the shortest)", L.rides[1].arriveExtra == 0 and HorseLead.RIDE_ARRIVE_SPREAD_M == 2.5)
-- the gait ladder is by the horse's own speeds: its xml has trot (2.5 m/s) slower than canter (5.0), the game's enum has canter first
local G = Rideable.GAITTYPES
local realSpeeds = { [G.WALK] = 1.08, [G.TROT] = 2.5, [G.CANTER] = 5.0, [G.GALLOP] = 10 }
check("the ladder by rank: the 2nd step is the 2nd slowest gait (trot here), the 3rd the canter", L.rideGait(G.WALK, 15, nil, nil, realSpeeds) == G.TROT and L.rideGait(G.TROT, 25, nil, nil, realSpeeds) == G.CANTER
    and L.rideGait(G.CANTER, 60, nil, nil, realSpeeds) == G.GALLOP)
check("... without speeds it is the enum's order (canter before trot), as before", L.rideGait(G.WALK, 15) == G.CANTER)
check("the leash ladder steps up early: 5 m away (the nose 3.5 m from him) it is at the 3rd gait (canter by the real speeds)", L.rideGait(G.TROT, 5.0, L.RIDE_GAITS_LEASH, L.RIDE_GAIT_MARGIN_LEASH_M, realSpeeds) == G.CANTER)
-- standing: it turns to face the player in place; riding: it comes closer
L.rides[1].phase, L.rides[1].phaseMs = "follow", 100000
horse.spec_rideable.currentTurnAngle = math.pi / 2                       -- facing +x
nodes[900].pos = { 10, 0, 13.0 }                                         -- 3 m away, straight on (+z): arrived (the carrot arrive distance is 5), standing, and not close enough to be backed away from
local standX, standZ = getWorldTranslation(horse.rootNode)
L.updateRide(50)
check("arrived and standing (3 m): it still turns to face the player, in place (3.5 rad/s: 0.175 rad a frame), the steer zero", horse.spec_rideable.inputValues.currentGait == Rideable.GAITTYPES.STILL
    and math.abs(horse.spec_rideable.currentTurnAngle - (math.pi / 2 - 0.175)) < 1e-6 and horse.spec_rideable.inputValues.axisSteer == 0 and getWorldTranslation(horse.rootNode) == standX)
for _ = 1, 20 do L.updateRide(50) end
check("... until it faces him", math.abs(horse.spec_rideable.currentTurnAngle) < 1e-6)
horse.spec_rideable.currentTurnAngle = math.pi / 2
-- looking at the gear: with "face off" a standing horse stays as it stands
horse.spec_rideable.currentTurnAngle = math.pi / 2
nodes[900].pos = { 10, 0, 13.0 }
check("hdLead face off: a standing horse does not turn to face the player", commands.hdLead("face", "off"):find("stays as it stands", 1, true) ~= nil and HorseLead.RIDE_TURN_RATE_STILL == 0)
for _ = 1, 10 do L.updateRide(50) end
check("... it stays as it stands while the player is 3 m away", horse.spec_rideable.currentTurnAngle == math.pi / 2)
check("hdLead face on turns it back on, and a wrong word says how", commands.hdLead("face", "on"):find("turns to face you", 1, true) ~= nil and HorseLead.RIDE_TURN_RATE_STILL == 3.5 and commands.hdLead("face", "x"):find("usage: hdLead face", 1, true) ~= nil)
-- frozen (Right Ctrl + F, hdFreezeHorse): the led horses stand completely still, whatever the rest would do
horse.spec_rideable.currentTurnAngle = math.pi / 2
nodes[900].pos = { 10, 0, 20 }                                           -- 10 m away: it would walk to him
check("hdFreezeHorse freezes the led horses, and says so", commands.hdFreezeHorse():find("frozen", 1, true) ~= nil and HorseLead.frozen == true)
for _ = 1, 5 do L.updateRide(50) end
check("a frozen horse 10 m from the player does not follow: it stands, does not turn, the steer is zero", horse.spec_rideable.inputValues.currentGait == Rideable.GAITTYPES.STILL
    and horse.spec_rideable.currentTurnAngle == math.pi / 2 and horse.spec_rideable.inputValues.axisSteer == 0)
nodes[900].pos = { 10, 0, 11.5 }                                         -- 1.5 m in front of it: it would back away
for _ = 1, 3 do L.updateRide(50) end
check("... a player walking into it does not make it back away", horse.spec_rideable.inputValues.currentGait == Rideable.GAITTYPES.STILL and horse.backingOff ~= true and L.rides[1].backingOff ~= true)
check("hdFreezeHorse again lets it go on", commands.hdFreezeHorse():find("follow you again", 1, true) ~= nil and HorseLead.frozen == false)
nodes[900].pos = { 10, 0, 20 }
for _ = 1, 3 do L.updateRide(50) end
check("... it walks to the player again", horse.spec_rideable.inputValues.currentGait ~= Rideable.GAITTYPES.STILL)
HorseLead.frozen = true
local ridesKept = L.rides
L.rides = {}
L.updateRide(50)
check("with no horse led any more the freeze is forgotten (a horse led later is not born frozen)", HorseLead.frozen == false)
L.rides = ridesKept
-- a horse that stays (it wears the harness, nothing leads it): it stands where it is whatever the player does
nodes[900].pos = { 10, 0, 20 }
L.rides[1].stay = true
for _ = 1, 5 do L.updateRide(50) end
check("a horse that stays does not follow: 10 m from the player it stands, and it is not given back at a stable", horse.spec_rideable.inputValues.currentGait == Rideable.GAITTYPES.STILL and #L.rides == 1)
nodes[900].pos = { 10, 0, 11.5 }
for _ = 1, 3 do L.updateRide(50) end
check("... a player walking into it does not make it back away", horse.spec_rideable.inputValues.currentGait == Rideable.GAITTYPES.STILL and L.rides[1].backingOff ~= true)
L.rides[1].stay = nil
nodes[900].pos = { 10, 0, 20 }
for _ = 1, 3 do L.updateRide(50) end
check("... and when it is not staying any more it follows again", horse.spec_rideable.inputValues.currentGait ~= Rideable.GAITTYPES.STILL)
-- a hitched horse whose load cannot keep up waits for it (HorseHitch sets hitch.waiting), and goes on when the load has caught up
HorseHitch = { update = function() end, updatePlayer = function() end, updateSaddle = function() end, limitGait = function(ride, gait) return Rideable.GAITTYPES.WALK end }
L.rides[1].hitch = {}
L.updateRide(50)
check("a horse that pulls has the gait HorseHitch.limitGait gives it (here: walk), whatever its steering chose, even with the player far away", horse.spec_rideable.inputValues.currentGait == Rideable.GAITTYPES.WALK)
L.rides[1].hitch = nil
for _ = 1, 3 do L.updateRide(50) end
HorseHitch = nil
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
-- on the leash: no pauses, a closer arrive distance, no stop and go at the edge, stepping back from a player who walks up
local ride1 = L.rides[1]
ride1.leash = true
horse.spec_rideable.currentTurnAngle = 0                                  -- facing +z, where the player is
ride1.phase, ride1.phaseMs = "pause", 100000
nodes[900].pos = { 10, 0, 18 }
L.updateRide(50)
check("a leashed horse does not pause: a pause is cancelled, it goes after him (8 m: a trot on a 3 m rope)", ride1.phase == "follow" and horse.spec_rideable.inputValues.currentGait == Rideable.GAITTYPES.TROT)
for _ = 1, 50 do L.updateRide(50) end                                    -- (the fake horse does not move: not long enough for the stuck rescue)
check("... and never starts one, however long it walks", ride1.phase == "follow" and horse.spec_rideable.inputValues.currentGait ~= Rideable.GAITTYPES.STILL)
nodes[900].pos = { 10, 0, 13.7 }                                          -- 3.7 m: beyond the leash arrive distance (3.4: the nose is 2 m from him), the rope hangs slack: still walking
horse.spec_rideable.inputValues.currentGait = Rideable.GAITTYPES.WALK
L.updateRide(50)
check("3.7 m on the leash: it is still walking (the nose is about 2.2 m from the player)", horse.spec_rideable.inputValues.currentGait == Rideable.GAITTYPES.WALK)
nodes[900].pos = { 10, 0, 13.35 }                                         -- 3.35 m: it stops
L.updateRide(50)
check("3.35 m: it stops", horse.spec_rideable.inputValues.currentGait == Rideable.GAITTYPES.STILL)
nodes[900].pos = { 10, 0, 13.6 }                                          -- 3.6 m: standing, the resume distance is 3.8
L.updateRide(50)
check("3.6 m while standing: it stays (no stop and go at the edge)", horse.spec_rideable.inputValues.currentGait == Rideable.GAITTYPES.STILL)
nodes[900].pos = { 10, 0, 13.9 }
L.updateRide(50)
check("3.9 m: it walks on", horse.spec_rideable.inputValues.currentGait == Rideable.GAITTYPES.WALK)
nodes[900].pos = { 10, 0, 12.5 }                                          -- 2.5 m (its nose 1 m from him), in front of it: the player walked up to it
L.updateRide(50)
check("the player walks up to the horse: it steps back", horse.spec_rideable.inputValues.currentGait == Rideable.GAITTYPES.BACKWARDS and ride1.backingOff == true)
nodes[900].pos = { 10, 0, 12.9 }                                          -- 2.9 m: not yet far enough (3.1)
L.updateRide(50)
check("... and keeps stepping back until he is 3.1 m away", horse.spec_rideable.inputValues.currentGait == Rideable.GAITTYPES.BACKWARDS)
nodes[900].pos = { 10, 0, 13.2 }
L.updateRide(50)
check("... then it stands", horse.spec_rideable.inputValues.currentGait == Rideable.GAITTYPES.STILL and ride1.backingOff == false)
nodes[900].pos = { 12.5, 0, 10 }                                          -- 2.5 m but at its side: stepping back would not help
L.updateRide(50)
check("a player beside it (not in front): it does not back up", horse.spec_rideable.inputValues.currentGait ~= Rideable.GAITTYPES.BACKWARDS)
nodes[900].pos = { 10, 0, 12.5 }
g_localPlayer.getCurrentVehicle = function() return { rootNode = 900 } end
L.updateRide(50)
check("a player on horseback is not backed away from", horse.spec_rideable.inputValues.currentGait ~= Rideable.GAITTYPES.BACKWARDS)
g_localPlayer.getCurrentVehicle = nil
ride1.leash, ride1.backingOff = nil, false
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
-- a horse on the leash is held by the player until he lets go: walking it through a pasture's gate must not take it away
commands.hdLead("start")
L.updateRide(50)
L.rides[1].leash = true
inRange = false
for _ = 1, 25 do L.updateRide(50) end
inRange = true
for _ = 1, 40 do L.updateRide(50) end
check("a horse on the leash is NOT handed back at a stable (walking it into a stable's range with the player close): still led", #L.rides == 1)
commands.hdLead("stop")
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
InputAction = { HORSEDYN_CALL = 1, HORSEDYN_RELEASE = 2, HORSEDYN_FREEZE = 3 }
GS_PRIO_LOW = 0
g_inputBinding = { registerActionEvent = function(_, action, target, method) registered[action] = method; return true, action end, setActionEventTextPriority = function() end, setActionEventTextVisibility = function() end }
HorseDynamics.registerActionEvents()
check("the three keys are registered", registered[1] ~= nil and registered[2] ~= nil and registered[3] ~= nil)
HorseDynamics.onFreeze()
check("the freeze key with no horse led: nothing to freeze, and it says so", HorseLead.frozen == false and (log[#log] or ""):find("nothing to freeze", 1, true) ~= nil)
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
nodes[4242] = { pos = { 0, 0, 0 }, children = {} }                    -- (the frame the fake rope pieces hang in: the guard skips a piece whose frame is not there)
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
HorseRope.gear = "rope"                                                  -- (the older tests are about the rope gear: leather has its tests below)
check("the default way to hold a led horse is the rope halter", HorseRope.style == "halter")
HorseRope.style = "rope"                                                 -- (the rope tests first)
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
local mid3 = nodes[chain.mids[3]].pos
check("a horse 6 m away is at the end of a 3 m rope: the rope is taut, the points on the straight line (x spread evenly)", math.abs(mid3[2] - 1.5) < 1e-6 and math.abs(mid3[1] - 13) < 1e-6)
nodes[555].pos = { 12, 1.5, 10 }                                          -- 2 m: a metre of slack
HorseRope.sync(ropeRide, 321)
mid3 = nodes[chain.mids[3]].pos
local mid1 = nodes[chain.mids[1]].pos
check("with slack the points hang below the straight line: the cap of the sag in the middle, a bit less nearer the ends", math.abs(mid3[2] - (1.5 - HorseRope.SAG_MAX_M)) < 1e-6 and mid1[2] < 1.5 and mid1[2] > mid3[2])
nodes[555].pos = { 12.9, 1.5, 10 }                                        -- 2.9 m: 10 cm of slack hangs less than the cap
HorseRope.sync(ropeRide, 321)
check("a little slack: the sag is smaller than the cap", nodes[chain.mids[3]].pos[2] > 1.5 - HorseRope.SAG_MAX_M and nodes[chain.mids[3]].pos[2] < 1.5)
nodes[555].pos = { 16, 1.5, 10 }
HorseRope.sync(ropeRide, 321)
check("the pieces follow the points in the same frame (updated after the points moved)", ropes[1].updates >= 1 and ropes[last].updates >= 1)
terrain = 1.4
nodes[555].pos = { 12, 1.5, 10 }                                          -- slack again: it would hang to 1.15, below the terrain
HorseRope.sync(ropeRide, 321)
check("the points stay above the ground", math.abs(nodes[chain.mids[3]].pos[2] - (1.4 + HorseRope.GROUND_CLEARANCE_M)) < 1e-9)
terrain = 0
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

-- the game's own reins
nodes[701], nodes[702], nodes[703], nodes[704] = { name = "reinLeft", children = {}, parent = 705 }, { name = "reinRight", children = {}, parent = 705 }, { children = {} }, { children = {} }
local equip, unlinks, entered = {}, 0, false
local reinHorse = { rootNode = 1, spec_rideable = { leftReinNode = 701, rightReinNode = 702 },
    setEquipmentVisibility = function(_, v) equip[#equip + 1] = v end, unlinkReins = function() unlinks = unlinks + 1 end, getIsEntered = function() return entered end }
HorseRope.style = "reins"
local reinRide = { vehicle = reinHorse }
local chainsBefore = #ropes
HorseRope.sync(reinRide, 321)
check("reins style: the whole tack is shown, both rein nodes are linked to the leash in the hand, no rope is made", equip[1] == true and nodes[701].parent == 321 and nodes[702].parent == 321 and reinRide.rope == nil and #ropes == chainsBefore)
HorseRope.sync(reinRide, 321)
check("... and nothing is redone every frame", #equip == 1)
HorseRope.sync(reinRide, 322)
check("another source (the leash put away: the anchor on the player): the reins follow it", nodes[701].parent == 322 and nodes[702].parent == 322 and #equip == 1)
HorseRope.sync(reinRide, nil)
check("nothing to hold them: the reins are put back where the game keeps them and the tack is hidden", unlinks == 1 and equip[2] == false and reinRide.tacked == nil)
HorseRope.sync(reinRide, 321)
HorseRope.remove(reinRide)
check("the horse is let go: reins put back, tack hidden", unlinks == 2 and equip[#equip] == false and reinRide.tacked == nil)
HorseRope.sync(reinRide, 321)
entered = true
HorseRope.remove(reinRide)
check("a horse a player has mounted is left alone (the game has linked its reins to his hands)", unlinks == 2)
entered = false
check("hdLead style: a wrong name says how to use it", commands.hdLead("style", "nothing"):find("usage: hdLead style", 1, true) ~= nil and HorseRope.style == "reins")
check("hdLead style rope switches, and re-dresses the led horses", commands.hdLead("style", "rope"):find("rope", 1, true) ~= nil and HorseRope.style == "rope")
check("hdLead style reins switches back", commands.hdLead("style", "reins"):find("reins", 1, true) ~= nil and HorseRope.style == "reins")
HorseRope.style = "rope"

-- the tack style: saddle, bridle and reins at rest, the rope to the bit ring on the head bone
nodes[830] = { name = "horseRoot", pos = { 0, 0, 0 }, children = { 831 } }
nodes[831] = { name = "skeleton", pos = { 0, 0, 0 }, children = { 832 } }
nodes[832] = { name = "Head_M", pos = { 0, 2, 1 }, children = {} }
local order, undressed = {}, 0
local tackVehicle = { rootNode = 830, spec_rideable = { leftReinNode = 701, rightReinNode = 702 },
    setEquipmentVisibility = function(_, v) order[#order + 1] = "equipment " .. tostring(v) end, unlinkReins = function() order[#order + 1] = "unlink" end, getIsEntered = function() return false end }
local ringNode = HorseRope.ringAnchor(tackVehicle)
check("the bit ring: a node on the head bone at the ring's offset (the one worked out from the bridle's geometry)", ringNode ~= nil and nodes[ringNode].parent == 832 and nodes[ringNode].pos[1] == -0.0983 and nodes[ringNode].pos[2] == 0.4425 and nodes[ringNode].pos[3] == 0.07)
check("... made once per horse", HorseRope.ringAnchor(tackVehicle) == ringNode)
HorseRope.setRing(-0.1, 0.45, 0.08)
check("hdLead ring moves it", nodes[ringNode].pos[1] == -0.1 and nodes[ringNode].pos[3] == 0.08 and commands.hdLead("ring", "-0.0983", "0.4425", "0.07"):find("bit ring is at", 1, true) ~= nil and nodes[ringNode].pos[3] == 0.07)
check("hdLead ring with a missing number says how to use it", commands.hdLead("ring", "1"):find("usage: hdLead ring", 1, true) ~= nil)
local boneless = { rootNode = 620, spec_rideable = {} }
check("a horse without a head bone: no anchor, and it is not searched for again every frame", HorseRope.ringAnchor(boneless) == nil and HorseRope.rings[boneless] == false and HorseRope.ringAnchor(boneless) == nil)
HorseRope.style = "tack"
nodes[701].parent, nodes[702].parent = 705, 705                           -- (where the earlier reins test left them: reset to the game's place)
check("the rope's target in this style is the bit ring (else the rein node)", HorseRope.targetNodeOf(tackVehicle) == ringNode)
local tackRide = { vehicle = tackVehicle }
local piecesBefore = #ropes
HorseRope.sync(tackRide, 321)
check("tack style: the reins are put at rest FIRST (unlinkReins hides them), then the equipment is shown (saddle, bridle and the reins)", order[1] == "unlink" and order[2] == "equipment true" and tackRide.tacked == true)
check("... and the winch rope is made (a chain of pieces, no reins linked to the hand)", tackRide.rope ~= nil and #ropes == piecesBefore + HorseRope.SEGMENTS and nodes[701].parent ~= 321)
HorseRope.sync(tackRide, 321)
check("... the tack is put on once", #order == 2)
loadAll()
HorseRope.sync(tackRide, 321)
check("the last piece is tied to the bit ring", ropes[#ropes].targetNode == ringNode)
HorseRope.remove(tackRide)
check("the horse is let go: the tack is taken off again and the rope deleted", order[#order] == "equipment false" and tackRide.rope == nil and ropes[#ropes].deleted == true)
check("hdLead style tack is accepted, and a wrong name says all three", commands.hdLead("style", "tack"):find("bridle", 1, true) ~= nil and commands.hdLead("style", "nothing"):find("tack|reins|rope", 1, true) ~= nil)
HorseRope.style = "rope"

-- the rope halter: loops of rope pieces on the head bone, the lead tied to the knot under the chin
localToWorld = function(node, x, y, z) local p = nodes[node].pos; return p[1] + x, p[2] + y, p[3] + z end        -- (a bone that only has a position)
check("the halter is on the head by default (it showed in the game with a 0.35 offset: loops, cheek pieces and lead as designed)", HorseRope.halterOffset[1] == 0 and HorseRope.halterOffset[2] == 0 and HorseRope.halterOffset[3] == 0)
HorseRope.halterOffset = { 0, 0, 0 }
HorseRope.style = "halter"
local savedSlack = { HorseRope.halter.nose.slack, HorseRope.halter.crown.slack }
HorseRope.halter.nose.slack, HorseRope.halter.crown.slack = 0, 0                                -- (the position tests first, without the sag)
worldDirectionToLocal = function(node, x, y, z) return x, y, z end                               -- (a bone with the world's axes: world-down is local -y)
local orderBefore = #order
local halterRide = { vehicle = tackVehicle }
local piecesBefore = #ropes
HorseRope.sync(halterRide, 321)
local halter = halterRide.halter
local S = HorseRope.halter.sides
local PIECES, POINTS = 70, 64
check("halter style: a noseband of 12 pieces, a crown path of 9 pieces, a cheek strap of 3 and two rings of 8 on each side (70 rope pieces with a strap along the bottom on each side, 64 points) plus the lead chain, the points under the world root", halter ~= nil and S == 12 and #halter.pieces == PIECES and #halter.nodes == POINTS
    and #ropes == piecesBefore + PIECES + HorseRope.SEGMENTS and nodes[halter.nodes[1]].parent == 1 and halter.bone == 832)
local k = 1 / math.cos(math.pi / S)
local m = HorseRope.halter.margin
local top, side, bottom = nodes[halter.nodes[1]].pos, nodes[halter.nodes[5]].pos, nodes[halter.nodes[S / 2 + 1]].pos             -- (the top, the front ring's point 120 degrees round from it, the bottom)
local bonePos = nodes[832].pos                                                                   -- (the bone's world position: 0 2 1)
check("the noseband's points are the measured muzzle (y 0.43, centre -0.043, half height 0.119, half width 0.085) plus the margin, scaled so the chords stay outside, at the bone's world position plus that",
    math.abs(top[1] - (bonePos[1] - 0.043 + (0.119 + m) * k)) < 1e-9 and math.abs(top[2] - (bonePos[2] + 0.43)) < 1e-9 and math.abs(top[3] - bonePos[3]) < 1e-9
    and math.abs(side[1] - (bonePos[1] - 0.043 + (0.119 + m + 0.2 * 0.14) * k * math.cos(math.rad(120)))) < 1e-9 and math.abs(side[3] - (bonePos[3] + (0.085 + m + 0.31 * 0.14) * k * math.sin(math.rad(120)))) < 1e-9
    and math.abs(bottom[1] - (bonePos[1] - 0.043 - (0.119 + m + 0.2 * 0.14) * k)) < 1e-9)
check("the noseband is bent as in the drawing: the top stays at y 0.43 (on the nose, a little behind the nostrils), the front ring low on the side (120 degrees round) and the bottom are both pulled back 0.14, so the lower leg falls straight down and the upper leg slopes up over the nose; the head is taller (0.2 per metre) and wider (0.31) there",
    math.abs(top[2] - (bonePos[2] + 0.43)) < 1e-9 and math.abs(side[2] - (bonePos[2] + 0.43 - 0.14)) < 1e-9 and math.abs(bottom[2] - (bonePos[2] + 0.43 - 0.14)) < 1e-9
    and math.abs(nodes[halter.nodes[6]].pos[2] - side[2]) < 1e-9)
local noseRingCentre = nodes[halter.nodes[13]].pos
local ringMid = (nodes[halter.nodes[13]].pos[2] + nodes[halter.nodes[17]].pos[2]) / 2
check("the front ring: radius 0.016 (as big as the cheek ring), 2 mm further to the front than the side point, in line with the strap sideways (not standing out)",
    math.abs(ringMid - (side[2] + 0.002)) < 1e-9 and math.abs(nodes[halter.nodes[13]].pos[3] - side[3]) < 1e-9 and math.abs(nodes[halter.nodes[13]].pos[1] - (side[1] + 0.016 / math.cos(math.pi / 8))) < 1e-9)
check("hdLead halter bend sets the pull-back, 0 is straight, and says how without a number", commands.hdLead("halter", "bend", "0"):find("pulled back 0.000", 1, true) ~= nil and HorseRope.halter.nose.bend == 0
    and commands.hdLead("halter", "bend"):find("usage: hdLead halter bend", 1, true) ~= nil)
HorseRope.halter.nose.bend = 0.14
local crownTop, crownBottom = nodes[halter.nodes[29]].pos, nodes[halter.nodes[30]].pos
check("the crown starts on the top of the head behind the ears (up and back, on the midline) and ends under the throat (down, on the midline)",
    math.abs(crownTop[1] - (bonePos[1] + 0.072)) < 1e-9 and math.abs(crownTop[3] - bonePos[3]) < 1e-9 and crownBottom[1] < bonePos[1] - 0.2 and math.abs(crownBottom[3] - bonePos[3]) < 1e-9)
-- the junction ring on the cheek: eight steel points round (-0.045, 0.155, 0.145), the three straps ending on their nearest points
local c = HorseRope.halter.crown
local firstRing = 38                                                          -- (after the noseband, its two rings, the top and the under point, and the 7 path points of the first side)
local rx, ry, rz = 0, 0, 0
for r = 0, 7 do
    local p = nodes[halter.nodes[firstRing + r]].pos
    rx, ry, rz = rx + p[1] / 8, ry + p[2] / 8, rz + p[3] / 8
end
check("the cheek ring: eight points round the junction on the head's left side, a vertical polygon 0.016 round", math.abs(rx - (bonePos[1] - 0.045)) < 1e-9 and math.abs(ry - (bonePos[2] + 0.155)) < 1e-9 and math.abs(rz - (bonePos[3] + 0.145)) < 1e-9
    and math.abs(nodes[halter.nodes[firstRing]].pos[1] - rx - 0.016 / math.cos(math.pi / 8)) < 1e-9)
local fx, fy, fz = 0, 0, 0
for i = 13, 20 do
    local p = nodes[halter.nodes[i]].pos
    fx, fy, fz = fx + p[1] / 8, fy + p[2] / 8, fz + p[3] / 8
end
local gap = math.sqrt((fx - rx) ^ 2 + (fy - ry) ^ 2 + (fz - rz) ^ 2)
check("the two rings on a side (the noseband's and the cheek ring) are 14 to 18 cm apart (the front ring low on the nose, the yellow line of a drawing from the ring to the cheek ring)", gap > 0.14 and gap < 0.18)
check("... and the other side's ring is its mirror image", math.abs(nodes[halter.nodes[firstRing + 17]].pos[3] - (bonePos[3] - 0.145)) < 1e-9)
local ringPieces, steel = 0, 0
for _, i in ipairs({ 13, 14, 15, 16, 17, 18, 19, 20, 29, 30, 31, 32, 33, 34, 35, 36 }) do
    ringPieces = ringPieces + 1
    steel = steel + (halter.pieces[i].rfMaterialDone and halter.pieces[i].diameter == 0.008 and 1 or 0)
end
check("the ring pieces are steel and thinner (the hemp is not put on them), the straps' pieces are hemp", steel == 16 and not halter.pieces[1].rfMaterialDone and halter.pieces[37].diameter == HorseRope.halter.diameter)
check("the ear strap, the cheek strap and the jaw strap end on three different ring points, with the angle between them (the ear strap comes from below behind, the cheek strap from above, the jaw strap down and back, 30 degrees forward of straight down)",
    halter.targets[40] == halter.nodes[firstRing + 7] and halter.pieces[41].linkNode == halter.nodes[firstRing + 3] and halter.targets[48] == halter.nodes[firstRing + 2]
    and halter.pieces[40].linkNode ~= halter.pieces[41].linkNode)
-- the strap down the cheek (the three points after the ring: 34, 35, 36) stands outside the head's measured half width at each (0.126, 0.114, 0.100), and runs 30 degrees forward of the head's straight down
local limits, clear = { 0.126, 0.114, 0.100 }, true
for n = 1, 3 do
    local p = nodes[halter.nodes[33 + n]].pos
    clear = clear and p[3] - bonePos[3] >= limits[n]
end
check("the strap down the cheek stands outside the measured half width of the head at each of its three points", clear)
local ringCentre = { bonePos[1] - 0.045, bonePos[2] + 0.155 }
local p1, p3 = nodes[halter.nodes[34]].pos, nodes[halter.nodes[36]].pos
check("... and runs 30 degrees forward of straight down (head -x), the three points in a line, 0.058 apart", math.abs((p1[1] - ringCentre[1]) / -0.058 - math.cos(math.rad(30))) < 1e-9 and math.abs((p1[2] - ringCentre[2]) / 0.058 - math.sin(math.rad(30))) < 1e-9
    and math.abs((p3[2] - ringCentre[2]) / (ringCentre[1] - p3[1]) - math.tan(math.rad(30))) < 1e-9)
check("hdLead halter jaw sets the angle (0 is straight down) and says how without a number", commands.hdLead("halter", "jaw", "0"):find("0 degrees forward", 1, true) ~= nil and HorseRope.halter.crown.jawAngle == 0 and HorseRope.halter.crown.sides[5][2] == 0.155
    and commands.hdLead("halter", "jaw"):find("usage: hdLead halter jaw", 1, true) ~= nil)
HorseRope.setJawAngle(30)
local cheekA, cheekB = nodes[halter.nodes[46]].pos, nodes[halter.nodes[47]].pos
check("the cheek strap bows out round the cheek: 0.130 / 0.142 from the middle at y 0.246 / 0.205, clear of the head's 0.114 / 0.13 there", math.abs(cheekA[3] - bonePos[3] - 0.130) < 1e-9 and math.abs(cheekB[3] - bonePos[3] - 0.142) < 1e-9 and math.abs(cheekA[2] - bonePos[2] - 0.246) < 1e-9)
nodes[832].pos = { 5, 3, 2 }
HorseRope.sync(halterRide, 321)
check("the points follow the head bone every frame (the horse moves, the head moves)", math.abs(nodes[halter.nodes[S / 2 + 1]].pos[1] - (5 - 0.043 - (0.119 + m + 0.2 * 0.14) * k)) < 1e-9 and math.abs(nodes[halter.nodes[1]].pos[2] - (3 + 0.43)) < 1e-9)
HorseRope.halterOffset = { 0, 0, 0.35 }
HorseRope.sync(halterRide, 321)
check("the offset moves the whole halter sideways in the head bone's space (a test: to see it beside the head), the knot with it", math.abs(nodes[halter.nodes[1]].pos[3] - (nodes[832].pos[3] + 0.35)) < 1e-9 and math.abs(nodes[halter.chin].pos[3] - (nodes[832].pos[3] + 0.35)) < 1e-9)
check("hdLead halteroffset sets it, and without numbers says how", commands.hdLead("halteroffset", "0", "0", "0"):find("offset by 0.000", 1, true) ~= nil and HorseRope.halterOffset[3] == 0 and commands.hdLead("halteroffset"):find("usage: hdLead halteroffset", 1, true) ~= nil)
HorseRope.sync(halterRide, 321)
nodes[832].pos = { 0, 2, 1 }
-- gravity: the top of a loop lies on the skin, below the head the rope hangs slack along world-down
HorseRope.remove(halterRide)
HorseRope.halter.nose.slack, HorseRope.halter.crown.slack = 0.012, 0.025
halterRide = { vehicle = tackVehicle }
HorseRope.sync(halterRide, 321)
halter = halterRide.halter
local topNow, bottomNow = nodes[halter.nodes[1]].pos, nodes[halter.nodes[S / 2 + 1]].pos
check("the slack: the top of the noseband is exactly where it was (weight 0), its bottom hangs 0.012 lower along world-down, the front ring's point (120 degrees round: weight 0.75) 0.009",
    math.abs(topNow[2] - top[2]) < 1e-9 and math.abs(bottomNow[2] - (bottom[2] - 0.012)) < 1e-9 and math.abs(nodes[halter.nodes[5]].pos[2] - (side[2] - 0.009)) < 1e-9)
local crownBottomNow = nodes[halter.nodes[30]].pos
check("... the crown's under-throat point 0.025 lower, its top on the skin", math.abs(crownBottomNow[2] - (crownBottom[2] - 0.025)) < 1e-9 and math.abs(nodes[halter.nodes[29]].pos[2] - crownTop[2]) < 1e-9)
worldDirectionToLocal = function(node, x, y, z) return 0, 0, -1 end                              -- a head turned so that world-down is the bone's -z
HorseRope.sync(halterRide, 321)
check("the slack follows world-down in the head's own space: with the head turned it hangs along the bone's -z, not -y", math.abs(nodes[halter.nodes[S / 2 + 1]].pos[3] - (bottom[3] - 0.012)) < 1e-9 and math.abs(nodes[halter.nodes[S / 2 + 1]].pos[2] - bottom[2]) < 1e-9)
worldDirectionToLocal = function(node, x, y, z) return x, y, z end
check("hdLead halter slack sets the hang of both loops, and says how without numbers", commands.hdLead("halter", "slack", "0.01", "0.02"):find("slack is 0.010", 1, true) ~= nil and HorseRope.halter.nose.slack == 0.01 and HorseRope.halter.crown.slack == 0.02
    and commands.hdLead("halter", "slack"):find("usage: hdLead halter slack", 1, true) ~= nil)
HorseRope.halter.nose.slack, HorseRope.halter.crown.slack = savedSlack[1], savedSlack[2]
HorseRope.sync(halterRide, 321)
check("the cheek strap runs from the noseband's own ring (its point towards the back: the neighbours of the side point are the ring's top and bottom, the strap leaves at the back) through two points round the cheek to the crown ring",
    halter.pieces[46].linkNode == halter.nodes[20] and halter.targets[46] == halter.nodes[46] and halter.pieces[47].linkNode == halter.nodes[46] and halter.targets[47] == halter.nodes[47]
    and halter.pieces[67].linkNode == halter.nodes[28])
check("the strap along the bottom: each side a piece from the chin (the bottom of the noseband, where the lead is tied) to the lower end of the strap down the cheek (its last point before the one under the jaw)",
    halter.pieces[49].linkNode == halter.nodes[7] and halter.targets[49] == halter.nodes[37] and halter.pieces[70].linkNode == halter.nodes[7] and halter.targets[70] == halter.nodes[54])
check("the cheek ring and the front ring are the same size (radius 0.016)", HorseRope.halter.ring.radius == HorseRope.halter.ring.noseRadius and HorseRope.halter.ring.radius == 0.016)
check("the noseband passes through its rings (low on the nose, 120 degrees round): the piece from above ends on the ring's upper-front point, the piece to the bottom starts on the ring's back point, not on the (unused) ring vertex",
    halter.pieces[4].linkNode == halter.nodes[4] and halter.targets[4] == halter.nodes[14] and halter.pieces[5].linkNode == halter.nodes[17] and halter.targets[5] == halter.nodes[6])
check("the chin knot is the bottom of the noseband, and it is what the lead is tied to", halter.chin == halter.nodes[S / 2 + 1] and HorseRope.chins[tackVehicle] == halter.chin and HorseRope.targetNodeOf(tackVehicle) == halter.chin)
check("the halter is made of rope on the bare horse: the tack stays off", #order == orderBefore)
check("... and nothing is tied before the shapes have loaded", halter.tied[1] == nil)
loadAll()
HorseRope.sync(halterRide, 321)
local allTied = true
for i, piece in ipairs(halter.pieces) do
    allTied = allTied and halter.tied[i] == true and piece.targetNode == halter.targets[i] and piece.activeDirty == true and piece.visibility == true
end
check("once loaded every piece is tied to its next point, active like the lead's pieces (the rope code re-reads the points every frame)", allTied)
check("the lead's last piece is tied to the chin knot", ropes[#ropes].targetNode == halter.chin)
HorseRope.remove(halterRide)
check("the horse is let go: the halter's pieces and points are deleted, and the horse does not keep a chin knot", halterRide.halter == nil and halter.pieces[1].deleted == true and gone[halter.nodes[1]] == true and gone[halter.nodes[#halter.nodes]] == true and HorseRope.chins[tackVehicle] == nil)
check("the halter logs its own report about two seconds after it was built (no need to type a command)", (function()
    local ride = { vehicle = tackVehicle }
    HorseRope.style = "halter"
    log = {}
    for _ = 1, HorseRope.HALTER_REPORT_FRAMES + 5 do HorseRope.sync(ride, 321) end
    local reports = 0
    for _, line in ipairs(log) do if line:find("halter report", 1, true) then reports = reports + 1 end end
    HorseRope.remove(ride)
    return reports == 1
end)())
check("hdLead halterinfo reports pieces, loaded, tied and where things are (to see why a halter does not show)", (function()
    local ride = { vehicle = tackVehicle }
    HorseRope.sync(ride, 321)
    local text = HorseRope.halterReport({ ride })
    HorseRope.remove(ride)
    return text:find("halter: 70 pieces", 1, true) ~= nil and text:find("the chin knot: world", 1, true) ~= nil and HorseRope.halterReport({}) == "no horse is led" and HorseRope.halterReport({ { vehicle = tackVehicle, halterTries = 5 } }):find("without a halter", 1, true) ~= nil
end)())
check("hdLead halter moves a loop (and rebuilds the halter)", commands.hdLead("halter", "nose", "0.36", "-0.05", "0.13", "0.1"):find("nose loop is at y 0.360", 1, true) ~= nil and HorseRope.halter.nose.y == 0.36 and HorseRope.halter.nose.lateral == 0.1)
check("hdLead halter with missing numbers says how to use it", commands.hdLead("halter", "nose", "1"):find("usage: hdLead halter", 1, true) ~= nil)
HorseRope.halter.nose.y, HorseRope.halter.nose.centre, HorseRope.halter.nose.vertical, HorseRope.halter.nose.lateral = 0.43, -0.043, 0.119, 0.085
local boneless = { vehicle = { rootNode = 620, spec_rideable = { leftReinNode = 701 } } }
HorseRope.sync(boneless, 321)
check("a horse without a head bone yet (just loaded): the halter is tried again, not given up on the first frame", boneless.halter == nil and boneless.halterFailed == nil and boneless.halterTries == 1)
for _ = 1, 200 do HorseRope.sync(boneless, 321) end
local said = 0
for _, line in ipairs(log) do if line:find("rope halter could not be built", 1, true) then said = said + 1 end end
check("... after about three seconds it is given up, said once, and the lead goes to the rein node", boneless.halter == nil and boneless.halterFailed == true and said == 1 and HorseRope.targetNodeOf(boneless.vehicle) == 701)
local lateBone = { rootNode = 840, spec_rideable = {} }
nodes[840] = { name = "lateHorse", pos = { 0, 0, 0 }, children = {} }
local lateRide = { vehicle = lateBone }
HorseRope.sync(lateRide, 321)
check("a horse whose model is not complete: no halter on the first frame", lateRide.halter == nil)
nodes[840].children = { 841 }
nodes[841] = { name = "Head_M", pos = { 0, 2, 1 }, children = {} }
HorseRope.sync(lateRide, 321)
check("... and when the head bone is there a frame later the halter is built", lateRide.halter ~= nil and #lateRide.halter.pieces == 70)
HorseRope.remove(lateRide)
HorseRope.remove(boneless)
check("hdLead style halter is accepted", commands.hdLead("style", "halter"):find("rope halter", 1, true) ~= nil and HorseRope.style == "halter")
HorseRope.style = "rope"

-- the harness: rope pieces on the horse's body bones, put on and taken off with the harness tool
dofile("scripts/HorseHarness.lua")
do
local boneNames = { "Root_M", "RootPart1_M", "Spine1_M", "Chest_M" }
nodes[860] = { name = "harnessHorse", pos = { 12, 0, 12 }, children = { 861 } }
nodes[861] = { name = "skeleton", pos = { 0, 0, 0 }, children = { 862, 863, 864, 865 } }
local boneNode = {}
for i, name in ipairs(boneNames) do
    boneNode[name] = 861 + i
    nodes[861 + i] = { name = name, pos = { 0, 0, 0 }, children = {} }
end
-- a bone at its rest pose: the model's space is the world (localToWorld applies the bone's rest axes, as the game would)
local savedLocalToWorld = localToWorld
localToWorld = function(node, lx, ly, lz)
    local b = HorseHarness.bones[nodes[node].name]
    return b.t[1] + b.x[1] * lx + b.y[1] * ly + b.z[1] * lz, b.t[2] + b.x[2] * lx + b.y[2] * ly + b.z[2] * lz, b.t[3] + b.x[3] * lx + b.y[3] * ly + b.z[3] * lz
end
local harnessVehicle = { rootNode = 860 }
local harnessRide = { vehicle = harnessVehicle, harness = true }
local piecesBefore2 = #ropes
HorseHarness.sync(harnessRide)
local rig = harnessRide.rig
check("the harness is built on a horse with the four body bones", rig ~= nil)
check("pieces: collar 12, 2 collar rings of 6, girth 18, 2 tug rings, pad 2, loin 4, hip straps 2 x 6, 2 breeching rings, breeching 2 x 5, traces 2 x 6 (they end on the hook ring), the hook ring 6, the false martingale 6, the back band 16, the neck strap 3 = 137 pieces on 126 points (the two trace ends are gone, the ring's 6 points and its middle are new)",
    #rig.pieces == 137 and #rig.nodes == 126 and #ropes == piecesBefore2 + 137)
check("the harness has ONE fixed hook: a middle node and the ring's rear point (a tow bar starts there), both among its points, hanging under the world root", rig.hookNode ~= nil and rig.hookRear ~= nil and rig.hookNode ~= rig.hookRear and nodes[rig.hookNode].parent == 1 and nodes[rig.hookRear].parent == 1 and rig.traceEnds == nil)
check("the points hang under the world root", nodes[rig.nodes[1]].parent == 1)
-- round trip: a bone at its rest pose puts every point where the model measured it
local padMiddle
for i, node in ipairs(rig.nodes) do
    local p = nodes[node].pos
    if math.abs(p[1]) < 1e-3 and math.abs(p[2] - 1.655) < 1e-3 and math.abs(p[3] - 0.20) < 1e-3 then padMiddle = true end
end
check("a point of the saddle pad is where the model says (0, 1.655, 0.20): the bone-space conversion round-trips", padMiddle == true)
local croup = HorseHarness.spec.loin.points[#HorseHarness.spec.loin.points]
local foundCroup = false
for _, node in ipairs(rig.nodes) do
    local p = nodes[node].pos
    if math.abs(p[1]) < 1e-3 and math.abs(p[2] - croup[2]) < 1e-3 and math.abs(p[3] - croup[3]) < 1e-3 then foundCroup = true end
end
check("... also on another bone (the croup on Root_M)", foundCroup)
-- the false martingale and the back band
local function nodeAt(x, y, z)
    for _, node in ipairs(rig.nodes) do
        local p = nodes[node].pos
        if math.abs(p[1] - x) < 1e-3 and math.abs(p[2] - y) < 1e-3 and math.abs(p[3] - z) < 1e-3 then return node end
    end
end
local function pieceBetween(a, b)
    for i, rope in ipairs(rig.pieces) do
        if (rope.linkNode == a and rig.targets[i] == b) or (rope.linkNode == b and rig.targets[i] == a) then return i end
    end
end
local girthBottom, lastMg = nodeAt(0, HorseHarness.spec.girth.bottom, HorseHarness.spec.girth.z), nodeAt(0, 0.89, 0.42)
check("the false martingale ends on the girth's bottom point (the underside, on the midline)", girthBottom ~= nil and lastMg ~= nil and pieceBetween(lastMg, girthBottom) ~= nil)
local chain4, prev = true, nil
for _, p in ipairs(HorseHarness.spec.martingale.points) do
    local n = nodeAt(0, p[2], p[3])
    chain4 = chain4 and n ~= nil and (prev == nil or pieceBetween(prev, n) ~= nil)
    prev = n
end
check("... through five points on the midline from the chest down to the belly, each joined to the next", chain4)
local collarBottom = nil
for i, rope in ipairs(rig.pieces) do
    local p = nodes[rope.linkNode].pos
    if rig.targets[i] == nodeAt(0, 1.06, 0.93) and math.abs(p[1]) < 1e-3 and p[2] > 1.1 and p[3] > 0.9 then collarBottom = rope.linkNode end
end
check("... and starts on the bottom point of the collar (the first point's other neighbour is a collar point at the point of the chest)", collarBottom ~= nil)
local neckA, neckB = nodeAt(0, 1.77, 0.50), nodeAt(0, 1.725, 0.40)
local padFront = nodeAt(0, HorseHarness.spec.pad.y, 0.30)
check("the neck strap runs from the collar's top (the point at the withers) over two points along the crest to the front end of the pad", neckA ~= nil and neckB ~= nil and padFront ~= nil
    and pieceBetween(neckA, neckB) ~= nil and pieceBetween(neckB, padFront) ~= nil and (function()
        for i, rope in ipairs(rig.pieces) do
            local p = nodes[rope.linkNode].pos
            if (rig.targets[i] == neckA or rope.linkNode == neckA) and nodes[(rope.linkNode == neckA) and rig.targets[i] or rope.linkNode].pos[2] > 1.7 and nodes[(rope.linkNode == neckA) and rig.targets[i] or rope.linkNode].pos[3] > 0.55 then return true end
        end
        return false
    end)())
local bb = HorseHarness.spec.backband
local bbTop, bbSide = nodeAt(0, bb.top, bb.z), nodeAt(bb.profile[4][1], bb.profile[4][2], bb.z)
local bbMirror = nodeAt(-bb.profile[4][1], bb.profile[4][2], bb.z)
check("the back band is a closed loop round the barrel behind the girth: its top, its widest side and the mirrored side are points, 16 pieces", bbTop ~= nil and bbSide ~= nil and bbMirror ~= nil and pieceBetween(bbTop, nodeAt(bb.profile[7][1], bb.profile[7][2], bb.z)) ~= nil
    and pieceBetween(nodeAt(0, bb.bottom, bb.z), nodeAt(bb.profile[1][1], bb.profile[1][2], bb.z)) ~= nil and pieceBetween(nodeAt(0, bb.bottom, bb.z), nodeAt(-bb.profile[1][1], bb.profile[1][2], bb.z)) ~= nil)
local steel = 0
for _, rope in ipairs(rig.pieces) do steel = steel + (rope.rfMaterialDone and 1 or 0) end
check("the seven rings (collar 2, tugs 2, breeching 2, the hook) of six pieces are steel, the straps are hemp", steel == 42)
-- the hitch hook: ONE fixed point on the hip bone at its model place, no slack (it does not hang); both traces end on the same point of its ring (a V that meets at the hook)
local hk = HorseHarness.spec.hook
local hp = nodes[rig.hookNode].pos
check("the hook is one fixed point at its model place, not hanging (no slack)", math.abs(hp[1] - hk.at[1]) < 1e-3 and math.abs(hp[2] - hk.at[2]) < 1e-3 and math.abs(hp[3] - hk.at[3]) < 1e-3)
-- the ring rides on a drawbar eye that a wagon holds (hookFollow): exactly on it, whatever the offset, and back on the bone when it lets go
nodes[9001] = { name = "eye", pos = { hp[1] + 0.3, hp[2] - 0.2, hp[3] - 0.5 }, children = {} }
local hearRearBefore = nodes[rig.hookRear].pos
rig.hookFollow = 9001
for _ = 1, 60 do HorseHarness.place(rig) end
local hf, hr = nodes[rig.hookNode].pos, nodes[rig.hookRear].pos
check("the hook ring follows the eye it is given: its middle is exactly on it", math.abs(hf[1] - (hp[1] + 0.3)) < 1e-3 and math.abs(hf[2] - (hp[2] - 0.2)) < 1e-3 and math.abs(hf[3] - (hp[3] - 0.5)) < 1e-3)
check("... and the whole ring moved with it (its rear point by the same way)", math.abs(hr[1] - hearRearBefore[1] - 0.3) < 1e-3 and math.abs(hr[3] - hearRearBefore[3] + 0.5) < 1e-3)
nodes[9001].pos = { hp[1] - 0.4, hp[2], hp[3] - 1 }
HorseHarness.place(rig)
check("the eye moves: the ring is on it in the very next frame (no lag)", math.abs(nodes[rig.hookNode].pos[1] - (hp[1] - 0.4)) < 1e-3 and math.abs(nodes[rig.hookNode].pos[3] - (hp[3] - 1)) < 1e-3)
rig.hookFollow = nil
for _ = 1, 80 do HorseHarness.place(rig) end
check("let go: the ring is back on the hip bone", math.abs(nodes[rig.hookNode].pos[1] - hp[1]) < 1e-3 and math.abs(nodes[rig.hookNode].pos[3] - hp[3]) < 1e-3)
local tally = {}
for i = 1, #rig.pieces do tally[rig.targets[i]] = (tally[rig.targets[i]] or 0) + 1 end
local meets = 0
for node, count in pairs(tally) do
    local q = nodes[node].pos
    if count == 3 and math.sqrt((q[1] - hp[1]) ^ 2 + (q[2] - hp[2]) ^ 2 + (q[3] - hp[3]) ^ 2) < hk.radius * 1.2 then
        meets = meets + 1
    end
end
check("both traces end on the same point of the hook ring (that point is the target of the ring's own piece and of two traces)", meets == 1)
-- sync ties the pieces once they have loaded
check("nothing is tied before the shapes have loaded", rig.tied[1] == nil)
loadAll()
HorseHarness.sync(harnessRide)
local allTied = true
for i, piece in ipairs(rig.pieces) do
    allTied = allTied and rig.tied[i] == true and piece.targetNode == rig.targets[i] and piece.visibility == true
end
check("once loaded every piece is tied to its next point", allTied)
-- off: taken off
harnessRide.harness = false
HorseHarness.sync(harnessRide)
check("the harness flag off: the pieces and points are deleted", harnessRide.rig == nil and rig.pieces[1].deleted == true and gone[rig.nodes[1]] == true)
harnessRide.harness = true
HorseHarness.sync(harnessRide)
local rig2 = harnessRide.rig
check("... and on again builds it again", rig2 ~= nil and rig2 ~= rig)
HorseRope.remove(harnessRide)
check("the horse is let go (HorseRope.remove): the harness goes with it, the flag stays for a rebuild", harnessRide.rig == nil and harnessRide.harness == true and rig2.pieces[1].deleted == true)
-- a horse whose model is not complete
nodes[864].name = "Spine"
HorseHarness.sync(harnessRide)
check("a missing bone: no harness yet, tried again", harnessRide.rig == nil and harnessRide.rigTries == 1)
for _ = 1, HorseHarness.TRIES do HorseHarness.sync(harnessRide) end
check("... given up after about three seconds and said once", harnessRide.rigFailed == true)
nodes[864].name = "Spine1_M"
harnessRide.rigFailed, harnessRide.rigTries = nil, nil
HorseRope.remove(harnessRide)
-- leather gear: flat straps with the skin's normal, round padded pieces, steel rings
HorseRope.gear = "leather"
HorseRope.remove(harnessRide)
HorseHarness.sync(harnessRide)
do
    local lrig = harnessRide.rig
    local flat, roundLeather, plain, steelPieces, normalsOk, widthsOk = 0, 0, 0, 0, true, true
    for _, rope in ipairs(lrig.pieces) do
        if rope.strap then
            flat = flat + 1
            local n = math.sqrt(rope.strap.lx ^ 2 + rope.strap.ly ^ 2 + rope.strap.lz ^ 2)
            normalsOk = normalsOk and math.abs(n - 1) < 1e-3 and rope.strap.bone ~= nil and rope.update == HorseRope.strapUpdate
            widthsOk = widthsOk and rope.diameter == rope.strap.width and rope.strap.thickness <= rope.strap.width * 0.2 + 1e-9
        elseif rope.leather then roundLeather = roundLeather + 1
        elseif rope.rfMaterialDone then steelPieces = steelPieces + 1
        else plain = plain + 1 end
    end
    check("leather gear: 81 flat straps, the collar and the pad (14 pieces) round leather, the seven rings (42 pieces) steel, nothing plain rope", flat == 81 and roundLeather == 14 and steelPieces == 42 and plain == 0)
    check("... every strap has a unit skin normal in its bone's space, a bone, the strap update, a shader size equal to its width (the shader's size is a diameter), and a thickness of at most a fifth of the width", normalsOk and widthsOk)
    local girthStrap
    for _, rope in ipairs(lrig.pieces) do
        if rope.strap and rope.strap.width == HorseHarness.spec.girth.strap then girthStrap = rope end
    end
    check("the girth's strap is the width in the spec (5 cm)", girthStrap ~= nil and girthStrap.strap.width == 0.05)
    -- the halter in leather: straps 2 cm wide, the rings steel
    local harnessL2W = localToWorld
    localToWorld = savedLocalToWorld                                          -- (the head bone of the fake halter horse only has a position)
    local lh = HorseRope.buildHalter(tackVehicle)
    localToWorld = harnessL2W
    local hFlat, hSteel = 0, 0
    for _, rope in ipairs(lh.pieces) do
        if rope.strap then hFlat = hFlat + 1 elseif rope.rfMaterialDone then hSteel = hSteel + 1 end
    end
    local sample
    for i, rope in ipairs(lh.pieces) do
        if rope.strap and lh.targets[i] == lh.nodes[2] then sample = rope end                  -- (the noseband piece from the top point to the next)
    end
    check("the halter in leather: 38 flat 2 cm straps and 32 steel ring pieces; a piece on the top of the head has the normal +x (up), one at the side +z", lh ~= nil and hFlat == 38 and hSteel == 32 and sample ~= nil and sample.strap.width == 0.02
        and sample.strap.lx > 0.9)
    HorseRope.destroyHalter({ halter = lh, vehicle = tackVehicle })
end
HorseRope.gear = "rope"
HorseRope.remove(harnessRide)
-- the console
check("hdHarness set changes a measurement and the harness is rebuilt", commands.hdHarness("set", "collar.a", "0.4"):find("collar.a is 0.4", 1, true) ~= nil and HorseHarness.spec.collar.a == 0.4)
check("... a path inside a list too", commands.hdHarness("set", "girth.profile.3.1", "0.3"):find("is 0.3", 1, true) ~= nil and HorseHarness.spec.girth.profile[3][1] == 0.3)
check("... a path that is not a number says so, and so does a missing value", commands.hdHarness("set", "collar.nothing", "1"):find("no such number", 1, true) ~= nil and commands.hdHarness("set", "collar.a"):find("usage: hdHarness set", 1, true) ~= nil)
check("hdHarness info lists the measurements, reset puts the defaults back", commands.hdHarness("info"):find("collar.a = 0.4", 1, true) ~= nil and commands.hdHarness("reset"):find("defaults", 1, true) ~= nil and HorseHarness.spec.collar.a == 0.40 and HorseHarness.spec.girth.profile[3][1] == 0.29)
-- the tool
local ridesBefore, commandBefore, distanceBefore = HorseLead.rides, HorseLead.command, HorseLead.nearestHorseDistance
HorseLead.rides = { { vehicle = harnessVehicle } }
g_localPlayer = { rootNode = 900 }
nodes[900].pos = { 12, 0, 13 }                                                       -- 1 m from the led horse
check("the harness tool with a led horse beside you puts the harness on it", HorseLead.harness():find("harness on", 1, true) ~= nil and HorseLead.rides[1].harness == true)
check("... and the same action takes it off, the horse stays led", HorseLead.harness() == "harness off" and HorseLead.rides[1].harness == false and #HorseLead.rides == 1)
nodes[900].pos = { 12, 0, 20 }                                                       -- 8 m from it
HorseLead.nearestHorseDistance = function() return 6 end
check("no horse within 4 m (a led one 8 m away does not count): it does not summon one", HorseLead.harness():find("no horse within 4 m", 1, true) ~= nil and HorseLead.rides[1].harness == false)
HorseLead.rides = {}
HorseLead.nearestHorseDistance = function() return 2 end
HorseLead.command = function() HorseLead.rides[#HorseLead.rides + 1] = { vehicle = harnessVehicle }; return "taken" end
nodes[900].pos = { 12, 0, 13 }
check("with no horse led, the nearest horse within reach is taken as a horse that STAYS and harnessed: no leash, no halter, it follows nobody",
    HorseLead.harness():find("without a halter", 1, true) ~= nil and #HorseLead.rides == 1 and HorseLead.rides[1].leash == nil and HorseLead.rides[1].stay == true and HorseLead.rides[1].harness == true)
check("taking the harness off a horse that only stays gives it back to its pasture", HorseLead.harness():find("goes back to its pasture", 1, true) ~= nil and #HorseLead.rides == 0)
-- independent of the halter: a led horse gets both
HorseLead.rides = { { vehicle = harnessVehicle, leash = true } }
check("a horse on the leash (it wears the halter) that is touched with the harness gets both, and says so", HorseLead.harness():find("halter too", 1, true) ~= nil and HorseLead.rides[1].harness == true and HorseLead.rides[1].leash == true and HorseLead.rides[1].stay == nil)
check("... taking the harness off leaves it led", HorseLead.harness() == "harness off" and #HorseLead.rides == 1 and HorseLead.rides[1].leash == true)
-- the leash takes a horse that stays in its harness
HorseLead.rides = { { vehicle = harnessVehicle, stay = true, harness = true } }
check("the leash tool takes the horse that stays in its harness: it gets the halter and follows, and keeps the harness", HorseLead.leash():find("leashed", 1, true) ~= nil and HorseLead.rides[1].leash == true and HorseLead.rides[1].stay == nil and HorseLead.rides[1].harness == true)
-- a horse that wears the harness and is mounted: the ride stays, the harness stays (it is not rebuilt, not deleted), only the halter and the lead go; when the rider gets off it stands in its harness again
MOUNTENTERED = true
MOUNTHORSE = { rootNode = 860, getIsEntered = function() return MOUNTENTERED end, getIsControlled = function() return MOUNTENTERED end, spec_rideable = { inputValues = {}, currentTurnAngle = 0 } }
MOUNTRIDE = { vehicle = MOUNTHORSE, leash = true, harness = true, halter = { pieces = {}, nodes = {}, tied = {} } }
HorseLead.rides = { MOUNTRIDE }
MOUNTBEFORE = #ropes
HorseHarness.sync(MOUNTRIDE)
MOUNTRIG, MOUNTBUILT = MOUNTRIDE.rig, #ropes - MOUNTBEFORE
HorseLead.updateRide(50)
check("(the harness was on the horse before it was mounted)", MOUNTBUILT > 100 and MOUNTRIG ~= nil)
check("a harnessed horse somebody mounts: the ride stays, the harness is neither rebuilt nor deleted", #HorseLead.rides == 1 and MOUNTRIDE.rig == MOUNTRIG and #ropes == MOUNTBEFORE + MOUNTBUILT)
check("... it is ridden: no leash, no halter (the saddle has the reins), no virtual rider", MOUNTRIDE.ridden == true and MOUNTRIDE.leash == nil and MOUNTRIDE.halter == nil and MOUNTHORSE.rfVirtualRider == nil)
HorseLead.updateRide(50)
check("... and stays so while the rider sits there", #HorseLead.rides == 1 and MOUNTRIDE.ridden == true and MOUNTRIDE.rig == MOUNTRIG)
MOUNTENTERED = false
HorseLead.updateRide(50)
check("the rider gets off: the horse stands where it is, in its harness, with the virtual rider again", MOUNTRIDE.ridden == nil and MOUNTRIDE.stay == true and MOUNTHORSE.rfVirtualRider == true and #HorseLead.rides == 1 and MOUNTRIDE.rig == MOUNTRIG)
-- a horse WITHOUT a harness that is mounted is given up as before (nothing to keep)
MOUNTENTERED = true
HorseLead.rides = { { vehicle = MOUNTHORSE, leash = true } }
HorseLead.updateRide(50)
check("a horse without a harness that somebody mounts: the ride is dropped, as before", #HorseLead.rides == 0)
MOUNTENTERED = false
-- letting go of the leash does not give a harnessed horse back
HorseLead.rides = { { vehicle = harnessVehicle, leash = true, harness = true }, { vehicle = { rootNode = 860 }, leash = true } }
local letGo = HorseLead.releaseFlagged("leash")
check("letting go of the leash: the horse without a harness is given back, the harnessed one stays where it is wearing it (no leash, no halter)", letGo == 2 and #HorseLead.rides == 1 and HorseLead.rides[1].harness == true and HorseLead.rides[1].leash == nil and HorseLead.rides[1].stay == true)
HorseLead.rides = {}
-- the halter's release leaves the harness rig and the trailer hitched to it alone (it was destroyed and rebuilt, and the hitch let go)
HITCHCALLS = 0
HorseHitch = { release = function(r) HITCHCALLS = HITCHCALLS + 1; return false end }
KEEP = { vehicle = harnessVehicle, leash = true, harness = true }
HorseLead.rides = { KEEP }
HorseHarness.sync(KEEP)
KEEPRIG = KEEP.rig
HorseLead.releaseFlagged("leash")
check("letting go of the halter leaves the harness rig and the trailer hitch alone (the horse keeps standing in the harness)", KEEPRIG ~= nil and KEEP.rig == KEEPRIG and HITCHCALLS == 0 and KEEP.stay == true and KEEP.leash == nil)
HorseLead.rides = {}
HorseHarness.destroy(KEEP)
check("taking the harness off (destroy) lets the trailer go", HITCHCALLS == 1)
HorseHitch = nil
-- let go outside a pasture: the halter stays on (only the rope goes), inside a pasture it comes off and the horse goes back
HALTER = { pieces = {}, nodes = {}, tied = {}, targets = {} }
STAYHORSE = { rootNode = 860, isDeleted = false, spec_rideable = { inputValues = {}, currentTurnAngle = 0 } }
HALTERED = { vehicle = STAYHORSE, leash = true, halter = HALTER, halterGear = "leather" }
HorseLead.rides = { HALTERED }
g_currentMission.husbandrySystem.getHusbandryInRideableRange = function() return false end
HALTERMSG = HorseLead.leash("rope")
check("let go outside a pasture: the halter stays on (the ride stays, no leash, no rope), and the message says so", HALTERED.halter == HALTER and HALTERED.stay == true and HALTERED.halterOn == true and HALTERED.leash == nil and #HorseLead.rides == 1 and HALTERMSG:find("halter stays on", 1, true) ~= nil)
HorseLead.updateRide(50)
check("... and the halter is still kept up every frame (no rope)", HALTER.frames ~= nil and HALTERED.rope == nil)
check("the harness tool does not give a horse that keeps its halter back when the harness goes off", (function() HALTERED.harness = true; local m = HorseLead.harness(); return m == "harness off" and #HorseLead.rides == 1 end)())
HALTERED.harness = nil
check("the leash takes the horse that stands there in its halter: it follows again, the halter on it keeps its gear", HorseLead.leash("rope"):find("leashed", 1, true) ~= nil and HALTERED.leash == true and HALTERED.halterOn == nil and HALTERED.stay == nil and HALTERED.halterGear == "leather")
g_currentMission.husbandrySystem.getHusbandryInRideableRange = function() return true end
HorseLead.leash("rope")
check("let go in the range of a pasture: the halter comes off and the horse is given back, as before", HALTERED.halter == nil and #HorseLead.rides == 0)
HALTERED = { vehicle = STAYHORSE, leash = true, halter = { pieces = {}, nodes = {}, tied = {} } }
HorseLead.rides = { HALTERED }
g_currentMission.husbandrySystem.getHusbandryInRideableRange = nil
HorseLead.leash("rope")
check("when the game cannot say where the horse is, it is given back, as before", HALTERED.halter == nil and #HorseLead.rides == 0)
HorseLead.rides = {}
HorseLead.command = function() return "no horse nearby" end
check("... and when no horse can be taken it says why", HorseLead.harness() == "no horse nearby")
HorseLead.rides, HorseLead.command, HorseLead.nearestHorseDistance = ridesBefore, commandBefore, distanceBefore
localToWorld = savedLocalToWorld
end

-- the rope's tint
check("the default tint is none (a tint through the emissive colour looks like candy stripes): the pieces get the game's own zero", HorseRope.tint[1] == 0 and HorseRope.tint[4] == 0 and ropes[#ropes].emissiveColor ~= nil and ropes[#ropes].emissiveColor[4] == 0)
local shaderCalls = {}
setShaderParameter = function(node, name, a, b, c, d) shaderCalls[#shaderCalls + 1] = { node, name, a, b, c, d } end
local lastPiece = ropes[#ropes]
lastPiece.ropeId = 9001
check("hdLead tint sets the tint for new and existing pieces (shader parameter ropeEmissiveColor, alpha 1)", commands.hdLead("tint", "0.5", "0.4", "0.3"):find("tint is 0.50 0.40 0.30", 1, true) ~= nil
    and HorseRope.tint[1] == 0.5 and lastPiece.emissiveColor[2] == 0.4 and shaderCalls[#shaderCalls][2] == "ropeEmissiveColor" and shaderCalls[#shaderCalls][3] == 0.5 and shaderCalls[#shaderCalls][6] == 1)
check("hdLead tint with a missing number says how to use it", commands.hdLead("tint", "1"):find("usage: hdLead tint", 1, true) ~= nil)
HorseRope.setTint(0, 0, 0)
HorseRope.tint = { 0, 0, 0, 0 }

-- the rope's material: hemp colour and a matte gloss map, our own textures, put on each piece once its shape has loaded
local matCalls = {}
getMaterial = function(node, index) return 500 end
setMaterialDiffuseMapFromFile = function(material, file, a, b, c) matCalls[#matCalls + 1] = { "diffuse", file }; return material + 1 end
setMaterialGlossMapFromFile = function(material, file, a, b, c) matCalls[#matCalls + 1] = { "gloss", file }; return material + 10 end
setMaterial = function(node, material, index) matCalls[#matCalls + 1] = { "set", node, material } end
check("the default material is hemp", HorseRope.material == "hemp" and HorseRope.modDirectory == "mods/FS25_HorseDynamics/")
local pieceA, pieceB = { ropeId = 7001 }, { ropeId = 7002 }
HorseRope.applyMaterial({ })
check("a piece whose shape has not loaded gets nothing yet (and is not marked done)", #matCalls == 0)
HorseRope.applyMaterial(pieceA)
HorseRope.applyMaterial(pieceB)
check("a loaded piece gets a copy of the game's rope material with our diffuse and our gloss map (files in the mod's textures folder), put on its shape",
    matCalls[1][1] == "diffuse" and matCalls[1][2] == "mods/FS25_HorseDynamics/textures/rope_hemp_diffuse.dds" and matCalls[2][1] == "gloss" and matCalls[2][2] == "mods/FS25_HorseDynamics/textures/rope_hemp_specular.dds"
    and matCalls[3][1] == "set" and matCalls[3][2] == 7001 and matCalls[3][3] == 511)
check("... every piece gets a material of its own (an id made for an earlier piece was stale in the game): the second piece makes its own and puts it on", #matCalls == 6 and matCalls[4][1] == "diffuse" and matCalls[5][1] == "gloss" and matCalls[6][1] == "set" and matCalls[6][2] == 7002)
HorseRope.applyMaterial(pieceA)
check("... and a piece is done once", #matCalls == 6 and pieceA.rfMaterialDone == true)
HorseRope.material = "steel"
local pieceC = { ropeId = 7003 }
HorseRope.applyMaterial(pieceC)
check("steel: the game's own material is left alone", #matCalls == 6)
HorseRope.material = "hemp"
setMaterialGlossMapFromFile = function() error("no such texture") end
HorseRope.applyMaterial({ ropeId = 7004 })
HorseRope.applyMaterial({ ropeId = 7005 })
local reported = 0
for _, line in ipairs(log) do if line:find("hemp material could not be applied", 1, true) then reported = reported + 1 end end
check("a failing engine call is caught and said once: the rope just stays steel", reported == 1)
setMaterialGlossMapFromFile = function(material, file, a, b, c) matCalls[#matCalls + 1] = { "gloss", file }; return material + 10 end
check("hdLead material hemp|steel switches it, and a wrong name says how", commands.hdLead("material", "steel"):find("steel cable", 1, true) ~= nil and HorseRope.material == "steel"
    and commands.hdLead("material", "hemp"):find("hemp", 1, true) ~= nil and HorseRope.material == "hemp" and commands.hdLead("material", "x"):find("usage: hdLead material", 1, true) ~= nil)
do
-- leather: flat straps
setMaterialNormalMapFromFile = function(material, file) matCalls[#matCalls + 1] = { "normal", file }; return material + 100 end
local scaled = {}
setScale = function(node, x, y, z) scaled[#scaled + 1] = { node, x, y, z } end
local before = #matCalls
HorseRope.applyMaterial({ ropeId = 7100, leather = true, strap = { width = 0.04, thickness = 0.004 } })
check("a leather strap: its tube is scaled thin on its own y axis (thickness over width: 0.1), and it gets the leather diffuse, the leather gloss and a flat normal map instead of the rope's strands",
    #scaled == 1 and scaled[1][1] == 7100 and scaled[1][2] == 1 and math.abs(scaled[1][3] - 0.1) < 1e-9 and scaled[1][4] == 1
    and matCalls[before + 1][2]:find("rope_leather_diffuse.dds", 1, true) ~= nil and matCalls[before + 2][2]:find("rope_leather_specular.dds", 1, true) ~= nil
    and matCalls[before + 3][1] == "normal" and matCalls[before + 3][2]:find("rope_leather_normal.dds", 1, true) ~= nil and matCalls[before + 4][1] == "set")
HorseRope.applyMaterial({ ropeId = 7101, leather = true })
check("a round leather piece (the padded collar): leather material, not scaled", #scaled == 1 and matCalls[#matCalls][1] == "set" and matCalls[#matCalls][2] == 7101)
HorseRope.applyMaterial({ ropeId = 7102 })
check("a plain rope piece in the same game (the lead) is still hemp", matCalls[#matCalls - 2][2]:find("rope_hemp_diffuse.dds", 1, true) ~= nil)
-- the leather look of the base-game prop in a leather tool's hand
do
    nodes[8800] = { name = "leash", children = { 8801, 8802, 8803 } }
    nodes[8801] = { name = "rope01", children = {}, shape = true }
    nodes[8802] = { name = "col", children = {}, shape = true }
    nodes[8803] = { name = "wrapper", children = { 8804 } }
    nodes[8804] = { name = "inner", children = {}, shape = true }
    local before = #matCalls
    local done = HorseRope.leatherProp(8800)
    local sets, files = {}, {}
    for i = before + 1, #matCalls do
        if matCalls[i][1] == "set" then sets[#sets + 1] = matCalls[i][2] else files[#files + 1] = matCalls[i][2] end
    end
    check("the leather prop: every shape but the collision gets the leather material (two shapes, each set once, the collision untouched)", done == 2 and #sets == 2 and sets[1] == 8801 and sets[2] == 8804)
    check("... with the leather diffuse and gloss files", files[1]:find("rope_leather_diffuse.dds", 1, true) ~= nil and files[2]:find("rope_leather_specular.dds", 1, true) ~= nil)
    check("no root, no walk, nothing done", HorseRope.leatherProp(nil) == 0)
end

-- the strap's own update: the tube points at the target and its flat face turns to the skin's normal
do
    local saved = { worldToLocal, localDirectionToWorld, worldDirectionToLocal, setDirection, getWorldTranslation }
    local direction
    worldToLocal = function(node, x, y, z) return x, y, z end
    localDirectionToWorld = function(node, x, y, z) return x, y, z end
    worldDirectionToLocal = function(node, x, y, z) return x, y, z end
    getWorldTranslation = function(node) return 0, 0, 3 end
    setDirection = function(node, dx, dy, dz, ux, uy, uz) direction = { node, dx, dy, dz, ux, uy, uz } end
    local piece = { validTarget = true, referenceFrame = 1, ropeId = 2, targetNode = 3, strap = { bone = 4, lx = 1, ly = 0, lz = 0 }, setLength = function(self, length) self.length = length end }
    for _, id in ipairs({ 1, 2, 3, 4 }) do nodes[id] = nodes[id] or { pos = { 0, 0, 0 }, children = {} } end      -- (the piece's frame, rope and target: there, or the guard skips it)
    HorseRope.strapUpdate(piece, 16)
    check("a strap points its tube at the target (along +z, 3 m) and turns its flat face to the skin's normal, not to world-up", direction ~= nil and direction[1] == 2 and direction[4] == 1 and direction[5] == 1 and direction[6] == 0 and piece.length == 3)
    -- setDirection drops the scale: the strap's flattening is put back after every turn, and the first piece logs the scale it found
    do
        local sc, getCalls = {}, 0
        local savedScale, savedGet = setScale, getScale
        setScale = function(node, x, y, z) sc[#sc + 1] = { node, x, y, z } end
        getScale = function() getCalls = getCalls + 1; return 1, 1, 1 end
        HorseRope.scaleLogged = nil
        piece.strap, piece.rfMaterialDone = { bone = 4, lx = 1, ly = 0, lz = 0, width = 0.02, thickness = 0.004 }, true
        HorseRope.strapUpdate(piece, 16)
        HorseRope.strapUpdate(piece, 16)
        check("a strap is flattened again after every setDirection (y = thickness / width), the scale is read and logged once", #sc == 2 and sc[1][1] == 2 and math.abs(sc[1][3] - 0.2) < 1e-9 and sc[1][2] == 1 and sc[1][4] == 1 and getCalls == 1)
        piece.rfMaterialDone = nil
        HorseRope.strapUpdate(piece, 16)
        check("... but not before its material (and so its first scaling) is done", #sc == 2)
        setScale, getScale = savedScale, savedGet
    end
    piece.strap = nil
    HorseRope.strapUpdate(piece, 16)
    check("a piece without a strap uses world-up as the game does", direction[5] == 0 and direction[6] == 1 and direction[7] == 0)
    piece.validTarget = false
    direction = nil
    HorseRope.strapUpdate(piece, 16)
    check("... and a piece with no valid target does nothing", direction == nil)
    worldToLocal, localDirectionToWorld, worldDirectionToLocal, setDirection, getWorldTranslation = saved[1], saved[2], saved[3], saved[4], saved[5]
end
setScale, setMaterialNormalMapFromFile = nil, nil
getMaterial, setMaterial, setMaterialDiffuseMapFromFile, setMaterialGlossMapFromFile = nil, nil, nil, nil
end

check("hdLead gear leather|rope switches the halter's and the harness's pieces, and a wrong word says how", commands.hdLead("gear", "leather"):find("flat leather straps", 1, true) ~= nil and HorseRope.gear == "leather"
    and commands.hdLead("gear", "rope"):find("round rope", 1, true) ~= nil and HorseRope.gear == "rope" and commands.hdLead("gear", "x"):find("usage: hdLead gear", 1, true) ~= nil)

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
-- the rope of a rider who leads a horse starts at the SIDE of the horse he sits on (not on its back, in the middle)
nodes[962] = { pos = { 0, 0, 0 }, children = {} }
RIDERHORSE = { rootNode = 962 }
g_localPlayer.getCurrentVehicle = function() return RIDERHORSE end
HorseLead.leashSource = nil
RIDERANCHOR = HorseLead.ropeSource()
check("a mounted rider's rope starts at HorseLead.MOUNTED_ANCHOR in the horse's own space, at its side (x beyond the middle line)", RIDERANCHOR ~= nil and nodes[RIDERANCHOR].parent == 962
    and nodes[RIDERANCHOR].pos[1] == HorseLead.MOUNTED_ANCHOR[1] and nodes[RIDERANCHOR].pos[2] == HorseLead.MOUNTED_ANCHOR[2] and nodes[RIDERANCHOR].pos[3] == HorseLead.MOUNTED_ANCHOR[3] and math.abs(HorseLead.MOUNTED_ANCHOR[1]) > 0.3)
-- ... and at the rider's hand when the game has one (the node the reins are linked to), the right hand first
nodes[963], nodes[964] = { pos = { 0, 0, 0 }, children = {} }, { pos = { 0, 0, 0 }, children = {} }
RIDERHORSE.getVehicleCharacter = function() return { playerModel = { thirdPersonRightHandNode = 963, thirdPersonLeftHandNode = 964 } } end
check("a mounted rider's rope starts at his right hand (the game's hand node)", HorseLead.ropeSource() == 963)
RIDERHORSE.getVehicleCharacter = function() return { playerModel = { thirdPersonLeftHandNode = 964 } } end
check("... the left hand when there is no right one", HorseLead.ropeSource() == 964)
RIDERHORSE.getVehicleCharacter = function() return { playerModel = { thirdPersonRightHandNode = 779977 } } end
check("... a hand node that is gone (the character was deleted) is not used: the anchor at the horse's side", HorseLead.ropeSource() == RIDERANCHOR or nodes[HorseLead.ropeSource()].parent == 962)
RIDERHORSE.getVehicleCharacter = function() return nil end
check("... no character at all: the anchor at the horse's side", nodes[HorseLead.ropeSource()].parent == 962)
RIDERHORSE.getVehicleCharacter = nil
g_localPlayer.getCurrentVehicle = nil
-- on foot: the rope starts in the player's hand when the character is seen (third person), else 1.1 m above the capsule's foot
nodes[965], nodes[966] = { pos = { 0, 0, 0 }, children = {} }, { pos = { 0, 0, 0 }, children = {} }
g_localPlayer.graphicsComponent = { model = { thirdPersonRightHandNode = 965, thirdPersonLeftHandNode = 966 } }
g_localPlayer.camera = { isFirstPerson = false }
check("on foot in third person the rope starts at the player's right hand (the node a hand tool is linked to)", HorseLead.ropeSource() == 965)
g_localPlayer.graphicsComponent.model.thirdPersonRightHandNode = nil
check("... the left hand when there is no right one", HorseLead.ropeSource() == 966)
g_localPlayer.camera.isFirstPerson = true
check("in first person (the character is hidden) it is the anchor above the capsule's foot", nodes[HorseLead.ropeSource()].parent == g_localPlayer.rootNode)
g_localPlayer.camera.isFirstPerson = false
g_localPlayer.graphicsComponent = nil
check("without a loaded model: the anchor above the capsule's foot", nodes[HorseLead.ropeSource()].parent == g_localPlayer.rootNode)
g_localPlayer.camera = nil
HorseLead.leashSource = 4242
check("a leash tool in the hand still wins: its own node", HorseLead.ropeSource() == 4242)
HorseLead.leashSource = nil
-- a piece whose node was deleted with a horse is skipped, not updated into an error every frame (a contract mod hands in a ridden and a led horse at once)
FORESTRYUPDATES = 0
ForestryRope.update = function(self, dt) FORESTRYUPDATES = FORESTRYUPDATES + 1 end
GUARDPIECE = HorseRope.createSegment(960, 0.02)
GUARDPIECE.referenceFrame, GUARDPIECE.ropeId = 960, 960
GUARDPIECE:update(16)
check("a rope piece whose nodes are there is updated by the game's own update", FORESTRYUPDATES == 1)
GUARDPIECE.referenceFrame = 777777
GUARDPIECE:update(16)
check("... one whose frame was deleted with a horse is skipped (no error every frame)", FORESTRYUPDATES == 1)
GUARDPIECE.referenceFrame, GUARDPIECE.targetNode = 960, 777777
GUARDPIECE:update(16)
check("... and so is one whose target was deleted", FORESTRYUPDATES == 1)
GUARDSTRAP = HorseRope.createSegment(960, 0.02, { leather = true, strap = { width = 0.02, thickness = 0.004, bone = 960, lx = 1, ly = 0, lz = 0 } })
GUARDSTRAP.referenceFrame, GUARDSTRAP.ropeId, GUARDSTRAP.validTarget, GUARDSTRAP.targetNode = 777777, 960, true, 960
check("a flat strap whose frame is gone is skipped too (the strap's own update would call worldToLocal on it)", pcall(GUARDSTRAP.update, GUARDSTRAP, 16) == true)
ForestryRope.update = nil

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
-- a gate in reach against the horse the click would take: the nearer one wins
local startCalls = 0
HorseLead.command = function() startCalls = startCalls + 1; return "taken" end
local realNearest = HorseLead.nearestHorseDistance
settle(a1, a2)
nodes[900].pos = { 12, 0, 12 }                                           -- the gate's door is 2 m away
HorseLead.nearestHorseDistance = function() return 6 end
check("no horse on the rope, a gate 2 m away and the nearest horse 6 m away: the click is for the gate, no horse is taken", HorseLead.leash() == "gate opens" and startCalls == 0)
settle(a1, a2)
HorseLead.nearestHorseDistance = function() return 1 end
check("... a horse right beside you (1 m) is nearer than the gate: the click takes the horse", HorseLead.leash() == "taken" and startCalls == 1)
HorseLead.nearestHorseDistance = function() return nil end
check("... no horse anywhere: the gate", HorseLead.leash() == "gate closes" and startCalls == 1)
nodes[900].pos = { 40, 0, 12 }                                           -- out of the gate's reach
HorseLead.nearestHorseDistance = function() return 3 end
check("... a gate out of reach and a horse 3 m away: the horse", HorseLead.leash() == "taken" and startCalls == 2)
HorseLead.nearestHorseDistance = function() return 6 end
check("the leash does not summon: the nearest horse 6 m away (beyond the 4 m reach) is not taken, and the message says to walk up to one", HorseLead.leash():find("no horse within 4 m", 1, true) ~= nil and startCalls == 2)
HorseLead.nearestHorseDistance = function() return 4 end
check("... a horse at exactly 4 m is still taken", HorseLead.leash() == "taken" and startCalls == 3)
-- the winch easter egg: with no horse in reach the leash hooks the attacher joint in view (the winch of FS25_WinchTow, published on g_currentMission.winchTow)
do
    local calls = {}
    local winch = { target = nil, pick = function() return calls.pickResult end, hold = function(node) calls[#calls + 1] = "hold " .. tostring(node) end, toggle = function() calls[#calls + 1] = "toggle"; return "hooked" end }
    g_currentMission.winchTow = winch
    L.leashSource = 321
    nodes[900].pos = { 40, 0, 12 }                                       -- (out of the gate's reach)
    HorseLead.nearestHorseDistance = function() return nil end
    calls.pickResult = { vehicle = {} }
    check("no horse anywhere and an attacher joint in view: the leash hooks it (the winch is given the tool's node, then toggled)", HorseLead.leash() == "hooked" and calls[1] == "hold 321" and calls[2] == "toggle")
    HorseLead.nearestHorseDistance = function() return 6 end
    calls = { pickResult = { vehicle = {} } }
    check("a horse 6 m away does not matter: a joint in view is for the winch", HorseLead.leash() == "hooked" and calls[2] == "toggle")
    calls = { pickResult = nil }
    check("no joint in view and a horse 6 m away: the leash says to walk up to a horse, as before", HorseLead.leash():find("no horse within 4 m", 1, true) ~= nil)
    winch.pickLog = function() return calls.logResult end
    HorseLead.nearestHorseDistance = function() return nil end
    calls = { pickResult = nil, logResult = { kind = "log" } }
    check("no joint but a log in view: the leash hooks the log too (no complaint about a horse)", HorseLead.leash() == "hooked" and calls[2] == "toggle")
    winch.pickLog = function() return nil, "that tree still stands: fell it first" end
    calls = { pickResult = nil }
    check("a log in view that cannot be hooked says why, not 'look at the horse'", HorseLead.leash() == "that tree still stands: fell it first")
    winch.pickLog = nil
    HorseLead.nearestHorseDistance = function() return 2 end
    calls = { pickResult = { vehicle = {} } }
    check("a horse within reach wins over a joint in view: the horse is taken", HorseLead.leash() == "taken" and calls[1] == nil)
    winch.target = { vehicle = {} }
    calls = { pickResult = nil }
    check("a hooked vehicle is let go first (the same key), whatever else is near", HorseLead.leash() == "hooked" and calls[1] == "toggle")
    g_currentMission.winchTow = nil
    winch.target = nil
    HorseLead.nearestHorseDistance = function() return nil end
    nodes[900].pos = { 40, 0, 12 }
    check("without the winch mod nothing changes: no horse anywhere is the old answer", HorseLead.leash() == "taken" or HorseLead.leash() == "no horse nearby")
    L.leashSource = nil
end
HorseLead.nearestHorseDistance = realNearest
check("the nearest horse distance is that of the nearest horse of a pasture (here the fake world's horses)", (function() local d = HorseLead.nearestHorseDistance(10, 10); return d ~= nil and d >= 0 and d < 5 end)())
HorseLead.command = realCommand
nodes[900].pos = { 12, 0, 12 }
HorseLead.command(nil, "stop")
check("the horses are given back: the rope is deleted", ropes[1].deleted == true)
leashHorse.isDeleted = true

-- the leash in the hand with no horse on it: a rope held in the hand, draped over it, the ends hanging down: two straight legs and a half circle on top
L.rides = {}
local ropesBefore = #ropes
L.leashSource = 321
nodes[321].pos = { 10, 1.5, 10 }
L.updateRide(50)
local stub = HorseRope.stub
check("the leash in the hand and no horse on it: 15 points and 14 rope pieces (3 + 8 + 3, open: the ends are free), each piece starting at its own point", stub ~= nil and #ropes == ropesBefore + 14 and #stub.nodes == 15 and #stub.pieces == 14 and ropes[#ropes].linkNode == stub.nodes[14])
loadAll()
L.updateRide(50)
local r, legLength = HorseRope.STUB_RADIUS_M, HorseRope.STUB_LEG_M
local leftEnd, arcStart, apex, arcEnd, rightEnd = nodes[stub.nodes[1]].pos, nodes[stub.nodes[4]].pos, nodes[stub.nodes[8]].pos, nodes[stub.nodes[12]].pos, nodes[stub.nodes[15]].pos
check("the apex is at the tool; the half circle runs from a radius to each side and a radius down; the legs hang the leg length further down (facing the camera: here the world's x axis)",
    math.abs(apex[1] - 10) < 1e-9 and math.abs(apex[2] - 1.5) < 1e-9 and math.abs(arcStart[1] - (10 - r)) < 1e-9 and math.abs(arcStart[2] - (1.5 - r)) < 1e-9 and math.abs(arcEnd[1] - (10 + r)) < 1e-9
    and math.abs(leftEnd[1] - (10 - r)) < 1e-9 and math.abs(leftEnd[2] - (1.5 - r - legLength)) < 1e-9 and math.abs(rightEnd[1] - (10 + r)) < 1e-9 and math.abs(rightEnd[2] - (1.5 - r - legLength)) < 1e-9)
local worst = 0
for i = 2, 14 do
    local a, b, c = nodes[stub.nodes[i - 1]].pos, nodes[stub.nodes[i]].pos, nodes[stub.nodes[i + 1]].pos
    local d1, d2 = { b[1] - a[1], b[2] - a[2] }, { c[1] - b[1], c[2] - b[2] }
    local dot = (d1[1] * d2[1] + d1[2] * d2[2]) / (math.sqrt(d1[1] ^ 2 + d1[2] ^ 2) * math.sqrt(d2[1] ^ 2 + d2[2] ^ 2))
    worst = math.max(worst, math.acos(math.max(-1, math.min(1, dot))))
end
check("no joint turns the rope by more than 22.5 degrees (the parabola's apex turned it by about 50 degrees in one joint: the hairpin with the wedge gap)", worst <= math.rad(22.5) + 1e-6)
local allShown = true
for i, rope in ipairs(stub.pieces) do allShown = allShown and rope.targetNode == stub.nodes[i + 1] and rope.activeDirty == true and rope.visibility == true end
check("every piece runs to the next point (an open chain), following the points every frame, shown", allShown)
getCamera = function() return 880 end
localDirectionToWorld = function(node, x, y, z) return 0, 0, 1 end           -- a camera whose right is world +z
L.updateRide(50)
local sideEnd = nodes[stub.nodes[15]].pos
check("the arch turns to face the camera: with the camera's right along z the end is a radius along z", math.abs(sideEnd[3] - (10 + r)) < 1e-9 and math.abs(sideEnd[1] - 10) < 1e-9)
getCamera, localDirectionToWorld = nil, nil
L.leashSource = nil
L.updateRide(50)
local anyShown = false
for _, rope in ipairs(stub.pieces) do anyShown = anyShown or rope.visibility end
check("the tool put away: the arch is hidden", not anyShown)

-- the harness tool in the hand: a collar, a thick round piece of rope hanging from the tool
local ropesBeforeCollar = #ropes
L.harnessSource = 321
nodes[321].pos = { 10, 1.5, 10 }
L.updateRide(50)
local collar = HorseRope.collar
check("the harness tool in the hand: a closed ring of 12 thick rope pieces (0.05 m), each starting at its own point", collar ~= nil and #ropes == ropesBeforeCollar + 12 and #collar.nodes == 12 and #collar.pieces == 12
    and ropes[#ropes].linkNode == collar.nodes[12] and ropes[#ropes].diameter == 0.05)
loadAll()
L.updateRide(50)
local cr = HorseRope.COLLAR_RADIUS_M
local topP, bottomP = nodes[collar.nodes[4]].pos, nodes[collar.nodes[10]].pos
check("the ring hangs from the tool: its top is at the hand, its bottom a diameter lower", math.abs(topP[2] - 1.5) < 1e-9 and math.abs(topP[1] - 10) < 1e-9 and math.abs(bottomP[2] - (1.5 - 2 * cr)) < 1e-9)
local closed = true
for i, rope in ipairs(collar.pieces) do closed = closed and rope.targetNode == collar.nodes[i % 12 + 1] and rope.visibility == true end
check("every piece runs to the next point and the last one back to the first: a closed ring", closed)
L.harnessSource = nil
L.updateRide(50)
local anyCollar = false
for _, rope in ipairs(collar.pieces) do anyCollar = anyCollar or rope.visibility end
check("the tool put away: the collar is hidden", not anyCollar)
L.harnessSource = nil

-- the tack probe
nodes[620] = { name = "horseRoot", pos = { 12, 0, 12 }, children = { 610, 613 } }
nodes[610] = { name = "equipment", children = { 611, 612 } }
nodes[611] = { name = "saddle", children = {} }
nodes[612] = { name = "bridle", children = {} }
nodes[613] = { name = "reins", children = {} }
local tackCalls = {}
getVisibility = function(n) return nodes[n].hidden ~= true end
setVisibility = function(n, v) nodes[n].hidden = not v end
local tackHorse = { rootNode = 620, spec_rideable = { equipmentNode = 610, reinsNode = 613 }, setEquipmentVisibility = function(_, v) tackCalls[#tackCalls + 1] = v end }
local realRideables = L.rideables
L.rideables = function() return { tackHorse } end
check("hdTack: the tack nodes are listed (the log has the tree of the equipment: saddle and bridle as children)", HorseLead.tack() == "the tack nodes of the nearest horse are in the log")
local tree = table.concat(log, "\n")
check("... with the children by name", tree:find("equipment", 1, true) and tree:find("  saddle", 1, true) and tree:find("  bridle", 1, true))
check("hdTack bridle on / off switches that node only", HorseLead.tack("saddle", "off") == "saddle hidden" and nodes[611].hidden == true and nodes[612].hidden ~= true and HorseLead.tack("saddle", "on") == "saddle shown" and nodes[611].hidden == false)
check("hdTack show / hide calls the game's own equipment switch", HorseLead.tack("show"):find("shown", 1, true) ~= nil and HorseLead.tack("hide"):find("hidden", 1, true) ~= nil and tackCalls[1] == true and tackCalls[2] == false)
check("an unknown node name says so", HorseLead.tack("nothing", "on"):find("no node called", 1, true) ~= nil)
L.rideables = function() return {} end
check("no horse vehicle: it says how to get one", HorseLead.tack():find("lead a horse first", 1, true) ~= nil)
L.rideables = realRideables

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

-- the shop: tools come in a rope and a leather tier; a second copy is refused, the rope one beside the leather one too, and the leather one trades the rope one in
do
    local G = { infos = {}, paid = {}, dir = "mods/FS25_HorseDynamics/handTools/" }      -- (one local: the main chunk of this file is at Lua's limit of 200)
    StoreItemUtil = { getIsHandTool = function(item) return item.hand == true end }
    InfoDialog = { show = function(text) G.infos[#G.infos + 1] = text end }
    DialogElement = { TYPE_WARNING = 1 }
    MoneyType = { SHOP_HANDTOOL_SELL = 9 }
    g_i18n = { getText = function(_, key) return key end }
    ShopController = { canBeBought = function(self, item, price) return true end }
    Player = { requestToEnterVehicle = function(self, vehicle, force) G.entered = vehicle; return "sent" end }
    dofile("scripts/HorseDynamics.lua")
    G.item = function(path, mod) return { hand = true, customEnvironment = mod or g_currentModName, xmlFilename = G.dir .. path } end
    G.tool = function(path, price)
        local t = { configFileName = G.dir .. path, customEnvironment = g_currentModName, getOwnerFarmId = function() return 1 end, getSellPrice = function() return price end, deleted = false }
        function t.delete(self) self.deleted = true end
        return t
    end
    G.system = { handTools = {} }
    g_currentMission.handToolSystem = G.system
    g_currentMission.getFarmId = function() return 1 end
    g_currentMission.addMoney = function(_, amount, farmId, moneyType, show) G.paid[#G.paid + 1] = { amount, farmId, moneyType } end
    G.rope, G.leather = G.item("leash/leash.xml"), G.item("leash/leash_leather.xml")
    local family, tier = HorseDynamics.toolFamily(G.dir .. "harness/harness_leather.xml")
    check("a tool's family is its folder and its tier says leather (2) or rope (1)", family == "harness" and tier == 2 and select(2, HorseDynamics.toolFamily(G.dir .. "leash/leash.xml")) == 1)
    check("the gear of a tool in the hand: leather for the leather file, rope for the other", HorseDynamics.gearOfTool({ configFileName = G.dir .. "leash/leash_leather.xml" }) == "leather" and HorseDynamics.gearOfTool({ configFileName = G.dir .. "harness/harness.xml" }) == "rope")
    -- a horse in its harness is not mounted
    G.harnessed, G.plain = { name = "harnessed" }, { name = "plain" }
    HorseLead.rides = { { vehicle = G.harnessed, harness = true }, { vehicle = G.plain } }
    check("by default a horse in its harness can be mounted (the ride keeps the harness): the key goes through", HorseDynamics.BLOCK_MOUNT_HARNESSED == false and Player.requestToEnterVehicle({}, G.harnessed) ~= nil and G.entered == G.harnessed)
    G.entered = nil
    HorseDynamics.BLOCK_MOUNT_HARNESSED = true
    check("with BLOCK_MOUNT_HARNESSED the mount key on a horse in its harness does nothing", Player.requestToEnterVehicle({}, G.harnessed) == nil and G.entered == nil)
    check("a horse without a harness (a led one, a loose one) is mounted as ever, the arguments passed on", Player.requestToEnterVehicle({}, G.plain, true) == "sent" and G.entered == G.plain)
    check("a vehicle that is no horse of a ride is none of its business", Player.requestToEnterVehicle({}, { name = "tractor" }) == "sent")
    check("HorseLead.isHarnessed: only a ride with the harness on", HorseLead.isHarnessed(G.harnessed) and not HorseLead.isHarnessed(G.plain) and not HorseLead.isHarnessed({}))
    HorseDynamics.BLOCK_MOUNT_HARNESSED = false
    HorseLead.rides = {}
    check("nothing owned: the shop sells both tiers", ShopController.canBeBought({}, G.rope, 25) == true and ShopController.canBeBought({}, G.leather, 90) == true)
    G.system.handTools[1] = G.tool("leash/leash.xml", 20)
    check("the farm has the rope leash: a second rope leash is refused with a message", ShopController.canBeBought({}, G.rope, 25) == false and G.infos[#G.infos] == "warning_horseDynamicsHandToolOwned")
    check("... the leather leash is for sale (an upgrade), and the harness it does not have too", ShopController.canBeBought({}, G.leather, 90) == true and ShopController.canBeBought({}, G.item("harness/harness.xml"), 120) == true)
    check("a tool of another mod is none of its business, even with the same file name", ShopController.canBeBought({}, G.item("leash/leash.xml", "FS25_SomethingElse"), 25) == true)
    G.system.handTools[2] = G.tool("leash/leash_leather.xml", 80)
    check("the farm has the leather leash: the rope leash is refused, saying a better one is owned", ShopController.canBeBought({}, G.rope, 25) == false and G.infos[#G.infos] == "warning_horseDynamicsBetterOwned")
    HorseDynamics.handToolCount = nil
    HorseDynamics.reconcileHandTools()
    check("the rope leash beside the leather one is traded in: deleted and paid back at its sell price (20), the leather one stays",
        G.system.handTools[1].deleted == true and G.system.handTools[2].deleted == false and #G.paid == 1 and G.paid[1][1] == 20 and G.paid[1][2] == 1 and G.paid[1][3] == 9)
    G.system.handTools = { G.system.handTools[2] }
    g_currentMission.handToolSystem = G.system
    HorseDynamics.reconcileHandTools()
    check("(nothing more to trade: no second payment)", #G.paid == 1)
    g_currentMission.getFarmId = function() return 2 end
    check("a tool of another farm does not count (a farm of its own may buy the rope one)", ShopController.canBeBought({}, G.rope, 25) == true)
    g_currentMission.handToolSystem, g_currentMission.getFarmId, g_currentMission.addMoney = nil, nil, nil
end

-- a led horse goes round a wagon another horse pulls (it ran into it, stood, and caught up at a gallop until it bumped it again)
;(function()
    nodes[950], nodes[951] = { pos = { 0, 0, 0 } }, { pos = { 0, 0, -4 } }           -- the pulling horse, and its wagon behind it (the string runs along -z)
    local savedRides = HorseLead.rides
    local puller = { vehicle = { rootNode = 950 }, joined = { vehicle = { rootNode = 951 } } }
    local led = { vehicle = { rootNode = 952 } }
    HorseLead.rides = { puller, led }
    local ax, az, round = HorseLead.aimAround(led, -1.5, -3, 0, 0)
    check("beside the wagon, the player at the pulling horse: it aims at a point beside the pulling horse on its OWN side (3 m to the left, x -3), a way round", round == true and math.abs(ax + 3) < 1e-9 and math.abs(az) < 1e-9)
    ax, az, round = HorseLead.aimAround(led, 1.5, -3, 0, 0)
    check("... the other side of the string: the other side of the pulling horse", round == true and math.abs(ax - 3) < 1e-9)
    ax, az, round = HorseLead.aimAround(led, -1.5, 2, 0, 0)
    check("ahead of the pulling horse there is nothing in the way: it aims at the player", round == false and ax == 0 and az == 0)
    ax, az, round = HorseLead.aimAround(led, -9, -3, -9, 6)
    check("a path that stays well clear of the string: the player", round == false and ax == -9 and az == 6)
    puller.joined, puller.hitch = nil, nil
    ax, az, round = HorseLead.aimAround(led, -1.5, -3, 0, 0)
    check("nothing hitched: the player", round == false and ax == 0)
    check("the string is not an obstacle for the horse that pulls it", (function() puller.joined = { vehicle = { rootNode = 951 } }; local _, _, r = HorseLead.aimAround(puller, 0, -1, 0, 5); return r == false end)())
    HorseLead.rides = savedRides
end)()

-- the tools act on the horse you LOOK at: of several horses near each other, the one the view ray points at, not the nearest
;(function()
    nodes[960], nodes[961], nodes[962] = { pos = { 0, 1.0, 0 } }, { pos = { 0, 0, 5 } }, { pos = { 1.8, 0, 3 } }
    local savedPlayer, savedDir, savedRides = g_localPlayer, localDirectionToWorld, HorseLead.rides
    g_localPlayer = { rootNode = 900, getCurrentCameraNode = function() return 960 end }
    localDirectionToWorld = function(n, x, y, z) if n == 960 then return 0, 0, 1 end; return savedDir(n, x, y, z) end
    local far, near = { vehicle = { rootNode = 961 } }, { vehicle = { rootNode = 962 } }
    HorseLead.rides = { near, far }
    local ride, t = HorseLead.pickRide(0, 0, 8)
    check("two horses, the nearer one (1.8 m to the side, 3 m away) not in the view: the one the ray points at is picked", ride == far and t ~= nil and math.abs(t - 5) < 0.1)
    HorseLead.LOOK = false
    ride = HorseLead.pickRide(0, 0, 8)
    check("LOOK = false: the nearest, as before", ride == near)
    HorseLead.LOOK = true
    nodes[962].pos = { 0.2, 0, 2.5 }
    ride = HorseLead.pickRide(0, 0, 8)
    check("two horses in the line of sight: the front one (the one you see), a graze does not count against it", ride == near)
    nodes[962].pos = { 0.9, 0, 2.5 }
    ride = HorseLead.pickRide(0, 0, 8)
    check("a horse that the ray only grazes (0.9 m off) 2.5 m away loses to one dead ahead at 5 m", ride == far)
    nodes[961].pos = { 0, 0, 12 }
    ride = HorseLead.pickRide(0, 0, 8, nil)
    check("a horse beyond the reach is not picked, and one that is only grazed still is when it is the only one", ride == near)
    nodes[962].pos = { 3, 0, 2.5 }
    ride = HorseLead.pickRide(0, 0, 8)
    check("looking at nothing (a log, no horse in the ray): no horse is picked, however near the horse stands", ride == nil)
    check("... and the distance says there is no horse in view", HorseLead.nearestHorseDistance(0, 0) == nil)
    g_localPlayer, localDirectionToWorld, HorseLead.rides = savedPlayer, savedDir, savedRides
end)()

print = realPrint
print(string.format("horsedynamics_test: %d/%d passed", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
