-- The discard pile on the table (client side). It remembers only its top two cards: the top one is drawn
-- and the one below takes its place when the top card is taken. `texture` is the empty-slot image shown
-- while there are no cards. Global constructor-style class: DiscardPile(x, y, texture, scaleX, scaleY),
-- created in client/layout.lua. x, y is the top-left corner.

require 'shaders'

local love = require "love"

-- Creates an empty pile at (x, y); `texture` is the empty-slot image.
function DiscardPile(x, y, texture, scaleX, scaleY)
    local self = {}
    self.x = x
    self.y = y
    self.texture = texture
    self.scaleX = scaleX
    self.scaleY = scaleY
    self.highest_card = nil
    self.second_highest_card = nil
    self.hover_scale = 1.0

    -- Puts `card` on top (the old top becomes second_highest_card) and snaps it to the pile's position and
    -- scale.
    function self:add_card(card)
        self.second_highest_card = self.highest_card
        self.highest_card = card
        card:set_position(self.x, self.y)
        card:set_scale(self.scaleX, self.scaleY)
    end

    -- Removes and returns the top card (nil if the pile is empty); the card below becomes the top. Only one
    -- level is remembered, so a second removal in a row without a new card empties the display.
    function self:remove_top_card()
        local removed_card = self.highest_card
        self.highest_card = self.second_highest_card
        self.second_highest_card = nil
        return removed_card
    end

    -- Forgets both cards (new round).
    function self:reset()
        self.highest_card = nil
        self.second_highest_card = nil
    end

    -- Returns the top-left corner x, y (cards that go to the pile fly here).
    function self:get_position()
        return self.x, self.y
    end

    -- On-screen width of the pile.
    function self:get_width()
        return self.texture:getWidth() * self.scaleX
    end

    -- On-screen height of the pile.
    function self:get_height()
        return self.texture:getHeight() * self.scaleY
    end

    -- Same hover animation as Deck:update (0.05 per frame up to 1.1, back to 1.0 when the mouse leaves).
    function self:update(mx, my)
        local width = self.texture:getWidth() * self.scaleX
        local height = self.texture:getHeight() * self.scaleY

        if mx >= self.x and mx <= self.x + width and
           my >= self.y and my <= self.y + height then
            self.hover_scale = math.min(self.hover_scale + 0.05, 1.1)
        else
            self.hover_scale = math.max(self.hover_scale - 0.05, 1.0)
        end
    end

    -- Draws the top card (or the empty slot) with the noise shader, enlarged by hover_scale around its
    -- centre. The shader that was active before is restored.
    function self:draw()
        local width = self.texture:getWidth() * self.scaleX
        local scale_offset = (self.hover_scale - 1.0) * width / 2

        local currentShader = love.graphics.getShader()
        love.graphics.setShader(card_shader)
        card_shader:send("time", love.timer.getTime())

        if self.highest_card ~= nil then
            love.graphics.draw(self.highest_card.texture,
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

    -- True if the click (x, y) hits the pile. `button` is unused; callers check the mouse button
    -- themselves.
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