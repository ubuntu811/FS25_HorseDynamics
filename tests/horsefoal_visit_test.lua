-- plain Lua: where "Visit" on a foal's map popup puts the player: the nearest free spot, nearest ring first, the foal's left side first
local passed, failed = 0, 0
local function check(name, ok) if ok then passed = passed + 1 else failed = failed + 1; print("  FAIL " .. name) end end
Utils = { prependedFunction = function(o, n) return o end, appendedFunction = function(o, n) return o end, overwrittenFunction = function(o, n) return o end }
g_currentModDirectory = "x/"
AnimalSystem, AnimalCluster, PlaceableHusbandryAnimals, Player, Rideable, VehicleLoadingData = {}, {}, {}, {}, {}, {}
dofile("scripts/HorseFoal.lua")
local ground = function(x, z) return 10 end
local x, y, z = HorseFoal.pickVisitSpot(0, 0, 0, function() return true end, ground)
check("everything free: 2.5 m from the foal, on its left (heading 0: +x)", math.abs(math.sqrt(x * x + z * z) - 2.5) < 1e-6 and x > 2.4 and y == 10)
local blocked = 0
local function free(px, pz) blocked = blocked + 1; return math.sqrt(px * px + pz * pz) > 3.0 end
x, y, z = HorseFoal.pickVisitSpot(0, 0, 0, free, ground)
check("the first ring blocked (a wall): the next ring, 3.5 m", math.abs(math.sqrt(x * x + z * z) - 3.5) < 1e-6)
local wall = function(px, pz) return px < 0 end            -- (the foal's left side, +x, is a wall: free only on the -x half)
x, y, z = HorseFoal.pickVisitSpot(0, 0, 0, wall, ground)
check("a wall on the left: a spot on the free right side", x < 0)
x, y, z = HorseFoal.pickVisitSpot(100, 200, math.pi, function() return false end, ground)
check("nothing free anywhere: it still returns the first spot (and does not fail)", x ~= nil and math.abs(math.sqrt((x - 100) ^ 2 + (z - 200) ^ 2) - 2.5) < 1e-6)
-- a saved adult horse vehicle (the game's horse.xml) is loaded as the clone, once the clone is on
local gameHorse = "dataS/character/animals/domesticated/horse/horse.xml"
HorseFoal.adultCloned = nil
check("clone off: the game's horse stays", HorseFoal.adultFilename(gameHorse) == gameHorse)
HorseFoal.adultCloned = true
check("clone on: the game's horse becomes the clone's xml", HorseFoal.adultFilename(gameHorse) == "x/xml/horseAdult.xml")
check("clone on: another vehicle is left alone", HorseFoal.adultFilename("dataS/vehicles/tractor.xml") == "dataS/vehicles/tractor.xml")
check("clone on: the foal's own xml is left alone", HorseFoal.adultFilename("x/xml/horseFoal.xml") == "x/xml/horseFoal.xml")
check("no filename, no failure", HorseFoal.adultFilename(nil) == nil)
check("screen white 1 stays 1 in linear light", math.abs(HorseFoal.toLinear(1) - 1) < 1e-9)
check("a mid grey (0.5) is darker in linear light than 0.5 (about 0.22)", math.abs(HorseFoal.toLinear(0.5) - 0.2176) < 0.001)
check("the default white is the game's tobiano white: nearly neutral (channels within 0.03), 0.7 .. 0.85", math.max(HorseFoal.WHITE_DEFAULT[1], HorseFoal.WHITE_DEFAULT[2], HorseFoal.WHITE_DEFAULT[3]) - math.min(HorseFoal.WHITE_DEFAULT[1], HorseFoal.WHITE_DEFAULT[2], HorseFoal.WHITE_DEFAULT[3]) <= 0.03 and math.min(HorseFoal.WHITE_DEFAULT[1], HorseFoal.WHITE_DEFAULT[2], HorseFoal.WHITE_DEFAULT[3]) > 0.7 and math.max(HorseFoal.WHITE_DEFAULT[1], HorseFoal.WHITE_DEFAULT[2], HorseFoal.WHITE_DEFAULT[3]) < 0.85)
-- the visit itself: the player node must really move (teleportTo's 4th argument is true, as in every call of the game's)
local port, left = nil, false
g_localPlayer = { getCurrentVehicle = function() return {} end, leaveVehicle = function() left = true end, teleportTo = function(_, x, y, z, setNode) port = { x, y, z, setNode } end }
g_terrainNode = 1
getWorldTranslation = function() return 50, 0, 60 end
localDirectionToWorld = function() return 0, 0, 1 end
getTerrainHeightAtWorldPos = function() return 7 end
overlapSphere = function() end
CollisionFlag = setmetatable({}, { __index = function() return 1 end })
HorseFoal.visit({ rootNode = 1 })
check("visit leaves the vehicle and teleports the player", left and port ~= nil)
check("visit passes setNodeTranslation = true, or the player node would not move", port ~= nil and port[4] == true)
check("the spot is next to the foal, at the terrain height", port ~= nil and math.abs(math.sqrt((port[1] - 50) ^ 2 + (port[3] - 60) ^ 2) - 2.5) < 1e-6 and port[2] == 7)
-- hdOriginal: the clone switched off at run time sends a reloaded clone vehicle back to the game's horse, and on again
HorseFoal.dir = "x/"; HorseFoal.cloneAvailable = true; HorseFoal.adultCloned = true
HorseFoal.adultFilename(gameHorse)
HorseFoal.adultCloned = false
check("original on: a reloaded clone vehicle goes back to the game's horse xml", HorseFoal.adultFilename("x/xml/horseAdult.xml") == gameHorse)
HorseFoal.adultCloned = true
check("original off: the clone's xml stays, the game's horse becomes the clone", HorseFoal.adultFilename("x/xml/horseAdult.xml") == "x/xml/horseAdult.xml" and HorseFoal.adultFilename(gameHorse) == "x/xml/horseAdult.xml")
HorsePreview = { reload = function() return "reloaded" end }
HorseFoal.cloneAvailable = true; HorseFoal.adultCloned = true
local r1 = HorseFoal.consoleOriginal(nil, "on")
check("hdOriginal on switches the clone off and reloads", HorseFoal.adultCloned == false and r1:find("game's own horse model", 1, true) ~= nil and r1:find("reloaded", 1, true) ~= nil)
HorseFoal.consoleOriginal(nil, "off")
check("hdOriginal off switches the clone back on", HorseFoal.adultCloned == true)
HorseFoal.cloneAvailable = nil
check("without a clone the command says so and changes nothing", HorseFoal.consoleOriginal(nil, "on"):find("not in use", 1, true) ~= nil and HorseFoal.adultCloned == true)
print(string.format("horsefoal_visit_test: %d/%d passed", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
