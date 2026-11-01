--[[
    HorseDynamics.lua -- the mod's entry: keys, console commands and the per-frame update. The behaviour is in HorseLead.lua.

    Keys (on foot and in a vehicle): Right Ctrl + C calls the nearest horse (a horse of a pasture, or one that stands loose as a vehicle; press again for each further horse), Right Ctrl + V
    gives them all back, Right Ctrl + F freezes the led horses (they stand completely still) and lets them go on again, to look at their gear. Console: hdLead [start|stop|status].
]]
HorseDynamics = {}
HorseDynamics.registered = false

-- A short message on screen (and in the log): the game's own notification when it is there.
function HorseDynamics.notify(text)
    print("[HorseDynamics] " .. text)
    if g_currentMission ~= nil and g_currentMission.addIngameNotification ~= nil and FSBaseMission ~= nil and FSBaseMission.INGAME_NOTIFICATION_INFO ~= nil then
        pcall(g_currentMission.addIngameNotification, g_currentMission, FSBaseMission.INGAME_NOTIFICATION_INFO, text)
    end
end

-- The tools come in tiers: a rope one and a leather one (leash.xml / leash_leather.xml, harness.xml / harness_leather.xml: the file name says it). The family is the folder (leash, harness, carrot), the
-- tier 2 for "leather". The tool in the hand decides the gear of the horse it touches (HorseDynamics.gearOfTool): rope or leather.
function HorseDynamics.toolFamily(filename)
    if filename == nil then
        return nil, nil
    end
    local family = string.match(filename, "handTools/([^/]+)/[^/]+%.xml$")
    local tier = string.find(filename, "_leather%.xml$") ~= nil and 2 or 1
    return family, tier
end

function HorseDynamics.gearOfTool(handTool)
    local _, tier = HorseDynamics.toolFamily(handTool ~= nil and handTool.configFileName or nil)
    return tier == 2 and "leather" or "rope"
end

