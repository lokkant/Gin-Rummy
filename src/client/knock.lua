-- Knock decisions of the client (the server checks everything again): whether a knock is possible, which
-- card it would discard and what to send. Used by hud.lua (button state) and input.lua (click).

local network = require "network"

local knock = {}

-- Returns (discard_card, deadwood). discard_card is the card the knock would throw away, or nil when
-- knocking is impossible: it needs 11 cards (after drawing) and at most 10 points of deadwood left after
-- the discard. deadwood is the number the button should show (the current one when no knock is possible).
function knock.evaluate(state)
    local hand = state.player_hand

    if #hand.cards ~= 11 then
        return nil, hand.score
    end

    local discard_card, resulting_deadwood = hand:get_knock_discard(state.taken_from_discard)
    if discard_card == nil then
        return nil, hand.score
    end

    -- More than 10 points left: a knock is not allowed.
    if resulting_deadwood > 10 then
        return nil, resulting_deadwood
    end

    return discard_card, resulting_deadwood
end

-- True if the player may knock right now: it is their turn, the game runs and a legal discard exists.
function knock.is_available(state)
    if not state.is_my_turn or state.is_game_over then return false end
    return knock.evaluate(state) ~= nil
end

-- Returns the shown meld arrangement as lists of card names for the knock message.
-- discard_card is thrown away by the knock, so it is left out of its meld.
function knock.build_combinations_message(state, discard_card)
    local combos = {}
    for _, meld in ipairs(state.player_hand:get_current_combination()) do
        local meld_names = {}
        for _, card in ipairs(meld) do
            if card ~= discard_card then
                table.insert(meld_names, card.rank .. "_" .. card.suit)
            end
        end
        table.insert(combos, meld_names)
    end
    return combos
end

-- Sends the knock if it is allowed (see evaluate) and marks our turn as finished. Returns true when sent.
function knock.try_send(state)
    if not state.is_my_turn or state.is_game_over then return false end

    local discard_card = knock.evaluate(state)
    if discard_card == nil then return false end

    network.send({
        type = "knock",
        discard = discard_card.rank .. "_" .. discard_card.suit,
        combinations = knock.build_combinations_message(state, discard_card)
    })
    state.is_my_turn = false

    return true
end

return knock
