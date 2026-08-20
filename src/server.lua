require 'server_deck'
require 'game'

local enet = require "enet"
local love = require "love"
local json = require "dkjson"

love.graphics = nil

local host
local player1
local player2
local game
local rematch_state

local Server = {}

local function start_new_match()
    game = Game(player1, player2, Deck())
    rematch_state = nil

    local message = json.encode({type = "new_game"})
    print("Send:", message)
    player1:send(message)
    player2:send(message)

    game:start_game()
end

local function handle_rematch_response(peer, wants_rematch)
    if game == nil or not game.is_over_game then return end
    if peer ~= player1 and peer ~= player2 then return end

    if not wants_rematch then
        local opponent = (peer == player1) and player2 or player1

        if opponent ~= nil then
            local message = json.encode({type = "opponent_declined_rematch"})
            print("Send:", message)
            opponent:send(message)
        end

        peer:disconnect()

        if peer == player1 then
            player1 = player2
        end
        player2 = nil
        game = nil
        rematch_state = nil
        return
    end

    rematch_state = rematch_state or {}
    rematch_state[peer] = true

    if player1 and player2 and rematch_state[player1] and rematch_state[player2] then
        start_new_match()
    end
end

local function handle_disconnect(peer)
    local was_player1 = (peer == player1)
    local was_player2 = (peer == player2)

    if not was_player1 and not was_player2 then return end

    if game ~= nil then
        local winner = was_player1 and player2 or player1

        if winner ~= nil then
            if not game.is_over_game then
                local message = json.encode({type = "game_over", you_won = true, opponent_disconnected = true})
                print("Send:", message)
                winner:send(message)
            else
                local message = json.encode({type = "opponent_declined_rematch"})
                print("Send:", message)
                winner:send(message)
            end
        end
    end

    game = nil
    rematch_state = nil

    if was_player1 then
        player1 = player2
        player2 = nil
    else
        player2 = nil
    end
end

function Server.load()
    host = enet.host_create("*:6789")
    print("Server started on port 6789")
end

function Server.update(dt)
    local event = host:service(0)

    while event do
        if event.type == "connect" then
            print("Player connected:", event.peer)
            if player1 == nil then
                player1 = event.peer
            elseif player2 == nil then
                player2 = event.peer
            end
        elseif event.type == "receive" then
            print("Received:", event.data, event.peer)
            local message = json.decode(event.data)
            if message ~= nil and message.type == "get_card_from_deck" then
                game:get_card_from_deck(event.peer)
            elseif message ~= nil and message.type == "put_card_to_discrad_pile" then
                game:put_card_to_discrad_pile(event.peer, message.card)
            elseif message ~= nil and message.type == "get_card_from_discrad_pile" then
                game:get_card_from_discard_pile(event.peer)
            elseif message ~= nil and message.type == "knock" then
                game:knock(event.peer, message.discard, message.combinations)
            elseif message ~= nil and message.type == "finish_layoff" then
                game:finish_layoff(event.peer, message.layoffs)
            elseif message ~= nil and message.type == "rematch_response" then
                handle_rematch_response(event.peer, message.answer)
            end
        elseif event.type == "disconnect" then
            print("Player disconnected:", event.peer)
            handle_disconnect(event.peer)
        end

        if player1 and player2 and game == nil then
            start_new_match()
        end

        event = host:service(0)
    end
end

return Server
