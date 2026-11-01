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
local SETLIN, SETANG, ANGS, HEADING = {}, {}, {}, {}      -- (the speeds the hitch set per node, the angular speeds the engine has, the heading of a body)
setLinearVelocity = function(n, x, y, z) SETLIN[n] = { x, y, z } end
setAngularVelocity = function(n, x, y, z) SETANG[n] = { x, y, z } end
getAngularVelocity = function(n) local v = ANGS[n] or { 0, 0, 0 }; return v[1], v[2], v[3] end
localDirectionToWorld = function(n, x, y, z)
    if n == 1 then return rootBack[1], rootBack[2], rootBack[3] end        -- (the horse: its way back)
    local h = HEADING[n] or 0
    return math.sin(h), 0, math.cos(h)                                      -- (any body: its forward axis)
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

local ride = { vehicle = { rootNode = 1 }, harness = true, harnessGear = "leather", rig = { hookNode = 2, hookRear = 3 } }
HorseLead.rides = { ride }

-- the click: nothing in view -> not its business
pickResult = nil
check("nothing in view: the click is none of the hitch's business (the harness tool does its own)", HorseHitch.click() == nil and ride.hitch == nil)
-- a joint in view, a harnessed horse 4 m away: hitched
pickResult = target
local message = HorseHitch.click()
check("a joint in view and a harnessed horse near it: hitched, with a message saying what and how to undo", message ~= nil and message:find("hitched to the drawbar eye of Small Trailer", 1, true) ~= nil and ride.hitch ~= nil)
check("hitching puts the support leg up", support[#support] == true)
check("a trailer's drawbar eye needs no pieces of its own (the hook ring and the traces are the harness's, always there): none, no tow bar", #pieces == 0 and ride.hitch.barLength == 0)

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
VELS[100], ANGS[100] = { 0, -0.3, 0 }, { 0.1, 0, 0.2 }
HorseHitch.update(ride, 16)
check("the vertical speed of a body and its pitch and roll are left to the physics (only the horizontal speed and the yaw are set)", SETLIN[100][2] == -0.3 and SETANG[100][1] == 0.1 and SETANG[100][3] == 0.2)
VELS[100], ANGS[100] = nil, nil

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

-- the height: the eye is carried at the height of the hook (0.9): the drawbar's own weight (a force on the drawbar alone), at most LIFT_MAX_KN; the force is vertical only
vehicle.total = 0.66                             -- (a drawbar of 60 kg on a wagon of 660: the lift is for such a drawbar)
forces = {}
HorseHitch.update(ride, 16)
check("the eye at the height of the hook, at rest: the drawbar's weight is carried (0.06 t * 9.81 = 0.589 kN up, on the drawbar)", forces[#forces] ~= nil and forces[#forces][1] == 100 and math.abs(forces[#forces][3] - 0.06 * HorseHitch.GRAVITY) < 1e-9 and forces[#forces][2] == 0 and forces[#forces][4] == 0)
nodes[10] = { 0, 0.6, -1 }
forces = {}
HorseHitch.update(ride, 16)
check("the eye 30 cm too low (on the ground): lifted harder (0.06 t * (9.81 + 12 * 1 m/s) = 1.31 kN, under the cap)", forces[#forces] ~= nil and math.abs(forces[#forces][3] - 0.06 * (HorseHitch.GRAVITY + HorseHitch.VEL_GAIN * HorseHitch.LIFT_SPEED_MS)) < 1e-9)
nodes[10] = { 0, 1.2, -1 }
forces = {}
HorseHitch.update(ride, 16)
check("the eye 30 cm too high: nothing lifts it (gravity brings it down)", forces[#forces] == nil)
MASSES[100] = 2
vehicle.total = 8                                -- (2 t of 8: 25 %, still a drawbar body)
nodes[10] = { 0, 0.6, -1 }
forces = {}
HorseHitch.update(ride, 16)
check("a heavy body on the joint (2 t here): the lift is capped (LIFT_MAX_KN), the horse does not lift a trailer by its eye", forces[#forces] ~= nil and math.abs(forces[#forces][3] - HorseHitch.LIFT_MAX_KN) < 1e-9)
vehicle.total = 2.5                              -- (2 t of 2.5: the joint sits on the main body)
forces = {}
HorseHitch.update(ride, 16)
check("the joint sits on the main body of the vehicle (2 t of 2.5 t): nothing lifts it, a rigid trailer or a machine is not tilted by its plate", forces[#forces] == nil)
MASSES[100] = 0.06
vehicle.total = 0.66
nodes[10] = { 0, 0.9, -1 }
for _ = 1, 40 do HorseHitch.update(ride, 16) end

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

-- the log line of the first seconds says what the drive does
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
    check("SPEED_LIMITS off (the default): a pulling horse keeps the gait its steering chose, a gallop included", HorseHitch.limitGait(ride, G0.GALLOP) == G0.GALLOP and HorseHitch.limitGait(ride, G0.TROT) == G0.TROT)
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
    check("SPEED_LIMITS off (the default): the player is not capped by what the horse pulls", HITCHCAPS.horsehitch == nil)
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
    check("a light wagon hitched: the player is capped at the speed the winch gives it (3.5 m/s)", HITCHCAPS.horsehitch == 3.5)
    vehicle.total = 14
    HorseHitch.updatePlayer()
    check("a 14 t load: capped at 2 km/h", math.abs(HITCHCAPS.horsehitch - 2 / 3.6) < 1e-9)
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

-- no winch mod: the click is none of its business
g_currentMission.winchTow = nil
check("without FS25_WinchTow the hitch does nothing (no pick)", HorseHitch.click() == nil)

print = realPrint
print(string.format("horsehitch_test: %d/%d passed", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
