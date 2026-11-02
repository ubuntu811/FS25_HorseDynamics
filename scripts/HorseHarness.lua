--[[
    HorseHarness.lua -- a draught harness for a led horse, made of rope pieces like the halter: a collar with a ring on each side, a girth round the barrel with a padded saddle on the back and a ring each side
    (the tugs, where a cart's shafts will go), a loin strap over the back to the croup, hip straps down to the breeching rings and a breeching strap behind the buttocks, and a trace each side from the collar's
    ring through the tug to a free end that hangs behind the horse (the cart will take those). Put on and taken off with the harness tool (HorseLead.harness); a led horse has it while ride.harness is set.

    The numbers are in the horse model's own space (+z forward along the body, +y up, +x to the horse's left), measured from the mesh without the saddle (an OBJ export of the whole horse): the barrel at z 0.2
    is 0.9 to 1.62 high and 0.30 half wide, the rump ends at z -0.8, the neck crest at the collar is 1.9 high, ... Each point belongs to one bone (so it follows the horse's walk) and is turned into that bone's space
    with the bone's rest pose (HorseHarness.bones: the bone's position and its axes in the model's space, worked out from horse.i3d). Like the halter's, the points hang under the world root and are put at their bone's
    place every frame, then moved down by their slack along WORLD-down.
    Console: hdHarness info | set <path> <value> (for example set girth.z 0.25, set collar.a 0.4) | reset.
]]
HorseHarness = {}

HorseHarness.TRIES = 180

-- the rest pose of the bones the harness hangs on: t its position, x / y / z its axes, all in the model's space (from horse.i3d, Euler order z y x)
HorseHarness.bones = {
    Root_M = { t = { 0.0000, 1.5350, -0.4256 }, x = { 0.0000, -0.2682, 0.9634 }, y = { 0.0000, -0.9634, -0.2682 }, z = { 1.0000, 0.0000, 0.0000 } },
    RootPart1_M = { t = { 0.0000, 1.4668, -0.1806 }, x = { 0.0000, -0.2682, 0.9634 }, y = { 0.0000, -0.9634, -0.2682 }, z = { 1.0000, 0.0000, 0.0000 } },
    Spine1_M = { t = { 0.0000, 1.3986, 0.0644 }, x = { 0.0000, -0.9243, 0.3818 }, y = { 0.0000, -0.3818, -0.9243 }, z = { 1.0000, 0.0000, 0.0000 } },
    Chest_M = { t = { 0.0000, 1.4553, 0.5235 }, x = { 0.0000, -0.1193, 0.9929 }, y = { 0.0000, -0.9929, -0.1193 }, z = { 1.0000, 0.0000, 0.0000 } },
}

function HorseHarness.defaults()
    return {
        -- the collar: a snug loop lying on the shoulder, from the withers (y 1.76, z 0.62) down to the point of the chest (y 1.16, z 0.97), leaning back 30 degrees at the top, 0.21 half wide (the neck there is 0.15);
        -- the first version was a big hoop round the whole neck (0.42 x 0.26), too big and too high in the game; a ring each side where the traces start
        -- (measured on the horse model, wholehorse.obj, slices along z: the crest line (y at the midline) is 1.755 at z 0.50, 1.83 at 0.60, 1.87 at 0.65, 1.95 at 0.80, 2.06 at 0.95; the neck is 0.14 half wide at
        -- y 1.4 to 1.6 (z 0.8), the chest 0.22 at y 1.2 to 1.4. The loop's top lay at 1.76 inside the neck (clipped), then at 1.955 above it (a floating hoop). Now the tube's centre is on the crest, 3 cm above it
        -- (y 1.89 at z 0.64) and at the chest point (y 1.17 at z 0.99): centre (1.53, 0.815), leaning back 26 degrees, 0.40 half long; the tube 6.5 cm thick like a padded collar.
        -- Tune with hdHarness set collar.centre.2 / collar.a / collar.b / collar.diameter)
        collar = { bone = "Chest_M", centre = { 0, 1.53, 0.815 }, up = { 0, 0.90, -0.44 }, a = 0.40, b = 0.22, sides = 12, diameter = 0.065, ringRadius = 0.03, ringOut = 0.037, ringDiameter = 0.012 },
        -- the girth: round the barrel just behind the elbows (z 0.2), half profile (x, y) outside the body by 1 to 3 cm, from the belly up to the back; the tug ring is on point `tug`
        girth = { bone = "Spine1_M", z = 0.20, bottom = 0.87, top = 1.635, tug = 6, tugRadius = 0.02, tugOut = 0.012, diameter = 0.03, strap = 0.05,
            profile = { { 0.17, 0.90 }, { 0.235, 0.97 }, { 0.29, 1.07 }, { 0.322, 1.20 }, { 0.315, 1.32 }, { 0.29, 1.43 }, { 0.21, 1.52 }, { 0.12, 1.585 } } },
        -- the false martingale (the belly rope): from the bottom of the collar down between the front legs and along the underside to the girth's bottom, the strap that carries the pull (a picture of this
        -- harness drawn by another program had it): { bone, y, z } on the midline (the underside is at y 0.956 at z 0.8, 0.878 at z 0.4 and 0.2, the chest's front at z 0.93 at y 1.1)
        martingale = { diameter = 0.03, strap = 0.045, points = { { "Chest_M", 1.06, 0.93 }, { "Chest_M", 0.99, 0.86 }, { "Spine1_M", 0.945, 0.76 }, { "Spine1_M", 0.915, 0.62 }, { "Spine1_M", 0.89, 0.42 } } },
        -- the back band: a lighter loop round the barrel behind the girth (z -0.10: the flank is 0.34 half wide at y 1.3 there), half profile (x, y) from the belly up to the back
        backband = { bone = "RootPart1_M", z = -0.10, bottom = 0.94, top = 1.665, diameter = 0.02, strap = 0.035,
            profile = { { 0.19, 0.97 }, { 0.27, 1.05 }, { 0.335, 1.20 }, { 0.36, 1.32 }, { 0.31, 1.43 }, { 0.22, 1.52 }, { 0.12, 1.62 } } },
        -- the saddle pad: a thick short piece along the back on the girth
        pad = { bone = "Spine1_M", y = 1.655, z = { 0.10, 0.20, 0.30 }, diameter = 0.05 },
        -- the neck strap: from the top of the collar back along the withers to the front of the pad (a red line in a screenshot: the strap was missing there); just above the topline (1.72 at z 0.4, 1.765 at z 0.5)
        neck = { diameter = 0.02, strap = 0.03, points = { { "Chest_M", 1.77, 0.50 }, { "Chest_M", 1.725, 0.40 } } },
        -- the loin strap from the pad over the back to the croup (just above the topline, 1.68 at the croup): { bone, y, z }
        loin = { diameter = 0.016, strap = 0.03, points = { { "RootPart1_M", 1.665, -0.05 }, { "RootPart1_M", 1.675, -0.25 }, { "Root_M", 1.695, -0.42 }, { "Root_M", 1.695, -0.58 } } },
        -- the hip straps from the croup down each side to the breeching ring: { x, y, z } (the rump at z -0.6 is 0.11 half wide at y 1.65, 0.205 at 1.6, 0.25 at 1.5, 0.29 at 1.4)
        hip = { bone = "Root_M", diameter = 0.016, strap = 0.03, ringRadius = 0.022, ringOut = 0.01, ring = { 0.325, 1.27, -0.54 },
            points = { { 0.13, 1.68, -0.58 }, { 0.17, 1.63, -0.58 }, { 0.235, 1.57, -0.58 }, { 0.27, 1.50, -0.58 }, { 0.31, 1.40, -0.56 } } },
        -- the breeching behind the buttocks (the rump ends at z -0.78 at x 0.15), from each ring to the middle: { x, y, z }, sagging by `slack` at the middle
        breeching = { bone = "Root_M", diameter = 0.022, strap = 0.045, slack = 0.03, points = { { 0.30, 1.26, -0.64 }, { 0.255, 1.25, -0.73 }, { 0.195, 1.245, -0.80 }, { 0.12, 1.24, -0.84 }, { 0, 1.235, -0.85 } } },
        -- the traces: from the collar's ring along the shoulder and the flank through the tug ring and on behind the horse, to the hook: { bone, x, y, z, weight }
        trace = { diameter = 0.02, strap = 0.04, slack = 0.30,
            before = { { "Chest_M", 0.30, 1.48, 0.62 }, { "Chest_M", 0.285, 1.45, 0.41 } },
            after = { { "RootPart1_M", 0.33, 1.38, -0.15, 0 }, { "Root_M", 0.37, 1.28, -0.72, 0.3 } } },
        -- the hitch hook: ONE fixed steel ring behind the rump, rigid on the hip bone (no slack), where both traces end; a trailer's drawbar eye is pinned to its middle (HorseHitch). In the vertical plane along the
        -- horse, `radius` 6 cm, at the height of a trailer's hitch (the Wooden Trailer's is 0.87 above the ground), 20 cm behind the breeching (the rump ends at z -0.8)
        hook = { bone = "Root_M", at = { 0, 1.08, -1.06 }, radius = 0.06, diameter = 0.014 },
    }
