-- Layoff scene (client): shown to BOTH players after a knock that is not a gin. The round is decided, so
-- every card is face up: at the top the knocker's melds (outlined) and leftover cards, at the bottom the
-- defender's hand. The defender drags cards onto the melds to reduce their deadwood and presses FINISH; each
-- placement goes to the server at once (layoff_card) and the knocker sees the same card slide from the
-- defender's hand onto the meld (opponent_layoff). Both leave when the round_result arrives. load() gets the
-- layoff_phase message (protocol: top of server.lua). The scene is left with SceneManager.set("game"), so
-- the game scene keeps its state and then shows the round_result.

require 'card'
require 'cards_database'
require 'best_melds'
require 'shaders'

local love = require "love"
local network = require "network"
local ui = require "ui"
local felt = require "client/felt"
local layout = require "client/layout"
local sounds = require "client/sounds"

local Scene = {}

-- "knocker" or "defender": the defender is the one who can move cards.
local role

-- The knocker's melds: each {cards = {Card, ...}, x, y, width, height}; the geometry is set by
-- compute_layout.
local melds = {}
-- The knocker's leftover cards, in the same shape as a meld (but nothing can be laid onto them).
local leftovers = {cards = {}}
-- The defender's hand as Card objects; laid off cards leave it. hand_meld_of[card] is the number of the
-- meld of the hand's best arrangement the card belongs to (nil for deadwood); it sets the outline colour.
local hand = {}
local hand_meld_of = {}

-- Drag state: the dragged card and where it was grabbed; hovered_card is the hand card lifted by the
-- cursor.
local dragging_card
local drag_offset_x
local drag_offset_y
local hovered_card

-- The defender pressed FINISH: nothing can be moved any more while the score is counted.
local is_submitted = false
-- The scene was left (the game scene runs again); nothing is updated after that.
local is_left = false

-- Cards here are a bit smaller than on the table so that three melds, the leftovers and the hand fit.
local CARD_SCALE_FACTOR = 0.85
-- Horizontal shift between neighbouring cards of a meld as a part of the card width; it shrinks (down to
-- MIN_MELD_OVERLAP) when the top row would not fit the window.
local MELD_OVERLAP = 0.55
local MIN_MELD_OVERLAP = 0.25
-- Gap between two groups (meld / leftovers) in the top row, in pixels.
local GROUP_GAP = 60
-- Y of the top row and the distance between the bottom row and the window bottom.
local TOP_Y = 110
local BOTTOM_MARGIN = 110
-- Hand cards are shifted by this part of the card width.
local HAND_OVERLAP = 0.65
-- A meld counts as hit by a drop when the cursor is within this many pixels of its rectangle.
local DROP_MARGIN = 25

local FINISH_BUTTON_WIDTH = 200
local FINISH_BUTTON_HEIGHT = 50
local FINISH_COLOR = {0.3, 0.6, 0.3, 1}
local finish_button

local title_font
local label_font

-- Creates a textured card for a card name, at this scene's scale.
local function new_card(name)
    local card = get_card(name)
    local card_scale = layout.card_scale() * CARD_SCALE_FACTOR
    card:set_scale(card_scale, card_scale)
    return card
end

-- Creates the cards for a list of names, in the same order.
local function new_cards(names)
    local cards = {}
    for _, name in ipairs(names) do
        table.insert(cards, new_card(name))
    end
    return cards
end

-- Orders cards by rank and suit. Melds keep this order so a run reads left to right after a layoff.
local function sort_cards(cards)
    table.sort(cards, function(a, b) return a:is_lesser_than(b) end)
end

-- Calls fn(card) for every card of the scene: melds, leftovers, then the hand.
local function each_card(fn)
    for _, meld in ipairs(melds) do
        for _, card in ipairs(meld.cards) do fn(card) end
    end
    for _, card in ipairs(leftovers.cards) do fn(card) end
    for _, card in ipairs(hand) do fn(card) end
end

