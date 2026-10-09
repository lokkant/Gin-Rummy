-- The main game scene (client): owns the shared `state` table and wires the client/* modules together -
-- network messages (messages), mouse input (input), layout, HUD and overlays. load(ip, options) connects
-- to the server at once; when the player hosts, the server runs in this process (see start_menu.lua). It
-- implements the scene API of SceneManager (load, resize, mouse/key callbacks, update, draw).

require 'animations'

local love = require "love"
local network = require "network"
local server = require "server"
local layout = require "client/layout"
local knock = require "client/knock"
local hud = require "client/hud"
local overlays = require "client/overlays"
local input = require "client/input"
local messages = require "client/messages"
local sounds = require "client/sounds"

local Scene = {}

-- The shared game state, created by Scene.load.
local state

-- Closes the connection and goes back: a host also shuts its server down and returns to the start menu,
-- a joining player returns to the address menu.
local function leave_to_menu()
    network.close()
    sounds.stop_ambient()

    if state ~= nil and state.hosting then
        server.stop()
        SceneManager.switch("start")
    else
        SceneManager.switch("menu")
    end
end

-- Creates the state table that all client/* modules read and write:
--   server_address, leave_to_menu   used by the connection overlays and for leaving
--   hosting, host_addresses         we run the server: the addresses the other player can join with
--   animations                      Animations() scheduler: flying cards, pauses, waiting for the wipe
--   pending_messages                server messages waiting for messages.process_next
--   has_started_first_game          true once the first "new_game" was handled
--   is_my_turn                      we may act now (draw, then discard or knock)
--   is_game_over, game_over_info    the match ended / the game_over message
--   is_paused                       the pause menu is open (ESC)
--   round_result                    the round_result message while its banner is shown
--   my_total_score, opponent_total_score   totals shown by the HUD
--   rematch_response_sent, opponent_left   state of the rematch question
--   dragging_card, drag_offset_x/y  the card being dragged and where it was grabbed
--   hovered_card                    the hand card lifted by the cursor
--   taken_from_discard              card taken from the discard pile this turn (can't be thrown back)
--   draw_requested                  a stock draw was sent and its answer is pending
--   turn_timer                      {elapsed, limits} how long our turn has gone without a game step, and the
--                                   server's limits (nil when it sent none); see client/impatience.lua
-- layout.create adds deck, discard_pile, player_hand, opponent_hand, opponent_card_reference and layout.
local function new_state(address, options)
    return {
        server_address = address,
        leave_to_menu = leave_to_menu,
        hosting = options.hosting == true,
        host_addresses = options.addresses or {},
        animations = Animations(),

        pending_messages = {},
        has_started_first_game = false,

        is_my_turn = false,
        is_game_over = false,
        is_paused = false,
        round_result = nil,
        game_over_info = nil,
        my_total_score = 0,
        opponent_total_score = 0,
        rematch_response_sent = false,
        opponent_left = false,

        dragging_card = nil,
        drag_offset_x = 0,
        drag_offset_y = 0,
        hovered_card = nil,
        taken_from_discard = nil,
        draw_requested = false,
        turn_timer = nil
    }
end

-- Scene entry (SceneManager.switch("game", ip, options)): connects to the server, creates a fresh state and
-- builds the table. options (optional): hosting = true when the server runs in this process, addresses =
-- the list of "ip:port" strings to show the other player. The connection result is shown by the overlays
-- while the status is "connecting".
function Scene.load(ip, options)
    options = options or {}

    network.connect(ip)

    state = new_state(ip, options)

    hud.load(state)
    layout.create(state)
end

-- Re-lays out the table after a window resize (ignored before the table exists).
function Scene.resize(w, h)
    if state == nil or state.deck == nil then return end

    layout.apply(state, w, h)
end

-- What each action name returned by overlays.handle_click does.
local overlay_actions = {
    leave = leave_to_menu,
    rematch_no = leave_to_menu,
    rematch_yes = function()
        state.rematch_response_sent = true
        network.send({type = "rematch_response", answer = true})
    end,
    toggle_fullscreen = function()
        love.window.setFullscreen(not love.window.getFullscreen())
    end,
    cycle_sound = function()
        sounds.cycle_mode()
    end,
    quit = function()
        love.event.quit()
    end
}

-- Overlays get the click first; only when none consumed it does it reach the table.
function Scene.mousepressed(x, y, button)
    local consumed, action = overlays.handle_click(state, x, y, button)

    if consumed then
        if action then
            overlay_actions[action]()
        end
        return
    end

    input.mousepressed(state, x, y, button)
end

-- Ignored while paused (pausing drops a dragged card, see keypressed).
function Scene.mousereleased(x, y, button)
    if state.is_paused then return end

    input.mousereleased(state, x, y, button)
end

-- Mouse moves drag the held card; ignored while paused.
function Scene.mousemoved(x, y)
    if state.is_paused then return end

    input.mousemoved(state, x, y)
end

-- ESC toggles the pause menu (not after the game is over); pausing drops a card that is being dragged.
function Scene.keypressed(key)
    if key == "escape" and not state.is_game_over then
        state.is_paused = not state.is_paused

        if state.is_paused then
            state.dragging_card = nil
        end
    end
end

-- Per frame: move the cards, advance the animations, handle at most one queued server message (it may start
-- new animations), update the hover, and read new network packets last.
function Scene.update(dt)
    local mx, my = love.mouse.getPosition()

    -- under an overlay the cursor is "nowhere", so the cards, deck and pile lose their hover
    if overlays.covers_table(state) then
        mx, my = -1, -1
    end

    state.player_hand:update(dt, layout.CARD_SPEED, state.dragging_card, state.hovered_card)
    state.opponent_hand:update(dt, layout.CARD_SPEED, state.dragging_card, state.hovered_card)
    state.deck:update(dt, mx, my)
    state.discard_pile:update(dt, mx, my)

    state.animations:update(dt)
    hud.update(state, dt)

    messages.process_next(state)

    input.update_hover(state, mx, my)

    messages.receive(state)
end

-- Draw order, back to front: table (with the spotlight), the watchers, stock, discard pile, eye, our hand,
-- flying cards, opponent's hand, KNOCK button, scores, cracked glass, overlays.
function Scene.draw()
    hud.draw_background(state)
    hud.draw_watchers(state)

    state.deck:draw()
    state.discard_pile:draw()
    hud.draw_eye(state)

    state.player_hand:draw(state.dragging_card, state.hovered_card)
    state.animations:draw()
    state.opponent_hand:draw()

    hud.draw_knock_button(state)
    hud.draw_scores(state)
    hud.draw_cracks(state)

    overlays.draw(state)

    love.graphics.setColor(1, 1, 1, 1)
end

return Scene
