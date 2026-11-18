-- plain Lua: which horse a tool acts on: the view ray's distance to the body's middle, or to the head bone (aiming the halter at the face)
local passed, failed = 0, 0
local function check(name, ok) if ok then passed = passed + 1 else failed = failed + 1; print("  FAIL " .. name) end end
g_currentModDirectory = "mods/FS25_HorseDynamics/"
addConsoleCommand = function() end
addModEventListener = function() end
Utils = { overwrittenFunction = function(old, new) return function(self, ...) return new(self, old, ...) end end, getFilename = function(n) return n end }
AnimalClusterHusbandry = { create = function() return 7 end }
dofile("scripts/HorseLead.lua")

local ray = { 0, 1.6, -4, 0, 0, 1 }                              -- a player at z = -4 looking along +z, eyes 1.6 m up
local rx, ry, rz = 1.7, 0, 0.0                                   -- a horse whose body's middle is 1.7 m to the side of the ray: a miss
check("aiming past the body's middle by 1.7 m: no horse (the old test)", HorseLead.lookT(ray, rx, ry, rz, 6) == nil)
local t, miss = HorseLead.lookT(ray, rx, ry, rz, 6, { { 0.2, 1.6, 1.0 } })       -- its head bone is 0.2 m from the ray
check("aiming at its head bone: the horse is looked at", t ~= nil and miss < 0.3)
check("t is how far along the ray the head is (5 m)", t ~= nil and math.abs(t - 5) < 1e-6)
check("a far head point does not spoil a body that is aimed at", HorseLead.lookT(ray, 0, 0, 0.0, 6, { { 5, 5, 5 } }) ~= nil)
check("no head points: the old behaviour", HorseLead.lookT(ray, 0, 0, 0.0, 6, nil) ~= nil)
check("a head point beyond the reach is not counted", HorseLead.lookT(ray, 9, 0, 9, 3, { { 0, 1.6, 9 } }) == nil)
local t3, m3 = HorseLead.lookT(ray, 0, 0, 0.0, 6, { { 0.0, 1.6, 2.0 } })
check("the point the ray passes closest counts (the head here, 0 m, not the body's middle, 0.6 m)", t3 ~= nil and m3 < 0.01)
check("no node: no head points", HorseLead.headPoints(nil) == nil)
-- a frozen horse's animation is skipped, an unfrozen or an unclaimed horse's is not
local claimedSet = {}
HorseLead.isClaimed = function(v) return claimedSet[v] == true end
local hv = {}
HorseLead.frozen = false
check("not frozen: the animation runs", not HorseLead.animationFrozen(hv))
HorseLead.frozen = true
check("frozen but not led: the animation runs (a horse nobody leads is not ours to stop)", not HorseLead.animationFrozen(hv))
claimedSet[hv] = true
check("frozen and led: the animation is skipped", HorseLead.animationFrozen(hv))
HorseLead.frozen = false
print(string.format("horselook_test: %d/%d passed", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