end
HorseHarness.spec = HorseHarness.defaults()

-- Model space -> a bone's space.
function HorseHarness.toLocal(boneName, x, y, z)
    local b = HorseHarness.bones[boneName]
    local dx, dy, dz = x - b.t[1], y - b.t[2], z - b.t[3]
    return b.x[1] * dx + b.x[2] * dy + b.x[3] * dz, b.y[1] * dx + b.y[2] * dy + b.y[3] * dz, b.z[1] * dx + b.z[2] * dy + b.z[3] * dz
end

-- A direction in the model's space -> a bone's space (the rotation only).
function HorseHarness.toLocalDirection(boneName, x, y, z)
    local b = HorseHarness.bones[boneName]
    return b.x[1] * x + b.x[2] * y + b.x[3] * z, b.y[1] * x + b.y[2] * y + b.y[3] * z, b.z[1] * x + b.z[2] * y + b.z[3] * z
end

-- The skin's normal at the middle (x, y, z) of a strap, in the model's space: out from the body's axis (a line along z at height 1.30) for the barrel, the back, the flank, the belly; out from the rump's
-- centre (0, 1.25, -0.55) in the x-z plane for the breeching behind the buttocks.
function HorseHarness.bodyNormal(x, y, z)
    local dy = y - 1.30
    local length = math.sqrt(x * x + dy * dy)
    if length < 1e-6 then
        return 0, 1, 0
    end
    return x / length, dy / length, 0
