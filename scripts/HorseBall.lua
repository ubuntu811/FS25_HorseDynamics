--[[
    HorseBall.lua -- a big, bright red ball (models/ball: a dynamic rigid body written by tools/make_horse_ball.py, 90 cm across) that horses kick around. Console: hdBall (a ball in front of you, or
    put the one you have there again), hdBall remove, hdBall game (the game's own football, scaled up, as a fallback if this one's physics does not work).
    The kick: the engine's own push of a horse's body is not counted on. A horse (any rideable vehicle: led, ridden or loose) that is moving and whose chest reaches the ball in front of it gives the ball an
    impulse along its heading, the way the game's own football is shot (addImpulse with mass * velocity, Football:shoot), once per KICK_COOLDOWN_MS per ball.
]]
HorseBall = {}
HorseBall.dir = g_currentModDirectory
HorseBall.RADIUS = 0.45
HorseBall.MIN_SPEED = 0.35                  -- m/s a horse needs to kick (a standing horse only nudges)
HorseBall.CHEST_M = 0.9                     -- the horse's chest: this far ahead of its root
HorseBall.REACH_M = 0.55                    -- a ball whose surface is this close to the chest is kicked
HorseBall.KICK_COOLDOWN_MS = 350
HorseBall.balls = {}
HorseBall.horses = {}                        -- vehicle -> { x, z } last position (speed from the way it moved)

local function say(format, ...)
    print(string.format("[HorseDynamics] ball: " .. format, ...))
end

function HorseBall.loadNode(path)
    local resolved = Utils ~= nil and Utils.getFilename ~= nil and Utils.getFilename(path, nil) or path
    local root = loadI3DFile(resolved, false, false, false)
    if root == nil or root == 0 then
        return nil
    end
    local node = getChildAt(root, 0)
    unlink(node)
    delete(root)
    return node
end

