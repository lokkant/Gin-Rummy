local love = require "love"
local network = require "network"
local layout = require "client/layout"

local messages = {}

local KNOCK_PAUSE_DURATION = 2
local ROUND_RESULT_DURATION = 6
local LEAVE_DELAY = 3

local function copy(original)
    local copy_t = {}
    for key, value in pairs(original) do
        copy_t[key] = value
    end
    return copy_t
end

local function add_opponent_card(state, x, y)
    local card = copy(state.opponent_card_reference)
    card.wobble_seed = love.math.random() * 2 * math.pi
    card:set_position(x, y)
    state.opponent_hand:add_card(card)
end

-- A face-down card flies from where it was to the discard pile; `options.on_finish` runs when it lands
local function fly_to_discard_pile(state, flying_card, options)
    state.animations:move_card(flying_card, function()
        return state.discard_pile:get_position()
    end, layout.CARD_SPEED, options)
end

-- Cleans the table for the next round (or game)
local function reset_table(state)
    state.dragging_card = nil
    state.taken_from_discard = nil
    state.draw_requested = false
    state.player_hand:reset()
    state.opponent_hand:reset()
    state.discard_pile:reset()
    state.is_my_turn = false
    state.animations:cancel("round_result")
    state.round_result = nil
    state.waiting_for_layoff = false
end

local function start_leaving(state)
    state.animations:delay(LEAVE_DELAY, {tag = "leave", on_finish = state.leave_to_menu})
end

-- The knocking card flies face-down to the pile, then comes a suspense pause before the result
local function handle_knock_discard(state, message)
    local flying_card

    if message.mine then
        flying_card = copy(state.opponent_card_reference)

        local rank, suit = string.match(message.card, "^([%w]+)_([%a]+)$")
        for _, card in ipairs(state.player_hand.cards) do
            if card.rank == rank and card.suit == suit then
                flying_card:set_position(card:get_position())
                break
            end
        end
        state.player_hand:remove_card(rank, suit)
    else
        flying_card = state.opponent_hand:remove_random_card() or copy(state.opponent_card_reference)
    end

    fly_to_discard_pile(state, flying_card, {
        blocking = true,
        on_finish = function()
            state.discard_pile:add_card(flying_card)
            state.animations:delay(KNOCK_PAUSE_DURATION, {blocking = true})
        end
    })
end

local handlers = {}

function handlers.is_my_turn(state, message)
    state.taken_from_discard = nil
    state.draw_requested = false
    state.is_my_turn = message.answer
end

function handlers.update_discard_pile(state, message)
    state.discard_pile:add_card(get_card(message.card))
end

function handlers.opponent_get_card_from_deck(state)
    add_opponent_card(state, state.deck:get_position())
end

function handlers.opponent_place_card_to_discard_pile(state, message)
    local flying_card = state.opponent_hand:remove_random_card() or copy(state.opponent_card_reference)
    local placed_card = get_card(message.card)

    fly_to_discard_pile(state, flying_card, {
        tag = "discard_pile",
        on_finish = function()
            state.discard_pile:add_card(placed_card)
        end
    })
end

function handlers.opponent_get_card_from_discard_pile(state)
    state.discard_pile:remove_top_card()
    add_opponent_card(state, state.discard_pile:get_position())
end

function handlers.get_card_from_deck(state, message)
    local card = get_card(message.card)
    card:set_position(state.deck:get_position())
    card:set_scale(layout.card_scale(), layout.card_scale())
    state.draw_requested = false
    state.player_hand:add_card(card)
end

handlers.knock_discard = handle_knock_discard

function handlers.new_round(state)
    reset_table(state)
end

function handlers.waiting_for_layoff(state)
    state.waiting_for_layoff = true
    state.is_my_turn = false
end

function handlers.layoff_phase(state, message)
    state.dragging_card = nil
    SceneManager.switch("layoff", message.combinations, state.player_hand.cards)
end

function handlers.round_result(state, message)
    state.round_result = message
    state.animations:cancel("round_result")
    state.animations:delay(ROUND_RESULT_DURATION, {
        tag = "round_result",
        blocking = true,
        on_finish = function()
            state.round_result = nil
        end
    })
    state.my_total_score = message.your_total_score
    state.opponent_total_score = message.opponent_total_score
    state.is_my_turn = false
    state.waiting_for_layoff = false
end

function handlers.game_over(state, message)
    state.game_over_info = message
    state.is_game_over = true
    state.is_paused = false
    state.is_my_turn = false
    state.dragging_card = nil
    state.waiting_for_layoff = false
    state.rematch_response_sent = false
    state.opponent_left = false

    if message.opponent_disconnected then
        start_leaving(state)
    end
end

function handlers.opponent_declined_rematch(state)
    state.opponent_left = true
    start_leaving(state)
end

function handlers.new_game(state)
    reset_table(state)
    state.is_paused = false
    state.is_game_over = false
    state.game_over_info = nil
    state.animations:cancel("leave")
    state.my_total_score = 0
    state.opponent_total_score = 0
    state.rematch_response_sent = false
    state.opponent_left = false
end

local function handle(state, message)
    local handler = handlers[message.type]
    if handler then
        handler(state, message)
    end
end

-- Moves everything the server sent since the last frame into the queue
function messages.receive(state)
    network.poll()

    local message = network.pop()
    while message do
        table.insert(state.pending_messages, message)
        message = network.pop()
    end
end

function messages.process_next(state)
    if state.animations:is_busy() or #state.pending_messages == 0 then return end

    local message = table.remove(state.pending_messages, 1)

    if message.type == "new_game" and not state.has_started_first_game then
        -- the transition into this scene has just played, a second one would be redundant
        state.has_started_first_game = true
        handle(state, message)
    elseif message.type == "new_round" or message.type == "new_game" then
        state.animations:wait_for(function(done)
            SceneManager.flash(function()
                handle(state, message)
                done()
            end)
        end, {blocking = true})
    else
        handle(state, message)
    end
end

return messages
