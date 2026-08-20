local function copy(tab)
    local new_table = {}
    for key, value in ipairs(tab) do
        new_table[key] = value
    end

    return new_table
end

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


local function is_run(cards)
    if #cards < 3 then return false end

    local sorted_cards = copy(cards)
    table.sort(sorted_cards, function(a, b) return a:is_lesser_than(b) end)

    local rank_values = {["A"]=1, ["2"]=2, ["3"]=3, ["4"]=4, ["5"]=5, ["6"]=6, ["7"]=7, ["8"]=8, ["9"]=9, ["10"]=10, ["J"]=11, ["Q"]=12, ["K"]=13}
    local previous_rank = sorted_cards[1].rank
    local suit = sorted_cards[1].suit

    for i = 2, #sorted_cards do
        if sorted_cards[i].suit ~= suit or (rank_values[sorted_cards[i].rank] - rank_values[previous_rank]) ~= 1 then
            return false
        end
        previous_rank = sorted_cards[i].rank
    end

    return true
end


function is_valid_meld(cards)
    return is_set(cards) or is_run(cards)
end


function can_extend_meld(card, meld_cards)
    local candidate = copy(meld_cards)
    table.insert(candidate, card)
    return is_valid_meld(candidate)
end


local function gen_combinations(cards, size)
    local function generate(index, size_)
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

function get_card_value(card)
    local rank_values = {["A"]=1, ["2"]=2, ["3"]=3, ["4"]=4, ["5"]=5, ["6"]=6, ["7"]=7, ["8"]=8, ["9"]=9, ["10"]=10, ["J"]=10, ["Q"]=10, ["K"]=10}
    return rank_values[card.rank]
end

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


local function contain(table_, element)
    for _, value in pairs(table_) do
        if value == element then
            return true
        end
    end
    return false
end

local function gen_melds_combinations(cards)
    local melds = get_melds(cards)

    local function gen(index, used_cards)
        if index > #melds then
            return {{}}
        end

        local result = {}
        local meld = melds[index]

        local skip_results = gen(index + 1, used_cards)
        for _, combination in ipairs(skip_results) do
            table.insert(result, combination)
        end

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


function best_combinations(cards)
    local best_combinations = {{}}
    local best_score = 0

    for _, card in ipairs(cards) do
        best_score = best_score + get_card_value(card)
    end

    local melds_combinations = gen_melds_combinations(cards)

    for _, combination in ipairs(melds_combinations) do
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
