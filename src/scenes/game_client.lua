require 'card'
require 'deck'
require 'player_hand'
require 'opponent_hand'
require 'discard_pile'
require 'shaders'
require 'cards_database'

local enet = require "enet"
local love = require "love"
local json = require "dkjson"

local Scene = {}

local host
local server

local deck
local discard_pile
local player_hand
local opponent_hand
local back_card_texture
local deck_texture
local white_pixel
local dragging_card
local drag_offset_x
local drag_offset_y
local hovered_card
local opponent_card_reference
local new_card_in_discard_pile
local movable_card_from_opponent_to_discard_pile

local OPPONENT_Y_FRACTION = 100 / 1080
local HAND_Y_FRACTION = 750 / 1080
local OPPONENT_Y_POSITION
local HAND_Y_POSITION
local SPEED = 1000
local CARD_HEIGHT

local KNOCK_BUTTON_WIDTH = 140
local KNOCK_BUTTON_HEIGHT = 50
local knock_button_x
local knock_button_y

local LAMP_RADIUS = 16
local MAX_HAND_CARDS = 11

local is_my_turn = false
local is_game_over = false
local round_result
local round_result_timer = 0
local game_over_info
local my_total_score = 0
local opponent_total_score = 0
local waiting_for_layoff = false

local rematch_response_sent = false
local rematch_declined_by_me = false
local opponent_left = false
local disconnected_from_server = false

local LEAVE_DELAY = 3
local leave_timer = 0

local REMATCH_BUTTON_WIDTH = 140
local REMATCH_BUTTON_HEIGHT = 50

local is_paused = false
local PAUSE_BUTTON_WIDTH = 260
local PAUSE_BUTTON_HEIGHT = 50

local pending_messages = {}
local knock_discard_anim
local KNOCK_PAUSE_DURATION = 2
local knock_pause_timer = 0
local flash_pending = false
local has_started_first_game = false

local font
local number_font
local gin_font
local round_result_font

local function update_hand_positions(h)
    OPPONENT_Y_POSITION = h * OPPONENT_Y_FRACTION
    HAND_Y_POSITION = h * HAND_Y_FRACTION
end

function Scene.load(ip)
    host = enet.host_create()
    server = host:connect(ip)

    pending_messages = {}
    knock_discard_anim = nil
    knock_pause_timer = 0
    flash_pending = false
    has_started_first_game = false
    leave_timer = 0

    font = love.graphics.newFont("ArchivoBlack-Regular.ttf")
    number_font = love.graphics.newFont("ArchivoBlack-Regular.ttf", 28)
    gin_font = love.graphics.newFont("ArchivoBlack-Regular.ttf", 48)
    round_result_font = love.graphics.newFont("ArchivoBlack-Regular.ttf", 20)

	back_card_texture = love.graphics.newImage("assets/back_flipped.png")
    local card_slot_texture = love.graphics.newImage("assets/card_slot.png")
    deck_texture = love.graphics.newImage("assets/deck.png")

    back_card_texture:setFilter("nearest", "nearest")
    card_slot_texture:setFilter("nearest", "nearest")
    deck_texture:setFilter("nearest", "nearest")

    local pixel_data = love.image.newImageData(1, 1)
    pixel_data:setPixel(0, 0, 1, 1, 1, 1)
    white_pixel = love.graphics.newImage(pixel_data)

    update_hand_positions(love.graphics.getHeight())

    deck = Deck(100, 0, deck_texture, scale, scale)
    discard_pile = DiscardPile(0, 0, card_slot_texture, scale, scale)
    player_hand = PlayerHand(love.graphics.getWidth() / 2, HAND_Y_POSITION)
    opponent_hand = OpponentHand(love.graphics.getWidth() / 2, OPPONENT_Y_POSITION)
    opponent_card_reference = Card("A", "heart", 0, 0, back_card_texture, scale, scale)

    -- set discard pile in the center
    discard_pile.x = love.graphics.getWidth() / 2 - discard_pile:get_width() / 2
    discard_pile.y = love.graphics.getHeight() / 2 - discard_pile:get_heigth() / 2

    deck.y = love.graphics.getHeight() / 2 - deck_texture:getHeight() * scale / 2

    CARD_HEIGHT = back_card_texture:getHeight() * scale

    knock_button_x = love.graphics.getWidth() - KNOCK_BUTTON_WIDTH - 30
    knock_button_y = HAND_Y_POSITION + CARD_HEIGHT / 2 - KNOCK_BUTTON_HEIGHT / 2
