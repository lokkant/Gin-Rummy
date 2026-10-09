-- Layoff scene (client): shown to the player who did NOT knock. The knocker's melds are displayed and the
-- player drags cards of their hand onto them (a layoff) to reduce their deadwood; FINISH sends the result.
-- load() receives the knocker's melds (lists of card names) and our hand cards from the game scene. The
-- scene is left with SceneManager.set("game"), so the game scene keeps its state and then receives the
-- round_result. Network messages are not consumed here (see Scene.update).

require 'card'
require 'cards_database'
require 'best_melds'

local love = require "love"
local network = require "network"

local Scene = {}

-- The knocker's melds: each {cards = {Card, ...}, x, y, width, height}; the geometry is set by
-- compute_layout.
local knocker_melds = {}
-- Our hand in this scene: textured copies of the hand cards; laid off cards are removed.
local my_cards = {}
-- Layoffs made so far, in order: {card = "<name>", meld_index = n}. Sent as finish_layoff.layoffs. The
-- order matters: the server replays it on its own copy of the melds, where each accepted card extends its
-- meld.
local laid_off = {}

-- Drag state: the dragged card and where it was grabbed; hovered_card is the hand card lifted by the
-- cursor.
local dragging_card
local drag_offset_x
local drag_offset_y
local hovered_card

local FINISH_BUTTON_WIDTH = 200
local FINISH_BUTTON_HEIGHT = 50
local finish_button_x
local finish_button_y
local font

-- Speed (pixels per second) at which cards slide to their targets.
local SPEED = 1000

-- Creates scaled Card objects (with textures) for a list of card names.
local function build_meld_cards(names)
    local cards = {}
    for _, name in ipairs(names) do
        local card = get_card(name)
        card:set_scale(scale / ASSET_RESOLUTION_FACTOR, scale / ASSET_RESOLUTION_FACTOR)
        table.insert(cards, card)
    end
    return cards
end

