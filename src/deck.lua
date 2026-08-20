require 'cards_database'

local love = require "love"

function Deck(x, y, texture, scaleX, scaleY)
    local self = {}
    self.x = x
    self.y = y
    self.texture = texture
    self.scaleX = scaleX
    self.scaleY = scaleY
    self.is_hovered = false
    self.hover_scale = 1.0

    function self:update(mx, my)
        local width = self.texture:getWidth() * self.scaleX
        local height = self.texture:getHeight() * self.scaleY

        if mx >= self.x and mx <= self.x + width and
           my >= self.y and my <= self.y + height then
            self.is_hovered = true
            self.hover_scale = math.min(self.hover_scale + 0.05, 1.1)
        else
            self.is_hovered = false
            self.hover_scale = math.max(self.hover_scale - 0.05, 1.0)
        end
    end

    function self:draw()
        local width = self.texture:getWidth() * self.scaleX
        local scale_offset = (self.hover_scale - 1.0) * width / 2

        love.graphics.draw(self.texture,
            self.x - scale_offset,
            self.y - scale_offset,
            0,
            self.scaleX * self.hover_scale,
            self.scaleY * self.hover_scale)
    end

    function self:mousepressed(x, y, button)
        if x >= self.x and x <= self.x + self.texture:getWidth() * self.scaleX and
           y >= self.y and y <= self.y + self.texture:getHeight() * self.scaleY then
            return true
        end
        return false
    end

    function self:get_position()
        return self.x, self.y
    end

    return self
end

return Deck