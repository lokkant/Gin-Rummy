-- Tunable parameters of the game (read by the server and by the client). All times are in seconds.
-- The values below are small on purpose, for debugging; raise them for real games. A file named
-- user_config.lua in the game's save directory (love.filesystem.getSaveDirectory()) may return a table
-- with any of these keys; its values replace the ones here, so the numbers can be changed without
-- rebuilding the game.
--
-- The turn timer works like this, counted from the player's last game step (the start of their turn,
-- taking a card): after idle_warning_start the eye starts to turn red, idle_warning_full_delay later it is
-- fiery red and the vessels are at their maximum, idle_crack_delay after that the screen cracks, and
-- idle_loss_delay after the crack the round ends and the opponent gets timeout_penalty points. Every
-- moment is counted from the previous one, so changing one number moves all the later moments with it.
-- The server decides about the timeout and sends the numbers to the clients with every "is_my_turn", so
-- both sides always agree. The clock only starts when the player's client confirms that it has shown
-- the turn ("turn_started"): a client shows a turn late, after the result banner, the deal and the
-- opponent's animations, and that time is not the player's fault.

local love = require "love"

local config = {
    -- Seconds without a game step until the eye starts to turn red.
    idle_warning_start = 5,
    -- Seconds after the eye started to turn red until the iris is fiery red and the vessels are at their
    -- maximum.
    idle_warning_full_delay = 6,
    -- Seconds after the iris became fiery red until the glass cracks on the screen.
    idle_crack_delay = 1,
    -- Seconds after the glass cracks until the round is lost by waiting (0 = at the very moment it cracks).
    idle_loss_delay = 1,
    -- Points the opponent gets when the round is lost by waiting.
    timeout_penalty = 10,
    -- Longest wait, in seconds, for the client's "turn_started" before the clock starts anyway (so that a
    -- client that never answers can't stop the game).
    turn_ack_wait = 20,

    -- How visible the red vessels in the eye are when the player is calm (0 = none, 1 = all of them).
    capillaries_base = 0.2,
    -- How fast the redness fades after the player moved, in "full redness" units per second.
    stress_recovery_speed = 1.0,
    -- Seconds the cracks need to heal after the player moved.
    crack_restore_time = 2.0,
    -- Opacity of the cracks (0..1); they stay faint so that everything can still be seen.
    crack_alpha = 0.45,
    -- Volume of the sound effects (0 = silent, 1 = as recorded).
    sound_volume = 0.8,
    -- Loudness of the sound of an invalid move (0 = none, 1 = as recorded), relative to sound_volume; it is
    -- kept low so that it does not get annoying.
    failure_volume = 0.4,
    -- Loudness of the card sounds that belong to the opponent (their cards being dealt, drawn, discarded),
    -- relative to our own: 0 = none, 1 = as loud as ours.
    opponent_card_volume = 0.6
}

-- Replaces defaults with the values of the optional user file; a broken file is ignored.
local function apply_user_config()
    if not love.filesystem.getInfo("user_config.lua") then return end

    local ok, user = pcall(function()
        return love.filesystem.load("user_config.lua")()
    end)

    if ok and type(user) == "table" then
        for key, value in pairs(user) do
            if config[key] ~= nil and type(value) == type(config[key]) then
                config[key] = value
            end
        end
    end
end

apply_user_config()

return config
