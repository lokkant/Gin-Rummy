-- Rules engine of one two-player Gin Rummy match. Server side only: players are ENet peers (anything with
-- :send(string)) and the engine pushes the resulting messages to them (protocol: top of server.lua). Global
-- constructor-style class: `require 'game'` defines Game(player1, player2, deck); server.lua owns it.
-- Rules: 10 cards each; a turn is a draw (stock or discard pile) followed by a discard or a knock. Knock
-- needs at most 10 deadwood after the discard; gin = 0 deadwood. Undercut = the defender has no more
-- deadwood than the knocker. First to WINNING_SCORE wins. Big gin (all 11 cards melded) is treated as plain
-- gin.

local json = require "dkjson"
local config = require "config"

require 'server_deck'
require 'best_melds'
require 'cards_database'

-- Bonus for knocking with gin (deadwood 0).
local GIN_BONUS = 25
-- Bonus for the defender who undercuts the knocker.
local UNDERCUT_BONUS = 25
-- The match ends when a player's total score reaches this.
local WINNING_SCORE = 100

-- Removes the first occurrence of `card_name` from the array `hand`; returns true if it was there.
local function remove_card_from_hand(hand, card_name)
    for i, name in ipairs(hand) do
        if name == card_name then
            table.remove(hand, i)
            return true
        end
    end
    return false
end

-- Returns true if `card_name` is in the array `hand`.
local function hand_contains(hand, card_name)
    for _, name in ipairs(hand) do
        if name == card_name then
            return true
        end
    end
    return false
end

-- Deadwood value (A = 1, 2-10 face value, J/Q/K = 10) of a card name; the rank is the part before "_".
local function card_value_from_name(name)
    local rank = string.match(name, "^([%w]+)_")
    return get_card_value({rank = rank})
end

-- The factor all turn timer limits are multiplied by in round number `round_number` (1 = the first of a
-- match): 1 at first, then config.timer_shrink_factor once more after every config.timer_shrink_every
-- rounds, but not below config.timer_shrink_min_factor. Both players get the same limits.
local function get_time_factor(round_number)
    if not (config.horror_enabled and config.timer_shrink_enabled) or config.timer_shrink_every <= 0 then
        return 1
    end

    local steps = math.floor((round_number - 1) / config.timer_shrink_every)
    return math.max(config.timer_shrink_min_factor, config.timer_shrink_factor ^ steps)
end

