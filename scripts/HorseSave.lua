--[[
    HorseSave.lua -- what the horses wear and pull survives a save: <savegame>/horseDynamics.xml.

    The game saves a horse that was taken out of its pasture (a vehicle, "ridden out") with its place and its animal data, but not what this mod put on it. This file saves, for each horse vehicle that is
    led or harnessed (HorseLead.rides): its vehicle's unique id, the harness and its gear, the halter (a leashed horse comes back standing, halter on: the leash itself needs your hand and your tool), and
    the hitch: the unique id of the vehicle it pulls, the kind of joint (hitch | drawbar eye) and the joint's index. A hitched LOG is not saved (a log has no id that lasts).
    Loading (when the mission starts) only reads the file; the horses are restored one at a time in update(), as soon as the vehicle is there, its harness rig is built (the hitch needs it) and the
    joint can be found, for TIMEOUT_S seconds at most. A record whose vehicle never shows up (sold, deleted) is dropped, and the file is written again on the next save without it.
    Kept apart from the engine: snapshot() and step() take what they need in `env` (the tests in tests/horse_save_test.lua use fakes).
]]
HorseSave = {}
HorseSave.FILE = "horseDynamics.xml"
HorseSave.TIMEOUT_S = 90
HorseSave.pending = {}

local function say(format, ...)
    print(string.format("[HorseDynamics] save: " .. format, ...))
end

