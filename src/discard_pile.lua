-- The discard pile on the table (client side). It remembers only its top two cards: the top one is drawn
-- and the one below takes its place when the top card is taken. `texture` is the empty-slot image shown
-- while there are no cards. Global constructor-style class: DiscardPile(x, y, texture, scaleX, scaleY),
-- created in client/layout.lua. x, y is the top-left corner.

require 'shaders'

local love = require "love"
local ui = require "ui"

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

    -- Same hover animation as Deck:update. dt is in seconds.
    function self:update(dt, mx, my)
        local width = self.texture:getWidth() * self.scaleX
        local height = self.texture:getHeight() * self.scaleY
        local is_hovered = mx >= self.x and mx <= self.x + width and
                           my >= self.y and my <= self.y + height

        self.hover_scale = ui.next_hover_scale(self.hover_scale, is_hovered, dt)
    end

    -- Draws the top card (or the empty slot) with the noise shader, enlarged by hover_scale around its
    -- centre. The shader that was active before is restored.
    function self:draw()
        local width = self.texture:getWidth() * self.scaleX
        local height = self.texture:getHeight() * self.scaleY
        local offset_x = (self.hover_scale - 1.0) * width / 2
        local offset_y = (self.hover_scale - 1.0) * height / 2

        local currentShader = love.graphics.getShader()
        love.graphics.setShader(card_shader)
        card_shader:send("time", love.timer.getTime())

        if self.highest_card ~= nil then
            love.graphics.draw(self.highest_card.texture,
                self.x - offset_x,
                self.y - offset_y,
                0,
                self.scaleX * self.hover_scale,
                self.scaleY * self.hover_scale)
        else
            love.graphics.draw(self.texture,
                self.x - offset_x,
                self.y - offset_y,
                0,
                self.scaleX * self.hover_scale,
                self.scaleY * self.hover_scale)
        end

        love.graphics.setShader(currentShader)
    end

    -- True if the click (x, y) hits the pile; callers check the mouse button themselves.
    function self:mousepressed(x, y)
        if x >= self.x and x <= self.x + self.texture:getWidth() * self.scaleX and
           y >= self.y and y <= self.y + self.texture:getHeight() * self.scaleY then
            return true
        end
        return false
    end

    return self
end

return DiscardPile