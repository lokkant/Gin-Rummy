-- "Watchers" (client side): pairs of pale eyes with slit pupils that slowly show in the dark half of the
-- table, in the free spots between the hands and the edges. They only appear when the cursor has stayed away
-- from them for a while and vanish quickly when it comes close - you never catch them looking. Used by
-- client/hud.lua; the numbers are in config.lua (watchers_*).

local love = require "love"
local config = require "config"
local horror = require "client/horror"

local watchers = {}

-- Where a pair can show, as {x, y} fractions of the window width and height, for the top half (dark when it
-- is our turn) and the bottom half (dark in the opponent's turn). The spots lie outside the card rows, the
-- stock, the eye and the KNOCK button.
local SPOTS = {
    top = {{0.06, 0.14}, {0.94, 0.14}, {0.06, 0.30}, {0.94, 0.30}, {0.30, 0.375}, {0.70, 0.375}},
    bottom = {{0.06, 0.86}, {0.06, 0.70}, {0.30, 0.635}, {0.70, 0.635}}
}

-- Most pairs there can be at once. How opaque a pair gets is config.watchers_alpha (they stay very dim).
local MAX_WATCHERS = 4
-- Seconds a pair needs to fade in.
local FADE_IN_TIME = 2.5

-- The picture of a pair of eyes: two almond shapes with a gap, in its own tiny pixel grid.
local EYE_WIDTH = 9
local EYE_HEIGHT = 5
local EYE_GAP = 5
local PAIR_WIDTH = EYE_WIDTH * 2 + EYE_GAP
local SCLERA = {0.62, 0.64, 0.6}
local PUPIL = {0.1, 0.1, 0.1}

local image

-- Makes the picture of a pair of eyes (once): pale ovals, each with a one pixel wide black slit.
local function prepare()
    if image ~= nil then return end

    local data = love.image.newImageData(PAIR_WIDTH, EYE_HEIGHT)

    for eye_index = 0, 1 do
        local left = eye_index * (EYE_WIDTH + EYE_GAP)
        local center_x = left + (EYE_WIDTH - 1) / 2
        local center_y = (EYE_HEIGHT - 1) / 2

        for y = 0, EYE_HEIGHT - 1 do
            for x = left, left + EYE_WIDTH - 1 do
                local inside = ((x - center_x) / (EYE_WIDTH / 2)) ^ 2 + ((y - center_y) / (EYE_HEIGHT / 2)) ^ 2 <= 1
                if inside then
                    local color = (x == math.floor(center_x + 0.5)) and PUPIL or SCLERA
                    data:setPixel(x, y, color[1], color[2], color[3], 1)
                end
            end
        end
    end

    image = love.graphics.newImage(data)
    image:setFilter("nearest", "nearest")
end

-- Creates the state: a list of pairs, filled when there is room (see update). A pair is {spot = {x, y} or
-- nil, half = "top"/"bottom", alpha, calm} where calm counts the seconds the cursor stayed away.
function watchers.create()
    local list = {}
    for i = 1, MAX_WATCHERS do
        list[i] = {spot = nil, half = nil, alpha = 0, calm = 0}
    end
    return {list = list}
end

-- True if the spot is already used by another pair.
local function is_spot_taken(self, spot)
    for _, watcher in ipairs(self.list) do
        if watcher.spot == spot then return true end
    end
    return false
end

-- Picks a free spot in the given half at random, or nil if all are taken.
local function pick_spot(self, half)
    local free = {}
    for _, spot in ipairs(SPOTS[half]) do
        if not is_spot_taken(self, spot) then
            table.insert(free, spot)
        end
    end

    if #free == 0 then return nil end
    return free[love.math.random(#free)]
end

-- Per frame (dt in seconds). Pairs show in the half that is dark at the moment (spotlight.turn near 1 = our
-- turn = the top is dark). A pair that has no spot takes one after the cursor stayed away for
-- config.watchers_idle_time seconds, then fades in slowly; it fades out within config.watchers_fade_time and
-- gives up its spot when the cursor comes within config.watchers_distance (at 1080 pixels of window height)
-- or its half gets lit.
function watchers.update(self, dt, state)
    local active = horror.is_on("watchers_enabled")
    local w, h = love.graphics.getDimensions()
    local mouse_x, mouse_y = love.mouse.getPosition()
    local near = config.watchers_distance * h / 1080

    local dark_half = state.spotlight.turn > 0.5 and "top" or "bottom"
    local darkness = math.abs(state.spotlight.turn - 0.5) * 2 * (1 - state.spotlight.open)
    local fade_out = dt / math.max(0.05, config.watchers_fade_time)

    for index, watcher in ipairs(self.list) do
        local wanted = active and index <= config.watchers_count and darkness > 0.5

        if watcher.spot ~= nil then
            local distance = math.sqrt((mouse_x - watcher.spot[1] * w) ^ 2 + (mouse_y - watcher.spot[2] * h) ^ 2)
            local is_seen = distance < near or watcher.half ~= dark_half or not wanted

            if is_seen then
                watcher.alpha = math.max(0, watcher.alpha - fade_out)
                watcher.calm = 0

                if watcher.alpha == 0 then
                    watcher.spot = nil
                end
            else
                watcher.alpha = math.min(config.watchers_alpha,
                                         watcher.alpha + dt / FADE_IN_TIME * config.watchers_alpha)
            end
        elseif wanted then
            watcher.calm = watcher.calm + dt

            if watcher.calm >= config.watchers_idle_time then
                local spot = pick_spot(self, dark_half)
                local far_enough = spot ~= nil and
                    math.sqrt((mouse_x - spot[1] * w) ^ 2 + (mouse_y - spot[2] * h) ^ 2) >= near

                if far_enough then
                    watcher.spot = spot
                    watcher.half = dark_half
                    watcher.alpha = 0
                else
                    watcher.calm = 0
                end
            end
        else
            watcher.calm = 0
        end
    end
end

-- Draws the visible pairs at their spots, dim and scaled by the effects' intensity. Each eye pixel is a
-- whole number of screen pixels so the picture stays crisp.
function watchers.draw(self)
    if not horror.is_on("watchers_enabled") then return end

    prepare()

    local w, h = love.graphics.getDimensions()
    local pixel_size = math.max(1, math.floor(scale * 0.8 + 0.5))
    local strength = horror.strength()

    for _, watcher in ipairs(self.list) do
        if watcher.spot ~= nil and watcher.alpha > 0 then
            love.graphics.setColor(1, 1, 1, watcher.alpha * strength)
            love.graphics.draw(image, watcher.spot[1] * w - PAIR_WIDTH * pixel_size / 2,
                               watcher.spot[2] * h - EYE_HEIGHT * pixel_size / 2, 0, pixel_size, pixel_size)
        end
    end

    love.graphics.setColor(1, 1, 1, 1)
end

return watchers
