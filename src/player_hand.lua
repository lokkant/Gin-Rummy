require 'card'
require 'shaders'
require 'best_melds'

local love = require "love"

local FIRST_COMBINATION_COLOR = {0.0, 0.0, 1.0}
local SECOND_COMBINATION_COLOR = {0.0, 1.0, 0.0}
local THIRD_COMBINATION_COLOR = {1.0, 0.0, 0.0}

function PlayerHand(x, y)
    local self = {}
    self.x = x
    self.y = y
    self.cards = {}
    self.best_combinations = {{}}
    self.index_of_combination = 1
    self.score = 0


    function self:update(dt, speed, dragging_card, hovered_card)
        for i, card in ipairs(self.cards) do
            if card ~= dragging_card then
                local width = card:get_width() / 1.5
                local total_width = width * #self.cards
                local target_x = self.x - total_width / 2 + (i - 1) * width

                local center_index = (#self.cards + 1) / 2
                local distance_from_center = math.abs(i - center_index)
                local fan_offset = (distance_from_center / math.max(#self.cards / 2, 1)) * 20
                local target_y = self.y + fan_offset

                if card == hovered_card then
                    target_y = target_y - card:get_height() / 6
                end

                card:move_to(dt, speed, target_x, target_y)
            end
        end
    end


    function self:increase_index_of_combination()
        self.index_of_combination = (self.index_of_combination % #self.best_combinations) + 1
        self:update_card_order()
    end


    function self:get_current_combination()
        return self.best_combinations[self.index_of_combination]
    end


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


    function self:get_knock_discard()
        local deadwood = self:get_deadwood_cards()
        if #deadwood == 0 then return nil end

        local best_card = deadwood[1]
        local best_value = get_card_value(best_card)

        for i = 2, #deadwood do
            local value = get_card_value(deadwood[i])
            if value > best_value then
                best_card = deadwood[i]
                best_value = value
            end
        end

        return best_card
    end


    function self:reset()
        self.cards = {}
        self.index_of_combination = 1
        self:update_best_combinations()
    end


    function self:add_card(card)
        table.insert(self.cards, card)
        self:update_best_combinations()
    end


    function self:remove_card(rank, suit)
        for i, card in ipairs(self.cards) do
            if rank == card.rank and suit == card.suit then
                table.remove(self.cards, i)
                self:update_best_combinations()
                break
            end
        end
    end


    function self:draw(dragging_card, hovered_card)
        local currentShader = love.graphics.getShader()
        love.graphics.setShader(highlight_card_shader)
        highlight_card_shader:send("time", love.timer.getTime())

        local colors = {FIRST_COMBINATION_COLOR, SECOND_COMBINATION_COLOR, THIRD_COMBINATION_COLOR}
        local count = 1

        for i, combination in ipairs(self.best_combinations[self.index_of_combination]) do
            for _, card in ipairs(combination) do
                if card ~= hovered_card and card ~= dragging_card then
                    highlight_card_shader:send("highlight_color", colors[i])
                    card:draw(true)
                elseif card == hovered_card then
                    love.graphics.setShader(hovered_card_shader)
                    hovered_card_shader:send("time", love.timer.getTime())

                    card:draw(true)

                    love.graphics.setShader(highlight_card_shader)
                elseif card == dragging_card then
                    love.graphics.setShader(dragging_card_shader)
                    dragging_card_shader:send("time", love.timer.getTime())

                    card:draw(true)

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
                card:draw(true)
            elseif card == hovered_card then
                love.graphics.setShader(hovered_card_shader)
                hovered_card_shader:send("time", love.timer.getTime())

                card:draw(true)

                love.graphics.setShader(card_shader)
            elseif card == dragging_card then
                love.graphics.setShader(dragging_card_shader)
                dragging_card_shader:send("time", love.timer.getTime())

                card:draw(true)

                love.graphics.setShader(highlight_card_shader)
            end
        end

        love.graphics.setShader(currentShader)
    end


    function self:update_best_combinations()
        table.sort(self.cards, function (a, b) return a:is_lesser_than(b) end)

        local best_combinations, best_score = best_combinations(self.cards)

        self.score = best_score
        self.best_combinations = best_combinations

        self:update_card_order()
    end


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