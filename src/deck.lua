-- The stock pile on the table (client side): a clickable sprite with a hover animation. It does not know
-- the cards inside, the server decides what is drawn. Global constructor-style class:
-- Deck(x, y, texture, scaleX, scaleY), created in client/layout.lua. x, y is the top-left corner.

local love = require "love"
local ui = require "ui"
local horror = require "client/horror"

-- Creates the pile at (x, y); hover_scale starts at 1 (no enlargement).
function Deck(x, y, texture, scaleX, scaleY)
    local self = {}
    self.x = x
    self.y = y
    self.texture = texture
    self.scaleX = scaleX
    self.scaleY = scaleY
    self.hover_scale = 1.0

    -- Hover animation, called every frame: hover_scale grows while the mouse (mx, my) is over the pile
    -- and shrinks back to 1.0 otherwise (see ui.next_hover_scale). dt is in seconds.
    function self:update(dt, mx, my)
        local width = self.texture:getWidth() * self.scaleX
        local height = self.texture:getHeight() * self.scaleY
        local is_hovered = mx >= self.x and mx <= self.x + width and
                           my >= self.y and my <= self.y + height

        self.hover_scale = ui.next_hover_scale(self.hover_scale, is_hovered, dt)
    end

    -- Draws the pile enlarged by hover_scale around its centre: the top-left corner moves back by half of
    -- the extra width and half of the extra height.
    function self:draw()
        -- The pile slowly "breathes": its size changes by config.deck_breathing (a few percent at most).
        local scale_now = self.hover_scale * (1 + horror.amount("deck_breathing") * math.sin(love.timer.getTime() * 1.1))
        local width = self.texture:getWidth() * self.scaleX
        local height = self.texture:getHeight() * self.scaleY
        local offset_x = (scale_now - 1.0) * width / 2
        local offset_y = (scale_now - 1.0) * height / 2

        love.graphics.draw(self.texture,
            self.x - offset_x,
            self.y - offset_y,
            0,
            self.scaleX * scale_now,
            self.scaleY * scale_now)
    end

    -- True if the click (x, y) hits the pile; callers check the mouse button themselves.
    function self:mousepressed(x, y)
        if x >= self.x and x <= self.x + self.texture:getWidth() * self.scaleX and
           y >= self.y and y <= self.y + self.texture:getHeight() * self.scaleY then
            return true
        end
        return false
    end

    -- Returns the top-left corner x, y (cards that come from the stock start their flight here).
    function self:get_position()
        return self.x, self.y
    end

    return self
end

return Deck