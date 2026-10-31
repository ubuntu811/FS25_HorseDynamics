--[[
    HorseRope.lua -- the leash as a real rope: a rope from the player (the leash in the hand, else the saddle or the player's chest) to the horse's head, drawn by the game's own winch rope (ForestryRope: a rope
    shape that the shader stretches to the distance between a link node and a target node, updated every frame; the forestry winch uses it for its rope). One rope per leashed horse.

    A ForestryRope is always straight, so the sag is made of SEGMENTS of them: the points between are plain transform nodes, put every frame on a hanging curve (a parabola: the slack makes the sag, capped, and
    kept above the ground). Segment k runs from point k-1 to point k; the first starts at the source node, the last is tied to the horse.

    The target is the horse's rein node (Rideable: leftReinNode, at the bridle; the game links the reins to it when the horse is ridden), else its leftReinParentNode, else the vehicle's root node.
]]
HorseRope = {}
HorseRope.FILENAME = "$data/shared/forestry/ropes.i3d"
HorseRope.ROPE_NODE = "4"   -- ropes.i3d shapes 0-4 are rope_300 ... rope_1; the game's vehicles use 4 most
HorseRope.DIAMETER = 0.015
HorseRope.UV_SCALE = 4
HorseRope.SEGMENTS = 6                  -- pieces per rope (SEGMENTS - 1 points between the two ends)
HorseRope.SAG_MAX_M = 0.35              -- the rope hangs at most this far below the straight line
HorseRope.SLACK_MIN_M = 0.15            -- the rope is this much longer than the distance, or SLACK_SHARE of it, whichever is more
HorseRope.SLACK_SHARE = 0.04
HorseRope.GROUND_CLEARANCE_M = 0.05     -- the points stay this far above the terrain

-- One piece of rope linked to linkNode, loading its shape asynchronously (rope.referenceFrame is set when it is there). nil when the engine pieces are missing.
local function createSegment(linkNode)
    local ok, rope = pcall(function()
        local r = ForestryRope.new(nil, linkNode)
        -- the engine does not know "$data": the game's own loader resolves the path first (ForestryRope:loadFromXML)
        r.i3dFilename, r.i3dRopePath = Utils.getFilename(HorseRope.FILENAME, nil), HorseRope.ROPE_NODE
        r.diameter, r.uvScale = HorseRope.DIAMETER, HorseRope.UV_SCALE
        r.emissiveColor, r.invalidEmissiveColor = { 0, 0, 0, 0 }, { 0, 0, 0, 0 }
        r.sharedLoadRequestId = g_i3DManager:loadSharedI3DFileAsync(r.i3dFilename, false, false, r.onI3DLoaded, r, r)
        return r
    end)
    if not ok then
        print("[HorseDynamics] leash rope: could not be created: " .. tostring(rope))
        return nil
    end
    return rope
end

-- A rope (a chain of segments) starting at sourceNode. nil when the engine pieces are missing.
function HorseRope.create(sourceNode, segments)
    if ForestryRope == nil or ForestryRope.new == nil or g_i3DManager == nil or Utils == nil or Utils.getFilename == nil or sourceNode == nil
        or createTransformGroup == nil or link == nil or getRootNode == nil then
        return nil
    end
    segments = segments or HorseRope.SEGMENTS
    local chain = { ropes = {}, mids = {}, tied = {}, segments = segments }
    local previous = sourceNode
    for i = 1, segments do
        local rope = createSegment(previous)
        if rope == nil then
            HorseRope.destroy(chain)
            return nil
        end
        chain.ropes[i] = rope
        if i < segments then
            local mid = createTransformGroup("horseLeashPoint")
            link(getRootNode(), mid)
            chain.mids[i] = mid
            previous = mid
        end
    end
    return chain
end

-- The node of the horse the rope is tied to.
function HorseRope.targetNodeOf(vehicle)
    local spec = vehicle ~= nil and vehicle.spec_rideable or nil
    if spec ~= nil then
        return spec.leftReinNode or spec.leftReinParentNode or vehicle.rootNode
    end
    return vehicle ~= nil and vehicle.rootNode or nil
end

-- The points between the ends, on the hanging curve from the source to the target (world coordinates: the points hang under the root node).
function HorseRope.place(chain, sourceNode, targetNode)
    local ax, ay, az = getWorldTranslation(sourceNode)
    local bx, by, bz = getWorldTranslation(targetNode)
    local dx, dy, dz = bx - ax, by - ay, bz - az
    local d = math.sqrt(dx * dx + dy * dy + dz * dz)
    local slack = math.max(HorseRope.SLACK_MIN_M, HorseRope.SLACK_SHARE * d)
    local sag = math.min(HorseRope.SAG_MAX_M, math.sqrt(3 * d * slack / 8))      -- (a parabola of span d and length d + slack)
    for i, mid in ipairs(chain.mids) do
        local t = i / chain.segments
        local x, y, z = ax + dx * t, ay + dy * t - sag * 4 * t * (1 - t), az + dz * t
        if getTerrainHeightAtWorldPos ~= nil and g_terrainNode ~= nil then
            y = math.max(y, getTerrainHeightAtWorldPos(g_terrainNode, x, 0, z) + HorseRope.GROUND_CLEARANCE_M)
        end
        setTranslation(mid, x, y, z)
    end
