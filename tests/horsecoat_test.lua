-- plain Lua: the random look of a horse (HorseCoat): deterministic from the seed, sensible shares, saved with the animal, applied once per rebuild
local passed, failed = 0, 0
local function check(name, ok) if ok then passed = passed + 1 else failed = failed + 1; print("  FAIL " .. name) end end
Utils = { prependedFunction = function(o) return o end, appendedFunction = function(o) return o end, overwrittenFunction = function(o) return o end }
dofile("scripts/HorseCoat.lua")

-- deterministic, varied
local a, ta = HorseCoat.fromSeed(123456)
local b, tb = HorseCoat.fromSeed(123456)
check("the same seed gives the same look", ta == tb and a.face == b.face and a.socks == b.socks and a.blanket == b.blanket and a.spots[3] == b.spots[3])
local kinds, n = {}, 5000
local plain, noface, nosocks, faceBad, socksBad, spotsBad = 0, 0, 0, 0, 0, 0
for seed = 1, n do
    local c, text = HorseCoat.fromSeed(seed * 3301 % HorseCoat.MAX_SEED + 1)
    kinds[text] = true
    if c.flecks == 0 and c.blanket == 0 and c.pattern[1] == 0 then plain = plain + 1 end
    if c.face == 0 then noface = noface + 1 end
    if c.socks == 0 then nosocks = nosocks + 1 end
    if c.face < 0 or c.face > 3 or c.face ~= math.floor(c.face) then faceBad = faceBad + 1 end
    if c.socks ~= 0 and (c.socks < 0.2 or c.socks > 0.8) then socksBad = socksBad + 1 end
    if c.spots[1] < 0.1 or c.spots[1] > 0.9 or c.spots[2] < 0.5 or c.spots[2] > 0.95 or c.spots[3] < 0 or c.spots[3] > 999 or c.spots[4] < 0.07 or c.spots[4] > 0.1 then spotsBad = spotsBad + 1 end
end
local distinct = 0
for _ in pairs(kinds) do distinct = distinct + 1 end
check("plenty of different looks (a text each): " .. distinct, distinct >= 40)
check("about 46 % plain coats: " .. plain / n, plain / n > 0.40 and plain / n < 0.52)
check("about a third without a face marking: " .. noface / n, noface / n > 0.29 and noface / n < 0.39)
check("about 40 % without socks: " .. nosocks / n, nosocks / n > 0.35 and nosocks / n < 0.45)
check("faces are whole numbers 0..3", faceBad == 0)
check("socks are 0 or 0.2 .. 0.8", socksBad == 0)
check("spot settings stay in their ranges", spotsBad == 0)

-- the seeds
local horse = { fitness = 0, riding = 0, dirt = 0 }
local s1 = HorseCoat.ensureSeed(horse)
check("a horse cluster gets a seed in range, and keeps it", s1 >= 1 and s1 <= HorseCoat.MAX_SEED and HorseCoat.ensureSeed(horse) == s1)
check("something that is not a horse gets none", HorseCoat.ensureSeed({ numAnimals = 3 }) == nil and HorseCoat.ensureSeed(nil) == nil)