-- Creates the match state for two peers. `deck` is a ServerDeck for the first round (later rounds replace
-- it). Returns the game object; call start_game() to deal the first round.
function Game(player1, player2, deck)
    local self = {}
    -- Match state: hands are arrays of card names, scores are match totals.
    --   turn                the peer who acts now
    --   take_card           this turn's draw already happened
    --   is_over_move        the discard is done, so next_turn() may pass the turn
    --   is_new_round        a deal is pending (see start_game)
    --   pending_knock       during layoff: {knocker, opponent, knocker_deadwood, knocker_combinations,
    --                       meld_cards (the knocker's melds as card objects, grown by every layoff),
    --                       laid_off_cards (names, in order), laid_off_value (points)}
    --   taken_from_discard  the card picked up from the discard pile this turn; it can't be discarded again
    --                       (otherwise taking it would be a free pass)
    --   round_number        1 for the first round of the match, then counts up
    --   time_factor         the turn timer limits of this round are multiplied by it (see get_time_factor);
    --                       the clients get it with new_game / new_round
    --   idle_time           seconds the player to move has gone without a game step (see update)
    --   turn_acknowledged   the client confirmed it showed this turn (turn_started); idle_time only counts
    --                       from then, or after config.turn_ack_wait seconds without an answer
    --   ack_wait            seconds spent waiting for that confirmation
    self.player1 = player1
    self.player2 = player2
    self.player1_score = 0
    self.player2_score = 0
    self.player1_hand = {}
    self.player2_hand = {}
    self.discard_pile = {}
    self.turn = player1
    self.take_card = false
    self.is_over_move = false
    self.is_over_game = false
    self.is_new_round = true
    self.pending_knock = nil
    self.taken_from_discard = nil
    self.round_number = 1
    self.time_factor = get_time_factor(1)
    self.idle_time = 0
    self.turn_acknowledged = false
    self.ack_wait = 0
    -- Phase state machine; every action checks it, so out-of-order messages are ignored:
    --   "draw"       the current player must take a card from the stock or the discard pile -> "discard"
    --   "discard"    must discard (-> opponent's "draw", or a draw round if the stock is almost empty)
    --                or knock (gin: scored at once; otherwise -> "layoff")
    --   "layoff"     the opponent lays cards onto the knocker's melds (layoff_card) until finish_layoff;
    --                the round is then scored -> next round "draw"
    --   "round_over" transient: finalize_draw sets it just before start_new_round resets the phase to "draw"
    --   "over"       someone reached WINNING_SCORE; the Game is dead until a rematch creates a new one
    self.phase = "draw"

    -- Returns the peer whose turn it is.
    function self:current_turn()
        return self.turn
    end

    -- Returns the hand (array of card names) of `player`.
    function self:get_hand(player)
        if player == player1 then
            return self.player1_hand
        else
            return self.player2_hand
        end
    end

    -- Returns the other peer.
    function self:get_opponent(player)
        if player == player1 then
            return player2
        else
            return player1
        end
    end

    -- Adds `amount` to the match total of `player`.
    function self:add_score(player, amount)
        if player == player1 then
            self.player1_score = self.player1_score + amount
        else
            self.player2_score = self.player2_score + amount
        end
    end

    -- Returns the match total of `player`.
    function self:get_total_score(player)
        if player == player1 then
            return self.player1_score
        else
            return self.player2_score
        end
    end

    -- The turn timer limits in seconds from the last game step (config.lua): the eye gets red from
    -- fade_start to fade_full, the glass cracks at crack, and at timeout the round is lost. Each moment is
    -- counted from the one before it (config.lua), so they can never get out of step.
    local function get_idle_limits()
        local fade_full = config.idle_warning_start + config.idle_warning_full_delay
        local crack = fade_full + config.idle_crack_delay

        -- Later rounds shorten every limit by the same factor.
        local factor = self.time_factor

        return {
            fade_start = config.idle_warning_start * factor,
            fade_full = fade_full * factor,
            crack = crack * factor,
            timeout = (crack + config.idle_loss_delay) * factor
        }
    end

    -- The "is_my_turn" JSON. It carries the turn timer limits so that the client can show the player how
    -- long they have been taking.
    local function build_turn_message()
        return json.encode({
            type = "is_my_turn",
            answer = true,
            limits = get_idle_limits()
        })
    end

    -- Passes the turn to the other player once the current move is finished (is_over_move) and tells them
    -- "is_my_turn". Does nothing before that, so it is safe to call after every discard.
    function self:next_turn()
        if self.is_over_move then
            if self.turn == self.player1 then
                self.turn = self.player2
            else
                self.turn = self.player1
            end
            self.take_card = false
            self.is_over_move = false
            self.taken_from_discard = nil
            self.idle_time = 0
            self.turn_acknowledged = false
            self.ack_wait = 0
            self.phase = "draw"

            local message = build_turn_message()
            print("Send:", message)
            self.turn:send(message)
        end
    end

    -- Deals the pending round: 10 cards to each player, one face-up card on the discard pile, then
    -- "is_my_turn" to the player who starts. Does nothing when no round is pending (is_new_round false).
    function self:start_game()
        if self.is_new_round then
            self.player1_hand = {}
            self.player2_hand = {}
            self.discard_pile = {}

            -- Cards go out one by one so the clients can animate each of them.
            for _ = 1, 10 do
                local card1 = deck:get_top_card()
                local card2 = deck:get_top_card()
                table.insert(self.player1_hand, card1)
                table.insert(self.player2_hand, card2)

                -- Each player gets their own card by name; the opponent's card is announced without its
                -- identity.
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
            self.phase = "draw"

            -- Sent last (after the upcard), so the starting player already has the whole table when the
            -- turn begins.
            self.idle_time = 0
            self.turn_acknowledged = false
            self.ack_wait = 0
            local message = build_turn_message()
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

    -- Draw phase: the current player takes the top stock card. The drawer gets its name, the opponent only
    -- a hidden-card notice. Ignored in the wrong phase/turn, after the draw was made or when the stock is
    -- empty.
    function self:get_card_from_deck(player)
        if self.phase == "draw" and not self.take_card and player == self:current_turn() and #deck.cards > 0 then
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
            self.idle_time = 0
            self.phase = "discard"
        end
    end

    -- Draw phase: the current player takes the top discard card. It is public, so only the opponent is
    -- told. The card is remembered in taken_from_discard (it can't be thrown back this turn).
    function self:get_card_from_discard_pile(player)
        if self.phase == "draw" and not self.take_card and player == self:current_turn() and #self.discard_pile > 0 then
            local card = table.remove(self.discard_pile)
            table.insert(self:get_hand(player), card)
            self.taken_from_discard = card

            local message = json.encode({type = "opponent_get_card_from_discard_pile"})
            print("Send:", message)
            if self.turn == player1 then
                player2:send(message)
            else
                player1:send(message)
            end
            self.take_card = true
            self.idle_time = 0
            self.phase = "discard"
        end
    end

    -- Discard phase: moves `card_name` from the current player's hand to the discard pile and ends the
    -- turn. Rejected if the card is the one just taken from the discard pile or is not in the hand.
    function self:put_card_to_discard_pile(player, card_name)
        if self.phase == "discard" and self.take_card and player == self:current_turn() then
            local hand = self:get_hand(player)

            if card_name ~= self.taken_from_discard and remove_card_from_hand(hand, card_name) then
                table.insert(self.discard_pile, card_name)

                local message = json.encode({type = "opponent_place_card_to_discard_pile", card = card_name})
                print("Send:", message)
                if self.turn == player1 then
                    player2:send(message)
                else
                    player1:send(message)
                end

                -- Standard rule: when the stock is down to two cards and nobody knocked, the round is a
                -- draw (no score).
                if #deck.cards <= 2 then
                    self:finalize_draw()
                    return
                end

                -- Marks the move as finished so that next_turn() really passes the turn.
                self.is_over_move = true
                self:next_turn()
            end
        end
    end

    -- The client of `player` reports that it has just shown them their turn (the "is_my_turn" message may
    -- wait in its queue behind the result banner or the deal), so the turn timer starts now. Only valid
    -- once per turn, from the player to move.
    function self:turn_started(player)
        if self.phase ~= "draw" or player ~= self.turn or self.turn_acknowledged then return end

        self.turn_acknowledged = true
        self.idle_time = 0
    end

    -- Per frame (dt in seconds): while a player has to draw or discard, counts the time since their last game
    -- step (the start of the turn once the client confirmed it, taking a card). When it reaches
    -- the timeout limit (get_idle_limits) the player has delayed too long and loses the round
    -- (finalize_timeout). Other phases have no timer.
    function self:update(dt)
        if self.phase ~= "draw" and self.phase ~= "discard" then return end

        -- Until the client confirms the turn nothing is counted; a client that never does is not allowed to
        -- stop the game for longer than config.turn_ack_wait.
        if not self.turn_acknowledged then
            self.ack_wait = self.ack_wait + dt
            if self.ack_wait < config.turn_ack_wait then return end

            self.turn_acknowledged = true
            self.idle_time = 0
        end

        self.idle_time = self.idle_time + dt

        if self.idle_time >= get_idle_limits().timeout then
            self:finalize_timeout(self.turn)
        end
    end

    -- Prepares the next round: new shuffled deck (this rebinds the `deck` argument of Game), empty hands,
    -- phase "draw", the starting player alternates, "new_round" to both, then the deal.
    function self:start_new_round()
        deck = ServerDeck()
        self.player1_hand = {}
        self.player2_hand = {}
        self.discard_pile = {}
        self.take_card = false
        self.is_over_move = false
        self.is_new_round = true
        self.pending_knock = nil
        self.taken_from_discard = nil
        self.phase = "draw"
        self.turn = (self.turn == player1) and player2 or player1
        self.round_number = self.round_number + 1
        self.time_factor = get_time_factor(self.round_number)

        local message = json.encode({type = "new_round", time_factor = self.time_factor, horror = config.horror_enabled})
        print("Send:", message)
        player1:send(message)
        player2:send(message)

        self:start_game()
    end

    -- What `player` gets to see of the opponent's hand when a round ends: opponent_cards (all card names:
    -- the melds first, then the deadwood, every group in ascending order) and opponent_melds (the melds as
    -- lists of names, taken from the best melding of that hand). The clients turn the cards face up.
    function self:reveal_fields(player)
        local hand_cards = self:hand_cards_data(self:get_opponent(player))
        local best = best_combinations(hand_cards)[1]

        -- Orders cards by rank, then suit.
        local function ascending(a, b)
            return a:is_lesser_than(b)
        end

        local cards = {}
        local melds = {}
        local in_meld = {}

        for _, meld in ipairs(best) do
            table.sort(meld, ascending)

            local names = {}
            for _, card in ipairs(meld) do
                local name = card.rank .. "_" .. card.suit
                in_meld[name] = true
                table.insert(names, name)
                table.insert(cards, name)
            end
            table.insert(melds, names)
        end

        local deadwood = {}
        for _, card in ipairs(hand_cards) do
            if not in_meld[card.rank .. "_" .. card.suit] then
                table.insert(deadwood, card)
            end
        end
        table.sort(deadwood, ascending)

        for _, card in ipairs(deadwood) do
            table.insert(cards, card.rank .. "_" .. card.suit)
        end

        return {opponent_cards = cards, opponent_melds = melds}
    end

    -- Ends the round as a draw: nobody scores. Both players get a round_result with is_draw = true (their
    -- deadwood is shown for information only) and the opponent's cards face up, then the next round starts
    -- at once.
    function self:finalize_draw()
        self.phase = "round_over"

        -- Builds the round_result JSON as seen by `player` (best_combinations returns melds, deadwood).
        local function build_message(player)
            local opponent_player = self:get_opponent(player)
            local _, own_deadwood = best_combinations(self:hand_cards_data(player))
            local _, opponent_deadwood = best_combinations(self:hand_cards_data(opponent_player))

            local reveal = self:reveal_fields(player)

            return json.encode({
                type = "round_result",
                you_knocked = false,
                is_gin = false,
                is_undercut = false,
                is_draw = true,
                your_deadwood = own_deadwood,
                opponent_deadwood = opponent_deadwood,
                laid_off_value = 0,
                laid_off_cards = {},
                opponent_cards = reveal.opponent_cards,
                opponent_melds = reveal.opponent_melds,
                your_round_score = 0,
                opponent_round_score = 0,
                your_total_score = self:get_total_score(player),
                opponent_total_score = self:get_total_score(opponent_player)
            })
        end

        -- The clients queue these messages: they show the result first, then the "new_round" that follows.
        local message1 = build_message(player1)
        local message2 = build_message(player2)
        print("Send:", message1)
        print("Send:", message2)
        player1:send(message1)
        player2:send(message2)

        self:start_new_round()
    end

    -- The round is lost by waiting: `slow_player` took too long, the opponent gets config.timeout_penalty
    -- points. Both get a round_result with is_timeout = true (you_timed_out tells who was slow) and the
    -- opponent's cards face up; then the match goes on or ends like after any other round.
    function self:finalize_timeout(slow_player)
        self.phase = "round_over"

        local winner = self:get_opponent(slow_player)
        self:add_score(winner, config.timeout_penalty)

        -- The round_result JSON as seen by `player`.
        local function build_message(player)
            local opponent_player = self:get_opponent(player)
            local _, own_deadwood = best_combinations(self:hand_cards_data(player))
            local _, opponent_deadwood = best_combinations(self:hand_cards_data(opponent_player))
            local reveal = self:reveal_fields(player)
            local own_score = (player == winner) and config.timeout_penalty or 0
            local opponent_score = (player == winner) and 0 or config.timeout_penalty

            return json.encode({
                type = "round_result",
                you_knocked = false,
                is_gin = false,
                is_undercut = false,
                is_timeout = true,
                you_timed_out = (player == slow_player),
                your_deadwood = own_deadwood,
                opponent_deadwood = opponent_deadwood,
                laid_off_value = 0,
                laid_off_cards = {},
                opponent_cards = reveal.opponent_cards,
                opponent_melds = reveal.opponent_melds,
                your_round_score = own_score,
                opponent_round_score = opponent_score,
                your_total_score = self:get_total_score(player),
                opponent_total_score = self:get_total_score(opponent_player)
            })
        end

        local message1 = build_message(player1)
        local message2 = build_message(player2)
        print("Send:", message1)
        print("Send:", message2)
        player1:send(message1)
        player2:send(message2)

        self:conclude_round(winner, slow_player)
    end

    -- Converts a player's hand (card names) into texture-less Card objects, the format best_melds.lua works
    -- on.
    function self:hand_cards_data(player)
        local cards = {}
        for _, name in ipairs(self:get_hand(player)) do
            table.insert(cards, get_card_data(name))
        end
        return cards
    end

    -- After the scores of a round are in: the match ends as soon as someone reaches WINNING_SCORE (the
    -- higher total wins, `first` on a tie), otherwise the next round starts.
    function self:conclude_round(first, second)
        if self:get_total_score(first) >= WINNING_SCORE or self:get_total_score(second) >= WINNING_SCORE then
            self.is_over_game = true
            self.phase = "over"

            local winner = first
            if self:get_total_score(second) > self:get_total_score(first) then
                winner = second
            end
            local loser = (winner == first) and second or first

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

    -- Scores a knock and notifies both players, then ends the match or starts the next round.
    -- knocker_deadwood / opponent_deadwood are final (the opponent's already reduced by layoffs); is_gin:
    -- the knocker had 0 deadwood; laid_off_value / laid_off_cards: points and names of the cards laid off
    -- (shown to the players only, the clients also drop those cards from the defender's hand). The hands
    -- are revealed in the message: the cards of the opponent, face up, with their melds.
    function self:finalize_round(knocker, opponent_player, knocker_deadwood, opponent_deadwood, is_gin,
                                 laid_off_value, laid_off_cards)
        laid_off_value = laid_off_value or 0
        laid_off_cards = laid_off_cards or {}

        local is_undercut = false
        local knocker_round_score = 0
        local opponent_round_score = 0

        -- Undercut: the defender has no more deadwood than the knocker. The defender scores the difference
        -- plus UNDERCUT_BONUS and the knocker nothing. A gin is never undercut (it is scored before any
        -- layoff). Otherwise the knocker scores the deadwood difference, plus GIN_BONUS for a gin.
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

        -- The same numbers for both players, each from their own point of view (your_* / opponent_*).
        local knocker_reveal = self:reveal_fields(knocker)
        local opponent_reveal = self:reveal_fields(opponent_player)

        local knocker_message = json.encode({
            type = "round_result",
            you_knocked = true,
            is_gin = is_gin,
            is_undercut = is_undercut,
            your_deadwood = knocker_deadwood,
            opponent_deadwood = opponent_deadwood,
            laid_off_value = laid_off_value,
            laid_off_cards = laid_off_cards,
            opponent_cards = knocker_reveal.opponent_cards,
            opponent_melds = knocker_reveal.opponent_melds,
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
            laid_off_cards = laid_off_cards,
            opponent_cards = opponent_reveal.opponent_cards,
            opponent_melds = opponent_reveal.opponent_melds,
            your_round_score = opponent_round_score,
            opponent_round_score = knocker_round_score,
            your_total_score = self:get_total_score(opponent_player),
            opponent_total_score = self:get_total_score(knocker)
        })

        print("Send:", knocker_message)
        print("Send:", opponent_message)
        knocker:send(knocker_message)
        opponent_player:send(opponent_message)

        self:conclude_round(knocker, opponent_player)
    end

    -- Knock request: `player` throws away `discard_name` and claims the melds in `combinations` (list of
    -- lists of card names). Everything is checked against the real hand and an invalid request is silently
    -- ignored. Deadwood = cards that are neither in a meld nor the discard; it must be <= 10. Deadwood 0 is
    -- gin: no layoff, the round is scored at once. Otherwise phase "layoff": both players get
    -- "layoff_phase" (the knocker's melds and deadwood and the opponent's hand, all face up because the
    -- round is decided) and the opponent lays cards off with layoff_card.
    function self:knock(player, discard_name, combinations)
        if self.phase ~= "discard" or self.is_over_game then return end
        if player ~= self:current_turn() then return end
        if not self.take_card then return end
        -- The card just taken from the discard pile can't be discarded, not even by knocking.
        if type(discard_name) ~= "string" or discard_name == self.taken_from_discard then return end
        if type(combinations) ~= "table" then combinations = {} end

        local hand = self:get_hand(player)
        if not hand_contains(hand, discard_name) then return end

        local opponent_player = self:get_opponent(player)
        local opponent_hand = self:get_hand(opponent_player)

        -- used[name] marks cards that are already spoken for (the discard or a meld), so no card counts
        -- twice.
        local used = {}
        used[discard_name] = true


        for _, meld in ipairs(combinations) do
            -- A meld needs at least three cards.
            if type(meld) ~= "table" or #meld < 3 then return end

            local meld_cards = {}
            for _, card_name in ipairs(meld) do
                -- Every card must exist in the knocker's hand and appear only once overall.
                if type(card_name) ~= "string" or used[card_name] or not hand_contains(hand, card_name) then
                    return
                end
                used[card_name] = true
                table.insert(meld_cards, get_card_data(card_name))
            end

            -- A valid meld is a set (3-4 cards of one rank) or a run (3+ consecutive cards of one suit).
            if not is_valid_meld(meld_cards) then return end
        end

        -- Whatever is not melded and not discarded is deadwood.
        local knocker_deadwood = 0
        for _, card_name in ipairs(hand) do
            if not used[card_name] then
                knocker_deadwood = knocker_deadwood + card_value_from_name(card_name)
            end
        end

        -- A knock needs at most 10 points of deadwood.
        if knocker_deadwood > 10 then return end

        remove_card_from_hand(hand, discard_name)
        table.insert(self.discard_pile, discard_name)

        -- knock_discard goes out before any result, so both clients can play the face-down discard
        -- animation first (their message queue handles the later layoff_phase / round_result only after it
        -- finishes).
        local knocker_discard_message = json.encode({type = "knock_discard", card = discard_name, mine = true})
        local opponent_discard_message = json.encode({type = "knock_discard", card = discard_name, mine = false})
        print("Send:", knocker_discard_message)
        print("Send:", opponent_discard_message)
        player:send(knocker_discard_message)
        opponent_player:send(opponent_discard_message)

        local is_gin = knocker_deadwood == 0

        -- Gin: no layoff is allowed; the opponent's deadwood is the best melding of their whole hand.
        if is_gin then
            local opponent_cards = {}
            for _, name in ipairs(opponent_hand) do
                table.insert(opponent_cards, get_card_data(name))
            end
            local _, opponent_deadwood = best_combinations(opponent_cards)

            self:finalize_round(player, opponent_player, knocker_deadwood, opponent_deadwood, true, 0)
            return
        end

        -- Working copies of the knocker's melds as card objects; every accepted layoff extends one of
        -- them, so a later card can attach to the extended meld (e.g. to both ends of a run).
        local meld_cards = {}
        for i, meld in ipairs(combinations) do
            meld_cards[i] = {}
            for _, name in ipairs(meld) do
                table.insert(meld_cards[i], get_card_data(name))
            end
        end

        self.phase = "layoff"
        self.pending_knock = {
            knocker = player,
            opponent = opponent_player,
            knocker_deadwood = knocker_deadwood,
            knocker_combinations = combinations,
            meld_cards = meld_cards,
            laid_off_cards = {},
            laid_off_value = 0
        }

        -- Everything the layoff screen needs: the melds, the knocker's leftover cards and the
        -- opponent's hand. Each player also learns which role they have.
        local deadwood_names = {}
        for _, card_name in ipairs(hand) do
            if not used[card_name] then
                table.insert(deadwood_names, card_name)
            end
        end

        -- The layoff_phase JSON for one of the two roles; the payload is the same for both.
        local function build_layoff_message(role)
            return json.encode({
                type = "layoff_phase",
                role = role,
                combinations = combinations,
                knocker_deadwood = deadwood_names,
                defender_hand = opponent_hand
            })
        end

        local knocker_message = build_layoff_message("knocker")
        local defender_message = build_layoff_message("defender")
        print("Send:", knocker_message)
        print("Send:", defender_message)
        player:send(knocker_message)
        opponent_player:send(defender_message)
    end

    -- Layoff phase: the knocker's opponent attaches `card_name` to the meld_index-th knocker meld (1-based
    -- position in the knock's combinations). Accepted only if the card is in their hand and extends that
    -- meld, as it is now, into a valid set/run; the knocker is told ("opponent_layoff") so their screen can
    -- animate it. Invalid requests are ignored.
    function self:layoff_card(player, card_name, meld_index)
        local pending = self.pending_knock
        if self.phase ~= "layoff" or pending == nil or player ~= pending.opponent then return end
        if type(card_name) ~= "string" or type(meld_index) ~= "number" then return end

        local hand = self:get_hand(player)
        local meld = pending.meld_cards[meld_index]
        if meld == nil or not hand_contains(hand, card_name) then return end

        local card = get_card_data(card_name)
        if not can_extend_meld(card, meld) then return end

        table.insert(meld, card)
        remove_card_from_hand(hand, card_name)
        table.insert(pending.laid_off_cards, card_name)
        pending.laid_off_value = pending.laid_off_value + card_value_from_name(card_name)

        local message = json.encode({type = "opponent_layoff", card = card_name, meld_index = meld_index})
        print("Send:", message)
        pending.knocker:send(message)
    end

    -- Layoff phase: the knocker's opponent is done. The cards they kept are melded again to get their final
    -- deadwood and the round is scored. Only accepted from the opponent during the "layoff" phase.
    function self:finish_layoff(player)
        local pending = self.pending_knock
        if self.phase ~= "layoff" or pending == nil or player ~= pending.opponent then return end

        local _, final_opponent_deadwood = best_combinations(self:hand_cards_data(player))

        self.pending_knock = nil

        self:finalize_round(pending.knocker, pending.opponent, pending.knocker_deadwood, final_opponent_deadwood,
                            false, pending.laid_off_value, pending.laid_off_cards)
    end

    return self
end

return Game
