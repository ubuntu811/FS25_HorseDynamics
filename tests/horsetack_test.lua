-- plain Lua: which tack a horse wears (HorseTack): saved with the animal, streamed, cloned, applied to the pieces, the console
local passed, failed = 0, 0
local function check(name, ok) if ok then passed = passed + 1 else failed = failed + 1; print("  FAIL " .. name) end end
Utils = { prependedFunction = function(o) return o end, appendedFunction = function(o) return o end, overwrittenFunction = function(o) return o end }
HorseCoat = { isHorseCluster = function(c) return type(c) == "table" and c.fitness ~= nil end }
dofile("scripts/HorseTack.lua")

-- a little scene: group "saddle" with the three pieces
local vis, names, kids = {}, {}, {}
local function node(name) local id = #names + 1; names[id] = name; vis[id] = true; return id end
local group = node("saddle")
kids[group] = { node("bridle"), node("saddleSeat"), node("blanket"), node("bit"), node("cheek"), node("halter"), node("panel") }
function getNumOfChildren(n) return kids[n] and #kids[n] or 0 end
function getChildAt(n, i) return kids[n][i + 1] end
function getName(n) return names[n] end
function setVisibility(n, v) vis[n] = v end
function getVisibility(n) return vis[n] end
local function shown(name) for id, n in ipairs(names) do if n == name then return vis[id] end end end

local cluster = { fitness = 0, riding = 0, dirt = 0 }
local vehicle = { spec_rideable = { equipmentNode = group }, getCluster = function() return cluster end, rootNode = 1 }

HorseTack.apply(vehicle)
check("a horse with no wish of its own is left to the game", shown("bridle") and shown("saddleSeat") and shown("blanket"))
cluster.hdTack = 2 + 4
HorseTack.apply(vehicle)
check("blanket + bridle: no saddle, no bit", shown("blanket") and shown("bridle") and shown("saddleSeat") == false and shown("bit") == false and vis[group] == true)
cluster.hdTack = 0
HorseTack.apply(vehicle)
check("nothing worn hides the whole group", vis[group] == false)
cluster.hdTack = 1
HorseTack.apply(vehicle)
check("the cheek strap goes with the bit", shown("cheek") == false)
check("the saddle alone shows although the group was hidden", shown("saddleSeat") and shown("bridle") == false and shown("blanket") == false and vis[group] == true)
check("bridleShowing follows the bridle", HorseTack.bridleShowing(vehicle) == false)
cluster.hdTack = 4; HorseTack.apply(vehicle)
check("bridleShowing: bridle worn", HorseTack.bridleShowing(vehicle) == true and shown("cheek") == false and shown("bit") == false)
check("bridle without the bit is a halter: the halter shape shows", shown("halter") and HorseTack.halterShowing(vehicle))
check("the full bridle (bit worn) hides the halter shape and shows the cheek strap", (function() cluster.hdTack = 12; HorseTack.apply(vehicle); return shown("halter") == false and shown("cheek") and shown("bit") and HorseTack.halterShowing(vehicle) == false end)())
check("a bit without a bridle floats nowhere", (function() cluster.hdTack = 8; HorseTack.apply(vehicle); return shown("bit") == false and shown("halter") == false end)())
cluster.hdTack = 4; HorseTack.apply(vehicle)


-- led horses wear the baked halter, and give the game's behaviour back when let go
cluster.hdTack = nil
vehicle.setEquipmentVisibility = function(_, v) vis[group] = v end
vehicle.getIsControlled = function() return false end
for _, id in ipairs(kids[group]) do vis[id] = true end
vis[group] = false
check("a horse that is not led and has no wish: the effective mask is none (the game's behaviour)", HorseTack.effectiveMask(vehicle, cluster) == nil)
check("the model has the baked halter", HorseTack.bakedHalterAvailable(vehicle) == true)
HorseTack.setLed(vehicle, true)
check("led: the bridle without its bit shows, as the halter", shown("bridle") and shown("halter") and shown("bit") == false and shown("saddleSeat") == false and vis[group] == true and vehicle.hdLed == true)
check("led and a wish with everything: the wish stays (bit worn, no halter shape)", (function() cluster.hdTack = 15; HorseTack.apply(vehicle); local ok = shown("bit") and shown("halter") == false and shown("saddleSeat"); cluster.hdTack = nil; HorseTack.apply(vehicle); return ok end)())
HorseTack.setLed(vehicle, false)
check("let go: the halter shape is hidden and the game's equipment visibility is back (not ridden: hidden)", vehicle.hdLed == nil and shown("halter") == false and vis[group] == false)
cluster.hdTack = 0
HorseTack.setLed(vehicle, true)
check("led with a wish of nothing: the halter is still worn", shown("halter") and vis[group] == true)
HorseTack.setLed(vehicle, false)
check("let go: the wish (nothing) is applied again", vis[group] == false)
cluster.hdTack = nil


