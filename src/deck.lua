-- The stock pile on the table (client side): a clickable sprite with a hover animation. It does not know
-- the cards inside, the server decides what is drawn. Global constructor-style class:
-- Deck(x, y, texture, scaleX, scaleY), created in client/layout.lua. x, y is the top-left corner.

local love = require "love"

-- Creates the pile at (x, y); hover_scale starts at 1 (no enlargement).
function Deck(x, y, texture, scaleX, scaleY)
    local self = {}
    self.x = x
    self.y = y
    self.texture = texture
    self.scaleX = scaleX
    self.scaleY = scaleY
    self.hover_scale = 1.0

    -- Hover animation: hover_scale grows by 0.05 per call up to 1.1 while the mouse (mx, my) is over the
    -- pile and shrinks back to 1.0 otherwise. Called every frame, so the speed depends on the frame rate.
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

    -- Draws the pile enlarged by hover_scale. The top-left corner is shifted by half of the extra width,
    -- which keeps it centred horizontally (the same shift is used vertically, exact only for square
    -- sprites).
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

    -- True if the click (x, y) hits the pile. `button` is unused; callers check the mouse button
    -- themselves.
    function self:mousepressed(x, y, button)
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