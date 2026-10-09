-- Small helpers shared by the screens: hit testing, a plain rounded button and the hover animation of
-- the deck and the discard pile. Rectangles are tables {x, y, w, h} in window pixels.

local love = require "love"

local ui = {}

-- How much the deck and the discard pile grow under the mouse (1.0 = normal size) and how fast
-- (scale units per second: the full change takes about a thirtieth of a second).
local HOVER_SCALE_MAX = 1.1
local HOVER_SPEED = 3.0

-- Returns true when the point (x, y) lies inside rect (edges included).
function ui.point_in_rect(x, y, rect)
    return x >= rect.x and x <= rect.x + rect.w and y >= rect.y and y <= rect.y + rect.h
end

-- Returns the next enlargement of a hoverable sprite: it grows while is_hovered and shrinks back
-- otherwise, at a speed that does not depend on the frame rate. dt is in seconds.
function ui.next_hover_scale(hover_scale, is_hovered, dt)
    if is_hovered then
        return math.min(hover_scale + HOVER_SPEED * dt, HOVER_SCALE_MAX)
    end

    return math.max(hover_scale - HOVER_SPEED * dt, 1.0)
end

-- Draws a filled rounded button with a centred one-line label in the current font; color is {r, g, b, a}
-- (alpha optional). Resets the draw colour to white afterwards.
function ui.draw_button(rect, label, color)
    love.graphics.setColor(color[1], color[2], color[3], color[4] or 1)
    love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h, 8, 8)

    love.graphics.setColor(1, 1, 1, 1)
    -- 8 is roughly half a text line, which centres the label vertically.
    love.graphics.printf(label, rect.x, rect.y + rect.h / 2 - 8, rect.w, "center")
end

return ui
