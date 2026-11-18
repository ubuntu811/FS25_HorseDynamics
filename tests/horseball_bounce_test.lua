-- plain Lua: the bounce a ball gets from the ground (HorseBall.bounceSpeed): lighter balls bounce more, soft ground takes some, small falls do not bounce
RigidBodyType = { NONE = 0, STATIC = 1, DYNAMIC = 2, KINEMATIC = 3 }
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
-- the throw
local tx, ty, tz = HorseBall.throwVelocity(0.4, 0, 0, P[1])
check("a tap (0.4 m/s from the game) still tosses the ball: faster than 2 m/s, and it goes up", tx ~= nil and math.sqrt(tx * tx + ty * ty + tz * tz) > 2 and ty > 0)
local fx, fy, fz = HorseBall.throwVelocity(8.7, 0, 0, P[1])
local fs = math.sqrt(fx * fx + fy * fy + fz * fz)
check("a full charge is far faster than a kick's ceiling but not past the throw ceiling", fs > P[1].max and fs <= P[1].max * HorseBall.THROW_MAX_FACTOR + 1e-9)
local hx, hy, hz = HorseBall.throwVelocity(8.7, 0, 0, P[5])
check("a medicine ball is thrown slower than the normal one", math.sqrt(hx * hx + hy * hy + hz * hz) < fs)
check("nothing from the game, nothing from us", HorseBall.throwVelocity(0, 0, 0, P[1]) == nil)
check("a flat throw gets a lift (an arc, not a drop)", fy >= HorseBall.THROW_LIFT * math.sqrt(fx * fx + fz * fz) - 1e-9)
-- the kick's direction and what it does to a ball that already rolls
local function near(a, b) return math.abs(a - b) < 1e-6 end
local kx, kz = HorseBall.kickDirection(0, 1, 0, 0.9, 0, 1.8)                    -- the ball dead ahead of the chest
check("a ball dead ahead goes along the heading", near(kx, 0) and near(kz, 1))
kx, kz = HorseBall.kickDirection(0, 1, 0, 0.9, 0.6, 1.2)                        -- to the left of the chest (heading +z, left is +x), a little ahead
check("a ball at the side goes off to that side and forward", kx > 0.4 and kz > 0.25 and near(kx * kx + kz * kz, 1))
kx, kz = HorseBall.kickDirection(0, 1, 0, 0.9, -0.6, 1.2)
check("the other side goes the other way (mirror)", kx < -0.4 and near(kz, select(2, HorseBall.kickDirection(0, 1, 0, 0.9, 0.6, 1.2))))
kx, kz = HorseBall.kickDirection(0, 1, 0, 0.9, 0.7, 0.6)                        -- beside the chest and behind it
check("a ball behind the chest line is still pushed forward a bit, never back", kz >= HorseBall.KICK_MIN_FORWARD - 1e-6)
kx, kz = HorseBall.kickDirection(0, 1, 0, 0.9, 0, 0.9)
check("no distance: the heading, no NaN", near(kx, 0) and near(kz, 1))
local dvx, dvz = HorseBall.kickDelta(3, 0, 0, 1, 4)                              -- rolling along +x at 3, kicked along +z at 4: it goes off along +z only
check("a ball rolling at another angle leaves along the kick (its old sideways speed is taken away)", near(3 + dvx, 0) and near(0 + dvz, 4))
dvx, dvz = HorseBall.kickDelta(0, 6, 0, 1, 4)
check("a ball already faster along the kick is not slowed", near(dvx, 0) and near(dvz, 0))
dvx, dvz = HorseBall.kickDelta(0, 0, 0.6, 0.8, 2)
check("a ball at rest gets the kick's speed along its direction", near(dvx, 1.2) and near(dvz, 1.6))
-- a ball in the hands is not ours to push; the throw aims at where the eye ray points
g_localPlayer = { hands = { getHeldItem = function() return 42 end } }
check("the ball the hands hold is held", HorseBall.isHeld(42))
check("another ball is not", not HorseBall.isHeld(43))
g_localPlayer = nil
check("no player: nothing is held", not HorseBall.isHeld(42))
local ray = { 0, 1.7, 0, 0, 0, 1 }                                     -- the eye at 1.7 m looking along +z
local aim = HorseBall.aimDirection(ray, 0.3, 1.2, 0.5, 8)             -- the ball is in the hand: right, lower, half a metre ahead
check("the aim points from the ball to the point 8 m along the eye ray (left and up a little)", aim ~= nil and aim[1] < 0 and aim[2] > 0 and aim[3] > 0.9 and math.abs(aim[1] ^ 2 + aim[2] ^ 2 + aim[3] ^ 2 - 1) < 1e-9)
check("a ball behind the aim point's plane gets no aim", HorseBall.aimDirection(ray, 0, 1.7, 20, 8) == nil)
local ax, ay, az = HorseBall.throwVelocity(0, 0, 4, P[1], { 0.6, 0.0, 0.8 })
local sp = math.sqrt(ax * ax + ay * ay + az * az)
check("an aimed throw goes along the aim (lift taken into account), same speed as without", ax > 0 and az > 0 and ay > 0 and math.abs(sp - math.sqrt((function() local a, b, c = HorseBall.throwVelocity(0, 0, 4, P[1]) return a * a + b * b + c * c end)())) < 1e-6)

-- far and slow balls are left alone; the rest stop is written once (writing a velocity wakes a sleeping body)
HorseBall.CULL_M = 80
HorseBall.watchAll = false; HorseBall.watch = { 0, 0 }
check("a ball near a horse or the player is looked at", HorseBall.isNear(30, 40) == true)
check("a ball 200 m from everything is not", HorseBall.isNear(200, 0) == false)
HorseBall.watchAll = true
check("with no player position nothing is far away", HorseBall.isNear(5000, 5000) == true)
check("the rest stop does not write below 3 mm/s (the body can sleep)", HorseBall.REST_WRITE_MIN == 0.003 and HorseBall.REST_WRITE_MIN < HorseBall.REST_SPEED)
local rc = 0
HorseBall.radiusOfUncached = function() rc = rc + 1; return 0.5 end
local bv = {}
HorseBall.radiusOf(bv); HorseBall.radiusOf(bv); HorseBall.radiusOf(bv)
check("the radius of a ball is worked out once", rc == 1)
print(string.format("horseball_bounce_test: %d/%d passed", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
