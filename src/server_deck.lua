require 'cards_database'

local love = require "love"

math.randomseed(os.time())

-- Fisher-Yates shuffle function
local function shuffle(tbl)
    for i = #tbl, 2, -1 do
        local j = math.random(i)
        tbl[i], tbl[j] = tbl[j], tbl[i]
    end
    return tbl
end

function Deck()
    local self = {}
    self.cards = shuffle(get_card_names()) -- Use the cards from the cardsDatabase.lua and shuffle them

    function self:get_top_card()
        return table.remove(self.cards)
    end

    return self
end

return Deck