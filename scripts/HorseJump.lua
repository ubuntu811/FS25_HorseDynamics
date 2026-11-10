--[[
    HorseJump.lua -- the horse's jump at a canter. The game (Rideable:jump) gives the horse only an upward speed: the xml's jumpHeight (2 m) at a gallop and half of it (1 m) at a canter, and keeps its forward speed
    (5 m/s at a canter, 10 at a gallop); a trot cannot jump. That makes a canter jump a steep lob (4.4 m/s up on 5 forward: 42 degrees, 4.5 m long) while a gallop's is flat (6.3 up on 10: 32 degrees, 13 m): a canter looks
    like jumping straight up, and a 90 cm bar needs more than the 1 m peak (the horse's body is a capsule of 0.9 m radius and has to rise over it). With the setting "canterJump" (HorseSettings, on by default) a jump
    at a canter rises to CANTER_FACTOR of the full height (1.2 m) AND leaves with LUNGE x the canter's speed (7.5 m/s: the game then slows it back in the air): a lower, longer arc (35 degrees, about 7 m).
    The jump itself and its animation are the game's: this only changes the speeds it leaves the ground with.
]]
HorseJump = {}
HorseJump.CANTER_FACTOR = 0.6                 -- of the xml's jumpHeight (the game: 0.5)
HorseJump.LUNGE = 1.5                         -- the jump leaves at this times the canter's speed (a horse stretches out over a jump)

function HorseJump.jump(horse, superFunc, ...)
    local result = superFunc(horse, ...)
    local spec = horse.spec_rideable
    if spec ~= nil and Rideable ~= nil and spec.inputValues.currentGait == Rideable.GAITTYPES.CANTER
        and HorseSettings ~= nil and HorseSettings.config.canterJump == true and spec.gravity ~= nil then
        spec.currentSpeedY = math.sqrt(2 * math.abs(spec.gravity) * spec.jumpHeight * HorseJump.CANTER_FACTOR)
        local canter = spec.topSpeeds ~= nil and spec.topSpeeds[Rideable.GAITTYPES.CANTER] or nil
        if canter ~= nil and spec.currentSpeed ~= nil and spec.currentSpeed >= 0.8 * canter then
            spec.currentSpeed = math.max(spec.currentSpeed, canter * HorseJump.LUNGE)      -- (in the air the game slows it back: 1 m/s each second)
        end
    end
    return result
end

if Rideable ~= nil and Rideable.jump ~= nil and Utils ~= nil and not HorseJump.hooked then
    HorseJump.hooked = true
    Rideable.jump = Utils.overwrittenFunction(Rideable.jump, HorseJump.jump)
end
