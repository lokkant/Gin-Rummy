-- Client side handling of server messages (the protocol table is at the top of server.lua). receive() only
-- moves packets from the network into state.pending_messages; process_next() then handles ONE message per
-- frame, and only while no blocking animation runs. This queue keeps the visuals in order: the server sends
-- bursts (e.g. knock_discard, round_result, new_round, the deal), but the player must see the card fly, the
-- pause, the result banner and the table reset one after another, not all at once. handlers[type](state,
-- message) apply a message to the state table of scenes/game_client.lua.

require 'cards_database'

local love = require "love"
local network = require "network"
local config = require "config"
local layout = require "client/layout"
local sounds = require "client/sounds"
local horror = require "client/horror"

local messages = {}

-- Seconds of suspense after the knocking card has landed, before the layoff / result messages are shown.
local KNOCK_PAUSE_DURATION = 2
-- Seconds the round result banner stays on screen; it blocks the queue, so the next deal waits for it.
local ROUND_RESULT_DURATION = 6
-- Seconds the end screen stays before returning to the menu after the opponent left.
local LEAVE_DELAY = 3

-- Shallow copy of a table's fields; used to clone the reference card back.
local function copy(original)
    local copy_t = {}
    for key, value in pairs(original) do
        copy_t[key] = value
    end
    return copy_t
end

-- Names of all 52 cards; hidden opponent cards borrow a random one (see add_opponent_card).
local card_names = get_card_names()

