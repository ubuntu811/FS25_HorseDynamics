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
