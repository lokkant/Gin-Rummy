-- The opponent's hand on screen (client side): face-down cards fanned along the top edge. The cards are
-- only counted, never identified (the server does not reveal them). Global constructor-style class:
-- OpponentHand(x, y), x = horizontal centre of the fan, y = top of the cards at the centre.
-- Uses the same fan layout as PlayerHand, mirrored vertically.

require 'card'
require 'shaders'

local love = require "love"


-- Creates an empty hand centred on x.
function OpponentHand(x, y)
    local self = {}
    self.x = x
    self.y = y
    self.cards = {}


    -- Moves every card towards its slot in the fan at `speed` pixels per second. dragging_card /
    -- hovered_card are skipped (they are controlled elsewhere); for the opponent they are normally nil.
    function self:update(dt, speed, dragging_card, hovered_card)
        for i, card in ipairs(self.cards) do
            if card ~= dragging_card and card ~= hovered_card then
                -- Horizontal step between cards is 2/3 of a card width, so neighbours overlap by a third.
                local width = card:get_width() / 1.5
                local total_width = width * #self.cards
                local target_x = self.x - total_width / 2 + (i - 1) * width

                -- Middle slot of the hand (fractional for an even number of cards) and how far slot i is
                -- from it.
                local center_index = (#self.cards + 1) / 2
                local distance_from_center = math.abs(i - center_index)
                -- The distance is normalised by half the hand size (0 in the middle, about 1 at the ends)
                -- and scaled to at most 20 px; the end cards sit higher than the middle ones, so the cards
                -- form an arc. max(..., 1) prevents a division by a number below 1 for an empty or one-card
                -- hand.
                local fan_offset = (distance_from_center / math.max(#self.cards / 2, 1)) * 20
                local target_y = self.y - fan_offset

                card:move_to(dt, speed, target_x, target_y)
            end
        end
    end


    -- Adds a card and keeps the hand sorted so the layout is stable.
    function self:add_card(card)
        table.insert(self.cards, card)
        table.sort(self.cards, function(a, b) return a:is_lesser_than(b) end)
    end


    -- Removes and returns a random card (nil if empty). The opponent's discard does not say which face-down
    -- card left their hand, so any of them will do.
    function self:remove_random_card()
        if #self.cards == 0 then return nil end
        local index = love.math.random(#self.cards)
        return table.remove(self.cards, index)
    end


    -- Removes all cards (new round).
    function self:reset()
        self.cards = {}
    end


    -- Draws all cards with the noise shader and wobble; both arguments are unused here. The previous shader
    -- is restored afterwards.
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