-- Adds a face-down card to the opponent's hand. It is a clone of the reference card back, starting at
-- (x, y) (the stock or the discard pile) and sliding to its slot. The clone shares the reference's
-- wobble_seed, so a new one is drawn, otherwise all opponent cards would sway in sync. It also gets a
-- random rank and suit (the real card is unknown and never shown): OpponentHand sorts its cards, so with
-- identical values every new card would land at the same end of the fan, while random ones slide into a
-- random place between the others, like cards that are really being sorted in a hand. A silent card (used
-- when the view is repaired) makes no sound and does not count as a move of the opponent.
local function add_opponent_card(state, x, y, silent)
    local card = copy(state.opponent_card_reference)
    card.wobble_seed = love.math.random() * 2 * math.pi
    card.rank, card.suit = string.match(card_names[love.math.random(#card_names)], "([%w]+)_([%a]+)")
    card:set_position(x, y)
    state.opponent_hand:add_card(card)

    if not silent then
        sounds.play_card(config.opponent_card_volume, true)
        state.opponent_idle = 0
    end
end

-- Flies a face-down card to the discard pile; options (tag, blocking, on_finish) go to Animations:move_card
-- and on_finish runs when it lands. The pile position is asked again every frame, so the card still lands
-- correctly after a window resize.
local function fly_to_discard_pile(state, flying_card, options)
    state.animations:move_card(flying_card, function()
        return state.discard_pile:get_position()
    end, layout.CARD_SPEED, options)
end

-- Returns the name ("7_heart") of a card object.
local function name_of(card)
    return card.rank .. "_" .. card.suit
end

-- True when our hand holds exactly the cards of the list of names `names`.
local function is_hand_equal(state, names)
    local cards = state.player_hand.cards
    if #cards ~= #names then return false end

    local wanted = {}
    for _, name in ipairs(names) do wanted[name] = true end

    for _, card in ipairs(cards) do
        if not wanted[name_of(card)] then return false end
    end

    return true
end

-- Puts our hand right: it holds exactly the cards of `names` afterwards. Cards that are in the hand already
-- stay the same objects (so they do not jump), missing ones appear at the stock, extra ones disappear. Drops
-- a held or lifted card, and the chosen meld arrangement starts over.
local function repair_hand(state, names)
    local wanted = {}
    for _, name in ipairs(names) do wanted[name] = true end

    local kept = {}
    for _, card in ipairs(state.player_hand.cards) do
        local name = name_of(card)
        if wanted[name] and kept[name] == nil then kept[name] = card end
    end

    state.dragging_card = nil
    state.hovered_card = nil
    state.player_hand:reset()

    for _, name in ipairs(names) do
        local card = kept[name]

        if card == nil then
            card = get_card(name)
            card:set_position(state.deck:get_position())
            card:set_scale(layout.card_scale(), layout.card_scale())
        end

        state.player_hand:add_card(card)
    end
end

-- Gives the opponent's hand `count` face-down cards: cards are added at the stock or removed at random.
local function repair_opponent_hand(state, count)
    while #state.opponent_hand.cards > count do
        state.opponent_hand:remove_random_card()
    end

    while #state.opponent_hand.cards < count do
        add_opponent_card(state, state.deck.x, state.deck.y, true)
    end
end

-- Shows the discard pile of the list of names `names` (bottom first): only the top two cards are displayed.
-- Does nothing when the top two are shown already.
local function repair_pile(state, names)
    local count = #names
    local top, second = state.discard_pile.highest_card, state.discard_pile.second_highest_card

    local top_ok = (count == 0 and top == nil) or (top ~= nil and name_of(top) == names[count])
    local second_ok = (count < 2 and second == nil) or (second ~= nil and name_of(second) == names[count - 1])
    if top_ok and second_ok then return end

    state.discard_pile:reset()
    if count >= 2 then state.discard_pile:add_card(get_card(names[count - 1])) end
    if count >= 1 then state.discard_pile:add_card(get_card(names[count])) end
end

-- Cleans the table for the next round (or game): hands, pile and flags, and a pending result banner.
-- `message` is the new_round / new_game message; its `time_factor` says how much shorter the turn timer
-- limits are in this round, and the limits of the last round no longer apply.
local function reset_table(state, message)
    state.time_factor = message.time_factor or 1
    horror.set_match_enabled(message.horror)
    state.turn_limits = nil
    state.dragging_card = nil
    state.taken_from_discard = nil
    state.draw_requested = false
    state.player_hand:reset()
    state.opponent_hand:reset()
    state.discard_pile:reset()
    state.is_my_turn = false
    state.animations:cancel("round_result")
    state.round_result = nil
end

-- Goes back to the menu after LEAVE_DELAY seconds, so the player can read why. The animation is tagged
-- "leave" so that a new_game can cancel it.
local function start_leaving(state)
    state.animations:delay(LEAVE_DELAY, {tag = "leave", on_finish = state.leave_to_menu})
end

-- Both players see the knocking card fly face-down to the pile, then a suspense pause follows before the
-- result. For our own knock the clone starts at the real card, which leaves the hand; for the opponent's a
-- random hidden card is used. Both steps are blocking, so the later messages (layoff_phase, round_result)
-- wait in the queue until the flight and the pause are over.
local function handle_knock_discard(state, message)
    local flying_card

    if message.mine then
        flying_card = copy(state.opponent_card_reference)

        -- Find the real card in the hand to start the flight from its position.
        local rank, suit = string.match(message.card, "^([%w]+)_([%a]+)$")
        for _, card in ipairs(state.player_hand.cards) do
            if card.rank == rank and card.suit == suit then
                flying_card:set_position(card:get_position())
                break
            end
        end
        state.player_hand:remove_card(rank, suit)
    else
        -- Fall back to a fresh card back if the opponent's hand is unexpectedly empty.
        flying_card = state.opponent_hand:remove_random_card() or copy(state.opponent_card_reference)
    end

    fly_to_discard_pile(state, flying_card, {
        blocking = true,
        -- The pause starts only when the card has landed.
        on_finish = function()
            state.discard_pile:add_card(flying_card)
            sounds.play_card(message.mine and 1 or config.opponent_card_volume, not message.mine)
            state.animations:delay(KNOCK_PAUSE_DURATION, {blocking = true})
        end
    })
end

-- One function per message type: handlers[type](state, message). Message fields: see server.lua.
local handlers = {}

-- Our turn begins: forget the card taken from the discard pile last turn and allow a new draw request.
function handlers.is_my_turn(state, message)
    state.turn_timer = message.limits and {elapsed = 0, limits = message.limits} or nil
    state.turn_limits = message.limits
    state.taken_from_discard = nil
    state.draw_requested = false
    state.is_my_turn = message.answer

    -- The server says which cards we hold and how many the opponent has: if the view drifted away from it
    -- (a move the server refused and the correction missed it), it is put right now.
    if message.hand and not is_hand_equal(state, message.hand) then
        repair_hand(state, message.hand)
    end
    if message.opponent_cards and #state.opponent_hand.cards ~= message.opponent_cards then
        repair_opponent_hand(state, message.opponent_cards)
    end

    -- This handler runs only now, after the result banner, the deal and the opponent's animations. The
    -- server starts our turn timer when it hears this, so our clock and the server's start together.
    if message.answer then
        network.send({type = "turn_started"})
    end
end

-- The face-up card that starts the round appears on the discard pile.
function handlers.update_discard_pile(state, message)
    state.discard_pile:add_card(get_card(message.card))
end

-- The opponent took a face-down card from the stock.
function handlers.opponent_get_card_from_deck(state)
    add_opponent_card(state, state.deck:get_position())
end

-- The opponent discards: a hidden card flies to the pile and the real face-up card replaces it when it
-- lands. The flight is tagged "discard_pile" (not blocking), which input.lua checks so the player cannot
-- take the pile's top card while the new one is still on its way.
function handlers.opponent_place_card_to_discard_pile(state, message)
    local flying_card = state.opponent_hand:remove_random_card() or copy(state.opponent_card_reference)
    local placed_card = get_card(message.card)

    fly_to_discard_pile(state, flying_card, {
        tag = "discard_pile",
        on_finish = function()
            state.discard_pile:add_card(placed_card)
            sounds.play_card(config.opponent_card_volume, true)
            state.opponent_idle = 0
        end
    })
end

-- The opponent took the top discard card: it leaves the pile and reappears, face-down, in their hand.
function handlers.opponent_get_card_from_discard_pile(state)
    state.discard_pile:remove_top_card()
    add_opponent_card(state, state.discard_pile:get_position())
end

-- We receive a card (deal or draw): it appears at the stock and slides into our hand. The answer to a
-- stock draw request also re-enables drawing (draw_requested).
function handlers.get_card_from_deck(state, message)
    local card = get_card(message.card)
    card:set_position(state.deck:get_position())
    card:set_scale(layout.card_scale(), layout.card_scale())
    state.draw_requested = false
    state.player_hand:add_card(card)
    sounds.play_card(1)

    -- a game step: the turn timer starts again
    if state.turn_timer then state.turn_timer.elapsed = 0 end
end

-- The server refused a move we had applied at once and sends the real table: our hand, the discard pile,
-- the size of the opponent's hand, whether it is our move and the card taken from the pile. The view is put
-- right (without animation) and the soft "no" sound tells the player the move did not count.
function handlers.sync(state, message)
    repair_hand(state, message.your_hand or {})
    repair_opponent_hand(state, message.opponent_cards or #state.opponent_hand.cards)
    repair_pile(state, message.discard_pile or {})

    state.is_my_turn = message.is_my_turn == true
    state.draw_requested = false
    state.taken_from_discard = nil

    if message.taken_from_discard then
        for _, card in ipairs(state.player_hand.cards) do
            if name_of(card) == message.taken_from_discard then
                state.taken_from_discard = card
            end
        end
    end

    sounds.play_failure()
end

-- The knock discard animation is handle_knock_discard above.
handlers.knock_discard = handle_knock_discard

-- A new round starts: clear the table; the cards of the deal follow as separate messages.
function handlers.new_round(state, message)
    reset_table(state, message)
end

-- Someone knocked without gin: both players switch to the layoff scene (the message says which role we
-- have and carries all the cards, which are face up now). The scene returns with SceneManager.set("game"),
-- so this scene keeps its state.
function handlers.layoff_phase(state, message)
    state.dragging_card = nil
    state.is_my_turn = false
    SceneManager.switch("layoff", message)
end

-- Shows what the round ended with: the opponent's cards turn face up with their melds outlined, and the
-- cards the defender laid off leave the hand they came from.
local function reveal_hands(state, message)
    if message.opponent_cards then
        local cards = {}
        local by_name = {}

        for _, name in ipairs(message.opponent_cards) do
            local card = get_card(name)
            by_name[name] = card
            table.insert(cards, card)
        end

        local melds = {}
        for _, meld_names in ipairs(message.opponent_melds or {}) do
            local meld = {}
            for _, name in ipairs(meld_names) do
                table.insert(meld, by_name[name])
            end
            table.insert(melds, meld)
        end

        state.opponent_hand:reveal(cards, melds)
    end

    for _, name in ipairs(message.laid_off_cards or {}) do
        local rank, suit = string.match(name, "^([%w]+)_([%a]+)$")
        state.player_hand:remove_card(rank, suit)
    end
end

-- The round was scored: show the banner, update the totals and reveal the hands. The banner is a blocking
-- animation, so the next deal waits until it has been seen; "round_result" is cancelled first in case a
-- previous banner is still up.
function handlers.round_result(state, message)
    reveal_hands(state, message)
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
end

-- The match ended: show the end screen with the rematch question. If the opponent disconnected there is
-- nobody to play with, so leave to the menu soon.
function handlers.game_over(state, message)
    state.game_over_info = message
    state.is_game_over = true
    state.is_paused = false
    state.is_my_turn = false
    state.dragging_card = nil
    state.rematch_response_sent = false
    state.opponent_left = false

    if message.opponent_disconnected then
        start_leaving(state)
    end
end

-- The opponent refused a rematch (or left after the game): there is nothing to wait for, leave soon.
function handlers.opponent_declined_rematch(state)
    state.opponent_left = true
    start_leaving(state)
end

-- A new match starts (first game or accepted rematch): reset the table, scores and end screen. A pending
-- "leave" is cancelled.
function handlers.new_game(state, message)
    reset_table(state, message)
    state.is_paused = false
    state.is_game_over = false
    state.game_over_info = nil
    state.animations:cancel("leave")
    state.my_total_score = 0
    state.opponent_total_score = 0
    state.rematch_response_sent = false
    state.opponent_left = false
end

-- Runs the handler for message.type; unknown types are ignored.
local function handle(state, message)
    local handler = handlers[message.type]
    if handler then
        handler(state, message)
    end
end

-- Messages that only the layoff scene understands; they stay in the network inbox until it reads them.
local LAYOFF_ONLY = {opponent_layoff = true, layoff_sync = true}

-- Moves everything the server sent since the last frame into the queue (nothing is handled here). The
-- layoff scene's own messages are left alone: the one that switches to it may still be waiting in the
-- queue while the next ones are already here.
function messages.receive(state)
    network.poll()

    local message = network.pop(LAYOFF_ONLY)
    while message do
        table.insert(state.pending_messages, message)
        message = network.pop(LAYOFF_ONLY)
    end
end

-- Handles at most one queued message per frame, and only while no blocking animation is running. This is
-- what puts the server's bursts of messages in order with the animations.
function messages.process_next(state)
    if state.animations:is_busy() or #state.pending_messages == 0 then return end

    -- A correction replaces the pile, so it waits until a card that is still flying onto it has landed (it
    -- would be added a second time).
    if state.pending_messages[1].type == "sync" and state.animations:is_active("discard_pile") then return end

    local message = table.remove(state.pending_messages, 1)

    if message.type == "new_game" and not state.has_started_first_game then
        -- the transition into this scene has just played, a second one would be redundant
        state.has_started_first_game = true
        handle(state, message)
    -- Between rounds / matches the table is reset behind a screen wipe: this blocking wait holds the queue
    -- until the wipe has covered the screen and the handler has run, so the player never sees the cards
    -- vanish.
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
