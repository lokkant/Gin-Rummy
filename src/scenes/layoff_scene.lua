require 'card'
require 'cards_database'
require 'best_melds'

local love = require "love"
local json = require "dkjson"

local Scene = {}

local host
local server

local knocker_melds = {}
local my_cards = {}
local laid_off = {}

local dragging_card
local drag_offset_x
local drag_offset_y
local hovered_card

local FINISH_BUTTON_WIDTH = 200
local FINISH_BUTTON_HEIGHT = 50
local finish_button_x
local finish_button_y
local font

local SPEED = 1000

local function build_meld_cards(names)
    local cards = {}
    for _, name in ipairs(names) do
        local card = get_card(name)
        card:set_scale(scale, scale)
        table.insert(cards, card)
    end
    return cards
end

-- Computes each card's target position; actual movement happens smoothly
-- in Scene.update via card:move_to, except right after Scene.load where
-- cards are snapped straight to their target (see snap_to_target)
local function compute_layout()
    local w = love.graphics.getWidth()
    local h = love.graphics.getHeight()

    local top_y = 100

    local card_h = 0
    if #knocker_melds > 0 then
        card_h = knocker_melds[1].cards[1]:get_height()
    end
    local meld_spacing_y = card_h + 20

    for i, meld in ipairs(knocker_melds) do
        local card_w = meld.cards[1]:get_width()
        local overlap = card_w * 0.55
        local total_width = overlap * (#meld.cards - 1) + card_w

        meld.x = w / 2 - total_width / 2
        meld.y = top_y + (i - 1) * meld_spacing_y
        meld.width = total_width
        meld.height = card_h

        for j, card in ipairs(meld.cards) do
            card.target_x = meld.x + (j - 1) * overlap
            card.target_y = meld.y
        end
    end

    if #my_cards > 0 then
        local card_w = my_cards[1]:get_width()
        local overlap = card_w * 0.65
        local total_width = overlap * (#my_cards - 1) + card_w
        local start_x = w / 2 - total_width / 2
        local hand_y = h - 220

        for i, card in ipairs(my_cards) do
            local target_y = hand_y
            if card == hovered_card then
                target_y = target_y - card:get_height() / 6
            end

            card.target_x = start_x + (i - 1) * overlap
            card.target_y = target_y
        end
    end

    finish_button_x = w / 2 - FINISH_BUTTON_WIDTH / 2
    finish_button_y = h - 90
end

local function snap_to_target()
    for _, meld in ipairs(knocker_melds) do
        for _, card in ipairs(meld.cards) do
            card:set_position(card.target_x, card.target_y)
        end
    end

    for _, card in ipairs(my_cards) do
        card:set_position(card.target_x, card.target_y)
    end
end

local function is_point_in_finish_button(x, y)
    return x >= finish_button_x and x <= finish_button_x + FINISH_BUTTON_WIDTH and
           y >= finish_button_y and y <= finish_button_y + FINISH_BUTTON_HEIGHT
end

local function find_meld_at(x, y)
    for i, meld in ipairs(knocker_melds) do
        if x >= meld.x - 25 and x <= meld.x + meld.width + 25 and
           y >= meld.y - 25 and y <= meld.y + meld.height + 25 then
            return i
        end
    end
    return nil
end

local finished = false

local function finish()
    finished = true
    server:send(json.encode({type = "finish_layoff", layoffs = laid_off}))
    SceneManager.set("game")
end

function Scene.load(shared_host, shared_server, combinations, my_hand_cards)
    host = shared_host
    server = shared_server

    font = love.graphics.newFont("ArchivoBlack-Regular.ttf")

    knocker_melds = {}
    for _, meld_names in ipairs(combinations) do
        table.insert(knocker_melds, {cards = build_meld_cards(meld_names)})
    end

    my_cards = {}
    for _, card in ipairs(my_hand_cards) do
        local copy = get_card(card.rank .. "_" .. card.suit)
        copy:set_scale(scale, scale)
        table.insert(my_cards, copy)
    end

    dragging_card = nil
    hovered_card = nil
    laid_off = {}
    finished = false

    compute_layout()
    snap_to_target()
end

function Scene.mousepressed(x, y, button)
    if button ~= 1 then return end

    if is_point_in_finish_button(x, y) then
        finish()
        return
    end

    if dragging_card == nil then
        for i = #my_cards, 1, -1 do
            local card = my_cards[i]
            if card:mousepressed(x, y, button) then
                dragging_card = card
                local cx, cy = card:get_position()
                drag_offset_x = x - cx
                drag_offset_y = y - cy
                break
            end
        end
    end
end

function Scene.mousereleased(x, y, button)
    if button ~= 1 or dragging_card == nil then return end

    local target_meld_index = find_meld_at(x, y)

    if target_meld_index ~= nil then
        local meld = knocker_melds[target_meld_index]
        if can_extend_meld(dragging_card, meld.cards) then
            table.insert(meld.cards, dragging_card)
            table.insert(laid_off, {card = dragging_card.rank .. "_" .. dragging_card.suit, meld_index = target_meld_index})

            for i, c in ipairs(my_cards) do
                if c == dragging_card then
                    table.remove(my_cards, i)
                    break
                end
            end
        end
    end

    dragging_card = nil
    compute_layout()
end

function Scene.mousemoved(x, y, dx, dy)
    if dragging_card then
        dragging_card:set_position(x - drag_offset_x, y - drag_offset_y)
    end
end

function Scene.update(dt)
    if finished then return end

    if dragging_card == nil then
        local mx, my = love.mouse.getPosition()
        hovered_card = nil
        for i = #my_cards, 1, -1 do
            local card = my_cards[i]
            if card:mousehover(mx, my) then
                hovered_card = card
                break
            end
        end
    else
        hovered_card = nil
    end

    compute_layout()

    for _, meld in ipairs(knocker_melds) do
        for _, card in ipairs(meld.cards) do
            if card ~= dragging_card then
                card:move_to(dt, SPEED, card.target_x, card.target_y)
            end
        end
    end

    for _, card in ipairs(my_cards) do
        if card ~= dragging_card then
            card:move_to(dt, SPEED, card.target_x, card.target_y)
        end
    end

    if host then
        local event = host:service(0)
        while event do
            event = host:service(0)
        end
    end
end

function Scene.draw()
    love.graphics.setFont(font)

    love.graphics.setColor(love.math.colorFromBytes(53, 101, 77, 255))
    love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.printf("Opponent's melds - drag your cards onto them to lay off", 0, 30, love.graphics.getWidth(), "center")

    for _, meld in ipairs(knocker_melds) do
        for _, card in ipairs(meld.cards) do
            if card ~= dragging_card then
                card:draw(true)
            end
        end
    end

    for _, card in ipairs(my_cards) do
        if card ~= dragging_card then
            card:draw(true)
        end
    end

    if dragging_card ~= nil then
        dragging_card:draw(true)
    end

    love.graphics.setColor(0.3, 0.6, 0.3, 1)
    love.graphics.rectangle("fill", finish_button_x, finish_button_y, FINISH_BUTTON_WIDTH, FINISH_BUTTON_HEIGHT, 8, 8)

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.printf("FINISH", finish_button_x, finish_button_y + FINISH_BUTTON_HEIGHT / 2 - 8, FINISH_BUTTON_WIDTH, "center")
end

return Scene
