-- Card names and card objects. A card name is "<rank>_<suit>" (e.g. "10_heart", "A_spade"); it is also the
-- asset file name (assets/cards/<name>.png) and how cards are identified in network messages.
-- Defines the globals get_card_names, get_card (with a texture, client only) and get_card_data (data
-- only, works on the server too).

require 'card'

local love = require "love"

-- Card images by file name. An image is loaded once and shared by all cards of that face; false marks a
-- file that does not exist.
local card_images = {}

-- Returns the image in the file at `path` (smoothed when scaled), or nil if there is no such file.
local function load_card_image(path)
    if card_images[path] == nil then
        if love.filesystem.getInfo(path) then
            local image = love.graphics.newImage(path)
            image:setFilter("linear", "linear")
            card_images[path] = image
        else
            card_images[path] = false
        end
    end

    return card_images[path] or nil
end

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
    local texture = load_card_image(texture_path)
    if texture == nil then
        error("missing card image " .. texture_path)
    end

    -- Splits "10_heart" into rank "10" and suit "heart".
    local rank, suit = string.match(name, "([%w]+)_([%a]+)")
    local card_scale = scale / ASSET_RESOLUTION_FACTOR
    local card = Card(rank, suit, 0, 0, texture, card_scale, card_scale)

    -- Jacks, queens and kings have a second picture with the pupils looking to the left (see
    -- Card:get_texture).
    card.look_left_texture = load_card_image(string.format("assets/cards/%s_l.png", name))

    return card
end

-- Creates a Card that has only a rank and a suit (no texture, scale 1): enough for the meld logic and
-- usable without graphics.
function get_card_data(name)
    local rank, suit = string.match(name, "([%w]+)_([%a]+)")
    return Card(rank, suit, 0, 0, nil, 1, 1)
end

return get_card_names, get_card, get_card_data