end

function Scene.resize(w, h)
    if deck == nil then return end

    update_hand_positions(h)

    deck.scaleX = scale
    deck.scaleY = scale
    discard_pile.scaleX = scale
    discard_pile.scaleY = scale
    opponent_card_reference:set_scale(scale, scale)

    player_hand.x = w / 2
    player_hand.y = HAND_Y_POSITION
    opponent_hand.x = w / 2
    opponent_hand.y = OPPONENT_Y_POSITION

    discard_pile.x = w / 2 - discard_pile:get_width() / 2
    discard_pile.y = h / 2 - discard_pile:get_heigth() / 2
    deck.y = h / 2 - deck_texture:getHeight() * scale / 2

    CARD_HEIGHT = back_card_texture:getHeight() * scale
    knock_button_x = w - KNOCK_BUTTON_WIDTH - 30
    knock_button_y = HAND_Y_POSITION + CARD_HEIGHT / 2 - KNOCK_BUTTON_HEIGHT / 2

    for _, card in ipairs(player_hand.cards) do
        card:set_scale(scale, scale)
    end

    for _, card in ipairs(opponent_hand.cards) do
        card:set_scale(scale, scale)
    end

    if discard_pile.hightest_card ~= nil then
        discard_pile.hightest_card:set_scale(scale, scale)
    end

    if discard_pile.second_highest_card ~= nil then
        discard_pile.second_highest_card:set_scale(scale, scale)
    end
end

local function copy(original)
    local copy_t = {}
    for key, value in pairs(original) do
        copy_t[key] = value
    end
    return copy_t
end

local function get_lamp_x()
    local card_width = back_card_texture:getWidth() * scale
    local max_hand_half_width = (card_width / 1.5) * MAX_HAND_CARDS / 2 + card_width / 2
    return love.graphics.getWidth() / 2 - max_hand_half_width - LAMP_RADIUS * scale - 30 * scale
end

local LAMP_GLOW_SCALE = 2

local function draw_turn_lamp(cx, cy, is_on)
    local radius = LAMP_RADIUS * scale
    local half = radius * LAMP_GLOW_SCALE

    love.graphics.setShader(lamp_shader)
    lamp_shader:send("time", love.timer.getTime())
    lamp_shader:send("is_on", is_on and 1 or 0)
    lamp_shader:send("lamp_color", {1, 0.75, 0.15})

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(white_pixel, cx - half, cy - half, 0, half * 2, half * 2)

    love.graphics.setShader()
end

