-- Heads-up display of the game scene: the table with the spotlight on the active player's half, the eye
-- that watches the cursor in our turn, the KNOCK button with the deadwood counter, and the scores. Owns
-- the fonts (loaded once) and the 1x1 white image the spotlight shader is drawn on. Called from
-- scenes/game_client.lua; reads the shared game state.

require 'shaders'

local love = require "love"
local ui = require "ui"
local knock = require "client/knock"
local eye = require "client/eye"
local impatience = require "client/impatience"
local sounds = require "client/sounds"

local hud = {}

-- Plain table colour (RGB 0..1); the spotlight shader lights and darkens it.
local FELT_COLOR = {53 / 255, 101 / 255, 77 / 255}
-- Vertical position of the light centre (0 = top edge, 1 = bottom edge) over the opponent's row and ours.
local LIGHT_Y_OPPONENT = 0.12
local LIGHT_Y_PLAYER = 0.85
-- How fast the light follows the turn (per second; the remaining distance shrinks by this factor).
local LIGHT_SPEED = 6

-- RGBA of the KNOCK button when a knock is possible / impossible.
local KNOCK_AVAILABLE_COLOR = {0.8, 0.2, 0.2, 1}
local KNOCK_UNAVAILABLE_COLOR = {0.4, 0.4, 0.4, 0.6}

-- Shared resources, created once by hud.load.
local fonts
local white_pixel

-- Loads the fonts (once) and exposes them as state.fonts; also creates the white pixel for the spotlight
-- and the spotlight's own state: spotlight.turn is 0 with the light on the opponent and 1 on us,
-- spotlight.strength is how visible the effect is.
function hud.load(state)
    if fonts == nil then
        fonts = {
            base = love.graphics.newFont("ArchivoBlack-Regular.ttf"),
            number = love.graphics.newFont("ArchivoBlack-Regular.ttf", 28),
            gin = love.graphics.newFont("ArchivoBlack-Regular.ttf", 48),
            round_result = love.graphics.newFont("ArchivoBlack-Regular.ttf", 20)
        }

        -- A single white pixel: the spotlight shader paints the whole table onto it, stretched to the
        -- window, so no image is needed (the shader only uses the texture coordinates).
        local pixel_data = love.image.newImageData(1, 1)
        pixel_data:setPixel(0, 0, 1, 1, 1, 1)
        white_pixel = love.graphics.newImage(pixel_data)
    end

    state.fonts = fonts
    state.spotlight = {turn = 0.5, strength = 0}
    state.eye = eye.create()
    state.impatience = impatience.create()
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

-- Size of one pixel of the eye picture on the screen: a whole number, so the enlarged pixels stay square
-- and equally sized; it follows the window size like the cards do.
local function get_eye_pixel_size()
    return math.max(1, math.floor(scale + 0.5))
end

-- Moves the light towards the active player and fades it out when nobody is active; wakes the eye in our
-- turn (it follows the cursor) and lets it sleep otherwise. dt is in seconds.
function hud.update(state, dt)
    local spotlight = state.spotlight
    local side = get_active_side(state)
    local follow = math.min(1, dt * LIGHT_SPEED)

    if side ~= nil then
        local target = side == "me" and 1 or 0
        spotlight.turn = spotlight.turn + (target - spotlight.turn) * follow
    end

    spotlight.strength = spotlight.strength + ((side ~= nil and 1 or 0) - spotlight.strength) * follow

    -- The turn timer (a taking-too-long player gets a red eye and a cracked screen) and the eye's reaction.
    if impatience.update(state.impatience, dt, state.turn_timer, state.is_my_turn) then
        sounds.play_crack()
    end
    sounds.update(dt)
    state.eye.stress = state.impatience.stress

    local center = state.layout.eye_center
    local mouse_x, mouse_y = love.mouse.getPosition()
    eye.update(state.eye, dt, side == "me", mouse_x, mouse_y, center.x, center.y, get_eye_pixel_size())
end

-- Draws the cracked glass (if any) over the table; its cracks start at the eye.
function hud.draw_cracks(state)
    local center = state.layout.eye_center
    impatience.draw(state.impatience, center.x, center.y)
end

-- Draws the eye to the right of the table centre.
function hud.draw_eye(state)
    local center = state.layout.eye_center
    eye.draw(state.eye, center.x, center.y, get_eye_pixel_size())
end

-- Paints the table: the spotlight shader on a window-sized white pixel. Resets shader and colour so that
-- the following draws start clean.
function hud.draw_background(state)
    local spotlight = state.spotlight

    love.graphics.setShader(spotlight_shader)
    spotlight_shader:send("time", love.timer.getTime())
    spotlight_shader:send("felt_color", FELT_COLOR)
    spotlight_shader:send("light_y", LIGHT_Y_OPPONENT + (LIGHT_Y_PLAYER - LIGHT_Y_OPPONENT) * spotlight.turn)
    spotlight_shader:send("strength", spotlight.strength)

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(white_pixel, 0, 0, 0, love.graphics.getWidth(), love.graphics.getHeight())

    love.graphics.setShader()
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
