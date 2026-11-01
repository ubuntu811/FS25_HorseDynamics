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
HorseRope.LENGTH_M = 3.0                -- a rope is as long as it is: slack (and with it the sag) is what is left of this over the distance, none when the horse is at the end of it
HorseRope.GROUND_CLEARANCE_M = 0.05     -- the points stay this far above the terrain
-- How a led horse is held (console: hdLead style tack|reins|rope):
--   "tack"  = the horse shows its saddle, bridle and reins (the reins at rest, as the game puts them when nobody holds them) and the winch rope below runs from the hand to the bridle's bit ring.
--   "reins" = the game's own reins linked to the leash in the hand, as they are to a rider's hands (the skinned reins mesh stretches into long angular shapes beyond about a metre: seen in the game).
--   "rope"  = the winch rope to the horse's rein node, on the bare horse (the rein node sits on the body, not at the head).
--   "halter" = a rope halter made of rope pieces on the head bone (noseband, crown, cheek pieces, a knot under the chin) on the bare horse, the lead tied to the knot.
HorseRope.style = "halter"
-- The rope halter, in the space of the head bone (+y forward along the face, +x up, z sideways; the nose tip is at y = 0.575). Measured from the horse mesh (an OBJ export of the whole horse): at y = 0.35 the muzzle
-- is x -0.18 to 0.09 (centre -0.046, half height 0.134) and 0.099 wide on each side; at y = 0.17, behind the jaw, centre -0.057, half height 0.166, half width 0.135. A loop is a polygon of `sides` pieces, scaled
-- so that its chords, not only its corners, stay outside the head, plus `margin`. Console: hdLead halter nose|crown y centre vertical lateral.
-- The noseband is a loop (an ellipse fits a muzzle). The CROWN is not: the head is not an ellipse (the measurement that showed it: the jowl, x -0.20 .. -0.14, is 0.15 to 0.17 m half wide at y -0.04 .. 0.08 while
-- the head behind the ears is 0.06 to 0.11 and the face 0.10 to 0.13: an elliptic crown ran 5 cm inside the jaw), so the crown is an explicit path, as a real halter's is (a reference photo of a halter:
-- the cheek strap, the strap to the ear and the strap down under the jaw meet at ONE ring at the cheekbone): from the top of the head behind the ears (T) down each side to the cheek ring (J, index `joint`),
-- on past the jowl and under the throat (U). Points are { x, y, z, weight } for the side z > 0 (mirrored for z < 0), in the head bone's space, each 0.005 to 0.015 outside the measured surface (width by height
-- and length, the table in tests/horsedynamics_test.lua); weight 0 at the top to 1 at the bottom: the share of the slack. The cheek strap runs from the noseband's side point through `cheek` to the cheek ring.
-- Gravity: the top of a loop rests on the skin, below the head the rope hangs slack: every point is moved by `slack` * weight metres along WORLD-down (turned into the head bone's space every frame).
HorseRope.halter = {
    nose = { y = 0.43, centre = -0.043, vertical = 0.119, lateral = 0.085, slack = 0.012, bend = 0.14, widen = 0.31, deepen = 0.2, ringAngle = 120 },     -- bend: how far the side points (the rings) are pulled back along the face, so that top, ring and jaw make an angle as a real halter's noseband does in side view (a photo); widen: the head is that much wider (m per m) further back
    crown = {
        top = { 0.072, -0.035, 0, 0 },                  -- T, on the skull just behind the ears (the top of the head is 0.059 .. 0.068 high there)
        sides = {
            { 0.068, -0.015, 0.080, 0 },                -- behind the ear
            { 0.045, 0.030, 0.112, 0 },
            { 0.000, 0.090, 0.135, 0.05 },
            { -0.045, 0.155, 0.145, 0.15 },             -- J, the cheek ring (index `joint`; 3 cm further back than it was, so the two rings are 12 cm apart and not 7)
            { 0, 0, 0, 0.3 },                           -- the three points after the ring are made by HorseRope.setJawAngle: the strap runs down the cheek
            { 0, 0, 0, 0.45 },                          -- at an angle forward of straight down, parallel to the noseband's lower leg (from the red lines
            { 0, 0, 0, 0.7 },                           -- in a screenshot: nearly vertical on screen, which is forward of the head's own "down")
            { -0.228, 0.275, 0.070, 0.9 },              -- under the jaw
        },
        under = { -0.235, 0.265, 0, 1 },                -- U, under the jaw on the midline
        jawAngle = 30,                                  -- degrees forward of the head's straight down
        jawZ = { 0.140, 0.128, 0.110 },                 -- half widths of the strap's points down the cheek (the head there: 0.126, 0.114, 0.100)
        joint = 4,
        slack = 0.025,
    },
    cheek = { { -0.095, 0.246, 0.130 }, { -0.058, 0.205, 0.142 } },     -- from the noseband's ring (low on the nose's side: x -0.12, y 0.29, z 0.117) to the cheek ring (-0.045, 0.155, 0.145): a straight line a little outside the cheek (0.114 at y 0.25, 0.13 at 0.2)
    ring = { radius = 0.016, noseRadius = 0.016, noseOut = 0, noseForward = 0.002, sides = 8, diameter = 0.008 },     -- the steel rings each side: where the cheek strap, the strap to the ear and the strap under the jaw meet (radius) and where the cheek strap meets the noseband (noseRadius); the pieces stay steel: a ring is metal
    clearance = 0,          -- added to the sideways distance of the crown and the cheek strap (hdLead halter clearance): + stands further off the head
    margin = 0.002,         -- clearance of the NOSEBAND outside the measured head (0.012, 0.02, 0.008, 0.004: "still too big", then "the top lies flat on its skin")
    sides = 12,             -- 12 pieces round the noseband: the polygon's corners stand out only 3.5 percent (8 pieces: 8 percent, an octagon)
    diameter = 0.012,
    strapWidth = 0.02,      -- the leather straps (HorseRope.gear): 2 cm wide, 4 mm thick (HorseRope.STRAP_THICKNESS_M), the flat face against the skin; the pieces of rope have `diameter`
    axisX = -0.045,         -- the head's axis (a line along the face) for the straps' normals
}
HorseRope.chins = setmetatable({}, { __mode = "k" })
-- An offset for the whole halter (and the knot the lead is tied to) in the head bone's space (z is sideways). With 0.35 sideways it showed in the game beside the head (loops, cheek pieces and the lead tied to
-- the knot, all as designed), so it is on the head now: 0 0 0. Console: hdLead halteroffset x y z.
HorseRope.halterOffset = { 0, 0, 0 }
HorseRope.HALTER_REPORT_FRAMES = 120   -- frames after the halter was built when it logs its report (about two seconds)
HorseRope.HALTER_TRIES = 180          -- a horse that was just loaded may not have its head bone yet: the halter is tried every frame for about three seconds before it is given up
-- The bit ring, in the space of the horse's head bone (Head_M of character/animals/domesticated/horse/horse.i3d). From the bridle's own geometry (an OBJ export of the saddle shape: the bit rings are the two
-- small pieces at x = +-7 cm, y = 180 cm, z = 151 cm of the model) and the bone's rest pose composed from the i3d (rotations apply as Rz * Ry * Rx; that puts Head_M at 0 / 2.061 / 1.139 m, which lies on
-- the bridle). Console: hdLead ring x y z moves it.
-- The winch rope is steel grey with a glossy cable map (the game's two rope shapes share it) and its shader has no colour parameter: only an emissive one, ropeEmissiveColor, which it multiplies with the
-- normal map and adds to the lit surface (alpha = the 4th number, it has to be above 0). A tint through it looks like candy stripes (it follows the normal map's strands), so the default is none.
-- Console: hdLead tint r g b. The real fix is the MATERIAL (below).
HorseRope.tint = { 0, 0, 0, 0 }
HorseRope.pieces = setmetatable({}, { __mode = "k" })
-- The rope's material: a copy of the game's rope material (same shader and normal map) with a hemp colour and a matte gloss map, both tiny solid textures of our own (textures/rope_hemp_*.dds). The gloss map's
-- channels, read from the game's own maps (the steel cable 189 / 208 / 255, the hemp rope prop 43 / 212 / 0): red is smoothness, green about the same for both, blue metalness. Ours is 43 / 212 / 0. The engine's own
-- way (VehicleMaterial.lua): setMaterialDiffuseMapFromFile / setMaterialGlossMapFromFile give a new material, setMaterial puts it on the shape. Console: hdLead material hemp|steel.
HorseRope.material = "hemp"
-- The halter's and the harness's pieces: "leather" (flat straps, brown) or "rope" (round hemp, as the lead). The lead and the hand tools' ropes stay rope.
HorseRope.gear = "rope"                                  -- the default (the console, and a ride whose tool did not say): the tools say it per ride (ride.halterGear, ride.harnessGear)
HorseRope.STRAP_THICKNESS_M = 0.004

-- The options for createSegment of a piece of the gear: nil when the gear is rope; round leather when there is no width; else a flat strap of that width whose flat face lies against the skin (bone-space
-- normal lx, ly, lz of the node `bone`).
function HorseRope.gearOptions(width, bone, lx, ly, lz, gear)
    if (gear or HorseRope.gear) ~= "leather" then
        return nil
    end
    if width == nil then
        return { leather = true }
    end
    return { leather = true, strap = { width = width, thickness = math.min(HorseRope.STRAP_THICKNESS_M, width * 0.2), bone = bone, lx = lx, ly = ly, lz = lz } }
end

-- ForestryRope:update with the flat face of a strap turned to the skin: the game's own update points the piece's tube from its link node to its target and always uses world-up as the "up" of the tube (a
-- flat strap would then lie flat in the world: edge on where it runs down a side), this uses the skin's normal instead (the piece's strap.bone-space direction turned to world every frame).
function HorseRope.strapUpdate(self, dt)
    if not self.validTarget or not HorseRope.pieceNodesAlive(self) then
        return
    end
    if self.targetNode ~= nil then
        self.tx, self.ty, self.tz = getWorldTranslation(self.targetNode)
    end
    local dx, dy, dz = worldToLocal(self.referenceFrame, self.tx, self.ty, self.tz)
    local length = math.sqrt(dx * dx + dy * dy + dz * dz)
    if length > 1e-9 then
        dx, dy, dz = dx / length, dy / length, dz / length
    end
    local ux, uy, uz = 0, 1, 0
    local s = self.strap
    if s ~= nil and s.bone ~= nil and (entityExists == nil or entityExists(s.bone)) then
        local wx, wy, wz = localDirectionToWorld(s.bone, s.lx, s.ly, s.lz)
        ux, uy, uz = worldDirectionToLocal(self.referenceFrame, wx, wy, wz)
    end
    setDirection(self.ropeId, dx, dy, dz, ux, uy, uz)
    -- setDirection builds the node's orientation afresh and (as far as the straps showed: still round tubes with the scale set once) drops the flattening: it is put back after every turn. The first
    -- piece says in the log what scale it found, so a miss shows there.
    if s ~= nil and self.rfMaterialDone and setScale ~= nil then
        if not HorseRope.scaleLogged and getScale ~= nil then
            HorseRope.scaleLogged = true
            local sx, sy, sz = getScale(self.ropeId)
            print(string.format("[HorseDynamics] strap scale after setDirection: %.3f %.3f %.3f (wanted y %.3f)", sx or -1, sy or -1, sz or -1, s.thickness / s.width))
        end
        setScale(self.ropeId, 1, s.thickness / s.width, 1)
    end
    self:setLength(length)
end
HorseRope.modDirectory = g_currentModDirectory
HorseRope.HEAD_BONE = "Head_M"
HorseRope.ring = { -0.0983, 0.4425, 0.07 }
HorseRope.rings = setmetatable({}, { __mode = "k" })

-- One piece of rope linked to linkNode, loading its shape asynchronously (rope.referenceFrame is set when it is there). nil when the engine pieces are missing.
-- options: nil for a plain rope piece; { leather = true } for a leather piece (round: the material only); { leather = true, strap = { width, thickness, bone, lx, ly, lz } } for a flat strap:
-- the piece's tube is scaled thin once it has loaded (applyMaterial), and strapUpdate turns it so that its flat face lies against `bone`-space direction (lx, ly, lz), the skin's normal.
-- The game's ForestryRope:update fails every frame with "worldToLocal: Unknown entity id" when a node the piece hangs from or points at was deleted with a horse: a contract mod that hands in a ridden and a
-- led horse at once deletes both vehicles, and the nodes on them (the rope's anchor on the horse the player sits on, the halter's points), in the middle of a frame, before this mod's own cleanup has run.
-- A piece whose nodes are gone is skipped until the cleanup deletes it.
function HorseRope.pieceNodesAlive(piece)
    if entityExists == nil then
        return true
    end
    if piece.referenceFrame ~= nil and not entityExists(piece.referenceFrame) then
        return false
    end
    if piece.targetNode ~= nil and not entityExists(piece.targetNode) then
        return false
    end
    if piece.ropeId ~= nil and not entityExists(piece.ropeId) then
        return false
    end
    return true
end

function HorseRope.guardedUpdate(piece, dt)
    if not HorseRope.pieceNodesAlive(piece) then
        return
    end
    return ForestryRope.update(piece, dt)
end

local function createSegment(linkNode, diameter, options)
    local ok, rope = pcall(function()
        local r = ForestryRope.new(nil, linkNode)
        -- the engine does not know "$data": the game's own loader resolves the path first (ForestryRope:loadFromXML)
        r.i3dFilename, r.i3dRopePath = Utils.getFilename(HorseRope.FILENAME, nil), HorseRope.ROPE_NODE
        r.diameter, r.uvScale = diameter or HorseRope.DIAMETER, HorseRope.UV_SCALE
        if options ~= nil then
            r.leather, r.strap = options.leather, options.strap
            if r.strap ~= nil then
                r.diameter = r.strap.width                              -- (the shader's size is the DIAMETER: the rope shape has radius 0.5; the first leather straps were half as wide as meant)
                r.update = HorseRope.strapUpdate
            end
        end
        if r.update == ForestryRope.update then
            r.update = HorseRope.guardedUpdate
        end
        local t = HorseRope.tint
        r.emissiveColor, r.invalidEmissiveColor = { t[1], t[2], t[3], t[4] }, { t[1], t[2], t[3], t[4] }
        HorseRope.pieces[r] = true
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
local function findBone(node, name, depth)
    if getName(node) == name then
        return node
    end
    if depth > 24 then
        return nil
    end
    for i = 0, getNumOfChildren(node) - 1 do
        local found = findBone(getChildAt(node, i), name, depth + 1)
        if found ~= nil then
            return found
        end
    end
    return nil
end

HorseRope.createSegment, HorseRope.findBone = createSegment, findBone                  -- (for the harness)

-- A node at the bit ring of the horse's bridle (a child of its head bone), made once per horse. nil when the horse has no such bone (then the rein node is the target).
function HorseRope.ringAnchor(vehicle)
    if vehicle == nil or vehicle.rootNode == nil or createTransformGroup == nil or link == nil or getName == nil or getNumOfChildren == nil or getChildAt == nil then
        return nil
    end
    local cached = HorseRope.rings[vehicle]
    if cached == false then
        return nil
    end
    if cached ~= nil and (entityExists == nil or entityExists(cached)) then
        return cached
    end
    local ok, bone = pcall(findBone, vehicle.rootNode, HorseRope.HEAD_BONE, 0)
    if not ok or bone == nil then
        HorseRope.rings[vehicle] = false
        print("[HorseDynamics] leash: no head bone (" .. HorseRope.HEAD_BONE .. ") on this horse: the rope is tied to its rein node")
        return nil
    end
    local node = createTransformGroup("horseLeashRing")
    link(bone, node)
    setTranslation(node, HorseRope.ring[1], HorseRope.ring[2], HorseRope.ring[3])
    HorseRope.rings[vehicle] = node
    return node
end

-- Puts the hemp material on a rope piece whose shape has loaded (once per piece; the new material is made once per base material).
function HorseRope.applyMaterial(rope)
    if rope.rfMaterialDone or rope.ropeId == nil then
        return
    end
    rope.rfMaterialDone = true
    -- a flat strap: the tube is scaled thin along its own y axis (the shader scales x and y alike, so the node does the flattening)
    if rope.strap ~= nil and setScale ~= nil then
        pcall(setScale, rope.ropeId, 1, rope.strap.thickness / rope.strap.width, 1)
    end
    local kind = rope.leather and "leather" or HorseRope.material
    if (kind ~= "hemp" and kind ~= "leather") or HorseRope.modDirectory == nil or getMaterial == nil or setMaterial == nil
        or setMaterialDiffuseMapFromFile == nil or setMaterialGlossMapFromFile == nil then
        return
    end
    -- one new material per piece: a material id made for an earlier piece was found stale in the game ("Unknown entity id ... for 'material' in method 'setMaterial'": the first piece got hemp, the next 26 pieces
    -- reusing its id failed), and the engine prints that error even when it is caught
    local ok, err = pcall(function()
        local base = getMaterial(rope.ropeId, 0)
        local hemp = setMaterialDiffuseMapFromFile(base, HorseRope.modDirectory .. "textures/rope_" .. kind .. "_diffuse.dds", false, true, false)
        hemp = setMaterialGlossMapFromFile(hemp, HorseRope.modDirectory .. "textures/rope_" .. kind .. "_specular.dds", false, false, false)
        if kind == "leather" and setMaterialNormalMapFromFile ~= nil then
            hemp = setMaterialNormalMapFromFile(hemp, HorseRope.modDirectory .. "textures/rope_leather_normal.dds", false, false, false)       -- (flat: the rope's own normal map is the strands)
        end
        setMaterial(rope.ropeId, hemp, 0)
    end)
    if not ok and not HorseRope.materialReported then
        HorseRope.materialReported = true
        print("[HorseDynamics] leash: the rope's hemp material could not be applied (the rope stays steel): " .. tostring(err))
    end
end

-- The rope's tint (all the pieces that exist too).
function HorseRope.setTint(r, g, b)
    HorseRope.tint = { r, g, b, 1 }
    for piece in pairs(HorseRope.pieces) do
        piece.emissiveColor, piece.invalidEmissiveColor = { r, g, b, 1 }, { r, g, b, 1 }
        if piece.ropeId ~= nil and setShaderParameter ~= nil then
            pcall(setShaderParameter, piece.ropeId, "ropeEmissiveColor", r, g, b, 1, false)
        end
    end
end

-- Moves the bit ring (all the horses' anchors too).
function HorseRope.setRing(x, y, z)
    HorseRope.ring = { x, y, z }
    for _, node in pairs(HorseRope.rings) do
        if node ~= false and (entityExists == nil or entityExists(node)) then
            setTranslation(node, x, y, z)
        end
    end
end

function HorseRope.targetNodeOf(vehicle)
    if HorseRope.style == "halter" and HorseRope.chins[vehicle] ~= nil then
        return HorseRope.chins[vehicle]
    end
    if HorseRope.style == "tack" or HorseRope.style == "halter" then
        local ring = HorseRope.ringAnchor(vehicle)
        if ring ~= nil then
            return ring
        end
    end
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
    local slack = math.max(0, HorseRope.LENGTH_M - d)
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

-- The game's own reins: the tack on (Rideable:setEquipmentVisibility shows the saddle and bridle, one mesh, and the reins), both rein nodes linked to the source node as the game links them to a rider's hands.
function HorseRope.syncReins(ride, sourceNode)
    local vehicle = ride.vehicle
    local spec = vehicle ~= nil and vehicle.spec_rideable or nil
    if spec == nil or spec.leftReinNode == nil or spec.rightReinNode == nil or vehicle.setEquipmentVisibility == nil then
        return
    end
    if sourceNode == nil then
        HorseRope.releaseReins(ride)
        return
    end
    if not ride.tacked then
        pcall(vehicle.setEquipmentVisibility, vehicle, true)
        ride.tacked = true
    end
    if ride.reinSource ~= sourceNode then
        local ok, err = pcall(function()
            link(sourceNode, spec.leftReinNode)
            link(sourceNode, spec.rightReinNode)
        end)
        if not ok then
            print("[HorseDynamics] leash reins: could not be linked: " .. tostring(err))
        end
        ride.reinSource = sourceNode
    end
end

-- ===== the rope halter =====
-- The points of a loop (a list of { x, y, z } in the head bone's space), starting at the top (+x) and going round through +z, the bottom (-x) and -z.
function HorseRope.loopPoints(spec, sides, margin)
    local scale = 1 / math.cos(math.pi / sides)
    local tilt = math.rad(spec.tilt or 0)
    local ax, ay = math.cos(tilt), -math.sin(tilt)               -- the loop's up-down axis in the head's x / y plane
    local points = {}
    for i = 0, sides - 1 do
        local angle = 2 * math.pi * i / sides
        -- how far back the point is pulled: with a ringAngle (the noseband: the front ring sits that many degrees round from the top, low on the side of the nose) it grows from 0 at the top to the whole bend
        -- at the ring and stays there down to the bottom, so the upper leg slopes up over the nose and the lower leg falls straight down; without one, 0 at the top and the bottom and the whole bend at the sides
        local fold = math.min(angle, 2 * math.pi - angle)
        local back = (spec.bend or 0) * math.abs(math.sin(angle))
        if spec.ringAngle ~= nil then
            back = (spec.bend or 0) * math.min(1, fold / math.rad(spec.ringAngle))
        end
        local up = (spec.vertical + margin + (spec.deepen or 0) * back) * scale * math.cos(angle)     -- (deepen: the muzzle is taller further back)
        points[#points + 1] = { spec.centre + up * ax, spec.y + up * ay - back, (spec.lateral + margin + (spec.widen or 0) * back) * scale * math.sin(angle), (1 - math.cos(angle)) / 2 }   -- (the 4th number: 0 at the top, 1 at the bottom)
    end
    return points
end

-- The strap down the cheek: three points from the ring's place, `degrees` forward of the head's straight down (the head's -x), 0.058 m apart, at the half widths in crown.jawZ.
function HorseRope.setJawAngle(degrees)
    local c = HorseRope.halter.crown
    local j, a = c.sides[c.joint], math.rad(degrees)
    c.jawAngle = degrees
    for m = 1, 3 do
        c.sides[c.joint + m][1], c.sides[c.joint + m][2], c.sides[c.joint + m][3] = j[1] - 0.058 * m * math.cos(a), j[2] + 0.058 * m * math.sin(a), c.jawZ[m]
    end
    local last = c.sides[c.joint + 3]
    c.sides[c.joint + 4][2] = last[2] + 0.003             -- (the corner of the jaw is as far forward as the strap got)
    c.under[2] = last[2] - 0.007
end
HorseRope.setJawAngle(HorseRope.halter.crown.jawAngle)

-- Builds the halter on a horse's head bone: nodes (children of the bone) and the rope pieces between them. Returns { nodes, pieces, tied } with the chin knot registered in HorseRope.chins, or nil.
function HorseRope.buildHalter(vehicle, gear)
    if ForestryRope == nil or ForestryRope.new == nil or g_i3DManager == nil or Utils == nil or Utils.getFilename == nil or createTransformGroup == nil or link == nil
        or vehicle == nil or vehicle.rootNode == nil or getName == nil or getNumOfChildren == nil or getChildAt == nil then
        return nil
    end
    local ok, bone = pcall(findBone, vehicle.rootNode, HorseRope.HEAD_BONE, 0)
    if not ok or bone == nil then
        return nil
    end
    local h = HorseRope.halter
    -- The points are NOT children of the head bone: pieces hung under the skeleton were loaded, tied and "visible" in the game and still did not render (something inherited from the skeleton: a hidden parent,
    -- a mirrored scale ...), while the lead's pieces, whose points hang under the world root, do. So the points live under the root and are put at the bone's world position every frame (halterPlace).
    local halter = { nodes = {}, locals = {}, slack = {}, bone = bone, pieces = {}, tied = {}, targets = {}, localOf = {} }
    local function point(x, y, z, slack)
        local node = createTransformGroup("horseHalterPoint")
        link(getRootNode(), node)
        halter.nodes[#halter.nodes + 1] = node
        halter.localOf[node] = { x, y, z }
        halter.locals[#halter.nodes] = { x, y, z }
        halter.slack[#halter.nodes] = slack or 0
        return node
    end
    local function loop(spec)
        local nodes = {}
        for _, p in ipairs(HorseRope.loopPoints(spec, h.sides, h.margin)) do
            nodes[#nodes + 1] = point(p[1], p[2], p[3], (spec.slack or 0) * p[4])
        end
        return nodes
    end
    local nose = loop(h.nose)
    -- the skin's normal at a strap: out from the head's axis (a line along the face at x = h.axisX), at the middle of the piece
    local function normalOf(from, to)
        local a, b = halter.localOf[from], halter.localOf[to]
        local mx, mz = (a[1] + b[1]) / 2 - h.axisX, (a[3] + b[3]) / 2
        local length = math.sqrt(mx * mx + mz * mz)
        if length < 1e-6 then
            return 1, 0, 0
        end
        return mx / length, 0, mz / length
    end
    local function piece(from, to, diameter, steel)
        local options = nil
        if not steel then
            local nx, ny, nz = normalOf(from, to)
            options = HorseRope.gearOptions(h.strapWidth, bone, nx, ny, nz, gear)
        end
        local rope = createSegment(from, diameter or h.diameter, options)
        if rope ~= nil then
            rope.rfMaterialDone = steel or nil                -- (the hemp is put on a piece whose shape has loaded, unless it is a ring)
            halter.pieces[#halter.pieces + 1] = rope
            halter.targets[#halter.pieces] = to
        end
    end
    -- A ring (a small vertical polygon of steel, round (x, y, z) in the head's space): its points, and near(tx, ty), the point nearest to the direction towards (tx, ty).
    local function ringAt(x, y, z, radius, slack)
        local ring, scale, sides = { nodes = {} }, 1 / math.cos(math.pi / h.ring.sides), h.ring.sides
        for r = 0, sides - 1 do
            local angle = 2 * math.pi * r / sides
            ring.nodes[#ring.nodes + 1] = point(x + radius * scale * math.cos(angle), y + radius * scale * math.sin(angle), z, slack)
        end
        ring.near = function(tx, ty)
            return ring.nodes[(math.floor(math.atan2(ty - y, tx - x) / (2 * math.pi / sides) + 0.5) % sides) + 1]
        end
        ring.close = function()
            for r = 1, sides do
                piece(ring.nodes[r], ring.nodes[r % sides + 1], h.ring.diameter, true)
            end
        end
        return ring
    end
    -- the noseband's side points are rings: the noseband passes through them and the cheek strap ends on them
    local noseRings = {}
    for _, side in ipairs({ 1, -1 }) do
        local step = math.floor(h.nose.ringAngle / 360 * h.sides + 0.5)                          -- (the ring's place round the loop, from the top: 4 of 12 steps, 120 degrees)
        local index = side > 0 and step + 1 or h.sides - step + 1
        local l = halter.locals[index]
        noseRings[side] = { index = index, ring = ringAt(l[1], l[2] + h.ring.noseForward, l[3] + side * h.ring.noseOut, h.ring.noseRadius, halter.slack[index]) }
    end
    for i = 1, h.sides do
        local next = i % h.sides + 1
        local from, to = nose[i], nose[next]
        for _, side in ipairs({ 1, -1 }) do
            local n = noseRings[side]
            if next == n.index then
                to = n.ring.near(halter.locals[i][1], halter.locals[i][2])              -- (the neighbours differ in x only: the ring's top or bottom point)
            elseif i == n.index then
                from = n.ring.near(halter.locals[next][1], halter.locals[next][2])
            end
        end
        piece(from, to)
    end
    for _, side in ipairs({ 1, -1 }) do
        noseRings[side].ring.close()
    end
    -- the crown: a path from the top of the head down each side to the cheek ring, past the jowl and under the throat (see the table at HorseRope.halter)
    local c = h.crown
    local top = point(c.top[1], c.top[2], c.top[3], c.slack * c.top[4])
    local under = point(c.under[1], c.under[2], c.under[3], c.slack * c.under[4])
    for _, side in ipairs({ 1, -1 }) do
        local function out(z) return side * (z + (z ~= 0 and h.clearance or 0)) end
        local path = {}
        for k, p in ipairs(c.sides) do
            if k ~= c.joint then
                path[k] = point(p[1], p[2], out(p[3]), c.slack * p[4])
            end
        end
        -- the ring at the junction: the three straps end on its points nearest to where they come from
        local j = c.sides[c.joint]
        local ring = ringAt(j[1], j[2], out(j[3]), h.ring.radius, c.slack * j[4])
        ring.close()
        local ear, jaw = c.sides[c.joint - 1], c.sides[c.joint + 1]
        piece(top, path[1])
        for k = 1, c.joint - 2 do
            piece(path[k], path[k + 1])
        end
        piece(path[c.joint - 1], ring.near(ear[1], ear[2]))
        piece(ring.near(jaw[1], jaw[2]), path[c.joint + 1])
        for k = c.joint + 1, #c.sides - 1 do
            piece(path[k], path[k + 1])
        end
        piece(path[#c.sides], under)
        -- the cheek strap: from the noseband's ring out round the cheek to the crown ring
        local first, second = h.cheek[1], h.cheek[2]
        local a = point(first[1], first[2], out(first[3]), 0)
        local b = point(second[1], second[2], out(second[3]), 0)
        local noseRing = noseRings[side].ring
        piece(noseRing.near(first[1], first[2]), a)
        piece(a, b)
        piece(b, ring.near(second[1], second[2]))
        -- the strap along the bottom: from the noseband's lower corner (150 and 210 degrees round the loop) back to the lower end of the strap down the cheek, as a halter has it between the two
        piece(nose[math.floor(h.sides / 2) + 1], path[#c.sides])                  -- (from the chin, the bottom of the noseband, on both sides)
    end
    halter.chin = nose[math.floor(h.sides / 2) + 1]                -- the bottom of the noseband: the knot the lead is tied to
    HorseRope.chins[vehicle] = halter.chin
    HorseRope.halterPlace(halter)
    return halter
end

-- Puts every point of the halter at its place in the head bone's space, in world coordinates (the points hang under the world root).
function HorseRope.halterPlace(halter)
    if halter.bone == nil or (entityExists ~= nil and not entityExists(halter.bone)) then
        return
    end
    -- world-down in the bone's space: the slack hangs down whatever way the head is turned
    local gx, gy, gz = 0, -1, 0
    if worldDirectionToLocal ~= nil then
        local ok, a, b, c = pcall(worldDirectionToLocal, halter.bone, 0, -1, 0)
        if ok and a ~= nil then
            gx, gy, gz = a, b, c
        end
    end
    local o = HorseRope.halterOffset
    for i, node in ipairs(halter.nodes) do
        local l, slack = halter.locals[i], halter.slack[i] or 0
        local x, y, z = localToWorld(halter.bone, l[1] + o[1] + gx * slack, l[2] + o[2] + gy * slack, l[3] + o[3] + gz * slack)
        setTranslation(node, x, y, z)
    end
end

-- Every frame for a led horse in the halter style: builds it, ties each piece once its shape has loaded (active, like the lead's pieces: the rope code re-reads the points every frame), shows it.

-- A report on the halter of the first led horse (console: hdLead halterinfo), to see why nothing shows: how many pieces were made, loaded and tied, and where the head bone, the points and a piece are.
function HorseRope.halterReport(rides)
    local lines = {}
    for _, ride in ipairs(rides) do
        local halter = ride.halter
        if halter ~= nil then
            local loaded, tied = 0, 0
            for i, rope in ipairs(halter.pieces) do
                loaded = loaded + (rope.referenceFrame ~= nil and 1 or 0)
                tied = tied + (halter.tied[i] and 1 or 0)
            end
            lines[#lines + 1] = string.format("halter: %d pieces, %d loaded, %d tied, %d points", #halter.pieces, loaded, tied, #halter.nodes)
            local function where(label, node)
                if node ~= nil and (entityExists == nil or entityExists(node)) then
                    local x, y, z = getWorldTranslation(node)
                    lines[#lines + 1] = string.format("  %s: world %.3f %.3f %.3f", label, x, y, z)
                else
                    lines[#lines + 1] = "  " .. label .. ": gone"
                end
            end
            where("a point of the noseband", halter.nodes[1])
            where("the chin knot", halter.chin)
            local rope = halter.pieces[1]
            if rope ~= nil then
                where("piece 1 shape", rope.ropeId)
                where("piece 1 frame", rope.referenceFrame)
                lines[#lines + 1] = string.format("  piece 1: visible %s, shape visible %s", tostring(rope.referenceFrame ~= nil and getVisibility ~= nil and getVisibility(rope.referenceFrame)),
                    tostring(rope.ropeId ~= nil and getVisibility ~= nil and getVisibility(rope.ropeId)))
                -- the ancestors of a piece, from its frame up: a hidden or oddly scaled parent would explain a piece that is loaded, tied and not drawn
                local node, depth = rope.referenceFrame, 0
                while node ~= nil and depth < 8 and getParent ~= nil do
                    local sx, sy, sz = 1, 1, 1
                    if getScale ~= nil then
                        local ok, a, b, c = pcall(getScale, node)
                        if ok then sx, sy, sz = a, b, c end
                    end
                    lines[#lines + 1] = string.format("    ancestor %d: %s visible=%s scale %.3f %.3f %.3f", depth, tostring(getName ~= nil and getName(node) or "?"), tostring(getVisibility ~= nil and getVisibility(node)), sx or 0, sy or 0, sz or 0)
                    local ok, parent = pcall(getParent, node)
                    node = ok and parent ~= 0 and parent or nil
                    depth = depth + 1
                end
            end
            if ride.vehicle ~= nil and ride.vehicle.rootNode ~= nil and halter.bone ~= nil and worldToLocal ~= nil then
                local hx, hy, hz = getWorldTranslation(halter.bone)
                local lx, ly, lz = worldToLocal(ride.vehicle.rootNode, hx, hy, hz)
                lines[#lines + 1] = string.format("  head bone in the horse's own space: %.3f %.3f %.3f (the rest pose is 0 / 2.061 / 1.139)", lx, ly, lz)
            end
        else
            lines[#lines + 1] = "a led horse without a halter (style " .. tostring(HorseRope.style) .. ", failed: " .. tostring(ride.halterFailed) .. ", tries: " .. tostring(ride.halterTries) .. ")"
        end
    end
    if #lines == 0 then
        lines[1] = "no horse is led"
    end
    print("[HorseDynamics] halter report:\n" .. table.concat(lines, "\n"))
    return table.concat(lines, "\n")
end
function HorseRope.halterSync(ride)
    if ride.halter == nil and not ride.halterFailed then
        ride.halter = HorseRope.buildHalter(ride.vehicle, ride.halterGear)
        if ride.halter == nil then
            ride.halterTries = (ride.halterTries or 0) + 1
            if ride.halterTries >= HorseRope.HALTER_TRIES then
                ride.halterFailed = true
                print("[HorseDynamics] leash: the rope halter could not be built (no head bone or no rope, tried for about three seconds): the rope is tied to the bit ring or the rein node")
            end
        end
    end
    local halter = ride.halter
    if halter == nil then
        return
    end
    -- two seconds after it was built the halter says how it is doing (the log is the evidence: no need to type hdLead halterinfo)
    halter.frames = (halter.frames or 0) + 1
    if halter.frames == HorseRope.HALTER_REPORT_FRAMES then
        HorseRope.halterReport({ ride })
    end
    pcall(HorseRope.halterPlace, halter)
    for i, rope in ipairs(halter.pieces) do
        HorseRope.applyMaterial(rope)
        pcall(rope.setVisibility, rope, true)
        if halter.tied[i] then
            pcall(rope.update, rope, 0)           -- (the points moved just now: the piece follows them this frame)
        end
        if rope.referenceFrame ~= nil and not halter.tied[i] then
            local tied, tieError = pcall(rope.setTargetNode, rope, halter.targets[i], true)
            halter.tied[i] = tied or nil
            if not tied and not ride.halterTieReported then
                ride.halterTieReported = true
                print("[HorseDynamics] leash: a halter piece could not be tied: " .. tostring(tieError))
            end
        end
    end
end

function HorseRope.destroyHalter(ride)
    local halter = ride.halter
    if halter ~= nil then
        for _, rope in ipairs(halter.pieces) do
            pcall(rope.delete, rope)
        end
        for _, node in ipairs(halter.nodes) do
            pcall(function()
                if entityExists == nil or entityExists(node) then
                    delete(node)
                end
            end)
        end
        if ride.vehicle ~= nil then
            HorseRope.chins[ride.vehicle] = nil
        end
    end
    ride.halter, ride.halterFailed, ride.halterTries, ride.halterTieReported = nil, nil, nil, nil
end

-- The tack on, the reins at rest: the reins back where the game keeps them (Rideable:unlinkReins, which also hides them), then the equipment shown (saddle, bridle and, with them, the reins).
function HorseRope.dress(ride)
    local vehicle = ride.vehicle
    if ride.tacked or vehicle == nil or vehicle.setEquipmentVisibility == nil then
        return
    end
    if vehicle.unlinkReins ~= nil then
        pcall(vehicle.unlinkReins, vehicle)
    end
    pcall(vehicle.setEquipmentVisibility, vehicle, true)
    ride.tacked = true
end

-- The tack off and the reins back where the game keeps them (Rideable:unlinkReins). Not for a horse a player sits on: the game has linked its reins to his hands then.
function HorseRope.releaseReins(ride)
    local vehicle = ride.vehicle
    if ride.tacked and vehicle ~= nil and not vehicle.isDeleted and not (vehicle.getIsEntered ~= nil and vehicle:getIsEntered()) then
        if vehicle.unlinkReins ~= nil then
            pcall(vehicle.unlinkReins, vehicle)
        end
        pcall(vehicle.setEquipmentVisibility, vehicle, false)
    end
    ride.tacked, ride.reinSource = nil, nil
end

-- Called every frame for a leashed horse: makes the rope, ties each piece once its shape has loaded, hangs the points, shows or hides it. sourceNode nil: nothing to hang it from.
function HorseRope.sync(ride, sourceNode)
    if HorseRope.style == "reins" then
        HorseRope.syncReins(ride, sourceNode)
        return
    end
    if HorseRope.style == "tack" and sourceNode ~= nil then
        HorseRope.dress(ride)
    end
    if HorseRope.style == "halter" then
        HorseRope.halterSync(ride)
    end
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
        HorseRope.applyMaterial(rope)
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
-- keepHarness: the horse stays in its harness (only the halter and the lead rope go): the harness, and a trailer hitched to it, are none of this (they were destroyed and rebuilt, and the hitch let go).
-- keepHalter: only the lead rope goes, the halter stays on the horse (a horse let go outside a pasture).
function HorseRope.remove(ride, keepHarness, keepHalter)
    HorseRope.releaseReins(ride)
    if not keepHalter then
        HorseRope.destroyHalter(ride)
    end
    if HorseHarness ~= nil and not keepHarness then
        HorseHarness.destroy(ride)
    end
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

-- The leash in the hand without a horse on it: a rope held in the hand, draped over it, the two ends hanging down: an inverted U made of two straight legs (STUB_LEG_PIECES pieces each, STUB_LEG_M long)
-- and a half circle on top (STUB_ARC_SEGMENTS pieces, STUB_RADIUS_M), the apex at the tool, in the vertical plane that faces the camera so it shows from the side. The points are plain nodes under the root node,
-- put there every frame. (The first version was a closed ring, a hoop lying on the grass seen from above; the second a parabola, whose apex bends under a centimetre across: two pieces meeting in a hairpin with
-- flat ends. Now the turn at the top is spread over 8 joints of 22.5 degrees.) sourceNode nil: not held, hidden.
HorseRope.STUB_RADIUS_M = 0.035
HorseRope.STUB_LEG_M = 0.25
HorseRope.STUB_LEG_PIECES = 3
HorseRope.STUB_ARC_SEGMENTS = 8

-- The points of the arch as { sideways, up } from the tool, from the end of the left leg over the apex to the end of the right leg.
function HorseRope.stubPath()
    local r, length, legs, arc = HorseRope.STUB_RADIUS_M, HorseRope.STUB_LEG_M, HorseRope.STUB_LEG_PIECES, HorseRope.STUB_ARC_SEGMENTS
    local points = {}
    for k = 0, legs - 1 do
        points[#points + 1] = { -r, -(r + length) + length * k / legs }          -- the left leg, from its free end up to just below the arc
    end
    for j = 0, arc do
        local phi = math.pi - math.pi * j / arc                                  -- the half circle from (-r, -r) over the apex (0, 0) to (r, -r)
        points[#points + 1] = { r * math.cos(phi), -r + r * math.sin(phi) }
    end
    for k = 1, legs do
        points[#points + 1] = { r, -r - length * k / legs }                      -- the right leg down to its free end
    end
    return points
end

function HorseRope.syncStub(sourceNode)
    local stub = HorseRope.stub
    if stub == nil then
        if sourceNode == nil or createTransformGroup == nil or link == nil or getRootNode == nil or ForestryRope == nil or ForestryRope.new == nil or g_i3DManager == nil
            or Utils == nil or Utils.getFilename == nil then
            return
        end
        stub = { nodes = {}, pieces = {}, tied = {} }
        HorseRope.stub = stub
    end
    if sourceNode == nil then
        for _, rope in ipairs(stub.pieces) do
            pcall(rope.setVisibility, rope, false)
        end
        return
    end
    local path = HorseRope.stubPath()
    -- made once (and again if the engine deleted the points, e.g. on a savegame change)
    if #stub.pieces ~= #path - 1 or (entityExists ~= nil and not entityExists(stub.nodes[1])) then
        for _, rope in ipairs(stub.pieces) do
            pcall(rope.delete, rope)
        end
        stub.nodes, stub.pieces, stub.tied = {}, {}, {}
        for i = 1, #path do
            local node = createTransformGroup("horseLeashLoop")
            link(getRootNode(), node)
            stub.nodes[i] = node
        end
        for i = 1, #path - 1 do
            stub.pieces[i] = createSegment(stub.nodes[i])
        end
    end
    -- the arch: its apex at the tool, hanging down, in the plane that faces the camera
    local hx, hy, hz = getWorldTranslation(sourceNode)
    local rx, rz = 1, 0
    if getCamera ~= nil and localDirectionToWorld ~= nil then
        local ok, dx, _, dz = pcall(localDirectionToWorld, getCamera(), 1, 0, 0)
        if ok and dx ~= nil then
            local length = math.sqrt(dx * dx + dz * dz)
            if length > 1e-6 then
                rx, rz = dx / length, dz / length
            end
        end
    end
    for i, p in ipairs(path) do
        setTranslation(stub.nodes[i], hx + rx * p[1], hy + p[2], hz + rz * p[1])
    end
    for i, rope in ipairs(stub.pieces) do
        HorseRope.applyMaterial(rope)
        pcall(rope.setVisibility, rope, true)
        if rope.referenceFrame ~= nil and not stub.tied[i] then
            local ok = pcall(rope.setTargetNode, rope, stub.nodes[i + 1], true)
            stub.tied[i] = ok or nil
        end
        if stub.tied[i] then
            pcall(rope.update, rope, 0)
        end
    end
end

-- The leather look for the base-game rope prop a hand tool holds (the tool's model is the AS pier rope01 in a wrapper): every shape under `root` but the collision gets the leather diffuse, gloss and a
-- flat normal map, a new material each (a shared id went stale in the game, see applyMaterial). Best effort, returns how many shapes it did.
function HorseRope.leatherProp(root)
    if root == nil or getNumOfChildren == nil or getChildAt == nil or getName == nil or getHasClassId == nil or ClassIds == nil or getMaterial == nil or setMaterial == nil
        or setMaterialDiffuseMapFromFile == nil or setMaterialGlossMapFromFile == nil or HorseRope.modDirectory == nil then
        return 0
    end
    local done = 0
    local function shape(node)
        local base = getMaterial(node, 0)
        local material = setMaterialDiffuseMapFromFile(base, HorseRope.modDirectory .. "textures/rope_leather_diffuse.dds", false, true, false)
        material = setMaterialGlossMapFromFile(material, HorseRope.modDirectory .. "textures/rope_leather_specular.dds", false, false, false)
        if setMaterialNormalMapFromFile ~= nil then
            material = setMaterialNormalMapFromFile(material, HorseRope.modDirectory .. "textures/rope_leather_normal.dds", false, false, false)
        end
        setMaterial(node, material, 0)
    end
    local function walk(node, depth)
        if depth > 8 then
            return
        end
        if getName(node) ~= "col" and getHasClassId(node, ClassIds.SHAPE) and pcall(shape, node) then
            done = done + 1
        end
        for i = 0, getNumOfChildren(node) - 1 do
            walk(getChildAt(node, i), depth + 1)
        end
    end
    pcall(walk, root, 0)
    return done
end

-- The harness tool in the hand: a collar, a thick round piece of rope (a padded ring) held at the top, hanging down, in the plane that faces the camera. Closed: the last piece ends at the first point.
HorseRope.COLLAR_RADIUS_M = 0.13
HorseRope.COLLAR_SEGMENTS = 12
HorseRope.COLLAR_DIAMETER = 0.05
function HorseRope.syncCollar(sourceNode, gear)
    local collar = HorseRope.collar
    if collar == nil then
        if sourceNode == nil or createTransformGroup == nil or link == nil or getRootNode == nil or ForestryRope == nil or ForestryRope.new == nil or g_i3DManager == nil
            or Utils == nil or Utils.getFilename == nil then
            return
        end
        collar = { nodes = {}, pieces = {}, tied = {} }
        HorseRope.collar = collar
    end
    if sourceNode == nil then
        for _, rope in ipairs(collar.pieces) do
            pcall(rope.setVisibility, rope, false)
        end
        return
    end
    local n, r = HorseRope.COLLAR_SEGMENTS, HorseRope.COLLAR_RADIUS_M
    -- the collar is made of the tool's gear: round leather for a leather harness tool (the tool in the hand changed: it is made again)
    if #collar.pieces == n and collar.gear ~= gear then
        for _, rope in ipairs(collar.pieces) do
            pcall(rope.delete, rope)
        end
        collar.pieces = {}
    end
    if #collar.pieces ~= n or (entityExists ~= nil and not entityExists(collar.nodes[1])) then
        collar.gear = gear
        for _, rope in ipairs(collar.pieces) do
            pcall(rope.delete, rope)
        end
        collar.nodes, collar.pieces, collar.tied = {}, {}, {}
        for i = 1, n do
            local node = createTransformGroup("horseCollarPoint")
            link(getRootNode(), node)
            collar.nodes[i] = node
        end
        for i = 1, n do
            collar.pieces[i] = createSegment(collar.nodes[i], HorseRope.COLLAR_DIAMETER, HorseRope.gearOptions(nil, nil, nil, nil, nil, gear))
        end
    end
    local hx, hy, hz = getWorldTranslation(sourceNode)
    local rx, rz = 1, 0
    if getCamera ~= nil and localDirectionToWorld ~= nil then
        local ok, dx, _, dz = pcall(localDirectionToWorld, getCamera(), 1, 0, 0)
        if ok and dx ~= nil then
            local length = math.sqrt(dx * dx + dz * dz)
            if length > 1e-6 then
                rx, rz = dx / length, dz / length
            end
        end
    end
    for i = 1, n do
        local phi = 2 * math.pi * (i - 1) / n                                  -- the circle hangs from the tool: its top (phi 90 degrees) is at the hand
        local x, y = r * math.cos(phi), -r + r * math.sin(phi)
        setTranslation(collar.nodes[i], hx + rx * x, hy + y, hz + rz * x)
    end
    for i, rope in ipairs(collar.pieces) do
        HorseRope.applyMaterial(rope)
        pcall(rope.setVisibility, rope, true)
        if rope.referenceFrame ~= nil and not collar.tied[i] then
            local ok = pcall(rope.setTargetNode, rope, collar.nodes[i % n + 1], true)
            collar.tied[i] = ok or nil
        end
        if collar.tied[i] then
            pcall(rope.update, rope, 0)
        end
    end
end