local function handle_message(message)
    if message.type == "is_my_turn" then
        is_my_turn = message.answer
    elseif message.type == "update_discard_pile" then
        local card = get_card(message.card)
        discard_pile:add_card(card)
    elseif message.type == "opponent_get_card_from_deck" then
        local opponent_card_reference_copy = copy(opponent_card_reference)
        opponent_card_reference_copy.wobble_seed = love.math.random() * 2 * math.pi
        opponent_card_reference_copy:set_position(deck:get_position())
        opponent_hand:add_card(opponent_card_reference_copy)
    elseif message.type == "opponent_place_card_to_discard_pile" then
        movable_card_from_opponent_to_discard_pile = copy(opponent_card_reference)
        new_card_in_discard_pile = get_card(message.card)
        opponent_hand:remove_random_card()
    elseif message.type == "opponent_get_card_from_discrad_pile" then
        discard_pile:remove_top_card()
        local opponent_card_reference_copy = copy(opponent_card_reference)
        opponent_card_reference_copy.wobble_seed = love.math.random() * 2 * math.pi
        opponent_card_reference_copy:set_position(discard_pile:get_position())
        opponent_hand:add_card(opponent_card_reference_copy)
    elseif message.type == "get_card_from_deck" then
        local card = get_card(message.card)
        card:set_position(deck:get_position())
        card:set_scale(scale, scale)
        player_hand:add_card(card)
    elseif message.type == "new_round" then
        player_hand:reset()
        opponent_hand:reset()
        discard_pile:reset()
        is_my_turn = false
        round_result = nil
        round_result_timer = 0
        waiting_for_layoff = false
    elseif message.type == "waiting_for_layoff" then
        waiting_for_layoff = true
        is_my_turn = false
    elseif message.type == "layoff_phase" then
        SceneManager.switch("layoff", host, server, message.combinations, player_hand.cards)
    elseif message.type == "round_result" then
        round_result = message
        round_result_timer = 6
        my_total_score = message.your_total_score
        opponent_total_score = message.opponent_total_score
        is_my_turn = false
        waiting_for_layoff = false
    elseif message.type == "game_over" then
        game_over_info = message
        is_game_over = true
        is_my_turn = false
        rematch_response_sent = false
        rematch_declined_by_me = false
        opponent_left = false
        if message.opponent_disconnected then
            leave_timer = LEAVE_DELAY
        end
    elseif message.type == "opponent_declined_rematch" then
        opponent_left = true
        leave_timer = LEAVE_DELAY
    elseif message.type == "new_game" then
        player_hand:reset()
        opponent_hand:reset()
        discard_pile:reset()
        is_my_turn = false
        is_game_over = false
        game_over_info = nil
        round_result = nil
        round_result_timer = 0
        waiting_for_layoff = false
        my_total_score = 0
        opponent_total_score = 0
        rematch_response_sent = false
        rematch_declined_by_me = false
        opponent_left = false
        leave_timer = 0
    end
end


local function handle_knock_discard(message)
    local flying_card = copy(opponent_card_reference)

    if message.mine then
        local rank, suit = string.match(message.card, "^([%w]+)_([%a]+)$")
        for _, card in ipairs(player_hand.cards) do
            if card.rank == rank and card.suit == suit then
                local cx, cy = card:get_position()
                flying_card:set_position(cx, cy)
                break
            end
        end
        player_hand:remove_card(rank, suit)
    else
        opponent_hand:remove_random_card()
    end

    knock_discard_anim = flying_card
end

local function is_busy()
    return knock_discard_anim ~= nil or knock_pause_timer > 0 or round_result_timer > 0 or flash_pending
end

local function process_next_queued_message()
    if is_busy() or #pending_messages == 0 then return end

    local message = table.remove(pending_messages, 1)

    if message.type == "new_game" and not has_started_first_game then
        has_started_first_game = true
        handle_message(message)
    elseif message.type == "new_round" or message.type == "new_game" then
        flash_pending = true
        SceneManager.flash(function()
            handle_message(message)
            flash_pending = false
        end)
    else
        handle_message(message)
    end
end

local function evaluate_knock()
    if #player_hand.cards ~= 11 then
        return nil, player_hand.score
    end

    local discard_card = player_hand:get_knock_discard()
    if discard_card == nil then
        return nil, player_hand.score
    end

    local resulting_deadwood = player_hand.score - get_card_value(discard_card)
    if resulting_deadwood > 10 then
        return nil, resulting_deadwood
    end

    return discard_card, resulting_deadwood
end

local function is_knock_available()
    if not is_my_turn or is_game_over then return false end
    local discard_card = evaluate_knock()
    return discard_card ~= nil
end

local function is_point_in_knock_button(x, y)
    return x >= knock_button_x and x <= knock_button_x + KNOCK_BUTTON_WIDTH and
           y >= knock_button_y and y <= knock_button_y + KNOCK_BUTTON_HEIGHT
end

local function build_combinations_message()
    local combos = {}
    for _, meld in ipairs(player_hand:get_current_combination()) do
        local meld_names = {}
        for _, card in ipairs(meld) do
            table.insert(meld_names, card.rank .. "_" .. card.suit)
        end
        table.insert(combos, meld_names)
    end
    return combos
end

