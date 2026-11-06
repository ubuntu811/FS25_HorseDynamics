-- plain Lua with fakes: what is saved of the led horses (snapshot) and how a record is restored over time (step)
local passed, failed = 0, 0
local realPrint = print
print = function() end
local function check(name, ok) if ok then passed = passed + 1 else failed = failed + 1; realPrint("  FAIL " .. name) end end
dofile("scripts/HorseSave.lua")

local ids = setmetatable({}, { __mode = "k" })
local function vehicle(id) local v = {}; ids[v] = id; return v end
local env = {
    uniqueId = function(v) return ids[v] end,
    jointIndex = function(hitch) return hitch.node == "eye" and 2 or nil end,
}

local horse1, horse2, horse3, wagon = vehicle("h1"), vehicle("h2"), vehicle("h3"), vehicle("wagon")
local rides = {
    { vehicle = horse1, harness = true, harnessGear = "leather", hitch = { vehicle = wagon, kind = "drawbar eye", node = "eye" } },
    { vehicle = horse2, leash = true },
    { vehicle = horse3 },                                                                  -- nothing worth saving
    { vehicle = vehicle("h4"), harness = true, hitch = { vehicle = wagon, kind = "log", isLog = true, node = "x" } },
    { vehicle = nil, harness = true },
}
local records = HorseSave.snapshot(rides, env)
check("three horses worth saving, the bare one and the vehicle-less one are not", #records == 3)
check("harness, gear and hitch of the first", records[1].vehicle == "h1" and records[1].harness and records[1].gear == "leather" and records[1].hitch.vehicle == "wagon" and records[1].hitch.index == 2 and records[1].hitch.kind == "drawbar eye")
check("a leashed horse comes back with the halter on, no harness", records[2].halter == true and records[2].harness == nil and records[2].hitch == nil)
check("a hitched log is not saved", records[3].hitch == nil and records[3].harness == true)
local deleted = vehicle("gone"); deleted.isDeleted = true
check("a deleted vehicle is skipped", #HorseSave.snapshot({ { vehicle = deleted, harness = true } }, env) == 0)
check("a hitch whose joint is not found is dropped, the harness stays", (function() local r = HorseSave.snapshot({ { vehicle = horse1, harness = true, hitch = { vehicle = wagon, kind = "hitch", node = "other" } } }, env)[1]; return r.hitch == nil and r.harness end)())

-- restoring
local world, claimed, newRides, hitched = {}, {}, {}, {}
local renv = {
    vehicleById = function(id) return world[id] end,
    claimed = function(v) return claimed[v] end,
    newRide = function(record, v) local ride = { vehicle = v, rig = nil }; newRides[#newRides + 1] = ride; return ride end,
    target = function(hitch) return world["joint"] end,
    hitch = function(ride, target) hitched[#hitched + 1] = { ride = ride, target = target }; ride.hitch = {} end,
}
local record = { vehicle = "h1", harness = true, gear = "leather", hitch = { vehicle = "wagon", kind = "drawbar eye", index = 2 } }
check("waits while the vehicle is not there", HorseSave.step(record, 1000, renv) == false and #newRides == 0)
world["h1"] = horse1
check("the vehicle appears: a ride is made, the hitch is still to do", HorseSave.step(record, 1000, renv) == false and #newRides == 1 and record.ride == newRides[1])
check("no rig yet: waits", HorseSave.step(record, 1000, renv) == false and #hitched == 0)
record.ride.rig = {}
check("rig built but no joint yet: waits", HorseSave.step(record, 1000, renv) == false and #hitched == 0)
world["joint"] = { node = "eye" }
check("joint found: hitched, done", HorseSave.step(record, 1000, renv) == true and #hitched == 1 and hitched[1].target == world["joint"])

local plain = { vehicle = "h2", halter = true }
world["h2"] = horse2
check("no hitch to restore: done as soon as the ride is made", HorseSave.step(plain, 1000, renv) == true and plain.ride ~= nil)
claimed[horse3] = true
world["h3"] = horse3
check("a horse already led by somebody else is left alone", HorseSave.step({ vehicle = "h3", harness = true }, 1000, renv) == true and #newRides == 2)
check("given up after the timeout", HorseSave.step({ vehicle = "nowhere", waited = HorseSave.TIMEOUT_S * 1000 }, 1000, renv) == true)

realPrint(string.format("horse_save_test: %d/%d passed", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
