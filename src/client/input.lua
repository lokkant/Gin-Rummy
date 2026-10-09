local network = require "network"
local ui = require "ui"
local knock = require "client/knock"

local input = {}

function input.mousepressed(state, x, y, button)
    local hand = state.player_hand

    if button == 2 then hand:increase_index_of_combination() end
    if button ~= 1 then return end

    if ui.point_in_rect(x, y, state.layout.knock_button) then
        knock.try_send(state)
        return
    end

    -- take card from deck (one request at a time: the card is only added when the server answers)
    if state.deck:mousepressed(x, y, button) and state.is_my_turn and #hand.cards == 10 and not state.draw_requested then
        state.draw_requested = true
        network.send({type = "get_card_from_deck"})
    -- take card from discard pile (not while the opponent's card is still flying onto it)
    elseif state.discard_pile:mousepressed(x, y, button) then
        if state.is_my_turn and #hand.cards == 10 and not state.animations:is_active("discard_pile") then
            local card = state.discard_pile:remove_top_card()
            if card ~= nil then
                state.taken_from_discard = card
                hand:add_card(card)
                network.send({type = "get_card_from_discard_pile"})
            end
        end
    -- dragging card
    elseif state.dragging_card == nil then
        for i = #hand.cards, 1, -1 do
            local card = hand.cards[i]
            if card:mousepressed(x, y, button) then
                local card_x, card_y = card:get_position()
                state.dragging_card = card
                state.drag_offset_x = x - card_x
                state.drag_offset_y = y - card_y
                break
            end
        end
    end
end

function input.mousereleased(state, x, y, button)
    local card = state.dragging_card

    -- move card to discard pile (the card just taken from it can't go straight back)
    if card ~= nil and card ~= state.taken_from_discard and
       state.discard_pile:mousepressed(x, y, button) and state.is_my_turn and #state.player_hand.cards == 11 then
        network.send({type = "put_card_to_discard_pile", card = card.rank .. "_" .. card.suit})

        state.discard_pile:add_card(card)
        state.player_hand:remove_card(card.rank, card.suit)

        state.is_my_turn = false
    end

    if button == 1 then state.dragging_card = nil end
end

function input.mousemoved(state, x, y)
    if state.dragging_card then
        state.dragging_card:set_position(x - state.drag_offset_x, y - state.drag_offset_y)
    end
end

-- The card under the cursor is lifted; a dragged card has no hover
function input.update_hover(state, mx, my)
    if state.dragging_card then
        state.hovered_card = nil
    else
        state.hovered_card = state.player_hand:get_card_at(mx, my, state.hovered_card)
    end
end

return input
