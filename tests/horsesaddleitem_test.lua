-- plain Lua: the saddle object (HorseSaddleItem): the look ray against the saddle's box, put on / take off through HorseTack
local passed, failed = 0, 0
local function check(name, ok) if ok then passed = passed + 1 else failed = failed + 1; print("  FAIL " .. name) end end
Utils = { prependedFunction = function(o) return o end, appendedFunction = function(o) return o end, overwrittenFunction = function(o) return o end }
HorseCoat = { isHorseCluster = function(c) return type(c) == "table" and c.fitness ~= nil end }
dofile("scripts/HorseTack.lua")
dofile("scripts/HorseSaddleItem.lua")
local R, lo, hi = HorseSaddleItem.rayBox, HorseSaddleItem.BOX_LO, HorseSaddleItem.BOX_HI

-- the box: x +-0.42, y 1.02 .. 1.72, z -0.20 .. 0.45
check("a ray from the left at saddle height enters the box at its side", math.abs(R(3, 1.4, 0.1, -1, 0, 0, lo, hi) - 2.58) < 1e-6)
check("a ray from the right enters it too", math.abs(R(-3, 1.4, 0.1, 1, 0, 0, lo, hi) - 2.58) < 1e-6)
check("over the saddle: no hit", R(3, 1.9, 0.1, -1, 0, 0, lo, hi) == nil)
check("under the leathers (the belly): no hit", R(3, 0.8, 0.1, -1, 0, 0, lo, hi) == nil)
check("in front of the pommel (the neck): no hit", R(3, 1.4, 0.8, -1, 0, 0, lo, hi) == nil)
check("a ray from a point inside the box hits at 0", R(0, 1.4, 0.1, -1, 0, 0, lo, hi) == 0)
check("a ray pointing away from the box: no hit", R(3, 1.4, 0.1, 1, 0, 0, lo, hi) == nil)
check("a slanting ray from the eye (1.7 m up, 2 m away) hits the box", R(2, 1.7, 0.1, -0.9, -0.3, 0, lo, hi) ~= nil)
check("a ray parallel to a slab and outside it: no hit", R(3, 1.4, 0.9, -1, 0, 0, lo, hi) == nil)

-- put on / take off
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
local equipped = 0
local horse = { spec_rideable = { equipmentNode = group }, getCluster = function() return cluster end, rootNode = 1, setEquipmentVisibility = function() equipped = equipped + 1 end }

check("a bare horse (the game's own behaviour) has no saddle", not HorseTack.wearsSaddle(horse))
check("the saddle goes on", HorseTack.saddleOn(horse) == true)
check("... the saddle, the pad and the panel show", shown("saddleSeat") and shown("blanket") and shown("panel"))
check("... and the horse wears it", HorseTack.wearsSaddle(horse) and cluster.hdTack == HorseTack.ALL)
HorseTack.saddleOff(horse)
check("taken off: the horse has its own behaviour back", cluster.hdTack == nil and not HorseTack.wearsSaddle(horse) and equipped == 1)

cluster.hdTack = 4
HorseTack.saddleOn(horse)
check("a horse with a bridle keeps it and gets the saddle", cluster.hdTack == 4 + 1 + 2 + 16 and shown("bridle"))
HorseTack.saddleOff(horse)
check("taken off: the bridle stays, the saddle pieces go", cluster.hdTack == 4 and not shown("saddleSeat") and not shown("panel") and shown("bridle"))
cluster.hdTack = 1 + 2
HorseTack.saddleOn(horse)
check("a pad worn already is not counted twice", cluster.hdTack == 1 + 2 + 16)
local noTack = { getCluster = function() return nil end }
check("a horse with no tack node or cluster cannot wear it", HorseTack.saddleOn(noTack) == false and HorseTack.saddleOn({ spec_rideable = {}, getCluster = function() return cluster end }) == false)

-- the item: equip, then the same horse refuses a second saddle
local calls = {}
local item = { rootNode = 7, removeFromPhysics = function() calls[#calls + 1] = "phys" end, setVisibility = function(_, v) calls[#calls + 1] = v and "show" or "hide" end }
cluster.hdTack = nil; horse.hdSaddlePrev = nil
local ok = HorseSaddleItem.equip(horse, item)
check("equip: worn, hidden, out of the physics", ok == true and item.horseWornBy == horse and horse.hdSaddleItem == item and calls[1] == "phys" and calls[2] == "hide")
local second = { rootNode = 8, removeFromPhysics = function() end, setVisibility = function() end }
local ok2, why = HorseSaddleItem.equip(horse, second)
check("a second saddle is refused", ok2 == false and why:find("already") ~= nil and second.horseWornBy == nil)
print(string.format("horsesaddleitem_test: %d/%d passed", passed, passed + failed))
