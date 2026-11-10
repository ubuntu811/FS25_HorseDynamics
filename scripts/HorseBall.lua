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
HorseBall.MIN_SPEED = 0.35                  -- m/s a horse needs to kick (a standing horse only nudges)
HorseBall.CHEST_M = 0.9                     -- the horse's chest: this far ahead of its root
HorseBall.REACH_M = 0.55                    -- a ball whose surface is this close to the chest is kicked
HorseBall.KICK_COOLDOWN_MS = 350
HorseBall.KICK_GAIN = 0.7                   -- the ball leaves at this times the horse's speed ...
HorseBall.KICK_BASE = 1.0                   -- ... plus this (m/s): a trot (2.5 m/s) sends it at 2.8 m/s, a gallop (10 m/s) at 8
HorseBall.MAX_SPEED = 7                      -- the ball is never faster than this (m/s, 25 km/h): a horse's hoof is not a rifle (the engine's own contact of a 400 kg horse with a 3 kg ball would send it off at twice the horse's speed)
HorseBall.horses = {}                        -- vehicle -> { x, z } at the last frame
HorseBall.moving = {}                        -- the horses that move now (worked out once per frame)
HorseBall.frame = -1
HorseBall.lastKick = setmetatable({}, { __mode = "k" })
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

-- One ball, one frame (called from the vehicle specialization on the server).
function HorseBall.kick(vehicle, dt)
    local node = vehicle.components ~= nil and vehicle.components[1] ~= nil and vehicle.components[1].node or nil
    if node == nil or not entityExists(node) then
        return
    end
    HorseBall.updateHorses(dt)
    local now = g_time or 0
    local bx, by, bz = getWorldTranslation(node)
    -- what the physics did with it: 3 s after it appeared, how high its centre is above the ground (a ball that fell and rests shows its collision radius)
    local age = (HorseBall.age[vehicle] or 0) + dt
    HorseBall.age[vehicle] = age
    if age >= 3000 and age - dt < 3000 then
        local ground = getTerrainHeightAtWorldPos(g_terrainNode, bx, 0, bz)
        say("probe: centre %.2f m above the ground (the ball is %.2f m in radius), mass %.1f kg, sleeping: %s", by - ground, HorseBall.RADIUS, getMass(node) * 1000, tostring(getIsSleeping ~= nil and getIsSleeping(node)))
    end
    -- a ceiling on its speed (whatever pushed it: the kick, or the horse's body in the physics)
    local vx, vy, vz = getLinearVelocity(node)
    local speed = math.sqrt(vx * vx + vy * vy + vz * vz)
    if speed > HorseBall.MAX_SPEED then
        local k = HorseBall.MAX_SPEED / speed
        setLinearVelocity(node, vx * k, vy * k, vz * k)
    end
    if now - (HorseBall.lastKick[vehicle] or -1e9) < HorseBall.KICK_COOLDOWN_MS then
        return
    end
    for _, h in ipairs(HorseBall.moving) do
        local cx, cz = h.x + h.fx * HorseBall.CHEST_M, h.z + h.fz * HorseBall.CHEST_M
        local d = math.sqrt((bx - cx) ^ 2 + (bz - cz) ^ 2)
        local ahead = (bx - h.x) * h.fx + (bz - h.z) * h.fz
        if h.forward and d < HorseBall.RADIUS + HorseBall.REACH_M and ahead > 0 then
            local mass = getMass(node)
            local v = math.min(h.speed * HorseBall.KICK_GAIN + HorseBall.KICK_BASE, HorseBall.MAX_SPEED)
            local along = vx * h.fx + vz * h.fz                  -- (what the horse's body already gave it along the way)
            if along < v then
                addImpulse(node, h.fx * mass * (v - math.max(along, 0)), mass * 0.6, h.fz * mass * (v - math.max(along, 0)), bx, by, bz, false)
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
        if vehicle.configFileName ~= nil and string.find(string.lower(vehicle.configFileName), "horseball.xml", 1, true) ~= nil then
            list[#list + 1] = vehicle
        end
    end
    return list
end

function HorseBall.console(_, argument)
    if argument == "remove" then
        local list = balls()
        for _, vehicle in ipairs(list) do
            vehicle:delete()
        end
        return string.format("%d ball(s) removed", #list)
    end
    local px, _, pz = HorseLead.playerPosition()
    if px == nil or g_localPlayer == nil then
        return "no player position"
    end
    local ray = HorseLead.viewRay()
    local dx, dz = 0, 1
    if ray ~= nil then
        local l = math.sqrt(ray[4] * ray[4] + ray[6] * ray[6])
        if l > 1e-4 then dx, dz = ray[4] / l, ray[6] / l end
    end
    local x, z = px + dx * 5, pz + dz * 5
    local y = getTerrainHeightAtWorldPos(g_terrainNode, x, 0, z) + HorseBall.RADIUS + 0.3
    local data = VehicleLoadingData.new()
    data:setFilename(HorseBall.dir .. HorseBall.XML)
    data:setPosition(x, y, z)
    data:setRotation(0, 0, 0)
    data:setPropertyState(VehiclePropertyState.OWNED)
    data:setOwnerFarmId(g_localPlayer.farmId)
    data:load(function(_, vehicles, state)
        say("the ball was %s (%d vehicle(s))", state == VehicleLoadingState.OK and "loaded" or "NOT loaded: state " .. tostring(state), #(vehicles or {}))
    end, HorseBall)
    return "a ball is put 5 m in front of you (or look at the log)"
end

if addConsoleCommand ~= nil then
    addConsoleCommand("hdBall", "HorseDynamics: put a horse ball 5 m in front of you [remove]", "console", HorseBall)
end