local function get_rematch_buttons()
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()
    local button_y = h / 2 + 10
    local spacing = 30
    local total_width = REMATCH_BUTTON_WIDTH * 2 + spacing
    local start_x = w / 2 - total_width / 2

    return {
        yes = {x = start_x, y = button_y, w = REMATCH_BUTTON_WIDTH, h = REMATCH_BUTTON_HEIGHT},
        no = {x = start_x + REMATCH_BUTTON_WIDTH + spacing, y = button_y, w = REMATCH_BUTTON_WIDTH, h = REMATCH_BUTTON_HEIGHT}
    }
end

local function is_point_in_rect(x, y, rect)
    return x >= rect.x and x <= rect.x + rect.w and y >= rect.y and y <= rect.y + rect.h
end

local function is_rematch_resolved()
    return rematch_response_sent or opponent_left or disconnected_from_server or
           (game_over_info ~= nil and game_over_info.opponent_disconnected)
end

local function get_pause_buttons()
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()
    local spacing = 20
    local row = PAUSE_BUTTON_HEIGHT + spacing
    local start_y = h / 2 - 10 - row

    return {
        fullscreen = {x = w / 2 - PAUSE_BUTTON_WIDTH / 2, y = start_y, w = PAUSE_BUTTON_WIDTH, h = PAUSE_BUTTON_HEIGHT},
        wobble = {x = w / 2 - PAUSE_BUTTON_WIDTH / 2, y = start_y + row, w = PAUSE_BUTTON_WIDTH, h = PAUSE_BUTTON_HEIGHT},
        quit = {x = w / 2 - PAUSE_BUTTON_WIDTH / 2, y = start_y + row * 2, w = PAUSE_BUTTON_WIDTH, h = PAUSE_BUTTON_HEIGHT}
    }
end

function Scene.mousepressed(x, y, button)
    if is_paused then
        if button ~= 1 then return end

        local buttons = get_pause_buttons()

        if is_point_in_rect(x, y, buttons.fullscreen) then
            love.window.setFullscreen(not love.window.getFullscreen())
        elseif is_point_in_rect(x, y, buttons.wobble) then
            WOBBLE_ENABLED = not WOBBLE_ENABLED
        elseif is_point_in_rect(x, y, buttons.quit) then
            love.event.quit()
        end

        return
    end

    if is_game_over then
        if button ~= 1 or is_rematch_resolved() then return end

        local buttons = get_rematch_buttons()

        if is_point_in_rect(x, y, buttons.yes) then
            rematch_response_sent = true
            server:send(json.encode({type = "rematch_response", answer = true}))
        elseif is_point_in_rect(x, y, buttons.no) then
            rematch_response_sent = true
            rematch_declined_by_me = true
            server:send(json.encode({type = "rematch_response", answer = false}))
            SceneManager.switch("menu")
        end

        return
    end

    if button == 2 then player_hand:increase_index_of_combination() end
    if button ~= 1 then return end

    if is_point_in_knock_button(x, y) then
        local discard_card = evaluate_knock()
        if is_my_turn and not is_game_over and discard_card ~= nil then
            server:send(json.encode({
                type = "knock",
                discard = discard_card.rank .. "_" .. discard_card.suit,
                combinations = build_combinations_message()
            }))
            is_my_turn = false
        end
        return
    end

    -- take card from deck
    if deck:mousepressed(x, y, button) and is_my_turn and #player_hand.cards == 10 then
        server:send(json.encode({type = "get_card_from_deck"}))
    -- take card from discard pile
    elseif discard_pile:mousepressed(x, y, button) then
        if is_my_turn and #player_hand.cards == 10 then
            local card = discard_pile:remove_top_card()
            if card ~= nil then
                player_hand:add_card(card)
                server:send(json.encode({type = "get_card_from_discrad_pile"}))
            end
        end
    -- dragging card
    elseif dragging_card == nil then
        for i = #player_hand.cards, 1, -1 do
            local card = player_hand.cards[i]
            if card:mousepressed(x, y, button) then
                dragging_card = card
                local card_x, card_y = card:get_position()
                drag_offset_x = x - card_x
                drag_offset_y = y - card_y
                break
            end
        end
    end
end


