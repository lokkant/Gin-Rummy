require 'shaders'

local love = require "love"
local ui = require "ui"
local knock = require "client/knock"

local hud = {}

local LAMP_RADIUS = 16
local LAMP_GLOW_SCALE = 2
local LAMP_COLOR = {1, 0.75, 0.15}
local MAX_HAND_CARDS = 11

local KNOCK_AVAILABLE_COLOR = {0.8, 0.2, 0.2, 1}
local KNOCK_UNAVAILABLE_COLOR = {0.4, 0.4, 0.4, 0.6}

local fonts
local white_pixel

function hud.load(state)
    if fonts == nil then
        fonts = {
            base = love.graphics.newFont("ArchivoBlack-Regular.ttf"),
            number = love.graphics.newFont("ArchivoBlack-Regular.ttf", 28),
            gin = love.graphics.newFont("ArchivoBlack-Regular.ttf", 48),
            round_result = love.graphics.newFont("ArchivoBlack-Regular.ttf", 20)
        }

        local pixel_data = love.image.newImageData(1, 1)
        pixel_data:setPixel(0, 0, 1, 1, 1, 1)
        white_pixel = love.graphics.newImage(pixel_data)
    end

    state.fonts = fonts
end

function hud.draw_background()
    -- poker table color
    love.graphics.setColor(love.math.colorFromBytes(53, 101, 77, 255))
    love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())

    love.graphics.setShader()
    love.graphics.setColor(1, 1, 1, 1)
end

local function get_lamp_x(state)
    local card_width = state.layout.card_width
    local max_hand_half_width = (card_width / 1.5) * MAX_HAND_CARDS / 2 + card_width / 2
    return love.graphics.getWidth() / 2 - max_hand_half_width - LAMP_RADIUS * scale - 30 * scale
end

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

function hud.draw_lamps(state)
    local lamp_x = get_lamp_x(state)
    local info = state.layout

    draw_turn_lamp(lamp_x, info.opponent_y + info.card_height / 2, not state.is_my_turn and not state.is_game_over)
    draw_turn_lamp(lamp_x, info.hand_y + info.card_height / 2, state.is_my_turn)
end

function hud.draw_knock_button(state)
    local button = state.layout.knock_button
    local discard_card, deadwood = knock.evaluate(state)
    local is_available = state.is_my_turn and not state.is_game_over and discard_card ~= nil

    love.graphics.setFont(state.fonts.base)
    ui.draw_button(button, "KNOCK", is_available and KNOCK_AVAILABLE_COLOR or KNOCK_UNAVAILABLE_COLOR)

    love.graphics.printf("Deadwood: " .. tostring(deadwood), button.x, button.y - 24, button.w, "center")
end

function hud.draw_scores(state)
    local info = state.layout

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setFont(state.fonts.number)

    love.graphics.printf(state.opponent_total_score, 0, info.opponent_y - 30 * scale, love.graphics.getWidth(), "center")
    love.graphics.printf(state.my_total_score, 0, info.hand_y + info.card_height + 15 * scale, love.graphics.getWidth(), "center")
end

return hud
