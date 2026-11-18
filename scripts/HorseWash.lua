--[[
    HorseWash.lua -- horses can be washed: the car wash (WashingStation) and the pressure washer (HandToolHPWLance) only take vehicles that answer getAllowsWashingByType and then call getDirtAmount / cleanVehicle /
    getWashDuration (the Washable specialization, which the horse vehicle type does not have). A horse's dirt is its animal's own (cluster.dirt, 0..100; Rideable:updateDirt draws it), so those four are given to
    every horse here and speak for the cluster. Whole points only (changeDirt floors), the rest is carried over to the next call.
]]
HorseWash = {}
HorseWash.WASH_MS = 30000                 -- a filthy horse is clean after this long under the washer

local function enabled()
    return Platform ~= nil and Platform.gameplay ~= nil and Platform.gameplay.needHorseCleaning == true
end

local function clusterOf(horse)
    local ok, cluster = pcall(horse.getCluster, horse)
    if ok and cluster ~= nil and cluster.getDirtFactor ~= nil and cluster.changeDirt ~= nil then
        return cluster
    end
    return nil
end

function HorseWash.getAllowsWashingByType(_, kind)
    if Washable ~= nil and kind == Washable.WASHTYPE_RAIN then
        return false                      -- (the animal system makes it dirty; rain is not drawn on it)
    end
    return enabled()
end

function HorseWash.getDirtAmount(self)
    local cluster = enabled() and clusterOf(self) or nil
    return cluster ~= nil and cluster:getDirtFactor() or 0
end

function HorseWash.getWashDuration(_)
    return HorseWash.WASH_MS
end

-- amount: the part of a full wash done this tick (1 = all the dirt).
function HorseWash.cleanVehicle(self, amount)
    local cluster = clusterOf(self)
    if cluster == nil or amount == nil or amount <= 0 then
        return
    end
    local now = g_time or 0
    if now - (self.horseWashLogAt or -1e9) > 2000 then              -- (one line per 2 s: what the washer asks for and what is left)
        self.horseWashLogAt = now
        print(string.format("[HorseDynamics] wash: dirt %d, asked %.4f of a full wash this call", cluster.dirt or -1, amount))
    end
    self.horseWashCarry = (self.horseWashCarry or 0) + amount * 100
    local whole = math.floor(self.horseWashCarry)
    if whole >= 1 then
        self.horseWashCarry = self.horseWashCarry - whole
        cluster:changeDirt(-whole)
        if self.updateDirt ~= nil then
            self:updateDirt()
        end
    end
end

-- Riding makes a horse dirty: the game adds 1 dirt each time its riding timer runs out (Rideable:updateRiding: 5 minutes / 100 = every 3 s at a walk or trot, 1.5 s at a canter, 1 s at a gallop), so a horse
-- is filthy after 5 minutes of walking. Only that gain is scaled here (the +10 a day, washing and everything else are the game's own); whole points only, the rest carried on the cluster.
HorseWash.RIDING_DIRT_SCALE = 0.2             -- 1 = the game's speed; 0.2: filthy after 25 minutes of walking (8 of galloping); 0 = riding no longer dirties
HorseWash.ridingNow = false                   -- true inside Rideable:updateRiding

-- carry + delta x scale -> (whole points to add now, the carry that is left). Pure.
function HorseWash.scaledDirt(carry, delta, scale)
    carry = carry + delta * scale
    local whole = math.floor(carry + 1e-9)
    return whole, carry - whole
end

function HorseWash.changeDirt(cluster, superFunc, delta)
    if HorseWash.ridingNow and delta == 1 and HorseWash.RIDING_DIRT_SCALE < 1 then
        local whole, carry = HorseWash.scaledDirt(cluster.hdDirtCarry or 0, delta, HorseWash.RIDING_DIRT_SCALE)
        cluster.hdDirtCarry = carry
        if whole > 0 then
            return superFunc(cluster, whole)
        end
        return
    end
    return superFunc(cluster, delta)
end

function HorseWash.updateRiding(self, superFunc, dt)
    HorseWash.ridingNow = true
    local ok, err = pcall(superFunc, self, dt)
    HorseWash.ridingNow = false
    if not ok then
        error(err, 0)
    end
end

function HorseWash.consoleDirt(_, scale)
    if tonumber(scale) ~= nil then
        HorseWash.RIDING_DIRT_SCALE = math.max(0, math.min(1, tonumber(scale)))
    end
    return string.format("riding dirties a horse at %.2f x the game's speed (hdDirt 1 = the game's, 0.2 = the default, 0 = never)", HorseWash.RIDING_DIRT_SCALE)
end

function HorseWash.install(horse)
    horse.getAllowsWashingByType = HorseWash.getAllowsWashingByType
    horse.getDirtAmount = HorseWash.getDirtAmount
    horse.getWashDuration = HorseWash.getWashDuration
    horse.cleanVehicle = HorseWash.cleanVehicle
    if horse.typeDesc == nil then
        horse.typeDesc = "Horse"                -- (the pressure washer prints the name of what it hits with string.format: nil would be an error)
    end
end

if Rideable ~= nil and Rideable.onLoad ~= nil and Utils ~= nil and Utils.appendedFunction ~= nil and not HorseWash.hooked then
    HorseWash.hooked = true
    Rideable.onLoad = Utils.appendedFunction(Rideable.onLoad, function(self)
        HorseWash.install(self)
    end)
end

if AnimalClusterHorse ~= nil and AnimalClusterHorse.changeDirt ~= nil and Utils ~= nil and Utils.overwrittenFunction ~= nil and not HorseWash.dirtHooked then
    HorseWash.dirtHooked = true
    AnimalClusterHorse.changeDirt = Utils.overwrittenFunction(AnimalClusterHorse.changeDirt, HorseWash.changeDirt)
    Rideable.updateRiding = Utils.overwrittenFunction(Rideable.updateRiding, HorseWash.updateRiding)
end
if addConsoleCommand ~= nil then
    addConsoleCommand("hdDirt", "HorseDynamics: how fast riding makes a horse dirty: hdDirt [0..1] (1 = the game's speed, default 0.2)", "consoleDirt", HorseWash)
end
