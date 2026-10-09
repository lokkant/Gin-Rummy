-- The stock of one round: a shuffled list of the 52 card names ("10_heart", ...), server side only. Global
-- constructor-style class: `require 'server_deck'` defines ServerDeck(), used by game.lua and server.lua.
-- The shuffle is seeded from several entropy sources so every deck differs, even between runs.

require 'cards_database'

local love = require "love"

-- Hash of the previous seed; chained so each new deck gets a different seed than the one before.
local seed_state = ""
-- How many decks were created so far (also mixed into the seed).
local decks_created = 0

-- Reads 4 bytes of `bytes` starting at `offset` as a little-endian unsigned 32-bit integer.
local function read_u32(bytes, offset)
    local b1, b2, b3, b4 = string.byte(bytes, offset, offset + 3)
    return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
end

-- Returns a new LOVE random generator seeded from time, clock, addresses and the previous seed, hashed
-- with SHA-256. The two 32-bit halves of the digest form the generator's 64-bit seed.
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

-- Shuffles the array `tbl` in place (Fisher-Yates, every permutation equally likely) and returns it.
local function shuffle(tbl)
    local generator = new_random_generator()

    for i = #tbl, 2, -1 do
        local j = generator:random(i)
        tbl[i], tbl[j] = tbl[j], tbl[i]
    end
    return tbl
end

-- Global constructor. Returns a deck object: self.cards is the array of card names (top = last element).
function ServerDeck()
    local self = {}
    self.cards = shuffle(get_card_names()) -- all names from cards_database.lua, shuffled

    -- Removes and returns the top card name, or nil when the stock is empty.
    function self:get_top_card()
        return table.remove(self.cards)
    end

    return self
end

return ServerDeck