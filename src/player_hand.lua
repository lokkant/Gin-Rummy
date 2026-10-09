-- The local player's hand (client side): fan layout, hover lift, hit testing, drawing with meld highlights
-- and the meld analysis behind the KNOCK button. Global constructor-style class: PlayerHand(x, y),
-- x = horizontal centre of the fan, y = top of the cards at the centre.
-- The cards are kept sorted: first by the meld arrangement currently shown (best_combinations), then the
-- deadwood by rank and suit. During play the hand has 10 cards, 11 between drawing and discarding.

require 'card'
require 'shaders'
require 'best_melds'

local love = require "love"

-- Creates an empty hand centred on x with the top of its cards at y.
function PlayerHand(x, y)
    -- best_combinations: all meld arrangements with the lowest deadwood ({{}} = one arrangement without
    -- melds); index_of_combination: the one shown; score: that lowest deadwood of the whole hand.
    local self = {}
    self.x = x
    self.y = y
    self.cards = {}
    -- Multiplier of the sway of the cards, set from outside (1 = calm).
    self.nervousness = 1
    self.best_combinations = {{}}
    self.index_of_combination = 1
    self.score = 0


    -- Returns the resting top-left position (x, y) of card number i. Cards overlap, each taking 2/3 of its
    -- width, and the row is centred on self.x. The cards at both ends are lowered by up to 20 px
    -- (fan_offset: distance from the middle slot divided by half the hand size, so 0 in the middle and
    -- about 1 at the ends).
    function self:get_rest_position(i)
        local card = self.cards[i]
        local width = card:get_width() / 1.5
        local total_width = width * #self.cards
        local target_x = self.x - total_width / 2 + (i - 1) * width

        local center_index = (#self.cards + 1) / 2
        local distance_from_center = math.abs(i - center_index)
        local fan_offset = (distance_from_center / math.max(#self.cards / 2, 1)) * 20

        return target_x, self.y + fan_offset
    end


    -- Returns the card under the point (x, y), or nil. Hit testing uses the REST positions, not the
    -- animated ones: a hovered card is lifted away from the cursor, and testing its moving position would
    -- make it flicker between hovered and not hovered. `hovered_card` is the currently lifted card.
    function self:get_card_at(x, y, hovered_card)
        -- Later cards are drawn on top, so test from the last to the first.
        for i = #self.cards, 1, -1 do
            local card = self.cards[i]
            local rx, ry = self:get_rest_position(i)
            local w, h = card:get_width(), card:get_height()
            if x >= rx and x <= rx + w and y >= ry and y <= ry + h then
                return card
            end
        end

        -- The lifted card also owns the strip it was lifted over (between its raised top and its rest top),
        -- so the cursor can stay in that strip without losing the hover.
        if hovered_card ~= nil then
            for i, card in ipairs(self.cards) do
                if card == hovered_card then
                    local rx, ry = self:get_rest_position(i)
                    local lift = card:get_height() / 6
                    if x >= rx and x <= rx + card:get_width() and y >= ry - lift and y < ry then
                        return card
                    end
                end
            end
        end

        return nil
    end


    -- Moves the cards towards their rest positions at `speed` pixels per second. The hovered card is raised
    -- by a sixth of its height; the dragged card follows the mouse and is skipped.
    function self:update(dt, speed, dragging_card, hovered_card)
        for i, card in ipairs(self.cards) do
            if card ~= dragging_card then
                local target_x, target_y = self:get_rest_position(i)

                if card == hovered_card then
                    target_y = target_y - card:get_height() / 6
                end

                card:move_to(dt, speed, target_x, target_y)
            end
        end
    end


    -- Switches to the next best arrangement (wraps around) and reorders the hand to show it. Bound to the
    -- right mouse button.
    function self:increase_index_of_combination()
        self.index_of_combination = (self.index_of_combination % #self.best_combinations) + 1
        self:update_card_order()
    end


    -- Returns the shown arrangement: a list of melds, each a list of Card objects.
    function self:get_current_combination()
        return self.best_combinations[self.index_of_combination]
    end


    -- Returns the cards that are in no meld of the shown arrangement.
    function self:get_deadwood_cards()
        local used = {}
        for _, meld in ipairs(self:get_current_combination()) do
            for _, card in ipairs(meld) do
                used[card] = true
            end
        end

        local deadwood = {}
        for _, card in ipairs(self.cards) do
            if not used[card] then
                table.insert(deadwood, card)
            end
        end

        return deadwood
    end


    -- Returns the meld cards that can leave their meld without breaking it: any card of a four-card set,
    -- only the two end cards of a run of four or more (taking from the middle would split the run). Melds
    -- of exactly three have no removable card. Needed when all 11 cards are melded (gin) and one must be
    -- discarded.
    function self:get_removable_meld_cards()
        local removable = {}

        for _, meld in ipairs(self:get_current_combination()) do
            if #meld >= 4 then
                local is_set = true
                for i = 2, #meld do
                    if meld[i].rank ~= meld[1].rank then
                        is_set = false
                        break
                    end
                end

                if is_set then
                    for _, card in ipairs(meld) do
                        table.insert(removable, card)
                    end
                else
                    table.insert(removable, meld[1])
                    table.insert(removable, meld[#meld])
                end
            end
        end

        return removable
    end


    -- Chooses the card to discard when knocking. Returns (card, deadwood left after the discard) or nil if
    -- there is none. Best is the deadwood card with the highest value (lowest deadwood left);
    -- `forbidden_card` (the card just taken from the discard pile, which may not be thrown back) is
    -- excluded. Without any usable deadwood card, a removable meld card is thrown and the deadwood stays
    -- self.score. Expects 11 cards.
    function self:get_knock_discard(forbidden_card)
        local best_card, best_deadwood

        for _, card in ipairs(self:get_deadwood_cards()) do
            if card ~= forbidden_card then
                -- Deadwood of the hand if this card were thrown away.
                local deadwood = self.score - get_card_value(card)
                -- Strictly less, so among equal cards the first one wins.
                if best_card == nil or deadwood < best_deadwood then
                    best_card = card
                    best_deadwood = deadwood
                end
            end
        end

        if best_card ~= nil then
            return best_card, best_deadwood
        end

        for _, card in ipairs(self:get_removable_meld_cards()) do
            if card ~= forbidden_card then
                return card, self.score
            end
        end

        return nil
    end


    -- Empties the hand (new round).
    function self:reset()
        self.cards = {}
        self.index_of_combination = 1
        self:update_best_combinations()
    end


    -- Adds a card and re-analyses the hand (sorting, best meld arrangements, deadwood).
    function self:add_card(card)
        table.insert(self.cards, card)
        self:update_best_combinations()
    end


    -- Removes the card with this rank and suit, if present, and re-analyses the hand.
    function self:remove_card(rank, suit)
        for i, card in ipairs(self.cards) do
            if rank == card.rank and suit == card.suit then
                table.remove(self.cards, i)
                self:update_best_combinations()
                break
            end
        end
    end


    -- Draws the hand in two passes. First the cards of the shown arrangement, each meld outlined by the
    -- highlight shader in its own colour (the hovered or dragged ones use the variant with a shine). Then
    -- the rest with the plain noise shader (hovered / dragged ones again with the shine variants).
    -- update_card_order puts melded cards first, so the first count - 1 cards of self.cards are the melded
    -- ones and the loop for the rest starts at index `count`. The previous shader is restored at the end.
    function self:draw(dragging_card, hovered_card)
        local currentShader = love.graphics.getShader()
        love.graphics.setShader(highlight_card_shader)
        highlight_card_shader:send("time", love.timer.getTime())

        local colors = combination_colors
        local count = 1

        for i, combination in ipairs(self.best_combinations[self.index_of_combination]) do
            for _, card in ipairs(combination) do
                if card ~= hovered_card and card ~= dragging_card then
                    highlight_card_shader:send("highlight_color", colors[i])
                    card:draw(true, self.nervousness)
                else
                    love.graphics.setShader(highlight_hovered_card_shader)
                    highlight_hovered_card_shader:send("time", love.timer.getTime())
                    highlight_hovered_card_shader:send("highlight_color", colors[i])

                    card:draw(true, self.nervousness)

                    love.graphics.setShader(highlight_card_shader)
                end
                count = count + 1
            end
        end

        love.graphics.setShader(card_shader)
        card_shader:send("time", love.timer.getTime())

        for ind = count, #self.cards do
            local card = self.cards[ind]
            if card ~= hovered_card and card ~= dragging_card then
                card:draw(true, self.nervousness)
            elseif card == hovered_card then
                love.graphics.setShader(hovered_card_shader)
                hovered_card_shader:send("time", love.timer.getTime())

                card:draw(true, self.nervousness)

                love.graphics.setShader(card_shader)
            elseif card == dragging_card then
                love.graphics.setShader(dragging_card_shader)
                dragging_card_shader:send("time", love.timer.getTime())

                card:draw(true, self.nervousness)

                love.graphics.setShader(card_shader)
            end
        end

        love.graphics.setShader(currentShader)
    end


    -- Re-analyses the hand after every change: sorts by rank/suit, finds the best meld arrangements and the
    -- lowest deadwood (self.score), then reorders the cards for display. The result names hide the global
    -- function only after the call has been evaluated, so calling best_combinations here is safe.
    function self:update_best_combinations()
        table.sort(self.cards, function (a, b) return a:is_lesser_than(b) end)

        local best_combinations, best_score = best_combinations(self.cards)

        self.score = best_score
        self.best_combinations = best_combinations

        self:update_card_order()
    end


    -- Reorders self.cards for display: cards of the shown arrangement first (meld 1, 2, 3, each sorted),
    -- then the deadwood by rank and suit. The index is clamped because the number of arrangements can
    -- shrink when the hand changes.
    function self:update_card_order()
        local priority = {}
        self.index_of_combination = math.min(self.index_of_combination, #self.best_combinations)
        for i, combination in ipairs(self.best_combinations[self.index_of_combination]) do
            table.sort(combination, function(a, b) return a:is_lesser_than(b) end)
            for _, card in ipairs(combination) do
                priority[card] = i
            end
        end

        table.sort(self.cards, function(a, b)
            -- Priority 4 puts deadwood after the (at most three) melds.
            local priority1 = priority[a] or 4
            local priority2 = priority[b] or 4

            if priority1 ~= priority2 then
                return priority1 < priority2
            end

            return a:is_lesser_than(b)
        end)
    end

    return self
end

return PlayerHand