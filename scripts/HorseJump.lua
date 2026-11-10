--[[
    HorseJump.lua -- the horse's jump at a canter. The game (Rideable:jump) gives a horse the xml's jumpHeight (2 m) at a gallop and HALF of it at a canter (1 m); a trot cannot jump. The horse's body is a capsule
    of 0.9 m radius, so it has to rise above a bar to pass it, and with a bar at 90 cm a 1 m peak is only just enough (and for a moment): only a full gallop cleared any jump. With the setting "canterJump"
    (HorseSettings, on by default) a jump at a canter is CANTER_FACTOR of the full height (1.6 m), the gallop stays 2 m. The jump itself is the game's: this only changes how fast it leaves the ground.
]]
HorseJump = {}
HorseJump.CANTER_FACTOR = 0.8                 -- of the xml's jumpHeight (the game: 0.5)

function HorseJump.jump(horse, superFunc, ...)
    local result = superFunc(horse, ...)
    local spec = horse.spec_rideable
    if spec ~= nil and Rideable ~= nil and spec.inputValues.currentGait == Rideable.GAITTYPES.CANTER
        and HorseSettings ~= nil and HorseSettings.config.canterJump == true and spec.gravity ~= nil then
        spec.currentSpeedY = math.sqrt(2 * math.abs(spec.gravity) * spec.jumpHeight * HorseJump.CANTER_FACTOR)
    end
    return result
end

if Rideable ~= nil and Rideable.jump ~= nil and Utils ~= nil and not HorseJump.hooked then
    HorseJump.hooked = true
    Rideable.jump = Utils.overwrittenFunction(Rideable.jump, HorseJump.jump)
end
