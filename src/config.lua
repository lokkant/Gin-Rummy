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
    idle_warning_start = 8,
    -- Seconds after the eye started to turn red until the iris is fiery red and the vessels are at their
    -- maximum.
    idle_warning_full_delay = 9,
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
    opponent_card_volume = 0.5,

    -- ===== Unsettling effects =====
    -- For now every effect works in every stage of the game (for debugging). Each one has its own switch;
    -- horror_enabled turns all of them off at once and horror_intensity (0..1) scales how strong they are.
    horror_enabled = true,
    horror_intensity = 1.0,

    -- How bright the unlit half of the table is (1 = as bright as the lit one, 0 = black). Lower = darker.
    darkness_unlit = 0.28,

    -- Pairs of pale eyes that show in the dark half of the table when nothing is near them and vanish when
    -- the cursor comes close: how many pairs, how visible they get (0..1, low = barely there), seconds the
    -- cursor must have stayed away before they appear, seconds they need to vanish, and the distance
    -- (pixels at 1080p) at which the cursor makes them vanish.
    watchers_enabled = true,
    watchers_alpha = 0.05,
    watchers_count = 4,
    watchers_idle_time = 3,
    watchers_fade_time = 0.4,
    watchers_distance = 230,

    -- A faint low hum that comes and goes (it is "on" for ambient_on_min.._max seconds, then gone for
    -- ambient_off_min.._max seconds), reverb on the opponent's card sounds (as if heard through a wall) and
    -- silence (the hum fades away) while the player hesitates. ambient_volume is relative to sound_volume.
    ambient_enabled = true,
    ambient_volume = 0.06,
    ambient_on_min = 8,
    ambient_on_max = 20,
    ambient_off_min = 40,
    ambient_off_max = 100,
    room_reverb = true,
    silence_on_stress = true,

    -- A very quiet rustle of a card from the dark side, now and then when nothing is happening: seconds
    -- between two rustles (shortest and longest) and its loudness relative to sound_volume.
    phantom_enabled = true,
    phantom_interval_min = 20,
    phantom_interval_max = 45,
    phantom_volume = 0.1,

    -- A muffled knock from one side, very rarely, at a random time when nothing is happening: seconds
    -- between two knocks (shortest and longest) and its loudness relative to sound_volume.
    knock_enabled = true,
    knock_interval_min = 90,
    knock_interval_max = 240,
    knock_volume = 0.3,

    -- The kings, queens and jacks look at the cursor (their eyes move to the side of the card where the
    -- cursor is, after a delay in seconds).
    face_gaze_enabled = true,
    face_gaze_delay = 0.35,

    -- Cards tremble more: card_nervousness multiplies the sway of the cards (1 = the original calm sway);
    -- while the opponent hesitates their cards twitch more and spread out (opponent_restlessness); the stock
    -- breathes (deck_breathing is the size change, 0 = none).
    card_nervousness = 1.8,
    opponent_restlessness = true,
    deck_breathing = 0.012,

    -- In the opponent's turn the eye now and then opens a slit and looks towards their cards, and closes
    -- again after eye_peek_duration seconds. The wait between two peeks is random, between
    -- eye_peek_interval_min and _max seconds (counted in the opponent's turns only); eye_peek_openness (0..1)
    -- is how wide it opens.
    eye_peek_enabled = true,
    eye_peek_interval_min = 20,
    eye_peek_interval_max = 45,
    eye_peek_duration = 2,
    eye_peek_openness = 0.4,

    -- The opponent's heart: in their turn, after they hesitated for the same time as ours would, a duller
    -- heartbeat is heard from one side, faster the longer they take. opponent_heartbeat_volume is relative
    -- to sound_volume.
    opponent_heartbeat_enabled = true,
    opponent_heartbeat_volume = 0.5,

    -- The turn timers get shorter as the match goes on: every timer_shrink_every rounds all the limits
    -- (the eye turning red, the crack, the loss by waiting) are multiplied by timer_shrink_factor once more,
    -- for both players, but never below timer_shrink_min_factor of the original. The server decides.
    timer_shrink_enabled = true,
    timer_shrink_every = 3,
    timer_shrink_factor = 0.8,
    timer_shrink_min_factor = 0.4
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
