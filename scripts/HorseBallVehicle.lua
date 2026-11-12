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

-- The game only gives the physics body a new mass when it changes by more than 20 kg (Vehicle:updateMass: 0.02 < math.abs(lastMass - mass)), so a weight option of a few kilos never reached the body: the vehicle
-- said 0.5 kg, the body was 3 kg, and the hands (their joint is sized from the vehicle's mass) could not lift it. After the game's update the body is given exactly the mass the vehicle has.
function HorseBallVehicle.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "updateMass", HorseBallVehicle.updateMass)
end

function HorseBallVehicle:updateMass(superFunc)
    superFunc(self)
    if self.isServer then
        for _, component in ipairs(self.components) do
            if component.isDynamic and component.mass ~= nil and component.node ~= nil and entityExists(component.node) and math.abs((component.lastMass or 0) - component.mass) > 1e-7 then
                setMass(component.node, component.mass)
                component.lastMass = component.mass
            end
        end
    end
end

function HorseBallVehicle.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onUpdate", HorseBallVehicle)
end

function HorseBallVehicle:onUpdate(dt)
    if self.isServer and HorseBall ~= nil then
        HorseBall.kick(self, dt)
    end
end
