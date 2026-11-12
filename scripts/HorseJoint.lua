--[[
    HorseJoint.lua -- a SPIKE: a REAL attacher joint on the horse, so that a trailer attaches to the horse with the game's own attach code (the physics joint, the support leg, the brake and lights of the
    trailer ...) instead of the kinematic glue of HorseHitch. What the horse's definition shows (data of the game, the horse's vehicle xml and i3d): `vehicle type="horse"`, ONE component of 400 kg whose root
    node `horse_main_component1` is a shape with kinematic="true": a kinematic rigid body, what a physics joint needs, moved by the character controller (cctDrivable).
    1. The vehicle type: AttacherJoints is added to the type "horse" when the vehicle types are validated (the way FS25_FollowMe adds its specialization): g_vehicleTypeManager:addSpecialization.
       AttacherJoints.prerequisitesPresent is just `return true`.
    2. The joint: a node under the horse's root component at the hook (HorseJoint.AT, the horse's model space), registered as i3d mapping "rfHitchJoint" ({ nodeId, rootNode }: what the loader makes of
       i3dMappings), then the game's own loader reads xml/horseJoint.xml (AttacherJoints:loadAttacherJointFromXML) and the joint is appended to spec_attacherJoints.
    3. The attach: attachImplementFromInfo with the info the game's Q handler uses ({ attacherVehicle, attacherVehicleJointDescIndex, attachable, attachableJointDescIndex }).
    Console (the spike's controls): hdJoint info | add | attach | detach | remove | rot <degrees> | at <x> <y> <z>.
]]
HorseJoint = {}
HorseJoint.INJECT = true                  -- add the attacher joints specialization to the horse type when the types are validated; false: the horse is untouched
HorseJoint.TYPE = "horse"
HorseJoint.SPEC = "attacherJoints"
HorseJoint.NODE_ID = "rfHitchJoint"
HorseJoint.AT = { 0, 1.08, -1.06 }        -- the hook, in the horse's model space (HorseHarness.spec.hook.at)
HorseJoint.ROT_Y_DEG = 180                -- a rear joint of a vehicle looks backwards
HorseJoint.REACH_M = 15                   -- the horse the console works on: the one you ride, else the nearest within this
HorseJoint.xmlPath = (g_currentModDirectory or "") .. "xml/horseJoint.xml"
HorseJoint.joints = setmetatable({}, { __mode = "k" })       -- horse vehicle -> { node, index, joint }

local function say(format, ...)
    local text = string.format("[HorseDynamics] joint: " .. format, ...)
    print(text)
    return text
end

-- Adds the specialization to the vehicle type of the horse. Returns whether the type has it afterwards.
function HorseJoint.inject()
    if not HorseJoint.INJECT or g_vehicleTypeManager == nil then
        return false
    end
    local types = g_vehicleTypeManager:getTypes() or {}
    local typeObject = types[HorseJoint.TYPE]
    if typeObject == nil then
        say("no vehicle type '%s' to add %s to", HorseJoint.TYPE, HorseJoint.SPEC)
        return false
    end
    if typeObject.specializationsByName ~= nil and typeObject.specializationsByName[HorseJoint.SPEC] ~= nil then
        return true
    end
    g_vehicleTypeManager:addSpecialization(HorseJoint.TYPE, HorseJoint.SPEC)
    say("the specialization %s was added to the vehicle type %s", HorseJoint.SPEC, HorseJoint.TYPE)
    return true
end

if TypeManager ~= nil and TypeManager.validateTypes ~= nil and Utils ~= nil and not HorseJoint.hooked then
    HorseJoint.hooked = true
    TypeManager.validateTypes = Utils.appendedFunction(TypeManager.validateTypes, function(self)
        if self.typeName == "vehicle" then
            local ok, err = pcall(HorseJoint.inject)
            if not ok then
                say("adding the specialization failed: %s", tostring(err))
            end
        end
    end)
end

