--[[
    HorseSaddleItemVehicle.lua -- the vehicle specialization of the loose saddle (vehicles/horseSaddle): it only keeps the list of the objects that exist (HorseSaddleItem.items). The logic is in HorseSaddleItem.lua.
]]
HorseSaddleItemVehicle = {}
function HorseSaddleItemVehicle.prerequisitesPresent(_) return true end
function HorseSaddleItemVehicle.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", HorseSaddleItemVehicle)
    SpecializationUtil.registerEventListener(vehicleType, "onDelete", HorseSaddleItemVehicle)
end
function HorseSaddleItemVehicle:onLoad(_)
    if HorseSaddleItem ~= nil then HorseSaddleItem.items[self] = true end
end
function HorseSaddleItemVehicle:onDelete()
    if HorseSaddleItem ~= nil then HorseSaddleItem.items[self] = nil end
end