-- Three bodies: "red" (the default): the game's own football body (its collision is baked by the Editor: a working dynamic body) scaled up, with my red sphere in place of its picture; "own": my own
-- mesh as the body (the engine has to cook its collision at runtime: it did not become a working body); "game": the game's football as it is, scaled up.
HorseBall.SCALE = 2.0                         -- the game's football hull is 0.23 m in radius: 0.46 m, a ball 92 cm across
function HorseBall.spawn(x, y, z, mode)
    local node, radius, scale = nil, HorseBall.RADIUS, 1
    if mode == "own" then
        node = HorseBall.loadNode(HorseBall.dir .. "models/ball/horseBall.i3d")
    else
        node = HorseBall.loadNode("$data/maps/mapEU/textures/props/gameplay/football.i3d")
        scale, radius = HorseBall.SCALE, 0.23 * HorseBall.SCALE
        if node ~= nil and mode == "red" then
            local picture = getChildAt(node, 0)
            local red = HorseBall.loadNode(HorseBall.dir .. "models/ball/horseBallVisual.i3d")
            if red ~= nil then
                delete(picture)
                link(node, red)
                setTranslation(red, 0, 0, 0)
            else
                say("the red picture could not be loaded: the game's own picture stays")
            end
        end
    end
    if node == nil then
        return nil, "the ball model could not be loaded (see the log)"
    end
    link(getRootNode(), node)
    if scale ~= 1 then
        setScale(node, scale, scale, scale)
    end
    local ok, err = pcall(function()
        setWorldTranslation(node, x, y, z)
        addToPhysics(node)
    end)
    if not ok then
        say("could not put the ball into the physics: %s", tostring(err))
    end
    local ball = { node = node, radius = radius, lastKick = -1e9, mode = mode, probeIn = 3000, spawnY = y }
    HorseBall.balls[#HorseBall.balls + 1] = ball
    say("a %s ball (radius %.2f m) at %.1f %.1f %.1f, mass %s kg", mode, radius, x, y, z, tostring(pcall(getMass, node) and getMass(node) * 1000 or "?"))
    return ball
end

function HorseBall.remove()
    local n = #HorseBall.balls
    for _, ball in ipairs(HorseBall.balls) do
        if ball.node ~= nil and entityExists(ball.node) then
            pcall(removeFromPhysics, ball.node)
            delete(ball.node)
        end
    end
    HorseBall.balls = {}
    return n
end

-- A point in front of the player, on the ground there.
local function spotInFront(distance)
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
    local x, z = px + dx * distance, pz + dz * distance
    local y = getTerrainHeightAtWorldPos(g_terrainNode, x, 0, z)
    return x, y, z
end

function HorseBall.console(_, argument)
    if argument == "remove" then
        return string.format("%d ball(s) removed", HorseBall.remove())
    end
    local mode = (argument == "own" or argument == "game") and argument or "red"
    local x, y, z = spotInFront(5)
    if x == nil then
        return "no player position"
    end
    local radius = mode == "own" and HorseBall.RADIUS or 0.23 * HorseBall.SCALE
    HorseBall.remove()
    local ball, err = HorseBall.spawn(x, y + radius + 0.3, z, mode)
    if ball == nil then
        return err
    end
    return string.format("the %s ball is 5 m in front of you: ride or lead a horse into it", mode)
end

-- The tool's switch: no ball -> one is put down 3.5 m in front of you; a ball -> it is picked up.
function HorseBall.toggle()
    if #HorseBall.balls > 0 then
        HorseBall.remove()
        return "ball picked up"
    end
    local x, y, z = spotInFront(3.5)
    if x == nil then
        return "no player position"
    end
    local ball, err = HorseBall.spawn(x, y + 0.23 * HorseBall.SCALE + 0.3, z, "red")
    return ball ~= nil and "ball put down: ride or lead a horse into it" or err
end

function HorseBall.update(dt)
    if #HorseBall.balls == 0 then
        return
    end
    local now = g_time or 0
    -- the horses' speed from the way they moved since the last frame
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
    for i = #HorseBall.balls, 1, -1 do
        local ball = HorseBall.balls[i]
        if ball.node == nil or not entityExists(ball.node) then
            table.remove(HorseBall.balls, i)
        else
            local bx, by, bz = getWorldTranslation(ball.node)
            local ground = getTerrainHeightAtWorldPos(g_terrainNode, bx, 0, bz)
            if ball.probeIn ~= nil then
                ball.probeIn = ball.probeIn - dt
                if ball.probeIn <= 0 then
                    ball.probeIn = nil
                    -- a dynamic ball has fallen on the grass by now and rests with its centre one radius above it; one that is not in the physics is still where it was put
                    say("probe 3 s after it was put down: centre %.2f m above the ground (it was put %.2f m above; a ball that fell and rests shows its collision radius, about %.2f), sleeping: %s",
                        by - ground, ball.spawnY - ground, ball.radius, tostring(getIsSleeping ~= nil and getIsSleeping(ball.node)))
                end
            end
            if by < ground - 3 then
                pcall(function() setWorldTranslation(ball.node, bx, ground + ball.radius + 1, bz); addToPhysics(ball.node) end)        -- (fell through: put back on top)
                say("the ball had fallen through the ground: put back")
            end
            if now - ball.lastKick >= HorseBall.KICK_COOLDOWN_MS then
                for _, h in ipairs(moving) do
                    local cx, cz = h.x + h.fx * HorseBall.CHEST_M, h.z + h.fz * HorseBall.CHEST_M
                    local d = math.sqrt((bx - cx) ^ 2 + (bz - cz) ^ 2)
                    local ahead = (bx - h.x) * h.fx + (bz - h.z) * h.fz
                    if h.forward and d < ball.radius + HorseBall.REACH_M and ahead > 0 then
                        local mass = getMass(ball.node)
                        local v = h.speed * 1.4 + 1.5               -- the ball leaves faster than the horse
                        addImpulse(ball.node, h.fx * mass * v, mass * 1.2, h.fz * mass * v, bx, by, bz, false)
                        ball.lastKick = now
                        say("kick: horse at %.1f m/s, ball leaves at about %.1f m/s", h.speed, v)
                        break
                    end
                end
            end
        end
    end
end

function HorseBall.delete()
    HorseBall.remove()
end

if addConsoleCommand ~= nil then
    addConsoleCommand("hdBall", "HorseDynamics: a big red ball for the horses to kick [remove | game]", "console", HorseBall)
end
