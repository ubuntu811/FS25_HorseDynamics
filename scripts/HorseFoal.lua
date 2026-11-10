-- Foals in the game: horses under HorseFoal.ADULT_AGE months use the baked foal model (animal dealer, pastures); they are led but never mounted; older ones the normal horse.
HorseFoal = {}
HorseFoal.dir = g_currentModDirectory
HorseFoal.ADULT_AGE = 12            -- months: from here on the game's own horse is shown
HorseFoal.NUM_COATS = 8             -- animals.xml holds the 8 adult coats, then the same 8 as foals

-- game base path -> mod directory as a "$" path (the game resolves "$x" as <game folder>x, in Lua and in the animal config alike)
local function relativeToGame(path)
    local function split(p) local t = {} for part in string.gmatch((p:gsub("\\", "/")), "[^/]+") do t[#t + 1] = part end return t end
    local base = (g_gameBasePath ~= nil and g_gameBasePath ~= "") and g_gameBasePath or getAppBasePath()   -- g_gameBasePath is empty: the game runs from its own folder
    Logging.info("[HorseFoal] game folder %s, mod folder %s", tostring(base), tostring(path))
    local g, m = split(base), split(path)
    local n = 0
    while n < #g and n < #m and string.lower(g[n + 1]) == string.lower(m[n + 1]) do n = n + 1 end
    if n == 0 then return nil end
    local parts = {}
    for _ = n + 1, #g do parts[#parts + 1] = ".." end
    for i = n + 1, #m do parts[#parts + 1] = m[i] end
    return "$" .. table.concat(parts, "/")
end

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

-- The foal head against the adult's, per axis of the Head_M bone (x up, y along the face, z sideways), about the bone's origin: measured on the baked horseFoal.i3d.shapes against horse.i3d.shapes (776 head
-- vertices, fit error under 1 cm). Re-measure after a re-bake with another head. Gear built for the adult head (HorseDynamics' halter) scales its points with this.
HorseFoal.HEAD_SCALE = { 0.387, 0.384, 0.562 }

-- published for other mods (mod globals are invisible across mods): g_currentMission.horseFoal.getHeadScale(vehicle) -> x, y, z of a foal's head, nothing for any other horse
local function publish()
    if g_currentMission == nil then return end
    g_currentMission.horseFoal = {
        adultAge = HorseFoal.ADULT_AGE,
        isFoal = function(vehicle) return vehicle ~= nil and vehicle.getCluster ~= nil and isFoalCluster(vehicle:getCluster()) end,
        getHeadScale = function(vehicle)
            if vehicle ~= nil and vehicle.getCluster ~= nil and isFoalCluster(vehicle:getCluster()) then
                return HorseFoal.HEAD_SCALE[1], HorseFoal.HEAD_SCALE[2], HorseFoal.HEAD_SCALE[3]
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

-- diagnostics: what the husbandry asks the engine for (cluster age / visual index, add / swap / remove calls)
local function wrapGlobal(name)
    local orig = _G[name]
    if orig == nil then return end
    _G[name] = function(...)
        local a = { ... }
        local parts = {}
        for i = 1, math.min(#a, 4) do parts[#parts + 1] = tostring(a[i]) end
        Logging.info("[HorseFoal] %s(%s)", name, table.concat(parts, ", "))
        return orig(...)
    end
end
for _, name in ipairs({ "addHusbandryAnimal", "setAnimalSubType", "removeHusbandryAnimal", "setAnimalTextureTile" }) do wrapGlobal(name) end

AnimalClusterHusbandry.updateVisuals = Utils.prependedFunction(AnimalClusterHusbandry.updateVisuals, function(self)
    for _, cluster in ipairs(self.nextUpdateClusters or {}) do
        local visual = cluster:getVisual()
        Logging.info("[HorseFoal] updateVisuals cluster %s subType %s age %s -> visual index %s (minAge %s)", tostring(cluster.id), tostring(cluster.subTypeIndex), tostring(cluster.age), tostring(visual and visual.visualAnimalIndex), tostring(visual and visual.minAge))
    end
end)
