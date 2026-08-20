local json = require "dkjson"

require 'server_deck'
require 'best_melds'
require 'cards_database'

local GIN_BONUS = 25
local UNDERCUT_BONUS = 25
local WINNING_SCORE = 100

local function remove_card_from_hand(hand, card_name)
    for i, name in ipairs(hand) do
        if name == card_name then
            table.remove(hand, i)
            return true
        end
    end
    return false
end

local function hand_contains(hand, card_name)
    for _, name in ipairs(hand) do
        if name == card_name then
            return true
        end
    end
    return false
end

local function card_value_from_name(name)
    local rank = string.match(name, "^([%w]+)_")
    return get_card_value({rank = rank})
end

function Game(player1, player2, deck)
    local self = {}
    self.player1 = player1
    self.player2 = player2
    self.player1_score = 0
    self.player2_score = 0
    self.player1_hand = {}
    self.player2_hand = {}
    self.discard_pile = {}
    self.deck = deck
    self.turn = player1
    self.take_card = false
    self.is_over_move = false
    self.is_over_game = false
    self.is_new_round = true
    self.pending_knock = nil

    function self:current_turn()
        return self.turn
    end

    function self:get_hand(player)
        if player == player1 then
            return self.player1_hand
        else
            return self.player2_hand
        end
    end

    function self:get_opponent(player)
        if player == player1 then
            return player2
        else
            return player1
        end
    end

    function self:add_score(player, amount)
        if player == player1 then
            self.player1_score = self.player1_score + amount
        else
            self.player2_score = self.player2_score + amount
        end
    end

    function self:get_total_score(player)
        if player == player1 then
            return self.player1_score
        else
            return self.player2_score
        end
    end

    function self:next_turn()
        if self.is_over_move then
            if self.turn == self.player1 then
                self.turn = self.player2
            else
                self.turn = self.player1
            end
            self.take_card = false
            self.is_over_move = false

            local message = json.encode({type = "is_my_turn", answer = true})
            print("Send:", message)
            self.turn:send(message)
        end
    end

    function self:start_game()
        if self.is_new_round then
            self.player1_hand = {}
            self.player2_hand = {}
            self.discard_pile = {}

            for _ = 1, 10 do
                local card1 = deck:get_top_card()
                local card2 = deck:get_top_card()
                table.insert(self.player1_hand, card1)
                table.insert(self.player2_hand, card2)

                local message1 = json.encode({type = "get_card_from_deck", card = card1})
                local message2 = json.encode({type = "get_card_from_deck", card = card2})
                local message3 = json.encode({type = "opponent_get_card_from_deck"})
                print("Send:", message1)
                print("Send:", message2)
                print("Send:", message3)
                player1:send(message1)
                player1:send(message3)
                player2:send(message2)
                player2:send(message3)
            end
            self.is_new_round = false

            local message = json.encode({type = "is_my_turn", answer = true})
            print("Send:", message)

            local top_discard = deck:get_top_card()
            table.insert(self.discard_pile, top_discard)
            local message2 = json.encode({type = "update_discard_pile", card = top_discard})
            print("Send:", message2)

            player1:send(message2)
            player2:send(message2)
            self:current_turn():send(message)

        end
    end

    function self:get_card_from_deck(player)
        if not self.take_card and player == self:current_turn() then
            local card = deck:get_top_card()
            table.insert(self:get_hand(player), card)

            local message = json.encode({type = "get_card_from_deck", card = card})
            local message2 = json.encode({type = "opponent_get_card_from_deck"})
            print("Send:", message)
            print("Send:", message2)
            self.turn:send(message)
            if self.turn == player1 then
                player2:send(message2)
            else
                player1:send(message2)
            end
            self.take_card = true
        end
    end

    function self:get_card_from_discard_pile(player)
        if not self.take_card and player == self:current_turn() and #self.discard_pile > 0 then
            local card = table.remove(self.discard_pile)
            table.insert(self:get_hand(player), card)

            local message = json.encode({type = "opponent_get_card_from_discrad_pile"})
            print("Send:", message)
            if self.turn == player1 then
                player2:send(message)
            else
                player1:send(message)
            end
            self.take_card = true
        end
    end

    function self:put_card_to_discrad_pile(player, card_name)
        if self.take_card and player == self:current_turn() then
            local hand = self:get_hand(player)

            if remove_card_from_hand(hand, card_name) then
                table.insert(self.discard_pile, card_name)

                local message = json.encode({type = "opponent_place_card_to_discard_pile", card = card_name})
                print("Send:", message)
                if self.turn == player1 then
                    player2:send(message)
                else
                    player1:send(message)
                end

                self.is_over_move = true;
                self:next_turn()
            end
        end
    end

    function self:start_new_round()
        deck = Deck()
        self.player1_hand = {}
        self.player2_hand = {}
        self.discard_pile = {}
        self.take_card = false
        self.is_over_move = false
        self.is_new_round = true
        self.turn = (self.turn == player1) and player2 or player1

        local message = json.encode({type = "new_round"})
        print("Send:", message)
        player1:send(message)
        player2:send(message)

        self:start_game()
    end

    function self:finalize_round(knocker, opponent_player, knocker_deadwood, opponent_deadwood, is_gin, laid_off_value)
        laid_off_value = laid_off_value or 0

        local is_undercut = false
        local knocker_round_score = 0
        local opponent_round_score = 0

        if not is_gin and opponent_deadwood <= knocker_deadwood then
            is_undercut = true
            opponent_round_score = (knocker_deadwood - opponent_deadwood) + UNDERCUT_BONUS
        else
            knocker_round_score = opponent_deadwood - knocker_deadwood
            if is_gin then
                knocker_round_score = knocker_round_score + GIN_BONUS
            end
        end

        self:add_score(knocker, knocker_round_score)
        self:add_score(opponent_player, opponent_round_score)

        local knocker_message = json.encode({
            type = "round_result",
            you_knocked = true,
            is_gin = is_gin,
            is_undercut = is_undercut,
            your_deadwood = knocker_deadwood,
            opponent_deadwood = opponent_deadwood,
            laid_off_value = laid_off_value,
            your_round_score = knocker_round_score,
            opponent_round_score = opponent_round_score,
            your_total_score = self:get_total_score(knocker),
            opponent_total_score = self:get_total_score(opponent_player)
        })
        local opponent_message = json.encode({
            type = "round_result",
            you_knocked = false,
            is_gin = is_gin,
            is_undercut = is_undercut,
            your_deadwood = opponent_deadwood,
            opponent_deadwood = knocker_deadwood,
            laid_off_value = laid_off_value,
            your_round_score = opponent_round_score,
            opponent_round_score = knocker_round_score,
            your_total_score = self:get_total_score(opponent_player),
            opponent_total_score = self:get_total_score(knocker)
        })

        print("Send:", knocker_message)
        print("Send:", opponent_message)
        knocker:send(knocker_message)
        opponent_player:send(opponent_message)

        if self:get_total_score(knocker) >= WINNING_SCORE or self:get_total_score(opponent_player) >= WINNING_SCORE then
            self.is_over_game = true

            local winner = knocker
            if self:get_total_score(opponent_player) > self:get_total_score(knocker) then
                winner = opponent_player
            end
            local loser = (winner == knocker) and opponent_player or knocker

            local win_message = json.encode({type = "game_over", you_won = true})
            local lose_message = json.encode({type = "game_over", you_won = false})

            print("Send:", win_message)
            print("Send:", lose_message)
            winner:send(win_message)
            loser:send(lose_message)
        else
            self:start_new_round()
        end
    end

    function self:knock(player, discard_name, combinations)
        if self.is_over_game then return end
        if player ~= self:current_turn() then return end
        if not self.take_card then return end
        if type(discard_name) ~= "string" then return end
        if type(combinations) ~= "table" then combinations = {} end

        local hand = self:get_hand(player)
        if not hand_contains(hand, discard_name) then return end

        local opponent_player = self:get_opponent(player)
        local opponent_hand = self:get_hand(opponent_player)

        local used = {}
        used[discard_name] = true


        for _, meld in ipairs(combinations) do
            if type(meld) ~= "table" or #meld < 3 then return end

            local meld_cards = {}
            for _, card_name in ipairs(meld) do
                if type(card_name) ~= "string" or used[card_name] or not hand_contains(hand, card_name) then
                    return
                end
                used[card_name] = true
                table.insert(meld_cards, get_card_data(card_name))
            end

            if not is_valid_meld(meld_cards) then return end
        end

        local knocker_deadwood = 0
        for _, card_name in ipairs(hand) do
            if not used[card_name] then
                knocker_deadwood = knocker_deadwood + card_value_from_name(card_name)
            end
        end

        if knocker_deadwood > 10 then return end

        remove_card_from_hand(hand, discard_name)
        table.insert(self.discard_pile, discard_name)

        -- Let both clients animate the discard face-down before anything else is revealed
        local knocker_discard_message = json.encode({type = "knock_discard", card = discard_name, mine = true})
        local opponent_discard_message = json.encode({type = "knock_discard", card = discard_name, mine = false})
        print("Send:", knocker_discard_message)
        print("Send:", opponent_discard_message)
        player:send(knocker_discard_message)
        opponent_player:send(opponent_discard_message)

        local is_gin = knocker_deadwood == 0

        if is_gin then
            local opponent_cards = {}
            for _, name in ipairs(opponent_hand) do
                table.insert(opponent_cards, get_card_data(name))
            end
            local _, opponent_deadwood = best_combinations(opponent_cards)

            self:finalize_round(player, opponent_player, knocker_deadwood, opponent_deadwood, true, 0)
            return
        end

        self.pending_knock = {
            knocker = player,
            opponent = opponent_player,
            knocker_deadwood = knocker_deadwood,
            knocker_combinations = combinations
        }

        local waiting_message = json.encode({type = "waiting_for_layoff"})
        local layoff_message = json.encode({type = "layoff_phase", combinations = combinations})

        print("Send:", waiting_message)
        print("Send:", layoff_message)
        player:send(waiting_message)
        opponent_player:send(layoff_message)
    end

    function self:finish_layoff(player, layoffs)
        local pending = self.pending_knock
        if pending == nil or player ~= pending.opponent then return end
        if type(layoffs) ~= "table" then layoffs = {} end

        local opponent_hand = self:get_hand(player)

        local meld_cards_by_index = {}
        for i, meld in ipairs(pending.knocker_combinations) do
            local cards = {}
            for _, name in ipairs(meld) do
                table.insert(cards, get_card_data(name))
            end
            meld_cards_by_index[i] = cards
        end

        local laid_off_value = 0
        local used = {}

        for _, layoff in ipairs(layoffs) do
            local card_name = layoff.card
            local meld_index = layoff.meld_index

            if type(card_name) == "string" and type(meld_index) == "number" and
               not used[card_name] and hand_contains(opponent_hand, card_name) and
               meld_cards_by_index[meld_index] ~= nil then

                local card = get_card_data(card_name)
                if can_extend_meld(card, meld_cards_by_index[meld_index]) then
                    table.insert(meld_cards_by_index[meld_index], card)
                    used[card_name] = true
                    laid_off_value = laid_off_value + card_value_from_name(card_name)
                end
            end
        end

        for card_name, _ in pairs(used) do
            remove_card_from_hand(opponent_hand, card_name)
        end


        local remaining_cards = {}
        for _, name in ipairs(opponent_hand) do
            table.insert(remaining_cards, get_card_data(name))
        end
        local _, final_opponent_deadwood = best_combinations(remaining_cards)

        self.pending_knock = nil

        self:finalize_round(pending.knocker, pending.opponent, pending.knocker_deadwood, final_opponent_deadwood, false, laid_off_value)
    end

    return self
end

return Game
