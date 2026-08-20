local love = require "love"

local WOBBLE_ANGLE = math.rad(2)
local WOBBLE_SPEED = 0.5
local WOBBLE_BOB = 2

WOBBLE_ENABLED = true

function Card(rank, suit, x, y, texture, scaleX, scaleY)
    local self = {}
    self.rank = rank
    self.suit = suit
    self.x = x
    self.y = y
    self.texture = texture
    self.scaleX = scaleX
    self.scaleY = scaleY
    self.is_active = true
    self.wobble_seed = love.math.random() * 2 * math.pi


    function self:draw(is_wobble)
        if is_wobble and self.is_active and WOBBLE_ENABLED then
            local t = love.timer.getTime() * WOBBLE_SPEED + self.wobble_seed
            local angle = math.sin(t) * WOBBLE_ANGLE
            local bob = math.sin(t * 2) * WOBBLE_BOB
            local w, h = self.texture:getWidth(), self.texture:getHeight()

            love.graphics.draw(self.texture, self.x + w * self.scaleX / 2, self.y + h * self.scaleY / 2 + bob,
                angle, self.scaleX, self.scaleY, w / 2, h / 2)
        else
            love.graphics.draw(self.texture, self.x, self.y, 0, self.scaleX, self.scaleY)
        end
    end

    function self:draw_with_offset(offsetX, offsetY, is_wobble)
        if is_wobble and WOBBLE_ENABLED then
            local t = love.timer.getTime() * WOBBLE_SPEED + self.wobble_seed
            local angle = math.sin(t) * WOBBLE_ANGLE
            local bob = math.sin(t * 2) * WOBBLE_BOB
            local w, h = self.texture:getWidth(), self.texture:getHeight()

            love.graphics.draw(self.texture, self.x + w * self.scaleX / 2 + offsetX, self.y + h * self.scaleY / 2 + bob + offsetY,
                angle, self.scaleX, self.scaleY, w / 2, h / 2)
        else
            love.graphics.draw(self.texture, self.x + offsetX, self.y + offsetY, 0, self.scaleX, self.scaleY)
        end
    end

    function self:mousepressed(x, y, button)
        if x >= self.x and x <= self.x + self.texture:getWidth() * self.scaleX and
           y >= self.y and y <= self.y + self.texture:getHeight() * self.scaleY then
            return self.is_active
        end
        return false
    end

    function self:mousehover(x, y, dx, dy)
        if x >= self.x and x <= self.x + self.texture:getWidth() * self.scaleX and
           y >= self.y and y <= self.y + self.texture:getHeight() * self.scaleY then
            return true
        end
        return false
    end

    function self:set_scale(scaleX, scaleY)
        self.scaleX = scaleX
        self.scaleY = scaleY
    end

    function self:set_position(x, y)
        self.x = x
        self.y = y
    end

    function self:get_position()
        return self.x, self.y
    end

    function self:get_width()
        return self.texture:getWidth() * self.scaleX
    end

    function self:get_height()
        return self.texture:getHeight() * self.scaleY
    end

    function self:move_to(dt, speed, target_x, target_y)
        self.is_active = false
        local dx = target_x - self.x
        local dy = target_y - self.y
        local distance = math.sqrt(dx * dx + dy * dy)

        if distance > 0 then
            local move_distance = speed * dt
            if move_distance >= distance then
                self.x = target_x
                self.y = target_y
            else
                self.x = self.x + (dx / distance) * move_distance
                self.y = self.y + (dy / distance) * move_distance
            end
        else 
            self.is_active = true
        end
    end

    function self:is_lesser_than(other_card)
        local rank_order = {["A"]=1, ["2"]=2, ["3"]=3, ["4"]=4, ["5"]=5, ["6"]=6, ["7"]=7, ["8"]=8, ["9"]=9, ["10"]=10, ["J"]=11, ["Q"]=12, ["K"]=13}
        local suit_order = {["club"]=2, ["diamond"]=1, ["heart"]=3, ["spade"]=4}

        if rank_order[self.rank] < rank_order[other_card.rank] then
            return true
        elseif rank_order[self.rank] == rank_order[other_card.rank] then
            return suit_order[self.suit] < suit_order[other_card.suit]
        end

        return false
    end

    return self
end

return Card