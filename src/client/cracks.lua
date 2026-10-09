-- A "cracked glass" picture drawn over the screen (client side): jagged cracks spread from one impact point
-- with a few branches and rings around it. A pattern is made once per crack (create), then drawn as many
-- times as needed (draw). Drawing only part of it - from the impact outwards - lets the glass heal from the
-- edges towards the centre. Used by client/impatience.lua.

local love = require "love"

local cracks = {}

-- Number of main cracks that start at the impact point.
local RAY_COUNT = 5
-- Length of a main crack as a part of the window height (the shortest and the longest one).
local MIN_RAY_LENGTH = 0.55
local MAX_RAY_LENGTH = 1.1
-- Length of one straight piece of a crack, as a part of the window height.
local MIN_PIECE = 0.035
local MAX_PIECE = 0.09
-- Chance that a piece of a crack sprouts a side branch.
local BRANCH_CHANCE = 0.3
-- Distances (part of the window height) of the rings around the impact point.
local RING_RADII = {0.12, 0.27}
-- The farthest a crack can be from the impact point; used to turn a distance into the 0..1 "order" of a
-- piece: pieces with a larger order are the first to vanish when the glass heals.
local MAX_REACH = 1.3

-- Adds one piece of a crack from (x1, y1) to (x2, y2) (offsets from the impact point, in window heights).
local function add_piece(pattern, x1, y1, x2, y2, thickness)
    local distance = math.sqrt(x2 * x2 + y2 * y2)
    table.insert(pattern.pieces, {x1, y1, x2, y2, math.min(1, distance / MAX_REACH), thickness})
end

-- Grows a crack from (x, y) in direction `angle` for `length`, turning a little at each piece; thick cracks
-- are drawn wider and may sprout thinner branches. Returns nothing, the pieces are added to `pattern`.
local function grow(pattern, rng, x, y, angle, length, thickness)
    local grown = 0

    while grown < length do
        local piece = rng:random() * (MAX_PIECE - MIN_PIECE) + MIN_PIECE
        angle = angle + (rng:random() - 0.5) * 0.4

        local next_x = x + math.cos(angle) * piece
        local next_y = y + math.sin(angle) * piece
        add_piece(pattern, x, y, next_x, next_y, thickness)

        if thickness > 1 and length - grown > 0.2 and rng:random() < BRANCH_CHANCE then
            local side = rng:random() < 0.5 and -1 or 1
            local branch_angle = angle + side * (0.5 + rng:random() * 0.4)
            grow(pattern, rng, next_x, next_y, branch_angle, (length - grown) * 0.5, thickness - 1)
        end

        x, y = next_x, next_y
        grown = grown + piece
    end
end

-- Returns the point where main crack `ray` (a list of pieces) first gets farther than `radius` from the
-- impact point, or nil if it stays closer.
local function find_on_ray(ray, radius)
    for _, piece in ipairs(ray) do
        if math.sqrt(piece[3] * piece[3] + piece[4] * piece[4]) >= radius then
            return piece[3], piece[4]
        end
    end
    return nil
end

-- Makes a new random pattern. rng is a love.math random generator.
function cracks.create(rng)
    local pattern = {pieces = {}}
    local rays = {}

    for i = 1, RAY_COUNT do
        local angle = (i - 1) / RAY_COUNT * 2 * math.pi + (rng:random() - 0.5) * 0.4
        local length = rng:random() * (MAX_RAY_LENGTH - MIN_RAY_LENGTH) + MIN_RAY_LENGTH

        -- the main crack is grown into its own list first, so the rings can find points on it
        local ray_pattern = {pieces = {}}
        grow(ray_pattern, rng, 0, 0, angle, length, 3)
        for _, piece in ipairs(ray_pattern.pieces) do
            table.insert(pattern.pieces, piece)
        end
        rays[i] = ray_pattern.pieces
    end

    -- Rings: neighbouring main cracks are joined by short crooked lines at the same distance.
    for _, radius in ipairs(RING_RADII) do
        for i = 1, RAY_COUNT do
            local x1, y1 = find_on_ray(rays[i], radius)
            local x2, y2 = find_on_ray(rays[i % RAY_COUNT + 1], radius)

            if x1 and x2 then
                local middle_x = (x1 + x2) / 2 + (rng:random() - 0.5) * 0.03
                local middle_y = (y1 + y2) / 2 + (rng:random() - 0.5) * 0.03
                add_piece(pattern, x1, y1, middle_x, middle_y, 1)
                add_piece(pattern, middle_x, middle_y, x2, y2, 1)
            end
        end
    end

    return pattern
end

-- Draws the pieces of `pattern` whose order is at most `visible` (0..1; 1 = the whole picture) around the
-- impact point (center_x, center_y) on the screen. `height` is the window height, which is the unit the
-- pattern is measured in; `alpha` (0..1) is the opacity. Each piece is a dark line with a thinner light
-- line on top, which reads as a crack in glass over any background.
function cracks.draw(pattern, visible, alpha, center_x, center_y, height)
    love.graphics.setLineStyle("rough")

    for _, piece in ipairs(pattern.pieces) do
        if piece[5] <= visible then
            local x1 = center_x + piece[1] * height
            local y1 = center_y + piece[2] * height
            local x2 = center_x + piece[3] * height
            local y2 = center_y + piece[4] * height
            -- a main crack is about 3 pixels wide in a window 1080 high, side branches 2 and 1
            local width = math.max(1, piece[6] * height / 1080)

            love.graphics.setColor(0, 0, 0, 0.55 * alpha)
            love.graphics.setLineWidth(width + 2)
            love.graphics.line(x1, y1, x2, y2)

            love.graphics.setColor(1, 1, 1, alpha)
            love.graphics.setLineWidth(width)
            love.graphics.line(x1 - 1, y1 - 1, x2 - 1, y2 - 1)
        end
    end

    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 1)
end

return cracks
