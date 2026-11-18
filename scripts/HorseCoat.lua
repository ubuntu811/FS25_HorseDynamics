--[[
    HorseCoat.lua -- every horse gets a random look the moment it exists: a blaze or not, socks or not, and a pattern (plain, snowflake, sparse flecks, blanket with spots, plain blanket, leopard, pinto patches).
    You never quite know what you get (genetics will come later and replace the dice with genes). The look is the shader's markings (shaders/foalCoatShader.xml, see dev/foal/ABOUT.md) on top of the game's own
    coat colour; what is rolled here is only the markings.

    One number per horse, the SEED (cluster.hdCoatSeed, 1 .. 2^24-1), saved with the animal (AnimalClusterHorse: save, load, streams, clone), so the horse looks the same on its pasture, led, ridden, after a
    save and as a foal and later as an adult. HorseCoat.fromSeed(seed) turns it into the coat table of HorseFoal (pure, tested). A horse without a seed (bought, born, or from an older game) gets one as it is created
    or first shown. Applied when a horse vehicle gets its cluster (Rideable.setCluster) and when a pasture builds its animals (AnimalClusterHusbandry:updateVisuals). The dealer shows a picture, not the model:
    nothing of this is visible there.
    The look is told on the information screens: a Coat line in the info box of a horse, and a line under the description of one of your own animals in the animal screen.
    Console (HorseFoal): hdCoat randomize [seed] rolls a new look for the nearest horse vehicle, hdCoat seed says what it has.
]]
HorseCoat = {}
HorseCoat.MAX_SEED = 16777215          -- 24 bits
HorseCoat.SEED_BITS = 24

