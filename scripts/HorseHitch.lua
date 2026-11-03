--[[
    HorseHitch.lua -- a horse in its harness pulls a trailer. With the harness tool in the hand (or the attach key from the saddle), a click while you look at an attacher joint (a drawbar eye, a hitch:
    FS25_WinchTow's pick, published on g_currentMission.winchTow) hitches the harnessed horse nearest to it; the same key unhitches.
    The harness has a HOOK (HorseHarness: rig.hookNode): one steel ring, rigid on the hip bone, behind the rump, where the two traces end. The vehicle's drawbar eye is GLUED to the middle of that ring.
    Forces did not work (a rope that pulls when taut made the wagon wander, a stiff servo on the drawbar body whipped it, the same pull on the heavy body at the eye's place spun the wagon round the hook:
    the log showed the eye orbiting it at 3 m with the horse standing, the force at its 4 kN limit all the time). So the wagon is DRIVEN, kinematically, every frame: the speed the eye should have is the
    horse's own plus POS_GAIN per metre it is off the hook (at most CATCH_SPEED_MS); the wagon moves as one rigid thing (every body of the vehicle gets v = v_ref + omega x (p - ref), vertical speed and
    pitch and roll left to the physics), its rear body (ref) moving only along the line to the eye and turning about itself as a trailer does (omega = the eye's speed across that line / its length).
    A horse is no tractor: how fast the wagon's speed may change is limited to MAX_PULL_KN / mass. The drawbar of the Wooden Trailer (60 kg) is carried at the height of the hook by a lift force on itself
    (LIFT_*). A vehicle nobody sits in has its brake pedal down: it is let off while hitched (FS25_WinchTow's WinchHand.setBrakeOff and the support leg).
]]
HorseHitch = {}
HorseHitch.REAL_JOINT = true            -- the saddle key joins a vehicle with an input attacher joint through a real attacher joint on the horse (HorseJoint); false (or a refusal) = the rope glue
HorseHitch.HANDOVER_GAP_M = 0.12        -- the rope hands a drawbar eye over to the game's joint when it is this close to the hook (horizontally) ...
HorseHitch.HANDOVER_HEIGHT_M = 0.1      -- ... and this close in height (the tongue is up all the way) ...
HorseHitch.HANDOVER_HOLD_S = 0.2        -- ... for this long
HorseHitch.SPEED_LIMITS = false     -- OFF until the glue is stable: the player's walk cap while a horse pulls (updatePlayer), no gallop for a pulling horse (limitGait), and the horse's pull limit (MAX_PULL_KN: how fast the wagon's speed may change)
HorseHitch.GALLOP_LIMIT = true      -- a pulling horse never gallops (limitGait: a trot, a canter under a rider): on whatever SPEED_LIMITS says. The pull limit above stays off on purpose: the smallest plows and cultivators are meant to be possible
HorseHitch.PLAYER_CAP = true        -- the player's walk and run are capped by what the horse pulls (updatePlayer): the heavier the load the slower, and so the whole string. On whatever SPEED_LIMITS says
HorseHitch.REACH_M = 12               -- the harnessed horse this near the joint you look at is the one that is hitched
HorseHitch.POS_GAIN = 4               -- 1/s: speed wanted per metre the eye is off the hook
HorseHitch.CATCH_SPEED_MS = 6         -- ... at most this (a wagon hitched from 10 m away is pulled in at this speed)
HorseHitch.INTEGRAL_GAIN = 2          -- 1/s2: a steady gap behind the hook (the physics takes a little speed off every step: rolling resistance, damping; at a gallop the wagon trailed a few metres behind) is closed by adding speed for as long as it lasts
HorseHitch.INTEGRAL_MAX_MS = 2        -- ... at most this much speed, and only while the gap is under INTEGRAL_RANGE_M (a wagon far away is the catch-up's)
HorseHitch.INTEGRAL_RANGE_M = 3
HorseHitch.LOG_GAP_M = 0.6            -- after the first LOG_FOR_S seconds a gap bigger than this is still logged (once a second): the evidence for a recording
HorseHitch.VEL_GAIN = 12              -- 1/s: acceleration per m/s the drawbar is short of its lifting speed (LIFT_*)
HorseHitch.MIN_ARM_M = 0.5            -- the wagon only turns when its rear body is this far from the eye (else it only moves)
HorseHitch.MAX_PULL_KN = 4            -- the most a horse pulls along (a draught horse: about 3 to 5 kN at a heave): the wagon's speed changes by at most this / its mass per second (14 t: 0.3 m/s2)
HorseHitch.STRAIN_STOP_M = 4.0        -- the load this far behind the pin (until it is within STRAIN_GO_M again) is strained; for STUCK_S seconds it is said once that the horse cannot move it. The horse does NOT stand and wait for a load (that made a heavy load bounce): a pulling horse never gallops, it trots (limitGait) and the PLAYER is slowed by the load (updatePlayer)
HorseHitch.STRAIN_GO_M = 2.0
HorseHitch.STUCK_S = 4                -- strained this long: said once that the load is too heavy
HorseHitch.LIFT_GAIN = 4              -- 1/s: the same for the height: the drawbar is DRIVEN up to the height of the hook (a lift force of at most 1.5 kN let a loaded wagon's drawbar tip drag on the ground: it dug in and the wagon pole-vaulted)
HorseHitch.LIFT_SPEED_MS = 1          -- ... at most this fast
HorseHitch.MAX_ACCEL_MS2 = 8          -- SAFETY, always on: the wagon's speed changes by at most this per second (a shove at a curb or a ditch must not fling it)
HorseHitch.TIP_UP_MIN = 0.6           -- the rear body's up axis (its y in the world) below this (a tilt of over 53 degrees): the wagon has tipped over, it is let go
HorseHitch.LIFT_MAX_SHARE = 0.25     -- the eye is only driven to the hook's height when the body it sits on is at most this share of the vehicle (a drawbar that is a body of its own: 60 kg of 660); a plate on the main body would tilt the whole machine (a skid steer was lifted by its tail)
HorseHitch.INHERIT_KEYS = true         -- the player on foot gets the keys of what the horse pulls (HorseHitch.keys); false: none
HorseHitch.LOG_EVERY_MS = 1000           -- for the first LOG_FOR_S seconds after hitching the log says what the pin does (the evidence for a recording: how far, how fast, with what force, brake)
HorseHitch.LOG_FOR_S = 40
HorseHitch.MOVING_MS = 0.15           -- a horse faster than this is "moving": the brake is off
HorseHitch.TOW_BAR_M = 1.6            -- a vehicle's OWN hitch (a skid steer's, a tractor's: kind "hitch", its body is right behind the plate) is pinned this far behind the hook, on a rigid tow bar: the body keeps clear of the horse
HorseHitch.TOW_BAR_DIAMETER = 0.03

local function winchApi()
    local winch = g_currentMission ~= nil and g_currentMission.winchTow or nil
    if winch ~= nil and winch.pick ~= nil then
        return winch
    end
    return nil
end

-- A notification (HorseDynamics.notify: the log and the game's notification), or just the log line when that is not there.
local function tell(text)
    if HorseDynamics ~= nil and HorseDynamics.notify ~= nil then
        HorseDynamics.notify(text)
    else
        print("[HorseDynamics] " .. text)
    end
end

local function vehicleName(vehicle)
    if vehicle.getName ~= nil then
        local ok, name = pcall(vehicle.getName, vehicle)
        if ok and name ~= nil then
            return tostring(name)
        end
    end
    return tostring(vehicle.configFileName or "vehicle")
end

-- The hook of the harness (world x, y, z): the middle of its steel ring, rigid on the horse's hip bone. nil when the harness is not there.
function HorseHitch.anchor(ride)
    local rig = ride.rig
    if rig ~= nil and rig.hookNode ~= nil and (entityExists == nil or entityExists(rig.hookNode)) then
        return getWorldTranslation(rig.hookNode)
    end
    if rig == nil or rig.traceEnds == nil then
        return nil
    end
    local sx, sy, sz, n = 0, 0, 0, 0
    for _, node in pairs(rig.traceEnds) do
        if entityExists == nil or entityExists(node) then
            local x, y, z = getWorldTranslation(node)
            sx, sy, sz, n = sx + x, sy + y, sz + z, n + 1
        end
    end
    if n == 0 then
        return nil
    end
    return sx / n, sy / n, sz / n
end

HorseHitch.LOG_CABLE_DIAMETER = 0.015

local function deletePieces(hitch)
    if hitch.cable ~= nil and HorseRope.dropCable ~= nil then
        HorseRope.dropCable(hitch.cable)
    end
    hitch.cable = nil
    for _, rope in ipairs(hitch.pieces) do
        pcall(rope.delete, rope)
    end
    for _, node in ipairs(hitch.nodes or {}) do
        pcall(function()
            if entityExists == nil or entityExists(node) then
                delete(node)
            end
        end)
    end
    hitch.pieces, hitch.tied, hitch.nodes, hitch.targets = {}, {}, {}, {}
end

-- The pieces of a hitch (made again when the harness was rebuilt: its nodes are new): none for a trailer's drawbar eye (the hook ring and the traces are the harness's own, always there). For a vehicle's OWN hitch
-- a rigid tow bar: one straight steel piece from the ring's rear point to the vehicle's hitch.
local function makePieces(ride, hitch)
    deletePieces(hitch)
    hitch.rig = ride.rig
    if hitch.isLog then
        hitch.cable = {}                                                    -- (the winch wire from the hook ring to the hook on the trunk: HorseRope.syncCable, every frame)
    elseif (hitch.barLength or 0) > 0 and ride.rig.hookRear ~= nil then
        local rope = HorseRope.createSegment(ride.rig.hookRear, HorseHitch.TOW_BAR_DIAMETER, nil)
        if rope ~= nil then
            rope.rfMaterialDone = true                                -- (steel: no gear material)
            hitch.pieces[1] = rope
            hitch.targets[1] = hitch.node
        end
    end
end

-- The keys of the hitched vehicle for the player on foot. A vehicle registers its action events (a trailer's tip key, the keys of a pallet autoload mod ...) in the VEHICLE input context, which is only active
-- while somebody sits in a vehicle. Here the vehicle's own registration is replayed inside a PLAYER context modification (what a hand tool does: HandTool:registerActionEvents): every specialization that
-- registers its keys "when active for input" registers them for the player, and the callbacks stay bound to the vehicle. The game clears and refills them whenever it re-registers the vehicle's events
-- (Vehicle:registerActionEvents, hooked below: registered again after it). on = false: the vehicle's own registration is left to the game (updateActionEvents: not active, so the specs clear theirs).
HorseHitch.keyed = setmetatable({}, { __mode = "k" })            -- vehicle -> true: the vehicles whose keys the player has on foot
HorseHitch.keyContext = setmetatable({}, { __mode = "k" })       -- vehicle -> the input context its keys were registered in

-- The input context the player is in now when it is one of the gameplay ones: PLAYER on foot, VEHICLE while riding the horse (a vehicle's keys only work in VEHICLE, a hand tool's in PLAYER); else nil.
function HorseHitch.activeContext()
    if g_inputBinding == nil or g_inputBinding.getContextName == nil or PlayerInputComponent == nil then
        return nil
    end
    local ok, context = pcall(g_inputBinding.getContextName, g_inputBinding)
    if ok and (context == PlayerInputComponent.INPUT_CONTEXT_NAME or (Vehicle ~= nil and context == Vehicle.INPUT_CONTEXT_NAME)) then
        return context
    end
    return nil
end

-- The player mounted or got off (the context changed): the keys of the hitched vehicle are registered in the new one. Called every frame.
function HorseHitch.updateKeys()
    local context = HorseHitch.activeContext()
    if context == nil then
        return
    end
    for vehicle in pairs(HorseHitch.keyed) do
        if HorseHitch.keyContext[vehicle] ~= context and not vehicle.isDeleted then
            HorseHitch.registerKeys(vehicle)
        end
    end
end

function HorseHitch.registerKeys(vehicle)
    if not HorseHitch.INHERIT_KEYS or g_inputBinding == nil or PlayerInputComponent == nil or SpecializationUtil == nil or vehicle.isDeleted then
        return false
    end
    local context = HorseHitch.activeContext()
    if context == nil then
        return false
    end
    HorseHitch.keyContext[vehicle] = context
    local began = false
    local ok, err = pcall(function()
        g_inputBinding:beginActionEventsModification(context)
        began = true
        SpecializationUtil.raiseEvent(vehicle, "onPreRegisterActionEvents", true, true)
        SpecializationUtil.raiseEvent(vehicle, "onRegisterActionEvents", true, true)
        g_inputBinding:endActionEventsModification()
        began = false
    end)
    if not ok then
        if began then
            pcall(g_inputBinding.endActionEventsModification, g_inputBinding)
        end
        if not HorseHitch.keysReported then
            HorseHitch.keysReported = true
            print("[HorseDynamics] hitch: the keys of the hitched vehicle could not be given to the player on foot: " .. tostring(err))
        end
        return false
    end
    return true
end

function HorseHitch.keys(vehicle, on)
    if vehicle.isLog then
        return false                                                 -- (a log has no keys of its own)
    end
    if on then
        HorseHitch.keyed[vehicle] = true
        return HorseHitch.registerKeys(vehicle)
    end
    if HorseHitch.keyed[vehicle] then
        HorseHitch.keyed[vehicle] = nil
        if not vehicle.isDeleted and vehicle.updateActionEvents ~= nil then
            pcall(vehicle.updateActionEvents, vehicle)               -- (not active for input: the specs clear their events, the vehicle's own ones are registered again where the game wants them)
        end
    end
    return false
end

-- Whenever the game registers the events of a vehicle again (it clears the ones this made) they are made again.
if Vehicle ~= nil and Vehicle.registerActionEvents ~= nil and Utils ~= nil and Utils.appendedFunction ~= nil and not HorseHitch.keysHooked then
    HorseHitch.keysHooked = true
    Vehicle.registerActionEvents = Utils.appendedFunction(Vehicle.registerActionEvents, function(self)
        if HorseHitch.keyed[self] then
            HorseHitch.registerKeys(self)
        end
    end)
end

-- Belts first (HorseHitch.AUTO_BELTS): a trailer with tension belts that are not fastened has them thrown before it is hitched (TensionBelts:setAllTensionBeltsActive, what the key does): the loose
-- logs on it became part of the frame, as the belted ones are, and are not thrown about when the nose comes up. Returns true when belts were thrown (the masses need a moment to settle).
HorseHitch.AUTO_BELTS = true
HorseHitch.BELT_SETTLE_S = 0.8
function HorseHitch.throwBelts(vehicle)
    local belts = vehicle ~= nil and vehicle.spec_tensionBelts or nil
    if not HorseHitch.AUTO_BELTS or belts == nil or not belts.hasTensionBelts or belts.areAllBeltsFastened or vehicle.setAllTensionBeltsActive == nil then
        return false
    end
    local ok, err = pcall(vehicle.setAllTensionBeltsActive, vehicle, true)
    if not ok then
        print("[HorseDynamics] hitch: the tension belts could not be thrown: " .. tostring(err))
        return false
    end
    print("[HorseDynamics] hitch: the tension belts were not fastened: thrown before the hitch")
    return true
end

-- Where the vehicle's joint node is, in the vehicle's own space (x right, y up, z forward), and what it hangs on: the tow bar ends exactly on this node, so when the wire ends in the air the node is there.
function HorseHitch.logJointPlace(target)
    pcall(function()
        local vehicle = target.vehicle
        if vehicle == nil or vehicle.rootNode == nil or target.node == nil or worldToLocal == nil or getWorldTranslation == nil then
            return
        end
        local wx, wy, wz = getWorldTranslation(target.node)
        local lx, ly, lz = worldToLocal(vehicle.rootNode, wx, wy, wz)
        local parent = getParent ~= nil and getParent(target.node) or nil
        local name = parent ~= nil and getName ~= nil and getName(parent) or "?"
        print(string.format("[HorseDynamics] hitch: the %s node of %s is %.2f m right, %.2f m up, %.2f m forward of its root node (on '%s', %s the vehicle's own body)",
            tostring(target.kind), vehicleName(vehicle), lx, ly, lz, tostring(name), parent == vehicle.rootNode and "directly on" or "not directly on"))
    end)
end

-- What the wagon is made of when it is hitched, for the puzzle "the tongue lifts with loose logs and not with belted ones": the bodies with their mass and height, which one the eye sits on, the mass the game
-- counts for the vehicle, the belts (how many objects are belted: spec_tensionBelts) and the component joints with their limits.
function HorseHitch.logLoad(target)
    pcall(function()
        local vehicle = target.vehicle
        local parts = {}
        for i, component in ipairs(vehicle.components or {}) do
            local _, y = getWorldTranslation(component.node)
            parts[#parts + 1] = string.format("body %d%s %.0f kg y %.2f", i, component.node == target.component and " (the eye's)" or "", getMass(component.node) * 1000, y)
        end
        local belts = vehicle.spec_tensionBelts
        local belted = 0
        for _ in pairs(belts ~= nil and belts.objectsToJoint or {}) do
            belted = belted + 1
        end
        local joints = {}
        for i, joint in ipairs(vehicle.componentJoints or {}) do
            joints[#joints + 1] = string.format("joint %d: bodies %s-%s, rot limit %s, trans limit %s", i, tostring(joint.componentIndices and joint.componentIndices[1]), tostring(joint.componentIndices and joint.componentIndices[2]),
                joint.rotLimit ~= nil and string.format("%.2f %.2f %.2f", joint.rotLimit[1], joint.rotLimit[2], joint.rotLimit[3]) or "nil", joint.transLimit ~= nil and string.format("%.2f %.2f %.2f", joint.transLimit[1], joint.transLimit[2], joint.transLimit[3]) or "nil")
        end
        local total = vehicle.getTotalMass ~= nil and vehicle:getTotalMass() or nil
        print(string.format("[HorseDynamics] hitch: %s is made of %d body(ies): %s | total mass %s t, %d object(s) belted (%s) | %s",
            vehicleName(vehicle), #(vehicle.components or {}), table.concat(parts, "; "), total ~= nil and string.format("%.2f", total) or "?", belted, belts ~= nil and "tension belts" or "no belts spec", #joints > 0 and table.concat(joints, "; ") or "no component joints"))
    end)
end

-- A wagon with tension belts that are not fastened (and could not be thrown: AUTO_BELTS off, or nothing to throw them with) may carry loose cargo that a jerk shoves about.
function HorseHitch.hasLooseLoad(vehicle)
    local belts = vehicle ~= nil and vehicle.spec_tensionBelts or nil
    return belts ~= nil and belts.hasTensionBelts == true and belts.areAllBeltsFastened ~= true
end

-- Is the eye on the wagon's own frame (then it is tilted about the axle, within TILT_MAX_DEG) or on a tongue (lifted)? Decided when the belts have settled: they put the logs' mass on the frame.
function HorseHitch.decideRigid(hitch)
    local target = { vehicle = hitch.vehicle, node = hitch.node, component = hitch.component, kind = hitch.kind }
    local now = hitch.restHeight
    if now == nil or hitch.goalHeight == nil or not HorseHitch.rigidEye(target) then
        return
    end
    local ex, ey, ez = getWorldTranslation(target.node)
    now = ey - HorseHitch.groundY(ex, ez)
    local tilt = HorseHitch.tiltOf({ vehicle = target.vehicle }, 1, ex, ez)
    hitch.rigid = true
    if tilt ~= nil then
        local rise = tilt.length * math.sin(math.rad(HorseHitch.TILT_MAX_DEG))
        hitch.goalHeight = math.min(hitch.goalHeight, now + rise)
        hitch.tilting = true
        print(string.format("[HorseDynamics] hitch: the eye is on the wagon's own frame (no tongue): it is tilted about its axle (%.1f m behind the eye), at most %d degrees: the eye goes from %.2f to %.2f m above the ground", tilt.length, HorseHitch.TILT_MAX_DEG, now, hitch.goalHeight))
    else
        hitch.goalHeight, hitch.lifted = now, true
        print(string.format("[HorseDynamics] hitch: the eye is on the wagon's own frame and the wagon shows no wheels to tilt it about: it stays where it rests, %.2f m above the ground", now))
    end
end

function HorseHitch.hitch(ride, target)
    local winch = winchApi()
    HorseHitch.logJointPlace(target)
    HorseHitch.logLoad(target)
    ride.hitch = { vehicle = target.vehicle, node = target.node, component = target.component, kind = target.kind, pieces = {}, tied = {}, speed = 0, isLog = target.kind == "log", ropeNode = target.ropeNode, ropeLength = HorseHitch.LOG_ROPE_M }
    ride.hitch.barLength = target.kind == "hitch" and HorseHitch.TOW_BAR_M or 0
    -- a trailer's drawbar eye is not lifted to the hook: the horse comes to the height the trailer is made to be pulled at (the game moves a tractor's hitch to it, AttacherJoints attacherHeight)
    if HorseHitch.canJoin(target) then
        local ax, ay, az = HorseHitch.anchor(ride)
        local now, reach = nil, nil
        ride.hitch.goalHeight, now, reach = HorseHitch.eyeHeight(target, ax ~= nil and ay - HorseHitch.groundY(ax, az) or nil)
        print(string.format("[HorseDynamics] hitch: the eye is held %.2f m above the ground (it is at %.2f m now, its hinge lifts it %.2f m at most)", ride.hitch.goalHeight, now, reach))
        ride.hitch.restHeight = now
        ride.hitch.beltWaitS = HorseHitch.throwBelts(target.vehicle) and HorseHitch.BELT_SETTLE_S or 0
        ride.hitch.gentle = HorseHitch.hasLooseLoad(target.vehicle)
        if ride.hitch.beltWaitS <= 0 then
            HorseHitch.decideRigid(ride.hitch)
        end
    end
    -- the heavy body of the vehicle (the wagon, not its drawbar): the swing round the pin is damped on it
    local heaviest, heaviestMass = nil, 0
    for _, component in ipairs(target.vehicle.components or {}) do
        if component.node ~= nil then
            local mass = getMass(component.node)
            if mass > heaviestMass then
                heaviest, heaviestMass = component.node, mass
            end
        end
    end
    ride.hitch.body = heaviest
    local px, _, pz = getWorldTranslation(ride.vehicle.rootNode)
    ride.hitch.lastX, ride.hitch.lastZ = px, pz
    if winch ~= nil and winch.setSupportUp ~= nil then
        winch.setSupportUp(target, true)
    end
    makePieces(ride, ride.hitch)
    HorseHitch.keys(target.vehicle, true)
end

-- Lets the vehicle go: the brake goes back on, the support leg down, the ropes are deleted. Quiet when the ride has no hitch.
-- keepSupport: the rope lets go to hand the vehicle to the game's joint (the handover): its support animation is not played back. On some trailers it IS the tongue's hinge (the DPW 1800's
-- "lockDrawbarLimit": the hinge is locked while it is parked, the attach frees it): played back, the hinge snapped locked in the middle of the hitch.
function HorseHitch.release(ride, keepSupport)
    local joined = ride.joined
    if joined ~= nil then
        ride.joined = nil
        HorseHitch.lowerHook(ride, false)
        if HorseJoint ~= nil then
            HorseJoint.remove(ride.vehicle)
        end
        HorseHitch.keys(joined.vehicle, false)
        local winch = winchApi()
        if winch ~= nil and not joined.vehicle.isDeleted and joined.target ~= nil then
            if winch.setSupportUp ~= nil then
                winch.setSupportUp(joined.target, false)
            end
            if winch.setBrakeOff ~= nil then
                winch.setBrakeOff(joined.target, false)                 -- (nobody sits in it: the brake goes back on)
            end
        end
        return true
    end
    local hitch = ride.hitch
    if hitch == nil then
        return false
    end
    ride.hitch = nil
    deletePieces(hitch)
    HorseHitch.keys(hitch.vehicle, false)
    local winch = winchApi()
    if hitch.winchTarget ~= nil and winch ~= nil and winch.dropGrip ~= nil then
        winch.dropGrip(hitch.winchTarget)                                    -- (a log: the grip node, the hook and the traffic group go with the hitch)
    end
    if winch ~= nil and not hitch.vehicle.isDeleted then
        if winch.setBrakeOff ~= nil then
            winch.setBrakeOff(hitch, false)
        end
        if winch.setSupportUp ~= nil and not keepSupport then
            winch.setSupportUp(hitch, false)
        end
    end
    return true
end

-- The harness tool's click: unhitches when a horse is hitched, else hitches the harnessed horse nearest to the joint in view. Returns a message, or nil when the click is none of its business (the harness
-- tool then puts the harness on or takes it off).
function HorseHitch.click()
    local released = 0
    for _, ride in ipairs(HorseLead.rides) do
        if HorseHitch.release(ride) then
            released = released + 1
        end
    end
    if released > 0 then
        return string.format("unhitched (%d horse(s))", released)
    end
    local winch = winchApi()
    local target = winch ~= nil and winch.pick() or nil
    if target == nil then
        return nil
    end
    local jx, _, jz = getWorldTranslation(target.node)
    local best, bestDistance = nil, HorseHitch.REACH_M
    for _, ride in ipairs(HorseLead.rides) do
        if ride.harness and ride.rig ~= nil and ride.vehicle ~= nil then
            local hx, _, hz = getWorldTranslation(ride.vehicle.rootNode)
            local d = math.sqrt((hx - jx) ^ 2 + (hz - jz) ^ 2)
            if d < bestDistance then
                best, bestDistance = ride, d
            end
        end
    end
    if best == nil then
        return nil
    end
    best.towRope = nil                                                       -- (the rope in hand is tied now)
    if HorseHitch.start(best, target) then
        return string.format("hitching the %s of %s: the rope pulls it in, then the game's joint takes over; the same click unhitches", target.kind, vehicleName(target.vehicle))
    end
    return string.format("hitched to the %s of %s: lead the horse on, the same key unhitches", target.kind, vehicleName(target.vehicle))
end

-- The leash has something hooked (the winch: a log, or the attacher joint of a vehicle) and you look at a harnessed horse: it is handed to the horse, which pulls it. Returns a message, nil when this is none of
-- its business.
function HorseHitch.takeHooked(winch)
    local hooked = winch ~= nil and winch.target or nil
    if hooked == nil or winch.handOver == nil then
        return nil
    end
    local px, _, pz = HorseLead.playerPosition()
    if px == nil then
        return nil
    end
    local ride = HorseLead.pickRide(px, pz, HorseLead.LEASH_REACH_M, function(r) return r.harness and r.rig ~= nil and r.vehicle ~= nil and r.hitch == nil and r.joined == nil end)
    if ride == nil then
        return nil
    end
    local target = winch.handOver()
    if target == nil then
        return nil
    end
    if target.kind == "log" then
        return HorseHitch.attachLog(ride, target)
    end
    return HorseHitch.hitchMessage(ride, target)
end
HorseHitch.takeLog = HorseHitch.takeHooked

-- A vehicle's joint is hitched to the horse (the same as the harness tool's click on a joint): the message says what happens.
function HorseHitch.hitchMessage(ride, target)
    if HorseHitch.start(ride, target) then
        return string.format("hitching the %s of %s: the rope pulls it in, then the game's joint takes over; the harness tool's click unhitches", target.kind, vehicleName(target.vehicle))
    end
    return string.format("hitched to the %s of %s: lead the horse on, the harness tool's click unhitches", target.kind, vehicleName(target.vehicle))
end

-- The log (a grip made by WinchHand.hookLog) is tied to the harness of this horse: it pulls it from now on.
function HorseHitch.attachLog(ride, target)
    HorseHitch.hitch(ride, target)
    ride.hitch.isLog, ride.hitch.winchTarget = true, target
    if target.hook ~= nil and ride.rig ~= nil and ride.rig.hookNode ~= nil then
        pcall(target.hook.setTargetNode, target.hook, ride.rig.hookNode, true)           -- (the hook on the trunk looks towards the horse now, not towards the hand)
    end
    return "the log is tied to the harness: lead the horse on, it pulls it; the leash (or the harness tool) lets it go"
end

-- The harness tool with a horse's rope in hand and a log in view: the log is tied to that horse at the point looked at. Returns a message, nil when this is none of its business.
function HorseHitch.clickLog()
    local winch = winchApi()
    if winch == nil or winch.pickLog == nil or winch.hookLog == nil then
        return nil
    end
    local roped = nil
    for _, ride in ipairs(HorseLead.rides) do
        if ride.towRope and ride.harness and ride.hitch == nil and ride.joined == nil and ride.vehicle ~= nil and ride.rig ~= nil then
            roped = ride
            break
        end
    end
    if roped == nil then
        return nil
    end
    local log, why = winch.pickLog()
    if log == nil then
        return why
    end
    local target, problem = winch.hookLog(log)
    if target == nil then
        return "the log could not be tied: " .. tostring(problem)
    end
    roped.towRope = nil
    return HorseHitch.attachLog(roped, target)
end

-- The ring of the harness tool while it has a horse's rope in hand: on the log it would tie to (WinchHand.hint). nil when there is none.
function HorseHitch.harnessHint()
    local winch = winchApi()
    if winch == nil or winch.pickLog == nil then
        return nil
    end
    local roped = false
    for _, ride in ipairs(HorseLead.rides) do
        roped = roped or (ride.towRope and ride.harness and ride.hitch == nil)
    end
    if not roped then
        return nil
    end
    local log = winch.pickLog()
    if log == nil then
        return nil
    end
    return log.ring or { log.x, log.y, log.z, 0, 1, 0, 0.18 }
end

-- The ring of the leash while something hangs on it (a log, a vehicle's joint): round the hook ring of the harnessed horse a click would hand it to (WinchHand.hint). nil when there is none.
HorseHitch.HINT_RADIUS_M = 0.12
function HorseHitch.leashHint()
    local winch = winchApi()
    local hooked = winch ~= nil and winch.target or nil
    if hooked == nil then
        return nil
    end
    local px, _, pz = HorseLead.playerPosition()
    if px == nil then
        return nil
    end
    local ride = HorseLead.pickRide(px, pz, HorseLead.LEASH_REACH_M, function(r) return r.harness and r.rig ~= nil and r.vehicle ~= nil and r.hitch == nil and r.joined == nil end)
    if ride == nil then
        return nil
    end
    local x, y, z = HorseHitch.anchor(ride)                                  -- (the hook ring, or the middle of the trace ends when the harness has no hook node)
    if x == nil then
        return nil
    end
    local bx, by, bz = localDirectionToWorld(ride.vehicle.rootNode, 0, 0, -1)
    return { x, y, z, bx, by, bz, HorseHitch.HINT_RADIUS_M }
end

-- The keys that let the wire of a tied log out or take it in (direction +1 longer, -1 shorter; inputValue 0..1, dt in ms). Returns the new length, nil when no log is tied.
function HorseHitch.adjustRope(direction, inputValue, dt)
    if (inputValue or 1) < 0.5 then
        return nil
    end
    local result = nil
    for _, ride in ipairs(HorseLead.rides) do
        local hitch = ride.hitch
        if hitch ~= nil and hitch.isLog then
            local length = (hitch.ropeLength or HorseHitch.LOG_ROPE_M) + direction * HorseHitch.ROPE_SPEED_MS * (dt or 16) / 1000
            hitch.ropeLength = math.max(HorseHitch.LOG_ROPE_MIN_M, math.min(HorseHitch.LOG_ROPE_MAX_M, length))
            if math.abs(hitch.ropeLength - (hitch.ropeToldAt or -100)) >= 1 then
                hitch.ropeToldAt = hitch.ropeLength
                tell(string.format("wire: %.1f m", hitch.ropeLength))
            end
            result = hitch.ropeLength
        end
    end
    return result
end

-- A log on a horse is let go (the leash's click). Returns true when one was.
function HorseHitch.releaseLogs()
    local released = false
    for _, ride in ipairs(HorseLead.rides) do
        if ride.hitch ~= nil and ride.hitch.isLog and HorseHitch.release(ride) then
            released = true
        end
    end
    return released
end

-- The rope hitches; when the game's joint can take the vehicle, the rope hands it over once the eye is at the hook (update). Returns true when a handover is to come. (The saddle key and the harness click.)
function HorseHitch.start(ride, target)
    HorseHitch.hitch(ride, target)
    if HorseHitch.canJoin(target) then
        ride.hitch.handover = true
        return true
    end
    return false
end

-- For the green ring of the harness tool (WinchHand.gate): a harnessed horse is there to be hitched.
function HorseHitch.ringFree()
    local px, _, pz = HorseLead.playerPosition()
    if px == nil then
        return false
    end
    for _, ride in ipairs(HorseLead.rides) do
        if ride.harness and ride.rig ~= nil and ride.vehicle ~= nil and ride.hitch == nil then
            local hx, _, hz = getWorldTranslation(ride.vehicle.rootNode)
            if math.sqrt((hx - px) ^ 2 + (hz - pz) ^ 2) <= HorseHitch.REACH_M + 6 then
                return true
            end
        end
    end
    return false
end

-- Every frame for a ride: the pull, the brake, the ropes.
HorseHitch.HANDOVER_LIFT_MS = 1.0        -- the tongue is lifted at this speed at most ...
HorseHitch.HANDOVER_LIFT_ACCEL_MS2 = 4   -- ... getting there this smoothly
HorseHitch.HANDOVER_LIFT_DONE_M = 0.05   -- lifted when the eye is this close to the height it is to have
HorseHitch.TILT_MAX_DEG = 12             -- a wagon with no tongue (the eye on its own frame) is TILTED about its axle to bring the eye up to the hook, not lifted: at most this far (the eye then hangs lower than the hook, and the hook ring follows it)
HorseHitch.LIFT_FORCE_SHARE = 0        -- OFF (0): a tongue that does not come up gets an upward FORCE (it threw the loose logs of the log trailer off: the frame is only 100 kg and the logs rest on it). A tongue that does not come up gets an upward FORCE on top of the speed it is driven at, growing while it stays stuck, at most this share of the whole vehicle's weight
HorseHitch.LIFT_FORCE_RAMP_S = 1.5       -- ... from nothing to the most in this long
HorseHitch.LIFT_STUCK_M = 0.1            -- stuck: further than this from its height and it has come up less than LIFT_PROGRESS_M in the last half second
HorseHitch.LIFT_PROGRESS_M = 0.02
HorseHitch.LIFT_STALL_S = 1             -- the tongue has reached its stop (a hinge limit) when it has come up less than LIFT_STALL_M in this long while it is driven: the eye is held where it is (driving on lifted the whole frame, and the loose logs on it off)
HorseHitch.LIFT_STALL_M = 0.04
HorseHitch.HANDOVER_TILT_MAX_RAD = 0.07  -- the lift is given up when the wagon's heavy body tilts more than this (4 degrees) from where it stood: the eye does not sit on a small hinged tongue (a locked hinge, a drawbar that is part of the body), driving it up lifted the whole loaded forest trailer's nose into the air
HorseHitch.HANDOVER_LIFT_MAX_S = 3       -- and not tried longer than this (a hinge at its stop does not get further; the pull-in goes on lifting)
HorseHitch.APPROACH_MS = 3             -- the pull-in of a wagon that is handed over: its speed and acceleration at most
HorseHitch.APPROACH_ACCEL_MS2 = 8
HorseHitch.GENTLE_LIFT_MS = 0.5          -- a wagon whose belts are NOT fastened (loose logs shoved about by every jerk: they were thrown off the trailer) is lifted and walked in gently: this fast ...
HorseHitch.GENTLE_LIFT_ACCEL_MS2 = 1
HorseHitch.GENTLE_APPROACH_ACCEL_MS2 = 2 -- ... and this smoothly. With the belts fastened (thrown first, HorseHitch.throwBelts) it is as quick as any other wagon
HorseHitch.TOW_APPROACH_MS = 1.5       -- animal welfare: a vehicle's own hitch (a tractor on the tow bar) is walked in to the pin at this speed at most, and never snatched ...
HorseHitch.TOW_APPROACH_ACCEL_MS2 = 2  -- ... at this acceleration, until it has come to the pin once (TOW_DOCKED_M): an 11 t tractor pulled in at 6 m/s ran into the horse's rump
HorseHitch.TOW_DOCKED_M = 0.3
HorseHitch.ROD = true                  -- false: the tow bar is pulled as springily as a wagon's pin
HorseHitch.ROD_POS_GAIN = 12           -- a docked tow bar is a steel rod, not a rubber band: the speed wanted per metre off the pin is this (3 times the wagon's), no integral to wind up (it was 0.1 to 0.5 m off at a trot) ...
HorseHitch.ROD_FILTER = 0.4            -- ... the horse's speed is followed with this share per frame (the wagon's 0.1 lagged a tenth of a second behind every change of gait) ...
HorseHitch.ROD_ACCEL_MS2 = 20          -- ... and the speed may change this fast

-- The wagon stands while its tongue is lifted: the brake stays ON (it is let off for the walk-in only) and every body of it is held at no horizontal speed, turning not at all. The tongue (the eye's body) is
-- driven up at liftV m/s when that is given. (A parked wagon on a slope rolled off while the tongue was lifted: two horse lengths backwards.)
function HorseHitch.holdStill(hitch, winch, liftV, tilt)
    if winch ~= nil and winch.setBrakeOff ~= nil then
        winch.setBrakeOff(hitch, false)
    end
    for _, component in ipairs(hitch.vehicle.components or { { node = hitch.component } }) do
        local node = component.node
        if node ~= nil and (entityExists == nil or entityExists(node)) then
            if tilt ~= nil then
                -- (a wagon with no tongue: turned about its axle, nothing else moves)
                local cx, cy, cz = getWorldTranslation(node)
                local vx, vy, vz, wx, wz = HorseHitch.tiltVelocity(tilt, cx, cy, cz, hitch.tiltSign)
                setLinearVelocity(node, vx, vy, vz)
                setAngularVelocity(node, wx, 0, wz)
            else
                local _, vy, _ = getLinearVelocity(node)
                if node == hitch.component and liftV ~= nil then
                    vy = liftV
                end
                setLinearVelocity(node, 0, vy, 0)
                setAngularVelocity(node, 0, 0, 0)
            end
        end
    end
end

-- The engine's sign of an angular velocity about a horizontal axis is not taken on trust (the yaw one was the other way round on some bodies): when the eye is commanded up and moves down for a few
-- frames in a row (or the other way round), the sign is flipped.
function HorseHitch.checkTiltSign(hitch, jy, eyeSpeed, seconds)
    local last = hitch.tiltLastY
    hitch.tiltLastY = jy
    if last == nil or math.abs(eyeSpeed) < 0.15 then
        hitch.tiltWrong = 0
        return
    end
    if (jy - last) * eyeSpeed < -0.0004 then
        hitch.tiltWrong = (hitch.tiltWrong or 0) + 1
        if hitch.tiltWrong >= 8 then
            hitch.tiltSign, hitch.tiltWrong = -(hitch.tiltSign or 1), 0
            print("[HorseDynamics] hitch: the wagon tilts the other way from what the angular speed says: the sign is flipped")
        end
    else
        hitch.tiltWrong = 0
    end
end

-- Step one of a hitch that is handed over to the game's joint: the eye's body (the tongue) is lifted on its hinge to the height the eye is to be held at, slowly, and nothing else of the wagon is touched. The
-- wagon is not moved until this is done: pulled in with the tongue on the ground it was dragged through the road. Done when the eye is there, or after HANDOVER_LIFT_MAX_S.
function HorseHitch.liftTongue(ride, hitch, seconds, winch)
    -- the belts were just thrown: the wagon stands still until the logs' mass has settled on the frame, then it is decided what the eye sits on
    if (hitch.beltWaitS or 0) > 0 then
        hitch.beltWaitS = hitch.beltWaitS - seconds
        HorseHitch.holdStill(hitch, winch, nil)
        if hitch.beltWaitS <= 0 then
            HorseHitch.decideRigid(hitch)
        end
        return
    end
    -- the support animation (the leg, and on some trailers the tongue's hinge: it is locked until the animation frees it) has to be done first; waited for 3 s at most
    local attachable = hitch.vehicle.spec_attachable
    if attachable ~= nil and hitch.vehicle.getIsAnimationPlaying ~= nil and (hitch.supportWaitS or 0) < 3 then
        for _, support in ipairs(attachable.supportAnimations or {}) do
            if support.animationName ~= nil and hitch.vehicle:getIsAnimationPlaying(support.animationName) then
                hitch.supportWaitS = (hitch.supportWaitS or 0) + seconds
                HorseHitch.holdStill(hitch, winch, nil)
                return
            end
        end
    end
    local ax, ay, az = HorseHitch.anchor(ride)
    local jx, jy, jz = getWorldTranslation(hitch.node)
    -- the wagon's heavy body must stay where it is: if it tilts, the eye is not on a free tongue, and the lift is given up: the eye goes back to where it rests, and is held THERE (the joint takes the height the eye has)
    local body = hitch.body or hitch.component
    local _, upY = localDirectionToWorld(body, 0, 1, 0)
    local tilt = math.acos(math.max(-1, math.min(1, upY)))
    if hitch.liftTilt0 == nil then
        hitch.liftTilt0, hitch.liftEye0 = tilt, jy - HorseHitch.groundY(jx, jz)
    elseif not hitch.rigid and not hitch.liftAborted and tilt - hitch.liftTilt0 > HorseHitch.HANDOVER_TILT_MAX_RAD then
        hitch.liftAborted = true
        hitch.goalHeight = hitch.liftEye0
        print(string.format("[HorseDynamics] hitch: the wagon's body tilted %.1f degrees while the tongue was lifted: the eye is not on a free tongue, the lift is given up, the eye stays at %.2f m above the ground", math.deg(tilt - hitch.liftTilt0), hitch.liftEye0))
    end
    local goal = jy
    if ax ~= nil then
        goal = hitch.goalHeight ~= nil and HorseHitch.groundY(ax, az) + hitch.goalHeight or ay
    end
    local err = goal - jy
    hitch.liftS = (hitch.liftS or 0) + seconds
    -- the speed the tongue is DRIVEN at ramps up on its own (liftV, not what the physics reports: it takes the speed a step off every frame, a ramp built on it never got going: the tongue stayed on the ground
    -- for 10 s), and the wagon is held where it is meanwhile (HorseHitch.holdStill): with its brake off it rolled away downhill
    -- a stuck tongue gets a force: the speed written to its body is only what the physics lets it keep, against a loaded wagon's nose weight it was not enough (the eye stayed 0.7 m low for the 3 s). The
    -- tilt check above stops it as soon as the heavy body comes up with it.
    hitch.liftCheckS = (hitch.liftCheckS or 0) + seconds
    if hitch.liftCheckS >= 0.5 then
        local rose = jy - (hitch.liftCheckY or jy)
        local stuck = not hitch.liftAborted and not hitch.rigid and err > HorseHitch.LIFT_STUCK_M and rose < HorseHitch.LIFT_PROGRESS_M
        hitch.liftBoost = stuck and math.min(1, (hitch.liftBoost or 0) + hitch.liftCheckS / HorseHitch.LIFT_FORCE_RAMP_S) or math.max(0, (hitch.liftBoost or 0) - hitch.liftCheckS / HorseHitch.LIFT_FORCE_RAMP_S)
        hitch.liftCheckS, hitch.liftCheckY = 0, jy
    end
    if (hitch.liftBoost or 0) > 0 and not hitch.liftAborted and not hitch.rigid and addForce ~= nil then
        local mass = winch ~= nil and winch.pullMass ~= nil and winch.pullMass(hitch.vehicle, hitch.component) or getMass(hitch.component)
        addForce(hitch.component, 0, hitch.liftBoost * HorseHitch.LIFT_FORCE_SHARE * mass * 9.81, 0, jx, jy, jz, false)        -- (tonnes * m/s2 = kN)
    end
    -- the stop: driven for LIFT_STALL_S and not come up by LIFT_STALL_M: it is as high as it goes, the eye is held there (the hook ring follows it)
    hitch.stallS = (hitch.stallS or 0) + seconds
    if hitch.stallS >= HorseHitch.LIFT_STALL_S then
        local rose = jy - (hitch.stallY or jy)
        if not hitch.rigid and not hitch.liftAborted and (hitch.liftV or 0) >= 0.3 and err > HorseHitch.HANDOVER_LIFT_DONE_M and rose < HorseHitch.LIFT_STALL_M and hitch.stallY ~= nil then
            hitch.goalHeight = jy - HorseHitch.groundY(jx, jz)
            hitch.lifted = true
            print(string.format("[HorseDynamics] hitch: the tongue has reached its stop (%.2f m short of the hook): the eye is held where it is, %.2f m above the ground", err, hitch.goalHeight))
            return
        end
        hitch.stallS, hitch.stallY = 0, jy
    elseif hitch.stallY == nil then
        hitch.stallY = jy
    end
    local liftMs = hitch.gentle and HorseHitch.GENTLE_LIFT_MS or HorseHitch.HANDOVER_LIFT_MS
    local want = math.max(-liftMs, math.min(liftMs, err * HorseHitch.LIFT_GAIN))
    local step = (hitch.gentle and HorseHitch.GENTLE_LIFT_ACCEL_MS2 or HorseHitch.HANDOVER_LIFT_ACCEL_MS2) * seconds
    hitch.liftV = (hitch.liftV or 0) + math.max(-step, math.min(step, want - (hitch.liftV or 0)))
    local tilt = hitch.tilting and HorseHitch.tiltOf(hitch, hitch.liftV, jx, jz) or nil
    if tilt ~= nil then
        HorseHitch.checkTiltSign(hitch, jy, hitch.liftV, seconds)
    end
    HorseHitch.holdStill(hitch, winch, hitch.liftV, tilt)
    hitch.liftLogS = (hitch.liftLogS or 1) + seconds
    if hitch.liftLogS >= 0.5 then
        hitch.liftLogS = 0
        print(string.format("[HorseDynamics] hitch: lifting the tongue: the eye is %.2f m below the height it is to have (%.2f m above the ground), driven at %.2f m/s", err, hitch.goalHeight or 0, hitch.liftV))
    end
    if math.abs(err) < HorseHitch.HANDOVER_LIFT_DONE_M or hitch.liftS > HorseHitch.HANDOVER_LIFT_MAX_S then
        if err > HorseHitch.LIFT_STUCK_M * 3 and not hitch.liftAborted and (hitch.liftBoost or 0) >= 1 then
            -- it never came up, even with the force: driving it up while the wagon is walked in would lift the whole wagon instead. The eye is held where it is.
            hitch.goalHeight = jy - HorseHitch.groundY(jx, jz)
            print(string.format("[HorseDynamics] hitch: the tongue would not come up (%.2f m short, even with the force): the eye is held where it is, %.2f m above the ground", err, hitch.goalHeight))
        end
        hitch.lifted = true
        print(string.format("[HorseDynamics] hitch: the tongue is up (%.2f m short, %.1f s): the wagon is walked to the hook now", err, hitch.liftS))
    end
end

-- The trace ropes / the tow bar / the log's cable: made again when the harness was rebuilt, tied once their shape has loaded, moved with their ends.
function HorseHitch.updatePieces(ride, hitch)
    if ride.rig ~= nil and ride.rig ~= hitch.rig then
        makePieces(ride, hitch)
    end
    if hitch.cable ~= nil and ride.rig ~= nil and ride.rig.hookRear ~= nil and HorseRope.syncCable ~= nil then
        HorseRope.syncCable(hitch.cable, ride.rig.hookRear, hitch.ropeNode or hitch.node, hitch.ropeLength, HorseHitch.LOG_CABLE_DIAMETER)
    end
    for i, rope in ipairs(hitch.pieces) do
        HorseRope.applyMaterial(rope)
        HorseRope.setShown(rope, true)
        if hitch.tied[i] then
            pcall(rope.update, rope, 0)
        elseif rope.referenceFrame ~= nil then
            hitch.tied[i] = pcall(rope.setTargetNode, rope, hitch.targets[i], true) or nil
        end
    end
end

-- A log is dragged on a rope, not driven like a wagon: a pull on the grip towards the hook ring when the log is further from it than LOG_REACH_M, never a push, never a speed override. A trunk hooked in
-- the middle then trails behind the horse instead of being swung round it.
HorseHitch.LOG_ROPE_M = 5             -- the wire's length when a log is tied (the keys change it, between LOG_ROPE_MIN_M and LOG_ROPE_MAX_M): a log nearer than this is not pulled, the rest of the wire lies on the ground
HorseHitch.LOG_ROPE_MIN_M, HorseHitch.LOG_ROPE_MAX_M = 2, 12
HorseHitch.LOG_STOP_OVER_M = 2.5      -- a log further than the wire's length plus this (stuck: the horse walked on and the wire is as long as it gets) stops the horse, as a load too heavy for a tractor does ...
HorseHitch.LOG_GO_OVER_M = 1          -- ... it goes on again within the length plus this
HorseHitch.ROPE_SPEED_MS = 1.5        -- the keys let the wire out or take it in this fast
HorseHitch.LOG_LIFT_SHARE = 0.35      -- the pull also lifts this share of the log's weight at the grip, so the front rides over the ground (a real winch lifts the end it drags)
HorseHitch.LOG_ACCEL_MS2 = 6          -- the most the pull accelerates it
HorseHitch.LOG_GAIN = 3               -- 1/s: speed wanted per metre it is further than the rope
HorseHitch.LOG_MAX_MS = 4             -- ... at most this fast
function HorseHitch.dragLog(ride, hitch, seconds, winch)
    local ax, _, az = HorseHitch.anchor(ride)
    if ax == nil then
        return
    end
    local jx, jy, jz = getWorldTranslation(hitch.node)
    local ex, ez = ax - jx, az - jz
    local d = math.sqrt(ex * ex + ez * ez)
    -- stuck: the rope as long as it gets and the log still not coming (the horse is stopped by limitGait until it is within LOG_GO_M again)
    local length = hitch.ropeLength or HorseHitch.LOG_ROPE_M
    if hitch.strained then
        if d < length + HorseHitch.LOG_GO_OVER_M then
            hitch.strained = false
        end
    elseif d > length + HorseHitch.LOG_STOP_OVER_M then
        hitch.strained = true
        tell("the log is stuck: the wire is as long as it gets, the horse stops. Back it up, free the log, or let more wire out")
    end
    if d <= length or d < 1e-3 then
        return
    end
    local ux, uz = ex / d, ez / d
    local vx, _, vz = getLinearVelocity(hitch.component)
    local along = vx * ux + vz * uz
    local horseAlong = (hitch.vx or 0) * ux + (hitch.vz or 0) * uz            -- (the horse's own speed away from the log: the log keeps up with it)
    local want = math.max(0, math.min(HorseHitch.LOG_MAX_MS, math.max(0, horseAlong) + HorseHitch.LOG_GAIN * (d - length)))
    local mass = winch ~= nil and winch.pullMass ~= nil and winch.pullMass(hitch.vehicle, hitch.component) or getMass(hitch.component)
    local a = math.max(0, math.min(HorseHitch.LOG_ACCEL_MS2, (want - along) / 0.3))
    if HorseHitch.SPEED_LIMITS and mass > 0 then
        a = math.min(a, HorseHitch.MAX_PULL_KN / mass)
    end
    if a > 1e-3 then
        addForce(hitch.component, ux * a * mass, HorseHitch.LOG_LIFT_SHARE * mass * 9.81, uz * a * mass, jx, jy, jz, false)        -- (tonnes * m/s2 = kN)
    end
end

function HorseHitch.update(ride, dt)
    local hitch = ride.hitch
    if hitch == nil then
        return
    end
    if hitch.vehicle.isDeleted or hitch.node == nil or not entityExists(hitch.node) then
        HorseHitch.release(ride)
        print("[HorseDynamics] hitch: let go (the vehicle is gone)")
        return
    end
    if hitch.isLog and (not entityExists(hitch.component) or getRigidBodyType(hitch.component) ~= RigidBodyType.DYNAMIC) then
        HorseHitch.release(ride)
        tell("the log was cut or belted: let go")
        return
    end
    -- the horse's own speed (smoothed): the vehicle is pulled at least that fast
    local px, _, pz = getWorldTranslation(ride.vehicle.rootNode)
    local seconds = math.max((dt or 16) / 1000, 0.001)
    local hvx, hvz = (px - hitch.lastX) / seconds, (pz - hitch.lastZ) / seconds
    local speed = math.sqrt(hvx * hvx + hvz * hvz)
    hitch.lastX, hitch.lastZ = px, pz
    hitch.speed = hitch.speed + (speed - hitch.speed) * 0.1
    local rod = (hitch.barLength or 0) > 0 and hitch.docked == true and HorseHitch.ROD
    local filter = rod and HorseHitch.ROD_FILTER or 0.1
    hitch.vx, hitch.vz = (hitch.vx or 0) + (hvx - (hitch.vx or 0)) * filter, (hitch.vz or 0) + (hvz - (hitch.vz or 0)) * filter      -- (the horse's velocity, smoothed: its position is a little noisy, and the servo multiplies that by the mass)
    local winch = winchApi()
    if hitch.isLog then
        HorseHitch.dragLog(ride, hitch, seconds, winch)
        HorseHitch.updatePieces(ride, hitch)
        return
    end
    -- step one of a hitch that hands over to the game's joint: only the tongue is lifted, the wagon stays where it is (HorseHitch.liftTongue); the pull-in starts when it is up
    if hitch.handover and not hitch.lifted then
        HorseHitch.liftTongue(ride, hitch, seconds, winch)
        return
    end
    local ax, ay, az = HorseHitch.anchor(ride)
    if ax ~= nil and hitch.goalHeight ~= nil then
        ay = HorseHitch.groundY(ax, az) + hitch.goalHeight
    end
    if ax ~= nil then
        -- the way back along the horse (horizontal): the hook ring is turned with the horse
        local bx, _, bz = localDirectionToWorld(ride.vehicle.rootNode, 0, 0, -1)
        local blen = math.sqrt(bx * bx + bz * bz)
        if blen > 1e-6 then
            bx, bz = bx / blen, bz / blen
        else
            bx, bz = 0, -1
        end
        local jx, jy, jz = getWorldTranslation(hitch.node)
        local ex, ez = ax + bx * (hitch.barLength or 0) - jx, az + bz * (hitch.barLength or 0) - jz       -- (the pin: the middle of the trace ends, or the tow bar's length behind it)
        local dist = math.sqrt(ex * ex + ez * ez)
        -- a load that cannot keep up (strained, with hysteresis): said once when it has been so for STUCK_S seconds. Nothing else is done about it: the horse goes on (limitGait), the player is slowed
        if hitch.strained then
            if dist < HorseHitch.STRAIN_GO_M then
                hitch.strained, hitch.strainedS = false, 0
            end
        elseif dist > HorseHitch.STRAIN_STOP_M then
            hitch.strained = true
        end
        if hitch.strained then
            hitch.strainedS = (hitch.strainedS or 0) + seconds
            if hitch.strainedS >= HorseHitch.STUCK_S and not hitch.reported and not hitch.handover then
                hitch.reported = true
                local text = string.format("the horse cannot move this load (%.1f t): it pulls %.0f kN at most. Unhitch it, or hitch something lighter", winch ~= nil and winch.pullMass ~= nil and winch.pullMass(hitch.vehicle, hitch.component) or getMass(hitch.component), HorseHitch.MAX_PULL_KN)
                tell(text)
            end
        end
        local mass = winch ~= nil and winch.pullMass ~= nil and winch.pullMass(hitch.vehicle, hitch.component) or getMass(hitch.component)
        -- the speed the eye should have: the horse's own, plus the way back to the hook (limited)
        local gain = rod and HorseHitch.ROD_POS_GAIN or HorseHitch.POS_GAIN
        local catchX, catchZ = ex * gain, ez * gain
        local catchLength = math.sqrt(catchX * catchX + catchZ * catchZ)
        if (hitch.barLength or 0) > 0 and not hitch.docked and dist < HorseHitch.TOW_DOCKED_M then
            hitch.docked = true
        end
        local towWalkIn = (hitch.barLength or 0) > 0 and not hitch.docked
        local catchMax = hitch.handover and HorseHitch.APPROACH_MS or towWalkIn and HorseHitch.TOW_APPROACH_MS or HorseHitch.CATCH_SPEED_MS            -- (a wagon that is to be handed over is walked to the hook, not snatched; nor is a tractor on the tow bar)
        if catchLength > catchMax then
            catchX, catchZ = catchX * catchMax / catchLength, catchZ * catchMax / catchLength
        end
        -- the integral of the gap (steady-state error): added speed while the wagon is within INTEGRAL_RANGE_M of the hook, reset when it is far away
        -- (not for a wagon that is walked to the hook for the handover: the integral wound up to its limit in a second and pushed the eye 0.2 to 0.5 m past the hook; the walk-in stops where the eye meets it)
        if dist < HorseHitch.INTEGRAL_RANGE_M and not hitch.handover and not rod then
            local limit = HorseHitch.INTEGRAL_MAX_MS
            hitch.ix = math.max(-limit, math.min(limit, (hitch.ix or 0) + ex * HorseHitch.INTEGRAL_GAIN * seconds))
            hitch.iz = math.max(-limit, math.min(limit, (hitch.iz or 0) + ez * HorseHitch.INTEGRAL_GAIN * seconds))
        else
            hitch.ix, hitch.iz = 0, 0
        end
        local vEx, vEz = (hitch.vx or 0) + catchX + (hitch.ix or 0), (hitch.vz or 0) + catchZ + (hitch.iz or 0)
        -- the wagon is one rigid thing that turns about its rear body (ref) as a trailer does: the rear moves only along the line to the eye, and the eye's speed across that line is a turn
        local ref = hitch.body
        if ref == nil or (entityExists ~= nil and not entityExists(ref)) then
            ref = hitch.component
        end
        local _, tipY, _ = localDirectionToWorld(ref, 0, 1, 0)
        if tipY < HorseHitch.TIP_UP_MIN and not hitch.isLog then
            HorseHitch.release(ride)
            tell("the wagon tipped over: unhitched")
            return
        end
        local rx, _, rz = getWorldTranslation(ref)
        local ux, uz = jx - rx, jz - rz
        local arm = math.sqrt(ux * ux + uz * uz)
        local vRx, vRz, omega = vEx, vEz, 0
        if arm > HorseHitch.MIN_ARM_M then
            ux, uz = ux / arm, uz / arm
            local along = vEx * ux + vEz * uz
            vRx, vRz = ux * along, uz * along
            omega = (vEx * uz - vEz * ux) / arm
        end
        -- the wagon's speed changes by at most MAX_ACCEL_MS2 per second (safety, always), and with SPEED_LIMITS by at most MAX_PULL_KN / mass (a horse is no tractor)
        local cvx, _, cvz = getLinearVelocity(ref)
        local dvx, dvz = vRx - cvx, vRz - cvz
        local dv = math.sqrt(dvx * dvx + dvz * dvz)
        local maxDv = (hitch.handover and (hitch.gentle and HorseHitch.GENTLE_APPROACH_ACCEL_MS2 or HorseHitch.APPROACH_ACCEL_MS2) or towWalkIn and HorseHitch.TOW_APPROACH_ACCEL_MS2 or rod and HorseHitch.ROD_ACCEL_MS2 or HorseHitch.MAX_ACCEL_MS2) * seconds
        if HorseHitch.SPEED_LIMITS then
            maxDv = math.min(maxDv, HorseHitch.MAX_PULL_KN / mass * seconds)
        end
        if dv > maxDv then
            dvx, dvz = dvx * maxDv / dv, dvz * maxDv / dv
        end
        vRx, vRz = cvx + dvx, cvz + dvz
        -- the engine's sign of a yaw speed is checked against what the ref body really does (its heading changes the way the command says, or the sign is flipped after a few frames)
        local fx, _, fz = localDirectionToWorld(ref, 0, 0, 1)
        local heading = math.atan2(fx, fz)
        if hitch.lastHeading ~= nil and math.abs(hitch.lastOmega or 0) > 0.15 then
            local turned = heading - hitch.lastHeading
            turned = turned - 2 * math.pi * math.floor((turned + math.pi) / (2 * math.pi))
            if turned * hitch.lastOmega < 0 then
                hitch.wrongTurns = (hitch.wrongTurns or 0) + 1
            else
                hitch.wrongTurns = 0
            end
            if hitch.wrongTurns >= 8 then
                hitch.omegaSign, hitch.wrongTurns = -(hitch.omegaSign or 1), 0
                print("[HorseDynamics] hitch: the wagon turns the other way from what the yaw speed says: the sign is flipped")
            end
        end
        hitch.lastHeading, hitch.lastOmega = heading, omega
        local sign = hitch.omegaSign or 1
        -- the drawbar (the joint's body, when it is a body of its own: a small share of the vehicle) is DRIVEN up or down to the height of the hook, 1 m/s at most: it holds the eye there whatever the load on it
        local ownMass = getMass(hitch.component)
        local driveHeight = (hitch.barLength or 0) == 0 and not hitch.rigid and (hitch.handover or ownMass <= HorseHitch.LIFT_MAX_SHARE * mass)
        local heightSpeed = math.max(-HorseHitch.LIFT_SPEED_MS, math.min(HorseHitch.LIFT_SPEED_MS, (ay - jy) * HorseHitch.LIFT_GAIN))
        local tilt = hitch.tilting and HorseHitch.tiltOf(hitch, heightSpeed, jx, jz) or nil
        if tilt ~= nil then
            HorseHitch.checkTiltSign(hitch, jy, heightSpeed, seconds)
        end
        for _, component in ipairs(hitch.vehicle.components or { { node = hitch.component } }) do
            local node = component.node
            if node ~= nil and (entityExists == nil or entityExists(node)) then
                local cx, cy, cz = getWorldTranslation(node)
                local _, vy, _ = getLinearVelocity(node)
                if driveHeight and node == hitch.component then
                    vy = heightSpeed
                end
                local wx, _, wz = getAngularVelocity(node)
                local lvx, lvz = vRx + omega * (cz - rz), vRz - omega * (cx - rx)
                if tilt ~= nil then
                    -- the eye is brought to (and held at) its height by turning the wagon about its axle, on top of the planar motion
                    local tvx, tvy, tvz, twx, twz = HorseHitch.tiltVelocity(tilt, cx, cy, cz, hitch.tiltSign)
                    lvx, lvz, vy, wx, wz = lvx + tvx, lvz + tvz, tvy, twx, twz
                end
                setLinearVelocity(node, lvx, vy, lvz)
                setAngularVelocity(node, wx, omega * sign, wz)
            end
        end
        hitch.logMs = (hitch.logMs or HorseHitch.LOG_EVERY_MS) + (dt or 16)
        hitch.loggedMs = (hitch.loggedMs or 0) + (dt or 16)
        if hitch.logMs >= HorseHitch.LOG_EVERY_MS and (hitch.loggedMs <= HorseHitch.LOG_FOR_S * 1000 or dist > HorseHitch.LOG_GAP_M) then
            hitch.logMs = 0
            print(string.format("[HorseDynamics] hitch: eye off the hook by %.2f m (%.2f, %.2f), eye height %.2f (hook %.2f), horse %.2f m/s, wagon %.2f, %.2f m/s -> set %.2f, %.2f m/s, turn %.2f rad/s, %.2f t, strained %s, gap integral %.2f, %.2f m/s",
                dist, ex, ez, jy, ay, hitch.speed, cvx, cvz, vRx, vRz, omega, mass, tostring(hitch.strained == true), hitch.ix or 0, hitch.iz or 0))
        end
        if winch ~= nil and winch.setBrakeOff ~= nil then
            winch.setBrakeOff(hitch, true)                              -- (the wagon is driven: its brake would only make the wheels skid)
        end
        -- the handover: the eye has come to the hook (and stays there for HANDOVER_HOLD_S), the rope lets go and the game's own joint takes the wagon, with nothing left to pull in
        if hitch.handover then
            if dist < HorseHitch.HANDOVER_GAP_M and math.abs(ay - jy) < HorseHitch.HANDOVER_HEIGHT_M then
                hitch.settledS = (hitch.settledS or 0) + seconds
            else
                hitch.settledS = 0
            end
            if hitch.settledS >= HorseHitch.HANDOVER_HOLD_S then
                local target = { vehicle = hitch.vehicle, node = hitch.node, component = hitch.component, kind = hitch.kind }
                HorseHitch.release(ride, true)
                if HorseHitch.join(ride, target) then
                    tell(string.format("the game's joint holds the %s of %s now", target.kind, vehicleName(target.vehicle)))
                else
                    HorseHitch.hitch(ride, target)                       -- (refused: it stays on the rope)
                end
                return
            end
        end
    end
    HorseHitch.updatePieces(ride, hitch)
end

-- From the saddle: like a tractor. Riding a horse in its harness, the game's own attach key (InputAction.ATTACH, Q) shows "Hitch" when a trailer's drawbar eye (or a machine's hitch) is within SADDLE_REACH_M of
-- the hook and behind the horse (back up to it), and "Unhitch" while something is hitched; the press hitches or unhitches. The key is registered on the horse you ride (Rideable:onRegisterActionEvents,
-- appended below) like the AttacherJoints spec does on a tractor, its text and visibility are kept up every frame (updateSaddle).
HorseHitch.SADDLE_REACH_M = 3.5
HorseHitch.saddle = setmetatable({}, { __mode = "k" })           -- horse (vehicle) -> { id = action event id, events = table }

-- The ride of this horse that is ridden in its harness, or nil.
function HorseHitch.ridden(vehicle)
    for _, ride in ipairs(HorseLead.rides) do
        if ride.vehicle == vehicle and ride.ridden and ride.harness and ride.rig ~= nil then
            return ride
        end
    end
    return nil
end

-- The joint behind the hook within reach: the winch's nearest joint to the hook, behind the horse. nil when there is none (or no FS25_WinchTow).
function HorseHitch.joinable(ride)
    local winch = winchApi()
    if winch == nil or winch.nearest == nil then
        return nil
    end
    local ax, _, az = HorseHitch.anchor(ride)
    if ax == nil then
        return nil
    end
    local bx, _, bz = localDirectionToWorld(ride.vehicle.rootNode, 0, 0, -1)
    local blen = math.sqrt(bx * bx + bz * bz)
    if blen > 1e-6 then
        bx, bz = bx / blen, bz / blen
    else
        bx, bz = 0, -1
    end
    local target = winch.nearest(ax, az, HorseHitch.SADDLE_REACH_M, ride.vehicle)
    if target ~= nil and (target.x - ax) * bx + (target.z - az) * bz > -0.3 then
        return target
    end
    return nil
end

-- The key's callback (the horse is self): hitches the vehicle behind, or lets it go.
function HorseHitch.onSaddleAttach(horse, actionName, inputValue)
    local ride = HorseHitch.ridden(horse)
    if ride == nil then
        return
    end
    if ride.hitch ~= nil or ride.joined ~= nil then
        HorseHitch.release(ride)
        tell("unhitched")
        return
    end
    local target = HorseHitch.joinable(ride)
    if target == nil then
        return
    end
    if HorseHitch.start(ride, target) then
        tell(string.format("hitching the %s of %s: the rope pulls it in, then the game's joint takes over", target.kind, vehicleName(target.vehicle)))
    else
        tell(string.format("hitched to the %s of %s", target.kind, vehicleName(target.vehicle)))
    end
end

-- The harness' hook ring rides on the drawbar eye that the joint holds (HorseHarness.place: the ring is put exactly on the eye, whatever the wagon does, the traces end on it), or goes back to the hip bone.
-- The ring follows the eye, not the joint: a wagon on a joint trails it by a little that grows with the gait.
function HorseHitch.lowerHook(ride, on)
    local rig = ride.rig
    if rig == nil then
        return
    end
    local eye = on and ride.joined ~= nil and ride.joined.target ~= nil and ride.joined.target.node or nil
    if eye ~= nil and (entityExists == nil or entityExists(eye)) then
        rig.hookFollow = eye
    else
        rig.hookFollow = nil
    end
    rig.hookDropTarget = 0
end

function HorseHitch.groundY(x, z)
    if g_terrainNode ~= nil and getTerrainHeightAtWorldPos ~= nil then
        return getTerrainHeightAtWorldPos(g_terrainNode, x, 0, z)
    end
    return 0
end

-- How far the eye can be lifted by the hinge of its own body alone (a tongue on the axle: the Wooden Trailer's tongue is a body of its own, 23 degrees of pitch on a lever of 1.2 m: 0.47 m up from its level pose,
-- 0.94 m from the bottom of its range). Past that the
-- hinge is at its stop and the only way up is to lift the axle with it, the wheels leave the ground. 0 when the eye's body has no hinge to another one (nothing of it can be lifted).
function HorseHitch.liftReach(target)
    local vehicle = target.vehicle
    local eyeIndex = nil
    for i, component in ipairs(vehicle.components or {}) do
        if component.node == target.component then
            eyeIndex = i
        end
    end
    local best = 0
    if eyeIndex == nil then
        return best
    end
    local ex, ey, ez = getWorldTranslation(target.node)
    for _, joint in ipairs(vehicle.componentJoints or {}) do
        local indices = joint.componentIndices
        if indices ~= nil and (indices[1] == eyeIndex or indices[2] == eyeIndex) and joint.rotLimit ~= nil and joint.jointNode ~= nil and (entityExists == nil or entityExists(joint.jointNode)) then
            local hx, hy, hz = getWorldTranslation(joint.jointNode)
            local lever = math.sqrt((ex - hx) ^ 2 + (ey - hy) ^ 2 + (ez - hz) ^ 2)
            -- the hinge swings from the pose the body has now up to its limit: a tongue that has drooped onto the ground (the bottom of its range) can swing up twice as far as one that is level
            local pitch = 0
            local other = vehicle.components[indices[1] == eyeIndex and indices[2] or indices[1]]
            if other ~= nil and other.node ~= nil and localDirectionToLocal ~= nil then
                local _, dy, _ = localDirectionToLocal(target.component, other.node, 0, 0, 1)
                pitch = math.asin(math.max(-1, math.min(1, dy or 0)))
            end
            local limit = math.min(joint.rotLimit[1] or 0, math.pi / 2)
            best = math.max(best, lever * math.max(0, math.sin(limit) - math.sin(pitch)))
        end
    end
    return best
end

-- The height above the ground the trailer's eye is held at: EYE_HEIGHT_M, the height a tractor's joint was measured at (0.81 m). Every trailer is made to hang on a tractor's joint, so it is taken to hang on this
-- one; the tongue is lifted ALL THE WAY up to it before the wagon is walked to the hook and attached (liftTongue, the handover's height check). hdJoint height <m> changes it for a test.
-- Without it (nil): the height of the hook (wanted), but no higher than the eye's hinge can lift it from where it rests now (liftReach, REACH_SHARE of it).
-- Second result: where the eye is now, third: the hinge's reach (log only).
HorseHitch.REACH_SHARE = 0.9
HorseHitch.EYE_HEIGHT_M = 0.81
function HorseHitch.eyeHeight(target, wanted)
    local x, y, z = getWorldTranslation(target.node)
    local now = y - HorseHitch.groundY(x, z)
    local reach = HorseHitch.liftReach(target)
    if HorseHitch.EYE_HEIGHT_M ~= nil then
        return HorseHitch.EYE_HEIGHT_M, now, reach
    end
    return math.min(wanted or now, now + HorseHitch.REACH_SHARE * reach), now, reach
end

-- The horse is a kinematic body that the game moves by teleport steps (Rideable:updateKinematic, moveCCT): to the physics it never has a speed, so a wagon on its joint was only dragged by the position error
-- and trailed behind by an amount that grew with the gait (0 standing, 0.1 m at 1 m/s, 0.2 m at 2.5 m/s in the log; the hook and the tongue's eye apart at a trot). The horse's body is given the speed the game
-- itself moves it at (spec_rideable: currentSpeed along currentTurnAngle, turning at currentTurnSpeed), every frame, the way a dynamic body (a tractor) has it.
HorseHitch.FEED_VELOCITY = true
function HorseHitch.feedVelocity(horse)
    local spec = horse ~= nil and horse.spec_rideable or nil
    local root = horse ~= nil and horse.components ~= nil and horse.components[1] ~= nil and horse.components[1].node or nil
    if not HorseHitch.FEED_VELOCITY or spec == nil or root == nil or (entityExists ~= nil and not entityExists(root)) then
        return
    end
    local speed = spec.currentSpeed or 0
    local angle = spec.currentTurnAngle or 0
    pcall(setLinearVelocity, root, math.sin(angle) * speed, 0, math.cos(angle) * speed)
    pcall(setAngularVelocity, root, 0, (spec.currentTurnSpeed or 0) * (speed >= 0 and 1 or -1), 0)
end

-- A vehicle nobody sits in has its brake pedal down (and the rope's release put it down): behind the horse's real joint its brake is let off, every frame (the call only does something when it changes).
-- The game does this for a trailer behind a driven tractor; behind a horse nobody does.
function HorseHitch.keepJoined(ride)
    local joined = ride.joined
    if joined ~= nil then
        HorseHitch.feedVelocity(ride.vehicle)
    end
    local winch = winchApi()
    if joined ~= nil and winch ~= nil and winch.setBrakeOff ~= nil and joined.target ~= nil and not joined.vehicle.isDeleted then
        winch.setBrakeOff(joined.target, true)
    end
end

-- Can the game's attach take this joint: the real joint is on, and it is an input attacher joint of an attachable vehicle.
-- The wagon's axle: the middle of its wheels in the world (x, y, z), nil when the vehicle shows none.
function HorseHitch.axleOf(vehicle)
    local wheels = vehicle ~= nil and vehicle.spec_wheels ~= nil and vehicle.spec_wheels.wheels or nil
    local sx, sy, sz, n = 0, 0, 0, 0
    for _, wheel in ipairs(wheels or {}) do
        local node = wheel.node or wheel.driveNode or wheel.repr
        if node ~= nil and (entityExists == nil or entityExists(node)) then
            local x, y, z = getWorldTranslation(node)
            sx, sy, sz, n = sx + x, sy + y, sz + z, n + 1
        end
    end
    if n == 0 then
        return nil
    end
    return sx / n, sy / n, sz / n
end

-- Tilting about the axle, not lifting: the eye (jx, jy, jz) is to rise at eyeSpeed while the wheels stay on the ground. The angular velocity is horizontal, across the way from the axle to the eye, eyeSpeed over
-- the distance (nose up for a positive speed); every body then moves as a point of a body turning about the axle (v = w x r). hitch.tiltSign is the engine's sign of an angular velocity (checked below).
-- Returns { wx, wz, ax, ay, az } or nil (no wheels, or the eye is above the axle).
function HorseHitch.tiltOf(hitch, eyeSpeed, jx, jz)
    local ax, ay, az = HorseHitch.axleOf(hitch.vehicle)
    if ax == nil then
        return nil
    end
    local dx, dz = jx - ax, jz - az
    local length = math.sqrt(dx * dx + dz * dz)
    if length < 0.5 then
        return nil
    end
    local omega = eyeSpeed / length
    return { wx = -dz / length * omega, wz = dx / length * omega, ax = ax, ay = ay, az = az, length = length }
end

-- The velocity of a body at (cx, cy, cz) in a turn about the axle: linear (v = w x r) and the angular velocity to give it (with the engine's sign).
function HorseHitch.tiltVelocity(tilt, cx, cy, cz, sign)
    local rx, ry, rz = cx - tilt.ax, cy - tilt.ay, cz - tilt.az
    local wx, wz = tilt.wx, tilt.wz
    return -wz * ry, wz * rx - wx * rz, wx * ry, wx * (sign or 1), wz * (sign or 1)
end

-- Is the eye on the wagon's own main body, with no tongue of its own to lift (a forest trailer whose drawbar is welded to the frame)? The share of the eye's body among the wagon's OWN bodies, not the mass the
-- game counts for the vehicle: belted logs add to that mass, which made the eye's body look like a small tongue exactly when the logs were belted (and only then was it lifted: the whole trailer's nose with it).
function HorseHitch.rigidEye(target)
    local components = target.vehicle ~= nil and target.vehicle.components or nil
    if components == nil or target.component == nil then
        return false
    end
    local own = 0
    for _, component in ipairs(components) do
        if component.node ~= nil then
            own = own + getMass(component.node)
        end
    end
    return own > 0 and getMass(target.component) > HorseHitch.LIFT_MAX_SHARE * own
end

function HorseHitch.canJoin(target)
    if not HorseHitch.REAL_JOINT or HorseJoint == nil then
        return false
    end
    local attachable = target.vehicle ~= nil and target.vehicle.spec_attachable or nil
    for _, input in ipairs(attachable ~= nil and attachable.inputAttacherJoints or {}) do
        if input.node == target.node then
            return true
        end
    end
    return false
end

-- The real thing: the horse gets an attacher joint (HorseJoint) and the game's own attach code joins the vehicle to it, so the physics feedback between horse and wagon is the game's. Only vehicles with an
-- input attacher joint (a drawbar eye the game knows) can be joined this way; anything else, or a refusal, falls back to the rope glue (hitch). Returns true when joined.
function HorseHitch.join(ride, target)
    if not HorseHitch.REAL_JOINT or HorseJoint == nil then
        return false
    end
    local ok, why = HorseJoint.attach(ride.vehicle, target)
    if not ok then
        HorseJoint.remove(ride.vehicle)
        tell(string.format("the horse's joint refused (%s): the rope glue instead", tostring(why)))
        return false
    end
    ride.joined = { vehicle = target.vehicle, target = target }
    HorseHitch.keepJoined(ride)
    HorseHitch.lowerHook(ride, true)
    HorseHitch.keys(target.vehicle, true)
    local winch = winchApi()
    if winch ~= nil and winch.setSupportUp ~= nil then
        winch.setSupportUp(target, true)
    end
    return true
end

-- The horse's own ATTACH event (AttacherJoints spec, there since HorseJoint injects it) as { id }, or nil while it is not registered (nobody sits on the horse yet).
function HorseHitch.gameEvent(horse)
    local spec = horse.spec_attacherJoints
    local event = spec ~= nil and spec.actionEvents ~= nil and InputAction ~= nil and InputAction.ATTACH ~= nil and spec.actionEvents[InputAction.ATTACH] or nil
    if event ~= nil and event.actionEventId ~= nil then
        return { id = event.actionEventId }
    end
    return nil
end

-- Registers the key on the horse (isActive: somebody sits on it and it is active for input) or takes it off. Called from the appended Rideable:onRegisterActionEvents.
function HorseHitch.registerSaddle(horse, isActive)
    local previous = HorseHitch.saddle[horse]
    if previous ~= nil then
        pcall(horse.clearActionEventsTable, horse, previous.events)
        HorseHitch.saddle[horse] = nil
    end
    if HorseHitch.REAL_JOINT and horse.spec_attacherJoints ~= nil then
        return false                                                     -- (the game's own ATTACH event on the horse is the key: HorseHitch.gameEvent)
    end
    if not isActive or g_inputBinding == nil or InputAction == nil or InputAction.ATTACH == nil or horse.addActionEvent == nil or HorseHitch.ridden(horse) == nil then
        return false
    end
    local events = {}
    local ok, _, id = pcall(horse.addActionEvent, horse, events, InputAction.ATTACH, horse, HorseHitch.onSaddleAttach, false, true, false, true, nil, nil, true)
    if ok and id ~= nil then
        pcall(g_inputBinding.setActionEventTextPriority, g_inputBinding, id, GS_PRIO_VERY_HIGH)
        pcall(g_inputBinding.setActionEventActive, g_inputBinding, id, false)
        HorseHitch.saddle[horse] = { id = id, events = events }
        return true
    end
    return false
end

if Rideable ~= nil and Rideable.onRegisterActionEvents ~= nil and Utils ~= nil and Utils.appendedFunction ~= nil and not HorseHitch.saddleHooked then
    HorseHitch.saddleHooked = true
    Rideable.onRegisterActionEvents = Utils.appendedFunction(Rideable.onRegisterActionEvents, function(self, isActiveForInput, isActiveForInputIgnoreSelection)
        HorseHitch.registerSaddle(self, isActiveForInputIgnoreSelection)
    end)
end

HorseHitch.REREGISTER_MS = 1000         -- the key is asked for again at most this often while the horse has none
HorseHitch.STALE_TRIES = 3

-- Is the action event (as { id }) one the input binding has forgotten? Only judged when the binding keeps a table of events by id (g_inputBinding.events); else never.
function HorseHitch.eventStale(entry)
    local events = g_inputBinding ~= nil and g_inputBinding.events or nil
    return HorseHitch.staleCheck ~= false and entry.id ~= nil and type(events) == "table" and next(events) ~= nil and events[entry.id] == nil
end

-- Every frame: the key of a ridden horse in its harness shows "Hitch" with a joint behind it, "Unhitch" while something is hitched, else it is off. A ride that was just mounted gets its events registered
-- (requestActionEventUpdate, once); the key of a horse that is not ridden any more is taken off.
function HorseHitch.updateSaddle()
    if g_inputBinding == nil then
        return
    end
    HorseHitch.updateKeys()
    for _, ride in ipairs(HorseLead.rides) do
        local horse = ride.vehicle
        if horse ~= nil and ride.ridden and ride.harness and ride.rig ~= nil and not horse.isDeleted then
            local entry = HorseHitch.saddle[horse] or (HorseHitch.REAL_JOINT and HorseHitch.gameEvent(horse) or nil)
            -- tabbing out of the game and back: the input binding forgets its events, the horse's table still names the old one (a dead id: the key is gone and nothing asks for it again). Asked again.
            if entry ~= nil and HorseHitch.eventStale(entry) then
                ride.staleCount = (ride.staleCount or 0) + 1
                if ride.staleCount > HorseHitch.STALE_TRIES then
                    HorseHitch.staleCheck = false                       -- (still "dead" after new ids every time: the check is wrong about how events are kept, it is not used again)
                    print("[HorseDynamics] hitch: the key check gave up (the events table is not keyed by action event id)")
                else
                    print("[HorseDynamics] hitch: the hitch key was lost (tabbed out?): registering it again")
                    entry = nil
                end
            elseif entry ~= nil then
                ride.staleCount = 0
            end
            if entry == nil then
                local now = g_time or 0
                if now - (ride.saddleAskedAt or -1e9) >= HorseHitch.REREGISTER_MS and horse.requestActionEventUpdate ~= nil then
                    ride.saddleAskedAt = now
                    ride.saddleRequested = true
                    pcall(horse.requestActionEventUpdate, horse)
                end
            else
                local text = nil
                if ride.hitch ~= nil or ride.joined ~= nil then
                    text = g_i18n:getText("action_detach")
                elseif HorseHitch.joinable(ride) ~= nil then
                    text = g_i18n:getText("action_attach")
                end
                pcall(g_inputBinding.setActionEventActive, g_inputBinding, entry.id, text ~= nil)
                if g_inputBinding.setActionEventTextVisibility ~= nil then
                    pcall(g_inputBinding.setActionEventTextVisibility, g_inputBinding, entry.id, text ~= nil)
                end
                if text ~= nil then
                    pcall(g_inputBinding.setActionEventText, g_inputBinding, entry.id, text)
                end
            end
        elseif horse ~= nil and HorseHitch.saddle[horse] ~= nil then
            HorseHitch.registerSaddle(horse, false)
        end
        if not ride.ridden then
            ride.saddleRequested, ride.saddleAskedAt, ride.staleCount = nil, nil, nil          -- (the next time it is mounted the events are requested again)
        end
    end
end

-- The player is led by the load too: while a horse pulls something, the player's speed is capped (walking and running: FS25_WinchTow's speed cap on the walk state) at the speed the winch gives a load of that
-- weight, the lowest of the loads when there are several. The horse follows the player, so the whole string slows down instead of the horse stopping and starting (which made a heavy load bounce). The cap is
-- taken off when nothing is hitched. Called every frame by HorseLead.updateRide.
-- The speed the player may walk at while a horse pulls: the horse's OWN top speed. The horse follows the player (it does not stop and start), so the player is held to what the horse can do, and not slower:
-- a horse that pulls trots at most (limitGait), so a tractor behind it costs the player nothing beyond that. The speed table of the hand winch is for pulling a load yourself, not for leading a horse that does.
-- The top speed of the fastest gait it may use (the game's topSpeeds per gait); without that table PLAYER_CAP_FALLBACK_MS.
HorseHitch.PLAYER_CAP_FALLBACK_MS = 3.5
function HorseHitch.horseTopSpeedMs(ride)
    local spec = ride.vehicle ~= nil and ride.vehicle.spec_rideable or nil
    local top = spec ~= nil and spec.topSpeeds or nil
    local gaits = Rideable ~= nil and Rideable.GAITTYPES or nil
    if top == nil or gaits == nil then
        return HorseHitch.PLAYER_CAP_FALLBACK_MS
    end
    local allowed = { "WALK", "CANTER", "TROT" }                        -- (what limitGait leaves a pulling horse)
    if not (HorseHitch.GALLOP_LIMIT or HorseHitch.SPEED_LIMITS) then
        allowed[#allowed + 1] = "GALLOP"
    end
    local best = 0
    for _, name in ipairs(allowed) do
        best = math.max(best, gaits[name] ~= nil and top[gaits[name]] or 0)
    end
    return best > 0 and best or HorseHitch.PLAYER_CAP_FALLBACK_MS
end

function HorseHitch.updatePlayer()
    local winch = winchApi()
    if winch == nil or winch.setSpeedCap == nil then
        return
    end
    local cap = nil
    if HorseHitch.PLAYER_CAP or HorseHitch.SPEED_LIMITS then
        for _, ride in ipairs(HorseLead.rides) do
            local hitch = ride.hitch or ride.joined                  -- (on the rope or on the game's own joint)
            if hitch ~= nil and hitch.vehicle ~= nil and not hitch.vehicle.isDeleted then
                local speed = HorseHitch.horseTopSpeedMs(ride)
                cap = cap ~= nil and math.min(cap, speed) or speed
            end
        end
    end
    winch.setSpeedCap("horsehitch", cap)
end

-- The gait a horse that pulls may use: it never gallops (a gallop is a trot; walking only for a heavy load was too boring). The gaits by speed (the numbers of the game's enumeration are not in the order
-- of the speeds: walk, canter, trot, gallop). Returns the gait to use for the one the horse's steering chose. A horse that is RIDDEN steps up one gait per key press (the game's order: walk, trot, canter, gallop):
-- its gallop is a canter, the gait below it in that order, so the key never wraps round to a trot.
function HorseHitch.limitGait(ride, gait)
    local hitch = ride.hitch
    if not (HorseHitch.GALLOP_LIMIT or HorseHitch.SPEED_LIMITS) or hitch == nil or hitch.vehicle == nil or hitch.vehicle.isDeleted then
        return gait
    end
    local gaits = Rideable.GAITTYPES
    if hitch.isLog and hitch.strained and gait ~= gaits.BACKWARDS then
        return gaits.STILL                                                    -- (the rope is as long as it gets: the horse stops, backing up is allowed)
    end
    local rank = { [gaits.STILL] = 0, [gaits.WALK] = 1, [gaits.CANTER] = 2, [gaits.TROT] = 3, [gaits.GALLOP] = 4 }
    if gaits.BACKWARDS ~= nil then
        rank[gaits.BACKWARDS] = 0
    end
    if rank[gait] ~= nil and rank[gait] > rank[gaits.TROT] then
        return ride.ridden and gaits.CANTER or gaits.TROT
    end
    return gait
end
