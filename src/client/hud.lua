-- Heads-up display of the game scene: the table with the spotlight on the active player's half (and the
-- pale watchers in the dark half), the eye that watches the cursor in our turn, the KNOCK button with the
-- deadwood counter, and the scores. Also drives the unsettling effects that depend on the turn: the
-- nervousness of the cards, the eye peeking in the opponent's turn and the sounds that belong to them.
-- Owns the fonts (loaded once) and the 1x1 white image the spotlight shader is drawn on. Called from
-- scenes/game_client.lua; reads the shared game state.

require 'shaders'

local love = require "love"
local ui = require "ui"
local knock = require "client/knock"
local eye = require "client/eye"
local impatience = require "client/impatience"
local sounds = require "client/sounds"
local watchers = require "client/watchers"
local felt = require "client/felt"
local horror = require "client/horror"
local config = require "config"

local hud = {}

-- How fast the opponent's fan spreads and closes again (per second, like LIGHT_SPEED). Slow on purpose: the
-- cards drift apart and back instead of snapping.
local RESTLESS_SPEED = 1.2
-- How much more the opponent's cards sway at full restlessness (1 = twice as much as usual).
local RESTLESS_SWAY_EXTRA = 1
-- How fast the light follows the turn (per second; the remaining distance shrinks by this factor).
local LIGHT_SPEED = 6

-- RGBA of the KNOCK button when a knock is possible / impossible.
local KNOCK_AVAILABLE_COLOR = {0.8, 0.2, 0.2, 1}
local KNOCK_UNAVAILABLE_COLOR = {0.4, 0.4, 0.4, 0.6}

-- Shared resources, created once by hud.load.
local fonts

-- Loads the fonts (once) and exposes them as state.fonts; also creates the light's own state:
-- spotlight.turn is 0 with the light on the opponent and 1 on us, spotlight.open is 0 while one player is
-- to move and 1 when nobody is (before the match, round result, end of the match): then the cards of both
-- players are open and both are lit.
function hud.load(state)
    if fonts == nil then
        fonts = {
            base = love.graphics.newFont("ArchivoBlack-Regular.ttf"),
            number = love.graphics.newFont("ArchivoBlack-Regular.ttf", 28),
            gin = love.graphics.newFont("ArchivoBlack-Regular.ttf", 48),
            round_result = love.graphics.newFont("ArchivoBlack-Regular.ttf", 20)
        }
    end

    state.fonts = fonts
    state.spotlight = {turn = 0.5, open = 1}
    state.eye = eye.create()
    state.impatience = impatience.create()
    state.watchers = watchers.create()
    -- opponent_idle: seconds the opponent has taken for their move so far (0 outside their turn);
    -- time_factor: the share of the normal turn timer limits in this round (the server sends it);
    -- eye_peek: seconds until the eye's next peek in the opponent's turn (nil = not drawn yet) and seconds
    -- the current peek still lasts.
    state.opponent_idle = 0
    state.time_factor = 1
    state.eye_peek = {wait = nil, remaining = 0}
    sounds.load()
end

-- Whose turn the light shows: "me", "opponent" or nil when nobody's (before the match, while a round
-- result or the end screen is up).
local function get_active_side(state)
    if not state.has_started_first_game or state.is_game_over or state.round_result ~= nil then
        return nil
    end

    return state.is_my_turn and "me" or "opponent"
end

-- The turn timer limits {fade_start, fade_full, ...} in seconds: the ones the server sent with our last
-- turn, or the ones it would send (config.lua, shortened in later rounds) before we had a turn this round.
local function get_turn_limits(state)
    if state.turn_limits then return state.turn_limits end

    local factor = state.time_factor
    local fade_start = config.idle_warning_start * factor

    return {fade_start = fade_start, fade_full = fade_start + config.idle_warning_full_delay * factor}
end

-- How worried the opponent is, 0..1: it grows from 0 to 1 while they take longer than the first limit, like
-- our own stress does for us.
local function get_opponent_stress(state)
    local limits = get_turn_limits(state)
    local span = math.max(0.001, limits.fade_full - limits.fade_start)

    return math.max(0, math.min(1, (state.opponent_idle - limits.fade_start) / span))
end

