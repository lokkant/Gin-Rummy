-- Heads-up display of the game scene: table background, turn lamps, the KNOCK button with the deadwood
-- counter, and the scores. Owns the fonts (loaded once) and the 1x1 white image the lamp shader is drawn
-- on. Called from scenes/game_client.lua; reads the shared game state.

require 'shaders'

local love = require "love"
local ui = require "ui"
local knock = require "client/knock"

local hud = {}

-- Lamp radius in design pixels (multiplied by the global scale) and the factor by which the quad drawn
-- around it is larger, so the glow has room.
local LAMP_RADIUS = 16
local LAMP_GLOW_SCALE = 2
-- Warm yellow, RGB.
local LAMP_COLOR = {1, 0.75, 0.15}
-- Widest hand: 11 cards between drawing and discarding. The lamps are placed left of it.
local MAX_HAND_CARDS = 11

-- RGBA of the KNOCK button when a knock is possible / impossible.
local KNOCK_AVAILABLE_COLOR = {0.8, 0.2, 0.2, 1}
local KNOCK_UNAVAILABLE_COLOR = {0.4, 0.4, 0.4, 0.6}

-- Shared resources, created once by hud.load.
local fonts
local white_pixel

-- Loads the fonts (once) and exposes them as state.fonts; also creates the white pixel for the lamps.
function hud.load(state)
    if fonts == nil then
        fonts = {
            base = love.graphics.newFont("ArchivoBlack-Regular.ttf"),
            number = love.graphics.newFont("ArchivoBlack-Regular.ttf", 28),
            gin = love.graphics.newFont("ArchivoBlack-Regular.ttf", 48),
            round_result = love.graphics.newFont("ArchivoBlack-Regular.ttf", 20)
        }

        -- A single white pixel: the lamp shader paints the whole lamp onto it, stretched to the lamp's
        -- size, so no lamp image is needed (the shader only uses the texture coordinates).
        local pixel_data = love.image.newImageData(1, 1)
        pixel_data:setPixel(0, 0, 1, 1, 1, 1)
        white_pixel = love.graphics.newImage(pixel_data)
    end

    state.fonts = fonts
end

-- Paints the table and resets shader and colour so that the following draws start clean.
function hud.draw_background()
    -- poker table color
    love.graphics.setColor(love.math.colorFromBytes(53, 101, 77, 255))
    love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())

    love.graphics.setShader()
    love.graphics.setColor(1, 1, 1, 1)
end

-- X of both lamps: the window centre minus half of the widest possible hand (cards overlap by a third, plus
-- half a card at the end), minus the lamp radius and a gap, so the lamps never touch the cards.
local function get_lamp_x(state)
    local card_width = state.layout.card_width
    local max_hand_half_width = (card_width / 1.5) * MAX_HAND_CARDS / 2 + card_width / 2
    return love.graphics.getWidth() / 2 - max_hand_half_width - LAMP_RADIUS * scale - 30 * scale
end

-- Draws one lamp centred at (cx, cy): the white pixel is stretched to a square and lamp_shader paints a
-- disc with glow and highlight on it; is_on lights it. The default shader is restored afterwards.
local function draw_turn_lamp(cx, cy, is_on)
    local half = LAMP_RADIUS * scale * LAMP_GLOW_SCALE

    love.graphics.setShader(lamp_shader)
    lamp_shader:send("time", love.timer.getTime())
    lamp_shader:send("is_on", is_on and 1 or 0)
    lamp_shader:send("lamp_color", LAMP_COLOR)

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(white_pixel, cx - half, cy - half, 0, half * 2, half * 2)

    love.graphics.setShader()
end

-- Draws the opponent's lamp (on when it is not our turn and the game is running) and ours (on in our turn),
-- each level with the middle of its card row.
function hud.draw_lamps(state)
    local lamp_x = get_lamp_x(state)
    local info = state.layout

    draw_turn_lamp(lamp_x, info.opponent_y + info.card_height / 2, not state.is_my_turn and not state.is_game_over)
    draw_turn_lamp(lamp_x, info.hand_y + info.card_height / 2, state.is_my_turn)
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
