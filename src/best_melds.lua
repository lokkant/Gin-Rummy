-- Gin Rummy meld logic shared by the server (validating knocks, scoring) and the client (sorting the hand,
-- meld highlights, KNOCK button). Works on logic-only Card objects (rank, suit, is_lesser_than), so it
-- needs no graphics. Defines the globals is_valid_meld, can_extend_meld, get_card_value and
-- best_combinations; callers `require 'best_melds'` for these side effects, the returned values at the end
-- are not used.
--
-- Terms: a meld is a set (3-4 cards of one rank) or a run (3+ consecutive cards of one suit; the ace is
-- low, so A-2-3 is a run but Q-K-A is not). Deadwood is the total value of the cards that are in no meld.

-- Shallow copy of an array (only the ipairs part); used so sorting or extending never touches the original.
local function copy(tab)
    local new_table = {}
    for key, value in ipairs(tab) do
        new_table[key] = value
    end

    return new_table
end

-- True if the cards form a set: 3 or 4 cards of the same rank.
local function is_set(cards)
    if #cards ~= 3 and #cards ~= 4 then return false end

    local rank = cards[1].rank

    for i = 2, #cards do
        if cards[i].rank ~= rank then
            return false
        end
    end

    return true
end


-- True if the cards form a run: 3 or more cards of one suit with consecutive ranks (ace low only).
-- Input order does not matter, the cards are sorted on a copy first.
local function is_run(cards)
    if #cards < 3 then return false end

    local sorted_cards = copy(cards)
    table.sort(sorted_cards, function(a, b) return a:is_lesser_than(b) end)

    -- Rank positions for the "consecutive" test.
    local rank_values = {["A"]=1, ["2"]=2, ["3"]=3, ["4"]=4, ["5"]=5, ["6"]=6, ["7"]=7, ["8"]=8, ["9"]=9, ["10"]=10, ["J"]=11, ["Q"]=12, ["K"]=13}
    local previous_rank = sorted_cards[1].rank
    local suit = sorted_cards[1].suit

    for i = 2, #sorted_cards do
        -- Every card must have the suit of the first one and be exactly one rank above its predecessor.
        if sorted_cards[i].suit ~= suit or (rank_values[sorted_cards[i].rank] - rank_values[previous_rank]) ~= 1 then
            return false
        end
        previous_rank = sorted_cards[i].rank
    end

    return true
end


-- True if the cards form a valid meld (a set or a run).
function is_valid_meld(cards)
    return is_set(cards) or is_run(cards)
end


-- True if adding `card` to the meld `meld_cards` still gives a valid meld (used for layoffs, e.g. a 7 onto
-- 4-5-6). Does not modify meld_cards.
function can_extend_meld(card, meld_cards)
    local candidate = copy(meld_cards)
    table.insert(candidate, card)
    return is_valid_meld(candidate)
end


-- Returns all subsets of exactly `size` cards of the array `cards` (n choose size), each as an array.
-- Recursive: generate(index, size_) picks one card at position >= index and combines it with every
-- (size_ - 1)-subset of the cards after it. The loop bound stops early enough to leave room for the rest.
-- Cards inside a subset come out in reverse order, which does not matter (is_run sorts its input).
local function gen_combinations(cards, size)
    -- Picks one card at a position >= index, then recurses for the remaining size_ - 1 cards.
    local function generate(index, size_)
        -- Choosing zero cards has exactly one result: the empty subset.
        if size_ == 0 then return {{}} end

        local result = {}

        for ind = index, (#cards - size_ + 1) do
            local generated = generate(ind + 1, size_ - 1)
            for _, set in ipairs(generated) do
                table.insert(set, cards[ind])
                table.insert(result, set)
            end
        end

        return result
    end

    return generate(1, size)
end

-- Deadwood value of a card: A = 1, 2-10 face value, J/Q/K = 10. Only card.rank is read.
function get_card_value(card)
    local rank_values = {["A"]=1, ["2"]=2, ["3"]=3, ["4"]=4, ["5"]=5, ["6"]=6, ["7"]=7, ["8"]=8, ["9"]=9, ["10"]=10, ["J"]=10, ["Q"]=10, ["K"]=10}
    return rank_values[card.rank]
end

-- Returns every meld (set or run) that can be built from `cards`. Melds overlap freely here; picking
-- disjoint ones is up to gen_melds_combinations. Subsets of every size 3..n are tried, which is cheap
-- for a hand of at most 11 cards.
local function get_melds(cards)
    local melds = {}

    for size = 3, #cards do
        for _, combination in ipairs(gen_combinations(cards, size)) do
            if is_set(combination) or is_run(combination) then
                table.insert(melds, combination)
            end
        end
    end

    return melds
end


-- True if `element` is one of the values of `table_` (compared by identity for cards).
local function contain(table_, element)
    for _, value in pairs(table_) do
        if value == element then
            return true
        end
    end
    return false
end

-- Returns every way to choose melds that share no card: a list of arrangements, each a list of melds
-- (the empty arrangement is included). Recursion gen(index, used_cards) decides for melds[index]: skip it,
-- or take it when none of its cards is used by the melds taken before. Exponential in the number of melds,
-- but hands are small (at most 11 cards).
local function gen_melds_combinations(cards)
    local melds = get_melds(cards)

    -- Returns all arrangements that can be made from melds[index..#melds] without touching used_cards.
    local function gen(index, used_cards)
        if index > #melds then
            return {{}}
        end

        local result = {}
        local meld = melds[index]

        -- Branch 1: arrangements that do not use this meld.
        local skip_results = gen(index + 1, used_cards)
        for _, combination in ipairs(skip_results) do
            table.insert(result, combination)
        end

        -- Branch 2: take this meld, which is only allowed if it does not overlap melds taken earlier.
        local is_contain = false
        for _, card in ipairs(meld) do
            if contain(used_cards, card) then
                is_contain = true
                break
            end
        end

        if not is_contain then
            local new_used_cards = copy(used_cards)
            for _, card in ipairs(meld) do
                table.insert(new_used_cards, card)
            end

            -- Each result built from the later melds is extended with this meld.
            local include_results = gen(index + 1, new_used_cards)
            for _, combination in ipairs(include_results) do
                table.insert(combination, meld)
                table.insert(result, combination)
            end
        end

        return result
    end

    return gen(1, {})
end


-- Finds the best way to meld a hand. Returns (arrangements, deadwood): ALL arrangements with the lowest
-- deadwood and that deadwood. Ties are common (e.g. a card that fits both a set and a run), and the
-- player can cycle through them with the right mouse button. Inside this function the local
-- `best_combinations` hides the function itself; that is harmless as there is no recursion.
function best_combinations(cards)
    local best_combinations = {}
    local best_score = math.huge

    local melds_combinations = gen_melds_combinations(cards)

    for _, combination in ipairs(melds_combinations) do
        -- Deadwood of this arrangement: the value of every card that is in none of its melds.
        local score = 0
        for _, card in ipairs(cards) do
            local is_used = false
            for _, meld in ipairs(combination) do
                if contain(meld, card) then
                    is_used = true
                end
            end

            if not is_used then
                score = score + get_card_value(card)
            end
        end

        -- Strictly better: restart the list. Equal: keep as an alternative.
        if score < best_score then
            best_combinations = {combination}
            best_score = score
        elseif score == best_score then
            table.insert(best_combinations, combination)
        end
    end

    return best_combinations, best_score
end

return best_combinations, is_valid_meld, can_extend_meld
