local network = require "network"

local knock = {}

-- The card the knock would discard (nil if knocking is impossible) and the deadwood to show
function knock.evaluate(state)
    local hand = state.player_hand

    if #hand.cards ~= 11 then
        return nil, hand.score
    end

    local discard_card, resulting_deadwood = hand:get_knock_discard(state.taken_from_discard)
    if discard_card == nil then
        return nil, hand.score
    end

    if resulting_deadwood > 10 then
        return nil, resulting_deadwood
    end

    return discard_card, resulting_deadwood
end

function knock.is_available(state)
    if not state.is_my_turn or state.is_game_over then return false end
    return knock.evaluate(state) ~= nil
end

-- discard_card is thrown away by the knock, so it can't stay in a meld
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
