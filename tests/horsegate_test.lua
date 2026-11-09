-- plain Lua with a fake engine: which gate a click is for (HorseGate.looked): the one the view ray points at, the nearest one only when there is no ray
local passed, failed = 0, 0
local realPrint = print
local function check(name, ok) if ok then passed = passed + 1 else failed = failed + 1; realPrint("  FAIL " .. name) end end

-- nodes: 1 gate A's trigger (0, 0, 3), 2 gate B's trigger (6, 0, 0), 3 a gate far away (0, 0, 40)
local nodes = { [1] = { 0, 0, 3 }, [2] = { 6, 0, 0 }, [3] = { 0, 0, 40 } }
getWorldTranslation = function(n) return nodes[n][1], nodes[n][2], nodes[n][3] end
local gateA, gateB, gateFar = { { triggerNode = 1 } }, { { triggerNode = 2 } }, { { triggerNode = 3 } }
g_currentMission = { placeableSystem = { placeables = { { spec_fence = { animatedObjects = { gateA[1], gateB[1], gateFar[1] } } } } } }
dofile("scripts/HorseGate.lua")

-- the player stands at the origin, eyes 1.7 m up; ray = { origin, direction }
local function ray(dx, dy, dz) local l = math.sqrt(dx * dx + dy * dy + dz * dz); return { 0, 1.7, 0, dx / l, dy / l, dz / l } end
local leaves = HorseGate.looked(0, 0, ray(0, -0.1, 1))
check("looking at gate A (straight ahead, 3 m): that one", leaves ~= nil and leaves[1] == gateA[1])
check("looking at gate B (to the side, 6 m, further than the reach 4.5): none, it is out of reach", HorseGate.looked(0, 0, ray(1, -0.1, 0)) == nil)
check("looking away from every gate: none", HorseGate.looked(0, 0, ray(-1, 0, -1)) == nil)
check("looking up at the sky above gate A: none", HorseGate.looked(0, 0, ray(0, 1, 0.3)) == nil)
check("a gate 40 m away is never in reach", select(1, HorseGate.looked(0, 0, ray(0, 0, 1))) ~= gateFar)
local near = HorseGate.looked(0, 0, nil)
check("no ray (LOOK off): the nearest gate in reach, as before", near ~= nil and near[1] == gateA[1])
nodes[2] = { 2, 0, 0 }
leaves = HorseGate.looked(0, 0, ray(1, -0.1, 0))
check("gate B moved within reach: looking at it picks B, not the nearer A", leaves ~= nil and leaves[1] == gateB[1])
local _, t = HorseGate.looked(0, 0, ray(0, -0.1, 1))
check("the second value is how far along the ray (about 3 m)", t ~= nil and math.abs(t - 3) < 0.6)

realPrint(string.format("horsegate_test: %d/%d passed", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
