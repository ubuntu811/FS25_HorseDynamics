--[[
    HorseStirrup.lua -- the stirrups hang flat against the horse while nobody rides (the game's own pose = the leading pose) and move under the rider's feet while somebody does (the riding pose).
    Each stirrup has its own bone in our models (stirrupJoint_L / _R under Spine1_M, at the top of the leather: dev/foal/tools/stirrup_bones.py). The riding pose is a translation of that bone
    (HorseStirrupPose.lua, generated from the measured position of the rider's ToeBase nodes: dev/foal/stirrup_feet.json) and a yaw about the iron's own vertical axis (HorseStirrup.YAW). HorseStirrup.SCALE multiplies the move (hdStirrup <factor>).
]]
HorseStirrup = HorseStirrup or {}

HorseStirrup.YAW = -60                -- the turn of each iron about its own vertical axis in the riding pose, degrees: the boot goes through it, so the bar runs across the foot (the left one turns by YAW, the right one by -YAW); hdStirrup yaw <deg>
HorseStirrup.SCALE = 1                 -- 1 = the measured riding move; hdStirrup <factor> changes it (5 or 100 shows the direction)
HorseStirrup.SPEED_PER_S = 4           -- how fast the bones move between the poses (1 = a whole move per second)
HorseStirrup.state = setmetatable({}, { __mode = "k" })

-- One step towards the target (0 = flat against the horse, 1 = under the rider's feet) (pure).
function HorseStirrup.step(f, target, dt)
    local maxStep = HorseStirrup.SPEED_PER_S * dt / 1000
    if math.abs(target - f) <= maxStep then
        return target
    end
    return f + (target > f and maxStep or -maxStep)
end

-- The quaternion q = (x, y, z, w) turned by the factor f about its own axis (pure): f = 0 is the identity, f = 1 is q, f = 2 turns twice as far.
function HorseStirrup.scaledQuaternion(q, f)
    local x, y, z, w = q[1], q[2], q[3], q[4]
    if w < 0 then
        x, y, z, w = -x, -y, -z, -w
    end
    local s = math.sqrt(x * x + y * y + z * z)
    if s < 1e-9 or f == 0 then
        return 0, 0, 0, 1
    end
    local angle = 2 * math.atan2(s, w) * f
    local h = math.sin(angle / 2)
    return x / s * h, y / s * h, z / s * h, math.cos(angle / 2)
end

-- quaternions (x, y, z, w): product a * b, and the rotation of a vector (pure)
function HorseStirrup.mul(a, b)
    return {
        a[4] * b[1] + a[1] * b[4] + a[2] * b[3] - a[3] * b[2],
        a[4] * b[2] - a[1] * b[3] + a[2] * b[4] + a[3] * b[1],
        a[4] * b[3] + a[1] * b[2] - a[2] * b[1] + a[3] * b[4],
        a[4] * b[4] - a[1] * b[1] - a[2] * b[2] - a[3] * b[3],
    }
end
function HorseStirrup.rotate(q, v)
    local x, y, z, w = q[1], q[2], q[3], q[4]
    local cx, cy, cz = y * v[3] - z * v[2] + w * v[1], z * v[1] - x * v[3] + w * v[2], x * v[2] - y * v[1] + w * v[3]
    return { v[1] + 2 * (y * cz - z * cy), v[2] + 2 * (z * cx - x * cz), v[3] + 2 * (x * cy - y * cx) }
end
function HorseStirrup.axisAngle(axis, deg)
    local h = math.rad(deg) / 2
    local s = math.sin(h)
    return { axis[1] * s, axis[2] * s, axis[3] * s, math.cos(h) }
end

-- The bone's local rotation and translation (relative to its rest) for the factor f of the leading pose and a yaw (degrees, about the horse's vertical axis `up` in the bone's parent space, turning about the iron's own
-- centre c): u' = Rp Ry u + Rp (c - Ry c) + tp, u = a point relative to the pivot (pure).
function HorseStirrup.pose(pose, f, up, yawDeg)
    local px, py, pz, pw = HorseStirrup.scaledQuaternion(pose.q, f)
    local qp = { px, py, pz, pw }
    local qy = HorseStirrup.axisAngle(up, yawDeg)
    local q = HorseStirrup.mul(qp, qy)
    local c = pose.c or { 0, 0, 0 }
    local rc = HorseStirrup.rotate(qy, c)
    local d = HorseStirrup.rotate(qp, { c[1] - rc[1], c[2] - rc[2], c[3] - rc[3] })
    return q, { f * pose.t[1] + d[1], f * pose.t[2] + d[2], f * pose.t[3] + d[3] }
end

local function modelKey(vehicle)
    local file = vehicle.configFileName or ""
    if string.find(file, "horseAdult", 1, true) ~= nil then
        return "horseAdult"
    elseif string.find(file, "horseFoal", 1, true) ~= nil then
        return "horseFoal"
    end
    return nil
end

local function stateOf(vehicle)
    local st = HorseStirrup.state[vehicle]
    if st ~= nil then
        return st or nil
    end
    st = false
    local key = modelKey(vehicle)
    local poses = key ~= nil and HorseStirrup.POSES ~= nil and HorseStirrup.POSES[key] or nil
    if poses ~= nil and HorseRope ~= nil and HorseRope.findBone ~= nil and vehicle.rootNode ~= nil then
        local l = HorseRope.findBone(vehicle.rootNode, "stirrupJoint_L", 0)
        local r = HorseRope.findBone(vehicle.rootNode, "stirrupJoint_R", 0)
        if l ~= nil and r ~= nil then
            local rest, up = {}, {}
            for i, bone in ipairs({ l, r }) do
                local x, y, z = getTranslation(bone)
                rest[i] = { x, y, z }
                local ux, uy, uz = localDirectionToLocal(vehicle.rootNode, getParent(bone), 0, 1, 0)       -- the horse's vertical in the bone's parent space (a unit vector)
                local len = math.sqrt(ux * ux + uy * uy + uz * uz)
                up[i] = len > 1e-6 and { ux / len, uy / len, uz / len } or { 0, 1, 0 }
            end
            st = { bones = { l, r }, rest = rest, up = up, pose = { poses.L, poses.R }, f = 0 }
        end
    end
    HorseStirrup.state[vehicle] = st
    return st or nil
end

local function apply(st)
    local f = st.f * HorseStirrup.SCALE
    for i, bone in ipairs(st.bones) do
        if entityExists == nil or entityExists(bone) then
            local pose, rest = st.pose[i], st.rest[i]
            local q, t = HorseStirrup.pose(pose, f, st.up[i], (i == 1 and 1 or -1) * HorseStirrup.YAW * st.f)
            setQuaternion(bone, q[1], q[2], q[3], q[4])
            setTranslation(bone, rest[1] + t[1], rest[2] + t[2], rest[3] + t[3])
        end
    end
end

function HorseStirrup.update(dt)
    local system = g_currentMission ~= nil and g_currentMission.vehicleSystem or nil
    local vehicles = system ~= nil and system.vehicles or nil
    if vehicles == nil then
        return
    end
    for i = 1, #vehicles do
        local vehicle = vehicles[i]
        if vehicle.spec_rideable ~= nil then
            local st = stateOf(vehicle)
            if st ~= nil then
                local ridden = vehicle.getIsControlled ~= nil and vehicle:getIsControlled() or false
                local target = ridden and 1 or 0
                if st.f ~= target or (st.f > 0 and (st.appliedScale ~= HorseStirrup.SCALE or st.appliedYaw ~= HorseStirrup.YAW)) then
                    st.f = HorseStirrup.step(st.f, target, dt)
                    st.appliedScale, st.appliedYaw = HorseStirrup.SCALE, HorseStirrup.YAW
                    apply(st)
                end
            end
        end
    end
end

-- The yaw (degrees, 0 = along the horse's +z, positive towards +x) of the direction from p to c, both in the horse's model space (pure).
function HorseStirrup.yawOf(p, c)
    return math.deg(math.atan2(c[1] - p[1], c[3] - p[3]))
end

-- hdStirrup measure: while you ride, writes the rider's feet (ankle and the first child, the toe) and the stirrup bones in the horse's model space to the log: the data to work out the riding pose of the irons.
function HorseStirrup.measure()
    local system = g_currentMission ~= nil and g_currentMission.vehicleSystem or nil
    local lines = {}
    for _, vehicle in ipairs(system ~= nil and system.vehicles or {}) do
        if vehicle.spec_rideable ~= nil and vehicle.getIsControlled ~= nil and vehicle:getIsControlled() then
            local function toModel(node)
                local x, y, z = getWorldTranslation(node)
                local lx, ly, lz = worldToLocal(vehicle.rootNode, x, y, z)
                return { lx, ly, lz }
            end
            local character = vehicle.getVehicleCharacter ~= nil and vehicle:getVehicleCharacter() or nil
            local pm = character ~= nil and character.playerModel or nil
            for _, side in ipairs({ { "left", pm and pm.thirdPersonLeftFootNode }, { "right", pm and pm.thirdPersonRightFootNode } }) do
                local node = side[2]
                if node ~= nil and entityExists(node) then
                    local p = toModel(node)
                    local line = string.format("%s foot (%s): model %.3f %.3f %.3f", side[1], getName(node), p[1], p[2], p[3])
                    local parent = getParent(node)
                    if parent ~= nil and parent ~= 0 then
                        local a = toModel(parent)
                        line = line .. string.format(" | parent %s %.3f %.3f %.3f | ankle to toe: yaw %.1f deg (0 = forward, + towards +x), drop %.1f cm", getName(parent), a[1], a[2], a[3], HorseStirrup.yawOf(a, p), 100 * (a[2] - p[2]))
                    end
                    if getNumOfChildren(node) > 0 then
                        local child = getChildAt(node, 0)
                        local c = toModel(child)
                        line = line .. string.format(" | first child %s %.3f %.3f %.3f | toe direction yaw %.1f deg", getName(child), c[1], c[2], c[3], HorseStirrup.yawOf(p, c))
                    end
                    lines[#lines + 1] = line
                else
                    lines[#lines + 1] = side[1] .. " foot: no node"
                end
            end
            local st = HorseStirrup.state[vehicle]
            if st then
                for i, bone in ipairs(st.bones) do
                    local b = toModel(bone)
                    lines[#lines + 1] = string.format("stirrup bone %s: model %.3f %.3f %.3f", i == 1 and "L (+x)" or "R (-x)", b[1], b[2], b[3])
                end
            end
        end
    end
    if #lines == 0 then
        return "ride a horse first (hdStirrup measure needs a ridden horse with a rider)"
    end
    for _, line in ipairs(lines) do
        print("[HorseStirrup] measure: " .. line)
    end
    return table.concat(lines, " | ")
end

-- hdStirrup [factor] | hdStirrup yaw <degrees> | hdStirrup measure (the riding pose: factor 1 = the measured move under the feet, 0 = flat; yaw = the turn of the irons): how far the stirrups move to the leading pose while nobody rides (1 = the fitted pose, 0 = off, negative = the other way) and the extra turn of the irons about the vertical.
function HorseStirrup.console(_, a, b)
    if a == "measure" then
        return HorseStirrup.measure()
    elseif a == "yaw" then
        if tonumber(b) ~= nil then
            HorseStirrup.YAW = tonumber(b)
        end
    elseif tonumber(a) ~= nil then
        HorseStirrup.SCALE = tonumber(a)
    end
    return string.format("while somebody rides the stirrups move %.2f x the measured move under the feet and turn %.0f degrees about the vertical (hdStirrup <factor> | hdStirrup yaw <degrees> | hdStirrup measure)", HorseStirrup.SCALE, HorseStirrup.YAW)
end

if addConsoleCommand ~= nil then
    addConsoleCommand("hdStirrup", "HorseDynamics: the stirrups' leading pose while nobody rides, as a factor of the fitted move (1 = fitted, 0 = off)", "console", HorseStirrup)
end
