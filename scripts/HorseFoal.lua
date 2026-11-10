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
    Logging.info("[HorseFoal] baseDirectory %q, model path %s/model/horseFoal.i3d (exists: %s)", tostring(baseDirectory), rel, tostring(fileExists(rel .. "/model/horseFoal.i3d")))
    local xml = XMLFile.load("horseFoalAnimals", HorseFoal.dir .. "animals.xml")
    if xml == nil then return end
    local n = 0
    for i = HorseFoal.NUM_COATS, 2 * HorseFoal.NUM_COATS - 1 do
        local key = string.format("animalHusbandry.animals.animal(%d).assets", i)
        xml:setString(key .. "#filename", rel .. "/model/horseFoal.i3d")
        xml:setString(key .. "#animation", rel .. "/model/horseFoal.i3d")
        n = n + 1
    end
    local outDir = getUserProfileAppPath() .. "modSettings/FS25_HorseFoalMod/"
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
            -- the shop / animal screen picture: the foal rendered in its coat (icons/store_foal<Coat>.dds), not the adult's icon
            local coat = HorseFoal.COATS[adult.visualAnimalIndex]
            if coat ~= nil and adult.store ~= nil then
                foal.store = copyVisual(adult.store)
                foal.store.imageFilename = HorseFoal.dir .. "icons/store_foal" .. coat .. ".dds"
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

-- a foal under ADULT_AGE becomes the foal vehicle (horseFoal.xml: led, steered, towed by script like any horse) but nobody mounts it
function HorseFoal.getRidableFilename(cluster, superFunc)
    local filename = superFunc(cluster)
    if filename ~= nil and isFoalCluster(cluster) and string.find(filename, "horse/horse.xml", 1, true) ~= nil then
        return HorseFoal.dir .. "horseFoal.xml"
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
-- (vertices with weight above 0.3 on the bone; fit errors 1 to 2 cm; Favorite 3: overall size 0.65, the head 0.55 to 0.63 of the adult's). Re-measure after a re-bake with another shape.
-- Gear built for the adult (HorseDynamics' halter and harness) scales its points with these.
HorseFoal.BONE_SCALE = {
    Head_M = { 0.551, 0.629, 0.625 },
    Chest_M = { 0.517, 0.545, 0.518 },
    Spine1_M = { 0.527, 0.527, 0.522 },
    RootPart1_M = { 0.598, 0.537, 0.528 },
    Root_M = { 0.536, 0.590, 0.534 },
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
end)
