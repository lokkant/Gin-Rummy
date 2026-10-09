-- The table felt (client side). The game scene and the layoff scene draw it with a vignette: the cloth is
-- lit by one or more soft elliptical lights and gets darker away from them, so the table is never evenly
-- bright. The game scene moves the lights with the turn (client/hud.lua); the layoff scene uses the ready
-- set below. The menus draw the plain cloth. The vignette is drawn with spotlight_shader (shaders.lua) on a
-- stretched 1x1 white image.

require 'shaders'

local love = require "love"
local horror = require "client/horror"
local config = require "config"

local felt = {}

-- Plain table colour (RGB 0..1); the shader lights and darkens it.
local FELT_COLOR = {53 / 255, 101 / 255, 77 / 255}
-- The brightness of the unlit part when the unsettling effects are off (1 = as bright as the lit part).
local NORMAL_UNLIT_BRIGHTNESS = 0.6
-- The shader takes at most this many lights.
local MAX_LIGHTS = 4

-- Vertical position of a light over the opponent's row and over ours (0 = top edge, 1 = bottom edge).
felt.LIGHT_Y_OPPONENT = 0.12
felt.LIGHT_Y_PLAYER = 0.85

-- A ready set of lights, each {x, y, level} with x and y as fractions of the window and level 0..1: a light
-- over each hand plus one in the middle (everything open: both hands, the melds between them and the
-- buttons).
felt.OPEN_LIGHTS = {{0.5, felt.LIGHT_Y_OPPONENT, 1}, {0.5, felt.LIGHT_Y_PLAYER, 1}, {0.5, 0.5, 1}}

local white_pixel

-- A single white pixel (made once): the shader paints the whole table onto it, stretched to the window,
-- so no image is needed (the shader only uses the texture coordinates).
local function get_white_pixel()
    if white_pixel == nil then
        local pixel_data = love.image.newImageData(1, 1)
        pixel_data:setPixel(0, 0, 1, 1, 1, 1)
        white_pixel = love.graphics.newImage(pixel_data)
    end

    return white_pixel
end

-- The brightness of the unlit part of the table: the original one without the effects, the (darker)
-- config.darkness_unlit with them.
local function get_unlit_brightness()
    local strength = horror.is_master_on() and horror.strength() or 0

    return NORMAL_UNLIT_BRIGHTNESS + (config.darkness_unlit - NORMAL_UNLIT_BRIGHTNESS) * strength
end

-- Paints the table over the whole window with the given lights (a list of {x, y, level}, at most
-- MAX_LIGHTS; a level of 0 is no light). Resets shader and colour so that the following draws start clean.
function felt.draw(lights)
    local sent = {}
    for i = 1, MAX_LIGHTS do
        local light = lights[i]
        sent[i] = light and {light[1], light[2], light[3]} or {0.5, 0.5, 0}
    end

    love.graphics.setShader(spotlight_shader)
    spotlight_shader:send("time", love.timer.getTime())
    spotlight_shader:send("felt_color", FELT_COLOR)
    spotlight_shader:send("unlit_brightness", get_unlit_brightness())
    spotlight_shader:send("lights", unpack(sent))

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(get_white_pixel(), 0, 0, 0, love.graphics.getWidth(), love.graphics.getHeight())

    love.graphics.setShader()
end

-- Paints the plain, evenly coloured cloth over the whole window (menus).
function felt.draw_plain()
    love.graphics.setColor(FELT_COLOR[1], FELT_COLOR[2], FELT_COLOR[3], 1)
    love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
    love.graphics.setColor(1, 1, 1, 1)
end

return felt