-- Computes each card's target position; the movement itself happens smoothly in Scene.update via
-- card:move_to, except right after Scene.load, where the cards are snapped straight to their target
-- (see snap_to_target). Melds are stacked from the top, one row per meld and centred; the hand is a row at
-- the bottom.
local function compute_layout()
    local w = love.graphics.getWidth()
    local h = love.graphics.getHeight()

    -- Y of the first meld row.
    local top_y = 100

    local card_h = 0
    if #knocker_melds > 0 then
        card_h = knocker_melds[1].cards[1]:get_height()
    end
    -- Vertical distance between meld rows: a card height plus a gap.
    local meld_spacing_y = card_h + 20

    for i, meld in ipairs(knocker_melds) do
        local card_w = meld.cards[1]:get_width()
        -- Cards of a meld are shifted by 55 % of a card width, so neighbours overlap by 45 %.
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
        -- Hand cards overlap less (shifted by 65 % of a card width) than the melds.
        local overlap = card_w * 0.65
        local total_width = overlap * (#my_cards - 1) + card_w
        local start_x = w / 2 - total_width / 2
        local hand_y = h - 220

        for i, card in ipairs(my_cards) do
            local target_y = hand_y
            -- The hovered card is lifted by a sixth of its height.
            if card == hovered_card then
                target_y = target_y - card:get_height() / 6
            end

            card.target_x = start_x + (i - 1) * overlap
            card.target_y = target_y
            -- rest_y is the position without the lift; hit testing uses it (see get_hand_card_at).
            card.rest_y = hand_y
        end
    end

    finish_button_x = w / 2 - FINISH_BUTTON_WIDTH / 2
    finish_button_y = h - 90
end

-- Puts every card exactly on its target (used once after loading, so nothing flies in at the start).
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

-- True if (x, y) is on the FINISH button.
local function is_point_in_finish_button(x, y)
    return x >= finish_button_x and x <= finish_button_x + FINISH_BUTTON_WIDTH and
           y >= finish_button_y and y <= finish_button_y + FINISH_BUTTON_HEIGHT
end

-- Returns the index of the knocker's meld under (x, y), or nil. The drop area is the meld's rectangle
-- enlarged by 25 pixels on each side to make dropping easier.
local function find_meld_at(x, y)
    for i, meld in ipairs(knocker_melds) do
        if x >= meld.x - 25 and x <= meld.x + meld.width + 25 and
           y >= meld.y - 25 and y <= meld.y + meld.height + 25 then
            return i
        end
    end
    return nil
end

-- True once FINISH was pressed or the game ended; then nothing more is sent or updated.
local finished = false

-- Sends the layoffs to the server and returns to the game scene, which will show the round result.
local function finish()
    finished = true
    network.send({type = "finish_layoff", layoffs = laid_off})
    SceneManager.set("game")
end

-- Scene entry, called by SceneManager.switch("layoff", combinations, hand_cards) from the game scene.
-- combinations: the knocker's melds as lists of card names; my_hand_cards: the Card objects of our hand.
-- Everything is rebuilt from scratch with fresh textured copies of the hand.
function Scene.load(combinations, my_hand_cards)
    font = love.graphics.newFont("ArchivoBlack-Regular.ttf")

    knocker_melds = {}
    for _, meld_names in ipairs(combinations) do
        table.insert(knocker_melds, {cards = build_meld_cards(meld_names)})
    end

    my_cards = {}
    for _, card in ipairs(my_hand_cards) do
        local copy = get_card(card.rank .. "_" .. card.suit)
        copy:set_scale(scale / ASSET_RESOLUTION_FACTOR, scale / ASSET_RESOLUTION_FACTOR)
        table.insert(my_cards, copy)
    end

    dragging_card = nil
    hovered_card = nil
    laid_off = {}
    finished = false

    compute_layout()
    snap_to_target()
end

-- Left button: FINISH, or the start of dragging a hand card (the topmost one under the cursor).
function Scene.mousepressed(x, y, button)
    if button ~= 1 then return end

    if is_point_in_finish_button(x, y) then
        finish()
        return
    end

    if dragging_card == nil then
        for i = #my_cards, 1, -1 do
            local card = my_cards[i]
            if card:mousepressed(x, y) then
                dragging_card = card
                local cx, cy = card:get_position()
                drag_offset_x = x - cx
                drag_offset_y = y - cy
                break
            end
        end
    end
end

-- Dropping: if the card is released over a meld that it extends into a valid set or run, it joins that meld
-- (locally and in `laid_off`) and leaves the hand. Otherwise it slides back to the hand. A meld that grew
-- can be extended further by later cards.
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

-- The dragged card follows the cursor, keeping the grab offset.
function Scene.mousemoved(x, y)
    if dragging_card then
        dragging_card:set_position(x - drag_offset_x, y - drag_offset_y)
    end
end


-- Returns the hand card under (x, y), or nil. Like PlayerHand:get_card_at it tests the REST position
-- (rest_y), not the lifted one, so the lifted card does not flicker; `current` is the card that is hovered
-- now and also owns the strip it was lifted over.
local function get_hand_card_at(x, y, current)
    for i = #my_cards, 1, -1 do
        local card = my_cards[i]
        if card.target_x and card.rest_y and
           x >= card.target_x and x <= card.target_x + card:get_width() and
           y >= card.rest_y and y <= card.rest_y + card:get_height() then
            return card
        end
    end

    if current and current.target_x and current.rest_y then
        local lift = current:get_height() / 6
        if x >= current.target_x and x <= current.target_x + current:get_width() and
           y >= current.rest_y - lift and y < current.rest_y then
            return current
        end
    end

    return nil
end

-- Per frame: hover, layout and card movement. The network is polled only to notice that the game ended or
-- the connection was lost; then we return to the game scene, which shows the outcome.
function Scene.update(dt)
    if finished then return end

    if dragging_card == nil then
        local mx, my = love.mouse.getPosition()
        hovered_card = get_hand_card_at(mx, my, hovered_card)
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

    -- messages stay in the shared inbox for the game scene; here we only watch for the game ending
    -- (e.g. the knocker left) so FINISH isn't sent into a game that no longer exists
    network.poll()
    if not network.is_connected() or network.has_message("game_over") then
        finished = true
        SceneManager.set("game")
    end
end

-- Draws the title, the melds, our hand, the dragged card on top and the FINISH button.
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