-- The records of the rides that are worth saving. env.uniqueId(vehicle) -> id | nil, env.jointIndex(hitch) -> number | nil.
function HorseSave.snapshot(rides, env)
    local records = {}
    for _, ride in ipairs(rides) do
        local vehicle = ride.vehicle
        local id = vehicle ~= nil and not vehicle.isDeleted and env.uniqueId(vehicle) or nil
        local halter = ride.halterOn or ride.leash
        if id ~= nil and (ride.harness or halter or ride.hitch ~= nil) then
            local record = { vehicle = id, harness = ride.harness and true or nil, gear = ride.harness and ride.harnessGear or nil, halter = halter and true or nil }
            local hitch = ride.hitch
            if hitch ~= nil and not hitch.isLog and hitch.vehicle ~= nil then
                local target = env.uniqueId(hitch.vehicle)
                local index = env.jointIndex(hitch)
                if target ~= nil and index ~= nil then
                    record.hitch = { vehicle = target, kind = hitch.kind, index = index }
                end
            end
            records[#records + 1] = record
        end
    end
    return records
end

-- One step of restoring one record. env: vehicleById(id), claimed(vehicle), newRide(record, vehicle) -> ride, target(record.hitch) -> target | nil, hitch(ride, target).
-- Returns true when the record is done (restored, not needed, or given up).
function HorseSave.step(record, dt, env)
    record.waited = (record.waited or 0) + dt
    if record.waited > HorseSave.TIMEOUT_S * 1000 then
        say("gave up on the horse %s (%s)", tostring(record.vehicle), record.ride == nil and "its vehicle did not show up" or "its hitch could not be restored")
        return true
    end
    if record.ride == nil then
        local vehicle = env.vehicleById(record.vehicle)
        if vehicle == nil then
            return false
        end
        if env.claimed(vehicle) then
            return true
        end
        record.ride = env.newRide(record, vehicle)
        return record.hitch == nil
    end
    local ride = record.ride
    if ride.hitch ~= nil or ride.joined ~= nil then
        return true
    end
    if ride.rig == nil then
        return false
    end
    local target = env.target(record.hitch)
    if target == nil then
        return false
    end
    env.hitch(ride, target)
    return true
end

-- ===== engine side =====
local function uniqueIdOf(vehicle)
    return vehicle.getUniqueId ~= nil and vehicle:getUniqueId() or vehicle.uniqueId
end

local function winch()
    local api = g_currentMission ~= nil and g_currentMission.winchTow or nil
    return api ~= nil and api.jointsOf ~= nil and api or nil
end

local function vehicleById(id)
    local system = g_currentMission ~= nil and g_currentMission.vehicleSystem or nil
    return system ~= nil and system:getVehicleByUniqueId(id) or nil
end

local function savePath()
    local info = g_currentMission ~= nil and g_currentMission.missionInfo or nil
    return info ~= nil and info.savegameDirectory ~= nil and (info.savegameDirectory .. "/" .. HorseSave.FILE) or nil
end

HorseSave.env = {
    uniqueId = uniqueIdOf,
    -- the joint of the pulled vehicle that the hitch sits on, by its node: its index among WinchTow's joints of that vehicle
    jointIndex = function(hitch)
        local api = winch()
        if api == nil then
            return nil
        end
        for _, joint in ipairs(api.jointsOf(hitch.vehicle, true)) do
            if joint.node == hitch.node then
                return joint.index
            end
        end
        return nil
    end,
    vehicleById = vehicleById,
    claimed = function(vehicle)
        return HorseLead.isClaimed(vehicle)
    end,
    newRide = function(record, vehicle)
        local x, _, z = getWorldTranslation(vehicle.rootNode)
        local ride = { vehicle = vehicle, known = {}, from = { x, z }, waited = 0, stableMs = 0, stay = true,
            harness = record.harness, harnessGear = record.gear, halterOn = record.halter }
        HorseLead.claimVehicle(vehicle)
        HorseLead.rides[#HorseLead.rides + 1] = ride
        say("the horse %s is back in its gear (harness %s, halter %s)", tostring(record.vehicle), tostring(record.harness == true), tostring(record.halter == true))
        return ride
    end,
    target = function(hitch)
        local api = winch()
        local vehicle = hitch ~= nil and vehicleById(hitch.vehicle) or nil
        if api == nil or vehicle == nil then
            return nil
        end
        for _, joint in ipairs(api.jointsOf(vehicle, true)) do
            if joint.kind == hitch.kind and joint.index == hitch.index then
                joint.vehicle = vehicle
                return joint
            end
        end
        return nil
    end,
    hitch = function(ride, target)
        say("hitching the horse to %s again", tostring(getName ~= nil and target.node ~= nil and getName(target.node) or "?"))
        HorseHitch.start(ride, target)
    end,
}

function HorseSave.save()
    local path = savePath()
    if path == nil or HorseLead == nil then
        return
    end
    local records = HorseSave.snapshot(HorseLead.rides, HorseSave.env)
    -- records still waiting to be restored are kept (a save right after loading must not lose them)
    for _, record in ipairs(HorseSave.pending) do
        if record.ride == nil then
            records[#records + 1] = { vehicle = record.vehicle, harness = record.harness, gear = record.gear, halter = record.halter, hitch = record.hitch }
        end
    end
    local xml = XMLFile.create("HorseSave", path, "horseDynamics")
    if xml == nil then
        say("could not write %s", path)
        return
    end
    for i, record in ipairs(records) do
        local key = string.format("horseDynamics.ride(%d)", i - 1)
        xml:setString(key .. "#vehicle", record.vehicle)
        xml:setBool(key .. "#harness", record.harness == true)
        xml:setString(key .. "#gear", record.gear or "rope")
        xml:setBool(key .. "#halter", record.halter == true)
        if record.hitch ~= nil then
            xml:setString(key .. ".hitch#vehicle", record.hitch.vehicle)
            xml:setString(key .. ".hitch#kind", record.hitch.kind)
            xml:setInt(key .. ".hitch#index", record.hitch.index)
        end
    end
    xml:save()
    xml:delete()
    say("%d horse(s) written to %s", #records, HorseSave.FILE)
end

function HorseSave.load()
    HorseSave.pending = {}
    local path = savePath()
    if path == nil then
        return
    end
    local xml = XMLFile.load("HorseSave", path)
    if xml == nil then
        return
    end
    local i = 0
    while true do
        local key = string.format("horseDynamics.ride(%d)", i)
        if not xml:hasProperty(key) then
            break
        end
        local record = { vehicle = xml:getString(key .. "#vehicle"), harness = xml:getBool(key .. "#harness", false) or nil, gear = xml:getString(key .. "#gear", "rope"), halter = xml:getBool(key .. "#halter", false) or nil }
        if xml:hasProperty(key .. ".hitch") then
            record.hitch = { vehicle = xml:getString(key .. ".hitch#vehicle"), kind = xml:getString(key .. ".hitch#kind"), index = xml:getInt(key .. ".hitch#index") }
        end
        if record.vehicle ~= nil then
            HorseSave.pending[#HorseSave.pending + 1] = record
        end
        i = i + 1
    end
    xml:delete()
    say("%d horse(s) read from %s, restored as their vehicles appear", #HorseSave.pending, HorseSave.FILE)
end

function HorseSave.update(dt)
    for i = #HorseSave.pending, 1, -1 do
        local ok, done = pcall(HorseSave.step, HorseSave.pending[i], dt, HorseSave.env)
        if not ok then
            say("restore failed: %s", tostring(done))
            done = true
        end
        if done then
            table.remove(HorseSave.pending, i)
        end
    end
end

if BaseMission ~= nil and Utils ~= nil and not HorseSave.hooked then
    HorseSave.hooked = true
    BaseMission.loadMap = Utils.overwrittenFunction(BaseMission.loadMap, function(mission, superFunc, ...)
        local result = superFunc(mission, ...)
        if g_messageCenter ~= nil and MessageType ~= nil then
            g_messageCenter:subscribeOneshot(MessageType.CURRENT_MISSION_START, function() HorseSave.load() end)
        end
        if FSCareerMissionInfo ~= nil and not HorseSave.saveHooked then
            HorseSave.saveHooked = true
            FSCareerMissionInfo.saveToXMLFile = Utils.appendedFunction(FSCareerMissionInfo.saveToXMLFile, function() HorseSave.save() end)
        end
        return result
    end)
end
