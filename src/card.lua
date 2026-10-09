-- A playing card, used both as plain data (rank, suit, ordering; also on the server) and as a sprite on the
-- client (position, texture, idle wobble, movement). Global constructor-style class: `require 'card'`
-- defines Card(rank, suit, x, y, texture, scaleX, scaleY).
-- Ranks: "A", "2".."10", "J", "Q", "K". Suits: "heart", "diamond", "club", "spade".
-- Methods take `self` explicitly, so a shallow table copy of a card is an independent card (messages.lua).

local love = require "love"

-- Idle wobble of cards: maximum sway angle (radians), speed factor of the sway and bob height in pixels.
local WOBBLE_ANGLE = math.rad(2)
local WOBBLE_SPEED = 0.5
local WOBBLE_BOB = 2

-- Global switch for the wobble; toggled from the pause menu.
WOBBLE_ENABLED = true

-- Creates a card. x, y is its top-left corner on screen; texture is nil for data-only cards.
-- is_active: false while the card is flying (see move_to), true once it rests and may be clicked.
-- wobble_seed gives every card its own phase so the cards do not sway in sync.
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


    -- Draws the card. With is_wobble (and wobble enabled, card at rest) it sways and bobs: t is the time
    -- scaled by WOBBLE_SPEED plus the card's own phase, the angle follows sin(t) and the vertical bob
    -- sin(2t), i.e. twice as fast. Rotation needs the card centre as origin, so it is drawn at position +
    -- half size with origin (w/2, h/2). Flying cards are drawn without wobble so their motion stays clean.
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

    -- True if (x, y) is on the card and the card is clickable (is_active). `button` is unused.
    function self:mousepressed(x, y, button)
        if x >= self.x and x <= self.x + self.texture:getWidth() * self.scaleX and
           y >= self.y and y <= self.y + self.texture:getHeight() * self.scaleY then
            return self.is_active
        end
        return false
    end

    -- Sets the draw scale.
    function self:set_scale(scaleX, scaleY)
        self.scaleX = scaleX
        self.scaleY = scaleY
    end

    -- Sets the top-left corner.
    function self:set_position(x, y)
        self.x = x
        self.y = y
    end

    -- Returns the top-left corner x, y.
    function self:get_position()
        return self.x, self.y
    end

    -- On-screen width (texture width times scale).
    function self:get_width()
        return self.texture:getWidth() * self.scaleX
    end

    -- On-screen height (texture height times scale).
    function self:get_height()
        return self.texture:getHeight() * self.scaleY
    end

    -- Moves the card towards (target_x, target_y) at `speed` pixels per second for a frame of length dt.
    -- The card is inactive while moving; it becomes active again on the first call after it has arrived.
    -- It never overshoots: when the step is longer than the remaining distance it snaps to the target.
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

    -- Ordering used to sort hands and runs: by rank (A low ... K high), ties by suit (diamond, club, heart,
    -- spade). Only the order between different cards matters, not the exact numbers.
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