-- Gives the horse its joint. Returns true, or false and why not.
function HorseJoint.add(horse)
    local spec = horse.spec_attacherJoints
    if spec == nil then
        return false, "the horse has no attacher joints specialization (the type injection did not work: see the log of the start, 'the specialization attacherJoints was added')"
    end
    if HorseJoint.joints[horse] ~= nil then
        return true
    end
    local root = horse.components ~= nil and horse.components[1] ~= nil and horse.components[1].node or nil
    if root == nil then
        return false, "the horse has no component"
    end
    local node = createTransformGroup("rfHitchJoint")
    link(root, node)
    setTranslation(node, HorseJoint.AT[1], HorseJoint.AT[2], HorseJoint.AT[3])
    setRotation(node, 0, math.rad(HorseJoint.ROT_Y_DEG), 0)
    horse.i3dMappings = horse.i3dMappings or {}
    horse.i3dMappings[HorseJoint.NODE_ID] = { nodeId = node, rootNode = root }
    local schema = horse.xmlFile ~= nil and horse.xmlFile.schema or (Vehicle ~= nil and Vehicle.xmlSchema) or nil
    local xml = XMLFile.load("horseJoint", HorseJoint.xmlPath, schema)
    local function fail(why)
        horse.i3dMappings[HorseJoint.NODE_ID] = nil
        pcall(delete, node)
        return false, why
    end
    if xml == nil then
        return fail("could not read " .. HorseJoint.xmlPath)
    end
    local joint = {}
    local ok, loaded = pcall(horse.loadAttacherJointFromXML, horse, joint, xml, "vehicle.attacherJoints.attacherJoint(0)", #spec.attacherJoints)
    xml:delete()
    if not ok or not loaded then
        return fail("the game's loader refused the joint: " .. tostring(loaded))
    end
    -- what the game's onPostLoad sets for the joints of a vehicle that loaded normally (attach and detach read these)
    joint.jointOrigRot = { getRotation(joint.jointTransform) }
    joint.jointOrigTrans = { getTranslation(joint.jointTransform) }
    table.insert(spec.attacherJoints, joint)
    joint.index = #spec.attacherJoints
    HorseJoint.joints[horse] = { node = node, index = joint.index, joint = joint }
    say("the horse has an attacher joint now (index %d, at %.2f, %.2f, %.2f in its model space, turned %d degrees)", joint.index, HorseJoint.AT[1], HorseJoint.AT[2], HorseJoint.AT[3], HorseJoint.ROT_Y_DEG)
    return true
end

-- Takes the joint off the horse again (what is attached is let go first).
function HorseJoint.remove(horse)
    local entry = HorseJoint.joints[horse]
    if entry == nil then
        return false
    end
    HorseJoint.detach(horse)
    local spec = horse.spec_attacherJoints
    if spec ~= nil then
        for i = #spec.attacherJoints, 1, -1 do
            if spec.attacherJoints[i] == entry.joint then
                table.remove(spec.attacherJoints, i)
            end
        end
        for i, joint in ipairs(spec.attacherJoints) do
            joint.index = i
        end
    end
    if horse.i3dMappings ~= nil then
        horse.i3dMappings[HorseJoint.NODE_ID] = nil
    end
    pcall(delete, entry.joint.jointTransformOrig)
    pcall(delete, entry.node)
    HorseJoint.joints[horse] = nil
    return true
end

-- Attaches the vehicle whose attacher joint (target.node) it is, to the horse: the game's attach code. target: { vehicle, node } (WinchTow's pick). Returns true, or false and why not.
function HorseJoint.attach(horse, target)
    local added, why = HorseJoint.add(horse)
    if not added then
        return false, why
    end
    local entry = HorseJoint.joints[horse]
    local trailer = target.vehicle
    local attachable = trailer.spec_attachable
    if attachable == nil or attachable.inputAttacherJoints == nil then
        return false, "that vehicle cannot be attached (no attachable specialization)"
    end
    local inputIndex = nil
    for i, input in ipairs(attachable.inputAttacherJoints) do
        if input.node == target.node then
            inputIndex = i
        end
    end
    if inputIndex == nil then
        return false, "that joint is not an input joint of the vehicle (it is one of its own hitches)"
    end
    if trailer.isAttachAllowed ~= nil then
        local ok, allowed, warning = pcall(trailer.isAttachAllowed, trailer, horse.getActiveFarm ~= nil and horse:getActiveFarm() or nil, horse)
        if ok and allowed == false then
            return false, "the game does not allow it: " .. tostring(warning)
        end
    end
    -- the game pulls the eye onto the joint: a joint above the eye lifts the drawbar (and the wagon's far wheels off the ground), so the joint takes the height the eye has now
    local root = horse.components[1].node
    local _, ly = worldToLocal(root, getWorldTranslation(target.node))
    ly = math.max(HorseJoint.MIN_Y, math.min(HorseJoint.AT[2], ly))
    -- a cart that holds its eye where it rests (the sulky): the joint stays at the horse's own hook (not above the eye, at most HOOK_DROP_M under it), so the eye is pulled DOWN to it and the cart pitches nose-down
    -- about its axle, as on a small horse; a joint above the eye would lift the shafts
    if HorseHitch ~= nil and HorseHitch.eyeIsRest ~= nil and HorseHitch.eyeIsRest(trailer) then
        local ride = nil
        for _, r in ipairs(HorseLead ~= nil and HorseLead.rides or {}) do
            if r.vehicle == horse then ride = r end
        end
        local rig = ride ~= nil and ride.rig or nil
        if rig ~= nil and rig.hookNode ~= nil and rig.hookFollow == nil and (entityExists == nil or entityExists(rig.hookNode)) then
            local _, hy = worldToLocal(root, getWorldTranslation(rig.hookNode))
            local natural = math.max(HorseJoint.MIN_Y, ly - HorseJoint.HOOK_DROP_M, math.min(ly, hy))
            say("attach: the joint goes to the horse's own hook height %.2f m (the eye is at %.2f m): the cart pitches down by about %.0f degrees", natural, ly, math.deg(math.atan2(ly - natural, 2.4)))
            ly = natural
        end
    end
    setTranslation(entry.node, HorseJoint.AT[1], ly, HorseJoint.AT[3])
    entry.joint.jointOrigTrans = { getTranslation(entry.node) }
    -- The joint's limits are measured from the rotation between its two frames (this node and the eye's node), so the frames have to be the same when the wagon is straight behind the horse: the joint looks the
    -- way the eye's node looks in the wagon's own frame (a standard trailer's eye looks backwards, 180 degrees; the Wooden Trailer's is turned 90 degrees in its model). With a fixed 180 degrees the Wooden
    -- Trailer's yaw limit was centred 90 degrees off straight: wide open to one side, at its stop at straight on the other.
    local input = attachable.inputAttacherJoints[inputIndex]
    local axisX, _, axisZ = localDirectionToLocal(input.node, trailer.rootNode, 0, 0, 1)
    local yaw = math.atan2(axisX, axisZ)
    setRotation(entry.node, 0, yaw, 0)
    entry.joint.jointOrigRot = { getRotation(entry.node) }
    entry.yawDeg = math.deg(yaw)
    local info = { attacherVehicle = horse, attacherVehicleJointDescIndex = entry.index, attachable = trailer, attachableJointDescIndex = inputIndex }
    local ok, err = pcall(horse.attachImplementFromInfo, horse, info)
    if not ok then
        return false, "attachImplementFromInfo failed: " .. tostring(err)
    end
    entry.watchMs, entry.watchLog = HorseJoint.WATCH_S * 1000, 0
    return true