-- (name, weight) of the patterns, and of the face markings (the value is the shader's face 0 .. 3)
HorseCoat.PATTERNS = {
    { "plain", 46 }, { "snowflake", 10 }, { "sparse flecks", 10 }, { "blanket with spots", 12 }, { "blanket", 8 }, { "leopard", 6 }, { "pinto patches", 8 },
}
HorseCoat.FACES = { { 0, 34 }, { 1, 24 }, { 2, 26 }, { 3, 16 } }
HorseCoat.FACE_NAMES = { [0] = "no face marking", [1] = "star", [2] = "blaze", [3] = "blaze and snip" }
HorseCoat.NO_SOCKS = 40                -- percent of the horses without socks

-- Park-Miller: exact in doubles (the product stays under 2^53), the same on every machine
local function generator(seed)
    local s = (math.floor(seed) % 2147483646) + 1
    return function()
        s = s * 16807 % 2147483647
        return s / 2147483647
    end
end

local function pick(r, list)
    local total = 0
    for _, entry in ipairs(list) do total = total + entry[2] end
    local x = r() * total
    for _, entry in ipairs(list) do
        x = x - entry[2]
        if x < 0 then return entry end
    end
    return list[#list]
end

-- The coat of a seed: a table like HorseFoal's coatNew (neutral colour, only markings), and a short text of what it is. Pure.
function HorseCoat.fromSeed(seed)
    local r = generator(seed)
    local white = HorseFoal ~= nil and HorseFoal.WHITE_DEFAULT or { 0.77, 0.78, 0.78 }
    local c = { tint = { 1, 1, 1 }, shade = { 1, 1 }, gloss = 0, pattern = { 0, white[1], white[2], white[3] }, white = { white[1], white[2], white[3] },
        face = 0, socks = 0, blanket = 0, keep = 0, flecks = 0, raw = true, spots = { 0.7, 0.8, 0, 0.08 } }      -- (raw: the spots as the shader draws them: it looked right in the clip of 2026-11-12, the distance helpers are opt-in)
    local parts = {}
    local face = pick(r, HorseCoat.FACES)[1]
    c.face = face
    if face > 0 then parts[#parts + 1] = HorseCoat.FACE_NAMES[face] end
    if r() * 100 >= HorseCoat.NO_SOCKS then
        c.socks = 0.2 + 0.6 * r()
        parts[#parts + 1] = c.socks > 0.55 and "high socks" or "socks"
    else
        r()
    end
    local pattern = pick(r, HorseCoat.PATTERNS)[1]
    local a, b, d, e = r(), r(), r(), r()                       -- (the four rolls every pattern may use, drawn always so the sequence does not depend on the pattern)
    c.spots = { 0.45 + 0.4 * a, 0.55 + 0.35 * b, math.floor(d * 1000), 0.07 + 0.03 * e }
    if pattern == "snowflake" then
        c.flecks = 1
    elseif pattern == "sparse flecks" then
        c.flecks = 1; c.spots[1] = 0.15 + 0.2 * a                  -- (sparse on purpose: a few spots on a whole horse is a look, the user likes that)
    elseif pattern == "blanket with spots" then
        c.blanket, c.keep = 0.3 + 0.3 * d, 1
    elseif pattern == "blanket" then
        c.blanket, c.keep = 0.3 + 0.25 * d, 0
    elseif pattern == "leopard" then
        c.blanket, c.keep = 1, 1
    elseif pattern == "pinto patches" then
        c.pattern[1] = 1
    end
    if pattern ~= "plain" then parts[#parts + 1] = pattern end
    return c, #parts > 0 and table.concat(parts, ", ") or "plain"
end

local function isHorseCluster(cluster)
    return cluster ~= nil and type(cluster) == "table" and cluster.fitness ~= nil and cluster.riding ~= nil and cluster.dirt ~= nil
end
HorseCoat.isHorseCluster = isHorseCluster

-- The seed of a horse cluster; a horse without one gets one now. nil for anything that is not a horse.
function HorseCoat.ensureSeed(cluster)
    if not isHorseCluster(cluster) then
        return nil
    end
    if cluster.hdCoatSeed == nil then
        cluster.hdCoatSeed = math.random(1, HorseCoat.MAX_SEED)
    end
    return cluster.hdCoatSeed
end

-- ===== saving: the seed goes with the animal =====
function HorseCoat.save(self, xmlFile, key)
    if self.hdCoatSeed ~= nil then
        xmlFile:setInt(key .. "#hdCoatSeed", self.hdCoatSeed)
    end
end
function HorseCoat.load(self, superFunc, xmlFile, key)
    local ok = superFunc(self, xmlFile, key)
    if ok then
        self.hdCoatSeed = xmlFile:getInt(key .. "#hdCoatSeed")
    end
    return ok
end
function HorseCoat.write(self, streamId)
    streamWriteUIntN(streamId, self.hdCoatSeed or 0, HorseCoat.SEED_BITS)
end
function HorseCoat.read(self, streamId)
    local v = streamReadUIntN(streamId, HorseCoat.SEED_BITS)
    self.hdCoatSeed = v > 0 and v or nil
end
function HorseCoat.clone(self, superFunc)
    local ret = superFunc(self)
    if ret ~= nil then
        ret.hdCoatSeed = self.hdCoatSeed
    end
    return ret
end

-- ===== showing it =====
-- a horse vehicle that has its cluster: the markings on its mesh (a look set by hand with hdCoat stays: vehicle.horseCoatManual)
function HorseCoat.applyVehicle(vehicle)
    if vehicle.horseCoatManual or vehicle.spec_rideable == nil or vehicle.spec_rideable.meshNode == nil or vehicle.getCluster == nil then
        return
    end
    local ok, cluster = pcall(vehicle.getCluster, vehicle)
    local seed = ok and HorseCoat.ensureSeed(cluster) or nil
    if seed == nil then
        return
    end
    local c = HorseCoat.fromSeed(seed)
    vehicle.horseCoat = c                       -- (hdCoat then tunes this one)
    HorseFoal.applyCoat(vehicle.spec_rideable.meshNode, c)
    HorseCoat.fresh[vehicle] = { left = HorseCoat.FRESH_MS, tick = HorseCoat.FRESH_TICK_MS }
end

-- the animals a pasture has just built (its animalIdToCluster is a new table every time it rebuilds them): each gets its look
function HorseCoat.applyHusbandry(self)
    local map = self.animalIdToCluster
    if map == nil or map == self.hdCoatMapped then
        return
    end
    self.hdCoatMapped = map
    HorseCoat.husbandries[self] = true
    for animalId, cluster in pairs(map) do
        local seed = HorseCoat.ensureSeed(cluster)
        if seed ~= nil then
            local node = getAnimalRootNode(self.husbandryId, animalId)
            if node ~= nil and node ~= 0 then
                HorseFoal.applyCoat(node, (HorseCoat.fromSeed(seed)))
            end
        end
    end
end

-- ===== telling it: the information screens =====
-- The info box of a horse (looking at it: on a pasture or a vehicle) and the animal screen's description of one of your own animals. The dealer's new animals are not clusters yet: what you buy is a surprise.
local function coatTitle()
    local text = g_i18n ~= nil and g_i18n.getText ~= nil and g_i18n:getText("hd_coat") or nil
    return (text ~= nil and text ~= "" and text ~= "Missing 'hd_coat' in l10n") and text or "Coat"
end

-- "blaze, socks, snowflake" for a horse cluster (it gets its seed now if it has none), nil for anything else
function HorseCoat.describeCluster(cluster)
    local seed = HorseCoat.ensureSeed(cluster)
    if seed == nil then
        return nil
    end
    local _, text = HorseCoat.fromSeed(seed)
    return text
end

function HorseCoat.showInfo(self, box)
    local text = HorseCoat.describeCluster(self)
    if text ~= nil then
        box:addLine(coatTitle(), text)
    end
end

function HorseCoat.itemDescription(self, superFunc)
    local description = superFunc(self)
    local text = HorseCoat.describeCluster(self.cluster)
    if text == nil then
        return description
    end
    return string.format("%s\n\n%s: %s", description or "", coatTitle(), text)
end

-- ===== the parameters get lost: alt-tab (the window out of focus and back) made the spots disappear, the engine rebuilds its materials and what Lua set per node is gone. So the looks are put on again, slowly:
-- every REAPPLY_MS, at most PER_TICK horses a frame (a horse costs a few native calls over its node tree), the horse vehicles and the pasture animals within REAPPLY_RANGE_M of the player.
HorseCoat.REAPPLY = false                  -- OFF (2026-11-12): the slow round and the burst for new horses were built for what the broken mip levels of the masks caused (texture streaming shows the smallest levels first, after an alt-tab or on a new horse, and those had the markings crushed: it looked like lost parameters); hdCoat reapply on|off to check
HorseCoat.REAPPLY_MS = 2000
HorseCoat.PER_TICK = 2
HorseCoat.REAPPLY_RANGE_M = 120
HorseCoat.FRESH_MS = 2000                  -- a horse vehicle that has just appeared (you jumped on it, you led it out) is put on again every FRESH_TICK_MS for this long: what is set at its creation does not always stick,
HorseCoat.FRESH_TICK_MS = 100               -- and waiting for the next slow round showed it without its spots for two seconds
HorseCoat.fresh = setmetatable({}, { __mode = "k" })
HorseCoat.queue = {}
HorseCoat.nextRound = 0
HorseCoat.husbandries = setmetatable({}, { __mode = "k" })

function HorseCoat.collect()
    local list = {}
    local px, pz                                              -- (not `a and f() or nil`: that keeps only the first return value)
    if HorseLead ~= nil and HorseLead.playerPosition ~= nil then
        local x, _, z = HorseLead.playerPosition()
        px, pz = x, z
    end
    local function near(x, z) return px == nil or (x - px) ^ 2 + (z - pz) ^ 2 < HorseCoat.REAPPLY_RANGE_M ^ 2 end
    if HorseLead ~= nil and HorseLead.rideables ~= nil then
        for _, vehicle in ipairs(HorseLead.rideables()) do
            if not vehicle.isDeleted and vehicle.rootNode ~= nil and vehicle.spec_rideable ~= nil and vehicle.spec_rideable.meshNode ~= nil and vehicle.horseCoat ~= nil then
                local x, _, z = getWorldTranslation(vehicle.rootNode)
                if near(x, z) then list[#list + 1] = { node = vehicle.spec_rideable.meshNode, coat = vehicle.horseCoat } end
            end
        end
    end
    for husbandry in pairs(HorseCoat.husbandries) do
        for animalId, cluster in pairs(husbandry.animalIdToCluster or {}) do
            local seed = isHorseCluster(cluster) and cluster.hdCoatSeed or nil
            local ok, node = pcall(getAnimalRootNode, husbandry.husbandryId, animalId)
            if seed ~= nil and ok and node ~= nil and node ~= 0 then
                local x, _, z = getWorldTranslation(node)
                if near(x, z) then list[#list + 1] = { node = node, coat = (HorseCoat.fromSeed(seed)) } end
            end
        end
    end
    return list
end

function HorseCoat.update(dt)
    if not HorseCoat.REAPPLY or HorseFoal == nil or HorseFoal.applyCoat == nil then
        return
    end
    for vehicle, state in pairs(HorseCoat.fresh) do
        state.left, state.tick = state.left - dt, state.tick - dt
        if state.left <= 0 or vehicle.isDeleted then
            HorseCoat.fresh[vehicle] = nil
        elseif state.tick <= 0 then
            state.tick = HorseCoat.FRESH_TICK_MS
            local spec = vehicle.spec_rideable
            if spec ~= nil and spec.meshNode ~= nil and vehicle.horseCoat ~= nil and (entityExists == nil or entityExists(spec.meshNode)) then
                pcall(HorseFoal.applyCoat, spec.meshNode, vehicle.horseCoat)
            end
        end
    end
    HorseCoat.nextRound = HorseCoat.nextRound - dt
    if #HorseCoat.queue == 0 and HorseCoat.nextRound <= 0 then
        HorseCoat.queue = HorseCoat.collect()
        HorseCoat.nextRound = HorseCoat.REAPPLY_MS
    end
    for _ = 1, HorseCoat.PER_TICK do
        local item = table.remove(HorseCoat.queue)
        if item == nil then break end
        if entityExists == nil or entityExists(item.node) then
            pcall(HorseFoal.applyCoat, item.node, item.coat)
        end
    end
end

-- hdCoat probe: what each shape of the nearest horse says about our parameters (do the lower detail meshes have them?)
function HorseCoat.probe(vehicle)
    local meshNode = vehicle.spec_rideable ~= nil and vehicle.spec_rideable.meshNode or nil
    if meshNode == nil then return "no mesh node" end
    local lines = {}
    local function walk(node, depth)
        local isShape = getHasClassId ~= nil and ClassIds ~= nil and getHasClassId(node, ClassIds.SHAPE)
        if isShape then
            local ok, a, b, c, d = pcall(getShaderParameter, node, "flecks")
            local ok2, m1, m2, m3, m4 = pcall(getShaderParameter, node, "marks")
            lines[#lines + 1] = string.format("%s%s: flecks %s, marks %s", string.rep("  ", depth), getName(node), ok and string.format("%.2f %.2f %.2f %.2f", a or -1, b or -1, c or -1, d or -1) or "no parameter", ok2 and string.format("%.2f %.2f %.2f %.2f", m1 or -1, m2 or -1, m3 or -1, m4 or -1) or "no parameter")
        end
        if depth < 8 then
            for i = 0, getNumOfChildren(node) - 1 do walk(getChildAt(node, i), depth + 1) end
        end
    end
    walk(meshNode, 0)
    print("[HorseCoat] probe:\n" .. table.concat(lines, "\n"))
    return string.format("%d shapes probed (see the log)", #lines)
end

if HorseCoat.hooked == nil and Utils ~= nil and Utils.overwrittenFunction ~= nil then
    HorseCoat.hooked = true
    if AnimalClusterHorse ~= nil then
        AnimalClusterHorse.saveToXMLFile = Utils.appendedFunction(AnimalClusterHorse.saveToXMLFile, HorseCoat.save)
        AnimalClusterHorse.loadFromXMLFile = Utils.overwrittenFunction(AnimalClusterHorse.loadFromXMLFile, HorseCoat.load)
        AnimalClusterHorse.writeStream = Utils.appendedFunction(AnimalClusterHorse.writeStream, HorseCoat.write)
        AnimalClusterHorse.readStream = Utils.appendedFunction(AnimalClusterHorse.readStream, HorseCoat.read)
        AnimalClusterHorse.clone = Utils.overwrittenFunction(AnimalClusterHorse.clone, HorseCoat.clone)
    end
    if AnimalClusterHorse ~= nil and AnimalClusterHorse.showInfo ~= nil then
        AnimalClusterHorse.showInfo = Utils.appendedFunction(AnimalClusterHorse.showInfo, HorseCoat.showInfo)
    end
    if AnimalItemStock ~= nil and AnimalItemStock.getDescription ~= nil then
        AnimalItemStock.getDescription = Utils.overwrittenFunction(AnimalItemStock.getDescription, HorseCoat.itemDescription)
    end
    if AnimalSystem ~= nil and AnimalSystem.createClusterFromSubTypeIndex ~= nil then          -- (a horse of the dealer or a newborn has its seed from the start)
        AnimalSystem.createClusterFromSubTypeIndex = Utils.overwrittenFunction(AnimalSystem.createClusterFromSubTypeIndex, function(self, superFunc, ...)
            local cluster = superFunc(self, ...)
            HorseCoat.ensureSeed(cluster)
            return cluster
        end)
    end
    if Rideable ~= nil and Rideable.setCluster ~= nil then
        Rideable.setCluster = Utils.appendedFunction(Rideable.setCluster, function(vehicle) HorseCoat.applyVehicle(vehicle) end)
    end
    if addModEventListener ~= nil then
        addModEventListener({ update = function(_, dt) HorseCoat.update(dt) end })
    end
    if AnimalClusterHusbandry ~= nil and AnimalClusterHusbandry.updateVisuals ~= nil then
        AnimalClusterHusbandry.updateVisuals = Utils.appendedFunction(AnimalClusterHusbandry.updateVisuals, HorseCoat.applyHusbandry)
    end
end
