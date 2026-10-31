--[[
    HorseDynamics.lua -- the mod's entry: keys, console commands and the per-frame update. The behaviour is in HorseLead.lua.

    Keys (on foot and in a vehicle): Right Ctrl + C calls the nearest horse (a horse of a pasture, or one that stands loose as a vehicle; press again for each further horse), Right Ctrl + V
    gives them all back. Console: hdLead [start|stop|status].
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

function HorseDynamics.onCall()
    HorseDynamics.notify(HorseLead.command(nil, "start"))
end

function HorseDynamics.onRelease()
    HorseDynamics.notify(HorseLead.command(nil, "stop"))
end

function HorseDynamics.registerActionEvents()
    if g_inputBinding == nil or InputAction == nil or InputAction.HORSEDYN_CALL == nil then
        return
    end
    for _, spec in ipairs({ { InputAction.HORSEDYN_CALL, HorseDynamics.onCall }, { InputAction.HORSEDYN_RELEASE, HorseDynamics.onRelease } }) do
        local _, eventId = g_inputBinding:registerActionEvent(spec[1], HorseDynamics, spec[2], false, true, false, true, nil, true)
        if eventId ~= nil then
            g_inputBinding:setActionEventTextPriority(eventId, GS_PRIO_LOW)
            g_inputBinding:setActionEventTextVisibility(eventId, true)
        end
    end
end

function HorseDynamics.update(_, dt)
    HorseLead.updateRide(dt)
end

function HorseDynamics.consoleLead(_, argument)
    return HorseLead.command(nil, argument)
end

if PlayerInputComponent ~= nil and PlayerInputComponent.registerGlobalPlayerActionEvents ~= nil and Utils ~= nil and not HorseDynamics.hooked then
    HorseDynamics.hooked = true
    PlayerInputComponent.registerGlobalPlayerActionEvents = Utils.appendedFunction(PlayerInputComponent.registerGlobalPlayerActionEvents, function()
        HorseDynamics.registerActionEvents()
    end)
end
if addConsoleCommand ~= nil then
    addConsoleCommand("hdLead", "HorseDynamics: lead the nearest horse [start|stop|status] (keys: Right Ctrl + C call, Right Ctrl + V release)", "consoleLead", HorseDynamics)
end
if addModEventListener ~= nil then
    addModEventListener(HorseDynamics)
end
print("[HorseDynamics] loaded: Right Ctrl + C calls the nearest horse, Right Ctrl + V gives them back (console: hdLead)")
