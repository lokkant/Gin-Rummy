require 'server_deck'
require 'game'

local enet = require "enet"
local love = require "love"
local json = require "dkjson"

love.graphics = nil

-- io.stdout:setvbuf("line")

local host
local player1
local player2
local game
local rematch_state

local Server = {}

local function start_new_match()
    game = Game(player1, player2, ServerDeck())
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

local function handle_message(peer, data)
    local ok, message = pcall(json.decode, data)
    if not ok or type(message) ~= "table" or type(message.type) ~= "string" then return end

    if peer ~= player1 and peer ~= player2 then return end

    if message.type == "rematch_response" then
        handle_rematch_response(peer, message.answer == true)
        return
    end

    if game == nil then return end

    if message.type == "get_card_from_deck" then
        game:get_card_from_deck(peer)
    elseif message.type == "put_card_to_discard_pile" then
        game:put_card_to_discard_pile(peer, message.card)
    elseif message.type == "get_card_from_discard_pile" then
        game:get_card_from_discard_pile(peer)
    elseif message.type == "knock" then
        game:knock(peer, message.discard, message.combinations)
    elseif message.type == "finish_layoff" then
        game:finish_layoff(peer, message.layoffs)
    end
end

local function handle_event(event)
    if event.type == "connect" then
        print("Player connected:", event.peer)
        if player1 == nil then
            player1 = event.peer
        elseif player2 == nil then
            player2 = event.peer
        else
            print("Rejecting extra connection:", event.peer)
            event.peer:disconnect()
        end
    elseif event.type == "receive" then
        print("Received:", event.data, event.peer)
        handle_message(event.peer, event.data)
    elseif event.type == "disconnect" then
        print("Player disconnected:", event.peer)
        handle_disconnect(event.peer)
    end

    if player1 and player2 and game == nil then
        start_new_match()
    end
end

function Server.load()
    host = enet.host_create("*:6789")

    if host == nil then
        print("ERROR: can't start the server on port 6789 (is another server already running?)")
        love.event.quit(1)
        return
    end

    print("Server started on port 6789")
end

function Server.update(dt)
    if host == nil then return end

    local event = host:service(0)

    while event do
        local ok, err = pcall(handle_event, event)
        if not ok then
            print("ERROR while handling event:", err)
        end

        event = host:service(0)
    end
end

return Server
