--[[
    HorseSaddleItem.lua -- the saddle as an object (vehicles/horseSaddle: a dynamic shop vehicle you pick up with your hands and set down anywhere).
    Put on: carry it up to a horse (hands holding it, within AUTO_M of the horse's root): the hands let go, the horse wears the saddle, the pad and the panel (HorseTack.saddleOn), the object is hidden and out of the physics while worn.
    Take off: look at the saddle ON the horse: the hands' pick-up key shows "take the saddle off", a click and the saddle is in your hand again.
    How the saddle is found: the saddle on the horse is a skinned mesh without a physics shape, a ray hits the horse's body and nothing else. So a box fitted to the saddle (BOX, in the tack node's own space, it moves with the horse) is tested
    against the look ray, and a hit is put into the hands' target list (like HandReach does for its ring): the game shows the hand and sends the click down its own pick-up path, which is answered here.
    Hooks: HandToolHands.onUpdate (appended: patches this hands object once, auto-equip, the prompt), PlayerTargeter.update / tryAddTargetWithMask (the target), on the hands object: getCanPickUpNode and pickUpTarget.
    Worn state: the pieces go with the animal (cluster.hdTack), the object does not: after a reload it lies where it was put on (like the harness).
]]
HorseSaddleItem = {}
HorseSaddleItem.AUTO_M = 2.0                 -- a carried saddle this close to a horse's root goes on
HorseSaddleItem.TAKE_M = 3.5                 -- the saddle on a horse can be clicked from this far along the look ray
HorseSaddleItem.REARM_M = 3.0                -- a saddle taken off a horse goes on it again only after it has been this far from it
HorseSaddleItem.HOLD_M = 1.2                 -- a saddle taken off is put this far along the look ray, in front of the player, and picked up from there
-- the saddle's box in the tack node's space (x to the horse's left, y up, z forward): the seat, the flaps, the leathers (the iron is not in it)
HorseSaddleItem.BOX_LO = { -0.42, 1.02, -0.20 }
HorseSaddleItem.BOX_HI = { 0.42, 1.72, 0.45 }
HorseSaddleItem.items = setmetatable({}, { __mode = "k" })     -- the saddle objects that exist

local function say(format, ...)
    print(string.format("[HorseDynamics] saddle item: " .. format, ...))
end

local function alive(node)
    return node ~= nil and (entityExists == nil or entityExists(node))
end

local function rootPos(vehicle)
    if vehicle == nil or vehicle.rootNode == nil or not alive(vehicle.rootNode) then
        return nil
    end
    return getWorldTranslation(vehicle.rootNode)
end

-- Where does the ray (origin o, direction d, both in the box's space) enter the box? Returns the distance along the ray, or nil.
function HorseSaddleItem.rayBox(ox, oy, oz, dx, dy, dz, lo, hi)
    local o, d = { ox, oy, oz }, { dx, dy, dz }
    local tmin, tmax = 0, math.huge
    for i = 1, 3 do
        if math.abs(d[i]) < 1e-9 then
            if o[i] < lo[i] or o[i] > hi[i] then
                return nil
            end
        else
            local t1, t2 = (lo[i] - o[i]) / d[i], (hi[i] - o[i]) / d[i]
            if t1 > t2 then
                t1, t2 = t2, t1
            end
            tmin, tmax = math.max(tmin, t1), math.min(tmax, t2)
            if tmin > tmax then
                return nil
            end
        end
    end
    return tmin
end

-- The horse that wears the object (its tack node), or nil.
local function tackNode(horse)
    local spec = horse ~= nil and horse.spec_rideable or nil
    local group = spec ~= nil and spec.equipmentNode or nil
    return alive(group) and group or nil
end

-- The look ray against the saddle of every horse that wears a saddle object: horse, item, distance, point.
function HorseSaddleItem.lookedAt(ox, oy, oz, dx, dy, dz)
    local best, bestT
    for item in pairs(HorseSaddleItem.items) do
        local horse = item.horseWornBy
        local group = (not item.isDeleted and horse ~= nil and not horse.isDeleted) and tackNode(horse) or nil
        if group ~= nil and getVisibility(group) then
            local lx, ly, lz = worldToLocal(group, ox, oy, oz)
            local ldx, ldy, ldz = worldDirectionToLocal(group, dx, dy, dz)
            local t = HorseSaddleItem.rayBox(lx, ly, lz, ldx, ldy, ldz, HorseSaddleItem.BOX_LO, HorseSaddleItem.BOX_HI)
            if t ~= nil and t <= HorseSaddleItem.TAKE_M and (bestT == nil or t < bestT) then
                best, bestT = { horse = horse, item = item }, t
            end
        end
    end
    if best == nil then
        return nil
    end
    return best.horse, best.item, bestT, ox + dx * bestT, oy + dy * bestT, oz + dz * bestT
end

-- ---------------------------------------------------------------------------------------------- put on / take off

function HorseSaddleItem.notify(text)
    if HorseDynamics ~= nil and HorseDynamics.notify ~= nil and text ~= nil then
        HorseDynamics.notify(text)
    end
end

-- The object's saddle goes on the horse: its pieces show, the object is out of the world.
function HorseSaddleItem.equip(horse, item)
    if horse.hdSaddleItem ~= nil or HorseTack.wearsSaddle(horse) then
        return false, "this horse wears a saddle already"
    end
    if not HorseTack.saddleOn(horse) then
        return false, "this horse cannot wear a saddle (lead it first, or ride it out of its pasture)"
    end
    horse.hdSaddleItem = item
    item.horseWornBy = horse
    pcall(item.removeFromPhysics, item)
    pcall(item.setVisibility, item, false)
    say("put on the horse")
    return true, "the saddle is on: look at it and click to take it off"
end

-- The object appears where it is told (or beside the horse, 2.2 m to its left) and is in the physics again.
function HorseSaddleItem.putDown(item, horse, at)
    if item == nil or item.isDeleted then
        return
    end
    local hx, _, hz = rootPos(horse)
    if hx == nil then
        local ix, _, iz = rootPos(item)
        if ix == nil then
            return
        end
        hx, hz = ix, iz
    end
    local dx, dz, yaw = 1, 0, 0
    if horse ~= nil and alive(horse.rootNode) then
        local lx, _, lz = localDirectionToWorld(horse.rootNode, 1, 0, 0)
        dx, dz = lx, lz
        local fx, _, fz = localDirectionToWorld(horse.rootNode, 0, 0, 1)
        yaw = math.atan2(fx, fz)                                    -- (the saddle keeps the horse's heading: it is held as it sat on the horse, the flap towards the one who pulled it off)
    end
    local x, z = hx + dx * 2.2, hz + dz * 2.2
    local y = getTerrainHeightAtWorldPos(g_terrainNode, x, 0, z) + 0.3
    if at ~= nil then
        x, y, z = at[1], at[2], at[3]
    end
    pcall(item.setAbsolutePosition, item, x, y, z, 0, yaw, 0)
    pcall(item.addToPhysics, item)
    pcall(item.setVisibility, item, true)
    item.horseWornBy = nil
end

function HorseSaddleItem.unequip(horse, at)
    local item = horse.hdSaddleItem
    horse.hdSaddleItem = nil
    HorseTack.saddleOff(horse)
    if item ~= nil then
        item.rearm = horse
        HorseSaddleItem.putDown(item, horse, at)
    end
    say("taken off the horse")
    return "the saddle is off"
end

-- A saddle object whose horse is gone (deleted, back in a pasture, the saddle taken off by the console) is put back into the world where the horse was.
function HorseSaddleItem.update(_)
    HorseSaddleItem.install()
    for item in pairs(HorseSaddleItem.items) do
        local horse = item.horseWornBy
        if horse ~= nil and not item.isDeleted then
            if horse.isDeleted or horse.hdSaddleItem ~= item or not HorseTack.wearsSaddle(horse) then
                if horse.hdSaddleItem == item then
                    horse.hdSaddleItem = nil
                end
                HorseSaddleItem.putDown(item, horse.isDeleted and nil or horse)
                say("the horse does not wear it any more: the saddle is put back in the world")
            end
        end
    end
end

-- ---------------------------------------------------------------------------------------------- the hands

local function localHands()
    local player = g_localPlayer
    local hands = player ~= nil and player.hands or nil
    if hands ~= nil and hands.getIsHoldingItem ~= nil and hands.spec_hands ~= nil then
        return hands
    end
    return nil
end

-- The saddle object the hands hold, or nil.
function HorseSaddleItem.held(hands)
    if hands == nil or not hands:getIsHoldingItem() then
        return nil
    end
    local node = hands:getHeldItem()
    for item in pairs(HorseSaddleItem.items) do
        if not item.isDeleted and item.rootNode == node then
            return item
        end
    end
    return nil
end

local function eachHorse()
    local vehicles = g_currentMission ~= nil and g_currentMission.vehicleSystem ~= nil and g_currentMission.vehicleSystem.vehicles or {}
    local list = {}
    for _, vehicle in ipairs(vehicles) do
        if vehicle.spec_rideable ~= nil and not vehicle.isDeleted and rootPos(vehicle) ~= nil then
            list[#list + 1] = vehicle
        end
    end
    return list
end

-- A carried saddle within reach of a horse goes on it: the hands let go, the horse wears it.
function HorseSaddleItem.autoEquip(hands)
    local item = HorseSaddleItem.held(hands)
    if item == nil then
        return
    end
    local ix, _, iz = rootPos(item)
    if ix == nil then
        return
    end
    for _, horse in ipairs(eachHorse()) do
        local hx, _, hz = rootPos(horse)
        local d = math.sqrt((ix - hx) ^ 2 + (iz - hz) ^ 2)
        if item.rearm == horse then
            if d > HorseSaddleItem.REARM_M then
                item.rearm = nil
            end
        elseif d < HorseSaddleItem.AUTO_M and horse.hdSaddleItem == nil then
            hands:dropHeldItem()
            local ok, text = HorseSaddleItem.equip(horse, item)
            if not ok then
                item.rearm = horse                                  -- (say why once; the next try is after it has been carried away)
            end
            HorseSaddleItem.notify(text)
            return
        end
    end
end

-- The click on the saddle of a horse: the saddle comes off and is in the hands (set down in front of the player, picked up from there).
function HorseSaddleItem.takeToHand(hands, superPick, horse)
    local player = g_localPlayer
    local ox, oy, oz, dx, dy, dz = player.targeter:getLastLookRay()
    local item = horse.hdSaddleItem
    local at = { ox + dx * HorseSaddleItem.HOLD_M, oy + dy * HorseSaddleItem.HOLD_M, oz + dz * HorseSaddleItem.HOLD_M }
    HorseSaddleItem.notify(HorseSaddleItem.unequip(horse, at))
    if item ~= nil and not item.isDeleted and superPick(hands, { node = item.rootNode, distance = HorseSaddleItem.HOLD_M }) then
        say("in your hand")
        return true
    end
    return false
end

function HorseSaddleItem.isProxy(node)
    for item in pairs(HorseSaddleItem.items) do
        if item.horseWornBy ~= nil and not item.isDeleted and item.rootNode == node then
            return true
        end
    end
    return false
end

-- The hands object of the local player: the saddle on a horse counts as something the hands can pick up (its target is ours), and the pick-up of it takes the saddle off.
function HorseSaddleItem.patchHands(hands)
    if hands.hdSaddlePatched then
        return
    end
    hands.hdSaddlePatched = true
    local canPick, pick = hands.getCanPickUpNode, hands.pickUpTarget
    hands.getCanPickUpNode = function(self, node)
        if HorseSaddleItem.isProxy(node) then
            return not self:getIsHoldingItem()
        end
        return canPick(self, node)
    end
    hands.pickUpTarget = function(self, target, noEventSend)
        if target ~= nil and target.hdSaddle ~= nil then
            local horse = target.hdSaddle
            if horse.hdSaddleItem ~= nil and not self:getIsHoldingItem() then
                return HorseSaddleItem.takeToHand(self, pick, horse)
            end
            return false
        end
        return pick(self, target, noEventSend)
    end
    say("the hands know the saddle on a horse")
end

-- Enters and leaves the saddle box: a line in the log each time (to tune BOX against what you see).
local function logLook(horse)
    if HorseSaddleItem.looking ~= horse then
        HorseSaddleItem.looking = horse
        say(horse ~= nil and "the look ray is on the saddle of a horse" or "the look ray left the saddle")
    end
end

-- Hooks on the game's hands and targeter (installed once the classes exist).
function HorseSaddleItem.install()
    if HorseSaddleItem.hooked or HandToolHands == nil or PlayerTargeter == nil or Utils == nil then
        return
    end
    HorseSaddleItem.hooked = true
    HandToolHands.onUpdate = Utils.appendedFunction(HandToolHands.onUpdate, function(self, dt)
        if self ~= localHands() then
            return
        end
        HorseSaddleItem.patchHands(self)
        HorseSaddleItem.autoEquip(self)
        local targeter = g_localPlayer.targeter
        local target = targeter ~= nil and targeter.closestTargetsByKey[HandToolHands] or nil
        if not self:getIsHoldingItem() and target ~= nil and target.hdSaddle ~= nil then
            local id = self.spec_hands.pickUpActionEventId
            if id ~= nil then
                g_inputBinding:setActionEventActive(id, true)
                g_inputBinding:setActionEventText(id, g_i18n:getText("hd_takeSaddleOff", g_currentModName))
            end
        end
    end)
    local update, tryAdd = PlayerTargeter.update, PlayerTargeter.tryAddTargetWithMask
    PlayerTargeter.update = function(self, dt)
        local hands = localHands()
        local mine = hands ~= nil and g_localPlayer ~= nil and self == g_localPlayer.targeter and hands:getIsHeld() and not hands:getIsHoldingItem() and self.targetedMasks[HandToolHands] ~= nil
        local nearReal = nil                                                    -- (last frame's real, pickable target: a nearer thing than the saddle wins)
        local last = self.closestTargetsByKey[HandToolHands]
        if last ~= nil and last.hdSaddle ~= nil then
            last.hdSaddle = nil                                                 -- (the game gives it back to its pool now: no stale flag on a target that is reused)
        elseif mine and last ~= nil and hands:getCanPickUpNode(last.node) then
            nearReal = last.distance
        end
        update(self, dt)
        if not mine then
            if g_localPlayer ~= nil and self == g_localPlayer.targeter then
                logLook(nil)
            end
            return
        end
        local ox, oy, oz, dx, dy, dz = self:getLastLookRay()
        local horse, item, t, x, y, z
        if ox ~= nil and dx ~= nil then
            horse, item, t, x, y, z = HorseSaddleItem.lookedAt(ox, oy, oz, dx, dy, dz)
        end
        if horse ~= nil and (nearReal == nil or nearReal > t) and self.pooledTargets ~= nil then
            local old = self.currentTargetsByKey[HandToolHands]
            if old ~= nil then
                old.hdSaddle = nil
                self.pooledTargets:returnToPool(old)
            end
            local target = self.pooledTargets:getOrCreateNext()
            target.x, target.y, target.z, target.node, target.distance, target.hdSaddle = x, y, z, item.rootNode, t, horse
            self.currentTargetsByKey[HandToolHands] = target
            logLook(horse)
        else
            logLook(nil)
        end
    end
    PlayerTargeter.tryAddTargetWithMask = function(self, hitNode, x, y, z, targetedMask, distance)
        if targetedMask.key == HandToolHands then
            local existing = self.currentTargetsByKey[HandToolHands]
            if existing ~= nil and existing.hdSaddle ~= nil then
                local hands = localHands()
                if hands == nil or distance >= existing.distance or not hands:getCanPickUpNode(hitNode) then
                    return                                                      -- (the horse's own body, or something farther: the saddle stays the target)
                end
                existing.hdSaddle = nil
                self.pooledTargets:returnToPool(existing)
                self.currentTargetsByKey[HandToolHands] = nil
            end
        end
        return tryAdd(self, hitNode, x, y, z, targetedMask, distance)
    end
end
HorseSaddleItem.install()