-- going back into a pasture clears the wish
cluster.hdTack = 15; vehicle.hdLed = true
HorseTack.clearWish(vehicle)
check("a horse that goes back into the pasture loses its tack wish and its led state", cluster.hdTack == nil and vehicle.hdLed == nil)
HorseTack.clearWish(nil)
check("clearing nothing is harmless", true)

-- saved, streamed, cloned
local xml = { set = {} }
function xml:setInt(key, v) self.set[key] = v end
function xml:getInt(key, d) return self.set[key] or d end
HorseTack.save({ hdTack = 5 }, xml, "a")
check("saved as an attribute", xml.set["a#hdTack"] == 5)
HorseTack.save({}, xml, "b")
check("no wish writes nothing", xml.set["b#hdTack"] == nil)
check("a mask of 0 (nothing worn) is saved too", (function() HorseTack.save({ hdTack = 0 }, xml, "z"); return xml.set["z#hdTack"] == 0 end)())
local loaded = {}
check("loaded back", HorseTack.load(loaded, function() return true end, xml, "a") == true and loaded.hdTack == 5)
local old = {}
HorseTack.load(old, function() return true end, xml, "none")
check("an older animal has no wish", old.hdTack == nil)
local stream = {}
function streamWriteUIntN(_, v, bits) stream[#stream + 1] = { v, bits } end
function streamReadUIntN(_, bits) local e = table.remove(stream, 1); assert(e[2] == bits); return e[1] end
local back = {}
HorseTack.write({ hdTack = 0 }, 1); HorseTack.read(back, 1)
check("nothing worn travels in the stream and stays 0 (not none)", back.hdTack == 0)
HorseTack.write({}, 1); HorseTack.read(back, 1)
check("no wish travels as none", back.hdTack == nil)
HorseTack.write({ hdTack = 15 }, 1); HorseTack.read(back, 1)
check("everything worn travels", back.hdTack == 15)
check("a clone keeps it", HorseTack.clone({ hdTack = 6 }, function() return {} end).hdTack == 6)

-- the console
HorseLead = { rideables = function() return { vehicle } end, playerPosition = function() return 0, 0, 0 end }
function getWorldTranslation() return 0, 0, 0 end
check("not our argument: nil, the old commands handle it", HorseTack.console("saddleSeat", "on") == nil and HorseTack.console("list") == nil)
cluster.hdTack = nil
HorseTack.console("saddle", "off")
check("saddle off from the game's default: everything else", cluster.hdTack == 30 and shown("saddleSeat") == false and shown("bridle"))
HorseTack.console("saddle")
check("saddle with no state toggles it back on", cluster.hdTack == 31)
HorseTack.console("bridle", "off"); HorseTack.console("bridle", "off")
check("off twice stays off", cluster.hdTack == 27)
check("none / all", (function() HorseTack.console("none"); local a = cluster.hdTack; HorseTack.console("all"); return a == 0 and cluster.hdTack == 31 end)())
HorseTack.console("none"); HorseTack.console("panel", "on")
check("panel on: the panel alone, nothing else", cluster.hdTack == 16 and shown("panel") and shown("saddleSeat") == false and shown("blanket") == false)
HorseTack.console("panel", "off")
check("panel off again", cluster.hdTack == 0 and shown("panel") == false)
HorseTack.console("halter")
check("halter: the bridle without the bit", cluster.hdTack == 4 and shown("bridle") and shown("bit") == false and shown("halter") and shown("saddleSeat") == false)
vehicle.setEquipmentVisibility = function(_, v) vis[group] = v end
HorseTack.console("reset")
check("reset: the game's behaviour again, every piece visible except the halter shape", cluster.hdTack == nil and shown("saddleSeat") and shown("blanket") and shown("bridle") and shown("halter") == false)
check("a horse far from anything gets a message", (function() HorseLead.rideables = function() return {} end; return HorseTack.console("all"):find("no horse") ~= nil end)())
print(string.format("horsetack_test: %d/%d passed", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