-- Per frame in the opponent's turn: returns the openness the eye peeks with, or nil while it stays shut.
-- After a random wait (config.eye_peek_interval_min.._max, counted in the opponent's turns only) it opens a
-- slit for config.eye_peek_duration seconds.
local function update_eye_peek(state, dt, is_opponents_turn)
    local peek = state.eye_peek

    if not is_opponents_turn or not horror.is_on("eye_peek_enabled") then
        peek.remaining = 0
        return nil
    end

    if peek.remaining > 0 then
        peek.remaining = peek.remaining - dt
        return config.eye_peek_openness
    end

    if peek.wait == nil then
        peek.wait = config.eye_peek_interval_min +
                    love.math.random() * (config.eye_peek_interval_max - config.eye_peek_interval_min)
    end

    peek.wait = peek.wait - dt
    if peek.wait <= 0 then
        peek.wait = nil
        peek.remaining = config.eye_peek_duration
        return config.eye_peek_openness
    end

    return nil
end

-- Per frame (dt in seconds). Moves the light towards the active player and fades it out when nobody is
-- active; wakes the eye in our turn (it follows the cursor) and lets it sleep in the opponent's turn
-- except for a rare short peek; counts how long the opponent has been thinking; runs our own turn timer (a
-- taking-too-long player gets a red eye and a cracked screen); updates the nervousness of the hands, the
-- watchers and the sounds.
function hud.update(state, dt)
    local spotlight = state.spotlight
    local side = get_active_side(state)
    local follow = math.min(1, dt * LIGHT_SPEED)

    if side ~= nil then
        local target = side == "me" and 1 or 0
        spotlight.turn = spotlight.turn + (target - spotlight.turn) * follow
    end

    spotlight.open = spotlight.open + ((side == nil and 1 or 0) - spotlight.open) * follow

    if side == "opponent" then
        state.opponent_idle = state.opponent_idle + dt
    else
        state.opponent_idle = 0
    end
    local opponent_stress = get_opponent_stress(state)

    if impatience.update(state.impatience, dt, state.turn_timer, state.is_my_turn) then
        sounds.stop_heartbeat()
        sounds.play_crack()
    end

    -- The heart beats from the moment the eye starts to turn red until the glass cracks.
    sounds.update_heartbeat(dt, state.impatience.stress, state.impatience.crack == nil)
    sounds.update_opponent_heartbeat(dt, opponent_stress, side == "opponent")

    -- Faint hum that comes and goes (it fades away while we hesitate), and the rare rustle and knock from
    -- the dark side, which only come when nothing happens on the table.
    local is_quiet = state.has_started_first_game and not state.is_game_over and side ~= nil and
                     not state.animations:is_busy() and not state.animations:is_active("discard_pile")
    sounds.update_ambient(dt, state.impatience.stress, state.is_my_turn)
    sounds.update_phantom(dt, is_quiet)
    sounds.update_knock(dt, is_quiet)
    sounds.update(dt)
    state.eye.stress = state.impatience.stress

    -- The eye follows the cursor in our turn; in the opponent's turn it sleeps, except for a rare short peek
    -- (a slit, looking up at their cards).
    local is_awake = side == "me"
    local peek_openness = update_eye_peek(state, dt, side == "opponent")

    local center = state.layout.eye_center
    local mouse_x, mouse_y = love.mouse.getPosition()
    eye.update(state.eye, dt, is_awake, mouse_x, mouse_y, center.x, center.y, eye.get_pixel_size(), peek_openness)

    -- Cards sway more; our own stress adds to it, and the opponent's hand gets restless while they take
    -- long: the cards twitch more and the fan spreads.
    local nervousness = horror.multiplier("card_nervousness")
    if state.player_hand then
        state.player_hand.nervousness = nervousness * (1 + state.impatience.stress)
    end
    if state.opponent_hand then
        local restlessness = horror.is_on("opponent_restlessness") and opponent_stress or 0
        local current = state.opponent_hand.restlessness
        current = current + (restlessness - current) * math.min(1, dt * RESTLESS_SPEED)
        state.opponent_hand.restlessness = current

        -- the sway follows the smoothed value, so it never jumps when the opponent moves
        state.opponent_hand.nervousness = nervousness * (1 + RESTLESS_SWAY_EXTRA * current)
    end

    watchers.update(state.watchers, dt, state)
end

-- Draws the pale eyes that watch from the dark half of the table; they lie on the felt, under the cards.
function hud.draw_watchers(state)
    watchers.draw(state.watchers)
end

-- Draws the cracked glass (if any) over the table; its cracks start at the eye.
function hud.draw_cracks(state)
    local center = state.layout.eye_center
    impatience.draw(state.impatience, center.x, center.y)
end

-- Draws the eye to the right of the table centre.
function hud.draw_eye(state)
    local center = state.layout.eye_center
    eye.draw(state.eye, center.x, center.y, eye.get_pixel_size())
end

-- Paints the table. While a player is to move the light is over their row (the two rows' lights fade into
-- each other with the turn); when nobody is, both rows and the middle are lit. The rest stays dark, so
-- there is always a vignette.
function hud.draw_background(state)
    local spotlight = state.spotlight
    local top_level = math.max(spotlight.open, 1 - spotlight.turn)
    local bottom_level = math.max(spotlight.open, spotlight.turn)

    felt.draw({{0.5, felt.LIGHT_Y_OPPONENT, top_level}, {0.5, felt.LIGHT_Y_PLAYER, bottom_level},
               {0.5, 0.5, spotlight.open}})
end

-- Draws the KNOCK button (red when knocking is possible right now, grey otherwise) and the deadwood count
-- above it. knock.evaluate gives the card the knock would discard (nil if not possible) and the number
-- shown.
function hud.draw_knock_button(state)
    local button = state.layout.knock_button
    local discard_card, deadwood = knock.evaluate(state)
    local is_available = state.is_my_turn and not state.is_game_over and discard_card ~= nil

    love.graphics.setFont(state.fonts.base)
    ui.draw_button(button, "KNOCK", is_available and KNOCK_AVAILABLE_COLOR or KNOCK_UNAVAILABLE_COLOR)

    love.graphics.printf("Deadwood: " .. tostring(deadwood), button.x, button.y - 24, button.w, "center")
end

-- Draws the match totals: the opponent's above their cards, ours below our cards.
function hud.draw_scores(state)
    local info = state.layout

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setFont(state.fonts.number)

    love.graphics.printf(state.opponent_total_score, 0, info.opponent_y - 30 * scale, love.graphics.getWidth(), "center")
    love.graphics.printf(state.my_total_score, 0, info.hand_y + info.card_height + 15 * scale, love.graphics.getWidth(), "center")
end

return hud
