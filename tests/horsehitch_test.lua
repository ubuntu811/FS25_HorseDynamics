-- plain Lua with a fake engine: a harnessed horse pulls a trailer (the wagon is driven kinematically so that its drawbar eye is glued to the harness's hook), the click hitches / unhitches, the lift, the keys and the saddle prompt follow
local passed, failed = 0, 0
local realPrint = print
local log = {}
print = function(text) log[#log + 1] = text end
local function check(name, ok) if ok then passed = passed + 1 else failed = failed + 1; realPrint("  FAIL " .. name) end end

-- nodes: 1 horse root, 2 the harness's hook (the pin: 0, 0.9, -1), 3 the hook ring's rear point, 10 the joint (the drawbar eye), 20 the player
local nodes = { [1] = { 0, 0, 0 }, [2] = { 0, 0.9, -1 }, [3] = { 0, 0.9, -1.06 }, [10] = { 0, 0.6, -4 }, [20] = { 0, 0, -3 } }
getWorldTranslation = function(n) local p = nodes[n]; return p[1], p[2], p[3] end
entityExists = function(n) return nodes[n] ~= nil end
local velocity = { 0, 0, 0 }
local VELS = {}                                  -- (a velocity of one node: the others have `velocity`)
getLinearVelocity = function(n) local v = VELS[n] or velocity; return v[1], v[2], v[3] end
local MASS = 2
local MASSES = {}                                -- (the mass of one node: the others have MASS)
getMass = function(n) return MASSES[n] or MASS end
local function noHorizontalForce(list)
    for _, f in ipairs(list) do
        if math.abs(f[2]) > 1e-9 or math.abs(f[4]) > 1e-9 then
            return false
        end
    end
    return true
end
local rootBack = { 0, 0, -1 }
local TILT = {}
local SETLIN, SETANG, ANGS, HEADING = {}, {}, {}, {}      -- (the speeds the hitch set per node, the angular speeds the engine has, the heading of a body)
setLinearVelocity = function(n, x, y, z) SETLIN[n] = { x, y, z } end
setAngularVelocity = function(n, x, y, z) SETANG[n] = { x, y, z } end
getAngularVelocity = function(n) local v = ANGS[n] or { 0, 0, 0 }; return v[1], v[2], v[3] end
localDirectionToWorld = function(n, x, y, z)
    if n == 1 then return rootBack[1], rootBack[2], rootBack[3] end        -- (the horse: its way back)
    if y == 1 and TILT[n] ~= nil then return 0, math.cos(math.rad(TILT[n])), math.sin(math.rad(TILT[n])) end      -- (a tilted body: its up axis)
    local h = HEADING[n] or 0
    return x * math.cos(h) + z * math.sin(h), y, -x * math.sin(h) + z * math.cos(h)      -- (any body: the direction turned by its heading about the vertical axis)
end
local forces = {}
addForce = function(node, fx, fy, fz, px, py, pz, isLocal) forces[#forces + 1] = { node, fx, fy, fz, px, py, pz, isLocal } end

local nextNode, deletedNodes = 500, {}
createTransformGroup = function() nextNode = nextNode + 1; nodes[nextNode] = { 0, 0, 0 }; return nextNode end
link = function() end
getRootNode = function() return 0 end
setTranslation = function(n, x, y, z) nodes[n] = { x, y, z } end
delete = function(n) deletedNodes[#deletedNodes + 1] = n; nodes[n] = nil end
local brake, support = {}, {}
local pickResult
local vehicle = { isDeleted = false, getName = function() return "Small Trailer" end, updateActionEvents = function() INPUTLOG[#INPUTLOG + 1] = "vehicle update" end }
local target = { vehicle = vehicle, node = 10, component = 100, kind = "drawbar eye" }
HITCHCAPS = {}
NEARESTJOINT = nil
g_currentMission = { winchTow = {
    pick = function() return pickResult end,
    setBrakeOff = function(t, off) brake[#brake + 1] = off end,
    setSupportUp = function(t, up) support[#support + 1] = up end,
    pullMass = function(v, c) return v.total or getMass(c) end,
    nearest = function(x, z, radius, except) NEARESTARGS = { x, z, radius, except }; return NEARESTJOINT end,
    pullSpeed = function(mass) if mass >= 10 then return 2 / 3.6 end return 3.5 end,
    setSpeedCap = function(source, cap) HITCHCAPS[source] = cap end,
} }

Rideable = { GAITTYPES = { BACKWARDS = 1, STILL = 2, WALK = 3, TROT = 4, CANTER = 5, GALLOP = 6 } }       -- (the game's numbers: not in the order of the speeds)
HITCHCAPS = {}
local pieces = {}
HorseRope = {
    createSegment = function(linkNode, diameter, options)
        local rope = { link = linkNode, diameter = diameter, options = options, visible = false, updates = 0,
            setVisibility = function(self, v) self.visible = v end,
            setTargetNode = function(self, node) self.target = node end,
            update = function(self) self.updates = self.updates + 1 end,
            delete = function(self) self.deleted = true end }
        pieces[#pieces + 1] = rope
        return rope
    end,
    gearOptions = function(w, b, x, y, z, gear) if gear == "leather" then return { leather = true } end return nil end,
    applyMaterial = function(rope) if not rope.rfMaterialDone then rope.materialDone = true end end,
    setShown = function(rope, visible) rope.visible = visible end,
}
HorseHarness = { spec = { trace = { diameter = 0.02 } } }
local player = true
HorseLead = { rides = {}, playerPosition = function() if player then return 0, 0, -3 end return nil end }
-- the input system: the vehicle's registration of its keys, replayed for the player on foot
INPUTLOG = {}
CONTEXT = "PLAYER"                              -- the input context the player is in
SADDLE = { active = {}, text = {}, priority = {}, removed = {} }
g_inputBinding = { getContextName = function() return CONTEXT end, beginActionEventsModification = function(_, context) INPUTLOG[#INPUTLOG + 1] = "begin " .. context end, endActionEventsModification = function() INPUTLOG[#INPUTLOG + 1] = "end" end,
    setActionEventTextPriority = function(_, id, p) SADDLE.priority[id] = p end,
    setActionEventActive = function(_, id, a) SADDLE.active[id] = a end,
    setActionEventText = function(_, id, t) SADDLE.text[id] = t end,
    removeActionEvent = function(_, id) SADDLE.removed[#SADDLE.removed + 1] = id end }
InputAction = { ATTACH = "ATTACH" }
GS_PRIO_VERY_HIGH = 5
g_i18n = { getText = function(_, key) return key end }
PlayerInputComponent = { INPUT_CONTEXT_NAME = "PLAYER" }
SPECERROR = false
SpecializationUtil = { raiseEvent = function(v, name, a, b)
    if SPECERROR then error("a spec broke") end
    INPUTLOG[#INPUTLOG + 1] = name .. " " .. tostring(a) .. " " .. tostring(b)
end }
Vehicle = { INPUT_CONTEXT_NAME = "VEHICLE", registerActionEvents = function(self) INPUTLOG[#INPUTLOG + 1] = "game registers" end }
Rideable = Rideable or {}
Rideable.onRegisterActionEvents = function(self, a, b) INPUTLOG[#INPUTLOG + 1] = "rideable registers" end
Utils = { appendedFunction = function(old, new) return function(...) old(...); new(...) end end }
dofile("scripts/HorseHitch.lua")
HorseHitch.MAX_PULL_KN = 1000        -- (the drive first, the horse's limit below)
HorseHitch.MAX_ACCEL_MS2 = 1000      -- (and the safety limit on how fast the wagon's speed may change: its own test below)

local ride = { vehicle = { rootNode = 1 }, harness = true, harnessGear = "leather", rig = { hookNode = 2, hookRear = 3 } }
HorseLead.rides = { ride }

-- the click: nothing in view -> not its business
pickResult = nil
check("nothing in view: the click is none of the hitch's business (the harness tool does its own)", HorseHitch.click() == nil and ride.hitch == nil)
-- a joint in view, a harnessed horse 4 m away: hitched
pickResult = target
ride.towRope = true                                                                  -- (the harness tool handed its rope over first)
local message = HorseHitch.click()
check("tying the rope to the joint uses it up", ride.towRope == nil)
check("a joint in view and a harnessed horse near it: hitched, with a message saying what and how to undo", message ~= nil and message:find("hitched to the drawbar eye of Small Trailer", 1, true) ~= nil and ride.hitch ~= nil)
check("hitching puts the support leg up", support[#support] == true)
check("a trailer's drawbar eye needs no pieces of its own (the hook ring and the traces are the harness's, always there): none, no tow bar", #pieces == 0 and ride.hitch.barLength == 0)

HorseHitch.INTEGRAL_GAIN = 0                     -- (the plain drive first, the gap integral below)
-- the wagon is DRIVEN, kinematically: a vehicle of two bodies, the drawbar (100, 0.06 t, at the eye) and the rear body (101, 0.3 t, 3 m behind it): the rear body is the reference, the eye is glued to the hook
vehicle.components = { { node = 100 }, { node = 101 } }
MASSES[100], MASSES[101] = 0.06, 0.3
vehicle.total = 0.66
nodes[100], nodes[101] = { 0, 0.5, -1 }, { 0, 0.5, -4 }
nodes[10] = { 0, 0.9, -1 }                       -- the eye on the hook (0, 0.9, -1)
HorseHitch.release(ride)
pickResult = target
HorseHitch.click()
check("the heavy body of the vehicle is found when hitching, the reference of the drive (the rear body 101, not the drawbar 100)", ride.hitch.body == 101)
local function still(n) return math.abs(SETLIN[n][1]) < 1e-9 and math.abs(SETLIN[n][3]) < 1e-9 end
HorseHitch.update(ride, 16)
check("the eye on the hook and the horse standing: every body is held (no horizontal speed), no turn", still(100) and still(101) and SETANG[101][2] == 0)
check("... and the brake is let off while it is driven (it would only make the wheels skid)", brake[#brake] == true)

-- the horse walks forward (its smoothed speed 2 m/s: one frame of the 10 % filter leaves 1.8): the whole wagon moves with it, straight
ride.hitch.vz = 2
HorseHitch.update(ride, 16)
check("the horse walks: every body of the wagon gets the horse's speed forward (1.8 m/s after the filter), no turn", math.abs(SETLIN[100][3] - 1.8) < 1e-9 and math.abs(SETLIN[101][3] - 1.8) < 1e-9 and math.abs(SETLIN[101][1]) < 1e-9 and SETANG[101][2] == 0)
ride.hitch.vz = 0
for _ = 1, 40 do HorseHitch.update(ride, 16) end

-- the hook moves sideways (the horse turns: 1 m/s, 0.9 after the filter): the wagon turns about its rear body as a trailer does: rear speed along the line (zero), turn 0.9 / 3 m = 0.3 rad/s,
-- the eye (at the drawbar, 3 m ahead of the rear body) moves 0.9 m/s sideways
ride.hitch.vx = 1
HorseHitch.update(ride, 16)
check("the horse turns: the drawbar at the eye moves sideways with the hook (0.9 m/s), the rear body stays (it only moves along the line to the eye), the turn is 0.3 rad/s",
    math.abs(SETLIN[100][1] - 0.9) < 1e-9 and math.abs(SETLIN[101][1]) < 1e-9 and math.abs(SETLIN[100][3]) < 1e-9 and math.abs(SETANG[101][2] - 0.3) < 1e-9 and math.abs(SETANG[100][2] - 0.3) < 1e-9)
ride.hitch.vx = 0
for _ = 1, 40 do HorseHitch.update(ride, 16) end

-- the eye is behind the hook: it is brought back at POS_GAIN per metre (0.5 m: 2 m/s), straight
nodes[10] = { 0, 0.9, -1.5 }
HorseHitch.update(ride, 16)
check("the eye 0.5 m behind the hook: the wagon is driven forward at 4 * 0.5 = 2 m/s, straight", math.abs(SETLIN[100][3] - 2) < 1e-9 and math.abs(SETLIN[101][3] - 2) < 1e-9 and SETANG[101][2] == 0)
-- far away and close to the rear body (no arm to turn on): pure movement, at most CATCH_SPEED_MS
nodes[10] = { 0, 0.9, -3.8 }
HorseHitch.update(ride, 16)
check("the eye 2.8 m behind the hook (4 * 2.8 = 11 m/s wanted): at most CATCH_SPEED_MS (6), the rear body 0.2 m from the eye: no turn, everything moves alike", math.abs(SETLIN[101][3] - 6) < 1e-9 and math.abs(SETLIN[100][3] - 6) < 1e-9 and SETANG[101][2] == 0)
nodes[10] = { 0, 0.9, -1 }

-- the vertical speed and the pitch and roll are the physics' own
VELS[101], ANGS[100] = { 0, -0.3, 0 }, { 0.1, 0, 0.2 }
HorseHitch.update(ride, 16)
check("the vertical speed of the rear body and the pitch and roll of the bodies are left to the physics (only the horizontal speed and the yaw are set; the drawbar's height is driven, below)", SETLIN[101][2] == -0.3 and SETANG[100][1] == 0.1 and SETANG[100][3] == 0.2)
VELS[101], ANGS[100] = nil, nil

-- the engine's sign of a yaw speed is checked against what the rear body really does: its heading turning the other way for 8 frames flips the sign
do
    log = {}
    for i = 1, 12 do
        ride.hitch.vx = 1
        HEADING[101] = -0.005 * i
        HorseHitch.update(ride, 16)
    end
    local flipped = false
    for _, line in ipairs(log) do if line:find("the sign is flipped", 1, true) then flipped = true end end
    check("a wagon that turns the other way from the yaw speed commanded: the sign is flipped (said once) and the turn is set the other way round", ride.hitch.omegaSign == -1 and flipped and SETANG[101][2] < 0)
    ride.hitch.omegaSign, ride.hitch.lastHeading, ride.hitch.wrongTurns = 1, nil, 0
    for i = 1, 12 do
        ride.hitch.vx = 1
        HEADING[101] = 0.005 * i
        HorseHitch.update(ride, 16)
    end
    check("a wagon that turns the way commanded keeps the sign", ride.hitch.omegaSign == 1 and SETANG[101][2] > 0)
    HEADING[101] = nil
    ride.hitch.vx, ride.hitch.lastHeading = 0, nil
    for _ = 1, 40 do HorseHitch.update(ride, 16) end
end

-- a vehicle that is ONE body (a machine, a rigid trailer): driven as it is
do
    vehicle.components = nil
    local ride2 = { vehicle = { rootNode = 1 }, harness = true, rig = ride.rig }
    nodes[100] = { 0, 0.5, -1 }
    nodes[10] = { 0, 0.9, -1.5 }
    HorseHitch.hitch(ride2, target)
    SETLIN[100] = nil
    HorseHitch.update(ride2, 16)
    check("a vehicle without a list of bodies: its joint's body is driven (0.5 m behind the hook: 2 m/s forward)", SETLIN[100] ~= nil and math.abs(SETLIN[100][3] - 2) < 1e-9)
    HorseHitch.release(ride2)
    vehicle.components = { { node = 100 }, { node = 101 } }
    nodes[10] = { 0, 0.9, -1 }
end

-- the hook moves with the horse (it is a node rigid on the hip bone): the wagon is driven towards it
nodes[2] = { 0.8, 0.9, -0.2 }
HorseHitch.update(ride, 16)
check("the hook moved (the horse turned): the eye on the old place is driven towards it (+x)", SETLIN[100][1] > 0)
do
    local ax, ay, az = HorseHitch.anchor(ride)
    check("HorseHitch.anchor is the hook node's place", ax == 0.8 and ay == 0.9 and az == -0.2)
end
nodes[2] = { 0, 0.9, -1 }
for _ = 1, 40 do HorseHitch.update(ride, 16) end
do
    local ax, ay, az = HorseHitch.anchor({ rig = { traceEnds = { [1] = 2, [-1] = 3 } } })
    check("a rig without a hook node (an older harness): the middle of its two trace ends", ax == 0 and math.abs(az + 1.03) < 1e-9)
    check("no harness: no anchor", HorseHitch.anchor({}) == nil)
end

-- the height: the drawbar (the joint's body, a small share of the vehicle) is DRIVEN to the height of the hook (0.9), 1 m/s at most, whatever the load on it; the other bodies keep their own vertical speed
vehicle.total = 0.66
nodes[10] = { 0, 0.6, -1 }                       -- the eye 30 cm too low (on the ground)
VELS[101] = { 0, -0.2, 0 }
HorseHitch.update(ride, 16)
check("the eye 30 cm too low: the drawbar is driven up (4 * 0.3 = 1.2, at most 1 m/s), the rear body keeps its own vertical speed", SETLIN[100][2] == 1 and SETLIN[101][2] == -0.2)
nodes[10] = { 0, 0.9, -1 }
HorseHitch.update(ride, 16)
check("the eye at the height of the hook: the drawbar is held (no vertical speed)", SETLIN[100][2] == 0)
nodes[10] = { 0, 1.0, -1 }
HorseHitch.update(ride, 16)
check("the eye 10 cm too high: the drawbar is driven down (4 * 0.1 = 0.4 m/s)", math.abs(SETLIN[100][2] + 0.4) < 1e-9)
MASSES[100] = 2
vehicle.total = 2.5                              -- (2 t of 2.5: the joint sits on the main body)
nodes[10] = { 0, 0.6, -1 }
VELS[100] = { 0, -0.1, 0 }
HorseHitch.update(ride, 16)
check("the joint sits on the main body of the vehicle (2 t of 2.5 t): its height is not driven (a rigid trailer or a machine is not tilted by its plate)", SETLIN[100][2] == -0.1)
VELS[100], VELS[101] = nil, nil
MASSES[100] = 0.06
vehicle.total = 0.66
nodes[10] = { 0, 0.9, -1 }
check("there are no forces at all any more (everything is driven)", #forces == 0)
for _ = 1, 40 do HorseHitch.update(ride, 16) end

-- the safety limit: the wagon's speed changes by at most MAX_ACCEL_MS2 per second, always (a shove at a curb or a ditch must not fling it)
HorseHitch.MAX_ACCEL_MS2 = 8
nodes[10] = { 0, 0.9, -3.8 }                     -- 2.8 m behind the hook: 6 m/s wanted
SETLIN[101] = nil
HorseHitch.update(ride, 16)
check("the wagon is given at most 8 m/s2 * 0.016 s = 0.128 m/s more in a frame (not the 6 m/s wanted), whatever the pull limit is", SETLIN[101] ~= nil and math.abs(SETLIN[101][3] - 8 * 0.016) < 1e-9)
HorseHitch.MAX_ACCEL_MS2 = 1000
nodes[10] = { 0, 0.9, -1 }
for _ = 1, 40 do HorseHitch.update(ride, 16) end

-- a wagon that has tipped over is let go (the rear body's up axis more than 53 degrees from the vertical)
do
    TILT[101] = 70
    log = {}
    HorseHitch.update(ride, 16)
    local said = false
    for _, l in ipairs(log) do if l:find("the wagon tipped over", 1, true) then said = true end end
    check("a wagon tilted by 70 degrees has tipped over: it is let go (unhitched) and it is said", ride.hitch == nil and said)
    TILT[101] = nil
    pickResult = target
    HorseHitch.click()
    check("(hitched again for the rest)", ride.hitch ~= nil)
end

-- the speed limits are OFF by default (until the glue is stable): a load is given the speed it wants however heavy
vehicle.total = 14
HorseHitch.MAX_PULL_KN = 4
nodes[10] = { 0, 0.9, -3.2 }
SETLIN[101] = nil
HorseHitch.update(ride, 16)
check("SPEED_LIMITS off (the default): even 14 t at a pull limit of 4 kN is driven at the full speed wanted (4 * 2.2 = 8.8, at most 6 m/s)", HorseHitch.SPEED_LIMITS == false and SETLIN[101] ~= nil and math.abs(SETLIN[101][3] - 6) < 1e-9)
-- a horse is no tractor (SPEED_LIMITS on): the wagon's speed changes by at most MAX_PULL_KN / mass per second; a load far behind the hook is strained (a message, nothing else)
HorseHitch.SPEED_LIMITS = true
vehicle.total = 14
nodes[10] = { 0, 0.9, -3.2 }                     -- 2.2 m behind the hook, 0.8 m from the rear body
SETLIN[101] = nil
HorseHitch.update(ride, 16)
check("a 14 t load: the speed the wagon is given changes by at most 4 kN / 14 t * 0.016 s = 0.0046 m/s in a frame (not the 6 m/s wanted)", SETLIN[101] ~= nil and math.abs(SETLIN[101][3] - 4 / 14 * 0.016) < 1e-9)
check("... it is not strained yet (2.2 m: under STRAIN_STOP_M)", ride.hitch.strained ~= true)
nodes[10] = { 0, 0.9, -5.5 }                     -- 4.5 m behind the hook
HorseHitch.update(ride, 16)
check("4.5 m behind the hook: strained (a message follows, the horse does not stand and wait)", ride.hitch.strained == true)
nodes[10] = { 0, 0.9, -2.5 }                     -- 1.5 m: caught up
HorseHitch.update(ride, 16)
check("... and not strained again when the load is within STRAIN_GO_M of the hook", ride.hitch.strained == false)
nodes[10] = { 0, 0.9, -4 }                       -- 3 m: between the two: the state stays (no stop and go at the edge)
HorseHitch.update(ride, 16)
check("between STRAIN_GO_M and STRAIN_STOP_M the state stays (hysteresis)", ride.hitch.strained == false)
nodes[10] = { 0, 0.9, -5.5 }
log = {}
for _ = 1, 6 do HorseHitch.update(ride, 1000) end
do
    local said = false
    for _, line in ipairs(log) do if line:find("cannot move this load (14.0 t)", 1, true) then said = true end end
    check("a load that does not come after STUCK_S seconds: said once that the horse cannot move it", said and ride.hitch.reported == true)
end
-- a light wagon is only limited by its own mass: 4 kN / 0.66 t = 6 m/s2: 0.1 m/s in a frame of 16 ms
vehicle.total = 0.66
nodes[10] = { 0, 0.9, -3.8 }
SETLIN[101] = nil
HorseHitch.update(ride, 16)
check("a 0.66 t wagon can change its speed by 4 / 0.66 * 0.016 = 0.097 m/s in a frame", SETLIN[101] ~= nil and math.abs(SETLIN[101][3] - 4 / 0.66 * 0.016) < 1e-9)
HorseHitch.MAX_PULL_KN = 1000
HorseHitch.SPEED_LIMITS = false
vehicle.total = nil
nodes[10] = { 0, 0.9, -1 }
for _ = 1, 40 do HorseHitch.update(ride, 16) end

-- a steady gap is closed by the integral: the eye 0.5 m behind the hook for 100 frames: the added speed grows (2 / s2 * 0.5 m * 1.6 s = 1.6 m/s), stays under INTEGRAL_MAX_MS, and is reset when the wagon is far away
HorseHitch.INTEGRAL_GAIN = 2
ride.hitch.ix, ride.hitch.iz = 0, 0
nodes[10] = { 0, 0.9, -1.5 }
for _ = 1, 100 do HorseHitch.update(ride, 16) end
check("a steady gap of 0.5 m for 100 frames: the integral has added about 1.6 m/s forward (so the wagon is driven at 2 + 1.6 m/s)", math.abs(ride.hitch.iz - 1.6) < 1e-6 and ride.hitch.ix == 0 and math.abs(SETLIN[100][3] - 3.6) < 1e-6)
for _ = 1, 400 do HorseHitch.update(ride, 16) end
check("... and it is limited (INTEGRAL_MAX_MS)", ride.hitch.iz == HorseHitch.INTEGRAL_MAX_MS)
nodes[10] = { 0, 0.9, -6 }
HorseHitch.update(ride, 16)
check("a wagon far away (5 m: over INTEGRAL_RANGE_M) has no integral (the catch-up is for that)", ride.hitch.iz == 0 and ride.hitch.ix == 0)
nodes[10] = { 0, 0.9, -1 }
HorseHitch.INTEGRAL_GAIN = 0
for _ = 1, 40 do HorseHitch.update(ride, 16) end

-- a gap is still logged after the first seconds (once a second), a wagon on the hook is not
ride.hitch.loggedMs, ride.hitch.logMs = 60000, 1000
nodes[10] = { 0, 0.9, -2 }                       -- 1 m behind the hook
log = {}
HorseHitch.update(ride, 16)
check("after the first seconds a gap of 1 m (over LOG_GAP_M) is still logged, with the gap integral", (function() for _, l in ipairs(log) do if l:find("eye off the hook by 1.00", 1, true) and l:find("gap integral", 1, true) then return true end end return false end)())
nodes[10] = { 0, 0.9, -1 }
ride.hitch.logMs = 1000
log = {}
HorseHitch.update(ride, 16)
check("... but an eye on the hook is not (the log stays quiet when all is well)", #log == 0)

-- the log line of the first seconds says what the drive does
ride.hitch.loggedMs, ride.hitch.logMs = 0, 1000
log = {}
for _ = 1, 70 do HorseHitch.update(ride, 16) end
do
    local line
    for _, l in ipairs(log) do if l:find("eye off the hook by", 1, true) then line = l end end
    check("for the first seconds the log says how far the eye is off the hook, the speeds, the turn and the mass", line ~= nil and line:find("turn", 1, true) ~= nil and line:find("strained", 1, true) ~= nil)
end

-- the ring gate for the harness tool
check("ring gate: a harnessed horse is there and not hitched: no, it is hitched already", HorseHitch.ringFree() == false)

-- unhitch: the same key
message = HorseHitch.click()
check("the click with a hitched horse unhitches (and says so)", message ~= nil and message:find("unhitched", 1, true) ~= nil and ride.hitch == nil)
check("unhitching puts the brake back and the support leg down", brake[#brake] == false and support[#support] == false)
check("ring gate: the horse is free again: the ring shows", HorseHitch.ringFree() == true)
player = false
check("ring gate: no player position, no ring", HorseHitch.ringFree() == false)
player = true

-- far away horse: the click hitches nobody
nodes[1] = { 0, 0, 50 }
pickResult = target
check("the harnessed horse is 50 m from the joint: the click is the harness's own", HorseHitch.click() == nil and ride.hitch == nil)
nodes[1] = { 0, 0, 0 }
ride.harness = false
check("a horse without a harness is not hitched", HorseHitch.click() == nil)
ride.harness = true

-- the vehicle is gone: let go quietly
HorseHitch.click()
check("hitched again", ride.hitch ~= nil)
vehicle.isDeleted = true
HorseHitch.update(ride, 16)
check("the vehicle is deleted: let go (no error, no brake call on a dead vehicle)", ride.hitch == nil)
vehicle.isDeleted = false

-- the eye on the wagon's own main body (no tongue): the eye is NOT lifted, the lift would be the whole trailer's; belted logs add to the mass the game counts and must not change that
do
    local savedMasses, savedMass = MASSES, MASS
    MASSES = { [100] = 0.06, [101] = 0.6 }
    local small = HorseHitch.rigidEye({ vehicle = { components = { { node = 100 }, { node = 101 } } }, component = 100 })
    MASSES = { [100] = 0.7, [101] = 0.1 }
    local frame = HorseHitch.rigidEye({ vehicle = { components = { { node = 100 }, { node = 101 } } }, component = 100 })
    MASSES = { [100] = 0.7 }
    local single = HorseHitch.rigidEye({ vehicle = { components = { { node = 100 } }, getTotalMass = function() return 9 end }, component = 100 })
    check("a small tongue body (60 kg of 660) is no rigid eye: it is lifted as before", small == false)
    check("an eye on the main frame (700 of 800 kg) is rigid: no tongue to lift", frame == true)
    check("a single body is rigid whatever the game counts for the vehicle (9 t with belted logs)", single == true)
    MASSES, MASS = savedMasses, savedMass
end

-- belts first: unfastened tension belts are thrown before the hitch, so the loose logs are part of the frame and not shoved about
do
    local thrown = 0
    local function belted(fastened, has)
        return { spec_tensionBelts = { hasTensionBelts = has ~= false, areAllBeltsFastened = fastened }, setAllTensionBeltsActive = function(self, active) thrown = thrown + (active and 1 or 0) end }
    end
    check("a trailer with unfastened tension belts: they are thrown (setAllTensionBeltsActive(true))", HorseHitch.throwBelts(belted(false)) == true and thrown == 1)
    check("belts that are fastened already: nothing is done", HorseHitch.throwBelts(belted(true)) == false and thrown == 1)
    check("a vehicle without belts (or no belts spec): nothing is done", HorseHitch.throwBelts(belted(false, false)) == false and HorseHitch.throwBelts({}) == false and thrown == 1)
    HorseHitch.AUTO_BELTS = false
    check("AUTO_BELTS = false: the belts are left alone", HorseHitch.throwBelts(belted(false)) == false and thrown == 1)
    HorseHitch.AUTO_BELTS = true
    check("a belt call that fails does not break the hitch", HorseHitch.throwBelts({ spec_tensionBelts = { hasTensionBelts = true, areAllBeltsFastened = false }, setAllTensionBeltsActive = function() error("boom") end }) == false)
end

-- gentle only for loose cargo: a wagon whose belts are fastened (thrown first) is as quick as any other
do
    check("belts fastened (or none): not a loose load, no gentle lift and walk-in", HorseHitch.hasLooseLoad({ spec_tensionBelts = { hasTensionBelts = true, areAllBeltsFastened = true } }) == false and HorseHitch.hasLooseLoad({}) == false)
    check("belts that are not fastened (AUTO_BELTS off, or they could not be thrown): a loose load: gentle", HorseHitch.hasLooseLoad({ spec_tensionBelts = { hasTensionBelts = true, areAllBeltsFastened = false } }) == true)
    check("the quick values are the old ones and the gentle ones are slower", HorseHitch.HANDOVER_LIFT_MS == 1 and HorseHitch.APPROACH_ACCEL_MS2 == 8 and HorseHitch.GENTLE_LIFT_MS < HorseHitch.HANDOVER_LIFT_MS and HorseHitch.GENTLE_APPROACH_ACCEL_MS2 < HorseHitch.APPROACH_ACCEL_MS2)
end

-- a wagon with no tongue is TILTED about its axle to bring the eye up, not lifted: the speed of a point of a body turning about the axle
do
    nodes[701], nodes[702], nodes[703] = { -0.8, 0.5, 0 }, { 0.8, 0.5, 0 }, { 0, 0.4, 3 }          -- two wheels (the axle at z 0) and the eye 3 m ahead of it
    local frame = { components = { { node = 704 } }, spec_wheels = { wheels = { { node = 701 }, { node = 702 } } } }
    local ax, ay, az = HorseHitch.axleOf(frame)
    check("the axle is the middle of the wheels", math.abs(ax) < 1e-9 and math.abs(ay - 0.5) < 1e-9 and math.abs(az) < 1e-9)
    check("a vehicle without wheels shows no axle", HorseHitch.axleOf({ components = {} }) == nil)
    local tilt = HorseHitch.tiltOf({ vehicle = frame }, 1, 0, 3)
    check("tilting the eye up at 1 m/s 3 m ahead of the axle: 1/3 rad/s about the horizontal axis across the wagon (nose up)", tilt ~= nil and math.abs(tilt.wx + 1 / 3) < 1e-9 and math.abs(tilt.wz) < 1e-9 and math.abs(tilt.length - 3) < 1e-9)
    local vx, vy, vz, wx, wz = HorseHitch.tiltVelocity(tilt, 0, 0.4, 3, 1)
    check("the eye itself rises at that 1 m/s (v = w x r)", math.abs(vy - 1) < 1e-9 and math.abs(vx) < 1e-9)
    vx, vy, vz = HorseHitch.tiltVelocity(tilt, 0, 0.5, 0, 1)
    check("a point on the axle does not move: the wheels stay on the ground", math.abs(vx) < 1e-9 and math.abs(vy) < 1e-9 and math.abs(vz) < 1e-9)
    vx, vy, vz, wx, wz = HorseHitch.tiltVelocity(tilt, 0, 0.5, 1.5, -1)
    check("half way to the eye: half the speed up, and the engine's sign flips only the angular velocity given", math.abs(vy - 0.5) < 1e-9 and math.abs(wx - 1 / 3) < 1e-9)
    check("the eye right above the axle has no lever: no tilt", HorseHitch.tiltOf({ vehicle = frame }, 1, 0, 0.2) == nil)
    local h = {}
    HorseHitch.checkTiltSign(h, 0.5, 1, 0.016)
    for i = 1, 9 do HorseHitch.checkTiltSign(h, 0.5 - 0.001 * i, 1, 0.016) end
    check("commanded up and moving down frame after frame: the engine's sign is flipped", h.tiltSign == -1)
    h = {}
    HorseHitch.checkTiltSign(h, 0.5, 1, 0.016)
    for i = 1, 9 do HorseHitch.checkTiltSign(h, 0.5 + 0.001 * i, 1, 0.016) end
    check("moving the way it is told: the sign stays", h.tiltSign == nil)
end

-- a vehicle's own hitch (kind "hitch": the body is right behind the plate) gets a rigid tow bar: the pin is TOW_BAR_M behind the hook, the bar is drawn straight from the hook to the plate
do
    local ride3 = { vehicle = { rootNode = 1 }, harness = true, harnessGear = "rope", rig = ride.rig }
    local before3 = #pieces
    HorseHitch.hitch(ride3, { vehicle = vehicle, node = 10, component = 100, kind = "hitch" })
    local bar = pieces[#pieces]
    check("a vehicle's own hitch gets a tow bar: ONE piece, steel, TOW_BAR_DIAMETER thick, from the hook ring's rear point",
        ride3.hitch.barLength == HorseHitch.TOW_BAR_M and #pieces == before3 + 1 and bar.diameter == HorseHitch.TOW_BAR_DIAMETER and bar.rfMaterialDone == true and bar.link == 3)
    nodes[10] = { 0, 0.4, -2.6 }                     -- the pin: 1.6 m behind the middle of the trace ends (z -1)
    forces = {}
    HorseHitch.update(ride3, 16)
    SETLIN[100] = nil
    HorseHitch.update(ride3, 16)
    check("glued at the end of the bar: a joint there is held (no horizontal speed), and the machine is not lifted by its plate (no force at all)", SETLIN[100] ~= nil and math.abs(SETLIN[100][1]) < 1e-9 and math.abs(SETLIN[100][3]) < 1e-9 and #forces == 0)
    nodes[10] = { 0, 0.4, -1 }                       -- the vehicle ran up to the hook
    nodes[100] = { 0, 0.4, -1 }
    HorseHitch.update(ride3, 16)
    check("a vehicle that runs up to the horse is driven back to the end of the bar (backwards: the bar keeps it clear, 1.6 m behind the hook)", SETLIN[100][3] < 0)

    bar.referenceFrame = 5
    HorseHitch.update(ride3, 16)
    check("the tow bar is tied to the vehicle's hitch once its shape has loaded", bar.target == 10)
    HorseHitch.release(ride3)
    -- animal welfare: a tractor on the tow bar that is far from the pin is walked in gently (not snatched into the horse's rump), until it has come to the pin once
    local ride5 = { vehicle = { rootNode = 1 }, harness = true, harnessGear = "rope", rig = ride.rig }
    HorseHitch.hitch(ride5, { vehicle = vehicle, node = 10, component = 100, kind = "hitch" })
    nodes[10], nodes[100] = { 0, 0.4, -12 }, { 0, 0.4, -12 }
    SETLIN[100] = nil
    HorseHitch.update(ride5, 16)
    local walkIn = math.abs(SETLIN[100][3])
    check("a tractor on the tow bar far from the pin: its speed grows by at most TOW_APPROACH_ACCEL_MS2 (not the snatch of MAX_ACCEL_MS2)", walkIn > 0 and walkIn <= HorseHitch.TOW_APPROACH_ACCEL_MS2 * 0.016 + 1e-9 and ride5.hitch.docked ~= true)
    nodes[10], nodes[100] = { 0, 0.4, -2.6 }, { 0, 0.4, -2.6 }
    HorseHitch.update(ride5, 16)
    check("... once it has come to the pin it is docked and pulled normally", ride5.hitch.docked == true)
    HorseHitch.release(ride5)
    -- a docked tow bar is a steel rod: it follows a gap about three times as hard as the wagon's pin (no rubber band)
    local function gapSpeed(rod)
        HorseHitch.ROD = rod
        local r = { vehicle = { rootNode = 1 }, harness = true, harnessGear = "rope", rig = ride.rig }
        HorseHitch.hitch(r, { vehicle = vehicle, node = 10, component = 100, kind = "hitch" })
        r.hitch.docked = true
        nodes[10], nodes[100] = { 0, 0.4, -2.6 }, { 0, 0.4, -2.6 }
        HorseHitch.update(r, 16)
        nodes[10], nodes[100] = { 0, 0.4, -2.8 }, { 0, 0.4, -2.8 }        -- 0.2 m behind the pin
        SETLIN[100] = nil
        HorseHitch.update(r, 1000)
        HorseHitch.release(r)
        return SETLIN[100] ~= nil and math.abs(SETLIN[100][3]) or 0
    end
    local rodSpeed, springSpeed = gapSpeed(true), gapSpeed(false)
    HorseHitch.ROD = true
    check("a docked tow bar follows a gap harder than a wagon's pin: 0.2 m off gives more speed (ROD) than before", rodSpeed > springSpeed * 1.5 and rodSpeed > 0)
    nodes[10] = { 0, 0.9, -1 }
    local ride4 = { vehicle = { rootNode = 1 }, harness = true, rig = ride.rig }
    local before4 = #pieces
    HorseHitch.hitch(ride4, { vehicle = vehicle, node = 10, component = 100, kind = "drawbar eye" })
    check("a trailer's drawbar eye gets no tow bar (its own drawbar is the clearance): no pieces, no bar length", ride4.hitch.barLength == 0 and #pieces == before4)
    HorseHitch.release(ride4)
end

-- from the saddle, like a tractor: the game's attach key shows "Hitch" with a joint behind the hook within reach, "Unhitch" while something is hitched
do
    local horse = { rootNode = 1, isDeleted = false }
    horse.addActionEvent = function(self, events, action, target, callback, a, b, c, d, e, f, g) events[action] = { actionEventId = 77 }; SADDLEEVENT = { action = action, target = target, callback = callback }; return true, 77 end
    horse.clearActionEventsTable = function(self, events) for k, v in pairs(events) do g_inputBinding:removeActionEvent(v.actionEventId); events[k] = nil end end
    horse.requestActionEventUpdate = function() SADDLEREQUESTS = (SADDLEREQUESTS or 0) + 1 end
    local rideS = { vehicle = horse, harness = true, ridden = true, rig = ride.rig }
    HorseLead.rides = { rideS }
    nodes[1] = { 0, 0, 0 }
    NEARESTJOINT = { vehicle = vehicle, node = 10, component = 100, kind = "drawbar eye", x = 0, y = 0.4, z = -2.5 }
    SADDLEREQUESTS = 0
    HorseHitch.updateSaddle()
    check("a ride that was just mounted: the horse is asked to register its events (once)", SADDLEREQUESTS == 1 and (function() HorseHitch.updateSaddle(); return SADDLEREQUESTS == 1 end)())
    Rideable.onRegisterActionEvents(horse, true, true)
    check("the appended Rideable:onRegisterActionEvents puts the game's attach key on the horse that is ridden in its harness, text priority very high, off for now",
        SADDLEEVENT ~= nil and SADDLEEVENT.action == "ATTACH" and SADDLEEVENT.target == horse and HorseHitch.saddle[horse].id == 77 and SADDLE.priority[77] == 5 and SADDLE.active[77] == false)
    HorseHitch.updateSaddle()
    check("a joint behind the hook within reach: the key shows \"Hitch\" (the game's action_attach text)", SADDLE.active[77] == true and SADDLE.text[77] == "action_attach")
    check("... the lookup is from the hook (the middle of the trace ends, z -1) with the reach, not for the horse itself", NEARESTARGS[1] == 0 and NEARESTARGS[2] == -1 and NEARESTARGS[3] == HorseHitch.SADDLE_REACH_M and NEARESTARGS[4] == horse)
    -- tabbed out of the game and back: the binding forgot the event (its id is not among the events any more), the horse's table still names it: the key is asked for again, at most once a second
    g_inputBinding.events = { [5] = true }
    g_time = 5000
    local askedBefore = SADDLEREQUESTS
    HorseHitch.updateSaddle()
    check("an action event the input binding has forgotten: the horse is asked to register its events again", SADDLEREQUESTS == askedBefore + 1)
    HorseHitch.updateSaddle()
    check("... but not again within REREGISTER_MS", SADDLEREQUESTS == askedBefore + 1)
    g_time = 5000 + HorseHitch.REREGISTER_MS
    HorseHitch.updateSaddle()
    check("... and once the second is over, again (it was not registered yet)", SADDLEREQUESTS == askedBefore + 2)
    g_time, g_inputBinding.events = nil, nil
    HorseHitch.updateSaddle()
    check("the event is there again: the key shows \"Hitch\" as before", SADDLE.active[77] == true and SADDLE.text[77] == "action_attach")
    NEARESTJOINT = { vehicle = vehicle, node = 10, component = 100, kind = "drawbar eye", x = 0, y = 0.4, z = 2.5 }
    HorseHitch.updateSaddle()
    check("a joint in front of the horse is not offered", SADDLE.active[77] == false)
    NEARESTJOINT = nil
    HorseHitch.updateSaddle()
    check("nothing near: the key is off", SADDLE.active[77] == false)
    NEARESTJOINT = { vehicle = vehicle, node = 10, component = 100, kind = "drawbar eye", x = 0, y = 0.4, z = -2.5 }
    HorseHitch.onSaddleAttach(horse, "ATTACH", 1)
    check("the key pressed: the horse is hitched to that joint", rideS.hitch ~= nil and rideS.hitch.node == 10)
    HorseHitch.updateSaddle()
    check("while something is hitched the key shows \"Unhitch\" (action_detach)", SADDLE.active[77] == true and SADDLE.text[77] == "action_detach")
    HorseHitch.onSaddleAttach(horse, "ATTACH", 1)
    check("pressed again: let go", rideS.hitch == nil)
    -- the real joint: the rope pulls the eye to the hook, then the game's joint takes over (HorseJoint here is a fake that records what it is asked)
    vehicle.spec_attachable = { inputAttacherJoints = { { node = 10 } } }
    JOINTED, JOINTREMOVED, JOINTOK = nil, false, true
    HorseJoint = { attach = function(h, t) JOINTED = t; return JOINTOK, "no" end, remove = function() JOINTREMOVED = true end }
    HorseHitch.onSaddleAttach(horse, "ATTACH", 1)
    check("an input attacher joint with the real joint on: the rope hitches first and is marked for the handover, the game's joint is not asked yet", rideS.hitch ~= nil and rideS.hitch.handover == true and JOINTED == nil and rideS.joined == nil)
    local goalY = rideS.hitch.goalHeight
    check("every trailer's eye is held at the height of a tractor's joint (0.81 m), whatever the trailer says", goalY == 0.81)
    nodes[10], nodes[100] = { 0, goalY - 0.5, -3 }, { 0, goalY - 0.5, -3 }
    HorseHitch.update(rideS, 250)
    check("step one is only the tongue's lift: the eye is 0.5 m below its height, so it is not lifted yet and the wagon is not pulled in (no horizontal speed written)", rideS.hitch.lifted ~= true and SETLIN[100] ~= nil and SETLIN[100][1] == SETLIN[100][1] and rideS.hitch.settledS == nil)
    check("... the wagon is held still meanwhile: no horizontal speed on its body, its brake stays on", SETLIN[100][1] == 0 and SETLIN[100][3] == 0 and brake[#brake] == false)
    check("... and the tongue is driven up at its own ramp (the accel times the step), not at what the physics reports", math.abs(SETLIN[100][2] - HorseHitch.HANDOVER_LIFT_ACCEL_MS2 * 0.25) < 1e-9)
    -- a wagon whose eye is not on a free tongue: driving it up tilts the heavy body, so the lift is given up and the eye stays where it rests
    local bodyNode = rideS.hitch.body or rideS.hitch.component
    local savedTilt = TILT[bodyNode]
    TILT[bodyNode] = 0
    rideS.hitch.liftTilt0, rideS.hitch.liftEye0, rideS.hitch.liftAborted = nil, nil, nil
    local goalBefore = rideS.hitch.goalHeight
    HorseHitch.update(rideS, 250)
    check("the lift starts from the wagon's tilt as it stands (no abort while it stays level)", rideS.hitch.liftAborted ~= true and rideS.hitch.liftTilt0 ~= nil)
    TILT[bodyNode] = 6                                                               -- degrees: the nose came up
    HorseHitch.update(rideS, 250)
    check("a heavy body that tilts more than HANDOVER_TILT_MAX_RAD (4 degrees) during the lift: the lift is given up", rideS.hitch.liftAborted == true)
    check("... and the eye is to stay where it rests (the height it had before the lift, not the 0.81 m of a tractor's joint)", rideS.hitch.goalHeight == rideS.hitch.liftEye0 and rideS.hitch.goalHeight ~= goalBefore)
    TILT[bodyNode] = savedTilt
    rideS.hitch.goalHeight, rideS.hitch.liftAborted, rideS.hitch.liftBoost = goalBefore, nil, nil
    -- a tongue that stays stuck: a growing upward force on its body (at most LIFT_FORCE_SHARE of the weight), and after the time is up it is held where it is
    forces = {}
    local savedShare, savedStall = HorseHitch.LIFT_FORCE_SHARE, HorseHitch.LIFT_STALL_S
    HorseHitch.LIFT_FORCE_SHARE, HorseHitch.LIFT_STALL_S = 0.4, 100                    -- (the force is off by default, and the stop is looked at below)
    rideS.hitch.lifted, rideS.hitch.liftS, rideS.hitch.liftCheckS, rideS.hitch.liftCheckY = nil, 0, nil, nil
    rideS.hitch.stallS, rideS.hitch.stallY = nil, nil
    for _ = 1, 8 do HorseHitch.update(rideS, 250) end                                  -- (the eye does not move: 2 s)
    local upForce = forces[#forces]
    check("a stuck tongue gets an upward force on its body, growing", upForce ~= nil and upForce[1] == 100 and upForce[3] > 0 and (rideS.hitch.liftBoost or 0) > 0)
    check("... at most LIFT_FORCE_SHARE of the vehicle's weight", upForce[3] <= HorseHitch.LIFT_FORCE_SHARE * (vehicle.total or 0.66) * 9.81 * 1.5 + 1e-6)
    HorseHitch.LIFT_FORCE_SHARE, HorseHitch.LIFT_STALL_S = savedShare, savedStall
    HorseHitch.update(rideS, 11000)
    check("a tongue that never came up (the force did not help either): the eye is held where it is, not driven on while the wagon is walked in", rideS.hitch.goalHeight < goalBefore - 0.2)
    -- the tongue reaches its stop (a hinge limit): not come up for LIFT_STALL_S while driven: the eye is held where it is, not driven on
    rideS.hitch.goalHeight, rideS.hitch.lifted, rideS.hitch.liftS, rideS.hitch.liftV, rideS.hitch.stallS, rideS.hitch.stallY, rideS.hitch.liftAborted = goalBefore, nil, 0, 0, nil, nil, nil
    for _ = 1, 8 do HorseHitch.update(rideS, 250) end
    check("a tongue that does not come up while driven (its stop): after LIFT_STALL_S it is as high as it goes: the eye is held where it is", rideS.hitch.lifted == true and rideS.hitch.goalHeight < goalBefore - 0.2)
    rideS.hitch.goalHeight = goalBefore
    forces = {}
    check("... and after HANDOVER_LIFT_MAX_S it goes on to the pull-in (a hinge at its stop does not get further)", rideS.hitch.lifted == true)
    check("the eye is not at the hook yet: no handover", rideS.hitch ~= nil and JOINTED == nil)
    check("the walk-in has no integral of the gap (it wound up to its limit and pushed the eye past the hook)", (rideS.hitch.ix or 0) == 0 and (rideS.hitch.iz or 0) == 0)
    local hx, _, hz = HorseHitch.anchor(rideS)
    local hy = HorseHitch.groundY(hx, hz) + goalY                         -- (at the hook, and up at the height it is held at: the handover wants both)
    nodes[10], nodes[100] = { hx, hy, hz }, { hx, hy, hz }
    HorseHitch.update(rideS, 100)
    check("at the hook but not for long enough: still the rope", rideS.hitch ~= nil and JOINTED == nil)
    HorseHitch.update(rideS, 150)
    check("at the hook for HANDOVER_HOLD_S: the rope lets go and the game's joint is asked for that eye", rideS.hitch == nil and rideS.joined ~= nil and JOINTED ~= nil and JOINTED.node == 10 and JOINTED.vehicle == vehicle)
    check("joined: the brake is let off (the rope's release put it on, nobody sits in the wagon to take it off), the last call before this", brake[#brake] == true)
    brake[#brake + 1] = "marker"
    HorseHitch.keepJoined(rideS)
    check("... and kept off by the per-frame call", brake[#brake] == true)
    -- the horse's body gets the speed the game moves it at (a kinematic body has none for the joint otherwise: the wagon trailed behind by an amount that grew with the gait)
    nodes[55] = { 0, 0, 0 }
    horse.components = { { node = 55 } }
    horse.spec_rideable = { currentSpeed = 3, currentTurnAngle = math.pi / 2, currentTurnSpeed = 0.5 }
    HorseHitch.keepJoined(rideS)
    check("a joined horse: its body is given its speed (3 m/s towards +x at a turn angle of 90 degrees) ...", SETLIN[55] ~= nil and math.abs(SETLIN[55][1] - 3) < 1e-9 and SETLIN[55][2] == 0 and math.abs(SETLIN[55][3]) < 1e-9)
    check("... and its turning speed (0.5 rad/s about up)", SETANG[55] ~= nil and SETANG[55][2] == 0.5)
    SETLIN[55] = nil
    HorseHitch.FEED_VELOCITY = false
    HorseHitch.keepJoined(rideS)
    check("... and not with FEED_VELOCITY off", SETLIN[55] == nil)
    HorseHitch.FEED_VELOCITY = true
    horse.components, horse.spec_rideable = nil, nil
    HorseHitch.updateSaddle()
    check("joined: the key shows \"Unhitch\"", SADDLE.active[77] == true and SADDLE.text[77] == "action_detach")
    HorseHitch.onSaddleAttach(horse, "ATTACH", 1)
    check("pressed again: the joint is taken off the horse, the wagon's brake goes back on", rideS.joined == nil and JOINTREMOVED == true and brake[#brake] == false)
    JOINTOK, JOINTED = false, nil
    local savedEye = HorseHitch.EYE_HEIGHT_M
    HorseHitch.EYE_HEIGHT_M = nil                                          -- (without the fixed height: the fallback, the hook's height capped by what the hinge reaches)
    HorseHitch.onSaddleAttach(horse, "ATTACH", 1)
    HorseHitch.update(rideS, 500)
    HorseHitch.update(rideS, 500)
    check("the game refuses the joint: it stays on the rope", JOINTED ~= nil and rideS.hitch ~= nil and rideS.joined == nil)
    check("an eye whose body has no hinge to another body cannot be lifted: it is held where it is (not lifted to the hook)", rideS.hitch.goalHeight == nodes[10][2])
    HorseHitch.release(rideS)
    -- the eye on a tongue that hangs on the axle by a hinge of 23 degrees of pitch, 1.2 m in front of the eye: the eye is lifted towards the hook, but no higher than the hinge lifts it
    local savedComponents, savedJoints = vehicle.components, vehicle.componentJoints
    vehicle.components = { { node = 99 }, { node = 100 } }
    vehicle.componentJoints = { { componentIndices = { 1, 2 }, jointNode = 300, rotLimit = { math.rad(23), 0, 0 } } }
    nodes[10][2] = 0.1                                 -- (the tongue lies on the ground)
    nodes[100][2] = 0.1
    nodes[300] = { nodes[10][1], nodes[10][2], nodes[10][3] + 1.2 }
    local _, hookY = HorseHitch.anchor(rideS)
    HorseHitch.onSaddleAttach(horse, "ATTACH", 1)
    local reach = 1.2 * math.sin(math.rad(23))
    check("... a tongue on a hinge: the eye is held at what the hinge reaches (0.9 of it) above where the eye is, below the hook", math.abs(rideS.hitch.goalHeight - (nodes[10][2] + HorseHitch.REACH_SHARE * reach)) < 1e-6 and rideS.hitch.goalHeight < hookY)
    HorseHitch.release(rideS)
    nodes[300] = { nodes[10][1], nodes[10][2], nodes[10][3] + 0.1 }
    nodes[10][2] = nodes[10][2] - 0.2
    HorseHitch.onSaddleAttach(horse, "ATTACH", 1)
    check("... and a hook below that reach: held at the hook", rideS.hitch ~= nil and math.abs(rideS.hitch.goalHeight - math.min(hookY, nodes[10][2] + HorseHitch.REACH_SHARE * math.sqrt(0.1 ^ 2 + 0.2 ^ 2) * math.sin(math.rad(23)))) < 1e-6)
    HorseHitch.release(rideS)
    HorseHitch.EYE_HEIGHT_M = savedEye
    vehicle.components, vehicle.componentJoints = savedComponents, savedJoints
    HorseJoint = nil
    vehicle.spec_attachable = nil
    rideS.ridden = nil
    HorseHitch.updateSaddle()
    check("the rider got off: the key is taken off the horse again", HorseHitch.saddle[horse] == nil and SADDLE.removed[#SADDLE.removed] == 77)
    -- a horse in its harness that is not ridden / without a harness has no key
    rideS.ridden = true
    rideS.harness = nil
    check("a ridden horse without a harness gets no key", HorseHitch.registerSaddle(horse, true) == false)
    HorseLead.rides = { ride }
end

-- the keys of what the horse pulls, for the player on foot: the vehicle's own registration replayed in the PLAYER context
do
    local ride6 = { vehicle = { rootNode = 1 }, harness = true, rig = ride.rig }
    INPUTLOG = {}
    HorseHitch.hitch(ride6, target)
    check("hitched: the vehicle's registration of its keys is replayed in the PLAYER context (begin, pre-register and register as active for input, end)",
        INPUTLOG[1] == "begin PLAYER" and INPUTLOG[2] == "onPreRegisterActionEvents true true" and INPUTLOG[3] == "onRegisterActionEvents true true" and INPUTLOG[4] == "end")
    check("... and the vehicle is remembered as keyed", HorseHitch.keyed[vehicle] == true)
    INPUTLOG = {}
    Vehicle.registerActionEvents(vehicle)
    check("the game registering the vehicle's events again (it cleared the player's): they are made again, after its own", INPUTLOG[1] == "game registers" and INPUTLOG[2] == "begin PLAYER" and INPUTLOG[4] == "onRegisterActionEvents true true" and INPUTLOG[5] == "end")
    INPUTLOG = {}
    Vehicle.registerActionEvents({})
    check("... but for a vehicle nobody pulls it does nothing of its own", INPUTLOG[1] == "game registers" and #INPUTLOG == 1)
    INPUTLOG = {}
    HorseHitch.release(ride6)
    check("unhitched: the game is asked to update the vehicle's events (not active for input: the specs clear the player's), nothing is registered for the player", INPUTLOG[1] == "vehicle update" and #INPUTLOG == 1 and HorseHitch.keyed[vehicle] == nil)
    INPUTLOG = {}
    Vehicle.registerActionEvents(vehicle)
    check("... and the game's later registrations are no longer followed", #INPUTLOG == 1)
    -- a spec that breaks: the modification is ended, nothing crashes, said once
    SPECERROR = true
    INPUTLOG = {}
    log = {}
    local ride7 = { vehicle = { rootNode = 1 }, harness = true, rig = ride.rig }
    HorseHitch.hitch(ride7, target)
    check("a spec that breaks while registering: the modification is ended again (no stuck input context), the hitch works, said once", INPUTLOG[1] == "begin PLAYER" and INPUTLOG[#INPUTLOG] == "end" and ride7.hitch ~= nil)
    SPECERROR = false
    HorseHitch.release(ride7)
    -- switched off
    HorseHitch.INHERIT_KEYS = false
    INPUTLOG = {}
    local ride8 = { vehicle = { rootNode = 1 }, harness = true, rig = ride.rig }
    HorseHitch.hitch(ride8, target)
    check("HorseHitch.INHERIT_KEYS = false: the player gets none of the vehicle's keys", #INPUTLOG == 0)
    HorseHitch.release(ride8)
    HorseHitch.INHERIT_KEYS = true
end

-- the keys follow the player's input context: PLAYER on foot, VEHICLE while he rides the horse (a vehicle's keys only work in VEHICLE)
do
    local ride9 = { vehicle = { rootNode = 1 }, harness = true, rig = ride.rig }
    CONTEXT = "PLAYER"
    INPUTLOG = {}
    HorseHitch.hitch(ride9, target)
    check("on foot the hitched vehicle's keys are registered in the PLAYER context", INPUTLOG[1] == "begin PLAYER" and HorseHitch.keyContext[vehicle] == "PLAYER")
    INPUTLOG = {}
    HorseHitch.updateKeys()
    check("nothing changed: nothing is registered again", #INPUTLOG == 0)
    CONTEXT = "VEHICLE"
    HorseHitch.updateKeys()
    check("the player mounted the horse (context VEHICLE): the keys are registered again, there", INPUTLOG[1] == "begin VEHICLE" and INPUTLOG[3] == "onRegisterActionEvents true true" and HorseHitch.keyContext[vehicle] == "VEHICLE")
    INPUTLOG = {}
    HorseHitch.updateKeys()
    check("... once", #INPUTLOG == 0)
    CONTEXT = "MENU"
    HorseHitch.updateKeys()
    check("in another context (a menu) nothing is done", #INPUTLOG == 0)
    CONTEXT = "PLAYER"
    HorseHitch.updateKeys()
    check("back on foot: registered in PLAYER again", INPUTLOG[1] == "begin PLAYER")
    INPUTLOG = {}
    CONTEXT = "VEHICLE"
    Vehicle.registerActionEvents(vehicle)
    check("the game registering the vehicle's events again while riding: made again in VEHICLE, after its own", INPUTLOG[1] == "game registers" and INPUTLOG[2] == "begin VEHICLE")
    HorseHitch.release(ride9)
    CONTEXT = "PLAYER"
end

-- the gait of a horse that pulls: never a gallop, a trot at the most (the game's gait numbers are not in the order of the speeds: walk, canter, trot, gallop), whatever the load
do
    local G0 = Rideable.GAITTYPES
    pickResult = target
    HorseHitch.click()
    check("GALLOP_LIMIT on (the default), SPEED_LIMITS off: a pulling horse never gallops, the other gaits are its steering's own", HorseHitch.SPEED_LIMITS == false and HorseHitch.limitGait(ride, G0.GALLOP) == G0.TROT and HorseHitch.limitGait(ride, G0.TROT) == G0.TROT and HorseHitch.limitGait(ride, G0.WALK) == G0.WALK)
    HorseHitch.GALLOP_LIMIT = false
    check("GALLOP_LIMIT off and SPEED_LIMITS off: it keeps the gait its steering chose, a gallop included", HorseHitch.limitGait(ride, G0.GALLOP) == G0.GALLOP)
    HorseHitch.GALLOP_LIMIT = true
    HorseHitch.click()
end
HorseHitch.SPEED_LIMITS = true
do
    local G = Rideable.GAITTYPES
    pickResult = target
    HorseHitch.click()
    vehicle.total = 0.66
    check("a pulling horse: walk, canter and trot are as they were, a gallop is a trot", HorseHitch.limitGait(ride, G.WALK) == G.WALK and HorseHitch.limitGait(ride, G.CANTER) == G.CANTER and HorseHitch.limitGait(ride, G.TROT) == G.TROT and HorseHitch.limitGait(ride, G.GALLOP) == G.TROT)
    check("... standing and backing up are none of its business", HorseHitch.limitGait(ride, G.STILL) == G.STILL and HorseHitch.limitGait(ride, G.BACKWARDS) == G.BACKWARDS)
    vehicle.total = 3.5
    check("a 3.5 t load (a skid steer): the same, it may trot (the player is slowed instead)", HorseHitch.limitGait(ride, G.TROT) == G.TROT and HorseHitch.limitGait(ride, G.CANTER) == G.CANTER and HorseHitch.limitGait(ride, G.GALLOP) == G.TROT)
    ride.ridden = true
    check("a RIDDEN horse that pulls: a gallop is a canter (the gait below it in the key order: walk, trot, canter, gallop), the others as they are", HorseHitch.limitGait(ride, G.GALLOP) == G.CANTER and HorseHitch.limitGait(ride, G.TROT) == G.TROT and HorseHitch.limitGait(ride, G.CANTER) == G.CANTER)
    ride.ridden = nil
    HorseHitch.click()
    check("nothing hitched: the gait is the steering's own", ride.hitch == nil and HorseHitch.limitGait(ride, G.GALLOP) == G.GALLOP)
    vehicle.total = nil
end
HorseHitch.SPEED_LIMITS = false

-- the player's speed is capped by what the horse pulls (FS25_WinchTow's cap on the walk state: walking and running)
do
    pickResult = target
    HorseHitch.click()
    vehicle.total = 0.66
    HorseHitch.updatePlayer()
    check("PLAYER_CAP on (the default), SPEED_LIMITS off: the player is capped by what the horse pulls (a light wagon: 3.5 m/s)", HorseHitch.SPEED_LIMITS == false and HITCHCAPS.horsehitch == 3.5)
    vehicle.total = 14
    HorseHitch.updatePlayer()
    check("... a 14 t load (a tractor) changes nothing: the cap is the horse's own speed, not the load's", HITCHCAPS.horsehitch == 3.5)
    local G1 = Rideable.GAITTYPES
    local horseSpec = ride.vehicle.spec_rideable
    ride.vehicle.spec_rideable = { topSpeeds = { [G1.WALK] = 1.08, [G1.TROT] = 2.5, [G1.CANTER] = 5.0, [G1.GALLOP] = 10 } }
    HorseHitch.updatePlayer()
    check("with the horse's own speeds: the fastest gait a pulling horse may use (no gallop): 5 m/s, not the winch's table and not slower", HITCHCAPS.horsehitch == 5.0)
    HorseHitch.GALLOP_LIMIT = false
    HorseHitch.updatePlayer()
    check("... a horse that may gallop: the player may run with it (10 m/s)", HITCHCAPS.horsehitch == 10)
    HorseHitch.GALLOP_LIMIT = true
    ride.vehicle.spec_rideable = horseSpec
    HorseHitch.PLAYER_CAP = false
    HorseHitch.updatePlayer()
    check("PLAYER_CAP off and SPEED_LIMITS off: no cap", HITCHCAPS.horsehitch == nil)
    HorseHitch.PLAYER_CAP = true
    HorseHitch.click()
    vehicle.total = nil
end
HorseHitch.SPEED_LIMITS = true
do
    HorseHitch.updatePlayer()
    check("nothing hitched: no cap (the source is told nil)", HITCHCAPS.horsehitch == nil)
    pickResult = target
    HorseHitch.click()
    vehicle.total = 0.66
    HorseHitch.updatePlayer()
    check("a light wagon hitched: the player is capped at the horse's speed (the fallback 3.5 m/s without its speed table)", HITCHCAPS.horsehitch == 3.5)
    vehicle.total = 14
    HorseHitch.updatePlayer()
    check("a 14 t load: the same cap (it is the horse's own speed, the load does not change it)", HITCHCAPS.horsehitch == 3.5)
    HorseHitch.click()
    HorseHitch.updatePlayer()
    check("unhitched: the cap is taken off", HITCHCAPS.horsehitch == nil)
    vehicle.total = nil
    local winchApi = g_currentMission.winchTow
    g_currentMission.winchTow = { pick = winchApi.pick }
    HorseHitch.updatePlayer()
    check("with a winch mod that has no speed cap: nothing breaks", true)
    g_currentMission.winchTow = winchApi
end
HorseHitch.SPEED_LIMITS = false

-- release is quiet and safe on a ride without a hitch (HorseHarness.destroy calls it for every ride)
check("release without a hitch: false, nothing happens", HorseHitch.release({}) == false)

-- a log on the leash (the winch) and a harnessed horse in view: the horse pulls it
do
    local winchApiFake = g_currentMission.winchTow
    local dropped = {}
    local logTarget = { vehicle = { isLog = true, isDeleted = false, components = { { node = 300 } }, getName = function() return "a log" end }, node = 301, component = 300, kind = "log" }
    nodes[300], nodes[301] = { 0, 0.3, -4 }, { 0, 0.3, -4 }
    RigidBodyType = { DYNAMIC = 2, KINEMATIC = 3 }
    local bodyType = 2
    getRigidBodyType = function() return bodyType end
    local logRide = { vehicle = { rootNode = 1 }, harness = true, harnessGear = "leather", rig = { hookNode = 2, hookRear = 3 } }
    HorseLead.rides = { logRide }
    local pickedRide = logRide
    HorseLead.LEASH_REACH_M = 4
    HorseLead.pickRide = function(px, pz, reach, filter) if pickedRide ~= nil and filter(pickedRide) then return pickedRide end end
    winchApiFake.target = logTarget
    winchApiFake.handOver = function() winchApiFake.target = nil; return logTarget end
    winchApiFake.dropGrip = function(t) dropped[#dropped + 1] = t end
    local message = HorseHitch.takeLog(winchApiFake)
    check("a log on the leash and a harnessed horse looked at: the log is handed over and tied to the harness", message ~= nil and message:find("tied to the harness", 1, true) ~= nil and logRide.hitch ~= nil and logRide.hitch.isLog == true and logRide.hitch.component == 300 and winchApiFake.target == nil)
    check("a log has no tow bar and no keys, but one steel cable from the hook ring to the log's hook", logRide.hitch.barLength == 0 and #logRide.hitch.pieces == 1 and logRide.hitch.pieces[1].diameter == HorseHitch.LOG_CABLE_DIAMETER and logRide.hitch.targets[1] == 301 and HorseHitch.keys(logTarget.vehicle, true) == false)
    TILT[300] = 90                                                              -- (a log lies on its side: its up axis is horizontal)
    HorseHitch.update(logRide, 16)
    check("a log lying on its side is not 'tipped over': it stays hitched", logRide.hitch ~= nil)
    -- the drag: a pull on the grip towards the hook ring when the log is further than the rope, nothing when it is nearer, never a push
    nodes[301] = { 0, 0.3, -8 }
    forces = {}
    HorseHitch.update(logRide, 16)
    local pull = forces[#forces]
    check("a log 7 m behind the hook ring (the rope is 5 m) is pulled towards it: a force on the log's body at the grip, along +z", pull ~= nil and pull[1] == 300 and pull[4] > 0 and math.abs(pull[2]) < 1e-9 and pull[5] == 0 and pull[7] == -8)
    check("... with at most LOG_ACCEL_MS2 times its mass", pull[4] <= HorseHitch.LOG_ACCEL_MS2 * MASS + 1e-9)
    check("... and a lift of LOG_LIFT_SHARE of its weight at the grip, so its front rides over the ground", math.abs(pull[3] - HorseHitch.LOG_LIFT_SHARE * MASS * 9.81) < 1e-9)
    nodes[301] = { 0, 0.3, -4 }
    forces = {}
    HorseHitch.update(logRide, 16)
    check("a log nearer than the rope (3 m from the ring) is not pulled, not lifted and not pushed away either", #forces == 0)
    -- stuck: the rope as long as it gets stops the horse until the log is near again (backing up is allowed)
    nodes[301] = { 0, 0.3, -12 }
    HorseHitch.update(logRide, 16)
    check("a log 11 m behind (the rope is longer than it gets) is stuck: the horse stops, and it says so", logRide.hitch.strained == true and HorseHitch.limitGait(logRide, Rideable.GAITTYPES.WALK) == Rideable.GAITTYPES.STILL and HorseHitch.limitGait(logRide, Rideable.GAITTYPES.TROT) == Rideable.GAITTYPES.STILL)
    check("... but it may back up", HorseHitch.limitGait(logRide, Rideable.GAITTYPES.BACKWARDS) == Rideable.GAITTYPES.BACKWARDS)
    nodes[301] = { 0, 0.3, -8 }
    HorseHitch.update(logRide, 16)
    check("still 7 m: between the two limits it stays stopped (no flapping)", logRide.hitch.strained == true)
    nodes[301] = { 0, 0.3, -6 }
    HorseHitch.update(logRide, 16)
    check("within 6 m of the ring again: the horse goes on", logRide.hitch.strained == false and HorseHitch.limitGait(logRide, Rideable.GAITTYPES.WALK) == Rideable.GAITTYPES.WALK)
    nodes[301] = { 0, 0.3, -4 }
    nodes[301] = { 0, 0.3, -4 }
    bodyType = 3
    HorseHitch.update(logRide, 16)
    check("a log that got belted or cut is let go, and its grip with it", logRide.hitch == nil and dropped[1] == logTarget)
    bodyType = 2
    winchApiFake.target = logTarget
    pickedRide = nil
    check("no harnessed horse in view: the click is none of its business (the leash lets the log go)", HorseHitch.takeLog(winchApiFake) == nil and winchApiFake.target == logTarget)
    winchApiFake.target = { vehicle = vehicle, node = 10, component = 100, kind = "drawbar eye" }
    pickedRide = logRide
    check("a joint on the winch is not a log: not handed over", HorseHitch.takeLog(winchApiFake) == nil)
    winchApiFake.target = logTarget
    winchApiFake.handOver = function() winchApiFake.target = nil; return logTarget end
    pickedRide = logRide
    HorseHitch.takeLog(winchApiFake)
    check("the leash's click lets a log on a horse go", HorseHitch.releaseLogs() == true and logRide.hitch == nil and dropped[2] == logTarget)
    check("... and with none hitched it says so by returning false", HorseHitch.releaseLogs() == false)
    -- the harness tool with a horse's rope in hand: the ring is on the log in view, the click ties the log there
    local logPick = { kind = "log", node = 300, component = 300, x = 1, y = 0.3, z = -6, ring = { 1, 0.3, -6, 0, 0, 1, 0.3 } }
    local why = nil
    winchApiFake.pickLog = function() return (why == nil) and logPick or nil, why end
    local hookedFrom = nil
    winchApiFake.hookLog = function(l) hookedFrom = l; l.vehicle = logTarget.vehicle; l.node = 301; l.ownsNode = true; return l end
    HorseLead.rides = { logRide }
    logRide.towRope = nil
    check("no rope in hand: no ring on logs and no click on them", HorseHitch.harnessHint() == nil and HorseHitch.clickLog() == nil)
    logRide.towRope = true
    local hint = HorseHitch.harnessHint()
    check("a horse's rope in hand and a log in view: the ring is the trunk's own (centre, axis, radius)", hint ~= nil and hint[1] == 1 and hint[7] == 0.3)
    logPick.ring = nil
    hint = HorseHitch.harnessHint()
    check("... or a flat ring on the point looked at when the game gave no trunk geometry", hint ~= nil and hint[3] == -6 and hint[5] == 1)
    local tied = HorseHitch.clickLog()
    check("the click ties the log to that horse at the point looked at, and uses the rope up", tied ~= nil and tied:find("tied to the harness", 1, true) ~= nil and logRide.hitch ~= nil and logRide.hitch.isLog and logRide.towRope == nil and hookedFrom == logPick)
    HorseHitch.release(logRide)
    logRide.towRope = true
    why = "that tree still stands: fell it first"
    check("a standing tree in view says why, the harness stays on", HorseHitch.clickLog() == why and logRide.hitch == nil and logRide.towRope == true)
    why = nil
    winchApiFake.pickLog = function() return nil end
    check("looking at the horse (no log): the click is none of its business, the harness tool takes the harness off", HorseHitch.clickLog() == nil)
    logRide.towRope = nil
    -- the leash with a log hooked: the ring is round the hook ring of the horse a click would hand it to
    winchApiFake.target = logTarget
    pickedRide = logRide
    local ringHint = HorseHitch.leashHint()
    check("a log on the leash and a harnessed horse looked at: the ring is round its hook ring (0.12 m)", ringHint ~= nil and ringHint[1] == 0 and ringHint[2] == 0.9 and ringHint[3] == -1 and ringHint[7] == 0.12)
    local savedHook = logRide.rig.hookNode
    logRide.rig.hookNode, logRide.rig.traceEnds = nil, { 2 }
    local fallback = HorseHitch.leashHint()
    check("a harness with no hook node: the ring is where the trace ends meet (the hitch's own anchor)", fallback ~= nil and fallback[2] == 0.9 and fallback[3] == -1)
    logRide.rig.hookNode, logRide.rig.traceEnds = savedHook, nil
    pickedRide = nil
    check("no horse in reach: no ring", HorseHitch.leashHint() == nil)
    winchApiFake.target = nil
    pickedRide = logRide
    check("nothing on the leash: no ring", HorseHitch.leashHint() == nil)
    winchApiFake.pickLog, winchApiFake.hookLog = nil, nil
    winchApiFake.target, winchApiFake.handOver, winchApiFake.dropGrip = nil, nil, nil
    HorseLead.rides = { ride }
end

-- no winch mod: the click is none of its business
g_currentMission.winchTow = nil
check("without FS25_WinchTow the hitch does nothing (no pick)", HorseHitch.click() == nil)

print = realPrint
print(string.format("horsehitch_test: %d/%d passed", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
