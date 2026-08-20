require 'shaders'

local love = require "love"

function DiscardPile(x, y, texture, scaleX, scaleY)
    local self = {}
    self.x = x
    self.y = y
    self.texture = texture
    self.scaleX = scaleX
    self.scaleY = scaleY
    self.hightest_card = nil
    self.second_highest_card = nil
    self.is_hovered = false
    self.hover_scale = 1.0

    function self:add_card(card)
        self.second_highest_card = self.hightest_card
        self.hightest_card = card
        card:set_position(self.x, self.y)
        card:set_scale(self.scaleX, self.scaleY)
    end

    function self:remove_top_card()
        local removed_card = self.hightest_card
        self.hightest_card = self.second_highest_card
        self.second_highest_card = nil
        return removed_card
    end

    function self:reset()
        self.hightest_card = nil
        self.second_highest_card = nil
    end

    function self:get_position()
        return self.x, self.y
    end

    function self:get_width()
        return self.texture:getWidth() * self.scaleX
    end

    function self:get_heigth()
        return self.texture:getHeight() * self.scaleY
    end

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

        local currentShader = love.graphics.getShader()
        love.graphics.setShader(card_shader)
        card_shader:send("time", love.timer.getTime())

        if self.hightest_card ~= nil then
            love.graphics.draw(self.hightest_card.texture,
                self.x - scale_offset,
                self.y - scale_offset,
                0,
                self.scaleX * self.hover_scale,
                self.scaleY * self.hover_scale)
        else
            love.graphics.draw(self.texture,
                self.x - scale_offset,
                self.y - scale_offset,
                0,
                self.scaleX * self.hover_scale,
                self.scaleY * self.hover_scale)
        end

        love.graphics.setShader(currentShader)
    end

    function self:mousepressed(x, y, button)
        if x >= self.x and x <= self.x + self.texture:getWidth() * self.scaleX and
           y >= self.y and y <= self.y + self.texture:getHeight() * self.scaleY then
            return true
        end
        return false
    end

    return self
end

return DiscardPile