end

-- What the game's attach does after the call, for WATCH_S seconds, once a second: the smooth attach (attachingIsInProgress, the limits it winds down) pulls the eye onto the joint, so a wagon that
-- stays where it is shows up here as a progress that never ends or an eye that never comes.
HorseJoint.WATCH_S = 60
function HorseJoint:update(dt)
    for horse, entry in pairs(HorseJoint.joints) do
        -- hdJoint trace: every frame for TRACE_S seconds: the frame's length, the horse's speed (from its position), the wagon's speed (its body), how far the eye is from the joint. Jerky = steps in these.
        if entry.traceMs ~= nil and entry.traceMs > 0 then
            entry.traceMs = entry.traceMs - dt
            pcall(function()
                local spec = horse.spec_attacherJoints
                local implement = spec.attachedImplements[1]
                local hx, _, hz = getWorldTranslation(horse.rootNode)
                local jx, jy, jz = getWorldTranslation(entry.node)
                local input = implement.object.spec_attachable.inputAttacherJoints[implement.inputJointDescIndex]
                local ex, ey, ez = getWorldTranslation(input.node)
                local vx, _, vz = getLinearVelocity(implement.object.rootNode)
                local fx, _, fz = localDirectionToLocal(input.rootNode, horse.rootNode, 0, 0, 1)        -- (which way the tongue looks, in the horse's frame: + = to the horse's left)
                local yaw = math.deg(math.atan2(fx, fz))
                local ax, _, az = localDirectionToLocal(input.node, entry.node, 0, 0, 1)                -- (the eye's frame against the joint's: what the joint's limits are measured from, 0 when straight)
                local frameYaw = math.deg(math.atan2(ax, az))
                local bx, _, bz = localDirectionToLocal(implement.object.rootNode, input.rootNode, 0, 0, 1)    -- (which way the wagon's main body looks, in the tongue's frame: the turntable's angle)
                local bodyYaw = math.deg(math.atan2(bx, bz))
                local horseSpeed = entry.traceX ~= nil and math.sqrt((hx - entry.traceX) ^ 2 + (hz - entry.traceZ) ^ 2) / (math.max(dt, 1) / 1000) or 0
                entry.traceX, entry.traceZ = hx, hz
                print(string.format("[HorseDynamics] trace: dt %.0f ms, horse %.2f m/s, wagon %.2f m/s, tongue yaw %.1f deg, eye frame against the joint's %.1f deg, body against the tongue %.1f deg, gap %.3f m (%.3f along, %.3f up)", dt, horseSpeed, math.sqrt(vx * vx + vz * vz), yaw, frameYaw, bodyYaw,
                    math.sqrt((ex - jx) ^ 2 + (ey - jy) ^ 2 + (ez - jz) ^ 2), (ex - jx) * math.sin(math.atan2(jx - hx, jz - hz)) + (ez - jz) * math.cos(math.atan2(jx - hx, jz - hz)), ey - jy))
            end)
        end
        if entry.watchMs ~= nil and entry.watchMs > 0 then
            entry.watchMs = entry.watchMs - dt
            entry.watchLog = entry.watchLog - dt
            if entry.watchLog <= 0 then
                entry.watchLog = 1000
                local spec = horse.spec_attacherJoints
                local implement = spec ~= nil and spec.attachedImplements ~= nil and spec.attachedImplements[1] or nil
                local ok, err = pcall(function()
                    if implement == nil or implement.object == nil then
                        say("watch: nothing attached any more")
                        entry.watchMs = 0
                        return
                    end
                    local jx, jy, jz = getWorldTranslation(entry.node)
                    local input = implement.object.spec_attachable.inputAttacherJoints[implement.inputJointDescIndex]
                    local ex, ey, ez = getWorldTranslation(input.node)
                    local limits = implement.attachingTransLimit or {}
                    local vx, vy, vz = getLinearVelocity(implement.object.rootNode)
                    local pitch = HorseJoint.tonguePitch(implement.object, implement.inputJointDescIndex)
                    say("watch: in progress %s, trans limit %.2f %.2f %.2f, joint index %s, eye off the joint %.2f m (height %.2f), joint %.3f m above the ground, tongue pitch %s, wagon %.2f m/s, horse update ticks running %s",
                        tostring(implement.attachingIsInProgress), limits[1] or -1, limits[2] or -1, limits[3] or -1, tostring(spec.attacherJoints[entry.index].jointIndex),
                        math.sqrt((ex - jx) ^ 2 + (ey - jy) ^ 2 + (ez - jz) ^ 2), ey - jy, jy - HorseHitch.groundY(jx, jz), pitch ~= nil and string.format("%.1f", pitch) or "?",
                        math.sqrt(vx * vx + vy * vy + vz * vz), tostring(horse.getIsActive ~= nil and horse:getIsActive()))
                end)
                if not ok then
                    say("watch failed: %s", tostring(err))
                    entry.watchMs = 0
                end
                -- once: what the game needs to animate the trailer's drawbar the way it does behind a tractor (Attachable: drawbarNode pointed at the joint on attach, updated in onUpdateInterpolation while the two vehicles update in the same loop and the horse is near enough)
                if not entry.diag and implement ~= nil and implement.object ~= nil then
                    entry.diag = true
                    pcall(function()
                        local trailer = implement.object
                        local input = trailer.spec_attachable.inputAttacherJoints[implement.inputJointDescIndex]
                        say("drawbar: node %s, trailer can point moving parts %s, steering axle target %s, update loop horse %s trailer %s, update distance %s of max %s, attach in progress %s",
                            tostring(input.drawbarNode), tostring(trailer.setMovingPartReferenceNode ~= nil), tostring(trailer.spec_attachable.steeringAxleTargetNode), tostring(horse.updateLoopIndex), tostring(trailer.updateLoopIndex),
                            tostring(trailer.currentUpdateDistance), tostring(spec.maxUpdateDistance), tostring(implement.attachingIsInProgress))
                    end)
                end
            end
        end
    end
end

-- Lets go of everything attached to the horse.
function HorseJoint.detach(horse)
    local spec = horse.spec_attacherJoints
    local count = 0
    if spec ~= nil and spec.attachedImplements ~= nil then
        for i = #spec.attachedImplements, 1, -1 do
            local ok = pcall(horse.detachImplement, horse, i)
            count = count + (ok and 1 or 0)
        end
    end
    return count
end

-- The saddle key is the horse's own ATTACH event of the AttacherJoints spec (a second event on the same action is hidden by the first): on a horse its press is HorseHitch.onSaddleAttach (no range or
-- angle check of the game's: the nearest eye behind the hook), its text and visibility are HorseHitch.updateSaddle's, the game's DETACH key does nothing.
if AttacherJoints ~= nil and Utils ~= nil and Utils.overwrittenFunction ~= nil and not HorseJoint.callbacksHooked then
    HorseJoint.callbacksHooked = true
    AttacherJoints.actionEventAttach = Utils.overwrittenFunction(AttacherJoints.actionEventAttach, function(self, superFunc, ...)
        if self.typeName == HorseJoint.TYPE then
            if HorseHitch ~= nil then
                HorseHitch.onSaddleAttach(self, ...)
            end
            return
        end
        return superFunc(self, ...)
    end)
    for _, name in ipairs({ "actionEventDetach", "updateActionEvents" }) do
        if AttacherJoints[name] ~= nil then
            AttacherJoints[name] = Utils.overwrittenFunction(AttacherJoints[name], function(self, superFunc, ...)
                if self.typeName == HorseJoint.TYPE then
                    return
                end
                return superFunc(self, ...)
            end)
        end
    end
end

-- Where the joint is (or would be): a green ring round it, a blue line along the way it looks (the way a trailer's eye has to look within 70 degrees for the game's own prompt), a yellow ring of the game's
-- own 0.7 m reach, and a red line to the eye the saddle key would take. For every horse in a harness. hdJoint show on|off.
HorseJoint.SHOW = false                 -- off: the sequence is seen without the debug drawing (hdJoint show on)
HorseJoint.HOOK_DROP_M = 0.5            -- a cart that holds its eye where it rests is pulled at most this far down to the horse's hook
HorseJoint.MIN_Y = 0.2                  -- the lowest the joint goes (in the horse's model space) to meet an eye
HorseJoint.RING_M = 0.3
HorseJoint.GAME_REACH_M = 0.7

local function ring(x, y, z, ax, ay, az, bx, by, bz, radius, r, g, b)
    local px, py, pz
    for i = 0, 16 do
        local angle = i / 16 * 2 * math.pi
        local c, s = math.cos(angle) * radius, math.sin(angle) * radius
        local qx, qy, qz = x + ax * c + bx * s, y + ay * c + by * s, z + az * c + bz * s
        if px ~= nil then
            drawDebugLine(px, py, pz, r, g, b, qx, qy, qz, r, g, b)
        end
        px, py, pz = qx, qy, qz
    end
end

function HorseJoint:draw()
    if not HorseJoint.SHOW or drawDebugLine == nil or HorseLead == nil or HorseLead.rides == nil then
        return
    end
    for _, ride in ipairs(HorseLead.rides) do
        local horse = ride.vehicle
        local root = horse ~= nil and not horse.isDeleted and horse.components ~= nil and horse.components[1] ~= nil and horse.components[1].node or nil
        if ride.harness and root ~= nil then
            local ok, err = pcall(function()
                local entry = HorseJoint.joints[horse]
                local x, y, z
                if entry ~= nil and entityExists(entry.node) then
                    x, y, z = getWorldTranslation(entry.node)             -- (the joint as it is: lowered to the eye it holds)
                else
                    x, y, z = localToWorld(root, HorseJoint.AT[1], HorseJoint.AT[2], HorseJoint.AT[3])
                end
                local angle = math.rad(HorseJoint.ROT_Y_DEG)
                local dx, dy, dz = localDirectionToWorld(root, math.sin(angle), 0, math.cos(angle))
                ring(x, y, z, 1, 0, 0, 0, 1, 0, HorseJoint.RING_M, 0.2, 1, 0.2)
                ring(x, y, z, 0, 0, 1, 0, 1, 0, HorseJoint.RING_M, 0.2, 1, 0.2)
                ring(x, y, z, 1, 0, 0, 0, 0, 1, HorseJoint.RING_M, 0.2, 1, 0.2)
                ring(x, y, z, 1, 0, 0, 0, 0, 1, HorseJoint.GAME_REACH_M, 1, 1, 0.2)
                drawDebugLine(x, y, z, 0.3, 0.5, 1, x + dx, y + dy, z + dz, 0.3, 0.5, 1)
                if HorseHitch ~= nil and HorseHitch.joinable ~= nil then
                    local target = HorseHitch.joinable(ride)
                    if target ~= nil and target.node ~= nil and entityExists(target.node) then
                        local tx, ty, tz = getWorldTranslation(target.node)
                        drawDebugLine(x, y, z, 1, 0.2, 0.2, tx, ty, tz, 1, 0.2, 0.2)
                    end
                end
            end)
            if not ok and not HorseJoint.drawFailed then
                HorseJoint.drawFailed = true
                say("drawing the ring failed: %s", tostring(err))
            end
        end
    end
end

if addModEventListener ~= nil and not HorseJoint.listening then
    HorseJoint.listening = true
    addModEventListener(HorseJoint)
end

-- The horse the console works on: the one the player rides, else the nearest horse vehicle within REACH_M.
function HorseJoint.horse()
    local player = g_localPlayer
    local riding = player ~= nil and player.getCurrentVehicle ~= nil and player:getCurrentVehicle() or nil
    if riding ~= nil and riding.spec_rideable ~= nil then
        return riding
    end
    if HorseLead == nil or HorseLead.rideables == nil or HorseLead.playerPosition == nil then
        return nil
    end
    local px, _, pz = HorseLead.playerPosition()
    if px == nil then
        return nil
    end
    local best, bestDistance = nil, HorseJoint.REACH_M
    for _, vehicle in ipairs(HorseLead.rideables()) do
        local x, _, z = getWorldTranslation(vehicle.rootNode)
        local d = math.sqrt((x - px) ^ 2 + (z - pz) ^ 2)
        if d < bestDistance then
            best, bestDistance = vehicle, d
        end
    end
    return best
end

-- The pitch (degrees, + = the eye's body points up) of the body that carries the trailer's input joint against the body it hangs on by a component joint: the tongue on its hinge. nil without such a joint.
function HorseJoint.tonguePitch(trailer, inputIndex)
    local input = trailer.spec_attachable.inputAttacherJoints[inputIndex]
    local eyeIndex = nil
    for i, component in ipairs(trailer.components or {}) do
        if component.node == input.rootNode then
            eyeIndex = i
        end
    end
    for _, joint in ipairs(trailer.componentJoints or {}) do
        local indices = joint.componentIndices
        if eyeIndex ~= nil and indices ~= nil and (indices[1] == eyeIndex or indices[2] == eyeIndex) then
            local other = trailer.components[indices[1] == eyeIndex and indices[2] or indices[1]]
            local _, dy, _ = localDirectionToLocal(input.rootNode, other.node, 0, 0, 1)
            return math.deg(math.asin(math.max(-1, math.min(1, dy))))
        end
    end
    return nil
end

-- hdJoint tractor: for the vehicle whose joint you look at (the winch's green ring; a tractor with the wagon, or the horse): the height of its attacher joint above the ground (the number to give the
-- horse: hdJoint height <m>), of the eye, how far the two are apart, and the pitch of the tongue.
function HorseJoint.dump()
    local winch = g_currentMission ~= nil and g_currentMission.winchTow or nil
    local target = winch ~= nil and winch.pick ~= nil and winch.pick() or nil
    if target == nil or target.vehicle == nil then
        return "look at a joint (the green ring of the winch) of a vehicle that has something attached"
    end
    -- the joint in view: a tractor's own joint, or the eye of the trailer hanging on it (then the tractor is the vehicle)
    local vehicle = target.vehicle
    if (vehicle.spec_attacherJoints == nil or #(vehicle.spec_attacherJoints.attachedImplements or {}) == 0) and vehicle.getAttacherVehicle ~= nil and vehicle:getAttacherVehicle() ~= nil then
        vehicle = vehicle:getAttacherVehicle()
    end
    local spec = vehicle.spec_attacherJoints
    local lines = {}
    -- only what hangs on the joint in view; when that joint holds nothing, all that the vehicle has attached (said so)
    local function holdsSomething(node)
        for _, implement in ipairs(spec ~= nil and spec.attachedImplements or {}) do
            local joint = spec.attacherJoints[implement.jointDescIndex]
            if joint ~= nil and joint.jointTransform == node then
                return true
            end
        end
        return false
    end
    local onlyThis = holdsSomething(target.node)
    if not onlyThis and spec ~= nil and #(spec.attachedImplements or {}) > 0 then
        say("dump: the joint in view holds nothing, these are the vehicle's attached ones:")
    end
    for _, implement in ipairs(spec ~= nil and spec.attachedImplements or {}) do
        pcall(function()
            local joint = spec.attacherJoints[implement.jointDescIndex]
            if onlyThis and joint.jointTransform ~= target.node then
                return
            end
            local input = implement.object.spec_attachable.inputAttacherJoints[implement.inputJointDescIndex]
            local jx, jy, jz = getWorldTranslation(joint.jointTransform)
            local ex, ey, ez = getWorldTranslation(input.node)
            local _, ly, _ = worldToLocal(vehicle.components[1].node, jx, jy, jz)
            local pitch = HorseJoint.tonguePitch(implement.object, implement.inputJointDescIndex)
            local fx, _, fz = localDirectionToLocal(input.node, joint.jointTransform, 0, 0, 1)
            say("dump: the eye's frame against this joint's: %.1f degrees about the vertical (what its limits are measured from; the horse's joint is made to have 0 when the wagon is straight)", math.deg(math.atan2(fx, fz)))
            lines[#lines + 1] = say("dump: %s, joint %d (%s) is %.3f m above the ground (%.3f m above its vehicle's root); the eye of %s is %.3f m above the ground, %.3f m from the joint; the tongue's pitch %s; the trailer declares %.2f m",
                vehicle.getName ~= nil and vehicle:getName() or tostring(vehicle.typeName), implement.jointDescIndex, tostring(joint.jointType), jy - HorseHitch.groundY(jx, jz), ly,
                implement.object.getName ~= nil and implement.object:getName() or "the trailer", ey - HorseHitch.groundY(ex, ez), math.sqrt((ex - jx) ^ 2 + (ey - jy) ^ 2 + (ez - jz) ^ 2),
                pitch ~= nil and string.format("%.1f degrees", pitch) or "unknown", input.attacherHeight or -1)
        end)
    end
    if #lines == 0 then
        return "nothing is attached to that vehicle (hitch the wagon to it first)"
    end
    return table.concat(lines, "\n")
end

function HorseJoint:command(argument, a, b, c)
    argument = argument or "info"
    if argument == "rot" then
        local degrees = tonumber(a)
        if degrees == nil then
            return "usage: hdJoint rot <degrees about the vertical axis>: now " .. HorseJoint.ROT_Y_DEG .. " (a joint made after this)"
        end
        HorseJoint.ROT_Y_DEG = degrees
        return say("the joint of a horse made from now on is turned %d degrees (remove and add it again)", degrees)
    elseif argument == "tractor" or argument == "dump" then
        return HorseJoint.dump()
    elseif argument == "height" then
        HorseHitch.EYE_HEIGHT_M = tonumber(a)
        return say("the horse holds a trailer's eye %s", HorseHitch.EYE_HEIGHT_M ~= nil and string.format("%.3f m above the ground, whatever the hinge reaches (hdJoint height clears it)", HorseHitch.EYE_HEIGHT_M) or "as high as the tongue's hinge reaches (towards the hook)")
    elseif argument == "trace" then
        local horse = HorseJoint.horse()
        local entry = horse ~= nil and HorseJoint.joints[horse] or nil
        if entry == nil then
            return "no horse with the joint (hitch the wagon first)"
        end
        entry.traceMs, entry.traceX = 10000, nil
        return say("tracing every frame for 10 seconds: walk the horse now, then send the 'trace:' lines of the log")
    elseif argument == "show" then
        HorseJoint.SHOW = a ~= "off"
        return say("the rings round the horse's joint are %s", HorseJoint.SHOW and "on" or "off")
    elseif argument == "at" then
        local x, y, z = tonumber(a), tonumber(b), tonumber(c)
        if x == nil or y == nil or z == nil then
            return string.format("usage: hdJoint at <x> <y> <z> in the horse's model space: now %.2f %.2f %.2f", HorseJoint.AT[1], HorseJoint.AT[2], HorseJoint.AT[3])
        end
        HorseJoint.AT = { x, y, z }
        return say("the joint of a horse made from now on is at %.2f %.2f %.2f (remove and add it again)", x, y, z)
    end
    local horse = HorseJoint.horse()
    if horse == nil then
        return "no horse vehicle within " .. HorseJoint.REACH_M .. " m (lead one first: hdLead start)"
    end
    local spec = horse.spec_attacherJoints
    if argument == "info" then
        local entry = HorseJoint.joints[horse]
        local lines = { string.format("horse type %s, attacher joints specialization %s, the injection is %s", tostring(horse.typeName), spec ~= nil and "THERE" or "MISSING", HorseJoint.INJECT and "on" or "off") }
        if spec ~= nil then
            lines[#lines + 1] = string.format("%d attacher joint(s), %d attached implement(s), this mod's joint %s", #spec.attacherJoints, #(spec.attachedImplements or {}), entry ~= nil and ("index " .. entry.index) or "not made")
        end
        local text = table.concat(lines, "; ")
        say("%s", text)
        return text
    elseif argument == "add" then
        local ok, why = HorseJoint.add(horse)
        return ok and "the horse has its attacher joint" or ("failed: " .. tostring(why))
    elseif argument == "remove" then
        return HorseJoint.remove(horse) and "the joint is off the horse" or "the horse has none of this mod's joints"
    elseif argument == "detach" then
        return string.format("%d implement(s) detached", HorseJoint.detach(horse))
    elseif argument == "attach" then
        local winch = g_currentMission ~= nil and g_currentMission.winchTow or nil
        local target = winch ~= nil and winch.pick ~= nil and winch.pick() or nil
        if target == nil then
            return "look at a trailer's drawbar eye within 6 m (FS25_WinchTow picks it)"
        end
        local ok, why = HorseJoint.attach(horse, target)
        if ok then
            return say("attached: %s", tostring(target.vehicle.configFileName or "vehicle"))
        end
        return say("not attached: %s", tostring(why))
    end
    return "hdJoint info | add | attach | detach | remove | rot <degrees> | at <x> <y> <z>"
end

if addConsoleCommand ~= nil then
    addConsoleCommand("hdJoint", "HorseDynamics spike: a real attacher joint on the horse (info | add | attach | detach | remove | rot <degrees> | at <x> <y> <z>)", "command", HorseJoint)
end
