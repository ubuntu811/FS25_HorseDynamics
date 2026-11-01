--[[
    HorseHitch.lua -- a horse in its harness pulls a trailer. With the harness tool in the hand, a click while you look at an attacher joint (a drawbar eye, a hitch: FS25_WinchTow's pick, published on
    g_currentMission.winchTow) hitches the harnessed horse nearest to it; the same key unhitches.
    The harness has a HOOK: a steel ring (HOOK_SEGMENTS pieces of radius HOOK_RADIUS_M, in the vertical plane along the horse) where the two traces meet, at the middle between the ends of the traces. The vehicle's
    drawbar eye is PINNED to the middle of that ring, as a tractor's hitch holds a trailer's eye (a dynamic rope that pulls only when it is taut made the wagon wander in S curves; a swingletree and a chain made it
    look worse). The pin is in the horse's own frame and at the height of the traces' ends: the eye is lifted off the ground to the harness. It is a stiff servo on the joint's body: the speed it wants is the horse's
    own plus POS_GAIN per metre of error (at most CATCH_SPEED_MS: far away it is pulled in), and the force is mass * VEL_GAIN * the speed it is short of, at most MAX_ACCEL_MS2, and never more than MAX_PULL_KN.
    So it holds in both directions (a horse that steps back pushes the wagon back), and the wagon swings round the pin on its own wheels; that swing of its heavy body is damped (SWING_DAMP).
    A vehicle nobody sits in has its brake pedal down: it is let off while the horse moves, and put back when the horse stands, so it stays where it is (FS25_WinchTow's WinchHand.setBrakeOff and the support leg).
]]
HorseHitch = {}
HorseHitch.REACH_M = 12               -- the harnessed horse this near the joint you look at is the one that is hitched
HorseHitch.POS_GAIN = 4               -- 1/s: speed wanted per metre the joint is off the pin
HorseHitch.CATCH_SPEED_MS = 6         -- ... at most this (a wagon hitched from 10 m away is pulled in at this speed)
HorseHitch.VEL_GAIN = 12              -- 1/s: acceleration per m/s the joint is short of the speed wanted
HorseHitch.MAX_ACCEL_MS2 = 10         -- the most the pin accelerates the vehicle (force = mass * this at the most)
HorseHitch.MAX_PULL_KN = 4            -- the most a horse pulls along (a draught horse: about 3 to 5 kN at a heave): a heavy load is accelerated slowly (14 t: 0.3 m/s2), or not at all
HorseHitch.STRAIN_STOP_M = 4.0        -- the load this far behind the pin (until it is within STRAIN_GO_M again) is strained; for STUCK_S seconds it is said once that the horse cannot move it. The horse does NOT stand and wait for a load (that made a heavy load bounce): a pulling horse never gallops, it trots (limitGait) and the PLAYER is slowed by the load (updatePlayer)
HorseHitch.STRAIN_GO_M = 2.0
HorseHitch.SATURATE_MS = 0.5          -- the servo's gain is lowered for a heavy load so that the force limit is reached only with this much speed error (else it bangs between the limit and zero: a bouncy mess)
HorseHitch.STUCK_S = 4                -- waiting this long: said once that the load is too heavy
HorseHitch.LIFT_GAIN = 4              -- 1/s: the same for the height: the eye is lifted to the height of the traces' ends (the harness), not left lying on the ground
HorseHitch.LIFT_SPEED_MS = 1          -- ... at most this fast
HorseHitch.LIFT_MAX_KN = 1.5          -- the most the horse carries of the vehicle (the drawbar's weight, a tongue weight): a heavy rigid trailer is not lifted by its eye
HorseHitch.GRAVITY = 9.81
HorseHitch.LIFT_MAX_SHARE = 0.25     -- the eye is only lifted when the body it sits on is at most this share of the vehicle (a drawbar that is a body of its own: 60 kg of 660); a plate on the main body would tilt the whole machine (a skid steer was lifted by its tail)
HorseHitch.SWING_DAMP = 3             -- 1/s: the sideways swing of the vehicle's heavy body round the pin is damped (a pendulum with nothing against it swung for ever in the recording): its speed across the line pin -> body is cut by this much per second
HorseHitch.SWING_MAX_ACCEL_MS2 = 4
HorseHitch.SWING_MIN_ARM_M = 0.5      -- ... only when the body is this far from the eye
HorseHitch.LOG_EVERY_MS = 1000           -- for the first LOG_FOR_S seconds after hitching the log says what the pin does (the evidence for a recording: how far, how fast, with what force, brake)
HorseHitch.LOG_FOR_S = 40
HorseHitch.MOVING_MS = 0.15           -- a horse faster than this is "moving": the brake is off
HorseHitch.TOW_BAR_M = 1.6            -- a vehicle's OWN hitch (a skid steer's, a tractor's: kind "hitch", its body is right behind the plate) is pinned this far behind the hook, on a rigid tow bar: the body keeps clear of the horse
HorseHitch.TOW_BAR_DIAMETER = 0.03
HorseHitch.HOOK_RADIUS_M = 0.06       -- the steel ring where the traces meet and the eye is pinned
HorseHitch.HOOK_DIAMETER = 0.014
HorseHitch.HOOK_SEGMENTS = 6

local function winchApi()
    local winch = g_currentMission ~= nil and g_currentMission.winchTow or nil
    if winch ~= nil and winch.pick ~= nil then
        return winch
    end
    return nil
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

-- The middle between the ends of the harness's two traces (world x, y, z), or nil when the harness is not there.
function HorseHitch.anchor(ride)
    local rig = ride.rig
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

-- The hook and the traces' last pieces (made again when the harness was rebuilt: its end nodes are new): the ring's points hang under the world root and are placed every frame. Pieces: HOOK_SEGMENTS of
-- steel round the ring, and a trace from each harness trace end to the ring's front point (the one nearest the horse): the two traces meet at the hook.
local function makePieces(ride, hitch)
    deletePieces(hitch)
    hitch.rig = ride.rig
    local n = HorseHitch.HOOK_SEGMENTS
    hitch.ring = {}
    for i = 1, n do
        local node = createTransformGroup("horseHitchPoint")
        link(getRootNode(), node)
        hitch.nodes[#hitch.nodes + 1] = node
        hitch.ring[i] = node
    end
    local function piece(from, to, diameter, steel)
        local options = nil
        if not steel then
            options = HorseRope.gearOptions(nil, nil, nil, nil, nil, ride.harnessGear)
        end
        local rope = HorseRope.createSegment(from, diameter, options)
        if rope ~= nil then
            rope.rfMaterialDone = steel or nil                -- (the gear's material goes on the traces; the ring stays steel)
            hitch.pieces[#hitch.pieces + 1] = rope
            hitch.targets[#hitch.pieces] = to
        end
    end
    for i = 1, n do
        piece(hitch.ring[i], hitch.ring[i % n + 1], HorseHitch.HOOK_DIAMETER, true)
    end
    local front = hitch.ring[math.floor(n / 2) + 1]
    for _, node in pairs(ride.rig.traceEnds) do
        piece(node, front, HorseHarness.spec.trace.diameter, false)
    end
    if (hitch.barLength or 0) > 0 then
        piece(hitch.ring[1], hitch.node, HorseHitch.TOW_BAR_DIAMETER, true)      -- the tow bar: straight from the hook (its rear point) to the vehicle's hitch, steel
    end
end

-- The ring hangs at the pin, in the vertical plane along the horse (bx, bz: the way back): its point i at the angle (i - 1) * 360 / n from the way back, so the point floor(n / 2) + 1 faces the horse.
local function placeHook(hitch, ax, ay, az, bx, bz)
    local n = HorseHitch.HOOK_SEGMENTS
    local r = HorseHitch.HOOK_RADIUS_M
    for i = 1, n do
        local phi = 2 * math.pi * (i - 1) / n
        local along, up = r * math.cos(phi), r * math.sin(phi)
        setTranslation(hitch.ring[i], ax + bx * along, ay + up, az + bz * along)
    end
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
end

-- Lets the vehicle go: the brake goes back on, the support leg down, the ropes are deleted. Quiet when the ride has no hitch.
function HorseHitch.release(ride)
    local hitch = ride.hitch
    if hitch == nil then
        return false
    end
    ride.hitch = nil
    deletePieces(hitch)
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
                if HorseDynamics ~= nil and HorseDynamics.notify ~= nil then
                    HorseDynamics.notify(text)
                else
                    print("[HorseDynamics] " .. text)
                end
            end
        end
        if hitch.ring ~= nil then
            placeHook(hitch, ax, ay, az, bx, bz)
        end
        -- the gains: a heavy load gets softer ones (the force limit is reached with SATURATE_MS of speed error, the position loop is a third as fast as the speed loop): no bang-bang on the limit
        local mass = winch ~= nil and winch.pullMass ~= nil and winch.pullMass(hitch.vehicle, hitch.component) or getMass(hitch.component)
        local velGain = math.min(HorseHitch.VEL_GAIN, HorseHitch.MAX_PULL_KN / (mass * HorseHitch.SATURATE_MS))
        local posGain = math.min(HorseHitch.POS_GAIN, velGain / 3)
        -- the speed the joint should have: the horse's, and towards the pin (limited)
        local catchX, catchZ = ex * posGain, ez * posGain
        local catchLength = math.sqrt(catchX * catchX + catchZ * catchZ)
        if catchLength > HorseHitch.CATCH_SPEED_MS then
            catchX, catchZ = catchX * HorseHitch.CATCH_SPEED_MS / catchLength, catchZ * HorseHitch.CATCH_SPEED_MS / catchLength
        end
        local vx, _, vz = getLinearVelocity(hitch.component)
        local accelX = velGain * ((hitch.vx or 0) + catchX - vx)
        local accelZ = velGain * ((hitch.vz or 0) + catchZ - vz)
        local accelLength = math.sqrt(accelX * accelX + accelZ * accelZ)
        if accelLength > HorseHitch.MAX_ACCEL_MS2 then
            accelX, accelZ = accelX * HorseHitch.MAX_ACCEL_MS2 / accelLength, accelZ * HorseHitch.MAX_ACCEL_MS2 / accelLength
        end
        local moving = hitch.speed > HorseHitch.MOVING_MS or dist > 0.15
        hitch.logMs = (hitch.logMs or HorseHitch.LOG_EVERY_MS) + (dt or 16)
        hitch.loggedMs = (hitch.loggedMs or 0) + (dt or 16)
        if hitch.logMs >= HorseHitch.LOG_EVERY_MS and hitch.loggedMs <= HorseHitch.LOG_FOR_S * 1000 then
            hitch.logMs = 0
            local f = hitch.lastForce or { 0, 0, 0 }
            print(string.format("[HorseDynamics] hitch: pin off by %.2f m (%.2f, %.2f), eye height %.2f (traces %.2f), horse %.2f m/s, vehicle %.2f, %.2f m/s, %.2f t (joint body %.2f t), force %.2f, %.2f, %.2f kN, brake %s, strained %s",
                dist, ex, ez, jy, ay, hitch.speed, vx, vz, winch ~= nil and winch.pullMass ~= nil and winch.pullMass(hitch.vehicle, hitch.component) or -1, getMass(hitch.component), f[1], f[2], f[3], moving and "off" or "on", tostring(hitch.strained == true)))
            hitch.lastForce = nil
        end
        if winch ~= nil and winch.setBrakeOff ~= nil then
            winch.setBrakeOff(hitch, moving)
        end
        -- the height: the eye is carried at the height of the traces' ends (the harness): the weight of the body the joint sits on (the drawbar, 60 kg of the Wooden Trailer) plus a servo on the height,
        -- at most LIFT_MAX_KN. The vehicle's support leg is up (hitch), so the drawbar does not rest on the ground.
        local ownMass = getMass(hitch.component)
        local _, vy, _ = getLinearVelocity(hitch.component)
        local liftSpeed = math.max(-HorseHitch.LIFT_SPEED_MS, math.min(HorseHitch.LIFT_SPEED_MS, (ay - jy) * HorseHitch.LIFT_GAIN))
        local lift = math.max(0, math.min(HorseHitch.LIFT_MAX_KN, ownMass * (HorseHitch.GRAVITY + HorseHitch.VEL_GAIN * (liftSpeed - vy))))
        if (hitch.barLength or 0) > 0 or ownMass > HorseHitch.LIFT_MAX_SHARE * mass then
            lift = 0                                                -- (a vehicle's own hitch sits where it sits, and a plate on the main body is not lifted: the bar slopes down to it)
        end
        if accelLength > 1e-6 or lift > 0 then
            local forceX, forceZ = accelX * mass, accelZ * mass
            local forceLength = math.sqrt(forceX * forceX + forceZ * forceZ)
            if forceLength > HorseHitch.MAX_PULL_KN then
                forceX, forceZ = forceX * HorseHitch.MAX_PULL_KN / forceLength, forceZ * HorseHitch.MAX_PULL_KN / forceLength     -- (a horse is no tractor)
            end
            addForce(hitch.component, forceX, lift, forceZ, jx, jy, jz, false)
            hitch.lastForce = { forceX, lift, forceZ }    -- (tonnes * m/s2 = kN: the whole vehicle's mass along, the joint's body up: the joint's body can be a drawbar of 60 kg)
        end
        -- the swing: the speed of the heavy body across the line from the eye to it (relative to the horse) is damped, at the body's centre: a pendulum behind the pin swung on and on
        local body = hitch.body
        if body ~= nil and (entityExists == nil or entityExists(body)) then
            local cx, cy, cz = getWorldTranslation(body)
            local rx, rz = cx - jx, cz - jz
            local arm = math.sqrt(rx * rx + rz * rz)
            if arm > HorseHitch.SWING_MIN_ARM_M then
                local tx, tz = -rz / arm, rx / arm
                local bvx, _, bvz = getLinearVelocity(body)
                local across = (bvx - (hitch.vx or 0)) * tx + (bvz - (hitch.vz or 0)) * tz
                local swing = math.max(-HorseHitch.SWING_MAX_ACCEL_MS2, math.min(HorseHitch.SWING_MAX_ACCEL_MS2, -HorseHitch.SWING_DAMP * across))
                if swing ~= 0 then
                    local bodyMass = getMass(body)
                    addForce(body, tx * swing * bodyMass, 0, tz * swing * bodyMass, cx, cy, cz, false)
                end
            end
        end
    end
    -- the trace ropes
    if ride.rig ~= nil and ride.rig ~= hitch.rig then
        makePieces(ride, hitch)
    end
    for i, rope in ipairs(hitch.pieces) do
        HorseRope.applyMaterial(rope)
        pcall(rope.setVisibility, rope, true)
        if hitch.tied[i] then
            pcall(rope.update, rope, 0)
        elseif rope.referenceFrame ~= nil then
            hitch.tied[i] = pcall(rope.setTargetNode, rope, hitch.targets[i], true) or nil
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
    if winch.pullSpeed ~= nil and winch.pullMass ~= nil then
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
-- of the speeds: walk, canter, trot, gallop). Returns the gait to use for the one the horse's steering chose.
function HorseHitch.limitGait(ride, gait)
    local hitch = ride.hitch
    if hitch == nil or hitch.vehicle == nil or hitch.vehicle.isDeleted then
        return gait
    end
    local gaits = Rideable.GAITTYPES
    local rank = { [gaits.STILL] = 0, [gaits.WALK] = 1, [gaits.CANTER] = 2, [gaits.TROT] = 3, [gaits.GALLOP] = 4 }
    if gaits.BACKWARDS ~= nil then
        rank[gaits.BACKWARDS] = 0
    end
    if rank[gait] ~= nil and rank[gait] > rank[gaits.TROT] then
        return gaits.TROT
    end
    return gait
end
