-- Foals in the game: horses under HorseFoal.ADULT_AGE months use the baked foal model (animal dealer, pastures); they are led but never mounted; older ones the normal horse.
HorseFoal = {}
HorseFoal.dir = g_currentModDirectory
HorseFoal.ADULT_AGE = 12            -- months: from here on the game's own horse is shown
-- animals.xml entry -> coat name (the game's store_horse<Coat> pictures; atlas tiles 0:0 .. 3:1 in this order)
HorseFoal.COATS = { "Gray", "Pinto", "Palomino", "Chestnut", "Bay", "Black", "SealBrown", "Dun" }
HorseFoal.NUM_COATS = 8             -- animals.xml holds the 8 adult coats, then the same 8 as foals

function HorseFoal.prepareConfig(animalSystem, animalType, baseDirectory)
    if animalType == nil or animalType.name ~= "HORSE" then return end
    local rel = HorseFoal.dir:gsub("\\", "/"):gsub("/$", "")          -- absolute: the engine loads the mods' own files that way
    Logging.info("[HorseFoal] baseDirectory %q, model path %s/models/foal/horseFoal.i3d (exists: %s)", tostring(baseDirectory), rel, tostring(fileExists(rel .. "/models/foal/horseFoal.i3d")))
    local xml = XMLFile.load("horseFoalAnimals", HorseFoal.dir .. "xml/foalAnimals.xml")
    if xml == nil then return end
    local n = 0
    for i = HorseFoal.NUM_COATS, 2 * HorseFoal.NUM_COATS - 1 do
        local key = string.format("animalHusbandry.animals.animal(%d).assets", i)
        xml:setString(key .. "#filename", rel .. "/models/foal/horseFoal.i3d")
        xml:setString(key .. "#animation", rel .. "/models/foal/horseFoal.i3d")
        n = n + 1
    end
    local outDir = getUserProfileAppPath() .. "modSettings/FS25_HorseDynamics/"
    createFolder(getUserProfileAppPath() .. "modSettings/")
    createFolder(outDir)
    xml:saveTo(outDir .. "animals.xml", false)
    xml:delete()
    animalType.configFilename = outDir .. "animals.xml"
    HorseFoal.configured = true
    Logging.info("[HorseFoal] horse config with %d foal animals written to %s", n, animalType.configFilename)
end

local function copyVisual(v) local c = {} for k, val in pairs(v) do c[k] = val end return c end

-- visuals: age 0 = foal, from ADULT_AGE the original adult entry
function HorseFoal.patchVisuals(animalSystem)
    if not HorseFoal.configured then return end
    local animalType = animalSystem:getTypeByName("HORSE")
    if animalType == nil or #animalType.animals < 2 * HorseFoal.NUM_COATS then
        Logging.warning("[HorseFoal] horse config has %d animals, expected %d", animalType and #animalType.animals or 0, 2 * HorseFoal.NUM_COATS)
        return
    end
    local n = 0
    for _, subTypeIndex in ipairs(animalType.subTypes) do
        local subType = animalSystem:getSubTypeByIndex(subTypeIndex)
        local adult = subType.visuals[1]
        if adult ~= nil and adult.visualAnimalIndex <= HorseFoal.NUM_COATS then
            local foal = copyVisual(adult)
            foal.visualAnimalIndex = adult.visualAnimalIndex + HorseFoal.NUM_COATS
            foal.visualAnimal = animalType.animals[foal.visualAnimalIndex]
            foal.minAge = 0
            -- the shop / animal screen picture: the foal rendered in its coat (store/foal/store_foal<Coat>.dds), not the adult's icon
            local coat = HorseFoal.COATS[adult.visualAnimalIndex]
            if coat ~= nil and adult.store ~= nil then
                foal.store = copyVisual(adult.store)
                foal.store.imageFilename = HorseFoal.dir .. "store/foal/store_foal" .. coat .. ".dds"
            end
            local grown = copyVisual(adult)
            grown.minAge = HorseFoal.ADULT_AGE
            subType.visuals = { foal, grown }
            n = n + 1
        end
    end
    Logging.info("[HorseFoal] %d horse subtypes: foal visual from 0 months, adult from %d months", n, HorseFoal.ADULT_AGE)
end

local function isFoalCluster(cluster)
    return cluster ~= nil and cluster.age ~= nil and cluster.age < HorseFoal.ADULT_AGE
end

-- a foal under ADULT_AGE becomes the foal vehicle (xml/horseFoal.xml: led, steered, towed by script like any horse) but nobody mounts it
function HorseFoal.getRidableFilename(cluster, superFunc)
    local filename = superFunc(cluster)
    if filename ~= nil and isFoalCluster(cluster) and string.find(filename, "horse/horse.xml", 1, true) ~= nil then
        return HorseFoal.dir .. "xml/horseFoal.xml"
    end
    return filename
end

-- no "ride" prompt on a pasture foal
function HorseFoal.getAnimalSupportsRiding(placeable, superFunc, clusterId)
    local cluster = placeable.spec_husbandryAnimals.clusterSystem:getClusterById(clusterId)
    if isFoalCluster(cluster) then return false end
    return superFunc(placeable, clusterId)
end

-- every way a player gets onto a vehicle (E, tab, map, force) ends here: not onto a foal
function HorseFoal.requestToEnterVehicle(player, superFunc, vehicle, force)
    local cluster = vehicle ~= nil and vehicle.getCluster ~= nil and vehicle:getCluster() or nil
    if isFoalCluster(cluster) then return end
    return superFunc(player, vehicle, force)
end

-- and no "enter" prompt next to a foal vehicle
function HorseFoal.hideEnterPrompt(vehicle)
    if vehicle.horseFoalPromptHidden then return end
    vehicle.horseFoalPromptHidden = true
    local orig = vehicle.getIsInteractive
    vehicle.getIsInteractive = function(self, ...)
        if isFoalCluster(self:getCluster()) then return false end
        return orig(self, ...)
    end
end

-- The foal's bone regions against the adult's, per axis of the bone, about the bone's origin: the least-squares fit of the baked horseFoal.i3d.shapes to horse.i3d.shapes, in each bone's own space
-- (vertices with weight above 0.3 on the bone; fit errors 1 to 2 cm; Favorite 6 (the user's tuned link): overall size 0.65, a nose-only cut; the head fit is a compromise between crown and muzzle). Re-measure after a re-bake with another shape.
-- Gear built for the adult (HorseDynamics' halter and harness) scales its points with these.
HorseFoal.BONE_SCALE = {          -- Favorite 8 = 7 with leg length 0.9, same chain scales (the app's per-bone scales chained to the adult, as measured for Favorite 6, scaled by the change)
    Head_M = { 0.560, 0.513, 0.625 },
    Chest_M = { 0.582, 0.613, 0.583 },
    Spine1_M = { 0.593, 0.593, 0.587 },
    RootPart1_M = { 0.664, 0.603, 0.595 },
    Root_M = { 0.618, 0.673, 0.615 },
}

-- published for other mods (mod globals are invisible across mods): g_currentMission.horseFoal.getBoneScale(vehicle, boneName) -> x, y, z for a foal, nothing for any other horse or bone
local function publish()
    if g_currentMission == nil then return end
    g_currentMission.horseFoal = {
        adultAge = HorseFoal.ADULT_AGE,
        isFoal = function(vehicle) return vehicle ~= nil and vehicle.getCluster ~= nil and isFoalCluster(vehicle:getCluster()) end,
        getBoneScale = function(vehicle, boneName)
            local scale = HorseFoal.BONE_SCALE[boneName]
            if scale ~= nil and vehicle ~= nil and vehicle.getCluster ~= nil and isFoalCluster(vehicle:getCluster()) then
                return scale[1], scale[2], scale[3]
            end
        end,
    }
end

AnimalSystem.loadAnimalConfig = Utils.prependedFunction(AnimalSystem.loadAnimalConfig, HorseFoal.prepareConfig)
AnimalSystem.loadAnimals = Utils.appendedFunction(AnimalSystem.loadAnimals, HorseFoal.patchVisuals)
AnimalCluster.getRidableFilename = Utils.overwrittenFunction(AnimalCluster.getRidableFilename, HorseFoal.getRidableFilename)
PlaceableHusbandryAnimals.getAnimalSupportsRiding = Utils.overwrittenFunction(PlaceableHusbandryAnimals.getAnimalSupportsRiding, HorseFoal.getAnimalSupportsRiding)
Player.requestToEnterVehicle = Utils.overwrittenFunction(Player.requestToEnterVehicle, HorseFoal.requestToEnterVehicle)
Rideable.setCluster = Utils.appendedFunction(Rideable.setCluster, function(vehicle, ...)
    if g_currentMission ~= nil and g_currentMission.horseFoal == nil then publish() end
    HorseFoal.hideEnterPrompt(vehicle)
    local ok, cluster = pcall(vehicle.getCluster, vehicle)
    if ok and isFoalCluster(cluster) and not vehicle.horseFoalLogged then        -- (one line per foal vehicle: a foal that was saved out of its pasture is, or is not, back in the world after a restart)
        vehicle.horseFoalLogged = true
        local x, y, z = getWorldTranslation(vehicle.rootNode)
        local ground = g_terrainNode ~= nil and getTerrainHeightAtWorldPos(g_terrainNode, x, 0, z) or y
        print(string.format("[HorseFoal] foal vehicle %s (%d months) is in the world at %.0f %.0f, %.2f m %s the terrain", tostring(cluster.name), cluster.getAge ~= nil and cluster:getAge() or -1, x, z, math.abs(y - ground), y >= ground and "above" or "BELOW"))
    end
end)

-- ===== the map: a foal cannot be ridden, so its popup says Visit and takes you next to it =====
HorseFoal.VISIT_RADII = { 2.5, 3.5, 5.0, 7.0 }        -- m from the foal, tried in this order
HorseFoal.VISIT_CLEAR_M = 0.7                           -- the spot is free when nothing solid is within this of a standing player's middle

-- The first free spot round (fx, fz), nearest ring first, starting at the foal's left side: isFree(x, z) and groundAt(x, z) are the engine's (injected: the tests use fakes). Falls back to the first spot.
function HorseFoal.pickVisitSpot(fx, fz, heading, isFree, groundAt)
    local first
    for _, r in ipairs(HorseFoal.VISIT_RADII) do
        for k = 0, 11 do
            local a = heading + math.pi / 2 + k * math.pi / 6
            local x, z = fx + math.sin(a) * r, fz + math.cos(a) * r
            first = first or { x, groundAt(x, z), z }
            if isFree(x, z) then
                return x, groundAt(x, z), z
            end
        end
    end
    return first[1], first[2], first[3]
end

local solidHits
function HorseFoal.onSolid(_, nodeId)
    solidHits = (solidHits or 0) + 1
    return true
end

local function visitSpotFree(x, z)
    local y = getTerrainHeightAtWorldPos(g_terrainNode, x, 0, z)
    solidHits = 0
    local mask = CollisionFlag.STATIC_OBJECT + CollisionFlag.BUILDING + CollisionFlag.TREE + CollisionFlag.VEHICLE + CollisionFlag.DYNAMIC_OBJECT + CollisionFlag.WATER
    overlapSphere(x, y + 1.0, z, HorseFoal.VISIT_CLEAR_M, "onSolid", HorseFoal, mask, true, true, false, true)
    return solidHits == 0
end

-- Takes the player to a free spot next to the foal vehicle (leaving the vehicle they are in).
function HorseFoal.visit(vehicle)
    local fx, _, fz = getWorldTranslation(vehicle.rootNode)
    local dx, _, dz = localDirectionToWorld(vehicle.rootNode, 0, 0, 1)
    local x, y, z = HorseFoal.pickVisitSpot(fx, fz, math.atan2(dx, dz), visitSpotFree, function(px, pz) return getTerrainHeightAtWorldPos(g_terrainNode, px, 0, pz) end)
    if g_localPlayer:getCurrentVehicle() ~= nil then
        g_localPlayer:leaveVehicle()
    end
    g_localPlayer:teleportTo(x, y, z)
end

local function foalOfHotspot(frame)
    local vehicle = InGameMenuMapUtil ~= nil and frame.currentHotspot ~= nil and InGameMenuMapUtil.getHotspotVehicle(frame.currentHotspot) or nil
    if vehicle ~= nil and vehicle.getCluster ~= nil and isFoalCluster(vehicle:getCluster()) then
        return vehicle
    end
    return nil
end

if InGameMenuMapFrame ~= nil and InGameMenuMapFrame.onClickEnterVehicle ~= nil and not HorseFoal.mapHooked then
    HorseFoal.mapHooked = true
    local function asVisit(frame)
        if frame.contextActions ~= nil and frame.contextActions[InGameMenuMapFrame.ACTIONS.ENTER_VEHICLE] ~= nil then
            frame.contextActions[InGameMenuMapFrame.ACTIONS.ENTER_VEHICLE].text = "action_visit"
        end
    end
    -- the popup of a foal offers the button, called Visit (the game's own text), instead of Ride
    InGameMenuMapFrame.setMapInputContext = Utils.overwrittenFunction(InGameMenuMapFrame.setMapInputContext, function(self, superFunc, canEnter, ...)
        if foalOfHotspot(self) ~= nil then
            canEnter = true
            asVisit(self)
        end
        return superFunc(self, canEnter, ...)
    end)
    InGameMenuMapFrame.setAIInputContext = Utils.overwrittenFunction(InGameMenuMapFrame.setAIInputContext, function(self, superFunc, canGoTo, canCreateJob, canCancel, canSkipTask, canEnter, ...)
        if foalOfHotspot(self) ~= nil then
            canEnter = true
            asVisit(self)
        end
        return superFunc(self, canGoTo, canCreateJob, canCancel, canSkipTask, canEnter, ...)
    end)
    InGameMenuMapFrame.onClickEnterVehicle = Utils.overwrittenFunction(InGameMenuMapFrame.onClickEnterVehicle, function(self, superFunc, ...)
        local foal = foalOfHotspot(self)
        if foal ~= nil and not g_currentMission.isPlayerFrozen then
            self.onClickBackCallback()
            local ok, err = pcall(HorseFoal.visit, foal)
            if not ok then
                print("[HorseFoal] visit: " .. tostring(err))
            end
            return true
        end
        return superFunc(self, ...)
    end)
end

-- ===== coat shader experiment (shaders/foalCoatShader.xml, see dev/foal/ABOUT.md): per-foal settings on the foal vehicles =====
--   hdCoat tint r g b          colour multiplying the COAT (not eyes, mouth, hooves)      hdCoat 0.6 0.6 0.6 is the same as hdCoat tint 0.6 0.6 0.6
--   hdCoat shade b [s]         brightness and saturation of the coat (1 1 = as it is)
--   hdCoat gloss g             glossy eyeballs, 0..1
--   hdCoat pattern a [r g b]   the pattern layer (the Pinto patches so far): strength 0..1 and its colour (white)
--   hdCoat reset               everything back
-- each acts on the nearest foal vehicle within 30 m; add "all" at the end for every foal vehicle.
HorseFoal.COAT_DEFAULT = { tint = { 1, 1, 1 }, shade = { 1, 1 }, gloss = 0, pattern = { 0, 1, 1, 1 } }
local function coatApply(vehicle, c)
    local node = vehicle.spec_rideable.meshNode
    I3DUtil.setShaderParameterRec(node, "coatTint", c.tint[1], c.tint[2], c.tint[3], 1)
    I3DUtil.setShaderParameterRec(node, "coatShade", c.shade[1], c.shade[2], 0, c.gloss)
    I3DUtil.setShaderParameterRec(node, "patternA", c.pattern[2], c.pattern[3], c.pattern[4], c.pattern[1])
end

function HorseFoal.consoleCoat(_, ...)
    local args = { ... }
    local all = args[#args] == "all"
    if all then table.remove(args) end
    local what = args[1]
    if tonumber(what) ~= nil then table.insert(args, 1, "tint"); what = "tint" end
    local n = function(i, default) return tonumber(args[i]) or default end
    local targets, px, _, pz = {}, HorseLead.playerPosition()
    local bestD, best = math.huge, nil
    for _, vehicle in ipairs(HorseLead.rideables()) do
        local ok, cluster = pcall(vehicle.getCluster, vehicle)
        if ok and isFoalCluster(cluster) and vehicle.spec_rideable.meshNode ~= nil then
            if all then
                targets[#targets + 1] = vehicle
            elseif px ~= nil then
                local x, _, z = getWorldTranslation(vehicle.rootNode)
                local d = math.sqrt((x - px) ^ 2 + (z - pz) ^ 2)
                if d < bestD then best, bestD = vehicle, d end
            end
        end
    end
    if best ~= nil and bestD < 30 then targets[1] = best end
    if #targets == 0 then
        return "no foal vehicle near you (lead one out of its pasture first; add 'all' for every foal)"
    end
    if what == nil then
        return "hdCoat tint r g b | shade b [s] | gloss g | pattern a [r g b] | reset   (+ 'all')"
    end
    for _, vehicle in ipairs(targets) do
        local c = vehicle.horseCoat or { tint = { 1, 1, 1 }, shade = { 1, 1 }, gloss = 0, pattern = { 0, 1, 1, 1 } }
        if what == "tint" then c.tint = { n(2, 1), n(3, n(2, 1)), n(4, n(2, 1)) }
        elseif what == "shade" then c.shade = { n(2, 1), n(3, 1) }
        elseif what == "gloss" then c.gloss = n(2, 0)
        elseif what == "pattern" then c.pattern = { n(2, 1), n(3, 1), n(4, 1), n(5, 1) }
        elseif what == "reset" then c = { tint = { 1, 1, 1 }, shade = { 1, 1 }, gloss = 0, pattern = { 0, 1, 1, 1 } }
        else return "unknown: " .. tostring(what) end
        vehicle.horseCoat = c
        coatApply(vehicle, c)
    end
    return string.format("hdCoat %s on %d foal(s)", what, #targets)
end
if addConsoleCommand ~= nil then
    addConsoleCommand("hdCoat", "HorseDynamics: coat shader experiment on foal vehicles: tint r g b | shade b [s] | gloss g | pattern a [r g b] | reset  [all]", "consoleCoat", HorseFoal)
end
