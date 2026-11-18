-- plain Lua with a fake engine: the attacher joint spike (HorseJoint): the type injection, the joint on the horse, the attach and detach calls, the console
local passed, failed = 0, 0
local realPrint = print
local log = {}
print = function(text) log[#log + 1] = text end
local function check(name, ok) if ok then passed = passed + 1 else failed = failed + 1; realPrint("  FAIL " .. name) end end

g_currentModDirectory = "mods/FS25_HorseDynamics/"
local consoleCommands = {}
addConsoleCommand = function(name, help, method, target) consoleCommands[name] = { method = method, target = target } end
Utils = { appendedFunction = function(old, new) return function(...) old(...); new(...) end end }
TypeManager = { validateTypes = function(self) end }
ADDED = nil
g_vehicleTypeManager = {
    types = { horse = { specializationsByName = {} }, tractor = { specializationsByName = {} } },
    getTypes = function(self) return self.types end,
    addSpecialization = function(self, typeName, specName) self.types[typeName].specializationsByName[specName] = true; ADDED = { typeName, specName } end,
}
dofile("scripts/HorseJoint.lua")

-- the type injection: when the vehicle types are validated the horse type gets the attacher joints specialization (once), no other type
TypeManager.validateTypes({ typeName = "placeable" })
check("another kind of types (placeables): nothing is added", ADDED == nil)
TypeManager.validateTypes({ typeName = "vehicle" })
check("the vehicle types validated: the horse type gets the attacherJoints specialization", ADDED ~= nil and ADDED[1] == "horse" and ADDED[2] == "attacherJoints" and g_vehicleTypeManager.types.tractor.specializationsByName.attacherJoints == nil)
ADDED = nil
TypeManager.validateTypes({ typeName = "vehicle" })
check("... and only once (the type has it already)", ADDED == nil)
g_vehicleTypeManager.types.horse.specializationsByName = {}
HorseJoint.INJECT = false
TypeManager.validateTypes({ typeName = "vehicle" })
check("HorseJoint.INJECT = false: the horse is left alone", ADDED == nil)
HorseJoint.INJECT = true
local savedHorse = g_vehicleTypeManager.types.horse
g_vehicleTypeManager.types.horse = nil
check("no horse type (another game version): no error, said so", pcall(TypeManager.validateTypes, { typeName = "vehicle" }) == true)
g_vehicleTypeManager.types.horse = savedHorse

-- the joint on the horse
local nodes, nextNode, deleted, translated, rotated = {}, 100, {}, {}, {}
createTransformGroup = function(name) nextNode = nextNode + 1; nodes[nextNode] = { name = name }; return nextNode end
link = function(parent, node) nodes[node].parent = parent end
setTranslation = function(node, x, y, z) translated[node] = { x, y, z } end
setRotation = function(node, x, y, z) rotated[node] = { x, y, z } end
getTranslation = function(node) local t = translated[node] or { 0, 0, 0 }; return t[1], t[2], t[3] end
getRotation = function(node) local r = rotated[node] or { 0, 0, 0 }; return r[1], r[2], r[3] end
delete = function(node) deleted[#deleted + 1] = node end
local eyeHeight = 0.45
local eyeAxis = { 1, 0, 0 }                          -- the eye's node looks sideways in the wagon's frame (the Wooden Trailer's, turned 90 degrees)
localDirectionToLocal = function() return eyeAxis[1], eyeAxis[2], eyeAxis[3] end
getWorldTranslation = function() return 0, eyeHeight, -3 end
worldToLocal = function(node, x, y, z) return x, y, z end
local loadedXml, xmlDeleted = nil, false
XMLFile = { load = function(name, path, schema) loadedXml = { name = name, path = path, schema = schema }; return { delete = function() xmlDeleted = true end } end }
local loaderCalls = {}
local function makeHorse()
    local horse = { spec_attacherJoints = { attacherJoints = {}, attachedImplements = {} }, components = { { node = 10 } }, xmlFile = { schema = "HORSE_SCHEMA" }, i3dMappings = {}, typeName = "horse" }
    horse.loadAttacherJointFromXML = function(self, joint, xml, key, index)
        loaderCalls[#loaderCalls + 1] = { key = key, index = index }
        joint.jointTransformOrig = 999
        joint.jointTransform = index == 0 and nextNode + 0 or 0
        return true
    end
    horse.detachImplement = function(self, i) horse.detached = (horse.detached or 0) + 1; table.remove(horse.spec_attacherJoints.attachedImplements, i) end
    horse.attachImplementFromInfo = function(self, info) horse.info = info end
    horse.getActiveFarm = function() return 1 end
    return horse
end
local horse = makeHorse()
local ok = HorseJoint.add(horse)
local entry = HorseJoint.joints[horse]
check("add: the horse gets a node under its root component at the hook, turned about the vertical axis (a rear joint looks backwards)", ok == true and entry ~= nil and nodes[entry.node].parent == 10
    and translated[entry.node][1] == 0 and translated[entry.node][2] == 1.08 and translated[entry.node][3] == -1.06 and math.abs(rotated[entry.node][2] - math.pi) < 1e-9)
check("... registered in the horse's i3d mappings the way the game's loader makes them ({ nodeId, rootNode })", horse.i3dMappings.rfHitchJoint ~= nil and horse.i3dMappings.rfHitchJoint.nodeId == entry.node and horse.i3dMappings.rfHitchJoint.rootNode == 10)
check("... the xml is read with the horse's own schema from the mod's xml folder and deleted again", loadedXml ~= nil and loadedXml.path == "mods/FS25_HorseDynamics/xml/horseJoint.xml" and loadedXml.schema == "HORSE_SCHEMA" and xmlDeleted == true)
check("... the game's loader is asked for the first joint of that xml, with the number of joints the horse has so far", loaderCalls[1].key == "vehicle.attacherJoints.attacherJoint(0)" and loaderCalls[1].index == 0)
check("... it has the original rotation and translation the game's post load would have stored (attach reads them)", entry.joint.jointOrigRot ~= nil and math.abs(entry.joint.jointOrigRot[2] - math.pi) < 1e-9 and entry.joint.jointOrigTrans ~= nil and entry.joint.jointOrigTrans[2] == 1.08)
check("... the joint is in the list of the horse's joints with its index", #horse.spec_attacherJoints.attacherJoints == 1 and horse.spec_attacherJoints.attacherJoints[1] == entry.joint and entry.joint.index == 1 and entry.index == 1)
check("add again: nothing more is made", HorseJoint.add(horse) == true and #horse.spec_attacherJoints.attacherJoints == 1 and #loaderCalls == 1)

local plain = { components = { { node = 11 } } }
local added, why = HorseJoint.add(plain)
check("a horse without the specialization (the injection did not work): refused, saying why", added == false and why:find("type injection", 1, true) ~= nil)

local refusing = makeHorse()
refusing.loadAttacherJointFromXML = function() return false end
local deletedBefore = #deleted
added, why = HorseJoint.add(refusing)
check("the game's loader refuses the joint: refused, the node is deleted again and the mapping taken off", added == false and why:find("refused", 1, true) ~= nil and #deleted == deletedBefore + 1 and refusing.i3dMappings.rfHitchJoint == nil and #refusing.spec_attacherJoints.attacherJoints == 0)
local broken = makeHorse()
broken.loadAttacherJointFromXML = function() error("boom") end
added, why = HorseJoint.add(broken)
check("an error in the loader is caught: refused, said", added == false and why:find("boom", 1, true) ~= nil and broken.i3dMappings.rfHitchJoint == nil)
XMLFile.load = function() return nil end
added, why = HorseJoint.add(makeHorse())
check("an xml that cannot be read: refused, saying which", added == false and why:find("horseJoint.xml", 1, true) ~= nil)
XMLFile.load = function(name, path, schema) loadedXml = { name = name, path = path, schema = schema }; return { delete = function() xmlDeleted = true end } end

-- the attach: the info the game's Q handler uses
local trailer = { configFileName = "wooden.xml", spec_attachable = { inputAttacherJoints = { { node = 5 }, { node = 6 } } }, isAttachAllowed = function() return true end }
ok, why = HorseJoint.attach(horse, { vehicle = trailer, node = 6 })
check("attach: the game's attachImplementFromInfo is called with the horse, its joint, the trailer and the trailer's input joint that was picked (the second)", ok == true and horse.info ~= nil
    and horse.info.attacherVehicle == horse and horse.info.attacherVehicleJointDescIndex == 1 and horse.info.attachable == trailer and horse.info.attachableJointDescIndex == 2)
ok, why = HorseJoint.attach(horse, { vehicle = trailer, node = 77 })
check("a joint that is not an input joint of that vehicle (its own hitch): refused, saying so", ok == false and why:find("not an input joint", 1, true) ~= nil)
check("... the joint was lowered to the height of the eye (it would lift the drawbar otherwise), keeping the hook's place behind the horse", translated[HorseJoint.joints[horse].node][2] == 0.45 and translated[HorseJoint.joints[horse].node][3] == -1.06
    and HorseJoint.joints[horse].joint.jointOrigTrans[2] == 0.45)
check("... the joint looks the way the eye's node looks in the wagon's frame (90 degrees here), so the limits are centred on straight (it was a fixed 180)", math.abs(rotated[HorseJoint.joints[horse].node][2] - math.pi / 2) < 1e-9 and math.abs(HorseJoint.joints[horse].joint.jointOrigRot[2] - math.pi / 2) < 1e-9)
eyeAxis = { 0, 0, -1 }
HorseJoint.attach(horse, { vehicle = trailer, node = 6 })
check("... and a standard trailer's eye, which looks backwards, gives the 180 degrees the joint was made with", math.abs(math.abs(rotated[HorseJoint.joints[horse].node][2]) - math.pi) < 1e-9)
eyeAxis = { 1, 0, 0 }
eyeHeight = 3
HorseJoint.attach(horse, { vehicle = trailer, node = 6 })
check("... an eye higher than the hook does not lift the joint above the hook", translated[HorseJoint.joints[horse].node][2] == 1.08)
eyeHeight = 0.45
ok, why = HorseJoint.attach(horse, { vehicle = { spec_attachable = nil }, node = 1 })
check("a vehicle that cannot be attached at all: refused", ok == false and why:find("cannot be attached", 1, true) ~= nil)
trailer.isAttachAllowed = function() return false, "wrong farm" end
ok, why = HorseJoint.attach(horse, { vehicle = trailer, node = 6 })
check("the game does not allow it (the farm, a brand ...): refused with its warning", ok == false and why:find("wrong farm", 1, true) ~= nil)
trailer.isAttachAllowed = function() return true end
horse.attachImplementFromInfo = function() error("physics said no") end
ok, why = HorseJoint.attach(horse, { vehicle = trailer, node = 6 })
check("an error in the game's attach code is caught and said", ok == false and why:find("physics said no", 1, true) ~= nil)
horse.attachImplementFromInfo = function(self, info) horse.info = info end
local fresh = makeHorse()
ok = HorseJoint.attach(fresh, { vehicle = trailer, node = 5 })
check("attach to a horse without the joint makes it first", ok == true and HorseJoint.joints[fresh] ~= nil and fresh.info.attachableJointDescIndex == 1)

-- detach and remove
horse.spec_attacherJoints.attachedImplements = { { object = trailer }, { object = trailer } }
check("detach: every attached implement is let go (last first)", HorseJoint.detach(horse) == 2 and horse.detached == 2 and #horse.spec_attacherJoints.attachedImplements == 0)
local jointNode = HorseJoint.joints[horse].node
deletedBefore = #deleted
check("remove: the joint is taken off the horse, the mapping and both nodes of it are deleted", HorseJoint.remove(horse) == true and #horse.spec_attacherJoints.attacherJoints == 0 and horse.i3dMappings.rfHitchJoint == nil
    and HorseJoint.joints[horse] == nil and #deleted == deletedBefore + 2)
check("remove of a horse that has none: false", HorseJoint.remove(horse) == false)

-- the console
local mine = makeHorse()
HorseJoint.horse = function() return mine end
local command = consoleCommands.hdJoint
check("the console command hdJoint is registered", command ~= nil and command.method == "command" and command.target == HorseJoint)
local text = HorseJoint.command(HorseJoint, "info")
check("info says the type, whether the specialization is there, the number of joints", text:find("horse type horse", 1, true) ~= nil and text:find("THERE", 1, true) ~= nil and text:find("0 attacher joint", 1, true) ~= nil and text:find("not made", 1, true) ~= nil)
check("add makes the joint, info then says so", HorseJoint.command(HorseJoint, "add"):find("has its attacher joint", 1, true) ~= nil and HorseJoint.command(HorseJoint, "info"):find("index 1", 1, true) ~= nil)
g_currentMission = { winchTow = { pick = function() return { vehicle = trailer, node = 6 } end } }
check("attach picks what you look at (FS25_WinchTow) and attaches it", HorseJoint.command(HorseJoint, "attach"):find("attached", 1, true) ~= nil and mine.info ~= nil and mine.info.attachable == trailer)
g_currentMission.winchTow.pick = function() return nil end
check("attach with nothing in view says what to look at", HorseJoint.command(HorseJoint, "attach"):find("look at a trailer", 1, true) ~= nil)
check("detach and remove", HorseJoint.command(HorseJoint, "detach"):find("implement(s) detached", 1, true) ~= nil and HorseJoint.command(HorseJoint, "remove"):find("off the horse", 1, true) ~= nil)
check("rot and at change what a horse made from now on gets", HorseJoint.command(HorseJoint, "rot", "90"):find("90 degrees", 1, true) ~= nil and HorseJoint.ROT_Y_DEG == 90
    and HorseJoint.command(HorseJoint, "at", "0", "1", "-2"):find("0.00 1.00 -2.00", 1, true) ~= nil and HorseJoint.AT[3] == -2)
check("rot and at without numbers say how they are used", HorseJoint.command(HorseJoint, "rot"):find("usage", 1, true) ~= nil and HorseJoint.command(HorseJoint, "at", "1"):find("usage", 1, true) ~= nil)
HorseJoint.horse = function() return nil end
check("no horse near: said", HorseJoint.command(HorseJoint, "add"):find("no horse vehicle", 1, true) ~= nil)

print = realPrint
print(string.format("horsejoint_test: %d/%d passed", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
