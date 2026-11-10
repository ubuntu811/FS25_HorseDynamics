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

realPrint(string.format("horsewash_test: %d/%d passed", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
