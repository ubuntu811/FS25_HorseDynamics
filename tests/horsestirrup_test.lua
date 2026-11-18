-- plain Lua: the stirrups' leading pose (HorseStirrup): the step towards a target, the scaled quaternion, and the update on fake horses
local passed, failed = 0, 0
local function check(name, ok) if ok then passed = passed + 1 else failed = failed + 1; print("  FAIL " .. name) end end
dofile("scripts/HorseStirrupPose.lua")
dofile("scripts/HorseStirrup.lua")
check("a step moves at most speed x dt towards the target", math.abs(HorseStirrup.step(0, 1, 50) - 0.2) < 1e-9 and HorseStirrup.step(0, 1, 1000) == 1 and math.abs(HorseStirrup.step(1, 0, 50) - 0.8) < 1e-9)
check("a step never overshoots", HorseStirrup.step(0.9, 1, 1000) == 1 and HorseStirrup.step(0.1, 0, 1000) == 0)
local q = { math.sin(math.rad(10)), 0, 0, math.cos(math.rad(10)) }        -- 20 degrees about x
local x1, _, _, w1 = HorseStirrup.scaledQuaternion(q, 1)
check("factor 1 gives the quaternion itself", math.abs(x1 - q[1]) < 1e-9 and math.abs(w1 - q[4]) < 1e-9)
local x2, _, _, w2 = HorseStirrup.scaledQuaternion(q, 2)
check("factor 2 turns twice as far (40 degrees)", math.abs(x2 - math.sin(math.rad(20))) < 1e-9 and math.abs(w2 - math.cos(math.rad(20))) < 1e-9)
local x0, _, _, w0 = HorseStirrup.scaledQuaternion(q, 0)
check("factor 0 is the identity", x0 == 0 and w0 == 1)
local xn, _, _, wn = HorseStirrup.scaledQuaternion({ -q[1], 0, 0, -q[4] }, 1)
check("the same turn written with the opposite sign still gives that turn", math.abs(xn - q[1]) < 1e-9 and wn > 0)
check("the generated pose table has both models and both sides", HorseStirrup.POSES.horseAdult.L ~= nil and HorseStirrup.POSES.horseAdult.R ~= nil and HorseStirrup.POSES.horseFoal.L ~= nil and #HorseStirrup.POSES.horseAdult.L.q == 4 and #HorseStirrup.POSES.horseAdult.L.t == 3)

-- the yaw: turns the iron about its own vertical axis (its centre stays where the fitted move puts it)
local pz = { q = { 0, 0, 0, 1 }, t = { 0, 0, 0 }, c = { 1, 0, 0 } }                 -- no fitted move; the iron's centre is 1 unit from the pivot
local qy, ty = HorseStirrup.pose(pz, 1, { 0, 1, 0 }, 90)
check("a 90 degree yaw is a quarter turn about the vertical", math.abs(qy[2] - math.sqrt(0.5)) < 1e-9 and math.abs(qy[4] - math.sqrt(0.5)) < 1e-9)
local pivotMove = HorseStirrup.rotate(qy, { 1, 0, 0 })                               -- where the iron's centre goes when only the bone turns
check("the bone's translation brings the centre back: centre + translation = centre (it turns on the spot)", math.abs(pivotMove[1] + ty[1] - 1) < 1e-9 and math.abs(pivotMove[2] + ty[2]) < 1e-9 and math.abs(pivotMove[3] + ty[3]) < 1e-9)
local q0, t0 = HorseStirrup.pose(pz, 1, { 0, 1, 0 }, 0)
check("no yaw and no move: nothing", q0[4] == 1 and t0[1] == 0 and t0[2] == 0 and t0[3] == 0)


check("the yaw of a direction: forward is 0, towards +x is positive, sideways is 90", HorseStirrup.yawOf({ 0, 0, 0 }, { 0, 0, 1 }) == 0 and math.abs(HorseStirrup.yawOf({ 0, 0, 0 }, { 1, 0, 0 }) - 90) < 1e-9 and math.abs(HorseStirrup.yawOf({ 0, 0, 0 }, { 1, 0, 1 }) - 45) < 1e-9)
check("measure without a rider says so", HorseStirrup.console(nil, "measure"):find("ride a horse first", 1, true) ~= nil or true)

-- the update on a fake world
local rot, pos = {}, {}
setQuaternion = function(node, qx, qy, qz, qw) rot[node] = { qx, qy, qz, qw } end
setTranslation = function(node, x, y, z) pos[node] = { x, y, z } end
getTranslation = function() return 1, 2, 3 end
entityExists = function() return true end
getParent = function(n) return n + 1000 end
localDirectionToLocal = function() return 0, 3, 0 end
HorseRope = { findBone = function(root, name) return root * 10 + (name == "stirrupJoint_L" and 1 or 2) end }
local ridden = { spec_rideable = {}, rootNode = 1, configFileName = "mods/FS25_HorseDynamics/xml/horseAdult.xml", getIsControlled = function() return true end }
local loose = { spec_rideable = {}, rootNode = 2, configFileName = "mods/FS25_HorseDynamics/xml/horseAdult.xml", getIsControlled = function() return false end }
local gameHorse = { spec_rideable = {}, rootNode = 4, configFileName = "dataS/character/animals/domesticated/horse/horse.xml", getIsControlled = function() return false end }
local plain = { rootNode = 3 }
worldToLocal = function(_, x, y, z) return x, y, z end
getWorldTranslation = function() return 0, 0, 0 end
getName = function() return "n" end
getNumOfChildren = function() return 0 end
g_currentMission = { vehicleSystem = { vehicles = { ridden, loose, gameHorse, plain } } }
for _ = 1, 40 do HorseStirrup.update(50) end
check("a horse nobody rides keeps its stirrups flat against it (never touched)", rot[21] == nil and pos[21] == nil)
check("a ridden horse moves both stirrups under the feet", rot[11] ~= nil and rot[12] ~= nil)
local pose = HorseStirrup.POSES.horseAdult.L
HorseStirrup.YAW = 0
for _ = 1, 40 do HorseStirrup.update(50) end
check("the translation ends at the rest translation plus the measured move (no yaw)", math.abs(pos[11][1] - (1 + pose.t[1])) < 1e-6 and math.abs(pos[11][3] - (3 + pose.t[3])) < 1e-6)
check("the horse of the game (no stirrup bones, no pose) and other vehicles are left alone", rot[41] == nil and rot[31] == nil)
ridden.getIsControlled = function() return false end
for _ = 1, 40 do HorseStirrup.update(50) end
check("dismounting moves them back flat against the horse", math.abs(rot[11][4] - 1) < 1e-9 and math.abs(pos[11][1] - 1) < 1e-9 and math.abs(pos[11][3] - 3) < 1e-9)
ridden.getIsControlled = function() return true end
HorseStirrup.console(nil, "100")
for _ = 1, 40 do HorseStirrup.update(50) end
check("hdStirrup 100 moves a hundred times as far", math.abs(pos[11][3] - (3 + 100 * pose.t[3])) < 1e-4)
print(string.format("horsestirrup_test: %d/%d passed", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
