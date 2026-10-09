-- Builds the table objects of the game scene (stock, discard pile, both hands, the reference card back) and
-- positions them for the current window size. Owns the shared textures. Fills these fields of the game
-- state: deck, discard_pile, player_hand, opponent_hand, opponent_card_reference and layout (shared sizes).
-- Vertical positions are fractions of the window height, so the layout follows resizes.

require 'card'
require 'deck'
require 'player_hand'
require 'opponent_hand'
require 'discard_pile'

local love = require "love"

local layout = {}

-- Speed of cards sliding into place and flying, in pixels per second.
layout.CARD_SPEED = 1000

-- Top of the opponent's / our card row as a fraction of the window height (design values at 1080 px).
local OPPONENT_Y_FRACTION = 100 / 1080
local HAND_Y_FRACTION = 750 / 1080

-- Size and margin (pixels) of the KNOCK button at the right edge, level with our card row.
local KNOCK_BUTTON_WIDTH = 140
local KNOCK_BUTTON_HEIGHT = 50
local KNOCK_BUTTON_MARGIN = 30

-- Textures are loaded once and shared by every game; nil until first needed.
local textures

-- Loads (once) and returns the shared textures: back (face-down card), card_slot (empty discard pile) and
-- deck. The card back is smoothed when scaled; the pixel-art slot and stock use nearest filtering to
-- stay crisp.
local function get_textures()
    if textures == nil then
        textures = {
            back = love.graphics.newImage("assets/back_flipped.png"),
            card_slot = love.graphics.newImage("assets/card_slot.png"),
            deck = love.graphics.newImage("assets/deck.png")
        }

        textures.back:setFilter("linear", "linear")
        textures.card_slot:setFilter("nearest", "nearest")
        textures.deck:setFilter("nearest", "nearest")
    end

    return textures
end

-- Draw scale of a card: the global UI scale divided by the art's resolution factor.
function layout.card_scale()
    return scale / ASSET_RESOLUTION_FACTOR
end

-- Creates the table objects into `state` and lays them out for the current window. The opponent's card
-- reference is a face-down card that is cloned for every card that flies or sits in the opponent's hand.
function layout.create(state)
    local loaded = get_textures()
    local card_scale = layout.card_scale()

    state.deck = Deck(100, 0, loaded.deck, card_scale, card_scale)
    state.discard_pile = DiscardPile(0, 0, loaded.card_slot, card_scale, card_scale)
    state.player_hand = PlayerHand(0, 0)
    state.opponent_hand = OpponentHand(0, 0)
    state.opponent_card_reference = Card("A", "heart", 0, 0, loaded.back, card_scale, card_scale)
    state.layout = {back_texture = loaded.back, deck_texture = loaded.deck}

    layout.apply(state, love.graphics.getWidth(), love.graphics.getHeight())
end

-- (Re)positions everything for a window of w x h pixels; called by create and on every resize. The stock is
-- at the left edge, the discard pile in the middle of the window, both hands centred horizontally. The
-- KNOCK button sits at the right edge, level with our cards.
function layout.apply(state, w, h)
    local card_scale = layout.card_scale()
    local info = state.layout

    info.opponent_y = h * OPPONENT_Y_FRACTION
    info.hand_y = h * HAND_Y_FRACTION
    info.card_width = info.back_texture:getWidth() * card_scale
    info.card_height = info.back_texture:getHeight() * card_scale
    -- Right edge minus margin, vertically centred on our card row.
    info.knock_button = {
        x = w - KNOCK_BUTTON_WIDTH - KNOCK_BUTTON_MARGIN,
        y = info.hand_y + info.card_height / 2 - KNOCK_BUTTON_HEIGHT / 2,
        w = KNOCK_BUTTON_WIDTH,
        h = KNOCK_BUTTON_HEIGHT
    }

    state.deck.scaleX = card_scale
    state.deck.scaleY = card_scale
    state.deck.y = h / 2 - info.deck_texture:getHeight() * card_scale / 2

    state.discard_pile.scaleX = card_scale
    state.discard_pile.scaleY = card_scale
    state.discard_pile.x = w / 2 - state.discard_pile:get_width() / 2
    state.discard_pile.y = h / 2 - state.discard_pile:get_height() / 2

    state.player_hand.x = w / 2
    state.player_hand.y = info.hand_y
    state.opponent_hand.x = w / 2
    state.opponent_hand.y = info.opponent_y

    state.opponent_card_reference:set_scale(card_scale, card_scale)

    -- Applies the current card scale to one card.
    local function rescale(card)
        card:set_scale(card_scale, card_scale)
    end

    -- Card sizes depend on the window, so every existing card is rescaled: both hands, the two remembered
    -- pile cards and the cards that are currently flying.
    for _, card in ipairs(state.player_hand.cards) do rescale(card) end
    for _, card in ipairs(state.opponent_hand.cards) do rescale(card) end
    if state.discard_pile.highest_card ~= nil then rescale(state.discard_pile.highest_card) end
    if state.discard_pile.second_highest_card ~= nil then rescale(state.discard_pile.second_highest_card) end
    if state.animations ~= nil then state.animations:each_card(rescale) end
end

return layout
