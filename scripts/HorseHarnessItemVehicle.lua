--[[
    HorseHarnessItemVehicle.lua -- the vehicle specialization of the harness object (vehicles/horseHarness): it only keeps the list of the objects that exist (HorseHarnessItem.items). The logic is in HorseHarnessItem.lua.
]]
HorseHarnessItemVehicle = {}
function HorseHarnessItemVehicle.prerequisitesPresent(_) return true end
function HorseHarnessItemVehicle.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", HorseHarnessItemVehicle)
    SpecializationUtil.registerEventListener(vehicleType, "onDelete", HorseHarnessItemVehicle)
end
function HorseHarnessItemVehicle:onLoad(_)
    if HorseHarnessItem ~= nil then HorseHarnessItem.items[self] = true end
end
function HorseHarnessItemVehicle:onDelete()
    if HorseHarnessItem ~= nil then HorseHarnessItem.items[self] = nil end
end

