--[[
    HorseBallVehicle.lua -- the vehicle specialization of the horse ball (vehicles/horseBall: a store item of the objects category, a dynamic rigid body like a pallet). A ball that is
    updated here gets kicked by the horses that run into it: HorseBall.kick (the game's own football is shot the same way, Football:shoot: addImpulse with mass * velocity).
]]
HorseBallVehicle = {}
HorseBallVehicle.modName = g_currentModName

function HorseBallVehicle.prerequisitesPresent(_)
    return true
end

-- the shop option "Weight" (the game's configuration mechanism; the items' additionalMass is applied by the game: VehicleConfigurationDataAdditionalMass)
function HorseBallVehicle.initSpecialization()
    g_vehicleConfigurationManager:addConfigurationType("horseBallWeight", g_i18n:getText("configuration_horseBallWeight", HorseBallVehicle.modName), nil, VehicleConfigurationItem)
end

function HorseBallVehicle.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onUpdate", HorseBallVehicle)
end

function HorseBallVehicle:onUpdate(dt)
    if self.isServer and HorseBall ~= nil then
        HorseBall.kick(self, dt)
    end
end
