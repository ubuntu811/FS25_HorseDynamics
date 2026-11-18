-- plain Lua with a fake engine: a horse answers the washers (HorseWash): dirt from its cluster, whole points only, the rest carried over
local passed, failed = 0, 0
local realPrint = print
local function check(name, ok) if ok then passed = passed + 1 else failed = failed + 1; realPrint("  FAIL " .. name) end end

Platform = { gameplay = { needHorseCleaning = true } }
Washable = { WASHTYPE_HIGH_PRESSURE_WASHER = 1, WASHTYPE_RAIN = 2, WASHTYPE_TRIGGER = 3 }
dofile("scripts/HorseWash.lua")

local cluster = { dirt = 80 }
function cluster:getDirtFactor() return self.dirt / 100 end
function cluster:changeDirt(d) self.dirt = math.max(0, math.min(100, math.floor(self.dirt + d))) end
local horse = { getCluster = function() return cluster end, drawn = 0 }
function horse:updateDirt() self.drawn = self.drawn + 1 end
HorseWash.install(horse)

check("the car wash and the pressure washer are allowed", horse:getAllowsWashingByType(Washable.WASHTYPE_TRIGGER) and horse:getAllowsWashingByType(Washable.WASHTYPE_HIGH_PRESSURE_WASHER))
check("rain is not", not horse:getAllowsWashingByType(Washable.WASHTYPE_RAIN))
check("dirt amount is the cluster's, 0..1", math.abs(horse:getDirtAmount() - 0.8) < 1e-9)
check("a wash duration is given", horse:getWashDuration() > 0)
for _ = 1, 100 do horse:cleanVehicle(0.0004) end            -- 0.04 points a call: 100 calls = 4 points (not a floor per call)
check("100 small cleanings take off 4 points, not 100", cluster.dirt == 76)
check("the coat is redrawn only when the dirt changed", horse.drawn >= 3 and horse.drawn <= 5)
horse:cleanVehicle(2)
check("a big wash cleans it all, no negative dirt", cluster.dirt == 0 and horse:getDirtAmount() == 0)
Platform.gameplay.needHorseCleaning = false
check("with horse cleaning off in this game: not washable, no dirt", not horse:getAllowsWashingByType(Washable.WASHTYPE_TRIGGER) and horse:getDirtAmount() == 0)
horse.getCluster = function() return nil end
horse:cleanVehicle(1)
check("a horse without a cluster: nothing happens", true)

-- riding dirt is scaled, nothing else
local w, c = HorseWash.scaledDirt(0, 1, 0.2)
check("scale 0.2: the first riding step adds nothing yet", w == 0 and math.abs(c - 0.2) < 1e-9)
local total, carry = 0, 0
for _ = 1, 50 do local a; a, carry = HorseWash.scaledDirt(carry, 1, 0.2); total = total + a end
check("scale 0.2: 50 riding steps add 10 dirt (float error does not lose one)", total == 10)
total, carry = 0, 0
for _ = 1, 7 do local a; a, carry = HorseWash.scaledDirt(carry, 1, 1); total = total + a end
check("scale 1: every step adds its point", total == 7)
local c2 = { dirt = 0, hdDirtCarry = nil }
local function superFn(cl, d) cl.dirt = cl.dirt + d end
HorseWash.RIDING_DIRT_SCALE = 0.5
HorseWash.ridingNow = true
for _ = 1, 4 do HorseWash.changeDirt(c2, superFn, 1) end
check("riding at 0.5: four steps give two points", c2.dirt == 2)
HorseWash.changeDirt(c2, superFn, 10)
check("the +10 a day is not scaled (delta is not the riding step's 1)", c2.dirt == 12)
HorseWash.changeDirt(c2, superFn, -5)
check("washing is not scaled", c2.dirt == 7)
HorseWash.ridingNow = false
HorseWash.changeDirt(c2, superFn, 1)
check("a +1 outside Rideable:updateRiding is not scaled", c2.dirt == 8)
HorseWash.RIDING_DIRT_SCALE = 0
HorseWash.ridingNow = true
for _ = 1, 10 do HorseWash.changeDirt(c2, superFn, 1) end
check("scale 0: riding no longer dirties", c2.dirt == 8)
HorseWash.ridingNow = false

realPrint(string.format("horsewash_test: %d/%d passed", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
