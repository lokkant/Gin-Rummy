require 'card'
require 'shaders'

local love = require "love"


function OpponentHand(x, y)
    local self = {}
    self.x = x
    self.y = y
    self.combination1 = {}
    self.combination2 = {}
    self.combination3 = {}
    self.cards = {}


    function self:update(dt, speed, dragging_card, hovered_card)
        for i, card in ipairs(self.cards) do
            if card ~= dragging_card and card ~= hovered_card then
                local width = card:get_width() / 1.5
                local total_width = width * #self.cards
                local target_x = self.x - total_width / 2 + (i - 1) * width

                local center_index = (#self.cards + 1) / 2
                local distance_from_center = math.abs(i - center_index)
                local fan_offset = (distance_from_center / math.max(#self.cards / 2, 1)) * 20
                local target_y = self.y - fan_offset

                card:move_to(dt, speed, target_x, target_y)
            end
        end
    end

    
    function self:add_card(card)
        table.insert(self.cards, card)
        table.sort(self.cards, function(a, b) return a:is_lesser_than(b) end)
    end


    function self:remove_random_card()
        if #self.cards == 0 then return end
        local index = love.math.random(#self.cards)
        table.remove(self.cards, index)
    end


    function self:reset()
        self.cards = {}
    end


    function self:draw(dragging_card, hovered_card)
        local currentShader = love.graphics.getShader()
        love.graphics.setShader(card_shader)
        card_shader:send("time", love.timer.getTime())

        for _, card in ipairs(self.cards) do
            card:draw(true)
        end

        love.graphics.setShader(currentShader)
    end

    return self
end

return OpponentHand