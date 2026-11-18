--[[
    HorseBall.lua -- the horse ball: a big red ball (vehicles/horseBall, written by tools/make_horse_ball.py: a mesh, its own baked collision hull and a dynamic component like the game's pallets) that is a
    shop item of the objects category (a vehicle of the type "horseBall", HorseBallVehicle). The game saves, delivers and syncs it like any vehicle.
    The kick: a horse (any rideable vehicle: led, ridden or loose) that is moving and whose chest reaches the ball in front of it gives the ball an impulse along its heading, the way the game's own football is
    shot (Football:shoot: addImpulse with mass * velocity), once per KICK_COOLDOWN_MS per ball. Console (testing without the shop): hdBall puts one in front of you, hdBall remove deletes them, hdBall free opens the tension belts that hold balls.
]]
HorseBall = {}
HorseBall.dir = g_currentModDirectory
HorseBall.XML = "vehicles/horseBall/horseBall.xml"
HorseBall.RADIUS = 0.45
HorseBall.RADII = { horseball = 0.45, horseballsmall = 0.25, horseballlarge = 0.70 }      -- by the vehicle's xml name (the test sizes of gsBall are vehicles/horseBall/horseBallSmall.xml and ...Large.xml)
HorseBall.MIN_SPEED = 0.35                  -- m/s a horse needs to kick (a standing horse only nudges)
HorseBall.CHEST_M = 0.9                     -- the horse's chest: this far ahead of its root
HorseBall.REACH_M = 0.55                    -- a ball whose surface is this close to the chest is kicked
HorseBall.KICK_COOLDOWN_MS = 350
HorseBall.KICK_GAIN = 1.0                   -- the ball leaves at this times the horse's speed ...
HorseBall.KICK_BASE = 1.5                   -- ... plus this (m/s): a walk (1.1 m/s) sends it at 2.6 m/s, a trot (2.5) at 4, a canter (5) at 6.5, a gallop is cut at the ball's top speed (7 for the normal one)
HorseBall.MAX_SPEED = 7                      -- the ball is never faster than this (m/s, 25 km/h): a horse's hoof is not a rifle (the engine's own contact of a 400 kg horse with a 3 kg ball would send it off at twice the horse's speed)
-- Rolling resistance follows the ground under the ball. The engine has one friction for every terrain, so it is set from the game's own measure of how soft the ground is (the depth that
-- getTerrainAttributesAtWorldPos returns: what WheelsUtil.getGroundType sorts into road / hard / soft terrain for the wheels; about 0 on a road, 0.6 on meadow): damping = base + gain * softness.
-- A road: the ball rolls a long way and stops in the end; grass: it slows down at once.
HorseBall.ROLL_ANGULAR_BASE = 0.05          -- the spin is damped lightly (a ball that is hit slides a moment, the ground's friction then spins it up: it rolls; a strong angular damping made it skid)
HorseBall.ROLL_ANGULAR_GAIN = 0.4           -- ... plus this times the softness (meadow 0.6: 0.29)
HorseBall.ROLL_LINEAR_BASE = 0.04           -- the rolling resistance is the slowing of the ball itself
HorseBall.ROLL_LINEAR_GAIN = 0.6            -- ... plus this times the softness (meadow: 0.40: a trot kick rolls about 10 m)
HorseBall.REST_WRITE_MIN = 0.003             -- m/s: slower than this nothing is written (the body is as good as asleep)
HorseBall.REST_SPEED = 0.08                 -- m/s: slower than this on the ground the ball is stopped (it would creep for ever)
HorseBall.CULL_M = 80                        -- a slow ball further than this from every horse and from the player is not looked at
HorseBall.CHECK_MS = 100                    -- the ground is read this often
-- How each weight option of the shop feels (the number is the option's place in horseBallWeightConfigurations, see tools/make_horse_ball.py WEIGHTS): how hard a horse kicks it, how soon it stops rolling
-- (a multiplier of the ground's damping), its top speed (m/s).
-- bounce: the part of the fall speed it gives back from the ground (the engine's own ball does not bounce at all): the lighter the ball, the more
HorseBall.PROFILES = {
    { kick = 1.0, roll = 1.0, max = 7.0, bounce = 0.5 },      -- 1 normal
    { kick = 1.4, roll = 1.5, max = 9.0, bounce = 0.85 },     -- 2 beach ball: light, flies off at a touch, but the air stops it; bounces like one
    { kick = 0.85, roll = 0.9, max = 6.5, bounce = 0.32 },    -- 3 medium
    { kick = 0.6, roll = 0.7, max = 5.0, bounce = 0.16 },     -- 4 heavy
    { kick = 0.4, roll = 0.5, max = 3.5, bounce = 0.05 },     -- 5 medicine ball: hardly moves, and once it does it keeps going
}
HorseBall.BOUNCE_MIN_FALL = 1.5              -- m/s: a slower fall does not bounce
HorseBall.BOUNCE_MIN_UP = 0.7                -- m/s: a bounce weaker than this is not made (the ball comes to rest)
HorseBall.BOUNCE_SOFT_LOSS = 0.5             -- the ground's softness (meadow 0.6) takes this times itself off a bounce: a road bounces most

-- Where a kick sends the ball: mostly away from the contact (from the horse's chest to the ball), a part along its heading, never more than about 75 degrees off the heading (a ball at the side of the chest is pushed
-- aside and forward, not back). (hx, hz) the heading, (cx, cz) the chest, (bx, bz) the ball; a unit vector. Pure.
HorseBall.KICK_HEADING_WEIGHT = 0.4          -- the share of the heading in the direction (the rest is the contact's)
HorseBall.KICK_MIN_FORWARD = 0.25            -- the least of the direction that goes along the heading
function HorseBall.kickDirection(hx, hz, cx, cz, bx, bz)
    local dx, dz = bx - cx, bz - cz
    local d = math.sqrt(dx * dx + dz * dz)
    if d < 1e-6 then
        return hx, hz
    end
    local w = HorseBall.KICK_HEADING_WEIGHT
    local kx, kz = hx * w + dx / d * (1 - w), hz * w + dz / d * (1 - w)
    local len = math.sqrt(kx * kx + kz * kz)
    if len < 1e-6 then
        return hx, hz
    end
    kx, kz = kx / len, kz / len
    local fwd = kx * hx + kz * hz
    if fwd < HorseBall.KICK_MIN_FORWARD then                  -- (pull it round towards the heading until enough of it points forward)
        kx, kz = kx + hx * (HorseBall.KICK_MIN_FORWARD - fwd), kz + hz * (HorseBall.KICK_MIN_FORWARD - fwd)
        len = math.sqrt(kx * kx + kz * kz); kx, kz = kx / len, kz / len
    end
    return kx, kz
end

-- The change of the ball's horizontal velocity (dvx, dvz) for a kick of speed v along the unit direction (kx, kz), the ball moving (vx, vz): it leaves along the kick, at v or at the speed it already had along it
-- (a faster ball is not slowed), and what it had sideways is taken away (a ball that was rolling at another angle goes off at the kick's). Pure.
function HorseBall.kickDelta(vx, vz, kx, kz, v)
    local along = math.max(0, vx * kx + vz * kz)
    local target = math.max(v, along)
    return kx * target - vx, kz * target - vz
end

-- The unit direction from (bx, by, bz) to the point `reach` m along the eye ray (ox, oy, oz, dx, dy, dz); nil when that is behind the ball or the ball is at the point. Pure.
function HorseBall.aimDirection(ray, bx, by, bz, reach)
    local ax, ay, az = ray[1] + ray[4] * reach, ray[2] + ray[5] * reach, ray[3] + ray[6] * reach
    local x, y, z = ax - bx, ay - by, az - bz
    local len = math.sqrt(x * x + y * y + z * z)
    if len < 0.5 or (x * ray[4] + y * ray[5] + z * ray[6]) <= 0 then
        return nil
    end
    return { x / len, y / len, z / len }
end

-- A ball in the player's hands is the hands' business: the joint moves it. Our code must not push it (a horse beside you "kicked" the ball you held, straight into your face; the speed ceiling and the
-- bounce wrote its velocity too). g_localPlayer.hands is the hands tool; getHeldItem is the node it holds.
function HorseBall.isHeld(node)
    local player = g_localPlayer
    local hands = player ~= nil and player.hands or nil
    return hands ~= nil and hands.getHeldItem ~= nil and node ~= nil and hands:getHeldItem() == node
end

-- A throw by the player (the game's hands: speed = 8 m/s x (1.1 - mass/0.2 t) x the charge, the charge growing over 1.2 s of holding the key: a tap is about 1 m/s, a full charge 8.8; thrown objects get object.thrownFromPosition).
-- The throw goes from the ball to the point the player's eye ray points at (THROW_AIM_M ahead), not parallel to the eye ray from the hand.
HorseBall.THROW_AIM_M = 8
-- Boosted once, when seen: speed = (THROW_GAIN x the game's speed + THROW_BASE) x the weight's kick, at least THROW_LIFT of its horizontal speed upwards (a flat throw would hit the ground at once), and for THROW_FLIGHT_MS
-- the ball may go THROW_MAX_FACTOR x faster than a kicked one, with the air's damping instead of the ground's.
HorseBall.THROW_GAIN = 1.8
HorseBall.THROW_BASE = 1.5                  -- m/s: even a tap is a toss (a full charge: 17 m/s before the ceiling, about 11 m/s after it)
HorseBall.THROW_LIFT = 0.3
HorseBall.THROW_MAX_FACTOR = 1.6
HorseBall.THROW_FLIGHT_MS = 2500
HorseBall.AIR_LINEAR = 0.03                 -- the linear damping while it flies (the ground's stays on it otherwise: a thrown ball lost its speed in the air)
HorseBall.handledThrow = setmetatable({}, { __mode = "k" })
HorseBall.thrownAt = setmetatable({}, { __mode = "k" })
-- The velocity a thrown ball gets from the one the game gave it (vx, vy, vz), prof = its weight profile. Pure. nil when the game gave it (almost) none.
function HorseBall.throwVelocity(vx, vy, vz, prof, aim)
    local s = math.sqrt(vx * vx + vy * vy + vz * vz)
    if s < 0.05 then
        return nil
    end
    local ns = math.min((HorseBall.THROW_GAIN * s + HorseBall.THROW_BASE) * prof.kick, prof.max * HorseBall.THROW_MAX_FACTOR)
    local k = ns / s
    vx, vy, vz = vx * k, vy * k, vz * k
    if aim ~= nil then                                          -- (the direction from the ball to where the player looks, not the eye ray's own: the hand is not at the eye)
        vx, vy, vz = aim[1] * ns, aim[2] * ns, aim[3] * ns
    end
    vy = math.max(vy, HorseBall.THROW_LIFT * math.sqrt(vx * vx + vz * vz))
    local k2 = ns / math.sqrt(vx * vx + vy * vy + vz * vz)          -- (the lift is taken from the horizontal speed: the total stays what was worked out)
    return vx * k2, vy * k2, vz * k2
end

-- The upward speed to give a ball whose fall was stopped by the ground this frame, or nil. lastVy: its vertical speed the frame before (negative: falling), vy: now. Pure.
function HorseBall.bounceSpeed(lastVy, vy, bounce, soft)
    if lastVy == nil or bounce == nil or bounce <= 0 or lastVy > -HorseBall.BOUNCE_MIN_FALL or vy <= lastVy * 0.4 then
        return nil                           -- (not falling fast enough, or the fall was not stopped: it is still falling)
    end
    local up = -lastVy * bounce * (1 - HorseBall.BOUNCE_SOFT_LOSS * math.max(0, math.min(1, soft or 0)))
    return up >= HorseBall.BOUNCE_MIN_UP and up or nil
end
function HorseBall.profile(vehicle)
    local id = vehicle.configurations ~= nil and vehicle.configurations.horseBallWeight or 1
    return HorseBall.PROFILES[id] or HorseBall.PROFILES[1]
end
HorseBall.horses = {}                        -- vehicle -> { x, z } at the last frame
HorseBall.moving = {}                        -- the horses that move now (worked out once per frame)
HorseBall.frame = -1
HorseBall.lastKick = setmetatable({}, { __mode = "k" })
HorseBall.ground = setmetatable({}, { __mode = "k" })
HorseBall.age = setmetatable({}, { __mode = "k" })
HorseBall.lastVy = setmetatable({}, { __mode = "k" })

local function say(format, ...)
    print(string.format("[HorseDynamics] ball: " .. format, ...))
end

-- The horses' speed and heading from the way they moved since the last frame, once per frame (every ball asks).
function HorseBall.updateHorses(dt)
    local frame = g_updateLoopIndex or 0
    if frame == HorseBall.frame then
        return
    end
    HorseBall.frame = frame
    local moving, watch = {}, {}
    for _, vehicle in ipairs(HorseLead.rideables()) do
        local x, _, z = getWorldTranslation(vehicle.rootNode)
        local last = HorseBall.horses[vehicle]
        if last ~= nil and dt > 0 then
            local vx, vz = (x - last[1]) / (dt / 1000), (z - last[2]) / (dt / 1000)
            local speed = math.sqrt(vx * vx + vz * vz)
            if speed >= HorseBall.MIN_SPEED and speed < 25 then
                local fx, _, fz = localDirectionToWorld(vehicle.rootNode, 0, 0, 1)
                local fl = math.sqrt(fx * fx + fz * fz)
                if fl > 1e-4 then
                    moving[#moving + 1] = { x = x, z = z, fx = fx / fl, fz = fz / fl, speed = speed, forward = (vx * fx + vz * fz) > 0 }
                end
            end
        end
        HorseBall.horses[vehicle] = { x, z }
        watch[#watch + 1] = x; watch[#watch + 1] = z
    end
    local px, _, pz = HorseLead.playerPosition()
    HorseBall.watchAll = px == nil                    -- (no player position: nothing is far away)
    if px ~= nil then
        watch[#watch + 1] = px; watch[#watch + 1] = pz
    end
    HorseBall.watch = watch
    HorseBall.moving = moving
end

-- A ball is near when a horse or the player is within CULL_M of it; far and slow balls are left alone (no work at all, so the engine can let them sleep).
function HorseBall.isNear(x, z)
    if HorseBall.watchAll then
        return true
    end
    local w, r2 = HorseBall.watch, HorseBall.CULL_M * HorseBall.CULL_M
    for i = 1, #w, 2 do
        local dx, dz = x - w[i], z - w[i + 1]
        if dx * dx + dz * dz < r2 then
            return true
        end
    end
    return false
end

HorseBall.radiusCache = setmetatable({}, { __mode = "k" })
function HorseBall.radiusOf(vehicle)
    local cached = HorseBall.radiusCache[vehicle]
    if cached ~= nil then
        return cached
    end
    local r = HorseBall.radiusOfUncached(vehicle)
    HorseBall.radiusCache[vehicle] = r
    return r
end

function HorseBall.radiusOfUncached(vehicle)
    local name = vehicle.configFileName ~= nil and string.match(string.lower(vehicle.configFileName), "([^/\\]+)%.xml$") or nil
    return HorseBall.RADII[name or ""] or HorseBall.RADIUS
end

-- One ball, one frame (called from the vehicle specialization on the server).
function HorseBall.kick(vehicle, dt)
    local node = vehicle.components ~= nil and vehicle.components[1] ~= nil and vehicle.components[1].node or nil
    if node == nil or not entityExists(node) then
        return
    end
    if HorseBall.isHeld(node) then
        HorseBall.lastVy[vehicle] = nil
        return
    end
    if getRigidBodyType ~= nil and getRigidBodyType(node) ~= RigidBodyType.DYNAMIC then
        HorseBall.ground[vehicle] = nil              -- (a body that is dynamic again is a new one: its damping is set anew)
        return                                     -- (frozen by the Hammer, or locked to something: nothing to kick or damp)
    end
    HorseBall.updateHorses(dt)
    do
        local ex, _, ez = getWorldTranslation(node)
        if not HorseBall.isNear(ex, ez) and vehicle.thrownFromPosition == HorseBall.handledThrow[vehicle] then
            local wx, wy, wz = getLinearVelocity(node)
            if wx * wx + wy * wy + wz * wz < 0.25 then
                return
            end
        end
    end
    local radius = HorseBall.radiusOf(vehicle)
    local prof = HorseBall.profile(vehicle)
    local now = g_time or 0
    local bx, by, bz = getWorldTranslation(node)         -- (the origin of the ball is its bottom: the centre is one radius up)
    local cy = by + radius
    -- what the physics did with it: 3 s after it appeared, how high its centre is above the ground (a ball that fell and rests shows its collision radius)
    local age = (HorseBall.age[vehicle] or 0) + dt
    HorseBall.age[vehicle] = age
    if age >= 3000 and age - dt < 3000 then
        local ground = getTerrainHeightAtWorldPos(g_terrainNode, bx, 0, bz)
        local _, _, _, depth = getTerrainAttributesAtWorldPos(g_terrainNode, bx, by, bz, true, true, true, true, false)
        say("probe: bottom %.2f m above the ground (0 = it rests on it; the ball is %.2f m in radius), ground softness %.2f, body mass %.1f kg (the vehicle says %.1f), sleeping: %s", by - ground, radius, depth or -1, getMass(node) * 1000, (vehicle.getTotalMass ~= nil and vehicle:getTotalMass() or 0) * 1000, tostring(getIsSleeping ~= nil and getIsSleeping(node)))
    end
    -- a ceiling on its speed (whatever pushed it: the kick, or the horse's body in the physics)
    local vx, vy, vz = getLinearVelocity(node)
    -- the bounce: a fall that the ground stopped this frame gives part of its speed back (lighter balls more)
    local lastVy = HorseBall.lastVy[vehicle]
    HorseBall.lastVy[vehicle] = vy
    if lastVy ~= nil and lastVy < -HorseBall.BOUNCE_MIN_FALL and by - getTerrainHeightAtWorldPos(g_terrainNode, bx, 0, bz) < 0.3 then
        local st0 = HorseBall.ground[vehicle]
        local up = HorseBall.bounceSpeed(lastVy, vy, prof.bounce, st0 ~= nil and st0.soft or 0.6)
        if up ~= nil then
            vy = up
            setLinearVelocity(node, vx, vy, vz)
            HorseBall.lastVy[vehicle] = up
        end
    end
    local thrown = vehicle.thrownFromPosition
    if thrown ~= nil and thrown ~= HorseBall.handledThrow[vehicle] then
        HorseBall.handledThrow[vehicle] = thrown
        local ray = HorseLead ~= nil and HorseLead.viewRay ~= nil and HorseLead.viewRay() or nil
        local aim = ray ~= nil and HorseBall.aimDirection(ray, bx, cy, bz, HorseBall.THROW_AIM_M) or nil
        local tx, ty, tz = HorseBall.throwVelocity(vx, vy, vz, prof, aim)
        if tx ~= nil then
            say("throw: the game gave it %.1f m/s, it leaves at %.1f m/s", math.sqrt(vx * vx + vy * vy + vz * vz), math.sqrt(tx * tx + ty * ty + tz * tz))
            vx, vy, vz = tx, ty, tz
            setLinearVelocity(node, vx, vy, vz)
            HorseBall.thrownAt[vehicle] = now
            local st0 = HorseBall.ground[vehicle]
            if st0 ~= nil then st0.soft = nil end
            pcall(setLinearDamping, node, HorseBall.AIR_LINEAR * prof.roll)
        end
    end
    local speed = math.sqrt(vx * vx + vy * vy + vz * vz)
    local cap = prof.max
    if HorseBall.thrownAt[vehicle] ~= nil and now - HorseBall.thrownAt[vehicle] < HorseBall.THROW_FLIGHT_MS then
        cap = prof.max * HorseBall.THROW_MAX_FACTOR
    end
    if speed > cap then
        local k = cap / speed
        setLinearVelocity(node, vx * k, vy * k, vz * k)
    end
    -- the ground under it: damping from its softness while it rolls on it (not while it flies)
    local st = HorseBall.ground[vehicle]
    if st == nil then
        st = { nextCheck = 0 }
        HorseBall.ground[vehicle] = st
    end
    if now >= st.nextCheck then
        st.nextCheck = now + HorseBall.CHECK_MS
        local terrainY = getTerrainHeightAtWorldPos(g_terrainNode, bx, 0, bz)
        if by - terrainY < 0.2 then
            local _, _, _, depth = getTerrainAttributesAtWorldPos(g_terrainNode, bx, by, bz, true, true, true, true, false)
            local soft = math.max(0, math.min(1, depth or 0))
            if st.soft == nil or math.abs(st.soft - soft) > 0.02 then
                st.soft = soft
                pcall(setAngularDamping, node, (HorseBall.ROLL_ANGULAR_BASE + HorseBall.ROLL_ANGULAR_GAIN * soft) * prof.roll)
                pcall(setLinearDamping, node, (HorseBall.ROLL_LINEAR_BASE + HorseBall.ROLL_LINEAR_GAIN * soft) * prof.roll)
            end
            if speed < HorseBall.REST_SPEED and speed > HorseBall.REST_WRITE_MIN then
                setLinearVelocity(node, 0, math.min(vy, 0), 0)          -- (once: writing a velocity wakes a sleeping body, so a ball that already stands still is left alone and can sleep)
            end
        elseif by - terrainY > 0.5 and not st.air then
            st.air = true
            pcall(setLinearDamping, node, HorseBall.AIR_LINEAR * prof.roll)
            st.soft = nil                                         -- (so the ground's damping is set again on landing)
        end
        if st.air and by - terrainY < 0.2 then st.air = false end
    end
    if now - (HorseBall.lastKick[vehicle] or -1e9) < HorseBall.KICK_COOLDOWN_MS then
        return
    end
    for _, h in ipairs(HorseBall.moving) do
        local cx, cz = h.x + h.fx * HorseBall.CHEST_M, h.z + h.fz * HorseBall.CHEST_M
        local d = math.sqrt((bx - cx) ^ 2 + (bz - cz) ^ 2)
        local ahead = (bx - h.x) * h.fx + (bz - h.z) * h.fz
        if h.forward and d < radius + HorseBall.REACH_M and ahead > 0 then
            local mass = getMass(node)
            local v = math.min((h.speed * HorseBall.KICK_GAIN + HorseBall.KICK_BASE) * prof.kick, prof.max)
            local kx, kz = HorseBall.kickDirection(h.fx, h.fz, cx, cz, bx, bz)
            local dvx, dvz = HorseBall.kickDelta(vx, vz, kx, kz, v)      -- (what the horse's body already gave it counts: it is the ball's own velocity now)
            addImpulse(node, dvx * mass, mass * 0.6, dvz * mass, bx, cy + 0.4 * radius, bz, false)
            HorseBall.lastKick[vehicle] = now
            say("kick: horse at %.1f m/s, ball leaves at about %.1f m/s, %.0f degrees off the horse's heading", h.speed, v, math.deg(math.atan2(kx * h.fz - kz * h.fx, kx * h.fx + kz * h.fz)))
            return
        end
    end
end

-- ===== console, to try one without the shop =====
local function balls()
    local list = {}
    local vehicles = g_currentMission ~= nil and g_currentMission.vehicleSystem ~= nil and g_currentMission.vehicleSystem.vehicles or {}
    for _, vehicle in ipairs(vehicles) do
        if vehicle.configFileName ~= nil and string.find(string.lower(vehicle.configFileName), "/horseball[a-z]*%.xml$") ~= nil then
            list[#list + 1] = vehicle
        end
    end
    return list
end

-- a point in front of the player: forward distance, sideways offset (to the right), on the ground
local function spot(forward, side)
    local px, _, pz = HorseLead.playerPosition()
    if px == nil then
        return nil
    end
    local ray = HorseLead.viewRay()
    local dx, dz = 0, 1
    if ray ~= nil then
        local l = math.sqrt(ray[4] * ray[4] + ray[6] * ray[6])
        if l > 1e-4 then dx, dz = ray[4] / l, ray[6] / l end
    end
    local x, z = px + dx * forward + dz * side, pz + dz * forward - dx * side
    return x, getTerrainHeightAtWorldPos(g_terrainNode, x, 0, z), z
end

function HorseBall.spawn(xml, x, y, z, weight)
    local data = VehicleLoadingData.new()
    data:setFilename(HorseBall.dir .. "vehicles/horseBall/" .. xml)
    data:setPosition(x, y, z)
    data:setRotation(0, 0, 0)
    data:setPropertyState(VehiclePropertyState.OWNED)
    data:setOwnerFarmId(g_localPlayer.farmId)
    if weight ~= nil then
        data:setConfigurations({ horseBallWeight = weight })
    end
    data:load(function(_, vehicles, state)
        if state ~= VehicleLoadingState.OK then
            say("%s (weight %s) was NOT loaded: state %s", xml, tostring(weight), tostring(state))
        end
    end, HorseBall)
end

function HorseBall.console(_, argument)
    if argument == "remove" then
        local list = balls()
        for _, vehicle in ipairs(list) do
            vehicle:delete()
        end
        return string.format("%d ball(s) removed", #list)
    end
    if argument == "free" then
        -- un-glue: every vehicle whose tension belts hold a ball opens them all (the game's own toggle of the belts)
        local freed, vehicles = 0, g_currentMission.vehicleSystem.vehicles
        for _, vehicle in ipairs(vehicles) do
            local spec = vehicle.spec_tensionBelts
            if spec ~= nil and spec.hasTensionBelts and vehicle.getHasObjectMounted ~= nil then
                for _, ball in ipairs(balls()) do
                    if vehicle:getHasObjectMounted(ball) then
                        vehicle:setAllTensionBeltsActive(false)
                        freed = freed + 1
                        break
                    end
                end
            end
        end
        return string.format("%d vehicle(s) opened their tension belts (they hold balls)", freed)
    end
    if g_localPlayer == nil then
        return "no player"
    end
    local x, y, z = spot(5, 0)
    if x == nil then
        return "no player position"
    end
    HorseBall.spawn(argument == "mice" and "horseBallMice.xml" or "horseBall.xml", x, y + 0.3, z, nil)
    return "a ball is put 5 m in front of you (or look at the log); hdBall mice for the mouse ball"
end

-- gsBall: a test set, 3 sizes (rows: small, normal, large) x 3 weights (columns: light, medium, heavy), in front of you; gsBall remove deletes every ball
function HorseBall.consoleSet(_, argument)
    if argument == "remove" then
        return HorseBall.console(nil, "remove")
    end
    if g_localPlayer == nil or HorseLead.playerPosition() == nil then
        return "no player"
    end
    local rows = { { "horseBallSmall.xml", 0.25 }, { "horseBall.xml", 0.45 }, { "horseBallLarge.xml", 0.70 } }
    local count = 0
    for r, row in ipairs(rows) do
        for weight = 1, 5 do
            local x, y, z = spot(4 + (r - 1) * 2.6, (weight - 3) * 2.2)
            HorseBall.spawn(row[1], x, y + 0.3, z, weight)
            count = count + 1
        end
    end
    return string.format("%d balls in front of you: rows small / normal / large, columns normal / beach ball / medium / heavy / medicine ball (gsBall remove deletes them)", count)
end

if addConsoleCommand ~= nil then
    addConsoleCommand("hdBall", "HorseDynamics: put a horse ball 5 m in front of you [remove|free]", "console", HorseBall)
    addConsoleCommand("gsBall", "HorseDynamics: a test set of horse balls in front of you: 3 sizes x 5 weights [remove]", "consoleSet", HorseBall)
end
