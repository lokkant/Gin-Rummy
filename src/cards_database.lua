-- Card names and card objects. A card name is "<rank>_<suit>" (e.g. "10_heart", "A_spade"); it is also the
-- asset file name (assets/cards/<name>.png) and how cards are identified in network messages.
-- Defines the globals get_card_names, get_card (with a texture, client only) and get_card_data (data
-- only, works on the server too).

require 'card'

local love = require "love"

-- Returns the 52 card names (4 suits x 13 ranks) in a fixed order; the server shuffles them.
function get_card_names()
    local cards = {}
    local suits = {"heart", "diamond", "club", "spade"}
    local ranks = {"2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A"}

    for _, suit in ipairs(suits) do
        for _, rank in ipairs(ranks) do
            table.insert(cards, rank .. "_" .. suit)
        end
    end

    return cards
end

-- Client only: creates a drawable Card at (0, 0) for `name` (loads its texture), already scaled for
-- the current window (global `scale` from main.lua divided by ASSET_RESOLUTION_FACTOR).
function get_card(name)
    local texture_path = string.format("assets/cards/%s.png", name)
    local texture = love.graphics.newImage(texture_path)
    texture:setFilter("linear", "linear")
    -- Splits "10_heart" into rank "10" and suit "heart".
    local rank, suit = string.match(name, "([%w]+)_([%a]+)")
    local card_scale = scale / ASSET_RESOLUTION_FACTOR
    return Card(rank, suit, 0, 0, texture, card_scale, card_scale)
end

-- Creates a Card that has only a rank and a suit (no texture, scale 1): enough for the meld logic and
-- usable without graphics.
function get_card_data(name)
    local rank, suit = string.match(name, "([%w]+)_([%a]+)")
    return Card(rank, suit, 0, 0, nil, 1, 1)
end

return get_card_names, get_card, get_card_data