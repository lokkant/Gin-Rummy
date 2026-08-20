require 'card'

local love = require "love"

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

function get_card(name)
    local texture_path = string.format("assets/cards/%s.png", name)
    local texture = love.graphics.newImage(texture_path)
    texture:setFilter("nearest", "nearest")
    local rank, suit = string.match(name, "([%w]+)_([%a]+)")
    return Card(rank, suit, 0, 0, texture, 1, 1)
end

function get_card_data(name)
    local rank, suit = string.match(name, "([%w]+)_([%a]+)")
    return Card(rank, suit, 0, 0, nil, 1, 1)
end

return get_card_names, get_card, get_card_data