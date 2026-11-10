--[[
    HorseTie.lua -- the hitching post (placeables/hitchingPost): two posts, a rail and two rings. A horse on the leash is tied to a ring with the leash tool (look at the ring, click); the horse then stands where it
    is, the rope runs from the ring to its halter. The same click on that ring unties it: it follows again. A tied horse is a ride with ride.tied = { node, placeable }, ride.stay = true (the existing "stands where it is"),
    no ride.leash (so the leash's let-go and the carrot's let-go do not touch it) and its rope drawn from the ring (HorseLead.updateRide).
    The rings are the nodes tie1 / tie2 of the post's i3d, found on the placed placeables by their xml name (mod globals are invisible between mods, so nothing is registered anywhere: a click looks the placeables up).
]]
HorseTie = {}

HorseTie.XML_NAME = "hitchingpost.xml"
HorseTie.NODE_NAMES = { "tie1", "tie2" }
HorseTie.REACH_M = 4.5          -- the player must stand within this of the ring
HorseTie.LOOK_RADIUS_M = 0.6    -- the view ray may miss the ring by this
HorseTie.HORSE_REACH_M = 14     -- a leashed horse this close is tied: it walks to the post by itself
HorseTie.STAND_M = 2.8          -- it stops this far from the ring (root distance: the nose is then about 1.6 m from it, the rope of about 3 m hangs slack)

local function say(format, ...)
    print(string.format("[HorseDynamics] tie: " .. format, ...))
end

-- the node called `name` anywhere under `node` (the rings are two levels down)
local function findNamed(node, name, depth)
    if getName(node) == name then
        return node
    end
    if depth > 4 then
        return nil
    end
    for i = 0, getNumOfChildren(node) - 1 do
        local found = findNamed(getChildAt(node, i), name, depth + 1)
        if found ~= nil then
            return found
        end
    end
    return nil
end

-- Every ring of every placed hitching post: { node, placeable, index }. (A handful of placeables to scan, only on a click.)
function HorseTie.rings()
    local list = {}
    local system = g_currentMission ~= nil and g_currentMission.placeableSystem or nil
    for _, placeable in ipairs(system ~= nil and system.placeables or {}) do
        local name = placeable.configFileName
        if name ~= nil and string.find(string.lower(name), HorseTie.XML_NAME, 1, true) ~= nil and placeable.rootNode ~= nil
            and (entityExists == nil or entityExists(placeable.rootNode)) then
            for index, nodeName in ipairs(HorseTie.NODE_NAMES) do
                local ok, node = pcall(findNamed, placeable.rootNode, nodeName, 0)
                if ok and node ~= nil then
                    list[#list + 1] = { node = node, placeable = placeable, index = index }
                end
            end
        end
    end
    return list
end

-- The ring the player looks at (within reach), or nil. Without a camera ray: the nearest ring.
function HorseTie.looked(px, pz)
    local ray = HorseLead.viewRay()
    local best, bestScore = nil, math.huge
    for _, ring in ipairs(HorseTie.rings()) do
        local x, y, z = getWorldTranslation(ring.node)
        local dx, dz = x - px, z - pz
        local flat = math.sqrt(dx * dx + dz * dz)
        if flat <= HorseTie.REACH_M then
            local score = flat
            if ray ~= nil then
                local vx, vy, vz = x - ray[1], y - ray[2], z - ray[3]
                local t = vx * ray[4] + vy * ray[5] + vz * ray[6]
                local qx, qy, qz = vx - ray[4] * t, vy - ray[5] * t, vz - ray[6] * t
                local miss = math.sqrt(qx * qx + qy * qy + qz * qz)
                score = (t >= 0 and miss <= HorseTie.LOOK_RADIUS_M) and (t + 3 * miss) or math.huge
            end
            if score < bestScore then
                best, bestScore = ring, score
            end
        end
    end
    return best
end

-- The ride tied to this ring node, if any.
function HorseTie.tiedAt(node)
    for _, ride in ipairs(HorseLead.rides) do
        if ride.tied ~= nil and ride.tied.node == node and ride.vehicle ~= nil then
            return ride
        end
    end
    return nil
end

-- The horse that goes to the ring: the leashed one the player looks at, else the leashed one nearest to the ring.
function HorseTie.leashedRide(ring, px, pz)
    local looked = HorseLead.pickRide(px, pz, HorseLead.LEASH_REACH_M * 2, function(r) return r.leash end)
    if looked ~= nil then
        return looked
    end
    local rx, _, rz = getWorldTranslation(ring.node)
    local best, bestD = nil, math.huge
    for _, ride in ipairs(HorseLead.rides) do
        if ride.leash and ride.vehicle ~= nil and ride.vehicle.rootNode ~= nil then
            local x, _, z = getWorldTranslation(ride.vehicle.rootNode)
            local d = math.sqrt((x - rx) ^ 2 + (z - rz) ^ 2)
            if d < bestD then
                best, bestD = ride, d
            end
        end
    end
    return best
end

-- A click of the leash while looking at a ring. Returns a message, or nil when no ring is looked at (the leash does what it always did).
function HorseTie.click(gear)
    if HorseLead == nil or HorseLead.playerPosition == nil then
        return nil
    end
    local px, _, pz = HorseLead.playerPosition()
    if px == nil then
        return nil
    end
    local ring = HorseTie.looked(px, pz)
    if ring == nil then
        return nil
    end
    local holder = HorseTie.tiedAt(ring.node)
    if holder ~= nil then
        holder.tied, holder.stay, holder.leash = nil, nil, true      -- (it follows the player again)
        holder.halterGear = holder.halter ~= nil and holder.halterGear or gear
        say("untied from ring %d", ring.index)
        return "untied: the horse follows you again"
    end
    local ride = HorseTie.leashedRide(ring, px, pz)
    if ride == nil then
        return "this ring is for a horse on the leash: leash one and lead it here"
    end
    local rx, ry, rz = getWorldTranslation(ring.node)
    local hx, _, hz = getWorldTranslation(ride.vehicle.rootNode)
    local d = math.sqrt((hx - rx) ^ 2 + (hz - rz) ^ 2)
    if d > HorseTie.HORSE_REACH_M then
        return string.format("the horse is %.0f m from the ring: lead it closer", d)
    end
    ride.leash, ride.carrot, ride.halterOn, ride.towRope = nil, nil, nil, nil
    ride.stay = nil
    ride.tied = { node = ring.node, placeable = ring.placeable }
    ride.halterGear = ride.halter ~= nil and ride.halterGear or gear
    say("a horse tied to ring %d (%.1f m away): it walks up to the post", ring.index, d)
    return "tied: the horse walks to the hitching post and stands there (click the ring again to untie it)"
end

-- The rope's start for a tied ride: its ring node, or nil when the ring is gone (the post was sold: the horse is let go of the post, it stands there with its halter on).
function HorseTie.sourceOf(ride)
    local tied = ride.tied
    if tied == nil then
        return nil
    end
    if tied.node == nil or (entityExists ~= nil and not entityExists(tied.node)) then
        ride.tied, ride.halterOn, ride.stay = nil, true, true
        say("the post is gone: the horse is let go of it")
        return nil
    end
    return tied.node
end
