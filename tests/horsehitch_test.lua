-- plain Lua with a fake engine: a harnessed horse pulls a trailer (the drawbar eye pinned to a steel ring at the harness by a stiff servo), the click hitches / unhitches, the ropes, the swing damping and the brake follow
local passed, failed = 0, 0
local realPrint = print
local log = {}
print = function(text) log[#log + 1] = text end
local function check(name, ok) if ok then passed = passed + 1 else failed = failed + 1; realPrint("  FAIL " .. name) end end

-- nodes: 1 horse root, 2 / 3 trace ends left / right (the pin is their middle: 0, 0.9, -1), 10 the joint (the drawbar eye), 20 the player
local nodes = { [1] = { 0, 0, 0 }, [2] = { 0.4, 0.9, -1 }, [3] = { -0.4, 0.9, -1 }, [10] = { 0, 0.6, -4 }, [20] = { 0, 0, -3 } }
getWorldTranslation = function(n) local p = nodes[n]; return p[1], p[2], p[3] end
entityExists = function(n) return nodes[n] ~= nil end
local velocity = { 0, 0, 0 }
getLinearVelocity = function() return velocity[1], velocity[2], velocity[3] end
local MASS = 2
getMass = function() return MASS end
local function noHorizontalForce(list)
    for _, f in ipairs(list) do
        if math.abs(f[2]) > 1e-9 or math.abs(f[4]) > 1e-9 then
            return false
        end
    end
    return true
end
local rootBack = { 0, 0, -1 }
localDirectionToWorld = function(n, x, y, z) return rootBack[1], rootBack[2], rootBack[3] end
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
local vehicle = { isDeleted = false, getName = function() return "Small Trailer" end }
local target = { vehicle = vehicle, node = 10, component = 100, kind = "drawbar eye" }
HITCHCAPS = {}
g_currentMission = { winchTow = {
    pick = function() return pickResult end,
    setBrakeOff = function(t, off) brake[#brake + 1] = off end,
    setSupportUp = function(t, up) support[#support + 1] = up end,
    pullMass = function(v, c) return v.total or getMass(c) end,
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
}
HorseHarness = { spec = { trace = { diameter = 0.02 } } }
local player = true
HorseLead = { rides = {}, playerPosition = function() if player then return 0, 0, -3 end return nil end }
dofile("scripts/HorseHitch.lua")
HorseHitch.MAX_PULL_KN = 1000        -- (the servo law first, the horse's limit below)

local ride = { vehicle = { rootNode = 1 }, harness = true, harnessGear = "leather", rig = { traceEnds = { [1] = 2, [-1] = 3 } } }
HorseLead.rides = { ride }

-- the click: nothing in view -> not its business
pickResult = nil
check("nothing in view: the click is none of the hitch's business (the harness tool does its own)", HorseHitch.click() == nil and ride.hitch == nil)
-- a joint in view, a harnessed horse 4 m away: hitched
pickResult = target
local message = HorseHitch.click()
check("a joint in view and a harnessed horse near it: hitched, with a message saying what and how to undo", message ~= nil and message:find("hitched to the drawbar eye of Small Trailer", 1, true) ~= nil and ride.hitch ~= nil)
check("hitching puts the support leg up", support[#support] == true)
check("the ropes: HOOK_SEGMENTS (6) steel pieces round the hook, then a trace from each harness trace end, in the harness's gear (leather), as thick as the traces", #pieces == 8
    and pieces[1].diameter == HorseHitch.HOOK_DIAMETER and pieces[1].rfMaterialDone == true and pieces[1].options == nil
    and pieces[7].diameter == 0.02 and pieces[7].rfMaterialDone == nil and pieces[7].options ~= nil and pieces[7].options.leather and (pieces[7].link == 2 or pieces[7].link == 3) and pieces[7].link ~= pieces[8].link)
check("six points for the ring are made under the world root", #ride.hitch.nodes == 6 and #ride.hitch.ring == 6)

-- the pull: the pin is the middle of the trace ends, (0, 0.9, -1). The joint is at z -4, 3 m off: far away it is pulled in at the limited acceleration (mass 2 t * 10 m/s2)
HorseHitch.update(ride, 16)
local f = forces[#forces]
check("far from the pin: pulled towards it (+z) at the most the pin accelerates (mass * MAX_ACCEL), at the joint, on the joint's body, in world coordinates", f ~= nil and f[1] == 100 and math.abs(f[2]) < 1e-9 and math.abs(f[4] - 2 * HorseHitch.MAX_ACCEL_MS2) < 1e-9 and f[5] == 0 and f[6] == 0.6 and f[7] == -4 and f[8] == false)
check("... and the brake is let off (setBrakeOff(hitch, true): the joint is off the pin, the vehicle must roll)", brake[#brake] == true)

do
    local r = ride.hitch.ring
    check("the hook ring hangs at the pin in the vertical plane along the horse: the point behind it (z -1.06), the point facing the horse (z -0.94), both at the pin's height",
        math.abs(nodes[r[1]][1]) < 1e-9 and math.abs(nodes[r[1]][2] - 0.9) < 1e-9 and math.abs(nodes[r[1]][3] + 1.06) < 1e-9
        and math.abs(nodes[r[4]][3] + 0.94) < 1e-9 and math.abs(nodes[r[4]][2] - 0.9) < 1e-9)
    check("... the points between are above and below (y 0.9 +- 0.052)", math.abs(nodes[r[2]][2] - 0.952) < 1e-3 and math.abs(nodes[r[6]][2] - 0.848) < 1e-3)
end

-- the whole vehicle's mass is moved: a drawbar of 0.06 t on a wagon of 0.66 t
vehicle.total = 0.66
forces = {}
HorseHitch.update(ride, 16)
check("the force is for the vehicle's total mass (0.66 t * 10 m/s2), not for the joint's body (2 t here)", forces[#forces] ~= nil and math.abs(forces[#forces][4] - 0.66 * HorseHitch.MAX_ACCEL_MS2) < 1e-9)
vehicle.total = nil

-- on the pin, at rest, the horse standing: nothing to do, and the brake is put back
nodes[10] = { 0, 0.9, -1 }
forces = {}
for _ = 1, 40 do HorseHitch.update(ride, 16) end
check("the eye on the pin and the horse standing: no horizontal force", noHorizontalForce(forces))
check("... and the brake is put back (setBrakeOff(hitch, false)): it stays where it is", brake[#brake] == false)

-- a stiff spring and damper, both ways (a rope would not push): 5 cm behind the pin: pulled with 2 t * 12 * 4 * 0.05 = 4.8 kN, 5 cm in front of it: pushed back with as much
nodes[10] = { 0, 0.9, -1.05 }
forces = {}
HorseHitch.update(ride, 16)
check("5 cm behind the pin: pulled forward, 2 t * 12 * 4 * 0.05 = 4.8 kN", forces[#forces] ~= nil and math.abs(forces[#forces][4] - 2 * HorseHitch.VEL_GAIN * HorseHitch.POS_GAIN * 0.05) < 1e-9)
nodes[10] = { 0, 0.9, -0.95 }
forces = {}
HorseHitch.update(ride, 16)
check("5 cm in front of the pin: pushed back (the pin is no rope), 4.8 kN backwards", forces[#forces] ~= nil and math.abs(forces[#forces][4] + 4.8) < 1e-9)
-- sideways: 10 cm to the +x of the pin: pushed to -x (what a rope that pulls only when taut could not do: the S curves)
nodes[10] = { 0.1, 0.9, -1 }
forces = {}
HorseHitch.update(ride, 16)
check("10 cm off the pin sideways (+x): pushed back to it (-x), 2 t * 12 * 4 * 0.1 = 9.6 kN", forces[#forces] ~= nil and math.abs(forces[#forces][2] + 9.6) < 1e-9 and math.abs(forces[#forces][4]) < 1e-9)
-- the swing of the joint is damped: it moves to +x at 1 m/s while on the pin: pushed against its speed
nodes[10] = { 0, 0.9, -1 }
velocity = { 1, 0, 0 }
forces = {}
HorseHitch.update(ride, 16)
check("on the pin but moving sideways at 1 m/s: the speed is damped (-x, 2 t * 12 * 1 = 24 kN, limited to 2 t * 10 = 20 kN)", forces[#forces] ~= nil and math.abs(forces[#forces][2] + 2 * HorseHitch.MAX_ACCEL_MS2) < 1e-9)
velocity = { 0, 0, 0 }

-- the horse's own speed is the speed the joint should have: a joint on the pin at rest while the horse walks forward (its smoothed velocity 3 m/s) is accelerated along
ride.hitch.vz = 3
forces = {}
HorseHitch.update(ride, 16)
check("the horse is walking: a joint at rest on the pin is accelerated forward (+z)", forces[#forces] ~= nil and forces[#forces][4] > 0)
ride.hitch.vz = 0
for _ = 1, 40 do HorseHitch.update(ride, 16) end

-- the hook turns with the horse: facing -x (its way back is +x) the ring's behind-point is at x +0.06
rootBack = { 1, 0, 0 }
HorseHitch.update(ride, 16)
check("the horse turned: the ring turned with it (the point behind at x +0.06, the point facing the horse at x -0.06, z at the pin)", math.abs(nodes[ride.hitch.ring[1]][1] - 0.06) < 1e-9 and math.abs(nodes[ride.hitch.ring[4]][1] + 0.06) < 1e-9 and math.abs(nodes[ride.hitch.ring[1]][3] + 1) < 1e-9)
rootBack = { 0, 0, -1 }
for _ = 1, 3 do HorseHitch.update(ride, 16) end

-- the height: the eye is carried at the height of the traces' ends (0.9): the drawbar's own weight plus a servo, at most LIFT_MAX_KN; the force is vertical only (fy, f[3])
MASS = 0.06
vehicle.total = 0.66                             -- (a drawbar of 60 kg on a wagon of 660: the lift is for such a drawbar)
nodes[10] = { 0, 0.9, -1 }
forces = {}
HorseHitch.update(ride, 16)
check("the eye at the height of the traces, at rest: the drawbar's weight is carried (0.06 t * 9.81 = 0.589 kN up)", forces[#forces] ~= nil and math.abs(forces[#forces][3] - 0.06 * HorseHitch.GRAVITY) < 1e-9)
nodes[10] = { 0, 0.6, -1 }
forces = {}
HorseHitch.update(ride, 16)
check("the eye 30 cm too low (on the ground): lifted harder (0.06 t * (9.81 + 12 * 1 m/s) = 1.31 kN, under the cap)", forces[#forces] ~= nil and math.abs(forces[#forces][3] - 0.06 * (HorseHitch.GRAVITY + HorseHitch.VEL_GAIN * HorseHitch.LIFT_SPEED_MS)) < 1e-9)
nodes[10] = { 0, 1.2, -1 }
forces = {}
HorseHitch.update(ride, 16)
check("the eye 30 cm too high: nothing lifts it (gravity brings it down)", forces[#forces] == nil or forces[#forces][3] == 0)
MASS = 2
vehicle.total = 8                                -- (2 t of 8: 25 %, still a drawbar body)
nodes[10] = { 0, 0.6, -1 }
forces = {}
HorseHitch.update(ride, 16)
check("a heavy body on the joint (2 t here): the lift is capped (LIFT_MAX_KN), the horse does not lift a trailer by its eye", forces[#forces] ~= nil and math.abs(forces[#forces][3] - HorseHitch.LIFT_MAX_KN) < 1e-9)
vehicle.total = 2.5                              -- (2 t of 2.5: the joint sits on the main body)
forces = {}
HorseHitch.update(ride, 16)
check("the joint sits on the main body of the vehicle (2 t of 2.5 t): nothing lifts it, a rigid trailer or a machine is not tilted by its plate", forces[#forces] == nil or forces[#forces][3] == 0)
vehicle.total = nil
nodes[10] = { 0, 0.9, -1 }
for _ = 1, 40 do HorseHitch.update(ride, 16) end

-- the swing of the heavy body round the pin is damped: the wagon's body (node 101) 2.7 m behind the eye, swinging to +x at 1 m/s: pushed back to -x (the force on the body, not on the drawbar)
do
    local ride2 = { vehicle = { rootNode = 1 }, harness = true, rig = ride.rig }
    vehicle.components = { { node = 100 }, { node = 101 } }
    nodes[100], nodes[101] = { 0, 0.5, -1 }, { 0, 0.5, -3.7 }
    HorseHitch.hitch(ride2, target)
    check("the heavy body of the vehicle is found when hitching (a component of the vehicle)", ride2.hitch.body == 100 or ride2.hitch.body == 101)
    HorseHitch.release(ride2)
    vehicle.components = nil
end
ride.hitch.body = 101
nodes[101] = { 0, 0.5, -3.7 }
velocity = { 1, 0, 0 }
forces = {}
HorseHitch.update(ride, 16)
do
    local swingForce
    for _, force in ipairs(forces) do if force[1] == 101 then swingForce = force end end
    check("a body swinging sideways (+x at 1 m/s, 2.7 m behind the eye): damped, a force on the body against the swing: mass 2 t * 3 1/s * 1 m/s = -6 kN x, at the body", swingForce ~= nil and math.abs(swingForce[2] + 6) < 1e-9 and swingForce[5] == 0 and swingForce[7] == -3.7)
end
velocity = { 0, 0, 0 }
forces = {}
HorseHitch.update(ride, 16)
check("not swinging: no force on the body", (function() for _, force in ipairs(forces) do if force[1] == 101 then return false end end return true end)())
nodes[101] = { 0, 0.5, -1.3 }
velocity = { 1, 0, 0 }
forces = {}
HorseHitch.update(ride, 16)
check("a body less than SWING_MIN_ARM_M from the eye is left alone (no arm to swing on)", (function() for _, force in ipairs(forces) do if force[1] == 101 then return false end end return true end)())
velocity = { 0, 0, 0 }
ride.hitch.body = nil
for _ = 1, 3 do HorseHitch.update(ride, 16) end

-- a horse is no tractor: the pull is at most MAX_PULL_KN, and a heavy load gets softer gains (the limit is reached with SATURATE_MS of speed error, the position loop a third of the speed loop): no bang-bang
HorseHitch.MAX_PULL_KN = 4
vehicle.total = 14
do
    local velGain = 4 / (14 * HorseHitch.SATURATE_MS)
    local posGain = velGain / 3
    nodes[10] = { 0, 0.9, -3.2 }                     -- 2.2 m behind the pin
    forces = {}
    HorseHitch.update(ride, 16)
    check("a 14 t load: soft gains (velocity 0.57 /s, position 0.19 /s): the force is mass * gain * gain * error = 3.35 kN, under the 4 kN limit", forces[#forces] ~= nil and math.abs(forces[#forces][4] - 14 * velGain * posGain * 2.2) < 1e-9 and forces[#forces][4] < 4)
    check("... and it is not strained yet (2.2 m: under STRAIN_STOP_M)", ride.hitch.strained ~= true)
    nodes[10] = { 0, 0.9, -5.5 }                     -- 4.5 m behind the pin
    forces = {}
    HorseHitch.update(ride, 16)
    check("4.5 m behind: the limit holds (MAX_PULL_KN: 4 kN along the way to the pin, +z)", forces[#forces] ~= nil and math.abs(forces[#forces][4] - 4) < 1e-9 and math.abs(forces[#forces][2]) < 1e-9)
    check("... and now it is strained (4.5 m behind the pin: hitch.strained, only a message follows: the horse does not stand and wait)", ride.hitch.strained == true)
    nodes[10] = { 0, 0.9, -2.5 }                     -- 1.5 m: caught up
    HorseHitch.update(ride, 16)
    check("... and not strained again when the load is within STRAIN_GO_M of the pin", ride.hitch.strained == false)
    nodes[10] = { 0, 0.9, -4 }                       -- 3 m: between the two: the state stays (no stop and go at the edge)
    HorseHitch.update(ride, 16)
    check("between STRAIN_GO_M and STRAIN_STOP_M the state stays (hysteresis)", ride.hitch.strained == false)
end
nodes[10] = { 0, 0.9, -5.5 }
log = {}
for _ = 1, 6 do HorseHitch.update(ride, 1000) end
do
    local said = false
    for _, line in ipairs(log) do if line:find("cannot move this load (14.0 t)", 1, true) then said = true end end
    check("a load that does not come after STUCK_S seconds: said once that the horse cannot move it", said and ride.hitch.reported == true)
end
-- a light wagon keeps the full gains (0.66 t: 4 kN / (0.66 t * 0.5) is above VEL_GAIN)
vehicle.total = 0.66
nodes[10] = { 0, 0.9, -1.05 }
forces = {}
HorseHitch.update(ride, 16)
check("a 0.66 t wagon keeps the full gains (12 and 4): 5 cm behind the pin: 0.66 t * 12 * 4 * 0.05 = 1.58 kN", forces[#forces] ~= nil and math.abs(forces[#forces][4] - 0.66 * HorseHitch.VEL_GAIN * HorseHitch.POS_GAIN * 0.05) < 1e-9)
vehicle.total = nil
HorseHitch.MAX_PULL_KN = 1000
nodes[10] = { 0, 0.9, -1 }
for _ = 1, 40 do HorseHitch.update(ride, 16) end

-- the brake: off when the horse walks
nodes[1] = { 0, 0, 0.5 }                         -- 0.5 m in 16 ms: 31 m/s (a teleport, but a "moving" horse for the controller)
HorseHitch.update(ride, 16)
check("the horse moves: the brake is off", brake[#brake] == true)
nodes[1] = { 0, 0, 0 }
for _ = 1, 40 do HorseHitch.update(ride, 16) end

-- the ropes follow: tied once their shape has loaded, material applied (not on the steel ring), shown, updated
pieces[1].referenceFrame, pieces[7].referenceFrame = 5, 5
HorseHitch.update(ride, 16)
HorseHitch.update(ride, 16)
check("a loaded ring piece is tied to the next point of the ring, shown, and updated every frame after (and has no gear material: it is steel)", pieces[1].target == ride.hitch.ring[2] and pieces[1].visible and pieces[1].updates >= 1 and not pieces[1].materialDone)
check("a loaded trace is tied to the ring's front point (the one facing the horse), has the gear's material, is shown and updated", pieces[7].target == ride.hitch.ring[4] and pieces[7].materialDone and pieces[7].visible and pieces[7].updates >= 1)

-- the harness rebuilt (new end nodes): the ropes are made again
nodes[4], nodes[5] = { 0.4, 0.9, -1 }, { -0.4, 0.9, -1 }
ride.rig = { traceEnds = { [1] = 4, [-1] = 5 } }
local before, deletedBefore = #pieces, #deletedNodes
HorseHitch.update(ride, 16)
check("a harness that was rebuilt: the old ropes and points are deleted and eight new ropes follow the new end nodes", pieces[1].deleted and #pieces == before + 8 and #deletedNodes == deletedBefore + 6 and (pieces[before + 7].link == 4 or pieces[before + 7].link == 5))

-- the ring gate for the harness tool
check("ring gate: a harnessed horse is there and not hitched: no, it is hitched already", HorseHitch.ringFree() == false)

-- unhitch: the same key
local lastRopes = { pieces[#pieces], pieces[#pieces - 7] }
deletedBefore = #deletedNodes
message = HorseHitch.click()
check("the click with a hitched horse unhitches (and says so)", message ~= nil and message:find("unhitched", 1, true) ~= nil and ride.hitch == nil)
check("unhitching deletes the ropes and the ring's points, puts the brake back and the support leg down", lastRopes[1].deleted and lastRopes[2].deleted and #deletedNodes == deletedBefore + 6 and brake[#brake] == false and support[#support] == false)
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
    check("a vehicle's own hitch gets a tow bar: nine pieces (six steel round the hook, two traces, the bar), the bar steel, TOW_BAR_DIAMETER thick, from the ring's rear point",
        ride3.hitch.barLength == HorseHitch.TOW_BAR_M and #pieces == before3 + 9 and bar.diameter == HorseHitch.TOW_BAR_DIAMETER and bar.rfMaterialDone == true and bar.link == ride3.hitch.ring[1])
    nodes[10] = { 0, 0.4, -2.6 }                     -- the pin: 1.6 m behind the middle of the trace ends (z -1)
    forces = {}
    HorseHitch.update(ride3, 16)
    check("pinned at the end of the bar: a joint there has no horizontal force, and the machine is not lifted by its plate (no vertical force)", noHorizontalForce(forces) and (#forces == 0 or forces[#forces][3] == 0))
    nodes[10] = { 0, 0.4, -1 }                       -- the vehicle ran up to the hook
    forces = {}
    HorseHitch.update(ride3, 16)
    check("a vehicle that runs up to the horse is pushed back by the pin (the bar keeps it clear)", forces[#forces] ~= nil and forces[#forces][4] < 0)
    bar.referenceFrame = 5
    HorseHitch.update(ride3, 16)
    check("the tow bar is tied to the vehicle's hitch once its shape has loaded", bar.target == 10)
    HorseHitch.release(ride3)
    nodes[10] = { 0, 0.9, -1 }
    local ride4 = { vehicle = { rootNode = 1 }, harness = true, rig = ride.rig }
    local before4 = #pieces
    HorseHitch.hitch(ride4, { vehicle = vehicle, node = 10, component = 100, kind = "drawbar eye" })
    check("a trailer's drawbar eye gets no tow bar (its own drawbar is the clearance): eight pieces, no bar length", ride4.hitch.barLength == 0 and #pieces == before4 + 8)
    HorseHitch.release(ride4)
end

-- the gait of a horse that pulls: never a gallop, a trot at the most (the game's gait numbers are not in the order of the speeds: walk, canter, trot, gallop), whatever the load
do
    local G = Rideable.GAITTYPES
    pickResult = target
    HorseHitch.click()
    vehicle.total = 0.66
    check("a pulling horse: walk, canter and trot are as they were, a gallop is a trot", HorseHitch.limitGait(ride, G.WALK) == G.WALK and HorseHitch.limitGait(ride, G.CANTER) == G.CANTER and HorseHitch.limitGait(ride, G.TROT) == G.TROT and HorseHitch.limitGait(ride, G.GALLOP) == G.TROT)
    check("... standing and backing up are none of its business", HorseHitch.limitGait(ride, G.STILL) == G.STILL and HorseHitch.limitGait(ride, G.BACKWARDS) == G.BACKWARDS)
    vehicle.total = 3.5
    check("a 3.5 t load (a skid steer): the same, it may trot (the player is slowed instead)", HorseHitch.limitGait(ride, G.TROT) == G.TROT and HorseHitch.limitGait(ride, G.CANTER) == G.CANTER and HorseHitch.limitGait(ride, G.GALLOP) == G.TROT)
    HorseHitch.click()
    check("nothing hitched: the gait is the steering's own", ride.hitch == nil and HorseHitch.limitGait(ride, G.GALLOP) == G.GALLOP)
    vehicle.total = nil
end

-- the player's speed is capped by what the horse pulls (FS25_WinchTow's cap on the walk state: walking and running)
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

-- release is quiet and safe on a ride without a hitch (HorseHarness.destroy calls it for every ride)
check("release without a hitch: false, nothing happens", HorseHitch.release({}) == false)

-- no winch mod: the click is none of its business
g_currentMission.winchTow = nil
check("without FS25_WinchTow the hitch does nothing (no pick)", HorseHitch.click() == nil)

print = realPrint
print(string.format("horsehitch_test: %d/%d passed", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
