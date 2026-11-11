-- plain Lua: the bounce a ball gets from the ground (HorseBall.bounceSpeed): lighter balls bounce more, soft ground takes some, small falls do not bounce
local passed, failed = 0, 0
local function check(name, ok) if ok then passed = passed + 1 else failed = failed + 1; print("  FAIL " .. name) end end
g_currentModDirectory = "x/"
HorseLead = {}
dofile("scripts/HorseBall.lua")
local P = HorseBall.PROFILES
check("a fall that is still going on (speed barely changed) gives nothing", HorseBall.bounceSpeed(-6, -5.8, P[2].bounce, 0) == nil)
check("a slow fall (1 m/s) does not bounce", HorseBall.bounceSpeed(-1, 0, P[2].bounce, 0) == nil)
local beach = HorseBall.bounceSpeed(-6, 0, P[2].bounce, 0)
local normal = HorseBall.bounceSpeed(-6, 0, P[1].bounce, 0)
local heavy = HorseBall.bounceSpeed(-6, 0, P[4].bounce, 0)
check("the lighter the ball the higher it comes back: beach > normal > heavy", beach ~= nil and normal ~= nil and heavy ~= nil and beach > normal and normal > heavy)
check("a medicine ball hardly bounces from a 6 m/s fall (the bounce is below the minimum)", HorseBall.bounceSpeed(-6, 0, P[5].bounce, 0) == nil)
check("meadow (softness 0.6) bounces less than a road (0)", HorseBall.bounceSpeed(-6, 0, P[2].bounce, 0.6) < HorseBall.bounceSpeed(-6, 0, P[2].bounce, 0))
check("each bounce is weaker than the fall (never gains energy)", beach < 6 and normal < 6)
print(string.format("horseball_bounce_test: %d/%d passed", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
