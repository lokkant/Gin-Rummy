-- Small helpers shared by every screen that draws buttons: hit testing and a plain rounded button.
-- Rectangles are tables {x, y, w, h} in window pixels.


local love = require "love"

local ui = {}

-- Returns true when the point (x, y) lies inside rect (edges included).
function ui.point_in_rect(x, y, rect)
    return x >= rect.x and x <= rect.x + rect.w and y >= rect.y and y <= rect.y + rect.h
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
