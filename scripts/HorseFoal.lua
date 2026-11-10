-- Points every horse subtype's rideable vehicle at the baked foal (horseFoal.xml -> model/horseFoal.i3d)
HorseFoal = {}
HorseFoal.dir = g_currentModDirectory

function HorseFoal.apply()
    local system = g_currentMission ~= nil and g_currentMission.animalSystem or nil
    if system == nil or system.subTypes == nil then
        Logging.warning("[HorseFoal] no animal system yet")
        return
    end
    local n = 0
    for _, subType in ipairs(system.subTypes) do
        local f = subType.rideableFilename
        if f ~= nil and string.find(f, "horse/horse.xml", 1, true) ~= nil then
            subType.rideableFilename = HorseFoal.dir .. "horseFoal.xml"
            n = n + 1
        end
    end
    Logging.info("[HorseFoal] %d horse subtypes now ride the foal model", n)
end

function HorseFoal:loadMap(name)
    HorseFoal.apply()
end

addModEventListener(HorseFoal)
