-- Authoritative game server. Runs only with `love . --server` (main.lua loads this module as the "server"
-- scene). It owns the two player peers, the current Game (game.lua) and the rematch votes: every client
-- message is validated here / in Game, and the clients only mirror what the server sends back.
--
-- MESSAGE PROTOCOL
-- Transport: ENet on port 6789, one JSON object per packet (dkjson): {"type": "<name>", ...fields}.
-- A card is its name "<rank>_<suit>", e.g. "10_heart", "A_spade" (ranks 2-10 J Q K A; suits heart,
-- diamond, club, spade). A meld is a list of card names; "combinations" is a list of melds.
-- Fields shown in [brackets] are optional. Invalid or out-of-turn requests are silently ignored.
--
-- Client -> server (routed in handle_message below, rules in game.lua)
--   type                        fields                    meaning
--   get_card_from_deck          -                         draw the top stock card (draw phase)
--   get_card_from_discard_pile  -                         take the top discard card (draw phase)
--   put_card_to_discard_pile    card                      discard a card, ends the turn (discard phase)
--   knock                       discard, combinations     discard `discard` and knock with these melds
--   finish_layoff               layoffs                   answer to a knock; layoffs is a list of
--                                                         {card, meld_index}, meld_index = 1-based position
--                                                         in the knocker's combinations
--   rematch_response            answer                    boolean, only valid after game_over
--
-- Server -> client (to one player unless noted)
--   type                                  fields           meaning
--   new_game                              -                both: a new match starts, scores are 0
--   new_round                             -                both: next round, clear the table; a deal follows
--   get_card_from_deck                    card             you received this card (deal or draw)
--   opponent_get_card_from_deck           -                the opponent received a hidden card
--   update_discard_pile                   card             both: the face-up card that starts the round
--   is_my_turn                            answer (true)    your turn starts (draw phase)
--   opponent_get_card_from_discard_pile   -                the opponent took the top discard card
--   opponent_place_card_to_discard_pile   card             the opponent discarded this card
--   knock_discard                         card, mine       both: the knocker's discard; mine = you knocked
--   waiting_for_layoff                    -                to the knocker: the opponent is laying off
--   layoff_phase                          combinations     to the opponent: the knocker's melds
--   round_result                          you_knocked, is_gin, is_undercut, [is_draw], your_deadwood,
--                                         opponent_deadwood, laid_off_value, your_round_score,
--                                         opponent_round_score, your_total_score, opponent_total_score
--                                                          the round is scored (each player gets their
--                                                          own point of view; is_draw only for a draw)
--   game_over                             you_won, [opponent_disconnected]
--                                                          the match ended (or the opponent left)
--   opponent_declined_rematch             -                the opponent said no / left after game_over
--
-- Typical order: new_game, then 10 x (get_card_from_deck + opponent_get_card_from_deck),
-- update_discard_pile, is_my_turn; turns repeat (draw, then discard or knock). A knock sends knock_discard,
-- then either round_result (gin) or waiting_for_layoff + layoff_phase and, after finish_layoff,
-- round_result. After round_result: new_round and a new deal, or game_over once someone reached 100 points.

require 'server_deck'
require 'game'

local enet = require "enet"
local love = require "love"
local json = require "dkjson"

-- If console output shows up late when stdout is redirected, call io.stdout:setvbuf("line") here.

-- ENet host; the two seats (ENet peers, nil while empty); the running Game; rematch_state[peer] = true
-- once that player answered "yes" after the match ended.
local host
local player1
local player2
local game
local rematch_state

-- The scene table handed to the SceneManager (load/update only; there is nothing to draw).
local Server = {}

-- Starts a fresh match for the two seated players: new Game with a newly shuffled deck, clears the rematch
-- votes, announces "new_game" to both and deals the first round.
local function start_new_match()
    game = Game(player1, player2, ServerDeck())
    rematch_state = nil

    local message = json.encode({type = "new_game"})
    print("Send:", message)
    player1:send(message)
    player2:send(message)

    game:start_game()
end

-- Handles "rematch_response" from `peer`; only meaningful once the match is over. "No" disconnects that
-- player, tells the other one and frees the seat; when both answered "yes" a new match starts.
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

        -- Graceful disconnect; the later "disconnect" event is ignored because the peer no longer holds a
        -- seat.
        peer:disconnect()

        -- Keep the remaining player in seat 1 so the next client to connect takes seat 2.
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

-- A peer's connection ended. If it was a player, the other one wins by forfeit ("game_over" with
-- opponent_disconnected) or, when the match was already over, is told that no rematch will happen.
-- The Game is dropped and the remaining player moves to seat 1.
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
            -- The match was already over: the leaver simply can't answer the rematch question any more.
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

-- Decodes one client packet and routes it. Bad JSON, unknown peers and messages while no game runs are
-- ignored; the Game itself checks whose turn it is and which phase we are in.
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

-- Dispatches one ENet event: "connect" takes the first free seat (a third client is rejected), "receive"
-- goes to handle_message, "disconnect" to handle_disconnect. Starts a match as soon as both seats are full.
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

-- Scene load: listens on port 6789 on all interfaces; quits with exit code 1 if the port is taken.
function Server.load()
    host = enet.host_create("*:6789")

    if host == nil then
        print("ERROR: can't start the server on port 6789 (is another server already running?)")
        love.event.quit(1)
        return
    end

    print("Server started on port 6789")
end

-- Scene update: drains all pending ENet events (non-blocking). Each event runs under pcall so one bad
-- message cannot take the whole server down.
function Server.update()
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
