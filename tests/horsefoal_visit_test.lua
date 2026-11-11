-- plain Lua: where "Visit" on a foal's map popup puts the player: the nearest free spot, nearest ring first, the foal's left side first
local passed, failed = 0, 0
local function check(name, ok) if ok then passed = passed + 1 else failed = failed + 1; print("  FAIL " .. name) end end
Utils = { prependedFunction = function(o, n) return o end, appendedFunction = function(o, n) return o end, overwrittenFunction = function(o, n) return o end }
g_currentModDirectory = "x/"
AnimalSystem, AnimalCluster, PlaceableHusbandryAnimals, Player, Rideable = {}, {}, {}, {}, {}
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
print(string.format("horsefoal_visit_test: %d/%d passed", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
