--[[
    HorseBall.lua -- the horse ball: a big red ball (vehicles/horseBall, written by tools/make_horse_ball.py: a mesh, its own baked collision hull and a dynamic component like the game's pallets) that is a
    shop item of the objects category (a vehicle of the type "horseBall", HorseBallVehicle). The game saves, delivers and syncs it like any vehicle.
    The kick: a horse (any rideable vehicle: led, ridden or loose) that is moving and whose chest reaches the ball in front of it gives the ball an impulse along its heading, the way the game's own football is
    shot (Football:shoot: addImpulse with mass * velocity), once per KICK_COOLDOWN_MS per ball. Console (testing without the shop): hdBall puts one in front of you, hdBall remove deletes them.
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
HorseBall.KICK_GAIN = 0.7                   -- the ball leaves at this times the horse's speed ...
HorseBall.KICK_BASE = 1.0                   -- ... plus this (m/s): a trot (2.5 m/s) sends it at 2.8 m/s, a gallop (10 m/s) at 8
HorseBall.MAX_SPEED = 7                      -- the ball is never faster than this (m/s, 25 km/h): a horse's hoof is not a rifle (the engine's own contact of a 400 kg horse with a 3 kg ball would send it off at twice the horse's speed)
-- Rolling resistance follows the ground under the ball. The engine has one friction for every terrain, so it is set from the game's own measure of how soft the ground is (the depth that
-- getTerrainAttributesAtWorldPos returns: what WheelsUtil.getGroundType sorts into road / hard / soft terrain for the wheels; about 0 on a road, 0.6 on meadow): damping = base + gain * softness.
-- A road: the ball rolls a long way and stops in the end; grass: it slows down at once.
HorseBall.ROLL_ANGULAR_BASE = 0.05          -- the spin is damped lightly (a ball that is hit slides a moment, the ground's friction then spins it up: it rolls; a strong angular damping made it skid)
HorseBall.ROLL_ANGULAR_GAIN = 0.4           -- ... plus this times the softness (meadow 0.6: 0.29)
HorseBall.ROLL_LINEAR_BASE = 0.04           -- the rolling resistance is the slowing of the ball itself
HorseBall.ROLL_LINEAR_GAIN = 0.9            -- ... plus this times the softness (meadow: 0.58)
HorseBall.REST_SPEED = 0.08                 -- m/s: slower than this on the ground the ball is stopped (it would creep for ever)
HorseBall.CHECK_MS = 100                    -- the ground is read this often
-- How each weight option of the shop feels (the number is the option's place in horseBallWeightConfigurations, see tools/make_horse_ball.py WEIGHTS): how hard a horse kicks it, how soon it stops rolling
-- (a multiplier of the ground's damping), its top speed (m/s).
HorseBall.PROFILES = {
    { kick = 1.0, roll = 1.0, max = 7.0 },      -- 1 normal
    { kick = 1.4, roll = 1.5, max = 9.0 },      -- 2 beach ball: light, flies off at a touch, but the air stops it
    { kick = 0.85, roll = 0.9, max = 6.5 },     -- 3 medium
    { kick = 0.6, roll = 0.7, max = 5.0 },      -- 4 heavy
    { kick = 0.4, roll = 0.5, max = 3.5 },      -- 5 medicine ball: hardly moves, and once it does it keeps going
}
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
    local moving = {}
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
    end
    HorseBall.moving = moving
end

function HorseBall.radiusOf(vehicle)
    local name = vehicle.configFileName ~= nil and string.match(string.lower(vehicle.configFileName), "([^/\\]+)%.xml$") or nil
    return HorseBall.RADII[name or ""] or HorseBall.RADIUS
end

-- One ball, one frame (called from the vehicle specialization on the server).
function HorseBall.kick(vehicle, dt)
    local node = vehicle.components ~= nil and vehicle.components[1] ~= nil and vehicle.components[1].node or nil
    if node == nil or not entityExists(node) then
        return
    end
    HorseBall.updateHorses(dt)
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
        say("probe: bottom %.2f m above the ground (0 = it rests on it; the ball is %.2f m in radius), ground softness %.2f, mass %.1f kg, sleeping: %s", by - ground, radius, depth or -1, getMass(node) * 1000, tostring(getIsSleeping ~= nil and getIsSleeping(node)))
    end
    -- a ceiling on its speed (whatever pushed it: the kick, or the horse's body in the physics)
    local vx, vy, vz = getLinearVelocity(node)
    local speed = math.sqrt(vx * vx + vy * vy + vz * vz)
    if speed > prof.max then
        local k = prof.max / speed
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
            if speed < HorseBall.REST_SPEED then
                setLinearVelocity(node, 0, math.min(vy, 0), 0)
            end
        end
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
            local along = vx * h.fx + vz * h.fz                  -- (what the horse's body already gave it along the way)
            if along < v then
                addImpulse(node, h.fx * mass * (v - math.max(along, 0)), mass * 0.6, h.fz * mass * (v - math.max(along, 0)), bx, cy + 0.4 * radius, bz, false)
            end
            HorseBall.lastKick[vehicle] = now
            say("kick: horse at %.1f m/s, ball leaves at about %.1f m/s", h.speed, v)
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
    if g_localPlayer == nil then
        return "no player"
    end
    local x, y, z = spot(5, 0)
    if x == nil then
        return "no player position"
    end
    HorseBall.spawn("horseBall.xml", x, y + 0.3, z, nil)
    return "a ball is put 5 m in front of you (or look at the log)"
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
    addConsoleCommand("hdBall", "HorseDynamics: put a horse ball 5 m in front of you [remove]", "console", HorseBall)
    addConsoleCommand("gsBall", "HorseDynamics: a test set of horse balls in front of you: 3 sizes x 5 weights [remove]", "consoleSet", HorseBall)
end
