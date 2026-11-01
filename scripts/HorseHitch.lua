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
HorseHitch.SPEED_LIMITS = false       -- OFF until the glue is stable: the player's walk cap while a horse pulls (updatePlayer), no gallop for a pulling horse (limitGait), and the horse's pull limit (MAX_PULL_KN: how fast the wagon's speed may change)
HorseHitch.REACH_M = 12               -- the harnessed horse this near the joint you look at is the one that is hitched
HorseHitch.POS_GAIN = 4               -- 1/s: speed wanted per metre the eye is off the hook
HorseHitch.CATCH_SPEED_MS = 6         -- ... at most this (a wagon hitched from 10 m away is pulled in at this speed)
HorseHitch.VEL_GAIN = 12              -- 1/s: acceleration per m/s the drawbar is short of its lifting speed (LIFT_*)
HorseHitch.MIN_ARM_M = 0.5            -- the wagon only turns when its rear body is this far from the eye (else it only moves)
HorseHitch.MAX_PULL_KN = 4            -- the most a horse pulls along (a draught horse: about 3 to 5 kN at a heave): the wagon's speed changes by at most this / its mass per second (14 t: 0.3 m/s2)
HorseHitch.STRAIN_STOP_M = 4.0        -- the load this far behind the pin (until it is within STRAIN_GO_M again) is strained; for STUCK_S seconds it is said once that the horse cannot move it. The horse does NOT stand and wait for a load (that made a heavy load bounce): a pulling horse never gallops, it trots (limitGait) and the PLAYER is slowed by the load (updatePlayer)
HorseHitch.STRAIN_GO_M = 2.0
HorseHitch.STUCK_S = 4                -- strained this long: said once that the load is too heavy
HorseHitch.LIFT_GAIN = 4              -- 1/s: the same for the height: the eye is lifted to the height of the traces' ends (the harness), not left lying on the ground
HorseHitch.LIFT_SPEED_MS = 1          -- ... at most this fast
HorseHitch.LIFT_MAX_KN = 1.5          -- the most the horse carries of the vehicle (the drawbar's weight, a tongue weight): a heavy rigid trailer is not lifted by its eye
HorseHitch.GRAVITY = 9.81
HorseHitch.LIFT_MAX_SHARE = 0.25     -- the eye is only lifted when the body it sits on is at most this share of the vehicle (a drawbar that is a body of its own: 60 kg of 660); a plate on the main body would tilt the whole machine (a skid steer was lifted by its tail)
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

local function deletePieces(hitch)
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
    if (hitch.barLength or 0) > 0 and ride.rig.hookRear ~= nil then
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

function HorseHitch.hitch(ride, target)
    local winch = winchApi()
    ride.hitch = { vehicle = target.vehicle, node = target.node, component = target.component, kind = target.kind, pieces = {}, tied = {}, speed = 0 }
    ride.hitch.barLength = target.kind == "hitch" and HorseHitch.TOW_BAR_M or 0
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
function HorseHitch.release(ride)
    local hitch = ride.hitch
    if hitch == nil then
        return false
    end
    ride.hitch = nil
    deletePieces(hitch)
    HorseHitch.keys(hitch.vehicle, false)
    local winch = winchApi()
    if winch ~= nil and not hitch.vehicle.isDeleted then
        if winch.setBrakeOff ~= nil then
            winch.setBrakeOff(hitch, false)
        end
        if winch.setSupportUp ~= nil then
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
    HorseHitch.hitch(best, target)
    return string.format("hitched to the %s of %s: lead the horse on, the same key unhitches", target.kind, vehicleName(target.vehicle))
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
    -- the horse's own speed (smoothed): the vehicle is pulled at least that fast
    local px, _, pz = getWorldTranslation(ride.vehicle.rootNode)
    local seconds = math.max((dt or 16) / 1000, 0.001)
    local hvx, hvz = (px - hitch.lastX) / seconds, (pz - hitch.lastZ) / seconds
    local speed = math.sqrt(hvx * hvx + hvz * hvz)
    hitch.lastX, hitch.lastZ = px, pz
    hitch.speed = hitch.speed + (speed - hitch.speed) * 0.1
    hitch.vx, hitch.vz = (hitch.vx or 0) + (hvx - (hitch.vx or 0)) * 0.1, (hitch.vz or 0) + (hvz - (hitch.vz or 0)) * 0.1      -- (the horse's velocity, smoothed: its position is a little noisy, and the servo multiplies that by the mass)
    local winch = winchApi()
    local ax, ay, az = HorseHitch.anchor(ride)
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
            if hitch.strainedS >= HorseHitch.STUCK_S and not hitch.reported then
                hitch.reported = true
                local text = string.format("the horse cannot move this load (%.1f t): it pulls %.0f kN at most. Unhitch it, or hitch something lighter", winch ~= nil and winch.pullMass ~= nil and winch.pullMass(hitch.vehicle, hitch.component) or getMass(hitch.component), HorseHitch.MAX_PULL_KN)
                tell(text)
            end
        end
        local mass = winch ~= nil and winch.pullMass ~= nil and winch.pullMass(hitch.vehicle, hitch.component) or getMass(hitch.component)
        local ownMass = getMass(hitch.component)
        -- the speed the eye should have: the horse's own, plus the way back to the hook (limited)
        local catchX, catchZ = ex * HorseHitch.POS_GAIN, ez * HorseHitch.POS_GAIN
        local catchLength = math.sqrt(catchX * catchX + catchZ * catchZ)
        if catchLength > HorseHitch.CATCH_SPEED_MS then
            catchX, catchZ = catchX * HorseHitch.CATCH_SPEED_MS / catchLength, catchZ * HorseHitch.CATCH_SPEED_MS / catchLength
        end
        local vEx, vEz = (hitch.vx or 0) + catchX, (hitch.vz or 0) + catchZ
        -- the wagon is one rigid thing that turns about its rear body (ref) as a trailer does: the rear moves only along the line to the eye, and the eye's speed across that line is a turn
        local ref = hitch.body
        if ref == nil or (entityExists ~= nil and not entityExists(ref)) then
            ref = hitch.component
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
        -- a horse is no tractor: the wagon's speed changes by at most MAX_PULL_KN / mass per second
        local cvx, _, cvz = getLinearVelocity(ref)
        local dvx, dvz = vRx - cvx, vRz - cvz
        local dv = math.sqrt(dvx * dvx + dvz * dvz)
        local maxDv = HorseHitch.MAX_PULL_KN / mass * seconds
        if HorseHitch.SPEED_LIMITS and dv > maxDv then
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
        for _, component in ipairs(hitch.vehicle.components or { { node = hitch.component } }) do
            local node = component.node
            if node ~= nil and (entityExists == nil or entityExists(node)) then
                local cx, _, cz = getWorldTranslation(node)
                local _, vy, _ = getLinearVelocity(node)
                setLinearVelocity(node, vRx + omega * (cz - rz), vy, vRz - omega * (cx - rx))
                local wx, _, wz = getAngularVelocity(node)
                setAngularVelocity(node, wx, omega * sign, wz)
            end
        end
        hitch.logMs = (hitch.logMs or HorseHitch.LOG_EVERY_MS) + (dt or 16)
        hitch.loggedMs = (hitch.loggedMs or 0) + (dt or 16)
        if hitch.logMs >= HorseHitch.LOG_EVERY_MS and hitch.loggedMs <= HorseHitch.LOG_FOR_S * 1000 then
            hitch.logMs = 0
            print(string.format("[HorseDynamics] hitch: eye off the hook by %.2f m (%.2f, %.2f), eye height %.2f (hook %.2f), horse %.2f m/s, wagon %.2f, %.2f m/s -> set %.2f, %.2f m/s, turn %.2f rad/s, %.2f t, strained %s",
                dist, ex, ez, jy, ay, hitch.speed, cvx, cvz, vRx, vRz, omega, mass, tostring(hitch.strained == true)))
        end
        if winch ~= nil and winch.setBrakeOff ~= nil then
            winch.setBrakeOff(hitch, true)                              -- (the wagon is driven: its brake would only make the wheels skid)
        end
        -- the height: the eye is carried at the height of the hook: the weight of the body the joint sits on (the drawbar, 60 kg of the Wooden Trailer) plus a servo on the height, at most LIFT_MAX_KN.
        -- The vehicle's support leg is up (hitch), so the drawbar does not rest on the ground.
        local _, vy, _ = getLinearVelocity(hitch.component)
        local liftSpeed = math.max(-HorseHitch.LIFT_SPEED_MS, math.min(HorseHitch.LIFT_SPEED_MS, (ay - jy) * HorseHitch.LIFT_GAIN))
        local lift = math.max(0, math.min(HorseHitch.LIFT_MAX_KN, ownMass * (HorseHitch.GRAVITY + HorseHitch.VEL_GAIN * (liftSpeed - vy))))
        if (hitch.barLength or 0) > 0 or ownMass > HorseHitch.LIFT_MAX_SHARE * mass then
            lift = 0                                                -- (a vehicle's own hitch sits where it sits, and a plate on the main body is not lifted: the bar slopes down to it)
        end
        if lift > 0 then
            addForce(hitch.component, 0, lift, 0, jx, jy, jz, false)
        end
    end
    -- the trace ropes
    if ride.rig ~= nil and ride.rig ~= hitch.rig then
        makePieces(ride, hitch)
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
    if ride.hitch ~= nil then
        HorseHitch.release(ride)
        tell("unhitched")
        return
    end
    local target = HorseHitch.joinable(ride)
    if target ~= nil then
        HorseHitch.hitch(ride, target)
        tell(string.format("hitched to the %s of %s", target.kind, vehicleName(target.vehicle)))
    end
end

-- Registers the key on the horse (isActive: somebody sits on it and it is active for input) or takes it off. Called from the appended Rideable:onRegisterActionEvents.
function HorseHitch.registerSaddle(horse, isActive)
    local previous = HorseHitch.saddle[horse]
    if previous ~= nil then
        pcall(horse.clearActionEventsTable, horse, previous.events)
        HorseHitch.saddle[horse] = nil
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
            local entry = HorseHitch.saddle[horse]
            if entry == nil then
                if not ride.saddleRequested and horse.requestActionEventUpdate ~= nil then
                    ride.saddleRequested = true
                    pcall(horse.requestActionEventUpdate, horse)
                end
            else
                local text = nil
                if ride.hitch ~= nil then
                    text = g_i18n:getText("action_detach")
                elseif HorseHitch.joinable(ride) ~= nil then
                    text = g_i18n:getText("action_attach")
                end
                pcall(g_inputBinding.setActionEventActive, g_inputBinding, entry.id, text ~= nil)
                if text ~= nil then
                    pcall(g_inputBinding.setActionEventText, g_inputBinding, entry.id, text)
                end
            end
        elseif horse ~= nil and HorseHitch.saddle[horse] ~= nil then
            HorseHitch.registerSaddle(horse, false)
        end
        if not ride.ridden then
            ride.saddleRequested = nil                                   -- (the next time it is mounted the events are requested again)
        end
    end
end

-- The player is led by the load too: while a horse pulls something, the player's speed is capped (walking and running: FS25_WinchTow's speed cap on the walk state) at the speed the winch gives a load of that
-- weight, the lowest of the loads when there are several. The horse follows the player, so the whole string slows down instead of the horse stopping and starting (which made a heavy load bounce). The cap is
-- taken off when nothing is hitched. Called every frame by HorseLead.updateRide.
function HorseHitch.updatePlayer()
    local winch = winchApi()
    if winch == nil or winch.setSpeedCap == nil then
        return
    end
    local cap = nil
    if HorseHitch.SPEED_LIMITS and winch.pullSpeed ~= nil and winch.pullMass ~= nil then
        for _, ride in ipairs(HorseLead.rides) do
            local hitch = ride.hitch
            if hitch ~= nil and not hitch.vehicle.isDeleted then
                local speed = winch.pullSpeed(winch.pullMass(hitch.vehicle, hitch.component))
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
    if not HorseHitch.SPEED_LIMITS or hitch == nil or hitch.vehicle == nil or hitch.vehicle.isDeleted then
        return gait
    end
    local gaits = Rideable.GAITTYPES
    local rank = { [gaits.STILL] = 0, [gaits.WALK] = 1, [gaits.CANTER] = 2, [gaits.TROT] = 3, [gaits.GALLOP] = 4 }
    if gaits.BACKWARDS ~= nil then
        rank[gaits.BACKWARDS] = 0
    end
    if rank[gait] ~= nil and rank[gait] > rank[gaits.TROT] then
        return ride.ridden and gaits.CANTER or gaits.TROT
    end
    return gait
end
