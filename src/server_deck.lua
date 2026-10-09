require 'cards_database'

local love = require "love"

local seed_state = ""
local decks_created = 0

local function read_u32(bytes, offset)
    local b1, b2, b3, b4 = string.byte(bytes, offset, offset + 3)
    return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
end

local function new_random_generator()
    decks_created = decks_created + 1

    local entropy = table.concat({
        seed_state,
        tostring(os.time()),
        tostring(os.clock()),
        tostring(love.timer.getTime()),
        tostring({}),      -- the address changes between runs (ASLR)
        tostring(print),
        tostring(decks_created)
    }, "|")

    seed_state = love.data.hash("sha256", entropy)

    return love.math.newRandomGenerator(read_u32(seed_state, 1), read_u32(seed_state, 5))
end

-- Fisher-Yates shuffle function
local function shuffle(tbl)
    local generator = new_random_generator()

    for i = #tbl, 2, -1 do
        local j = generator:random(i)
        tbl[i], tbl[j] = tbl[j], tbl[i]
    end
    return tbl
end

function ServerDeck()
    local self = {}
    self.cards = shuffle(get_card_names()) -- Use the cards from the cardsDatabase.lua and shuffle them

    function self:get_top_card()
        return table.remove(self.cards)
    end

    return self
end

return ServerDeck