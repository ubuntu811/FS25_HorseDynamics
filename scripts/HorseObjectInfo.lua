--[[
    HorseObjectInfo.lua -- a vehicle specialization shared by the horse objects (the ball, the jumps, the harness): the info box at the bottom right (what you look at) gets the weight, as the game's own pallets
    show theirs (PlayerHUDUpdater:showPalletInfo: infohud_mass, formatMass of the total mass). With the Weight option of the ball this is the weight that was bought.
]]
HorseObjectInfo = {}

function HorseObjectInfo.prerequisitesPresent(_)
    return true
end

function HorseObjectInfo.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "showInfo", HorseObjectInfo.showInfo)
end

function HorseObjectInfo:showInfo(superFunc, box)
    local ok, mass = pcall(self.getTotalMass, self)
    if ok and mass ~= nil then
        box:addLine(g_i18n:getText("infohud_mass"), g_i18n:formatMass(mass))
    end
    superFunc(self, box)
end