function Scene.mousereleased(x, y, button)
    -- move card to discard pile
    if dragging_card ~= nil and discard_pile:mousepressed(x, y, button) and is_my_turn and #player_hand.cards == 11  then
        server:send(json.encode({type = "put_card_to_discrad_pile", card = dragging_card.rank .. "_" .. dragging_card.suit}))

        discard_pile:add_card(dragging_card)
        player_hand:remove_card(dragging_card.rank, dragging_card.suit)

        is_my_turn = false
    end

    if button == 1 then dragging_card = nil end
end

function Scene.keypressed(key)
    if key == "escape" and not is_game_over then
        is_paused = not is_paused
    end
end

function Scene.mousemoved(x, y, dx, dy)
    if hovered_card ~= nil and not hovered_card:mousehover(x, y) then
            hovered_card = nil
    end

    if dragging_card then
        dragging_card:set_position(x - drag_offset_x, y - drag_offset_y)
    end
end


function Scene.update(dt)
    local mx, my = love.mouse.getPosition()

    player_hand:update(dt, SPEED, dragging_card, hovered_card)
    opponent_hand:update(dt, SPEED, dragging_card, hovered_card)
    deck:update(mx, my)
    discard_pile:update(mx, my)

    if round_result_timer > 0 then
        round_result_timer = round_result_timer - dt
        if round_result_timer <= 0 then
            round_result_timer = 0
            round_result = nil
        end
    end

    if leave_timer > 0 then
        leave_timer = leave_timer - dt
        if leave_timer <= 0 then
            leave_timer = 0
            if server then
                server:disconnect()
            end
            SceneManager.switch("menu")
        end
    end

    -- move card from opponent hand to discard pile
    if movable_card_from_opponent_to_discard_pile ~= nil then
        movable_card_from_opponent_to_discard_pile:move_to(dt, SPEED, discard_pile:get_position())
        if movable_card_from_opponent_to_discard_pile:get_position() == discard_pile:get_position() then
            movable_card_from_opponent_to_discard_pile = nil
            discard_pile:add_card(new_card_in_discard_pile)
            new_card_in_discard_pile = nil
        end
    end

    -- knock discard: card flies face-down to the pile, then a suspense pause
    if knock_discard_anim ~= nil then
        knock_discard_anim:move_to(dt, SPEED, discard_pile:get_position())
        if knock_discard_anim:get_position() == discard_pile:get_position() then
            discard_pile:add_card(knock_discard_anim)
            knock_discard_anim = nil
            knock_pause_timer = KNOCK_PAUSE_DURATION
        end
    elseif knock_pause_timer > 0 then
        knock_pause_timer = knock_pause_timer - dt
        if knock_pause_timer < 0 then knock_pause_timer = 0 end
    end

    process_next_queued_message()

    -- find hovered card
    if not dragging_card then
        local mx, my = love.mouse.getPosition()
        for i = #player_hand.cards, 1, -1 do
            local card = player_hand.cards[i]
            if card:mousepressed(mx, my, 1) then
                hovered_card = card
                break
            end
        end
    end

    -- get message from server
    local event = host:service(0)

    while event do
        if event.type == "connect" then
            print("Connected to server!")
        elseif event.type == "disconnect" then
            disconnected_from_server = true
        elseif event.type == "receive" then
            local message = json.decode(event.data)
            if message ~= nil and message.type == "knock_discard" then
                handle_knock_discard(message)
            elseif message ~= nil then
                table.insert(pending_messages, message)
            end
        end

        event = host:service(0)
    end
end