-- saved with the animal
local xml = { set = {} }
function xml:setInt(key, v) self.set[key] = v end
function xml:getInt(key, d) return self.set[key] or d end
HorseCoat.save({ hdCoatSeed = 777 }, xml, "a")
check("saved as an attribute of the animal", xml.set["a#hdCoatSeed"] == 777)
HorseCoat.save({}, xml, "b")
check("a horse without a seed writes nothing", xml.set["b#hdCoatSeed"] == nil)
local loaded = {}
check("loaded back, the game's own load result passed on", HorseCoat.load(loaded, function() return true end, xml, "a") == true and loaded.hdCoatSeed == 777)
local failedLoad = {}
check("a failed load stays failed and reads nothing", HorseCoat.load(failedLoad, function() return false end, xml, "a") == false and failedLoad.hdCoatSeed == nil)
local old = {}
HorseCoat.load(old, function() return true end, xml, "none")
check("an animal from an older game has no seed (it gets one when first shown)", old.hdCoatSeed == nil)
local stream = {}
function streamWriteUIntN(_, v, bits) stream[#stream + 1] = { v, bits } end
function streamReadUIntN(_, bits) local e = table.remove(stream, 1); assert(e[2] == bits); return e[1] end
HorseCoat.write({ hdCoatSeed = 4242 }, 1); local viaStream = {}; HorseCoat.read(viaStream, 1)
check("the seed travels in the stream (24 bits)", viaStream.hdCoatSeed == 4242)
HorseCoat.write({}, 1); HorseCoat.read(viaStream, 1)
check("no seed travels as 0 and reads back as none", viaStream.hdCoatSeed == nil)
check("a clone keeps the seed", HorseCoat.clone({ hdCoatSeed = 99 }, function() return {} end).hdCoatSeed == 99)

-- applied once per rebuild
local applied = {}
HorseFoal = { applyCoat = function(node, c) applied[#applied + 1] = { node = node, c = c } end }
function getAnimalRootNode(husbandry, animalId) return animalId * 10 end
local map = { [1] = { fitness = 0, riding = 0, dirt = 0 }, [2] = { fitness = 0, riding = 0, dirt = 0 }, [3] = { numAnimals = 5 } }
local husbandry = { husbandryId = 7, animalIdToCluster = map }
HorseCoat.applyHusbandry(husbandry)
check("every horse of a pasture gets its look, a cow does not", #applied == 2)
HorseCoat.applyHusbandry(husbandry)
check("the same animals again: nothing is done twice", #applied == 2)
husbandry.animalIdToCluster = { [1] = map[1] }
HorseCoat.applyHusbandry(husbandry)
check("a rebuild (a new table) applies again", #applied == 3)
check("the look of a seed is the same on the pasture as on a vehicle", applied[3].c.face == select(1, HorseCoat.fromSeed(map[1].hdCoatSeed)).face)
local vehicle = { spec_rideable = { meshNode = 55 }, getCluster = function() return map[2] end }
HorseCoat.applyVehicle(vehicle)
check("a horse vehicle is shown with its cluster's look, and remembers it for hdCoat", #applied == 4 and applied[4].node == 55 and vehicle.horseCoat ~= nil)
vehicle.horseCoatManual = true
HorseCoat.applyVehicle(vehicle)
check("a look set by hand is not overwritten", #applied == 4)
-- told on the information screens
local lines = {}
local box = { addLine = function(_, title, text) lines[#lines + 1] = { title, text } end }
local told = { fitness = 0, riding = 0, dirt = 0, hdCoatSeed = 4711 }
HorseCoat.showInfo(told, box)
local _, expect = HorseCoat.fromSeed(4711)
check("the info box gets a Coat line with the look's text", #lines == 1 and lines[1][1] == "Coat" and lines[1][2] == expect)
HorseCoat.showInfo({ numAnimals = 4 }, box)
check("a cow's info box gets nothing", #lines == 1)
local d = HorseCoat.itemDescription({ cluster = told }, function() return "A fine horse." end)
check("the animal screen's description gets the coat under it", d == "A fine horse.\n\nCoat: " .. expect)
check("a description of something that is not a horse stays as it is", HorseCoat.itemDescription({ cluster = { numAnimals = 4 } }, function() return "Cow." end) == "Cow.")
check("no description from the game: just the coat", HorseCoat.itemDescription({ cluster = told }, function() return nil end) == "\n\nCoat: " .. expect)
-- the looks are put on again slowly (an option now: off by default)
do
    HorseCoat.REAPPLY = true
    local applied2 = {}
    HorseFoal = { applyCoat = function(node, c) applied2[#applied2 + 1] = node end }
    local nodes = { [1] = { 0, 0, 0 }, [2] = { 10, 0, 0 }, [3] = { 500, 0, 0 } }
    getWorldTranslation = function(node) local p = nodes[node]; return p[1], p[2], p[3] end
    HorseLead = { playerPosition = function() return 0, 0, 0 end,
        rideables = function() return {
            { rootNode = 1, spec_rideable = { meshNode = 11 }, horseCoat = { id = "a" } },
            { rootNode = 2, spec_rideable = { meshNode = 12 }, horseCoat = { id = "b" } },
            { rootNode = 3, spec_rideable = { meshNode = 13 }, horseCoat = { id = "far" } },
            { rootNode = 1, spec_rideable = { meshNode = 14 } },
        } end }
    HorseCoat.husbandries = setmetatable({}, { __mode = "k" })          -- (the pastures of the sections above are not part of this one)
    HorseCoat.fresh = setmetatable({}, { __mode = "k" })                 -- (nor the vehicles)
    HorseCoat.queue, HorseCoat.nextRound = {}, 0
    HorseCoat.update(16)
    check("the first tick of a round puts at most PER_TICK horses on again", #applied2 <= HorseCoat.PER_TICK and #applied2 >= 1)
    HorseCoat.update(16); HorseCoat.update(16)
    check("the horses in range (two) are done after a few ticks, the far one (500 m) and the one without a look are not", #applied2 == 2)
    local n = #applied2
    HorseCoat.update(500)
    check("nothing again before REAPPLY_MS has passed", #applied2 == n)
    HorseCoat.update(HorseCoat.REAPPLY_MS)
    HorseCoat.update(16); HorseCoat.update(16)
    check("the next round puts them on again", #applied2 >= n + 2)
    check("a dead node is skipped without an error", (function() entityExists = function() return false end local before = #applied2; HorseCoat.queue = { { node = 1, coat = {} } }; HorseCoat.update(16); entityExists = nil; return #applied2 == before end)())
end
-- a vehicle that has just appeared is put on again every 100 ms for 2 s (the option on)
do
    HorseCoat.REAPPLY = true
    local count = 0
    HorseFoal = { applyCoat = function() count = count + 1 end }
    entityExists = nil
    local v = { spec_rideable = { meshNode = 5 }, getCluster = function() return { fitness = 0, riding = 0, dirt = 0, hdCoatSeed = 99 } end }
    HorseCoat.fresh = setmetatable({}, { __mode = "k" })
    HorseCoat.applyVehicle(v)
    check("applying a vehicle puts the look on at once and marks it fresh", count == 1 and HorseCoat.fresh[v] ~= nil)
    HorseCoat.husbandries = setmetatable({}, { __mode = "k" }); HorseCoat.queue, HorseCoat.nextRound = {}, 99999
    HorseLead = { rideables = function() return {} end }
    for _ = 1, 10 do HorseCoat.update(100) end
    check("a second later it has been put on again about every 100 ms", count >= 9 and count <= 12)
    for _ = 1, 15 do HorseCoat.update(100) end
    local after = count
    check("after two seconds it is no longer fresh and the burst stops", HorseCoat.fresh[v] == nil)
    HorseCoat.update(100); HorseCoat.update(100)
    check("no more bursts", count == after)
end
-- off by default: nothing is put on again by the loops
do
    HorseCoat.REAPPLY = false
    local n2 = 0
    HorseFoal = { applyCoat = function() n2 = n2 + 1 end }
    HorseCoat.fresh = setmetatable({ [{ spec_rideable = { meshNode = 1 }, horseCoat = {} }] = { left = 2000, tick = 0 } }, { __mode = "k" })
    HorseCoat.queue, HorseCoat.nextRound = {}, 0
    for _ = 1, 30 do HorseCoat.update(100) end
    check("with the option off the loops do nothing", n2 == 0)
    HorseCoat.REAPPLY = true
end
print(string.format("horsecoat_test: %d/%d passed", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