-- Arranges the hand like the player's own hand on the table: finds the best meld arrangement, puts the
-- melded cards first (meld 1, 2, 3, each sorted) and the deadwood after them by rank and suit, and
-- remembers which meld each card is in (hand_meld_of). Called whenever the hand changes.
local function arrange_hand()
    hand_meld_of = {}
    sort_cards(hand)
    if #hand == 0 then return end

    local arrangements = best_combinations(hand)
    for i, meld in ipairs(arrangements[1]) do
        for _, card in ipairs(meld) do
            hand_meld_of[card] = i
        end
    end

    table.sort(hand, function(a, b)
        -- Priority 4 puts deadwood after the (at most three) melds.
        local priority_a = hand_meld_of[a] or 4
        local priority_b = hand_meld_of[b] or 4

        if priority_a ~= priority_b then
            return priority_a < priority_b
        end

        return a:is_lesser_than(b)
    end)
end

-- Returns the width of the top row (all groups side by side) for a given overlap factor.
local function get_top_row_width(groups, card_w, overlap_factor)
    local width = GROUP_GAP * (#groups - 1)
    for _, group in ipairs(groups) do
        width = width + card_w * overlap_factor * (#group.cards - 1) + card_w
    end
    return width
end

-- Computes each card's target position; the movement itself happens smoothly in Scene.update via
-- card:move_to (this is also what makes a laid-off card fly onto its meld). Top row: the melds and then the
-- leftovers, centred; bottom row: the hand.
local function compute_layout()
    local w = love.graphics.getWidth()
    local h = love.graphics.getHeight()

    local groups = {}
    for _, meld in ipairs(melds) do table.insert(groups, meld) end
    if #leftovers.cards > 0 then table.insert(groups, leftovers) end

    local sample = groups[1].cards[1]
    local card_w = sample:get_width()
    local card_h = sample:get_height()

    -- Squeeze the melds together until the whole row fits the window.
    local overlap_factor = MELD_OVERLAP
    while overlap_factor > MIN_MELD_OVERLAP and get_top_row_width(groups, card_w, overlap_factor) > w - 80 do
        overlap_factor = overlap_factor - 0.05
    end

    local x = (w - get_top_row_width(groups, card_w, overlap_factor)) / 2
    for _, group in ipairs(groups) do
        group.x = x
        group.y = TOP_Y
        group.width = card_w * overlap_factor * (#group.cards - 1) + card_w
        group.height = card_h

        for j, card in ipairs(group.cards) do
            card.target_x = group.x + (j - 1) * card_w * overlap_factor
            card.target_y = group.y
        end

        x = x + group.width + GROUP_GAP
    end

    if #hand > 0 then
        local step = card_w * HAND_OVERLAP
        local start_x = (w - (step * (#hand - 1) + card_w)) / 2
        local hand_y = h - card_h - BOTTOM_MARGIN

        for i, card in ipairs(hand) do
            local target_y = hand_y
            -- The hovered card is lifted by a sixth of its height.
            if card == hovered_card then
                target_y = target_y - card:get_height() / 6
            end

            card.target_x = start_x + (i - 1) * step
            card.target_y = target_y
            -- rest_y is the position without the lift; hit testing uses it (see get_hand_card_at).
            card.rest_y = hand_y
        end
    end

    finish_button = {
        x = w / 2 - FINISH_BUTTON_WIDTH / 2,
        y = h - 80,
        w = FINISH_BUTTON_WIDTH,
        h = FINISH_BUTTON_HEIGHT
    }
end

-- Puts every card exactly on its target (used once after loading, so nothing flies in at the start).
local function snap_to_target()
    each_card(function(card)
        card:set_position(card.target_x, card.target_y)
    end)
end

-- True when no card is still sliding to its place.
local function are_cards_settled()
    local settled = true
    each_card(function(card)
        if card.x ~= card.target_x or card.y ~= card.target_y then
            settled = false
        end
    end)
    return settled
end

-- Returns the index of the knocker's meld under (x, y), or nil. The drop area is the meld's rectangle
-- enlarged by DROP_MARGIN to make dropping easier.
local function find_meld_at(x, y)
    for i, meld in ipairs(melds) do
        if x >= meld.x - DROP_MARGIN and x <= meld.x + meld.width + DROP_MARGIN and
           y >= meld.y - DROP_MARGIN and y <= meld.y + meld.height + DROP_MARGIN then
            return i
        end
    end
    return nil
end

-- Returns the hand card under (x, y), or nil. Like PlayerHand:get_card_at it tests the REST position
-- (rest_y), not the lifted one, so the lifted card does not flicker; `current` is the card that is hovered
-- now and also owns the strip it was lifted over.
local function get_hand_card_at(x, y, current)
    for i = #hand, 1, -1 do
        local card = hand[i]
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

-- Moves `card` from the hand onto the end of meld `meld_index` (the layout then slides it there) and keeps
-- the meld in rank order. Returns false if the hand or the meld does not exist.
local function move_card_to_meld(card, meld_index)
    local meld = melds[meld_index]
    if meld == nil then return false end

    for i, hand_card in ipairs(hand) do
        if hand_card == card then
            table.remove(hand, i)
            break
        end
    end

    table.insert(meld.cards, card)
    sort_cards(meld.cards)
    arrange_hand()
    return true
end

-- Leaves the scene: the game scene continues with its own state and shows the outcome.
local function leave()
    is_left = true

    -- a correction that came too late must not rebuild the next layoff scene
    while network.take("layoff_sync") do end

    SceneManager.set("game")
end

-- The knocker's side: the defender laid `message.card` onto meld `message.meld_index`. The matching card
-- of the displayed defender's hand moves to the meld, which shows as a flight across the screen.
local function apply_opponent_layoff(message)
    for _, card in ipairs(hand) do
        if card.rank .. "_" .. card.suit == message.card then
            move_card_to_meld(card, message.meld_index)
            return
        end
    end
end

-- Scene entry, called by SceneManager.switch("layoff", layoff_phase_message) from the game scene.
-- Everything is rebuilt from scratch with fresh textured cards.
function Scene.load(info)
    if title_font == nil then
        title_font = love.graphics.newFont("ArchivoBlack-Regular.ttf", 28)
        label_font = love.graphics.newFont("ArchivoBlack-Regular.ttf", 22)
    end

    role = info.role

    melds = {}
    for _, meld_names in ipairs(info.combinations) do
        table.insert(melds, {cards = new_cards(meld_names)})
    end
    for _, meld in ipairs(melds) do sort_cards(meld.cards) end

    leftovers = {cards = new_cards(info.knocker_deadwood)}
    sort_cards(leftovers.cards)

    hand = new_cards(info.defender_hand)
    arrange_hand()

    dragging_card = nil
    hovered_card = nil
    is_submitted = false
    is_left = false

    compute_layout()
    snap_to_target()
end

-- Re-lays out after a window resize: the cards take the new scale and slide to their new places.
function Scene.resize()
    local card_scale = layout.card_scale() * CARD_SCALE_FACTOR
    each_card(function(card)
        card:set_scale(card_scale, card_scale)
    end)

    compute_layout()
end

-- Left button (defender only): FINISH, or the start of dragging a hand card (the topmost one under the
-- cursor).
function Scene.mousepressed(x, y, button)
    if button ~= 1 or is_submitted or is_left then return end

    -- The knocker has nothing to move: grabbing a card is an invalid move.
    if role ~= "defender" then
        if get_hand_card_at(x, y, nil) ~= nil then
            sounds.play_failure()
        end
        return
    end

    if ui.point_in_rect(x, y, finish_button) then
        is_submitted = true
        dragging_card = nil
        network.send({type = "finish_layoff"})
        return
    end

    if dragging_card == nil then
        for i = #hand, 1, -1 do
            local card = hand[i]
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

-- Dropping: if the card is released over a meld that it extends into a valid set or run, it joins that
-- meld at once and the server is told (layoff_card). Otherwise it slides back to the hand. A meld that grew
-- can be extended further by later cards.
function Scene.mousereleased(x, y, button)
    if button ~= 1 or dragging_card == nil then return end

    local card = dragging_card
    local meld_index = find_meld_at(x, y)

    if meld_index ~= nil and can_extend_meld(card, melds[meld_index].cards) then
        network.send({type = "layoff_card", card = card.rank .. "_" .. card.suit, meld_index = meld_index})
        move_card_to_meld(card, meld_index)
    elseif meld_index ~= nil then
        -- dropped on a meld that the card does not fit
        sounds.play_failure()
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

-- Per frame: hover, layout and card movement, then the network. The scene watches for the end of the round
-- (round_result, once the last card has landed) or of the game (game_over, connection lost) and returns to
-- the game scene, which shows the outcome. Its messages stay in the shared inbox for it.
function Scene.update(dt)
    if is_left then return end

    if dragging_card == nil and role == "defender" and not is_submitted then
        local mx, my = love.mouse.getPosition()
        hovered_card = get_hand_card_at(mx, my, hovered_card)
    else
        hovered_card = nil
    end

    compute_layout()

    each_card(function(card)
        if card ~= dragging_card then
            card:move_to(dt, layout.CARD_SPEED, card.target_x, card.target_y)
        end
    end)

    network.poll()

    -- The defender's layoffs arrive as separate messages; the cards fly one after another.
    local message = network.take("opponent_layoff")
    while message do
        apply_opponent_layoff(message)
        message = network.take("opponent_layoff")
    end

    -- The server refused a layoff we had applied at once and sends the real melds and hands: the scene is
    -- built again from them (the last of several corrections is the one that counts).
    local correction = network.take("layoff_sync")
    while correction do
        local newer = network.take("layoff_sync")
        if newer == nil then
            Scene.load(correction)
            sounds.play_failure()
            return
        end
        correction = newer
    end

    if not network.is_connected() or network.has_message("game_over") then
        leave()
    elseif network.has_message("round_result") and are_cards_settled() then
        leave()
    end
end

-- True if `card` is in the hand (not in a meld or the leftovers).
local function is_in_hand(card)
    for _, hand_card in ipairs(hand) do
        if hand_card == card then return true end
    end
    return false
end

-- Draws a card of the hand the way the table draws it: melded cards with the outline of their meld, the
-- deadwood with the plain shimmer. Leaves the shader set (draw_group and Scene.draw reset it).
local function draw_hand_card(card)
    local meld_index = hand_meld_of[card]

    if meld_index then
        love.graphics.setShader(highlight_card_shader)
        highlight_card_shader:send("time", love.timer.getTime())
        highlight_card_shader:send("highlight_color", combination_colors[meld_index])
    else
        love.graphics.setShader(card_shader)
        card_shader:send("time", love.timer.getTime())
    end

    card:draw(true)
end

-- Draws a group of cards with the outline shader in the colour of its meld (nil index: no outline).
local function draw_group(group, meld_index)
    if meld_index then
        love.graphics.setShader(highlight_card_shader)
        highlight_card_shader:send("time", love.timer.getTime())
        highlight_card_shader:send("highlight_color", combination_colors[meld_index])
    end

    for _, card in ipairs(group.cards) do
        if card ~= dragging_card and card.x == card.target_x and card.y == card.target_y then
            card:draw(true)
        end
    end

    love.graphics.setShader()
end

-- Draws the table (both hands are open, so both are lit), the captions, the settled cards (melds
-- outlined), the cards that are still flying and the dragged card on top of everything, and the FINISH
-- button for the defender.
function Scene.draw()
    felt.draw(felt.OPEN_LIGHTS)

    local w = love.graphics.getWidth()
    local top_caption, bottom_caption, title

    if role == "defender" then
        title = is_submitted and "Counting the score..." or "Drag your cards onto the melds to lay them off"
        top_caption = "Opponent's cards"
        bottom_caption = "Your hand"
    else
        title = "Your opponent is laying off cards onto your melds..."
        top_caption = "Your cards"
        bottom_caption = "Opponent's hand"
    end

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setFont(title_font)
    love.graphics.printf(title, 0, 30, w, "center")

    love.graphics.setFont(label_font)
    love.graphics.printf(top_caption, 0, TOP_Y - 34, w, "center")
    if #hand > 0 then
        love.graphics.printf(bottom_caption, 0, hand[1].rest_y - 34, w, "center")
    end

    for i, meld in ipairs(melds) do
        draw_group(meld, i)
    end
    draw_group(leftovers, nil)
    for _, card in ipairs(hand) do
        if card ~= dragging_card and card.x == card.target_x and card.y == card.target_y then
            draw_hand_card(card)
        end
    end
    love.graphics.setShader()

    -- Cards in flight are drawn over the settled ones, the dragged card over everything. Cards of the hand
    -- keep their outline while they slide to a new place.
    each_card(function(card)
        if card ~= dragging_card and (card.x ~= card.target_x or card.y ~= card.target_y) then
            if is_in_hand(card) then
                draw_hand_card(card)
                love.graphics.setShader()
            else
                card:draw(true)
            end
        end
    end)

    if dragging_card ~= nil then
        draw_hand_card(dragging_card)
        love.graphics.setShader()
    end

    if role == "defender" and not is_submitted then
        love.graphics.setFont(label_font)
        ui.draw_button(finish_button, "FINISH", FINISH_COLOR)
    end

    love.graphics.setColor(1, 1, 1, 1)
end

return Scene