function Scene.draw()
    -- poker table color
    love.graphics.setColor(love.math.colorFromBytes(53, 101, 77, 255))

    love.graphics.rectangle(
        "fill",
        0,
        0,
        love.graphics.getWidth(),
        love.graphics.getHeight()
    )

    love.graphics.setShader()
    love.graphics.setColor(1, 1, 1, 1)

    deck:draw()

    discard_pile:draw()

    local lamp_x = get_lamp_x()
    draw_turn_lamp(lamp_x, OPPONENT_Y_POSITION + CARD_HEIGHT / 2, not is_my_turn and not is_game_over)
    draw_turn_lamp(lamp_x, HAND_Y_POSITION + CARD_HEIGHT / 2, is_my_turn)

    player_hand:draw(dragging_card, hovered_card)

    if movable_card_from_opponent_to_discard_pile ~= nil then
        movable_card_from_opponent_to_discard_pile:draw()
    end

    if knock_discard_anim ~= nil then
        knock_discard_anim:draw()
    end

    opponent_hand:draw()

    local knock_available = is_knock_available()
    if knock_available then
        love.graphics.setColor(0.8, 0.2, 0.2, 1)
    else
        love.graphics.setColor(0.4, 0.4, 0.4, 0.6)
    end

    love.graphics.setFont(font)

    love.graphics.rectangle("fill", knock_button_x, knock_button_y, KNOCK_BUTTON_WIDTH, KNOCK_BUTTON_HEIGHT, 8, 8)

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.printf("KNOCK", knock_button_x, knock_button_y + KNOCK_BUTTON_HEIGHT / 2 - 8, KNOCK_BUTTON_WIDTH, "center")

    local _, display_deadwood = evaluate_knock()
    love.graphics.printf("Deadwood: " .. tostring(display_deadwood), knock_button_x, knock_button_y - 24, KNOCK_BUTTON_WIDTH, "center")

    love.graphics.setColor(1, 1, 1, 1)

    love.graphics.setFont(number_font)

    love.graphics.printf(opponent_total_score, 0, OPPONENT_Y_POSITION - 30 * scale, love.graphics.getWidth(), "center")
    love.graphics.printf(my_total_score, 0, HAND_Y_POSITION + CARD_HEIGHT + 15 * scale, love.graphics.getWidth(), "center")

    if round_result ~= nil then
        local w, h = 520, 240
        local px, py = love.graphics.getWidth() / 2 - w / 2, love.graphics.getHeight() / 2 - h / 2

        if round_result.is_gin then
            love.graphics.setFont(gin_font)
            love.graphics.setColor(1, 0.85, 0.1, 1)
            love.graphics.printf(
                round_result.you_knocked and "YOU GOT GIN!" or "OPPONENT GOT GIN!",
                0, py - 70, love.graphics.getWidth(), "center")
        end

        love.graphics.setColor(0, 0, 0, 0.7)
        love.graphics.rectangle("fill", px, py, w, h, 10, 10)

        love.graphics.setFont(round_result_font)
        love.graphics.setColor(1, 1, 1, 1)

        local title
        if round_result.is_gin then
            title = round_result.you_knocked and "You scored big!" or "Better luck next time"
        elseif round_result.is_undercut then
            title = round_result.you_knocked and "Undercut! Opponent scored" or "You undercut the knocker!"
        else
            title = round_result.you_knocked and "You knocked!" or "Opponent knocked!"
        end

        love.graphics.printf(title, px, py + 20, w, "center")
        love.graphics.printf(
            "Your deadwood: " .. round_result.your_deadwood .. "   Opponent deadwood: " .. round_result.opponent_deadwood,
            px, py + 70, w, "center")

        local score_y = py + 115
        if round_result.laid_off_value ~= nil and round_result.laid_off_value > 0 then
            local who = round_result.you_knocked and "Opponent" or "You"
            love.graphics.printf(who .. " laid off " .. round_result.laid_off_value .. " points", px, score_y, w, "center")
            score_y = score_y + 35
        end

        love.graphics.printf(
            "Round score  You: +" .. round_result.your_round_score .. "   Opponent: +" .. round_result.opponent_round_score,
            px, score_y, w, "center")
        love.graphics.printf(
            "Total  You: " .. round_result.your_total_score .. "   Opponent: " .. round_result.opponent_total_score,
            px, score_y + 40, w, "center")
    end

    if waiting_for_layoff then
        local w, h = 380, 100
        local px, py = love.graphics.getWidth() / 2 - w / 2, love.graphics.getHeight() / 2 - h / 2

        love.graphics.setColor(0, 0, 0, 0.7)
        love.graphics.rectangle("fill", px, py, w, h, 10, 10)

        love.graphics.setFont(font)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.printf("Waiting for opponent to lay off cards...", px, py + h / 2 - font:getHeight() / 2, w, "center")
    end

    if game_over_info ~= nil then
        local w, h = love.graphics.getWidth(), love.graphics.getHeight()

        love.graphics.setColor(0, 0, 0, 0.75)
        love.graphics.rectangle("fill", 0, 0, w, h)

        love.graphics.setColor(1, 1, 1, 1)
        local text = game_over_info.you_won and "YOU WIN!" or "YOU LOSE"
        love.graphics.printf(text, 0, h / 2 - 100, w, "center")

        if game_over_info.opponent_disconnected then
            love.graphics.printf("Opponent disconnected.", 0, h / 2 - 40, w, "center")
            love.graphics.printf("Returning to menu...", 0, h / 2 - 10, w, "center")
        elseif disconnected_from_server then
            love.graphics.printf(rematch_declined_by_me and "You left the game." or "Disconnected from server.", 0, h / 2 - 40, w, "center")
        elseif opponent_left then
            love.graphics.printf("Opponent left the game.", 0, h / 2 - 40, w, "center")
            love.graphics.printf("Returning to menu...", 0, h / 2 - 10, w, "center")
        elseif rematch_response_sent then
            love.graphics.printf("Waiting for opponent's response...", 0, h / 2 - 40, w, "center")
        else
            love.graphics.printf("Play again?", 0, h / 2 - 40, w, "center")

            local buttons = get_rematch_buttons()

            love.graphics.setColor(0.3, 0.6, 0.3, 1)
            love.graphics.rectangle("fill", buttons.yes.x, buttons.yes.y, buttons.yes.w, buttons.yes.h, 8, 8)

            love.graphics.setColor(0.6, 0.3, 0.3, 1)
            love.graphics.rectangle("fill", buttons.no.x, buttons.no.y, buttons.no.w, buttons.no.h, 8, 8)

            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.printf("YES", buttons.yes.x, buttons.yes.y + buttons.yes.h / 2 - 8, buttons.yes.w, "center")
            love.graphics.printf("NO", buttons.no.x, buttons.no.y + buttons.no.h / 2 - 8, buttons.no.w, "center")
        end
    end

    if is_paused then
        local w, h = love.graphics.getWidth(), love.graphics.getHeight()

        love.graphics.setColor(0, 0, 0, 0.75)
        love.graphics.rectangle("fill", 0, 0, w, h)

        love.graphics.setFont(font)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.printf("PAUSED", 0, h / 2 - 200, w, "center")

        local buttons = get_pause_buttons()

        love.graphics.setColor(0.3, 0.3, 0.3, 1)
        love.graphics.rectangle("fill", buttons.fullscreen.x, buttons.fullscreen.y, buttons.fullscreen.w, buttons.fullscreen.h, 8, 8)
        love.graphics.rectangle("fill", buttons.wobble.x, buttons.wobble.y, buttons.wobble.w, buttons.wobble.h, 8, 8)

        love.graphics.setColor(0.6, 0.2, 0.2, 1)
        love.graphics.rectangle("fill", buttons.quit.x, buttons.quit.y, buttons.quit.w, buttons.quit.h, 8, 8)

        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.printf("Fullscreen: " .. (love.window.getFullscreen() and "ON" or "OFF"),
            buttons.fullscreen.x, buttons.fullscreen.y + buttons.fullscreen.h / 2 - 8, buttons.fullscreen.w, "center")
        love.graphics.printf("Card wobble: " .. (WOBBLE_ENABLED and "ON" or "OFF"),
            buttons.wobble.x, buttons.wobble.y + buttons.wobble.h / 2 - 8, buttons.wobble.w, "center")
        love.graphics.printf("QUIT GAME", buttons.quit.x, buttons.quit.y + buttons.quit.h / 2 - 8, buttons.quit.w, "center")

        love.graphics.printf("Press ESC to resume", 0, buttons.quit.y + buttons.quit.h + 25, w, "center")
    end

    love.graphics.setColor(1, 1, 1, 1)
end


return Scene