end
function HorseHarness.rumpNormal(x, y, z)
    local dz = z + 0.55
    local length = math.sqrt(x * x + dz * dz)
    if length < 1e-6 then
        return 0, 0, -1
    end
    return x / length, 0, dz / length
end

-- Builds the harness on a horse vehicle: points (under the world root), the pieces between them. Returns the rig or nil (a bone is missing: the horse model is not complete yet, or it is not a horse).
function HorseHarness.build(vehicle, gear)
    if HorseRope == nil or HorseRope.createSegment == nil or HorseRope.findBone == nil or createTransformGroup == nil or link == nil or getRootNode == nil or vehicle == nil or vehicle.rootNode == nil then
        return nil
    end
    local bones = {}
    for name in pairs(HorseHarness.bones) do
        local ok, node = pcall(HorseRope.findBone, vehicle.rootNode, name, 0)
        if not ok or node == nil then
            return nil
        end
        bones[name] = node
    end
    local s = HorseHarness.spec
    local rig = { nodes = {}, bone = {}, locals = {}, slack = {}, pieces = {}, targets = {}, tied = {}, bones = bones, frames = 0, model = {} }
    local function point(boneName, x, y, z, slack)
        local node = createTransformGroup("horseHarnessPoint")
        link(getRootNode(), node)
        local n = #rig.nodes + 1
        rig.model[node] = { x, y, z, boneName }
        rig.nodes[n] = node
        rig.bone[n] = bones[boneName]
        local lx, ly, lz = HorseHarness.toLocal(boneName, x, y, z)
        rig.locals[n] = { lx, ly, lz }
        rig.slack[n] = slack or 0
        return node
    end
    -- strapWidth: the piece is a flat leather strap of that width (when the gear is leather), its flat face to the skin: normalFn(x, y, z) gives the skin's normal at its middle in the model's space
    local function piece(from, to, diameter, steel, strapWidth, normalFn)
        local options = nil
        if not steel then
            local a, b = rig.model[from], rig.model[to]
            local bone = bones[a[4]]
            if strapWidth ~= nil then
                local nx, ny, nz = (normalFn or HorseHarness.bodyNormal)((a[1] + b[1]) / 2, (a[2] + b[2]) / 2, (a[3] + b[3]) / 2)
                local lx, ly, lz = HorseHarness.toLocalDirection(a[4], nx, ny, nz)
                options = HorseRope.gearOptions(strapWidth, bone, lx, ly, lz, gear)
            else
                options = HorseRope.gearOptions(nil, nil, nil, nil, nil, gear)
            end
        end
        local rope = HorseRope.createSegment(from, diameter, options)
        if rope ~= nil then
            rope.rfMaterialDone = steel or nil                   -- (the hemp is put on a piece whose shape has loaded, unless it is a ring)
            rig.pieces[#rig.pieces + 1] = rope
            rig.targets[#rig.pieces] = to
        end
    end
    local function chain(nodes, diameter, strapWidth, normalFn)
        for i = 1, #nodes - 1 do
            piece(nodes[i], nodes[i + 1], diameter, nil, strapWidth, normalFn)
        end
    end
    -- A ring: a small vertical hexagon of steel in the y-z plane (its normal sideways), round (x, y, z); near(ty, tz) is its point nearest to the direction towards (ty, tz).
    local function ringAt(boneName, x, y, z, radius, slack, diameter)
        local ring, sides = { nodes = {} }, 6
        local scale = 1 / math.cos(math.pi / sides)
        for k = 0, sides - 1 do
            local angle = 2 * math.pi * k / sides
            ring.nodes[#ring.nodes + 1] = point(boneName, x, y + radius * scale * math.cos(angle), z + radius * scale * math.sin(angle), slack)
        end
        ring.near = function(ty, tz)
            return ring.nodes[(math.floor(math.atan2(tz - z, ty - y) / (2 * math.pi / sides) + 0.5) % sides) + 1]
        end
        ring.close = function()
            for k = 1, sides do
                piece(ring.nodes[k], ring.nodes[k % sides + 1], diameter, true)
            end
        end
        return ring
    end
    -- A closed loop through points { x, y, z, slack } with rings at some of them (rings[index] = ring): the loop's pieces next to a ring end on the ring's nearest points.
    local function loop(boneName, pts, rings, diameter, strapWidth, normalFn)
        local nodes = {}
        for i, p in ipairs(pts) do
            if rings[i] == nil then
                nodes[i] = point(boneName, p[1], p[2], p[3], p[4])
            end
        end
        for i = 1, #pts do
            local nextI = i % #pts + 1
            local from, to = nodes[i], nodes[nextI]
            if rings[nextI] ~= nil then
                to = rings[nextI].near(pts[i][2], pts[i][3])
            end
            if rings[i] ~= nil then
                from = rings[i].near(pts[nextI][2], pts[nextI][3])
            end
            piece(from, to, diameter, nil, strapWidth, normalFn)
        end
        return nodes
    end

    -- the collar
    local c = s.collar
    local ul = math.sqrt(c.up[1] ^ 2 + c.up[2] ^ 2 + c.up[3] ^ 2)
    local ux, uy, uz = c.up[1] / ul, c.up[2] / ul, c.up[3] / ul
    local scale = 1 / math.cos(math.pi / c.sides)
    local collarPts, collarRings, collarRingAt = {}, {}, {}
    for k = 0, c.sides - 1 do
        local angle = 2 * math.pi * k / c.sides
        local up, side = c.a * scale * math.cos(angle), c.b * scale * math.sin(angle)
        collarPts[k + 1] = { c.centre[1] + side, c.centre[2] + up * uy, c.centre[3] + up * uz }
    end
    for _, sign in ipairs({ 1, -1 }) do
        local index = sign > 0 and c.sides / 4 + 1 or c.sides * 3 / 4 + 1
        local p = collarPts[index]
        collarRings[index] = ringAt(c.bone, p[1] + sign * c.ringOut, p[2], p[3], c.ringRadius, 0, c.ringDiameter)
        collarRingAt[sign] = collarRings[index]
    end
    local collarNodes = loop(c.bone, collarPts, collarRings, c.diameter)
    for _, sign in ipairs({ 1, -1 }) do
        collarRingAt[sign].close()
    end

    -- the girth: bottom, the right profile up, top, the left profile down; the tug rings on the profile's point `tug`
    local g = s.girth
    local girthPts, girthRings, tugAt = { { 0, g.bottom, g.z } }, {}, {}
    for _, p in ipairs(g.profile) do
        girthPts[#girthPts + 1] = { p[1], p[2], g.z }
    end
    girthPts[#girthPts + 1] = { 0, g.top, g.z }
    for i = #g.profile, 1, -1 do
        girthPts[#girthPts + 1] = { -g.profile[i][1], g.profile[i][2], g.z }
    end
    local rightIndex, leftIndex = 1 + g.tug, #girthPts - g.tug + 1
    for _, sign in ipairs({ 1, -1 }) do
        local index = sign > 0 and rightIndex or leftIndex
        local p = girthPts[index]
        girthRings[index] = ringAt(g.bone, p[1] + sign * g.tugOut, p[2], p[3], g.tugRadius, 0, 0.01)
        tugAt[sign] = girthRings[index]
    end
    local girthNodes = loop(g.bone, girthPts, girthRings, g.diameter, g.strap)
    for _, sign in ipairs({ 1, -1 }) do
        tugAt[sign].close()
    end

    -- the false martingale: from the collar's bottom point along the underside to the girth's bottom point
    local mg = s.martingale
    local mgNodes = { collarNodes[c.sides / 2 + 1] }
    for _, p in ipairs(mg.points) do
        mgNodes[#mgNodes + 1] = point(p[1], 0, p[2], p[3])
    end
    mgNodes[#mgNodes + 1] = girthNodes[1]
    chain(mgNodes, mg.diameter, mg.strap)

    -- the back band: a second, lighter loop round the barrel
    local bb = s.backband
    local bbPts = { { 0, bb.bottom, bb.z } }
    for _, p in ipairs(bb.profile) do
        bbPts[#bbPts + 1] = { p[1], p[2], bb.z }
    end
    bbPts[#bbPts + 1] = { 0, bb.top, bb.z }
    for i = #bb.profile, 1, -1 do
        bbPts[#bbPts + 1] = { -bb.profile[i][1], bb.profile[i][2], bb.z }
    end
    loop(bb.bone, bbPts, {}, bb.diameter, bb.strap)

    -- the pad on the back, and the loin strap from its rear end to the croup
    local pd = s.pad
    local padNodes = {}
    for i, z in ipairs(pd.z) do
        padNodes[i] = point(pd.bone, 0, pd.y, z)
    end
    chain(padNodes, pd.diameter)
    -- the neck strap: from the collar's top point back along the withers to the pad's front end
    local nk = s.neck
    local neckNodes = { collarNodes[1] }
    for _, p in ipairs(nk.points) do
        neckNodes[#neckNodes + 1] = point(p[1], 0, p[2], p[3])
    end
    neckNodes[#neckNodes + 1] = padNodes[#padNodes]
    chain(neckNodes, nk.diameter, nk.strap)
    local loinNodes = { padNodes[1] }
    for _, p in ipairs(s.loin.points) do
        loinNodes[#loinNodes + 1] = point(p[1], 0, p[2], p[3])
    end
    chain(loinNodes, s.loin.diameter, s.loin.strap)
    local croup = loinNodes[#loinNodes]

    -- the hip straps from the croup to the breeching rings, and the breeching behind the buttocks from ring to ring
    local h, b = s.hip, s.breeching
    local sideRingAt, arcs = {}, {}
    local middle = nil
    for _, sign in ipairs({ 1, -1 }) do
        local ring = ringAt(h.bone, sign * (h.ring[1] + h.ringOut), h.ring[2], h.ring[3], h.ringRadius, 0, 0.01)
        sideRingAt[sign] = ring
        ring.close()
        local nodes = { croup }
        for _, p in ipairs(h.points) do
            nodes[#nodes + 1] = point(h.bone, sign * p[1], p[2], p[3])
        end
        local last = h.points[#h.points]
        nodes[#nodes + 1] = ring.near(last[2], last[3])                          -- (the strap comes from above)
        chain(nodes, h.diameter, h.strap)
        local arc = { ring.near(b.points[1][2], b.points[1][3]) }                 -- (the breeching leaves the ring backwards)
        for i, p in ipairs(b.points) do
            if i == #b.points then
                middle = middle or point(b.bone, 0, p[2], p[3], b.slack)
                arc[#arc + 1] = middle
            else
                arc[#arc + 1] = point(b.bone, sign * p[1], p[2], p[3], b.slack * (i / (#b.points - 1)))
            end
        end
        chain(arc, b.diameter, b.strap, HorseHarness.rumpNormal)
    end

    -- the traces: collar ring, two points along the shoulder, the tug ring, three points behind (the last hangs free)
    local t = s.trace
    local hk = s.hook
    rig.hookFrom = #rig.nodes + 1
    local hookRing = ringAt(hk.bone, hk.at[1], hk.at[2], hk.at[3], hk.radius, 0, hk.diameter)
    hookRing.close()
    rig.hookNode = point(hk.bone, hk.at[1], hk.at[2], hk.at[3], 0)                       -- (the middle of the ring, rigid on the bone: HorseHitch pins the drawbar eye here)
    rig.hookTo = #rig.nodes                                                              -- (the ring's points and its middle are nodes hookFrom to hookTo: they go down together, hookDrop)
    rig.hookDrop, rig.hookDropTarget = 0, 0
    rig.hookRear = hookRing.near(hk.at[2], hk.at[3] - 1)                                 -- (the ring's point furthest behind: a tow bar starts there)
    for _, sign in ipairs({ 1, -1 }) do
        local nodes = {}
        local first = t.before[1]
        nodes[1] = collarRingAt[sign].near(first[3], first[4])
        for _, p in ipairs(t.before) do
            nodes[#nodes + 1] = point(p[1], sign * p[2], p[3], p[4])
        end
        local after = t.after[1]
        nodes[#nodes + 1] = tugAt[sign].near(after[3], after[4])
        chain(nodes, t.diameter, t.strap)
        local tail = { tugAt[sign].near(after[3], after[4]) }
        for _, p in ipairs(t.after) do
            tail[#tail + 1] = point(p[1], sign * p[2], p[3], p[4], t.slack * (p[5] or 0))
        end
        local last = t.after[#t.after]
        tail[#tail + 1] = hookRing.near(last[3], last[4])           -- (both traces end on the same point of the hook ring: a V that meets at the hook)
        chain(tail, t.diameter, t.strap)
    end
    HorseHarness.place(rig)
    return rig
end

-- Every point at its bone's place (world coordinates, the points hang under the world root), then down by its slack.
-- rig.hookFollow: a node (a drawbar's eye) the hook ring rides on, EXACTLY: the whole ring moves by the way from where it would be (rigid on the hip bone) to that node, so the traces end on the eye whatever the
-- wagon does (a hitched wagon trails the hook by a little that grows with the gait; the ring stays on the eye). rig.hookBlend eases it in when it is set and out when it is cleared (the offset of the last
-- frame is kept for that).
HorseHarness.FOLLOW_EASE = 0.25
function HorseHarness.place(rig)
    -- the hook ring is let down to where a joint holds a drawbar eye (hookDropTarget), a little each frame, and back up when it lets go
    local drop = rig.hookDrop or 0
    if rig.hookDropTarget ~= nil and math.abs(rig.hookDropTarget - drop) > 0.002 then
        drop = drop + (rig.hookDropTarget - drop) * 0.15
        rig.hookDrop = drop
    end
    local blend = rig.hookBlend or 0
    local blendTarget = rig.hookFollow ~= nil and 1 or 0
    if blend ~= blendTarget then
        blend = blend + (blendTarget - blend) * HorseHarness.FOLLOW_EASE
        if math.abs(blendTarget - blend) < 0.005 then
            blend = blendTarget
        end
        rig.hookBlend = blend
    end
    if rig.hookFollow ~= nil and rig.hookTo ~= nil and (entityExists == nil or entityExists(rig.hookFollow)) then
        local bone = rig.bone[rig.hookTo]
        if bone ~= nil and (entityExists == nil or entityExists(bone)) then
            local l = rig.locals[rig.hookTo]
            local hx, hy, hz = localToWorld(bone, l[1], l[2], l[3])
            local ex, ey, ez = getWorldTranslation(rig.hookFollow)
            rig.hookOffset = { ex - hx, ey - hy, ez - hz }
        end
    end
    local offset = blend > 0 and rig.hookOffset or nil
    for i, node in ipairs(rig.nodes) do
        local bone = rig.bone[i]
        if bone ~= nil and (entityExists == nil or entityExists(bone)) then
            local l = rig.locals[i]
            local x, y, z = localToWorld(bone, l[1], l[2], l[3])
            local inRing = rig.hookFrom ~= nil and i >= rig.hookFrom and i <= rig.hookTo
            local down = inRing and drop * (1 - blend) or 0
            if inRing and offset ~= nil then
                x, y, z = x + offset[1] * blend, y + offset[2] * blend, z + offset[3] * blend
            end
            setTranslation(node, x, y - (rig.slack[i] or 0) - down, z)
        end
    end
end

function HorseHarness.destroy(ride)
    if HorseHitch ~= nil then
        HorseHitch.release(ride)                                 -- (a trailer on the harness is let go with it)
    end
    local rig = ride.rig
    if rig ~= nil then
        for _, rope in ipairs(rig.pieces) do
            pcall(rope.delete, rope)
        end
        for _, node in ipairs(rig.nodes) do
            pcall(function()
                if entityExists == nil or entityExists(node) then
                    delete(node)
                end
            end)
        end
    end
    ride.rig, ride.rigTries, ride.rigFailed = nil, nil, nil
end

-- Every frame for a led horse: the harness is built when ride.harness is set (tried for a few seconds while the horse's bones are not there yet), kept in place, shown; taken off when it is not set.
function HorseHarness.sync(ride)
    if not ride.harness then
        if ride.rig ~= nil then
            HorseHarness.destroy(ride)
        end
        return
    end
    if ride.rig == nil and not ride.rigFailed then
        ride.rig = HorseHarness.build(ride.vehicle, ride.harnessGear)
        if ride.rig == nil then
            ride.rigTries = (ride.rigTries or 0) + 1
            if ride.rigTries >= HorseHarness.TRIES then
                ride.rigFailed = true
                print("[HorseDynamics] harness: could not be built (a bone of the horse is missing, or no rope), tried for about three seconds")
            end
        end
    end
    local rig = ride.rig
    if rig == nil then
        return
    end
    rig.frames = rig.frames + 1
    if rig.frames == HorseRope.HALTER_REPORT_FRAMES then
        local loaded, tied = 0, 0
        for i, rope in ipairs(rig.pieces) do
            loaded = loaded + (rope.referenceFrame ~= nil and 1 or 0)
            tied = tied + (rig.tied[i] and 1 or 0)
        end
        print(string.format("[HorseDynamics] harness: %d pieces, %d loaded, %d tied, %d points", #rig.pieces, loaded, tied, #rig.nodes))
    end
    pcall(HorseHarness.place, rig)
    for i, rope in ipairs(rig.pieces) do
        HorseRope.applyMaterial(rope)
        HorseRope.setShown(rope, true)
        if rig.tied[i] then
            pcall(rope.update, rope, 0)               -- (the points moved just now: the piece follows them this frame)
        end
        if rope.referenceFrame ~= nil and not rig.tied[i] then
            local tied, tieError = pcall(rope.setTargetNode, rope, rig.targets[i], true)
            rig.tied[i] = tied or nil
            if not tied and not ride.rigTieReported then
                ride.rigTieReported = true
                print("[HorseDynamics] harness: a piece could not be tied: " .. tostring(tieError))
            end
        end
    end
end

-- Console: hdHarness info | set <path> <value> | reset  (the path walks the spec: collar.a, girth.profile.3.1 ...)
function HorseHarness:command(argument, path, value)
    if argument == "reset" then
        HorseHarness.spec = HorseHarness.defaults()
        HorseHarness.rebuildAll()
        return "the harness measurements are the defaults again"
    elseif argument == "set" then
        local number = tonumber(value)
        if path == nil or number == nil then
            return "usage: hdHarness set <path> <number> (for example collar.a 0.4, girth.z 0.25, girth.profile.3.1 0.3, hip.ring.1 0.33)"
        end
        local node, key = HorseHarness.spec, nil
        local parts = {}
        for part in string.gmatch(path, "[^%.]+") do
            parts[#parts + 1] = tonumber(part) or part
        end
        for i = 1, #parts - 1 do
            node = type(node) == "table" and node[parts[i]] or nil
        end
        key = parts[#parts]
        if type(node) ~= "table" or type(node[key]) ~= "number" then
            return "no such number in the harness: " .. tostring(path)
        end
        node[key] = number
        HorseHarness.rebuildAll()
        return string.format("%s is %s", path, tostring(number))
    end
    local lines = {}
    local function walk(prefix, node)
        local keys = {}
        for k in pairs(node) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        for _, k in ipairs(keys) do
            local v = node[k]
            if type(v) == "table" then
                walk(prefix .. tostring(k) .. ".", v)
            else
                lines[#lines + 1] = prefix .. tostring(k) .. " = " .. tostring(v)
            end
        end
    end
    walk("", HorseHarness.spec)
    return "usage: hdHarness info | set <path> <number> | reset\n" .. table.concat(lines, "\n")
end

-- The harnesses are rebuilt on the next frame (after a measurement changed).
function HorseHarness.rebuildAll()
    if HorseLead ~= nil then
        for _, ride in ipairs(HorseLead.rides) do
            HorseHarness.destroy(ride)
        end
    end
end

if addConsoleCommand ~= nil then
    addConsoleCommand("hdHarness", "HorseDynamics: the draught harness (info | set <path> <number> | reset)", "command", HorseHarness)
end
