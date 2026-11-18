--[[
    HorseTack.lua -- which pieces of the tack a horse wears: saddle, blanket, bridle (the three shapes under the model's saddle group, see dev/foal/ABOUT.md).
    cluster.hdTack: nil = the game's own behaviour (everything shown while ridden); a number 0..15 = the pieces worn (1 saddle, 2 blanket, 4 bridle, 8 bit), shown whether or not the horse is ridden.
    Saved with the animal like the coat seed (AnimalClusterHorse: save, load, streams, clone) and applied after every setEquipmentVisibility / setCluster of the vehicle.
]]
HorseTack = HorseTack or {}

-- the bridle (crown, browband, noseband, throatlatch) is worn with the bit and the cheek straps that carry it ("bit"), or without them as a halter: then the `halter` shape (one clean cheek strap per side and a chin ring) shows instead.
-- The game's default (nothing set) shows the whole bridle; `halter` stays hidden in the model until a horse has a wish of its own.
HorseTack.PIECES = { { name = "saddle", node = { "saddleSeat" }, bit = 1 }, { name = "blanket", node = { "blanket" }, bit = 2 }, { name = "bridle", node = { "bridle" }, bit = 4 }, { name = "bit", node = { "bit", "cheek" }, bit = 8 }, { name = "panel", node = { "panel" }, bit = 16 } }
HorseTack.ALL = 31
HorseTack.HALTER = 4        -- the bridle without its bit
HorseTack.BITS = 6          -- stream: 0 = the game's behaviour, else mask + 1

local function worn(mask, bit)
    return math.floor(mask / bit) % 2 == 1
end
HorseTack.worn = worn

local function childByName(group, name)
    for i = 0, getNumOfChildren(group) - 1 do
        local child = getChildAt(group, i)
        if getName(child) == name then
            return child
        end
    end
    return nil
end

local function clusterOf(vehicle)
    if vehicle == nil or vehicle.getCluster == nil then
        return nil
    end
    local ok, cluster = pcall(vehicle.getCluster, vehicle)
    if ok and HorseCoat ~= nil and HorseCoat.isHorseCluster(cluster) then
        return cluster
    end
    return nil
end

HorseTack.clusterOf = clusterOf
HorseTack.SADDLE_SET = { 1, 2, 16 }          -- what the loose saddle puts on a horse: the saddle, the pad, the panel under it

-- The loose saddle goes on this horse: the saddle, the pad and the panel are worn (a horse with the game's own behaviour gets all the tack, as when it is ridden). False when the horse has no cluster or no tack node.
function HorseTack.saddleOn(vehicle)
    local spec = vehicle ~= nil and vehicle.spec_rideable or nil
    local cluster = spec ~= nil and spec.equipmentNode ~= nil and clusterOf(vehicle) or nil
    if cluster == nil then
        return false
    end
    vehicle.hdSaddlePrev = cluster.hdTack == nil and -1 or cluster.hdTack
    local mask = cluster.hdTack or HorseTack.ALL
    for _, bit in ipairs(HorseTack.SADDLE_SET) do
        if not worn(mask, bit) then
            mask = mask + bit
        end
    end
    cluster.hdTack = mask
    HorseTack.apply(vehicle)
    return true
end

-- The saddle comes off: its pieces go, the rest stays; a horse that had no wish of its own gets the game's own behaviour back.
function HorseTack.saddleOff(vehicle)
    local cluster = clusterOf(vehicle)
    if cluster == nil then
        return false
    end
    local mask = cluster.hdTack or HorseTack.ALL
    for _, bit in ipairs(HorseTack.SADDLE_SET) do
        if worn(mask, bit) then
            mask = mask - bit
        end
    end
    local prev = vehicle.hdSaddlePrev
    vehicle.hdSaddlePrev = nil
    if prev == -1 then
        cluster.hdTack = nil
        local spec = vehicle.spec_rideable
        local group = spec ~= nil and spec.equipmentNode or nil
        if group ~= nil and (entityExists == nil or entityExists(group)) then
            for i = 0, getNumOfChildren(group) - 1 do
                setVisibility(getChildAt(group, i), getName(getChildAt(group, i)) ~= "halter")
            end
            local ridden = vehicle.getIsControlled ~= nil and vehicle:getIsControlled() or false
            if vehicle.setEquipmentVisibility ~= nil then
                pcall(vehicle.setEquipmentVisibility, vehicle, ridden)
            end
        end
        if vehicle.hdLed then
            cluster.hdTack = HorseTack.HALTER
            HorseTack.apply(vehicle)
        end
    else
        cluster.hdTack = mask
        HorseTack.apply(vehicle)
    end
    return true
end

-- Does this horse wear a removable piece of tack (an object put on with the hands: the saddle)? Such a horse is not given back to its pasture until it is taken off.
function HorseTack.hasRemovable(vehicle)
    return vehicle ~= nil and vehicle.hdSaddleItem ~= nil
end

-- True when the horse wears the saddle piece.
function HorseTack.wearsSaddle(vehicle)
    local cluster = clusterOf(vehicle)
    return cluster ~= nil and cluster.hdTack ~= nil and worn(cluster.hdTack, 1)
end

-- Shows the worn pieces of this vehicle. Nothing to do for a horse with no wish of its own.
-- The pieces a horse wears now: its own wish, or while it is led (vehicle.hdLed, set by HorseRope) at least the halter (the bridle without its bit).
function HorseTack.effectiveMask(vehicle, cluster)
    local mask = cluster ~= nil and cluster.hdTack or nil
    if vehicle ~= nil and vehicle.hdLed then
        mask = mask or HorseTack.HALTER
        if not worn(mask, 4) then
            mask = mask + 4
        end
    end
    return mask
end

function HorseTack.apply(vehicle)
    local spec = vehicle ~= nil and vehicle.spec_rideable or nil
    local group = spec ~= nil and spec.equipmentNode or nil
    local cluster = group ~= nil and clusterOf(vehicle) or nil
    local mask = cluster ~= nil and HorseTack.effectiveMask(vehicle, cluster) or nil
    if mask == nil then
        return
    end
    local bridle, bit = worn(mask, 4), worn(mask, 8)
    for _, piece in ipairs(HorseTack.PIECES) do
        local on = worn(mask, piece.bit)
        if piece.name == "bit" then
            on = on and bridle                          -- a bit without a bridle would float
        end
        for _, name in ipairs(piece.node) do
            local child = childByName(group, name)
            if child ~= nil then
                setVisibility(child, on)
            end
        end
    end
    local halter = childByName(group, "halter")
    if halter ~= nil then
        setVisibility(halter, bridle and not bit)
    end
    setVisibility(group, mask > 0)
end

-- True when this horse's model has the baked halter (our clone and the foal do; the game's own horse does not).
function HorseTack.bakedHalterAvailable(vehicle)
    local spec = vehicle ~= nil and vehicle.spec_rideable or nil
    local group = spec ~= nil and spec.equipmentNode or nil
    return group ~= nil and (entityExists == nil or entityExists(group)) and childByName(group, "halter") ~= nil
end

-- A horse that goes back into a pasture loses its tack wish (the pasture model wears nothing: when it is taken out again it starts with the game's own behaviour, not with what it wore last time).
function HorseTack.clearWish(vehicle)
    local cluster = clusterOf(vehicle)
    if cluster ~= nil then
        cluster.hdTack = nil
    end
    if vehicle ~= nil then
        vehicle.hdLed = nil
    end
end

-- A led horse wears the baked halter (on = true), a horse that is let go of in a pasture gets the game's own tack behaviour back (off).
function HorseTack.setLed(vehicle, on)
    if vehicle == nil or (vehicle.hdLed == true) == (on == true) then
        return
    end
    vehicle.hdLed = on and true or nil
    local cluster = clusterOf(vehicle)
    if on or (cluster ~= nil and cluster.hdTack ~= nil) then
        HorseTack.apply(vehicle)
        return
    end
    local spec = vehicle.spec_rideable
    local group = spec ~= nil and spec.equipmentNode or nil
    if group ~= nil and (entityExists == nil or entityExists(group)) then
        for i = 0, getNumOfChildren(group) - 1 do
            setVisibility(getChildAt(group, i), getName(getChildAt(group, i)) ~= "halter")
        end
        local ridden = vehicle.getIsControlled ~= nil and vehicle:getIsControlled() or false
        if vehicle.setEquipmentVisibility ~= nil then
            pcall(vehicle.setEquipmentVisibility, vehicle, ridden)
        end
    end
end

-- True while the baked halter shows (the bridle worn without its bit): the lead is tied to its chin ring.
function HorseTack.halterShowing(vehicle)
    local spec = vehicle ~= nil and vehicle.spec_rideable or nil
    local group = spec ~= nil and spec.equipmentNode or nil
    if group == nil or (entityExists ~= nil and not entityExists(group)) or getVisibility(group) ~= true then
        return false
    end
    local halter = childByName(group, "halter")
    return halter ~= nil and getVisibility(halter) == true
end

-- True while this horse's bridle shows (the rope halter steps aside then).
function HorseTack.bridleShowing(vehicle)
    local spec = vehicle ~= nil and vehicle.spec_rideable or nil
    local group = spec ~= nil and spec.equipmentNode or nil
    if group == nil or (entityExists ~= nil and not entityExists(group)) or getVisibility(group) ~= true then
        return false
    end
    local bridle = childByName(group, "bridle")
    return bridle == nil or getVisibility(bridle) == true
end

-- ===== saving: the pieces worn go with the animal =====
function HorseTack.save(self, xmlFile, key)
    if self.hdTack ~= nil then
        xmlFile:setInt(key .. "#hdTack", self.hdTack)
    end
end
function HorseTack.load(self, superFunc, xmlFile, key)
    local ok = superFunc(self, xmlFile, key)
    if ok then
        self.hdTack = xmlFile:getInt(key .. "#hdTack")
    end
    return ok
end
function HorseTack.write(self, streamId)
    streamWriteUIntN(streamId, self.hdTack ~= nil and self.hdTack + 1 or 0, HorseTack.BITS)
end
function HorseTack.read(self, streamId)
    local v = streamReadUIntN(streamId, HorseTack.BITS)
    self.hdTack = v > 0 and v - 1 or nil
end
function HorseTack.clone(self, superFunc)
    local ret = superFunc(self)
    if ret ~= nil then
        ret.hdTack = self.hdTack
    end
    return ret
end

-- ===== the console: hdTack saddle|blanket|bridle|bit [on|off], hdTack all|none|halter|reset =====
function HorseTack.nearest()
    local px, _, pz = HorseLead.playerPosition()
    if px == nil then
        return nil
    end
    local vehicle, best = nil, math.huge
    for _, candidate in ipairs(HorseLead.rideables()) do
        local x, _, z = getWorldTranslation(candidate.rootNode)
        local d = (x - px) ^ 2 + (z - pz) ^ 2
        if d < best then
            vehicle, best = candidate, d
        end
    end
    return vehicle
end

function HorseTack.describe(mask)
    if mask == nil then
        return "the game's own (everything while ridden)"
    end
    local names = {}
    for _, piece in ipairs(HorseTack.PIECES) do
        if worn(mask, piece.bit) then
            names[#names + 1] = piece.name
        end
    end
    return #names == 0 and "nothing" or table.concat(names, " + ")
end

-- Returns a message, or nil when the argument is not one of ours (the old node commands handle it).
function HorseTack.console(argument, state)
    local piece
    for _, p in ipairs(HorseTack.PIECES) do
        if p.name == argument then piece = p end
    end
    if piece == nil and argument ~= "all" and argument ~= "none" and argument ~= "reset" and argument ~= "worn" and argument ~= "halter" then
        return nil
    end
    local vehicle = HorseTack.nearest()
    local cluster = vehicle ~= nil and clusterOf(vehicle) or nil
    if cluster == nil then
        return "no horse vehicle near: lead a horse first (the leash), it is one then"
    end
    if argument == "worn" then
        return "this horse wears: " .. HorseTack.describe(cluster.hdTack)
    end
    if argument == "all" then
        cluster.hdTack = HorseTack.ALL
    elseif argument == "none" then
        cluster.hdTack = 0
    elseif argument == "halter" then
        cluster.hdTack = HorseTack.HALTER
    elseif argument == "reset" then
        cluster.hdTack = nil
    else
        local mask = cluster.hdTack or HorseTack.ALL
        local on = state == "on" or (state ~= "off" and not worn(mask, piece.bit))
        mask = on and (worn(mask, piece.bit) and mask or mask + piece.bit) or (worn(mask, piece.bit) and mask - piece.bit or mask)
        cluster.hdTack = mask
    end
    local spec = vehicle.spec_rideable
    if cluster.hdTack == nil then
        local group = spec ~= nil and spec.equipmentNode or nil
        if group ~= nil then
            for i = 0, getNumOfChildren(group) - 1 do
                setVisibility(getChildAt(group, i), getName(getChildAt(group, i)) ~= "halter")
            end
        end
        local ridden = vehicle.getIsControlled ~= nil and vehicle:getIsControlled() or false
        pcall(vehicle.setEquipmentVisibility, vehicle, ridden)
    else
        HorseTack.apply(vehicle)
    end
    return "this horse wears: " .. HorseTack.describe(cluster.hdTack)
end

if HorseTack.hooked == nil and Utils ~= nil and Utils.overwrittenFunction ~= nil then
    HorseTack.hooked = true
    if AnimalClusterHorse ~= nil then
        AnimalClusterHorse.saveToXMLFile = Utils.appendedFunction(AnimalClusterHorse.saveToXMLFile, HorseTack.save)
        AnimalClusterHorse.loadFromXMLFile = Utils.overwrittenFunction(AnimalClusterHorse.loadFromXMLFile, HorseTack.load)
        AnimalClusterHorse.writeStream = Utils.appendedFunction(AnimalClusterHorse.writeStream, HorseTack.write)
        AnimalClusterHorse.readStream = Utils.appendedFunction(AnimalClusterHorse.readStream, HorseTack.read)
        AnimalClusterHorse.clone = Utils.overwrittenFunction(AnimalClusterHorse.clone, HorseTack.clone)
    end
    if Rideable ~= nil then
        if Rideable.onUpdate ~= nil then
            Rideable.onUpdate = Utils.prependedFunction(Rideable.onUpdate, function(vehicle)
                local spec = vehicle.spec_rideable
                if spec ~= nil and HorseTack.hasRemovable(vehicle) then
                    spec.doHusbandryCheck = 0                        -- (the game takes a rideable near its pasture in by itself: not with a saddle on it)
                    spec.pendingHusbandryHandover = nil
                end
            end)
        end
        if Rideable.setEquipmentVisibility ~= nil then
            Rideable.setEquipmentVisibility = Utils.appendedFunction(Rideable.setEquipmentVisibility, function(vehicle) HorseTack.apply(vehicle) end)
        end
        if Rideable.setCluster ~= nil then
            Rideable.setCluster = Utils.appendedFunction(Rideable.setCluster, function(vehicle) HorseTack.apply(vehicle) end)
        end
    end
end