end

-- Called every frame for a leashed horse: makes the rope, ties each piece once its shape has loaded, hangs the points, shows or hides it. sourceNode nil: nothing to hang it from.
function HorseRope.sync(ride, sourceNode)
    if sourceNode == nil then
        HorseRope.hide(ride)
        return
    end
    if ride.rope == nil and not ride.ropeFailed then
        ride.rope = HorseRope.create(sourceNode, ride.segments)
        ride.ropeSource = sourceNode
        ride.ropeFailed = ride.rope == nil
    end
    local chain = ride.rope
    if chain == nil then
        return
    end
    if ride.ropeSource ~= sourceNode then
        pcall(chain.ropes[1].link, chain.ropes[1], sourceNode)
        ride.ropeSource = sourceNode
    end
    local target = ride.targetNode or HorseRope.targetNodeOf(ride.vehicle)
    if target == nil then
        return
    end
    local ok, err = pcall(HorseRope.place, chain, sourceNode, target)
    if not ok then
        print("[HorseDynamics] leash rope: could not hang the rope: " .. tostring(err))
    end
    for i, rope in ipairs(chain.ropes) do
        pcall(rope.setVisibility, rope, true)
        -- (tied only after its shape has loaded: the game's update would fail on a missing frame; the points are in place before that)
        if rope.referenceFrame ~= nil and not chain.tied[i] then
            local tied, tieError = pcall(rope.setTargetNode, rope, chain.mids[i] or target, true)
            if tied then
                chain.tied[i] = true
            else
                print("[HorseDynamics] leash rope: could not be tied: " .. tostring(tieError))
                HorseRope.remove(ride)
                ride.ropeFailed = true
                return
            end
        end
        if chain.tied[i] then
            pcall(rope.update, rope, 0)       -- (the points moved just now: the piece follows them this frame, not the next)
        end
    end
end

function HorseRope.hide(ride)
    for _, rope in ipairs(ride.rope ~= nil and ride.rope.ropes or {}) do
        pcall(rope.setVisibility, rope, false)
    end
end

function HorseRope.destroy(chain)
    for _, rope in ipairs(chain.ropes) do
        pcall(rope.delete, rope)
    end
    for _, mid in ipairs(chain.mids) do
        pcall(function()
            if entityExists == nil or entityExists(mid) then
                delete(mid)
            end
        end)
    end
end

-- The horse is not led any more: the rope goes.
function HorseRope.remove(ride)
    if ride.rope ~= nil then
        HorseRope.destroy(ride.rope)
    end
    ride.rope, ride.ropeSource = nil, nil
end

-- A node hanging from `parent` at (x, y, z) in its space, for the rope to start at when the leash tool is not in the hand (the saddle of the horse you ride, the player). One node, moved when the parent changes.
function HorseRope.anchorOn(parent, x, y, z)
    if parent == nil or createTransformGroup == nil or link == nil then
        return nil
    end
    local anchor = HorseRope.anchor
    local alive = anchor ~= nil and (entityExists == nil or entityExists(anchor.node))
    if alive and anchor.parent == parent then
        return anchor.node
    end
    if alive then
        pcall(delete, anchor.node)
    end
    local node = createTransformGroup("horseLeashAnchor")
    link(parent, node)
    setTranslation(node, x, y, z)
    HorseRope.anchor = { node = node, parent = parent }
    return node
end

-- The leash in the hand without a horse on it: a short end of rope hanging from the tool (the tool has no model of its own), STUB_M long, straight down. sourceNode nil: not held, hidden.
HorseRope.STUB_M = 0.2
function HorseRope.syncStub(sourceNode)
    local stub = HorseRope.stub
    if stub == nil then
        if sourceNode == nil or createTransformGroup == nil or link == nil or getRootNode == nil then
            return
        end
        stub = { segments = 1 }
        HorseRope.stub = stub
    end
    if sourceNode == nil then
        HorseRope.hide(stub)
        return
    end
    if stub.targetNode == nil or (entityExists ~= nil and not entityExists(stub.targetNode)) then
        stub.targetNode = createTransformGroup("horseLeashEnd")
        link(getRootNode(), stub.targetNode)
        HorseRope.remove(stub)
        stub.ropeFailed = nil
    end
    local x, y, z = getWorldTranslation(sourceNode)
    setTranslation(stub.targetNode, x, y - HorseRope.STUB_M, z)
    HorseRope.sync(stub, sourceNode)
end
