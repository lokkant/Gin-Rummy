-- Small helpers shared by every screen that draws buttons

local love = require "love"

local ui = {}

-- rect is {x, y, w, h}
function ui.point_in_rect(x, y, rect)
    return x >= rect.x and x <= rect.x + rect.w and y >= rect.y and y <= rect.y + rect.h
end

-- A filled rounded button with a centered label, drawn in the current font; color is {r, g, b, a}
function ui.draw_button(rect, label, color)
    love.graphics.setColor(color[1], color[2], color[3], color[4] or 1)
    love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h, 8, 8)

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.printf(label, rect.x, rect.y + rect.h / 2 - 8, rect.w, "center")
end

return ui
