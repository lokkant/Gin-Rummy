-- Mouse handling of the game scene while playing: taking cards from the stock or the discard pile, dragging
-- cards inside the hand, discarding by dropping onto the discard pile, cycling meld arrangements and
-- pressing KNOCK. Moves are applied optimistically: the client updates its own view and tells the server at
-- the same time (only a stock draw waits for the server's card). Overlays get the clicks first
-- (game_client.lua).

local network = require "network"
local ui = require "ui"
local knock = require "client/knock"
local sounds = require "client/sounds"

local input = {}

-- Left button: KNOCK button, stock, discard pile or the start of a card drag. Right button: next best meld
-- arrangement. A hand of 10 cards means "draw first", 11 cards means "discard (or knock) now".
function input.mousepressed(state, x, y, button)
    local hand = state.player_hand

    if button == 2 then hand:increase_index_of_combination() end
    if button ~= 1 then return end

    -- A KNOCK that is not allowed (not our turn, nothing to throw away, too much deadwood) gets the soft
    -- "no" sound.
    if ui.point_in_rect(x, y, state.layout.knock_button) then
        if not knock.try_send(state) then
            sounds.play_failure()
        end
        return
    end

    -- take card from deck (one request at a time: the card is only added when the server answers)
    if state.deck:mousepressed(x, y) then
        if state.is_my_turn and #hand.cards == 10 then
            if not state.draw_requested then
                state.draw_requested = true
                network.send({type = "get_card_from_deck"})
            end
        else
            -- not our turn, or the card for this turn is already drawn
            sounds.play_failure()
        end
    -- take card from discard pile (not while the opponent's card is still flying onto it, and not while a
    -- stock draw is pending: the server would refuse the second card, but the stock card still arrives and
    -- the hand would end up with 12 cards)
    elseif state.discard_pile:mousepressed(x, y) then
        if not (state.is_my_turn and #hand.cards == 10) or state.draw_requested or
           state.animations:is_active("discard_pile") then
            sounds.play_failure()
        else
            -- Taken locally at once; taken_from_discard remembers it, because it may not be thrown back
            -- this turn.
            local card = state.discard_pile:remove_top_card()
            if card ~= nil then
                state.taken_from_discard = card
                hand:add_card(card)
                sounds.play_card(1)

                -- a game step: the turn timer starts again
                if state.turn_timer then state.turn_timer.elapsed = 0 end
                network.send({type = "get_card_from_discard_pile"})
            end
        end
    -- dragging card
    elseif state.dragging_card == nil then
        for i = #hand.cards, 1, -1 do
            local card = hand.cards[i]
            if card:mousepressed(x, y) then
                local card_x, card_y = card:get_position()
                state.dragging_card = card
                state.drag_offset_x = x - card_x
                state.drag_offset_y = y - card_y
                break
            end
        end
    end
end

-- Dropping a dragged card on the discard pile discards it. That needs our turn, 11 cards and a card other
-- than the one just taken from the pile (the server refuses it too). The local view is updated at once and
-- our turn is marked finished. Releasing the left button always ends the drag.
function input.mousereleased(state, x, y, button)
    local card = state.dragging_card

    -- A card dropped on the discard pile is discarded (the card just taken from the pile can't go straight
    -- back); any other drop there is an invalid move (not our turn, nothing drawn yet, the taken card).
    if card ~= nil and state.discard_pile:mousepressed(x, y) then
        if card ~= state.taken_from_discard and state.is_my_turn and #state.player_hand.cards == 11 then
            network.send({type = "put_card_to_discard_pile", card = card.rank .. "_" .. card.suit})

            state.discard_pile:add_card(card)
            state.player_hand:remove_card(card.rank, card.suit)
            sounds.play_card(1)

            state.is_my_turn = false
        else
            sounds.play_failure()
        end
    end

    if button == 1 then state.dragging_card = nil end
end

-- A dragged card follows the cursor, keeping the offset at which it was grabbed.
function input.mousemoved(state, x, y)
    if state.dragging_card then
        state.dragging_card:set_position(x - state.drag_offset_x, y - state.drag_offset_y)
    end
end

-- (mx, my) is the cursor. The card under it is lifted; a dragged card has no hover
function input.update_hover(state, mx, my)
    if state.dragging_card then
        state.hovered_card = nil
    else
        state.hovered_card = state.player_hand:get_card_at(mx, my, state.hovered_card)
    end
end

return input