-- The tools of this mod the player's farm owns in a family: { handTool, tier }.
function HorseDynamics.ownedTools(family)
    local out = {}
    local system = g_currentMission ~= nil and g_currentMission.handToolSystem or nil
    local farmId = g_currentMission ~= nil and g_currentMission.getFarmId ~= nil and g_currentMission:getFarmId() or nil
    for _, handTool in ipairs(system ~= nil and system.handTools or {}) do
        local f, tier = HorseDynamics.toolFamily(handTool.configFileName)
        if f == family and handTool.customEnvironment == g_currentModName and (farmId == nil or handTool.getOwnerFarmId == nil or handTool:getOwnerFarmId() == farmId) then
            out[#out + 1] = { handTool = handTool, tier = tier }
        end
    end
    return out
end

-- Is this store item one of this mod's tools that the farm should not buy: one it has already, or a rope one when it has the leather one? Returns the text key of the reason, or nil.
function HorseDynamics.blockedPurchase(storeItem)
    if storeItem == nil or StoreItemUtil == nil or not StoreItemUtil.getIsHandTool(storeItem) or storeItem.customEnvironment ~= g_currentModName then
        return nil
    end
    local family, tier = HorseDynamics.toolFamily(storeItem.xmlFilename)
    local same, better = false, false
    for _, owned in ipairs(HorseDynamics.ownedTools(family)) do
        same = same or owned.tier == tier
        better = better or owned.tier > tier
    end
    if better then
        return "warning_horseDynamicsBetterOwned"
    end
    return same and "warning_horseDynamicsHandToolOwned" or nil
end

-- The shop asks canBeBought before it sells a hand tool: for one of this mod's tools the farm should not buy it says why and refuses (a second one, or a rope one beside the leather one).
if ShopController ~= nil and ShopController.canBeBought ~= nil and Utils ~= nil and not HorseDynamics.shopHooked then
    HorseDynamics.shopHooked = true
    ShopController.canBeBought = Utils.overwrittenFunction(ShopController.canBeBought, function(self, superFunc, storeItem, price)
        local reason = HorseDynamics.blockedPurchase(storeItem)
        if reason ~= nil then
            if InfoDialog ~= nil and g_i18n ~= nil then
                InfoDialog.show(g_i18n:getText(reason), DialogElement ~= nil and DialogElement.TYPE_WARNING or nil)
            end
            return false
        end
        return superFunc(self, storeItem, price)
    end)
end

-- A horse in its harness is a work horse: the mount key (Player:requestToEnterVehicle, a plain class method) says so and does nothing (the harness comes off with the harness tool first).
if Player ~= nil and Player.requestToEnterVehicle ~= nil and Utils ~= nil and not HorseDynamics.mountHooked then
    HorseDynamics.mountHooked = true
    Player.requestToEnterVehicle = Utils.overwrittenFunction(Player.requestToEnterVehicle, function(self, superFunc, vehicle, ...)
        if HorseLead ~= nil and HorseLead.isHarnessed(vehicle) then
            HorseDynamics.notify(g_i18n:getText("warning_horseDynamicsHarnessed"))
            return
        end
        return superFunc(self, vehicle, ...)
    end)
end

-- A leather tool beside the rope one of its family: the rope one is traded in (sold for its sell price, as the shop's own sale does: SellHandToolEvent). Checked when the number of hand tools changes.
HorseDynamics.handToolCount = nil
function HorseDynamics.reconcileHandTools()
    local system = g_currentMission ~= nil and g_currentMission.handToolSystem or nil
    if system == nil then
        return
    end
    local count = #system.handTools
    if count == HorseDynamics.handToolCount then
        return
    end
    HorseDynamics.handToolCount = count
    for _, family in ipairs({ "leash", "harness" }) do
        local owned = HorseDynamics.ownedTools(family)
        local hasLeather = false
        for _, o in ipairs(owned) do
            hasLeather = hasLeather or o.tier == 2
        end
        if hasLeather then
            for _, o in ipairs(owned) do
                if o.tier == 1 then
                    local handTool = o.handTool
                    local price = handTool.getSellPrice ~= nil and handTool:getSellPrice() or 0
                    local farmId = handTool.getOwnerFarmId ~= nil and handTool:getOwnerFarmId() or nil
                    handTool:delete()
                    if g_currentMission.addMoney ~= nil and MoneyType ~= nil then
                        g_currentMission:addMoney(price, farmId, MoneyType.SHOP_HANDTOOL_SELL, true)
                    end
                    HorseDynamics.handToolCount = nil
                    HorseDynamics.notify(string.format("the rope %s is traded in for the leather one (%d paid back)", family, price))
                end
            end
        end
    end
end

function HorseDynamics.onCall()
    HorseDynamics.notify(HorseLead.command(nil, "start"))
end

function HorseDynamics.onFreeze()
    HorseDynamics.notify(HorseLead.toggleFreeze())
end

function HorseDynamics.onRelease()
    HorseDynamics.notify(HorseLead.command(nil, "stop"))
end

function HorseDynamics.registerActionEvents()
    if g_inputBinding == nil or InputAction == nil or InputAction.HORSEDYN_CALL == nil then
        return
    end
    for _, spec in ipairs({ { InputAction.HORSEDYN_CALL, HorseDynamics.onCall }, { InputAction.HORSEDYN_RELEASE, HorseDynamics.onRelease }, { InputAction.HORSEDYN_FREEZE, HorseDynamics.onFreeze } }) do
        local _, eventId = g_inputBinding:registerActionEvent(spec[1], HorseDynamics, spec[2], false, true, false, true, nil, true)
        if eventId ~= nil then
            g_inputBinding:setActionEventTextPriority(eventId, GS_PRIO_LOW)
            g_inputBinding:setActionEventTextVisibility(eventId, true)
        end
    end
end

function HorseDynamics.update(_, dt)
    HorseLead.updateRide(dt)
    HorseDynamics.reconcileHandTools()
end

function HorseDynamics.consoleLead(_, argument, value, ...)
    if argument == "style" then
        if value ~= "halter" and value ~= "tack" and value ~= "reins" and value ~= "rope" then
            return "usage: hdLead style halter|tack|reins|rope (now: " .. tostring(HorseRope.style) .. ")"
        end
        for _, ride in ipairs(HorseLead.rides) do
            HorseRope.remove(ride)                       -- (the led horses are re-dressed in the new style on the next frame)
        end
        HorseRope.style = value
        local what = { halter = "a rope halter on the bare horse", tack = "a rope to the bridle, saddle and reins at rest", reins = "the game's reins (the whole tack shows)", rope = "a rope to the rein node on the bare horse" }
        return "a led horse is held by " .. what[value]
    elseif argument == "halter" then
        local y, centre, vertical, lateral, tilt = ...
        if value == "slack" then
            -- hdLead halter slack nose crown (metres of hang below each loop)
            local nose, crown = tonumber(y), tonumber(centre)
            if nose == nil or crown == nil then
                return string.format("usage: hdLead halter slack nose crown (metres the bottom of each loop hangs below the head; now %.3f %.3f)", HorseRope.halter.nose.slack, HorseRope.halter.crown.slack)
            end
            HorseRope.halter.nose.slack, HorseRope.halter.crown.slack = nose, crown
            for _, ride in ipairs(HorseLead.rides) do
                HorseRope.remove(ride)
            end
            return string.format("the slack is %.3f below the noseband, %.3f below the crown", nose, crown)
        end
        if value == "jaw" then
            -- hdLead halter jaw degrees (the strap down the cheek runs this many degrees forward of straight down)
            local d = tonumber(y)
            if d == nil then
                return string.format("usage: hdLead halter jaw degrees (the strap down the cheek runs this far forward of straight down; now %.0f)", HorseRope.halter.crown.jawAngle)
            end
            HorseRope.setJawAngle(d)
            for _, ride in ipairs(HorseLead.rides) do
                HorseRope.remove(ride)
            end
            return string.format("the strap down the cheek runs %.0f degrees forward of straight down", d)
        end
        if value == "bend" then
            -- hdLead halter bend d (metres the noseband's side points are pulled back along the face: 0 is a straight noseband)
            local d = tonumber(y)
            if d == nil then
                return string.format("usage: hdLead halter bend d (metres the noseband's side points are pulled back, 0 is straight; now %.3f)", HorseRope.halter.nose.bend)
            end
            HorseRope.halter.nose.bend = d
            for _, ride in ipairs(HorseLead.rides) do
                HorseRope.remove(ride)
            end
            return string.format("the noseband's sides are pulled back %.3f", d)
        end
        if value == "clearance" then
            -- hdLead halter clearance d (metres the crown, the cheek straps and the rings stand further off the head; negative: closer)
            local d = tonumber(y)
            if d == nil then
                return string.format("usage: hdLead halter clearance d (metres the crown, cheek straps and rings stand further off the head, negative closer; now %.3f)", HorseRope.halter.clearance)
            end
            HorseRope.halter.clearance = d
            for _, ride in ipairs(HorseLead.rides) do
                HorseRope.remove(ride)
            end
            return string.format("the crown, the cheek straps and the rings stand %.3f further off the head", d)
        end
        local part = HorseRope.halter[value]
        y, centre, vertical, lateral, tilt = tonumber(y), tonumber(centre), tonumber(vertical), tonumber(lateral), tonumber(tilt)
        if value ~= "nose" or type(part) ~= "table" or y == nil or centre == nil or vertical == nil or lateral == nil then
            local nose = HorseRope.halter.nose
            return string.format("usage: hdLead halter nose y centre vertical lateral [tilt degrees] (head bone space; now nose %.3f %.3f %.3f %.3f), hdLead halter clearance d, hdLead halter bend d, hdLead halter jaw degrees, hdLead halter slack nose crown",
                nose.y, nose.centre, nose.vertical, nose.lateral)
        end
        part.y, part.centre, part.vertical, part.lateral = y, centre, vertical, lateral
        if tilt ~= nil then
            part.tilt = tilt
        end
        for _, ride in ipairs(HorseLead.rides) do
            HorseRope.remove(ride)                       -- (the halter is rebuilt on the next frame)
        end
        return string.format("the %s loop is at y %.3f, centre %.3f, half height %.3f, half width %.3f", value, y, centre, vertical, lateral)
    elseif argument == "face" then
        if value ~= "on" and value ~= "off" then
            return "usage: hdLead face on|off (a horse that stands turns to face you; off: it stands still while you walk round it to look at its gear; now " .. (HorseLead.RIDE_TURN_RATE_STILL > 0 and "on" or "off") .. ")"
        end
        HorseLead.RIDE_TURN_RATE_STILL = value == "on" and HorseLead.RIDE_TURN_RATE_STILL_DEFAULT or 0
        return "a standing horse " .. (value == "on" and "turns to face you" or "stays as it stands")
    elseif argument == "halteroffset" then
        local second, third = ...
        local x, y, z = tonumber(value), tonumber(second), tonumber(third)
        if x == nil or y == nil or z == nil then
            local o = HorseRope.halterOffset
            return string.format("usage: hdLead halteroffset x y z (the whole halter moved in the head bone's space, z is sideways; now %.3f %.3f %.3f; 0 0 0 puts it on the head)", o[1], o[2], o[3])
        end
        HorseRope.halterOffset = { x, y, z }
        return string.format("the halter is offset by %.3f %.3f %.3f", x, y, z)
    elseif argument == "halterinfo" then
        return HorseRope.halterReport(HorseLead.rides)
    elseif argument == "material" then
        if value ~= "hemp" and value ~= "steel" then
            return "usage: hdLead material hemp|steel (now: " .. tostring(HorseRope.material) .. ")"
        end
        for _, ride in ipairs(HorseLead.rides) do
            HorseRope.remove(ride)                       -- (the rope is made again on the next frame)
        end
        HorseRope.material = value
        return "the rope is " .. (value == "hemp" and "hemp (matte, our own textures)" or "the game's steel cable")
    elseif argument == "gear" then
        if value ~= "leather" and value ~= "rope" then
            return "usage: hdLead gear leather|rope (the halter and the harness: flat brown leather straps, or round rope like the lead; now: " .. tostring(HorseRope.gear) .. ")"
        end
        HorseRope.gear = value
        for _, ride in ipairs(HorseLead.rides) do
            HorseRope.remove(ride)                       -- (the halter and the harness are made again on the next frame)
        end
        return value == "leather" and "the halter and the harness are flat leather straps" or "the halter and the harness are round rope"
    elseif argument == "tint" then
        local second, third = ...
        local r, g, b = tonumber(value), tonumber(second), tonumber(third)
        if r == nil or g == nil or b == nil then
            return string.format("usage: hdLead tint r g b (the rope's emissive tint, now %.2f %.2f %.2f; 0 0 0 = plain steel grey, try 0.3 0.2 0.1)", HorseRope.tint[1], HorseRope.tint[2], HorseRope.tint[3])
        end
        HorseRope.setTint(r, g, b)
        return string.format("the rope's tint is %.2f %.2f %.2f", r, g, b)
    elseif argument == "ring" then
        local second, third = ...
        local x, y, z = tonumber(value), tonumber(second), tonumber(third)
        if x == nil or y == nil or z == nil then
            return string.format("usage: hdLead ring x y z (the bit ring in the head bone's space, now %.4f %.4f %.4f)", HorseRope.ring[1], HorseRope.ring[2], HorseRope.ring[3])
        end
        HorseRope.setRing(x, y, z)
        return string.format("the bit ring is at %.4f %.4f %.4f in the head bone's space", x, y, z)
    end
    return HorseLead.command(nil, argument)
end

if PlayerInputComponent ~= nil and PlayerInputComponent.registerGlobalPlayerActionEvents ~= nil and Utils ~= nil and not HorseDynamics.hooked then
    HorseDynamics.hooked = true
    PlayerInputComponent.registerGlobalPlayerActionEvents = Utils.appendedFunction(PlayerInputComponent.registerGlobalPlayerActionEvents, function()
        HorseDynamics.registerActionEvents()
    end)
end
function HorseDynamics.consoleFreeze()
    return HorseLead.toggleFreeze()
end

function HorseDynamics.consoleTack(_, argument, state)
    return HorseLead.tack(argument, state)
end

if addConsoleCommand ~= nil then
    addConsoleCommand("hdFreezeHorse", "HorseDynamics: freeze the led horses (they stand completely still) / let them go on: a toggle", "consoleFreeze", HorseDynamics)
    addConsoleCommand("hdTack", "HorseDynamics: the tack of the nearest horse vehicle [list | show | hide | <node name> on|off]", "consoleTack", HorseDynamics)
    addConsoleCommand("hdLead", "HorseDynamics: lead the nearest horse [start|stop|status] (keys: Right Ctrl + C call, Right Ctrl + V release)", "consoleLead", HorseDynamics)
end
if addModEventListener ~= nil then
    addModEventListener(HorseDynamics)
end
print("[HorseDynamics] loaded: Right Ctrl + C calls the nearest horse, Right Ctrl + V gives them back (console: hdLead)")
